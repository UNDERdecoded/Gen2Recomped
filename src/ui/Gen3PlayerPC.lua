-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S PC.
--
-- The PC in the room the game starts in is a script -- `special 217 /
-- "{PLAYER} booted up the PC." / special 252 BedroomPC / waitstate` -- and
-- 252 opened the GAME BOY screen, because nothing was registered under
-- `PlayerPC` for Hoenn.  Reported from play: "the pc in the starting bedroom
-- ... I get the gen1 menus for depositing items".
--
-- The words and the ORDER are the cartridge's, read by
-- RomExtractorGen3:extractPCMenu out of Emerald's own three menu tables:
--
--     ITEM STORAGE / MAILBOX / DECORATION / TURN OFF
--       FireRed ITEM STORAGE -> WITHDRAW ITEM / DEPOSIT ITEM / CANCEL
--       MAILBOX      -> READ / MOVE TO BAG / GIVE / CANCEL
--
-- Note that WITHDRAW comes FIRST here.  Gen 1's screen puts it after nothing
-- at all -- its rows are WITHDRAW / DEPOSIT / TOSS / LOG OFF -- but the two
-- happen to agree on that one; what they do not agree on is the menu ABOVE
-- it, which Gen 1 does not have.
--
-- WHAT WORKS AND WHAT DOES NOT. Item storage shares save.pcItems, but its
-- screens are cartridge-specific: FireRed keeps its own rows, Item PC
-- furniture, GIVE path, and SELECT reorder; Emerald uses the Gen3 bag's
-- store screens and the cartridge's row descriptions. MAILBOX and DECORATION
-- remain the cartridge's rows, with unsupported actions reported explicitly.

local Menu = require("src.ui.Menu")
local Strings = require("src.core.Strings")

local Gen3PlayerPC = {}

local function record(game)
  local c = game and game.data and game.data.constants
  local r = c and c.gen3PCMenu
  return type(r) == "table" and r or nil
end

-- A row's label, from the dataset where there is one.  A cache imported
-- before extractPCMenu existed keeps the same rows in the same order under
-- names this file spells itself, so the screen never comes up blank.
local FALLBACK = {
  main = { "ITEM STORAGE", "MAILBOX", "DECORATION", "TURN OFF" },
  itemStorage = { "WITHDRAW ITEM", "DEPOSIT ITEM", "TOSS ITEM", "CANCEL" },
  mailbox = { "READ", "MOVE TO BAG", "GIVE", "CANCEL" },
}
local FRLG_FALLBACK = {
  main = { "ITEM STORAGE", "MAILBOX", "TURN OFF" },
  itemStorage = { "WITHDRAW ITEM", "DEPOSIT ITEM", "CANCEL" },
  mailbox = { "READ", "MOVE TO BAG", "GIVE", "EXIT" },
}

-- sStandardTextBox_WindowTemplates[0] in new_menu_helpers.c.  Both the static
-- top-menu prompt and the highlighted Item Storage description are printed in
-- this same field-dialogue window on FireRed.
local FRLG_DIALOGUE_BOX = {
  tx = 2, ty = 15, tw = 26, th = 4,
  gbaWindow = true, textX = 0, textY = 1,
}

function Gen3PlayerPC.words(game, menu)
  local c = game and game.data and game.data.constants or {}
  local r = record(game)
  local bag = c.gen3BagScreen
  local fireRed = c.gen3FRLGItemPc ~= nil
                  or (type(bag) == "table" and bag.layout == "frlg")
  if fireRed then
    local expected = FRLG_FALLBACK[menu]
    local list = r and r[menu]
    -- A cache imported before the FireRed-specific player_pc.c reader may
    -- still contain Emerald's 4-row main/item-storage tables.  The Item PC
    -- asset itself is a FireRed cartridge marker, so use the cartridge's exact
    -- row set until the required-file reimport refreshes constants.lua.
    if expected and type(list) == "table" and #list == #expected then return list end
    return expected or {}
  end
  local list = (r and r[menu]) or FALLBACK[menu]
  return list or {}
end

-- ---------------------------------------------------------------------------
-- THE ITEM STORAGE SCREENS ARE GEN 3, NOT THE GAME BOY'S.
--
-- Reported from play: "after I write withdraw item then the menu where potion
-- is visible... that menu is gbc color".  It was.  The three flows used to be
-- taken wholesale from src/ui/PlayerPC.lua, and those push `ListMenu`, which
-- paints a 160x144 white Game Boy page with the Game Boy font -- so choosing
-- WITHDRAW ITEM out of a Gen 3 PC dropped the player onto a Kanto screen.
--
-- Emerald can still reuse Gen3BagMenu for the PC-owned list. FireRed cannot:
-- item_pc.c has a dedicated background, windows and item-icon placement, so
-- WITHDRAW uses Gen3ItemPcFRLG while DEPOSIT still opens the real bag.
--
-- WHAT IS REUSED AND WHAT IS NOT.  The store/capacity mutations are shared,
-- but FireRed owns the list, action submenu, quantity prompt, result windows,
-- GIVE path and SELECT reorder.  DEPOSIT opens the real bag, which is what the
-- cartridge opens: you are choosing out of your pockets, not out of the PC.
local function itemDef(game, id)
  return (game.data.items or {})[id]
end

local function itemName(game, id)
  local def = itemDef(game, id)
  return (def and def.name) or id
end

-- The Gen 3 save really stores the PC's fifty slots in order. Preserve that
-- order instead of rebuilding the screen alphabetically, because item_pc.c's
-- SELECT move mode edits these slots in place and Gen3Save writes pcOrder back
-- to the cartridge layout.
local function pcOrder(game, store)
  local out, seen = {}, {}
  for _, id in ipairs(game.save.pcOrder or {}) do
    if not seen[id] and (tonumber(store[id]) or 0) > 0 then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  local rest = {}
  for id, n in pairs(store) do
    if not seen[id] and (tonumber(n) or 0) > 0 then rest[#rest + 1] = id end
  end
  table.sort(rest, function(a, b)
    local ai = tonumber((itemDef(game, a) or {}).index) or math.huge
    local bi = tonumber((itemDef(game, b) or {}).index) or math.huge
    if ai ~= bi then return ai < bi end
    return tostring(a) < tostring(b)
  end)
  for _, id in ipairs(rest) do out[#out + 1] = id end
  game.save.pcOrder = out
  return out
end

local function reorderPc(game, store, sourceId, beforeId)
  local order = pcOrder(game, store)
  local source
  for i, id in ipairs(order) do
    if id == sourceId then source = i; break end
  end
  if not source then return end
  table.remove(order, source)
  local target = #order + 1
  if beforeId then
    for i, id in ipairs(order) do
      if id == beforeId then target = i; break end
    end
  end
  table.insert(order, target, sourceId)
  game.save.pcOrder = order
end

-- A Gen3BagMenu row per stack in `store`, in item order, with the CANCEL the
-- cartridge ends every one of these lists with.
local function storageRows(game, store)
  local ids = pcOrder(game, store)
  local rows = {}
  for _, id in ipairs(ids) do
    local def = itemDef(game, id)
    rows[#rows + 1] = {
      id = id,
      label = itemName(game, id),
      qty = tonumber(store[id]),
      -- a key item prints no count, here as in the bag
      important = (def and (def.keyItem or (tonumber(def.importance) or 0) ~= 0))
                  or nil,
      description = def and (def.description or def.desc),
    }
  end
  rows[#rows + 1] = { close = true, label = Strings("CANCEL") }
  return rows
end

-- FireRed's dedicated Item PC, or the shared Gen 3 bag-list fallback on the
-- other Gen 3 dataset. This list is one list, not bag pockets.
local function storageList(game, title, rows, onPick, onCancel, onReorder, nativeProse)
  local bagScreen = (game.data.constants or {}).gen3BagScreen
  local fireRed = ((game.data.constants or {}).gen3FRLGItemPc ~= nil)
                  or (type(bagScreen) == "table" and bagScreen.layout == "frlg")
  local menu
  if fireRed then
    menu = require("src.ui.Gen3ItemPcFRLG").new(game, {
      title = title, rows = rows, onPick = onPick, onCancel = onCancel,
      onReorder = onReorder, nativeProse = nativeProse,
    })
  else
    menu = require("src.ui.Gen3BagMenu").new(game, {
      rows = rows, pick = true, onPick = onPick, onCancel = onCancel,
    })
    menu.pockets = { { key = "ITEM", name = title } }
    menu.pocket = 1
    menu.lockPocket = true
  end
  game.stack:push(menu)
  return menu
end

-- Key items and HMs always move one, with no prompt (IsKeyItem in
-- players_pc.asm, and FireRed's own ItemStorage arm does the same).
local function askQuantity(game, id, max, cb, itemPc, verb)
  local def = itemDef(game, id)
  if (def and def.keyItem) or tostring(id):find("^HM_") or (max or 1) <= 1 then
    return cb(1)
  end
  if itemPc and itemPc.box then
    game.stack:push(require("src.ui.Gen3ItemPcQuantity").new(game, itemPc, {
      max = max,
      itemName = itemName(game, id),
      verb = verb,
      onDone = function(qty) if qty then cb(qty) end end,
    }))
    return
  end
  game.stack:push(require("src.ui.QuantityBox").new(game, {
    max = max,
    onDone = function(qty) if qty then cb(qty) end end,
  }))
end

local function say(game, text, after, itemPc, kind)
  if itemPc then
    game.stack:push(require("src.ui.Gen3ItemPcMessage").new(
      game, itemPc, text, after, kind))
    return
  end
  game.stack:push(require("src.render.TextBox").new(game, text, after))
end

local function giveFromPc(game, itemPc, pc, id, resume)
  local party = game.save.party or {}
  if #party == 0 then
    return say(game, Strings("There is no POKéMON."), resume, itemPc, "noParty")
  end
  require("src.ui.Screens").push(game, "PartyMenu", {
    pickOnly = true,
    onSwitch = function(mon)
      require("src.ui.BagMenu").handOver(game, mon, id, function()
        pc[id] = (pc[id] or 0) - 1
        if pc[id] <= 0 then pc[id] = nil end
        pcOrder(game, pc)
        resume()
      end, {
        giveHeld = function(target, giveId)
          local previous = target.item
          if previous then
            local Bag = require("src.inventory.Bag")
            if not Bag.add(game.save, previous, 1, game.data) then return false end
          end
          target.item = giveId
          return true
        end,
      })
    end,
  })
end

local function g3Withdraw(game, back)
  local pc = game.save.pcItems
  local open
  local current
  local function resume()
    if current and current.setRows then
      current:setRows(storageRows(game, pc))
    else
      open()
    end
  end
  open = function()
    current = storageList(game, Strings("WITHDRAW ITEM"), storageRows(game, pc),
      function(id, screen, action)
        current = screen or current
        if action == "give" then
          return giveFromPc(game, current, pc, id, resume)
        end
        askQuantity(game, id, pc[id] or 1, function(qty)
          local Bag = require("src.inventory.Bag")
          if not Bag.add(game.save, id, qty, game.data) then
            return say(game, Strings("You can't carry\nany more items."),
                       resume, current)
          end
          pc[id] = (pc[id] or 0) - qty
          if pc[id] <= 0 then pc[id] = nil end
          pcOrder(game, pc)
          require("src.core.Sound").play(game.data, "Withdraw_Deposit")
          local line = require("src.ui.Gen3BagMenu").pcWord(game, "withdrew")
          line = tostring(line or Strings("Withdrew {VAR2}\n{VAR1}(s)."))
            :gsub("{STR_VAR1}", "{VAR1}"):gsub("{STR_VAR2}", "{VAR2}")
            :gsub("{VAR2}", tostring(qty)):gsub("{VAR1}", itemName(game, id))
          say(game, line,
              resume, current)
        end, current, "WITHDRAW")
      end, back, function(sourceId, beforeId)
        reorderPc(game, pc, sourceId, beforeId)
        current:setRows(storageRows(game, pc))
      end, true)
  end
  open()
end

local function g3Deposit(game, back)
  -- ITEMMENULOCATION_ITEMPC is still the real bag, but it is a BAG MODE, not
  -- a generic pick callback that closes the screen.  Let Gen3BagMenu own that
  -- mode so its deposit title, CANCEL/return row, quantity path and result
  -- window stay on the same retail screen throughout the operation.
  game.stack:push(require("src.ui.Gen3BagMenu").new(game, {
    store = "deposit",
    itemPc = true,
    onCancel = back,
  }))
end

local function g3Toss(game, back)
  local pc = game.save.pcItems
  local open
  local current
  local function resume()
    if current and current.setRows then
      current:setRows(storageRows(game, pc))
    else
      open()
    end
  end
  open = function()
    current = storageList(game, Strings("TOSS ITEM"), storageRows(game, pc),
      function(id, screen)
        current = screen or current
        local def = itemDef(game, id)
        if (def and def.keyItem) or tostring(id):find("^HM_") then
          return say(game, Strings("That's too impor-\ntant to toss!"), resume)
        end
        askQuantity(game, id, pc[id] or 1, function(qty)
          say(game, Strings("Toss %s?", itemName(game, id)), function()
            game.stack:push(require("src.ui.ChoiceBox").new(game, function(yes)
              if not yes then return resume() end
              pc[id] = (pc[id] or 0) - qty
              if pc[id] <= 0 then pc[id] = nil end
              say(game, Strings("Threw away %s.", itemName(game, id)), resume)
            end, { noSound = true }))
          end)
        end, current, "TOSS")
      end, back)
  end
  open()
end

local STORE_MODES = { "withdraw", "deposit", "toss" }

local function openStore(game, mode)
  local Gen3BagMenu = require("src.ui.Gen3BagMenu")
  game.save.pcItems = game.save.pcItems or {}
  game.stack:push(Gen3BagMenu.new(game, { store = mode }))
end

-- FireRed keeps the dedicated item_pc.c screens above. Emerald uses the
-- shared Gen3 bag's store modes and exposes each row's cartridge description.
local function itemStorage(game, onCancel)
  local words = Gen3PlayerPC.words(game, "itemStorage")
  local constants = (game.data or {}).constants or {}
  local bagScreen = constants.gen3BagScreen
  local fireRed = constants.gen3FRLGItemPc ~= nil
                  or (type(bagScreen) == "table" and bagScreen.layout == "frlg")
  local describe = (record(game) or {}).describe or {}
  game.save.pcItems = game.save.pcItems or {}
  local rows = {}
  for i, label in ipairs(words) do
    if fireRed then
      local word = tostring(label or ""):upper()
      local flow = word:find("WITHDRAW", 1, true) and g3Withdraw
        or word:find("DEPOSIT", 1, true) and g3Deposit
        or word:find("TOSS", 1, true) and g3Toss
        or nil
      rows[#rows + 1] = {
        label = Strings(label),
        describe = describe[i],
        keepOpen = flow ~= nil,
        onSelect = flow and function() flow(game) end or nil,
      }
    else
      local mode = STORE_MODES[i]
      rows[#rows + 1] = {
        label = Strings(label),
        describe = describe[i],
        keepOpen = mode ~= nil,
        onSelect = mode and function() openStore(game, mode) end or nil,
      }
    end
  end
  -- sWindowTemplate_ItemStorageSubmenu: (1,1), 14 wide inside its frame
  local sub = Menu.new(game, rows, { noSound = true, tx = 0, ty = 0, tw = 16,
                                     describeBox = fireRed and FRLG_DIALOGUE_BOX or nil,
                                     onCancel = onCancel })
  -- placed on the GBA's own 240x160, not the Game Boy's centred 160x144
  function sub:uiSize() return 240, 160 end
  game.stack:push(sub)
end

-- DECORATION -- the same screen the secret base's PC opens.
--
-- Reported from play: "the lady in the game corner that is supposed to give
-- you a doll doesnt give you anything".  She does: a thousand coins buy a
-- DOLL and it lands in the decoration inventory, and her line is "we'll send
-- it to your PC at home".  This row said the feature was not built, so home
-- was where the doll went to disappear.  The screen behind it -- DECORATE,
-- PUT AWAY, TOSS -- has existed since the secret bases went in; only this
-- door onto it was missing.
local function decoration(game, back)
  local okC, Gen3Commands = pcall(require, "src.script.Gen3Commands")
  local okD, Decor = pcall(require, "src.world.Gen3Decorations")
  -- ASKED BEFORE ANYTHING IS PUSHED.  A cache imported before the decoration
  -- tables were read has no menu to show, and finding that out halfway
  -- through would leave the player looking at a screen that had already
  -- decided to go back.
  local rows = okD and (Decor.record(game and game.data) or {}).menu
  if not (okC and Gen3Commands.decorationPC and type(rows) == "table"
          and #rows > 0) then
    return false
  end
  Gen3Commands.decorationPC(
    { game = game, save = game.save, overworld = game.overworld }, back)
  return true
end

local function notBuilt(game, what)
  local TextBox = require("src.render.TextBox")
  game.stack:push(TextBox.new(game,
    Strings("%s is not in this\nport yet.", what)))
end

-- `onDone` is what the script's `waitstate` is waiting for: Gen3Commands'
-- pushBlocking parks the runner until this screen closes.  Every way out of
-- here goes through `close`, so the park can never outlive the screen.
-- WHICH OF THE FOUR ROWS THIS PC SHOWS.
--
-- The bedroom's shows all four; the one in a Poke Centre leaves DECORATION
-- out and shows three.  That is not this screen's choice -- both specials
-- load a list of row numbers, and the import reads both (pcMenuOrders).  A
-- dataset without them shows everything, which is what this screen did
-- before either was read.
function Gen3PlayerPC.order(game, which, count)
  local r = record(game)
  local list = which and r and r.orders and r.orders[which]
  if type(list) == "table" and #list > 0 then return list end
  local all = {}
  for i = 1, count do all[i] = i end
  return all
end

-- ...and the way back onto this screen once one of its rows is finished with.
-- The decoration menu pushes its own stack of menus and pops them itself, so
-- what it returns to has to be a FRESH PC menu rather than the one it
-- replaced -- which is exactly what the cartridge does: every one of the PC's
-- rows ends by walking back into the PC script.
function Gen3PlayerPC.reopen(game, opts)
  local ok, menu = pcall(Gen3PlayerPC.new, game, opts)
  if ok and menu then pcall(game.stack.push, game.stack, menu) end
end

function Gen3PlayerPC.new(game, opts)
  opts = opts or {}
  game.save.pcItems = game.save.pcItems or {}
  local words = Gen3PlayerPC.words(game, "main")
  local constants = (game.data or {}).constants or {}
  local bagScreen = constants.gen3BagScreen
  local fireRed = constants.gen3FRLGItemPc ~= nil
                  or (type(bagScreen) == "table" and bagScreen.layout == "frlg")
  local pcRecord = record(game) or {}
  local topPrompt = pcRecord.topPrompt
                    or (fireRed and "What would you like to do?" or nil)
  local menu
  local function close()
    local done = opts.onDone
    opts.onDone = nil
    if done then done() end
  end
  local rows = {}
  for _, i in ipairs(Gen3PlayerPC.order(game, opts.order, #words)) do
    local label = words[i]
    local row = { label = Strings(label or ""), describe = topPrompt }
    local word = tostring(label or ""):upper()
    if word:find("ITEM STORAGE", 1, true) then
      row.keepOpen = true
      row.onSelect = function() itemStorage(game) end
    elseif word:find("DECORATION", 1, true) then
      -- DECORATION opens its own screen, and that screen owns what happens
      -- next -- so this row does NOT keepOpen: the decoration menu walks back
      -- into this one itself when the player is done with it.
      row.onSelect = function()
        if not decoration(game, function() Gen3PlayerPC.reopen(game, opts) end) then
          notBuilt(game, Strings(label))
        end
      end
    elseif word:find("MAILBOX", 1, true) then
      if fireRed then
        -- Task_PlayerPcMailbox removes the top menu before displaying this
        -- exact field message, then Task_ReturnToTopMenu redraws the menu after
        -- A/B.  The port has no mail-save model yet, so its representable
        -- FireRed state is precisely the cartridge's zero-mail arm.
        row.onSelect = function()
          local TextBox = require("src.render.TextBox")
          game.stack:push(TextBox.new(game, Strings("There's no MAIL here."),
            function() Gen3PlayerPC.reopen(game, opts) end,
            { promptOnlyWhenWaiting = true }))
        end
      else
        row.keepOpen = true
        row.onSelect = function() notBuilt(game, Strings(label)) end
      end
    else
      -- TURN OFF: the row that ends the session
      row.onSelect = close
    end
    rows[#rows + 1] = row
  end
  menu = Menu.new(game, rows, {
    -- PlayersPCMenu holds BIT_NO_MENU_BUTTON_SOUND on both cartridges
    noSound = true,
    -- sWindowTemplate_TopMenu_*: (1,1), 13 wide inside its frame
    tx = 0, ty = 0, tw = 15,
    describeBox = fireRed and FRLG_DIALOGUE_BOX or nil,
    onCancel = close,
  })
  function menu:uiSize() return 240, 160 end
  return menu
end

return Gen3PlayerPC
