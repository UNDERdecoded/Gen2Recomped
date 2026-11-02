-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DOOR CAMERA'S ZONE RECORDS, /a/1/7/9 -> constants.gen5DoorCameras.
--
-- READ FROM CODE (ov21): a warp's transition type of 7 or more
-- (0x02162370: `type >= 7`) names a record of its own for the door camera
-- effect -- 0x021BE148 loads member (type - 7) of archive 0xB3 (/a/1/7/9,
-- 0x02048F4C) and the going-in / coming-out variants 0x021BDFB0 /
-- 0x021BE068 take the camera from it. 50 members of 64 bytes, sixteen u32:
--   [0]  the type itself (7..56)
--   [1]  u16 pitch, [2] u16 yaw (angles, 65536 a turn)
--   [3]  distance (whole units, << 12 into fx32)
--   [4]  1: [5..7] is the point looked at (whole units); 0: the player's
--   [8..10] the point's offset (whole units, << 12 -- so 0xFFFD9 is -39)
--   [11] frames the camera moves over (0: set at once, then a 16-frame hold,
--        0x021BDD48 / step 10)
--   [12] used going in (task +0x68), [13] used coming out (task +0x6C)
--   [14] [15] two camera flags (controller +0x44 / +0x48) -- not ported

local M = {}

M.PATH = "/a/1/7/9"
M.FIRST = 7

local function u32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  if not d then return 0 end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- a whole-unit value shifted into fx32 as the cartridge does (<< 12, 32-bit)
local function units(v)
  local fx = (v * 4096) % 4294967296
  if fx >= 2147483648 then fx = fx - 4294967296 end
  return fx / 4096
end

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local ok, bytes = pcall(function() return rom:read(M.PATH) end)
  if not (ok and bytes) then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(bytes)
  local out = {}
  for i = 0, arc.count - 1 do
    local d = arc:get(i)
    if d and #d >= 64 then
      local v = {}
      for k = 0, 15 do v[k] = u32(d, k * 4) end
      local pitch, yaw = v[1] % 65536, v[2] % 65536
      out[M.FIRST + i] = {
        pitch = (pitch >= 32768 and pitch - 65536 or pitch) / 65536 * 360,
        yaw = (yaw >= 32768 and yaw - 65536 or yaw) / 65536 * 360,
        distance = units(v[3]),
        usePoint = v[4] ~= 0, x = units(v[5]), y = units(v[6]), z = units(v[7]),
        offset = { units(v[8]), units(v[9]), units(v[10]) },
        frames = v[11], goingIn = v[12] ~= 0, comingOut = v[13] ~= 0,
      }
    end
  end
  return out
end

return M
