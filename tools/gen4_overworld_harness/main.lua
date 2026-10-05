-- tools/gen4_overworld_harness/main.lua
--
-- A HEADLESS SINNOH OVERWORLD, RENDERED TO A PNG AND TRACED PER TICK.
--
-- WHY THIS EXISTS.  The terrain harness stands in Twinleaf and draws the
-- GROUND; the battle harness draws a BATTLE.  Neither stands up an
-- `OverworldState`, so nothing about the live cast -- who is on the map, who
-- is drawn, who follows the player -- could be looked at.  Items 9 and 10 of
-- the play-test list ("Barry is invisible while following", "Rowan is
-- translucent") are both about exactly that, and both were unanswerable.
--
--   POKEPORT_DATA_DIR=<platinum cache>/data/generated \
--     MAP=T01 X=15 Y=25 WALK=down STEPS=8 TAG=barry \
--     love tools/gen4_overworld_harness
--
-- Env: MAP, X, Y, FACING, WALK (a direction to hold), STEPS, TICKS, TAG,
--      W/H, VERSION, FOLLOW (a localId to make into a follower), TRACE,
--      THEN/THEN_X/THEN_Y (cross to another map mid-run), WARPAT=x,y,
--      OBJRELOAD=index,x,y, PARTY/PARTYLEVEL, HURT, PRESS (A every n
--      ticks), GIVE/GIVE_G4 (items), DEX_SEEN (species, or "all"), HOF
--      (hall-of-fame rosters), SCREEN (a UI screen to push over the
--      world, by registry name OR module name) and POCKET.
--
-- WHAT IT DELIBERATELY DOES NOT DO.  No launcher, no save on disk, no window.
-- It pushes the real `OverworldController` onto a real stack, because the
-- whole point is to exercise the engine's own path rather than a
-- reimplementation of it -- the battle harness learned that lesson three
-- times (`enter`, `Font.load`, `Game.input`) and each gap was first reported
-- as an engine fault.
local W = tonumber(os.getenv("W") or "512")
local H = tonumber(os.getenv("H") or "384")
local TAG = os.getenv("TAG") or "ow"

local function dirHeld(want)
  return function(_, k) return want and k == want end
end

function love.load()
  local ok, err = xpcall(function()
    local GameVersion = require("src.core.GameVersion")
    GameVersion.set(os.getenv("VERSION") or "platinum")

    -- POKEPORT_ASSET_ROOT: the launcher mounts the cache's `assets/`; with no
    -- launcher here, read pictures straight from that folder (as the battle
    -- and contest harnesses do), or every screen pushed over the world --
    -- the shop's counter art included -- comes up placeholder.
    local assetRoot = os.getenv("POKEPORT_ASSET_ROOT")
    if assetRoot then
      local Assets = require("src.render.Assets")
      local realImage, held = Assets.image, {}
      Assets.image = function(path, ...)
        if type(path) == "string" and not held[path] then
          local f = io.open(assetRoot .. "/" .. path, "rb")
          if f then
            local bytes = f:read("*a"); f:close()
            local okI, img = pcall(love.graphics.newImage, love.filesystem.newFileData(bytes, path))
            if okI then img:setFilter("nearest", "nearest"); held[path] = img end
          end
        end
        return held[path] or realImage(path, ...)
      end
    end

    local Data = require("src.core.Data")
    Data:load()
    if not Data.isGen4Cache then
      print("WARNING: POKEPORT_DATA_DIR is not a Gen 4 cache")
    end

    local SaveData = require("src.core.SaveData")
    local Game = require("src.core.Game")
    Game.data = Data

    -- THE SERVICES THE ENGINE BRINGS UP, IN THE ENGINE'S OWN ORDER.
    --
    -- Taken from `Game:boot` rather than picked one at a time as each nil
    -- was hit.  The battle harness was assembled the second way and reported
    -- three engine faults that were all missing lifecycle -- `enter`,
    -- `Font.load`, `Game.input`.  Anything added here should be added
    -- because `Game:boot` does it, and in the place `Game:boot` does it.
    -- MODS FIRST, because that is what REGISTERS THE COMMAND SET.
    -- `src/mods/Builtins.lua` calls `Commands.registerInto`, and that is the
    -- only thing that puts the `g4_*` verbs in the script registry.  Without
    -- it every Gen 4 script runs and every row reports "unknown command
    -- 'g4_set_var' (skipped)" -- which looks exactly like a lowering bug and
    -- is nothing of the kind.  Fifth harness gap of this kind; the rule
    -- stands -- do what `Game:boot` does, in the order it does it.
    local ModLoader = require("src.mods.Loader")
    Game.mods = ModLoader.new()
    Game.mods:load(Data)
    Game.modStatus = Game.mods:status()
    require("src.render.Pipelines").install(Data)
    local Renderer = require("src.render.Renderer")
    Game.renderer = Renderer
    Renderer:init()
    require("src.render.Font").load(Data)
    require("src.ui.Theme").load(Data)
    require("src.core.Strings").load(Data)
    local StateStack = require("src.core.StateStack")
    StateStack:init()
    Game.stack = StateStack
    Game.save = SaveData.newGame(Game.bootConfig and Game:bootConfig() or {})
    if Game.adoptSave then pcall(Game.adoptSave, Game, Game.save, true) end

    -- INPUT IS A REAL OBJECT FROM THE FIRST FRAME.  The battle harness
    -- reported a stall as an engine fault because its press loop sat behind
    -- `if Game.input then` with a nil input and pressed nothing.  Here it
    -- exists before anything ticks.
    local held = nil
    local pressA = false
    Game.input = {
      wasPressed  = function(_, k) return pressA and k == "a" end,
      isDown      = function(_, k) return held ~= nil and k == held end,
      wasReleased = function() return false end,
    }

    local OW = require("src.world.OverworldController")
    Game.stack:push(OW, os.getenv("MAP") or "T01",
                    tonumber(os.getenv("X") or "15"),
                    tonumber(os.getenv("Y") or "25"),
                    os.getenv("FACING") or "down")

    -- OPTIONALLY MAKE SOMEONE A FOLLOWER, which is what `setmovementtype
    -- <id>, 48` does in the cartridge.  Done through the module's own `adopt`
    -- rather than by setting the flag by hand, so the harness exercises the
    -- seam the script uses.
    -- FOLLOW NAMES A SPRITE, NOT JUST A localId.
    --
    -- The first version took a localId and the first run adopted T01's
    -- `map_signpost` -- localId 4 -- which has no character art at all, so
    -- "the follower did not draw" was true and meant nothing.  Two objects
    -- can also share a localId on a Gen 4 map (T01's guitarist and its arrow
    -- signpost are both 3), so a number is not an identifier here.  A sprite
    -- name is, and the cast is printed either way.
    -- FLAGS GO THROUGH THE ENGINE'S OWN COMMANDS, so `syncFlagObjects` runs
    -- exactly as it does for a script.  Route 201 makes Barry the partner and
    -- then SETS his hide flag on the very next line, and that sequence is the
    -- thing under test -- faking it by poking `save.flags` would skip the
    -- half that does the damage.
    local Commands = require("src.script.Commands")
    local flagCtx = { save = Game.save, overworld = OW, game = Game,
                      data = Data, mapCallback = true }

    local clearFlag = os.getenv("CLEAR_FLAG")
    if clearFlag then
      Commands.clear_flag(flagCtx, clearFlag)
      print("cleared " .. clearFlag)
    end

    local Follower = require("src.world.Gen4Follower")
    local follow = os.getenv("FOLLOW")
    if follow then
      local wantId = tonumber(follow)
      local target
      local cast = {}
      for _, e in ipairs(OW.entities or {}) do
        local d = e.def
        local lid = e.localId or (d and d.localId)
        local name = d and (d.spriteName or d.sprite)
        cast[#cast + 1] = ("%s:%s@(%s,%s)"):format(tostring(lid), tostring(name), tostring(e.cellX), tostring(e.cellY))
        if not target and ((wantId and lid == wantId) or (not wantId and name == follow)) then
          target = e
        end
      end
      print("live cast -- " .. table.concat(cast, "  "))
      if target and os.getenv("HIDE_FIRST") then
        -- A HIDDEN OBJECT CAN STILL BE ADOPTED.  The cartridge hides the
        -- partner behind a flag and the script that starts the escort runs
        -- near it, so this is not a contrived state.
        target.hidden = true
        print("marked the target hidden BEFORE adopting")
      end
      if target then
        Follower.adopt(Game.save, OW, target)
        print(("adopted %s (localId %s, sprite %s)"):format(
          follow, tostring(target.localId or (target.def and target.def.localId)),
          tostring(target.def and (target.def.spriteName or target.def.sprite))))
      else
        print(("FOLLOW %s matched nobody on %s"):format(follow, tostring(OW.map and OW.map.id)))
      end
    end

    -- CROSSING A SEAM ON PURPOSE.  `Gen4Follower` has two ways to put the
    -- partner on a map: adopt the map's own object, or REBUILD one with
    -- `spawnFollower`.  Only the first is exercised by staying put, and the
    -- play report is about what happens at a border.
    local thenMap = os.getenv("THEN_MAP")
    local thenAt = tonumber(os.getenv("THEN_AT") or "40")
    if thenMap then
      -- Persistent, or the record is dropped at the door by design -- Amity
      -- Square's pet is the case that rule exists for.
      local rec = Game.save.gen4Follower
      if rec then rec.persistent = true end
    end

    -- ...and the line the cartridge runs immediately after SetMovementType.
    local setFlag = os.getenv("SET_FLAG_AFTER")
    if setFlag then
      Commands.set_flag(flagCtx, setFlag)
      local f = Follower.current(OW)
      local live = 0
      for _, e in ipairs(OW.entities or {}) do live = live + 1 end
      print(("after SetFlag %s -- follower=%s, %d live entit(ies)"):format(
        setFlag, f and "still here" or "GONE", live))
    end

    -- OPEN A UI SCREEN OVER THE WORLD.  Items 13-15 of the play-test list
    -- are all screens (Pokedex, trainer card, bag), and the only honest way
    -- to answer "is it Platinum's art" is to draw it and look.
    -- Pushed AFTER the overworld so the stack is the shape the game has.
    -- ITEMS IN THE BAG, because a new-game save has almost none and a bag
    -- screen with nothing in it draws nothing correctly.
    -- THE ENGINE'S OWN PATH, not Bag.add directly: g4_give_item is what a
    -- Sinnoh script row runs, and it is the thing under test.
    if os.getenv("GIVE_G4") then
      local C = require("src.script.Commands")
      require("src.script.Gen4Commands")
      local ctx = { game = Game, save = Game.save, data = Data, overworld = OW }
      for id in tostring(os.getenv("GIVE_G4")):gmatch("%d+") do
        local ok, err = pcall(C.g4_give_item, ctx, tonumber(id), 2)
        print(("[g4give] item %s -> %s"):format(id, ok and "ok" or tostring(err)))
      end
    end
    local give = os.getenv("GIVE")
    if give then
      local Bag = require("src.inventory.Bag")
      for name in tostring(give):gmatch("[^,]+") do name = tonumber(name) or name
        local ok, err = pcall(Bag.add, Game.save, name, 3, Data)
        print(("[give] %s -> %s"):format(name, ok and "ok" or tostring(err)))
      end
    end
    -- WHICH WARP A TILE RESOLVES TO, asked of the REAL Map rather than of a
    -- second copy of the rule.  "WARPAT=48,43 49,43" prints one line each.
    if os.getenv("WARPAT") and OW.map then
      for pair in tostring(os.getenv("WARPAT")):gmatch("%S+") do
        local x, y = pair:match("(%-?%d+),(%-?%d+)")
        x, y = tonumber(x), tonumber(y)
        local hit = x and OW.map.warpAt
                    and OW.map.warpAt[y * OW.map.widthCells + x]
        print(("[warpat] (%d,%d) -> %s"):format(x or -1, y or -1,
          hit and ("warp %d, dest %s header %s"):format(hit.index,
            tostring(hit.def.destMap), tostring(hit.def.destHeader))
            or "none"))
      end
    end

    -- DOES A SCRIPTED MOVE SURVIVE A SAVE AND A RELOAD?
    -- "OBJRELOAD=index,x,y" moves that object, captures the save, throws
    -- the pool away and rebuilds the map the way a fresh boot would, then
    -- prints where the object came back.
    if os.getenv("OBJRELOAD") then
      local idx, nx, ny = tostring(os.getenv("OBJRELOAD")):match("(%d+),(%d+),(%d+)")
      idx, nx, ny = tonumber(idx), tonumber(nx), tonumber(ny)
      local before
      for _, npc in ipairs(OW.npcs or {}) do
        if npc.def and npc.def.index == idx then before = npc end
      end
      if not before then
        print(("[objreload] no object with index %d on this map"):format(idx or -1))
      else
        print(("[objreload] #%d starts at (%s,%s)"):format(idx,
          tostring(before.cellX), tostring(before.cellY)))
        before.cellX, before.cellY = nx, ny
        before.px, before.py = nx * 16, ny * 16
        print(("[objreload] moved to (%d,%d)"):format(nx, ny))
        OW:captureSave(Game.save)
        local kept = Game.save.gen4Objects
        kept = kept and kept[OW.map.id] and kept[OW.map.id][idx]
        print(("[objreload] save holds %s"):format(kept
          and ("(%s,%s)"):format(tostring(kept.x), tostring(kept.y)) or "NOTHING"))
        OW.npcPool = {}
        OW.npcs = {}
        OW:setMap(OW.map.id, 10, 10, "down")
        local after
        for _, npc in ipairs(OW.npcs or {}) do
          if npc.def and npc.def.index == idx then after = npc end
        end
        print(("[objreload] after a rebuild #%d is at %s"):format(idx,
          after and ("(%s,%s)"):format(tostring(after.cellX),
            tostring(after.cellY)) or "GONE"))
      end
    end

    local screenName = os.getenv("SCREEN")
    if os.getenv("SCREEN") then
      local d = Data.gen4_dex
      local mons = Data.pokemon or {}
      local n, firstKey = 0, nil
      for k in pairs(mons) do n = n + 1; if firstKey == nil then firstKey = k end end
      do local lo, hi, nDex = math.huge, -math.huge, 0
        for k, v in pairs(mons) do
          if type(k) == "number" then
            if k < lo then lo = k end
            if k > hi then hi = k end
          end
          if type(v) == "table" and v.dex then nDex = nDex + 1 end
        end
        print(("[dex] numeric ids %s..%s | species carrying a `dex` field: %d"):format(
          tostring(lo), tostring(hi), nDex)) end
      print(("[dex] pokemon entries=%d firstKey=%s(%s) [1]=%s [387]=%s dexSize=%s"):format(
        n, tostring(firstKey), type(firstKey), tostring(mons[1] ~= nil),
        tostring(mons[387] ~= nil), tostring((Data.constants or {}).dexSize)))
      print(("[dex] data.gen4_dex=%s banner=%s"):format(type(d),
        type(d)=="table" and tostring(d.banner and d.banner.path) or "-"))
    end

    -- GIFT=<key>: a Mystery Gift waiting for the deliveryman (Gen4MysteryGift)
    if os.getenv("GIFT") then
      local MG = require("src.pokemon.Gen4MysteryGift")
      Game.save.hallOfFame = { {} }
      print(("[gift] waiting %s -> %s"):format(os.getenv("GIFT"), tostring(MG.choose(Game.save, os.getenv("GIFT")))))
    end
    -- A PARTY, because a new-game save has none and a heal test on an empty
    -- party is a test that cannot fail.
    if os.getenv("PARTY") then
      local Pokemon = require("src.pokemon.Pokemon")
      Game.save.party = { Pokemon.new(Data, tonumber(os.getenv("PARTY")),
                                      tonumber(os.getenv("PARTYLEVEL") or "12")) }
    end
    -- HURT THE PARTY FIRST, so "it healed" is a change and not a constant.
    -- A heal test on a full-health party passes whether or not anything runs.
    if os.getenv("HURT") then
      for _, mon in ipairs(Game.save.party or {}) do
        mon.hp = math.max(1, math.floor(((mon.stats and mon.stats.hp) or 20) / 4))
      end
    end
    local function partyHp()
      local out = {}
      for _, mon in ipairs(Game.save.party or {}) do
        out[#out+1] = ("%s/%s"):format(tostring(mon.hp), tostring(mon.stats and mon.stats.hp))
      end
      return table.concat(out, " ")
    end
    print("party before: " .. partyHp())
    -- MARK SPECIES SEEN/OWNED, so the dex has something to list and an entry
    -- page to open.  A dex screen on an empty dex draws an empty dex
    -- correctly, which tells you nothing about its art.
    local dexSeen = os.getenv("DEX_SEEN")
    if dexSeen then
      Game.save.pokedex = Game.save.pokedex or {}
      local d = Game.save.pokedex
      d.seen, d.owned = d.seen or {}, d.owned or {}
      if dexSeen == "all" then
        for id = 1, 600 do d.seen[id] = true; d.owned[id] = true end
      end
      for id in tostring(dexSeen):gmatch("%d+") do
        d.seen[tonumber(id)] = true; d.owned[tonumber(id)] = true
      end
    end
    -- A HALL OF FAME ENTRY, because the trainer card picks one of SEVEN faces
    -- from the card level, and a screen looked at in one state says nothing
    -- about the other six.  `HOF=n` puts n empty rosters in the save, which is
    -- what `#save.hallOfFame > 0` -- the one criterion of the five that this
    -- port can evaluate -- is asking about.
    if os.getenv("HOF") then
      local rosters = tonumber(os.getenv("HOF")) or 1
      Game.save.hallOfFame = {}
      for i = 1, rosters do Game.save.hallOfFame[i] = {} end
      print(("[hof] %d roster(s)"):format(#Game.save.hallOfFame))
    end
    if screenName then
      local Screens = require("src.ui.Screens")
      -- OPEN IT AT A NAMED PAGE.  A screen that only ever renders its first
      -- page proves nothing about the ones that select something else: the
      -- bag's pocket icons all look plausible until you check that the
      -- highlighted one MOVES.
      local opts = {}
      if os.getenv("POCKET") then opts.pocket = os.getenv("POCKET") end
      -- ANY SCREEN, NOT ONLY A REGISTERED ONE.  The starter selection,
      -- the intro and the title are pushed by script rather than named
      -- in `Screens`, so a harness that can only reach the registry
      -- cannot look at half the screens there are.
      local okS, errS = pcall(Screens.push, Game, screenName, opts)
      if not okS then
        local okM, mod = pcall(require, "src.ui." .. screenName)
        if okM and type(mod) == "table" and mod.new then
          okS, errS = pcall(function()
            Game.stack:push(mod.new(Game, opts))
          end)
          if okS then errS = "pushed by module name" end
        end
      end
      print(("[screen] push %s -> %s"):format(screenName,
             okS and "ok" or tostring(errS)))
    end
    held = os.getenv("WALK")
    local ticks = tonumber(os.getenv("TICKS") or "180")
    -- A-PRESSES ON A SCHEDULE, and the press is REAL: the battle harness
    -- once guarded its presses behind `if Game.input then` with a nil input
    -- and reported a stall as though presses had been tried.
    local pressEvery = tonumber(os.getenv("PRESS") or "0")
    for i = 1, ticks do
      pressA = pressEvery > 0 and (i % pressEvery == 0)
      if thenMap and i == thenAt then
        local okM, errM = pcall(OW.setMap, OW, thenMap,
                                tonumber(os.getenv("THEN_X") or "10"),
                                tonumber(os.getenv("THEN_Y") or "10"), "down")
        print(("crossed to %s: %s"):format(thenMap, okM and "ok" or tostring(errM)))
        local f2 = Follower.current(OW)
        print(("after crossing -- follower=%s"):format(
          f2 and ("spawned=%s sprite=%s"):format(tostring(f2.gen4FollowerSpawned),
                 tostring(f2.def and (f2.def.spriteName or f2.def.sprite))) or "NONE"))
      end
      -- TICK THE STACK, NOT THE OVERWORLD.  `StateStack:update` runs the TOP
      -- state, and a text box, menu or yes/no prompt is pushed above the
      -- overworld -- so ticking `OW` directly leaves every box unable to
      -- consume a press.  Measured before this: talking to the Pokemon
      -- Centre nurse parked at `g4_message_var` for 360 frames and the
      -- party never healed, which reads exactly like the play report and
      -- was this loop.
      -- TRANSITION_AT=n: start Platinum's into-battle cut-in on tick n over
      -- the real field (TRANSITION_CLASS for a trainer, else a wild one of
      -- TRANSITION_SPECIES/TRANSITION_LEVEL), with nothing pushed after it.
      if tonumber(os.getenv("TRANSITION_AT") or "") == i then
        local class = tonumber(os.getenv("TRANSITION_CLASS") or "")
        local fake = { kind = class and "trainer" or "wild",
                       trainer = class and { class = class, name = os.getenv("NAME") or "ROARK" } or nil,
                       enemy = { mon = { species = tonumber(os.getenv("TRANSITION_SPECIES") or "396"),
                                         level = tonumber(os.getenv("TRANSITION_LEVEL") or "3") } } }
        local okT, errT = pcall(OW.pushBattleTransition, OW, fake, nil, function() end)
        print(("[transition] %s"):format(okT and "pushed" or tostring(errT)))
      end
      -- RADAR_AT=n: switch the Poke Radar on at tick n where the player
      -- stands, then put them on the first live patch (src/world/Gen4Radar.lua)
      if tonumber(os.getenv("RADAR_AT") or "") == i then
        Game.save.inventory = Game.save.inventory or {}
        Game.save.inventory[431] = 1
        Game.save.gen4RadarCharge = 50
        local why = OW:gen4UseRadar()
        local c = OW.gen4Radar
        print(("[radar] use -> %s; chain active=%s"):format(tostring(why), tostring(c and c.active)))
        for k, pt in ipairs((c and c.patches) or {}) do
          print(("[radar] patch %d at (%d,%d) active=%s continue=%s shake=%s"):format(k, pt.x, pt.y,
            tostring(pt.active), tostring(pt.continueChain), tostring(pt.shakeType)))
        end
        for _, pt in ipairs((c and c.patches) or {}) do
          if pt.active then
            OW.player.cellX, OW.player.cellY = pt.x, pt.y
            local ok, hit = pcall(OW.gen4RadarEncounter, OW,
              require("src.world.Encounter").forMap(Game.data, OW.map.def, OW.map.id, nil, Game.save))
            local top = Game.stack.states[#Game.stack.states]
            print(("[radar] stepped on (%d,%d): encounter=%s top=%s chain=%s species=%s"):format(pt.x, pt.y,
              tostring(ok and hit or hit), tostring(top and (top.kind or top.name or top.style)),
              tostring(OW.gen4Radar and OW.gen4Radar.count), tostring(OW.gen4Radar and OW.gen4Radar.species)))
            break
          end
        end
      end
      local okU, errU = pcall(Game.stack.update, Game.stack, 1 / 60)
      if not okU then print(("update raised on tick %d: %s"):format(i, tostring(errU))) break end
      -- WATCH ONE ACTOR BY SPRITE NAME.  The absence of a warning is not
      -- evidence that a movement ran; seeing the facing change is.
      local watch = os.getenv("WATCH")
      if watch and i % (tonumber(os.getenv("WATCH_EVERY") or "60")) == 0 then
        for _, e in ipairs(OW.entities or {}) do
          local d = e.def
          if d and (d.spriteName == watch or d.sprite == watch) then
            print(("t=%d %s facing=%s at (%s,%s) moving=%s"):format(
              i, watch, tostring(e.facing), tostring(e.cellX),
              tostring(e.cellY), tostring(e.moving)))
          end
        end
      end
      if screenName and i == 14 then
        local it = Data.items or {}
        local n, sample = 0, nil
        for k, v in pairs(it) do n = n + 1
          if sample == nil and type(v) == "table" then sample = {k, v} end end
        local byName = it["POTION"]
        print(("[items] ITEM_017=%s ITEM_17=%s item_17=%s"):format(
          type(it["ITEM_017"]), type(it["ITEM_17"]), type(it["item_17"])))
        local strKeys = 0
        for k in pairs(it) do if type(k) == "string" then strKeys = strKeys + 1 end end
        print(("[items] string-keyed entries: %d"):format(strKeys))
        local mc = (Data.constants or {}).martCommon
        if type(mc) == "table" then
          local r = mc[1]
          local ks = {}
          if type(r) == "table" then for k, v in pairs(r) do ks[#ks+1] = k .. "=" .. tostring(v) end end
          table.sort(ks)
          print("[mart] row1: " .. table.concat(ks, " "))
        end
        local e0 = it[0] or it[1]
        if type(e0) == "table" then
          local ks = {}
          for k in pairs(e0) do ks[#ks+1] = tostring(k) end
          table.sort(ks)
          print("[items] numeric entry fields: " .. table.concat(ks, ","))
          print("[items] its name=" .. tostring(e0.name) .. " desc=" .. tostring(e0.description and "yes" or "no"))
        end
        print(("[items] count=%d sampleKey=%s(%s) POTION=%s"):format(
          n, tostring(sample and sample[1]), type(sample and sample[1]),
          type(byName)))
        if type(byName) == "table" then
          local keys = {}
          for k in pairs(byName) do keys[#keys+1] = tostring(k) end
          table.sort(keys)
          print("[items] POTION fields: " .. table.concat(keys, ","))
        end
      end
      if screenName and i == 15 then
        local top = Game.stack.states[#Game.stack.states]
        if top and top.selected then
          local r = top:selected()
          print(("[bag] selected=%s desc=%s"):format(
            tostring(r and (r.name or r.id)),
            r and tostring(r.description and r.description:sub(1,40)) or "-"))
        end
      end
      if screenName and i % 20 == 0 then
        local top = Game.stack.states[#Game.stack.states]
        print(("t=%d top=%s page=%s index=%s species=%s"):format(i,
          tostring(top and top.name or (top == OW and "overworld" or "screen")),
          tostring(top and top.page), tostring(top and top.index),
          tostring(top and top.species and top:species())))
      end
      if os.getenv("TRACE") then
        local f = Follower.current(OW)
        local p = OW.player
        print(("t=%d player=(%s,%s)%s | follower=%s"):format(
          i, tostring(p and p.cellX), tostring(p and p.cellY),
          tostring(p and p.facing),
          f and ("(%s,%s) spawned=%s hidden=%s sprite=%s"):format(
                 tostring(f.cellX), tostring(f.cellY),
                 tostring(f.gen4FollowerSpawned), tostring(f.hidden),
                 tostring(f.def and (f.def.spriteName or f.def.sprite)))
            or "none"))
      end
    end

    -- DRAWING GOES THROUGH `Game:draw`, NOT `OverworldState:draw`.
    --
    -- The first version of this called the state's own `draw` into a canvas,
    -- the way the battle harness does, and got a BLACK FRAME -- not even the
    -- player.  `Game:_draw` is what sizes the UI surface, picks the visible
    -- base, runs the world pass and presents it; the state's `draw` is one
    -- step inside that and paints into a surface nobody had set up.  A
    -- harness that skips it is not testing what the player sees.
    print("party after:  " .. partyHp())
    -- DUMPNPCS=1: every object on the map and whether it stands there
    if os.getenv("GIFT") then
      local MG = require("src.pokemon.Gen4MysteryGift")
      local st = MG.state(Game.save)
      print(("[gift] after: waiting %d, Member Card %s, Oak's Letter %s, Azure Flute %s, var 4043=%s 4044=%s 4045=%s"):format(
        #st.waiting, tostring((Game.save.inventory or {})[454]), tostring((Game.save.inventory or {})[452]),
        tostring((Game.save.inventory or {})[455]), tostring((Game.save.gen4Vars or {})[0x4043]),
        tostring((Game.save.gen4Vars or {})[0x4044]), tostring((Game.save.gen4Vars or {})[0x4045])))
    end
    if os.getenv("DUMPNPCS") then
      for _, n in ipairs(OW.npcs or {}) do
        local d = n.def or {}
        print(("[npc] local %s %s at (%s,%s) hidden=%s"):format(tostring(d.localId or n.localId),
          tostring(d.spriteName or d.sprite), tostring(n.cellX), tostring(n.cellY), tostring(n.hidden)))
      end
    end
    _G.__owHarness = { game = Game, ow = OW, tag = TAG }
  end, debug.traceback)
  if not ok then print("FAILED:\n" .. tostring(err)) end
end

-- One real frame, captured after it is presented.
local shot = false
function love.draw()
  local h = _G.__owHarness
  if not h then love.event.quit() return end
  local okD, errD = pcall(h.game.draw, h.game)
  if not okD then print("draw raised: " .. tostring(errD)) end
  if not shot then
    shot = true
    love.graphics.captureScreenshot(function(imageData)
      imageData:encode("png", "ow_" .. h.tag .. ".png")
      print("wrote ow_" .. h.tag .. ".png")
      love.event.quit()
    end)
  end
end
