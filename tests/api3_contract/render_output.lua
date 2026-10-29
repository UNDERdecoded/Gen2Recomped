local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/render_output%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, "render_output")
  love = love or require("tests.love_stub")
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local Runtime = require("src.mods.Runtime")
  local Output = backend == "gen2" and require("src.render.Output")
    or {
      enabled = function()
        return Runtime.wantsHook("render.output")
          and Runtime.call("render.output_enabled", function()
            return false
          end) == true
      end,
      draw = function(ctx)
        return Runtime.call("render.output", function()
          return false
        end, ctx) == true
      end,
    }
  assert(not Output.enabled())
  local ctx = {
    canvas = newproxy(true),
    width = 320,
    height = 288,
    gameX = 0,
    gameY = 0,
    gameWidth = 320,
    gameHeight = 288,
    scale = 2,
    dpiX = 1,
    dpiY = 1,
    generation = f.gen,
  }
  f.exports.state(true, true)
  assert(Output.enabled() and Output.draw(ctx))
  f.exports.state(true, false)
  assert(Output.enabled() and not Output.draw(ctx))
  f.exports.state(false, true)
  assert(not Output.enabled())
  local report = { trace = f.exports.trace(), disabled = true, fallback = true }
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
