-- Final-output ownership comes after composition and before display effects.
local Runtime = require("src.mods.Runtime")
local Scope = require("src.render.GraphicsScope")
local Logger = require("src.core.Logger")
local O = {}
function O.enabled()
  if not Runtime.wantsHook("render.output") then
    return false
  end
  local ok, value = Scope.call(function()
    return Runtime.call("render.output_enabled", function()
      return false
    end)
  end)
  if not ok then
    Logger.warn("render output gate failed: %s", tostring(value))
  end
  return ok and value == true
end
function O.draw(ctx)
  local ok, value = Scope.call(function()
    local G = love.graphics
    G.origin()
    G.setShader()
    G.setScissor()
    G.setBlendMode("alpha")
    G.setColor(1, 1, 1, 1)
    return Runtime.call("render.output", function()
      return false
    end, ctx)
  end)
  if not ok then
    Logger.warn("render output failed: %s", tostring(value))
  end
  return ok and value == true
end
return O
