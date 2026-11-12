-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- OUTDOOR ENEMIES (round 25): the overworld's own sprites from the area
-- lists (Npc.lua's per-phase lists, the GBA's 0x080CB140 =
-- Overworld_LoadSprites), loaded the cartridge's way and run by the SNES
-- routines the GBA keeps (zelda3 names; every table read from the GBA ROM,
-- file offsets in OFF, found by value with r25/py/tabfind.py /
-- dmdsearch.py):
--
-- LOADING (GBA 0x080CB140 / 0x080CA934 / 0x080CA988 / 0x080CA9F8 /
-- 0x080CAA64 / 0x080CBD44 = Overworld_LoadSprites,
-- Sprite_ActivateAllProxima, Sprite_ActivateWhenProximal(Big),
-- Sprite_Overworld_ProximityMotivatedLoad, Overworld_LoadProximaSpriteIfAlive):
-- the list goes into a 16 px grid (sprite_where_in_overworld, 0x02006B80);
-- on the area's load the 22 columns from the camera's x - 16 are loaded
-- (rows y - 0x30 .. + 21 * 16); then each frame the camera moved, the
-- column at x + 0x110 / x - 0x10 (GBA table 0x1728A8) or the row at
-- y + 0x110 / y - 0x10 (columns x - 0x30 ..) is loaded. A grid cell loads
-- once (overworld_sprite_was_loaded, 0x02007B80) until its sprite leaves
-- the screen box (GBA 0x080C5ACC = Sprite_PrepOamCoordOrDoubleRet: x - cam
-- + 0x40 or y - cam + 0x40 above 0x16F -> Sprite_KillSelf 0x080CB1E0, the
-- cell can load again; sprite_defl_bits & 0x80 keeps it). A killed sprite's
-- cell stays loaded: it is back only when the area is loaded again.
-- Overworld_AllocSprite: the highest free slot from 13 (14 for 0xEB / 0x53).
--
--   0x00 Sprite_Raven (SpritePrep_Raven: bump 0x81 / health 4 / prize 6 in
--        the Light World): waits until Link is within 0x50 x 0x58, rises
--        24 frames, flies at Link (speed 32, nudged 1 a step every other
--        frame) for kRaven_AscendTime[A] frames, then flees at 48.
--   0x01 Sprite_01_Vulture: dormant 160 frames, rises 16, circles Link
--        (the projection at (k & 15) + 24 turned 90 degrees, pulled in by a
--        quarter of it outside a 0x28 box), every other frame by slot.
--   0x0D Sprite_0D_Buzzblob: wanders (kBuzzBlob_Xvel / Yvel / Delay by rng
--        & 7), bounces off walls; the fighter sword zaps Link
--        (Sprite_AttemptZapDamage: delay_aux1 64, link_electrocute_on_touch,
--        Sprite_AttemptDamageToLinkPlusRecoil; LinkState_Zapped: 8 steps of
--        3 frames held).
--   0x27 Sprite_27_Deadrock: picks a direction (every 4th towards Link)
--        for 32-63 frames at 32, turns at walls; the sword stuns it (damage
--        0, sprite_flags & 4: sprite_F 15 -> at 14 it turns to stone for
--        255 frames (defl bit 4: the sword tinks), shaking from 0x20 left).
--   0x4C Sprite_4C_Geldman: under the sand at its home until Link is
--        within 0x30 (every 8th frame by slot), emerges 31 frames, pursues at
--        16 for 96 frames (the only state it hurts or can be hurt), sinks
--        8 frames, back home after 16.
--   0xC9 Sprite_Tektite: hops (z speed 24-31, 1 of 4 directions at 16),
--        every 4th hop a 48-111 frame run of small hops towards Link's side;
--        jumps away (32) when Link comes within 40 px not facing it.
--   0xD4 Sprite_D4_Landmine: touching Link (Sprite_CheckDamageToLink)
--        starts an 8-frame blink, then the sprite bomb (Sprite_SpawnBomb ->
--        SpriteModule_Die -> Sprite_4A_BombGuard with C 2: 31 frames,
--        hit box 9, it hurts Link; SpriteDraw_SpriteBombExplosion).
--
-- OURS: no sound; the overlords in the lists (0xF4+: falling rocks) are not
-- loaded; the Buzzblob's Cukeman talk (magic powder) and the zap's palette
-- flash / mosaic are not drawn; the Landmine's bomb does not hurt other
-- sprites (SpriteBomb_CheckDamageToSprite) nor break tiles; sloped tiles
-- (0x10-0x13) count as solid for the sprites; the slot numbers count only
-- these sprites.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local OE = {}

OE.OFF = {
  flags2 = 0x2275A4,                       -- kSpriteInit_Flags2 (243)
  prox = 0x1728A8,                         -- the proximity offsets (s16 0x110, -0x10)
  raven = 0x177498,                        -- kSpriteRaven_BumpDamage / Health / Flags5 (2 each)
  ravenAscend = 0x1774B0,                  -- kRaven_AscendTime (2)
  vultureGfx = 0x1774BC, vultureDmd = 0x1774C0,
  buzzGfx = 0x177568, buzzPrio = 0x17756C, buzzXv = 0x177570, buzzYv = 0x177578, buzzDelay = 0x177580,
  buzzDrawX = 0x177588, buzzDrawY = 0x17758E, buzzChar = 0x177594, buzzFlags = 0x1775B8, buzzExt = 0x1775CA,
  rockGfx = 0x1777E4, rockFlags = 0x1777ED, rockXv = 0x177804, rockYv = 0x177808,
  geldEmerge = 0x177CC4, geldPursue = 0x177CCC, geldSubmerge = 0x177CCE,
  geldX = 0x177CD3, geldY = 0x177CE5, geldChar = 0x177CF7, geldFlags = 0x177D09, geldBig = 0x177D1B,
  tekPrep = 0x178A40,                      -- kGanonHelpers_OamFlags / Health / BumpDamage (2 each)
  tekDir = 0x178A68, tekXv = 0x178A6C, tekYv = 0x178A70, tekDmd = 0x178A74,
  mineFlags = 0x178CCC, mineDmd = 0x178CD0,
  bombX = 0x1773AC, bombY = 0x1773BC, bombChar = 0x1773CC, bombFlags = 0x1773DC,
}

-- the types this module loads and runs
OE.TYPES = { [0x00] = true, [0x01] = true, [0x0D] = true, [0x27] = true, [0x4C] = true, [0xC9] = true, [0xD4] = true }
-- what the shared actor code fights (contact, the sword, prizes)
OE.FIGHTS = { [0x00] = true, [0x01] = true, [0x0D] = true, [0x27] = true, [0x4C] = true, [0xC9] = true }

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
local function dmd(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local p = o + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end

-- ------------------------------------------------------------ import
function OE.extract(rom, R, check)
  local O = OE.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = {
    flags2 = u8(O.flags2, 243), prox = s16(rom:bytesU16(O.prox, 2)),
    ravenBump = u8(O.raven, 2), ravenHp = u8(O.raven + 2, 2), ravenF5 = u8(O.raven + 4, 2),
    ravenAscend = u8(O.ravenAscend, 2),
    vultureGfx = u8(O.vultureGfx, 4), vultureDmd = dmd(rom, O.vultureDmd, 8),
    buzzGfx = u8(O.buzzGfx, 4), buzzPrio = u8(O.buzzPrio, 4), buzzXv = s8(u8(O.buzzXv, 8)),
    buzzYv = s8(u8(O.buzzYv, 8)), buzzDelay = u8(O.buzzDelay, 8),
    buzzDrawX = s16(rom:bytesU16(O.buzzDrawX, 3)), buzzDrawY = s16(rom:bytesU16(O.buzzDrawY, 3)),
    buzzChar = rom:bytesU16(O.buzzChar, 18), buzzFlags = u8(O.buzzFlags, 18), buzzExt = u8(O.buzzExt, 3),
    rockGfx = u8(O.rockGfx, 9), rockFlags = u8(O.rockFlags, 9), rockXv = s8(u8(O.rockXv, 4)), rockYv = s8(u8(O.rockYv, 4)),
    geldEmerge = u8(O.geldEmerge, 8), geldPursue = u8(O.geldPursue, 2), geldSubmerge = u8(O.geldSubmerge, 5),
    geldX = s8(u8(O.geldX, 18)), geldY = s8(u8(O.geldY, 18)), geldChar = u8(O.geldChar, 18),
    geldFlags = u8(O.geldFlags, 18), geldBig = u8(O.geldBig, 18),
    tekOam = u8(O.tekPrep, 2), tekHp = u8(O.tekPrep + 2, 2), tekBump = u8(O.tekPrep + 4, 2),
    tekDir = u8(O.tekDir, 4), tekXv = s8(u8(O.tekXv, 4)), tekYv = s8(u8(O.tekYv, 4)), tekDmd = dmd(rom, O.tekDmd, 6),
    mineFlags = u8(O.mineFlags, 4), mineDmd = dmd(rom, O.mineDmd, 2),
    bombX = s8(u8(O.bombX, 16)), bombY = s8(u8(O.bombY, 16)), bombChar = u8(O.bombChar, 16), bombFlags = u8(O.bombFlags, 16),
  }
  -- structural checks (shapes, not the data)
  check(t.prox[1] == -t.prox[2] + 0x100 and t.flags2[0x41 + 1] ~= nil, "overworld proximity table")
  check(t.ravenAscend[1] < t.ravenAscend[2] and t.ravenHp[1] < t.ravenHp[2] and t.vultureDmd[1][5] == 2
        and t.vultureDmd[1][1] == -t.vultureDmd[2][1], "raven / vulture tables")
  check(t.buzzXv[1] == -t.buzzXv[4] and t.buzzDelay[7] > t.buzzDelay[1] and t.buzzExt[3] == 2, "buzzblob tables")
  check(t.rockXv[1] == -t.rockXv[2] and t.rockYv[3] == -t.rockYv[4] and t.rockGfx[9] == 4, "deadrock tables")
  check(t.geldBig[18] == 2 and t.geldBig[1] == 0 and t.geldSubmerge[5] == t.geldSubmerge[4], "geldman tables")
  check(t.tekXv[1] == -t.tekXv[2] and t.tekDmd[1][5] == 2 and t.mineDmd[2][4] == 0x40 and t.bombFlags[2] == 0x40,
        "tektite / landmine / bomb tables")
  return t
end
local function T(game) return game.data.t and game.data.t.owe end
OE.tabs = T

-- ------------------------------------------------------------ helpers
local function A() return require("src.zelda.alttp.Actors") end
local function cbOf(game) return game.data.roomIdx and game.data.roomIdx.combat end
local function palT(game) return game.data.roomIdx and game.data.roomIdx.palace end
local function rnd(game) return require("src.zelda.alttp.Drops").rng(game:dropRng()) end

-- Sprite_MoveXY / Sprite_MoveZ: 1/16 px (8.8 positions)
local function moveXY(a)
  local px = a.x * 16 + (a.fx or 0) + (a.vx or 0)
  local py = a.y * 16 + (a.fy or 0) + (a.vy or 0)
  a.x, a.fx = math.floor(px / 16), px % 16
  a.y, a.fy = math.floor(py / 16), py % 16
end
local function moveZ(a)
  local pz = (a.z or 0) * 16 + (a.fz or 0) + (a.vz or 0)
  a.z, a.fz = math.floor(pz / 16), pz % 16
end
local function wrap8(v) v = v % 256 return v >= 128 and v - 256 or v end

-- Sprite_IsRightOfLink / Sprite_IsBelowLink (16-bit sign, low byte value)
local function rightOf(a, lk)
  local d = lk.x - a.x
  return d < 0, d % 256
end
local function below(a, lk)
  local d = lk.y + 8 + (a.z or 0) - a.y
  return d < 0, d % 256
end
-- Sprite_ProjectSpeedTowardsLink: x, y velocities, the low-byte distances
local function project(a, lk, vel)
  if vel == 0 then return 0, 0, 0, 0 end
  local bNeg, bB = below(a, lk)
  local rNeg, rB = rightOf(a, lk)
  local r12 = math.abs(wrap8(bB))
  local r13 = math.abs(wrap8(rB))
  local swapped = false
  if r13 < r12 then swapped = true; r12, r13 = r13, r12 end
  local xv, yv, t = vel, 0, 0
  for _ = 1, vel do
    t = t + r12
    if t >= r13 then t = t - r13; yv = yv + 1 end
  end
  if swapped then xv, yv = yv, xv end
  return rNeg and -xv or xv, bNeg and -yv or yv, rB, bB
end
OE.project = project
-- Sprite_DirectionToFaceLink: 0 Link right, 1 left, 2 below, 3 above
local function faceLink(a, lk)
  local bNeg, bB = below(a, lk)
  local rNeg, rB = rightOf(a, lk)
  local ym, xm = math.abs(wrap8(bB)), math.abs(wrap8(rB))
  if xm >= ym then return rNeg and 1 or 0, rB, bB end
  return (bNeg and 1 or 0) + 2, rB, bB
end

-- Sprite_CheckTileProperty at probe j (kSprite_Func5_X / Y) on the
-- overworld's attributes (Overworld_GetTileAttrAtLocation), solid by
-- kSprite_Func5_Tab3; outside the area: solid (flags2 & 0x40: gone)
local function solidAt(game, a, j)
  local c = cbOf(game)
  local x = a.x + (c.sprPointX[j + 1] or 8)
  local y = a.y + (c.sprPointY[j + 1] or 8)
  local ar = game.area
  if ar and (x < ar.x or y < ar.y or x >= ar.x + ar.w or y >= ar.y + ar.h) then return true end
  local b = game.ow:attrAt(game.link.world, x, y) or 0
  return (c.sprTileSolid[b + 1] or 0) ~= 0
end
local WALLBIT = { [0] = 8, 4, 2, 1 }
-- Sprite_CheckTileCollision (the velocity's directions; flags2 & 0x20:
-- the single point 0x35): sprite_wallcoll bits, the push back 1 (3 while
-- recoiling)
local function tileCollision(game, a)
  local P = palT(game)
  a.wall = 0
  if band(a.flags2 or 0, 0x20) ~= 0 then
    if solidAt(game, a, 0x35) then a.wall = 1 end
    return a.wall
  end
  local base = rshift(band(P.sprFlags[a.type + 1] or 0, 0xF0), 2)
  local n = a.recoil and 3 or 1
  if (a.vy or 0) ~= 0 then
    local yy = a.vy < 0 and 0 or 1
    if solidAt(game, a, base + yy) then a.wall = bor(a.wall, WALLBIT[yy]); a.y = a.y + ((yy == 1) and -n or n) end
  end
  if (a.vx or 0) ~= 0 then
    local yy = a.vx < 0 and 2 or 3
    if solidAt(game, a, base + yy) then a.wall = bor(a.wall, WALLBIT[yy]); a.x = a.x + ((yy == 3) and -n or n) end
  end
  return a.wall
end

local function timers(a)
  for _, k in ipairs({ "delay", "aux1", "aux2" }) do
    if (a[k] or 0) > 0 then a[k] = a[k] - 1 end
  end
end

-- Sprite_CheckDamageToLink (every 4th frame by slot, no hit timer): the
-- bump damage; true on contact
local function contact(self, a, lk, box)
  local game = self.game
  local cb = cbOf(game)
  if band(bxor(a.k or 0, self.frame), 3) ~= 0 or (a.inv or 0) > 0 then return false end
  local hx, hy, hw, hh
  if box then
    local b = { type = a.type, x = a.x, y = a.y }
    local save = cb.flags4[a.type + 1]
    cb.flags4[a.type + 1] = box
    hx, hy, hw, hh = A().hitbox(cb, b)
    cb.flags4[a.type + 1] = save
  else
    hx, hy, hw, hh = A().hitbox(cb, a)
  end
  local lx, ly, lw, lh = A().linkBox(lk)
  if not A().overlapCart(lx, ly, lw, lh, hx, hy - (a.z or 0), hw, hh) then return false end
  local cls = band(a.bump or cb.bump[a.type + 1] or 0, 0x0F)
  game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
  return true
end

-- ------------------------------------------------------------ loading
-- the area's list into the grid (Overworld_LoadSprites)
function OE.loadArea(game)
  local t = game.data.t and game.data.t.npc
  if not (t and game.area) then return nil end
  local parent = game.area.parent
  local prog = game:storyProgress()
  local phase = (prog == 2 and 2) or (prog == 3 and 3) or 1
  local lists = t.ow[phase]
  local list = lists and lists[parent + 1]
  if phase == 1 and parent >= 64 then list = nil end
  local st = { key = parent .. ":" .. game.link.world, grid = {}, loaded = {},
               bx = game.area.x, by = game.area.y, w = game.area.w, h = game.area.h, cx = nil, cy = nil, tog = 0 }
  for _, e in ipairs(list or {}) do
    if OE.TYPES[e[3]] then
      -- cell = the entry's 16 px spot in the area
      st.grid[e[2] .. "," .. e[1]] = e[3]
    end
  end
  game.oweState = st
  return st
end

local function alloc(oa, t)
  local used = {}
  for _, a in ipairs(oa.list) do if a.owe and not a.dead then used[a.k or -1] = true end end
  local top = (t == 0xEB or t == 0x53) and 14 or 13
  for i = top, 0, -1 do if not used[i] then return i end end
  return nil
end

-- the sprite's own setup (SpritePrep_* + SpritePrep_LoadProperties)
function OE.prep(game, a)
  local tb = T(game)
  local cb = cbOf(game)
  local t = a.type
  a.owe = true
  a.ai, a.delay, a.aux1, a.aux2 = 0, 0, 0, 0
  a.vx, a.vy, a.vz, a.z, a.fx, a.fy, a.fz = 0, 0, 0, 0, 0, 0, 0
  a.A, a.B, a.G, a.D, a.sub2, a.gfx, a.wall = 0, 0, 0, 0, 0, 0, 0
  a.hp = cb.health[t + 1] or 1
  a.flags2 = tb.flags2[t + 1] or 0
  local dw = game.link.world == "dw" and 2 or 1
  if t == 0x00 then
    a.bump, a.hp, a.flags5 = tb.ravenBump[dw], tb.ravenHp[dw], tb.ravenF5[dw]
    a.A = rshift(band(a.x, 16), 4)
  elseif t == 0x01 then
    a.A = rshift(band(a.x, 16), 4)
  elseif t == 0x4C then
    -- SpritePrep_Geldman: x + 8, home kept (SpritePrep_Kyameron)
    a.x = a.x + 8
    a.homeX, a.homeY = a.x, a.y
  elseif t == 0xC9 then
    -- SpritePrep_Tektite: A = x bit 4; its OAM flags, health, bump; the
    -- speed towards Link (16), z speed 32, state 1 (aloft)
    local j = band(rshift(a.x, 4), 1)
    a.A = j
    a.oam = tb.tekOam[j + 1]
    a.hp, a.bump = tb.tekHp[j + 1], tb.tekBump[j + 1]
    a.vx, a.vy = project(a, game.link, 16)
    a.vz = 32
    a.ai = 1
  elseif t == 0xD4 then
    a.untouchable = true   -- SpritePrep_IgnoreProjectiles; no sword (flags3 0x40)
  end
  -- the Deadrock's contact and sword are its own (OE.sword)
  if t == 0x27 then a.untouchable = true end
  return a
end

-- Overworld_LoadProximaSpriteIfAlive for the grid cell at world (x, y)
local function loadAt(game, oa, st, x, y)
  local xt, yt = x - st.bx, y - st.by
  if xt < 0 or yt < 0 or xt >= st.w or yt >= st.h then return end
  local key = math.floor(xt / 16) .. "," .. math.floor(yt / 16)
  local t = st.grid[key]
  if not t or st.loaded[key] then return end
  local k = alloc(oa, t)
  if not k then return end
  st.loaded[key] = true
  local a = { type = t, x = st.bx + math.floor(xt / 16) * 16, y = st.by + math.floor(yt / 16) * 16,
              lower = false, t = 0, index = -1, dir = 1, state = "chase", k = k, cell = key }
  OE.prep(game, a)
  oa.list[#oa.list + 1] = a
  game.oweSpawned = (game.oweSpawned or 0) + 1
end

-- Sprite_ActivateAllProxima (the area's load) and the per-frame
-- Sprite_ProximityActivation by the camera's movement
function OE.proximity(game, oa, st, all)
  local tb = T(game)
  local cx, cy = game.cam.x, game.cam.y
  if all then
    for i = 0, 21 do
      local x = cx - 16 + i * 16
      for r = 0, 21 do loadAt(game, oa, st, x, cy - 0x30 + r * 16) end
    end
  else
    local dx, dy = cx - (st.cx or cx), cy - (st.cy or cy)
    st.tog = (st.tog or 0) + 1
    if dx ~= 0 and st.tog % 2 == 1 then
      local x = cx + (dx < 0 and tb.prox[2] or tb.prox[1])
      for r = 0, 21 do loadAt(game, oa, st, x, cy - 0x30 + r * 16) end
    end
    if dy ~= 0 and st.tog % 2 == 0 then
      local y = cy + (dy < 0 and tb.prox[2] or tb.prox[1])
      for c = 0, 21 do loadAt(game, oa, st, cx - 0x30 + c * 16, y) end
    end
  end
  st.cx, st.cy = cx, cy
end

-- the screen box (Sprite_PrepOamCoordOrDoubleRet -> Sprite_KillSelf)
function OE.offscreen(game, oa, st)
  local cb = cbOf(game)
  local cx, cy = game.cam.x, game.cam.y
  for _, a in ipairs(oa.list) do
    if a.owe and not a.dead then
      local x, y = a.x - cx + 0x40, a.y - cy + 0x40
      local f4 = cb.flags4[a.type + 1] or 0
      if (x < 0 or x > 0x16F or ((y < 0 or y > 0x16F) and band(f4, 0x20) == 0))
         and band(cb.deflBits[a.type + 1] or 0, 0x80) == 0 then
        a.dead, a.gone = true, true
        if a.cell then st.loaded[a.cell] = nil end
        game.oweKilled = (game.oweKilled or 0) + 1
      end
    end
  end
end

-- ------------------------------------------------------------ the sprites
local function raven(self, a, lk)
  local game, tb = self.game, T(self.game)
  local fc = self.frame
  if a.ai == 0 then
    -- (Sprite_IsRightOfLink: the h-flip while Link is left of it)
    a.hflip = (lk.x - a.x < 0) and 0x40 or 0
    local x, y = lk.x - a.x, lk.y - a.y
    if (x + 0x50 + (x >= 0 and 1 or 0)) % 65536 < 0xA0 and (y + 0x58 + (y >= 0 and 1 or 0)) % 65536 < 0xA0 then
      a.ai, a.delay = 1, 24
    end
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.ai = 2
      a.delay = tb.ravenAscend[a.A + 1]
      a.vx, a.vy = project(a, lk, 32)
    end
    a.z = a.z + 1
    a.gfx = band(rshift(fc, 1), 1) + 1
  else
    if a.ai == 2 and a.delay == 0 and not (game.link.world == "dw" and a.A ~= 0) then a.ai = 3 end
    local flee = a.ai == 3
    if band(bxor(a.k, fc), 1) == 0 then
      local px, py = project(a, lk, flee and 48 or 32)
      if flee then px, py = -px, -py end
      if a.vx ~= px then a.vx = a.vx + ((a.vx - px < 0) and 1 or -1) end
      if a.vy ~= py then a.vy = a.vy + ((a.vy - py < 0) and 1 or -1) end
    end
    a.gfx = band(rshift(fc, 1), 1) + 1
    a.hflip = (a.vx < 0) and 0x40 or 0
  end
end

local function vulture(self, a, lk)
  local tb = T(self.game)
  local fc = self.frame
  if a.ai == 0 then
    a.sub2 = band(a.sub2 + 1, 0xFF)
    if a.sub2 == 160 then a.ai, a.delay = 1, 16 end
  else
    a.gfx = tb.vultureGfx[band(rshift(fc, 1), 3) + 1]
    if a.delay > 0 then a.z = a.z + 1 return end
    if band(bxor(a.k, fc), 1) ~= 0 then return end
    local px, py, xd, yd = project(a, lk, band(a.k, 15) + 24)
    a.vx, a.vy = -py, px
    if (xd + 0x28) % 256 < 0x50 and (yd + 0x28) % 256 < 0x50 then return end
    a.vy = a.vy + math.floor(py / 4)
    a.vx = a.vx + math.floor(px / 4)
  end
end

local function buzzblob(self, a, lk)
  local game, tb = self.game, T(self.game)
  a.gfx = tb.buzzGfx[band(rshift(a.sub2, 3), 3) + 1] + ((a.aux1 or 0) > 0 and 3 or 0)
  a.sub2 = band(a.sub2 + 1, 0xFF)
  if a.delay == 0 then
    local j = band(rnd(game), 7)
    a.vx, a.vy, a.delay = tb.buzzXv[j + 1], tb.buzzYv[j + 1], tb.buzzDelay[j + 1]
  end
  if (a.aux1 or 0) == 0 then moveXY(a) end
  tileCollision(game, a)
  -- Sprite_BounceOffWall
  if band(a.wall, 3) ~= 0 then a.vx = -a.vx end
  if band(a.wall, 12) ~= 0 then a.vy = -a.vy end
end

local function deadrock(self, a, lk)
  local game, tb = self.game, T(self.game)
  -- the picture (before the routine's checks)
  local j
  if (a.aux2 or 0) > 0 then j = (band(a.aux2, 4) ~= 0) and a.A or 8
  else j = (a.ai ~= 2) and a.A or 8 end
  a.gfx = tb.rockGfx[j + 1]
  a.hflip = tb.rockFlags[j + 1]
  -- contact (Sprite_CheckDamageToLink_same_layer; harmless when stone)
  if a.ai ~= 2 then contact(self, a, lk) end
  if a.recoil == 14 then a.ai, a.aux1, a.aux2 = 2, 255, 64 end
  if a.recoil then return end
  if a.ai == 0 then
    if a.delay == 0 then
      a.ai = 1
      a.delay = band(rnd(game), 31) + 32
      a.B = a.B + 1
      local d
      if a.B == 4 then a.B = 0; d = faceLink(a, lk) else d = band(rnd(game), 3) end
      a.D, a.vx, a.vy = d, tb.rockXv[d + 1], tb.rockYv[d + 1]
    end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai, a.delay = 0, 32
    else
      moveXY(a)
      if tileCollision(game, a) ~= 0 then
        local d = bxor(a.D, 1)
        a.D, a.vx, a.vy = d, tb.rockXv[d + 1], tb.rockYv[d + 1]
      end
      a.sub2 = band(a.sub2 + 1, 0xFF)
      a.A = a.D * 2 + band(rshift(a.sub2, 2), 1)
    end
  else
    -- petrified: the timer runs on every other frame (the extra frame
    -- puts it back); at 0x20 it starts to shake
    if band(self.frame, 1) == 0 then
      if a.aux1 == 0 then a.ai, a.delay = 0, 16
      elseif a.aux1 == 0x20 then a.aux2 = 0x40 end
    else
      a.aux1 = a.aux1 + 1
    end
  end
end

local function geldman(self, a, lk)
  local tb = T(self.game)
  a.untouchable = a.ai ~= 3
  if a.ai == 0 then
    if a.delay == 0 then a.x, a.y, a.fx, a.fy, a.ai = a.homeX, a.homeY, 0, 0, 1 end
  elseif a.ai == 1 then
    if band(bxor(a.k, self.frame), 7) == 0 and (lk.x - a.x + 0x30) % 65536 < 0x60
       and (lk.y - a.y + 0x30) % 65536 < 0x60 then
      a.ai, a.delay = 2, 31
    end
  elseif a.ai == 2 then
    if a.delay == 0 then
      a.ai, a.delay = 3, 96
      a.vx, a.vy = project(a, lk, 16)
    else
      a.gfx = tb.geldEmerge[rshift(a.delay, 2) + 1]
    end
  elseif a.ai == 3 then
    if a.delay == 0 then a.ai, a.delay = 4, 8
    else
      a.gfx = tb.geldPursue[band(rshift(a.delay, 2), 1) + 1]
      moveXY(a)
    end
  elseif a.ai == 4 then
    if a.delay == 0 then a.ai, a.delay = 0, 16
    else a.gfx = tb.geldSubmerge[rshift(a.delay, 1) + 1] end
  end
  a.untouchable = a.ai ~= 3
end

local function tektite(self, a, lk)
  local game, tb = self.game, T(self.game)
  if (a.aux1 or 0) > 0 then a.gfx = 0 end
  moveZ(a); moveXY(a)
  -- Sprite_BounceFromTileCollision
  local w = tileCollision(game, a)
  if band(w, 3) ~= 0 then a.vx = -a.vx; a.G = a.G + 1 end
  if band(w, 12) ~= 0 then a.vy = -a.vy; a.G = a.G + 1 end
  a.vz = a.vz - 1
  if a.z < 0 then a.z, a.vz, a.fz = 0, 0, 0 end
  if a.ai == 0 then
    local j, px, py = faceLink(a, lk)
    if (px + 40) % 256 < 80 and (py + 40) % 256 < 80 and a.z == 0
       and j ~= tb.tekDir[rshift(game.link.facing or 2, 1) + 1] then
      local vx, vy = project(a, lk, 32)
      a.vx, a.vy, a.vz, a.ai = -vx, -vy, 16, 1
      return
    end
    if a.delay == 0 then
      a.ai = a.ai + 1
      a.B = a.B + 1
      local d
      if a.B == 4 then
        a.B = 0
        a.ai = a.ai + 1
        a.delay = band(rnd(game), 63) + 48
        a.vz = 12
        local bNeg = below(a, lk)
        local rNeg = rightOf(a, lk)
        d = (bNeg and 2 or 0) + (rNeg and 1 or 0)
      else
        a.vz = band(rnd(game), 7) + 24
        d = band(rnd(game), 3)
      end
      a.vx, a.vy = tb.tekXv[d + 1], tb.tekYv[d + 1]
    else
      a.gfx = band(rshift(a.delay, 4), 1)
    end
  elseif a.ai == 1 then
    if a.z == 0 then
      a.ai, a.delay, a.vx, a.vy = 0, band(rnd(game), 63) + 72, 0, 0
    else a.gfx = 2 end
  else
    if a.delay == 0 then
      a.ai, a.delay, a.vx, a.vy = 0, band(rnd(game), 63) + 72, 0, 0
      return
    end
    if a.z == 0 then a.vz, a.z, a.aux1 = 12, a.z + 1, 8 end
    a.gfx = 2
  end
end

local function landmine(self, a, lk)
  local tb = T(self.game)
  if a.boom then
    -- the sprite bomb (Sprite_4A_BombGuard, C 2): it hurts Link (hit box 9)
    contact(self, { type = 0x4A, x = a.x, y = a.y, k = a.k }, lk, 9)
    if a.aux1 == 0 then a.dead, a.gone = true, true end
    return
  end
  if a.delay == 0 then
    a.oam = 4
    if contact(self, a, lk) then a.delay = 8 end
    return
  end
  if a.delay ~= 1 then a.oam = tb.mineFlags[band(rshift(a.delay, 1), 3) + 1] return end
  -- Sprite_SpawnBomb -> state 6 (C 2, 31 frames)
  a.boom, a.aux1 = true, 31
  self.game.mines = (self.game.mines or 0) + 1
end

-- one frame (before the shared code's recoil / timers / contact)
function OE.update(self, a, lk)
  if not T(self.game) then return end
  timers(a)
  local t = a.type
  if t == 0x27 then return deadrock(self, a, lk) end
  if a.recoil then return end   -- Sprite_ReturnIfRecoiling (the shared code moves it)
  if t == 0x00 then moveXY(a); raven(self, a, lk)
  elseif t == 0x01 then moveXY(a); vulture(self, a, lk)
  elseif t == 0x0D then buzzblob(self, a, lk)
  elseif t == 0x4C then geldman(self, a, lk)
  elseif t == 0xC9 then tektite(self, a, lk)
  elseif t == 0xD4 then landmine(self, a, lk)
  end
end

-- the sword on the sprites with their own rule (Sprite_CheckDamageFromLink):
-- returns true when it handled a hit
function OE.sword(self, a, x, y, w, h, how)
  local game = self.game
  local cb = cbOf(game)
  -- the swing outdoors passes only its recoil speed (Escape.lua); arrows,
  -- bombs and thrown things name their class
  local sword = how and (how.sword or (how.vel and not how.cls and not how.arrow and not how.bomb))
  if a.dead or not sword then return false end
  local hx, hy, hw, hh = A().hitbox(cb, a)
  if not A().overlapCart(x, y, w, h, hx, hy - (a.z or 0), hw, hh) then return false end
  if a.type == 0x27 then
    if (a.inv or 0) > 0 then return false end
    if a.ai == 2 then
      -- defl bit 4 while stone: the tink ("getting_out")
      self:tinkLink(a)
      return true
    end
    -- Sprite_AttemptZapDamage: recoil away (0x50 / 0x40), damage 0 ->
    -- sprite_flags & 4: sprite_F 15, no hit timer
    local px, py = A().project(a.x, a.y, game.link.x, game.link.y, how.vel or 0x50)
    a.rvx, a.rvy, a.subx, a.suby, a.recoil = -px, -py, 0, 0, 15
    game.swde = 16
    return true
  elseif a.type == 0x0D then
    -- the fighter sword zaps Link (link_sword_type < 4)
    if ((game.progress.swordLevel or 1) < 4) then
      if (game.blink or 0) == 0 then
        a.aux1 = 64
        game.zapT = 24
        local cls = band(cb.bump[a.type + 1] or 0, 0x0F)
        game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
        game.zaps = (game.zaps or 0) + 1
      end
      return true
    end
  end
  return false
end

-- ------------------------------------------------------------ drawing
local function oamFlags(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
function OE.draw(spr, a, x, y, frame)
  local tb = spr.data.t and spr.data.t.owe
  if not tb then return false end
  local t = a.type
  local f = a.oam or oamFlags(spr, t)
  local z = a.z or 0
  if t == 0x00 then
    spr:single(a, x, y, a.gfx or 0, a.hflip or 0)
  elseif t == 0x01 then
    spr:drawShadow(x, y + z, t)
    spr:drawDmd(a, tb.vultureDmd, (a.gfx or 0) * 2, 2, x, y, f)
  elseif t == 0x0D then
    local g = a.gfx or 0
    for i = 2, 0, -1 do
      local j = g * 3 + i
      local ch = tb.buzzChar[j + 1] or 0
      if ch ~= 0 then
        spr:oam(x + tb.buzzDrawX[i + 1], y + tb.buzzDrawY[i + 1], band(ch, 0xFF),
                bor(tb.buzzFlags[j + 1] or 0, f, rshift(ch, 8)), tb.buzzExt[i + 1])
      end
    end
  elseif t == 0x27 then
    spr:single(a, x, y, a.gfx or 0, a.hflip or 0)
  elseif t == 0x4C then
    if (a.ai or 0) < 2 then return true end
    local g = a.gfx or 0
    for i = 2, 0, -1 do
      local j = g * 3 + i
      spr:oam(x + tb.geldX[j + 1], y + tb.geldY[j + 1], tb.geldChar[j + 1], bor(tb.geldFlags[j + 1], f), tb.geldBig[j + 1])
    end
  elseif t == 0xC9 then
    spr:drawShadow(x, y + z, t)
    spr:drawDmd(a, tb.tekDmd, (a.gfx or 0) * 2, 2, x, y, f)
  elseif t == 0xD4 then
    if a.boom then
      local base = band(rshift(a.aux1 or 0, 1), 0x0C)
      for i = 3, 0, -1 do
        local j = base + i
        spr:oam(x + tb.bombX[j + 1], y + tb.bombY[j + 1], tb.bombChar[j + 1], bor(tb.bombFlags[j + 1], 8), 2)
      end
    else
      spr:drawDmd(a, tb.mineDmd, 0, 2, x, y, f)
    end
  else
    return false
  end
  return true
end

-- ------------------------------------------------------------ install
function OE.install(G)
  local Actors = require("src.zelda.alttp.Actors")
  local Palace = require("src.zelda.alttp.Palace")
  for t in pairs(OE.FIGHTS) do Palace.FIGHTS[t] = true end
  -- the per-frame part before the shared actor loop (overworld lists only)
  local up0 = Actors.update
  function Actors:update()
    if self.room == -1 and self.game and self.game.state == "play" then
      local lk = self.game.link
      for _, a in ipairs(self.list) do
        if a.owe and not a.dead then OE.update(self, a, lk) end
      end
    end
    return up0(self)
  end
  local sh0 = Actors.swordHit
  function Actors:swordHit(x, y, w, h, how)
    if self.room ~= -1 then return sh0(self, x, y, w, h, how) end
    local n, saved = 0, {}
    for _, a in ipairs(self.list) do
      if a.owe and not a.dead and (a.type == 0x27 or a.type == 0x0D) then
        if OE.sword(self, a, x, y, w, h, how) then n = n + 1 end
        if not a.untouchable then a.untouchable = true; saved[#saved + 1] = a end
      end
    end
    n = n + sh0(self, x, y, w, h, how)
    for _, a in ipairs(saved) do a.untouchable = nil end
    return n
  end
  -- drawing
  local S = require("src.zelda.alttp.Sprites")
  local da0 = S.drawActor
  function S:drawActor(a, x, y, frame, room)
    if a.owe then return OE.draw(self, a, x, y, frame) end
    return da0(self, a, x, y, frame, room)
  end
  -- loading / the screen box, each overworld frame
  local upd0 = G.updateOwActors
  function G:updateOwActors()
    -- the people first (Npc.lua makes the area's list), then this module's loading
    local r = upd0(self)
    if self.state == "play" and self.area and T(self) and self.data.t.npc and not self.scroll then
      local key = self.area.parent .. ":" .. self.link.world
      local st = self.oweState
      local fresh = not st or st.key ~= key
      if fresh then st = OE.loadArea(self) end
      if st then
        local oa = self:owActorList()
        -- (an emptied list is made again by Npc.lua: keep the grid's memory)
        OE.proximity(self, oa, st, fresh)
        OE.offscreen(self, oa, st)
      end
    end
    return r
  end
  -- LinkState_Zapped: held 8 steps of 3 frames
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if (self.zapT or 0) > 0 then
      self.zapT = self.zapT - 1
      self.link.moving = false
      return true
    end
    return owFrame(self, inp)
  end
end

-- r27a: the shared sprite helpers for OwEnemies27.lua (more outdoor types)
OE.H = { moveXY = moveXY, moveZ = moveZ, project = project, faceLink = faceLink, below = below,
         rightOf = rightOf, solidAt = solidAt, tileCollision = tileCollision, contact = contact,
         timers = timers, rnd = rnd, wrap8 = wrap8, alloc = alloc }

return OE
