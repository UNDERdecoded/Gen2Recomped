-- Playback front end for the Game Boy audio synth (src/core/ChipSynth.lua).
--
-- Map/battle MUSIC is streamed from a background worker thread
-- (src/core/chip_worker.lua): the worker synthesizes the PCM buffers and this
-- module only queues finished SoundData onto a QueueableSource.  That is the
-- fix for the map-transition stutter -- filling the deep (~6s) playback queue
-- from scratch when a song changes is ~200ms of Lua synthesis, and doing it on
-- the render thread dropped frames for the ~10 frames after every seam
-- crossing.  Off-thread, a song change costs the main loop essentially
-- nothing.
--
-- When love.thread is unavailable (the headless test stub) or a worker fails
-- to start, music falls back to the original synchronous, amortized queue fill
-- so behavior is unchanged -- see the `threaded` branch in each entry point.
--
-- SFX and cries stay synchronous: they are short one-shots rendered once into
-- a static Source, not a per-frame streaming cost.

local Assets = require("src.render.Assets")
local ChipSynth = require("src.core.ChipSynth")

local ChipAudio = {}

-- ---------------------------------------------------------------------------
-- WHICH SYNTH.
--
-- Everything below -- the queueing, the worker, the per-channel mixer, the
-- underrun recovery -- is about MOVING PCM, not about making it.  Gen 3's
-- music is made by a completely different engine (src/core/M4ASynth.lua: a
-- sequencer over sampled instruments, not four Game Boy channels), and the
-- only thing this file has to know about it is that it answers the same three
-- methods: sample, sampleStereo, finished.
--
-- So a song def carries the name of the synth that can play it and every path
-- here goes through this one lookup.  A def with no name is a Game Boy song,
-- which is every song this module was originally written for.
-- ---------------------------------------------------------------------------
local SYNTHS = {
  chip = "src.core.ChipSynth",
  m4a = "src.core.M4ASynth",
}

local function synthFor(name)
  local module = SYNTHS[name or "chip"]
  if not module then return ChipSynth end
  local ok, synth = pcall(require, module)
  return (ok and synth) or ChipSynth
end

ChipAudio.SYNTHS = SYNTHS
ChipAudio.synthFor = synthFor

local SAMPLE_RATE = ChipSynth.SAMPLE_RATE
local MUSIC_BUFFER_SAMPLES = ChipSynth.MUSIC_BUFFER_SAMPLES
local MUSIC_BUFFER_COUNT = ChipSynth.MUSIC_BUFFER_COUNT

-- ---------------------------------------------------------------------------
-- Per-channel mix (edit these)
-- Applied on load and whenever this file hot-reloads.
-- Runtime: ChipAudio.setChannelVolume / setChannelPitch.
--   [1] pulse 1   [2] pulse 2   [3] wave   [4] noise / drums
-- Volume: 1 = authentic, 0 = mute, >1 boosts
-- Pitch:  1 = authentic, 2 = +1 octave, 0.5 = -1 octave
-- The shipped values stay at 1: 0.25 / 0.5 on the wave channel buried the Ch3
-- countermelodies an octave low (#429), and ChipSynth already applies the
-- wave channel's own hardware octave (frequency * 0.5).
-- ---------------------------------------------------------------------------
local CHANNEL_VOLUME = {
  [1] = 1, -- pulse 1
  [2] = 1, -- pulse 2
  [3] = 1, -- wave
  [4] = 1, -- noise / drums
}
local CHANNEL_PITCH = {
  [1] = 1, -- pulse 1
  [2] = 1, -- pulse 2
  [3] = 1, -- wave
  [4] = 1, -- noise / drums
}
ChipSynth.setChannelVolumes(CHANNEL_VOLUME)
ChipSynth.setChannelPitches(CHANNEL_PITCH)

-- currentMusic: { source, gen, threaded, started, finished, engine }
--   threaded songs stream from the worker (engine is nil here);
--   the fallback path owns a local engine and fills the source itself.
local currentMusic
local pendingBuf -- a current-gen buffer popped from the worker but not yet
                 -- queued because the Source was momentarily full

-- Music holds playback while a fanfare owns the music channels (#398).
-- Pausing the Source is not enough on its own: this module is what starts a
-- chip song (immediately on the sync path, on the first worker buffer on the
-- threaded one), so a song that begins during a jingle would come up
-- underneath it.  Music.duckForFanfare sets the hold, Music releases it when
-- the jingle ends.
local musicHeld = false

-- ---------------------------------------------------------------------------
-- AUDIO SESSION SUSPEND (mobile interruption: an incoming phone call)
--
-- Reported from play: "on iOS when they got a phone call the game would
-- crash".  On iOS an incoming call takes the audio session away from the app
-- outright; SDL reports it as SDL_APP_WILLENTERBACKGROUND /
-- SDL_APP_DIDENTERBACKGROUND, which LOVE delivers as love.focus(false) /
-- love.visible(false) -- main.lua -> Game:focus -> Music.suspend -> here.
-- Android delivers the same app events.
--
-- THIS module is the one that cannot ride that out on its own.  Sound effects
-- are static Sources played once on demand, but MUSIC is a queue fed a buffer
-- at a time: ChipAudio.update runs every frame and calls
-- Source:getFreeBufferCount and QueueableSource:queue on it.  So the frame the
-- device goes away is the frame we make an AL call against a device that no
-- longer exists; LOVE turns OpenAL's refusal into a love::Exception, and that
-- reaches Lua as an error thrown out of the middle of Music.update -- which is
-- the crash in the report.
--
-- Two halves, therefore, and both are needed:
--   * sessionSuspended, set once the event arrives, stops feeding the queue
--     at all while the OS holds the session; and
--   * the pcall'd helpers below, because the event arrives a frame LATE --
--     the interruption is already in effect while we are still finishing the
--     frame that will dispatch it, so that frame has to survive on its own.
local sessionSuspended = false

-- Wrap one audio call that cannot fail on a healthy device and CAN fail while
-- the OS holds the session.  Logged, never swallowed: a raise from here on
-- desktop, or while focused, is a real bug and the log line names the call.
-- debug level rather than warn because during an actual interruption this is
-- the expected outcome and would otherwise print once per frame.
local function safeAudio(what, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    require("src.core.Logger").debug(
      "chip audio: %s failed (%s) -- the audio device is gone or going "
      .. "(incoming call / backgrounding on mobile)", what, tostring(err))
  end
  return ok
end

-- Free buffers on the streaming Source, or nil when it will not answer.  The
-- queue loops below lead with this call, so it is also the first one an
-- invalidated OpenAL device raises from; nil means "stop queueing this frame"
-- and is deliberately distinct from 0, which means "the queue is full".
local function freeBuffers(source)
  local ok, free = pcall(source.getFreeBufferCount, source)
  if not ok then
    require("src.core.Logger").debug(
      "chip audio: getFreeBufferCount failed (%s) -- treating the audio "
      .. "device as gone until the focus event arrives", tostring(free))
    return nil
  end
  return free
end

-- ---------------------------------------------------------------------------
-- worker management
-- ---------------------------------------------------------------------------

local worker, cmdCh, outCh
local workerReady -- nil = untried, true = running, false = unavailable

local function ensureWorker()
  if workerReady ~= nil then return workerReady end
  -- ...including the one thing music cannot do without.  Without this the
  -- module announced "threaded worker", started a thread, and only then
  -- discovered it had nowhere to put the buffers.
  if not (love.audio and love.audio.newQueueableSource) then
    workerReady = false
    return false
  end
  if not (love.thread and love.thread.newThread and love.audio) then
    workerReady = false
    return false
  end
  local ok, thread = pcall(love.thread.newThread, "src/core/chip_worker.lua")
  if not ok or not thread then
    workerReady = false
    return false
  end
  cmdCh = love.thread.getChannel("chipaudio_cmd")
  outCh = love.thread.getChannel("chipaudio_out")
  local started = pcall(function() thread:start() end)
  if not started then
    workerReady = false
    return false
  end
  worker = thread
  workerReady = true
  return true
end

-- Music has three possible paths and picking the wrong one is SILENT, which
-- makes "no audio on <platform>" impossible to triage from a bug report.  Say
-- which one this host took, once.
local announced
local function announcePath(path, why)
  if announced then return end
  announced = true
  require("src.core.Logger").info("chip audio: music path = %s%s",
                                  path, why and (" (" .. why .. ")") or "")
end

-- Both music paths -- threaded and synchronous -- stand on ONE call the sound
-- effects never make: love.audio.newQueueableSource.  Effects are static
-- Sources built from a finished SoundData; music is a queue fed a buffer at a
-- time.  So "effects play, music does not" is not a vague symptom, it is a
-- fingerprint, and this is the only line in the module that can print it.
--
-- It was being thrown away.  Source creation is wrapped in pcall and the
-- failure returned to a caller that does not read the second value, so a host
-- without queueable sources went silent with nothing said anywhere -- on the
-- Switch, where there is no console, that is indistinguishable from the audio
-- simply not being wired up.
local queueWarned
local function warnNoQueue(err)
  if queueWarned then return end
  queueWarned = true
  require("src.core.Logger").warn(
    "chip audio: no music source -- love.audio.newQueueableSource %s. "
      .. "Sound effects are static Sources and are unaffected; music has no "
      .. "other path. (%s)",
    (love.audio and love.audio.newQueueableSource) and "failed" or "is missing",
    tostring(err))
end

-- only the tables ChipSynth.newEngine reads for ROM songs; sent with every
-- play so a hot-reloaded dataset (or a mod's audio) always reaches the worker
local function slimAudio(data)
  local audio = data.audio or {}
  return {
    programFile = audio.programFile,
    programPrefix = require('src.core.WorkerFs').prefix(),
    bankOrder = audio.bankOrder,
    waveBanks = audio.waveBanks,
    gen2Dialect = audio.gen2Dialect,
    drumkits = audio.gen2Dialect=="polishedcrystal" and audio.drumkits or nil,
    noiseHeaders = audio.noiseHeaders,
    -- the Gen 3 synth reads its bytecode, voicegroups and sampled
    -- instruments out of one image beside the cache; this is where it is
    gen3 = audio.gen3,
  }
end

-- If the worker died (a malformed def that errors mid-synth), fall back to the
-- synchronous path for the rest of the session instead of going silent.
local function workerAlive()
  if not worker then return false end
  local err = worker:getError()
  if err then
    require("src.core.Logger").warn("chip audio worker died: %s", tostring(err))
    workerReady = false
    worker = nil
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- synchronous fallback (no love.thread): the original amortized queue fill
-- ---------------------------------------------------------------------------

-- The queue is deep (MUSIC_BUFFER_COUNT, ~6s) for stall tolerance, but
-- synthesizing all of it on the frame a song starts renders ~6s of audio at
-- once.  Cap how many buffers each fill renders; playback drains ~1 buffer
-- every ~11 frames while update() tops up a few per frame, so the deep queue
-- still ramps to full within a fraction of a second.
local MUSIC_FILL_INITIAL = 4
local MUSIC_FILL_PER_CALL = 3

local function fillSync(limit)
  local music = currentMusic
  if not music or not music.engine or music.engine:finished() then return end
  -- INTERRUPTION: never synthesize into a Source whose device the OS has
  -- taken (see sessionSuspended).  Returning leaves the engine untouched, so
  -- nothing about the song's position is lost while the call is in progress.
  if sessionSuspended then return end
  limit = limit or MUSIC_FILL_PER_CALL
  local free = freeBuffers(music.source)
  if not free then return end
  while free > 0 and limit > 0 and not music.engine:finished() do
    -- soundData is pure synthesis and stays OUTSIDE the guard on purpose: a
    -- raise from there is a malformed song def, which is a real bug and must
    -- not be quietly turned into silence.  Only queue -- the call that talks
    -- to the device -- is guarded.
    local sd = (music.synth or ChipSynth)
                 .soundData(music.engine, MUSIC_BUFFER_SAMPLES, 2)
    if not safeAudio("QueueableSource:queue", music.source.queue,
                     music.source, sd) then
      return
    end
    free = free - 1
    limit = limit - 1
  end
end

local function playMusicSync(data, header, allowLoops, synthName)
  local synth = synthFor(synthName)
  -- build before tearing down: a def that fails to compile must leave the
  -- outgoing song sounding
  local ok, engine = pcall(synth.newEngine, data, header,
                           { allowLoops = allowLoops })
  if not ok then return nil, engine end
  local ok2, source = pcall(
    love.audio.newQueueableSource, SAMPLE_RATE, 16, 2, MUSIC_BUFFER_COUNT)
  if not ok2 or not source then warnNoQueue(source) return nil, source end
  ChipAudio.stopMusic()
  currentMusic = { source = source, engine = engine, threaded = false,
                   synth = synth, synthName = synthName,
                   started = true, finished = false }
  fillSync(MUSIC_FILL_INITIAL)
  if not musicHeld then source:play() end
  return source
end

-- ---------------------------------------------------------------------------
-- threaded music
-- ---------------------------------------------------------------------------

local musicGen = 0

function ChipAudio.playMusic(data, header, allowLoops, synthName)
  local synth = synthFor(synthName)
  if not ensureWorker() then
    announcePath("synchronous",
                 (love.thread and love.thread.newThread)
                   and "worker would not start" or "no love.thread")
    return playMusicSync(data, header, allowLoops, synthName)
  end
  announcePath("threaded worker")
  -- validate the def on this thread (cheap: engine construction, no synthesis)
  -- so a broken def costs nothing but a log line and keeps the old song
  local ok, engine = pcall(synth.newEngine, data, header,
                           { allowLoops = allowLoops })
  if not ok then return nil, engine end
  -- build the new source before tearing the old song down
  local ok2, source = pcall(
    love.audio.newQueueableSource, SAMPLE_RATE, 16, 2, MUSIC_BUFFER_COUNT)
  if not ok2 or not source then warnNoQueue(source) return nil, source end
  ChipAudio.stopMusic()
  musicGen = musicGen + 1
  local gen = musicGen
  cmdCh:push({ cmd = "play", gen = gen, header = header, synth = synthName,
               allowLoops = allowLoops, audio = slimAudio(data),
               channelVolumes = ChipSynth.getChannelVolumes(),
               stereo = ChipSynth.getStereo(),
               channelPitches = ChipSynth.getChannelPitches() })
  currentMusic = { source = source, gen = gen, threaded = true,
                   synth = synth, synthName = synthName,
                   started = false, finished = false,
                   -- kept so a worker that dies before delivering its first
                   -- buffer can be recovered onto the sync path below
                   def = { data = data, header = header,
                           allowLoops = allowLoops, synth = synthName } }
  -- playback starts in update() once the first buffer arrives (~1 frame)
  return source
end

local function pushChannelMix()
  if workerReady and cmdCh then
    cmdCh:push({ cmd = "channelMix",
                 volumes = ChipSynth.getChannelVolumes(),
                 stereo = ChipSynth.getStereo(),
                 pitches = ChipSynth.getChannelPitches() })
  end
end

-- move finished buffers from the worker into the Source; start playback once
-- the first one lands
local function updateThreaded()
  local m = currentMusic
  if not m then return end
  -- INTERRUPTION: the worker keeps producing into the hand-off channel (its
  -- own LOOKAHEAD bounds that), but nothing is queued into the Source while
  -- the OS holds the audio session.  ChipAudio.resume rebuilds the stream.
  if sessionSuspended then return end
  if not workerAlive() then
    -- The worker is gone.  If it already delivered buffers, let what is queued
    -- finish -- but if it died BEFORE the first one, this song has never made
    -- a sound and never will: nothing re-queues it, `started` stays false, and
    -- the result is indistinguishable from "this build has no music".  That is
    -- the shape of a silent port.  Re-drive it on the synchronous path, which
    -- is the same path a host without love.thread uses all the time.
    if not m.started and not m.finished and m.def then
      local def = m.def
      currentMusic = nil
      require("src.core.Logger").warn(
        "chip audio: worker died before first buffer, replaying on the "
        .. "synchronous path")
      playMusicSync(def.data, def.header, def.allowLoops, def.synth)
    end
    return
  end
  while true do
    local free = freeBuffers(m.source)
    -- nil, not 0: the Source refused to answer, so its device went away
    -- between the last frame and this one and the focus event has not been
    -- delivered yet.  Stop queueing; ChipAudio.suspend follows in a frame.
    if not free then break end
    local buf = pendingBuf
    if buf then pendingBuf = nil else buf = outCh:pop() end
    if not buf then break end
    if buf.gen ~= m.gen then
      -- stale buffer from a superseded song: drop it
    elseif buf.done then
      m.finished = true
    elseif buf.error then
      require("src.core.Logger").warn("chip audio: %s", tostring(buf.error))
      m.finished = true
    elseif buf.sd then
      if free > 0 then
        if not safeAudio("QueueableSource:queue", m.source.queue,
                         m.source, buf.sd) then
          -- the device went away mid-loop: keep the buffer rather than drop
          -- audio on the floor, and let the suspend/resume pair sort it out
          pendingBuf = buf
          break
        end
      else
        pendingBuf = buf -- Source full; hold this one for next frame
        break
      end
    end
  end
  if not m.started and not musicHeld then
    -- getFreeBufferCount used to be called bare here.  On the frame that
    -- straddles an interruption this is a raise, and it is raised from inside
    -- Music.update with nothing between it and love.run: one of the concrete
    -- shapes of the phone-call crash.
    local free = freeBuffers(m.source)
    if free and (MUSIC_BUFFER_COUNT - free) > 0 then
      pcall(function() m.source:play() end)
      m.started = true
    end
  end
end

function ChipAudio.update()
  local m = currentMusic
  if not m then return end
  -- INTERRUPTION: nothing is fed to the device while the OS holds the session
  if sessionSuspended then return end
  if m.threaded then
    updateThreaded()
  else
    fillSync()
  end
end

-- Recover from a queue underrun caused by a long render stall.  Called after
-- Music has handled intentional fanfare pauses, so it never fights the normal
-- pause/resume behavior.
function ChipAudio.ensureMusicPlaying()
  local m = currentMusic
  if not m or m.finished or musicHeld then return end
  -- INTERRUPTION: a queue that stopped draining because the OS took the
  -- audio session is not a render stall, and must not be "recovered" by
  -- poking the dead device once every frame of the call
  if sessionSuspended then return end
  if m.threaded then
    if not m.started then return end
    local ok, playing = pcall(function() return m.source:isPlaying() end)
    if ok and not playing then
      -- getFreeBufferCount sat OUTSIDE the pcall above: on the frame that
      -- straddles an interruption isPlaying can answer while this one raises
      local free = freeBuffers(m.source)
      if free and (MUSIC_BUFFER_COUNT - free) > 0 then
        pcall(function() m.source:play() end)
      end
    end
  else
    if not m.engine or m.engine:finished() then return end
    local ok, playing = pcall(m.source.isPlaying, m.source)
    if ok and not playing then
      fillSync(MUSIC_FILL_INITIAL)
      pcall(m.source.play, m.source)
    end
  end
end

-- Silence the song for the length of a fanfare and start whatever was held
-- back once it ends.  Held state outlives a song change: Music.play may swap
-- songs while the jingle is still sounding.
function ChipAudio.holdMusic(held)
  held = not not held
  if held == musicHeld then return end
  musicHeld = held
  if held then return end
  ChipAudio.update()
  ChipAudio.ensureMusicPlaying()
end

-- Threaded playMusic returns an empty QueueableSource and only calls
-- Source:play once the first worker buffer lands (~1 frame later).  Until
-- then Source:isPlaying is false -- callers that treat that as "song over"
-- (Music.oneShotPlaying / pendingRestore) must wait here instead, or a
-- playOnce jingle like Music_PkmnHealed is cut off before it starts.
local forceAwaitingFirstBuffer -- test-only override (see _simulate*)

function ChipAudio.awaitingFirstBuffer()
  if forceAwaitingFirstBuffer then return true end
  local m = currentMusic
  if not (m and m.threaded and not m.started and not m.finished) then
    return false
  end
  -- a dead worker will never deliver the first buffer
  if workerReady == false then return false end
  if worker and worker.getError and worker:getError() then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- audio session suspend / resume (see sessionSuspended at the top)
-- ---------------------------------------------------------------------------

-- Called from Music.suspend, which Game:focus / Game:visible drive on mobile
-- only.  Stops feeding the streaming Source and tells the worker to stop
-- producing, so a multi-minute phone call does not leave a full look-ahead of
-- stale buffers to dump into the player's ear on the way back.
function ChipAudio.suspend()
  if sessionSuspended then return end
  sessionSuspended = true
  pendingBuf = nil
  local m = currentMusic
  if m and m.source then
    -- pause rather than stop: stop is what resume does anyway, and doing it
    -- here would make the last thing we ask of a device that is being taken
    -- away the call most likely to raise
    safeAudio("Source:pause", m.source.pause, m.source)
  end
  if workerReady and cmdCh then cmdCh:push({ cmd = "stop" }) end
  if outCh then outCh:clear() end
end

-- Called from Music.resume once the app has the audio session back.
--
-- The streaming Source is DROPPED rather than resumed.  iOS hands the app a
-- new audio session after a call and OpenAL sources built against the old one
-- are not reliably usable again -- they come back mute, or refuse to play,
-- and there is no call that answers "is this Source still alive".  Music
-- re-cues the song by label immediately after this, so the price of always
-- rebuilding is that an interrupted song restarts from its beginning; the
-- price of guessing the other way is music that never comes back at all for
-- the rest of the session.
function ChipAudio.resume()
  if not sessionSuspended then return end
  sessionSuspended = false
  -- A worker that errored while the app was backgrounded gets collected by
  -- workerAlive(), which latches workerReady = false for the REST OF THE
  -- SESSION: music would silently drop to the synchronous path (and take its
  -- ~200ms-per-song-change stutter with it) even though nothing is wrong with
  -- this host's threads.  An interruption is not evidence that love.thread
  -- does not work here, so clear the latch and let the next play try one
  -- fresh worker.  Only when workerAlive() actually cleared `worker`: if a
  -- thread is still live, starting a second would leave two workers popping
  -- the same command channel.
  if workerReady == false and worker == nil then workerReady = nil end
  ChipAudio.stopMusic()
end

function ChipAudio.stopMusic()
  if currentMusic and currentMusic.source then
    pcall(currentMusic.source.stop, currentMusic.source)
  end
  if workerReady and cmdCh then
    cmdCh:push({ cmd = "stop" })
    if outCh then outCh:clear() end
  end
  pendingBuf = nil
  currentMusic = nil
  forceAwaitingFirstBuffer = nil
end

-- hot reload: the next play re-reads programs.bin (a mod may have swapped the
-- file out from under the single-slot bank cache), on both threads
function ChipAudio.invalidate()
  ChipAudio.stopMusic()
  ChipSynth.invalidateBanks()
  if workerReady and cmdCh then cmdCh:push({ cmd = "invalidate" }) end
end

-- End the worker thread.  LOVE waits for every live love.thread before the
-- process exits and the worker's command loop only returns on "quit", so
-- skipping this leaves the process running after the window is gone (#339).
function ChipAudio.shutdown()
  ChipAudio.stopMusic()
  if workerReady and cmdCh then cmdCh:push({ cmd = "quit" }) end
  if worker then pcall(function() worker:wait() end) end
  worker, cmdCh, outCh = nil, nil, nil
  workerReady = false
end

-- Runtime mix for one hardware channel (1..4).  Takes effect on the next
-- synthesized buffer (live music) and on any SFX/cry rendered after the call.
function ChipAudio.setChannelVolume(hw, scale)
  ChipSynth.setChannelVolume(hw, scale)
  pushChannelMix()
end

function ChipAudio.getChannelVolume(hw)
  return ChipSynth.getChannelVolume(hw)
end

function ChipAudio.setChannelVolumes(volumes)
  ChipSynth.setChannelVolumes(volumes)
  pushChannelMix()
end
function ChipAudio.setStereo(value)
  ChipSynth.setStereo(value)
  pushChannelMix()
end

function ChipAudio.getChannelVolumes()
  return ChipSynth.getChannelVolumes()
end

function ChipAudio.setChannelPitch(hw, scale)
  ChipSynth.setChannelPitch(hw, scale)
  pushChannelMix()
end

function ChipAudio.getChannelPitch(hw)
  return ChipSynth.getChannelPitch(hw)
end

function ChipAudio.setChannelPitches(pitches)
  ChipSynth.setChannelPitches(pitches)
  pushChannelMix()
end

function ChipAudio.getChannelPitches()
  return ChipSynth.getChannelPitches()
end

-- aliases for channel 4 (noise / drums)
function ChipAudio.setNoiseVolume(scale)
  ChipAudio.setChannelVolume(4, scale)
end

function ChipAudio.getNoiseVolume()
  return ChipAudio.getChannelVolume(4)
end

-- a stale song must not keep sounding past the flush that replaced its
-- program (20 §2 cache contract, chip music row)
Assets.register(ChipAudio.invalidate)

-- ---------------------------------------------------------------------------
-- one-shot effects (SFX, cries, low-health alarm): synchronous static Sources
-- ---------------------------------------------------------------------------

local function renderEffect(data, header, options)
  local sd = ChipSynth.renderEffectData(data, header, options)
  if not sd then return nil end
  return love.audio.newSource(sd, "static")
end

function ChipAudio.newSfx(data, name, pitch, tempo, header)
  header = header or data.audio.sfx[name]
  return renderEffect(data, header, {
    frequencyOffset = pitch or 0,
    frameTicks = 0x80 + (tempo or 0x80),
  })
end

-- `resolved` is a {header|chip, pitch, length} def the caller already worked
-- out -- a derived cry borrowing another species' header with its own
-- modifiers, which no registry lookup under `species` could find
-- A Gen 3 sound effect: the same sequencer as the music, run once to its end
-- and handed over as a static Source.
function ChipAudio.newM4AEffect(data, def)
  local songs = data.audio and data.audio.songs
  local song = songs and def and def.m4a ~= nil
                and songs[("SONG_%03X"):format(def.m4a)]
  if not song then return nil end
  local sd = synthFor("m4a").renderEffect(data, song)
  if not sd then return nil end
  return love.audio.newSource(sd, "static")
end

function ChipAudio.newCry(data, species, resolved)
  local cry = resolved or (data.audio.cries and data.audio.cries[species])
  if not cry then return nil end
  -- A GEN 3 CRY IS A RECORDING, not a chip program with a pitch shift: it
  -- names an index into the cartridge's cry table and is rendered by the
  -- sampler next door.  Same seam, same Source, different generation.
  if cry.m4a then
    local sd = synthFor("m4a").renderCry(data, cry.m4a)
    if not sd then return nil end
    return love.audio.newSource(sd, "static")
  end
  return renderEffect(data, cry.chip and cry or cry.header, {
    frequencyOffset = cry.pitch,
    cryLength = cry.length,
  })
end

-- Two channels for the same reason ChipSynth.renderEffectData renders stereo:
-- a mono Source is spatialized by OpenAL at the listener position and spreads
-- over every output an interface has (#626).  The siren itself is unchanged,
-- both channels carry the same sample.
function ChipAudio.newLowHealthAlarm()
  local samples = math.floor(SAMPLE_RATE * 62 / 60)
  local data = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 2)
  local phase = 0
  for index = 0, samples - 1 do
    local frame = math.floor(index * 60 / SAMPLE_RATE) % 31
    local register = frame < 11 and 0x750 or 0x6EE
    local frequency = 131072 / (2048 - register)
    phase = (phase + frequency / SAMPLE_RATE) % 1
    local value = (phase < 0.5 and 1 or -1) * 0.25
    data:setSample(index, 1, value)
    data:setSample(index, 2, value)
  end
  return love.audio.newSource(data, "static")
end

-- ---------------------------------------------------------------------------
-- test hooks (headless): synchronous synthesis straight through ChipSynth
-- ---------------------------------------------------------------------------

-- Force the "threaded, first buffer not yet queued" window so Music's
-- playOnce / pendingRestore race can be asserted without love.thread.
-- Returns a clear() that drops the override (call after the assertion).
function ChipAudio._simulateAwaitingFirstBufferForTest()
  local m = currentMusic
  if not m or not m.source then return nil end
  m.threaded = true
  m.started = false
  m.finished = false
  pcall(function() m.source.playing = false end)
  forceAwaitingFirstBuffer = true
  return function() forceAwaitingFirstBuffer = nil end
end

function ChipAudio._renderMusicForTest(data, header, seconds)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = true })
  return ChipSynth.soundData(engine, math.floor(seconds * SAMPLE_RATE), 2)
end

function ChipAudio._renderMusicChannelForTest(data, header, seconds, number)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = true })
  local samples = math.floor(seconds * SAMPLE_RATE)
  local result = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)
  for index = 0, samples - 1 do
    result:setSample(index, engine:sampleChannel(number))
  end
  return result
end

function ChipAudio._traceFirstMusicSampleForTest(data, header)
  local engine = ChipSynth.newEngine(data, header, { allowLoops = true })
  local result = {}
  for _, channel in ipairs(engine.channels) do
    local value = channel:sample()
    local event = channel.event or {}
    result[#result + 1] = {
      number = channel.number,
      value = value,
      register = event.register,
      duration = event.duration,
      volume = event.volume,
      duty = event.duty,
      wave = event.wave,
      waveInstrument = event.waveInstrument,
      drumSegments = event.drum and #event.drum or nil,
      noiseParameter = event.noiseParameter,
      sweep = event.sweep,
    }
  end
  return result
end

function ChipAudio._traceFirstSfxSampleForTest(data, header)
  local engine = ChipSynth.newEngine(data, header, {
    sfx = true,
    allowLoops = false,
  })
  local result = {}
  for _, channel in ipairs(engine.channels) do
    local value = channel:sample()
    local event = channel.event or {}
    result[#result + 1] = {
      number = channel.number,
      value = value,
      register = event.register,
      duration = event.duration,
      volume = event.volume,
      fade = event.fade,
      noiseParameter = event.noiseParameter,
      sweep = event.sweep,
    }
  end
  return result
end

function ChipAudio._renderSfxForTest(data, header, seconds)
  local engine = ChipSynth.newEngine(data, header, {
    sfx = true,
    allowLoops = false,
  })
  return ChipSynth.soundData(engine, math.floor(seconds * SAMPLE_RATE), 1)
end

return ChipAudio
