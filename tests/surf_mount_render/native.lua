local M = {}
function M.attach(f)
  local Player = require("src.world.Player")
  package.loaded["src.core.Game"] = f.game
  function f.drawNative(camera)
    if f.player.hidden or f.player.invisible then
      return
    end
    -- Native Player:draw calls pose then drawSurfBlob. Observe on a native copy
    -- to isolate legacy spin/hop draw writes from the next comparison.
    local copy = {}
    for k, v in pairs(f.player) do
      copy[k] = v
    end
    setmetatable(copy, Player)
    copy.isUnderwater = function()
      return f.world.map.def.mapType == "UNDERWATER"
    end
    local _, px, py, facing = Player.pose(copy)
    if copy.fishing and copy.fishTiles and copy.fishTiles[facing] then
      return
    end
    copy:drawSurfBlob(px, py, camera.x, camera.y, facing)
  end
  function f.drawBody(camera)
    local copy = {}
    for k, v in pairs(f.player) do
      copy[k] = v
    end
    setmetatable(copy, Player)
    copy.isUnderwater = function()
      return f.world.map.def.mapType == "UNDERWATER"
    end
    copy.drawSurfBlob = function() end
    Player.draw(copy, camera.x, camera.y)
  end
  return f
end
return M
