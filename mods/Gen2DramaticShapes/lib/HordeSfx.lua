-- HORDE MODE: the gun, in Game Boy hardware.
--
-- Every sound this mode makes is SYNTHESIZED on the same emulated APU the
-- rest of the game speaks through -- no sample files ship with the mod.
-- That is a deliberate aesthetic choice as much as a legal one: Lavender
-- Town is playing, the cries are the real cries, and a 44kHz foley
-- gunshot dropped on top would read as a different program running in the
-- same window. Authored here with ChipAsm (src/audio/ChipAsm.lua), which
-- assembles note tables into the channel bytecode ChipAudio interprets.
--
-- WHAT A GUNSHOT IS, on this hardware. Channel 4 is a noise generator
-- whose `parameter` byte is NR43: the high nibble is the shift clock (LOW
-- values are BRIGHT, high values are low rumble), bit 3 picks the short
-- 7-bit LFSR (metallic and pitched) over the long 15-bit one (white
-- hiss), and the low three bits divide. A real gunshot is a bright crack
-- collapsing into a body and then a room tail, so each sound here is a
-- STAGED program: three or four noise notes marching down the parameter
-- byte, each shorter-lived than the last. `len` is in frames of 1/60s,
-- `volume` is 0-15, and `fade` is the envelope period -- 1 decays fastest,
-- 7 slowest, 0 holds for the note's whole length.
--
-- The shot also gets two frames of channel 1 underneath it: a square note
-- swept hard downward, which is the only way to put a low thump on this
-- chip. It costs the music its lead channel for 1/30s per shot, which is
-- inaudible as interference and is most of what makes the shot feel like
-- it has weight.
--
-- THREE SHOT VARIANTS, round-robined. Sound.play caches ONE Source per
-- registered name and restarts it (stop then play), so firing twice on
-- one name cuts the first shot's tail off. Three names means three
-- Sources, so a fast trigger finger overlaps its own echoes the way a
-- real one does -- and the variants differ slightly in their tails, which
-- takes the machine-gun sameness off a repeated sound.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local HordeSfx = {}

-- the registered names, in the shape the rest of the mode asks for them
HordeSfx.SHOTS = { "DS_HORDE_SHOT_1", "DS_HORDE_SHOT_2", "DS_HORDE_SHOT_3" }
HordeSfx.DRY = "DS_HORDE_DRY"
HordeSfx.MAG_OUT = "DS_HORDE_MAG_OUT"
HordeSfx.MAG_IN = "DS_HORDE_MAG_IN"
HordeSfx.RACK = "DS_HORDE_RACK"
HordeSfx.HIT = "DS_HORDE_HIT"
HordeSfx.HURT = "DS_HORDE_HURT"
HordeSfx.WAVE = "DS_HORDE_WAVE"

-- ------- the programs

-- The shot's noise stage list: bright crack, body, tail, room. `tail`
-- lets the three variants differ in how the last stage rings out without
-- restating the whole program.
local function shotNoise(tail)
  return {
    -- the crack: one frame, full volume, brightest parameter the chip has
    { noiseNote = { len = 1, volume = 15, fade = 1, parameter = 0x00 } },
    -- the body: the shift clock drops, the 7-bit LFSR gives it a metallic
    -- edge -- this is the part that reads as "a mechanism did that"
    { noiseNote = { len = 2, volume = 13, fade = 2, parameter = 0x2C } },
    -- the tail: lower, softer, longer
    { noiseNote = { len = 3, volume = 8, fade = 3, parameter = tail[1] } },
    -- the room: a low breath of noise fading under everything
    { noiseNote = { len = tail[2], volume = 4, fade = 4, parameter = tail[3] } },
  }
end

-- The thump under the crack: channel 1's frequency register swept down
-- hard. 0x600 is around 250Hz; the sweep drags it into the floor over the
-- two frames it lives, which is a kick drum by another name.
local THUMP = {
  { pitchSweep = { pace = 2, subtract = true, shift = 3 } },
  { squareNote = { len = 2, volume = 12, fade = 2, frequency = 0x600 } },
}

local function shot(tail)
  return {
    channels = {
      { hw = 1, program = THUMP },
      { hw = 4, program = shotNoise(tail) },
    },
  }
end

-- The reload, in three separate sounds the gun fires on its own clock:
-- the magazine dropping out, the fresh one seating, and the slide coming
-- back and going home. Noise only -- these are mechanical clicks, and
-- keeping them off the tone channels leaves the music alone.
local PROGRAMS = {
  [HordeSfx.SHOTS[1]] = shot({ 0x55, 5, 0x76 }),
  [HordeSfx.SHOTS[2]] = shot({ 0x54, 6, 0x77 }),
  [HordeSfx.SHOTS[3]] = shot({ 0x65, 4, 0x86 }),

  -- the hammer falling on nothing: one dull tick, no tail
  [HordeSfx.DRY] = {
    channels = {
      { hw = 4, program = {
        { noiseNote = { len = 1, volume = 7, fade = 1, parameter = 0x38 } },
        { noiseNote = { len = 1, volume = 3, fade = 1, parameter = 0x54 } },
      } },
    },
  },

  -- the magazine leaving: a click and a soft drop away from it
  [HordeSfx.MAG_OUT] = {
    channels = {
      { hw = 4, program = {
        { noiseNote = { len = 1, volume = 10, fade = 1, parameter = 0x1A } },
        { noiseNote = { len = 2, volume = 5, fade = 2, parameter = 0x58 } },
      } },
    },
  },

  -- the fresh magazine seating: a firmer, lower clack with a bit of body
  [HordeSfx.MAG_IN] = {
    channels = {
      { hw = 4, program = {
        { noiseNote = { len = 1, volume = 13, fade = 1, parameter = 0x18 } },
        { noiseNote = { len = 2, volume = 8, fade = 2, parameter = 0x46 } },
        { noiseNote = { len = 2, volume = 3, fade = 3, parameter = 0x67 } },
      } },
    },
  },

  -- the slide: back (bright scrape), a frame of nothing, then home (hard)
  [HordeSfx.RACK] = {
    channels = {
      { hw = 4, program = {
        { noiseNote = { len = 2, volume = 9, fade = 2, parameter = 0x25 } },
        { rest = 1 },
        { noiseNote = { len = 1, volume = 14, fade = 1, parameter = 0x11 } },
        { noiseNote = { len = 2, volume = 6, fade = 2, parameter = 0x44 } },
      } },
    },
  },

  -- a bullet arriving: short, bright, gone -- the hit marker's own sound
  [HordeSfx.HIT] = {
    channels = {
      { hw = 4, program = {
        { noiseNote = { len = 1, volume = 11, fade = 1, parameter = 0x14 } },
        { noiseNote = { len = 1, volume = 5, fade = 2, parameter = 0x42 } },
      } },
    },
  },

  -- being hit: a low ugly thud on the noise channel with a square groan
  -- under it, sweeping DOWN -- the sound of losing something
  [HordeSfx.HURT] = {
    channels = {
      { hw = 1, program = {
        { pitchSweep = { pace = 3, subtract = true, shift = 4 } },
        { squareNote = { len = 6, volume = 11, fade = 3, frequency = 0x480 } },
      } },
      { hw = 4, program = {
        { noiseNote = { len = 2, volume = 12, fade = 2, parameter = 0x66 } },
        { noiseNote = { len = 4, volume = 6, fade = 3, parameter = 0x78 } },
      } },
    },
  },

  -- a wave arriving: two rising square stabs, deliberately not a fanfare
  [HordeSfx.WAVE] = {
    channels = {
      { hw = 1, program = {
        { squareNote = { len = 3, volume = 10, fade = 2, frequency = 0x5C0 } },
        { rest = 1 },
        { squareNote = { len = 6, volume = 12, fade = 3, frequency = 0x680 } },
      } },
    },
  },
}

-- ------- registration

-- Assemble every program and put it in the sfx registry. Called once from
-- main.lua at load. A malformed note table raises inside ChipAsm; each is
-- assembled under pcall so one bad program is one missing sound rather
-- than a mod that fails to load.
function HordeSfx.register(mod)
  local ok, ChipAsm = pcall(require, "src.audio.ChipAsm")
  if not (ok and ChipAsm) then return false end
  local n = 0
  for name, spec in pairs(PROGRAMS) do
    local built, out = pcall(ChipAsm.sfx, spec)
    if built and out and out.chip then
      local reg = pcall(function()
        mod.content.sfx:register(name, { chip = out.chip })
      end)
      if reg then n = n + 1 end
    elseif mod.log then
      mod.log:error("horde: sfx %s did not assemble: %s", name, tostring(out))
    end
  end
  return n > 0
end

-- ------- playback
--
-- One indirection so callers never touch Sound directly and a headless
-- run (no love.audio) costs a pcall rather than an error.

local function play(name)
  pcall(function()
    local Game = require("src.core.Game")
    require("src.core.Sound").play(Game.data, name)
  end)
end

HordeSfx.play = play

local shotIndex = 0

-- The next shot in the round-robin, so consecutive rounds overlap rather
-- than cutting each other off (see the header).
function HordeSfx.shot()
  shotIndex = shotIndex % #HordeSfx.SHOTS + 1
  play(HordeSfx.SHOTS[shotIndex])
end

-- ------- the cries
--
-- Every mob that dies screams as something from the national dex. The
-- list is built once from the live cry registry -- whatever the game and
-- whatever mods are loaded have between them -- so this needs no data of
-- its own and picks up a total conversion's roster for free.

local cryList = nil

local function cries()
  if cryList then return cryList end
  local out = {}
  pcall(function()
    local Game = require("src.core.Game")
    local table_ = Game.data and Game.data.audio and Game.data.audio.cries
    for species in pairs(table_ or {}) do out[#out + 1] = species end
  end)
  table.sort(out)   -- love.math.random over a stable order, not hash order
  cryList = out
  return out
end

-- A random cry, at a random-ish pitch. Nothing is more Pokemon than the
-- wrong animal noise coming out of a man in a suit.
function HordeSfx.randomCry()
  local list = cries()
  if #list == 0 then return nil end
  local species = list[love.math.random(#list)]
  pcall(function()
    local Game = require("src.core.Game")
    require("src.core.Sound").playCry(Game.data, species)
  end)
  return species
end

-- a fresh boot (or a hot reload) rebuilds the species list
function HordeSfx.invalidate()
  cryList = nil
end

return HordeSfx
