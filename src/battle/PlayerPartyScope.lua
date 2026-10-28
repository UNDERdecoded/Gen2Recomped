-- Battle-local ordered references; never reorder or replace save.party.
local Logger = require("src.core.Logger")
local M = {}
function M.select(game, indices)
  if indices == nil then
    return nil, nil
  end
  local function fallback()
    Logger.warn("trainer battle party scope is invalid; using full party")
    return nil, nil
  end
  if type(indices) ~= "table" or #indices == 0 then
    return fallback()
  end
  local count = #indices
  local keys = 0
  for key in pairs(indices) do
    keys = keys + 1
    if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
      return fallback()
    end
  end
  if keys ~= count then
    return fallback()
  end
  local party, normalized, seen = {}, {}, {}
  for i = 1, count do
    local index = indices[i]
    if type(index) ~= "number" or index % 1 ~= 0 or not game.save.party[index] or seen[index] then
      return fallback()
    end
    seen[index], normalized[i], party[i] = true, index, game.save.party[index]
  end
  return party, normalized
end
return M
