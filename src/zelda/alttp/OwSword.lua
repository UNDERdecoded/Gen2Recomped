-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SWORD OUTDOORS (round 21): the held sword and the spin attack on the
-- overworld, as indoors (Escape.lua's room frame; the SNES LinkItem_Sword ->
-- HandleSwordControls -> Player_Sword_SpinAttackJerks_HoldDown, then
-- Link_ActivateSpinAttack -> LinkState_SpinAttack), and the tiles the sword
-- acts on (TileDetect_MainHandler):
--
--   * the swing's cut at button_b_frames 5: TileDetect_MainHandler(1) (the
--     fighter sword; 6 for the better swords): the point Link + (x, y) of
--     kDoSwordInteractionWithTiles_x / _y[(item * 8 + facing) >> 1] (the
--     GBA's own 40 x s16 tables at 0x1681D4 / 0x16817C; Effects.extract)
--   * the spin: on each of its 12 steps, TileDetect_MainHandler(8): a =
--     state_for_spin_attack - 2 (0..7, else nothing), the point at index
--     (kDoSwordInteractionWithTiles_o[a] + 0x40) >> 1 -- bushes and grass
--     all round are cut (Overworld_ToolAndTileInteraction)
--   * the held sword walks at link_speed_setting 12 facing one way, pokes
--     the overworld's sprites (kPlayer_SetupActionHitBox row 9), and is put
--     away after a poke (set_when_damaging_enemies 16 -> 1)
--
-- OURS: the held sword's wall tap (frames 13, TileDetect_MainHandler(1) on
-- bitmask_of_dragstate) and the sword beam are not ported.

local M = {}

local function fx(game)
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  return cb and cb.fx
end

-- the point Link + offset a tool `item` acts on (nil without the tables)
function M.tileOffset(game, item)
  local T = fx(game)
  if not T or not T.tileX then return nil end
  local o = math.floor((item * 8 + (game.link.facing or 2)) / 2)
  return { T.tileX[o + 1], T.tileY[o + 1] }
end

-- cut what the point (x, y) holds (a bush, thick grass): the swing's own
-- routine (the tile change, its drop and debris)
function M.cut(game, x, y)
  local G = getmetatable(game) and getmetatable(game).__index
  local SWORD_CUT = game.SWORD_CUT or (G and G.SWORD_CUT)
  if not SWORD_CUT or not game.owTileChange then return false end
  if game:owTileChange(x, y, SWORD_CUT) then
    local Drops = require("src.zelda.alttp.Drops")
    local kind = Drops.CUT_KIND[game.lastCutFrom] or 2
    local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
    game:terrainDrop(kind, game.lastSecret, tx, ty)
    game:spawnDebris(kind, tx, ty)
    game.spinCuts = (game.spinCuts or 0) + ((game.swing and game.swing.spin) and 1 or 0)
    return true
  end
  return false
end

-- TileDetect_MainHandler(8) for the spin's picture `gfx`
function M.spinTile(game, gfx)
  local T = fx(game)
  if not T or not T.spinO then return end
  local a = (gfx or 0) - 2
  if a < 0 or a >= 8 then return end
  local o = math.floor(((T.spinO[a + 1] or 0) + 0x40) / 2)
  local lk = game.link
  M.cut(game, lk.x + (T.tileX[o + 1] or 0), lk.y + (T.tileY[o + 1] or 0))
end

local function bHeld(game)
  local i = game.input
  return i and i.isDown and i.isDown("b")
end

local function hit(game, x, y, w, h, opts)
  if game.owActors then return game.owActors:swordHit(x, y, w, h, opts) end
  return 0
end

-- at the swing's end (button_b_frames 9): B still down keeps the sword out
function M.startHold(game)
  local s = game.swing
  if not s or not bHeld(game) or not fx(game) then return false end
  s.held, s.step, s.delay, s.charge, s.facing = true, 9, 0, 0, game.link.facing
  game.swordHeld = 9
  game.swordHolds = (game.swordHolds or 0) + 1
  return true
end

-- one overworld frame of a held sword or a spin: true = the frame is the
-- sword's, false = Link walks (held), nil = an ordinary swing (the caller's)
function M.frame(game)
  local s = game.swing
  if not s or not (s.held or s.spin) then return nil end
  local cb = game.data.roomIdx.combat
  local lk = game.link
  local Actors = require("src.zelda.alttp.Actors")
  if s.spin then
    s.delay = s.delay - 1
    if s.delay < 0 then
      s.step = s.step + 1
      if s.step >= 12 then
        game.swing, game.swordHeld = nil, 0
        return true
      end
      s.gfx = cb.spinGfx[s.step + s.offs + 1] or 0
      s.delay = cb.spinDelays[s.step + 1] or 1
      M.spinTile(game, s.gfx)
    end
    s.box = { lk.x - 14, lk.y - 10, 44, 45 }
    hit(game, lk.x - 14, lk.y - 10, 44, 45, { vel = 0x50, sword = true, spin = true, bFrames = 144 })
    return true
  end
  -- held
  if not bHeld(game) then
    lk.speedSetting = 0
    if (s.charge or 0) >= 48 then
      s.held, s.spin, s.step, s.delay = nil, true, 0, 3
      s.offs = math.floor(lk.facing / 2) * 12
      s.gfx = cb.spinGfx[s.offs + 1] or 0
      game.swordHeld = 144
      game.spins = (game.spins or 0) + 1
      s.delay = s.delay - 1
      s.box = { lk.x - 14, lk.y - 10, 44, 45 }
      hit(game, lk.x - 14, lk.y - 10, 44, 45, { vel = 0x50, sword = true, spin = true, bFrames = 144 })
      return true
    end
    game.swing, game.swordHeld = nil, 0
    return true
  end
  -- (no sprites outdoors: Actors:update is not there to count it down)
  if not game.owActors and (game.swde or 0) > 0 then game.swde = game.swde - 1 end
  local swde = game.swde or 0
  if s.step == 9 and swde == 0 then
    lk.speedSetting = 12
    if (s.charge or 0) < 64 then s.charge = (s.charge or 0) + 1 end
    game.swordHeld = 9
  elseif swde == 1 then
    lk.speedSetting = 0
    game.swing, game.swordHeld = nil, 0
    return true
  else
    if s.step == 9 then s.step, s.delay = 10, cb.swordDelays[11] or 0 end
    s.delay = s.delay - 1
    if s.delay < 0 then
      local f = s.step + 1
      if f == 13 then f = 10 end
      s.step, s.delay = f, cb.swordDelays[f + 1] or 0
    end
  end
  local yt, rt = 2, 0
  if s.step > 9 then yt, rt = 3, s.step - 10 end
  local x, y, w, h = Actors.swordBox(cb, lk, s.step, game.data.t.playerOamOffs, yt, rt)
  s.box = x and { x, y, w, h } or nil
  if x then hit(game, x, y, w, h, { vel = 0x40, sword = true, held = true, bFrames = s.step }) end
  return false
end

-- after the overworld walk: the held sword keeps Link's facing; the walk's
-- speed 12 ends with it
function M.after(game)
  local s = game.swing
  local lk = game.link
  if s and s.held and s.facing then lk.facing = s.facing end
  if not (s and s.held) and not game.dash and lk.speedSetting == 12 then lk.speedSetting = 0 end
end

return M
