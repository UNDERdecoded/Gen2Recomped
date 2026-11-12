-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- AGAHNIM (round 26, team B): Hyrule Castle Tower's boss (room 0x20) and
-- Ganon's Tower's (room 0x0D), the SNES routines the GBA keeps (zelda3
-- names), run by Palace.lua through Dungeons26.lua's registry. Tables are the
-- GBA's (file offsets in OFF, found by value with r26b/py/tabfind.py /
-- dmd26.py / bfind.py; the GBA's OBJ chars differ):
--
--   0x7A Sprite_7A_Agahnim: SpritePrep_Agahnim (8 px down / right, D 3,
--        oam flags 11 Light World / 7 Dark World). States: 1 message 0x13F
--        -> 3; 2 materialise (kAgahnim_Gfx0) -> 3 (255 frames); 3 fight:
--        while delay >= 128 he faces Link (kAgahnim_Dir by the speed-2
--        projection) and aims at 32, at delay 112 Agahnim_PerformAttack; he
--        is hurt / hurts only in slot 0 with 16 <= delay < 239; 4 fade
--        (kAgahnim_Gfx2) -> a spot of kAgahnim_Tab3 / Tab4 (subtype 4 ->
--        spot 4); 5 glide there (speed 8 up to 64) -> 2. Dark World: 6
--        message 0x141 -> 7: at delay 64 two clones (kAgahnim_Tab6 oam
--        flags, kAgahnim_Tab5 x speed, y speed + 2 a frame) -> 3.
--        Agahnim_PerformAttack: slot 0 counts subtype (& 3 in the Dark
--        World); at 5 four lightning bolts (0xBF), else a ball 0x7B at
--        kAgahnim_X0 / Y0 by D with his speed; from subtype 2 one ball in
--        two is a seeker (B 1, aims 32 frames). Kill branch (Sprite_Check
--        DamageFromLink, type 0x7A): Sprite_KillFriends; Light World ai 10
--        (255 frames, the spin kAgahnim_Gfx3 by z_subpos carries), then
--        PrepareDungeonExitFromBossFight; Dark World ai 8 (255, gfx 17),
--        clones ai 9 (back into slot 0 at 0x20).
--   0x7B Sprite_7B_AgahnimBalls: a trail ball (ai 15, kEnergyBall_Gfx)
--        every 4th frame by slot; a wall ends it (a seeker splits into six
--        0x55 balls, kEnergyBall_Split*Vel); Link's sword (Sprite_Check
--        DamageFromLink carry) sends it back (speed 0x30, negated, A + 1) or
--        splits a seeker; a returned ball touching Agahnim (15 x 15 box,
--        slot 0 not ignoring projectiles) gives 16 damage (hit timer 0xA0)
--        and recoils him by its speed.
--   0xBF Sprite_BF_Lightning: every 2 frames 16 px down, x by
--        kSpriteLightning_Xoff[A << 3 | rnd & 7], a trail piece
--        (Garnish09_LightningTrail: 32 frames, GBA chars 0x172DFF + 0x80 in
--        room 0x20, Garnish_CheckPlayerCollision: x + 12 < 24, y + 22 < 28,
--        every 8th frame, 16 damage); gone past screen y 0xD0.
--   0xC1 Sprite_C1_CutsceneAgahnim (room 0x30): Zelda on the altar (A 1,
--        y + 40); message 0x13D, levitates her (z to 22), the telewarp, she
--        is gone, message 0x13E, he flies up to y < 48 and is gone
--        (dung_savegame_state_bits 0x4000 -- the room's memory here).
--
-- The warp (PrepareDungeonExitFromBossFight, room 0x20 -> kDungeonExit_To
-- 0x20): sram_progress_indicator 3, the Dark World; the room's exit is the
-- pyramid (exit table: area 0x5B, Dark World). Hand-off: game.progress
-- .agahnim1 / .sramProgress = 3 / .bossBeaten[0x20], health refilled
-- (BossVictory_Heal), then G:leaveRoom() lands Link on the pyramid.
--
-- OURS: no sound; Module15's warp / victory spin animation (Link is put on
-- the pyramid by the exit walk); AgahnimWarpShadowFilter, the palette flash,
-- the motion blur, the spell's telewarp art (SpriteDraw_CutsceneAgahnimSpell)
-- and Altar Zelda's warp / body art are not drawn; the split balls use the
-- Desert Palace's 0x55 fireball (their blue oam flags 4 not set); the
-- shadow under Agahnim is not drawn; Phantom Ganon (Agahnim 2's death) is
-- not spawned (game.progress.agahnim2 is set).

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = { NAME = "agahnim" }

M.OFF = {
  gfx3 = 0x175BD8, tab6 = 0x175BDF, tab5 = 0x175BE1, startState = 0x175BE3, gfx0 = 0x175BE5,
  tab0 = 0x175BEA, tab1 = 0x175BFA, tab2 = 0x175C0A, dir = 0x175C10, gfx1 = 0x175C29, gfx2 = 0x175C2F,
  tab3 = 0x175C34, tab4 = 0x175C44, x0 = 0x175C54, y0 = 0x175C60,
  drawX0 = 0x175C66, drawY0 = 0x175CAE, char0 = 0x175CF6, flags0 = 0x175D3E,
  drawX1 = 0x175D86, drawY1 = 0x175DCE, char1 = 0x175E16, big1 = 0x175E3A,
  ballGfx = 0x175E60, splitXv = 0x175E70, splitYv = 0x175E76, ballDmd = 0x175E7C,
  ltGfx = 0x175EBC, ltFlags = 0x175EC4, ltXoff = 0x175ECC, ltX = 0x175F0C,
  trailChar = 0x172DFF, trailFlags = 0x172E07,
  chattyDmd = 0x175A1C, altarDmd = 0x175B28,
}
M.OAM = { [0] = 11, 7 }        -- kAgahnim_OamFlags (SpritePrep_Agahnim's code constants)
M.MSG_TOWER, M.MSG_GT = 0x13F, 0x141
M.MSG_ALTAR1, M.MSG_ALTAR2 = 0x13D, 0x13E

M.TYPES = { [0x7A] = true, [0x7B] = true, [0xBF] = true, [0xC1] = true }
M.FIGHTS = { [0x7A] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8 = D.s8
  local t = {
    gfx3 = u8(O.gfx3, 7), tab6 = u8(O.tab6, 2), tab5 = s8(u8(O.tab5, 2)), startState = u8(O.startState, 2),
    gfx0 = u8(O.gfx0, 5), tab0 = u8(O.tab0, 16), tab1 = u8(O.tab1, 16), tab2 = u8(O.tab2, 6),
    dir = u8(O.dir, 25), gfx1 = u8(O.gfx1, 6), gfx2 = u8(O.gfx2, 5), tab3 = u8(O.tab3, 16), tab4 = u8(O.tab4, 16),
    x0 = s8(u8(O.x0, 6)), y0 = s8(u8(O.y0, 6)),
    drawX0 = s8(u8(O.drawX0, 72)), drawY0 = s8(u8(O.drawY0, 72)), char0 = u8(O.char0, 72), flags0 = u8(O.flags0, 72),
    drawX1 = s8(u8(O.drawX1, 72)), drawY1 = s8(u8(O.drawY1, 72)), char1 = u8(O.char1, 36), big1 = u8(O.big1, 36),
    ballGfx = u8(O.ballGfx, 16), splitXv = s8(u8(O.splitXv, 6)), splitYv = s8(u8(O.splitYv, 6)),
    ballDmd = D.dmd(rom, O.ballDmd, 8),
    ltGfx = u8(O.ltGfx, 8), ltFlags = u8(O.ltFlags, 8), ltXoff = s8(u8(O.ltXoff, 64)), ltX = s8(u8(O.ltX, 8)),
    trailChar = u8(O.trailChar, 8), trailFlags = u8(O.trailFlags, 8),
    chattyDmd = D.dmd(rom, O.chattyDmd, 16), altarDmd = D.dmd(rom, O.altarDmd, 4),
  }
  check(t.gfx3[2] == 8 and t.tab6[1] == 9 and t.tab5[2] == -32 and t.startState[2] == 6 and t.gfx0[1] == 12,
        "Agahnim state tables")
  check(t.dir[11] == 5 and t.gfx1[2] == 10 and t.tab2[1] == 30 and t.tab3[1] == 0x38 and t.tab4[16] == 0xA0
        and t.x0[2] == 10 and t.y0[1] == -9, "Agahnim movement / attack tables")
  check(t.drawX0[1] == -8 and t.drawY0[72] == 8 and t.char0[1] == 0x82 and t.flags0[2] == 0x40
        and t.drawX1[1] == -7 and t.big1[1] == 0 and t.char1[1] == 0x9E, "Agahnim_Draw tables (GBA chars)")
  check(t.ballGfx[1] == 2 and t.splitYv[1] == -32 and t.ballDmd[1][3] == 0x9E and t.ltXoff[1] == -15
        and t.ltX[2] == 8 and t.trailChar[1] == 0x9C and t.trailFlags[5] == 0x71, "energy balls / lightning tables")
  check(t.chattyDmd[1][5] == 2 and t.altarDmd[1][1] == -4, "cutscene Agahnim / altar Zelda draw tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.agahnim end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end

local function dark(self)
  return require("src.zelda.alttp.Palace").palaceId(self.game) ~= 8 and self.inside.room ~= 0x20
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  local t = a.type
  a.game = self.game
  if t == 0x7A then
    if M._clone then
      a.clone, a.slot = M._clone.slot, M._clone.slot
      a.oam = M._clone.oam
      return
    end
    if D().bossFinished(self) then a.dead = true return end
    -- SpritePrep_Agahnim
    a.slot = 0
    a.gfx, a.D = 0, 3
    a.x, a.y = a.x + 8, a.y + 8
    a.dark = dark(self)
    a.oam = M.OAM[a.dark and 1 or 0]
    a.subtype = 0
    a.untouchable = true
  elseif t == 0x7B or t == 0xBF then
    a.untouchable, a.noTouch = true, true
  elseif t == 0xC1 then
    a.untouchable, a.noTouch = true, true
    if M._zelda then a.A = 1 return end
    -- SpritePrep_CutsceneAgahnim (dung_savegame_state_bits 0x4000)
    if self.inside.mem and self.inside.mem.agahnimGone then a.dead = true return end
    a.A = 0
    -- CutsceneAgahnim_SpawnZeldaOnAltar
    a.x, a.y = a.x + 8, a.y + 6
    M._zelda = true
    local z = D().spawn(self, 0xC1, a.x, a.y + 40, a.lower)
    M._zelda = nil
    z.A, z.z = 1, 0
    a.zelda = z
  end
end

-- ------------------------------------------------------------ helpers
local function mainOf(self)
  for _, b in ipairs(self.list) do if b.type == 0x7A and b.slot == 0 and not b.dead then return b end end
end

-- Agahnim_PerformAttack
local function attack(self, a, lk)
  local tb = T(self.game)
  local d = D()
  if a.slot == 0 then
    a.subtype = (a.subtype or 0) + 1
    if a.dark then a.subtype = band(a.subtype, 3) end
  end
  if (a.subtype or 0) == 5 then
    a.subtype = 0
    for _ = 1, 4 do
      -- Sprite_SpawnLightning
      local i = band(d.rnd(self), 7)
      local b = d.spawn(self, 0xBF, a.x + tb.ltX[i + 1], a.y + 12, a.lower)
      b.A, b.delay = i, 2
      self.game.agLightning = (self.game.agLightning or 0) + 1
    end
  else
    local i = a.D or 0
    local b = d.spawn(self, 0x7B, a.x + tb.x0[i + 1], a.y + tb.y0[i + 1], a.lower)
    b.vx, b.vy = a.vx or 0, a.vy or 0
    b.ai, b.A, b.B = 0, 0, 0
    if (a.subtype or 0) >= 2 and band(d.rnd(self), 1) == 0 then b.B, b.delay = 1, 32 end
    self.game.agBalls = (self.game.agBalls or 0) + 1
  end
end
M.attack = attack

-- PrepareDungeonExitFromBossFight (room 0x20): the hand-off to the pyramid
function M.exitFromBoss(game)
  local p = game.progress
  p.bossBeaten = p.bossBeaten or {}
  local room = game.interior and game.interior.room
  if room then p.bossBeaten[room] = true end
  if room == 0x20 then
    p.agahnim1 = true
    p.sramProgress = 3                    -- sram_progress_indicator 3
    game.stats.health = game.stats.healthMax or game.stats.health   -- BossVictory_Heal
    game.agahnimWarps = (game.agahnimWarps or 0) + 1
    if game.leaveRoom then game:leaveRoom() end
  end
end

-- the kill branch for 0x7A (Sprite_CheckDamageFromLink)
local function kill(self, a)
  -- Sprite_KillFriends
  for _, b in ipairs(self.list) do
    if b ~= a and not b.dead and not (b.type == 0x7A and b.clone) and b.type ~= 0xEA then b.dead = true end
  end
  a.untouchable, a.noTouch = true, true
  a.recoil, a.pend, a.inv = nil, nil, 0
  if not a.dark then
    a.ai, a.delay, a.vz = 10, 255, 32
    a.zsub, a.sub2 = 0, 0
  else
    a.delay, a.ai = 255, 8
    for _, b in ipairs(self.list) do
      if b.type == 0x7A and b.clone and not b.dead then b.ai, b.gfx = 9, 0 end
    end
  end
  self.game.agahnimDown = (self.game.agahnimDown or 0) + 1
end

-- ------------------------------------------------------------ Agahnim
local function agahnim(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  -- damage taken at hit timer 24 (ours: before the shared code's, so the
  -- kill branch replaces the death puff)
  if a.inv == 24 and a.pend then
    a.hp = (a.hp or 0) - a.pend
    a.pend = nil
    if a.hp <= 0 then kill(self, a) end
  end
  if a.recoil and a.ai ~= 10 and a.ai ~= 8 and self:recoilStep(a) then return end
  local ai = a.ai or 0
  a.untouchable = true
  if ai == 0 then
    a.ai = tb.startState[(a.dark and 1 or 0) + 1]
  elseif ai == 1 then
    if a.delay == 0 then
      game:showMessage(M.MSG_TOWER)
      a.ai, a.delay = 3, 32
    end
  elseif ai == 2 then
    if a.delay == 0 then a.ai, a.delay = 3, 255
    else a.gfx = tb.gfx0[rshift(a.delay, 3) + 1] or a.gfx end
  elseif ai == 3 then
    local j = a.delay
    if not (j >= 239 or j < 16) and a.slot == 0 then a.untouchable = false end
    if a.delay == 0 then a.ai, a.delay = 4, 39 return end
    if a.delay >= 128 then
      local vx, vy = d.towardsLink(a, lk, 2)
      a.D = tb.dir[(vy + 2) * 5 + 2 + vx + 1] or a.D
      a.vx, a.vy = d.towardsLink(a, lk, 32)
      if a.subtype == 4 then a.D = 3 end
    elseif a.delay == 112 then
      attack(self, a, lk)
    end
    j = rshift(a.delay, 4)
    a.A = tb.tab0[j + 1]
    local t = tb.tab1[j + 1]
    a.headDir = (t ~= 0) and (t + tb.tab2[(a.D or 0) + 1]) or 0
    a.gfx = tb.gfx1[(a.D or 0) + 1] + a.A
  elseif ai == 4 then
    if a.delay == 0 then
      a.ai = 5
      local j = (a.subtype == 4) and 4 or band(d.rnd(self), 15)
      a.C, a.E, a.G = tb.tab3[j + 1], tb.tab4[j + 1], 8
    else
      a.gfx = tb.gfx2[rshift(a.delay, 3) + 1] or a.gfx
    end
  elseif ai == 5 then
    local xl, yl = band(a.x, 0xFF), band(a.y, 0xFF)
    if band(xl - a.C + 7, 0xFFFF) < 14 and band(yl - a.E + 7, 0xFFFF) < 14 then
      a.x, a.y = a.x - xl + a.C, a.y - yl + a.E
      a.ai, a.delay = 2, 39
      return
    end
    local tx, ty = a.x - xl + a.C, a.y - yl + a.E
    a.vx, a.vy = require("src.zelda.alttp.Actors").project(a.x, a.y, tx, ty, a.G)
    if a.G < 64 then a.G = a.G + 1 end
    H().moveXY(a)
  elseif ai == 6 then
    if a.delay == 0 then
      game:showMessage(M.MSG_GT)
      a.ai, a.delay = 7, 80
    end
  elseif ai == 7 then
    if a.clone then
      if a.delay == 0 then a.ai, a.delay = 3, 32
      else
        a.vx = tb.tab5[a.slot]
        a.vy = (a.vy or 0) + 2
        H().moveXY(a)
      end
    else
      if a.delay == 0 then a.ai, a.delay = 3, 32
      elseif a.delay == 64 then
        for slot = 1, 2 do
          M._clone = { slot = slot, oam = band(tb.tab6[slot], 15) }
          local c = d.spawn(self, 0x7A, a.x, a.y, a.lower)
          M._clone = nil
          c.ai, c.delay, c.dark, c.subtype, c.gfx = a.ai, 32, true, 0, a.gfx
          c.vx, c.vy = 0, 0
          c.untouchable = true
        end
        game.agClones = (game.agClones or 0) + 2
      end
    end
  elseif ai == 8 then
    a.headDir = 0
    if a.delay < 64 then
      if a.delay == 1 then
        -- Sprite_SpawnPhantomGanon (not ported: the hand-off flag)
        game.progress.agahnim2 = true
        game.phantomGanon = true
      end
      a.gfx = 17
    end
  elseif ai == 9 then
    a.headDir = 0
    local m = mainOf(self)
    if not m then a.dead = true return end
    if band(a.x - m.x + 4, 0xFFFF) < 8 and band(a.y - m.y + 4, 0xFFFF) < 8 then a.dead = true return end
    a.vx, a.vy = require("src.zelda.alttp.Actors").project(a.x, a.y, m.x, m.y, 0x20)
    H().moveXY(a)
  elseif ai == 10 then
    if a.delay == 0 then
      a.dead = true
      M.exitFromBoss(game)
      return
    end
    if a.vz ~= 0xFF then a.vz = a.vz + 1 end
    local j = (a.zsub or 0) + a.vz
    a.zsub = band(j, 0xFF)
    if band(j, 0x100) ~= 0 then
      a.sub2 = (a.sub2 or 0) + 1
      if a.sub2 == 7 then a.sub2 = 0 end
    end
    a.gfx = tb.gfx3[(a.sub2 or 0) + 1]
  end
end

-- ------------------------------------------------------------ the balls
local function sixBalls(self, a)
  local tb = T(self.game)
  for i = 5, 0, -1 do
    local f = D().spawn(self, 0x55, a.x + 4, a.y + 4, a.lower)
    f.fire, f.aux1 = true, 4
    f.vx, f.vy = tb.splitXv[i + 1], tb.splitYv[i + 1]
    f.bump = 1
  end
  self.game.agSplits = (self.game.agSplits or 0) + 1
end

local function ball(self, a, lk)
  local tb = T(self.game)
  local d = D()
  if (a.B or 0) ~= 0 then
    if (a.delay or 0) ~= 0 and (a.ai or 0) == 0 then a.vx, a.vy = d.towardsLink(a, lk, 32) end
    a.oamF = 5
  else
    a.oamF = band(rshift(self.frame, 1), 2) + 3
  end
  if (a.ai or 0) ~= 0 then
    if (a.delay or 0) == 0 then a.dead = true return end
    if a.delay == 6 then a.vx, a.vy = 64, 64; H().moveXY(a) end
    a.gfx = tb.ballGfx[a.delay + 1] or 0
    return
  end
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  H().moveXY(a)
  if H().tileCollision(self, a) ~= 0 then
    a.dead = true
    if (a.B or 0) ~= 0 then sixBalls(self, a) end
    return
  end
  local m = mainOf(self)
  if (a.A or 0) ~= 0 and m and not m.untouchable then
    -- the returned ball on Agahnim (slot 0)
    local cb = d.cbOf(self)
    local A = require("src.zelda.alttp.Actors")
    local hx, hy, hw, hh = A.hitbox(cb, m)
    if A.overlapCart(a.x, a.y, 15, 15, hx, hy - (m.z or 0), hw, hh) then
      -- Sprite_GiveDamage(0, 16, 0xA0)
      m.pend = math.max(m.pend or 0, 16)
      m.inv = 0xA0
      m.recoil, m.rvx, m.rvy, m.subx, m.suby = 15, a.vx or 0, a.vy or 0, 0, 0
      a.dead = true
      self.game.agReturnHits = (self.game.agReturnHits or 0) + 1
      return
    end
  elseif (a.A or 0) == 0 then
    d.contact(self, a, lk)
  end
  if band(bxor(a.k or 0, self.frame), 3) ~= 0 or (a.B or 0) ~= 0 then return end
  local tr = d.spawn(self, 0x7B, a.x, a.y, a.lower)
  tr.delay, tr.ai, tr.B = 15, 15, a.B
end

-- the sword on a ball (Sprite_CheckDamageFromLink carry)
function M.swordBalls(actors, x, y, w, h, how)
  if not (how and how.sword) then return 0 end
  local n = 0
  local cb = D().cbOf(actors)
  local A = require("src.zelda.alttp.Actors")
  local lk = actors.game.link
  for _, a in ipairs(actors.list or {}) do
    if a.type == 0x7B and not a.dead and (a.ai or 0) == 0 and (a.retT or 0) == 0 then
      local hx, hy, hw, hh = A.hitbox(cb, a)
      if A.overlapCart(x, y, w, h, hx, hy, hw, hh) then
        n = n + 1
        if (a.B or 0) ~= 0 then
          a.dead = true
          sixBalls(actors, a)
        else
          local vx, vy = D().towardsLink(a, lk, 0x30)
          a.vx, a.vy = -vx, -vy
          a.A = (a.A or 0) + 1
          a.retT = 8           -- (ours: one return per swing)
          actors.game.agReturns = (actors.game.agReturns or 0) + 1
        end
      end
    end
  end
  return n
end

-- ------------------------------------------------------------ lightning
local function lightning(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  if a.trail then
    if (a.delay or 0) == 0 then a.dead = true return end
    -- Garnish_CheckPlayerCollision
    if band(bxor(a.k or 0, self.frame), 7) == 0 and (game.blink or 0) == 0 and not game.pitFall then
      if band(lk.x - a.x + 12, 0xFF) < 24 and band(lk.y - a.y + 22, 0xFF) < 28 then
        game:hurtLink(16, a.x + 8, a.y + 8)
        game.agZaps = (game.agZaps or 0) + 1
      end
    end
    return
  end
  local j = a.A or 0
  a.flipF = tb.ltFlags[j + 1]
  a.gfx = tb.ltGfx[j + 1] + ((self.inside.room == 0x20) and 4 or 0)
  if (a.delay or 0) ~= 0 then return end
  -- Lightning_SpawnGarnish
  M._trail = true
  local tr = d.spawn(self, 0xBF, a.x, a.y + 16, a.lower)
  M._trail = nil
  tr.trail, tr.delay, tr.A = true, 32, a.A
  a.delay = 2
  a.y = a.y + 16
  local cy = 0
  if self.inside.camera then cy = select(2, self.inside:camera(lk.x, lk.y, 256, 256)) end
  if band(a.y - cy, 0xFF) >= 0xD0 then a.dead = true return end
  local rr = band(d.rnd(self), 7)
  a.x = a.x + tb.ltXoff[lshift(a.A or 0, 3) + rr + 1]
  a.A = rr
end

-- ------------------------------------------------------------ the cutscene
local function cutscene(self, a, lk)
  local game = self.game
  if a.A == 1 then
    -- Sprite_CutsceneAgahnim_Zelda: the warp ends her
    if (a.delay or 0) ~= 0 and a.delay == 1 then a.dead = true end
    return
  end
  local z = a.zelda
  local ai = a.ai or 0
  if ai == 0 then
    if a.delay == 0 then
      game.agHold = true                                  -- flag_is_link_immobilized
      game:showMessage(M.MSG_ALTAR1)
      a.ai = 1
    end
  elseif ai == 1 then
    a.B = band((a.B or 0) + 1, 0xFF)
    local LEV = { [0] = 2, 0, 3, 0 }                      -- kChattyAgahnim_LevitateGfx
    a.gfx = (z and (z.z or 0) < 16) and LEV[band(rshift(a.B, 5), 3)] or 1
    if band(a.B, 15) == 0 and z then
      z.gfx = 1
      z.z = (z.z or 0) + 1
      if z.z == 22 then a.ai, a.delay = 2, 255 end
    end
  elseif ai == 2 then
    if a.delay == 0 then a.ai, a.delay = 3, 80 end
  elseif ai == 3 then
    if a.delay == 0 then
      if z then z.delay = 19 end
      a.ai, a.delay = 4, 80
    end
  elseif ai == 4 then
    if a.delay == 0 then
      game:showMessage(M.MSG_ALTAR2)
      a.ai, a.delay = 5, 2
    end
  elseif ai == 5 then
    a.vy = -32
    a.vx = 0
    H().moveXY(a)
    if band(a.y, 0xFF) < 48 then a.aux4, a.ai = 66, 6 end
  elseif ai == 6 then
    if (a.aux4 or 0) == 0 then
      game.agHold = nil
      a.dead = true
      self.inside.mem.agahnimGone = true                  -- dung_savegame_state_bits 0x4000
      game.agAltarDone = (game.agAltarDone or 0) + 1
    end
  end
end

function M.update(self, a, lk)
  local t = a.type
  if a.retT and a.retT > 0 then a.retT = a.retT - 1 end
  if t == 0x7A then return agahnim(self, a, lk)
  elseif t == 0x7B then return ball(self, a, lk)
  elseif t == 0xBF then return lightning(self, a, lk)
  elseif t == 0xC1 then return cutscene(self, a, lk)
  end
end

function M.swordImmune() return false end
function M.died() end

-- ------------------------------------------------------------ drawing
local function singleChar(spr, t, g) return spr.info.single2[(spr.info.single1[t + 1] or 0) + (g or 0) + 1] end

function M.draw(spr, a, x, y, frame, game)
  local tb = (game and T(game)) or (spr.data.t and spr.data.t.d26 and spr.data.t.d26.agahnim)
  if not tb then return false end
  local t = a.type
  local fr = frame or 0
  if t == 0x7A then
    if a.ai == 8 and (a.delay or 0) >= 64 and band(fr, 2) ~= 0 then return true end   -- (hit flash)
    local g = a.gfx or 0
    local f = a.oam or 11
    -- the spell (head_dir) behind the body (OAM region B / C)
    local hd = a.headDir or 0
    if hd ~= 0 then
      local j = hd - 1
      local fl = band(rshift(fr, 1), 2) + 2 + 0x31
      for i = 1, 0, -1 do
        spr:oam(x + tb.drawX1[j * 2 + i + 1], y + tb.drawY1[j * 2 + i + 1], tb.char1[j + 1], fl, tb.big1[j + 1])
      end
    end
    for i = 3, 0, -1 do
      local j = g * 4 + i
      if tb.char0[j + 1] then
        spr:oam(x + tb.drawX0[j + 1], y + tb.drawY0[j + 1], tb.char0[j + 1], bor(f, tb.flags0[j + 1]),
                (j >= 0x40 and j < 0x44) and 0 or 2)
      end
    end
  elseif t == 0x7B then
    local f = a.oamF or 3
    if (a.ai or 0) == 0 and (a.B or 0) ~= 0 then
      spr:drawDmd(a, tb.ballDmd, band(rshift(a.sub2 or 0, 2), 1) * 4, 4, x, y, f)
    else
      local g = a.gfx or 0
      local ch = singleChar(spr, t, g)
      if ch then spr:oam(x, y, ch, f, (g == 2) and 0 or 2) end
    end
  elseif t == 0xBF then
    local ff = band(spr.info.flags3[t + 1] or 0, 0x0F)
    if a.trail then
      local j = a.A or 0
      local room = game and game.interior and game.interior.room
      local ch = band(tb.trailChar[j + 1] + ((room == 0x20) and 0x80 or 0), 0xFF)
      spr:oam(x, y, ch, bor(band(lshift(fr, 1), 0x0E), tb.trailFlags[j + 1]), 2)
    else
      local ch = singleChar(spr, t, a.gfx)
      local fl = bor(band(ff, 0xB1), a.flipF or 0, band(lshift(fr, 1), 0x0E))
      if ch then spr:oam(x, y, ch, fl, 2) end
    end
  elseif t == 0xC1 then
    if a.A == 1 then
      if (a.delay or 0) ~= 0 and a.delay < 12 then return true end
      spr:drawDmd(a, tb.altarDmd, (a.gfx or 0) * 2, 2, x, y - (a.z or 0), 12)
    else
      if band(a.aux4 or 0, 1) ~= 0 then return true end
      spr:drawDmd(a, tb.chattyDmd, (a.gfx or 0) * 4, 4, x, y, 0)
    end
  else
    return false
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  local Act = require("src.zelda.alttp.Actors")
  local sh0 = Act.swordHit
  function Act:swordHit(x, y, w, h, how)
    local n = M.swordBalls(self, x, y, w, h, how)
    return sh0(self, x, y, w, h, how) + n
  end
  -- flag_is_link_immobilized during the altar cutscene
  local Doors = require("src.zelda.alttp.Doors")
  local move0 = Doors.move
  function Doors.move(g, inp)
    if g.agHold then local lk = g.link; lk.moving, lk.steps = false, 0; return end
    return move0(g, inp)
  end
end

return M
