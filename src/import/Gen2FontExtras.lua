-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional GSC font records consumed by Gen1's public Font controls.
local Writer = require('src.import.ImageWriter')
local M = { REVISION = 1 }
local function read(e, name, count)
  local sym = e:symbol(name)
  if not (sym and e.rom) then return end
  local ok, raw = pcall(e.rom.bytes, e.rom, sym.bank, sym.address, count)
  if not ok or type(raw) ~= 'table' or #raw ~= count then return end
  return raw
end
local function ink(raw, width, height, bits)
  local decode = bits == 1 and Writer.decode1bpp or Writer.decode2bpp
  local source = decode(raw, width, height)
  local image = Writer.blank(width, height, 0, 0, 0, 0)
  for y = 0, height - 1 do
    for x = 0, width - 1 do
      if source:getPixel(x, y) < .5 then image:setPixel(x, y, 0, 0, 0, 1) end
    end
  end
  return image
end
function M.patchExtra(e, image)
  if e.manifest and e.manifest.fontSheets then return end
  -- LoadFontsExtra does not load FontExtra's unused bold A/B/C at $60-$62.
  -- GS uses a paired 1bpp black/up-arrow source; Crystal separates them and
  -- stores the arrow in 2bpp. Both load the Pokegear telephone at $62.
  for _, row in ipairs{
    {'FontsExtra_SolidBlackAndUpArrowGFX', 16, 16, 1, 0},
    {'FontsExtra_SolidBlackGFX', 8, 8, 1, 0},
    {'FontsExtra2_UpArrowGFX', 16, 8, 2, 8},
    {'PokegearPhoneIconGFX', 16, 8, 2, 16},
  } do
    local raw = read(e, row[1], row[2])
    if raw then Writer.blit(image, ink(raw, row[3], 8, row[4]), row[5], 0, 0, 0, row[3], 8) end
  end
end
function M.extract(e)
  local record = {}
  -- Hack manifests can change the VRAM loading program entirely (including
  -- compression and stride). Do not reinterpret their custom extra segments
  -- as the retail GSC font layout.
  if e.manifest and e.manifest.fontSheets then return record end
  local battle = read(e, 'FontBattleExtra', 32 * 16)
  if battle then
    e:saveImage(ink(battle, 128, 16, 2), 'fonts/font_battle_extra.png')
    record.imageBattleExtra = 'assets/generated/fonts/font_battle_extra.png'
  end
  -- GSC NUM_FRAMES is eight. Other cartridges keep their prior baked frame
  -- unless their manifest explicitly supplies a count for this sheet.
  local stock = e.version == 'gold' or e.version == 'silver' or e.version == 'crystal'
  local count = tonumber(e.manifest and e.manifest.fontFrameCount) or (stock and 8)
  if count and count % 1 == 0 and count >= 1 and count <= 256 then
    local frames = read(e, 'Frames', count * 6 * 8)
    if frames then
      e:saveImage(ink(frames, 48, count * 8, 1), 'fonts/frames.png')
      record.imageFrames = 'assets/generated/fonts/frames.png'
      record.frameBase, record.frameTiles, record.frameCount = 0x79, 6, count
    end
  end
  return record
end
return M
