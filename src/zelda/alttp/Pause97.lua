-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 97: indoor sprites pause off screen (Sprite_PrepOamCoord's
-- sprite_pause + Sprite_ReturnIfInactive).
--
-- Traced on the GBA: Sprite_PrepOamCoordOrDoubleRet (0x080C5ACC) first
-- clears sprite_pause (+0x10D2, `ldr =0x10D2` + strb 0), then compares the
-- sprite's x - camera + 0x40 (`adds r2, #0x40`) against 0x016F0000 (the
-- halfword shifted up: > 0x16F) and the same for y - z; off the screen it
-- sets sprite_pause. Sprite_ReturnIfInactive (0x080C3468) returns 1 when
-- +0x1605 / +0x9AD are set or when sprite_pause is set and the deflection
-- bits (+0xE75) lack 0x80; Sprite_ReturnIfInactive's state-checking twin
-- (0x080C3438) tests sprite_state == 9 first. Sprite_TimersAndOam runs
-- before the routine either way: the timers keep counting.
-- So almost every room sprite stands still while it is more than 0x40 px
-- off the 240 x 160 screen: the Lanmolas (Sprite_54: 0x080EFC74 calls the
-- prep wrapper 0x080C632C, Lanmola_Draw, then 0x080C3468; Lanmola_Wait
-- 0x080EFCF0 also waits while sprite_pause is set) and the Medusa
-- (Sprite_C5 0x080F5364: no fireball count while paused) of Ganon's Tower
-- 0x6C woke and fired from the next quadrant in the port.
--
-- Which sprites: at import every main routine of the sprite table (0x08174138,
-- one word per type) is walked (its `bl`s, two calls deep, until `pop {pc}` /
-- `bx lr`): a type pauses when its first call that reaches 0x080C5ACC is
-- followed by a call to Sprite_ReturnIfInactive (directly or one call in).
-- Types the port runs by other code paths (guards, followers, shop, keys)
-- and the Goriyas (Goriya95) are left alone: only the palace-family sprites
-- (Palace.update and its registered modules) are paused here.
-- OURS: a headless game (no screen: the unit tests' stand-in rooms) does not
-- pause; the port's camera (Interior:camera, the GBA's 240 x 160) stands in
-- for BG2HOFS / BG2VOFS; a paused sprite's palace timers (delay, aux1-4) and
-- hit timer still count (Sprite_TimersAndOam).

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local M = { NAME = "pause97" }

M.SITES = { prep = 0x080C5ACC, rii = 0x080C3468, rii9 = 0x080C3438, table = 0x08174138,
            ripPause = 0x080C3496, riiDefl = 0x080C3486, riiMask = 0x080C348E,
            prepPause = 0x080C5AE8, prepAdd = 0x080C5B1C, prepCmp = 0x080C5B20 }
M.TYPES = 0xF3

local function off(a) return a - 0x08000000 end
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end

-- the `bl` targets of the code at a (bytes a .. a + 2n), until pop {.., pc} / bx lr
function M.calls(rom, a, n)
  local out = {}
  local o, e = off(a), off(a) + 2 * n
  while o + 2 <= e do
    local h = rom:u16(o)
    if band(h, 0xF800) == 0xF000 and o + 4 <= e then
      local h2 = rom:u16(o + 2)
      if band(h2, 0xF800) == 0xF800 then
        local v = bor(lshift(band(h, 0x7FF), 12), lshift(band(h2, 0x7FF), 1))
        if v >= 0x400000 then v = v - 0x800000 end
        out[#out + 1] = 0x08000000 + o + 4 + v
        o = o + 4
      else
        o = o + 2
      end
    else
      if band(h, 0xFF00) == 0xBD00 or h == 0x4770 then break end
      o = o + 2
    end
  end
  return out
end

-- the import's walk (see the header)
function M.scan(rom, S)
  S = S or M.SITES
  local RII = { [S.rii] = true, [S.rii9] = true }
  local memo = {}
  local function reachPrep(a, d)
    if a == S.prep then return true end
    if d == 0 or RII[a] then return false end
    local k = a * 8 + d
    if memo[k] ~= nil then return memo[k] end
    memo[k] = false
    local r = false
    for _, c in ipairs(M.calls(rom, a, 90)) do if reachPrep(c, d - 1) then r = true break end end
    memo[k] = r
    return r
  end
  local function reachRii(a, d)
    if RII[a] then return true end
    if d == 0 then return false end
    for _, c in ipairs(M.calls(rom, a, 90)) do if reachRii(c, d - 1) then return true end end
    return false
  end
  local types = {}
  for t = 0, M.TYPES - 1 do
    local m = band(rom:u32(off(S.table) + 4 * t), bit.bnot(1))
    if m >= 0x08000000 and m < 0x08000000 + (rom.data and #rom.data or 0x2000000) then
      local seq = M.calls(rom, m, 160)
      for i, c in ipairs(seq) do
        if RII[c] then break end
        if reachPrep(c, 3) then
          for j = i + 1, #seq do
            if RII[seq[j]] or reachRii(seq[j], 2) then types[t] = true break end
          end
          break
        end
      end
    end
  end
  return types
end

function M.extract(rom, R, check)
  local S = M.SITES
  -- shapes: the prep clears / sets +0x10D2 and compares (v + 0x40) << 16 against 0x016F0000;
  -- Sprite_ReturnIfInactive reads +0xE75 & 0x80 and +0x10D2
  local pauseOff, cmpv = lit(rom, S.prepPause), lit(rom, S.prepCmp)
  local addh = rom:u16(off(S.prepAdd))
  local deflOff, ripOff = lit(rom, S.riiDefl), lit(rom, S.ripPause)
  local maskh = rom:u16(off(S.riiMask))
  local ok = pauseOff == 0x10D2 and ripOff == 0x10D2 and deflOff == 0xE75 and cmpv ~= nil
             and band(addh, 0xFF00) == 0x3200 and band(maskh, 0xFF00) == 0x2000
  check(ok, "pause97: prep / return-if-inactive shapes")
  if not ok then return {} end
  local t = { margin = band(addh, 0xFF), span = rshift(cmpv, 16) + 1, defl = band(maskh, 0xFF), types = {} }
  local ty = M.scan(rom, S)
  local n = 0
  for k in pairs(ty) do t.types[#t.types + 1] = k; n = n + 1 end
  table.sort(t.types)
  check(n > 100 and ty[0x54] and ty[0xC5] and ty[0x55], "pause97: the pausing sprite types")
  return t
end

local function tabs(game) return game and game.data and game.data.t and game.data.t.pause97 end
M.tabs = tabs

-- the set of types (built once per table)
local sets = setmetatable({}, { __mode = "k" })
local function setOf(T)
  local s = sets[T]
  if not s then
    s = {}
    for _, k in ipairs(T.types or {}) do s[k] = true end
    sets[T] = s
  end
  return s
end
M.setOf = setOf

-- Sprite_PrepOamCoordOrDoubleRet's test: (x - cx + margin) & 0xFFFF and (y - z - cy + margin) & 0xFFFF >= span
function M.offscreen(T, a, cx, cy)
  local sx = band(a.x - cx + T.margin, 0xFFFF)
  local sy = band(a.y - (a.z or 0) - cy + T.margin, 0xFFFF)
  return sx >= T.span or sy >= T.span
end

-- whether this sprite stands still this frame (the caller skips its routine)
function M.paused(actors, a, cx, cy)
  local game = actors.game
  local T = tabs(game)
  if not T or game.headless or not a.palace or a.type == 0x83 or a.type == 0x84 then return false end
  if not setOf(T)[a.type] then return false end
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if cb and cb.deflBits and band(cb.deflBits[a.type + 1] or 0, T.defl) ~= 0 then return false end
  return M.offscreen(T, a, cx, cy)
end

-- the paused frame: the timers only (Sprite_TimersAndOam)
function M.tick(a)
  for _, k in ipairs({ "delay", "aux1", "aux2", "aux3", "aux4" }) do
    if (a[k] or 0) > 0 then a[k] = a[k] - 1 end
  end
  if a.inv and a.inv > 0 then
    a.inv = a.inv - 1
    if a.inv == 0 then a.invSword = nil end
  end
end

function M.install(G)
  if G.pause97Installed then return end
  G.pause97Installed = true
  local A = require("src.zelda.alttp.Actors")
  -- Actors:update asks this before a live sprite's routine
  function A:pause97(a, cx, cy)
    if M.paused(self, a, cx, cy) then
      M.tick(a)
      a.paused97 = true
      self.game.paused97 = (self.game.paused97 or 0) + 1
      return true
    end
    a.paused97 = nil
    return false
  end
end

return M
