-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THIS PROVES: that the mining game's extra art (src/import/Gen4MiningArt)
-- and the menus' cursor and Underground icons (src/import/Gen4MenuArt) come out
-- of the cartridge the shape and colour the screens assume, and that the
-- sprite sequences Gen4MiningScreen plays are the ones in animations_anim.NANR
-- rather than a copy that drifted.
--
-- Usage: python tools/run_lua_check.py tools/gen4_mining_sprites_check.lua <rom>

local root = (arg[0] or ""):gsub("[^/\\]*$", "")
if root ~= "" then package.path = root .. "../?.lua;" .. package.path end
package.path = "./?.lua;" .. package.path

local romPath = arg[1]
if not romPath then
  print("usage: texlua tools/gen4_mining_sprites_check.lua <rom>")
  return
end

local fails, checks = 0, 0
local function ok(cond, fmt, ...)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    io.write("FAIL: ", (select("#", ...) > 0) and fmt:format(...) or fmt, "\n")
  end
end

local G = require("src.import.Gen4Graphics")
local N = require("src.import.NarcArchive")
local A = require("src.import.Gen4Archives")
local Anim = require("src.import.Gen4CellAnim")
local rom = assert(require("src.import.NdsRom").open(romPath))

local function pixel(pic, x, y)
  local at = (y * pic.width + x) * 4
  return pic.rgba:byte(at + 1), pic.rgba:byte(at + 2), pic.rgba:byte(at + 3), pic.rgba:byte(at + 4)
end

-- 1. the mining art
local images = assert(require("src.import.Gen4MiningArt").images(rom))
local function size(key, w, h)
  local p = images[key]
  ok(p and p.width == w and p.height == h, "%s is %sx%s, expected %dx%d", key,
     tostring(p and p.width), tostring(p and p.height), w, h)
end
size("interface_tiles_row2", 432, 64)
size("dirt_tiles_row2", 128, 16)
for _, k in ipairs({ "hammer_btn_up", "hammer_btn_mid", "hammer_btn_down",
                     "pickaxe_btn_up", "pickaxe_btn_mid", "pickaxe_btn_down" }) do
  size(k, 48, 64)
end
for n = 1, 22 do
  local p = images["anim_" .. n]
  ok(p and p.originX and p.originY, "anim_%d is missing or has no origin", n)
end
for n = 0, 5 do
  local p = images["crack_end_" .. n]
  ok(p and p.width == 32 and p.height == 32 and p.originX == -32 and p.originY == -16,
     "crack_end_%d is not a 32x32 cell from (-32, -16)", n)
end

-- the row-2 sheets really are in row 2: every opaque pixel is a row-2 colour
local fossil = N.parse(rom:read("/data/ug_fossil.narc"))
local pal = G.palette(fossil:get(A.find("/data/ug_fossil.narc", "interface_tiles.NCLR")))
local row2 = {}
for i = 33, 48 do local c = pal[i]; row2[c[1] .. "," .. c[2] .. "," .. c[3]] = true end
for _, key in ipairs({ "interface_tiles_row2", "dirt_tiles_row2" }) do
  local p, bad, seen = images[key], 0, 0
  for y = 0, p.height - 1 do
    for x = 0, p.width - 1 do
      local r, g, b, a = pixel(p, x, y)
      if a ~= 0 then
        seen = seen + 1
        if not row2[r .. "," .. g .. "," .. b] then bad = bad + 1 end
      end
    end
  end
  ok(seen > 0 and bad == 0, "%s: %d of %d opaque pixels are not interface_tiles.NCLR row 2", key, bad, seen)
end
-- row 2 starts 008bb4 (BGR555 rounded: 0, 140, 181 or near)
ok(pal[33] and pal[33][1] < 8 and math.abs(pal[33][2] - 0x8b) < 4 and math.abs(pal[33][3] - 0xb4) < 4,
   "interface_tiles.NCLR row 2 does not start 008bb4")
-- the pressed blocks differ from the unpressed ones
ok(images.hammer_btn_up.rgba ~= images.hammer_btn_down.rgba, "hammer up and down are the same picture")
ok(images.pickaxe_btn_up.rgba ~= images.pickaxe_btn_mid.rgba, "pickaxe up and mid are the same picture")

-- 2. the sequences the screen plays are the NANR's
local anim = N.parse(rom:read("/data/ug_anim.narc"))
local nanr = Anim.parse(anim:get(A.find("/data/ug_anim.narc", "animations_anim.NANR")), G)
local Screen = require("src.ui.Gen4MiningScreen")
for seq = 0, 10 do
  local frames = Anim.frames(nanr, seq)
  local mine = Screen.SEQUENCES[seq]
  local same = frames and mine and #frames == #mine
  if same then
    for i, f in ipairs(frames) do
      if f.cell ~= mine[i][1] or f.duration ~= mine[i][2] then same = false end
    end
  end
  ok(same, "sequence %d differs from animations_anim.NANR", seq)
end
-- crack_end_anim: animation k (1..6) is the single cell k - 1
local crack = Anim.parse(anim:get(A.find("/data/ug_anim.narc", "crack_end_anim.NANR")), G)
for k = 1, 6 do
  local f = Anim.frames(crack, k)
  ok(f and #f == 1 and f[1].cell == k - 1, "crack_end animation %d is not cell %d", k, k - 1)
end
for integrity = 0, 196 do
  local cell, x, y = Screen.crackEnd(integrity)
  local rounded = math.floor(integrity / 4) * 4
  ok(cell == 6 - (rounded % 24) / 4 - 1 and x == rounded + 16 and y == 16,
     "crack end at integrity %d is cell %d at %d,%d", integrity, cell, x, y)
end
ok(Screen.cellOf(0, 0) == 5 and Screen.cellOf(0, 2) == 6 and Screen.cellOf(0, 100) == 0,
   "cellOf does not walk a sequence to its empty end")

-- 3. the menu art
local menu = assert(require("src.import.Gen4MenuArt").images(rom))
for _, key in ipairs({ "cursor", "ug_cursor" }) do
  local p = menu[key]
  ok(p and p.width == 96 and p.height == 32 and p.originX == -48 and p.originY == -16,
     "%s is not a 96x32 cell from (-48, -16)", key)
  -- ROW 1: its edge is the orange 255,106,16 (menu.NCLR entry 31), not grey
  local orange = 0
  if p then
    for y = 0, p.height - 1 do
      for x = 0, p.width - 1 do
        local r, g, b, a = pixel(p, x, y)
        if a ~= 0 and r > 240 and g > 90 and g < 120 and b < 30 then orange = orange + 1 end
      end
    end
  end
  ok(orange > 50, "%s has %d orange pixels; it is not in palette row 1", key, orange)
end
for i = 0, 6 do
  local grey, colour = menu[("ug_icon_%d_grey"):format(i)], menu[("ug_icon_%d_colour"):format(i)]
  ok(grey and colour and grey.width == 32 and colour.originX == -16,
     "underground icon %d is missing or not 32x32 from (-16, -16)", i)
  ok(grey and colour and grey.rgba ~= colour.rgba, "underground icon %d: grey and colour are the same", i)
end

print(("%d checks, %d failed"):format(checks, fails))
if fails > 0 then error("gen4_mining_sprites_check failed") end
