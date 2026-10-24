-- The party handle remains native; only the navigation decision is shared.
local Runtime = require("src.mods.Runtime")
local M = {}
function M.enabled(menu)
  if not menu.battle or not Runtime.wantsHook("ui.party.grid_navigation") then
    return false
  end
  return Runtime.call("ui.party.grid_navigation", function()
    return false
  end, menu) == true
end
function M.rows(index, count, input)
  if count < 1 then
    return nil
  end
  local row, col = math.floor((index - 1) / 2), (index - 1) % 2
  if input:wasPressed("left") or input:wasPressed("right") then
    local other = row * 2 + (1 - col) + 1
    return other <= count and other or index
  end
  local step = input:wasPressed("up") and -1 or input:wasPressed("down") and 1
  if not step then
    return nil
  end
  local rows = math.ceil(count / 2)
  for offset = 1, rows do
    local other = ((row + step * offset) % rows) * 2 + col + 1
    if other <= count then
      return other
    end
  end
  return index
end
local function position(menu, i)
  local panel = menu:panelFor(i)
  if panel.icon then
    return panel.icon.x, panel.icon.y
  end
  -- The fallback art draws a 32-pixel icon at the left of its panel.
  return panel.x + 20, panel.y + panel.height / 2
end
function M.spatial(menu, input)
  local dir = input:wasPressed("up") and "up"
    or input:wasPressed("down") and "down"
    or input:wasPressed("left") and "left"
    or input:wasPressed("right") and "right"
  if not dir then
    return nil
  end
  local count, cur = #menu:party(), menu.index
  local cancel, target = count + 1, cur
  if cur == cancel then
    if count > 0 then
      if dir == "up" then
        target = count
      elseif dir == "down" then
        target = 1
      end
    end
  elseif cur >= 1 and cur <= count then
    local x, y = position(menu, cur)
    local best
    for i = 1, count do
      if i ~= cur then
        local tx, ty = position(menu, i)
        local dx, dy = tx - x, ty - y
        local distance
        if
          (dir == "left" and dx < 0)
          or (dir == "right" and dx > 0)
          or (dx == 0 and ((dir == "up" and dy < 0) or (dir == "down" and dy > 0)))
        then
          distance = math.abs(dy)
        end
        if distance and (not best or distance < best) then
          target, best = i, distance
        end
      end
    end
    if not best and (dir == "up" or dir == "down") then
      target = cancel
    end
  end
  return target
end
return M
