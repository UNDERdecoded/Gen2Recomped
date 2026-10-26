-- The native doll is a 64x64 OBJ centered on the battler's raw coordinates.
local M = {}
local V = require("src.core.GameVersion")
local Assets = require("src.render.Assets")

function M.pose(battle, battler)
  if not V.isGen3() or not battler then
    return nil
  end
  if battle.gen3Layout and not battle:gen3Layout() then
    return nil
  end
  local constants = battle.data and battle.data.constants or {}
  local record, coords = constants.gen3SubstituteArt, constants.gen3BattlerCoords
  if not record or record.version ~= 1 or record.width ~= 64 or record.height ~= 64 then
    return nil
  end
  local positions = coords and (battle:isDouble() and coords.doubles or coords.singles)
  local id = tonumber(battler.position) or (battler.isPlayer and 0 or 1)
  local raw = positions and positions[id + 1]
  local path = battler.isPlayer and record.back or record.front
  if not raw or type(path) ~= "string" then
    return nil
  end
  local dx, dy = battle:gen3AnimShake(battler)
  return {
    image = path,
    x = require("src.battle.Gen3Battle").fieldOffset(battle) + raw.x - 32 + (dx or 0),
    y = raw.y + (battler.isPlayer and 17 or 16) - 32 + (dy or 0),
  }
end

function M.draw(battle, battler)
  local pose = M.pose(battle, battler)
  if not pose then
    return false
  end
  local image = Assets.image(pose.image)
  local g = love.graphics
  local r, green, blue, coeff
  if battle.gen3AnimTint then
    r, green, blue, coeff = battle:gen3AnimTint(battler)
  end
  if coeff and coeff > 0 then
    local cr, cg, cb, ca = g.getColor()
    local blend, alpha = g.getBlendMode()
    g.setColor(cr * (1 - coeff), cg * (1 - coeff), cb * (1 - coeff), ca)
    g.draw(image, pose.x, pose.y)
    g.setBlendMode("add")
    g.setColor(r * coeff, green * coeff, blue * coeff, ca)
    g.draw(image, pose.x, pose.y)
    g.setBlendMode(blend, alpha)
    g.setColor(cr, cg, cb, ca)
  else
    g.draw(image, pose.x, pose.y)
  end
  return true
end

return M
