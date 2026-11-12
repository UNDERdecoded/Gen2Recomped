-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 12: LINK INDOORS -- walking, doorways and the transitions they start,
-- the cartridge's way. A port of the SNES player code (snesrev/zelda3,
-- player.c / tile_detect.c / dungeon.c); the GBA's own HandleDoorTransitions
-- (0x0809B0DC: link_y +0x16C0, link_x +0x16C4, direction +0x16CC,
-- is_standing_in_doorway +0x172C; the same +28 / -18 / +21 / -8 tests) was
-- read in the ROM and matches it.
--
--   * Player_LimitDirections_Inner: on a diagonal, the slope probes drop the
--     component a wall blocks, and in a doorway the one across the door.
--   * Link_HandleVelocity / Link_MovePosition: both axes move first.
--   * StartMovementCollisionChecks_Y/_X (_HandleIndoors): TileDetect_Movement
--     probes three points (y + 8 / y + 24 rows at x + 0, 8, 15; x + 0 / x + 15
--     columns at y + 8, 16, 23); door attributes (0x80-0x8F, 0x90-0xAF; the
--     SNES TileHandlerIndoor_80 / _82, TileBehavior_Entrance, *ToggleShutter*)
--     mark Link as standing in a doorway (1 north/south, 2 east/west); a probe
--     on a wall beside a doorway slides him 1 px a frame into it
--     (CalculateSnapScratch); all three in the doorway let him through;
--     walking across a doorway moves him along it
--     (ChangeAxisOfPerpendicularDoorMovement); elsewhere
--     HandlePushingBonkingSnaps: snap to the wall, the 1 px corner slide off
--     the 8 px grid (HandleNudging).
--   * HandleDoorTransitions: in a doorway the room changes when y + 28
--     reaches the next 256 px page (down), y - 18 leaves the page (up),
--     x + 21 / x - 8 (right / left); HandleEdgeTransitionMovementSouth_DownBy16
--     / _RightBy8 / Dung_StartInterRoomTrans_Left_Plus shift Link 16 / 8 px;
--     the exit to the overworld is that same down move with the entrance
--     attribute 0x8E under Link (x + 8, y + 20; Dungeon_StartInterRoomTrans_Down).
--   * The landing: SubtileTransitionCalculateLanding / MoveLinkOutDoor put
--     Link at kStaircaseTab2's spot in the new page by the attribute under his
--     centre, and walk him there 2 px a frame.
-- OURS: no slopes, conveyors, moving floors, water or spikes (none on the
-- escape route); "solid" is the room's collision grid (Interior:blocked)
-- plus solid actors.

local Link = require("src.zelda.alttp.Link")

local D = {}

-- door attribute -> 1 (doorway) / 2 (doorway that also sets R14 bits 8-10)
local DOOR = {}
for v = 0x80, 0x8D do DOOR[v] = 1 end
DOOR[0x82], DOOR[0x83] = 2, 2
DOOR[0x8E], DOOR[0x8F] = 1, 1
for v = 0x90, 0x9F do DOOR[v] = 2 end
for v = 0xA8, 0xAF do DOOR[v] = 2 end
DOOR[0xA0], DOOR[0xA1], DOOR[0xA4], DOOR[0xA5] = 1, 1, 1, 1
DOOR[0xA2], DOOR[0xA3] = 2, 2
D.DOOR = DOOR

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

-- one TileDetection_Execute: returns the R14 bits for `bits`, tiledetect_var1
local function detect(g, x, y, bits)
  local inside = g.interior
  local a = inside:attrAt(x, y) or 0
  local solid = inside:blocked(x, y) or (g.actors and g.actors:solidAt(x, y))
  local d = DOOR[a]
  if d and not solid then
    local r = bits * 16
    if d == 2 then r = r + bits * 256 end
    local var1 = (a == 0x8E or a == 0x8F) and 0 or 2 * (a % 2)
    return r, var1, a
  end
  return solid and bits or 0, nil, a
end
D.detect = detect

local function detect3(g, pts)
  local r14, var1, last = 0, 0, 0
  for i, p in ipairs(pts) do
    local r, v, a = detect(g, p[1], p[2], 2 ^ (i - 1))
    r14 = bor(r14, r)
    if v then var1 = v end
    last = a
  end
  return r14, var1, last
end

-- TileDetect_Movement_Y (dir 0 up / 1 down) and _X (2 left / 3 right)
local function probesY(lk, dir)
  local y = lk.y + (dir == 0 and 8 or 24)
  return { { lk.x, y }, { lk.x + 8, y }, { lk.x + 15, y } }, y
end
local function probesX(lk, dir)
  local x = lk.x + (dir == 2 and 0 or 15)
  return { { x, lk.y + 8 }, { x, lk.y + 16 }, { x, lk.y + 23 } }
end

-- HandleNudging (kLink_Move_Helper6_tab0..3): after a 1 px corner slide, the
-- two cells on the side Link slid to must be free, else the slide is undone
local NY0 = { 8, 8, 23, 23, 8, 23, 8, 23 }
local NX0 = { 0, 15, 0, 15, 0, 0, 15, 15 }
local NY1 = { 23, 23, 8, 8, 8, 23, 8, 23 }
local NX1 = { 0, 15, 0, 15, 15, 15, 0, 0 }
local function nudging(g, lk, dirMoved, r14, r0)
  local p
  if band(dirMoved, 2) == 0 then p = band(dirMoved, 1) ~= 0 and 4 or 0
  else p = band(dirMoved, 1) ~= 0 and 12 or 8 end
  local o = band(r14, 4) ~= 0 and 0 or 2
  local i = rshift(o + p, 1) + 1
  local a = detect(g, lk.x + NX0[i], lk.y + NY0[i], 1)
  local b = detect(g, lk.x + NX1[i], lk.y + NY1[i], 2)
  if band(bor(a, b), 3) ~= 0 then
    if band(dirMoved, 2) ~= 0 then lk.y = lk.y - r0 else lk.x = lk.x - r0 end
  end
  lk.nudged = (lk.nudged or 0) + 1
end

-- Link_AddInVelocityYFalling / SnapOnX
local function snapY(lk, py, yv) lk.y = lk.y - ((py % 8) - (yv < 0 and 8 or 0)) end
local function snapX(lk, xv) lk.x = lk.x - ((lk.x % 8) - (xv < 0 and 8 or 0)) end

-- HandlePushingBonkingSnaps_Y
local function bonkY(g, lk, r14, py, yv, orth, dirMoved)
  if band(r14, 7) == 0 then return end
  if band(r14, 2) ~= 0 then snapY(lk, py, yv)
  else
    if orth == 1 then return end
    snapY(lk, py, yv)
    if orth == 2 then return end
  end
  if band(r14, 5) == 5 then return end
  if band(r14, 2) ~= 0 then return end
  if lk.x % 8 == 0 then return end
  local r0 = band(r14, 4) ~= 0 and -1 or 1
  lk.x = lk.x + r0
  nudging(g, lk, dirMoved, r14, r0)
end

-- HandlePushingBonkingSnaps_X
local function bonkX(g, lk, r14, xv, orth, dirMoved)
  if band(r14, 7) == 0 then return end
  if band(r14, 7) == 7 then snapX(lk, xv)
  else
    if orth == 2 then return end
    snapX(lk, xv)
    if orth == 1 then return end
  end
  if band(r14, 5) == 5 then return end
  if band(r14, 2) ~= 0 then return end
  if lk.y % 8 == 0 then return end
  local r0 = band(r14, 4) ~= 0 and -1 or 1
  lk.y = lk.y + r0
  nudging(g, lk, dirMoved, r14, r0)
end

-- StartMovementCollisionChecks_Y_HandleIndoors
local function checkY(g, lk, yv, orth, incap)
  local dir
  if lk.doorway == 1 then dir = (lk.y % 256) < 0x80 and 0 or 1 else dir = yv < 0 and 0 or 1 end
  lk.dirMoved = dir
  local pts, py = probesY(lk, dir)
  local r14, var1, last = detect3(g, pts)
  lk.tileBelow = last
  if incap then
    r14 = bor(r14, band(rshift(r14, 4), 7))
    lk.doorway = 0
    return bonkY(g, lk, r14, py, yv, orth, dir)
  end
  if lk.doorway == 2 then
    if orth == 0 then
      -- Link_AddInVelocityY + ChangeAxisOfPerpendicularDoorMovement_Y
      lk.y = lk.y - yv
      local t = band(bor(r14, rshift(r14, 4)), 0xF)
      if band(t, 7) == 0 then lk.doorway = 0 return end
      if lk.x % 256 >= 0x80 then lk.x = lk.x - 1; lk.facing = Link.LEFT
      else lk.x = lk.x + 1; lk.facing = Link.RIGHT end
      return
    elseif var1 ~= 0 then
      lk.y = lk.y - yv
      return bonkY(g, lk, r14, py, yv, orth, dir)
    end
  end
  if band(r14, 0x70) ~= 0 then
    lk.doorway = 1
    if band(r14, 0x70) ~= 0x70 then
      if band(r14, 5) ~= 0 then
        snapY(lk, py, yv)
        -- CalculateSnapScratch_Y: towards the doorway
        lk.x = lk.x + (band(r14, 4) ~= 0 and -1 or 1)
        lk.doorway = 0
        if band(r14, 0x20) ~= 0 and band(r14, 1) == 0 and lk.x % 8 == 1 then lk.x = lk.x - 1 end
        lk.doorSlides = (lk.doorSlides or 0) + 1
        return
      end
      if band(r14, 0x20) ~= 0 then return end
    else
      return
    end
  end
  lk.doorway = 0
  return bonkY(g, lk, r14, py, yv, orth, dir)
end

-- StartMovementCollisionChecks_X_HandleIndoors
local function checkX(g, lk, xv, orth, incap)
  local dir
  if lk.doorway == 2 then dir = (lk.x % 256) < 0x80 and 2 or 3 else dir = xv < 0 and 2 or 3 end
  lk.dirMoved = dir
  local r14, var1, last = detect3(g, probesX(lk, dir))
  lk.tileBelow = last
  if incap then
    r14 = bor(r14, band(rshift(r14, 4), 7))
    lk.doorway = 0
    return bonkX(g, lk, r14, xv, orth, dir)
  end
  if lk.doorway == 1 and orth == 0 then
    -- SnapOnX + ChangeAxisOfPerpendicularDoorMovement_X + HandleNudgingInADoor
    snapX(lk, xv)
    local t = band(bor(r14, rshift(r14, 4)), 0xF)
    if band(t, 7) == 0 then lk.doorway = 0 return end
    local spd
    if lk.y % 256 >= 0x80 then spd = -math.abs(xv); lk.facing = Link.UP
    else spd = math.abs(xv); lk.facing = Link.DOWN end
    lk.y = lk.y + spd
    local k = (lk.y % 256) < 0x80 and 1 or 0
    local px, py = lk.x + 8, lk.y + (k == 1 and 23 or 8)
    if band(detect(g, px, py, 1), 3) ~= 0 then lk.y = lk.y - spd end
    return
  end
  if band(r14, 0x70) ~= 0 then
    lk.doorway = 2
    if band(r14, 0x70) ~= 0x70 then
      if band(r14, 7) ~= 0 then
        lk.doorway = 0
        snapX(lk, xv)
        -- CalculateSnapScratch_X
        lk.y = lk.y + (band(r14, 4) ~= 0 and -1 or 1)
        lk.doorSlides = (lk.doorSlides or 0) + 1
        return
      end
    end
    return
  end
  lk.doorway = 0
  return bonkX(g, lk, r14, xv, orth, dir)
end

-- Player_LimitDirections_Inner: the diagonal's components a wall (or a
-- doorway across them) blocks. dir bits: 8 up, 4 down, 2 left, 1 right.
local function limitDirections(g, lk, dir)
  if band(dir, 0xC) == 0 or band(dir, 3) == 0 then return dir, 0 end
  local maskA, maskB = 0xF, 0xF
  local MASKS = { [0] = 7, 0xB, 0xD, 0xE }
  local dv = band(dir, 8) ~= 0 and 0 or 1
  local yy = lk.y + (dv == 0 and 7 or 24)
  local a1, v1 = detect(g, lk.x, yy, 1)
  local a2, v2 = detect(g, lk.x + 15, yy, 2)
  local r14, var1 = bor(a1, a2), (v1 or v2 or 0)
  if band(r14, 0x30) ~= 0 and band(var1, 2) == 0 and band(rshift(band(r14, 0x30), 4), dir) == 0 then
    maskA = MASKS[band(dir, 2) ~= 0 and 2 or 3]
  elseif band(r14, 3) ~= 0 then
    maskA = MASKS[dv]
  end
  local dh = band(dir, 2) ~= 0 and 2 or 3
  local xx = lk.x + (dh == 2 and -1 or 16)
  local b1, w1 = detect(g, xx, lk.y + 8, 1)
  local b2, w2 = detect(g, xx, lk.y + 23, 2)
  r14, var1 = bor(b1, b2), (w1 or w2 or 0)
  if band(r14, 0x30) ~= 0 and band(var1, 2) ~= 0 and band(rshift(band(r14, 0x30), 2), dir) == 0 then
    maskB = MASKS[band(dir, 8) ~= 0 and 0 or 1]
  elseif band(r14, 3) ~= 0 then
    maskB = MASKS[dh]
  end
  return band(dir, band(maskA, maskB)), 2
end

local function moveAxis(coord, sub, vel)
  local tmp = sub + vel * 16 + coord * 256
  return math.floor(tmp / 256), tmp % 256
end

-- one frame of Link walking indoors. inp: { up, down, left, right }.
function D.move(g, inp)
  local lk = g.link
  local t = lk.data.t
  lk.doorway = lk.doorway or 0
  local dir = (inp.up and 8 or 0) + (inp.down and 4 or 0) + (inp.left and 2 or 0) + (inp.right and 1 or 0)
  if band(dir, 0xC) == 0xC then dir = dir - 0xC end
  if band(dir, 3) == 3 then dir = dir - 3 end
  lk.dirLast = dir
  lk.moving = dir ~= 0
  if dir == 0 then lk.steps, lk.counter, lk.velX, lk.velY = 0, 0, 0, 0 return end
  -- facing: kept while one of the held directions
  local held = { [Link.UP] = band(dir, 8) ~= 0, [Link.DOWN] = band(dir, 4) ~= 0,
                 [Link.LEFT] = band(dir, 2) ~= 0, [Link.RIGHT] = band(dir, 1) ~= 0 }
  if not held[lk.facing] then
    if band(dir, 8) ~= 0 then lk.facing = Link.UP elseif band(dir, 4) ~= 0 then lk.facing = Link.DOWN
    elseif band(dir, 2) ~= 0 then lk.facing = Link.LEFT else lk.facing = Link.RIGHT end
  end
  local mdir, orth = limitDirections(g, lk, dir)
  if orth == 2 then orth = (lk.facing == Link.LEFT or lk.facing == Link.RIGHT) and 2 or 1 end
  local dx = (band(mdir, 1) ~= 0 and 1 or 0) - (band(mdir, 2) ~= 0 and 1 or 0)
  local dy = (band(mdir, 4) ~= 0 and 1 or 0) - (band(mdir, 8) ~= 0 and 1 or 0)
  local diag = dx ~= 0 and dy ~= 0
  local vel = t.speedMod[lk.speedSetting + (diag and 1 or 0) + 1]
  local x0, y0 = lk.x, lk.y
  if dx ~= 0 then lk.x, lk.subX = moveAxis(lk.x, lk.subX, dx * vel) end
  if dy ~= 0 then lk.y, lk.subY = moveAxis(lk.y, lk.subY, dy * vel) end
  local xv, yv = lk.x - x0, lk.y - y0
  lk.velX, lk.velY = xv, yv
  local incap = g.recoil ~= nil
  if yv ~= 0 then checkY(g, lk, yv, orth, incap) end
  if xv ~= 0 then checkX(g, lk, xv, orth, incap) end
  -- TileDetect_MainHandler(0): the attribute under Link (x + 8, y + 20)
  lk.tileBelow = g.interior:attrAt(lk.x + 8, lk.y + 20)
  -- walk cycle (as Link:update)
  lk.counter = (lk.counter or 0) + 1
  if lk.counter >= t.animTab3[(lk.steps or 0) + 1] then
    lk.counter = 0
    lk.steps = (lk.steps or 0) + 1
    if lk.steps == 9 then lk.steps = 1 end
  end
end

-- HandleDoorTransitions for the current frame: returns the direction of an
-- inter-page move in a doorway ("up" / "down" / "left" / "right") or nil.
-- Pages are 256 px; `page` is the page Link's camera area is in.
function D.doorTransition(g)
  local lk = g.link
  local d = lk.dirLast or 0
  local inside = g.interior
  local x0, y0, x1, y1 = inside:area()
  if band(d, 0xC) ~= 0 and lk.doorway == 1 then
    if band(d, 4) ~= 0 then
      local t = lk.y + 28
      if t >= y1 and t < y1 + 4 then return "down" end
    else
      if lk.y - 18 < y0 then return "up" end
    end
  end
  if band(d, 3) ~= 0 and lk.doorway == 2 then
    if band(d, 1) ~= 0 then
      local t = lk.x + 21
      if t >= x1 and t < x1 + 4 then return "right" end
    else
      if lk.x - 8 < x0 then return "left" end
    end
  end
end

-- the shift at the start (HandleEdgeTransitionMovementSouth_DownBy16,
-- HandleEdgeTransitionMovementEast_RightBy8, Dung_StartInterRoomTrans_Left_Plus)
D.START_SHIFT = { down = { 0, 16 }, right = { 8, 0 }, left = { -8, 0 }, up = { 0, 0 } }

-- kStaircaseTab2 by transition (0 down, 1 up, 2 right, 3 left) and landing kind
local TAB2 = { 12, 32, 48, 56, 72, -44, -40, -64, -64, -88, 12, 24, 40, 48, 64, -28, -40, -56, -64, -80 }
local TRANS = { down = 0, up = 1, right = 2, left = 3 }

-- CalculateTransitionLanding: the attribute under Link's centre
function D.landingKind(g, ox, oy)
  local lk = g.link
  local a = g.interior:attrAt(lk.x + 8 + (ox or 0), lk.y + 12 + (oy or 0)) or 0
  if a == 0 or a == 9 then return 0 end
  local m = band(a, 0x8E)
  if m == 0x80 then return 1 end
  if m == 0x82 then return 2 end
  if m == 0x84 or m == 0x88 then return 3 end
  if m == 0x86 then return 4 end
  return 2
end

-- SubtileTransitionCalculateLanding: returns the axis, the coordinate Link
-- is set to and the one he walks to (2 px a frame, MoveLinkOutDoor)
function D.landing(g, dir)
  local lk = g.link
  local tr = TRANS[dir]
  -- DungeonTransition_ScrollRoom moves Link 4 px a frame once its counter
  -- reaches kStaircaseTab4 (52 / 52 / 59 / 58) of the 64-step scroll: 13 / 13
  -- / 6 / 7 steps, 52 px vertically, 24 right, 28 left, before the landing
  local MOVED = { down = { 0, 52 }, up = { 0, -52 }, right = { 24, 0 }, left = { -28, 0 } }
  local mv = MOVED[dir]
  local kind = D.landingKind(g, mv[1], mv[2])
  local a = kind
  if a == 2 then a = 1 elseif a == 4 then a = 2 end
  local v = TAB2[tr * 5 + a + 1]
  local target = v % 256
  local start = (v - ((v < 0) and -8 or 8)) % 256
  local axis = (tr >= 2) and "x" or "y"
  -- the cartridge sets only the low byte (BYTE(link_y_coord) = v): the page
  -- is the one Link is in after the scroll's own 4 px steps
  local page
  if axis == "y" then page = math.floor((lk.y + mv[2]) / 256) * 256
  else page = math.floor((lk.x + mv[1]) / 256) * 256 end
  return axis, page + start, page + target, kind
end

return D
