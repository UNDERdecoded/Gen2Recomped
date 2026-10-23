-- Resource accounting only. Pixel correctness is covered by the native GPU tool.
local M = {}
function M.install()
  local g = love.graphics
  local stats = {
    images = 0,
    quads = 0,
    canvases = 0,
    releasedImages = 0,
    releasedQuads = 0,
    releasedCanvases = 0,
    draws = {},
  }
  local function object(kind, w, h)
    local row = { w = w, h = h }
    function row:getWidth()
      assert(not self.released)
      return self.w
    end
    function row:getHeight()
      assert(not self.released)
      return self.h
    end
    function row:getDimensions()
      return self:getWidth(), self:getHeight()
    end
    function row:typeOf(name)
      return name == kind
    end
    function row:setFilter() end
    function row:release()
      assert(not self.released, "double release")
      self.released = true
      local key = kind == "Image" and "releasedImages"
        or kind == "Canvas" and "releasedCanvases"
        or "releasedQuads"
      stats[key] = stats[key] + 1
    end
    return row
  end
  love.image = {
    newImageData = function(w, h, format, bytes)
      assert(format == "rgba8" and #bytes == w * h * 4, "RGBA atlas length")
      return { w = w, h = h, bytes = bytes, release = function() end }
    end,
  }
  g.newImage = function(data)
    local row = object("Image", data.w, data.h)
    stats.images = stats.images + 1
    local checksum = 0
    for i = 1, #data.bytes do
      checksum = (checksum + data.bytes:byte(i) * (i % 131 + 1)) % 2147483647
    end
    row.checksum = checksum
    return row
  end
  g.newCanvas = function(w, h)
    stats.canvases = stats.canvases + 1
    return object("Canvas", w, h)
  end
  g.newQuad = function(x, y, w, h)
    stats.quads = stats.quads + 1
    local q = object("Quad", w, h)
    q.x, q.y = x, y
    return q
  end
  g.getSystemLimits = function()
    return { texturesize = 8192 }
  end
  g.setDepthMode = function() end
  g.draw = function(image, quad, x, y)
    assert(not image.released and not quad.released, "drawing released graphics")
    stats.draws[#stats.draws + 1] = { image.checksum, quad.x, quad.y, x, y }
  end
  return stats
end
return M
