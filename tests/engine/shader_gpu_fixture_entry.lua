-- Standalone GPU tools must reach their pixel oracle even when a distro's
-- LÖVE does not export private PhysFS symbols. Exercise their real entrypoints;
-- the actual shaders/pixels remain covered by the shader-import CI job.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
love.event = love.event or {}
local getenv, stderr = os.getenv, io.stderr
local presets, cache = package.loaded["src.render.ShaderPresets"], package.loaded["src.import.CacheFs"]
local info, source, quit = love.filesystem.getInfo, love.filesystem.getSource, love.event.quit
local cases = {
  { file = "tools/slang-import-check/main.lua", env = "SLANG_IMPORT_CHECK_DIR", unavailable = "fixture directory mounted" },
  { file = "tools/shader-graph-check/main.lua", env = "SHADER_GRAPH_CHECK_DIR", unavailable = "mount unavailable" },
}
for _, tool in ipairs(cases) do
  for _, mode in ipairs({ "staged", "missing", "external", "unavailable" }) do
    local body, mounts, message, exit = 0, 0, "", nil
    package.loaded["src.render.ShaderPresets"] = { new = function()
      body = body + 1
      error("GPU pixel oracle reached", 0)
    end }
    package.loaded["src.import.CacheFs"] = { withMounted = function(dir, point, fn)
      mounts = mounts + 1
      T.eq(dir, "/isolated/generated", "external fixture directory retained")
      T.eq(point, "imports", "external mount stays namespaced")
      if mode == "unavailable" then return nil end
      return fn()
    end }
    os.getenv = function(key)
      if key == tool.env then
        return (mode == "staged" or mode == "missing") and "imports" or "/isolated/generated"
      end
      return getenv(key)
    end
    love.filesystem.getSource = function() return "/isolated/" .. tool.file:gsub("/main.lua$", "") end
    love.filesystem.getInfo = function(path, kind)
      if path == "imports" and kind == "directory" and mode == "staged" then return {type="directory"} end
    end
    io.stderr = { write = function(_, text) message = message .. text end }
    love.event.quit = function(code) exit = code end
    assert(loadfile(tool.file))()
    love.load()
    T.eq(exit, 1, "test sentinel or unavailable fixture exits cleanly")
    T.eq(body, (mode == "staged" or mode == "external") and 1 or 0, "only available fixtures reach GPU oracle")
    T.eq(mounts, (mode == "external" or mode == "unavailable") and 1 or 0, "staged path never asks private FFI to mount")
    local expected = mode == "missing" and "staged fixtures present"
      or mode == "unavailable" and tool.unavailable or "GPU pixel oracle reached"
    T.check(message:find(expected, 1, true) ~= nil, "error preserves real failure cause")
  end
end
os.getenv, io.stderr = getenv, stderr
package.loaded["src.render.ShaderPresets"], package.loaded["src.import.CacheFs"] = presets, cache
love.filesystem.getInfo, love.filesystem.getSource, love.event.quit = info, source, quit
T.finish("standalone GPU fixture entrypoints")
