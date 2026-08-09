-- Driver: #200 Pokemon Tower 7F Rocket grunts must walk off + despawn.
-- The three grunts (POKEMONTOWER7F_ROCKET1/2/3, obj indices 1/2/3, at
-- (9,11)/(12,9)/(9,7)) are sight/talk trainers.  In Gen1
-- (scripts/PokemonTower7F.asm: PokemonTower7FEndBattleScript ->
-- PokemonTower7FRocketLeaveMovementScript -> PokemonTower7FHideNPCScript)
-- each grunt, after losing, shows its EndBattle text ("I give up!"), then its
-- AfterBattle text ("I'm not going to forget this!"), then walks off toward
-- the (9,16) stairs (MoveSprite) and HideObject despawns it.  The bug left
-- every beaten grunt standing in place forever -- att1 in the report shows
-- all three still lined up in the corridor after being defeated.
--
-- This driver beats each grunt in turn and, per grunt, samples ow.npcs every
-- frame: the grunt must MOVE off its start tile before it leaves ow.npcs, and
-- must end despawned (gone from ow.npcs, objectToggle == false, beat flag set).
-- Before the fix each grunt stays at its start tile and never despawns, so the
-- movement + despawn assertions fail.  After the fix they pass.
--
--   SHOT_DIR=/tmp/t7f POKEPORT_IDENTITY=bug200 POKEPORT_TOUCH=0 \
--     POKEPORT_SPEED=4 \
--     POKEPORT_DRIVER=tests/drivers/tower7f_bug200_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")

  -- clean slate: no grunt may read as already defeated / hidden
  game.save.defeatedTrainers = {}
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles.POKEMON_TOWER_7F = nil
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_BEAT_POKEMONTOWER_7_TRAINER_0 = nil
  game.save.flags.EVENT_BEAT_POKEMONTOWER_7_TRAINER_1 = nil
  game.save.flags.EVENT_BEAT_POKEMONTOWER_7_TRAINER_2 = nil
  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "RED"

  -- a tank that one-shots any of the L19-25 Rocket parties regardless of
  -- type, so the mash win is quick and deterministic (same valve as
  -- gamecorner_rocket_bug198_test)
  local function freshParty()
    local tank = Pokemon.new(game.data, "MEWTWO", 100)
    tank.moves = {
      { id = "PSYCHIC_M", pp = 99 },
      { id = "THUNDERBOLT", pp = 99 },
      { id = "ICE_BEAM", pp = 99 },
      { id = "EARTHQUAKE", pp = 99 },
    }
    game.save.party = { tank }
  end

  -- Each grunt: object index/name/id, home tile, and the tile the player
  -- stands on (facing up, directly below the grunt) to talk it into a battle.
  -- The talk tiles are the ones the vanilla movement table keys on, so the
  -- exit walk is the exact PokemonTower7F path (not the safety fallback).
  local ROCKETS = {
    { index = 1, name = "POKEMONTOWER7F_ROCKET1",
      id = "POKEMON_TOWER_7F_obj_1",
      beat = "EVENT_BEAT_POKEMONTOWER_7_TRAINER_0",
      afterFrag = "forget this",
      rx = 9, ry = 11, standX = 9, standY = 12 },
    { index = 2, name = "POKEMONTOWER7F_ROCKET2",
      id = "POKEMON_TOWER_7F_obj_2",
      beat = "EVENT_BEAT_POKEMONTOWER_7_TRAINER_1",
      afterFrag = "making",
      rx = 12, ry = 9, standX = 12, standY = 10 },
    { index = 3, name = "POKEMONTOWER7F_ROCKET3",
      id = "POKEMON_TOWER_7F_obj_3",
      beat = "EVENT_BEAT_POKEMONTOWER_7_TRAINER_2",
      afterFrag = "getting", rx = 9, ry = 7, standX = 9, standY = 8 },
  }

  local function pageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local parts = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  local shotN = 0
  local function shot(tag)
    shotN = shotN + 1
    U.shot(game, DIR .. ("/tower7f_%02d_%s.png"):format(shotN, tag))
  end

  -- Beat one grunt via a talk engagement, then verify it walks off + despawns.
  -- shots ~= nil requests the before/walk/after screenshot trio for the report.
  local function beatGrunt(r, shots)
    U.teleport(game, "POKEMON_TOWER_7F", r.standX, r.standY, "up")
    local ow = game.overworld

    local function findGrunt()
      for _, n in ipairs(ow.npcs or {}) do
        if n.def and n.def.name == r.name then return n end
      end
      return nil
    end
    local function idle()
      return game.stack:top() == ow and not ow.runner:isRunning()
             and #ow.scriptMoves == 0 and not ow.transitioning
    end

    local g = findGrunt()
    assert(g, r.name .. " not present at start")
    assert(g.cellX == r.rx and g.cellY == r.ry,
      r.name .. " not at expected start tile")
    U.log(r.name, "start:", g.cellX, g.cellY, g.facing)
    if shots then shot("standing") end

    -- Phase A: talk, then mash through pre-battle text + the battle, stopping
    -- the instant the win is registered (the beat flag is set inside the
    -- battle's onFinish, before the EndBattle box is pushed) so Phase B can
    -- watch the exit walk that follows.
    U.tap(game, "a")
    local sawAfter = false
    for f = 1, 4000 do
      if game.save.flags[r.beat] then break end
      if pageText():find(r.afterFrag, 1, true) then sawAfter = true end
      local top = game.stack:top()
      if top and top.phase then
        if top.phase == "menu" then top.menuIndex = 1
        elseif top.phase == "moveSelect" then top.moveIndex = 1 end
        U.tap(game, "a")
        if f > 2400 and top.onFinish then
          U.log("force-finishing stalled battle")
          top.onFinish("win")
          if game.stack:top() == top then game.stack:pop() end
        end
      else
        U.tap(game, "a") -- talk / advance pre-battle text
      end
      U.wait(2)
    end
    assert(game.save.flags[r.beat], r.name .. " never registered a win")

    -- Phase B: sample every logic frame while advancing the EndBattle +
    -- AfterBattle boxes.  The grunt must move off its start tile (mid-walk it
    -- carries targetX/targetY toward the stairs, then its cell updates) before
    -- HideObject removes it from ow.npcs.
    local moved, walkShot = false, false
    for _ = 1, 2000 do
      local gg = findGrunt()
      if gg then
        if gg.cellX ~= r.rx or gg.cellY ~= r.ry
           or (gg.targetX and gg.targetX ~= r.rx)
           or (gg.targetY and gg.targetY ~= r.ry) then
          moved = true
          if shots and not walkShot then
            walkShot = true
            shot("walkoff")
          end
        end
      elseif idle() then
        break
      end
      if pageText():find(r.afterFrag, 1, true) then sawAfter = true end
      if game.stack:top() ~= ow then U.tap(game, "a") end
      U.wait(1)
    end

    for _ = 1, 400 do
      if idle() then break end
      if game.stack:top() ~= ow then U.tap(game, "a") end
      U.wait(2)
    end
    U.wait(5)
    if shots then shot("gone") end

    local toggles = game.save.objectToggles.POKEMON_TOWER_7F
    U.log(r.name, "sawAfter:", sawAfter, "moved:", moved,
      "gone:", findGrunt() == nil,
      "toggle:", tostring(toggles and toggles[r.name]))

    -- CORRECT Gen1 behavior: EndBattle/AfterBattle speech, then the grunt
    -- walks off before despawning -- it must not vanish in place.
    assert(sawAfter, r.name .. " never showed its after-battle text (#200)")
    assert(moved,
      r.name .. " never walked off its tile before despawning (#200)")
    assert(findGrunt() == nil, r.name .. " still present after the exit walk")
    assert(toggles and toggles[r.name] == false,
      r.name .. " objectToggle not persisted hidden")
    assert(game.save.defeatedTrainers[r.id], r.name .. " not recorded defeated")
    for _, n in ipairs(ow.npcs or {}) do
      assert(not (n.cellX == r.rx and n.cellY == r.ry),
        "an NPC still occupies " .. r.name .. "'s old tile")
    end
  end

  freshParty()
  beatGrunt(ROCKETS[1], true)  -- ROCKET1 gets the report screenshot trio
  freshParty()
  beatGrunt(ROCKETS[2], false)
  freshParty()
  beatGrunt(ROCKETS[3], false)

  -- all three gone: confirm the corridor up to Mr. Fuji is clear of grunts
  U.teleport(game, "POKEMON_TOWER_7F", 9, 13, "up")
  local ow = game.overworld
  for _, n in ipairs(ow.npcs or {}) do
    assert(n.def.name == "POKEMONTOWER7F_MR_FUJI",
      "a Rocket grunt is still on the floor after all three were beaten")
  end
  local fuji
  for _, n in ipairs(ow.npcs or {}) do
    if n.def.name == "POKEMONTOWER7F_MR_FUJI" then fuji = n end
  end
  assert(fuji, "MR_FUJI missing from the top floor")
  shot("fuji_clear")
  U.log("tower7f_bug200_test: ok")
end
