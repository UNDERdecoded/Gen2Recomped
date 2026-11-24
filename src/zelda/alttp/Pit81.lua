-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 81: the pit takes Link one frame after he first stands over it.
--
-- The cartridge's Link state table (0x081680AC) runs LinkState_Default
-- (0x0809D5CC) on the ground: it moves Link (0x080975B4) and then runs his
-- tile collision (0x0809407C), whose Player_TileDetectNearby (0x0809EDA4)
-- notes the pit tiles under his four points and hands him to the pit state
-- (state 1, 0x0809AD6C). Only that state, on the NEXT frame and before
-- moving him, reads the four points again (`bl 0x0809EDA4` at 0x0809AEC4):
-- all four on a pit (`cmp r1, #0xF` at 0x0809AF44) starts the fall, some of
-- them pull him towards it. Between the two frames the sprites run, and the
-- Somaria platform (Sprite_ED, 0x08110914 -> the contact test 0x080C46EC)
-- marks Link as standing on it, after which the pit tiles do not count
-- (TileBehavior_Pit, Floors27.lua).
--
-- The port (Dungeons26.pitCheck, after Doors.move) started the fall in the
-- very frame Link's four points first met the pit. At Turtle Rock's
-- entrance (room 0xD6) the track's end sits two pit rows above the ledge:
-- Link's walk from y 265 to 263 put all four points over the pit before
-- the platform (its hit box 16 px high, Link's 8 x 8 at y + 8) could take
-- him, and every boarding fell. Now the first frame over a pit only enters
-- the pit state; the fall (or the pull) comes from the next frame's test.
-- No ROM reads.

local M = { NAME = "pit81" }

function M.extract(rom, R, check) return {} end

function M.install(G)
  if G.pit81Installed then return end
  G.pit81Installed = true
  local D = require("src.zelda.alttp.Dungeons26")
  local pit0 = D.pitCheck
  function D.pitCheck(g)
    local inside, lk = g.interior, g.link
    if inside and lk and not g.pitFall and not g.roomScroll and not lk.hop and not g.climb
       and (g.onPlatform or 0) == 0 and not g.pipeOwner then
      if g.pitState81 ~= inside then
        -- LinkState_Default's collision after the move: into the pit state, nothing more
        if D.pitBits(inside, lk.x, lk.y) ~= 0 then
          g.pitState81 = inside
          g.pitEntries81 = (g.pitEntries81 or 0) + 1
        end
        return false
      end
      -- the pit state: the four points where the frame began (before the move)
      local pre = g.pre81
      local px, py = pre and pre[1] or lk.x, pre and pre[2] or lk.y
      local bits = D.pitBits(inside, px, py)
      if bits == 0 then
        if D.pitBits(inside, lk.x, lk.y) == 0 then g.pitState81 = nil end
        return false
      end
      -- the fall (from where he stood: this frame's step is not taken) or
      -- the pull, both decided at the frame's first position
      local dx, dy = lk.x - px, lk.y - py
      lk.x, lk.y = px, py
      local fell = pit0(g)
      if not fell then lk.x, lk.y = lk.x + dx, lk.y + dy end
      return fell
    end
    return pit0(g)
  end
  -- the position each frame's walk starts from
  local Doors = require("src.zelda.alttp.Doors")
  local move0 = Doors.move
  function Doors.move(g, inp)
    local lk = g.link
    if lk then g.pre81 = { lk.x, lk.y } end
    return move0(g, inp)
  end
end

return M
