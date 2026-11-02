-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CUTSCENE CAMERA'S PRESETS, /a/1/6/3: what script op 0x146 <preset,
-- frames> moves the camera to (READ FROM CODE, ov21 0x021B542C: the 44-byte
-- member is read whole -- 0x02048F4C with archive 0xA3 -- and handed to the
-- camera's move, 0x0218F900, with the frames). A record, as the seven in
-- Black stand:
--   +0x00 u16 pitch, +0x02 u16 yaw, +0x04 fx32 distance,
--   +0x08 / +0x0C / +0x10 fx32 x / y / z of the point looked at,
--   +0x14 u32, +0x18 / +0x1C / +0x20 u32 (1 1 1 in every record),
--   +0x24 u32, +0x28 u32 -- 1 only on the one record whose point is set
--   (preset 6, (248, 33, 88): the Route 10 badge gates' bars at (15.5, 5.5));
--   read here as "the point is used" -- INFERRED from the data, not the code

local M = {}

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function s32(s, o)
  local v = u16(s, o) + u16(s, o + 2) * 65536
  if v >= 0x80000000 then v = v - 0x100000000 end
  return v
end

M.PATH = "/a/1/6/3"

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local ok, bytes = pcall(function() return rom:read(M.PATH) end)
  if not (ok and bytes) then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(bytes)
  local out = {}
  for i = 0, arc.count - 1 do
    local d = arc:get(i)
    if d and #d >= 44 then
      out[i] = { pitch = u16(d, 0), yaw = u16(d, 2), distance = s32(d, 4) / 4096,
                 x = s32(d, 8) / 4096, y = s32(d, 12) / 4096, z = s32(d, 16) / 4096,
                 usePoint = s32(d, 40) ~= 0 }
    end
  end
  return out
end

return M
