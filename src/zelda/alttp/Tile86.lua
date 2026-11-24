-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 86: a sprite's tile collision in two-layer rooms checks all four
-- directions.
--
-- Sprite_CheckTileCollision's core (GBA 0x080C7014, sprite k in r4, the
-- sprite block in r5):
--   * +0x1132[k] (sprite_flags4) & 0x20: the single point (0x080C7490),
--     as before (Palace.lua's first branch);
--   * else, +0x1132[k] & 0x80 clear and the halfword +0xB14 (the room
--     header's collision mode, dung_hdr_collision: compared with 0..4 all
--     over the code, e.g. 0x080C6C90 / 0x080C724C) not 0 -> 0x080C7A80:
--     the vertical test 0x080C7384 for direction 1 (down) then 0 (up),
--     the horizontal test 0x080C7278 for 3 (right) then 2 (left), then
--     0x080C70E8 (the slope / pit step the single-layer path also ends
--     with) -- whatever the sprite's speed;
--   * else (0x080C7090): only the directions of a non-zero speed (y speed
--     sign -> 1 / 0, x speed sign -> 3 / 2), as the port did everywhere.
-- Each directional test (0x080C7384 / 0x080C7278) sets the direction's
-- wall bit and pushes the sprite back by one step (three while recoiling),
-- the port's existing rule.
-- No data here: the flags4 bytes are the import's (roomIdx.combat.flags4,
-- or a sprite's own a.flags4), the collision mode is the room header's
-- byte 0 bits 2-4 (as DesertPalace.lua reads it).
-- OURS: the "& 7 <= 4" guard of the push (0x080C73C0) is not modelled (as
-- before r86).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = { NAME = "tile86" }
M.FLAG = 0x80                 -- +0x1132 bit tested at 0x080C706C
M.ORDER = { 1, 0, 3, 2 }      -- 0x080C7A80's order: down, up, right, left

-- the room header's collision mode (dung_hdr_collision, GBA +0xB14)
function M.collision(inside)
  local b0 = inside and inside.hdr and inside.hdr[1] or 0
  return band(rshift(b0, 2), 7)
end

function M.flags4(game, a)
  if a.flags4 then return a.flags4 end
  local cb = game and game.data and game.data.roomIdx and game.data.roomIdx.combat
  return (cb and cb.flags4 and cb.flags4[a.type + 1]) or 0
end

-- true when sprite `a` takes the four-direction branch in this room
function M.allDirs(game, inside, a)
  if M.disabled then return false end
  return band(M.flags4(game, a), M.FLAG) == 0 and M.collision(inside) ~= 0
end

-- the four tests; solidAt(j) answers the probe j = base + direction
function M.check(a, base, n, solidAt, wallbit)
  for _, d in ipairs(M.ORDER) do
    if solidAt(base + d) then
      a.wall = bit.bor(a.wall or 0, wallbit[d])
      if d == 1 then a.y = a.y - n elseif d == 0 then a.y = a.y + n
      elseif d == 3 then a.x = a.x - n else a.x = a.x + n end
      M.pushes = (M.pushes or 0) + 1
    end
  end
  return a.wall
end

return M
