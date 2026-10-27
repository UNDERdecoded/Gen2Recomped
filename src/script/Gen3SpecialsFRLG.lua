-- FIRERED'S OWN SPECIALS.
--
-- The importer rewrites every FireRed `special n` to the Emerald index of the
-- same-named function (manifest specialRemap), so everything the two games
-- share already runs on Gen3Commands.SPECIALS.  A FireRed-only special has no
-- Emerald twin and arrives as 0x1000 + its FireRed index (pokefirered
-- data/specials.inc); this file is where those are served, each written from
-- the pokefirered function of the same name.  Emerald handlers that do the
-- same job under another name are aliased rather than rewritten.

local Commands = require("src.script.Commands")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

return function(Gen3Commands)
  local S = Gen3Commands.SPECIALS
  local getVar, setVar = Gen3Commands.getVar, Gen3Commands.setVar
  local VAR_RESULT = Gen3Commands.VAR_RESULT
  local BASE = 0x1000
  local function def(index, fn) S[BASE + index] = fn end
  local function alias(index, emerald)
    if S[emerald] then S[BASE + index] = S[emerald] end
  end
  local function var(ctx, id) return math.floor(tonumber(getVar(ctx.save, id)) or 0) end
  local function texts(ctx)
    local c = ctx.game and ctx.game.data and ctx.game.data.constants
    return (c and c.gen3FRLGSpecialTexts) or {}
  end
  local function flag(ctx, n)
    return ((ctx.save and ctx.save.flags) or {})[Gen3Commands.flagKey(n)] == true
  end
  local function setFlag(ctx, n)
    ctx.save.flags = ctx.save.flags or {}
    ctx.save.flags[Gen3Commands.flagKey(n)] = true
  end
  local function mapId(ctx)
    local ow = ctx.overworld
    return ow and ow.map and ow.map.id
  end

  -- ---- Emerald twins under FireRed names ---------------------------------
  alias(148, 151)   -- BufferBigGuyOrBigGirlString  = GetPlayerBigGuyGirlString
  alias(214, 217)   -- AnimatePcTurnOn              = DoPCTurnOnEffect
  alias(304, 306)   -- IsThereRoomInAnyBoxForMorePokemon
  alias(327, 329)   -- GetPartyMonSpecies           = ScriptGetPartyMonSpecies
  alias(336, 338)   -- IsMonOTNameNotPlayers        = MonOTNameNotPlayer
  alias(286, 288)   -- GetRandomSlotMachineId       = GetSlotMachineId
  alias(220, 223)   -- SelectMoveDeleterMove        = MoveDeleterChooseMoveToForget
  alias(191, 194)   -- GetDaycareCost               = GetDaycareCostAndPrepareString
  alias(163, 166)   -- Script_IsFanClubMemberFanOfPlayer
  alias(164, 167)   -- Script_GetNumFansOfPlayerInTrainerFanClub
  alias(165, 168)   -- Script_BufferFanClubTrainerName
  alias(310, 312)   -- ShakeScreen                  = ShakeCamera

  -- ---- things with no visible effect in this port ------------------------
  -- The quest log (the "previously on..." replay), the help system, the
  -- fame checker's flavour flags and the message-box walkaway are FireRed
  -- systems the port does not have; their specials answer "not replaying"
  -- and change nothing.
  for _, i in ipairs({ 361, 368, 369, 371, 372, 381, 382, 383, 388, 392, 400,
                       408, 409, 417, 196, 359, 360 }) do
    def(i, function() end)
  end
  def(391, function() return 0 end)            -- GetQuestLogState: not replaying

  -- ---- gym and field puzzles -----------------------------------------------
  -- SetVermilionTrashCans: the first switch in 0x8004, its neighbour in 0x8005
  def(347, function(ctx)
    local first = math.random(0, 14) + 1
    local second = first
    local r = function(n) return math.random(0, n - 1) end
    local steps = {
      [1] = { 1, 5 }, [2] = { 1, 5, -1 }, [3] = { 1, 5, -1 }, [4] = { 1, 5, -1 },
      [5] = { 5, -1 }, [6] = { -5, 1, 5 }, [7] = { -5, 1, 5, -1 }, [8] = { -5, 1, 5, -1 },
      [9] = { -5, 1, 5, -1 }, [10] = { -5, 5, -1 }, [11] = { -5, 1 }, [12] = { -5, 1, -1 },
      [13] = { -5, 1, -1 }, [14] = { -5, 1, -1 }, [15] = { -5, -1 },
    }
    local choices = steps[first]
    second = first + choices[r(#choices) + 1]
    if second > 15 then
      if first % 5 == 1 then second = first + 1
      elseif first % 5 == 0 then second = first - 1
      else second = first + 1 end
    end
    setVar(ctx.save, 0x8004, first)
    setVar(ctx.save, 0x8005, second)
  end)

  -- ForcePlayerOntoBike (Cycling Road) and ForcePlayerToStartSurfing (Seafoam)
  def(343, function(ctx)
    local save = ctx.save
    if not save.onBike then
      save.onBike, save.bikeKind = true, "mach"
    end
  end)
  def(353, function(ctx)
    local ow = ctx.overworld
    local p = ow and ow.player
    if not p then return end
    p.surfing = true
    if ow.map and ow.map.cellElevation then
      p.elevation = ow.map:cellElevation(p.cellX, p.cellY) or p.elevation
    end
  end)
  -- SeafoamIslandsB4F_CurrentDumpsPlayerOnLand: the current carries you off
  -- the water facing north
  def(348, function(ctx)
    local ow = ctx.overworld
    local p = ow and ow.player
    if not p then return end
    p.surfing = false
    p.facing = "up"
  end)

  -- ---- battles -------------------------------------------------------------
  def(312, function(ctx) Commands.g3_wild_battle(ctx) end)   -- StartLegendaryBattle
  def(236, function(ctx) Commands.g3_wild_battle(ctx) end)   -- StartSpecialBattle
  -- StartMarowakBattle: the ghost at Pokemon Tower 6F.  With the SILPH SCOPE it
  -- is MAROWAK, level 30, and can be fought; without it the cartridge runs an
  -- unwinnable GHOST battle, which this port answers as a run.
  def(342, function(ctx)
    local bag = (ctx.save or {}).inventory or {}
    if (bag.SILPH_SCOPE or 0) > 0 then
      Commands.g3_set_wild(ctx, 105, 30, 0)
      Commands.g3_wild_battle(ctx)
    else
      ctx.lastBattleResult = "run"
    end
  end)

  -- ---- elevators (Silph Co., Rocket Hideout, Celadon, Trainer Tower) -------
  local SILPH = { MAP_G01_N47 = 4, MAP_G01_N48 = 5, MAP_G01_N49 = 6, MAP_G01_N50 = 7,
                  MAP_G01_N51 = 8, MAP_G01_N52 = 9, MAP_G01_N53 = 10, MAP_G01_N54 = 11,
                  MAP_G01_N55 = 12, MAP_G01_N56 = 13, MAP_G01_N57 = 14,
                  MAP_G01_N42 = 3, MAP_G01_N43 = 2, MAP_G01_N45 = 0,
                  MAP_G10_N00 = 4, MAP_G10_N01 = 5, MAP_G10_N02 = 6, MAP_G10_N03 = 7,
                  MAP_G10_N04 = 8, MAP_G02_N10 = 3 }
  local CURSOR = { MAP_G01_N57 = { 0, 0 }, MAP_G01_N56 = { 0, 1 }, MAP_G01_N55 = { 0, 2 },
                   MAP_G01_N54 = { 0, 3 }, MAP_G01_N53 = { 0, 4 }, MAP_G01_N52 = { 1, 4 },
                   MAP_G01_N51 = { 2, 4 }, MAP_G01_N50 = { 3, 4 }, MAP_G01_N49 = { 4, 4 },
                   MAP_G01_N48 = { 5, 4 }, MAP_G01_N47 = { 5, 5 },
                   MAP_G01_N42 = { 0, 0 }, MAP_G01_N43 = { 0, 1 }, MAP_G01_N45 = { 0, 2 },
                   MAP_G10_N04 = { 0, 0 }, MAP_G10_N03 = { 0, 1 }, MAP_G10_N02 = { 0, 2 },
                   MAP_G10_N01 = { 0, 3 }, MAP_G10_N00 = { 0, 4 }, MAP_G02_N10 = { 0, 1 } }
  local function dynamicMap(ctx)
    local warp = (ctx.save or {}).gen3DynamicWarp
    return warp and warp.map
  end
  def(216, function(ctx)                        -- GetElevatorFloor -> VAR_ELEVATOR_FLOOR
    local m = dynamicMap(ctx)
    local floor = (m and SILPH[m]) or 4
    if m and m:match("^MAP_G02_N0[1-9]$") then floor = 15 end
    setVar(ctx.save, 0x403A, floor)
  end)
  def(440, function(ctx)                        -- InitElevatorFloorSelectMenuPos
    local c = CURSOR[dynamicMap(ctx) or ""] or { 0, 0 }
    ctx.save.frlgElevatorScroll = c[1]
    ctx.save.frlgElevatorCursor = c[2]
    return c[2]
  end)
  def(306, function(ctx)                        -- DrawElevatorCurrentFloorWindow
    local t = texts(ctx)
    local ow = ctx.overworld
    if not ow then return end
    ow.frlgFloorWindow = { nowOn = t.nowOn or Strings("Now on:"),
                           floor = (t.floors or {})[var(ctx, 0x8005) + 1] or "" }
  end)
  def(352, function(ctx)                        -- CloseElevatorCurrentFloorWindow
    if ctx.overworld then ctx.overworld.frlgFloorWindow = nil end
  end)
  -- AnimateElevator: the car shakes a pixel every third frame for a count set
  -- by how many floors it travels (sElevatorAnimationDuration), then dings
  local ELEVATOR_SHAKES = { 8, 16, 24, 32, 38, 46, 53, 56, 57 }
  def(273, function(ctx)
    local ow, runner = ctx.overworld, ctx.runner
    if not (ow and runner) then return end
    local from, to = var(ctx, 0x8005), var(ctx, 0x8006)
    local n = math.min(8, math.abs(from - to))
    local done = false
    -- AnimateElevatorWindowView: the 3x3 window at (1..3, 0..2) cycles its
    -- three frames every six frames, upward or downward, for 3n+3 steps
    local goingDown = from > to
    local ROWS = { { 0x2E8, 0x2E9, 0x2EA }, { 0x2F0, 0x2F1, 0x2F2 }, { 0x2F8, 0x2F9, 0x2FA } }
    local win = { tick = 0, step = 0, steps = (n + 1) * 3 }
    local function windowFrame()
      if win.step >= win.steps then return end
      win.tick = win.tick + 1
      if win.tick < 6 then return end
      win.tick = 0
      win.step = win.step + 1
      local f = win.step % 3
      if goingDown and f ~= 0 then f = 3 - f end
      for i = 0, 2 do
        for j = 0, 2 do
          pcall(Commands.g3_set_metatile, ctx, j + 1, i, ROWS[i + 1][f + 1], 1)
        end
      end
    end
    ow.gen3Elevator = { shakes = ELEVATOR_SHAKES[n + 1], frames = 0, period = 3, amplitude = 1,
                        onFrame = windowFrame,
                        resume = function()
                          if done then return end
                          done = true
                          ow.gen3Elevator = nil
                          ow.bgShakeY = 0
                          pcall(Commands.play_sound, ctx, "SE_DING_DONG")
                          runner:resume()
                        end }
    runner:yield()
  end)

  -- ListMenu (0x8004 = which list) and ReturnToListMenu.  The answer is the
  -- row in VAR_RESULT, 127 for backing out; the badge list stays open
  -- across the script's reply and is re-asked by ReturnToListMenu.
  local function listLabels(ctx, which)
    local t = texts(ctx)
    local exit = t.exit or Strings("EXIT")
    local f = t.floors or {}
    if which == 0 then
      local rows = {}
      for i = 1, 8 do rows[i] = (t.badges or {})[i] or ("BADGE %d"):format(i) end
      rows[9] = exit
      return rows, 4
    elseif which == 1 then
      return { f[15], f[14], f[13], f[12], f[11], f[10], f[9], f[8], f[7], f[6], f[5], exit }, 7
    elseif which == 2 then
      return { f[4], f[3], f[1], exit }, 4
    elseif which == 3 then
      return { f[9], f[8], f[7], f[6], f[5], exit }, 4
    elseif which == 6 then
      return { f[16], f[4], exit }, 3
    end
  end
  local function runList(ctx, which)
    local rows, visible = listLabels(ctx, which)
    if not rows then
      setVar(ctx.save, VAR_RESULT, 0x7F)
      return 0x7F
    end
    -- the elevators open on the floor you are on (sElevatorScroll + cursor)
    local start
    if which == 1 or which == 2 or which == 3 or which == 6 then
      start = (ctx.save.frlgElevatorScroll or 0) + (ctx.save.frlgElevatorCursor or 0) + 1
    end
    local picked = Gen3Commands.listPick(ctx, rows, nil, visible, start)
    local answer = picked and (picked - 1) or 0x7F
    setVar(ctx.save, VAR_RESULT, answer)
    return answer
  end
  def(344, function(ctx)
    local which = var(ctx, 0x8004)
    ctx.save.frlgLastList = which
    return runList(ctx, which)
  end)
  def(345, function(ctx)
    local which = ctx.save.frlgLastList
    if which then return runList(ctx, which) end
  end)

  -- ---- the Seagallop ferry and the Sevii Islands ---------------------------
  local MORE, CANCEL = 254, 127
  def(425, function(ctx)                        -- GetSeagallopNumber
    local o, d = var(ctx, 0x8004), var(ctx, 0x8006)
    local function either(x) return o == x or d == x end
    if either(8) then return 1 end
    if either(0) then return 7 end
    if either(9) then return 10 end
    if either(10) then return 12 end
    local function inSet(x, a, b, c) return x == a or x == b or x == c end
    if inSet(o, 1, 2, 3) and inSet(d, 1, 2, 3) then return 2 end
    if inSet(o, 4, 5) and inSet(d, 4, 5) then return 3 end
    if inSet(o, 6, 7) and inSet(d, 6, 7) then return 5 end
    return 6
  end)
  def(423, function(ctx)                        -- DrawSeagallopDestinationMenu
    local t = texts(ctx)
    local names = t.seagallop or {}
    local origin, page = var(ctx, 0x8004), var(ctx, 0x8005)
    local dest, count
    if page == 1 then
      dest, count = (origin < 5) and 5 or 4, 5
    else
      dest, count = 0, 6
    end
    local rows, i = {}, 0
    while i < count - 2 do
      if dest ~= origin then
        rows[#rows + 1] = names[dest + 1] or ""
        i = i + 1
      end
      dest = dest + 1
      if dest == 8 then dest = 0 end
    end
    rows[#rows + 1] = t.other or Strings("OTHER")
    rows[#rows + 1] = t.exit or Strings("EXIT")
    local picked = Gen3Commands.listPick(ctx, rows, nil, #rows)
    setVar(ctx.save, VAR_RESULT, picked and (picked - 1) or CANCEL)
  end)
  def(424, function(ctx)                        -- GetSelectedSeagallopDestination
    local result, origin = var(ctx, VAR_RESULT), var(ctx, 0x8004)
    if result == CANCEL then return CANCEL end
    if var(ctx, 0x8005) == 1 then
      if result == 3 then return MORE end
      if result == 4 then return CANCEL end
      if result == 0 then return origin > 4 and 4 or 5 end
      if result == 1 then return origin > 5 and 5 or 6 end
      if result == 2 then return origin > 6 and 6 or 7 end
      return 0
    end
    if result == 4 then return MORE end
    if result == 5 then return CANCEL end
    if result >= origin then return result + 1 end
    return result
  end)
  local HARBORS = {
    [0] = { "MAP_G03_N05", 0x17, 0x20 }, { "MAP_G32_N04", 8, 5 }, { "MAP_G33_N04", 8, 5 },
    { "MAP_G38_N00", 8, 5 }, { "MAP_G35_N05", 8, 5 }, { "MAP_G36_N02", 8, 5 },
    { "MAP_G37_N02", 8, 5 }, { "MAP_G31_N06", 8, 5 }, { "MAP_G03_N08", 0x15, 7 },
    { "MAP_G02_N59", 8, 5 }, { "MAP_G02_N58", 8, 5 },
  }
  -- push a scene and park the script until it leaves (the cartridge's
  -- SetMainCallback2 + waitstate)
  local function runScene(ctx, make)
    local game, runner = ctx.game, ctx.runner
    if not (game and runner) then return false end
    local resumed = false
    local scene = make(function()
      if resumed then return end
      resumed = true
      runner:resume()
    end)
    if not scene then return false end
    game.stack:push(scene)
    runner:yield()
    return true
  end
  Gen3Commands.frlgRunScene = runScene

  def(379, function(ctx)                        -- DoSeagallopFerryScene
    local dest = HARBORS[var(ctx, 0x8006)] or HARBORS[0]
    local Scenes = require("src.ui.Gen3FRLGScenes")
    runScene(ctx, function(onDone)
      return Scenes.Seagallop.new(ctx.game, { origin = var(ctx, 0x8004), dest = var(ctx, 0x8006),
                                              onDone = onDone })
    end)
    Commands.warp(ctx, dest[1], dest[2], dest[3])
  end)
  def(429, function(ctx)                        -- IsPlayerLeftOfVermilionSailor
    local p = ctx.overworld and ctx.overworld.player
    return (mapId(ctx) == "MAP_G03_N05" and p and p.cellX < 24) and 1 or 0
  end)
  -- DoSSAnneDepartureCutscene: slide the visual sprite, as ss_anne.c does
  -- with x2. Its map object stays put until the script removes it.  The wake
  -- and smoke are OAM-only companions to that visual position: one wake is
  -- created after the 50-frame horn pause, and smoke puffs spawn every 70 run
  -- frames until the funnel is offscreen.
  def(401, function(ctx)
    pcall(Commands.play_sound, ctx, "SE_SS_ANNE_HORN")
    local ow, runner = ctx.overworld, ctx.runner
    if not (ow and runner) then return end
    local boat
    for _, e in ipairs(ow.entities or {}) do
      if e.def and e.def.localId == 1 and e ~= ow.player then boat = e break end
    end
    if not boat then return end
    local wait, moved, tail = 50, 0, nil
    boat.shiftPx = 0
    ow.ssAnneDepartureFx = nil
    local fx
    local function boatScreenX()
      -- Preserve the same port-space centre used by the existing offscreen
      -- check.  The player does not move during this cutscene, so this is the
      -- GBA object's screen x (including the ship's visual-only x2 shift).
      return boat.px + (boat.shiftPx or 0) + 8 - (ow.player.px - 112)
    end
    local function makeWake()
      fx = { boat = boat, wakeAge = 1, smoke = {} }
      ow.ssAnneDepartureFx = fx
    end
    local function makeSmoke()
      if not fx then return end
      local x = boatScreenX() + 49
      if x >= -32 then
        local camX = (ow.camera and ow.camera.x) or (ow.player.px - 112)
        fx.smoke[#fx.smoke + 1] = {
          x = boat.px + (boat.shiftPx or 0) + 8 - camX + 49,
          age = 0,
        }
      end
    end
    local function advanceEffects()
      if not fx then return end
      if fx.wakeAge < 132 then fx.wakeAge = fx.wakeAge + 1 end
      for i = #fx.smoke, 1, -1 do
        local puff = fx.smoke[i]
        puff.age = puff.age + 1
        if puff.age >= 80 then table.remove(fx.smoke, i) end
      end
    end
    -- A runner-owned poll also tells the stuck-script watchdog this long
    -- cutscene has work pending; a detached field task was killed at 720f.
    runner.waitingCheck = function()
      if wait > 0 then
        wait = wait - 1
        if wait == 0 then makeWake() end
        return false
      end
      if tail then
        advanceEffects()
        tail = tail - 1
        if tail <= 0 then
          ow.ssAnneDepartureFx = nil
          return true
        end
        return false
      end
      moved = moved + 1
      if moved % 70 == 0 then makeSmoke() end
      local screenX = boatScreenX()
      if screenX < -120 or moved > 5 * 600 then
        pcall(Commands.play_sound, ctx, "SE_SS_ANNE_HORN")
        tail = 40
      else
        boat.shiftPx = -math.floor(moved / 5)
      end
      advanceEffects()
      return false
    end
    runner:yield()
  end)

  -- ---- Pokedex, starter, party --------------------------------------------
  def(354, function(ctx)                        -- GetStarterSpecies
    local starters = { [0] = 1, 7, 4 }             -- BULBASAUR, SQUIRTLE, CHARMANDER
    return starters[var(ctx, 0x4031)] or 1
  end)
  def(403, function(ctx) return ctx.save.nationalDex and 1 or 0 end)  -- IsNationalPokedexEnabled
  local function kantoCounts(ctx)
    local dex = (ctx.save or {}).pokedex or {}
    local mons = (ctx.game and ctx.game.data and ctx.game.data.pokemon) or {}
    local seen, owned = 0, 0
    for id in pairs(dex.seen or {}) do
      local n = tonumber((mons[id] or {}).dex)
      if n and n >= 1 and n <= 151 then seen = seen + 1 end
    end
    for id in pairs(dex.owned or {}) do
      local n = tonumber((mons[id] or {}).dex)
      if n and n >= 1 and n <= 151 then owned = owned + 1 end
    end
    return seen, owned
  end
  def(212, function(ctx)                        -- GetPokedexCount
    local seen, owned
    if var(ctx, 0x8004) == 0 then
      seen, owned = kantoCounts(ctx)
    else
      seen, owned = Gen3Commands.dexCounts(ctx, true)
    end
    setVar(ctx.save, 0x8005, seen)
    setVar(ctx.save, 0x8006, owned)
    return ctx.save.nationalDex and 1 or 0
  end)
  def(213, function(ctx)                        -- GetProfOaksRatingMessage
    local count = var(ctx, 0x8004)
    local lines = texts(ctx).rating or {}
    setVar(ctx.save, VAR_RESULT, 0)
    local index = math.min(15, math.floor(count / 10) + 1)
    if count >= 150 then
      index = 16
      setVar(ctx.save, VAR_RESULT, 1)
    end
    local line = lines[index]
    if line then Commands.show_text(ctx, line) end
  end)
  def(335, function(ctx)                        -- HasAllKantoMons
    local _, owned = kantoCounts(ctx)
    return owned >= 150 and 1 or 0
  end)
  def(432, function(ctx)                        -- HasAllMons
    local _, owned = Gen3Commands.dexCounts(ctx, true)
    return owned >= 386 and 1 or 0
  end)
  def(355, function(ctx)                        -- SetSeenMon (0x8004 = species)
    local data = ctx.game and ctx.game.data
    local id = Gen3Commands.speciesId(data, var(ctx, 0x8004))
    if not id then return end
    ctx.save.pokedex = ctx.save.pokedex or {}
    ctx.save.pokedex.seen = ctx.save.pokedex.seen or {}
    ctx.save.pokedex.seen[id] = true
  end)
  local function party(ctx) return (ctx.save and ctx.save.party) or {} end
  def(380, function(ctx)                        -- DoesPlayerPartyContainSpecies
    local data = ctx.game and ctx.game.data
    local want = Gen3Commands.speciesId(data, var(ctx, 0x8004))
    for _, mon in ipairs(party(ctx)) do
      if mon.species == want then return 1 end
    end
    return 0
  end)
  def(230, function(ctx)                        -- GetLeadMonFriendship
    local lead = Gen3Commands.leadMon and Gen3Commands.leadMon(ctx)
    local f = tonumber(lead and (lead.friendship or lead.happiness)) or 0
    if f == 255 then return 6 elseif f >= 200 then return 5 elseif f >= 150 then return 4
    elseif f >= 100 then return 3 elseif f >= 50 then return 2 elseif f > 0 then return 1 end
    return 0
  end)

  -- ---- the league and after -----------------------------------------------
  -- EnterHallOfFame: FireRed's GameClear.  FLAG_SYS_GAME_CLEAR is 0x82C here
  -- (Emerald's is 0x864), then the same ceremony and walk home.
  def(272, function(ctx)
    local data = ctx.game and ctx.game.data
    if data then
      data.constants = data.constants or {}
      data.constants.gen3GameClear = data.constants.gen3GameClear or { flag = 0x82C }
    end
    if S[275] then return S[275](ctx) end
    setFlag(ctx, 0x82C)
  end)
  def(410, function(ctx)                        -- SetPostgameFlags
    ctx.save.frlgChampionSaveWarp = true
  end)
  def(421, function() end)                      -- DoCredits (run by the ceremony)
  def(93, function(ctx) return 0 end)           -- Field_AskSaveTheGame

  local function buffer(ctx, n, text)
    local game = ctx.game
    if not game then return end
    game.stringBuffers = game.stringBuffers or {}
    game.stringBuffers[n] = text
  end
  local function data_(ctx) return ctx.game and ctx.game.data end
  local function nameOf(ctx, mon)
    local d = data_(ctx)
    local def = d and d.pokemon and d.pokemon[mon.species]
    return mon.nickname or (def and def.name) or tostring(mon.species)
  end
  local function clearFlag(ctx, n)
    if ctx.save.flags then ctx.save.flags[Gen3Commands.flagKey(n)] = nil end
  end

  -- ---- links, wireless, e-Reader: nothing to connect to --------------------
  -- The cable club and the wireless club answer "the link failed" rather than
  -- walking the player into a colosseum with nobody in it.
  local LINKUP_FAILED = 5
  for _, i in ipairs({ 28, 29 }) do          -- TryBattleLinkup / TryTradeLinkup (Emerald slots)
    if not S[i] then
      S[i] = function(ctx) setVar(ctx.save, VAR_RESULT, LINKUP_FAILED) return LINKUP_FAILED end
    end
  end
  def(32, function() end)                    -- EnterColosseumPlayerSpot
  def(33, function() end)                    -- EnterTradeSeat
  def(248, function() end)                   -- ReducePlayerPartyToThree (link battles)
  def(235, function() end)                   -- BufferEReaderTrainerGreeting
  def(96, function() end)                    -- ShowEasyChatMessage (link record corner)
  for _, i in ipairs({ 249, 324, 287, 418, 420, 421, 422, 423, 424, 429, 431, 511 }) do
    if not S[i] then S[i] = function() return 0 end end
  end
  -- LoadPlayerBag (Emerald 333) restores the bag after a link battle; there
  -- is never one to restore from.  SetUnlockedPokedexFlags (496) is GameCube
  -- link bookkeeping.
  if not S[333] then S[333] = function() end end
  if not S[496] then S[496] = function() end end

  -- SetHiddenItemFlag (Emerald 153): every hidden item in Kanto is a script
  -- `setvar 0x8004, FLAG_HIDDEN_ITEM_...; special SetHiddenItemFlag`
  if not S[153] then
    S[153] = function(ctx) setFlag(ctx, var(ctx, 0x8004)) end
  end

  -- ---- purely visual, nothing waits on them --------------------------------
  def(434, function() end)                   -- BrailleCursorToggle
  -- Bill's SEA COTTAGE teleporter (special_field_anim.c): the light blinks
  -- yellow/red and the door glows for 13 beats of 16 frames, then goes green;
  -- the cable ball runs four cells left, a cell every four frames
  local function fieldTask(ctx, fn)
    local ow = ctx.overworld
    if not ow then return end
    ow.fieldTasks = ow.fieldTasks or {}
    ow.fieldTasks[#ow.fieldTasks + 1] = fn
  end
  local function setTile(ctx, x, y, id)
    pcall(Commands.g3_set_metatile, ctx, x, y, id, 1)
  end
  def(437, function(ctx)                     -- AnimateTeleporterHousing
    local p = ctx.overworld and ctx.overworld.player
    if not p then return end
    local tx = var(ctx, 0x8004) == 0 and p.cellX + 6 or p.cellX - 1
    local ty = p.cellY - 5
    local timer, state = 0, 0
    fieldTask(ctx, function()
      if timer == 0 then
        if state % 2 == 0 then
          setTile(ctx, tx, ty, 0x2B5) setTile(ctx, tx, ty + 2, 0x2B7)
        else
          setTile(ctx, tx, ty, 0x2B6) setTile(ctx, tx, ty + 2, 0x2B8)
        end
      end
      timer = timer + 1
      if timer ~= 16 then return false end
      timer, state = 0, state + 1
      if state ~= 13 then return false end
      setTile(ctx, tx, ty, 0x28A) setTile(ctx, tx, ty + 2, 0x296)
      return true
    end)
  end)
  def(439, function(ctx)                     -- AnimateTeleporterCable
    local p = ctx.overworld and ctx.overworld.player
    if not p then return end
    local tx, ty = p.cellX + 4, p.cellY - 5
    local timer, state = 0, 0
    fieldTask(ctx, function()
      if timer == 0 then
        if state ~= 0 then
          setTile(ctx, tx, ty, 0x285) setTile(ctx, tx, ty + 1, 0x2B4)
          if state == 4 then return true end
          tx = tx - 1
        end
        setTile(ctx, tx, ty, 0x2B9) setTile(ctx, tx, ty + 1, 0x2BA)
      end
      timer = timer + 1
      if timer == 4 then timer, state = 0, state + 1 end
      return false
    end)
  end)
  -- OpenMuseumFossilPic: 0x8004 KABUTOPS or AERODACTYL, the picture's window
  -- at tile (0x8005, 0x8006) -- the same framed box showmonpic uses
  def(395, function(ctx)
    local d = data_(ctx)
    local a = d and d.constants and d.constants.gen3FRLGArt
    local species = Gen3Commands.speciesId(d, var(ctx, 0x8004))
    local path = a and a.fossils and ((species == "KABUTOPS" and a.fossils.kabutops)
                                      or (species == "AERODACTYL" and a.fossils.aerodactyl))
    local ow, game = ctx.overworld, ctx.game
    if not (path and ow and game) then return 0 end
    if ow.pokepicBox then ow.pokepicBox:remove() end
    local tx, ty = var(ctx, 0x8005), var(ctx, 0x8006)
    local box = require("src.ui.PicBox").new(game, {
      path = path, trueColor = true, passive = true, overworld = ow,
      box = { x = tx, y = ty, w = 10, h = 10 }, picTiles = 8,
    })
    ow.pokepicBox = box
    game.stack:push(box)
    return 1
  end)
  def(396, function(ctx)                     -- CloseMuseumFossilPic
    local ow = ctx.overworld
    if ow and ow.pokepicBox then
      ow.pokepicBox:remove()
      ow.pokepicBox = nil
      return 1
    end
    return 0
  end)
  def(428, function() end)                   -- SetDeoxysTrianglePalette
  def(442, function(ctx) pcall(Commands.play_sound, ctx, "Wing_Attack") end)  -- LoopWingFlapSound
  def(264, function(ctx)                     -- ShowDiploma
    local Scenes = require("src.ui.Gen3FRLGScenes")
    local _, owned = Gen3Commands.dexCounts(ctx, true)
    Gen3Commands.frlgRunScene(ctx, function(onDone)
      return Scenes.Diploma.new(ctx.game, { national = (owned or 0) >= 386, onDone = onDone })
    end)
  end)
  def(167, function() end)                   -- Script_TryLoseFansFromPlayTime
  def(169, function() end)                   -- Script_UpdateTrainerFanClubGameClear
  -- StartOldManTutorialBattle (battle_setup.c): the Viridian old man's demo
  -- against a level 5 male WEEDLE, run by the engine's scripted catch demo
  -- with FireRed's OLD MAN back pic (field.playerPics.demoBack)
  def(157, function(ctx)
    local d = data_(ctx)
    local BattleState = require("src.battle.BattleState")
    local runner = ctx.runner
    if not (d and runner and d.pokemon and d.pokemon.WEEDLE) then
      ctx.lastBattleResult = "caught"
      return
    end
    local ok, battle = pcall(BattleState.newWild, ctx.game, "WEEDLE", 5)
    if not (ok and battle) then
      ctx.lastBattleResult = "caught"
      return
    end
    battle:makeOldManDemo()
    battle.onFinish = function(result)
      ctx.lastBattleResult = result or "caught"
      runner:resume()
    end
    if ctx.overworld and ctx.overworld.pushBattle then
      ctx.overworld:pushBattle(battle)
    else
      ctx.game.stack:push(battle)
    end
    runner:yield()
  end)

  -- ---- size records: HERACROSS (Two Island) and MAGIKARP (Pewter / Fuchsia)
  -- pokefirered pokemon_size_record.c: the record starts at 0, and sizes are
  -- centimetres shown in inches.
  local BIG_MON_SIZE = {
    { 290, 1, 0 }, { 300, 1, 10 }, { 400, 2, 110 }, { 500, 4, 310 }, { 600, 20, 710 },
    { 700, 50, 2710 }, { 800, 100, 7710 }, { 900, 150, 17710 }, { 1000, 150, 32710 },
    { 1100, 100, 47710 }, { 1200, 50, 57710 }, { 1300, 20, 62710 }, { 1400, 5, 64710 },
    { 1500, 2, 65210 }, { 1600, 1, 65410 }, { 1700, 1, 65510 },
  }
  local function monSize(ctx, species, hash)
    local d = data_(ctx)
    local def = d and d.pokemon and d.pokemon[species]
    local height = math.floor((tonumber(def and def.height) or 0) * 10 + 0.5)
    local index = 15
    for i = 1, 14 do
      if hash < BIG_MON_SIZE[i + 1][3] then index = i - 1 break end
    end
    local row = BIG_MON_SIZE[index + 1]
    local units = row[1] + math.floor((hash - row[3]) / row[2])
    return math.floor(height * units / 10)
  end
  local function formatSize(size)
    size = math.floor(size * 100 / 254)
    return ("%d.%d"):format(math.floor(size / 10), size % 10)
  end
  local function sizeInfo(ctx, speciesNum, recordVar)
    local species = Gen3Commands.speciesId(data_(ctx), speciesNum)
    buffer(ctx, 3, formatSize(monSize(ctx, species, var(ctx, recordVar))))
    local d = data_(ctx)
    local def = d and d.pokemon and d.pokemon[species]
    buffer(ctx, 1, (def and def.name) or tostring(species))
  end
  local function compareSize(ctx, speciesNum, recordVar)
    local slot = var(ctx, VAR_RESULT)
    if slot >= 6 then return 0 end
    local mon = party(ctx)[slot + 1]
    local species = Gen3Commands.speciesId(data_(ctx), speciesNum)
    if not mon or mon.isEgg or mon.species ~= species then return 1 end
    local hash = Gen3Commands.monSizeHash(mon)
    local mine = monSize(ctx, species, hash)
    local best = monSize(ctx, species, var(ctx, recordVar))
    buffer(ctx, 3, formatSize(best))
    buffer(ctx, 2, formatSize(mine))
    if mine == best then return 4 end
    if mine < best then return 2 end
    setVar(ctx.save, recordVar, hash)
    return 3
  end
  def(119, function(ctx) sizeInfo(ctx, 214, 0x403D) end)              -- GetHeracrossSizeRecordInfo
  def(120, function(ctx) return compareSize(ctx, 214, 0x403D) end)    -- CompareHeracrossSize
  def(121, function(ctx) sizeInfo(ctx, 129, 0x4040) end)              -- GetMagikarpSizeRecordInfo
  def(122, function(ctx) return compareSize(ctx, 129, 0x4040) end)    -- CompareMagikarpSize

  -- NameRaterWasNicknameChanged: the nickname before the naming screen is in
  -- STR_VAR_3 (put there by ChangePokemonNickname)
  def(123, function(ctx)
    local mon = party(ctx)[var(ctx, 0x8004) + 1]
    if not mon then return 0 end
    local now = nameOf(ctx, mon)
    buffer(ctx, 1, now)
    local before = ctx.game and ctx.game.stringBuffers and ctx.game.stringBuffers[3]
    return (before ~= nil and before == now) and 0 or 1
  end)

  -- ---- the Route 5 Pokemon day care: one pen, no eggs ----------------------
  local DayCare = require("src.pokemon.DayCare")
  local function route5Levels(ctx)
    local slot = DayCare.slot(ctx.save, DayCare.ROUTE5)
    if not (slot and slot.mon) then return 0 end
    local level = DayCare.pendingLevel(data_(ctx), slot)
    return math.max(0, (level or slot.mon.level or 0) - (slot.depositLevel or slot.mon.level or 0))
  end
  def(374, function(ctx)                     -- PutMonInRoute5Daycare
    local list = party(ctx)
    local slot = var(ctx, 0x8004) + 1
    local mon = list[slot]
    if not mon then return end
    table.remove(list, slot)
    DayCare.deposit(ctx.save, DayCare.ROUTE5, mon)
  end)
  def(375, function(ctx)                     -- GetCostToWithdrawRoute5DaycareMon
    local cost = 100 + 100 * route5Levels(ctx)
    setVar(ctx.save, 0x8005, cost)
    buffer(ctx, 2, tostring(cost))
  end)
  def(376, function(ctx)                     -- IsThereMonInRoute5Daycare
    return DayCare.mon(ctx.save, DayCare.ROUTE5) and 1 or 0
  end)
  def(377, function(ctx)                     -- GetNumLevelsGainedForRoute5DaycareMon
    local mon = DayCare.mon(ctx.save, DayCare.ROUTE5)
    local n = route5Levels(ctx)
    if mon then buffer(ctx, 1, nameOf(ctx, mon)) end
    buffer(ctx, 2, tostring(n))
    return n
  end)
  def(378, function(ctx)                     -- TakePokemonFromRoute5Daycare
    local d = data_(ctx)
    local slot = DayCare.slot(ctx.save, DayCare.ROUTE5)
    local mon = slot and slot.mon
    if not mon then return 0 end
    local startLevel = slot.depositLevel or mon.level or 1
    local newLevel, exp = DayCare.pendingLevel(d, slot)
    DayCare.withdraw(ctx.save, DayCare.ROUTE5)
    local def = d and d.pokemon and d.pokemon[mon.species]
    if newLevel and def then
      mon.exp, mon.level = exp, newLevel
      local okStats, Stats = pcall(require, "src.pokemon.Stats")
      if okStats and Stats.calc then
        mon.stats = Stats.calc(def, mon.level, mon.ivs or mon.dvs, mon.statExp, mon.evs, mon.nature)
        if mon.stats and mon.stats.hp then mon.hp = math.min(mon.hp or mon.stats.hp, mon.stats.hp) end
      end
      local okP, Pokemon = pcall(require, "src.pokemon.Pokemon")
      if okP and Pokemon.learnMovesFromDayCare then
        pcall(Pokemon.learnMovesFromDayCare, d, mon, def, startLevel, newLevel)
      end
    end
    local list = party(ctx)
    list[#list + 1] = mon
    buffer(ctx, 1, nameOf(ctx, mon))
    local order = d and d.constants and d.constants.speciesOrder or {}
    for n, id in ipairs(order) do if id == mon.species then return n end end
    return 0
  end)

  -- ---- Sevii Island odds and ends ------------------------------------------
  -- SetIcefallCaveCrackedIceMetatiles: the ice already stepped on (flags 1-9)
  -- comes back cracked when the room loads
  local ICEFALL_ICE = { { 8, 3 }, { 10, 5 }, { 15, 5 }, { 8, 9 }, { 9, 9 }, { 16, 9 },
                        { 8, 10 }, { 9, 10 }, { 8, 14 } }
  def(309, function(ctx)
    for i, c in ipairs(ICEFALL_ICE) do
      if flag(ctx, i) then pcall(Commands.g3_set_metatile, ctx, c[1], c[2], 0x35A, 0) end
    end
  end)

  -- SampleResortGorgeousMonAndReward (Five Island): a seen species and a prize
  local RESORT_REWARDS = { "BIG_PEARL", "PEARL", "STARDUST", "STAR_PIECE", "NUGGET", "RARE_CANDY" }
  local function itemNumber(ctx, id)
    local order = (data_(ctx) and data_(ctx).constants or {}).itemOrder or {}
    for n, name in pairs(order) do if name == id then return n end end
    return 0
  end
  def(349, function(ctx)
    local d = data_(ctx)
    local want = var(ctx, 0x4036)
    if want == 0 or want == 0xFFFF then
      local seen = {}
      local order = d and d.constants and d.constants.speciesOrder or {}
      local dex = (ctx.save.pokedex or {}).seen or {}
      for n, id in ipairs(order) do if dex[id] then seen[#seen + 1] = n end end
      want = #seen > 0 and seen[math.random(#seen)] or 1
      setVar(ctx.save, 0x4036, want)
      local reward = math.random(100) > 30 and "LUXURY_BALL"
                     or RESORT_REWARDS[math.random(#RESORT_REWARDS)]
      setVar(ctx.save, 0x403B, itemNumber(ctx, reward))
      setVar(ctx.save, 0x4035, 0)
    end
    local id = Gen3Commands.speciesId(d, want)
    local def = d and d.pokemon and d.pokemon[id]
    buffer(ctx, 1, (def and def.name) or tostring(id))
  end)

  -- DaisyMassageServices: the massage is a friendship event
  def(407, function(ctx)
    local mon = party(ctx)[var(ctx, 0x8004) + 1]
    if mon then
      local f = tonumber(mon.friendship or mon.happiness) or 0
      local gain = f < 100 and 3 or (f < 200 and 2 or 1)
      mon.friendship = math.min(255, f + gain)
      mon.happiness = mon.friendship
    end
    setVar(ctx.save, 0x4025, 0)
  end)

  -- UpdateLoreleiDollCollection: a doll comes out for every 25 Hall of Fame entries
  def(441, function(ctx)
    local n = tonumber((ctx.save.gameStats or {}).enteredHof or ctx.save.hallOfFameCount) or 0
    if n < 25 then return end
    local dolls = { 0x0A5, 0x0A6, 0x0A7, 0x0A8, 0x0A9, 0x0AA, 0x0AB, 0x0AC }
    for i, f in ipairs(dolls) do
      if i == 1 or n >= 25 * i then clearFlag(ctx, f) end
    end
  end)

  -- PlayerPartyContainsSpeciesWithPlayerID (0x8004 = species)
  def(436, function(ctx)
    local want = Gen3Commands.speciesId(data_(ctx), var(ctx, 0x8004))
    local myId = tonumber((ctx.save.player or {}).id or (ctx.save.player or {}).trainerId)
    for _, mon in ipairs(party(ctx)) do
      if mon.species == want and not mon.isEgg then
        local ot = tonumber(mon.otId or mon.ot and mon.ot.id)
        if ot == nil or myId == nil or ot == myId then return 1 end
      end
    end
    return 0
  end)

  -- Cape Brink: the ultimate moves for a fully friendly final starter
  local CAPE_BRINK = {
    { species = "VENUSAUR", move = "FRENZY_PLANT", tutor = 15, flag = 0x2DE },
    { species = "CHARIZARD", move = "BLAST_BURN", tutor = 16, flag = 0x2DF },
    { species = "BLASTOISE", move = "HYDRO_CANNON", tutor = 17, flag = 0x2E0 },
  }

  -- FireRed's ChooseMonForMoveTutor has a different contract from Emerald's
  -- same-named special.  In FireRed the party action owns the ENTIRE teach:
  -- compatibility, already-known check, insertion/replacement, and only then
  -- VAR_RESULT=TRUE.  The importer maps the name to shared special 477, whose
  -- Emerald implementation is intentionally only a picker (it returns a slot
  -- in 0x8008 for a later script step).  Route 4 therefore used to consume its
  -- one-shot tutor flag after any party pick while leaving the mon unchanged.
  --
  -- Keep Emerald's handler intact globally and replace it only while FireRed's
  -- specials are installed.
  local emeraldChooseMonForMoveTutor = S[477]
  local function capeBrinkTutor(tutor)
    for _, row in ipairs(CAPE_BRINK) do
      if row.tutor == tutor then return row end
    end
  end
  local function regularTutorMove(ctx, tutor)
    local moves = ((data_(ctx) or {}).constants or {}).tutorMoves or {}
    return moves[tutor + 1]
  end
  local function tutorCompatible(ctx, mon, tutor, move)
    if tutor >= 15 then
      local row = capeBrinkTutor(tutor)
      return row ~= nil and mon.species == row.species
    end
    local def = ((data_(ctx) or {}).pokemon or {})[mon.species]
    for _, id in ipairs((def and def.tutorMoves) or {}) do
      if id == move then return true end
    end
    return false
  end
  local function knowsMove(mon, move)
    for _, slot in ipairs(mon.moves or {}) do
      local id = type(slot) == "table" and slot.id or slot
      if id == move then return true end
    end
    return false
  end
  local function tutorLine(ctx, role, mon, move)
    local d = data_(ctx) or {}
    local lines = (d.constants or {}).gen3MoveLearn or {}
    local mdef = (d.moves or {})[move]
    local pdef = (d.pokemon or {})[mon.species]
    local monName = mon.nickname or (pdef and pdef.name) or tostring(mon.species)
    local moveName = (mdef and mdef.name) or tostring(move)
    local fallback = ({
      learned = Strings("{VAR1} learned\n{VAR2}!"),
      alreadyKnows = Strings("{VAR1} already knows\n{VAR2}."),
      notCompatible = Strings("{VAR1} and {VAR2}\nare not compatible."),
    })[role] or ""
    local text = lines[role] or fallback
    text = text:gsub("{VAR1}", function() return monName end)
               :gsub("{VAR2}", function() return moveName end)
    Commands.show_text(ctx, text)
  end

  S[477] = function(ctx)
    if not require("src.core.GameVersion").isFRLG() then
      return emeraldChooseMonForMoveTutor and emeraldChooseMonForMoveTutor(ctx)
    end
    local game, runner = ctx.game, ctx.runner
    local tutor = var(ctx, 0x8005)
    -- A malformed/new tutor id should retain the shared behavior rather than
    -- turning an unrelated script into a failed teach.
    if tutor < 0 or tutor > 17 then
      return emeraldChooseMonForMoveTutor and emeraldChooseMonForMoveTutor(ctx)
    end

    local move
    if tutor < 15 then
      move = regularTutorMove(ctx, tutor)
    else
      local row = capeBrinkTutor(tutor)
      move = row and row.move
    end
    setVar(ctx.save, VAR_RESULT, 0)
    if not (game and game.stack and runner and move) then return end

    local mon
    if tutor >= 15 then
      -- Cape Brink preselects the lead mon in 0x8007 and the cartridge skips
      -- the ordinary party picker for these three ultimate moves.
      mon = party(ctx)[var(ctx, 0x8007) + 1]
    else
      local okScreens, Screens = pcall(require, "src.ui.Screens")
      if not okScreens then return end
      local picked
      local pushed = pcall(Screens.push, game, "PartyMenu", {
        pickOnly = true,
        tmhm = { move = move, kind = "TUTOR" },
        onCancel = function() runner:resume() end,
        onSwitch = function(chosen)
          picked = chosen
          runner:resume()
        end,
      })
      if not pushed then return end
      runner:yield()
      mon = picked
    end

    if not mon or mon.isEgg or mon.egg or mon.species == "EGG" then return end
    if not tutorCompatible(ctx, mon, tutor, move) then
      tutorLine(ctx, "notCompatible", mon, move)
      return
    end
    if knowsMove(mon, move) then
      tutorLine(ctx, "alreadyKnows", mon, move)
      return
    end

    local d = data_(ctx) or {}
    local mdef = (d.moves or {})[move]
    mon.moves = mon.moves or {}
    if #mon.moves < (Gen3Commands.MAX_MON_MOVES or 4) then
      table.insert(mon.moves, { id = move, pp = (mdef and mdef.pp) or 5 })
      setVar(ctx.save, VAR_RESULT, 1)
      tutorLine(ctx, "learned", mon, move)
      return
    end

    local okScreens, Screens = pcall(require, "src.ui.Screens")
    if not okScreens then return end
    local learned = false
    local pushed = pcall(Screens.push, game, "MoveLearnMenu", mon, move,
                         function(ok)
                           learned = ok and true or false
                           runner:resume()
                         end)
    if not pushed then return end
    runner:yield()
    setVar(ctx.save, VAR_RESULT, learned and 1 or 0)
  end

  def(419, function(ctx)                     -- CapeBrinkGetMoveToTeachLeadPokemon
    local list = party(ctx)
    local lead = 0
    for i, mon in ipairs(list) do
      if not mon.isEgg and (mon.hp or 1) > 0 then lead = i - 1 break end
    end
    setVar(ctx.save, 0x8007, lead)
    local mon = list[lead + 1]
    if not mon or mon.isEgg then return 0 end
    local row
    for _, r in ipairs(CAPE_BRINK) do if mon.species == r.species then row = r end end
    if not row or (tonumber(mon.friendship or mon.happiness) or 0) ~= 255 then return 0 end
    local d = data_(ctx)
    local mdef = d and d.moves and d.moves[row.move]
    buffer(ctx, 2, (mdef and mdef.name) or row.move)
    setVar(ctx.save, 0x8005, row.tutor)
    if flag(ctx, row.flag) then return 0 end
    setVar(ctx.save, 0x8006, #(mon.moves or {}))
    return 1
  end)
  def(420, function(ctx)                     -- HasLearnedAllMovesFromCapeBrinkTutor
    local t = var(ctx, 0x8005)
    for _, r in ipairs(CAPE_BRINK) do if r.tutor == t then setFlag(ctx, r.flag) end end
    local all = true
    for _, r in ipairs(CAPE_BRINK) do if not flag(ctx, r.flag) then all = false end end
    return all and 1 or 0
  end)

  -- Birth Island: the triangle moves each time it is touched, within a step
  -- budget, and the tenth touch wakes DEOXYS (FLAG_SYS_DEOXYS_AWAKENED)
  local DEOXYS_COORDS = { [0] = { 15, 12 }, { 11, 14 }, { 15, 8 }, { 19, 14 }, { 12, 11 },
                          { 18, 11 }, { 15, 14 }, { 11, 14 }, { 19, 14 }, { 15, 15 }, { 15, 10 } }
  local DEOXYS_STEPS = { 4, 8, 8, 8, 4, 4, 4, 6, 3, 3 }
  local function moveRock(ctx, num)
    local c = DEOXYS_COORDS[num]
    pcall(Commands.play_sound, ctx, num == 0 and "Confuse_Ray" or "Deoxys_Move")
    pcall(Commands.g3_place, ctx, 1, c[1], c[2])
    pcall(Commands.g3_place_perm, ctx, 1, c[1], c[2])
  end
  def(427, function(ctx)
    local awake = 0x800 + 0x48
    if flag(ctx, awake) then setVar(ctx.save, VAR_RESULT, 3) return 3 end
    local n, steps = var(ctx, 0x403E), var(ctx, 0x4026)
    setVar(ctx.save, 0x4026, 0)
    if n ~= 0 and DEOXYS_STEPS[n] < steps then
      moveRock(ctx, 0)
      setVar(ctx.save, 0x403E, 0)
      setVar(ctx.save, VAR_RESULT, 0)
      return 0
    elseif n == 10 then
      setFlag(ctx, awake)
      setVar(ctx.save, VAR_RESULT, 2)
      return 2
    end
    n = n + 1
    moveRock(ctx, n)
    setVar(ctx.save, 0x403E, n)
    setVar(ctx.save, VAR_RESULT, 1)
    return 1
  end)

  -- berry powder (One Island's Berry Crush shop) lives in the save
  def(414, function(ctx)                     -- Script_HasEnoughBerryPowder
    return (tonumber(ctx.save.berryPowder) or 0) >= var(ctx, 0x8004) and 1 or 0
  end)
  def(415, function(ctx)                     -- Script_TakeBerryPowder
    local have, cost = tonumber(ctx.save.berryPowder) or 0, var(ctx, 0x8004)
    if have < cost then return 0 end
    ctx.save.berryPowder = have - cost
    return 1
  end)

  -- ---- the Pokemon Centre PC (EventScript_PC) ------------------------------
  alias(215, 218)                            -- AnimatePcTurnOff = DoPCTurnOffEffect
  alias(251, 254)                            -- ShowTownMap = FieldShowRegionMap
  def(263, function() end)                   -- HallOfFamePCBeginFade (no HoF PC viewer yet)
  -- CreatePCMenu (script_menu.c CreatePCMenuWindow): SOMEONE'S / BILL'S PC,
  -- the player's PC, then PROF. OAK'S PC with the POKeDEX, HALL OF FAME once
  -- the league is beaten, LOG OFF.  VAR_RESULT is the row, 127 for B.
  def(262, function(ctx)
    local t = texts(ctx).pcMenu or {}
    local player = ((ctx.save or {}).player or {}).name or "RED"
    local rows = {
      flag(ctx, 0x834) and (t[2] or Strings("BILL'S PC")) or (t[1] or Strings("SOMEONE'S PC")),
      ((t[3] or Strings("{PLAYER}'s PC")):gsub("{PLAYER}", player)),
    }
    if flag(ctx, 0x82C) then
      rows[#rows + 1] = t[4] or Strings("PROF. OAK'S PC")
      rows[#rows + 1] = t[5] or Strings("HALL OF FAME")
    elseif flag(ctx, 0x829) then
      rows[#rows + 1] = t[4] or Strings("PROF. OAK'S PC")
    end
    rows[#rows + 1] = t[6] or Strings("LOG OFF")
    local picked = Gen3Commands.listPick(ctx, rows, nil, #rows)
    local answer = picked and (picked - 1) or 0x7F
    setVar(ctx.save, VAR_RESULT, answer)
    return answer
  end)

  def(433, function(ctx)                     -- IsPlayerNotInTrainerTowerLobby
    return mapId(ctx) == "MAP_G02_N10" and 0 or 1
  end)

  -- ---- field step counters FireRed runs from the step (field_control_avatar.c)
  function Gen3Commands.frlgStep(ctx)
    local save = ctx.save
    if not save then return end
    local n = var(ctx, 0x4023)
    if n < 1500 then setVar(save, 0x4023, n + 1) end
    n = var(ctx, 0x4025)
    if n < 500 then setVar(save, 0x4025, n + 1) end
    if var(ctx, 0x4036) ~= 0 then
      n = var(ctx, 0x4035) + 1
      if n >= 250 then
        setVar(save, 0x4036, 0xFFFF)
        setVar(save, 0x4035, 0)
      else
        setVar(save, 0x4035, n)
      end
    end
    if mapId(ctx) == "MAP_G02_N56" then
      n = var(ctx, 0x4026) + 1
      setVar(save, 0x4026, n > 99 and 0 or n)
    end
  end

  -- ---- the Trainer Tower (CallTrainerTowerFunc, 0x8004 = which) ------------
  -- pokefirered trainer_tower.c, function for function, over the floors the
  -- import read (constants.gen3FRLGTrainerTower).  The cartridge's timer is a
  -- VBlank counter; here it is wall time at sixty frames a second, paused the
  -- same places the cartridge pauses it (the owner, a loss).
  local TT_MAX_TIME = 60 * 60 * 60 * 10 - 1
  local function now() return (love and love.timer and love.timer.getTime()) or os.clock() end
  local function ttTimer(st)
    if st.running then
      st.startedAt = st.startedAt or (now() - (st.timer or 0) / 60)
      st.timer = math.min(TT_MAX_TIME, math.floor((now() - st.startedAt) * 60))
    end
    return st.timer or 0
  end
  local function ttPause(st)
    ttTimer(st)
    st.running, st.startedAt = false, nil
  end
  local function tower(ctx)
    local d = data_(ctx)
    return d and d.constants and d.constants.gen3FRLGTrainerTower
  end
  local function ttState(ctx)
    ctx.save.frlgTrainerTower = ctx.save.frlgTrainerTower or
      { challenge = 0, floorsCleared = 0, timer = 0, bestTime = {}, receivedPrize = {} }
    return ctx.save.frlgTrainerTower
  end
  local function floorNumber(ctx)
    local id = mapId(ctx) or ""
    local n = tonumber(id:match("^MAP_G02_N0([1-8])$"))
    return n
  end
  local function currentFloor(ctx)
    local T, st = tower(ctx), ttState(ctx)
    local n = floorNumber(ctx)
    local floors = T and T.challenges[(st.challenge or 0) + 1]
    return floors and n and floors[n], n
  end
  local function ttSpeech(ctx, words)
    local ok, EasyChat = pcall(require, "src.script.EasyChat")
    local text = ok and EasyChat.phrase(data_(ctx), words, 3) or ""
    buffer(ctx, 4, text)
  end
  local function ttBattle(ctx)
    local T, st = tower(ctx), ttState(ctx)
    local floor = currentFloor(ctx)
    local d = data_(ctx)
    if not (T and floor and d) then ctx.lastBattleResult = "win" return end
    local level = 0
    for _, mon in ipairs(party(ctx)) do
      if not mon.isEgg and (mon.level or 0) > level then level = mon.level end
    end
    local cleared = math.min(7, st.floorsCleared or 0) + 1
    local trainerIdx = var(ctx, 0x4001)
    local picks = {}
    if floor.challengeType == 1 then
      local idx = T.doubleIdx[cleared]
      picks = { { floor.trainers[1], idx[1] }, { floor.trainers[2], idx[2] } }
    elseif floor.challengeType == 2 then
      local idx = T.knockoutIdx[cleared]
      picks = { { floor.trainers[trainerIdx + 1], idx[trainerIdx + 1] } }
    else
      local idx = T.singleIdx[cleared]
      local tr = floor.trainers[trainerIdx + 1] or floor.trainers[1]
      picks = { { tr, idx[1] }, { tr, idx[2] } }
    end
    local partyDef = {}
    for _, p in ipairs(picks) do
      local m = p[1] and p[1].mons[(p[2] or 0) + 1]
      local species = m and Gen3Commands.speciesId(d, m.species)
      if species and d.pokemon[species] then
        local moves = {}
        for _, mv in ipairs(m.moves) do
          local id = (d.constants.moveOrder or {})[mv]
          if type(id) == "string" then moves[#moves + 1] = id end
        end
        partyDef[#partyDef + 1] = { species = species, level = math.max(1, level),
                                    moves = #moves > 0 and moves or nil }
      end
    end
    if #partyDef == 0 then ctx.lastBattleResult = "win" return end
    local lead = picks[1][1]
    local trainerClass = T.classToTrainer[lead.facilityClass]
    -- the class's name, money and music come from a FireRed trainer of the
    -- same class; the PIC comes from gFacilityClassToPicIndex, never from
    -- that trainer (a template picked by class alone wore the wrong face)
    local picIndex = T.classToPic[lead.facilityClass] or T.classToPic[tostring(lead.facilityClass)]
    local template
    for _, tr in pairs(d.trainers or {}) do
      if type(tr) == "table" and tr.class == trainerClass and tr.picIndex
         and type(tr.pic) == "string" and tr.pic:find("battle/trainers/", 1, true) then
        template = tr
        if tr.picIndex == picIndex then break end
      end
    end
    local pic = picIndex and ("assets/generated/battle/trainers/%03d.png"):format(picIndex) or nil
    local record = setmetatable({
      id = "FRLG_TRAINER_TOWER", name = lead.name, parties = { partyDef }, party = partyDef,
      doubleBattle = floor.challengeType == 1 or nil, trainerTower = true,
      pic = pic, picIndex = picIndex, female = nil,
    }, { __index = template or {} })
    d.trainers.FRLG_TRAINER_TOWER = record
    ctx.g3Trainer = nil
    Commands.start_battle(ctx, "trainer", "FRLG_TRAINER_TOWER", 1,
                          { canLose = true, double = floor.challengeType == 1 or nil })
    local outcome = (Gen3Commands.GEN3_BATTLE_OUTCOME or {})[ctx.lastBattleResult] or 2
    setVar(ctx.save, VAR_RESULT, outcome)
  end
  local TT = {
    [0] = function(ctx)                      -- INIT_FLOOR
      local T = tower(ctx)
      local floor, n = currentFloor(ctx)
      if not (T and floor) or n > (T.numFloors or 8) then
        setVar(ctx.save, VAR_RESULT, 3)
        return
      end
      setVar(ctx.save, VAR_RESULT, floor.challengeType)
      local function gfxFor(class)
        local s = T.singles and (T.singles[class] or T.singles[tostring(class)])
        return s and s.gfx or 7
      end
      if floor.challengeType == 0 then
        setVar(ctx.save, 0x4011, gfxFor(floor.trainers[1].facilityClass))
      elseif floor.challengeType == 1 then
        local dd = T.doubles and (T.doubles[floor.trainers[1].facilityClass]
                                  or T.doubles[tostring(floor.trainers[1].facilityClass)])
        setVar(ctx.save, 0x4010, dd and dd.gfx1 or 7)
        setVar(ctx.save, 0x4013, dd and dd.gfx2 or 7)
      else
        setVar(ctx.save, 0x4012, gfxFor(floor.trainers[1].facilityClass))
        setVar(ctx.save, 0x4010, gfxFor(floor.trainers[2].facilityClass))
        setVar(ctx.save, 0x4011, gfxFor(floor.trainers[3].facilityClass))
      end
    end,
    [1] = function(ctx)                      -- GET_SPEECH (0x8005 which, 0x8006 trainer)
      local floor = currentFloor(ctx)
      if not floor then buffer(ctx, 4, "") return end
      local tr = floor.trainers[var(ctx, 0x8006) + 1] or floor.trainers[1]
      local which = var(ctx, 0x8005)
      local words = ({ [0] = tr.speechBefore, tr.speechWin, tr.speechLose, tr.speechAfter })[which]
      ttSpeech(ctx, words or {})
    end,
    [2] = ttBattle,                          -- DO_BATTLE
    [3] = function(ctx)                      -- GET_CHALLENGE_TYPE
      local floor = currentFloor(ctx)
      if var(ctx, 0x8005) == 0 then setVar(ctx.save, VAR_RESULT, floor and floor.challengeType or 0) end
    end,
    [4] = function(ctx)                      -- CLEARED_FLOOR
      local st = ttState(ctx)
      st.floorsCleared = (st.floorsCleared or 0) + 1
    end,
    [5] = function(ctx)                      -- GET_FLOOR_CLEARED
      local st = ttState(ctx)
      local floor, n = currentFloor(ctx)
      local notYet = n and (n - 1) == (st.floorsCleared or 0) and floor and n <= (floor.floorIdx or n)
      setVar(ctx.save, VAR_RESULT, notYet and 0 or 1)
    end,
    [6] = function(ctx)                      -- START_CHALLENGE
      local st = ttState(ctx)
      local c = var(ctx, 0x8005)
      st.challenge = (c < 4) and c or 0
      st.floorsCleared, st.timer, st.running, st.startedAt = 0, 0, true, now()
      st.spokeToOwner, st.checkedFinalTime, st.hasLost = false, false, false
    end,
    [7] = function(ctx)                      -- GET_OWNER_STATE
      local st = ttState(ctx)
      ttPause(st)
      local r = 0
      if st.spokeToOwner then r = r + 1 end
      if st.receivedPrize[st.challenge + 1] and st.checkedFinalTime then r = r + 1 end
      st.spokeToOwner = true
      setVar(ctx.save, VAR_RESULT, r)
    end,
    [8] = function(ctx)                      -- GIVE_PRIZE
      local T, st = tower(ctx), ttState(ctx)
      if st.receivedPrize[st.challenge + 1] then setVar(ctx.save, VAR_RESULT, 2) return end
      local floors = T and T.challenges[st.challenge + 1]
      local itemNum = floors and T.prizes[(floors[1].prize or 0) + 1]
      local d = data_(ctx)
      local item = itemNum and Gen3Commands.itemId(d, itemNum)
      local Bag = require("src.inventory.Bag")
      if item and Bag.add(ctx.save, item, 1, d) then
        local idef = d.items and d.items[item]
        buffer(ctx, 2, (idef and idef.name) or item)
        st.receivedPrize[st.challenge + 1] = true
        setVar(ctx.save, VAR_RESULT, 0)
      else
        setVar(ctx.save, VAR_RESULT, 1)
      end
    end,
    [9] = function(ctx)                      -- CHECK_FINAL_TIME
      local st = ttState(ctx)
      local best = st.bestTime[st.challenge + 1] or TT_MAX_TIME
      local time = ttTimer(st)
      if st.checkedFinalTime then
        setVar(ctx.save, VAR_RESULT, 2)
      elseif best > time then
        st.bestTime[st.challenge + 1] = time
        setVar(ctx.save, VAR_RESULT, 0)
      else
        setVar(ctx.save, VAR_RESULT, 1)
      end
      st.checkedFinalTime = true
    end,
    [10] = function(ctx)                     -- RESUME_TIMER
      local st = ttState(ctx)
      if not st.spokeToOwner and not st.running and (st.timer or 0) < TT_MAX_TIME then
        st.running = true
      end
    end,
    [11] = function(ctx) ttState(ctx).hasLost = true end,   -- SET_LOST
    [12] = function(ctx)                     -- GET_CHALLENGE_STATUS
      local st = ttState(ctx)
      if st.hasLost then
        st.hasLost = false
        ttPause(st)
        setVar(ctx.save, VAR_RESULT, 1)
      else
        setVar(ctx.save, VAR_RESULT, 0)
      end
    end,
    [13] = function(ctx)                     -- GET_TIME
      local frames = ttTimer(ttState(ctx))
      buffer(ctx, 1, ("%2d"):format(math.floor(frames / 3600)))
      buffer(ctx, 2, ("%2d"):format(math.floor(frames / 60) % 60))
      buffer(ctx, 3, ("%02d"):format(math.floor((frames % 60) * 168 / 100)))
    end,
    [14] = function(ctx)                     -- SHOW_RESULTS
      local T, st = tower(ctx), ttState(ctx)
      local lines = { (T and T.timeBoard) or Strings("TIME BOARD") }
      for i = 1, 4 do
        local frames = st.bestTime[i] or TT_MAX_TIME
        lines[#lines + 1] = ("%s  %d min. %02d.%02d sec."):format(
          (T and T.typeTexts and T.typeTexts[i]) or "", math.floor(frames / 3600),
          math.floor(frames / 60) % 60, math.floor((frames % 60) * 168 / 100))
      end
      Commands.show_text(ctx, table.concat(lines, "\n"))
    end,
    [15] = function() end,                   -- CLOSE_RESULTS
    [16] = function(ctx)                     -- CHECK_DOUBLES
      local n = 0
      for _, mon in ipairs(party(ctx)) do
        if not mon.isEgg and (mon.hp or 0) > 0 then n = n + 1 end
      end
      setVar(ctx.save, VAR_RESULT, n >= 2 and 0 or (n == 1 and 1 or 2))
    end,
    [17] = function(ctx)                     -- GET_NUM_FLOORS
      local T = tower(ctx)
      local n = T and T.numFloors or 8
      buffer(ctx, 1, tostring(n))
      setVar(ctx.save, VAR_RESULT, (T and T.challenges[1][1].floorIdx ~= n) and 1 or 0)
    end,
    [18] = function(ctx) setVar(ctx.save, VAR_RESULT, 0) end,   -- SHOULD_WARP_TO_COUNTER
    [19] = function() end,                   -- ENCOUNTER_MUSIC
    [20] = function(ctx) setVar(ctx.save, VAR_RESULT, ttState(ctx).spokeToOwner and 1 or 0) end,
  }
  def(404, function(ctx)
    local fn = TT[var(ctx, 0x8004)]
    if fn then return fn(ctx) end
  end)

  Logger.info("gen3: FireRed specials served")
end
