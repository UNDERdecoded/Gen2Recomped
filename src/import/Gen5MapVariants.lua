-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MAP REPLACEMENTS, /a/0/1/0 -> constants.gen5MapVariants.
--
-- READ FROM CODE (Black, ov10): the field's map load (0x02159CC4) opens
-- archive 0x0A (/a/0/1/0 -- one member, 16 bytes a record, 0x02159D84 /
-- 0x02159DCC) and for each record of the zone's matrix asks 0x02159E00 which
-- value applies:
--   +0  u16 the matrix the record belongs to (0 = Unova, 175 ...)
--   +2  u8  0: a CHUNK replacement -- every cell of the matrix holding the
--           first value gets the chosen one (0x02159C9A); 1: the MATRIX itself
--           is replaced by the chosen one (0x02159C86 -> 0x02159B94)
--   +3  u8  the condition: 0 the season, 1 the version (Black 0, White 1),
--           2 White's season + 1 (Black 0), 3..12 an event var equal to a
--           value (ov10 table 0x02170FB0)
--   +4  u16[5] the values, indexed by the condition's answer (+4 the base)
-- 47 records in Black: Icirrus / Route 8's chunks 64..69 -> 194..199 in
-- winter, chunks 3 / 4 -> 273..278 for summer / autumn / winter, matrix 93 ->
-- 193 and 183 -> 253 in winter, and the story's swaps.

local M = {}

M.PATH = "/a/0/1/0"

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local ok, d = pcall(function() return require("src.import.NarcArchive").parse(rom:read(M.PATH)):get(0) end)
  if not (ok and d) then return nil, "no " .. M.PATH end
  local out = { records = {} }
  for i = 0, math.floor(#d / 16) - 1 do
    local o = i * 16
    out.records[#out.records + 1] = { matrix = u16(d, o), kind = d:byte(o + 3), cond = d:byte(o + 4),
      values = { u16(d, o + 4), u16(d, o + 6), u16(d, o + 8), u16(d, o + 10), u16(d, o + 12) } }
  end
  -- THE SWAPPED-IN CHUNKS' OWN HEIGHTS (gen5-field-parts-v6). READ FROM THE
  -- DATA: winter's chunks do not keep the summer ground's heights -- 194 /
  -- 195 / 196 (Icirrus's snow, 0x02159C9A's swaps) differ from 64 / 65 / 66
  -- on 35 / 241 / 116 tiles, White's Opelucid 200..203 from 74..77 on 65..190
  -- (bw_cmds4/hcmp.lua); 197..199, 273..278 and 215..218 agree. The field
  -- reads a chunk's heights from the chunk itself (the 8-byte tiles of its
  -- permission section, Gen5Heights), so a swapped chunk walks on its own.
  -- For every chunk a record can bring in (a chunk record's values, every
  -- cell of a replacement matrix): { h = { [tile] = height }, s = { [tile] =
  -- true } } -- the flat tiles' non-zero heights and the slopes, as Gen5Field writes a
  -- def's gen4HeightEdits / gen5SlopeTiles (GC layers merged the same way).
  local okC, chunks = pcall(M.chunkHeights, rom, out.records)
  out.chunks = okC and chunks or nil
  return out
end

function M.chunkHeights(rom, records)
  local Narc = require("src.import.NarcArchive")
  local Maps = require("src.import.Gen5Maps")
  local F = require("src.import.Gen5Field")
  local H = F.HeightValues
  local values = H.build(rom) or {}
  local chunkArc = Narc.parse(rom:read(F.PATH.chunks))
  local mxArc = Narc.parse(rom:read(F.PATH.matrices))
  local want = {}
  for _, r in ipairs(records) do
    for k = 2, 5 do
      local v = r.values[k]
      if v ~= r.values[1] and v ~= 0 and v ~= 0xFFFF then
        if r.kind == 0 then want[v] = true
        else
          local m = Maps.matrix(mxArc:get(v))
          for i = 1, m and m.width * m.height or 0 do
            local c = m.chunks[i]
            if c and c ~= F.NO_CHUNK then want[c] = true end
          end
        end
      end
    end
  end
  local out = {}
  for c in pairs(want) do
    local ch = c < chunkArc.count and Maps.chunk(chunkArc:get(c)) or nil
    local raw = ch and ch.permissions
    if raw and ch.kind == "GC" and ch.layer2 then raw = F.mergeLayers(raw, ch.layer2) end
    if raw then
      local h, s = {}, {}
      for t = 0, F.CHUNK * F.CHUNK - 1 do
        local v = H.valueAt(raw, t)
        local y = v and values[v]
        if y then if y ~= 0 then h[t] = y end
        elseif H.isSlope(raw, t) then s[t] = true end
      end
      out[c] = { h = h, s = s }
    end
  end
  return out
end

return M
