-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SMITHS AND THE FROG (round 30; research in round 29, 29.4).
--
-- Sprite 0x1A (GBA routine 0x080D36DC; zelda3 Sprite_1A_Smithy) by
-- subtype2: 0 the smith (0x080D3064, Smithy_Main), 1 the spark
-- (Smithy_Spark), 2 the frog (0x080D2FA0, Smithy_Frog), 3 the partner
-- walking home (Smithy_Homecoming). The GBA's tables, read at import (OFF):
-- kSmithy_Dmd 0x174DF4 (by graphics * 4 + D * 2, two entries),
-- kReturningSmithy_Dmd / _Dma 0x174D64 / 0x174DA4 (one entry, its tile
-- DMA'd from follower 8's sheet), kSmithyFrog_Dmd 0x174DAC, kSmithySpark_Dmd
-- 0x174EA4 and its Gfx / Delay 0x174E94 / 0x174E9B, the hammer's kSmithy_Gfx
-- / kSmithy_B 0x174DB4 / 0x174DBC, the partner's walk (kReturningSmithy_
-- Delay / Dir / Xvel / Yvel 0x174D54 / 56 / 59 / 5D). Followers 7 (the frog)
-- and 8 (the dwarf) are drawn by Tagalong_Draw's tables:
-- kTagalongDmaAndFlags 0x17EA0E, kTagalongDraw_SprXY 0x17EA3E (s16),
-- kTagalongDraw_Offs 0x17EBFE (u16), kTagalongDraw_Pals 0x17EC3A, from the
-- follower sheet (Sprites.info.follower, as OldMan.lua).
--
-- SpritePrep_Smithy: in the Dark World the frog (area 0x69's list) is
-- there unless the smiths are reunited (sram_progress_indicator_3 & 0x20,
-- here progress.smith) or someone follows Link. In the smithy (room 0x121)
-- the smith moves (+2, -3); reunited, his partner stands 0x2C to the right
-- (D 1, hammer phase 4); tempering (& 0x80) puts both in state 5.
-- The frog hops (z velocity -2 a frame, 16 on landing), blocks Link and asks
-- 0xE1 (solicited); then he is follower 7 (Sprite_BecomeFollower) and the
-- sprite is gone. A world switch turns follower 7 into 8 and back
-- (Link's mirror / portal code: follower_indicator ^= 7 ^ 8).
-- The smith (states, messages = SNES numbers, GBA - 3):
--   0  follower 8 and Link's y low byte < 0xC2: 0xE0, state 10, Link held;
--      else a dash into him (GBA 0x080D383C; the SNES listened for the
--      hammer) 0xE4 (and 96 frames before the next); reunited: 0xD8 -> 1;
--      else 0xDF
--   1  choice 0: 0xD9 -> 2; else 0xDC -> 0
--   2  choice 0: sword < 3 -> 0xDA -> 3, else 0xDB -> 0; else 0xDC -> 0
--   3  choice 0 and 10 Rupees: pay, 0xDD, both smiths 5, no sword
--      (link_sword_type 0xFF), & 0x80, the area-change flag cleared; else 0xDC
--   4/5 dash: 0xE4; once Link has been in another area
--      (flag_overworld_area_did_change, GBA +0xCB4): 0xDE -> 6 (graphics 4);
--      else 0xE2
--   6  receipt 2 (the Tempered Sword), & ~0x80, both 0
--   10 the partner (subtype 3) appears on Link, the follower goes, -> 11
--   11 0xE3
-- The hammer: while either smith's state is 0 (both), 5, 7 or 9 the phase
-- steps by kSmithy_B; phase 1 hops (z velocity 16), phase 3 makes a spark
-- (+-15, +2). The partner walks (104 frames up, 12 left at 13), then 0xE3,
-- & 0x20 (reunited).
--
-- OURS: talking is R while facing (the touch + R of Sprite_ShowSolicited-
-- Message); the dash test is our dash state touching his box; the follower
-- trails 20 steps like OldMan.lua's and is drawn under Link; the dumb
-- barrier sprite 0x31 (subtype 1) is not spawned (Barrier29 makes 0x1A
-- solid); no sound; the area-change flag is not saved (it is RAM).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = {}

M.TYPE, M.ROOM, M.FROG_AREA = 0x1A, 0x121, 0x69
M.FROG, M.DWARF = 7, 8
M.RESCUED, M.TEMPER = 0x20, 0x80

M.OFF = {
  smith = { 0x174DF4, 20 }, ret = { 0x174D64, 8 }, retDma = 0x174DA4, frog = { 0x174DAC, 1 },
  spark = { 0x174EA4, 6 }, sparkGfx = 0x174E94, sparkDelay = 0x174E9B,
  hammerGfx = 0x174DB4, hammerB = 0x174DBC,
  retDelay = 0x174D54, retDir = 0x174D56, retXv = 0x174D59, retYv = 0x174D5D,
  tagDma = 0x17EA0E, tagXY = 0x17EA3E, tagOffs = 0x17EBFE, tagPals = 0x17EC3A,
}

local function dmd(rom, spec)
  local t = {}
  for i = 0, spec[2] - 1 do
    local p = spec[1] + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end
local function s8(t) for i, v in ipairs(t) do if v >= 128 then t[i] = v - 256 end end return t end
local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { smith = dmd(rom, O.smith), ret = dmd(rom, O.ret), frog = dmd(rom, O.frog), spark = dmd(rom, O.spark),
              retDma = rom:bytesU8(O.retDma, 8), sparkGfx = s8(rom:bytesU8(O.sparkGfx, 7)),
              sparkDelay = rom:bytesU8(O.sparkDelay, 6), hammerGfx = rom:bytesU8(O.hammerGfx, 8),
              hammerB = rom:bytesU8(O.hammerB, 8), retDelay = rom:bytesU8(O.retDelay, 3),
              retDir = s8(rom:bytesU8(O.retDir, 3)), retXv = s8(rom:bytesU8(O.retXv, 4)), retYv = s8(rom:bytesU8(O.retYv, 4)),
              tagDma = rom:bytesU8(O.tagDma, 48), tagOffs = rom:bytesU16(O.tagOffs, 14), tagPals = rom:bytesU8(O.tagPals, 14),
              tagXY = {} }
  for i = 0, 55 do
    local w = rom:bytesU16(O.tagXY + i * 8, 4)
    t.tagXY[i + 1] = { s16(w[1]), s16(w[2]), s16(w[3]), s16(w[4]) }
  end
  check(t.smith[1][5] == 2 and t.ret[1][5] == 2 and t.retDma[1] == t.retDma[2] and t.hammerB[1] == 24
        and t.retDir[3] == -1 and t.retXv[3] == -13 and t.sparkGfx[7] == -1 and t.tagOffs[8] == 0xC0
        and t.tagPals[8] == 4 and t.tagXY[1][1] == -2, "smithy tables")
  return t
end
local function T(game) local t = game.data.t and game.data.t.smith return t and t.smith and t or nil end
M.tabs = T

-- ------------------------------------------------------------ helpers
local function prog(game) return game.progress end
local function flags(game) return game.progress.smith or 0 end
local function setFlag(game, f, on)
  local p = game.progress
  p.smith = on and bor(p.smith or 0, f) or band(p.smith or 0, bit.bnot(f))
end
M.flags = flags
local function msg(game, n) return game:showMessage(n) end
local SM = require("src.zelda.alttp.RomTables").get("msg.smith")   -- r37: the smiths' messages
local PRICE = require("src.zelda.alttp.RomTables").get("price37")
local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end
local function swordLevel(game) return inv(game)[0x3D] or 0 end
local function touching(game, a, grow)
  local A = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if not cb then return false end
  local hx, hy, hw, hh = A.hitbox(cb, a)
  local lx, ly, lw, lh = A.linkBox(game.link)
  grow = grow or 0
  return A.overlapCart(lx - grow, ly - grow, lw + grow * 2, lh + grow * 2, hx, hy, hw, hh)
end
local function newSprite(base, x, y, sub2)
  return { type = M.TYPE, x = x, y = y, lower = base.lower, smith = true, sub2 = sub2, ai = 0, gfx = 0,
           delay = 0, D = 0, A = 0, B = 0, z = 0, zv = 0, fx = 0, fy = 0, vx = 0, vy = 0,
           dir = 1, t = 0, state = "idle", hp = 255, index = -1 }
end

-- ------------------------------------------------------------ the follower
local function initTrail(game, x, y, facing)
  local tr = {}
  for i = 0, 19 do tr[i] = { x, y, facing or 2 } end
  game.smTrail = { t = tr, v1 = 0, v2 = 0, key = game.omKey and game:omKey() }
end
function M.becomeFollower(game, a)
  game.progress.follower = M.FROG
  initTrail(game, a.x, a.y, game.link.facing)
  game.frogTaken = (game.frogTaken or 0) + 1
end
function M.followerFrame(game)
  local p = game.progress
  local f = p.follower or 0
  if f ~= M.FROG and f ~= M.DWARF then game.smTrail = nil return end
  -- a world switch: follower_indicator ^= 7 ^ 8 (indoors keeps the world
  -- Link came from)
  local want = game.link.world == "dw" and M.FROG or M.DWARF
  if f ~= want then p.follower = want end
  local lk = game.link
  local key = game.omKey and game:omKey()
  if not game.smTrail or game.smTrail.key ~= key then initTrail(game, lk.x, lk.y, lk.facing) end
  local tr = game.smTrail
  local moved = tr.lx and (tr.lx ~= lk.x or tr.ly ~= lk.y)
  tr.lx, tr.ly = lk.x, lk.y
  if moved then
    tr.v1 = (tr.v1 + 1) % 20
    tr.t[tr.v1] = { lk.x, lk.y - (lk.z or 0), lk.facing }
    if tr.v1 == tr.v2 then tr.v2 = (tr.v2 + 1) % 20 end
    tr.walk = true
  elseif band(game.frame or 0, 3) == 0 and tr.v1 ~= tr.v2 then
    local t = (tr.v1 - 9) % 20
    if t ~= tr.v2 then tr.v2 = (tr.v2 + 1) % 20 else tr.walk = false end
  else
    tr.walk = tr.v1 ~= tr.v2 and tr.walk
  end
end

-- ------------------------------------------------------------ the sprites
local function moveZ(a)
  a.zv = a.zv - 2
  local z = a.z * 16 + (a.zf or 0) + a.zv
  a.z, a.zf = math.floor(z / 16), z % 16
  if a.z < 0 then a.z, a.zf = 0, 0; return true end
  return false
end
local function moveXY(a)
  local px = a.x * 16 + (a.fx or 0) + (a.vx or 0)
  local py = a.y * 16 + (a.fy or 0) + (a.vy or 0)
  a.x, a.fx = math.floor(px / 16), px % 16
  a.y, a.fy = math.floor(py / 16), py % 16
end

function M.prep(actors, a)
  local game = actors.game
  a.smith, a.prepped = true, true
  a.sub2 = a.sub2 or 0
  a.ai, a.gfx, a.delay, a.D, a.A, a.B, a.z, a.zv, a.aux1 = 0, 0, 0, 0, 0, 0, 0, 0, 0
  if actors.room == -1 then
    -- the Dark World: the frog
    if band(flags(game), M.RESCUED) ~= 0 or (prog(game).follower or 0) ~= 0 then a.dead = true return end
    a.sub2, a.npc, a.D = 2, true, 1
    return
  end
  a.x, a.y = a.x + 2, a.y - 3
  if band(flags(game), M.RESCUED) ~= 0 then
    local b = newSprite(a, a.x + 0x2C, a.y, 0)
    b.D, b.A, b.prepped, b.partner = 1, 4, true, a
    a.partner = b
    if band(flags(game), M.TEMPER) ~= 0 then a.ai, b.ai = 5, 5 end
    actors.list[#actors.list + 1] = b
  end
end

local function spark(actors, a)
  local s = newSprite(a, a.x + (a.D ~= 0 and -15 or 15), a.y + 2, 1)
  s.prepped, s.noBarrier = true, true   -- (Smithy_Spark is no barrier)
  actors.list[#actors.list + 1] = s
end

local function bothState(a, v) a.ai = v; if a.partner then a.partner.ai = v end end

-- Smithy_Main
local function smithFrame(actors, a)
  local game, tb = actors.game, T(actors.game)
  if moveZ(a) then a.zv = 0 end
  if (a.aux1 or 0) > 0 then a.aux1 = a.aux1 - 1 end
  local j = a.partner and a.partner.ai or 0
  local i = a.ai
  local run = j == 5 or j == 7 or j == 9 or i == 5 or i == 7 or i == 9 or bor(i, j) == 0
  if run then
    if a.B == 0 then
      local k = a.A
      a.A = band(k + 1, 7)
      a.gfx, a.B = tb.hammerGfx[k + 1], tb.hammerB[k + 1]
      if k == 1 then a.zv = 16 end
      if k == 3 then spark(actors, a); game.smithSparks = (game.smithSparks or 0) + 1 end
    else a.B = a.B - 1 end
  end
  if game.textBox then return end
  local p = prog(game)
  if a.ai == 0 then
    if (p.follower or 0) == M.DWARF then
      if band(game.link.y, 0xFF) < 0xC2 then
        msg(game, SM.home)
        a.ai = 10
        game.smithHold = true
      end
    elseif game.dash and (a.aux1 or 0) == 0 and touching(game, a, 2) then
      msg(game, SM.dash)
      a.aux1 = 0x60
      game.dash = nil
    end
  elseif a.ai == 4 or a.ai == 5 then
    if game.dash and (a.aux1 or 0) == 0 and touching(game, a, 2) then
      msg(game, SM.dash)
      a.aux1 = 0x60
      game.dash = nil
    end
  elseif a.ai == 6 then
    bothState(a, 0)
    if a.partner then a.partner.ai = 0 end
    setFlag(game, M.TEMPER, false)
    require("src.zelda.alttp.Townsfolk30").give(game, 2)
    game.smithTempered = (game.smithTempered or 0) + 1
  elseif a.ai == 10 then
    local b = newSprite(a, game.link.x, game.link.y, 3)
    b.prepped, b.noBarrier = true, true   -- (Smithy_Homecoming: a barrier once home)
    actors.list[#actors.list + 1] = b
    a.ai = 11
    p.follower = 0
    game.smTrail = nil
    a.gfx = 4
  end
end

-- talking (R while facing): the solicited messages
function M.talk(game, a)
  local p = prog(game)
  if a.sub2 == 2 then
    if a.ai == 0 then
      msg(game, SM.frog)
      game.onTextDone = function() a.ai = 1 end
    end
    return true
  elseif a.sub2 == 3 then
    if a.ai == 1 then msg(game, SM.frog2) end
    return true
  elseif a.sub2 ~= 0 then return false end
  local s = a
  if s.ai == 0 then
    if (p.follower or 0) == M.DWARF then return false end
    if band(flags(game), M.RESCUED) ~= 0 then
      msg(game, SM.offer)
      game.onTextDone = function(g)
        if (g.lastChoice or 0) ~= 0 then msg(g, SM.no) return end
        msg(g, SM.ask)
        g.onTextDone = function(g2)
          if (g2.lastChoice or 0) ~= 0 then msg(g2, SM.no) return end
          if swordLevel(g2) >= 3 then msg(g2, SM.best) return end
          msg(g2, SM.price)
          g2.onTextDone = function(g3)
            local st = g3.stats
            if (g3.lastChoice or 0) ~= 0 or (st.rupees or 0) < PRICE.temper then msg(g3, SM.no) return end
            st.rupees = st.rupees - PRICE.temper
            msg(g3, SM.paid)
            bothState(a, 5)
            g3.smithAreaChanged = false
            local q = g3.progress
            q.smithSword = swordLevel(g3)
            q.inv = q.inv or {}
            q.inv[0x3D] = 0          -- link_sword_type 0xFF: no sword while it is tempered
            q.inv["61"] = nil
            q.sword = false
            setFlag(g3, M.TEMPER, true)
            g3.smithPaid = (g3.smithPaid or 0) + 1
          end
        end
      end
    else
      msg(game, SM.busy)
    end
    return true
  elseif s.ai == 4 or s.ai == 5 then
    if game.smithAreaChanged then
      msg(game, SM.done)
      game.onTextDone = function() a.ai = 6; a.gfx = 4 end
    else
      msg(game, SM.wait)
    end
    return true
  elseif s.ai == 11 then
    msg(game, SM.frog2)
    return true
  end
  return false
end

function M.update(actors, a)
  local game, tb = actors.game, T(actors.game)
  if not a.prepped then M.prep(actors, a) end
  if a.dead then return end
  if (a.delay or 0) > 0 then a.delay = a.delay - 1 end
  if a.sub2 == 0 then
    smithFrame(actors, a)
  elseif a.sub2 == 1 then
    if a.delay == 0 then
      local j = a.A
      a.A = band(j + 1, 7)
      local g = tb.sparkGfx[j + 1]
      if not g or g < 0 then a.dead = true return end
      a.gfx, a.delay = g, tb.sparkDelay[j + 1] or 1
    end
  elseif a.sub2 == 2 then
    -- the frog hops
    if moveZ(a) then a.zv = 16 end
    a.D = 1
    if a.ai == 1 and not game.textBox then
      M.becomeFollower(game, a)
      a.dead = true
    end
  elseif a.sub2 == 3 then
    if a.ai == 0 then
      game.smithHold = true
      moveXY(a)
      a.gfx = band(rshift(band(game.frame or 0, 255), 3), 1)
      if a.delay == 0 then
        local j = a.A
        a.A = j + 1
        a.delay = tb.retDelay[j + 1] or 0
        local d = tb.retDir[j + 1]
        if d and d >= 0 then
          a.D, a.vx, a.vy = d, tb.retXv[d + 1], tb.retYv[d + 1]
        else
          a.ai, a.vx, a.vy = 1, 0, 0
        end
      end
    else
      a.D, a.noBarrier = 1, nil
      game.smithHold = nil
      if band(flags(game), M.RESCUED) == 0 then
        setFlag(game, M.RESCUED, true)
        game.smithReunited = (game.smithReunited or 0) + 1
      end
    end
  end
end

-- ------------------------------------------------------------ drawing
local function oamFlags(spr) return band(spr.info.flags3[M.TYPE + 1] or 0, 0x0F) end

local function rgba(c) return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31 end
-- a follower's 16 x 16 tiles at DMA offset var (the follower sheet:
-- 0x65 + (v >> 11) for followers 2-8, as OldMan.lua)
local function followerImage(spr, f, var, palRow)
  local key = "sm" .. f .. ":" .. var .. ":" .. palRow
  local im = spr.cache[key]
  if im ~= nil then return im or nil end
  local v = spr.info.follower[f + 1] or 0
  local base = (0x65 + rshift(v, 11)) * 4096 + band(v, 0x7FF) + var * 2
  local img = love.image.newImageData(16, 16)
  local src, pal = spr.data.spr, spr.pal[palRow] or spr.pal[4]
  for ty = 0, 1 do
    for tx = 0, 1 do
      local off = base + ty * 0x200 + tx * 32
      for y = 0, 7 do
        for xb = 0, 3 do
          local b = src:byte(off + y * 4 + xb + 1) or 0
          local lo, hi = b % 16, math.floor(b / 16)
          if lo ~= 0 then local r, g, bb = rgba(pal[lo]) img:setPixel(tx * 8 + xb * 2, ty * 8 + y, r, g, bb, 1) end
          if hi ~= 0 then local r, g, bb = rgba(pal[hi]) img:setPixel(tx * 8 + xb * 2 + 1, ty * 8 + y, r, g, bb, 1) end
        end
      end
    end
  end
  im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  spr.cache[key] = im
  return im
end
local function tile16(spr, f, var, row, x, y, hf, vf)
  local im = followerImage(spr, f, var, row)
  love.graphics.draw(im, x + (hf and 16 or 0), y + (vf and 16 or 0), 0, hf and -1 or 1, vf and -1 or 1)
end
M.tile16 = tile16   -- r66: Blind66 draws the follower slot's chars (Blind's picture 21)

-- Tagalong_Draw for followers 7 / 8: head (char 0x20, dma6) and body
-- (0x22, dma7) by frame = direction + (4 standing / walking step)
function M.drawFollower(spr, tb, f, dir, walk, step, x, y)
  local av = walk and band(step, 4) or 4
  local frame = dir + av
  local d = tb.tagDma
  local dma6, dma7, fl = d[frame * 3 + 1], d[frame * 3 + 2], d[frame * 3 + 3]
  local xy = tb.tagXY[frame + rshift(tb.tagOffs[f + 1] or 0, 3) + 1]
  local pal = tb.tagPals[f + 1] or 4
  local bf = band(fl, 0x0F) * 16
  tile16(spr, f, dma7, pal, x + xy[4], y + xy[3] + 8, band(bf, 0x40) ~= 0, band(bf, 0x80) ~= 0)
  local hfl = band(fl, 0xF0)
  tile16(spr, f, dma6, pal, x + xy[2], y + xy[1], band(hfl, 0x40) ~= 0, band(hfl, 0x80) ~= 0)
end

function M.draw(spr, a, x, y, frame)
  local tb = spr.data.t and spr.data.t.smith
  if not (tb and tb.smith) then return false end
  local f = oamFlags(spr)
  y = y - (a.z or 0)
  if a.sub2 == 0 then
    spr:drawDmd(a, tb.smith, (a.gfx or 0) * 4 + (a.D or 0) * 2, 2, x, y, f)
  elseif a.sub2 == 1 then
    spr:drawDmd(a, tb.spark, (a.gfx or 0) * 2, 2, x, y, f)
  elseif a.sub2 == 2 then
    spr:drawDmd(a, tb.frog, 0, 1, x, y, f)
  elseif a.sub2 == 3 then
    local j = (a.D or 0) * 2 + (a.gfx or 0)
    local e = tb.ret[j + 1]
    local fl = bxor(e[4], f)
    tile16(spr, M.DWARF, tb.retDma[j + 1] or 0, band(rshift(fl, 1), 7), x + e[1], y + e[2], band(fl, 0x40) ~= 0, false)
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  local A = require("src.zelda.alttp.Actors")
  local up0 = A.update
  function A:update()
    local game = self.game
    if game and T(game) and not game.textBox then
      local list = self.list
      for i = 1, #list do
        local a = list[i]
        if a.type == M.TYPE and not a.dead and (self.room == M.ROOM or a.smith) then M.update(self, a) end
      end
    end
    return up0(self)
  end
  -- the frog in the Dark World's area 0x69 (Npc.spawnArea's lists)
  local N = require("src.zelda.alttp.Npc")
  local spawn0 = N.spawnArea
  function N.spawnArea(game, oa)
    spawn0(game, oa)
    local t = game.data.t and game.data.t.npc
    if not (T(game) and t and game.area and game.area.parent == M.FROG_AREA) then return end
    local prg = game:storyProgress()
    local phase = (prg == 2 and 2) or (prg == 3 and 3) or 1
    local list = t.ow[phase] and t.ow[phase][M.FROG_AREA + 1]
    local bx, by = (M.FROG_AREA % 8) * 512, math.floor((M.FROG_AREA % 64) / 8) * 512
    for _, e in ipairs(list or {}) do
      if e[3] == M.TYPE then
        local a = { type = M.TYPE, x = bx + e[2] * 16, y = by + e[1] * 16, lower = false, dir = 1, t = 0,
                    state = "idle", hp = 255, index = -1 }
        oa.list[#oa.list + 1] = a
        M.prep(oa, a)
      end
    end
  end
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if a.type == M.TYPE and a.smith and self.data.t and self.data.t.smith and self.data.t.smith.smith then return M.draw(self, a, x, y, frame) end
    return da0(self, a, x, y, frame, room)
  end
  -- the follower, the area-change flag
  local upd0 = G.update
  function G:update(dt)
    local r = upd0(self, dt)
    if T(self) and (self.state == "play" or self.state == "room") and not self.roomScroll and not self.scroll then
      M.followerFrame(self)
      if self.state == "play" and self.area then
        local k = self.area.parent .. self.link.world
        if self.smithLastArea and self.smithLastArea ~= k then self.smithAreaChanged = true end
        self.smithLastArea = k
      end
    end
    return r
  end
  -- R in front of a smith (rooms) or the frog (outdoors)
  local function facing(game, list)
    local C = require("src.zelda.alttp.Carry")
    local q = C.QUERY[game.link.facing]
    local px, py = game.link.x + q[1], game.link.y + q[2]
    local cb = game.data.roomIdx and game.data.roomIdx.combat
    for _, a in ipairs(list) do
      if a.type == M.TYPE and a.smith and not a.dead then
        local hx, hy, hw, hh = a.x, a.y, 16, 16
        if cb then hx, hy, hw, hh = A.hitbox(cb, a) end
        if px >= hx - 4 and px < hx + hw + 4 and py >= hy - 4 and py < hy + hh + 4 then return a end
      end
    end
  end
  local act0 = G.escapeAct
  function G:escapeAct()
    if T(self) and self.actors and self.interior and not self.textBox then
      local a = facing(self, self.actors.list)
      if a and M.talk(self, a) then self.smithTalks = (self.smithTalks or 0) + 1 return true end
    end
    return act0(self)
  end
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if inp.a and T(self) and self.owActors and not self.textBox then
      local a = facing(self, self.owActors.list)
      if a and M.talk(self, a) then self.smithTalks = (self.smithTalks or 0) + 1 return true end
    end
    return owFrame(self, inp)
  end
  -- Link held (flag_is_link_immobilized) while the partner walks home
  local roomFrame = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    -- (the room's sprites run inside escapeRoomFrame: only Link's input goes)
    if self.smithHold and inp then
      for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "y" }) do inp[k] = false end
    end
    return roomFrame(self, inp)
  end
  -- the follower under Link
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    local f = self.progress.follower or 0
    if lk == self.link and not tint and (f == M.FROG or f == M.DWARF) and self.smTrail and T(self) then
      local spr = self:shadowSprites()
      if spr then
        local tr = self.smTrail
        local p = tr.t[tr.v2]
        local d = ({ [0] = 0, 1, 2, 3 })[math.floor((p[3] or 2) / 2)] or 1
        M.drawFollower(spr, T(self), f, d, tr.walk, band(rshift(self.frame or 0, 1), 0xFF), p[1] - self.cam.x, p[2] - self.cam.y)
      end
    end
    return dl0(self, lk, tint)
  end
end

return M
