-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- EMERALD'S MUSIC.
--
-- Gen 1 and Gen 2 drive four Game Boy channels from a small note engine, and
-- ChipSynth next door renders exactly that.  NOTHING about it applies here.
-- Hoenn's music is M4A (Sappy): a sequencer that reads MIDI-ish bytecode off
-- one track pointer per part, looks each note's instrument up in a
-- VOICEGROUP, and mixes SAMPLED INSTRUMENTS in software -- with the Game
-- Boy's four channels still there alongside, as four more instrument types.
--
-- So the port had 611 songs, every one of them carrying its track pointers
-- and its voicegroup, and no way to play a single note: Music.startSong knew
-- a chip program and a sound file and neither is what a Gen 3 song is.  The
-- region was silent.
--
-- This module is the missing engine.  It presents the SAME three methods
-- ChipSynth's engine does -- sample, sampleStereo, finished -- so ChipAudio's
-- queueing, its worker thread, its per-channel mixer and Music's whole
-- lifecycle drive it without knowing which generation is playing.
--
-- ---------------------------------------------------------------------------
-- THE FORMAT, and how much of it is guesswork: none.
--
-- The command set below is not transcribed from a document; it is the one
-- that walks all 2082 track pointers in a real Emerald dump from their first
-- byte to a terminator without ever landing on a byte it cannot name.  The
-- import stage does that walk on every import (RomExtractorGen3
-- :extractAudioImage) and refuses the whole image if a single track does not
-- come out clean, so a wrong table cannot quietly ship.
--
--   0x00..0x7F   an argument -- or, where a command is expected, a repeat of
--                the last command that set RUNNING STATUS
--   0x80..0xB0   W00..W96, wait this many ticks (gClockTable)
--   0xB1         FINE, the track ends
--   0xB2         GOTO   + 4-byte pointer   (this is what makes a song loop)
--   0xB3         PATT   + 4-byte pointer   (call)
--   0xB4         PEND                      (return)
--   0xB5         REPT   + count + pointer
--   0xB9         MEMACC + 3
--   0xBA..0xC5   PRIO TEMPO KEYSH VOICE VOL PAN BEND BENDR LFOS LFODL MOD
--                MODT, one byte each
--   0xC8         TUNE   + 1
--   0xCD         XCMD   + 2
--   0xCE         EOT    + up to 1          (end of tie)
--   0xCF         TIE    + up to 2          (a note with no length)
--   0xD0..0xFF   N01..N96 + up to 3        (key, velocity, gate extension)
--
-- Running status starts at 0xBD, not at the notes: a bare argument byte after
-- a VOICE repeats VOICE.  That one rule is the difference between every track
-- parsing and four out of five failing.
-- ---------------------------------------------------------------------------

local M4A = {}

local SAMPLE_RATE = 44100
M4A.SAMPLE_RATE = SAMPLE_RATE

-- the sequencer's own clock: the cartridge's mixer runs one engine frame per
-- video frame, and every tempo in the game is expressed against that
local FRAME_RATE = 60
local SAMPLES_PER_FRAME = SAMPLE_RATE / FRAME_RATE

-- gClockTable: a wait or note length index turned into ticks
local CLOCK = {
  [0] = 0,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23, 24, 28, 30, 32, 36, 40, 42, 44,
  48, 52, 54, 56, 60, 64, 66, 68, 72, 76, 78, 80, 84, 88, 90, 92,
  96,
}
M4A.CLOCK = CLOCK

-- commands that take a fixed number of argument bytes
local FIXED_ARGS = {
  [0xB1] = 0,                      -- FINE
  [0xB2] = 4, [0xB3] = 4,          -- GOTO, PATT
  [0xB4] = 0,                      -- PEND
  [0xB5] = 5,                      -- REPT
  [0xB9] = 3,                      -- MEMACC
  [0xBA] = 1, [0xBB] = 1, [0xBC] = 1, [0xBD] = 1, [0xBE] = 1, [0xBF] = 1,
  [0xC0] = 1, [0xC1] = 1, [0xC2] = 1, [0xC3] = 1, [0xC4] = 1, [0xC5] = 1,
  [0xC8] = 1,
  [0xCD] = 2,
}
M4A.FIXED_ARGS = FIXED_ARGS

-- the most argument bytes a note-shaped command reads; each is optional and
-- stops at the first byte with the top bit set
local function noteArgs(cmd)
  if cmd >= 0xD0 then return 3 end   -- key, velocity, gate extension
  if cmd == 0xCF then return 2 end   -- TIE: key, velocity
  return 1                           -- EOT: key
end
M4A.noteArgs = noteArgs

-- ---------------------------------------------------------------------------
-- THE WALKER, shared with the import stage
--
-- `read(offset)` returns the byte at a ROM offset (or nil past the end).
-- `visit` is called as visit(pc, cmd, argsAt, nextPc) for every command; a
-- visitor returning "stop" ends that strand.  Returns true, or nil plus the
-- offset and reason it gave up -- which is what the import stage refuses on.
-- ---------------------------------------------------------------------------
function M4A.walk(read, start, visit, pointerAt)
  local seen = {}
  -- PATT is a CALL and PEND is its return, and walking them as anything else
  -- gets the shape of a track wrong: read linearly, the walk falls off the
  -- end of the last command into the first pattern body and mistakes that
  -- pattern's PEND for the end of the track -- which hid the GOTO that says
  -- the song loops, and had two thirds of Hoenn's map themes filed as
  -- one-shot sound effects.
  local function strand(pc)
    local stack, running = {}, nil
    while true do
      if not pc or seen[pc] then return end
      local c = read(pc)
      if not c then return nil, pc, "past the end of the image" end
      seen[pc] = true
      local cmd, at
      if c < 0x80 then
        if not running then
          return nil, pc, ("an argument byte with no running status (%02X)")
                          :format(c)
        end
        cmd, at = running, pc
      else
        cmd, at = c, pc + 1
        if cmd >= 0xBD then running = cmd end
      end

      local next_, done
      if cmd >= 0x80 and cmd <= 0xB0 then
        next_ = at
      elseif cmd == 0xB1 then                       -- FINE
        next_, done = at, true
      elseif cmd == 0xB2 then                       -- GOTO: the loop
        next_, done = at + 4, true
      elseif cmd == 0xB3 then                       -- PATT: call
        next_ = at + 4
      elseif cmd == 0xB4 then                       -- PEND: return
        next_ = at
      elseif FIXED_ARGS[cmd] then
        next_ = at + FIXED_ARGS[cmd]
      elseif cmd >= 0xCE then
        local n, o = noteArgs(cmd), at
        local k = 0
        while k < n do
          local b = read(o)
          if not b or b >= 0x80 then break end
          o, k = o + 1, k + 1
        end
        next_ = o
      else
        return nil, pc, ("no command %02X"):format(cmd)
      end

      if visit then
        local answer = visit(pc, cmd, at, next_)
        if answer == "stop" then return end
      end

      if cmd == 0xB3 then
        local target = pointerAt and pointerAt(at)
        if target then
          stack[#stack + 1] = next_
          pc = target
        else
          pc = next_
        end
      elseif cmd == 0xB4 then
        -- A PEND WITH NOTHING TO RETURN TO IS NOT THE END.  The cartridge's
        -- own handler does nothing at all in that case and lets the command
        -- pointer walk straight past it, and four of Hoenn's map themes rely
        -- on exactly that -- their tracks carry a PEND partway through and
        -- keep playing.  Stopping here filed all four as one-shot sound
        -- effects and cut them off in the game after about nine seconds.
        pc = table.remove(stack) or next_
      elseif cmd == 0xB2 then
        -- follow the jump ONCE, so a loop body reached only from the far end
        -- is still measured
        local target = pointerAt and pointerAt(at)
        if target and not seen[target] then
          local okJump, atJump, whyJump = strand(target)
          if not okJump and atJump then return nil, atJump, whyJump end
        end
        return
      elseif done then
        return
      else
        pc = next_
      end
    end
  end
  local ok, at, why = strand(start)
  if ok == nil and at then return nil, at, why end
  return true
end

-- ---------------------------------------------------------------------------
-- THE IMAGE
--
-- The import stage wrote one span of the cartridge -- bytecode, voicegroups
-- and sampled instruments together -- beside the cache, and recorded the ROM
-- offset it starts at.  Everything below addresses the cartridge by its own
-- offsets and this is the only place that knows they are not.
-- ---------------------------------------------------------------------------

local cachedFile, cachedImage

local function loadImage(audio)
  local gen3 = audio and audio.gen3
  if not (gen3 and gen3.file) then
    error("this dataset carries no Gen 3 music image -- import the ROM again")
  end
  if cachedFile == gen3.file and cachedImage then return cachedImage end
  local raw, readError = love.filesystem.read(gen3.file)
  if not raw then
    error("could not read the music image: " .. tostring(readError))
  end
  cachedFile, cachedImage = gen3.file, raw
  return raw
end

function M4A.invalidate()
  cachedFile, cachedImage = nil, nil
end

-- ---------------------------------------------------------------------------
-- INSTRUMENTS
--
-- A voicegroup is an array of twelve-byte records.  Which KIND of instrument
-- a record describes is its first byte, and the four Game Boy channels are in
-- there beside the sampled ones -- Hoenn's music uses both at once, which is
-- why a square lead sits on top of a sampled drum kit.
--
--   0x00        a sampled instrument
--   0x08        the same, at a FIXED pitch: the note picks the drum, not
--               the frequency
--   0x01 0x02   the two Game Boy square channels
--   0x03        the Game Boy's programmable wave
--   0x04        its noise
--   0x40        a KEY SPLIT: the note chooses which instrument out of a
--               second voicegroup, through a 128-entry table
--   0x80        a DRUM KIT: the note IS the index into a second voicegroup
-- ---------------------------------------------------------------------------

local TONE_BYTES = 12
local TYPE_SPLIT, TYPE_RHYTHM = 0x40, 0x80
local WAVE_HEADER = 16

local function u8At(image, base, at)
  local b = image:byte(at - base + 1)
  return b
end

local function u16At(image, base, at)
  local a, b = image:byte(at - base + 1, at - base + 2)
  if not b then return nil end
  return a + b * 256
end

local function u32At(image, base, at)
  local a, b, c, d = image:byte(at - base + 1, at - base + 4)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

local function pointerAt(image, base, at)
  local v = u32At(image, base, at)
  if not v or v < 0x08000000 or v >= 0x0A000000 then return nil end
  return v - 0x08000000
end

-- struct WaveData, read once per instrument and cached on the engine
local function waveInfo(engine, at)
  local hit = engine.waves[at]
  if hit ~= nil then return hit or nil end
  local image, base = engine.image, engine.base
  local status = u16At(image, base, at + 2)
  local freq = u32At(image, base, at + 4)
  local loopStart = u32At(image, base, at + 8)
  local size = u32At(image, base, at + 12)
  if not (status and freq and loopStart and size) or size == 0
     or size > 4 * 1024 * 1024 then
    engine.waves[at] = false
    return nil
  end
  local info = {
    -- the cartridge stores the pitch as Hz shifted ten places, for a note
    -- played at middle C
    midC = freq / 1024,
    -- 0x4000 in the status word is what says a held note keeps sounding
    -- instead of stopping when the sample runs out
    loops = (status % 0x8000) >= 0x4000,
    loopStart = loopStart,
    size = size,
    data = at + WAVE_HEADER,
  }
  engine.waves[at] = info
  return info
end

-- The record VOICE `index` selects, resolved through a key split or a drum
-- kit if that is what it turns out to be.  Returns the record and the key to
-- sound it at.
local function instrument(engine, group, index, key, depth)
  if not group then return nil end
  local image, base = engine.image, engine.base
  -- VOICE's argument is an argument byte, so a track can only ever name
  -- 0..127; the cry table is addressed the same way and is longer than that,
  -- which is why the index is NOT folded here
  local at = group + index * TONE_BYTES
  local kind = u8At(image, base, at)
  if not kind then return nil end

  if (kind == TYPE_SPLIT or kind == TYPE_RHYTHM) and (depth or 0) < 3 then
    local sub = pointerAt(image, base, at + 4)
    if not sub then return nil end
    local pick = key % 128
    if kind == TYPE_SPLIT then
      local table_ = pointerAt(image, base, at + 8)
      if table_ then
        local mapped = u8At(image, base, table_ + (key % 128))
        if mapped then pick = mapped % 128 end
      end
      -- a key split keeps the note; only the instrument changes
      return instrument(engine, sub, pick, key, (depth or 0) + 1)
    end
    -- a drum kit: the note picked the drum, and the drum says its own pitch
    local drumKey = u8At(image, base, sub + pick * TONE_BYTES + 1) or key
    return instrument(engine, sub, pick, drumKey, (depth or 0) + 1)
  end

  local psg = kind % 8                     -- 1,2 square  3 wave  4 noise
  return {
    kind = kind,
    -- 0x08 on a SAMPLED instrument means the note picks the drum rather than
    -- the pitch.  On a Game Boy channel it means something else entirely --
    -- almost every CGB record in the cartridge carries it, and reading it as
    -- "fixed pitch" would flatten every square-lead melody in Hoenn to one
    -- note.
    fixed = psg == 0 and kind % 16 >= 8,
    psg = psg,
    key = u8At(image, base, at + 1) or 60,
    length = u8At(image, base, at + 2) or 0,
    panSweep = u8At(image, base, at + 3) or 0,
    wav = u32At(image, base, at + 4) or 0,
    attack = u8At(image, base, at + 8) or 255,
    decay = u8At(image, base, at + 9) or 255,
    sustain = u8At(image, base, at + 10) or 255,
    release = u8At(image, base, at + 11) or 255,
  }, key
end

-- ---------------------------------------------------------------------------
-- SOUNDING NOTES
-- ---------------------------------------------------------------------------

local ENV_ATTACK, ENV_DECAY, ENV_SUSTAIN, ENV_RELEASE = 1, 2, 3, 4

local Voice = {}
Voice.__index = Voice

local function noteFrequency(key)
  -- equal temperament off A440; the Game Boy channels take their pitch this
  -- way, and so does a sampled instrument once its own middle C is known
  return 440 * 2 ^ ((key - 69) / 12)
end

-- how far above its named note the noise channel's shift register runs
local NOISE_CLOCK = 32

local function newVoice(engine, track, tone, key, velocity)
  local self = setmetatable({
    engine = engine, track = track, tone = tone,
    velocity = velocity or 127,
    env = 0, state = ENV_ATTACK,
    pos = 0, phase = 0,
    lfsr = 0x7FFF,
    ticks = -1,               -- -1 = tied: sounds until EOT
    key = key,
  }, Voice)

  if tone.psg == 0 then
    local wave = waveInfo(engine, tone.wav - 0x08000000)
    if not wave then return nil end
    self.wave = wave
    local sounded = tone.fixed and tone.key or key
    self.baseRate = wave.midC * 2 ^ ((sounded - 60) / 12)
  else
    -- a Game Boy channel, whose envelope counts in SIXTEEN levels and frames
    -- per level rather than the sampled path's 0..255 (see stepEnvelope)
    self.cgb = true
    self.level, self.envFrames = 0, 0
    self.baseRate = noteFrequency(key)
    if tone.psg == 4 then
      -- noise is a shift register clocked far above the note it is named
      -- by; the note picks how bright the hiss is
      self.baseRate = self.baseRate * NOISE_CLOCK
    elseif tone.psg == 3 then
      -- the programmable wave's own 32 four-bit steps
      self.waveTable = tone.wav - 0x08000000
    end
  end
  self:retune()
  return self
end

-- the track's bend, its fine tune and its transposition, folded into the rate
function Voice:retune()
  local track = self.track
  local cents = (track.bend or 0) * (track.bendRange or 2)
                + (track.tune or 0)
  local scale = 2 ^ (cents / 12)
  if self.wave then
    self.step = self.baseRate * scale / M4A.SAMPLE_RATE
  else
    self.step = self.baseRate * scale / M4A.SAMPLE_RATE
  end
end

function Voice:release()
  if self.state ~= ENV_RELEASE then
    self.state = ENV_RELEASE
    self.envFrames = 0
    -- a release of zero is a hard stop, which is what percussion wants
    if self.cgb then
      if (self.tone.release or 0) % 8 == 0 then self.level, self.env = 0, 0 end
    elseif (self.tone.release or 0) == 0 then
      self.env = 0
    end
  end
end

function Voice:dead()
  return self.state == ENV_RELEASE and self.env <= 0
end

-- THE GAME BOY'S ENVELOPE, which is not the sampled one with different
-- numbers: it is sixteen LEVELS, and its attack/decay/release say how many
-- frames one level takes rather than how far to move in one frame.  Nought
-- means "immediately".
--
-- Read as the sampled envelope, every Game Boy instrument in the cartridge
-- was silent: their attack byte is almost always 0, which as a per-frame
-- increment means the volume never leaves the floor.  That was every menu
-- blip, every bump into a wall, every door.
local CGB_LEVELS = 15

function Voice:stepCgbEnvelope()
  local tone = self.tone
  local attack = tone.attack % 8
  local decay = tone.decay % 8
  local sustain = tone.sustain % 16
  local release = tone.release % 8
  local state = self.state
  self.envFrames = self.envFrames + 1

  if state == ENV_ATTACK then
    if attack == 0 then
      self.level = CGB_LEVELS
      self.state = ENV_DECAY
    elseif self.envFrames >= attack then
      self.envFrames = 0
      self.level = self.level + 1
      if self.level >= CGB_LEVELS then
        self.level = CGB_LEVELS
        self.state = ENV_DECAY
      end
    end
  elseif state == ENV_DECAY then
    if decay == 0 then
      self.level = sustain
      self.state = ENV_SUSTAIN
    elseif self.envFrames >= decay then
      self.envFrames = 0
      self.level = self.level - 1
      if self.level <= sustain then
        self.level = sustain
        self.state = ENV_SUSTAIN
      end
    end
  elseif state == ENV_SUSTAIN then
    self.level = sustain
  else
    if release == 0 then
      self.level = 0
    elseif self.envFrames >= release then
      self.envFrames = 0
      self.level = self.level - 1
      if self.level < 0 then self.level = 0 end
    end
  end
  self.env = math.floor(self.level * 255 / CGB_LEVELS)
end

-- one engine frame of the volume envelope
function Voice:stepEnvelope()
  if self.cgb then return self:stepCgbEnvelope() end
  local tone = self.tone
  local state = self.state
  if state == ENV_ATTACK then
    self.env = self.env + (tone.attack or 255)
    if self.env >= 255 then self.env = 255 self.state = ENV_DECAY end
  elseif state == ENV_DECAY then
    self.env = math.floor(self.env * (tone.decay or 255) / 256)
    if self.env <= (tone.sustain or 0) then
      self.env = tone.sustain or 0
      self.state = ENV_SUSTAIN
    end
  elseif state == ENV_SUSTAIN then
    self.env = tone.sustain or 0
  else
    self.env = math.floor(self.env * (tone.release or 0) / 256)
  end
end

-- one output sample, -1..1, before the track's volume and pan
function Voice:sample()
  local wave = self.wave
  if wave then
    local pos = self.pos
    if pos >= wave.size then
      if not wave.loops then self.state = ENV_RELEASE self.env = 0 return 0 end
      local span = wave.size - wave.loopStart
      if span <= 0 then self.env = 0 return 0 end
      pos = wave.loopStart + (pos - wave.loopStart) % span
      self.pos = pos
    end
    local byte = self.engine.image:byte(
      wave.data + math.floor(pos) - self.engine.base + 1)
    self.pos = pos + self.step
    if not byte then return 0 end
    if byte >= 128 then byte = byte - 256 end
    return byte / 128
  end

  local psg = self.tone.psg
  local phase = self.phase + self.step
  if psg == 4 then
    -- noise: step the shift register once per period rather than per sample
    local out = (self.lfsr % 2 == 0) and 1 or -1
    while phase >= 1 do
      phase = phase - 1
      local r = self.lfsr
      local bit0 = r % 2
      local bit1 = math.floor(r / 2) % 2
      r = math.floor(r / 2)
      if bit0 ~= bit1 then r = r + 0x4000 end
      self.lfsr = r
    end
    self.phase = phase
    return out
  end
  self.phase = phase % 1
  if psg == 3 and self.waveTable then
    local step = math.floor(self.phase * 32)
    local byte = self.engine.image:byte(
      self.waveTable + math.floor(step / 2) - self.engine.base + 1)
    if not byte then return 0 end
    local nibble = (step % 2 == 0) and math.floor(byte / 16) or (byte % 16)
    return (nibble - 7.5) / 7.5
  end
  -- square, at the duty the record asks for
  local duty = ({ [0] = 0.125, 0.25, 0.5, 0.75 })[self.tone.wav % 4] or 0.5
  return self.phase < duty and 1 or -1
end

-- ---------------------------------------------------------------------------
-- TRACKS
-- ---------------------------------------------------------------------------

local Track = {}
Track.__index = Track

local function newTrack(engine, at)
  return setmetatable({
    engine = engine, pc = at, wait = 0, running = nil,
    voice = 0, volume = 100, pan = 0, bend = 0, bendRange = 2, tune = 0,
    keyShift = 0, ended = false,
    stack = {}, repeats = {},
    lastKey = 60, lastVelocity = 127,
    voices = {},
  }, Track)
end

function Track:cut(all)
  for i = #self.voices, 1, -1 do
    local v = self.voices[i]
    if all or v.ticks == 0 then v:release() end
  end
end

function Track:noteOn(key, velocity, ticks)
  local engine = self.engine
  local tone, sounded = instrument(engine, engine.voicegroup, self.voice, key)
  if not tone then return end
  local voice = newVoice(engine, self, tone, sounded or key, velocity)
  if not voice then return end
  voice.ticks = ticks
  voice.bornTick = engine.tickIndex
  self.voices[#self.voices + 1] = voice
  engine.voices[#engine.voices + 1] = voice
end

-- ---------------------------------------------------------------------------
-- THE ENGINE
-- ---------------------------------------------------------------------------

local Engine = {}
Engine.__index = Engine

local TEMPO_UNIT = 150          -- the tick threshold the cartridge counts to
local DEFAULT_TEMPO = 150       -- one tick per frame

function M4A.newEngine(data, def, options)
  options = options or {}
  local audio = (data and data.audio) or {}
  local gen3 = audio.gen3 or {}
  local image = loadImage(audio)
  if type(def) ~= "table" or type(def.tracks) ~= "table" or #def.tracks == 0 then
    error("this song has no tracks")
  end
  local self = setmetatable({
    image = image,
    base = gen3.base or 0,
    voicegroup = def.voicegroup,
    allowLoops = options.allowLoops ~= false,
    waves = {},
    voices = {},
    tracks = {},
    tempo = DEFAULT_TEMPO,
    tempoCounter = 0,
    -- WHICH TICK IT IS, because a note keyed on THIS tick has not had its
    -- tick yet.  See Engine:tick.
    tickIndex = 0,
    frameLeft = 0,
    volume = options.volume or 1,
  }, Engine)
  for i, at in ipairs(def.tracks) do
    self.tracks[i] = newTrack(self, at)
  end
  return self
end

function Engine:byte(at)
  return self.image:byte(at - self.base + 1)
end

function Engine:pointer(at)
  return pointerAt(self.image, self.base, at)
end

-- one command; returns false when the track has run out
function Engine:step(track)
  local c = self:byte(track.pc)
  if not c then track.ended = true return false end
  local cmd, at
  if c < 0x80 then
    cmd, at = track.running, track.pc
    if not cmd then track.ended = true return false end
  else
    cmd, at = c, track.pc + 1
    if cmd >= 0xBD then track.running = cmd end
  end

  if cmd >= 0x80 and cmd <= 0xB0 then
    track.wait = CLOCK[cmd - 0x80] or 0
    track.pc = at
    return true
  end

  if cmd == 0xB1 then                       -- FINE
    track.pc = at
    track.ended = true
    track:cut(true)
    return false
  end

  if cmd == 0xB2 then                       -- GOTO: the song's loop
    local target = self:pointer(at)
    if not (target and self.allowLoops) then
      track.ended = true
      track:cut(true)
      return false
    end
    track.pc = target
    track.running = nil
    self.looped = true
    return true
  end

  if cmd == 0xB3 then                       -- PATT: call
    local target = self:pointer(at)
    track.stack[#track.stack + 1] = at + 4
    track.pc = target or (at + 4)
    return true
  end

  if cmd == 0xB4 then                       -- PEND: return
    -- ...but only from a pattern.  A PEND with nothing to return to is not
    -- the end of the track: the cartridge's own handler does NOTHING in that
    -- case and lets the command pointer walk past it, and a track that fell
    -- into a pattern body rather than calling it relies on exactly that.
    -- Ending the track here cut two of every three map themes off after
    -- about nine seconds.
    local back = table.remove(track.stack)
    track.pc = back or at
    return true
  end

  if cmd == 0xB5 then                       -- REPT
    -- a count of zero is the cartridge's "for ever"
    local count = self:byte(at) or 0
    local target = self:pointer(at + 1)
    local key = at
    if target and count == 0 then
      track.pc = target
      return true
    end
    local seen = (track.repeats[key] or 0) + 1
    if target and seen < count then
      track.repeats[key] = seen
      track.pc = target
    else
      track.repeats[key] = nil
      track.pc = at + 5
    end
    return true
  end

  local fixed = FIXED_ARGS[cmd]
  if fixed then
    local arg = self:byte(at)
    if cmd == 0xBB then                     -- TEMPO, in half beats a minute
      self.tempo = (arg or 75) * 2
    elseif cmd == 0xBC then                 -- KEYSH, signed
      track.keyShift = (arg or 0) < 128 and arg or (arg - 256)
    elseif cmd == 0xBD then                 -- VOICE
      track.voice = arg or 0
    elseif cmd == 0xBE then                 -- VOL
      track.volume = arg or 100
    elseif cmd == 0xBF then                 -- PAN, centred on 64
      track.pan = ((arg or 64) - 64) / 64
    elseif cmd == 0xC0 then                 -- BEND, centred on 64
      track.bend = ((arg or 64) - 64) / 64
      for _, v in ipairs(track.voices) do v:retune() end
    elseif cmd == 0xC1 then                 -- BENDR, in semitones
      track.bendRange = arg or 2
      for _, v in ipairs(track.voices) do v:retune() end
    elseif cmd == 0xC8 then                 -- TUNE, centred on 64
      track.tune = ((arg or 64) - 64) / 64
      for _, v in ipairs(track.voices) do v:retune() end
    end
    track.pc = at + fixed
    return true
  end

  if cmd >= 0xCE then
    -- key, velocity and a gate extension, each of them optional: an absent
    -- one keeps whatever the track played last
    local n, o = noteArgs(cmd), at
    local args = {}
    while #args < n do
      local b = self:byte(o)
      if not b or b >= 0x80 then break end
      args[#args + 1] = b
      o = o + 1
    end
    track.pc = o
    if cmd == 0xCE then                     -- EOT: let the tied notes go
      track:cut(true)
      return true
    end
    local key = args[1] or track.lastKey
    local velocity = args[2] or track.lastVelocity
    track.lastKey, track.lastVelocity = key, velocity
    local ticks = (cmd == 0xCF) and -1
                  or ((CLOCK[cmd - 0xCF] or 1) + (args[3] or 0))
    track:noteOn(key + track.keyShift, velocity, ticks)
    return true
  end

  -- unreachable on a cartridge that walked clean at import
  track.ended = true
  return false
end

-- one tick: every track that is not waiting runs commands until it is
-- A NOTE KEYED ON THIS TICK HAS NOT HAD ITS TICK YET.
--
-- The countdown below runs after the track has stepped, so a note started in
-- this tick used to be counted down in the same tick it began -- every note
-- in the cartridge came out one tick short, and a note whose whole gate IS
-- one tick was released before a single sample was drawn from it and pruned
-- at the end of the frame.  That is why the PokeNav rang silently, why
-- swapping a Pokemon in battle made no sound, and why nothing in Hoenn with
-- a one-tick percussion hit could be heard: the voice existed for exactly no
-- audio at all.  bornTick is the guard.
function Engine:tick()
  self.tickIndex = self.tickIndex + 1
  for _, track in ipairs(self.tracks) do
    if not track.ended then
      if track.wait > 0 then track.wait = track.wait - 1 end
      local guard = 0
      while not track.ended and track.wait == 0 do
        guard = guard + 1
        if guard > 4096 then track.ended = true break end
        if not self:step(track) then break end
      end
    end
    -- notes count down in ticks, and let go when they run out
    for i = #track.voices, 1, -1 do
      local v = track.voices[i]
      if v.ticks > 0 and v.bornTick ~= self.tickIndex then
        v.ticks = v.ticks - 1
        if v.ticks == 0 then v:release() end
      end
    end
  end
end

-- one engine frame: the tempo says how many ticks fit in it, then every
-- sounding note steps its envelope once
function Engine:frame()
  self.tempoCounter = self.tempoCounter + self.tempo
  while self.tempoCounter >= TEMPO_UNIT do
    self.tempoCounter = self.tempoCounter - TEMPO_UNIT
    self:tick()
  end
  local voices = self.voices
  for i = #voices, 1, -1 do
    local v = voices[i]
    v:stepEnvelope()
    if v:dead() then
      table.remove(voices, i)
      local own = v.track.voices
      for k = #own, 1, -1 do
        if own[k] == v then table.remove(own, k) break end
      end
    end
  end
end

local function clamp(v)
  if v > 1 then return 1 elseif v < -1 then return -1 end
  return v
end

-- The mix.  Sixteen tracks of sampled instruments will clip a naive sum, and
-- the cartridge's own mixer divides down too; a quarter is what keeps a full
-- battle theme inside the rails without making a two-track jingle inaudible.
local MIX_SCALE = 0.6
local PSG_LEVEL = 0.45

function Engine:sampleStereo()
  if self.frameLeft <= 0 then
    self:frame()
    self.frameLeft = SAMPLES_PER_FRAME
  end
  self.frameLeft = self.frameLeft - 1
  local left, right = 0, 0
  local voices = self.voices
  for i = 1, #voices do
    local v = voices[i]
    local env = v.env
    if env > 0 then
      local track = v.track
      local gain = (env / 255) * (v.velocity / 127) * (track.volume / 127)
      -- a square at full scale is far louder than a sampled instrument at
      -- the same nominal level, which is true of the hardware too and is
      -- why the cartridge mixes them down
      if v.cgb then gain = gain * PSG_LEVEL end
      local value = v:sample() * gain
      local pan = track.pan
      left = left + value * (1 - math.max(0, pan))
      right = right + value * (1 + math.min(0, pan))
    else
      v:sample()
    end
  end
  local scale = MIX_SCALE * self.volume
  return clamp(left * scale), clamp(right * scale)
end

function Engine:sample()
  local left, right = self:sampleStereo()
  return (left + right) / 2
end

function Engine:finished()
  if #self.voices > 0 then return false end
  for _, track in ipairs(self.tracks) do
    if not track.ended then return false end
  end
  return true
end

M4A.newTrack = newTrack

-- ---------------------------------------------------------------------------
-- CRIES
--
-- A Gen 3 cry is not a program with a pitch shift and a length, the way Gen
-- 1's and Gen 2's are.  It is a RECORDING, and the cartridge holds one per
-- species in a table of the same twelve-byte instrument records a voicegroup
-- is made of -- so it plays through exactly the machinery above, as a single
-- note at the pitch it was recorded at.
--
-- One-shot, so it is rendered whole into a buffer rather than streamed: a
-- cry is under a second and the caller wants a Source it can start, stop and
-- poll (Sound.playCry blocks on it, the way the cartridge's own PlayCry
-- does).
-- ---------------------------------------------------------------------------

local CRY_KEY = 60          -- the key every cry record is recorded at
local CRY_CAP = 5           -- seconds; nothing in the cartridge is close
-- the samples are eight-bit and mastered to the rail, so played back at
-- full scale every cry clips; a cry still wants to be well above the music,
-- which sits around a tenth of full scale
local CRY_GAIN = 0.5

function M4A.renderCry(data, index, options)
  options = options or {}
  local audio = (data and data.audio) or {}
  local gen3 = audio.gen3 or {}
  local cries = audio.gen3Cries or {}
  if not (cries.table and index) then return nil end
  local engine = setmetatable({
    image = loadImage(audio),
    base = gen3.base or 0,
    waves = {},
    voices = {},
    tracks = {},
  }, Engine)
  local track = newTrack(engine, 0)
  track.volume = 127
  local tone = instrument(engine, cries.table, index, CRY_KEY)
  if not tone then return nil end
  local voice = newVoice(engine, track, tone, CRY_KEY, 127)
  if not voice then return nil end

  -- the sample's own length, which is what the record already told the
  -- import stage; a cap in case a record ever names a looping sample
  -- the sample's own length: `step` is how far the source advances per
  -- output sample, so its length over that is how long it takes to play
  local seconds = options.seconds
  if not seconds and voice.wave and voice.step > 0 then
    seconds = voice.wave.size / (voice.step * SAMPLE_RATE)
  end
  seconds = math.min(CRY_CAP, math.max(0.05, seconds or 1))
  local samples = math.floor(SAMPLE_RATE * seconds)
  if samples < 64 then return nil end

  -- two channels for the same reason every other one-shot here is stereo:
  -- OpenAL spatializes a mono Source at the listener and spreads it over
  -- every output the device has
  local result = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 2)
  local gain = (options.volume or 1) * CRY_GAIN
  local frame, left = 0, 0
  for i = 0, samples - 1 do
    if frame <= 0 then
      voice:stepEnvelope()
      frame = SAMPLES_PER_FRAME
    end
    frame = frame - 1
    local value = voice:sample() * (voice.env / 255) * gain
    if value > 1 then value = 1 elseif value < -1 then value = -1 end
    result:setSample(i, 1, value)
    result:setSample(i, 2, value)
    left = value
  end
  local _ = left
  return result
end

-- ---------------------------------------------------------------------------
-- ONE-SHOT EFFECTS
--
-- A Gen 3 sound effect is a SONG.  The cartridge's own scripts say so --
-- `playse` takes a song number out of the same table the map themes come
-- from -- and the difference between an effect and a theme is only that an
-- effect ends instead of looping.  So this is the streaming engine run to
-- its end and handed over as one buffer, which is what a Source a caller can
-- start, stop and poll wants.
--
-- Rendered with looping OFF, so a def that turns out to be a theme after all
-- stops at its loop point rather than filling the cap with music.
-- ---------------------------------------------------------------------------

local EFFECT_CAP = 8            -- seconds; the longest jingle is well under

function M4A.renderEffect(data, def, options)
  options = options or {}
  local ok, engine = pcall(M4A.newEngine, data, def, { allowLoops = false })
  if not (ok and engine) then return nil end
  local cap = math.floor(SAMPLE_RATE * math.min(EFFECT_CAP,
                                                options.seconds or EFFECT_CAP))
  local left, right, n, audible = {}, {}, 0, 0
  while n < cap do
    local l, r = engine:sampleStereo()
    n = n + 1
    left[n], right[n] = l, r
    local a = l < 0 and -l or l
    local b = r < 0 and -r or r
    if a > 0.002 or b > 0.002 then audible = n end
    if engine:finished() then break end
  end
  -- trim the tail: the sequencer keeps counting after the last note lets go,
  -- and a Source that is mostly silence blocks a caller waiting on it
  local length = math.min(n, audible + math.floor(SAMPLE_RATE * 0.05))
  if length < 64 then return nil end
  local result = love.sound.newSoundData(length, SAMPLE_RATE, 16, 2)
  for i = 1, length do
    result:setSample(i - 1, 1, left[i])
    result:setSample(i - 1, 2, right[i])
  end
  return result
end

-- The same shape ChipSynth hands ChipAudio, so the queueing path does not
-- have to know which generation it is filling buffers for.
function M4A.soundData(engine, samples, channels)
  local result = love.sound.newSoundData(samples, SAMPLE_RATE, 16, channels)
  for index = 0, samples - 1 do
    if channels == 2 then
      local left, right = engine:sampleStereo()
      result:setSample(index, 1, left)
      result:setSample(index, 2, right)
    else
      result:setSample(index, engine:sample())
    end
  end
  return result
end

return M4A
