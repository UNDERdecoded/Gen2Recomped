-- CPU image storage: actual importer pixels, without a graphics application.
local M = {}
function M.image(width, height)
  local image = { width = width, height = height, pixels = {} }
  function image:getWidth()
    return self.width
  end
  function image:getHeight()
    return self.height
  end
  function image:getDimensions()
    return self.width, self.height
  end
  function image:setPixel(x, y, r, g, b, a)
    self.pixels[y * self.width + x] = { r, g, b, a }
  end
  function image:getPixel(x, y)
    return unpack(self.pixels[y * self.width + x] or { 0, 0, 0, 0 })
  end
  function image:mapPixel(fn)
    for y = 0, self.height - 1 do
      for x = 0, self.width - 1 do
        self:setPixel(x, y, fn(x, y, self:getPixel(x, y)))
      end
    end
  end
  function image:rgba8()
    local bytes = {}
    for y = 0, self.height - 1 do
      for x = 0, self.width - 1 do
        local pixel = { self:getPixel(x, y) }
        for i = 1, 4 do
          bytes[#bytes + 1] = string.char(math.floor(pixel[i] * 255 + 0.5))
        end
      end
    end
    return table.concat(bytes)
  end
  return image
end
return M
