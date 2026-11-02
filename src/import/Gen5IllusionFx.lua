-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S SCRIPTED FIELD OBJECTS -> constants.gen5FieldFx: Zorua's
-- illusion (/a/2/0/4, overlay 59) and N's Castle's (/a/2/1/9, overlay 64).
--
-- READ FROM CODE (Black, overlay 59): its resource table 0x021F3F74 lists
-- archive 0xCC (/a/2/0/4) members {4, 0, 5, 7, 6, 1, 3, 2}, and the two
-- effects of 0x021F3EC4 are effect 0 = model 4 with animations 5 (BCA), 7
-- (BTP), 6 (BMA), effect 1 = model 0 with 1 (BCA), 3 (BTP), 2 (BMA); 0x021F3AA0
-- plays SE 0x567 (effect 0) or 0x793 (effect 1). Packed the way
-- Gen4HgssFieldFx packs a field object (model, joint tracks, texture and
-- material records), the pictures under bw_illusion/.
-- READ FROM CODE (overlay 64): its resource table 0x021F3CCC lists archive
-- 0xDB (/a/2/1/9) members {0, 1, 2, 3, 4, 6, 7, 9, 8}; effect 0 = model 0
-- with animations 1 (BCA), 2 (BMA), 3 (BTA), 4 (BTP) (list 0x021F3C10),
-- effect 1 = model 6 with 7 (BCA), 9 (BTP), 8 (BMA) (list 0x021F3C04).

local M = {}

M.PATH = "/a/2/0/4"
M.PARTS = { bwIllusion0 = { model = 4, anims = { 5, 7, 6 } }, bwIllusion1 = { model = 0, anims = { 1, 3, 2 } } }
M.CASTLE_PATH = "/a/2/1/9"
M.CASTLE_PARTS = { bwCastle0 = { model = 0, anims = { 1, 2, 3, 4 } }, bwCastle1 = { model = 6, anims = { 7, 9, 8 } } }

function M.build(x)
  if not (x and x.rom) then return nil, "no rom" end
  -- the pictures go under bw_illusion/ rather than the field effects' folder
  local function proxy(dir)
    return setmetatable({ saveImage = function(_, rel, image, extra)
      return x:saveImage((rel:gsub("^field_fx/", dir .. "/")), image, extra)
    end }, { __index = x })
  end
  local FX = require("src.import.Gen4HgssFieldFx")
  local out = FX.build(proxy("bw_illusion"), { path = M.PATH, parts = M.PARTS,
    source = "ROM:" .. M.PATH .. " (ov59 0x021F3AA0) + " .. M.CASTLE_PATH .. " (ov64)" })
  local okC, castle = pcall(FX.build, proxy("bw_castle"), { path = M.CASTLE_PATH, parts = M.CASTLE_PARTS })
  if okC and castle then for k, v in pairs(castle.parts) do out.parts[k] = v end end
  return out
end

return M
