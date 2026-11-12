-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CARTRIDGE'S FRONT END (round 13): what the GBA shows after its title,
-- the shared ALttP / Four Swords screens of the top-level tasks 8 (CHOOSE A
-- FILE, ENTER A NAME: 0x0800F809) and 6 (CHOOSE A GAME: 0x0803074D).
-- Found by running the cartridge from AgbMain in the scratch Thumb
-- interpreter (VBlank and the object loop's ARM routines stood in for) and
-- logging what each screen decompresses into VRAM (BIOS LZ77 0x12) and
-- which palette rows land in palette RAM; every map, tile block and
-- palette here is one of those, checked against the VRAM the cartridge
-- built (scratch r13/py/fe_an.py).
--
-- Writes:
--   assets/generated/alttp/front_file.bin  VRAM image (0x18000) of task 8,
--        then the name screen's BG0 / BG2 / BG1 maps (3 x 0x800)
--   assets/generated/alttp/front_game.bin  VRAM image (0x18000) of task 6
--   data/generated/alttp_front.lua         the two screens' palettes
--        (BG + OBJ, 256 colours each)
-- Not taken: the letters of the name grid and the names on the file
-- panels, which the cartridge renders at run time with its own font
-- (0x0800EE50, base *0x03000030 = 0x0854F7E8; the glyph format is not
-- decoded) -- the runtime writes them with the dialogue font (OURS).

local R = require("src.zelda.alttp.RomMap")

local F = {}

F.FILES = {
  file = "assets/generated/alttp/front_file.bin",
  game = "assets/generated/alttp/front_game.bin",
  info = "data/generated/alttp_front.lua",
}

local function check(c, fmt, ...)
  if not c then error("ALttP import (front end): " .. fmt:format(...), 0) end
end

local function vramImage(rom, loads)
  local parts = {}
  local size = 0x18000
  local buf = {}
  for i = 1, size do buf[i] = 0 end
  for _, l in ipairs(loads) do
    local data, why = rom:lz77(l[1])
    check(data, "LZ77 at %06X: %s", l[1], tostring(why))
    check(#data == l[3], "LZ77 at %06X is %X bytes, expected %X", l[1], #data, l[3])
    check(l[2] + #data <= size, "LZ77 at %06X outside VRAM", l[1])
    for k = 1, #data do buf[l[2] + k] = data:byte(k) end
  end
  for i = 1, size, 4096 do
    parts[#parts + 1] = string.char(unpack(buf, i, math.min(size, i + 4095)))
  end
  return table.concat(parts)
end

local function colours(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local c = rom:u16(o + i * 2)
    check(c < 0x8000, "colour word at %06X", o + i * 2)
    t[i + 1] = c
  end
  return t
end

function F.run(rom, cache, tick)
  local S = require("src.zelda.alttp.Serialize")
  local f = R.front
  local file = vramImage(rom, f.fileLoads)
  if tick then tick(1, 3) end
  -- the name screen's maps (BG0 header, BG2 panel, BG1 letter grid)
  local maps = {}
  for _, l in ipairs(f.nameMaps) do
    local data = assert(rom:lz77(l[1]))
    check(#data == l[2], "name map at %06X is %X bytes", l[1], #data)
    maps[#maps + 1] = data .. string.rep("\0", 0x800 - #data)
  end
  assert(cache:write(F.FILES.file, file .. table.concat(maps)))
  local game = vramImage(rom, f.gameLoads)
  assert(cache:write(F.FILES.game, game))
  if tick then tick(2, 3) end
  local info = {
    fileBg = colours(rom, f.filePalBg, 256), fileObj = colours(rom, f.filePalObj, 256),
    gameBg = colours(rom, f.gamePalBg, 256), gameObj = colours(rom, f.gamePalObj, 256),
  }
  -- OBJ row 7 of task 8 comes from its own row (the cursor's colours)
  local row7 = colours(rom, f.filePalObj7, 16)
  for i = 1, 16 do info.fileObj[7 * 16 + i] = row7[i] end
  check(info.fileBg[1] == info.fileBg[1] and #info.gameObj == 256, "front-end palettes")
  assert(cache:write(F.FILES.info, S.encode(info)))
  if tick then tick(3, 3) end
end

function F.files()
  return { F.FILES.file, F.FILES.game, F.FILES.info }
end

return F
