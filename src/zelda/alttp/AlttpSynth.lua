-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ALttP SOUND DRIVER (round 33): the GBA port's own driver (not M4A --
-- that is the Four Swords half), ported from the cartridge's code and run on
-- the bank the importer copies out of the user's ROM (assets/generated/alttp/
-- snd.bin, nothing of it is in the repo). Plays the 142 + n sound effects of
-- sub-banks 0 / 1 and the 34 songs.
--
-- THE BANK (0x198C30, pointers):
--   +0x00 samples   u32 sub-bank offsets; sub-bank: u32 offsets to sample
--                   headers {u32 length, u32 rate, u32 loop start, u32 loop
--                   end (0 = no loop), s8 data from +0x10}
--   +0x04 instrument sets   u32 offsets; set: u16 offsets to 8-byte records
--                   {type, flags, u16 sample (or table), u16 envelope, u8
--                   release, u8 root key}; type 0x00 one sample, 0x10 key
--                   range (table at +2 from key byte +4: {u16 record, u8 pan}),
--                   0x11 per-key sample (envelope 0x198EB4), 0x12 key split
--                   ({u8 upper key, -, u16 record} ...)  (0x0812AB30)
--   +0x08 songs     u32 offsets; song: u16 track count, u16 track offsets
--   +0x0C sfx sub-banks   u32 offsets; sub-bank: u16 offsets to sequences
--   +0x10 set -> sample sub-bank (u16)   +0x14 song info   +0x18 sfx info
--                   (info: u16 list, C7 n -> instrument set info[n])
--   envelope: (u16 frames, s16 level) pairs, a negative frame count = hold
--   the last pair (0x0812AEEC).
--
-- THE SEQUENCER (0x0812BE54, per track per frame at 59.73 Hz): lengths are
-- ticks x 150, a track waits while wait > 0 and loses tempo (E4, default
-- 150) per frame; notes 00-5F (last length / velocity), 60-BF (varlen
-- length + velocity), C0 / C1 rest, Dx slide, C2-FF commands (see `exec`).
-- In a sound effect (C8 / the sfx default) a note also waits its length.
-- THE VOICE (0x0812B7B4 note-on, 0x0812B01C volume, 0x0812B194 pitch,
-- 0x0812A964 mix): pitch table 0x199040 (0x8000 = the root key, the sample's
-- own rate), volume = velocity x player / track volumes x envelope, release
-- = x (release byte + 230) / 512 per frame, pan 0x00-0x7F, the vibrato sine
-- 0x199220. The cartridge mixes 176 samples a frame at 10512 Hz; this
-- renders 2x (21024 Hz) with linear interpolation.
--
-- OURS: one engine per stream (music, each sfx render) instead of one pool
-- of 7 voices for everything; voice stealing is "free, else quietest
-- released, else lowest priority"; the echo buffer (track +0x4C / E3) and
-- the hook commands (CA, the note hook 0x03000180) are not modelled.

local S = {}

local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local sbyte, floor = string.byte, math.floor

S.OFF = {
  bank = 0x198C30, songs = 0x2163FC, pitch = 0x199040, sine = 0x199220,
  drumEnv = 0x198EB4, songMap = 0x198C50, songMapN = 34,
}
S.MIX = 10512            -- the cartridge's mixing rate (timer 0 reload 0xF9C4)
S.OVER = 2
S.RATE = S.MIX * S.OVER  -- 21024
S.SPF = 176 * S.OVER     -- samples a frame
S.FPS = 16777216 / 280896

-- ---------------------------------------------------------------------------
-- IMPORT: the spans the driver reads, copied out of the ROM
-- ---------------------------------------------------------------------------

local function u32le(v)
  return string.char(band(v, 0xFF), band(rshift(v, 8), 0xFF), band(rshift(v, 16), 0xFF),
                     band(rshift(v, 24), 0xFF))
end

local function varlenAt(r, p)
  local b = r:u8(p)
  if b >= 0x80 then return p + 2 end
  return p + 1
end

-- the highest address a track's walk touches (for the music span's end)
local ARGS = {
  [0xC2] = 1, [0xC3] = 1, [0xC4] = 1, [0xC7] = 1, [0xCA] = 1,
  [0xE0] = 1, [0xE1] = 1, [0xE2] = 1, [0xE3] = 1, [0xE4] = -1, [0xE5] = 1, [0xE6] = 1,
  [0xE7] = 1, [0xE9] = 1, [0xEA] = 1,
}
S.ARGS = ARGS
function S.walkEnd(r, base, start)
  local hi, queue, seen = start, { start }, {}
  while #queue > 0 do
    local p = table.remove(queue, 1)
    local stack, visited, steps = {}, {}, 0
    while true do
      steps = steps + 1
      if steps > 20000 then return nil end
      local c = r:u8(p)
      p = p + 1
      if c < 0x60 then
      elseif c < 0xC0 then p = varlenAt(r, p) + 1
      elseif c == 0xC0 then
      elseif c == 0xC1 then p = varlenAt(r, p)
      elseif band(c, 0xF0) == 0xD0 then p = p + 2 + band(c, 1)
      elseif c == 0xF0 then
        if p + 2 > hi then hi = p + 2 end
        local to = base + r:u16(p)
        if visited[to] then break end
        visited[to] = true; p = to
      elseif c == 0xF4 then
        stack[#stack + 1] = p + 2
        if #stack > 8 then return nil end
        p = base + r:u16(p)
      elseif c == 0xF8 then
        local to = base + r:u16(p + 1)
        if not seen[to] then seen[to] = true; queue[#queue + 1] = to end
        p = p + 3
      elseif c == 0xFF then
        if #stack > 0 then
          if p > hi then hi = p end
          p = table.remove(stack)
        else break end
      else
        local n = ARGS[c]
        if n == -1 then p = varlenAt(r, p) elseif n then p = p + n end
      end
      if p > hi then hi = p end
    end
  end
  return hi
end

-- the bank's own spans: tables + sets + sample bank (one block) and the songs
function S.spans(rom)
  local B = S.OFF.bank
  local smp = rom:ptr(B)
  local hiA, nSmp = 0, 0
  for k = 0, rom:u32(smp) / 4 - 1 do      -- every sample sub-bank
    local sub = smp + rom:u32(smp + k * 4)
    local n = rom:u32(sub) / 4
    for i = 0, n - 1 do
      local h = sub + rom:u32(sub + i * 4)
      local e = h + 0x10 + rom:u32(h) + 4
      if e > hiA then hiA = e end
    end
    if sub + 4 > hiA then hiA = sub + 4 end
    nSmp = nSmp + n
  end
  local songs = rom:ptr(B + 8)
  local nSongs = rom:u32(songs) / 4
  local hiB = songs + nSongs * 4
  for s = 0, nSongs - 1 do
    local base = songs + rom:u32(songs + s * 4)
    local n = rom:u16(base)
    for t = 0, n - 1 do
      local o = rom:u16(base + 2 + t * 2)
      if o ~= 0 then
        local e = S.walkEnd(rom, base, base + o)
        if not e then return nil, ("song %d track %d does not walk"):format(s, t) end
        if e > hiB then hiB = e end
      end
    end
  end
  return { { B, hiA - B }, { songs, hiB - songs } }, nSmp, nSongs
end

-- the image the importer writes: "ASND" u32 n, n x (u32 rom offset, u32
-- length), then the spans' bytes
function S.image(rom)
  local spans, nSmp, nSongs = S.spans(rom)
  if not spans then return nil, nSmp end
  local parts = { "ASND", u32le(#spans) }
  for _, s in ipairs(spans) do parts[#parts + 1] = u32le(s[1]) .. u32le(s[2]) end
  for _, s in ipairs(spans) do parts[#parts + 1] = rom:sub(s[1], s[2]) end
  return table.concat(parts), { samples = nSmp, songs = nSongs }
end

-- ---------------------------------------------------------------------------
-- THE BANK READER (the image, addressed by ROM offset)
-- ---------------------------------------------------------------------------

local Bank = {}
Bank.__index = Bank

function S.open(img)
  if type(img) ~= "string" or img:sub(1, 4) ~= "ASND" then return nil end
  local function rd(o) local a, b, c, d = sbyte(img, o + 1, o + 4) return a + b * 256 + c * 65536 + d * 16777216 end
  local n = rd(4)
  local spans, off = {}, 8 + n * 8
  for i = 1, n do
    local lo, len = rd(8 + (i - 1) * 8), rd(12 + (i - 1) * 8)
    spans[i] = { lo, lo + len, off - lo }
    off = off + len
  end
  local self = setmetatable({ data = img, spans = spans, smpCache = {} }, Bank)
  local B = S.OFF.bank
  self.B0, self.B4, self.B8 = self:ptr(B), self:ptr(B + 4), self:ptr(B + 8)
  self.BC, self.B10, self.B14, self.B18 = self:ptr(B + 12), self:ptr(B + 16), self:ptr(B + 20), self:ptr(B + 24)
  self.nSongs = self:u32(self.B8) / 4
  return self
end

function Bank:pos(o)
  local sp = self.spans
  for i = 1, #sp do
    local s = sp[i]
    if o >= s[1] and o < s[2] then return o + s[3] end
  end
  error(("ALttP sound: read outside the bank at %06X"):format(o), 0)
end
function Bank:u8(o) return sbyte(self.data, self:pos(o) + 1) end
function Bank:s8(o) local v = self:u8(o) return v >= 128 and v - 256 or v end
function Bank:u16(o) local p = self:pos(o) local a, b = sbyte(self.data, p + 1, p + 2) return a + b * 256 end
function Bank:s16(o) local v = self:u16(o) return v >= 0x8000 and v - 0x10000 or v end
function Bank:u32(o)
  local p = self:pos(o)
  local a, b, c, d = sbyte(self.data, p + 1, p + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function Bank:ptr(o) return self:u32(o) - 0x08000000 end

-- a sample header -> { pos (1-based into data), len, rate, ls, le }
function Bank:sample(h)
  local c = self.smpCache[h]
  if c then return c end
  c = { pos = self:pos(h + 0x10) + 1, len = self:u32(h), rate = self:u32(h + 4),
        ls = self:u32(h + 8), le = self:u32(h + 12) }
  self.smpCache[h] = c
  return c
end

-- GBA song for a music number (0x0812A044: table 0x198C50, u16 x 34)
function Bank:songFor(id)
  if id < 0 or id >= S.OFF.songMapN then return nil end
  return self:u16(S.OFF.songMap + id * 2)
end

-- the sound effects of sub-bank `sub`: count
function Bank:sfxCount(sub)
  local base = self.BC + self:u32(self.BC + sub * 4)
  local lowest, i = self:u16(base), 0
  while i * 2 < lowest do
    local o = self:u16(base + i * 2)
    if o < lowest then lowest = o end
    i = i + 1
  end
  return floor(lowest / 2)
end

-- ---------------------------------------------------------------------------
-- THE ENGINE
-- ---------------------------------------------------------------------------

local Eng = {}
Eng.__index = Eng

function S.engine(bank, opts)
  opts = opts or {}
  return setmetatable({ bank = bank, players = {}, voices = {}, maxVoices = opts.voices or 7,
                        frame = 0, gain = opts.gain or (1 / 20000) }, Eng)
end

local function newPlayer(P)
  P = P or {}
  P.tempo, P.adj, P.vol40, P.vol41, P.master = 150, 0, 0x80, 0x80, 0x8000
  P.tracks = {}
  return P
end

-- 0x0812C334 (C7): instrument set n and its sample sub-bank
local function setInstSet(E, T, n)
  local b = E.bank
  T.set, T.inst = n, 0
  local idx = b:u16(T.P.info + n * 2)
  local sub = b:u16(b.B10 + idx * 2)
  T.smpBase = b.B0 + b:u32(b.B0 + sub * 4)
end

-- 0x0812BD50: a track's defaults
local function newTrack(E, P, pc)
  local T = { P = P, pc = pc, wait = 0, stack = {}, hold = false, voices = {},
              vibDelay = 0, vibSpeed = 0x22, vibDepth = 0, slide = false, slFlags = 0, slKey = 0,
              slDelay = 0, slLen = 0, pan = 0x40, vol4D = 0x80, vol4E = 0x80, bend = 0, range = 2,
              transpose = 0, lastLen = 0x7F, lastVel = 0x7F, restLen = 0, active = true }
  if P.sfx then T.prio, T.echo, T.noteWait = 0x0C, 0x7F, true
  else T.prio, T.echo, T.noteWait = 3, 0, false end
  setInstSet(E, T, 0)
  return T
end

local function releaseTrack(E, T)
  local h = T.hold
  T.hold = false
  for _, v in ipairs(T.voices) do
    if v.state == 1 then v.state = 2 end
  end
  T.hold = h
end

function Eng:stop()
  self.players, self.voices = {}, {}
end

function Eng:stopPlayer(ch)
  local P = self.players[ch]
  if P then
    for _, T in pairs(P.tracks) do releaseTrack(self, T); T.active = false end
    self.players[ch] = nil
  end
end

-- command 1 (0x0812C494 / 0x0812C548): sound `num` of sfx sub-bank `sub` on player `ch`
function Eng:playSfx(sub, num, ch)
  local b = self.bank
  ch = ch or 0
  self:stopPlayer(ch)
  local base = b.BC + b:u32(b.BC + sub * 4)
  local P = newPlayer({ sfx = true, base = base, info = b.B18 + b:u32(b.B18 + sub * 4) })
  P.tracks[0] = newTrack(self, P, base + b:u16(base + num * 2))
  self.players[ch] = P
  return P
end

-- command 0 (0x0812C46C / 0x0812C4C0): GBA song `song` on player `ch`
function Eng:playSong(song, ch)
  local b = self.bank
  ch = ch or 0x12
  self:stopPlayer(ch)
  if song < 0 or song >= b.nSongs then return nil end
  local base = b.B8 + b:u32(b.B8 + song * 4)
  local P = newPlayer({ sfx = false, base = base, info = b.B14 + b:u32(b.B14 + song * 4) })
  local n = b:s8(base)
  for t = 0, n - 1 do
    local o = b:u16(base + 2 + t * 2)
    if o ~= 0 then P.tracks[t] = newTrack(self, P, base + o) end
  end
  self.players[ch] = P
  return P
end

function Eng:busy()
  for _, P in pairs(self.players) do
    for _, T in pairs(P.tracks) do if T.active then return true end end
  end
  return #self.voices > 0
end

-- 0x0812AB30: the instrument record for a key
local function lookup(E, T, key)
  local b = E.bank
  local setIdx = b:u16(T.P.info + T.set * 2)
  local setBase = b.B4 + b:u32(b.B4 + setIdx * 4)
  local rec = setBase + b:u16(setBase + T.inst * 2)
  local ty = b:u8(rec)
  local out = { drum = false, kit = false }
  local r
  if band(ty, 0xF0) == 0 then
    r = rec
  elseif ty == 0x10 then
    local tab = setBase + b:u16(rec + 2)
    local e = tab + band(key - b:u8(rec + 4), 0xFF) * 4
    out.drum, out.pan = true, b:u8(e + 2)
    r = setBase + b:u16(e)
  elseif ty == 0x11 then
    local tab = setBase + b:u16(rec + 2)
    out.kit = true
    out.type, out.flags, out.smp, out.b6, out.root = 0, 0, b:u16(tab + key * 2), 0, 0x30
    out.env = S.OFF.drumEnv
    return out
  elseif ty == 0x12 then
    local e = setBase + b:u16(rec + 2)
    local guard = 0
    while key > b:u8(e) and guard < 64 do e = e + 4; guard = guard + 1 end
    r = setBase + b:u16(e + 2)
  else
    return nil
  end
  out.type, out.flags, out.smp = b:u8(r), b:u8(r + 1), b:u16(r + 2)
  out.env = setBase + b:u16(r + 4)
  out.b6, out.root = b:u8(r + 6), b:u8(r + 7)
  return out
end

-- 0x0812AE7C: the pitch word of a key for a root (PCM: table 0x199040)
local function pitchOf(E, key, root)
  local n = key + 0x30 - root
  if n < 0 then n = 0 elseif n > 0x77 then n = 0x77 end
  return E.bank:u32(S.OFF.pitch + n * 4)
end

local function sdiv(a, b)
  if b == 0 then return 0 end
  local q = a / b
  return q >= 0 and floor(q) or -floor(-q)
end

local function allocVoice(E, prio)
  local vs = E.voices
  if #vs < E.maxVoices then
    local v = {}
    vs[#vs + 1] = v
    return v
  end
  local best, bi
  for i, v in ipairs(vs) do
    if v.state ~= 1 and (not best or (v.v14 or 0) < (best.v14 or 0)) then best, bi = v, i end
  end
  if not best then
    for i, v in ipairs(vs) do
      if v.prio <= prio and (not best or v.prio < best.prio) then best, bi = v, i end
    end
  end
  if not best then return nil end
  if best.T then
    for k, w in ipairs(best.T.voices) do if w == best then table.remove(best.T.voices, k) break end end
  end
  local v = {}
  vs[bi] = v
  return v
end

-- 0x0812B7B4: note-on (len = ticks x 150)
local function noteOn(E, T, key, vel, len)
  local P = T.P
  key = band(key + T.transpose, 0xFF)
  local inst = lookup(E, T, key)
  if not inst then return end
  local tempo = band(inst.flags, 0x10) ~= 0 and P.tempo or (P.tempo + P.adj)
  if tempo <= 0 then tempo = 1 end
  local frames = band(floor(len / tempo), 0xFFFF)
  local v
  local head = T.voices[#T.voices]
  if T.hold and head and head.alive then
    v = head
  else
    v = allocVoice(E, T.prio)
    if not v then return end
    v.alive, v.T, v.prio, v.state = true, T, T.prio, 1
    v.pos, v.vibPhase, v.vibDelay = 0, 0, T.vibDelay
    v.env, v.envLevel, v.envTarget, v.envFrames, v.envStep, v.envIdx = inst.env, 0, 0, 0, 0, -1
    v.b6 = inst.b6
    v.v14 = 0
    T.voices[#T.voices + 1] = v
  end
  v.state = 1
  v.drum = inst.drum
  if inst.drum then key = 0x30; v.dpan = inst.pan
  elseif inst.kit then key = 0x30 end
  v.vel, v.v14, v.dur = vel, 0, frames
  v.pitch = pitchOf(E, key, inst.root)
  v.slDelay, v.slCount, v.slCur, v.slTarget, v.slStep = 0, 0, 0, 0, 0
  if T.slide then
    local tp = pitchOf(E, T.slKey, inst.root)
    v.slDelay = T.slDelay
    v.slCount = rshift(T.slLen * frames, 8)
    if band(T.slFlags, 2) ~= 0 then
      v.slTarget = tp - v.pitch
    else
      v.slTarget = v.pitch - tp
      v.pitch = tp
    end
    v.slStep = sdiv(v.slTarget, v.slCount)
    if band(T.slFlags, 4) ~= 0 then T.slKey = key else T.slide = false end
  end
  local h = T.smpBase + E.bank:u32(T.smpBase + inst.smp * 4)
  v.smp = E.bank:sample(h)
  if v.pos ~= 0 and head ~= v then v.pos = 0 end
end

local function varlen(E, T)
  local b = E.bank
  local c = b:u8(T.pc)
  T.pc = T.pc + 1
  if c >= 0x80 then
    c = lshift(band(c, 0x7F), 8) + b:u8(T.pc)
    T.pc = T.pc + 1
  end
  return c
end

-- one command (0x0812BE90..); returns false when the track ended
local function exec(E, T, slot)
  local b, P = E.bank, T.P
  local c = b:u8(T.pc)
  T.pc = T.pc + 1
  if c < 0xC0 then
    local len, vel
    if c < 0x60 then
      len, vel = T.lastLen, T.lastVel
    else
      len = varlen(E, T); T.lastLen = len
      vel = b:u8(T.pc); T.pc = T.pc + 1; T.lastVel = vel
      c = c - 0x60
    end
    noteOn(E, T, c, vel, len * 150)
    if T.noteWait then T.wait = T.wait + len * 150 end
    return true
  end
  if c == 0xC0 then T.wait = T.wait + T.restLen * 150 return true end
  if c == 0xC1 then T.restLen = varlen(E, T); T.wait = T.wait + T.restLen * 150 return true end
  if band(c, 0xF0) == 0xD0 then
    T.slFlags = band(c, 0x0F)
    T.slKey = band(T.transpose + b:u8(T.pc), 0xFF)
    T.slLen = b:u8(T.pc + 1)
    T.pc = T.pc + 2
    if band(c, 1) ~= 0 then T.slDelay = b:u8(T.pc); T.pc = T.pc + 1 else T.slDelay = 0 end
    T.slide = true
    return true
  end
  local function arg() local v = b:u8(T.pc) T.pc = T.pc + 1 return v end
  if c == 0xC2 then T.inst = arg()
  elseif c == 0xC3 then T.pan = arg()
  elseif c == 0xC4 then T.prio = arg()
  elseif c == 0xC5 or c == 0xC6 then releaseTrack(E, T); T.hold = (c == 0xC5)
  elseif c == 0xC7 then setInstSet(E, T, arg())
  elseif c == 0xC8 then T.noteWait = true
  elseif c == 0xC9 then T.noteWait = false
  elseif c == 0xCA then arg()
  elseif c == 0xE0 then T.vol4D = arg()
  elseif c == 0xE1 then local v = arg() T.bend = v >= 128 and v - 256 or v
  elseif c == 0xE2 then T.range = arg()
  elseif c == 0xE3 then T.echo = arg()
  elseif c == 0xE4 then P.tempo = varlen(E, T)
  elseif c == 0xE5 then T.vibDelay = arg()
  elseif c == 0xE6 then T.vibSpeed = arg()
  elseif c == 0xE7 then T.vibDepth = arg()
  elseif c == 0xE8 then T.slide = false
  elseif c == 0xE9 then T.transpose = arg()
  elseif c == 0xEA then P.vol40 = arg()
  elseif c == 0xF0 then T.pc = P.base + b:u16(T.pc)
  elseif c == 0xF4 then
    T.stack[#T.stack + 1] = T.pc + 2
    T.pc = P.base + b:u16(T.pc)
  elseif c == 0xF8 then
    local n = arg()
    local o = b:u16(T.pc)
    T.pc = T.pc + 2
    local old = P.tracks[n]
    if old then releaseTrack(E, old) end
    local N = newTrack(E, P, P.base + o)
    N.smpBase, N.set, N.inst, N.pan, N.echo = T.smpBase, T.set, T.inst, T.pan, T.echo
    N.vol4D, N.vol4E, N.prio, N.bend, N.range, N.transpose = T.vol4D, T.vol4E, T.prio, T.bend, T.range, T.transpose
    P.tracks[n] = N
  elseif c == 0xFF then
    if #T.stack > 0 then
      T.pc = table.remove(T.stack)
    else
      releaseTrack(E, T)
      T.active = false
      return false
    end
  end
  return true
end

local function stepTrack(E, T)
  if not T.active then return end
  local guard = 0
  while T.wait <= 0 do
    if not exec(E, T) then return end
    guard = guard + 1
    if guard > 4096 then T.active = false return end   -- a loop with no wait
  end
  T.wait = T.wait - (T.P.tempo + T.P.adj)
end

-- 0x0812AEEC: the envelope's next level
local function envStep(E, v)
  local b = E.bank
  if v.envFrames == 0 then
    v.envLevel = v.envTarget
    local idx = v.envIdx + 1
    if b:s16(v.env + idx * 4) < 0 then idx = v.envIdx end
    if idx < 0 then idx = 0 end
    v.envIdx = idx
    local t = b:u16(v.env + idx * 4)
    local lv = b:s16(v.env + idx * 4 + 2)
    v.envTarget, v.envFrames = lv, t
    v.envStep = sdiv(lv - v.envLevel, t)
  end
  v.envLevel = v.envLevel + v.envStep
  v.envFrames = band(v.envFrames - 1, 0xFFFF)
  return v.envLevel
end

-- 0x0812B01C: the voice's volume this frame (0 = free it)
local function volume(E, v)
  local T, x = v.T, 0
  local P = T.P
  if v.state == 1 then
    x = v.vel * 128
    x = rshift(x * P.master, 8)
    x = rshift(x * P.vol40, 7)
    x = rshift(x * P.vol41, 8)
    x = rshift(x * T.vol4D, 8)
    x = rshift(x * T.vol4E, 15)
    local env = envStep(E, v)
    if env < 0 then env = 0 end
    x = rshift(x * env, 11)
    v.v14 = x
  else
    x = rshift((v.b6 + 0xE6) * v.v14, 9)
    v.v14 = x
  end
  return rshift(x * 3, 9)
end

-- 0x0812B194: the voice's pitch word this frame (slide, bend, vibrato)
local function pitchFx(E, v)
  local T, b = v.T, E.bank
  local p = v.pitch
  if v.slDelay > 0 then v.slDelay = v.slDelay - 1
  elseif v.slCount > 0 then
    v.slCur = v.slCur + v.slStep
    v.slCount = v.slCount - 1
    if v.slCount == 0 then v.slCur = v.slTarget end
  end
  p = p + v.slCur
  if T.bend ~= 0 then
    local tab = b:u32(S.OFF.pitch + (T.range + 0x30) * 4)
    if T.bend > 0 then
      p = p * (T.bend * tab / 128 + 0x8000) / 0x8000
    else
      p = p * 0x8000 / (-T.bend * tab / 128 + 0x8000)
    end
  end
  if T.vibDepth ~= 0 then
    if v.vibDelay == 0 then
      local s = b:s8(S.OFF.sine + rshift(v.vibPhase, 1))
      if s >= 0 then p = p + p * s * T.vibDepth / 524288
      else p = p / (1 + (-s) * T.vibDepth / 524288) end
      v.vibPhase = v.vibPhase + T.vibSpeed
      if rshift(v.vibPhase, 1) > 0xFF then v.vibPhase = v.vibPhase - 0x200 end
    else
      v.vibDelay = v.vibDelay - 1
    end
  end
  return p
end

-- mix one voice's frame into L / R (1-based, n samples); returns true at
-- the sample's end (no loop)
local function mixVoice(E, v, L, R, n, out, pitch)
  local smp = v.smp
  local pan = v.drum and v.dpan or v.T.pan
  if pan > 0x7F then pan = 0x7F end
  local gl = band(rshift((0x7F - pan) * out, 8), 0xFF)
  local gr = band(rshift(pan * out, 8), 0xFF)
  local step = pitch / 32768 * smp.rate / S.RATE
  local pos = v.pos
  local data, base = E.bank.data, smp.pos
  local looped = smp.le ~= 0
  local stop = looped and smp.le or smp.len
  local ls = smp.ls
  local ended = false
  for i = 1, n do
    if pos >= stop then
      if looped and stop > ls then
        pos = ls + (pos - stop) % (stop - ls)
      else
        ended = true
        break
      end
    end
    local ip = floor(pos)
    local f = pos - ip
    local a = sbyte(data, base + ip)
    local c = ip + 1 < stop and sbyte(data, base + ip + 1) or (looped and sbyte(data, base + ls) or 0)
    if a >= 128 then a = a - 256 end
    if c >= 128 then c = c - 256 end
    local s = a + (c - a) * f
    L[i] = L[i] + s * gl
    R[i] = R[i] + s * gr
    pos = pos + step
  end
  v.pos = pos
  return ended
end

-- one 59.73 Hz frame: sequencer, then every voice mixed into L / R
function Eng:frameStep(L, R)
  local n = S.SPF
  for i = 1, n do L[i], R[i] = 0, 0 end
  for _, P in pairs(self.players) do
    for slot = 0, 15 do
      local T = P.tracks[slot]
      if T then stepTrack(self, T) end
    end
  end
  local vs = self.voices
  local i = 1
  while i <= #vs do
    local v = vs[i]
    local free = false
    if v.state == 1 then v.dur = band(v.dur - 1, 0xFFFF) end
    local out = volume(self, v)
    if out == 0 and v.state ~= 1 then
      free = true
    else
      local p = pitchFx(self, v)
      if out > 0 and mixVoice(self, v, L, R, n, out, p) then free = true end
    end
    if free then
      v.alive = false
      for k, w in ipairs(v.T.voices) do if w == v then table.remove(v.T.voices, k) break end end
      table.remove(vs, i)
    else
      i = i + 1
    end
  end
  for _, v in ipairs(vs) do
    if v.state == 1 and v.dur == 0 and not v.T.hold then v.state = 2 end
  end
  -- players with no live track and no voice are done
  for ch, P in pairs(self.players) do
    local live = false
    for _, T in pairs(P.tracks) do if T.active then live = true break end end
    if not live then self.players[ch] = nil end
  end
  self.frame = self.frame + 1
end

-- render whole frames into a flat interleaved array of floats (-1..1)
function Eng:renderFrames(frames, out, at)
  out, at = out or {}, at or 0
  local L, R = self.L or {}, self.R or {}
  self.L, self.R = L, R
  local g = self.gain
  for _ = 1, frames do
    self:frameStep(L, R)
    for i = 1, S.SPF do
      local l, r = L[i] * g, R[i] * g
      if l > 1 then l = 1 elseif l < -1 then l = -1 end
      if r > 1 then r = 1 elseif r < -1 then r = -1 end
      out[at + 1], out[at + 2] = l, r
      at = at + 2
    end
  end
  return out, at
end

-- a whole sound effect (until its tracks and voices are done, at most
-- maxFrames), as interleaved floats + the frame count
function S.renderSfx(bank, sub, num, maxFrames)
  local E = S.engine(bank, { voices = 7 })
  E:playSfx(sub, num, 0)
  local out, at, frames = {}, 0, 0
  maxFrames = maxFrames or 60 * 8
  repeat
    out, at = E:renderFrames(1, out, at)
    frames = frames + 1
  until not E:busy() or frames >= maxFrames
  return out, frames
end

-- ---------------------------------------------------------------------------
-- LÖVE: sound data / a streaming source
-- ---------------------------------------------------------------------------

-- write interleaved floats into a 16-bit stereo SoundData (n values)
function S.fillSoundData(sd, out, n)
  local frames = sd:getSampleCount()
  local okF, ffi = pcall(require, "ffi")
  local ptr = okF and sd.getFFIPointer and sd:getFFIPointer()
  if ptr then
    local p = ffi.cast("int16_t*", ptr)
    for i = 0, frames * 2 - 1 do p[i] = i < n and floor((out[i + 1] or 0) * 32767) or 0 end
  else
    for i = 0, frames - 1 do
      sd:setSample(i, 1, i * 2 < n and out[i * 2 + 1] or 0)
      sd:setSample(i, 2, i * 2 + 1 < n and out[i * 2 + 2] or 0)
    end
  end
  return sd
end

function S.toSoundData(out, n)
  if not (love and love.sound) then return nil end
  n = n or #out
  local frames = math.max(1, floor(n / 2))
  return S.fillSoundData(love.sound.newSoundData(frames, S.RATE, 16, 2), out, n)
end

-- a RIFF WAV of interleaved stereo floats (harness / tests)
function S.wav(out, n)
  n = n or #out
  local parts = {}
  for i = 1, n do
    local v = floor((out[i] or 0) * 32767)
    if v < 0 then v = v + 65536 end
    parts[i] = string.char(band(v, 0xFF), rshift(v, 8))
  end
  local body = table.concat(parts)
  local function u16(v) return string.char(band(v, 0xFF), rshift(v, 8)) end
  return "RIFF" .. u32le(36 + #body) .. "WAVEfmt " .. u32le(16) .. u16(1) .. u16(2)
      .. u32le(S.RATE) .. u32le(S.RATE * 4) .. u16(4) .. u16(16) .. "data" .. u32le(#body) .. body
end

return S
