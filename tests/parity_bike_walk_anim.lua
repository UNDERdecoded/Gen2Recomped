-- Regression: bike / desynced walk steps must not flash stand on land (issue #82).
--
-- walkPhase used to return 0 whenever moving was false.  A step clears
-- moving on its final FixedStep tick, so the draw after landing snapped
-- to stand even when animClock was mid walk-cycle.  Bike steps are 8
-- frames, so they land at animClock % 16 == 8 (walk) every tile -- always
-- stuttery.  Walking after a bike ride inherits a desynced animClock and
-- hit the same stand flash "sometimes."
--
-- Self-contained; run via `luajit tests/parity_bike_walk_anim.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local Player = require("src.world.Player")
local S = require("tests.harness").suite("parity bike walk anim")
local check, eq = S.check, S.eq

local function makePlayer(onBike)
  local p = Player.new(Data, 5, 5, "down")
  p.onBike = onBike
  if onBike then
    p.stepFramesCur = p.bikeStepFrames or 8
  else
    p.stepFramesCur = p.stepFrames or 16
  end
  p.animClock = 0
  return p
end

local function startStep(p)
  p.moving = true
  p.progress = 0
  p.targetX, p.targetY = p.cellX, p.cellY + 1
end

-- --- bike: every land frame mid-cycle must stay walk ---
local bike = makePlayer(true)
local landPhases = {}
for tile = 1, 4 do
  startStep(bike)
  local stepLen = bike.stepFramesCur
  for _ = 1, stepLen do
    local done = bike:update()
    if done then
      landPhases[#landPhases + 1] = bike:walkPhase()
      eq(bike.moving, false, "bike step clears moving on land")
      check(bike.stepLanded, "bike land latches stepLanded for draw")
    end
  end
end
-- lands at animClock 8, 16, 24, 32 → %16 = 8, 0, 8, 0
-- walk band is 4..11, so lands at 8 must be phase 1; at 0 must be phase 0
eq(landPhases[1], 1, "bike land at animClock%16==8 keeps walk pose")
eq(landPhases[2], 0, "bike land at animClock%16==0 is stand (in-band)")
eq(landPhases[3], 1, "bike land at animClock%16==8 keeps walk pose again")
eq(landPhases[4], 0, "bike land at animClock%16==0 is stand again")

-- continuous bike phases across two tiles: no forced stand in the walk band
bike = makePlayer(true)
local phases = {}
for _ = 1, 2 do
  startStep(bike)
  for _ = 1, bike.stepFramesCur do
    bike:update()
    phases[#phases + 1] = bike:walkPhase()
  end
end
-- frames 4..11 of animClock are walk; across 16 ticks that is indices 4..11
for i = 4, 11 do
  eq(phases[i], 1, "bike continuous walk band has no stand flash at " .. i)
end

-- idle after land: next update drops the latch → stand
bike = makePlayer(true)
startStep(bike)
for _ = 1, bike.stepFramesCur do bike:update() end
eq(bike:walkPhase(), 1, "latched land frame still walk")
bike:update()
eq(bike.stepLanded, false, "idle update clears stepLanded")
eq(bike:walkPhase(), 0, "truly idle is stand")

-- --- walk after desynced animClock (post-bike): land must not force stand ---
local walk = makePlayer(false)
walk.animClock = 8 -- leftover from a bike half-cycle
startStep(walk)
local lastPhase
for _ = 1, walk.stepFramesCur do
  walk:update()
  lastPhase = walk:walkPhase()
end
eq(walk.animClock % 16, 8, "desynced walk lands mid walk-cycle")
eq(lastPhase, 1, "desynced walk land keeps walk pose (no post-bike stutter)")

S.finish()
