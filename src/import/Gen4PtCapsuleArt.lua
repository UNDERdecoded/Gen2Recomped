-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S BALL CAPSULE APP ART (pokeplatinum src/applications/
-- capsule_menu/graphics.c, placement.c) -> `gen4_pt_capsule_art`, drawn by
-- src/ui/PtCapsuleMenu.lua.
--
-- /application/custom_ball/data/cb_data.narc (NARC_INDEX_APPLICATION__
-- CUSTOM_BALL__DATA__CB_DATA), read the way the app reads it (READ FROM CODE):
--   CapsuleGraphics_LoadBgLayer2Tilemap  main BG2  268 / 284, main BG3 269 /
--                                        285, palette 288 (two rows)
--   CapsuleGraphics_LoadBgLayer5Tilemap  sub BG1   267 / 283, palette 287
--   CapsuleGraphics_LoadBgLayer7Tilemap  sub BG3   267 / 282, palette 287
--   CapsuleGraphics_InitCapsuleSprites   the twelve capsules {266, 286, 174,
--                                        82} (anim 0 empty, 1 sealed) and the
--                                        two cursors {275, 291, 179, 87}
--   CapsuleGraphics_LoadSelectionResources  the corner arrows {265, 290 row 2,
--                                        173, 81}
--   CapsuleGraphics_LoadCapsuleUI        page up / down {273 / 274, 290 row 1,
--                                        177 / 178, 85 / 86}, throw {272, 290
--                                        row 1, 176, 84}, confirm / cancel
--                                        {270, 290 row 0, 175, 83}
--   SealPlacement_LoadSeal               a placed seal: char = the seal's
--                                        memberIdx (184 + ...), palette 293,
--                                        cell 93, anim 1
--   CapsuleGraphics_LoadPageSprites      the seal list's icons: the same chars,
--                                        palette 293, cell 180, anim 88

--
-- HEARTGOLD / SOULSILVER (overlay 57, pokeheartgold asm/overlay_57.s,
-- undecompiled): every resource is in one smaller archive, /a/0/8/7
-- (NARC_a_0_8_7, NARC_New(0x57)), READ FROM the overlay's loader calls --
-- main BG2 8 / 12, main BG3 9 / 13, sub BG1 7 / 11, sub BG3 7 / 10, the BG
-- palettes 2 (main) and 1 (sub); sprites arrows {14, -, 16, 15}, capsules
-- {17, -, 19, 18}, cursor {32, -, 34, 33}, buttons {20, -, 22, 21}, throw
-- {23, -, 25, 24}, page up {26, -, 28, 27}, page down {29, -, 31, 30}; a
-- placed seal cell 38 / anim 36, a list icon cell 37 / anim 35. The sprite
-- palettes are matched colour for colour against Platinum's (INFERRED from
-- that match, the overlay passes them through registers): 3 = Platinum's
-- 286, 4 = 290, 5 = 291, 6 = 293, 2 = 288, 1 = 287 (rows 1..); and the seal
-- characters run 39 + (Platinum's memberIdx - 0xB8) (INFERRED: the archive
-- holds the 81 seal sheets in Platinum's order from member 39).

local S = {}

S.PATH = "/application/custom_ball/data/cb_data.narc"
S.HGSS_PATH = "/a/0/8/7"

S.LAYOUT = {
  platinum = {
    path = S.PATH, mainPal = 288, subPal = 287,
    bg = { main2 = { 268, 284 }, main3 = { 269, 285 }, sub1 = { 267, 283 }, sub3 = { 267, 282 } },
    sealPal = 293, sealCell = 93, iconCell = 180, sealBase = 0,
  },
  hgss = {
    path = S.HGSS_PATH, mainPal = 2, subPal = 1,
    bg = { main2 = { 8, 12 }, main3 = { 9, 13 }, sub1 = { 7, 11 }, sub3 = { 7, 10 } },
    sealPal = 6, sealCell = 38, iconCell = 37, sealBase = 39 - 0xB8,
    groups = {
      capsule = { 17, 3, 19, 18, 0 }, cursor = { 32, 5, 34, 33, 0 },
      arrow = { 14, 4, 16, 15, 2 },
      pageUp = { 26, 4, 28, 27, 1 }, pageDown = { 29, 4, 31, 30, 1 },
      throw = { 23, 4, 25, 24, 1 }, button = { 20, 4, 22, 21, 0 },
    },
  },
}

-- capsule_menu/main.c sealTypeValues[].memberIdx, by seal id (0 = SEAL_DUMMY)
S.MEMBER = {
  [0] = 0xB8, 0xB9, 0xBA, 0xBB, 0xBC, 0xBD, 0xBE, 0xC0, 0xBF, 0xC2, 0xC1, 0xC4, 0xC3, 0xC5, 0xC6, 0xC7,
  0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD6, 0xD5, 0xD8,
  0xD7, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7,
  0xE8, 0xE9, 0xEA, 0xEB, 0xEC, 0xED, 0xEE, 0xEF, 0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7,
  0xF8, 0xF9, 0xFA, 0xFB, 0xFC, 0xFD, 0xFE, 0xFF, 0x100, 0x101, 0x102, 0x103, 0x104, 0x105, 0x106,
  0x107, 0x108,
}

S.GROUPS = {
  capsule = { 266, 286, 174, 82, 0 }, cursor = { 275, 291, 179, 87, 0 },
  arrow = { 265, 290, 173, 81, 2 },
  pageUp = { 273, 290, 177, 85, 1 }, pageDown = { 274, 290, 178, 86, 1 },
  throw = { 272, 290, 176, 84, 1 }, button = { 270, 290, 175, 83, 0 },
}

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom and rom:read(path or S.PATH)
  local narc = bytes and require("src.import.NarcArchive").parse(bytes)
  if not narc then return nil end
  return function(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function colours(G, data)
  local pal = G.palette(data, true) or {}
  local out = {}
  for i = 1, 256 do local c = pal[i] or { 0, 0, 0 }; out[i] = { c[1], c[2], c[3] } end
  return out
end

-- every cell of a bank over one tile sheet, on palette row `row` (+ the OAM
-- entry's own row)
local function cells(G, sheet, bank, pal, row)
  local Cells = require("src.import.Gen4Cells")
  local out = {}
  if not (sheet and bank) then return out end
  for i, c in ipairs(bank.cells) do
    local flat = { oam = {} }
    for k, v in pairs(c) do if k ~= "oam" then flat[k] = v end end
    local r = row
    for j, o in ipairs(c.oam) do
      local copy = {}
      for k, v in pairs(o) do copy[k] = v end
      r = row + (o.palette or 0)
      copy.palette = 0
      flat.oam[j] = copy
    end
    local slice = {}
    for k = 1, 16 do slice[k] = pal[r * 16 + k] or { 0, 0, 0 } end
    local pic = Cells.assemble(flat, sheet, slice, bank, G)
    if pic then pic.originX, pic.originY = Cells.extent(flat) end
    out[i - 1] = pic
  end
  return out
end

local function seqs(G, data)
  local CA = require("src.import.Gen4CellAnim")
  local anim = CA.parse(data, G)
  local out = {}
  for s, q in ipairs((anim and anim.sequences) or {}) do
    local frames = {}
    for _, f in ipairs(q.frames) do frames[#frames + 1] = { f.cell, f.duration } end
    out[s - 1] = frames
  end
  return out
end

-- build(x) -> the index RomExtractorGen4 writes as gen4_pt_capsule_art
function S.build(x)
  local hgss = require("src.import.Gen4Versions").isHgss(x.version)
  local L = S.LAYOUT[hgss and "hgss" or "platinum"]
  local member = opener(x.rom, L.path)
  if not member then return nil, "no " .. L.path end
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local out = { bg = {}, groups = {}, seals = {}, icons = {}, version = 1, hgss = hgss or nil }
  local function save(key, image)
    return x:saveImage("pt_capsule/" .. key, image, { originX = image.originX, originY = image.originY })
  end
  local mainPal, subPal = colours(G, member(L.mainPal)), colours(G, member(L.subPal))
  out.backdropMain = mainPal[1]
  out.backdropSub = subPal[1]
  local function bg(key, chars, map, pal)
    local pic = G.compose(G.tilemap(member(map)), G.tiles(member(chars)), pal)
    if pic then out.bg[key] = save("bg_" .. key, pic) end
  end
  for key, b in pairs(L.bg) do bg(key, b[1], b[2], key:match("^main") and mainPal or subPal) end
  for name, g in pairs(L.groups or S.GROUPS) do
    local rec = { cells = {}, seqs = seqs(G, member(g[4])) }
    local pics = cells(G, G.tiles(member(g[1])), Cells.parse(member(g[3]), G), colours(G, member(g[2])), g[5])
    for c, pic in pairs(pics) do rec.cells[c] = save(name .. "_" .. c, pic) end
    out.groups[name] = rec
  end
  local sealPal = colours(G, member(L.sealPal))
  local placed, icon = Cells.parse(member(L.sealCell), G), Cells.parse(member(L.iconCell), G)
  for id = 1, 80 do
    local sheet = G.tiles(member(S.MEMBER[id] + L.sealBase))
    local a = cells(G, sheet, placed, sealPal, 0)[0]
    local b = cells(G, sheet, icon, sealPal, 0)[0]
    if a then out.seals[id] = save("seal_" .. id, a) end
    if b then out.icons[id] = save("icon_" .. id, b) end
  end
  -- THE TRAINERS' CAPSULES (Pokemon_SetBallSeal): member 0 of
  -- /application/custom_ball/edit/pl_cb_data.narc (HeartGold / SoulSilver
  -- /a/1/8/5, gs_cb_data), BallCapsule after BallCapsule, 8 x { type, x, y }
  -- bytes; a trainer's Pokemon with cbSeal n wears capsule n - 1
  pcall(function()
    local bytes = x.rom:read(hgss and "/a/1/8/5" or "/application/custom_ball/edit/pl_cb_data.narc")
    local narc = bytes and require("src.import.NarcArchive").parse(bytes)
    local blob = narc and narc:get(0)
    if not blob then return end
    out.trainerCapsules = {}
    for n = 1, math.floor(#blob / 24) do
      local cap = { seals = {} }
      for k = 1, 8 do
        local at = (n - 1) * 24 + (k - 1) * 3
        cap.seals[k] = { type = blob:byte(at + 1), x = blob:byte(at + 2), y = blob:byte(at + 3) }
      end
      out.trainerCapsules[n] = cap
    end
  end)
  return out
end

return S
