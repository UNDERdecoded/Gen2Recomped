-- Public choice of navigation mode; battle handles stay opaque to callbacks.
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local Wide = require("src.battle.WideBattle")
local M = {}
local function nativeGrid(battle)
  return battle:isWideBattleLayout() or battle:gen3Layout() or battle:gen4Layout()
end
function M.grid(battle)
  -- Gen1's wide GB layout has a fixed grid. Gold's distinct native screen
  -- allows wrappers to choose a list even when composed on a wider surface.
  if battle:isWideBattleLayout() and not Version.isGen2() then
    return true
  end
  if not Runtime.wantsHook("battle.move_grid_navigation") then
    return nativeGrid(battle)
  end
  return Runtime.call("battle.move_grid_navigation", nativeGrid, battle) == true
end
function M.navigate(battle, index, count, input)
  if not M.grid(battle) or count < 1 then
    return nil
  end
  if not (battle:gen3Layout() and battle:isDouble()) then
    return Wide.navigate(index, count, input)
  end
  -- GBA's doubles controller clamps to its current row/column. Singles and
  -- the GB mod grid wrap; missing cells retain the current occupied slot.
  local target = index
  local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
  if input:wasPressed("left") then
    if column == 1 then
      target = index - 1
    end
  elseif input:wasPressed("right") then
    if column == 0 then
      target = index + 1
    end
  elseif input:wasPressed("up") then
    if row == 1 then
      target = index - 2
    end
  elseif input:wasPressed("down") then
    if row == 0 then
      target = index + 2
    end
  else
    return nil
  end
  return target >= 1 and target <= count and target or index
end
return M
