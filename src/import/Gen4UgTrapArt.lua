-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- PLATINUM'S UNDERGROUND TRAP EFFECTS, in their own palettes
-- (/data/ug_trap.narc; pokeplatinum res/graphics/trap_effects, the member
-- order of trap_effects.order; src/underground/traps.c).
--
-- The generic archive pass (Gen4Archives) already writes these members as
-- underground/*.png, but pairs each sheet with whatever palette sits near it,
-- so the smoke and the flames came out pink. Here each one is drawn the way
-- traps.c loads it (READ):
--   petal      anim 0 / cell 1 / NCGR 2 / NCLR 3       (Flower)
--   bubble     4 / 5 / 6 / 7                            (Foam, Bubble)
--   smoke      tiles 9 + palette 10 on BG2; the maps big_smoke_pattern 8
--              (Big Smoke) and smoke_pattern_1..4 11..14 (Smoke, LCRNG % 4)
--              (traps.c 2472-2488); each map's tile numbers are kept as a
--              32 x 24 grid -- the rubbing counts them up and a tile past 5
--              is clear (2295-2452), so they are the smoke's starting state
--   fire       20 / 21 / 22 with ember_fire.NCLR 19; ember 23 / 24 / 25
--   leaf       26 / 27 / 28 / 29
--   boulder    anim 30 / cell 31 / NCGR 32, damaged_1..6 NCGR 35 38 41 44
--              47 50 drawn with the boulder's cell (their own cells are the
--              _unused ones), all with boulder.NCLR 51
-- A sprite is the first frame of each frame of animation sequence 0 (or of
-- every sequence for the petals' three looks), with its origin.
-- Written to assets/generated/gen4/ug_trap/<key>.png, indexed in
-- `gen4_ug_trap_art` (rev platinum-ug-trap-art-v1).

local M = {}
M.PATH = "/data/ug_trap.narc"

function M.build(x)
  local rom = x.rom
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local bytes = rom and rom:read(M.PATH)
  if not bytes then return nil, "no ug_trap.narc" end
  local a = N.parse(bytes)
  local function member(i)
    local b = a:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local images, rec = {}, { sprites = {}, smoke = {} }
  local function put(key, pic, ox, oy)
    images[key] = pic
    rec.sprites[key] = { key = key, originX = ox or 0, originY = oy or 0, width = pic.width, height = pic.height }
  end
  -- every frame of sequence `seq`
  local function sprite(prefix, t, c, an, p, seq, maxFrames)
    local sheet, pal = G.tiles(member(t)), G.palette(member(p))
    local okB, bank = pcall(Cells.parse, member(c), G)
    local okA, anim = pcall(Anim.parse, member(an), G)
    if not (sheet and pal and okB and bank and okA and anim) then return 0 end
    local frames = Anim.frames(anim, seq or 0) or {}
    local n, seen = 0, {}
    for _, fr in ipairs(frames) do
      if n >= (maxFrames or 8) then break end
      local cellIndex = fr.cell
      if not seen[cellIndex] then
        seen[cellIndex] = true
        local cell = bank.cells[cellIndex + 1]
        local pic = cell and Cells.assemble(cell, sheet, pal, bank, G)
        if pic then
          local ox, oy = Cells.extent(cell)
          put(("%s_%02d"):format(prefix, n), pic, ox, oy)
          n = n + 1
        end
      end
    end
    return n
  end
  rec.counts = {}
  rec.counts.bubble = sprite("bubble", 6, 5, 4, 7, 0, 8)
  rec.counts.leaf = sprite("leaf", 28, 27, 26, 29, 0, 8)
  rec.counts.fire = sprite("fire", 22, 21, 20, 19, 0, 8)
  rec.counts.ember = sprite("ember", 25, 24, 23, 19, 0, 8)
  rec.counts.boulder = sprite("boulder", 32, 31, 30, 51, 0, 1)
  for k = 1, 6 do sprite("boulder_damaged_" .. k, 32 + 3 * k, 31, 30, 51, 0, 1) end
  do
    local okA, anim = pcall(Anim.parse, member(0), G)
    local nseq = okA and anim and anim.sequences and #anim.sequences or 1
    for s = 0, math.max(0, nseq - 1) do sprite("petal_s" .. s, 2, 1, 0, 3, s, 1) end
    rec.counts.petal = nseq
  end
  -- the smoke: its tiles as a strip (tile n at x = n * 8) and the five maps
  local tiles, pal = G.tiles(member(9)), G.palette(member(10))
  if tiles and pal then
    local n = math.min(tiles.count or 0, 16)
    local cells = {}
    for i = 0, n - 1 do cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 } end
    local strip = G.compose({ width = n * 8, height = 8, cells = cells }, tiles, pal)
    if strip then put("smoke_tiles", strip) end
    rec.smokeTiles = n
    for _, m in ipairs({ { "big", 8 }, { "1", 11 }, { "2", 12 }, { "3", 13 }, { "4", 14 } }) do
      local map = G.tilemap(member(m[2]))
      if map then
        local w = math.floor((map.width or 256) / 8)
        local grid = {}
        for ty = 0, 23 do
          local row = {}
          for tx = 0, 31 do
            local c = map.cells[ty * w + tx + 1]
            row[tx + 1] = c and c.tile or 0
          end
          grid[ty + 1] = table.concat(row, ",")
        end
        rec.smoke[m[1]] = grid
      end
    end
  end
  return images, rec
end

return M
