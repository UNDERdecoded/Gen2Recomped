-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root = assert(os.getenv("AUDIO_PROFILE_ROOT"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Pcm = require("src.core.AudioPcm")
local Performance = require("src.core.Performance")
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
local names = { "src.core.ChipSynth", "src.core.M4ASynth" }
local function engine()
  return {
    at = 0,
    sample = function(self)
      self.at = self.at + 1
      -- Include signed extremes and values near the native float/int boundary.
      return self.at % 7 == 0 and -1 or (self.at % 65535 - 32767) / 32767
    end,
    sampleStereo = function(self)
      local value = self:sample()
      return value, -value
    end,
  }
end
local checks = 0
local function qualifyEffects()
  -- The QA app lives in tools/. Adapt only module file resolution; the
  -- actual worker and channel protocol still run in a fresh native Lua state.
  local newThread = love.thread.newThread
  love.thread.newThread = function(path)
    assert(path == "src/core/chip_worker.lua", "unexpected worker")
    local boot = ('local root=%q; package.path=root.."/?.lua;"..package.path; require("love.filesystem"); love.filesystem.load=function(path)return loadfile(root.."/"..path)end; assert(loadfile(root.."/src/core/chip_worker.lua"))()'):format(
      root
    )
    return newThread(love.filesystem.newFileData(boot, "audio_qa_worker.lua"))
  end
  local Synth = require("src.core.ChipSynth")
  local Chip = require("src.core.ChipAudio")
  local Sound = require("src.core.Sound")
  local Runtime = require("src.mods.Runtime")
  local Asm = require("src.audio.ChipAsm")
  local effects, played, builds = {}, 0, 0
  love.audio = {
    newQueueableSource = function(_, _, _, capacity)
      local q = { capacity = capacity, buffers = {}, playing = false, volume = 1 }
      function q:stop()
        self.buffers = {}
        self.playing = false
      end
      function q:play()
        self.playing = true
      end
      function q:pause()
        self.playing = false
      end
      function q:isPlaying()
        return self.playing
      end
      function q:getFreeBufferCount()
        return self.capacity - #self.buffers
      end
      function q:queue(sd)
        assert(#self.buffers < self.capacity)
        self.buffers[#self.buffers + 1] = sd
      end
      function q:setVolume(v)
        self.volume = v
      end
      function q:getVolume()
        return self.volume
      end
      return q
    end,
    newSource = function(sd)
      builds = builds + 1
      local source = { sd = sd, volume = 1, plays = 0 }
      function source:setVolume(v)
        self.volume = v
      end
      function source:stop()
        self.playing = false
      end
      function source:play()
        self.plays = self.plays + 1
        self.playing = true
      end
      function source:isPlaying()
        return self.playing
      end
      function source:release()
        self.released = true
      end
      effects[#effects + 1] = source
      return source
    end,
  }
  local oldEmit, oldWants = Runtime.emit, Runtime.wants
  Runtime.wants = function(name)
    return name == "sound.played"
  end
  Runtime.emit = function(name)
    if name == "sound.played" then
      played = played + 1
    end
  end
  local beep = Asm.song({
    tempo = 0x100,
    channels = {
      {
        hw = 1,
        program = {
          { duty = 2 },
          { notetype = { speed = 1, volume = 12, fade = 0 } },
          { octave = 4 },
          { note = "C", len = 1 },
        },
      },
    },
  })
  local data = { audio = { sfx = { beep = beep }, cries = { MON = { header = beep, pitch = 0, length = 128 } } } }
  local function wait(count)
    local deadline = love.timer.getTime() + 10
    repeat
      Sound.update(data)
      love.timer.sleep(0.001)
    until builds >= count or love.timer.getTime() > deadline
    assert(builds >= count, "prewarm worker did not deliver its PCM")
  end
  wait(2)
  assert(played == 0 and effects[1].plays == 0 and effects[2].plays == 0, "prewarm played/emitted")
  Performance.audioWorkerOptimization = false
  local expected = Synth.renderEffectData(data, beep, { frequencyOffset = 0, frameTicks = 256 })
  Performance.audioWorkerOptimization = true
  local before = builds
  local source = assert(Sound.play(data, "beep"))
  assert(builds == before and source.sd:getString() == expected:getString(), "prewarm did not reuse exact cached PCM")
  assert(played == 1 and source.plays == 1, "real sound event/play count changed")
  checks = checks + 4
  Sound.invalidate()
  Chip.cancelEffects()
  wait(before + 2)
  -- A changed mix invalidates an unused speculative source, while used
  -- sources keep the original cache semantics.
  Chip.setChannelVolume(1, 0.4)
  before = builds
  assert(Sound.play(data, "beep"))
  assert(builds == before + 1, "stale speculative mix was reused")
  checks = checks + 1
  Sound.invalidate()
  -- A wholly owned tiny M4A image: one sampled voice and a short sequence.
  local function word(n)
    local out = {}
    for i = 1, 4 do
      out[i] = string.char(n % 256)
      n = math.floor(n / 256)
    end
    return table.concat(out)
  end
  local image = string.char(0, 60, 0, 0) .. word(0x08000040) .. string.rep(string.char(255), 4)
  image = image .. string.rep("\0", 16 - #image) .. string.char(0xBD, 0, 0xBE, 127, 0xD4, 60, 127, 0x85, 0xB1)
  image = image .. string.rep("\0", 64 - #image) .. word(0) .. word(32768 * 1024) .. word(0) .. word(128)
  for n = 1, 128 do
    image = image .. string.char(math.floor(math.sin(n * 0.17) * 100) % 256)
  end
  assert(love.filesystem.write("audio-owned-image.bin", image))
  data = {
    audio = {
      gen3 = { file = "audio-owned-image.bin", base = 0 },
      gen3Cries = { table = 0 },
      songs = { SONG_001 = { voicegroup = 0, tracks = { 16 } } },
      sfx = { sampled = { m4a = 1 } },
      cries = { SAMPLED = { m4a = 0 } },
    },
  }
  before = builds
  wait(before + 2)
  local M4A = require("src.core.M4ASynth")
  Performance.audioWorkerOptimization = false
  local effect = M4A.renderEffect(data, data.audio.songs.SONG_001)
  local cry = M4A.renderCry(data, 0)
  Performance.audioWorkerOptimization = true
  assert(effect and cry, "owned sampled fixture is silent/invalid")
  assert(Sound.play(data, "sampled").sd:getString() == effect:getString(), "sampled worker effect PCM differs")
  assert(Sound.playCry(data, "SAMPLED").sd:getString() == cry:getString(), "sampled worker cry PCM differs")
  assert(builds == before + 2, "sampled effects did not reuse Sound cache")
  checks = checks + 3
  Sound.invalidate()
  before = builds
  wait(before + 2)
  -- Def-local edits cannot reuse speculative bytes made before that edit.
  data.audio.sfx.sampled = { m4a = 99 }
  before = builds
  assert(Sound.play(data, "sampled") == nil and builds == before, "stale edited definition was played")
  Sound.invalidate()
  -- Cancelling in-flight jobs never admits their late SoundData into cache.
  Sound.update(data)
  Sound.suspend()
  before = builds
  local untilTime = love.timer.getTime() + 0.05
  repeat
    Sound.update(data)
    love.timer.sleep(0.001)
  until love.timer.getTime() > untilTime
  assert(builds == before, "late cancelled source entered a suspended cache")
  checks = checks + 2
  before = builds
  Sound.update(data)
  assert(builds == before and Sound.play(data, "beep") == nil, "suspended prewarm built/played")
  Sound.resume()
  Chip.setChannelVolume(1, 1)
  checks = checks + 1
  local dsChecks, ds = assert(loadfile(root .. "/tools/audio-profile-check/NitroCheck.lua"))()(root)
  checks = checks + dsChecks
  Sound.invalidate()
  data = { audio = { sfx = {}, cries = {} } }
  for i = 1, 240 do
    data.audio.sfx["cue" .. i] = beep
  end
  before = builds
  wait(before + 240)
  Runtime.emit, Runtime.wants = oldEmit, oldWants
  return {
    ds = ds,
    cold = function()
      return Chip.newSfx(data, "cue1")
    end,
    warm = function(i)
      return assert(Sound.play(data, "cue" .. i))
    end,
    close = function()
      ds.close()
      Sound.invalidate()
      Chip.shutdown()
      love.thread.newThread = newThread
      love.audio = nil
    end,
  }
end
local function qualify()
  for _, name in ipairs(names) do
    local synth = require(name)
    for _, channels in ipairs({ 1, 2 }) do
      local a, b = engine(), engine()
      Performance.audioWorkerOptimization = false
      local before = synth.soundData(a, 65536, channels)
      Performance.audioWorkerOptimization = true
      local after = synth.soundData(b, 65536, channels)
      assert(before:getString() == after:getString(), name .. " PCM differs")
      assert(a.at == b.at and a.at == 65536, "sample cadence changed")
      assert(not jit.status() or Pcm.pointer(after), "native FFI path is unavailable")
      before:release()
      after:release()
      checks = checks + 1
    end
  end
  local left, right = {}, {}
  for n = 1, 65536 do
    left[n], right[n] = (n % 65535 - 32767) / 32767, math.sin(n) * 0.9
  end
  for _, stereo in ipairs({ false, true }) do
    Performance.audioWorkerOptimization = false
    local before = Pcm.arrays(left, stereo and right or nil, 65536, 32768)
    Performance.audioWorkerOptimization = true
    local after = Pcm.arrays(left, stereo and right or nil, 65536, 32768)
    assert(before:getString() == after:getString(), "effect-array PCM differs")
    before:release()
    after:release()
    checks = checks + 1
  end
end
local phase, frame, total = 1, 0, 0
local results = {}
function love.errorhandler(message)
  print(debug.traceback(tostring(message), 2))
  local chip = package.loaded["src.core.ChipAudio"]
  if chip then
    pcall(chip.shutdown)
  end
  return function()
    return 1
  end
end
function love.run()
  qualify()
  local fx = qualifyEffects()
  local labels = {
    "setSample",
    "automatic PCM",
    "cold effect trigger",
    "prewarmed effect trigger",
    "legacy DS update",
    "worker DS update",
  }
  return function()
    love.event.pump()
    for event in love.event.poll() do
      if event == "quit" then
        return 1
      end
    end
    if frame == 120 then
      Profile.setEnabled(true)
    end
    Performance.audioWorkerOptimization = true
    if phase ~= 6 then
      fx.ds.keepAlive()
    end
    Performance.audioWorkerOptimization = phase >= 2
    local close = Profile.section(
      phase <= 2 and "audio.PCM write (8192 stereo)"
        or phase <= 4 and "audio.effect trigger (owned Source hardware)"
        or "audio.DS update (512 samples/frame consumption)"
    )
    local began = love.timer.getTime()
    local sound
    if phase <= 2 then
      sound = Pcm.render(engine(), 8192, 2, 32768)
    elseif phase == 3 then
      fx.cold()
    elseif phase == 4 then
      fx.warm(frame + 1)
    elseif phase == 5 then
      fx.ds.legacy()
    else
      fx.ds.threaded()
    end
    if frame >= 120 then
      total = total + love.timer.getTime() - began
    end
    close()
    if sound then
      sound:release()
    end
    love.graphics.clear(0.03, 0.04, 0.06)
    love.graphics.print(labels[phase], 12, 12)
    love.graphics.present()
    if frame >= 120 then
      Profile.frame()
    end
    frame = frame + 1
    if frame == 240 then
      results[phase] = { mode = labels[phase], frames = 120, meanMs = total / 120 * 1000 }
      if phase == 6 then
        fx.close()
        print("AUDIO_PCM_RESULT " .. Json.encode({
          phases = results,
          checks = checks,
          renderer = love.graphics.getRendererInfo(),
          os = love.system.getOS(),
          arch = jit.arch,
          jitEnabled = jit.status(),
          scope = "Native SoundData/worker, owned sample programs and Source hardware double; no device playback or cartridge music",
        }))
        return 0
      end
      Profile.setEnabled(false)
      phase, frame, total = phase + 1, 0, 0
    end
  end
end
