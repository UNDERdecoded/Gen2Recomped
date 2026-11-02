-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S ICE BLOCKS (Seafoam Islands B3F, SPRITE_ICE 406).
--
-- pokeheartgold, read from code:
--
--   * THE TRIGGER (asm/unk_0205CB48.s sub_0205D0A8, the player's move on an
--     ICE tile): the way ahead is blocked -> sub_0206D494 (src/unk_0206D494.c).
--     The object in front (sub_0206D590: the player's x / z + the facing
--     delta, height within 2) must be SPRITE_ICE and FACING SOUTH -- a block
--     that has come to rest against another object faces north and is fixed
--     for good. Then SEQ_SE_GS_HYOUKAI_HIT and the task; no Strength.
--   * THE TASK (sub_0206D4E4 / sub_0206D688): SEQ_SE_GS_HYOUKAI_SUBERU while
--     the block runs; each step asks the tile ahead of it (sub_0206D7B8):
--       an OBJECT there  -> LockDir-free stop: the block (and that object,
--                           if it is another block) turn north, SEQ_SE_GS_
--                           HYOUKAI_KETUGOU -- joined, never pushed again
--       a wall, or ground that is not ice -> it just stops (still south)
--       else             -> LockDir, then a normal step (MOVEMENT_STEP_<dir>,
--                           WalkNormal) in the PLAYER'S facing, facing kept
--     then the slide sound stops and the player's forced movement clears.
-- Without it the blocks were plain walls ("no text for Seafoam Islands") and
-- B3F's ice could not be arranged.

local M = {}

M.SPRITE_ICE = 406
M.SE_HIT, M.SE_SLIDE, M.SE_JOIN = "SEQ_SE_GS_HYOUKAI_HIT", "SEQ_SE_GS_HYOUKAI_SUBERU", "SEQ_SE_GS_HYOUKAI_KETUGOU"

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function Game() return package.loaded["src.core.Game"] end

local function se(name, stop)
  local G = Game()
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and G) then return end
  if stop then
    if Sound.stopSe then pcall(Sound.stopSe, G.data, name) end
  elseif Sound.playSe then
    pcall(Sound.playSe, G.data, name)
  end
end

local function isHgss(ow)
  local def = ow and ow.map and ow.map.def
  return def and def.generation == 4 and def.cameraFamily == "hgss" or false
end

function M.isBlock(npc)
  return npc ~= nil and not npc.hidden and npc.def ~= nil and tonumber(npc.def.graphicsId) == M.SPRITE_ICE
end

-- the visible object standing on (x, y), the block itself aside
local function objectAt(ow, x, y, except)
  for _, e in ipairs(ow.entities or {}) do
    if e ~= except and not e.hidden and not e.passable
       and ((e.cellX == x and e.cellY == y) or (e.targetX == x and e.targetY == y)) then
      return e
    end
  end
  return nil
end

-- sub_0206D494: the player, on ice, was stopped moving `dir`. True when an
-- ice block in front took the push.
function M.tryPush(ow, dir)
  if not isHgss(ow) or ow.hgssIceBlock then return false end
  local p = ow.player
  if not (p and ow.isIceCell and ow:isIceCell(p.cellX, p.cellY)) then return false end
  local d = DELTA[dir]
  if not d then return false end
  local npc = ow.npcAtCell and ow:npcAtCell(p.cellX + d[1], p.cellY + d[2])
  if not (M.isBlock(npc) and npc.facing == "down" and not npc.moving) then return false end
  se(M.SE_HIT)
  ow.hgssIceBlock = { npc = npc, dir = dir }
  p.facing = dir
  se(M.SE_SLIDE)
  M.step(ow)
  return true
end

-- one tile of the block's run (sub_0206D688 state 0), chained through the
-- scripted-move queue so the field waits on it
function M.step(ow)
  local s = ow.hgssIceBlock
  if not s then return end
  local npc, d = s.npc, DELTA[s.dir]
  local nx, ny = npc.cellX + d[1], npc.cellY + d[2]
  local map = ow.map
  local other = objectAt(ow, nx, ny, npc)
  if other == ow.player then other = nil end
  if other then
    se(M.SE_SLIDE, true)
    se(M.SE_JOIN)
    npc.facing = "up"
    if M.isBlock(other) then other.facing = "up" end
    ow.hgssIceBlock = nil
    return
  end
  local wall = not (map and map.isWalkableCell and map:isWalkableCell(nx, ny))
  local notIce = not (ow.isIceCell and ow:isIceCell(nx, ny))
  if wall or notIce then
    se(M.SE_SLIDE, true)
    ow.hgssIceBlock = nil
    return
  end
  -- LockDir + MOVEMENT_STEP_<dir>: a normal step, the block still facing south
  ow:scriptMove(npc, s.dir, 1, function() M.step(ow) end, true)
end

return M
