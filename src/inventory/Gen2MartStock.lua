-- The ROM's mart number is zero based. Type 2 uses its independent priced
-- rows and deliberately ignores that number, as BargainShop does.
local M = {}
function M.get(data, index, martType)
  local pool = data.map_scripts and data.map_scripts.marts
  return pool and pool[martType == 2 and "bargain" or index], { bargain = martType == 2 }
end
function M.entry(data, entry)
  if entry and entry.martId ~= nil and require("src.core.GameVersion").generation() == 2 then
    return M.get(data, entry.martId, entry.martType)
  end
  return entry and entry.mart
end
return M
