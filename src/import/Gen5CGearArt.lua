-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S C-GEAR (/a/0/3/0, narc 30, 35 members, the same in both
-- games), written as `gen5_cgear_art`, drawn by src/ui/Gen5CGear.lua.
--
-- READ FROM CODE (Black; ov029 = the live C-Gear lower screen, base 0x021EFEC0;
-- ov035 = its message screen, same base):
--   palette  BG member [13, 6][gender] (0x021F31E0), OBJ [19, 12][gender]
--            (0x021F31C8); ov035 the same BG pair (0x021F05BC)
--   chars    [skin][gender] (0x021F32E0, rows of three): skin 0..4 boy 14..18,
--            girl 7..11 -- one char set shared by the three BG layers
--   screens  member 2 = the frame (BG2, 0x021F155C), member 1 = the top bar
--            (BG1, 0x021F161C), member 3 = ov035's message screen
--   OBJ      char 22, cells 21, anims 20 (0x021F158C..0x021F15AA)
--   honeycomb (0x021F1290): each cell 4 x 4 tiles at tile column
--            [0x18, 0x0C, 0x10, 0x14, 0x18, 0x1C][type] (0x021F3354) + row * 32
--            + column, in the palette row picked in src/ui/Gen5CGear.lua
-- WRITTEN
--   back_<g>_<s>  the frame (screen 2, 256 x 192)
--   bar_<g>_<s>   the top bar (screen 1)
--   hex_<g>_<s>   a 6 x 7 sheet of 32 x 32 honeycomb cells: column = cell
--                 type 0..5, row = palette row 0..6
--   msg_<g>       ov035's message screen (screen 3, skin 0's chars)
--   obj_<g>_<n>   OBJ cell n (the clock digits, battery, labels, icons)
-- g is "m" (boy) or "f" (girl), s the skin 0..4.

local A = {}

A.PATH = "/a/0/3/0"
A.BG_PAL = { m = 13, f = 6 }
A.OBJ_PAL = { m = 19, f = 12 }
A.CHARS = { m = { 14, 15, 16, 17, 18 }, f = { 7, 8, 9, 10, 11 } }
A.HEX_TILE = { [0] = 0x18, 0x0C, 0x10, 0x14, 0x18, 0x1C }
-- the cells the screen draws: digits 0-9, colon 10/11, battery 12-17, AM/PM
-- 18/19, the IR / WIRELESS / ONLINE labels 23-25, wrench 26/27, the logo 36,
-- help 52/53, power 54/55, the touched rings 20-22 / 28-33 (affine, drawn
-- centred by the screen)
A.OBJ_CELLS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
  20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 36, 52, 53, 54, 55 }

local char = string.char

local function crop(img, w, h)
  if not img then return nil end
  if img.width == w and img.height == h then return img end
  local out = {}
  local CLEAR = char(0, 0, 0, 0)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local p = CLEAR
      if x < img.width and y < img.height then
        local at = (y * img.width + x) * 4 + 1
        p = img.rgba:sub(at, at + 3)
      end
      out[y * w + x + 1] = p
    end
  end
  return { width = w, height = h, rgba = table.concat(out) }
end

function A.build(x)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Lz = require("src.import.Gen5Lz")
  local Narc = require("src.import.NarcArchive")
  local raw = x.rom:read(A.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil end
  local function m(i)
    local b = arc:get(i)
    if b and Lz.isCompressed(b) then b = Lz.decompress(b) elseif b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local index = { _source = "ROM:/a/0/3/0 (ov029 / ov035, src/import/Gen5CGearArt.lua)" }
  local function save(key, image, extra)
    if not image then return end
    local entry = x:saveImage("bw_cgear/" .. key, image, extra)
    if entry then index[key] = entry end
  end

  local frameMap, barMap, msgMap = G.tilemap(m(2)), G.tilemap(m(1)), G.tilemap(m(3))
  for g, palId in pairs(A.BG_PAL) do
    local pal = G.palette(m(palId))
    for s, charId in ipairs(A.CHARS[g]) do
      local sheet = G.tiles(m(charId))
      if sheet and pal then
        local tag = ("%s_%d"):format(g, s - 1)
        if frameMap then save("back_" .. tag, crop(G.compose(frameMap, sheet, pal), 256, 192)) end
        if barMap then save("bar_" .. tag, crop(G.compose(barMap, sheet, pal), 256, 192)) end
        -- the honeycomb cells: 6 types across, palette rows 0..6 down
        local cells = {}
        for row = 0, 27 do
          for col = 0, 23 do
            local t, p = math.floor(col / 4), math.floor(row / 4)
            cells[row * 24 + col + 1] = { tile = A.HEX_TILE[t] + (row % 4) * 32 + col % 4,
                                          flipX = false, flipY = false, palette = p }
          end
        end
        save("hex_" .. tag, G.compose({ width = 192, height = 224, cells = cells }, sheet, pal))
        if s == 1 and msgMap then save("msg_" .. g, crop(G.compose(msgMap, sheet, pal), 256, 192)) end
      end
    end
  end

  local objSheet, bank = G.tiles(m(22)), Cells.parse(m(21), G)
  for g, palId in pairs(A.OBJ_PAL) do
    local pal = G.palette(m(palId))
    if objSheet and bank and pal then
      for _, n in ipairs(A.OBJ_CELLS) do
        local cell = bank.cells[n + 1]
        local pic = cell and Cells.assemble(cell, objSheet, pal, bank, G)
        if pic then
          local ox, oy = Cells.extent(cell)
          save(("obj_%s_%d"):format(g, n), pic, { originX = ox, originY = oy })
        end
      end
    end
  end
  return index
end

return A
