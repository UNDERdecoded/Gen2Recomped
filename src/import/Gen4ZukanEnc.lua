-- THE POKEDEX AREA MAP'S DATA AND ART (zukan_enc), Platinum and HGSS, written
-- as the cache module `gen4_zukan_enc` (revision tags platinum-zukan-enc-v1 /
-- hgss-zukan-enc-v1, RomImporter). Drawn by src/ui/Gen4DexAreaMap.lua
-- (Platinum's AREA page) and src/ui/HgssDexDetails.lua (HGSS's AREA page).
--
-- PLATINUM -- READ FROM CODE (pokeplatinum src/applications/pokedex/
-- pokedex_enc_data.c, pokedex_field_map.c, ov21_021DC9BC.c):
--   * /application/zukanlist/zkn_data/zukan_enc_platinum.narc: member 0 the
--     22 dungeons {x, y, isMtCoronet, unused}; member 2 the 51 fields
--     {y, x, height, width, cellMatrix[32]} (decomp names; see below); from
--     member 4, 495 members per category, one per species: dungeon morning /
--     day / night / special / special (National Dex), field morning / day /
--     night / special / special (National Dex) -- each a list of s32 indices
--     ending in 0 (the 0 is not a place: the loops stop at count - 1)
--   * the field window: cell (a, b) of the 30 x 30 grid is `map[a * 30 + b]`,
--     a running over the field's byte 1 / byte 3 and b over byte 0 / byte 2,
--     and lands at window pixel (89 + b * 5, 30 + a * 5) (DisplayOnWindow
--     passes the "y" loop as the blit's x); the cell's matrix entry is
--     `cellMatrix[(a - byte1) * byte2 + (b - byte0)]`
--   * the field pieces are 5 x 5 rects of dummy1.NCGR (timed fields) and
--     dummy2.NCGR (special fields), piece n at x = n * 5, in BG palette 8
--     (Window_SetPalette 8) of banner_sinnoh.NCLR (the main BG palette,
--     ov21_021E29DC.c:631)
--   * the dungeons are dungeon_highlight OBJ (anim 2 timed / 3 special, Mt.
--     Coronet 0 / 1, Feebas 4 / 5) in size_check_icons.NCLR
--   * "Area Unknown" is size_check_icons anim 2 at (160, 96); the bottom
--     screen is area_sub.NSCR over entry_sub.NCGR in banner_sinnoh.NCLR with
--     sub BG palette 2 replaced by row 0 of area_<time>.NCLR, and the slider
--     is time_day_icons anim <time> (palette info.NCLR, INFERRED from the
--     resource tag info_NCLR + 2100)
-- The member numbers below are the narc's own (Gen4Archives names).
--
-- HGSS -- READ FROM CODE (pokeheartgold ov18_021E5C40.c ov18_021E8528 ..
-- ov18_021E8B78, asm/overlay_18.s ov18_021F41C4 / 42E4 / 4384 / 463C / 47C0 /
-- 47F8, files/application/zukanlist/zkn_data/zukan_enc.json.txt):
--   * /a/1/3/3 (fs id 133): member 0 gDungeons (26 x {x, y, 0, 0}), member 1
--     gOverworlds (70 x {x, y, w, h, 32 bytes}), from member 2, 495 members
--     per method: 0-2 dungeons morning / day / night, 3-5 overworld morning /
--     day / night, 6 dungeons special, 7 overworld special (s32 lists ending
--     in 0)
--   * the markers' OBJ (ov18_021F3E24): zukan_gra /a/0/6/8 char 119, cell
--     120, anim 121, palette 122 (two rows; the timed set draws with palette
--     override 4, the special set with 5 -- rows 0 / 1 here, INFERRED from
--     the two-row load)

local Z = {}

Z.PT_PATH = "/application/zukanlist/zkn_data/zukan_enc_platinum.narc"
Z.HG_PATH = "/a/1/3/3"
Z.HG_GRA = "/a/0/6/8"
Z.SPECIES = 495 -- MAX_SPECIES, the members per category / method

-- -------------------------------------------------- HGSS map id tables --
-- OVERWORLDS (70), READ FROM CODE: pokeheartgold ov18_021E5C40.c sOverworldMapIDs
Z.HG_OVERWORLDS = {
  0xFFFF, 60, 33, 67, 34, 35, 73, 36, 37, 38, 39, 40, 41, 78, 42, 43, 77, 94, 95, 75, 44, 45,
  88, 46, 89, 47, 48, 151, 90, 20, 91, 92, 49, 50, 52, 54, 55, 56, 57, 152, 30, 31, 32, 9, 10,
  11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 422, 25, 26, 93, 27, 28, 29, 414, 51, 74, 174,
  24, 0xFFFF,
}
-- DUNGEONS (26), READ FROM CODE: pokeheartgold ov18_021E5C40.c sDungeonMapIDs
Z.HG_DUNGEONS = {
  0xFFFF, 155, 113, 99, 177, 117, 96, 7, 332, 121, 119, 120, 253, 176, 449, 146, 462, 279, 342,
  240, 108, 124, 126, 106, 147, 145,
}
-- ALPHABETICAL (142), READ FROM CODE: pokeheartgold ov18_021E5C40.c sMapIDs_Alphabetical
Z.HG_ALPHABETICAL = {
  9, 10, 414, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 422, 24, 25, 26, 91, 92, 93,
  27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 94, 95, 44, 45, 46, 47,
  48, 151, 152, 74, 332, 333, 334, 335, 336, 337, 338, 339, 341, 89, 7, 217, 55, 145, 450, 451,
  52, 67, 75, 57, 342, 279, 106, 123, 176, 253, 78, 56, 120, 237, 238, 239, 117, 88, 107, 448,
  449, 513, 119, 250, 251, 252, 90, 122, 459, 460, 461, 462, 463, 464, 96, 487, 60, 240, 77,
  49, 51, 108, 452, 113, 315, 490, 491, 492, 177, 181, 357, 174, 146, 453, 454, 455, 456, 155,
  156, 126, 298, 99, 153, 154, 54, 124, 178, 179, 73, 50, 147, 121, 242, 243, 486, 244,
}

-- ------------------------------------------------------------ helpers --
local function s32list(b)
  if not b then return nil end
  local out = {}
  for k = 0, math.floor(#b / 4) - 1 do
    local b1, b2, b3, b4 = b:byte(k * 4 + 1, k * 4 + 4)
    local v = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    if v >= 2147483648 then v = v - 4294967296 end
    out[#out + 1] = v
  end
  -- the closing 0 is the list's end (the cartridge loops to count - 1)
  if out[#out] == 0 then out[#out] = nil end
  return out
end

local function bytes(b, at, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = b:byte(at + i + 1) or 0 end
  return t
end

-- every 16-entry row of `pal` replaced by row `row` (an OBJ whose palette
-- the code overrides draws in that row whatever its OAM says)
local function onlyRow(pal, row)
  local out = {}
  for slot = 0, 15 do
    for i = 1, 16 do out[slot * 16 + i] = pal[row * 16 + i] end
  end
  return out
end

local function cellsOf(G, Cells, CellAnim, sheet, pal, bank, anim, prefix, out)
  if not (sheet and pal and bank and anim) then return 0 end
  local n = 0
  for a = 0, #anim.sequences - 1 do
    local f = CellAnim.frames(anim, a)
    local cell = f and f[1] and bank.cells[f[1].cell + 1]
    local pic = cell and Cells.assemble(cell, sheet, pal, bank, G)
    if pic then
      pic.originX, pic.originY = Cells.extent(cell)
      out[prefix .. a] = pic
      n = n + 1
    end
  end
  return n
end

-- ----------------------------------------------------------- Platinum --
function Z.platinum(x)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local raw = x.rom:read(Z.PT_PATH)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  local data = { family = "platinum", dungeons = {}, fields = {}, lists = {} }
  local d0 = arc:get(0) or ""
  for i = 0, math.floor(#d0 / 4) - 1 do
    local t = bytes(d0, i * 4, 4)
    data.dungeons[i] = { x = t[1], y = t[2], coronet = t[3] ~= 0 }
  end
  local f2 = arc:get(2) or ""
  for i = 0, math.floor(#f2 / 36) - 1 do
    local t = bytes(f2, i * 36, 36)
    local cells = {}
    for k = 5, 36 do cells[#cells + 1] = t[k] end
    data.fields[i] = { b0 = t[1], a0 = t[2], bn = t[3], an = t[4], cells = cells }
  end
  local names = { "dungeonMorning", "dungeonDay", "dungeonNight", "dungeonSpecial", "dungeonSpecialNat",
                  "fieldMorning", "fieldDay", "fieldNight", "fieldSpecial", "fieldSpecialNat" }
  for k, name in ipairs(names) do
    local per = {}
    for sp = 1, Z.SPECIES - 1 do
      local list = s32list(arc:get(4 + Z.SPECIES * (k - 1) + sp))
      if list and #list > 0 then per[sp] = list end
    end
    data.lists[name] = per
  end
  data.source = "ROM:" .. Z.PT_PATH .. " (pokeplatinum pokedex_enc_data.c)"

  -- the art, out of the Pokedex's own archive
  local images = {}
  pcall(function()
    local A = require("src.import.Gen4Archives")
    local Cells = require("src.import.Gen4Cells")
    local CellAnim = require("src.import.Gen4CellAnim")
    local dexPath = require("src.import.Gen4Dex").PATH
    local draw = x.rom:read(dexPath)
    local dex = draw and N.parse(draw)
    if not dex then return end
    local function m(name)
      local i = A.find(dexPath, name)
      local b = i and dex:get(i)
      if b and G.isCompressed(b) then b = G.decompress(b) end
      return b
    end
    local banner = G.palette(m("banner_sinnoh.NCLR"))
    -- the field pieces: dummy1 / dummy2 as a bitmap in palette 8
    for k, name in ipairs({ "dummy1.NCGR.lz", "dummy2.NCGR.lz" }) do
      local sheet = G.tiles(m(name))
      local px, w, h = G.indices(sheet, 32)
      if px and banner then
        local out = {}
        for i = 1, w * h do
          local v = px[i]
          local c = v ~= 0 and banner[8 * 16 + v + 1]
          out[i] = c and string.char(c[1], c[2], c[3], 255) or "\0\0\0\0"
        end
        images["pt_field_" .. k] = { width = w, height = h, rgba = table.concat(out) }
      end
    end
    -- the dungeon highlights and the "Area Unknown" box
    local icons = G.palette(m("size_check_icons.NCLR"))
    cellsOf(G, Cells, CellAnim, G.tiles(m("dungeon_highlight.NCGR.lz")), icons,
      Cells.parse(m("dungeon_highlight_cell.NCER.lz"), G), CellAnim.parse(m("dungeon_highlight_anim.NANR.lz"), G),
      "pt_dungeon_", images)
    cellsOf(G, Cells, CellAnim, G.tiles(m("size_check_icons.NCGR.lz")), icons,
      Cells.parse(m("size_check_icons_cell.NCER.lz"), G), CellAnim.parse(m("size_check_icons_anim.NANR.lz"), G),
      "pt_sizeicon_", images)
    -- the slider's icon
    cellsOf(G, Cells, CellAnim, G.tiles(m("time_day_icons.NCGR.lz")), G.palette(m("info.NCLR")),
      Cells.parse(m("time_day_icons_cell.NCER.lz"), G), CellAnim.parse(m("time_day_icons_anim.NANR.lz"), G),
      "pt_timeicon_", images)
    -- the bottom screen per time: banner_sinnoh with palette 2 from area_<t>
    local subChars = G.tiles(m("entry_sub.NCGR.lz"))
    local subMap = G.tilemap(m("area_sub.NSCR.lz"))
    for t, name in ipairs({ "area_morning.NCLR", "area_day.NCLR", "area_night.NCLR" }) do
      local row = G.palette(m(name))
      if banner and row and subChars and subMap then
        local pal = {}
        for i = 1, #banner do pal[i] = banner[i] end
        for i = 1, 16 do pal[2 * 16 + i] = row[i] or pal[2 * 16 + i] end
        images["pt_area_sub_" .. (t - 1)] = G.compose(subMap, subChars, pal)
      end
    end
    -- the four hidden places' patches (Bg_LoadToTilemapRect onto BG3)
    local mainChars = G.tiles(m("entry_main.NCGR.lz"))
    for _, name in ipairs({ "newmoon_island", "seabreak_path", "fullmoon_island", "spring_path" }) do
      local map = G.tilemap(m("map_" .. name .. ".NSCR.lz"))
      if map and mainChars and banner then images["pt_map_" .. name] = G.compose(map, mainChars, banner) end
    end
    local map = G.tilemap(m("area_map.NSCR.lz"))
    if map and mainChars and banner then images.pt_area_map = G.compose(map, mainChars, banner) end
  end)
  return data, images
end

-- --------------------------------------------------------------- HGSS --
function Z.hgss(x)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local raw = x.rom:read(Z.HG_PATH)
  local arc = raw and N.parse(raw)
  if not arc then return nil end
  local data = { family = "hgss", dungeons = {}, overworlds = {}, methods = {} }
  local d0 = arc:get(0) or ""
  for i = 0, math.floor(#d0 / 4) - 1 do
    local t = bytes(d0, i * 4, 4)
    data.dungeons[i] = { x = t[1], y = t[2] }
  end
  local o1 = arc:get(1) or ""
  for i = 0, math.floor(#o1 / 36) - 1 do
    local t = bytes(o1, i * 36, 4)
    data.overworlds[i] = { x = t[1], y = t[2], w = t[3], h = t[4] }
  end
  for meth = 0, 7 do
    local per = {}
    for sp = 1, Z.SPECIES - 1 do
      local list = s32list(arc:get(2 + Z.SPECIES * meth + sp))
      if list and #list > 0 then per[sp] = list end
    end
    data.methods[meth] = per
  end
  data.source = "ROM:" .. Z.HG_PATH .. " (pokeheartgold ov18_021E5C40.c)"

  local images = {}
  pcall(function()
    local Cells = require("src.import.Gen4Cells")
    local CellAnim = require("src.import.Gen4CellAnim")
    local gr = x.rom:read(Z.HG_GRA)
    local gra = gr and N.parse(gr)
    if not gra then return end
    local function m(i)
      local b = gra:get(i)
      if b and G.isCompressed(b) then b = G.decompress(b) end
      return b
    end
    local sheet, pal = G.tiles(m(119)), G.palette(m(122))
    local bank, anim = Cells.parse(m(120), G), CellAnim.parse(m(121), G)
    if pal then
      cellsOf(G, Cells, CellAnim, sheet, onlyRow(pal, 0), bank, anim, "hg_marker_t_", images)
      cellsOf(G, Cells, CellAnim, sheet, onlyRow(pal, 1), bank, anim, "hg_marker_s_", images)
    end
  end)
  return data, images
end

function Z.build(x)
  local family = require("src.import.Gen4Versions").family(x.version)
  local data, images
  if family == "hgss" then data, images = Z.hgss(x)
  else data, images = Z.platinum(x) end
  if not data then return nil end
  data.art = {}
  for key, image in pairs(images or {}) do
    data.art[key] = x:saveImage("zukan_enc/" .. key, image, { originX = image.originX, originY = image.originY })
  end
  return data
end

return Z
