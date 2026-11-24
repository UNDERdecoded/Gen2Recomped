-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SOUND EFFECTS (round 32). What is ported: the cartridge's own chain from a
-- game event to the sound it starts, read at import; what is NOT: the
-- synthesizer (no sound is heard yet -- see PROGRESS-alttp.md round 32).
--
-- THE CHAIN on the GBA:
--   call site       `movs r0/r1, #id` + bl to a wrapper (Ancilla_Sfx2_Near
--                   0x0809E43C, Sfx3_Near 0x0809E49C, ancilla pan 0x080C19F8
--                   (id in r1), Link pan 0x080C1A8C, sprite pan 0x080CF018 /
--                   0x080CF0AC / 0x080CF140 (id in r1), 0x080CF1D4) or the
--                   player itself 0x0812A324. Ids are the GBA's own numbers,
--                   per call site; tables give some (the sword's 0x16809E,
--                   kAbsorptionSfx 0x173034, the debris 0x1720BC).
--   play-by-id      0x0812A324: the u32 table 0x198C94 (133 ids): low 16 bits
--                   = the sound number, bits 16-23 = the channel, bit 27 = a
--                   variant sound (+1 / +2 for the second / third start of a
--                   frame: counter 0x03000105), bit 28 / 25 = priority rules
--                   against what the channel plays (0x030000C8 holds it).
--   sound command   0x0812C73C queues command 1 (channel, sub-bank 0, number)
--                   in a ring (0x030003C0); 0x0812CC24 runs the ring through
--                   the handler table 0x198EC8; 0x0812C494 looks the number
--                   up in the sound bank 0x198C30 (+0x0C: sub-bank offsets;
--                   sub-bank 0 = the 142 sound effects, u16 offsets from its
--                   base) and starts the sequence (0x0812C548 / 0x0812BD50).
--
-- THIS IS NOT M4A. The cartridge's MusicPlayer2000 song table (0x3C3BBC, 545
-- songs, Extract.readMusic) is the Four Swords half's bank: its song n is a
-- different sound from the ALttP bank's sound n (the ALttP bank's 19 / 20 / 21
-- are one swing in three variants; the m4a songs 19 / 20 / 21 are unrelated,
-- and many of the numbers the id table names are empty m4a songs). So the
-- engine's M4A synth cannot play these.
--
-- The sequence format (0x0812BE54, read for the walker below):
--   00-5F  note (key 00-5F), last length / velocity
--   60-BF  note (key - 0x60), varlen length (0x0812C30C: 1 byte, or 2 with
--          bit 7), velocity byte
--   C0     rest, last length          C1  rest, varlen length
--   Dx     slide: 2 bytes (+1 when x & 1)
--   C2-FF  table 0x0812BF98: C2 instrument, C3, C4, C7 instrument set, CA,
--          E0-E3, E5-E7, E9, EA = 1 byte; E4 = varlen (tempo); F0 jump /
--          F4 call = u16 offset from the sub-bank base; F8 = open track
--          (track byte + u16 offset); FF = return / end; the rest none.

local M = {}

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

M.OFF = {
  idTable = 0x198C94, idCount = 133,
  bank = 0x198C30,
  sword = 0x16809E,    -- u16 x 4, by sword level 1-4
  absorb = 0x173034,   -- kAbsorptionSfx: u8 x 15, sprite types 0xD8-0xE6
  debris = 0x1720BC,   -- kSprite_Func21_Sfx: u8 x 16 (bush / pot shatter)
}

-- event -> the `movs` instruction before the call (its immediate is the id).
-- Names are the SNES routines the GBA code was matched to (same shape, same
-- order of calls); the SNES id it replaces is in the comment.
M.SITES = {
  tink        = 0x0809D1D8,  -- sword on a wall (SNES sfx2 5/6)
  clink       = 0x0809D1F4,  -- sword on a solid tile (shield clink)
  spinCharge  = 0x0809D2BE,  -- spin attack charged (sfx2 0x37)
  spin        = 0x0809C210,  -- spin attack / medallion whoosh (sfx3 0x23)
  hurt        = 0x0809DAE2,  -- Link hurt
  itemGet     = 0x080ACE82,  -- AncillaAdd_ItemReceipt (sfx3 0x0F)
  masterSword = 0x080ACE32,  -- the same, item 1 (sfx2 0x2C)
  heartPiece  = 0x080ACBF6,  -- the same, item 0x17 (sfx3 0x2D)
  capeOn      = 0x08116724,  -- the cape (sfx2 0x14)
  capeOff     = 0x08116738,  -- (sfx2 0x15)
  hookshot    = 0x0811CBCE,  -- Ancilla1F_Hookshot (sfx2 0x0A)
  arrowWall   = 0x08119A2E,  -- Ancilla09_Arrow into a wall (sfx2 8)
  explode     = 0x0811B106,  -- Ancilla07_Bomb's blast (sfx2 0x0C)
  bombLand    = 0x0811B092,  -- Ancilla07_Bomb lands (sfx2 0x21)
  lift        = 0x080C7D60,  -- a sprite lifted (sfx2 0x1D)
  throw       = 0x080C7DBE,  -- thrown (sfx3 0x13)
  enemyHit    = 0x080C429A,  -- a sprite takes damage
  error       = 0x080A1EB0,  -- "can't" (sfx2 0x3C)
  jump        = 0x080946DC,  -- ledge hop (sfx2 0x20)
  land        = 0x0809969A,  -- landing (sfx2 0x21)
  pit         = 0x0809AC3E,  -- falling into a pit
  swim        = 0x0809B62E,  -- swim stroke
  -- r33
  chest       = 0x0808469C,  -- the chest opener (tile attributes 0x58.. / 0x63)
  menuOpen    = 0x080AA522,  -- the item menu's first state (OURS: by its place)
  menuMove    = 0x080AA664,  -- the same function's second sound (cursor)
  splash      = 0x080AD20A,  -- r73: AncillaAdd_Splash (0x080AD1EC; Link pan 0x080C1A8C)
}
M.ENT_MUSIC = 0x150EC4   -- r33: the entrance table (0x2C bytes, 0x89), +0x28 = music id

-- the walker's argument byte counts for C2-FF (nil = none; -1 = varlen)
local ARGS = {
  [0xC2] = 1, [0xC3] = 1, [0xC4] = 1, [0xC7] = 1, [0xCA] = 1,
  [0xE0] = 1, [0xE1] = 1, [0xE2] = 1, [0xE3] = 1, [0xE4] = -1, [0xE5] = 1, [0xE6] = 1,
  [0xE7] = 1, [0xE9] = 1, [0xEA] = 1,
}

local function varlen(rom, p)
  local b = rom:u8(p)
  if b >= 0x80 then return p + 2 end
  return p + 1
end

-- walk one sound's tracks from the sub-bank base; returns notes, tracks, ok
function M.walk(rom, base, start)
  local notes, tracks, ok = 0, 0, true
  local queue, seen = { start }, {}
  while #queue > 0 do
    local p = table.remove(queue, 1)
    tracks = tracks + 1
    local stack, steps, done = {}, 0, false
    local visited = {}
    while not done do
      steps = steps + 1
      if steps > 4000 then ok = false break end
      local c = rom:u8(p)
      p = p + 1
      if c < 0x60 then notes = notes + 1
      elseif c < 0xC0 then notes = notes + 1; p = varlen(rom, p) + 1
      elseif c == 0xC0 then -- rest
      elseif c == 0xC1 then p = varlen(rom, p)
      elseif band(c, 0xF0) == 0xD0 then p = p + 2 + band(c, 1)
      elseif c == 0xF0 then
        local to = base + rom:u16(p)
        if visited[to] then done = true else visited[to] = true; p = to end
      elseif c == 0xF4 then
        stack[#stack + 1] = p + 2
        if #stack > 8 then ok = false break end
        p = base + rom:u16(p)
      elseif c == 0xF8 then
        local to = base + rom:u16(p + 1)
        if not seen[to] then seen[to] = true; queue[#queue + 1] = to end
        p = p + 3
      elseif c == 0xFF then
        if #stack > 0 then p = table.remove(stack) else done = true end
      else
        local n = ARGS[c]
        if n == -1 then p = varlen(rom, p) elseif n then p = p + n end
      end
    end
  end
  return notes, tracks, ok
end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { ids = {}, ev = {}, bank = {} }
  for i = 0, O.idCount - 1 do
    local v = rom:u32(O.idTable + i * 4)
    t.ids[i + 1] = { band(v, 0xFFFF), band(rshift(v, 16), 0xFF), band(rshift(v, 24), 0xFF) }
  end
  for name, at in pairs(M.SITES) do
    local h = rom:u16(at - 0x08000000)
    -- movs rN, #imm is 00100 nnn iiiiiiii
    check(rshift(h, 11) == 4, "sfx site %s at %08X is not movs #imm (%04X)", name, at, h)
    t.ev[name] = band(h, 0xFF)
  end
  t.sword = rom:bytesU16(O.sword, 4)
  t.absorb = rom:bytesU8(O.absorb, 15)
  t.debris = rom:bytesU8(O.debris, 16)
  t.entMusic = {}
  for i = 0, 0x88 do t.entMusic[i + 1] = rom:u16(M.ENT_MUSIC + i * 0x2C + 0x28) end
  -- the bank: sub-bank table at +0x0C, sub-bank 0 = the sound effects
  local subs = rom:ptr(O.bank + 0x0C)
  local base = subs + rom:u32(subs)
  -- the offset table ends where the first sequence starts
  local lowest, i = rom:u16(base), 0
  while i * 2 < lowest do
    local o = rom:u16(base + i * 2)
    if o < lowest then lowest = o end
    i = i + 1
  end
  local count = math.floor(lowest / 2)
  local walked, notes = 0, 0
  for i = 0, count - 1 do
    local n, _, ok = M.walk(rom, base, base + rom:u16(base + i * 2))
    if ok then walked = walked + 1 end
    notes = notes + n
  end
  t.bank = { base = base, count = count, walked = walked, notes = notes,
             sub1 = subs + rom:u32(subs + 4) }
  check(#t.ids == 133 and t.ids[1][1] == 19 and t.ev.spinCharge == 0x19 and t.ev.itemGet == 0x7A
        and t.absorb[1] == 0x70 and t.absorb[2] == 0x74 and t.sword[4] == 3 and count == 142
        and walked == count,
        "ALttP sound bank / sfx ids not where expected (%d ids, %d sounds, %d walked)",
        #t.ids, count, walked)
  return t
end

-- ---------------------------------------------------------------------------
-- RUNTIME: event -> id -> (sound number, channel). The backend is what will
-- render the bank's sequences; until it exists M.backend is nil and only the
-- log is kept (game.sfxLog: the last 64 starts, for tests / harnesses).
-- ---------------------------------------------------------------------------

M.backend = nil

local function tab(game) return game.data and game.data.t and game.data.t.sfx end

-- the GBA's 0x0812A324 for one id: variant by starts this frame (bit 27),
-- one sound per channel
function M.start(game, id, ev)
  local t = tab(game)
  local row = t and t.ids[(id or -1) + 1]
  if not row then return nil end
  local song = row[1]
  if band(row[3], 0x08) ~= 0 then
    local n = game.sfxFrameStarts or 0
    song = song + math.min(n, 2)
    game.sfxFrameStarts = n + 1
  end
  game.sfxLog = game.sfxLog or {}
  local log = game.sfxLog
  log[#log + 1] = { ev = ev, id = id, song = song, ch = row[2], frame = game.frame or 0 }
  if #log > 64 then table.remove(log, 1) end
  game.sfxChannels = game.sfxChannels or {}
  game.sfxChannels[row[2]] = song
  if M.backend then pcall(M.backend, game, song, row[2], id) end
  return song
end

function M.play(game, ev, arg)
  local t = tab(game)
  if not t then return nil end
  local id
  if ev == "sword" then id = t.sword[math.max(1, math.min(4, arg or 1))]
  elseif ev == "absorb" then id = t.absorb[(arg or 0xD8) - 0xD8 + 1]
  elseif ev == "debris" then id = t.debris[(arg or 0) + 1]
  else id = t.ev[ev] end
  if not id then return nil end
  return M.start(game, id, ev)
end

function M.install(G)
  if G.sfx32 then return end
  G.sfx32 = true
  require("src.zelda.alttp.AlttpSound").install(G)   -- r33: the synthesizer
  function G:sfx(ev, arg) return M.play(self, ev, arg) end
  local update = G.update
  function G:update(dt)
    self.sfxFrameStarts = 0
    M.lastGame = self
    local swing0, spins0, swde0 = self.swing, self.spins or 0, self.swde or 0
    local charge0 = self.swing and self.swing.charge or 0
    local abs0 = self.absorbed or 0
    local ex0 = self.explosions or 0
    local pull0 = self.groveSwordPulls or 0
    local r = update(self, dt)
    if (self.explosions or 0) > ex0 then M.play(self, "explode") end   -- r33
    -- r33: the pull starts the GBA's music 0x19 (0x080D46B4)
    if (self.groveSwordPulls or 0) > pull0 and self.music and self.music.playId then
      self.music:playId(0x19)
    end
    local s = self.swing
    if s and s ~= swing0 and not s.spin then
      M.play(self, "sword", (self.progress and self.progress.swordLevel) or 1)
    end
    if (self.spins or 0) > spins0 then M.play(self, "spin") end
    if s and (s.charge or 0) >= 48 and charge0 < 48 then M.play(self, "spinCharge") end
    if (self.swde or 0) == 16 and swde0 ~= 16 then M.play(self, "tink") end
    if (self.absorbed or 0) > abs0 and self.absorbLog then
      M.play(self, "absorb", self.absorbLog[#self.absorbLog])
    end
    return r
  end
  local hurt = G.hurtLink
  if hurt then
    function G:hurtLink(dmg, fx, fy)
      local h0 = self.stats and self.stats.health
      local r = hurt(self, dmg, fx, fy)
      if self.stats and h0 and self.stats.health < h0 then M.play(self, "hurt") end
      return r
    end
  end
  local get = G.getItem
  if get then
    function G:getItem(id)
      local r = get(self, id)
      M.play(self, id == 1 and "masterSword" or (id == 0x17 and "heartPiece" or "itemGet"))
      return r
    end
  end
  -- r33: lift / throw (Carry.lua), the item menu, chests
  local lift = G.startLift
  if lift then
    function G:startLift(obj)
      local r = lift(self, obj)
      M.play(self, "lift")
      return r
    end
  end
  local throw = G.throwCarried
  if throw then
    function G:throwCarried(...)
      local had = self.carry
      local r = throw(self, ...)
      if had then M.play(self, "throw") end
      return r
    end
  end
  local menu = G.openMenu
  if menu then
    function G:openMenu(...)
      local r = menu(self, ...)
      M.play(self, "menuOpen")
      return r
    end
  end
  local I = require("src.zelda.alttp.Interior")
  if not I.sfx33 then
    I.sfx33 = true
    local open = I.openChest
    function I:openChest(c)
      local r = open(self, c)
      if self.game then M.play(self.game, "chest") elseif M.lastGame then M.play(M.lastGame, "chest") end
      return r
    end
  end
  local A = require("src.zelda.alttp.Actors")
  if not A.sfx32 then
    A.sfx32 = true
    local take = A.takeDamage
    function A:takeDamage(a)
      local hp = a.hp
      local r = take(self, a)
      if self.game and a.hp ~= hp then M.play(self.game, "enemyHit") end
      return r
    end
  end
end

return M
