-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE STREET CROWDS, /a/1/8/6 -> constants.gen5Walkers.
--
-- READ FROM CODE (Black, overlay 55, script command 0x134): the config
-- loader 0x021F3E84 opens archive 0xBA (/a/1/8/6), finds the zone in member
-- 5 (u32 zone ids, 0x021F3EC2) and reads that index's 0x32-byte record:
--   +0x00 u16[5]  frames between spawns, by the time of day (0x021F3F30)
--   +0x0C u8      number of spawn lines (at most 2)
--   +0x0D u8      number of sprites, +0x0E u16[4] their ids (0x021F3C40)
--   +0x18 u16     the walk speed: 2 / 4 / 6 / 8 / 16 -> movement 0x14 /
--                 0x10 / 0x4C / 0x0C / 0x08, else 0x0C (0x021F40F4)
--   +0x1A 12 bytes a line: u16 z0, z1, x0, x1, dir, steps -- a walker
--                 starts on z0 (dir 0 / 1) or x0 (dir 2 / 3), the other
--                 coordinate drawn from its range, and walks `steps` cells
--                 (0x021F3F9C)
-- and member 6, 16-byte rows { u32 sprite, u16[6] } (0x021F3C62: the walker
-- keeps one of the six at random beside its sprite).

local M = {}

M.PATH = "/a/1/8/6"

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local arc = require("src.import.NarcArchive").parse(assert(rom:read(M.PATH)))
  local zones = arc:get(5) or ""
  local out = { zones = {}, rows = {} }
  for i = 0, math.floor(#zones / 4) - 1 do
    local z = u32(zones, i * 4)
    local d = arc:get(i)
    if z ~= 0 and d and #d >= 0x32 then
      local c = { intervals = {}, sprites = {}, lines = {}, speed = u16(d, 0x18) }
      for k = 0, 4 do c.intervals[k + 1] = u16(d, k * 2) end
      for k = 0, d:byte(0x0D + 1) - 1 do c.sprites[k + 1] = u16(d, 0x0E + k * 2) end
      for k = 0, d:byte(0x0C + 1) - 1 do
        local o = 0x1A + k * 12
        c.lines[k + 1] = { z0 = u16(d, o), z1 = u16(d, o + 2), x0 = u16(d, o + 4), x1 = u16(d, o + 6),
                           dir = u16(d, o + 8), steps = u16(d, o + 10) }
      end
      out.zones[z] = c
    end
  end
  local rows = arc:get(6) or ""
  for i = 0, math.floor(#rows / 16) - 1 do
    local o = i * 16
    local t = {}
    for k = 0, 5 do t[k + 1] = u16(rows, o + 4 + k * 2) end
    out.rows[u32(rows, o)] = t
  end
  return out
end

return M
