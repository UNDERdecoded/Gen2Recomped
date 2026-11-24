-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 60: Link against the indoor diagonal walls, as the cartridge does it.
--
-- The tile handlers of the diagonal attributes set no wall bit (+0x97C):
-- 0x10-0x13 (0x080A0698) OR the probe's bit (+0x974) into +0x978 and set
-- the diagonal kind +0x172E = 0x081682F6[attr & 3] (u16); 0x18-0x1B
-- (0x0809FE64) also OR it into +0x16E4. TileDetect_Movement_Y / _X
-- (0x0809EA40 / 0x0809EB58, which clear +0x978 / +0x97C / +0x16E4 first,
-- 0x0809E970) keep the probe rows: +0x1708 = the Y probe's row, or y + 16
-- for X (+0x170C = y + 23). The kind is cleared once a frame
-- (0x0809407C).
--
--   * FlagMovingIntoSlopes_Y (0x08093B68, from the indoor Y check at
--     0x080950C2 when (+0x97C & 7) == 0 and (+0x978 & 5) != 0): the slope's
--     depth at Link's column, d = 0x08167D02[kind * 4 + (x' & 7)] - (row &
--     7) (x' = x - 1 when the right probe hit); for 0x18-0x1B the row part
--     is 8 - (row & 7) or (row & 7) + 8 by (kind & 2), negated going up;
--     up and d > 0 -> y += d, +0x172B = 8; down and d < 0 -> y += d, 4;
--     then +0x172B |= 0x08167D22[right probe ? 2 : 3] | 0x10 (the side to
--     slide to). +0x172B & 0xF set -> the rest of the Y check is skipped.
--   * FlagMovingIntoSlopes_X (0x08093CF8, from the X check at 0x08096562
--     when (+0x97C & 2) == 0 and (+0x978 & 5) != 0): the same on x with the
--     row (y + 16 or, the lower probe hit, y + 23) and x - 1 for kind 6;
--     2 / 1 by the direction, | 0x08167D22[kind & 2 ? 0 : 1] | 0x20.
--   * The next frame Player_LimitDirections_Inner (0x0809380C) ends with
--     (0x08093AE0..FE) link_direction = +0x172B & 0xF when both are set:
--     Link walks along the slope (straight speed, +0x172A from the held
--     keys); the cardinal checks (0x0809E650) skip Y while +0x172B & 0x20,
--     X while & 0x10.
--   * Diagonal keys (both velocities, 0x08093EB0 from 0x0809407C unless
--     +0x172B & 0x30): X probe + FlagMovingIntoSlopes_X, x put back and its
--     change kept as the x velocity, Y probe + FlagMovingIntoSlopes_Y, the
--     y change as the y velocity; then x += 0x08167D26[v] / 0x08167D30[-v]
--     and y += 0x08167D3A[v] / 0x08167D44[-v] (s8), +0x172D = +0x172B,
--     +0x172B = 0.
--
-- Before this the port's room grid made every diagonal tile a wall: Link
-- stopped dead walking straight into a slope (the Swamp Palace's 0x16
-- corridor) and only held diagonals got past.
-- OURS: velocities above 9 read the last table entry.

local M = {}

local RT = require("src.zelda.alttp.RomTables")
M.KIND = RT.get("slope60.kind")    -- 0x081682F6: kind by attr & 3
M.DEPTH = RT.get("slope60.depth")  -- 0x08167D02: 32 depths
M.SIDE = RT.get("slope60.side")    -- 0x08167D22: 8, 4, 2, 1
M.PXP = RT.get("slope60.pxp")      -- 0x08167D26
M.PXN = RT.get("slope60.pxn")      -- 0x08167D30
M.PYP = RT.get("slope60.pyp")      -- 0x08167D3A
M.PYN = RT.get("slope60.pyn")      -- 0x08167D44

local bit = require("bit")
local band, bor = bit.band, bit.bor

local function s8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end
local function ready() return M.DEPTH[0] ~= nil and M.KIND[0] ~= nil end
M.ready = ready

-- 0x10-0x13 / 0x18-0x1B
function M.isDiag(a) return a ~= nil and a >= 0x10 and a <= 0x1B and band(a, 0xC) ~= 0xC end
function M.isSolidDiag(a) return a ~= nil and a >= 0x18 and a <= 0x1B end

-- a tile handler on a diagonal (point bit `bits`); true when it was one
function M.mark(lk, a, bits)
  if not (ready() and M.isDiag(a)) then return false end
  lk.r12 = bor(lk.r12 or 0, bits)
  if M.isSolidDiag(a) then lk.r16e4 = bor(lk.r16e4 or 0, bits) end
  lk.slopeK = M.KIND[band(a, 3)]
  return true
end

-- TileDetect_Movement's clear (0x0809E970) and its probe rows
function M.probes(lk, row1, row2)
  lk.r12, lk.r16e4 = 0, 0
  lk.tdY1, lk.tdY2 = row1, row2
end

-- FlagMovingIntoSlopes_Y (0x08093B68); yv the y velocity
function M.flagY(lk, yv)
  local K = lk.slopeK or 0
  local r4 = band(lk.tdY1 or 0, 7)
  local x = band(lk.x, 0xFF)
  if band(lk.r12 or 0, 4) ~= 0 then x = band(x - 1, 0xFF) end
  local idx = band(K * 4 + band(x, 7), 0xFF)
  local v
  if band(lk.r16e4 or 0, 5) ~= 0 then
    local r1 = r4
    local r2 = band(K, 2) == 0 and band(8 - r1, 0xFF) or (r1 + 8)
    r2 = band((M.DEPTH[idx] or 0) - r2, 0xFF)
    if yv == 0 then return end
    if yv < 0 then r2 = band(-r2, 0xFF) end
    v = s8(r2)
  else
    v = s8((M.DEPTH[idx] or 0) - r4)
  end
  if yv == 0 then return end
  local d
  if yv < 0 then
    if v <= 0 then return end
    lk.y = lk.y + v; d = 8
  else
    if v >= 0 then return end
    lk.y = lk.y + v; d = 4
  end
  local r3 = band(lk.r12 or 0, 4) ~= 0 and 2 or 3
  lk.slopeD = bor(d, M.SIDE[r3] or 0, 0x10)
end

-- FlagMovingIntoSlopes_X (0x08093CF8); xv the x velocity
function M.flagX(lk, xv)
  local K = lk.slopeK or 0
  local x = band(lk.x, 0xFF)
  if K == 6 then x = band(x - 1, 0xFF) end
  local r960 = band(x, 7)
  local row = band(lk.r12 or 0, 4) ~= 0 and (lk.tdY2 or 0) or (lk.tdY1 or 0)
  local idx = band(band(row, 7) + K * 4, 0xFF)
  local v
  if band(lk.r16e4 or 0, 5) ~= 0 then
    local r3 = band(lk.x, 7)
    local r0
    if K == 4 or K == 6 then r0 = (M.DEPTH[idx] or 0) - (8 - r3) else r0 = -r3 end
    r0 = band(r0, 0xFF)
    if xv == 0 then return end
    if xv < 0 then r0 = band(-r0, 0xFF) end
    v = s8(r0)
  else
    v = s8((M.DEPTH[idx] or 0) - r960)
  end
  if xv == 0 then return end
  local d
  if xv < 0 then
    if v <= 0 then return end
    lk.x = lk.x + v; d = 2
  else
    if v >= 0 then return end
    lk.x = lk.x + v; d = 1
  end
  local r2 = band(K, 2) == 0 and 1 or 0
  lk.slopeD = bor(d, M.SIDE[r2] or 0, 0x20)
end

-- the indoor Y check's slope step (0x080950A0..D6): true = the check ends
function M.afterY(lk, yv, r14)
  if not ready() then return false end
  if band(r14, 7) == 0 and band(lk.r12 or 0, 5) ~= 0 then
    M.flagY(lk, yv)
    if band(lk.slopeD or 0, 0xF) ~= 0 then
      lk.slopeHits = (lk.slopeHits or 0) + 1
      return true
    end
  end
  lk.slopeD = 0
  return false
end

-- the indoor X check's slope step (0x08096540..76)
function M.afterX(lk, xv, r14)
  if not ready() then return false end
  if band(r14, 2) == 0 and band(lk.r12 or 0, 5) ~= 0 then
    M.flagX(lk, xv)
    if band(lk.slopeD or 0, 0xF) ~= 0 then
      lk.slopeHits = (lk.slopeHits or 0) + 1
      return true
    end
  end
  lk.slopeD = 0
  return false
end

-- Player_LimitDirections_Inner's last step (0x08093AE0..FE)
function M.direction(lk, dir)
  if not ready() then return dir end
  local d = band(lk.slopeD or 0, 0xF)
  if band(dir, 0xF) ~= 0 and d ~= 0 then return d end
  return dir
end

local function push(tp, tn, v)
  if v >= 0 then return s8(tp[math.min(v, 9)] or 0) end
  return s8(tn[math.min(-v, 9)] or 0)
end
M.push = push

-- 0x08093EB0 for diagonal keys; detectX / detectY run the port's probes
-- (they call M.probes and the tile handlers). Returns the new xv, yv.
function M.diagonal(lk, xv, yv, detectX, detectY)
  lk.slopeHandled = 0
  if not ready() or yv == 0 or xv == 0 then lk.slopeD = 0 return xv, yv end
  local sx, sy = lk.x, lk.y
  detectX(xv < 0 and 2 or 3)
  if band(lk.r12 or 0, 5) == 0 then lk.slopeD = 0 return xv, yv end
  M.flagX(lk, xv)
  if band(lk.slopeD or 0, 0xF) == 0 then lk.slopeD = 0 return xv, yv end
  xv = s8(lk.x - sx)
  lk.x = sx
  detectY(yv >= 0 and 1 or 0)
  if band(lk.r12 or 0, 5) == 0 then lk.slopeD = 0 return xv, yv end
  M.flagY(lk, yv)
  if band(lk.slopeD or 0, 0xF) == 0 then lk.slopeD = 0 return xv, yv end
  lk.slopeHandled = lk.slopeD
  yv = s8(lk.y - sy)
  lk.x = lk.x + push(M.PXP, M.PXN, xv)
  lk.y = lk.y + push(M.PYP, M.PYN, yv)
  lk.slopeD = 0
  lk.slopeDiag = (lk.slopeDiag or 0) + 1
  return xv, yv
end

return M
