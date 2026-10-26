local M = {}
function M.install(native, f, options)
  options = options or {}
  local oldAudio, tick, trace, sources = love.audio, 0, {}, {}
  local Source = {}
  Source.__index = Source
  function Source:stop()
    self.playing = false
  end
  function Source:isPlaying()
    return self.playing or false
  end
  function Source:setVolume(value)
    self.volume = value
  end
  function Source:setLooping() end
  function Source:play()
    self.playing = true
    local samples, channels, rate
    if type(self.input) == "table" then
      channels, rate = self.input:getChannelCount(), self.input:getSampleRate()
      samples = {}
      for i = 0, self.input:getSampleCount() - 1 do
        local frame = {}
        for c = 1, channels do
          frame[c] = self.input:getSample(i, c)
        end
        samples[#samples + 1] = frame
      end
    end
    trace[#trace + 1] = {
      tick = tick,
      file = type(self.input) == "string" and self.input or nil,
      channels = channels,
      rate = rate,
      samples = samples,
      volume = self.volume,
    }
  end
  love.audio = {
    newSource = function(input)
      local source = setmetatable({ input = input }, Source)
      sources[#sources + 1] = source
      return source
    end,
  }
  local pcm = {}
  for i = 0, 1023 do
    pcm[#pcm + 1] = string.char((i * 37 + i * i * 13) % 256)
  end
  pcm = table.concat(pcm)
  local audio = native and require("src.core.game3.audio") or nil
  local saved, savedPlayer
  if native then
    saved = {
      ready = audio._ready,
      pack = audio._pack,
      clock = audio._cryClock,
      cache = audio._cryCache,
      cacheCount = audio._cryCacheN,
      slot = audio._crySlot,
      params = audio._cryParams,
      source = audio._crySource,
      untilFrame = audio._cryUntil,
      mono = audio._mono,
      volume = audio._sfxVolume,
      modData = require("src.core.game3.mod_audio").data,
      modPokemon = require("src.core.game3.mod_audio").pokemon,
      duck = audio._duck,
      hold = audio._duckHold,
      restore = audio._duckRestore,
    }
    require("src.core.Sound").invalidate()
    audio.stopCry()
    audio._cryClock, audio._cryCache, audio._cryCacheN = 0, {}, 0
    audio._cryParams, audio._crySource, audio._cryUntil = nil, nil, nil
    audio._ready, audio._mono, audio._sfxVolume = not options.noPack, options.mono or false, 1
    audio._pack = {
      index = {
        cries = { [3] = { sampleId = 1 }, [273] = { sampleId = 2 } },
        cryIds = { [4] = 3, [277] = 273 },
      },
      samplesBin = pcm .. pcm:reverse(),
      samples = {
        { offset = 0, size = #pcm, freq = 8000 * 1024 },
        { offset = #pcm, size = #pcm, freq = 8000 * 1024 },
      },
    }
    require("src.core.game3.mod_audio").reset()
  else
    local Sound = require("src.core.Sound")
    Sound.invalidate()
    Sound.stopCry()
    savedPlayer = package.loaded["src.core.NativeCryPlayer"]
    package.loaded["src.core.NativeCryPlayer"] = nil
    Sound.applyOptions({ sfxVol = 7, stereo = not options.mono })
    local bytes = {}
    for i = 1, 388 * 12 + 2 * (16 + #pcm) do
      bytes[i] = 0
    end
    local function put(offset, value, count)
      for i = 0, count - 1 do
        bytes[offset + i + 1] = math.floor(value / 256 ^ i) % 256
      end
    end
    for n, index in ipairs({ 3, 273 }) do
      local wave = 388 * 12 + (n - 1) * (16 + #pcm)
      put(index * 12 + 1, 60, 1)
      put(index * 12 + 4, 0x08000000 + wave, 4)
      put(index * 12 + 8, 255, 1)
      put(index * 12 + 9, 255, 1)
      put(index * 12 + 10, 255, 1)
      put(wave + 4, 8000 * 1024, 4)
      put(wave + 12, #pcm, 4)
      local input = n == 1 and pcm or pcm:reverse()
      for i = 1, #input do
        bytes[wave + 16 + i] = input:byte(i)
      end
    end
    local chars = {}
    for i, value in ipairs(bytes) do
      chars[i] = string.char(value)
    end
    love.filesystem.write("owned-native-cries.bin", table.concat(chars))
    f.data.audio = {
      gen3 = options.noPack and nil or { base = 0, file = "owned-native-cries.bin" },
      gen3Cries = { table = 0, count = 388, mapping = "native-species-v1" },
      cries = { CHARMANDER = { m4a = 3 }, TREECKO = { m4a = options.legacyMapping and 251 or 273 } },
    }
    if options.noPack then
      f.data.audio.gen3 = nil
    end
    f.data.constants.speciesOrder = { [4] = "CHARMANDER", [277] = "TREECKO" }
    require("src.core.M4ASynth").invalidate()
  end
  return {
    override = function(species, kind)
      local name = species == 277 and "TREECKO" or "CHARMANDER"
      local file = "owned-cry-override.wav"
      local def = kind == "file" and { file = file } or kind == "string" and file or false
      if native then
        require("src.core.Sound").invalidate()
        require("src.core.game3.mod_audio").install({
          audio = { cries = { [name] = def } },
          gen3Pokemon = { _names = { [4] = "CHARMANDER", [277] = "TREECKO" } },
        })
      else
        f.data.audio.cries[name] = def
        f.data.audio._owners = { cries = { [name] = "owned_cry_override" } }
      end
    end,
    play = function(species, options)
      if native then
        return audio.playCry(species, options)
      end
      return require("src.core.Sound").playCry(f.data, species, options)
    end,
    update = function()
      if native then
        audio.update(1 / 60)
      else
        require("src.core.Sound").updateCry()
        require("src.core.Music").update(f.data)
        require("src.core.Sound").update()
      end
    end,
    stop = function()
      if native then
        audio.stopCry()
      else
        require("src.core.Sound").stopCry()
      end
    end,
    snapshot = function()
      if native then
        return {
          finished = audio.isCryFinished(),
          clock = audio._cryClock,
          untilFrame = audio._cryUntil,
          mode = audio._cryParams and audio._cryParams.mode,
          mix = { level = audio._duck, hold = audio._duckHold or 0, restore = audio._duckRestore or false },
        }
      end
      return {
        finished = require("src.core.Sound").isCryFinished(),
        clock = require("src.core.NativeCryPlayer").snapshot().clock,
        untilFrame = require("src.core.NativeCryPlayer").snapshot().untilFrame,
        mode = require("src.core.NativeCryPlayer").snapshot().controls.mode,
        mix = require("src.core.Music").nativeCryMixSnapshot(),
      }
    end,
    tick = function(value)
      tick = value
    end,
    trace = function()
      return trace
    end,
    endSources = function()
      for _, source in ipairs(sources) do
        source:stop()
      end
    end,
    active = function()
      local values = {}
      for _, source in ipairs(sources) do
        values[#values + 1] = source:isPlaying()
      end
      return values
    end,
    close = function()
      if native then
        audio.stopCry()
        audio._ready, audio._pack, audio._cryClock = saved.ready, saved.pack, saved.clock
        audio._cryCache, audio._cryParams, audio._crySource = saved.cache, saved.params, saved.source
        audio._cryCacheN, audio._crySlot = saved.cacheCount, saved.slot
        audio._cryUntil, audio._mono, audio._sfxVolume = saved.untilFrame, saved.mono, saved.volume
        audio._duck, audio._duckHold, audio._duckRestore = saved.duck, saved.hold, saved.restore
        require("src.core.game3.mod_audio").data = saved.modData
        require("src.core.game3.mod_audio").pokemon = saved.modPokemon
      else
        require("src.core.Sound").invalidate()
        require("src.core.Sound").stopCry()
        package.loaded["src.core.NativeCryPlayer"] = savedPlayer
        love.filesystem.remove("owned-native-cries.bin")
      end
      love.audio = oldAudio
    end,
  }
end
return M
