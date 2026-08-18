-- The population ceiling, and the two nil-shaped holes the first cut had.
--
-- v1 keyed on self.activeMapId and returned false whenever a target was 0.
-- On the WATER path both are true -- trySpawnWater derives its own mapId from
-- the overworld and targetWaterCount can be 0 -- so the ceiling never engaged
-- and 791 water spawns went through in one session.  It now counts every live
-- entity, with no map key and no zero-target escape.
local pass, fail = 0, 0
local function check(name, got, want)
  if got == want then pass = pass + 1
  else fail = fail + 1 print(("  FAIL %-54s got %s want %s")
    :format(name, tostring(got), tostring(want))) end
end

local POPULATION_SLACK, ABSOLUTE_MAX = 2, 18

local function newLogic(land, water)
  local self = { entities = {}, targetSpawnCount = land, targetWaterCount = water }
  function self:liveEntityCount()
    local n = 0
    for _ in pairs(self.entities or {}) do n = n + 1 end
    return n
  end
  function self:populationBudget()
    local a = tonumber(self.targetSpawnCount) or 0
    local b = tonumber(self.targetWaterCount) or 0
    local budget = a + b
    if budget <= 0 then budget = ABSOLUTE_MAX end
    if budget > ABSOLUTE_MAX then budget = ABSOLUTE_MAX end
    return budget + POPULATION_SLACK
  end
  function self:atPopulationCeiling()
    return self:liveEntityCount() >= self:populationBudget()
  end
  function self:fill(n) for i = 1, n do self.entities["e" .. i] = {} end end
  return self
end

-- ------- the hole that let 791 through: no target at all
do
  local L = newLogic(0, 0)
  check("a zero budget falls back, it does not disable", L:populationBudget(),
        ABSOLUTE_MAX + POPULATION_SLACK)
  L:fill(19)
  check("19 live is under the fallback", L:atPopulationCeiling(), false)
  L:fill(20)
  check("20 live hits it", L:atPopulationCeiling(), true)
end

-- nil targets are the same story
do
  local L = newLogic(nil, nil)
  check("nil targets still budget", L:populationBudget(), ABSOLUTE_MAX + POPULATION_SLACK)
  L:fill(25)
  check("and still cap", L:atPopulationCeiling(), true)
end

-- ------- normal operation: the mod's real numbers
do
  local L = newLogic(12, 6)
  check("budget is target + slack", L:populationBudget(), 20)
  L:fill(19)
  check("under budget spawns continue", L:atPopulationCeiling(), false)
  L:fill(20)
  check("at budget they stop", L:atPopulationCeiling(), true)
end

-- ------- an absurd target cannot lift the ceiling
do
  local L = newLogic(500, 500)
  check("a runaway target is clamped", L:populationBudget(),
        ABSOLUTE_MAX + POPULATION_SLACK)
  L:fill(21)
  check("and the cap still bites", L:atPopulationCeiling(), true)
end

-- ------- despawning frees it again
do
  local L = newLogic(12, 6)
  L:fill(25)
  check("capped", L:atPopulationCeiling(), true)
  for i = 6, 25 do L.entities["e" .. i] = nil end
  check("count follows the entity table", L:liveEntityCount(), 5)
  check("and spawning resumes", L:atPopulationCeiling(), false)
end

-- ------- no map id anywhere: the ceiling must not care
do
  local L = newLogic(12, 6)
  L.activeMapId = nil
  L.byMap = nil
  L:fill(25)
  check("no map key is consulted at all", L:atPopulationCeiling(), true)
end

-- ------- the ceiling is an upper bound on ANYTHING the loops can do
do
  local L = newLogic(12, 6)
  local spawned = 0
  -- the three refill loops, run 400 times the way a tick would
  for _ = 1, 400 do
    for _ = 1, 4 do
      if not L:atPopulationCeiling() then
        spawned = spawned + 1
        L.entities["s" .. spawned] = {}
      end
    end
  end
  check("1600 attempts cannot exceed the budget", spawned, 20)
  check("which is nothing like 791", spawned < 100, true)
end

print(("spawn ceiling: %d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
