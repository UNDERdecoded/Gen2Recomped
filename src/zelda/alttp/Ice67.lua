-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SLIPPERY ICE FLOORS (round 67). The Ice Palace's floors (attributes
-- 0x0E / 0x0F) were plain floor. Traced on the GBA (zelda3 names):
--
--   TileDetect (jump table 0x0816832C): 0x0E -> 0x080A076C
--     (tiledetect_icy_floor +0x17D8 |= the probe's bit), 0x0F -> 0x080A078C
--     (|= bit << 4). The nearby probe 0x0809EEB4 (one point, Link +
--     kNearbyX / Y [0]: Warp48's data.t.warp48.px / py) runs after Link's
--     move; its tail 0x0809F2C0:
--       icy & 0x11, link_flag_moving (+0x17DA) 0 -> link_flag_moving =
--         (icy & 1) ? 1 : 2, link_direction_last (+0x17CE) = link_direction,
--         Link_ResetSwimmingState (0x0809E2CC -> 0x08092B0C: the momentum
--         words +0x17B2 .. +0x17CC cleared; the 0x180 it stored first at
--         +0x17CA is cleared with them). Already sliding: kept (a change of
--         ice type keeps the first flag).
--       no ice, not swimming: the reset, link_flag_moving = 0.
--   PlayerHandler_00_Ground (0x080981D0): keys -> link_direction_last; on ice
--     swimcoll_var9 (+0x17C2 / +0x17C4, the top speed) = 0x180 (the movs at
--     0x080982D2), Link_SetMomentum (0x08097A74: per axis the timer var3 =
--     kSwimmingTab2[link_flag_moving - 1] on ice (0x20 off it), var5 = 2
--     when the keys turn against the motion, else the direction var11 and
--     var5 0, var9 240 if 0), Link_SetTheMaxAccel (0x08097D70: nothing on
--     ice). No keys: both speeds 0 -> the reset.
--   Link_HandleVelocity (0x080975B4): swimming, or link_flag_moving and not
--     dashing (+0x1804) -> 0x0809834C (HandleSwimStrokeAndSubpixels): per
--     axis var3 - 1 (below 0: var5 = 1), speed var7 + kSwimmingTab4[var5 +
--     link_flag_moving * 4] (the ice rows; Swim.lua uses row 0), at or
--     below 0 stopped (var5 2 -> 2 and var9 240), else capped at var9; the
--     move is the speed (1/256 px), 3/4 of it while +0x172A (diagonal keys),
--     negative for var11 0.
--   Then the walls as for walking (Link_HandleCardinalCollision: Doors.lua's
--     checkY / checkX).
--
-- No new import: the tables are Swim.lua's (data.t.swim tab2 / tab4) and the
-- probe Warp48's; the 0x180 is the code's (data.t.ice67, read at import).
-- The port's walkable set (Interior.WALKABLE) held neither 0x0E nor 0x0F:
-- the ice was a wall. Both are floor now.
-- OURS: the walk cycle runs while keys are held; the slope pre-step
-- (Slope60) is not run while sliding; the GBA's other resets on a turn
-- (+0x16D0, +0x172B ...) are not modelled.

local bit = require("bit")
local band, bor, bnot, rshift = bit.band, bit.bor, bit.bnot, bit.rshift

local M = {}
M.HANDLERS = { [0x0E] = 0x080A076C, [0x0F] = 0x080A078C }   -- TileDetect's jump table entries (Thumb + 1)
M.TABLE = 0x0816832C
M.SITES = { topSpeed = 0x080982D2, tail = 0x0809F2C0 }

function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local v, form = RT.codeImm(rom, M.SITES.topSpeed)
  local ok = form == "movs"
  for a, h in pairs(M.HANDLERS) do
    ok = ok and rom:u32(M.TABLE - 0x08000000 + a * 4) == h + 1
  end
  check(ok and v, "the ice floor (TileDetect 0x0E / 0x0F, the top speed)")
  return { top = v }
end

local function tab(game) return game.data and game.data.t and game.data.t.ice67 end
M.tab = tab

function M.newState()
  return { flag = 0, v1 = { 0, 0 }, v3 = { 0, 0 }, v5 = { 0, 0 }, v7 = { 0, 0 }, v9 = { 0, 0 }, v11 = { 0, 0 },
           last = 0, ldir = 0 }
end

-- 0x08092B0C
function M.reset(st)
  for i = 1, 2 do st.v1[i], st.v3[i], st.v5[i], st.v7[i], st.v9[i] = 0, 0, 0, 0, 0 end
end

-- Link_SetMomentum (y = 1, x = 2); j = the keys (up 8, down 4, left 2, right 1)
function M.setMomentum(st, j, var3)
  local mask, bitv = 12, 8
  for i = 1, 2 do
    if band(j, mask) ~= 0 then
      st.v3[i] = var3
      if band(bor(st.last, st.ldir), mask) == mask then
        st.v5[i] = 2
      else
        st.v11[i] = (band(j, bitv) ~= 0) and 0 or 1
        st.v5[i] = 0
      end
      if st.v9[i] == 0 then st.v9[i] = 240 end
    end
    mask, bitv = rshift(mask, 2), rshift(bitv, 2)
  end
end

-- HandleSwimStrokeAndSubpixels with link_flag_moving = flag; returns the
-- move per axis in 1/256 px ({ y, x })
local CLEAR = { bnot(0xC), bnot(3) }
local SETB = { [0] = 8, 4, 2, 1 }
function M.velocity(st, flag, diag, tab4)
  local S = { 0, 0 }
  for i = 2, 1, -1 do
    st.v3[i] = st.v3[i] - 1
    if st.v3[i] < 0 then st.v3[i] = 0; st.v5[i] = 1 end
    local sum = st.v7[i] + (tab4[st.v5[i] + flag * 4 + 1] or 0)
    if sum <= 0 then
      st.ldir = band(st.ldir, CLEAR[i])
      if st.v5[i] == 2 then st.v5[i], st.v9[i], sum = 0, 240, 2
      else st.v5[i], st.v9[i], sum = 0, 0, 0 end
    else
      st.ldir = bor(st.ldir, SETB[st.v11[i] + (i - 1) * 2])
      if sum >= st.v9[i] then sum = st.v9[i] end
    end
    st.v7[i] = sum
    local v = sum
    if diag then v = sum - rshift(sum, 2) end
    if st.v11[i] == 0 then v = -v end
    S[i] = v
  end
  return S
end

local function add(coord, sub, v)
  local tmp = sub + v + coord * 256
  return math.floor(tmp / 256), tmp % 256
end

-- the nearby probe after the move: link_flag_moving on / off
function M.detect(g)
  local t, lk, inside = g.data.t and g.data.t.warp48, g.link, g.interior
  if not (t and inside and tab(g)) then return end
  local st = lk.ice67
  local a = inside:attrAt(lk.x + t.px, lk.y + t.py)
  local nf = (a == 0x0E and 1) or (a == 0x0F and 2) or 0
  if nf > 0 then
    if not st then st = M.newState(); lk.ice67 = st end
    if st.flag == 0 then
      st.flag = nf
      st.last = lk.dirLast or 0
      M.reset(st)
      g.iceEntries = (g.iceEntries or 0) + 1
    end
  elseif st and st.flag ~= 0 and not lk.swim then
    M.reset(st)
    st.flag = 0
  end
end

-- one frame of Link on ice (in place of Doors.move)
function M.move(g, inp, st)
  local D = require("src.zelda.alttp.Doors")
  local Link = require("src.zelda.alttp.Link")
  local lk = g.link
  local t = lk.data.t
  local sw = g.data.t.swim
  local top = tab(g).top
  lk.doorway = lk.doorway or 0
  local dir = (inp.up and 8 or 0) + (inp.down and 4 or 0) + (inp.left and 2 or 0) + (inp.right and 1 or 0)
  if band(dir, 0xC) == 0xC then dir = dir - 0xC end
  if band(dir, 3) == 3 then dir = dir - 3 end
  lk.dirLast = dir
  if dir ~= 0 then
    st.last = dir
    st.v9[1], st.v9[2] = top, top
    M.setMomentum(st, dir, sw.tab2[st.flag] or 0)
    local held = { [Link.UP] = band(dir, 8) ~= 0, [Link.DOWN] = band(dir, 4) ~= 0,
                   [Link.LEFT] = band(dir, 2) ~= 0, [Link.RIGHT] = band(dir, 1) ~= 0 }
    if not held[lk.facing] then
      if band(dir, 8) ~= 0 then lk.facing = Link.UP elseif band(dir, 4) ~= 0 then lk.facing = Link.DOWN
      elseif band(dir, 2) ~= 0 then lk.facing = Link.LEFT else lk.facing = Link.RIGHT end
    end
  elseif st.v7[1] == 0 and st.v7[2] == 0 then
    M.reset(st)
  end
  local diag = band(dir, 0xC) ~= 0 and band(dir, 3) ~= 0
  local S = M.velocity(st, st.flag, diag, sw.tab4)
  local x0, y0 = lk.x, lk.y
  lk.subX, lk.subY = lk.subX or 0, lk.subY or 0
  lk.x, lk.subX = add(lk.x, lk.subX, S[2])
  lk.y, lk.subY = add(lk.y, lk.subY, S[1])
  local xv, yv = lk.x - x0, lk.y - y0
  lk.velX, lk.velY = xv, yv
  local orth = 0
  if dir ~= 0 then
    local _
    _, orth = D.limitDirections(g, lk, dir)
    if orth == 2 then orth = (lk.facing == Link.LEFT or lk.facing == Link.RIGHT) and 2 or 1 end
  end
  local incap = g.recoil ~= nil
  if yv ~= 0 then D.checkY(g, lk, yv, orth, incap) end
  if xv ~= 0 then D.checkX(g, lk, xv, orth, incap) end
  lk.tileBelow = g.interior:attrAt(lk.x + 8, lk.y + 20)
  lk.moving = dir ~= 0
  g.iceFrames = (g.iceFrames or 0) + 1
  if dir == 0 then lk.steps, lk.counter = 0, 0 return end
  lk.counter = (lk.counter or 0) + 1
  if lk.counter >= t.animTab3[(lk.steps or 0) + 1] then
    lk.counter = 0
    lk.steps = (lk.steps or 0) + 1
    if lk.steps == 9 then lk.steps = 1 end
  end
end

function M.install(G)
  -- the ice is floor: TileDetect's 0x0E / 0x0F handlers only mark it (the
  -- port's walkable set left both out, so the ice was a wall to Link)
  local I = require("src.zelda.alttp.Interior")
  for a in pairs(M.HANDLERS) do I.WALKABLE[a] = true end
  local D = require("src.zelda.alttp.Doors")
  local move0 = D.move
  function D.move(g, inp)
    local lk = g.link
    local st = lk.ice67
    if st and st.flag ~= 0 and tab(g) and g.data.t.swim and not g.dash and not lk.swim and g.state == "room"
       and D.checkY then
      M.move(g, inp, st)
    else
      move0(g, inp)
    end
    if g.state == "room" then M.detect(g) end
  end
end

return M
