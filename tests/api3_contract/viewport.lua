local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/viewport%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, "viewport")
  love = love or require("tests.love_stub")
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local V = require("src.render.GameViewport")
  local Game = require(backend == "gen1" and f.gen > 1 and ("src.core.Game" .. f.gen) or "src.core.Game")
  local G = love.graphics
  local dims, pixels = G.getDimensions, G.getPixelDimensions
  G.getDimensions = function()
    return 640, 480
  end
  G.getPixelDimensions = function()
    return 1280, 960
  end
  f.exports.request({ x = 100, y = 20, width = 320, height = 288 })
  local r = V.begin(f.gen)
  assert(V.active() and r.x == 100 and r.y == 20 and r.width == 320 and r.height == 288)
  assert(select(1, V.dimensions()) == 320)
  assert(select(1, V.pixelDimensions()) == 640)
  local x, y, inside = V.toLocal(132, 52)
  assert(x == 32 and y == 32 and inside)
  x, y, inside = V.toLocal(99, 19)
  assert(x == -1 and y == -1 and not inside)
  f.exports.canvas(V.target())
  Game.pointerEvent(f.game, "pressed", "mouse", "mouse", 132, 52, 0, 0, nil, 1)
  Game.pointerEvent(f.game, "moved", "mouse", "mouse", 99, 19, -33, -33, nil, 1)
  V.finish(f.game)
  f.exports.request({ capture = true })
  V.begin(f.gen)
  assert(V.active() and select(1, V.dimensions()) == 640)
  f.exports.canvas(V.target())
  V.finish(f.game)
  f.exports.request(nil)
  V.begin(f.gen)
  assert(not V.active())
  V.finish(f.game)
  local report = f.exports.trace()
  G.getDimensions, G.getPixelDimensions = dims, pixels
  V.reset()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
