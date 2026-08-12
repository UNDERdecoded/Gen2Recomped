local Flags = require("src.script.Flags")
local Gen2Flags = require("src.script.Gen2Flags")

local M = {}

local DAILY_ENGINE = {
  47, -- ENGINE_KURT_MAKING_BALLS  (clear → Kurt delivers)
  48, -- ENGINE_DAILY_BUG_CONTEST
  51, -- ENGINE_ALL_FRUIT_TREES
  52, -- ENGINE_GOT_SHUCKIE_TODAY
}

function M.dayKey()
  return os.date("%Y-%m-%d")
end

function M.onNewDay(save)
  if not save then return end
  for _, idx in ipairs(DAILY_ENGINE) do
    Flags.clear(save, Gen2Flags.engineFlag(idx))
  end
  -- Fruit trees: clear pick memory (g2_fruittree)
  save.g2FruitTrees = {}
  save.g2LastDailyDay = M.dayKey()
end

function M.poll(save)
  if not save then return end
  local today = M.dayKey()
  if save.g2LastDailyDay ~= today then
    M.onNewDay(save)
  end
end

return M