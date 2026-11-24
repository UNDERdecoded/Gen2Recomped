-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 97: a sprite under the floor has no hit box (Sprite_SetupHitBox's
-- negative-height rule).
--
-- Traced on the GBA: Sprite_SetupHitBox (0x080C4574) loads the sprite's
-- height (+0x1142) signed (`ldrsb` at 0x080C4584); when it is below 0
-- (`bge` not taken) it only writes 0x80 to the box's x high byte (+0x974,
-- `movs r0, #0x80` at 0x080C458E) and returns: the box is 0x8000 px away
-- and nothing (the sword, arrows, the rods, Link's body) can meet it.
-- The Lanmolas sit at height -1 (0xFF) while waiting, as a mound and under
-- the sand: in the port their box was still at the mound, so a Fire Rod
-- shot or an arrow burst on a buried Lanmola for nothing (Ganon's Tower
-- 0x6C: four of six shots lost). The port's Actors.hitbox now returns a box
-- far away for a sprite with z < 0, as the cartridge.
-- No ROM data; the extract only checks the routine's shape.

local bit = require("bit")
local band = bit.band

local M = { NAME = "hitbox97" }

M.SITES = { setup = 0x080C4574, ldrsb = 0x080C4584, bge = 0x080C4588, far = 0x080C458E }
M.FAR = 0x8000

local function off(a) return a - 0x08000000 end

function M.extract(rom, R, check)
  local S = M.SITES
  local push = rom:u16(off(S.setup))
  local ld, bge, far = rom:u16(off(S.ldrsb)), rom:u16(off(S.bge)), rom:u16(off(S.far))
  -- push {.., lr}; ldrsb r0, [rX, r0] (0x5600 group); bge (0xDA..); movs r0, #0x80
  local ok = band(push, 0xFF00) == 0xB500 and band(ld, 0xFE00) == 0x5600 and band(bge, 0xFF00) == 0xDA00
             and far == 0x2080
  check(ok, "hitbox97: Sprite_SetupHitBox's negative-height rule")
  if not ok then return {} end
  return { far = M.FAR }
end

-- the box of a sprite: unchanged at height >= 0, far away below the floor
function M.wrap(hitbox)
  return function(cb, a)
    local x, y, w, h = hitbox(cb, a)
    if (a.z or 0) < 0 then return x + M.FAR, y + M.FAR, w, h end
    return x, y, w, h
  end
end

function M.install(G)
  if G.hitbox97Installed then return end
  G.hitbox97Installed = true
  local A = require("src.zelda.alttp.Actors")
  A.hitbox = M.wrap(A.hitbox)
end

return M
