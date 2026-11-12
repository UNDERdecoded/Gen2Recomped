-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- TURTLE ROCK (round 26, team B): Trinexx, the SNES routines the GBA keeps
-- (zelda3 names), run by Palace.lua through Dungeons26.lua's registry.
-- Tables are the GBA's (file offsets in OFF, found by value with
-- r26b/py/tabfind.py / dmd26.py and a dump of the block between them; the
-- GBA's OBJ chars differ and come from its own tables / literals:
-- kTrinexxHead_FirstPart_Char 4 / 4 / 0x44 / 0x44 / 0x0A, kTrinexx_Draw_Char
-- 6 / 0x48 / 0x48 / 0x4C / 0x4C; the legs 0x0C / 0x4A (0x08108200 /
-- 0x0810822E), the neck 8 (0x08106D4A), the lunge chain 0x48 (0x08108090);
-- kTrinexx_Draw_X / Y are int16 on the GBA; kTrinexx_X0 / Y0 are split lo /
-- hi byte tables):
--
--   0xCB Sprite_CB_TrinexxRockHead (room 0xA4; SpritePrep_Trinexx: x + 8,
--        y + 16, the shell's spot cached (sprite_A / C), y = C + 12): waits
--        overlord_x_lo[6] (255, -1 every other frame), then ai 0 picks a
--        spot (kTrinexx_Tab0 / Tab1, rnd & 3; one time in four fast) and
--        ai 1 walks there (8 / 16), every 3rd stop ai 2 (80 frames, the tail
--        wags twice as fast) then ai 3 lunges at Link (48, back at delay
--        0x20, the chain of kTrinexx_Mults links). The shell hurts Link
--        within (A - x + 40 < 80, C - y + 16 < 64): 8 and thrown at 32
--        (Trinexx_HandleShellCollision); the tail wags (Trinexx_WagTail).
--        It waits while a head breathes (ai 3). The sword tinks (defl 4,
--        "is_many": Link thrown back at 32). Both heads gone (ai < 2): ai
--        255, delay 255; it rises (0xE0..0xFF: y speed -8, the tail drops 2
--        a frame), explodes (rnd kTrinexx_X0 / Y0 every other frame) and
--        becomes the snake (overlord_x_hi[0]).
--        Sprite_Trinexx_FinalPhase: 128 frames of ai 0 (kSprite_TrinexxD_
--        Xvel / Yvel, a wall turns it D + 1), then ai 1 (every other frame
--        the speed steps towards a speed-31 projection at Link); a hit in ai
--        0 (sprite_F 14) -> ai 2 (no case: it keeps its speed). 16 body
--        segments on the 128-position history (kTrinexxD_HistPos /
--        kSprite_TrinexxD_Gfx2); a segment touching Link hurts him (8);
--        segment 4 flashes and is the only place the sword hurts once ai is
--        not 0 (Sprite_Trinexx_CheckDamageToFlashingSegment), the head
--        itself tinks then. At 0 health (ai 128, delay 128): every 12 frames
--        a segment explodes (anim_clock 16 -> 0), then state 4 (224) and the
--        heart container at (0x78, 0x78) of Link's quadrant.
--   0xCC / 0xCD Sprite_Sidenexx (the fire / ice heads; slots 1 / 2): on the
--        shell's spot -14 / +13, y - 0x20; 9 parts (head + neck) on
--        TrinexxHeadSin(angle, radius) per part (alt_sprite_type /
--        alt_sprite_y_hi), stepping towards kTrinexxHead_Target0 / Target1
--        [D * 9 + part] (ai 2). Ai 0 emerging (128 / 255 frames, flags3
--        0x40); ai 1 picks D 1..4 ((rnd & 7) + 1 < 5), from D 1 one time in
--        two (Trinexx ai < 2) ai 3 breathes (127 frames: at 64
--        Sidenexx_ExhaleDanger; the mouth opens kTrinexxHead mouth offset).
--        A rod hit (the Ice Rod on the fire head, the Fire Rod on the ice
--        head: enemy_damage_data) sets the hit timer, which the head clears:
--        ai 4 (128 frames, palette 3, defl bit 4 off) -- the sword hurts it
--        only then ("is_many": Link thrown back at 32). At 0 health (ai 128,
--        delay 96): every 12 frames a neck part explodes, then it is gone.
--   0xCC / 0xCD with sprite_E (the breath): y speed 24, the x speed steps
--        towards +-16 at Link every 4th frame (Sprite_CC_CD_Common), gone on
--        a wall; the fire leaves a flame (Garnish 0x10, 127 frames, 16 to
--        Link within x + 12 < 24, y + 22 < 28 on every 8th frame by slot,
--        kGanonBatFlame_Idx / Char / Flags), the ice (two, x drift +1 / -2)
--        an ice cloud (Garnish 0x0C, kTrinexxIce_Char / Flags) every 8th
--        frame.
--
-- OURS: no sound; the shell is the room's BG2 and is not moved with the
-- body (LayerEffect_Trinexx / dung_floor_x_vel), its palette flashes
-- (Trinexx_FlashShellPalette_*) and the hit flash are not drawn; the
-- explosions are the death puff (Dungeons26.explodeFrame); the sparkle /
-- lava-bubble garnishes of the breathing head and the withering flame
-- (Garnish 0x11) are not drawn; the ice cloud's floor tile
-- (Dungeon_UpdateTileMapWithCommonTile 18 at countdown 0x50) is only
-- counted; a flame's / a body segment's hit uses our hurtLink recoil (the
-- cartridge reverses Link's speed); the garnish palettes are the SNES constants (0x22 / 0x35);
-- the Ice Rod / Fire Rod are a test hook (M.rodHit) until the items exist
-- (team A).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "tr" }

M.OFF = {
  headXoffs = 0x17BF10, target0 = 0x17BF2B, target1 = 0x17BF58, frameMask = 0x17BF85,
  partX = 0x17BF8F, partY = 0x17BF94, partChar = 0x17BF99, partFlags = 0x17BF9E,
  x0 = 0x17BFB8, y0 = 0x17BFC8, tab0 = 0x17BFEC, tab1 = 0x17BFF0, dmd = 0x17BFFC,
  drawX = 0x17C11C, drawY = 0x17C162, drawChar = 0x17C1A8, mults = 0x17C1AD,
  legX = 0x17C1B5, legFlags = 0x17C1B7, xoffs = 0x17C1B9, yoffs = 0x17C1C9,
  dGfx3 = 0x17C1D9, dGfx = 0x17C1E1, dXv = 0x17C1F4, dYv = 0x17C1F8, histPos = 0x17C1FC, gfx2 = 0x17C214,
  flameChar = 0x172E31, flameFlags = 0x172E38, flameIdx = 0x172E3F, iceChar = 0x172E5F, iceFlags = 0x172E6B,
}
M.LEG_CHAR, M.LEG_CHAR2, M.NECK_CHAR, M.CHAIN_CHAR = 0x0C, 0x4A, 0x08, 0x48
M.FIRE_ROD, M.ICE_ROD = 11, 12        -- kAncilla_Damage[2] / [0x0B]

M.TYPES = { [0xCB] = true, [0xCC] = true, [0xCD] = true }
M.FIGHTS = { [0xCB] = true, [0xCC] = true, [0xCD] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8, s16 = D.s8, D.s16
  local t = {
    headXoffs = s8(u8(O.headXoffs, 2)), target0 = u8(O.target0, 45), target1 = u8(O.target1, 45),
    frameMask = u8(O.frameMask, 8),
    partX = s8(u8(O.partX, 5)), partY = s8(u8(O.partY, 5)), partChar = u8(O.partChar, 5), partFlags = u8(O.partFlags, 5),
    x0 = s8(u8(O.x0, 8)), y0 = s8(u8(O.y0, 8)), tab0 = u8(O.tab0, 4), tab1 = u8(O.tab1, 4),
    dmd = D.dmd(rom, O.dmd, 36),
    drawX = s16(rom:bytesU16(O.drawX, 35)), drawY = s16(rom:bytesU16(O.drawY, 35)), drawChar = u8(O.drawChar, 5),
    mults = u8(O.mults, 8), legX = s8(u8(O.legX, 2)), legFlags = u8(O.legFlags, 2),
    xoffs = s8(u8(O.xoffs, 16)), yoffs = s8(u8(O.yoffs, 16)),
    dGfx3 = u8(O.dGfx3, 8), dGfx = u8(O.dGfx, 8), dXv = s8(u8(O.dXv, 4)), dYv = s8(u8(O.dYv, 4)),
    histPos = u8(O.histPos, 24), gfx2 = u8(O.gfx2, 24),
    flameChar = u8(O.flameChar, 7), flameFlags = u8(O.flameFlags, 7), flameIdx = u8(O.flameIdx, 32),
    iceChar = u8(O.iceChar, 12), iceFlags = u8(O.iceFlags, 4),
  }
  check(t.headXoffs[1] == -14 and t.headXoffs[2] == 13 and t.target0[10] == 0x58 and t.target1[37] == 0x48
        and t.frameMask[8] == 0x1F, "Trinexx head tables")
  check(t.partX[1] == -8 and t.partY[5] == 2 and t.partChar[3] == 0x44 and t.partChar[5] == 0x0A
        and t.partFlags[1] == 0x40, "TrinexxHead_Draw tables (GBA chars)")
  check(t.x0[2] == 8 and t.x0[5] == -24 and t.y0[4] == 24 and t.tab0[1] == 0x60 and t.tab1[3] == 0x60,
        "Trinexx movement / explosion tables")
  check(t.dmd[1][1] == -8 and t.dmd[1][2] == -8 and t.dmd[4][2] == 8 and #t.dmd == 36,
        "kTrinexx_Draw1_Dmd")
  check(t.drawX[2] == 3 and t.drawX[35] == -24 and t.drawY[1] == 0x18 and t.drawY[20] == 0x3D
        and t.drawChar[1] == 6 and t.drawChar[2] == 0x48 and t.mults[1] == 0xFC and t.legX[1] == -28
        and t.legFlags[1] == 0x40 and t.xoffs[2] == 2 and t.yoffs[1] == -4, "Trinexx body tables (GBA chars)")
  check(t.dGfx3[1] == 6 and t.dGfx[1] == 7 and t.dXv[2] == -31 and t.dYv[1] == 31 and t.histPos[1] == 8
        and t.histPos[24] == 0x74 and t.gfx2[4] == 3, "Trinexx snake tables")
  check(t.flameIdx[1] == 7 and t.flameChar[1] == 0xAC and t.flameFlags[2] == 0x41 and t.iceChar[1] == 0xD8
        and t.iceFlags[2] == 0x40, "flame / ice garnish tables (GBA chars)")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.tr end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function A() return require("src.zelda.alttp.Actors") end
local function u8(v) return band(v, 0xFF) end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

-- TrinexxHeadMult / TrinexxHeadSin (kSinusLookupTable)
local function headSin(game, a, b)
  local s = D().tabs(game).sine[band(a, 0xFF) + 1] or 0
  local t
  if s >= 256 then t = b else local p = s * b; t = rshift(p, 8) + band(rshift(p, 7), 1) end
  t = u8(t)
  if band(a, 0x100) ~= 0 then t = u8(-t) end
  return i8(t)
end
M.headSin = headSin

-- TrinexxMult (signed a)
local function mult(a, b)
  a = u8(a)
  local neg = a >= 128
  local at = neg and u8(-a) or a
  local p = at * b
  local r = u8(rshift(p, 8) + band(rshift(p, 7), 1))
  return i8(neg and -r or r)
end

-- Link hurt by raw damage (link_give_damage); (vx, vy): link_actual_vel
-- (incapacitated 16 frames)
local function hurtRaw(game, dmg, fx, fy, vx, vy)
  if (game.blink or 0) > 0 or game.pitFall then return false end
  game:hurtLink(dmg, fx, fy)
  if vx and game.recoil then game.recoil.vx, game.recoil.vy, game.recoil.t = vx, vy, 16 end
  return true
end

-- ------------------------------------------------------------ garnishes
-- the flame (Garnish 0x10) and the ice cloud (Garnish 0x0C): not sprites
-- (they do not count for Sprite_CheckIfScreenIsClear)
function M.garnish(actors, kind, x, y, t)
  actors.trxG = actors.trxG or {}
  actors.trxGk = band((actors.trxGk or 0) + 1, 15)
  local g = { kind = kind, x = x, y = y, t = t or 127, k = actors.trxGk, room = actors.room }
  actors.trxG[#actors.trxG + 1] = g
  local game = actors.game
  if kind == 0x10 then game.trxFlames = (game.trxFlames or 0) + 1 else game.trxIce = (game.trxIce or 0) + 1 end
  return g
end

-- Garnish_CheckPlayerCollision
local function garnishHit(actors, g, lk)
  local game = actors.game
  if band(bxor(g.k, actors.frame), 7) ~= 0 then return end
  if u8(lk.x - g.x + 12) < 24 and u8(lk.y - g.y + 22) < 28 then
    if hurtRaw(game, 16, g.x + 8, g.y + 8) then game.flameHits = (game.flameHits or 0) + 1 end
  end
end

function M.garnishFrame(actors, lk)
  local list = actors.trxG
  if not list or actors.trxGf == actors.frame then return end
  actors.trxGf = actors.frame
  local keep = {}
  for _, g in ipairs(list) do
    g.t = g.t - 1
    if g.t > 0 and g.room == actors.room then
      keep[#keep + 1] = g
      if g.kind == 0x10 then
        if g.t == 8 then g.kind = 0x11 end
        if g.kind == 0x10 then garnishHit(actors, g, lk) end
      elseif g.kind == 0x11 then
        g.y = g.y - 1
      elseif g.kind == 0x0C and g.t == 0x50 then
        actors.game.trxIceTiles = (actors.game.trxIceTiles or 0) + 1
      end
    end
  end
  actors.trxG = keep
end

function M.drawGarnish(spr, actors, ox, oy, game)
  local tb = T(game)
  for _, g in ipairs(actors.trxG or {}) do
    if g.room ~= actors.room then
    elseif g.kind == 0x10 then
      local j = tb.flameIdx[rshift(g.t, 3) + 1] or 4
      spr:oam(g.x + ox, g.y + oy, tb.flameChar[j + 1], bor(tb.flameFlags[j + 1], 0x22), 2)
    elseif g.kind == 0x0C then
      spr:oam(g.x + ox, g.y + oy, tb.iceChar[rshift(g.t, 4) + 1] or tb.iceChar[1],
              bor(tb.iceFlags[band(rshift(g.t, 2), 3) + 1], 0x35), 2)
    end
  end
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  local t = a.type
  a.game = self.game
  if not T(self.game) then return end
  if M._seg then
    a.segOf, a.noTouch = M._seg, true
    return
  end
  if M._breath then
    -- Sidenexx_ExhaleDanger: sprite_E 1, y speed 24, no projectiles
    a.breath, a.vy, a.vx, a.C = true, 24, 0, 0
    a.untouchable, a.noTouch = true, true
    return
  end
  -- SpritePrep_Trinexx (Sprite_ReturnIfBossFinished) + TrinexxComponents_Initialize
  if D().bossFinished(self) then a.dead = true return end
  a.noTouch = true
  if t == 0xCB then
    a.x, a.y = a.x + 8, a.y + 16
    a.cx, a.cy = a.x, a.y
    a.ov = { [0] = 0, 0, 0, 0, 0, 0, 255, 0, hi0 = 0 }
    a.y = a.cy + 12                                   -- Trinexx_RestoreXY
    a.anim, a.subtype, a.headDir = 0, 0, 0
  else
    a.gfx = (t == 0xCC) and 3 or 0
    a.delay = (t == 0xCC) and 128 or 255
    a.angT, a.radT = {}, {}
    for i = 0, 8 do a.angT[i], a.radT[i] = 0x40, 0 end
    a.parts, a.subtype = 1, 0
    a.cx, a.cy = a.x, a.y
  end
end

local function bossOf(self, a)
  if a.boss and a.boss.type == 0xCB then return a.boss end
  for _, b in ipairs(self.list) do
    if b.type == 0xCB and not b.segOf and not b.dead then a.boss = b return b end
  end
end

-- ------------------------------------------------------------ the rods
-- Ancilla_CheckDamageToSprite_preset (class 11 the Fire Rod, 12 the Ice
-- Rod): Sprite_ApplyCalculatedDamage (nothing while flags3 & 0x40), the hit
-- timer 0x20. Team A's rods call this; tests too.
function M.rodHit(actors, a, cls)
  local game = actors.game
  if not a or a.dead or a.breath or a.segOf or a.flags40 or a.untouchable then return false end
  if a.type == 0xCB then return false end   -- flags3 0x41 (the rock head)
  local dmg = require("src.zelda.alttp.Items").damage(game, cls, a.type)
  if dmg == 0 or dmg >= 249 then return false end
  a.pend = math.max(a.pend or 0, dmg)
  a.inv = 0x20
  game.rodHits = (game.rodHits or 0) + 1
  return true
end

-- the sword's "is_many" rule (Sprite_CheckDamageFromLink, types 0xCB-0xCD):
-- Link thrown back at 32, set_when_damaging_enemies 144
local function zap(self, a, x, y)
  if a.invSword and a.inv == 0x1D and not a.zapSeen then
    a.zapSeen = true
    D().pushLink(self.game, x or a.x, y or a.y, 32, 16)
    self.game.swde = 144
  elseif (a.inv or 0) == 0 then a.zapSeen = nil end
end

-- ------------------------------------------------------------ the heads
-- part i's offset (TrinexxHead_Draw)
local function partOff(game, a, i)
  local r6 = (a.type ~= 0xCD) and (0x100 + u8(-a.angT[i])) or a.angT[i]
  local r15 = a.radT[i]
  return headSin(game, r6, r15), headSin(game, r6 + 0x80, r15)
end
M.partOff = partOff

local function exhale(self, a)
  local d = D()
  local game = self.game
  M._breath = true
  if a.type == 0xCD then
    for i = 0, 1 do
      local j = d.spawn(self, 0xCD, a.x, a.y, a.lower)
      j.C = (i == 1) and 1 or -2
    end
  else
    d.spawn(self, 0xCC, a.x, a.y, a.lower)
  end
  M._breath = nil
  game.trxBreaths = (game.trxBreaths or 0) + 1
end

local function sidenexx(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  local b = bossOf(self, a)
  if b then
    a.cx = b.cx + tb.headXoffs[a.type - 0xCC + 1]
    a.cy = b.cy - 0x20
  end
  -- TrinexxHead_Draw: the sprite sits on part 0
  local ox, oy = partOff(game, a, 0)
  a.x, a.y = a.cx + ox, a.cy + oy
  a.recoil = nil
  if a.ai >= 128 then
    -- Sidenexx_Explode
    a.untouchable, a.noTouch = true, true
    if a.delay == 0 then
      a.delay = 12
      local i = math.max(0, a.parts - 1)
      local px, py = partOff(game, a, i)
      require("src.zelda.alttp.Effects").death(game, { type = 0x00, x = a.cx + px, y = a.cy + py, z = 0, lower = a.lower })
      game.bossBooms = (game.bossBooms or 0) + 1
      if a.parts == 1 then a.dead = true; game.trxHeadsGone = (game.trxHeadsGone or 0) + 1 return end
      a.parts = a.parts - 1
    end
    return
  end
  -- the damage the hit timer gives at 24 (Sprite_GiveDamage: ai 128, 96)
  if a.inv == 24 and a.pend then
    local dmg = a.pend
    a.pend = nil
    a.hp = a.hp - dmg
    if a.hp <= 0 then
      a.hp, a.ai, a.delay, a.inv = 0, 128, 96, 0
      a.untouchable = true
      game.trxHeadKills = (game.trxHeadKills or 0) + 1
      return
    end
  end
  -- a hit (the rods) outside ai 4: the hit timer is cleared, ai 4
  if (a.inv or 0) ~= 0 and a.ai ~= 4 then
    a.inv, a.pend, a.invSword = 0, nil, nil
    a.delay, a.ai = 128, 4
    a.oamSave, a.oam = a.oam, 3
    game.trxOpened = (game.trxOpened or 0) + 1
  end
  zap(self, a)
  d.contact(self, a, lk)
  local ai = a.ai
  if ai == 0 then
    a.flags40 = true
    if a.delay == 0 then a.ai, a.parts, a.flags40 = 2, 9, nil end
  elseif ai == 1 then
    if a.delay == 0 then
      local i = band(d.rnd(self), 7) + 1
      local j = a.D
      if i < 5 and a.D ~= i then
        a.D, a.ai = i, 2
        if j == 1 and band(d.rnd(self), 1) == 0 and b and b.ai < 2 then
          a.gfx, a.ai, a.delay = 0, 3, 127
        end
      end
    end
  elseif ai == 2 then
    local j0 = a.D * 9
    local n = 0
    for m = 0, 8 do
      local t0, t1 = tb.target0[j0 + m + 1], tb.target1[j0 + m + 1]
      for _ = 1, 2 do
        local v = a.angT[m]
        if v ~= t0 then a.angT[m] = u8(v + ((i8(v - t0) < 0) and 1 or -1)); n = n + 1 end
      end
      local r = a.radT[m]
      if r ~= t1 then a.radT[m] = u8(r + ((i8(r - t1) < 0) and 1 or -1)); n = n + 1 end
    end
    if n == 0 then a.ai, a.delay = 1, band(d.rnd(self), 15) end
  elseif ai == 3 then
    local j = a.delay
    if j == 0 then a.ai, a.delay = 0, 32 return end
    if j == 64 then exhale(self, a) end
    a.subtype = (j < 8) and j or ((j < 121) and 8 or u8(bit.bnot(j + 0x80)))
  elseif ai == 4 then
    a.subtype = 0
    if a.delay == 0 then
      a.ai, a.delay = 1, 32
      a.oam, a.inv = a.oamSave, 0
    end
  end
end

-- Sprite_CC (fire) / Sprite_CD (ice) with sprite_E: the breath
local function breath(self, a, lk)
  local d = D()
  if a.type == 0xCD then
    local vx = a.vx
    a.vx = vx + (a.C or 0)
    H().moveXY(a)
    a.vx = vx
    a.sub2 = u8((a.sub2 or 0) + 1)
    if band(a.sub2, 7) == 0 then M.garnish(self, 0x0C, a.x, a.y + 16, 127) end
  else
    H().moveXY(a)
    a.sub2 = u8((a.sub2 or 0) + 1)
    if band(a.sub2, 7) == 0 then M.garnish(self, 0x10, a.x, a.y + 16, 127) end
  end
  -- Sprite_CC_CD_Common
  if band(self.frame, 3) == 0 then
    local m = (lk.x - a.x < 0) and -1 or 1
    if a.vx ~= 16 * m then a.vx = a.vx + m end
  end
  if H().tileCollision(self, a) ~= 0 then a.dead = true end
end

-- ------------------------------------------------------------ the rock head
local function wagTail(a)
  local ov = a.ov
  if ov[5] == 0 then
    ov[4] = u8(ov[4] + 1)
    if band(ov[4], 3) == 0 then
      local j = band(ov[3], 1)
      ov[2] = u8(ov[2] + ((j == 1) and -1 or 1))
      if ov[2] == ((j == 1) and 0 or 6) then ov[3] = u8(ov[3] + 1); ov[5] = 8 end
    end
  else
    ov[5] = ov[5] - 1
  end
end

local function shellCollision(self, a, lk)
  local game = self.game
  if band(a.cx - lk.x + 40, 0xFFFF) < 80 and band(a.cy - lk.y + 16, 0xFFFF) < 64 then
    local vx, vy = D().towardsLink(a, lk, 32)
    if hurtRaw(game, 8, a.x + 8, a.y + 8, vx, vy) then game.shellHits = (game.shellHits or 0) + 1 end
  end
end

local function headAlive(self, t)
  for _, b in ipairs(self.list) do
    if b.type == t and not b.dead and not b.breath and not b.segOf then return b end
  end
end

-- the snake's flashing segment (a stand-in sprite at kTrinexxD_HistPos[4])
local function spawnSeg(self, a)
  M._seg = a
  local s = D().spawn(self, 0xCB, a.x, a.y, a.lower)
  M._seg = nil
  s.hp = a.hp
  a.seg = s
  return s
end

local function becomeSnake(self, a)
  local ov = a.ov
  ov.hi0 = 1
  -- Sprite_InitializedSegmented
  a.hist = {}
  for i = 0, 127 do a.hist[i] = { a.x, a.y } end
  a.sub2, a.headDir, a.ai, a.D = 0, 0, 0, 0
  a.anim, a.vx, a.vy, a.Acnt = 16, 0, 0, 128
  a.snake, a.untouchable = true, false
  self.game.trxSnake = (self.game.trxSnake or 0) + 1
  spawnSeg(self, a)
end

local function rockHead(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  local ov = a.ov
  if a.ai >= 128 then
    if a.delay == 0 then
      becomeSnake(self, a)
    elseif a.delay >= 0xFF then
    elseif a.delay >= 0xE0 then
      a.vy = -8
      local py = a.y * 16 + (a.fy or 0) + a.vy
      a.y, a.fy = math.floor(py / 16), py % 16
      a.cx, a.cy = a.x, a.y - 12
      ov[7] = ov[7] + 2
    else
      if band(a.delay, 1) == 0 then
        local x = a.x + tb.x0[band(d.rnd(self), 7) + 1]
        local y = a.y + tb.y0[band(d.rnd(self), 7) + 1] - 8
        require("src.zelda.alttp.Effects").death(game, { type = 0x00, x = x, y = y, z = 0, lower = a.lower })
        game.bossBooms = (game.bossBooms or 0) + 1
      end
      a.headDir = 255
    end
    return
  end
  if not headAlive(self, 0xCC) and not headAlive(self, 0xCD) and a.ai < 2 then
    a.delay, a.ai = 255, 255
    a.untouchable = true
    game.trxRise = (game.trxRise or 0) + 1
    return
  end
  wagTail(a)
  shellCollision(self, a, lk)
  zap(self, a)
  d.contact(self, a, lk)
  if band(self.frame, 63) == 0 then
    local dx = lk.x - a.x
    a.gfx = (u8(u8(dx) + 24) < 48) and 0 or ((dx < 0) and 1 or 7)
  end
  if ov[6] ~= 0 then
    if band(self.frame, 1) == 0 then ov[6] = ov[6] - 1 end
    return
  end
  for _, t in ipairs({ 0xCC, 0xCD }) do
    local h = headAlive(self, t)
    if h and h.ai == 3 then return end
  end
  local ai = a.ai
  if ai == 0 then
    if a.delay == 0 then
      local j = band(d.rnd(self), 3)
      if band(a.subtype, 0x7F) == j then return end
      a.anim = a.anim + 1
      if a.anim == 2 then
        a.anim, a.ai, a.delay = 0, 2, 80
        return
      end
      ov[0], ov[1] = tb.tab0[j + 1], tb.tab1[j + 1]
      a.subtype = j + ((band(d.rnd(self), 3) == 0) and 0x80 or 0)
      a.ai = 1
    end
  elseif ai == 1 then
    local fast = a.subtype >= 0x80
    local tx, ty = bor(band(a.x, 0xFF00), ov[0]), bor(band(a.y, 0xFF00), ov[1])
    a.vx, a.vy = A().project(a.x, a.y, tx, ty, fast and 16 or 8)
    H().moveXY(a)
    a.cx, a.cy = a.x, a.y - 12
    if u8(ov[0] - a.x + 2) < 4 and u8(ov[1] - a.y + 2) < 4 then a.ai, a.delay = 0, 48 end
    for _ = 1, fast and 2 or 1 do a.sub2 = u8((a.sub2 or 0) + ((a.vx < 0) and 1 or -1)) end
    game.trxSteps = (game.trxSteps or 0) + 1
  elseif ai == 2 then
    wagTail(a); wagTail(a)
    if a.delay == 0 then
      a.ai = 3
      a.vx, a.vy = d.towardsLink(a, lk, 48)
      a.delay = 64
      game.trxLunges = (game.trxLunges or 0) + 1
    end
  elseif ai == 3 then
    H().moveXY(a)
    if a.delay == 0 then
      a.x, a.y = a.cx, a.cy + 12          -- Trinexx_RestoreXY
      a.ai, a.delay = 0, 48
    elseif a.delay == 0x20 then
      a.vx, a.vy = -a.vx, -a.vy
    end
  end
end

-- ------------------------------------------------------------ the snake
local function segPos(a, i, tb)
  return a.hist[band((a.sub2 or 0) - tb.histPos[i + 1], 0x7F)] or { a.x, a.y }
end

local function snake(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  a.recoil, a.rvx, a.rvy = nil, nil, nil
  if a.exploding then
    if (a.delay or 0) <= 32 then
      -- SpriteExplode_SpawnEA (tmp_counter 0xCB): the heart at 0x78, 0x78
      a.x, a.y = bor(band(lk.x, 0xFF00), 0x78), bor(band(lk.y, 0xFF00), 0x78)
    end
    d.explodeFrame(self, a)
    return
  end
  if a.ai >= 128 then
    if a.delay == 0 then
      a.delay = 12
      if a.anim == 0 then
        d.explode(self, a, 224)                  -- Sprite_ScheduleBossForDeath
        return
      end
      local p = segPos(a, a.anim - 1, tb)
      require("src.zelda.alttp.Effects").death(game, { type = 0x00, x = p[1], y = p[2], z = 0, lower = a.lower })
      game.bossBooms = (game.bossBooms or 0) + 1
      a.anim = a.anim - 1
    end
    return
  end
  -- the damage the hit timer gives at 24 (the kill branch: ai 128, 128)
  local function take(dmg)
    a.hp = a.hp - dmg
    if a.hp <= 0 then
      a.hp, a.ai, a.delay, a.inv = 0, 128, 128, 0
      a.untouchable = true
      if a.seg then a.seg.dead = true end
      game.bossDying = a
      game.trxSnakeKills = (game.trxSnakeKills or 0) + 1
      return true
    end
  end
  if a.inv == 24 and a.pend then
    local dmg = a.pend; a.pend = nil
    if take(dmg) then return end
  end
  local s = a.seg
  if s and s.inv == 24 and s.pend then
    local dmg = s.pend; s.pend = nil
    game.trxSegHits = (game.trxSegHits or 0) + 1
    if take(dmg) then return end
  end
  zap(self, a)
  -- the body segments touching Link (Sprite_TrinexxD_Draw)
  if (game.blink or 0) == 0 then
    for i = 0, a.anim - 1 do
      local p = segPos(a, i, tb)
      if band(lk.x - p[1] + 8, 0xFFFF) < 16 and band(lk.y - p[2] + 16, 0xFFFF) < 16 then
        if hurtRaw(game, 8, p[1] + 8, p[2] + 8) then game.trxBodyHits = (game.trxBodyHits or 0) + 1 end
        break
      end
    end
  end
  a.sub2 = u8((a.sub2 or 0) + 1)
  a.hist[band(a.sub2, 0x7F)] = { a.x, a.y }
  -- sprite_F 14: a fresh hit (the hit timer just set) in ai 0 -> ai 2
  if (a.inv == 0x1D or a.inv == 0x20) and a.ai == 0 then a.ai = 2 end
  H().moveXY(a)
  d.contact(self, a, lk)
  local ai = a.ai
  if ai == 0 then
    a.Acnt = a.Acnt - 1
    if a.Acnt == 0 then a.ai, a.delay = 1, 192 end
    if H().tileCollision(self, a) ~= 0 then
      a.D = band(a.D + 1, 3)
      a.aux1 = 8
    end
    a.vx, a.vy = tb.dXv[a.D + 1], tb.dYv[a.D + 1]
  elseif ai == 1 then
    if band(self.frame, 1) == 0 then
      local px, py = d.towardsLink(a, lk, 31)
      if a.vx ~= px then a.vx = a.vx + ((a.vx - px < 0) and 1 or -1) end
      if a.vy ~= py then a.vy = a.vy + ((a.vy - py < 0) and 1 or -1) end
    end
  end
  -- the flashing segment: the only place the sword hurts once ai is not 0
  if s and not s.dead then
    local p = segPos(a, 4, tb)
    s.x, s.y, s.lower = p[1], p[2], a.lower
    s.untouchable = (a.ai == 0)
    s.hp = math.max(1, a.hp)
    zap(self, s)
  end
end

local function rockOrSnake(self, a, lk)
  if a.segOf then
    local b = a.segOf
    if not b or b.dead or b.exploding or (b.ai or 0) >= 128 then a.dead = true end
    a.recoil = nil
    return
  end
  if a.ov.hi0 ~= 0 then return snake(self, a, lk) end
  a.recoil = nil
  return rockHead(self, a, lk)
end

function M.update(self, a, lk)
  if not T(self.game) then return end
  M.garnishFrame(self, lk)
  local t = a.type
  if t == 0xCB then return rockOrSnake(self, a, lk) end
  if a.breath then return breath(self, a, lk) end
  return sidenexx(self, a, lk)
end

-- the sword: the rock head tinks (defl 4) but not the snake in ai 0; the
-- flashing segment once ai is not 0; a head only in ai 4
function M.swordImmune(a, how)
  if a.segOf then return false end
  if a.type == 0xCB then
    if a.ov and a.ov.hi0 ~= 0 then return a.ai ~= 0 end
    return true
  end
  if a.breath then return true end
  return a.ai ~= 4
end

function M.died(self, a) end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
local function singleChar(spr, t, g) return spr.info.single2[(spr.info.single1[t + 1] or 0) + (g or 0) + 1] end

local function drawRock(spr, tb, a, x, y, f, g)
  spr:drawDmd(a, tb.dmd, (g or 0) * 4, 4, x, y, f)
end

function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = g and T(g)
  if not tb then return false end
  local t = a.type
  local f = oamF(spr, t)
  local ox, oy = x - a.x, y - a.y
  if a.segOf or a.breath then return true end
  if t == 0xCB then
    if g.actors then M.drawGarnish(spr, g.actors, ox, oy, g) end
    if a.ov.hi0 ~= 0 then return M.drawSnake(spr, tb, a, x, y, ox, oy, g) end
    if (a.headDir or 0) >= 128 then return true end
    -- SpriteDraw_TrinexxRockHeadAndBody: tail, legs, chain, then the head
    local xb, yb = a.cx + ox, a.cy + oy
    local gi = a.ov[2]
    for i = 4, 0, -1 do
      local j = gi * 5 + i
      spr:oam(xb + tb.drawX[j + 1], yb - tb.drawY[j + 1] - 0x20 + a.ov[7], tb.drawChar[i + 1], f, 2)
    end
    local s2 = a.sub2 or 0
    local xidx = (u8((a.vx or 0) + 3) < 7) and 0 or rshift(s2, 2)
    local yidx = rshift(s2, 2)
    for i = 1, 0, -1 do
      local lx = xb + tb.legX[1 - i + 1] + tb.xoffs[band(xidx + (1 - i) * 8, 15) + 1]
      local ly = yb - 8 + tb.yoffs[band(yidx + i * 8, 15) + 1]
      local fl = bor(f, tb.legFlags[i + 1])
      spr:oam(lx, ly + 16, M.LEG_CHAR2, fl, 2)
      spr:oam(lx, ly, M.LEG_CHAR, fl, 2)
    end
    if a.ai == 3 then
      local xd, yd = u8(a.cx - a.x), u8(a.cy - a.y)
      for i = 7, 0, -1 do
        spr:oam(x + mult(xd, tb.mults[i + 1]), y + mult(yd, tb.mults[i + 1]), M.CHAIN_CHAR, f, 2)
      end
    end
    drawRock(spr, tb, a, x, y, f, a.gfx)
    return true
  end
  -- TrinexxHead_Draw: the neck (far end first), then the head and mouth
  local fl = a.oam or f
  local bx, by = a.cx + ox, a.cy + oy
  for i = (a.parts or 1) - 1, 1, -1 do
    local px, py = partOff(g, a, i)
    spr:oam(bx + px, by + py, M.NECK_CHAR, fl, 2)
  end
  local px, py = partOff(g, a, 0)
  for m = 5, 1, -1 do
    local yy = by + py + tb.partY[m] + ((m == 5) and (a.subtype or 0) or 0)
    spr:oam(bx + px + tb.partX[m], yy, tb.partChar[m], bor(fl, tb.partFlags[m]), 2)
  end
  return true
end

-- Sprite_TrinexxD_Draw: the segments (back to front), then the head
function M.drawSnake(spr, tb, a, x, y, ox, oy, g)
  local s2 = a.sub2 or 0
  for i = (a.anim or 0) - 1, 0, -1 do
    local p = segPos(a, i, tb)
    local fl = 1
    if i == 4 and a.ai ~= 0 then fl = bxor(band(s2, 6), fl) end
    local gg = tb.gfx2[i + 1]
    if gg ~= 3 then
      local ch = singleChar(spr, 0xCB, gg)
      if ch then spr:oam(p[1] + ox, p[2] + oy, ch, fl, 2) end
    else
      drawRock(spr, tb, a, p[1] + ox, p[2] + oy, fl, 8)
    end
  end
  local j = rshift(D().angle(g, a.vx or 0, a.vy or 0), 1)
  local gfx = tb.dGfx3[band(j, 7) + 1]
  if (a.aux1 or 0) ~= 0 then gfx = tb.dGfx[gfx + 1] end
  drawRock(spr, tb, a, x, y, band(spr.info.flags3[0xCB + 1] or 0, 0x0F), gfx)
  return true
end

-- ------------------------------------------------------------ install
function M.install(G, Dm)
  -- the sword on the rock head / a closed head / the snake's head:
  -- "is_many" (Link thrown back at 32, set_when_damaging_enemies 144), then
  -- the tink (Sprite_CheckDamageFromLink "getting_out")
  local Act = A()
  local tink0 = Act.tinkLink
  function Act:tinkLink(a)
    if a and M.TYPES[a.type] and not a.breath and not a.segOf then
      local game = self.game
      if (game.swde or 0) ~= 0 then return end
      game.swde = 144
      D().pushLink(game, a.x, a.y, 32, 16)
      game.trxTinks = (game.trxTinks or 0) + 1
      return
    end
    return tink0(self, a)
  end
end

return M
