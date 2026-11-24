-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 83: Link's facing on the Somaria platform, traced (Ride82's
-- inferred part).
--
-- Ride82 let the held d-pad turn Link on a moving platform on every frame,
-- keeping the current facing while it is held. Traced on the GBA
-- (LinkState_Default 0x0809D5CC, zelda3's PlayerHandler_00 order):
--   0x0809D708..0x0809D824: while Link is busy the d-pad is NOT read --
--     the recoil (+0x16F8: the recoil handler 0x08099D98 and return), and
--     `b 0x0809D92E` (past the read) when +0x1809, +0x176D, +0x1808 & ~2
--     (grabbing), +0x1791 & 0x7F (an item in hand), +0x178A (an item's
--     position mode), +0x180C (lifting) or a sword swing (+0x176C <= 8 and
--     +0x16E8 & 0xA0 == 0x80) is set;
--   0x0809D8F0..0x0809D92C: otherwise a held direction (+0x16FC & 0xF)
--     becomes link_direction_last (+0x16CC); nothing held keeps it;
--   0x0809D95E -> Link_HandleMovingAnimation_FullLongEntry (0x08096F30):
--     the facing (+0x16D5) from link_direction_last: a vertical bit wins
--     (`& 0xC`: down if bit 4, else up), otherwise right if bit 1, else
--     left (0x08096FC8..0x08097016). Nothing in it or before it tests
--     player_on_somaria_platform (+0x1783); only the velocity (0x0809792E)
--     and the walk animation (0x080970FC) do.
-- So on the platform the d-pad turns Link exactly as on foot, but not while
-- he uses an item, swings, lifts or recoils -- during the fire rod's
-- swing a held direction does nothing until the rod is done. A held
-- facing is not kept (a diagonal turns him to its vertical). The pending
-- drag is still taken every frame (Ride82). No ROM reads.

local band8 = require("bit").band

local M = { NAME = "ride83" }

function M.extract(rom, R, check) return {} end

local L
local function link() L = L or require("src.zelda.alttp.Link") return L end

-- the d-pad's direction bits (8 up, 4 down, 2 left, 1 right)
local function dirBits(game)
  local i = game.input
  local function d(k) return i and i.isDown and i.isDown(k) and true or false end
  return (d("up") and 8 or 0) + (d("down") and 4 or 0) + (d("left") and 2 or 0) + (d("right") and 1 or 0)
end
M.dirBits = dirBits

-- Link_HandleMovingAnimation_FullLongEntry's facing from link_direction_last
function M.facing(dir)
  local Lk = link()
  if band8(dir, 0xC) ~= 0 then return band8(dir, 4) ~= 0 and Lk.DOWN or Lk.UP end
  return band8(dir, 1) ~= 0 and Lk.RIGHT or Lk.LEFT
end

-- the GBA's busy checks before the d-pad read, in the port's terms
function M.busy(game)
  if game.recoil or game.swing or game.bowUse or game.toolUse or game.hookUse or game.climb then return true end
  if game.carry and game.carry.phase == "lift" then return true end
  if game.receipt or game.holdItem then return true end
  return false
end

function M.frame(game)
  if (game.onPlatform or 0) ~= 2 or game.pipeOwner then return end
  local lk = game.link
  local dx, dy = game.dragX or 0, game.dragY or 0
  if dx ~= 0 or dy ~= 0 then
    lk.x, lk.y = lk.x + dx, lk.y + dy
    game.dragX, game.dragY = 0, 0
    game.rideDrags82 = (game.rideDrags82 or 0) + 1
  end
  if M.busy(game) then
    game.rideBusy83 = (game.rideBusy83 or 0) + 1
    return
  end
  local dir = dirBits(game)
  if dir == 0 then return end
  local f = M.facing(dir)
  if f ~= lk.facing then lk.facing = f; game.rideTurns82 = (game.rideTurns82 or 0) + 1 end
end

function M.install(G)
  if G.ride83Installed then return end
  G.ride83Installed = true
  -- Ride82's room-frame hook calls Ride82.frame: it runs this one instead
  require("src.zelda.alttp.Ride82").frame = M.frame
end

return M
