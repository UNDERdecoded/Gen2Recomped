-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PEGASUS BOOTS DASH (round 19). The SNES routines the GBA keeps (zelda3
-- names; the action is the GBA's R button, where the SNES has A):
--
--   Link_PerformDash      R with nothing to talk to / open / lift, the boots
--                         owned (GBA inventory byte 0x39): link_countdown_
--                         for_dash = 29, link_dash_ctr = 64
--   LinkState_Dashing     the charge: 29 frames running in place; letting go
--                         of R stops it. Then the run: link_speed_setting 16
--                         (kSpeedMod[16] = 64, 4 px a frame) the way Link
--                         faces; any other direction pressed stops it
--                         (LinkState_ExitingDash); the sword is held out
--                         (button_b_frames 9) and the run's own hit box
--                         (kPlayerActionBoxRun: 16 x 16 ahead) hurts sprites
--   RepelDash / LinkApplyTileRebound
--                         a wall ahead: Link bounces back (speed 24, 24
--                         frames incapacitated) and the dash ends
--   Dungeon_ProcessTorchesAndDoors
--                         a breakable wall (door 0x28) ahead while running
--                         (link_dash_ctr < 63) breaks
--
-- OURS: the sound, the running pose (the walking frames at the
-- run's speed). r21: the dust and the drawn screen shake (Effects.lua).
-- r20: the rebound's hop (link_actual_vel_z 36, Escape's
-- recoil), the screen shake's timer (game.tremor) and the overworld (M.owAfter: Link_BonkAndSmash on bushes; the big
-- rock piles 0x226-0x229 are not ported).

local M = {}

M.CHARGE = 29          -- link_countdown_for_dash
M.SPEED = 16           -- link_speed_setting while running (kSpeedMod[16] = 64)
M.REBOUND = 24         -- kDashTab6X/Y, 1/16 px a frame
M.REBOUND_FRAMES = 24  -- link_incapacitated_timer
-- kPlayerActionBoxRun_X/Y by facing >> 1 (up, down, left, right)
M.RUN_BOX = { [0] = { 0, -8 }, [1] = { 0, 16 }, [2] = { -8, 8 }, [3] = { 8, 8 } }
local DIR = { [0] = { 0, -1 }, [2] = { 0, 1 }, [4] = { -1, 0 }, [6] = { 1, 0 } }
local KEY = { [0] = "up", [2] = "down", [4] = "left", [6] = "right" }

-- the boots: GBA inventory byte 0x39 (SNES link_item_boots 0x55; see Npc.lua)
function M.hasBoots(game)
  local inv = game.progress and game.progress.inv
  return inv and ((inv[0x39] or 0) ~= 0 or (inv["57"] or 0) ~= 0) or false
end

-- R pressed with nothing else to do (Link_PerformDash)
function M.start(game)
  if game.dash or game.carry or game.swing or not M.hasBoots(game) then return false end
  game.dash = { cd = M.CHARGE, ctr = 64, facing = game.link.facing }
  game.dashes = (game.dashes or 0) + 1
  return true
end

-- one frame indoors, before the walk. `inp` is the frame's input (up / down /
-- left / right booleans), `rHeld` whether R is still down. Returns true when
-- the frame is the dash's alone (the charge); while running it rewrites inp
-- to the facing direction and sets the run speed.
function M.before(game, inp, rHeld)
  local d = game.dash
  if not d then return false end
  local lk = game.link
  if d.cd >= 0 then
    d.cd = d.cd - 1
    if not rHeld then game.dash = nil; lk.speedSetting = 0; return false end
    -- running in place: the walk cycle turns, Link does not move
    lk.counter = (lk.counter or 0) + 1
    if lk.counter >= 3 then lk.counter = 0; lk.steps = ((lk.steps or 0) % 8) + 1 end
    lk.facing = d.facing
    -- r21: the charge's dust (AncillaAdd_DashDust_charging, Effects.lua)
    require("src.zelda.alttp.Effects").dashDust(game, false)
    return true
  end
  -- running: another direction stops it (LinkState_ExitingDash)
  local want = KEY[d.facing]
  for _, k in ipairs({ "up", "down", "left", "right" }) do
    if inp[k] and k ~= want then game.dash = nil; lk.speedSetting = 0; return false end
  end
  inp.up, inp.down, inp.left, inp.right = false, false, false, false
  inp[want] = true
  lk.speedSetting = M.SPEED
  d.x0, d.y0 = lk.x, lk.y
  d.ctr = math.max(32, d.ctr - 1)
  -- r21: the run's dust (AncillaAdd_DashDust, Effects.lua)
  require("src.zelda.alttp.Effects").dashDust(game, true)
  return false
end

-- after the walk: the run's hit box, the wall rebound, breakable walls
function M.after(game)
  local d = game.dash
  if not d or d.cd >= 0 then return end
  local lk, inside = game.link, game.interior
  lk.facing = d.facing
  local v = DIR[d.facing]
  -- the run's hit box hurts sprites (the sword is out)
  local b = M.RUN_BOX[d.facing / 2]
  if game.actors and game.progress.sword then
    game.actors:swordHit(lk.x + b[1], lk.y + b[2], 16, 16, { vel = 0x40, lower = inside and inside.lower or false, sword = true, run = true, bFrames = 9 })
  end
  -- door 0x28 ahead: it breaks (Dungeon_ProcessTorchesAndDoors)
  if inside and d.ctr < 63 then
    local px, py = lk.x + 8 + v[1] * 10, lk.y + 16 + v[2] * 12
    local cell = math.floor(py / 8) * 64 + math.floor(px / 8)
    for _, l in ipairs(inside.locks or {}) do
      if not l.open and l.type == 0x28 then
        for _, c in ipairs(l.cells) do
          if c == cell then
            inside:openLock(l)
            inside.mem.doors = inside.mem.doors or {}
            inside.mem.doors[l.index] = true
            game.roomImages = nil
            game.wallsDashed = (game.wallsDashed or 0) + 1
          end
        end
      end
    end
  end
  -- stopped by a wall: the rebound (RepelDash -> LinkApplyTileRebound)
  local moved = (lk.x - (d.x0 or lk.x)) * v[1] + (lk.y - (d.y0 or lk.y)) * v[2]
  if moved <= 0 and (lk.doorway or 0) == 0 then
    game.dash = nil
    lk.speedSetting = 0
    -- r20: the hop (link_actual_vel_z = 36) and the tremor (AncillaAdd_DashTremor)
    game.recoil = { t = M.REBOUND_FRAMES, vx = -v[1] * M.REBOUND, vy = -v[2] * M.REBOUND, sx = 0, sy = 0, bonk = true, vz = 36 }
    game.tremor = M.TREMOR
    M.shake(game)
    game.bonks = (game.bonks or 0) + 1
  end
end

-- r20: OUTDOORS (the same LinkState_Dashing on the overworld). After the
-- walk: the run's hit box on the overworld's sprites; stopped by something
-- solid, Link_BonkAndSmash breaks what he runs into (Overworld_SmashRockPile:
-- the 16 x 16 tile at Link + kGetBestActionToPerformOnTile[facing], and the
-- one 8 px lower: a bush 0x36 -> 0xDC7, its secret and drop as the sword's
-- cut), then RepelDash: the rebound, the hop and the screen shake
-- (AncillaAdd_DashTremor, 17 frames)
function M.owAfter(game)
  local d = game.dash
  if not d or d.cd >= 0 then return end
  local lk = game.link
  lk.facing = d.facing
  local v = DIR[d.facing]
  local b = M.RUN_BOX[d.facing / 2]
  if game.owActors and game.progress.sword then
    game.owActors:swordHit(lk.x + b[1], lk.y + b[2], 16, 16, { vel = 0x40, sword = true, run = true, bFrames = 9 })
  end
  local moved = (lk.x - (d.x0 or lk.x)) * v[1] + (lk.y - (d.y0 or lk.y)) * v[2]
  if moved > 0 then return end
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  local j = d.facing / 2
  if cb and cb.actTileX and d.ctr ~= 64 then
    for i = 0, 1 do
      local tx, ty = lk.x + cb.actTileX[j + 1], lk.y + cb.actTileY[j + 1] + i * 8
      if M.rockPile(game, tx, ty) then
        game.rockPiles = (game.rockPiles or 0) + 1
      elseif game:owTileChange(tx, ty, M.SMASH) then
        local Drops = require("src.zelda.alttp.Drops")
        local kind = Drops.CUT_KIND[game.lastCutFrom] or 2
        local sx, sy = math.floor(tx / 16) * 16, math.floor(ty / 16) * 16
        game:terrainDrop(kind, game.lastSecret, sx, sy)
        game:spawnDebris(kind, sx, sy)
        game.dashSmashes = (game.dashSmashes or 0) + 1
      end
    end
  end
  game.dash = nil
  lk.speedSetting = 0
  game.recoil = { t = M.REBOUND_FRAMES, vx = -v[1] * M.REBOUND, vy = -v[2] * M.REBOUND, sx = 0, sy = 0, bonk = true, vz = 36 }
  game.tremor = M.TREMOR
  M.shake(game)
  game.bonks = (game.bonks or 0) + 1
end
-- r21: the screen shake (AncillaAdd_DashTremor; Effects.lua draws it), its
-- first sign from Link's spot on the screen
function M.shake(game)
  local lk = game.link
  local cx, cy = 0, 0
  if game.state == "room" and game.interior and game.interior.camera then
    cx, cy = game.interior:camera(lk.x, lk.y, 240, 160)
  elseif game.cam then
    cx, cy = game.cam.x, game.cam.y
  end
  require("src.zelda.alttp.Effects").tremor(game, lk.x - cx, lk.y - cy)
end
M.SMASH = { [0x36] = 0xDC7 }

-- r21: Overworld_SmashRockPile / SmashRockPile_fromLift: a big rock pile is
-- four map16 tiles 0x226 (top left), 0x227, 0x228, 0x229 (bottom right). The
-- one Link runs into gives the pile's top left (kBigRockTab1: 0, -1, -64,
-- -65 map16 cells); its secret is revealed there (Overworld_RevealSecret);
-- the four tiles become kDoorAnimTiles[20..23] (0xDCD-0xDD0), or [40..43]
-- (0x918-0x91B) when the secret is a hole / stairs (door_open_closed_counter
-- 80). OURS: the rubble's debris kind (kLink_Lift_tab by the new tile's
-- attribute) is the small rock's; no sound.
M.PILE_DX = { [0] = 0, -16, 0, -16 }
M.PILE_DY = { [0] = 0, 0, -16, -16 }
function M.rockPile(game, x, y)
  local m16 = game.data.roomIdx and game.data.roomIdx.map16
  if not (m16 and m16[0x226] and m16[0xDCD] and game.owSetMap16) then return false end
  local O = require("src.zelda.alttp.Overworld")
  local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
  local screen = O.screenAt(game.link.world, tx, ty)
  if not screen then return false end
  local n = game.data:mapNumber("bg2", screen)
  local lx, ly = (tx % 512) / 8, (ty % 512) / 8
  -- (the cell order of G:owTileChange)
  local cells = { O.cellIndex(lx, ly), O.cellIndex(lx + 1, ly), O.cellIndex(lx, ly + 1), O.cellIndex(lx + 1, ly + 1) }
  local q
  for k = 0, 3 do
    local w = m16[0x226 + k]
    local same = true
    for c = 1, 4 do if game.data:mapWord(n, cells[c]) ~= w[c] then same = false break end end
    if same then q = k break end
  end
  if not q then return false end
  local ux, uy = tx + M.PILE_DX[q], ty + M.PILE_DY[q]
  -- the secret at the top left (owTileChange reveals it: lastSecret)
  local s0 = game.secretsFound or 0
  game:owTileChange(ux, uy, { [0x226] = 0xDCD })
  local hole = (game.secretsFound or 0) > s0 and game.lastSecret == 0xFF
  local base = hole and 0x918 or 0xDCD
  for k = 0, 3 do
    if hole or k > 0 then
      game:owSetMap16(ux + (k % 2) * 16, uy + math.floor(k / 2) * 16, base + k)
    end
  end
  game:spawnDebris(4, ux + 8, uy + 8)
  return true
end
M.TREMOR = 17

function M.cancel(game)
  if game.dash then game.dash = nil; game.link.speedSetting = 0 end
end

return M
