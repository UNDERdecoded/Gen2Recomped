-- The bag: lists inventory, uses items via ItemEffects.
-- opts.battle = BattleState when opened mid-battle (balls throwable,
-- using an item consumes the turn).

local ItemEffects = require("src.inventory.ItemEffects")
local ListMenu = require("src.ui.ListMenu")
local TextBox = require("src.render.TextBox")

local BagMenu = {}

local Bag = require("src.inventory.Bag")
local Strings = require("src.core.Strings")

-- Gen2's pack has four pages (engine/items/pack.asm): ITEM, BALL, KEY ITEM
-- and TM/HM, switched with LEFT/RIGHT.  The pocket lives on the item record
-- (ItemAttributes byte 5); a cache from before that was extracted -- and
-- every Gen1 item -- is classified from the fields the port already has, so
-- the page split degrades to something sensible rather than emptying.
local POCKETS = {
  { key = "ITEM", title = "ITEMS" },
  { key = "BALL", title = "BALLS" },
  { key = "KEY_ITEM", title = "KEY ITEMS" },
  { key = "TM_HM", title = "TM/HM" },
}

local function pocketOf(def, id)
  if def and def.pocket then return def.pocket end
  if def and def.machine then return "TM_HM" end
  if def and def.ball then return "BALL" end
  if def and def.keyItem then return "KEY_ITEM" end
  if type(id) == "string" and (id:find("^TM_") or id:find("^HM_")) then
    return "TM_HM"
  end
  return "ITEM"
end

-- acquisition order like wBagItems (Bag.order), not alphabetical
local function buildItems(game, pocket)
  local items = {}
  for _, id in ipairs(Bag.order(game.save)) do
    local def = game.data.items[id]
    if not pocket or pocketOf(def, id) == pocket then
      table.insert(items, {
        value = id,
        label = def and def.name or id,
        right = "x" .. game.save.inventory[id],
      })
    end
  end
  return items
end

local function consume(game, id)
  Bag.remove(game.save, id, 1)
end

local function save_name(game)
  return game.save.player.name
end

local function showMessages(game, msgs, onDone)
  if not msgs or #msgs == 0 then
    if onDone then onDone() end
    return
  end
  game.stack:push(TextBox.new(game, table.concat(msgs, "\f"), onDone))
end

-- run the use-flow for an item on a chosen target.  `picker` is the party
-- menu when it was opened with keepOpen (HP medicine only): it is still on
-- the stack, so every exit that prints has to close it afterwards.  For
-- every other item the picker popped itself first and closePicker's identity
-- check makes it a no-op (#252).
local function useOn(game, battle, id, target, list, moveIndex, picker)
  local result, payload, extra = ItemEffects.use(game.data, game.save, id, target,
                                                 battle, moveIndex, game.overworld)
  local function closePicker()
    if picker then picker:close() end
  end

  -- field POKé FLUTE: play the tune, then the no-effect text
  if result == "flute_field" then
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload)
    return
  end

  -- field POKé FLUTE next to a not-yet-beaten Snorlax: "had effect" text,
  -- then the woke-up/battle sequence (data/scripts/story.lua snorlaxWake)
  if result == "flute_wake" then
    list:close()
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload, function()
      local ow = game.overworld
      local mod = ow and require("data.scripts.init").get(extra.mapId)
      if ow and mod and mod.snorlaxWake then
        ow.runner:run(mod.snorlaxWake.script, { npc = extra.npc })
      end
    end)
    return
  end

  if result == "consumed_escape" then -- Poké Doll
    consume(game, id)
    list:close()
    showMessages(game, payload, function()
      -- ItemUsePokeDoll sets wEscapedFromBattle and never touches
      -- wBattleResult, so a script that reads the result afterwards sees
      -- 0 -- "defeated". The ghost MAROWAK's script keys on exactly that
      -- (the Poke Doll trick); the flag lets it tell this escape from an
      -- ordinary RUN, which writes $2.
      battle.pokeDollEscape = true
      battle.result = "run"
      battle.afterQueue = "finish"
      battle.phase = "messages"
    end)
    return
  end

  if result == "bicycle" then
    -- StartMenu_Item .useOrTossItem (engine/menus/start_sub_menus.asm):
    -- while BIT_ALWAYS_ON_BIKE of wStatusFlags6 is set -- the Cycling Road,
    -- armed by the forced-bike tiles and cleared by the Route 16/18 gate
    -- scripts -- the BICYCLE refuses with _CannotGetOffHereText and jumps
    -- back to ItemMenuLoop, so the bag stays open and no dismount happens
    -- (#513).  The gate sits ahead of UseItem, before ItemUseBicycle ever
    -- runs, which is why it precedes list:close() here.
    if game.save.forcedBike then
      showMessages(game, { Strings("You can't get off\nhere.") })
      return
    end
    list:close()
    local ow = game.overworld
    local Music = require("src.core.Music")
    -- IsBikeRidingAllowed (home/overworld.asm) for Gen1, BikeFunction
    -- .CheckEnvironment for Gen2; the overworld owns both rules.
    local function bikeAllowed()
      return ow and ow:bikeAllowed(ow.map.id) or false
    end
    if game.save.onBike then
      game.save.onBike = false
      Music.playMap(game.data, ow and ow.map.id, false)
      showMessages(game, { Strings("%s got off\nthe BICYCLE.", save_name(game)) })
    elseif bikeAllowed() then
      game.save.onBike = true
      Music.playMap(game.data, ow.map.id, true)
      showMessages(game, { Strings("%s got on\nthe BICYCLE!", save_name(game)) })
    else
      showMessages(game, { Strings("No cycling\nallowed here.") })
    end
    return
  end

  if result == "fish" then
    list:close()
    local ow = game.overworld
    local p = ow and ow.player
    if ow and p then
      local fx, fy = p:facingCell()
      if ow.map:inBounds(fx, fy) and ow.map:isWaterCell(fx, fy) then
        ow:goFishing(id)
        return
      end
    end
    showMessages(game, { Strings("No good! It's not\neven near water.") })
    return
  end

  if result == "ball" then
    if not battle then
      showMessages(game, { Strings("OAK: %s!\nThis isn't the\ntime to use that!",
                              game.save.player.name) })
      return
    end
    consume(game, id)
    list:close()
    -- Catching/AnimPlayer key off the Gen1 ball ids
    battle:throwBall(ItemEffects.alias(id, game.data.items[id]))
    return
  end

  if result == "learn" or result == "learnkept" then
    local moveId = payload
    local mdef = game.data.moves[moveId]
    local function teach()
      -- PIKAHAPPY_USEDTMHM on a successful teach (item_effects.asm:2500)
      local function taught()
        require("src.world.PikachuFollower")
          .modifyHappiness(game.save, "USEDTMHM", target)
      end
      if #target.moves < 4 then
        table.insert(target.moves, { id = moveId, pp = mdef.pp })
        showMessages(game, { Strings("%s learned\n%s!", target.nickname or
          game.data.pokemon[target.species].name, mdef.name) })
        if result == "learn" then consume(game, id) end
        taught()
      else
        require("src.ui.Screens").push(game, "MoveLearnMenu", target, moveId,
          function(learned)
            if learned and result == "learn" then consume(game, id) end
            if learned then taught() end
          end)
      end
    end
    list:close()
    teach()
    return
  end

  -- the TOWN MAP screen (engine/menus/town_map.asm)
  if result == "townmap" then
    local ok = pcall(function()
      require("src.ui.Screens").push(game, "TownMap")
    end)
    if not ok then
      showMessages(game, { Strings("The TOWN MAP is\nunreadable here.") })
    end
    return
  end

  -- ITEMFINDER (engine/items/itemfinder.asm): responds if the current
  -- map still has an unfound hidden item
  if result == "itemfinder" then
    local ow = game.overworld
    local t = game.data.text
    if ow and ow:hasHiddenItemLeft() then
      showMessages(game, { t._ItemfinderFoundItemText
        or Strings("Yes! ITEMFINDER\nindicates there's\nan item nearby.") })
    else
      showMessages(game, { t._ItemfinderFoundNothingText
        or Strings("Nope! ITEMFINDER\nisn't responding.") })
    end
    return
  end

  -- POKé FLUTE in battle: not consumed, but uses the turn
  if result == "flute" then
    list:close()
    require("src.core.Sound").play(game.data, "Pokeflute")
    showMessages(game, payload, function() battle:itemUsed({}) end)
    return
  end

  if result == "escape_rope" then
    -- ItemUseEscapeRope: only inside the dungeon tilesets
    -- (escape_rope_tilesets.asm), never in Agatha's room, and it sets
    -- BIT_ESCAPE_WARP so special_warps.asm warps to wLastBlackoutMap
    -- -- the last Pokémon Center town, same as Dig/Teleport (NOT the
    -- spot you entered the dungeon from)
    local ESCAPE_ROPE_TILESETS = { FOREST = true, CEMETERY = true,
                                   CAVERN = true, FACILITY = true,
                                   INTERIOR = true }
    -- Gen2 gates on the map header's environment byte instead
    -- (ENVIRONMENT_CAVE / ENVIRONMENT_DUNGEON, scripts/std_scripts.asm)
    local GEN2_ESCAPE_ROPE_ENVIRONMENTS = { [4] = true, [7] = true }
    local ow = game.overworld
    local allowed = ow and (ESCAPE_ROPE_TILESETS[ow.map.def.tileset]
      or GEN2_ESCAPE_ROPE_ENVIRONMENTS[ow.map.def.environment])
    if allowed and ow.map.id ~= "AGATHAS_ROOM" then
      list:close()
      consume(game, id)
      -- LeaveMapAnim spin-up + SFX_TELEPORT_EXIT_1, a fade, then land OUTSIDE
      -- the last Pokémon Center town door like Fly (#196), via the shared
      -- departure helper -- the same path Dig/Teleport take from the party menu
      ow:beginTeleportOut()
    else
      showMessages(game, { Strings(
        "OAK: %s!\nThis isn't the\ntime to use that!",
        game.save.player.name) })
    end
    return
  end

  if result == "consumed" then
    consume(game, id)
    if extra and extra.evolveTo then
      list:close()
      local Evolution = require("src.pokemon.Evolution")
      Evolution.evolve(game, target, extra.evolveTo)
      return
    end
    -- RARE CANDY: after the level text, the stat window, any level-up
    -- moves and a level evolution follow (item_effects.asm .useRareCandy
    -- runs PrintStatsBox, LearnMoveFromLevelUp and TryEvolvingMon)
    if extra and extra.leveledTo and target then
      list:close()
      showMessages(game, payload, function()
        local StatBox = require("src.battle.BattleState").StatBox
        game.stack:push(StatBox.new(game, target, function()
          local Experience = require("src.battle.Experience")
          local def = game.data.pokemon[target.species]
          local moves = Experience.movesLearnedAt(def, extra.leveledTo)
          local i = 0
          local function nextStep()
            i = i + 1
            local moveId = moves[i]
            if not moveId then
              local Evolution = require("src.pokemon.Evolution")
              local evoTo, evo = Evolution.pendingFor(game, target,
                                                     { kind = "levelup" })
              if evoTo then
                Evolution.evolve(game, target, evoTo, nil, evo and evo.method)
              end
              return
            end
            for _, mv in ipairs(target.moves) do
              if mv.id == moveId then return nextStep() end
            end
            local mdef = game.data.moves[moveId]
            if #target.moves < 4 then
              table.insert(target.moves, { id = moveId, pp = mdef.pp })
              local name = target.nickname or def.name
              showMessages(game, { Strings("%s learned\n%s!", name, mdef.name) },
                           nextStep)
            else
              require("src.ui.Screens").push(game, "MoveLearnMenu",
                                             target, moveId, nextStep)
            end
          end
          nextStep()
        end))
      end)
      return
    end
    -- refresh counts in the list
    for i, it in ipairs(list.items) do
      if it.value == id then
        local left = game.save.inventory[id]
        if left then it.right = "x" .. left else table.remove(list.items, i) end
        break
      end
    end
    list.index = math.min(list.index, math.max(1, #list.items))
    -- HP medicine: fill the bar in the still-open picker first, then print
    -- and close, the order item_effects.asm .doneHealing runs in
    -- (SFX_HEAL_HP -> UpdateHPBar2 -> RedrawPartyMenu prints the message).
    -- Only a keepOpen picker is still on the stack to animate: every other
    -- item, and every in-battle use, popped it in PartyMenu before onSwitch,
    -- and takes the pop-then-print path below -- which is the path that
    -- spends the battle turn.  #252, #379
    if picker and picker.keepOpen and extra and extra.healedFrom and target then
      picker:animateTo(target, extra.healedFrom, function()
        showMessages(game, payload, closePicker)
      end)
      return
    end
    if battle then
      list:close()
      showMessages(game, payload, function() battle:itemUsed({}) end)
    else
      showMessages(game, payload, closePicker)
    end
    return
  end

  -- .healingItemNoEffect prints over the still-drawn party menu too, so the
  -- refusal closes the picker the same way (#252)
  showMessages(game, payload, closePicker) -- failed
end

local function pickTargetAndUse(game, battle, id, list)
  -- pick a target from the party
  -- the ETHERs and PP UP open the move menu after picking a mon
  -- (ItemUsePPRestore / ItemUsePPUp); the ELIXERs hit every move
  local def = game.data.items[id]
  local key = ItemEffects.alias(id, def)
  local wantsMove = key == "ETHER" or key == "MAX_ETHER" or key == "PP_UP"
  local opts = {
    pickOnly = true,
    -- HP medicine animates its bar with the picker still up (#252).  Only
    -- out of battle: the in-battle tail closes the bag list underneath
    -- first, which needs the picker already gone.
    keepOpen = (not battle) and ItemEffects.healsHP(id),
    onSwitch = function(mon, picker)
      if not wantsMove then
        useOn(game, battle, id, mon, list, nil, picker)
        return
      end
      local rows = {}
      for mi, mv in ipairs(mon.moves) do
        local mdef = game.data.moves[mv.id]
        table.insert(rows, {
          value = mi,
          label = mdef and mdef.name or mv.id,
          right = ("%d"):format(mv.pp),
        })
      end
      game.stack:push(ListMenu.new(game, "Which move?", rows, {
        onChoose = function(row, l)
          l:close()
          useOn(game, battle, id, mon, list, row.value)
        end,
      }))
    end,
  }
  -- TM/HM: open the party menu in Gen 1's TM/HM display mode so each mon
  -- shows ABLE / NOT ABLE from its learnset and the prompt reads "Use TM on
  -- which POKeMON?" (engine/items/item_effects.asm ItemUseTMHM ->
  -- party_menu.asm TM/HM type). Stones and other pickOnly items keep the
  -- plain HP layout (Gen 1 shows no ABLE/NOT ABLE for them), so gate
  -- strictly on def.machine. #210
  if def and def.machine then
    opts.tmhm = { move = def.machine.move, kind = def.machine.kind }
  end
  require("src.ui.Screens").push(game, "PartyMenu", opts)
end

local function useItem(game, battle, id, list)
  local def = game.data.items[id]
  -- ItemUseTMHM checks wIsInBattle before BootedUpTMText
  if battle and def and def.machine then
    local _, payload = ItemEffects.use(game.data, game.save, id, nil, battle)
    showMessages(game, payload)
    return
  end
  if ItemEffects.needsTarget(id, def) and not ItemEffects.isBall(id) then
    -- TMs/HMs boot up and announce their move before the target picker
    -- (ItemUseTMHM: BootedUpTMText / BootedUpHMText + TeachMachineMoveText)
    if def and def.machine then
      local moveDef = game.data.moves[def.machine.move]
      local moveName = moveDef and moveDef.name or def.machine.move
      local booted = def.machine.kind == "HM"
        and "Booted up an HM!" or Strings("Booted up a TM!")
      showMessages(game, { booted, Strings("It contained\n%s!", moveName) },
        function() pickTargetAndUse(game, battle, id, list) end)
      return
    end
    pickTargetAndUse(game, battle, id, list)
  else
    useOn(game, battle, id, nil, list)
  end
end

-- GSC's GiveItem: pick a party mon, then hand it the item.  A mon that is
-- already holding something is offered the swap (TryGiveItemToMon).
-- TryGiveItemToMon: hand `id` to `mon`, offering the swap when it is already
-- holding something.  Key items and mail stay in the pack.
local function handOver(game, mon, id, onChanged)
  local def = game.data.items[id]
  local name = (def and def.name) or id
  local monName = mon.nickname
    or (game.data.pokemon[mon.species] or {}).name or "?"
  if require("src.pokemon.Party").isEgg(mon) then
    showMessages(game, { Strings("An EGG can't hold\nan item.") })
    return
  end
  if def and def.keyItem then
    showMessages(game, { Strings("%s can't be\nheld.", name) })
    return
  end
  local held = mon.item
  local function hand()
    require("src.inventory.Bag").giveHeld(game.save, mon, id, game.data)
    if onChanged then onChanged() end
  end
  if not held then
    hand()
    showMessages(game, { Strings("%s is now holding\n%s.", monName, name) })
    return
  end
  local heldName = (game.data.items[held] or {}).name or held
  local ChoiceBox = require("src.ui.ChoiceBox")
  showMessages(game, {
    Strings("%s is already\nholding %s.", monName, heldName),
    Strings("Switch items?"),
  }, function()
    game.stack:push(ChoiceBox.new(game, function(yes)
      if not yes then return end
      hand()
      showMessages(game, { Strings("Took %s and\nmade it hold %s.",
        heldName, name) })
    end))
  end)
end

-- GSC's GiveItem (pack.asm): pick a party mon, then hand it the item.
local function giveItem(game, id, onChanged)
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onSwitch = function(mon) handOver(game, mon, id, onChanged) end,
  })
end

-- swap the two marked rows inside save.bagOrder by their item ids
local function swapRows(game, list)
  local a = list.items[list.swapIndex] and list.items[list.swapIndex].value
  local b = list.items[list.index] and list.items[list.index].value
  list.swapIndex = nil
  if not (a and b) or a == b then return end
  local order = Bag.order(game.save)
  local ia, ib
  for i, id in ipairs(order) do
    if id == a then ia = i end
    if id == b then ib = i end
  end
  if ia and ib then order[ia], order[ib] = order[ib], order[ia] end
end

-- _CGB_PackPals.PackPals (2:$596F): six palettes, then an attrmap that puts
-- 1 over the left half of the header row, 2 over the right half, 3 down the
-- cursor column, 4 on the pocket-name box and 5 on the pack picture.
local PACK_PALS = {
  { { 255, 255, 255 }, { 123, 123, 255 }, { 0, 0, 255 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 123, 123, 255 }, { 0, 0, 255 }, { 0, 0, 0 } },
  { { 255, 90, 255 }, { 123, 123, 255 }, { 0, 0, 255 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 123, 123, 255 }, { 0, 0, 255 }, { 255, 0, 0 } },
  { { 255, 255, 255 }, { 123, 123, 255 }, { 255, 0, 0 }, { 0, 0, 0 } },
  { { 255, 255, 255 }, { 58, 156, 58 }, { 58, 156, 58 }, { 0, 0, 0 } },
}

local function packPalettes()
  local P = require("src.render.PaletteFX")
  return {
    P.whole(PACK_PALS[1]),
    P.zone(PACK_PALS[2], 0, 0, 9, 0),
    P.zone(PACK_PALS[3], 10, 0, 19, 0),
    P.zone(PACK_PALS[4], 7, 2, 7, 10),
    P.zone(PACK_PALS[5], 0, 7, 4, 9),
    P.zone(PACK_PALS[6], 0, 3, 4, 5),
  }
end

function BagMenu.new(game, opts)
  opts = opts or {}
  local battle = opts.battle
  local list
  -- Gen2 pages the pack; Gen1's bag is one flat list (pocket = nil)
  local gen2 = require("src.core.GameVersion").isGen2()
  local pocketIndex = gen2 and (opts.pocketIndex or 1) or nil
  local function pocketKey()
    return pocketIndex and POCKETS[pocketIndex].key or nil
  end
  local function refresh(l)
    l.items = buildItems(game, pocketKey())
    l.index = math.min(l.index, math.max(1, #l.items))
    l.scroll = 0
  end
  list = ListMenu.new(game, pocketIndex and POCKETS[pocketIndex].title or "ITEMS",
    buildItems(game, pocketKey()), {
    kind = "bag",
    pocketIndex = pocketIndex and (pocketIndex - 1) or 0,
    onPocketSwitch = pocketIndex and function(l, delta)
      pocketIndex = ((pocketIndex - 1 + delta) % #POCKETS) + 1
      l.pocketIndex = pocketIndex - 1
      l.title = POCKETS[pocketIndex].title
      l.swapIndex = nil
      l.index = 1
      refresh(l)
      require("src.core.Sound").play(game.data, "Press_AB")
    end or nil,
    footer = ("¥%d"):format(game.save.money),
    -- B returns to the start menu when the bag was opened from it
    onCancel = opts.onCancel,
    -- SELECT reorders items like the original bag (swap_items.asm).  A
    -- pocket page is a filtered view of Bag.order, so the swap is done by
    -- item id rather than by row number.
    onSelectKey = function(item, l)
      if not item then return end
      if not l.swapIndex then
        l.swapIndex = l.index
        return
      end
      swapRows(game, l)
      require("src.core.Sound").play(game.data, "Swap")
      refresh(l)
    end,
    onChoose = function(item)
      local id = item.value
      local def = game.data.items[id]
      if list.swapIndex then -- A also completes a pending swap
        swapRows(game, list)
        require("src.core.Sound").play(game.data, "Swap")
        refresh(list)
        return
      end
      if opts.giveTo then
        -- opened from MonMenu's ITEM -> GIVE: the pick hands straight over
        list:close()
        handOver(game, opts.giveTo, id, nil)
        return
      end
      if battle then -- no tossing mid-battle
        useItem(game, battle, id, list)
        return
      end
      -- USE / TOSS submenu (the original's item options).
      -- data/text_boxes.asm USE_TOSS_MENU_TEMPLATE: box (13,10)-(19,14),
      -- text at (15,11); start_sub_menus.asm then sets wTopMenuItemY/X to
      -- 11/14 for the cursor.  Menu's own geometry reproduces all of that
      -- from the box alone, so this needs opts rather than a change to the
      -- shared Menu.  The old 12/10/8/6 box was a column too wide and a row
      -- too tall, which left the labels stranded near its top edge (#284).
      --
      -- Gen 2 has held items, so pack.asm's .ItemBallsKey_LoadSubmenu picks
      -- one of six headers instead: USE only when the item does something,
      -- GIVE and TOSS only when it is not a key item, always QUIT.  Its box
      -- is on the LEFT (menu_coords 0, y, SCREEN_WIDTH - 14, TEXTBOX_Y - 1)
      -- and grows upward from the text box.
      local Menu = require("src.ui.Menu")
      local tossable = not (gen2 and (not def or def.keyItem
        or ItemEffects.alias(id, def):find("^HM_")))
      local options = {
        { label = Strings("USE"), onSelect = function()
            useItem(game, battle, id, list)
          end },
      }
      if gen2 and tossable then
        options[#options + 1] = { label = Strings("GIVE"),
          onSelect = function()
            giveItem(game, id, function() refresh(list) end)
          end }
      end
      if tossable then
        options[#options + 1] = { label = Strings("TOSS"), onSelect = function()
            -- KeyItemFlags + HMs decide tossability (not price:
            -- MOON STONE is price 0 but tossable)
            if not def or def.keyItem
               or ItemEffects.alias(id, def):find("^HM_") then
              showMessages(game, { Strings("That's too impor-\ntant to toss!") })
              return
            end
            local QuantityBox = require("src.ui.QuantityBox")
            game.stack:push(QuantityBox.new(game, {
              max = game.save.inventory[id] or 1,
              onDone = function(qty)
                if not qty then return end
                local ChoiceBox = require("src.ui.ChoiceBox")
                game.stack:push(ChoiceBox.new(game, function(yes)
                  if not yes then return end
                  Bag.remove(game.save, id, qty)
                  refresh(list)
                  showMessages(game, { Strings("Threw away\n%s.", def and def.name or id) })
                end))
              end,
            }))
          end }
      end
      -- SEL: the property byte's CANT_SELECT bit is what Pack's
      -- .selectable branches read, so the six key items GSC lets you put on
      -- the SELECT button (BICYCLE, ITEMFINDER, the three rods) offer it and
      -- nothing else does.
      if gen2 and def and def.registerable then
        options[#options + 1] = { label = Strings("SEL"), onSelect = function()
            game.save.registeredItem = id
            require("src.core.Sound").play(game.data, "Press_AB")
            showMessages(game, { Strings("Registered the\n%s.",
              def.name or id) })
          end }
      end
      if gen2 then
        options[#options + 1] = { label = Strings("QUIT"), onSelect = function() end }
      end
      local th = #options * 2 + 1
      game.stack:push(Menu.new(game, options, gen2
        and { tx = 0, ty = 12 - th, tw = 7, th = th }
        or { tx = 13, ty = 10, tw = 7, th = th }))
    end,
  })
  if gen2 then list.sgbPalettes = packPalettes end
  return list
end

BagMenu.POCKETS = POCKETS
BagMenu.pocketOf = pocketOf

-- The SELECT button's registered item (home/menu.asm CheckRegisteredItem):
-- the pack never opens, so the use flow runs against a stub list.  A
-- registration the player no longer holds is dropped and nothing happens,
-- which is .CheckRegisteredNo.
function BagMenu.useRegistered(game)
  local id = game.save.registeredItem
  if not id then return false end
  local def = game.data.items[id]
  if not def or not def.registerable or not game.save.inventory[id] then
    game.save.registeredItem = nil
    return false
  end
  useItem(game, nil, id, { close = function() end, items = {}, index = 1 })
  return true
end

return BagMenu
