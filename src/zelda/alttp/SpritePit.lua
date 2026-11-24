-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 42: SPRITES FALLING INTO PITS (indoors), traced on the GBA.
--
--   Sprite_CheckTileCollision 0x080C6F48 -> SingleLayer 0x080C7014 -> the
--   floor probe 0x080C70E8: no flier (flags5 0x11B2 & 0x80), on the ground
--   (z 0x1142 == 0), Sprite_CheckTileProperty 0x080C7490 at probe byte 0x68
--   (kSprite_Func5 entry 0x34); tile type 0x20 and kSpriteInit_Flags
--   (0x227A81, sprite 0xD84) bit 0 -> indoors sprite_state 5, delay_main
--   0x3F for the Hardhat Beetle / Mini Helmasaur (their OAM name bit
--   cleared), 0x5F for the others (outdoors 0x080C8094: not here).
--   Sprite_ReturnIfRecoiling 0x080C1FD0 runs the same collision (0x080C79D0)
--   on its move frames: a knocked sprite drops in.
--   Sprite_CheckTileProperty's pit rule (0x080C7760): tile 0x20 is a wall to
--   every sprite, except a flags-bit-0 sprite while it recoils (sprite_F
--   0x1072 != 0). The pit-fallers by that bit: 0x0B, 0x13, 0x26, 0x41-0x4B.
--   SpriteModule_Fall2 (state 5, 0x080C8784; table 0x171D88): delay 0 ->
--   state 0 and Sprite_ManuallySetDeathFlagUW (no prize). Delay >= 0x40:
--   the sprite's routine runs (it returns at once: not active) and draws.
--   Below: graphics kFall_Gfx[delay >> 1] (0x172558 for 0x13 / 0x26, drawn
--   from 0x1725BC / 0x17258C, one OAM entry), and on frames where
--   (frame & kFall_Mask[delay >> 3]) == 0 (0x172578) it drifts at its recoil
--   / 4 (the recoil zeroed once the probe is off the pit), Sprite_MoveXY.
--
-- OURS: the probe is checked every recoil frame (the cartridge: its recoil
-- move frames); no sound (0x65 / 0x6C); the other pit-fallers' shrinking
-- picture (0x080C8998) is not drawn -- only the beetle / Mini Helmasaur use
-- this module (Hera.lua).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local SP = { PROBE = 0x34, PIT = 0x20 }

local function cbOf(actors) return actors.game.data.roomIdx.combat end
local function palTabs(game) return game.data.roomIdx and game.data.roomIdx.palace end
local function heraTabs(game)
  local d = require("src.zelda.alttp.Dungeons26").tabs(game)
  return d and d.hera
end

-- the tile type at a sprite's probe j (Sprite_CheckTileProperty), its layer
function SP.attrAt(actors, a, j)
  local cb = cbOf(actors)
  local inside = actors.inside
  if not inside then return nil end
  local x = a.x + (cb.sprPointX[j + 1] or 8)
  local y = a.y + (cb.sprPointY[j + 1] or 8)
  if x < 0 or y < 0 or x >= 512 or y >= 512 then return nil end
  local t = a.lower and inside.attrsLo or inside.attrs
  return t and t[math.floor(y / 8) * 64 + math.floor(x / 8)] or 0
end

-- kSpriteInit_Flags bit 0
function SP.faller(game, t)
  local T = palTabs(game)
  return T and band(T.sprFlags[t + 1] or 0, 1) ~= 0 or false
end

-- Sprite_CheckTileProperty's rule for tile 0x20: a wall unless the sprite
-- falls into pits and recoils
function SP.pitSolid(game, a)
  return not (a.recoil and SP.faller(game, a.type))
end

-- the floor probe's pit branch (0x080C70E8); true when the fall begins
function SP.floor(actors, a)
  if a.pitFall or a.dead then return false end
  local game = actors.game
  local cb = cbOf(actors)
  local t = a.type
  if band(cb.flags5 and cb.flags5[t + 1] or 0, 0x80) ~= 0 or (a.z or 0) ~= 0 then return false end
  if SP.attrAt(actors, a, SP.PROBE) ~= SP.PIT or not SP.faller(game, t) then return false end
  a.pitFall = true
  if t == 0x13 or t == 0x26 then
    a.oam = band(a.oam or 0, 0xFE)
    a.delay = 0x3F
  else
    a.delay = 0x5F
  end
  a.recoil = nil
  a.untouchable, a.noTouch = true, true
  game.spritePitFalls = (game.spritePitFalls or 0) + 1
  return true
end

-- SpriteModule_Fall2, one frame (the timers have run)
function SP.fallFrame(actors, a)
  local d = a.delay or 0
  if d == 0 then
    local km = actors.kills
    if km and a.index and a.index > 0 and actors.room then
      km.dead[actors.room] = km.dead[actors.room] or {}
      km.dead[actors.room][a.index] = true
    end
    a.dead, a.gone = true, true
    return
  end
  if d >= 0x40 then return end
  local tb = heraTabs(actors.game)
  if not tb or not tb.fallGfx then return end
  a.fallGfx = tb.fallGfx[rshift(d, 1) + 1] or 0
  if band(actors.frame or 0, tb.fallMask[rshift(d, 3) + 1] or 0) == 0 then
    if SP.attrAt(actors, a, SP.PROBE) ~= SP.PIT then a.rvx, a.rvy = 0, 0 end
    local function q(v) v = v or 0; return (v < 0) and -rshift(-v, 2) or rshift(v, 2) end
    a.vy, a.vx = q(a.rvy), q(a.rvx)
    require("src.zelda.alttp.Palace")._h.moveXY(a)
  end
end

-- the falling picture (one OAM entry of the type's fall table)
function SP.draw(spr, tb, a, x, y, f)
  local list = (a.type == 0x13) and tb.fallHelm or tb.fallHH
  if not list then return false end
  spr:drawDmd(a, list, a.fallGfx or 0, 1, x, y, band(f or 0, 0xFE))
  return true
end

return SP
