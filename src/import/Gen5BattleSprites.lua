-- BLACK AND WHITE'S POKEMON BATTLE PICTURES (/a/0/0/4, the pokegra archive).
--
-- Twenty members a species, from species 0 (the "?" picture) at member 0:
--
--   +0  front, 96 x 96 (LZ11 RGCN, 144 tiles)     +1  female front (or empty)
--   +2  front animation parts (128 x 256)          +3  female parts (or empty)
--   +4  RECN cells   +5 RNAN   +6 RCMN   +7 RAMN   +8 the animation script
--   +9  back, 96 x 96                              +10 female back (or empty)
--   +11 back parts   +12 female back parts         +13..+17 the back's cells
--   +18 normal palette (RLCN)                      +19 shiny palette
--
-- The 96 x 96 still is 1D-mapped for four OAM blocks -- 64x64 at (0, 0),
-- 32x64 at (64, 0), 64x32 at (0, 64), 32x32 at (64, 64) -- 64 + 32 + 32 + 16
-- = 144 tiles, which is what every member decodes to. Read row-major instead
-- the picture comes out as the four blocks laid in a strip.
--
-- THE OTHER FORMS (gen5-form-sprites-v1). After species 649 the archive keeps
-- one more 20-member slot per alternate-form picture: slot 652 + k (650 / 651
-- are the Eggs). READ: the
-- personal record's +0x1E (`formSpriteIndex`) is the species' first k and
-- +0x20 (`formCount`) its form count (Black: Unown 0 x 27, Castform 27,
-- Deoxys 30, Burmy 33, Wormadam 35, Cherrim 37, Shellos 38, Gastrodon 39,
-- Rotom 40, Giratina 45, Shaymin 46, Basculin 47, Darmanitan 48, Deerling 49,
-- Sawsbuck 52, Meloetta 55 = slots 652..707), so form f (1..count-1) is slot
-- 652 + index + f - 1. Index 0 belongs to Unown alone (Arceus also reads 0
-- with 17 forms: its types are palettes, not pictures -- see below.
-- Genesect's Drives (index 56) are ordinary slots 708-711: the same picture
-- with the Douse / Shock / Burn / Chill palettes, written by the loop).
-- Each form is written like a species
-- (front / back / shiny pair, its MCSS animation bundle) as
-- rec.forms[f] / def.gen5FormSprites[f], read by Sprites.path and
-- Gen5MonAnimPlayer through the mon's `form`.
--
-- Written under the same keys Platinum's species stage stamps on a species
-- row (spriteFront, spriteBack, spriteShiny, spriteShinyBack, plus the female
-- pair), so the battle screen and every other reader of Sprites.path draw a
-- Unova Pokemon without knowing which cartridge it came from.

local B = {}

B.PATH = "/a/0/0/4"
B.STRIDE = 20
B.SPECIES = 649
B.SIZE = 96
-- the first alternate-form slot: 650 and 651 hold the two Eggs (checked by
-- composing slots 650.. against each species' own pictures)
B.FORM_SLOT = 652
B.ARCEUS, B.ARCEUS_PALETTES = 493, 14253
B.BLOCKS = { { 0, 0, 8, 8 }, { 8, 0, 4, 8 }, { 0, 8, 8, 4 }, { 8, 8, 4, 4 } }

local function cellsFor()
  local grid, t = {}, 0
  for _, bl in ipairs(B.BLOCKS) do
    for ty = 0, bl[4] - 1 do
      for tx = 0, bl[3] - 1 do
        grid[(bl[2] + ty) * 12 + bl[1] + tx + 1] = { tile = t, palette = 0 }
        t = t + 1
      end
    end
  end
  return { width = B.SIZE, height = B.SIZE, cells = grid }
end

-- build(x) -> report; stamps x._pokemon and writes gen4_species_sprites
function B.build(x)
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local raw = x.rom:read(B.PATH)
  local arc = raw and require("src.import.NarcArchive").parse(raw)
  if not arc then return { error = "no " .. B.PATH } end
  local function member(i)
    local b = arc:get(i)
    if not b or #b == 0 then return nil end
    if Lz.isCompressed(b) then b = Lz.decompress(b) end
    return b
  end
  local map = cellsFor()
  local mons = x._pokemon or {}
  local index = { species = {}, counts = { images = 0, missing = 0, female = 0, animations=0, animationErrors=0 } }
  local Anim=require("src.import.Gen5MonAnim")
  local function slug(id)
    local def = mons[id]
    local name = def and def.name or ("species_%03d"):format(id)
    return ("%03d_%s"):format(id, tostring(name):lower():gsub("[^%w]+", "_"))
  end
  local function save(rel, sheetBytes, palette)
    local sheet = sheetBytes and G.tiles(sheetBytes)
    if not (sheet and palette) then return nil end
    local image = G.compose(map, sheet, palette)
    local entry = image and x:saveImage("battle/" .. rel, image)
    if entry then index.counts.images = index.counts.images + 1 end
    -- the lowest row with a pixel in it: where the Pokemon's feet are, which
    -- is the point the battle stands on its platform in the 3D field
    local feet
    if image then
      for y = B.SIZE - 1, 0, -1 do
        local row = image.rgba:sub(y * B.SIZE * 4 + 1, (y + 1) * B.SIZE * 4)
        for px = 4, #row, 4 do
          if row:byte(px) > 0 then feet = y + 1 break end
        end
        if feet then break end
      end
    end
    return entry and entry.path, feet
  end
  for id = 1, B.SPECIES do
    local base = id * B.STRIDE
    local normal = G.palette(member(base + 18))
    local shiny = G.palette(member(base + 19))
    local name = slug(id)
    local rec = { feet = {} }
    rec.front, rec.feet.front = save("front/" .. name, member(base + 0), normal)
    rec.back, rec.feet.back = save("back/" .. name, member(base + 9), normal)
    local more = {
      shiny_front = save("shiny_front/" .. name, member(base + 0), shiny),
      shiny_back = save("shiny_back/" .. name, member(base + 9), shiny),
    }
    for k, v in pairs(more) do rec[k] = v end
    local femaleFront = member(base + 1)
    if femaleFront then
      rec.female_front = save("female_front/" .. name, femaleFront, normal)
      rec.female_back = save("female_back/" .. name, member(base + 10), normal)
      rec.female_shiny_front = save("female_shiny_front/" .. name, femaleFront, shiny)
      rec.female_shiny_back = save("female_shiny_back/" .. name, member(base + 10), shiny)
      index.counts.female = index.counts.female + 1
    end
    if not rec.front then index.counts.missing = index.counts.missing + 1 end
    index.species[id] = rec
    local def = mons[id]
    if def then
      def.spriteFront, def.spriteBack = rec.front, rec.back
      def.spriteShiny, def.spriteShinyBack = rec.shiny_front, rec.shiny_back
      def.spriteFemaleFront, def.spriteFemaleBack = rec.female_front, rec.female_back
      def.battleSpriteSize = B.SIZE
      local front,frontError=Anim.load(arc,id,"front")
      local back,backError=Anim.load(arc,id,"back")
      if front and back then
        local path=x:saveBinary(("battle/mcss/%03d.bin"):format(id),Anim.pack(arc,id))
        def.gen5Animation={path=path,species=id}
        rec.animation=def.gen5Animation
        index.counts.animations=index.counts.animations+2
      else
        index.counts.animationErrors=index.counts.animationErrors+1
        rec.animationError=frontError or backError
      end
    end
    -- the other forms (see the header)
    if def and (tonumber(def.formCount) or 0) > 1 and ((tonumber(def.formSpriteIndex) or 0) > 0 or id == 201) then
      rec.forms = {}
      for f = 1, def.formCount - 1 do
        local slot = B.FORM_SLOT + def.formSpriteIndex + f - 1
        local sb = slot * B.STRIDE
        if member(sb + 0) then
          local fn, fs = G.palette(member(sb + 18)), G.palette(member(sb + 19))
          local fname = ("%s_f%d"):format(name, f)
          local fr = { feet = {} }
          fr.front, fr.feet.front = save("front/" .. fname, member(sb + 0), fn)
          fr.back, fr.feet.back = save("back/" .. fname, member(sb + 9), fn)
          fr.shiny_front = save("shiny_front/" .. fname, member(sb + 0), fs)
          fr.shiny_back = save("shiny_back/" .. fname, member(sb + 9), fs)
          if Anim.load(arc, slot, "front") and Anim.load(arc, slot, "back") then
            local path = x:saveBinary(("battle/mcss/%03d_f%d.bin"):format(id, f), Anim.pack(arc, slot))
            fr.animation = { path = path, species = slot }
          end
          rec.forms[f] = fr
          index.counts.forms = (index.counts.forms or 0) + 1
        end
      end
      def.gen5FormSprites = rec.forms
    end
    -- ARCEUS's types are palettes, not pictures: the base sheets in the pair
    -- at B.ARCEUS_PALETTES + 2 (f - 1) (normal) / + 1 (shiny), f = 1..16 the
    -- forms after Normal (INFERRED from the colours: Fighting's browns first,
    -- then Flying's blues; the archive's last 32 members)
    if id == B.ARCEUS and def then
      rec.forms = {}
      for f = 1, 16 do
        local pn = member(B.ARCEUS_PALETTES + 2 * (f - 1))
        local ps = member(B.ARCEUS_PALETTES + 2 * (f - 1) + 1)
        local fn, fs = pn and G.palette(pn), ps and G.palette(ps)
        if fn and fs then
          local fname = ("%s_f%d"):format(name, f)
          local fr = { feet = {} }
          fr.front, fr.feet.front = save("front/" .. fname, member(base + 0), fn)
          fr.back, fr.feet.back = save("back/" .. fname, member(base + 9), fn)
          fr.shiny_front = save("shiny_front/" .. fname, member(base + 0), fs)
          fr.shiny_back = save("shiny_back/" .. fname, member(base + 9), fs)
          if rec.animation then
            -- the species' own bundle with this form's two palettes
            local shim = { count = arc.count, get = function(_, i)
              if i == base + 18 then return arc:get(B.ARCEUS_PALETTES + 2 * (f - 1)) end
              if i == base + 19 then return arc:get(B.ARCEUS_PALETTES + 2 * (f - 1) + 1) end
              return arc:get(i)
            end }
            local path = x:saveBinary(("battle/mcss/%03d_f%d.bin"):format(id, f), Anim.pack(shim, id))
            fr.animation = { path = path, species = id }
          end
          rec.forms[f] = fr
          index.counts.forms = (index.counts.forms or 0) + 1
        end
      end
      def.gen5FormSprites = rec.forms
    end
    if x.tick then x:tick("battle_sprites", id, B.SPECIES) end
  end
  index.size = B.SIZE
  index.source = ("ROM:%s (%d a species; front +0, back +9, palettes +18 / +19)"):format(B.PATH, B.STRIDE)
  return index
end

return B
