package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Extractor = require("src.import.RomExtractorGen3")
local Rom = require("src.import.RomGba")
local previous = love.image
love.image = {}
local pixels
love.image.newImageData = function(w, h)
  pixels = { w = w, h = h }
  return {
    setPixel = function(_, x, y, ...)
      pixels[y * w + x] = { ... }
    end,
    mapPixel = function(self, fn)
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          self:setPixel(x, y, fn(x, y, 0, 0, 0, 0))
        end
      end
    end,
  }
end
local extractor = setmetatable({
  saveImage = function(_, image, path)
    T.eq(path, "battle/hud/caught.png", "native marker has a dedicated cache asset")
  end,
}, { __index = Extractor })
local elements = {}
for i = 1, 71 * 32 do
  elements[i] = 0
end
-- Tile 69 differs deliberately; decoding its neighbor would fail every pixel.
for i = 69 * 32 + 1, 70 * 32 do
  elements[i] = 0x33
end
for i = 70 * 32 + 1, 71 * 32 do
  elements[i] = i % 2 == 0 and 0x21 or 0x10
end
local encoded = {}
for i, byte in ipairs(elements) do
  encoded[i] = string.char(byte)
end
local offset = 37
extractor.rom = Rom.new(string.rep(string.char(255), offset) .. table.concat(encoded))
local before = extractor.rom:bytes(offset, 66 * 32)
T.eq(#before, 66 * 32, "normal bar/status scan retains its original 66 tiles")
local palette = { { 0, 0, 0 }, { 255, 0, 0 }, { 0, 255, 0 }, { 0, 0, 255 } }
T.eq(
  extractor:battleCaughtMarker(offset, palette),
  "assets/generated/battle/hud/caught.png",
  "import publishes tile 70 path"
)
T.eq(pixels.w, 8, "native caught marker is eight pixels wide")
T.eq(pixels.h, 8, "native caught marker is eight pixels high")
for y = 0, 7 do
  for x = 0, 7 do
    local value = pixels[y * 8 + x]
    local byte = elements[70 * 32 + y * 4 + math.floor(x / 2) + 1]
    local index = x % 2 == 0 and byte % 16 or math.floor(byte / 16)
    local expected = palette[index + 1]
    T.eq(value[4], index == 0 and 0 or 1, "4bpp zero remains transparent")
    if index > 0 then
      for channel = 1, 3 do
        T.eq(value[channel], expected[channel] / 255, "native tile/palette channel")
      end
    end
  end
end
T.same(extractor.rom:bytes(offset, 66 * 32), before, "marker import does not alter the bar/status scan")
extractor.rom = Rom.new(string.rep(string.char(0), offset + 66 * 32))
T.eq(extractor:battleCaughtMarker(offset, palette), nil, "short optional sheet refuses an out-of-ROM tail")
T.eq(extractor:battleCaughtMarker(-1, palette), nil, "invalid element offset is refused")
love.image = previous
T.finish("native caught-marker 4bpp import")
