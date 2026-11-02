-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE GATES' ELECTRONIC BOARDS (import side; src/world/Gen5GateBoard.lua runs
-- them). READ FROM CODE in Black, the gate overlay (ov48, 0x021F36C0..):
--
--   /a/1/7/4  one 0x7C-byte record per board (0x021F392C picks the first
--             whose zone is the field's and whose version is 0 or the
--             cartridge's -- 20 White, 21 Black):
--     +0x00 zone  +0x04 version  +0x08 x  +0x0C y  +0x10 z (world units,
--     16 a cell, from the zone's corner)  +0x14 facing (1 / 3 turn the
--     camera's yaw a quarter)  +0x18 the date line  +0x1C (unread here)
--     +0x20 the outbreak line  +0x24..+0x44 nine local lines and
--     +0x48..+0x60 seven advertisements, picked by weekday (0x021F4104 ..
--     0x021F4290)  +0x64..+0x70 four zones whose weather the board reports
--     (427 none)  +0x74 the board model's animation  +0x78 lit
--   every line is a message of system bank 38 (0x26)
--   zone weather: the zone header's +0x1C bits 0..5 (arm9 0x02013C10, the
--     last answer of 0x0202C794 when no daily or event weather overrides it)
--   ov48 0x021F5124: weather -> its bank-38 word (181 "Sunny" ...)

local M = {}

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end
local function s32(s, o) local v = u32(s, o) if v >= 0x80000000 then v = v - 0x100000000 end return v end

M.PATH, M.ZONES, M.ZONE_BYTES = "/a/1/7/4", "/a/0/1/2", 48
-- Black's table, should ov48's not be found by shape
M.FALLBACK_WEATHER = { [0] = 181, 182, 183, 184, 186, 187, 190, 191, 189, 188, 188, 188, 185, 188, 188 }

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local okA, bytes = pcall(function() return rom:read(M.PATH) end)
  if not (okA and bytes) then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(bytes)
  local out = { records = {}, weather = {}, weatherWord = {} }
  for i = 0, arc.count - 1 do
    local d = arc:get(i)
    if d and #d >= 0x7C then
      local w = function(k) return s32(d, k * 4) end
      local r = { zone = w(0), version = w(1), x = w(2), y = w(3), z = w(4), facing = w(5),
                  date = w(6), unread = w(7), outbreak = w(8), lines = {}, places = {},
                  model = w(29), lit = w(30) }
      for k = 0, 15 do r.lines[k] = w(9 + k) end
      for k = 0, 3 do r.places[k] = w(25 + k) end
      out.records[#out.records + 1] = r
    end
  end
  -- (a NARC of one member, 48 bytes a zone -- src/import/Gen5Maps.lua)
  local okZ, zones = pcall(function()
    return require("src.import.NarcArchive").parse(rom:read(M.ZONES)):get(0)
  end)
  if okZ and zones then
    for z = 0, math.floor(#zones / M.ZONE_BYTES) - 1 do
      out.weather[z] = u16(zones, z * M.ZONE_BYTES + 0x1C) % 64
    end
  end
  -- the weather words: fifteen u32 starting 181, 182, 183, 184 in ov48
  local okO, ov = pcall(function() return rom:overlay(48) end)
  local key = string.char(181, 0, 0, 0, 182, 0, 0, 0, 183, 0, 0, 0, 184, 0, 0, 0)
  local at = okO and ov and ov:find(key, 1, true)
  for k = 0, 14 do
    out.weatherWord[k] = at and u32(ov, at - 1 + k * 4) or M.FALLBACK_WEATHER[k]
  end
  return out
end

return M
