-- The cartridge's own text font (src/text.c sub_0805F25C / sub_0805F820).
--
-- Bank 0 of gUnk_08109248 holds 256 glyphs of 8x16 pixels, one u32 per row,
-- one nibble per pixel (low nibble first): $E is ink, $0 is the cell's
-- background, $F is outside the glyph.  A glyph's width is the run of
-- non-$F nibbles after the leading $F ones on its first row
-- (sub_0805F7A0).  USA text uses the ASCII codes 0x20-0x7E.
--
-- Built into a LÖVE ImageFont (white ink, transparent background) so the
-- text box, HUD and menus all draw with it; tint with setColor.

local Font = {}

local FIRST, LAST = 0x20, 0x7E

local function nib(blob, glyph, row, col)
  local byte = blob:byte(glyph * 64 + row * 4 + math.floor(col / 2) + 1) or 0xFF
  if col % 2 == 0 then return byte % 16 end
  return math.floor(byte / 16)
end

-- leading $F count and width, from the first row (sub_0805F7A0)
local function extent(blob, glyph)
  local lead = 0
  while lead < 8 and nib(blob, glyph, 0, lead) == 0xF do lead = lead + 1 end
  local w = 0
  while lead + w < 8 and nib(blob, glyph, 0, lead + w) ~= 0xF do w = w + 1 end
  return lead, w
end
Font.extent = extent

-- returns a love Font, or nil when the cache has no font
function Font.load(store)
  local blob = store:read("font.bin")
  if not blob or #blob < (LAST + 1) * 64 then return nil end
  local glyphs, widths, total = {}, {}, 1
  for c = FIRST, LAST do
    local lead, w = extent(blob, c)
    if c == 0x20 and w == 0 then w = 4 end
    widths[c] = { lead, math.max(w, 1) }
    total = total + widths[c][2] + 1
    glyphs[#glyphs + 1] = string.char(c)
  end
  local img = love.image.newImageData(total, 16)
  -- separator columns: an opaque colour that never appears in a glyph
  local x = 0
  local function sep()
    for y = 0, 15 do img:setPixel(x, y, 1, 0, 1, 1) end
    x = x + 1
  end
  sep()
  for c = FIRST, LAST do
    local lead, w = widths[c][1], widths[c][2]
    for col = 0, w - 1 do
      for row = 0, 15 do
        local v = nib(blob, c, row, lead + col)
        if v ~= 0 and v ~= 0xF then img:setPixel(x + col, row, 1, 1, 1, 1)
        else img:setPixel(x + col, row, 0, 0, 0, 0) end
      end
    end
    x = x + w
    sep()
  end
  local ok, font = pcall(love.graphics.newImageFont, img, table.concat(glyphs), 0)
  if not ok then return nil end
  font:setFilter("nearest", "nearest")
  return font
end

return Font
