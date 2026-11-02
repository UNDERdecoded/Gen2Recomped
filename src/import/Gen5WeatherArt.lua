-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE FIELD WEATHER'S PICTURES, /a/0/5/6 -> constants.gen5WeatherArt +
-- gen4/bw_weather/*.png.
--
-- READ FROM CODE (Black, ov21): the weather table 0x021D8868 is fifteen
-- { record, overlay } pairs (24..28); each record (in its overlay) opens
-- with u16 archive 0x38 (/a/0/5/6, opened at 0x021A298C), u16 "has sprites",
-- a u16 variant, then the sprite's NCGR / NCLR / NCER / NANR members
-- (loaded at 0x021A29A8: +6 char, +8 palette, +0xA cell, +0xC animation),
-- then up to two 6-u16 texture records (member, 0, size, 3, 0x0102 ...) for
-- the BTX0 sheets 0x27..0x2B, the work size at +0x28 and the eight
-- callbacks at +0x2C (+0x48 is the per-particle update, 0x021A27F8).
--   1 snow      char 0x17 pal 0x18 cell 0x16 anim 0x15
--   2 rain      char 0x0D pal 0x0E cell 0x0C anim 0x0B
--   3 / 12 sand char 0x22 pal 0x23 cell 0x21 anim 0x20, texture 0x2B
--   4 blizzard  char 0x1F pal 0x18 cell 0x1E anim 0x1D, texture 0x2A
--   5 hail      char 0x02 pal 0x03 cell 0x01 anim 0x00
--   6 thunder   char 0x11 pal 0x0E cell 0x10 anim 0x0F, texture 0x29
--   7 storm     char 0x06 pal 0x07 cell 0x05 anim 0x04, textures 0x28, 0x27
--   8 diamond dust char 0x1B pal 0x1C cell 0x1A anim 0x19
--   0 / 9..11 / 13 / 14 (none, mists): no resources in the record
-- Each cell is written whole (its OAM entries composed; a "particle" is one
-- cell, which can be a whole curtain of drops) with its origin, and each
-- NANR sequence as { cell, duration } frames.

local M = {}

M.PATH = "/a/0/5/6"
M.SPRITES = {
  [1] = { char = 0x17, pal = 0x18, cell = 0x16, anim = 0x15 },
  [2] = { char = 0x0D, pal = 0x0E, cell = 0x0C, anim = 0x0B },
  [3] = { char = 0x22, pal = 0x23, cell = 0x21, anim = 0x20, textures = { 0x2B } },
  [4] = { char = 0x1F, pal = 0x18, cell = 0x1E, anim = 0x1D, textures = { 0x2A } },
  [5] = { char = 0x02, pal = 0x03, cell = 0x01, anim = 0x00 },
  [6] = { char = 0x11, pal = 0x0E, cell = 0x10, anim = 0x0F, textures = { 0x29 } },
  [7] = { char = 0x06, pal = 0x07, cell = 0x05, anim = 0x04, textures = { 0x28, 0x27 } },
  [8] = { char = 0x1B, pal = 0x1C, cell = 0x1A, anim = 0x19 },
}
M.SPRITES[12] = M.SPRITES[3]

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local G = require("src.import.Gen4Graphics")
  local Narc = require("src.import.NarcArchive")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local Models = require("src.import.Gen4Models")
  local arc = assert(Narc.parse(assert(rom:read(M.PATH))))
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local function save(rel, image)
    local saved = image and x.saveImage and x:saveImage("bw_weather/" .. rel, image)
    return saved and (type(saved) == "table" and saved.path or saved) or nil
  end
  local out = { source = "ROM:" .. M.PATH .. " (ov21 0x021D8868)", sets = {}, textures = {} }
  local done = {}
  for id, spec in pairs(M.SPRITES) do
    local key = spec.char .. ":" .. spec.cell
    if not done[key] then
      local sheet = G.tiles(member(spec.char))
      local bank = Cells.parse(member(spec.cell), G)
      local anim = Anim.parse(member(spec.anim), G)
      local colours = G.palette(member(spec.pal))
      local set = { cells = {}, sequences = {} }
      if sheet and bank and colours then
        local pal = Anim.paletteFor(colours, Anim.bankOf(bank))
        for ci, cell in ipairs(bank.cells or {}) do
          local pic = Cells.assemble(cell, sheet, pal, bank, G)
          if pic then
            local ox, oy = Cells.extent(cell)
            set.cells[ci] = { path = save(("c%02x_%d"):format(spec.cell, ci - 1), pic),
                              x = ox, y = oy, w = pic.width, h = pic.height }
          end
        end
      end
      for si, seq in ipairs(anim and anim.sequences or {}) do
        local frames = {}
        for _, f in ipairs(seq.frames or {}) do frames[#frames + 1] = { cell = f.cell, duration = f.duration } end
        set.sequences[si] = frames
      end
      done[key] = set
    end
    out.sets[id] = done[key]
  end
  -- the BTX0 sheets (0x27..0x2B)
  for t = 0x27, 0x2B do
    local b = member(t)
    local at = b and b:find("TEX0", 1, true)
    local tex = at and Models.parse(b, at - 1)
    if tex and tex.textures and tex.textures[1] then
      -- (INFERRED: index 0 is the clear between the streaks -- the sheets do
      -- not set transparent0, and decoded opaque they black out the field)
      tex.textures[1].transparent0 = true
      local image = Models.decode(tex, b, 1, 1)
      out.textures[t] = { path = save(("t%02x"):format(t), image), name = tex.textures[1].name,
                          w = image and image.width, h = image and image.height }
    end
  end
  -- the weathers' LIGHT files, /a/0/6/2 (archive 0x3E, loaded by each
  -- program through 0x021A2108 with member arm9 0x0209E054[weather],
  -- 0x02014A10): 52-byte records by time of day ({u16 hour, s16 minute,
  -- 4 light flags, 4 colours, 4 directions, diffuse, ambient, specular,
  -- emission, FOG COLOUR (+48, written to FOG_COLOR by 0x021A066C ->
  -- 0x021A01C4 / 0x021A0170), clear colour}), picked by 0x021A07B4
  local okL, larc = pcall(function() return require("src.import.NarcArchive").parse(rom:read("/a/0/6/2")) end)
  if okL and larc then
    out.lights = {}
    for m = 0, larc.count - 1 do
      local d = larc:get(m) or ""
      local recs = {}
      for i = 0, math.floor(#d / 52) - 1 do
        local o = i * 52
        local function h(k) return (d:byte(o + k + 1) or 0) + (d:byte(o + k + 2) or 0) * 256 end
        local minute = h(2); if minute >= 0x8000 then minute = minute - 0x10000 end
        recs[#recs + 1] = { t = h(0) * 3600 + minute * 60, fog = h(48) }
      end
      out.lights[m] = recs
    end
  end
  -- the snow's sideways sway, ov25 0x021EF790 in Black: 337 s8 steps
  -- (0x021EE9C4, phase + 1 mod 0x151), found by its opening in either
  -- cartridge's overlay 25
  local ov = rom.overlay and rom:overlay(25)
  if ov then
    local sig = string.char(0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1)
    local at = ov:find(sig, 1, true)
    if at and #ov >= at + 336 then
      local t = {}
      for i = 0, 336 do local v = ov:byte(at + i); if v >= 128 then v = v - 256 end; t[i + 1] = v end
      out.snowSway = t
    end
  end
  return out
end

return M
