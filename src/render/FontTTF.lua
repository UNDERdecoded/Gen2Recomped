-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Opt-in Gen1 font record. Tile glyphs and translation-service glyphs keep
-- their existing code ranges; these codes carry Unicode through TextBox.
local T = { BASE = 0x400000,
  FILE = 'assets/fonts/plainpixel/PlainPixel-Regular.ttf', SIZE = 15 }

function T.decode(text, first)
  local b = text:byte(first)
  if not b then return nil, first end
  if b < 128 then return b, first end
  local count, cp
  if b >= 240 then count, cp = 3, b - 240
  elseif b >= 224 then count, cp = 2, b - 224
  elseif b >= 192 then count, cp = 1, b - 192
  else return nil, first end
  for i = first + 1, first + count do
    local c = text:byte(i)
    if not c or c < 128 or c > 191 then return nil, first end
    cp = cp * 64 + c - 128
  end
  return cp, first + count
end

local function character(cp)
  if cp < 128 then return string.char(cp) end
  if cp < 2048 then return string.char(192 + math.floor(cp / 64), 128 + cp % 64) end
  if cp < 65536 then return string.char(224 + math.floor(cp / 4096),
    128 + math.floor(cp / 64) % 64, 128 + cp % 64) end
  return string.char(240 + math.floor(cp / 262144), 128 + math.floor(cp / 4096) % 64,
    128 + math.floor(cp / 64) % 64, 128 + cp % 64)
end

local function tiles(spec)
  local keep = {}
  if type(spec) == 'table' then
    for _, seq in ipairs(spec) do keep[tostring(seq)] = true end
  elseif type(spec) == 'string' then
    local first = 1
    while first <= #spec do
      local _, last = T.decode(spec, first)
      keep[spec:sub(first, last)] = true
      first = last + 1
    end
  end
  return keep
end

function T.open(spec)
  if type(spec) ~= 'table' then return nil end
  local file, size = spec.file or T.FILE, spec.size or T.SIZE
  local ok, font = pcall(love.graphics.newFont, file, size, 'mono', 1)
  if not ok or not font then
    require('src.core.Logger').warn('font: could not load ttf %q (%s)', tostring(file), tostring(font))
    return nil
  end
  if font.setFilter then pcall(font.setFilter, font, 'nearest', 'nearest') end
  local offset = spec.yOffset
  if offset == nil then
    offset = font.getBaseline and (7 - font:getBaseline()) or (8 - font:getHeight())
  end
  return {font=font, tiles=tiles(spec.tiles), spacing=spec.spacing or 0,
    bold=spec.bold == true, yOffset=offset, chars={}, widths={}}
end

local function glyph(face, code)
  local ch = face.chars[code]
  if not ch then ch = character(code - T.BASE); face.chars[code] = ch end
  return ch
end

function T.advance(face, code)
  local width = face.widths[code]
  if width == nil then
    width = face.font:getWidth(glyph(face, code)) + face.spacing + (face.bold and 1 or 0)
    face.widths[code] = width
  end
  return width
end

function T.draw(face, code, x, y)
  local previous = love.graphics.getFont()
  love.graphics.setFont(face.font)
  local ch = glyph(face, code)
  love.graphics.print(ch, x, y + face.yOffset)
  if face.bold then love.graphics.print(ch, x + 1, y + face.yOffset) end
  if previous then love.graphics.setFont(previous) end
end

return T
