-- Developer reference, OFF by default. Not the complete OASC mod.
local mod = ...
local function module(name, ...)
  local source = assert(mod:read(name .. ".lua"))
  return assert((loadstring or load)(source, "@portable_oasc_world/" .. name))(...)
end
local Adapter, Atlas = module("WorldAdapter"), module("Atlas")
local Pass = module("RenderPass", Adapter, Atlas)
local pass, why = Pass.new(mod.renderData)
if not pass then
  mod.exports.unavailable = why
  return
end
local ok, result = pcall(function()
  return mod.content.render_pipelines:register("portable_oasc_world", {
    label = "PORTABLE TERRAIN (DEVELOPER)",
    levels = { "OFF", "ON" },
    worldFormat = "renderData.v1",
    available = function()
      return mod.renderData:supports(1)
    end,
    drawWorld = function(frame)
      return pass:drawWorld(frame)
    end,
    update = function(_, level)
      if level == 0 then
        pass:invalidate()
      end
    end,
    invalidate = function()
      pass:invalidate()
    end,
  })
end)
if not ok or not result then
  pass:invalidate()
  mod.exports.unavailable = tostring(result)
  return
end
mod.exports.pass = pass
mod.exports.adapter = Adapter
mod.exports.atlas = Atlas
