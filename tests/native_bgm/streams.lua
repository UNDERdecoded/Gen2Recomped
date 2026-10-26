-- Real native/host sequencers with owned tracks and queueable audio hardware.
local M = {}
function M.install(root, backend, version, f, options)
  options = options or {}
  local native = backend == "gen1"
  local h = dofile(root .. "/tests/native_bgm/fixture.lua").install(root, backend, version, f)
  local Music = require("src.core.Music")
  Music.stop()
  local soundData = dofile(root .. "/tests/native_bgm/sounddata.lua").install()
  local oldThread, oldQueue = love.thread, love.audio.newQueueableSource
  local voices, tick = {}, 0
  local queueMode = options.queueFailure
  love.thread = nil
  local Queue = {}
  Queue.__index = Queue
  function Queue:stop()
    self.playing = false
    self.queued = {}
  end
  function Queue:pause()
    self.playing = false
  end
  function Queue:isPlaying()
    return self.playing or false
  end
  function Queue:setVolume(value)
    self.volume = value
  end
  function Queue:setLooping() end
  function Queue:setFilter() end
  function Queue:play()
    self.playing = true
    self.plays[#self.plays + 1] = { tick = tick, volume = self.volume }
  end
  function Queue:getFreeBufferCount()
    return self.capacity - #self.queued
  end
  function Queue:queue(sd)
    self.queued[#self.queued + 1] = sd
    local samples = {}
    for i = 0, sd:getSampleCount() - 1 do
      samples[#samples + 1] = { sd:getSample(i, 1), sd:getSample(i, 2) }
    end
    self.buffers[#self.buffers + 1] = { tick = tick, rate = sd:getSampleRate(), samples = samples }
  end
  local function queueBuilder(rate, bits, channels, capacity)
    if queueMode == "error" then
      error("owned queue device unavailable")
    end
    if queueMode == "nil" then
      return nil
    end
    local voice = setmetatable({
      rate = rate,
      bits = bits,
      channels = channels,
      capacity = capacity,
      queued = {},
      buffers = {},
      plays = {},
    }, Queue)
    voices[#voices + 1] = voice
    return voice
  end
  if queueMode == "missing" then
    love.audio.newQueueableSource = nil
  else
    love.audio.newQueueableSource = queueBuilder
  end
  local programs = {}
  for i = 1, 3 do
    programs[i] = string.char(0xBD, 0, 0xBE, 127, 0xBF, 64, 0xCF, 57 + i * 3, 127)
      .. string.rep(string.char(0xB0), options.finite and 0 or 100)
      .. string.char(0xB1)
  end
  local audio = native and require("src.core.game3.audio")
  if native then
    require("src.core.game3.mod_audio").reset()
    audio._worker, audio._cmdCh, audio._outCh, audio._bgmSource = nil, nil, nil, nil
    audio._currentSong, audio._bgmLocal = nil, nil
    audio._pack = {
      root = "owned-native-bgm",
      samplesBin = "",
      samples = {},
      index = { songs = {} },
      voicegroups = {
        [1] = {
          [0] = {
            type = 1,
            key = 60,
            attack = 15,
            decay = 0,
            sustain = 15,
            release = 1,
            wavParam = 2,
          },
        },
      },
      songCache = {},
    }
    for i, id in ipairs(h.ids) do
      audio._pack.index.songs[id] = { voicegroupId = 1, loop = not options.finite }
      audio._pack.songCache[id] = {
        tracks = 1,
        blocks = 0,
        priority = 0,
        reverb = 0,
        voicegroup = 0,
        trackData = { programs[i] },
        trackEntries = { 0 },
      }
    end
    if options.initialShared then
      require("src.core.game3.mod_audio").install({
        audio = { songs = { MUS_TITLE = { file = "owned-bgm-title.ogg" } } },
      })
    end
    assert(audio.playSong(h.ids[1]))
    if not options.initialShared then
      assert(audio._bgmLocal and audio._bgmLocal.seq, "actual native sequencer starts")
    end
  else
    local bytes = {}
    for i = 1, 32 do
      bytes[i] = 0
    end
    bytes[1], bytes[2], bytes[5], bytes[9], bytes[11], bytes[12] = 1, 60, 2, 15, 15, 1
    local chars = {}
    for i, value in ipairs(bytes) do
      chars[i] = string.char(value)
    end
    love.filesystem.write("owned-native-bgm-image.bin", table.concat(chars) .. table.concat(programs))
    f.data.audio = { gen3 = { base = 0, file = "owned-native-bgm-image.bin" }, songs = {}, mapSongs = {} }
    local offset = 32
    for i, id in ipairs(h.ids) do
      local label = ("SONG_%03X"):format(id)
      f.data.audio.songs[label] = { index = id, tracks = { offset }, voicegroup = 0 }
      if i == 1 then
        f.data.audio.mapSongs.OWNED_NATIVE_BGM_MAP = label
      end
      offset = offset + #programs[i]
    end
    if options.initialShared then
      f.data.audio.songs.MUS_TITLE = { file = "owned-bgm-title.ogg" }
      f.data.audio.mapSongs.OWNED_NATIVE_BGM_MAP = "MUS_TITLE"
    end
    require("src.core.M4ASynth").invalidate()
    Music.playMap(f.data, "OWNED_NATIVE_BGM_MAP", false, false)
  end
  local function inventory()
    local rows = {}
    for _, voice in ipairs(voices) do
      rows[#rows + 1] = {
        playing = voice:isPlaying(),
        volume = voice.volume,
        queued = #voice.queued,
        produced = #voice.buffers,
        plays = #voice.plays,
      }
    end
    return rows
  end
  return {
    ids = h.ids,
    soundData = soundData,
    invalidateQueues = function()
      local restore = {}
      for _, voice in ipairs(voices) do
        local methods = {}
        for _, key in ipairs({
          "getFreeBufferCount",
          "queue",
          "isPlaying",
          "setVolume",
          "play",
          "stop",
          "pause",
        }) do
          methods[key] = voice[key]
          voice[key] = function()
            error("owned invalidated audio source: " .. key)
          end
        end
        voice.playing = false
        restore[#restore + 1] = function()
          for key, value in pairs(methods) do
            voice[key] = value
          end
        end
      end
      return function()
        for _, fn in ipairs(restore) do
          fn()
        end
      end
    end,
    endFiles = h.hardware.endSources,
    queueDevice = function(mode)
      queueMode = mode
      if mode == "missing" then
        love.audio.newQueueableSource = nil
      else
        love.audio.newQueueableSource = queueBuilder
      end
    end,
    fanfares = function()
      f.data.constants = f.data.constants or {}
      local resolve = native and audio.resolveSong or require("src.core.Gen3SongIds").resolve
      local ids = { resolve("MUS_LEVEL_UP"), resolve("MUS_OBTAIN_ITEM") }
      local rows = {
        LEVEL_UP = { index = ids[1], frames = 4 },
        ITEM = { index = ids[2], frames = 6 },
      }
      f.data.constants.gen3Fanfares = { fanfares = rows }
      local image = not native and assert(love.filesystem.read("owned-native-bgm-image.bin")) or nil
      if native then
        audio._fanfareActive, audio._fanfareFrames, audio._fanfareRestore, audio._bgmPaused =
          false, 0, nil, false
        audio._fanfareSource, audio._fanfareSrc, audio._fanfareSd, audio._waitFanfareCb = nil, {}, {}, nil
        audio._pack.index.fanfares = {}
      end
      for i, id in ipairs(ids) do
        local program = string.char(0xBD, 0, 0xBE, 127, 0xBF, 64, 0xFF, 69 + i * 3, 127, 0xB0, 0xB1)
        if native then
          audio._pack.index.fanfares[id] = rows[i == 1 and "LEVEL_UP" or "ITEM"]
          audio._pack.index.songs[id] = { kind = "fanfare", voicegroupId = 1, player = i + 1 }
          audio._pack.songCache[id] = {
            tracks = 1,
            blocks = 0,
            priority = 0,
            reverb = 0,
            voicegroup = 0,
            trackData = { program },
            trackEntries = { 0 },
          }
        else
          f.data.audio.songs[("SONG_%03X"):format(id)] = {
            kind = "fanfare",
            index = id,
            tracks = { #image },
            voicegroup = 0,
            player = i + 1,
          }
          image = image .. program
        end
      end
      if not native then
        love.filesystem.write("owned-native-bgm-image.bin", image)
        require("src.core.M4ASynth").invalidate()
      end
      return ids
    end,
    fanfareState = function(ids)
      local Sound = not native and require("src.core.Sound")
      local state = native
          and {
            active = audio._fanfareActive,
            frames = audio._fanfareFrames,
            restore = audio._fanfareRestore,
            paused = audio._bgmPaused,
          }
        or Music.nativeFanfareSnapshot()
      if native then
        state.finished = audio.isFanfareFinished()
      else
        state.finished = Music.nativeFanfareFinished()
      end
      local query = function(id)
        if native then
          return audio.isSePlaying(id)
        end
        return Sound.isSePlaying(f.data, id)
      end
      state.se = { any = query(), first = query(ids[1]), second = query(ids[2]) }
      return state
    end,
    value = function(runner)
      if native then
        return require("src.core.game3.scripting.flags").getVar(runner.store, runner.ctx, 0x4001)
      end
      return require("src.script.Gen3Commands").getVar(f.game.save, 0x4001)
    end,
    clear = function()
      if not native then
        require("src.script.Gen3Commands").setVar(f.game.save, 0x4001, 0)
      end
    end,
    start = h.start,
    options = h.options,
    override = function(kind)
      local def = { file = "owned-bgm-stream-override.ogg" }
      if kind == "chip" then
        def = require("src.audio.ChipAsm").song({
          channels = {
            {
              hw = 1,
              program = {
                { notetype = { speed = 12, volume = 12, fade = 0 } },
                { octave = 4 },
                { note = "C", len = 8 },
                { loop = { count = 0, to = 1 } },
              },
            },
          },
        })
      end
      if native then
        require("src.core.game3.mod_audio").install({ audio = { songs = { MUS_CYCLING = def } } })
        audio.applyEngineOptions({ musicVol = 7, sfxVol = 7 })
      else
        f.data.audio.songs.MUS_CYCLING = def
      end
    end,
    tick = function(value)
      tick = value
      h.tick(value)
    end,
    state = function()
      return { native = h.state(), queues = inventory() }
    end,
    update = h.update,
    drain = function()
      for _, voice in ipairs(voices) do
        if #voice.queued > 0 then
          table.remove(voice.queued, 1)
        end
        if #voice.queued == 0 then
          voice.playing = false
        end
      end
    end,
    trace = function()
      local rows = {}
      for _, voice in ipairs(voices) do
        rows[#rows + 1] = {
          rate = voice.rate,
          bits = voice.bits,
          channels = voice.channels,
          capacity = voice.capacity,
          buffers = voice.buffers,
          plays = voice.plays,
        }
      end
      return { queues = rows, files = h.trace() }
    end,
    close = function()
      love.thread, love.audio.newQueueableSource = oldThread, oldQueue
      soundData.close()
      h.close()
      if not native then
        require("src.core.M4ASynth").invalidate()
        love.filesystem.remove("owned-native-bgm-image.bin")
      end
    end,
  }
end
return M
