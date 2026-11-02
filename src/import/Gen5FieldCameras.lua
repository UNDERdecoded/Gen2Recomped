-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S FIELD CAMERA RECORDS -> constants.gen5Cameras: every
-- record of /a/0/6/0, decoded the way Gen5Field decodes a zone's own (see
-- THE CAMERAS there), for the scripts that switch the field camera to one by
-- number -- 0x1A3 in the Elite Four's rooms (src/script/Gen5MiscFieldOps.lua).

local M = {}

M.PATH = "/a/0/6/0"

function M.build(x)
  local rom = x and x.rom
  local bytes = rom and rom:read(M.PATH)
  local arc = bytes and require("src.import.NarcArchive").parse(bytes)
  local t = arc and arc:get(0)
  if not t then return nil end
  local function cu16(o) return t:byte(o + 1) + t:byte(o + 2) * 256 end
  local function cs32(o)
    local v = cu16(o) + cu16(o + 2) * 65536
    return (v >= 2147483648 and v - 4294967296 or v) / 4096
  end
  local out = { source = "ROM:" .. M.PATH, records = {} }
  for i = 0, math.floor(#t / 44) - 1 do
    local o = i * 44
    out.records[i + 1] = { id = ("bw_%d"):format(i), family = "bw",
      distance = cu16(o) + cu16(o + 2) * 65536,
      pitch = cu16(o + 4) * 360 / 65536, projection = "perspective",
      halfFov = cu16(o + 0x12) * 360 / 65536,
      near = 16, far = math.max(cu16(o + 0x1A), 32) * 16,
      offset = { x = cs32(o + 0x20), y = cs32(o + 0x24), z = cs32(o + 0x28) } }
  end
  return out
end

return M
