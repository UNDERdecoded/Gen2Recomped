-- Alternate-form battle pictures: pl_otherpoke.narc.
--
-- 253 members, and the only thing in this cartridge's graphics that has no
-- pattern at all.  pokeplatinum's own build says so out loud -- `otherpoke_index
-- = {} # otherpoke uses a unique, non-uniform structure` -- and the index below
-- is that structure, read out of the per-species meson files that populate it
-- (res/pokemon/<species>/meson.build) rather than inferred from the archive.
--
-- THE SHAPE, from tools/scripts/make_pl_otherpoke.py and the 154/94 counts the
-- build passes it:
--   0..153    sprites (NCGR), 20x10 tiles at 4bpp
--   154..247  palettes (NCLR), 16 colours
--   248..250  the Substitute doll: back, front, palette
--   251..252  the in-battle shadows and their palette
-- Verified against the cartridge: every member in 0..153 IS an NCGR of that
-- shape and every member in 154..247 IS a 16-colour NCLR, 0 wrong.
--
-- WHY THIS IS A TABLE AND NOT ARITHMETIC.  Two orderings coexist inside the
-- same archive and neither announces itself:
--
--   INTERLEAVED   Deoxys, Unown, Burmy, Wormadam, Arceus, Shaymin, Rotom,
--                 Giratina -- back, front, back, front, one pair per form
--   GROUPED       Castform, Shellos, Gastrodon, Cherrim -- EVERY back, then
--                 EVERY front
--
-- Castform's four backs are 64-67 and its four fronts are 68-71.  Read as
-- interleaved, Castform-sunny's "back" is Castform-rainy's back and its
-- "front" is Castform-base's front: four plausible pictures, all of the wrong
-- forms, and nothing anywhere reports an error.  The palettes split the same
-- way -- Castform and Cherrim group normal-then-shiny while everyone else
-- alternates -- so the same guess also hands sunny Castform snowy's colours.
--
-- THIRTY FORMS HAVE NO PALETTE OF THEIR OWN.  Deoxys's three alternate formes
-- and Unown's twenty-seven letters are recoloured from their species' BASE
-- palette; only their sheets differ.  `palette` is nil for those, and
-- `Gen4Otherpoke.palettes` falls back to the base form's rather than leaving
-- them black.
--
-- THE EGG IS NOT A POKEMON HERE.  Members 132/133 are the ordinary egg and the
-- Manaphy egg: a front picture and a normal palette each, no back and no shiny,
-- because an egg is never sent out and never sparkles.  `species = 0` marks
-- them as belonging to no species row.
--
-- Every `base` form duplicates what pl_pokegra already holds for that species.
-- That is the cartridge's doing, not a mistake here: the form-switching code
-- reads one archive rather than two, so the base art is in both.

local Gen4Otherpoke = {}

Gen4Otherpoke.PATH = "/poketool/pokegra/pl_otherpoke.narc"

Gen4Otherpoke.SPRITE_MEMBERS = 154
Gen4Otherpoke.PALETTE_MEMBERS = 94

-- The five-member tail the packer appends after the indexed block.
Gen4Otherpoke.SUBSTITUTE = { back = 248, front = 249, palette = 250 }
Gen4Otherpoke.SHADOWS = { sheet = 251, palette = 252 }

-- One row per (species, form), in archive order.  `palette`/`shiny` nil means
-- "use the species' base form's".
Gen4Otherpoke.FORMS = {
  { species = 386, name = "deoxys", form = "base", back = 0, front = 1, palette = 154, shiny = 155 },
  { species = 386, name = "deoxys", form = "attack", back = 2, front = 3, palette = nil, shiny = nil },
  { species = 386, name = "deoxys", form = "defense", back = 4, front = 5, palette = nil, shiny = nil },
  { species = 386, name = "deoxys", form = "speed", back = 6, front = 7, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "base", back = 8, front = 9, palette = 156, shiny = 157 },
  { species = 201, name = "unown", form = "b", back = 10, front = 11, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "c", back = 12, front = 13, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "d", back = 14, front = 15, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "e", back = 16, front = 17, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "f", back = 18, front = 19, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "g", back = 20, front = 21, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "h", back = 22, front = 23, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "i", back = 24, front = 25, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "j", back = 26, front = 27, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "k", back = 28, front = 29, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "l", back = 30, front = 31, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "m", back = 32, front = 33, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "n", back = 34, front = 35, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "o", back = 36, front = 37, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "p", back = 38, front = 39, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "q", back = 40, front = 41, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "r", back = 42, front = 43, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "s", back = 44, front = 45, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "t", back = 46, front = 47, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "u", back = 48, front = 49, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "v", back = 50, front = 51, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "w", back = 52, front = 53, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "x", back = 54, front = 55, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "y", back = 56, front = 57, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "z", back = 58, front = 59, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "exc", back = 60, front = 61, palette = nil, shiny = nil },
  { species = 201, name = "unown", form = "que", back = 62, front = 63, palette = nil, shiny = nil },
  { species = 351, name = "castform", form = "base", back = 64, front = 68, palette = 158, shiny = 162 },
  { species = 351, name = "castform", form = "sunny", back = 65, front = 69, palette = 159, shiny = 163 },
  { species = 351, name = "castform", form = "rainy", back = 66, front = 70, palette = 160, shiny = 164 },
  { species = 351, name = "castform", form = "snowy", back = 67, front = 71, palette = 161, shiny = 165 },
  { species = 412, name = "burmy", form = "base", back = 72, front = 73, palette = 166, shiny = 167 },
  { species = 412, name = "burmy", form = "sandy", back = 74, front = 75, palette = 168, shiny = 169 },
  { species = 412, name = "burmy", form = "trash", back = 76, front = 77, palette = 170, shiny = 171 },
  { species = 413, name = "wormadam", form = "base", back = 78, front = 79, palette = 172, shiny = 173 },
  { species = 413, name = "wormadam", form = "sandy", back = 80, front = 81, palette = 174, shiny = 175 },
  { species = 413, name = "wormadam", form = "trash", back = 82, front = 83, palette = 176, shiny = 177 },
  { species = 422, name = "shellos", form = "base", back = 84, front = 86, palette = 178, shiny = 179 },
  { species = 422, name = "shellos", form = "east_sea", back = 85, front = 87, palette = 180, shiny = 181 },
  { species = 423, name = "gastrodon", form = "base", back = 88, front = 90, palette = 182, shiny = 183 },
  { species = 423, name = "gastrodon", form = "east_sea", back = 89, front = 91, palette = 184, shiny = 185 },
  { species = 421, name = "cherrim", form = "base", back = 92, front = 94, palette = 186, shiny = 188 },
  { species = 421, name = "cherrim", form = "sunny", back = 93, front = 95, palette = 187, shiny = 189 },
  { species = 493, name = "arceus", form = "base", back = 96, front = 97, palette = 190, shiny = 191 },
  { species = 493, name = "arceus", form = "fighting", back = 98, front = 99, palette = 192, shiny = 193 },
  { species = 493, name = "arceus", form = "flying", back = 100, front = 101, palette = 194, shiny = 195 },
  { species = 493, name = "arceus", form = "poison", back = 102, front = 103, palette = 196, shiny = 197 },
  { species = 493, name = "arceus", form = "ground", back = 104, front = 105, palette = 198, shiny = 199 },
  { species = 493, name = "arceus", form = "rock", back = 106, front = 107, palette = 200, shiny = 201 },
  { species = 493, name = "arceus", form = "bug", back = 108, front = 109, palette = 202, shiny = 203 },
  { species = 493, name = "arceus", form = "ghost", back = 110, front = 111, palette = 204, shiny = 205 },
  { species = 493, name = "arceus", form = "steel", back = 112, front = 113, palette = 206, shiny = 207 },
  { species = 493, name = "arceus", form = "mystery", back = 114, front = 115, palette = 208, shiny = 209 },
  { species = 493, name = "arceus", form = "fire", back = 116, front = 117, palette = 210, shiny = 211 },
  { species = 493, name = "arceus", form = "water", back = 118, front = 119, palette = 212, shiny = 213 },
  { species = 493, name = "arceus", form = "grass", back = 120, front = 121, palette = 214, shiny = 215 },
  { species = 493, name = "arceus", form = "electric", back = 122, front = 123, palette = 216, shiny = 217 },
  { species = 493, name = "arceus", form = "psychic", back = 124, front = 125, palette = 218, shiny = 219 },
  { species = 493, name = "arceus", form = "ice", back = 126, front = 127, palette = 220, shiny = 221 },
  { species = 493, name = "arceus", form = "dragon", back = 128, front = 129, palette = 222, shiny = 223 },
  { species = 493, name = "arceus", form = "dark", back = 130, front = 131, palette = 224, shiny = 225 },
  { species =   0, name = "egg", form = "base", back = nil, front = 132, palette = 226, shiny = nil },
  { species =   0, name = "egg", form = "manaphy", back = nil, front = 133, palette = 227, shiny = nil },
  { species = 492, name = "shaymin", form = "base", back = 134, front = 135, palette = 228, shiny = 229 },
  { species = 492, name = "shaymin", form = "sky", back = 136, front = 137, palette = 230, shiny = 231 },
  { species = 479, name = "rotom", form = "base", back = 138, front = 139, palette = 232, shiny = 233 },
  { species = 479, name = "rotom", form = "heat", back = 140, front = 141, palette = 234, shiny = 235 },
  { species = 479, name = "rotom", form = "wash", back = 142, front = 143, palette = 236, shiny = 237 },
  { species = 479, name = "rotom", form = "frost", back = 144, front = 145, palette = 238, shiny = 239 },
  { species = 479, name = "rotom", form = "fan", back = 146, front = 147, palette = 240, shiny = 241 },
  { species = 479, name = "rotom", form = "mow", back = 148, front = 149, palette = 242, shiny = 243 },
  { species = 487, name = "giratina", form = "base", back = 150, front = 151, palette = 244, shiny = 245 },
  { species = 487, name = "giratina", form = "origin", back = 152, front = 153, palette = 246, shiny = 247 },
}

-- forms(speciesId) -> the rows for one species, in archive order.
function Gen4Otherpoke.forms(species)
  local out = {}
  for _, row in ipairs(Gen4Otherpoke.FORMS) do
    if row.species == species then out[#out + 1] = row end
  end
  return out
end

-- base(name) -> the row every palette-less form of this species borrows from.
function Gen4Otherpoke.base(name)
  for _, row in ipairs(Gen4Otherpoke.FORMS) do
    if row.name == name and row.form == "base" then return row end
  end
  return nil
end

-- palettes(row) -> normalMember, shinyMember, borrowed
-- `borrowed` is true when the numbers came from the base form rather than from
-- this row, so a caller can say so rather than implying the form has its own.
function Gen4Otherpoke.palettes(row)
  if not row then return nil end
  if row.palette then return row.palette, row.shiny, false end
  local base = Gen4Otherpoke.base(row.name)
  if not base then return nil end
  return base.palette, base.shiny, true
end

-- key(row) -> the stable name a cache entry and an override path use.
-- Species id first for the same reason the base pictures carry it: it sorts,
-- it cannot collide, and it stays right if a form is ever renamed.
function Gen4Otherpoke.key(row)
  return ("%03d_%s_%s"):format(row.species, row.name, row.form)
end

-- HEARTGOLD / SOULSILVER'S OTHERPOKE (/a/1/1/4) IS NOT PLATINUM'S LAYOUT.
-- READ FROM pokeheartgold files/poketool/pokegra/otherpoke/*/meson.build:
-- the sheets 0..153 are the same, then Pichu's four (154 normal back, 155
-- normal front, 156 Spiky-eared back, 157 Spiky-eared front); so every
-- palette moves up by four (Deoxys 158/159 where Platinum has 154/155,
-- Castform 162.., Giratina-Origin 250/251), Pichu's palettes are 252..255
-- (normal / shiny of each form), the Substitute doll 256 back, 257 front,
-- 258 palette, and the shadows 259 / 260. Reading Platinum's numbers out of
-- it took NCGRs for palettes: no Unown letter or Deoxys forme was written
-- and Castform, Burmy, Rotom & co. came out in other forms' colours.
-- (revision tag hgss-otherpoke-v1)
Gen4Otherpoke.HGSS_PICHU = {
  { species = 172, name = "pichu", form = "base", back = 154, front = 155, palette = 252, shiny = 253 },
  { species = 172, name = "pichu", form = "spiky", back = 156, front = 157, palette = 254, shiny = 255 },
}

-- layout(family) -> rows, substitute, shadows for that cartridge family
function Gen4Otherpoke.layout(family)
  if family ~= "hgss" then
    return Gen4Otherpoke.FORMS, Gen4Otherpoke.SUBSTITUTE, Gen4Otherpoke.SHADOWS
  end
  local rows = {}
  for _, row in ipairs(Gen4Otherpoke.FORMS) do
    local r = {}
    for k, v in pairs(row) do r[k] = v end
    if r.palette then r.palette = r.palette + 4 end
    if r.shiny then r.shiny = r.shiny + 4 end
    rows[#rows + 1] = r
  end
  for _, row in ipairs(Gen4Otherpoke.HGSS_PICHU) do rows[#rows + 1] = row end
  return rows, { back = 256, front = 257, palette = 258 }, { sheet = 259, palette = 260 }
end

-- palettesIn(rows, row): palettes() over a layout's own rows
function Gen4Otherpoke.palettesIn(rows, row)
  if not row then return nil end
  if row.palette then return row.palette, row.shiny, false end
  for _, b in ipairs(rows) do
    if b.name == row.name and b.form == "base" then return b.palette, b.shiny, true end
  end
  return nil
end

return Gen4Otherpoke
