-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK CITY / WHITE FOREST'S RESIDENTS, /a/1/5/4 -> constants.gen5BlackCity.
--
-- READ FROM CODE (Black, overlay 20): the resident data is archive 0x9A
-- (/a/1/5/4, opened at 0x021867C4). Members 0..29 are the 30 resident TYPES,
-- 48 bytes each:
--   +0x00 u16 the object's sprite (a map object graphics id)
--   +0x04 / +0x06 u16 a new resident's starting mood (White / Black; the
--         city's version byte picks, 0x021860D4) -- 20 or less and the
--         resident wants to move on (0x021867B4)
--   +0x18 u16 the trainer fought (0x1C4 kind 0)
--   +0x1C / +0x1E u16 the object's script in White / Black (0x02186538);
--         +0x20 / +0x22 the same for the second list
--   +0x2C u16 the weight a new city draws types by (0x021869E0; the 30
--         weights sum to 462 = 0x1CE, the draw's range)
-- Members 34 / 35 are the resident SPOTS for Black / White (0x02186830:
-- member 0x22 + the version byte), 20 (x, z) byte pairs in the zone's own
-- cells: 0..9 the residents (0x02186538), 10..19 the second list's
-- (0x021868B8).

local M = {}

M.PATH = "/a/1/5/4"

local function u16(s, o) return (s:byte(o + 1) or 0) + (s:byte(o + 2) or 0) * 256 end

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local ok, bytes = pcall(function() return rom:read(M.PATH) end)
  if not (ok and bytes) then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(bytes)
  -- graphics id -> sprite member, as Gen5Field keys the sheets
  local spriteOf = {}
  local okT, tb = pcall(function()
    local O = require("src.import.Gen5Overworld")
    return O.table(require("src.import.NarcArchive").parse(rom:read(O.TABLE)):get(0))
  end)
  if okT and type(tb) == "table" then spriteOf = tb end
  local out = { types = {}, spots = {}, source = "ROM:" .. M.PATH }
  for t = 0, 29 do
    local d = arc:get(t)
    if not d or #d < 48 then break end
    local g = u16(d, 0)
    local member = spriteOf[g]
    out.types[t] = {
      graphicsId = g,
      sprite = member and ("SPRITE_G4_%03d"):format(member) or nil,
      spriteName = member and ("bw_%03d"):format(member) or nil,
      mood = { white = u16(d, 4), black = u16(d, 6) },
      trainer = u16(d, 0x18),
      script = { white = u16(d, 0x1C), black = u16(d, 0x1E) },
      script2 = { white = u16(d, 0x20), black = u16(d, 0x22) },
      weight = u16(d, 0x2C),
      -- White Forest's Pokemon of the day (0x021862A8): one of three species,
      -- and the u16 at +0x24 that goes with it
      species = { u16(d, 8), u16(d, 0xA), u16(d, 0xC) }, forest = u16(d, 0x24),
    }
  end
  for k, key in pairs({ [34] = "black", [35] = "white" }) do
    local d = arc:get(k)
    if d and #d >= 40 then
      local spots = {}
      for i = 0, 19 do spots[i] = { x = d:byte(i * 2 + 1), z = d:byte(i * 2 + 2) } end
      out.spots[key] = spots
    end
  end
  return out
end

return M
