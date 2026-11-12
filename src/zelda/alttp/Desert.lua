-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DESERT OF MYSTERY (round 23): the Desert Palace's door.
--
-- Area 0x30's sprite list (Npc.lua's per-phase lists, GBA 0x227E70) holds
-- three desert statues (0x57) around the palace's stairs and the stone
-- plaque (0xB3) below them. The cartridge (SNES names, zelda3):
--
--   Sprite_B3_PedestalPlaque (area 48 branch): Link facing up, touching
--   the plaque (Sprite_CheckDamageToLink_same_layer), with the Book of
--   Mudora on the item button and the item button newly pressed -> message
--   0xBD and kPlayerState_OpeningDesertPalace (button_b_frames 1:
--   LinkState_ReadingDesertTablet -> Link_PerformDesertPrayer once the text
--   is gone); the action button alone -> message 0xBC ("you can't read").
--   SpritePrep_PedestalPlaque: x + 7 in area 48.
--
--   Module0E_05_DesertPrayer: the palette filter darkens (31 steps), the
--   iris (DesertPrayer_InitializeIrisHDMA: radius spotlight_var1 = 0x26
--   around Link, x + 8 / y + 12) closes on Link while the palette lightens
--   back (30 steps); Link prays (kPrayingScene_Delays 22, 22, 22, 64) until
--   a button is pressed, then the radius halves and grows 8 a frame; at
--   0xC0 the module ends and byte_7E02F0 ^= 1.
--
--   Sprite_57_DesertStatue: SpritePrep_DesertStatue (x + 8, y + 8; its
--   direction from its x's low byte: < 0x30 left, < 0xE0 up, else down);
--   waits for byte_7E02F0, then 128 frames shaking (x + ((delay >> 1) & 1)),
--   then moves 16 (1 px a frame) its way (kDesertBarrier_Xv / Yv), turning
--   on a wall (kDesertBarrier_NextD 3, 2, 0, 1); Link is held
--   (flag_is_link_immobilized) until its counter (one every other frame)
--   reaches 130. r25: NOT a barrier: the GBA's Sprite_57 (0x080EE1D0)
--   calls only Sprite_CheckDamageToLink_same_layer (0x080C500C) ->
--   Sprite_NullifyHookshotDrag / Sprite_RepelDash, as the SNES one (r23's
--   32 x 32 box trapped Link on the palace stairs once the area reloaded
--   the statues at their list spots). Drawn with
--   kDesertBarrier_Dmd (GBA copy at 0x178A20, Npc.extract's dmd tables).
--   byte_7E02F0 is cleared by Sprite_ResetAll, so the statues stand again
--   whenever the area is loaded (no saved flag on the SNES either).
--
-- OURS: the palette filter is drawn as a dark veil (not the per-channel bit
-- filter); the iris is a filled circle (not the HDMA shape table); Link's
-- praying poses are not drawn (he stands facing up); the statue's wall test
-- uses the overworld attribute under its probe point with the indoor
-- solidity table; no sound.

local bit = require("bit")
local band = bit.band

local D = {}

D.AREA = 0x30
D.STATUE, D.PLAQUE = 0x57, 0xB3
D.MSG_NOBOOK, D.MSG_BOOK = 0xBC, 0xBD
D.BOOK = 0x1D

-- ------------------------------------------------------------ import
-- the GBA's copies (file offsets, RomMap.desert), found by value:
-- kDesertBarrier_Xv / Yv / NextD 0x178A14 (the Dmd follows at 0x178A20),
-- kPrayingScene_Delays 0x14DAA6; Sprite_71_Leever's tables 0x175340..
-- (Emerge / AttackSpd / AttackGfx / Submerge, then Leever_Draw's Num, X,
-- Y (s16), Char (GBA chars), Flags, Big); Beamos_Draw's Y (s16) / Char and
-- SpriteDraw_Beamos_Eyeball's X / Y / Char / Flags 0x179B90..
local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
function D.extract(rom, R, check)
  local M = R.desert
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = {
    xv = s8(u8(M.barrierXv, 4)), yv = s8(u8(M.barrierYv, 4)), nextD = u8(M.barrierNext, 4),
    pray = u8(M.prayDelays, 5),
    lvEmerge = u8(M.leever, 16), lvSpd = u8(M.leever + 16, 2), lvAtk = u8(M.leever + 18, 4),
    lvSub = u8(M.leever + 22, 16), lvNum = u8(M.leever + 38, 14),
    lvX = s16(rom:bytesU16(M.leeverX, 56)), lvY = s16(rom:bytesU16(M.leeverX + 112, 56)),
    lvChar = u8(M.leeverX + 224, 56), lvFlags = u8(M.leeverX + 280, 56), lvBig = u8(M.leeverX + 336, 56),
    bmY = s16(rom:bytesU16(M.beamos, 2)), bmChar = u8(M.beamos + 4, 2),
    eyeX = s8(u8(M.beamos + 6, 32)), eyeY = s8(u8(M.beamos + 38, 32)),
    eyeChar = u8(M.beamos + 70, 32), eyeFlags = u8(M.beamos + 102, 32),
  }
  -- structural checks (shapes): opposite speeds, the turn table a
  -- permutation, the leever's draw counts, the eyeball's flip halves
  check(t.xv[1] == -t.xv[2] and t.yv[3] == -t.yv[4] and t.nextD[1] + t.nextD[2] + t.nextD[3] + t.nextD[4] == 6,
        "desert statue tables")
  check(t.lvNum[1] == 1 and t.lvBig[56] == 0 and t.lvEmerge[16] == 0 and t.lvAtk[2] == t.lvAtk[1] + 1, "leever tables")
  check(t.bmY[1] == -16 and t.bmY[2] == 0 and t.eyeFlags[1] == 0 and t.eyeFlags[9] == 0x40, "beamos tables")
  return t
end
local function T(game) return game.data.t and game.data.t.desert end
D.tabs = T

local function hasItem(game, id)
  for _, v in ipairs(game.progress.items or {}) do if v == id then return true end end
  return false
end
D.hasItem = hasItem

-- ------------------------------------------------------------ spawning
-- from Npc.spawnArea (the area's list, its corner)
function D.spawnArea(game, oa, list, bx, by)
  if not (game.area and game.area.parent == D.AREA and game.link.world == "lw") then return end
  game.desertFlag = 0   -- byte_7E02F0 (Sprite_ResetAll)
  for _, e in ipairs(list) do
    local t = e[3]
    if t == D.STATUE then
      local x, y = bx + e[2] * 16 + 8, by + e[1] * 16 + 8
      local lo = x % 256
      oa.list[#oa.list + 1] = { type = t, desert = true, x = x, y = y, t = 0, hp = 255, lower = false,
                                state = "idle", ai = 0, D = (lo < 0x30) and 1 or ((lo < 0xE0) and 3 or 2),
                                delay = 0, sub2 = 0, G = 0 }   -- r25: no barrier box (see below)
    elseif t == D.PLAQUE then
      oa.list[#oa.list + 1] = { type = t, desert = true, x = bx + e[2] * 16 + 7, y = by + e[1] * 16,
                                t = 0, hp = 255, lower = false, state = "idle", plaque = true }
    end
  end
end

-- ------------------------------------------------------------ sprites
local function overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function touching(actors, a, lk)
  local A = require("src.zelda.alttp.Actors")
  local cb = actors.game.data.roomIdx and actors.game.data.roomIdx.combat
  local hx, hy, hw, hh = a.x, a.y, 16, 16
  if cb then hx, hy, hw, hh = A.hitbox(cb, a) end
  local lx, ly, lw, lh = A.linkBox(lk)
  return A.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh)
end
D.touching = touching

-- Sprite_CheckTileCollision for the statue outdoors: the probe point of
-- its tile hit box (kSpriteInit_Flags & 0xF0 -> point base, + 0 up, 1 down,
-- 2 left, 3 right; kSprite_Func5_X / Y) on the overworld's attributes,
-- solid by kSprite_TileSolidity (the same rule Palace.lua uses indoors)
local function wallAt(actors, a, vx, vy)
  local game = actors.game
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  local pt = game.data.roomIdx and game.data.roomIdx.palace
  if not (cb and pt) then return false end
  local base = bit.rshift(band(pt.sprFlags[a.type + 1] or 0, 0xF0), 2)
  local j = base + ((vy < 0 and 0) or (vy > 0 and 1) or (vx < 0 and 2) or 3)
  local x = a.x + (cb.sprPointX[j + 1] or 8)
  local y = a.y + (cb.sprPointY[j + 1] or 8)
  local at = game.ow:attrAt(game.link.world, x, y) or 0
  return (cb.sprTileSolid[at + 1] or 0) ~= 0
end

function D.update(actors, a, lk)
  local game = actors.game
  if a.plaque then return D.plaque(actors, a, lk) end
  if a.type ~= D.STATUE then return end
  if a.ai >= 128 then return end
  if a.ai == 0 then
    if (game.desertFlag or 0) == 0 then return end
    a.ai, a.delay = game.desertFlag, 128
    game.statuesMoving = (game.statuesMoving or 0) + 1
    return
  end
  if a.delay > 0 then a.delay = a.delay - 1 return end
  local tb = T(game)
  if not tb then return end
  local j = a.D
  local vx, vy = tb.xv[j + 1], tb.yv[j + 1]
  -- Sprite_MoveXY (1/16 px a frame)
  a.sx, a.sy = (a.sx or 0) + vx, (a.sy or 0) + vy
  local mx = (a.sx >= 0) and math.floor(a.sx / 16) or -math.floor(-a.sx / 16)
  local my = (a.sy >= 0) and math.floor(a.sy / 16) or -math.floor(-a.sy / 16)
  a.sx, a.sy = a.sx - mx * 16, a.sy - my * 16
  a.x, a.y = a.x + mx, a.y + my
  local hit = false
  if wallAt(actors, a, vx, vy) then
    -- the push back out of the wall (1 px), then kDesertBarrier_NextD
    hit = true
    a.x, a.y = a.x - (vx > 0 and 1 or (vx < 0 and -1 or 0)), a.y - (vy > 0 and 1 or (vy < 0 and -1 or 0))
  end
  if hit then a.D = tb.nextD[a.D + 1] end
  a.sub2 = (a.sub2 + 1) % 256
  if band(a.sub2, 1) == 0 then
    a.G = a.G + 1
    if a.G == 130 then
      a.ai = 128
      game.statuesMoving = math.max(0, (game.statuesMoving or 1) - 1)
    end
  end
end

-- Sprite_B3_PedestalPlaque (area 48)
function D.plaque(actors, a, lk)
  local game = actors.game
  if game.textBox or game.prayer or game.tablet then return end
  local inp = game.owInp
  if not inp then return end
  if lk.facing ~= 0 or not touching(actors, a, lk) then return end
  local Items = require("src.zelda.alttp.Items")
  local book = false
  if inp.y and game.yItem then
    local item = game:yItem()
    book = item == "book"
  end
  if book then
    game.tablet = true
    game.desertReads = (game.desertReads or 0) + 1
    game:showMessage(D.MSG_BOOK)
    game.onTextDone = function(g) g.tablet = nil; D.startPrayer(g) end
    inp.y = false
  elseif inp.a then
    game:showMessage(D.MSG_NOBOOK)
    inp.a = false
  end
  local _ = Items
end

-- ------------------------------------------------------------ the prayer
function D.startPrayer(game)
  local tb = T(game)
  game.prayer = { sub = 0, t = 0, filter = 0, radius = 0x26, open = false, step = 0, delay = tb and tb.pray[1] or 22 }
  game.prayers = (game.prayers or 0) + 1
  if game.music and game.music.stop then pcall(game.music.stop, game.music) end
end

function D.prayerFrame(game, pressedAny)
  local p = game.prayer
  p.t = p.t + 1
  if p.sub == 0 then
    p.sub, p.filter = 1, 0
  elseif p.sub == 1 then
    -- ApplyPaletteFilter_bounce: darkening to mosaic_target_level 31
    p.filter = p.filter + 1
    if p.filter >= 31 then p.sub = 2 end
  elseif p.sub == 2 then
    p.radius, p.sub, p.filter = 0x26, 3, 30
  elseif p.sub == 3 or p.sub == 4 then
    if p.sub == 3 then
      p.filter = p.filter - 1
      if p.filter <= 0 then p.filter, p.sub = 0, 4 end
    end
    if p.sub == 4 then
      if not p.open and pressedAny then p.open = true; p.radius = math.floor(p.radius / 2) end
      if p.open then
        p.radius = p.radius + 8
        if p.radius >= 0xC0 then
          game.prayer = nil
          game.desertFlag = bit.bxor(game.desertFlag or 0, 1)
          game.desertOpened = (game.desertOpened or 0) + 1
          if game.music and game.music.playForScreen and game.area then
            pcall(game.music.playForScreen, game.music, game.area.parent, game.link.world)
          end
          return
        end
      else
        p.delay = p.delay - 1
        if p.delay < 0 then
          local i = p.step + 1
          if i ~= 4 then p.step = i end
          local tb = T(game)
          p.delay = tb and tb.pray[i + 1] or 1
        end
      end
    end
  end
end

-- the veil (palette filter) and the iris over the drawn frame
function D.drawPrayer(game, lx, ly, w, h)
  local p = game.prayer
  if not p then return end
  local veil = 0
  if p.sub == 1 then veil = p.filter / 31 * 0.5 elseif p.sub == 3 then veil = p.filter / 30 * 0.5 end
  if p.sub <= 1 then
    love.graphics.setColor(0, 0, 0, veil)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  love.graphics.setColor(0, 0, 0, 1)
  local r = p.radius
  for y = 0, h - 1 do
    local dy = y + 0.5 - ly
    if math.abs(dy) >= r then
      love.graphics.rectangle("fill", 0, y, w, 1)
    else
      local hw = math.sqrt(r * r - dy * dy)
      local x0, x1 = math.floor(lx - hw), math.ceil(lx + hw)
      if x0 > 0 then love.graphics.rectangle("fill", 0, y, x0, 1) end
      if x1 < w then love.graphics.rectangle("fill", x1, y, w - x1, 1) end
    end
  end
  if veil > 0 then
    love.graphics.setColor(0, 0, 0, veil)
    love.graphics.circle("fill", lx, ly, r)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------ drawing
function D.draw(spr, a, x, y, frame)
  if a.type ~= D.STATUE then return true end   -- the plaque is in the BG
  local t = spr.data.t and spr.data.t.npc
  local list = t and t.dmd and t.dmd.statue
  if not list then return false end
  local dx = (a.delay or 0) > 0 and band(math.floor(a.delay / 2), 1) or 0
  local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
  spr:drawDmd(a, list, 0, 4, x + dx, y, f)
  return true
end

-- ------------------------------------------------------------ install
function D.install(G)
  local update0 = G.update
  function G:update(dt)
    if self.prayer and self.state == "play" and not self.textBox then
      self.frame = self.frame + 1
      if self.music and self.music.update then self.music:update() end
      local inp = self.input
      local function pr(b) return inp and inp.wasPressed(b) end
      local any = pr("a")
      any = pr("b") or any
      any = pr("r") or any
      D.prayerFrame(self, any)
      return
    end
    return update0(self, dt)
  end
  local draw0 = G.draw
  function G:draw()
    draw0(self)
    if self.prayer and self.state == "play" and not self.headless then
      local cam = self.cam
      local vx, vy = cam.x, cam.y
      if self.viewOrigin then vx, vy = self:viewOrigin(cam.x, cam.y) end
      local cv = love.graphics.getCanvas()
      local w, h = 240, 160
      if cv then w, h = cv:getDimensions() end
      D.drawPrayer(self, self.link.x + 8 - vx, self.link.y + 12 - vy, w, h)
    end
  end
  -- flag_is_link_immobilized while a statue moves; LinkItem_Book
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if (self.statuesMoving or 0) > 0 then return true end
    return owFrame(self, inp)
  end
end

-- ------------------------------------------------------------ the Desert Palace's sprites
-- Sprite_71_Leever and Sprite_61_Beamos (zelda3 0x86CBA2 / 0x858F54), run
-- by Palace.update with its helpers (Palace._h: Sprite_MoveXY, the tile
-- collision, the hit test, Sprite_ApplySpeedTowardsLink).
--
-- Leever: under the sand it creeps towards Link at 16 (no hits either
-- way); it surfaces (127 frames, kLeever_EmergeGfx by delay >> 3), attacks
-- for 160-223 frames (speed 12 / 8 towards Link every 8th frame, the
-- only state where it hurts and can be hurt), stops at a wall, sinks
-- (127 frames) and stays under 64-95 frames. Not drawn under the sand.
-- Beamos: a statue that sends a probe every 4th frame round its 64
-- directions (Sprite_SpawnProbeAlways; Guard.lua's probe rule); a probe
-- reaching Link starts 16 frames of flashing, the laser at 15 (four
-- Sprite_MoveXY a frame at 0x20 towards Link after a 12-frame wait, a
-- 32-point trail, damage class 4; stops 16 frames on Link or a wall),
-- then 80 frames of rest. At most four lasers live (sprite_limit_instance).
-- OURS: the leever's palette mask for the sand chars is taken as GBA chars
-- >= 0x48; the laser's char 0x3C is the SNES 0x5C by the Beamos sheet's
-- row shift (0x4X -> 0x1X, 0x5X -> 0x3X); its hit sparkle is not drawn; no sound.
D.LEEVER, D.BEAMOS = 0x71, 0x61

function D.palacePrep(self, a)
  if a.type == D.LEEVER then
    a.untouchable = true
    a.A = 0
  elseif a.type == D.BEAMOS then
    a.probes, a.lasers = {}, {}
  end
end

local function rnd(self) return require("src.zelda.alttp.Drops").rng(self.game:dropRng()) end

local function leever(self, a, lk, h)
  local tb = T(self.game)
  if not tb then return end
  if a.ai == 0 then
    if a.delay == 0 then a.ai, a.delay = 1, 127
    else
      a.vx, a.vy = h.towardsLink(a, lk, 16)
      h.moveXY(a)
      h.tileCollision(self, a)
    end
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.ai, a.delay = 2, band(rnd(self), 63) + 160
      a.vx, a.vy = 0, 0
    else
      a.gfx = tb.lvEmerge[bit.rshift(a.delay, 3) + 1] or 0
    end
  elseif a.ai == 2 then
    local stop = a.delay == 0
    if not stop then
      if band(a.sub2, 7) == 0 then a.vx, a.vy = h.towardsLink(a, lk, tb.lvSpd[(a.A or 0) + 1] or 12) end
      h.moveXY(a)
      if h.tileCollision(self, a) ~= 0 then stop = true end
      a.sub2 = band(a.sub2 + 1, 0xFF)
      a.gfx = tb.lvAtk[band(bit.rshift(a.sub2, 2), 3) + 1] or 9
    end
    if stop then a.ai, a.delay = 3, 127 end
  elseif a.ai == 3 then
    if a.delay == 0 then
      a.ai, a.delay = 0, band(rnd(self), 31) + 64
    else
      a.gfx = tb.lvSub[bit.bxor(bit.rshift(a.delay, 3), 15) + 1] or 0
    end
  end
  a.untouchable = a.ai ~= 2
end

local function camOf(self, lk)
  if self.inside and self.inside.camera then return self.inside:camera(lk.x, lk.y, 240, 160) end
  return 0, 0
end

local function cellAttr(self, a, x, y)
  local t = (a.lower and self.inside.attrsLo) or self.inside.attrs
  if not t or x < 0 or y < 0 or x >= 512 or y >= 512 then return nil end
  return t[math.floor(y / 8) * 64 + math.floor(x / 8)] or 0
end

local function beamos(self, a, lk, h)
  local game = self.game
  local cb = game.data.roomIdx.combat
  -- contact (Sprite_CheckDamageToLink: the type's bump damage)
  if band(bit.bxor(a.k or 0, self.frame), 3) == 0 and h.touchLink(self, a, lk) then
    local cls = band(cb.bump[a.type + 1] or 0, 0x0F)
    game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
  end
  local camx, camy = camOf(self, lk)
  -- the probes (Probe: x / y speed a frame; a solid cell other than 9 or
  -- off the screen ends one; within 16 px of Link on its level: state 3)
  local Guard = require("src.zelda.alttp.Guard")
  local keep = {}
  for _, p in ipairs(a.probes) do
    p.x, p.y = p.x + p.vx, p.y + p.vy
    local b = cellAttr(self, a, p.x, p.y)
    local alive = true
    if b == nil or (Guard.simpleSolid(cb, b) and b ~= 9) then alive = false
    else
      local dx, dy = p.x - lk.x, p.y - lk.y
      if dx >= 0 and dx < 16 and dy >= 0 and dy < 16 and (a.lower or false) == (self.inside.lower or false) then
        if a.ai ~= 3 then a.ai, a.delay, a.sub2 = 3, 16, 0 end
        alive = false
      elseif p.x - camx < 0 or p.x - camx >= 256 or p.y - camy < 0 or p.y - camy >= 256 then alive = false end
    end
    if alive then keep[#keep + 1] = p end
  end
  a.probes = keep
  if a.ai == 0 then
    if band(bit.bxor(a.k or 0, self.frame), 3) == 0 then
      local j = band(a.D, 63)
      a.probes[#a.probes + 1] = { x = a.x + 8, y = a.y + 4, vx = cb.probeXvel[j + 1] or 0, vy = cb.probeYvel[j + 1] or 0 }
      a.D = a.D + 1
    end
    a.D = band(a.D, 63)
  elseif a.ai == 3 then
    if a.delay == 0 then
      a.ai, a.delay, a.flash = 4, 80, 0
    else
      if a.delay == 15 then D.fireLaser(self, a, lk) end
      a.flash = bit.bxor(a.flash or 0, band(bit.rshift(a.delay, 1), 0xE))
    end
  else
    if a.delay == 0 then a.ai = 0 end
  end
  D.lasers(self, a, lk)
end

function D.fireLaser(self, a, lk)
  local game = self.game
  local tb = T(game)
  local live = 0
  for _, b in ipairs(self.list) do for _, l in ipairs(b.lasers or {}) do live = live + 1 end end
  if live >= 4 then return end
  local i = bit.rshift(band(a.D, 63), 1)
  local ex, ey = (tb.eyeX[i + 1] or 0) - 3, (tb.eyeY[i + 1] or 0) - 18
  local l = { x = a.x + ex, y = a.y + ey, wait = 12, delay = 0, trail = {}, n = 0 }
  local A = require("src.zelda.alttp.Actors")
  l.vx, l.vy = A.project(l.x, l.y, lk.x, lk.y + 8, 0x20)
  for k = 1, 32 do l.trail[k] = { l.x, l.y } end
  a.lasers[#a.lasers + 1] = l
  game.beamosLasers = (game.beamosLasers or 0) + 1
end

function D.lasers(self, a, lk)
  local game = self.game
  local cb = game.data.roomIdx.combat
  local A = require("src.zelda.alttp.Actors")
  local keep = {}
  for _, l in ipairs(a.lasers) do
    if l.wait > 0 then l.wait = l.wait - 1; keep[#keep + 1] = l
    elseif l.delay > 0 then
      l.delay = l.delay - 1
      if l.delay > 1 then keep[#keep + 1] = l end
    else
      for _ = 1, 4 do
        l.n = l.n % 32 + 1
        l.trail[l.n] = { l.x, l.y }
        l.sx, l.sy = (l.sx or 0) + l.vx, (l.sy or 0) + l.vy
        local mx = (l.sx >= 0) and math.floor(l.sx / 16) or -math.floor(-l.sx / 16)
        local my = (l.sy >= 0) and math.floor(l.sy / 16) or -math.floor(-l.sy / 16)
        l.sx, l.sy = l.sx - mx * 16, l.sy - my * 16
        l.x, l.y = l.x + mx, l.y + my
      end
      -- Sprite_CheckDamageToLink_same_layer (flags4 0x54: hit box 0x14,
      -- bump damage 4) or Sprite_CheckTileCollision
      local i = 0x14 + 1
      local xo = (cb.hitXLo[i] or 0) % 256 + (cb.hitXHi[i] or 0) * 256
      local yo = (cb.hitYLo[i] or 0) % 256 + (cb.hitYHi[i] or 0) * 256
      if xo >= 0x8000 then xo = xo - 0x10000 end
      if yo >= 0x8000 then yo = yo - 0x10000 end
      local lx, ly, lw, lh = A.linkBox(lk)
      local hitLink = A.overlapCart(lx, ly, lw, lh, l.x + xo, l.y + yo, cb.hitXSize[i] or 8, cb.hitYSize[i] or 8)
      local b = cellAttr(self, a, l.x + 4, l.y + 4)
      local wall = b == nil or (cb.sprTileSolid[b + 1] or 0) ~= 0
      if hitLink then
        game:hurtLink(cb.playerDamage[3 * 4 + 1] or 4, l.x + 4, l.y + 4)
        game.laserHits = (game.laserHits or 0) + 1
      end
      if hitLink or wall then l.delay, l.vx, l.vy = 16, 0, 0 end
      keep[#keep + 1] = l
    end
  end
  a.lasers = keep
end

function D.palaceUpdate(self, a, lk, h)
  if a.type == D.LEEVER then
    if a.recoil and self:recoilStep(a) then return end
    return leever(self, a, lk, h)
  elseif a.type == D.BEAMOS then
    return beamos(self, a, lk, h)
  end
end

function D.drawPalace(spr, a, x, y, frame, game)
  local tb = game and T(game) or (spr.data.t and spr.data.t.desert)
  if not tb then return false end
  local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
  if a.type == D.LEEVER then
    if (a.ai or 0) == 0 then return true end
    local d = a.gfx or 0
    for i = tb.lvNum[d + 1] or 0, 0, -1 do
      local j = d * 4 + i + 1
      local ch = tb.lvChar[j] or 0
      local ff = f
      if ch >= 0x48 then ff = band(ff, 0xF0) end
      spr:oam(x + tb.lvX[j], y + tb.lvY[j], ch, bit.bor(tb.lvFlags[j] or 0, ff), tb.lvBig[j] or 0)
    end
    return true
  elseif a.type == D.BEAMOS then
    local ff = bit.bxor(f, a.flash or 0)
    local i = bit.rshift(band(a.D or 0, 63), 1)
    local function eye()
      spr:oam(x + (tb.eyeX[i + 1] or 0) - 3, y + (tb.eyeY[i + 1] or 0) - 18, tb.eyeChar[i + 1] or 0,
              bit.bor(band(ff, 0x31), 0xA, tb.eyeFlags[i + 1] or 0), 0)
    end
    if (a.D or 0) >= 0x20 then eye() end
    for k = 2, 1, -1 do spr:oam(x, y + tb.bmY[k], tb.bmChar[k], ff, 2) end
    if (a.D or 0) < 0x20 then eye() end
    -- the lasers' trails (char 0x3C, 8 x 8)
    local ox, oy = x - a.x, y - a.y
    for _, l in ipairs(a.lasers or {}) do
      if l.wait == 0 then
        for _, p in ipairs(l.trail) do spr:oam(p[1] + ox, p[2] + oy, 0x3C, bit.bor(band(f, 0x30), 6), 0) end
      end
    end
    return true
  end
  return false
end

return D
