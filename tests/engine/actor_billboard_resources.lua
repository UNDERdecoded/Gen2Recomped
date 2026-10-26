package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local f = dofile("tests/actor_render/fixture.lua").new(".", "emerald", 2)
local new = assert(f.result.loader.exports.actor_reference.new)
local stats = { images = 0, quads = 0, releasedImages = 0, releasedQuads = 0, draws = 0 }
local function object(kind)
  local o = {}
  function o:release()
    assert(not self.released, "double release")
    self.released = true
    stats["released" .. kind] = stats["released" .. kind] + 1
  end
  function o:setFilter() end
  return o
end
love.filesystem.newFileData = function(bytes)
  return { bytes = bytes, release = function() end }
end
love.image = {
  newImageData = function(file)
    local function be(at)
      local a, b, c, d = file.bytes:byte(at, at + 3)
      return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return {
      getDimensions = function()
        return be(17), be(21)
      end,
      release = function() end,
    }
  end,
}
love.graphics.newImage = function()
  stats.images = stats.images + 1
  return object("Images")
end
love.graphics.newQuad = function()
  stats.quads = stats.quads + 1
  return object("Quads")
end
love.graphics.draw = function(image, quad)
  assert(not image.released and not quad.released)
  stats.draws = stats.draws + 1
end
local pass = assert(new(f.data))
local frame = { mapId = "A", camera = { x = -64, y = 0 }, viewWidth = 200, viewHeight = 128 }
local actors = assert(pass:prepare(frame))
T.eq(#actors, 4, "visible players/NPCs/ghosts")
T.eq(stats.images, 1, "one source shared by four actors")
T.eq(stats.quads, 9, "quads prepared once")
pass:draw(actors)
T.eq(stats.draws, 4, "draw all visible actors")
assert(pass:prepare(frame))
T.eq(stats.images, 1, "identical PNG reuses images")
local file = assert(io.open(f.walk.def.image, "rb"))
local bytes = file:read("*a")
file:close()
f.files[f.walk.def.image] = bytes .. "\0"
assert(pass:prepare(frame))
T.eq(stats.images, 2, "changed source bytes rebuild same ID")
T.eq(stats.releasedImages, 1, "old image released")
T.eq(stats.releasedQuads, 9, "old quads released")
frame.camera.x = 500
T.eq(#assert(pass:prepare(frame)), 0, "culling")
T.eq(stats.images, stats.releasedImages, "offscreen resources released")
T.eq(stats.quads, stats.releasedQuads, "offscreen quads released")
frame.camera.x = -64
local newImage = love.graphics.newImage
love.graphics.newImage = function()
  error("allocation failed")
end
T.eq(pass:prepare(frame), nil, "image allocation failure declines")
T.eq(next(pass.sheets), nil, "failed construction retains no resources")
love.graphics.newImage = newImage
local newQuad = love.graphics.newQuad
love.graphics.newQuad = function()
  error("quad allocation failed")
end
T.eq(pass:prepare(frame), nil, "quad failure declines")
T.eq(stats.images, stats.releasedImages, "partially constructed image released")
love.graphics.newQuad = newQuad
assert(pass:prepare(frame))
f.world.map.id = "B"
T.eq(pass:prepare(frame), nil, "warp prevents stale billboard scene")
T.eq(stats.images, stats.releasedImages, "warp releases images")
T.eq(stats.quads, stats.releasedQuads, "warp releases quads")
pass:invalidate()
pass:invalidate()
T.eq(stats.images, stats.releasedImages, "cleanup is idempotent")
T.finish("Portable actor billboard resources")
