-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SLOT MACHINE ART (overlay 101; pokeplatinum src/overlay101/*.c)
-- -> `gen4_pt_slot_art`, drawn by src/ui/PtSlotMachineApp.lua.
--
-- /data/slot.narc (NARC_INDEX_DATA__SLOT), 77 members, read the way the app
-- reads them (READ FROM CODE):
--   ov101_021D121C   main BG1  chars 0 / map 1   (the cabinet, stop buttons)
--                    main BG2  chars 8 / map 9   (the reel glass, blended
--                              over the reels: G2_SetBlendAlpha BG2/OBJ 8/9)
--                    sub  BG3  chars 2 / map 4   (the Poke Ball panel)
--                    palette 3, 13 rows, to both engines' BG palettes
--   ov101_021D4D38   the lamp / panel palette fades: palette 3 rows 1..4,
--                    members 5 / 6 / 7 row 0 (sub BG row 1's bonus colour and
--                    its two flashes), members 74 / 75 / 76 row 0 (the five
--                    pay-line lamps lit)
--   ov101_021D15BC   OBJ resource sets {char, pal, cell, anim}: 0 the reel
--                    symbols {11, 10, 12, 13}; 1 the credit / payout digits
--                    {21, 20, 22, 23}; 6 / 7 / 8 / 9 the bottom screen's
--                    bonus counters
--   ov101_021D630C   the hint ball, one look per role (Unk_ov101_021D93D4)
--   ov101_021D65F4   the sparkle {44, 47, 45, 46}
--   ov101_021D66D0   Clefairy's three looks (Unk_ov101_021D93A4)
--   ov101_021D6D68   the two-sided burst {56, 59, 57, 58}
--   ov101_021D7D94   the winning-line marks: {14, -, 15, 16} for the red 7,
--                    {17, -, 18, 19} for the rest, on palette 10
--
-- BACKGROUNDS ARE STORED AS INDEX PICTURES so the app can run the cartridge's
-- palette fades (the lamps, Bg_ChangeTilemapRectPalette on the stop buttons,
-- the bottom panel's bonus colour): each opaque pixel's RED is its colour
-- index x 17 and its GREEN its palette row x 17; the app looks the colour up
-- in the palette it keeps. Sprites are plain pictures on their palette's row
-- the OAM entry names (every cell bank here uses row 0).

local S = {}

S.PATH = "/data/slot.narc"

-- every OBJ group the app draws: name -> { char, pal, cell, anim }
S.GROUPS = {
  reel = { 11, 10, 12, 13 },
  credit = { 21, 20, 22, 23 },
  ball0 = { 24, 27, 25, 26 }, ball1 = { 28, 31, 29, 30 }, ball2 = { 32, 35, 33, 34 },
  ball3 = { 36, 39, 37, 38 }, ball4 = { 40, 43, 41, 42 },
  sparkle = { 44, 47, 45, 46 },
  clefairy0 = { 48, 51, 49, 50 }, clefairy1 = { 52, 51, 53, 54 }, clefairy2 = { 48, 55, 49, 50 },
  burst = { 56, 59, 57, 58 },
  bonusLabel = { 68, 67, 69, 70 },            -- set 6 (ov101_021D7228 / 72D4)
  gamesLabel = { 71, 67, 72, 73 },            -- char 7 / pal 6 (ov101_021D73EC / 74A0)
  digits = { 64, 67, 65, 66 },                -- set 8, pal 6 (ov101_021D7588 / 76EC / 7810)
  bigDigits = { 60, 63, 61, 62 },             -- set 9, pal 7 (ov101_021D7A00)
  line7 = { 14, 10, 15, 16 },                 -- set 10 on pal 0 (ov101_021D7BB4)
  lineOther = { 17, 10, 18, 19 },
}

local function opener(rom)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom and rom:read(S.PATH)
  local narc = bytes and require("src.import.NarcArchive").parse(bytes)
  if not narc then return nil end
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function rows(G, data, n)
  local pal = G.palette(data, true) or {}
  local out = {}
  for i = 1, n * 16 do
    local c = pal[i] or { 0, 0, 0 }
    out[i] = { c[1], c[2], c[3] }
  end
  return out
end

-- the index picture of a background (see the header)
local INDEX = {}
for row = 0, 15 do
  for i = 0, 15 do INDEX[row * 16 + i + 1] = { i * 17, row * 17, 0 } end
end

local function indexPicture(G, member, chars, map)
  return G.compose(G.tilemap(member(map)), G.tiles(member(chars)), INDEX)
end

-- every cell of a group, on row `row` of its palette
local function cells(G, member, group)
  local Cells = require("src.import.Gen4Cells")
  local sheet, bank = G.tiles(member(group[1])), Cells.parse(member(group[3]), G)
  local colours = rows(G, member(group[2]), 16)
  local out = {}
  if not (sheet and bank) then return out end
  for i, c in ipairs(bank.cells) do
    local pic = Cells.assemble(c, sheet, colours, bank, G)
    if pic then pic.originX, pic.originY = Cells.extent(c) end
    out[i - 1] = pic
  end
  return out
end

-- build(x) -> the index RomExtractorGen4 writes as gen4_pt_slot_art
function S.build(x)
  local member = opener(x.rom)
  if not member then return nil, "no " .. S.PATH end
  local G = require("src.import.Gen4Graphics")
  local CA = require("src.import.Gen4CellAnim")
  local out = { bg = {}, palettes = {}, groups = {}, version = 1 }
  local function save(key, image)
    return x:saveImage("pt_slot/" .. key, image, { originX = image.originX, originY = image.originY })
  end
  out.bg.main1 = save("bg_main1", assert(indexPicture(G, member, 0, 1)))
  out.bg.main2 = save("bg_main2", assert(indexPicture(G, member, 8, 9)))
  out.bg.sub3 = save("bg_sub3", assert(indexPicture(G, member, 2, 4)))
  out.palettes.bg = rows(G, member(3), 16)
  for _, m in ipairs({ 5, 6, 7, 74, 75, 76 }) do out.palettes["m" .. m] = rows(G, member(m), 1) end
  for name, group in pairs(S.GROUPS) do
    local rec = { cells = {}, seqs = {} }
    for c, pic in pairs(cells(G, member, group)) do rec.cells[c] = save(name .. "_" .. c, pic) end
    local anim = CA.parse(member(group[4]), G)
    for s, q in ipairs((anim and anim.sequences) or {}) do
      local frames = {}
      for _, f in ipairs(q.frames) do frames[#frames + 1] = { f.cell, f.duration } end
      rec.seqs[s - 1] = frames
    end
    out.groups[name] = rec
  end
  return out
end

return S
