-- Species battle pictures: pl_pokegra.narc, and the placement bytes beside it.
--
-- WHAT THE ARCHIVE IS.  2,964 members = 494 species slots of SIX, and the six
-- are in the order pokeplatinum's own packer writes them
-- (tools/scripts/make_pl_pokegra.py, `for face in back, front / for gender in
-- female, male`):
--
--   +0 back female   +1 back male   +2 front female   +3 front male
--   +4 normal palette (NCLR)        +5 shiny palette (NCLR)
--
-- Positional, with no name table -- pl_pokegra has no `.order` file that
-- Gen4Archives could match -- so the order above is the only thing saying
-- which member is which, and it comes from the packer rather than from a
-- guess at the pattern.
--
-- THE FEMALE-ONLY TRAP, which costs sixteen species outright.  The obvious
-- read is "the male sheet is the sprite, the female sheet is the optional
-- variant".  For a female-only species the MALE SLOT IS EMPTY and the art is
-- in the female one.  Reading only +3 leaves Nidoran-f, Nidorina, Nidoqueen,
-- Chansey, Kangaskhan, Jynx, Smoochum, Miltank, Blissey, Illumise, Latias,
-- Wormadam, Vespiquen, Happiny, Froslass and Cresselia with NO PICTURE AT
-- ALL -- and not as an error, because an empty member is a legal member.
-- `Gen4Pokegra.sheet` falls back, and reports which slot it used.
--
-- THE DATA IS ENCRYPTED AND NOT TILED.  Every sheet is 20x10 "tiles" at 4bpp,
-- but the NCGR's layout flag says LINEAR BITMAP: the pixels are rows of the
-- picture, not 8x8 cells in reading order.  Reading it as tiles produces a
-- picture -- the right pixels in 8x8 blocks shuffled across the frame, which
-- looks like a palette bug rather than a layout one.  Gen4Graphics.tiles
-- already reports `bitmap`; the pixels still have to go through
-- Gen4Graphics.decryptSprite first.
--
-- 20x10 tiles is 160x80, which is TWO 80x80 FRAMES SIDE BY SIDE.  Measured
-- across the 477 species with a front sheet: 475 have two genuinely different
-- frames, 2 are identical and 2 have an empty second frame. So it is a real
-- two-frame animation, and -- this is the useful part -- a horizontal
-- two-frame strip is ALREADY the shape `picAnim` reads. Nothing is restacked.

local Gen4Pokegra = {}

local floor = math.floor
local char, concat = string.char, table.concat

Gen4Pokegra.PATH = "/poketool/pokegra/pl_pokegra.narc"
Gen4Pokegra.HEIGHT_PATH = "/poketool/pokegra/height.narc"
Gen4Pokegra.MEMBERS_PER_SPECIES = 6

-- Slot offsets within a species' six members.
Gen4Pokegra.SLOT = {
  backFemale = 0, backMale = 1, frontFemale = 2, frontMale = 3,
  normalPalette = 4, shinyPalette = 5,
}

-- The two faces, each with the slot to prefer and the slot to fall back to.
Gen4Pokegra.FACES = {
  front = { preferred = 3, fallback = 2 },
  back  = { preferred = 1, fallback = 0 },
}

-- A frame is square and half the sheet.  Stated rather than derived so a
-- member with an unexpected width is caught instead of silently halved.
Gen4Pokegra.FRAME = 80
Gen4Pokegra.FRAMES = 2

-- Colour 0 is the transparent one, the same as every other paletted sprite in
-- this cartridge.
Gen4Pokegra.TRANSPARENT = 0

function Gen4Pokegra.speciesCount(narc)
  if not narc or not narc.count then return 0 end
  return floor(narc.count / Gen4Pokegra.MEMBERS_PER_SPECIES)
end

-- sheet(narc, Gen4Graphics, species, face) -> { pixels, width, height }, slot
-- `pixels` is DECRYPTED and linear, one nibble per pixel, low nibble first.
function Gen4Pokegra.sheet(narc, Gen4Graphics, species, face)
  local spec = Gen4Pokegra.FACES[face]
  if not (narc and spec) then return nil end
  local base = species * Gen4Pokegra.MEMBERS_PER_SPECIES

  for _, slot in ipairs({ spec.preferred, spec.fallback }) do
    local member = narc:get(base + slot)
    local info = member and #member > 0 and Gen4Graphics.tiles(member)
    if info and info.tilesX and info.tilesY then
      return {
        pixels = Gen4Graphics.decryptSprite(info.pixels),
        width = info.tilesX * 8,
        height = info.tilesY * 8,
        bitmap = info.bitmap,
        bpp = info.bpp,
      }, slot
    end
  end
  return nil
end

-- The same read, at an explicit slot rather than by face.  Used for the
-- female variant, where the caller has already decided which slot it wants
-- and must not be given the fallback.
function Gen4Pokegra.sheetAt(narc, Gen4Graphics, species, slot)
  if not narc then return nil end
  local member = narc:get(species * Gen4Pokegra.MEMBERS_PER_SPECIES + slot)
  local info = member and #member > 0 and Gen4Graphics.tiles(member)
  if not (info and info.tilesX and info.tilesY) then return nil end
  return {
    pixels = Gen4Graphics.decryptSprite(info.pixels),
    width = info.tilesX * 8,
    height = info.tilesY * 8,
    bitmap = info.bitmap,
    bpp = info.bpp,
  }
end

-- Does this species have a female sheet that DIFFERS from the one used?
-- 105 of them do; the rest either repeat the male art byte for byte or have
-- no female member at all, and writing a second identical picture for 322
-- species would double the stage's output for nothing.
function Gen4Pokegra.femaleDiffers(narc, species, face)
  local spec = Gen4Pokegra.FACES[face]
  if not (narc and spec) then return false end
  local base = species * Gen4Pokegra.MEMBERS_PER_SPECIES
  local female = narc:get(base + spec.fallback)
  local male = narc:get(base + spec.preferred)
  if not female or #female == 0 or not male or #male == 0 then return false end
  return female ~= male
end

-- rgba(sheet, colours, opts) -> { width, height, rgba }
-- opts.frame  nil for the whole strip, 1 or 2 for one frame
local function paint(sheet, colours, x0, x1)
  local w, h = sheet.width, sheet.height
  local outWidth = x1 - x0 + 1
  local out, n = {}, 0
  local blank = char(0, 0, 0, 0)
  local pixels = sheet.pixels
  local byte = string.byte
  -- at most 16 colours, in thousands of pixels: each made into bytes once
  local painted, transparent = {}, Gen4Pokegra.TRANSPARENT
  for y = 0, h - 1 do
    local row = y * w
    for x = x0, x1 do
      local linear = row + x
      local b = byte(pixels, floor(linear / 2) + 1)
      local index
      if not b then index = 0
      elseif linear % 2 == 0 then index = b % 16
      else index = floor(b / 16) end
      local pixel = painted[index]
      if not pixel then
        local colour = colours and colours[index + 1]
        if index == transparent or not colour then
          pixel = blank
        else
          pixel = char(colour[1], colour[2], colour[3], 255)
        end
        painted[index] = pixel
      end
      n = n + 1
      out[n] = pixel
    end
  end
  return { width = outWidth, height = h, rgba = concat(out) }
end

function Gen4Pokegra.strip(sheet, colours)
  if not sheet then return nil end
  return paint(sheet, colours, 0, sheet.width - 1)
end

function Gen4Pokegra.frame(sheet, colours, index)
  if not sheet then return nil end
  local frameWidth = floor(sheet.width / Gen4Pokegra.FRAMES)
  local x0 = (index - 1) * frameWidth
  if x0 < 0 or x0 + frameWidth > sheet.width then return nil end
  return paint(sheet, colours, x0, x0 + frameWidth - 1)
end

-- THE PLACEMENT BYTES.  height.narc is 1,976 one-byte members -- four per
-- species, in the SAME slot order as the sheets (back female, back male,
-- front female, front male) -- and the byte is how far down the picture sits.
-- 164 of them are zero-length, which is the same "no such sheet" hole the
-- archive itself has, so a miss returns nil rather than 0: a real 0 and a
-- missing entry mean different things to whatever places the sprite.
function Gen4Pokegra.offset(heightNarc, species, slot)
  if not heightNarc then return nil end
  local member = heightNarc:get(species * 4 + slot)
  if not member or #member < 1 then return nil end
  return member:byte(1)
end

return Gen4Pokegra
