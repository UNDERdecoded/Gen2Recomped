-- Import only the player's own verified native Substitute sheets/palette.
local M = {}
local Rom = require("src.import.RomGba")
local ImageWriter = require("src.import.ImageWriter")

local function blob(extractor, name, size)
  local off = extractor:symbol(name)
  local rom = extractor.rom
  if not off or off < 0 or off % 4 ~= 0 or off + 4 > rom.size then
    return nil, name
  end
  if rom:u8(off) ~= 0x10 or math.floor(rom:u32(off) / 256) ~= size then
    return nil, name
  end
  local ok, raw = pcall(rom.lz77, rom, off)
  if not ok or type(raw) ~= "table" or #raw ~= size then
    return nil, name
  end
  return raw, off
end

local function image(raw, colors)
  local pixels = Rom.tiles4bpp(raw, 8, 8)
  local out = ImageWriter.blank(64, 64)
  for y = 1, 64 do
    for x = 1, 64 do
      local index = pixels[y][x]
      local color = colors[index + 1]
      out:setPixel(x - 1, y - 1, color[1] / 255, color[2] / 255, color[3] / 255, index == 0 and 0 or 1)
    end
  end
  return out
end

function M.extract(extractor)
  local palette, palAt = blob(extractor, "gSubstituteDollPal", 32)
  local front, frontAt = blob(extractor, "gSubstituteDollFrontGfx", 2048)
  local back, backAt = blob(extractor, "gSubstituteDollBackGfx", 2048)
  if not palette or not front or not back then
    return nil, "missing or malformed native Substitute art"
  end
  for i = 2, 32, 2 do
    if palette[i] >= 128 then
      return nil, "invalid Substitute BGR555 palette"
    end
  end
  -- The shared native animation-pack contract carries five-bit channels in
  -- the high bits of each byte. Retain RGB even behind transparent index 0.
  local colors = {}
  for i = 1, 16 do
    local word = palette[i * 2 - 1] + palette[i * 2] * 256
    colors[i] = { word % 32 * 8, math.floor(word / 32) % 32 * 8, math.floor(word / 1024) % 32 * 8 }
  end
  local frontImage, backImage = image(front, colors), image(back, colors)
  local frontPath, backPath = "battle/substitute_front.png", "battle/substitute_back.png"
  extractor:saveImage(frontImage, frontPath)
  extractor:saveImage(backImage, backPath)
  local record = {
    version = 1,
    width = 64,
    height = 64,
    paletteEncoding = "rgb555-msb",
    front = "assets/generated/" .. frontPath,
    back = "assets/generated/" .. backPath,
    source = { palette = palAt, front = frontAt, back = backAt },
  }
  local constants = extractor._constants or {}
  constants.gen3SubstituteArt = record
  extractor._constants = constants
  extractor:write("constants", constants)
  return record
end

return M
