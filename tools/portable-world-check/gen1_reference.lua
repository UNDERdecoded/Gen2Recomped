-- Explicit test/reference extension. Upstream Gen1 Game3 does not dispatch
-- this portable mode yet. Its real Loader and legacy Pipelines still run.
local M = {}
function M.install(loaderClass, data)
  -- Native Game3 marks its dataset as not supporting legacy world pipelines.
  -- This isolated reference view explicitly supplies the missing dispatch;
  -- it does not change the reference dataset or claim upstream availability.
  local pipelines = require("src.render.Pipelines")
  local install = pipelines.install
  pipelines.install = function(source)
    return install({ render_pipelines = source.render_pipelines })
  end
  local S = require("src.mods.Schemas")
  S.REGISTRIES.render_pipelines.fields.worldFormat = S.f.opt(S.f.enum({ "renderData.v1" }))
  local original = loaderClass._api
  loaderClass._api = function(loader, mod)
    local api = original(loader, mod)
    api.renderData = data
    local registry = api.content.render_pipelines
    local register = registry.register
    registry.register = function(self, id, def, ...)
      if def.worldFormat == "renderData.v1" then
        local draw = def.drawWorld
        def.drawWorld = function(native)
          -- Deliberately independent of Gen2's context converter.
          local g = love.graphics
          local target = g.getCanvas()
          local ok, result = pcall(function()
            g.origin()
            g.setShader()
            g.setScissor()
            g.setDepthMode()
            g.setColor(1, 1, 1, 1)
            g.setBlendMode("alpha", "alphamultiply")
            return draw({
              version = 1,
              generation = 3,
              mapId = native.state.map.id,
              width = native.pixelWidth,
              height = native.pixelHeight,
              pixelWidth = native.pixelWidth,
              pixelHeight = native.pixelHeight,
              unitWidth = native.unitWidth,
              unitHeight = native.unitHeight,
              dpiX = native.pixelWidth / native.unitWidth,
              dpiY = native.pixelHeight / native.unitHeight,
              viewWidth = native.vw,
              viewHeight = native.vh,
              level = native.level,
              camera = { x = native.cam.x, y = native.cam.y },
            })
          end)
          g.setCanvas(target)
          if not ok then
            error(result)
          end
          return result
        end
      end
      return register(self, id, def, ...)
    end
    return api
  end
end
return M
