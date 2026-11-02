-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S FIELD WEATHER -> constants.gen5Weather.
--
-- READ FROM CODE (Black):
--   * a zone's own weather: zone header (/a/0/1/2, 48 bytes a zone) +0x1C,
--     bits 0..5 (arm9 0x02013C10)
--   * the WEATHER CALENDAR, /a/0/9/7 (ov10 0x021647FC opens archive 0x61):
--     member 1 is a u16 count (68) and that many { u16 zone, u16 base }
--     (0x02164890 reads them, 0x021648A8 looks a zone up); member 0 is one
--     weather byte a day, at base + the day of the year (0x021648CC: the
--     days of the months before, February always 29, plus the day - 1)
-- The runtime is src/world/Gen5Weather.lua.

local M = {}

M.ZONES = "/a/0/1/2"
M.CALENDAR = "/a/0/9/7"

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local Narc = require("src.import.NarcArchive")
  local out = { zones = {}, calendar = {} }
  local okZ, zb = pcall(function() return Narc.parse(rom:read(M.ZONES)):get(0) end)
  if okZ and zb then
    for z = 0, math.floor(#zb / 48) - 1 do
      local w = u16(zb, z * 48 + 0x1C) % 64
      if w ~= 0 then out.zones[z] = w end
    end
  end
  local okC, arc = pcall(function() return Narc.parse(rom:read(M.CALENDAR)) end)
  if okC and arc then
    local days, idx = arc:get(0), arc:get(1)
    local n = idx and u16(idx, 0) or 0
    for i = 0, n - 1 do
      local zone, base = u16(idx, 2 + i * 4), u16(idx, 4 + i * 4)
      local hex = {}
      for d = 0, 365 do hex[#hex + 1] = ("%02x"):format(days:byte(base + d + 1) or 0) end
      out.calendar[zone] = table.concat(hex)
    end
  end
  return out
end

return M
