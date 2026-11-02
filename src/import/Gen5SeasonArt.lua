-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SEASON SPLASH'S PICTURES, /a/1/5/1 -> constants.gen5SeasonArt
-- (+ bw_season/s0..s3.png). READ FROM CODE (Black, ov20 0x0218794C):
-- archive 0x97, season s: member 3s the palette, 3s + 1 the chars, 3s + 2
-- the screen (256 x 256). The runtime is src/world/Gen5Season.lua.

local M = {}

M.PATH = "/a/1/5/1"

function M.build(x)
  local rom = x and x.rom
  if not rom then return nil, "no rom" end
  local G = require("src.import.Gen4Graphics")
  local Lz = require("src.import.Gen5Lz")
  local ok, bytes = pcall(function() return rom:read(M.PATH) end)
  if not (ok and bytes) then return nil, "no " .. M.PATH end
  local arc = require("src.import.NarcArchive").parse(bytes)
  local function member(i)
    local b = assert(arc:get(i))
    if Lz.isCompressed(b) then return assert(Lz.decompress(b)) end
    if G.isCompressed(b) then return assert(G.decompress(b)) end
    return b
  end
  local out = {}
  for s = 0, 3 do
    local pic = G.compose(assert(G.tilemap(member(3 * s + 2))), assert(G.tiles(member(3 * s + 1))),
      assert(G.palette(member(3 * s))))
    out[s] = pic and x:saveImage("bw_season/s" .. s, pic) or nil
  end
  return out
end

return M
