-- Driver: Fighting Dojo Karate Master does not leave his post (#502),
-- the opposite-direction report against the same script #495 fixed
-- (data/scripts/story4.lua dojoMasterGate / M.FIGHTING_DOJO.onStep).
--
-- Before the fix his trainer header used range=4/DOWN sight aggro
-- (src/core/Data.lua seedFightingDojoKarateMaster), so walking up his
-- column from below put him in CheckFightingMapTrainers' generic path:
-- the NPC walks toward the player before the pre-battle text, straight
-- through FIGHTINGDOJO_BLACKBELT3/4's tiles at (5,5)/(5,7) -- the
-- "merges with a pupil" glitch, and it fired regardless of whether the
-- pupils in front of him had been beaten yet ("forces the fight early").
-- The fix sets range=0 and gates him on the single tile at his left
-- (4,3) instead (onStep = dojoMasterGate): he only ever turns to face
-- the player there, never steps.
--
--   POKEPORT_DRIVER=tests/drivers/fighting_dojo_master_bug502_test.lua \
--     POKEPORT_IDENTITY=bug502 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function masterIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == "FIGHTINGDOJO_KARATE_MASTER" then return n end
    end
    return nil
  end

  -- No pupil beaten, master not beaten: the exact state the report says
  -- triggered the early merge (walking up before clearing the pupils).
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_BEAT_KARATE_MASTER = nil
  game.save.defeatedTrainers = {}

  ------------------------------------------------------------------
  -- Direction 1 (#502): stand in the master's own sight column, below
  -- him, with his southern pupils (BLACKBELT3 at (5,5), BLACKBELT4 at
  -- (5,7)) still in the way -- exactly the "walk towards Karate Master"
  -- report.  The old range=4/DOWN header put any of these cells in his
  -- sight; his first step toward the player collided with BLACKBELT3's
  -- tile.  Collision blocks a real walk onto an NPC's cell, so probe by
  -- teleport (a scripted approach cannot walk through them either) and
  -- watch several fixed steps for the master moving or engaging at all.
  ------------------------------------------------------------------
  local ow, master
  local function probe(px, py, label)
    U.teleport(game, "FIGHTING_DOJO", px, py, "up")
    U.wait(10)
    ow = game.stack:top()
    master = masterIn(ow)
    U.shot(game, DIR .. "/bug502_1_" .. label .. "_before.png")
    local moved, engaged = false, false
    for _ = 1, 40 do
      U.wait(1)
      if master.cellX ~= 5 or master.cellY ~= 3 then moved = true end
      if getmetatable(game.stack:top()) == TextBox then engaged = true; break end
    end
    U.shot(game, DIR .. "/bug502_1_" .. label .. "_after.png")
    check("Fighting Dojo is loaded (" .. label .. ")", ow.map.id == "FIGHTING_DOJO")
    check("Karate Master stayed at (5,3), did not walk toward (" .. label .. ")",
          not moved)
    check("standing at " .. label .. " started no battle on its own",
          not engaged)
    return moved or engaged
  end

  -- (5,4): directly below the master, one tile from BLACKBELT3 (5,5).
  -- (5,6): the gap between BLACKBELT3 and BLACKBELT4, still in the old
  -- sight range and still boxed in by pupils on both sides.
  local bad1 = probe(5, 4, "below_master")
  local bad2 = probe(5, 6, "between_pupils")

  ------------------------------------------------------------------
  -- Direction 2 (#495, same script): the ONLY tile that should start his
  -- fight is one step left of him.  Confirm the gate still works so the
  -- fix didn't just make him inert in both directions.
  ------------------------------------------------------------------
  U.teleport(game, "FIGHTING_DOJO", 4, 2, "down")
  U.wait(10)
  ow = game.stack:top()
  master = masterIn(ow)
  U.shot(game, DIR .. "/bug502_3_gate_before.png")
  U.tap(game, "down")
  U.wait(30)
  local gateOpened = getmetatable(game.stack:top()) == TextBox
  U.shot(game, DIR .. "/bug502_4_gate_after.png")
  check("stepping onto (4,3) still starts the Master's challenge", gateOpened)
  check("he turned to face the player instead of walking to them",
        master.cellX == 5 and master.cellY == 3 and master.facing == "left")

  U.log("Compare bug502_1/2: the Master's sprite should sit in the same")
  U.log("spot in both, never sliding down onto BLACKBELT3 or BLACKBELT4.")
  U.log("bug502_4 should show his pre-battle text box, with him still on")
  U.log("(5,3), just turned to face left -- that is the correct trigger,")
  U.log("distinct from the column walk that used to glitch him south.")

  while true do
    coroutine.yield()
  end
end
