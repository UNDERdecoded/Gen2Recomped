-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S SCRIPTED FLIGHT PATHS -> constants.gen5FlightPaths: the
-- baked paths 0x15D flies an object along around the player (Tornadus /
-- Thundurus sweeping past at Z337, Z376).
--
-- READ FROM CODE (Black): 0x15D <path> (ov21 0x021D1A74 -> 0x021D1894)
-- loads member `path` of archive 0xCB (/a/2/0/3) through arm9 0x0201147C /
-- 0x020116E0. A member is a u32 frame count, three u8 flags -- translation,
-- rotation, scale tracks present (+4, +5, +6) -- a pad byte, then per frame
-- the present tracks' three floats each in the order scale, rotation,
-- translation (0x0201183C), each turned into fx32 (* 4096, rounded half away
-- from zero). Rotation is in degrees, translation in world units (16 a tile).

local M = {}

M.PATH = "/a/2/0/3"

local function f32(d, o)
  local b1, b2, b3, b4 = d:byte(o + 1, o + 4)
  if not b4 then return 0 end
  local bits = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  local sign = bits >= 2147483648 and -1 or 1
  local e = math.floor(bits / 8388608) % 256
  local m = bits % 8388608
  if e == 0 then return 0 end
  return sign * (1 + m / 8388608) * 2 ^ (e - 127)
end

-- one member -> { frames, t = { x, y, z, ... }, r = { ry, ... } } (only the
-- translation and the rotation's y are kept: those are all 0x021D1988 reads)
function M.parse(d)
  if not d or #d < 8 then return nil end
  local n = d:byte(1) + d:byte(2) * 256 + d:byte(3) * 65536 + d:byte(4) * 16777216
  local hasT, hasR, hasS = d:byte(5) ~= 0, d:byte(6) ~= 0, d:byte(7) ~= 0
  local per = (hasT and 1 or 0) + (hasR and 1 or 0) + (hasS and 1 or 0)
  if n <= 0 or per == 0 or #d < 8 + n * per * 12 then return nil end
  local function q(v) return v >= 0 and math.floor(v + 0.5) or -math.floor(-v + 0.5) end
  local out = { frames = n, t = {}, ry = {} }
  for f = 0, n - 1 do
    local o = 8 + f * per * 12
    if hasS then o = o + 12 end
    if hasR then out.ry[f + 1] = q(f32(d, o + 4) * 4096) / 4096; o = o + 12 end
    if hasT then
      local t = out.t
      t[#t + 1] = q(f32(d, o) * 4096) / 4096
      t[#t + 1] = q(f32(d, o + 4) * 4096) / 4096
      t[#t + 1] = q(f32(d, o + 8) * 4096) / 4096
    end
  end
  return out
end

function M.build(x)
  if not (x and x.rom) then return nil, "no rom" end
  local raw = x.rom:read(M.PATH)
  if not raw then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(raw)
  if not arc then return nil, "not a narc" end
  local out = { source = "ROM:" .. M.PATH .. " (ov21 0x021D1894)", paths = {} }
  for i = 0, (arc.count or 0) - 1 do
    local ok, d = pcall(arc.get, arc, i)
    out.paths[i + 1] = ok and M.parse(d) or false   -- member i at [i + 1]
  end
  return out
end

return M
