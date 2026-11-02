-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LAYERED FIELD THEMES, /a/1/4/7 -> constants.gen5MusicParts.
--
-- READ FROM CODE (Black, arm9): the field's sound system keeps a "parts"
-- manager (game system +0x20, made at 0x0202C070 -> 0x0202C148) that loads
-- every member of archive 0x93 (/a/1/4/7) through 0x0202C3E0:
--   +0   u32  the BGM sequence the record belongs to (matched against the
--             playing sequence by 0x0202C268)
--   +4   u16[9] a TRACK MASK per part (part 0 is the base band, 1..8 the
--             players a script can bring in)
--   +22  u16  the fade length in frames, shared by the nine parts
--   +24  u8   n, then n u16 zone ids: the zones the record stays live in
--             (0x0202C218 drops it when the player leaves them)
-- Black has three: SEQ 0x42B (zone 75), 0x422 SEQ_BGM_H_04 (Village Bridge,
-- zones 255..262: four players) and 0x3FB (Accumula Town, zones 397..405:
-- two), all with a 60-frame fade. The runtime is src/world/Gen5MusicParts.lua.

local M = {}

M.PATH = "/a/1/4/7"

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

function M.parse(d)
  if not d or #d < 25 then return nil end
  local rec = { seq = u32(d, 0), masks = {}, fade = u16(d, 22), zones = {} }
  for i = 0, 8 do rec.masks[i] = u16(d, 4 + i * 2) end
  local n = d:byte(25) or 0
  for i = 0, n - 1 do
    if 25 + i * 2 + 2 <= #d then rec.zones[#rec.zones + 1] = u16(d, 25 + i * 2) end
  end
  return rec
end

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local ok, bytes = pcall(function() return rom:read(M.PATH) end)
  if not (ok and bytes) then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(bytes)
  local out = {}
  for i = 0, arc.count - 1 do
    local rec = M.parse(arc:get(i))
    if rec then out[#out + 1] = rec end
  end
  return out
end

return M
