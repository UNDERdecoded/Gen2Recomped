-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- PLATINUM'S UNDERGROUND TOP SCREEN: the map of the passages and its markers
-- (/data/underg_radar.narc; pokeplatinum res/graphics/underground_top_screen,
-- the member order of underground_top_screen.order; src/underground/
-- top_screen.c).
--
-- READ FROM CODE (top_screen.c 448-490):
--   * the map: background_tiles.NCGR (1) under background.NSCR (2) with the
--     two palettes of background_tiles.NCLR (0) on SUB BG0, at (0, 0);
--   * the markers: map_markers.NCGR (4) / .NCLR (3) / map_markers_cell.NCER
--     (5) / map_markers_anim.NANR (6) -- one sequence per MARKER_ANIM_*
--     (underground/manager.h 51-66: 0 a link, 1 the player, 3 the Secret
--     Base, 9 a Sphere, 11 a Trap, 12 a mining spot; the rest unused).
-- Every frame of every sequence is written with its duration and its cell
-- origin, so the screen plays them as the sprite system does.
-- And the base decoration cursor's model, data/ug_base_cur.nsbmd (below).
-- Written to assets/generated/gen4/ug_top/<key>.png, indexed in
-- `gen4_ug_top_art` (rev platinum-ug-top-v1; the cursor platinum-ug-cursor-v1).

local M = {}
M.PATH = "/data/underg_radar.narc"
M.CURSOR_PATH = "/data/ug_base_cur.nsbmd"

function M.build(x)
  local rom = x.rom
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local bytes = rom and rom:read(M.PATH)
  if not bytes then return nil, "no underg_radar.narc" end
  local a = N.parse(bytes)
  local function member(i)
    local b = a:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local images, rec = {}, { sprites = {}, sequences = {} }
  -- the map
  local map, tiles, pal = G.tilemap(member(2)), G.tiles(member(1)), G.palette(member(0))
  local bg = map and tiles and pal and G.compose(map, tiles, pal)
  if bg then
    images.background = bg
    rec.background = { key = "background", width = bg.width, height = bg.height }
  end
  -- the markers
  local sheet, mpal = G.tiles(member(4)), G.palette(member(3))
  local okB, bank = pcall(Cells.parse, member(5), G)
  local okA, anim = pcall(Anim.parse, member(6), G)
  if sheet and mpal and okB and bank and okA and anim then
    local made = {}
    local nseq = anim.sequences and #anim.sequences or 0
    for s = 0, nseq - 1 do
      local out = {}
      for _, fr in ipairs(Anim.frames(anim, s) or {}) do
        local key = ("marker_c%02d"):format(fr.cell)
        if made[fr.cell] == nil then
          local cell = bank.cells[fr.cell + 1]
          local pic = cell and Cells.assemble(cell, sheet, mpal, bank, G)
          if pic then
            local ox, oy = Cells.extent(cell)
            images[key] = pic
            rec.sprites[key] = { key = key, originX = ox or 0, originY = oy or 0, width = pic.width, height = pic.height }
            made[fr.cell] = true
          else
            made[fr.cell] = false
          end
        end
        if made[fr.cell] then out[#out + 1] = { key = key, duration = fr.duration or 1 } end
      end
      rec.sequences[s] = out
    end
    rec.sequenceCount = nseq
  end
  -- THE DECORATION CURSOR (rev platinum-ug-cursor-v1): the loose model
  -- /data/ug_base_cur.nsbmd (base_decoration.c 1222-1233, Easy3D), packed as
  -- the model stage packs one; its pictures are sprites `cursor_<texture>`
  local okC, err = pcall(function()
    local cur = rom:read(M.CURSOR_PATH)
    if not cur then return end
    if G.isCompressed(cur) then cur = G.decompress(cur) end
    local Nsbmd = require("src.import.Gen4Nsbmd")
    local Models = require("src.import.Gen4Models")
    local Pack = require("src.import.Gen4ModelPack")
    local parsed = Nsbmd.parse(cur)
    local sections = Nsbmd.sections(cur)
    local textures = sections and sections.TEX0 and Models.parse(cur, sections.TEX0) or nil
    local model = parsed and parsed.models and parsed.models[1]
    if not model then return end
    local packed = Pack.pack(model)
    for _, shape in ipairs(packed.shapes or {}) do
      local name = shape.texture
      if name and textures then
        local key = "cursor_" .. tostring(name):gsub("[^%w_%-]", "_")
        if not images[key] then
          local ti, pi
          for i, tx in ipairs(textures.textures) do if tx.name == name then ti = i end end
          for i, pl in ipairs(textures.palettes) do if pl.name == shape.palette then pi = i end end
          local pic = ti and Models.decode(textures, cur, ti, pi or 1)
          if pic then
            images[key] = pic
            rec.sprites[key] = { key = key, width = pic.width, height = pic.height }
          end
        end
        shape.imageKey = key
      end
    end
    rec.cursor = packed
  end)
  if not okC then rec.cursorError = tostring(err) end
  return images, rec
end

return M
