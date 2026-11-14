-- A trainer's walk-up that ends while a map script is still running must queue
-- the fight behind it, not assert out of the field's update.
--
-- Route 207: the player stood on a coordinate event as a trainer spotted them;
-- `fight()` called ScriptRunner:run with the coordinate script still going and
-- `assert(not self:isRunning(), "script already running")` raised from
-- OverworldState:update -- the game was over. Found by tools/gen4_field_sweep.
--
-- Run: python tools/gen4_field_sweep.py --install <cache> --regress
-- (a probe: it runs inside the sweep harness with PROBE=<this file>)

local S = _G.__sweep
local OW, Game = S.OW, S.Game
local failed = false
local function check(cond, what)
  if not cond then failed = true; print("REGRESS_FAIL trainer_queue: " .. what) end
end

S.enterMap("R207", 31, 40, "down")
S.run(90)
for _ = 1, 20 do if not (OW.runner:isRunning() or OW.transitioning) then break end S.run(30) end

local trainer
for _, npc in ipairs(OW.npcs or {}) do
  if npc.def and type(npc.def.trainer) == "table" and npc.def.trainer.id and not npc.hidden then
    trainer = npc
    break
  end
end
check(trainer ~= nil, "Route 207 has a visible trainer")
if trainer then
  -- a map script is running (a long wait, as a coordinate event's walk is) ...
  OW.runner:run({ { "wait", 300 } }, { mapId = OW.map.id })
  check(OW.runner:isRunning(), "the stand-in map script is running")
  -- ...when the trainer's walk-up ends
  trainer.facing = "down"
  OW:startTrainerApproach(trainer, 1)
  local ok = S.run(600)
  check(ok, "updating through the walk-up must not raise")
  check(#(OW.pendingScripts or {}) <= 1, "at most the one queued fight is pending")
end

print(failed and "REGRESS_FAIL trainer_queue" or "REGRESS_OK trainer_queue")
