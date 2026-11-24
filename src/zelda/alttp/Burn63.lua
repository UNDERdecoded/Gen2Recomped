-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 63: the burn (damage code 0xFD: the Fire Rod / Bombos on a Gibdo
-- and the other sprites whose damage table gives 0xFD).
--
-- The port held every code 251-255 as a 64-frame stun (Tools.spriteHit);
-- on the cartridge 0xFD sets the sprite on fire: Skull Woods 0x59's Gibdos
-- (32 hp, 4 a sword swing) die to one Fire Rod shot.
--
-- GBA, read at import from the code below:
--   * Sprite_ApplyCalculatedDamage 0x080C414C keeps the code in
--     sprite_give_damage (+0xEB5); the hit-timer step 0x080C2160 (sprite
--     state > 8): `cmp r0, #n` 0x080C2190 (the burn code) -> sound
--     `movs r1, #n` 0x080C2196 (sprite pan 0x080CF140), sprite_state = 7
--     (`movs r0, #n` 0x080C219C), sprite_delay_main = `movs r1, #n`
--     0x080C21A6, flags2 += 2, the damage cleared;
--   * the module table (literal 0x080C33E2) entry 7 = SpriteModule_Burn
--     0x080CA688: sprite_hit_timer = 0; at delay `cmp r0, #n` 0x080CA6B6
--     the death and its drop (0x080C6DA8 -> 0x080C6818, no death puff);
--     while delay > `cmp r0, #n` 0x080CA6DC the sprite's own routine runs
--     (0x080C33FC: the active table by type), so it keeps moving; the
--     flames: sprite_graphics = kBurn_Gfx[delay >> 3] (literal 0x080CA712),
--     its OAM flags `movs r0, #n` 0x080CA720 for the draw 0x080F2410:
--     Sprite_DrawMultiple(k, table (literal 0x080F2422) + gfx * 16, 2):
--     two entries of {x16, y16, char, flags, 0, ext}.
--
-- OURS: below the threshold the sprite's routine is held by putting it back
-- where it stood and keeping it from touching Link (its timers still run);
-- the sprite and its shadow are not drawn then.

local M = {}

local bit = require("bit")
local band, bor = bit.band, bit.bor

M.HIT_FN = 0x080C2160
M.BURN_FN = 0x080CA688
M.SITES = {
  code = 0x080C2190, snd = 0x080C2196, state = 0x080C219C, delay = 0x080C21A6,
  modLit = 0x080C33E2, dieAt = 0x080CA6B6, showAbove = 0x080CA6DC,
  gfxLit = 0x080CA712, flags = 0x080CA720, oamLit = 0x080F2422,
}

-- ------------------------------------------------------------ import
function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function imm(at, want)
    local v, form = RT.codeImm(rom, at)
    if want and form ~= want then return nil end
    return v
  end
  local t = {}
  t.code = imm(S.code, "cmp")
  t.snd = imm(S.snd, "movs")
  t.state = imm(S.state, "movs")
  t.delay = imm(S.delay, "movs")
  t.dieAt = imm(S.dieAt, "cmp")
  t.showAbove = imm(S.showAbove, "cmp")
  t.flags = imm(S.flags, "movs")
  local mods = imm(S.modLit, "ldr")
  local entry = mods and t.state and rom:u32(mods - 0x08000000 + t.state * 4)
  local gfx, oam = imm(S.gfxLit, "ldr"), imm(S.oamLit, "ldr")
  t.gfx = {}
  if gfx and t.delay then
    for i = 0, math.floor(t.delay / 8) do t.gfx[i] = rom:u8(gfx - 0x08000000 + i) end
  end
  local nf = 0
  for _, v in pairs(t.gfx) do nf = math.max(nf, v + 1) end
  t.oam = {}
  if oam then
    for f = 0, nf - 1 do
      local list = {}
      for e = 0, 1 do
        local o = oam - 0x08000000 + f * 16 + e * 8
        local x, y = rom:u16(o), rom:u16(o + 2)
        if x >= 0x8000 then x = x - 0x10000 end
        if y >= 0x8000 then y = y - 0x10000 end
        list[#list + 1] = { x = x, y = y, char = rom:u8(o + 4), flags = rom:u8(o + 5), big = band(rom:u8(o + 7), 2) }
      end
      t.oam[f] = list
    end
  end
  check(t.code == 0xFD and t.snd and t.state and entry == M.BURN_FN + 1 and t.delay and t.delay >= 0x10
        and t.dieAt and t.showAbove and t.showAbove < t.delay and t.flags and nf > 0 and t.oam[nf - 1] ~= nil,
        "burn tables (code %s, delay %s)", tostring(t.code), tostring(t.delay))
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.burn63 end
M.tab = tab

-- ------------------------------------------------------------ the burn
-- set a sprite on fire (the hit-timer step's 0xFD branch)
function M.start(game, s)
  local t = tab(game)
  if not t or s.dead or s.burn then return false end
  s.burn = t.delay
  s.recoil, s.stunned, s.pend, s.inv, s.invSword = nil, nil, nil, 0, nil
  game.burns63 = (game.burns63 or 0) + 1
  if t.snd then pcall(function() require("src.zelda.alttp.Sfx").start(game, t.snd, "burn") end) end
  return true
end

-- the damage a class gives a sprite type is the burn code
function M.isBurn(game, cls, ty)
  local t = tab(game)
  if not (t and cls) then return false end
  return require("src.zelda.alttp.Items").damage(game, cls, ty) == t.code
end

-- one frame of SpriteModule_Burn before the sprites run; returns the
-- sprites held this frame (to put back after)
function M.before(actors)
  local game = actors.game
  local t = tab(game)
  if not t then return nil end
  local held
  for _, a in ipairs(actors.list) do
    if a.burn and not a.dead then
      a.burn = a.burn - 1
      a.inv, a.pend, a.recoil, a.stunned = 0, nil, nil, nil   -- sprite_hit_timer = 0
      if a.burn <= t.dieAt then
        -- 0x080C6818: the death and its drop, no puff (the flames were it)
        a.dead, a.burn = true, nil
        actors:died(a)
        if a.drop and actors.inside then
          actors.inside.mem.taken[a.index] = true
          actors.list[#actors.list + 1] = { type = require("src.zelda.alttp.Actors").KEY, x = a.x, y = a.y,
                                            lower = a.lower, big = a.drop == 2, t = 0, index = -1 }
        end
        game.burnDeaths63 = (game.burnDeaths63 or 0) + 1
      elseif a.burn <= t.showAbove then
        held = held or {}
        held[#held + 1] = { a = a, x = a.x, y = a.y, u = a.untouchable }
        a.untouchable = true
      end
    end
  end
  return held
end

function M.after(held)
  for _, h in ipairs(held or {}) do
    h.a.x, h.a.y, h.a.untouchable = h.x, h.y, h.u
  end
end

-- the flames (0x080F2410) at the sprite's screen spot
function M.drawFlames(spr, t, a, x, y)
  local f = t.gfx[math.floor(a.burn / 8)] or 0
  for _, e in ipairs(t.oam[f] or {}) do
    spr:oam(x + e.x, y - (a.z or 0) + e.y, e.char, bor(e.flags, t.flags), e.big)
  end
end

-- ------------------------------------------------------------ install
function M.install(G)
  if G.burn63Installed then return end
  G.burn63Installed = true
  local TL = require("src.zelda.alttp.Tools")
  local sh0 = TL.spriteHit
  function TL.spriteHit(game, a, cls, box)
    local st0 = game.toolStuns or 0
    local s = sh0(game, a, cls, box)
    if s and (game.toolStuns or 0) > st0 and M.isBurn(game, cls, s.type) and M.start(game, s) then
      game.toolStuns = st0
    end
    return s
  end
  local A = require("src.zelda.alttp.Actors")
  local up0 = A.update
  function A:update()
    local held = M.before(self)
    local r = up0(self)
    M.after(held)
    return r
  end
  local Spr = require("src.zelda.alttp.Sprites")
  local da0 = Spr.drawActor
  function Spr:drawActor(a, x, y, frame, room)
    if not a.burn then return da0(self, a, x, y, frame, room) end
    local t = M.tab({ data = self.data })
    local r
    if not t or a.burn > t.showAbove then r = da0(self, a, x, y, frame, room) end
    if t then M.drawFlames(self, t, a, x, y) end
    return r
  end
end

return M
