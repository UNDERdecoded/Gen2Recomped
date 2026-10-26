-- Owned waveform hardware and native M4A carrier. This does not replace
-- either engine's sound functions or assert equality of their synthesizers.
local M = {}
function M.install(root, native, f)
  local previousAudio, currentTick = love.audio, 0
  local trace, carrier = {}, nil
  local allSources, lastSource = {}, nil
  local roleIds = {}
  local Audio = native and require("src.core.game3.audio")
  local Source = {}
  Source.__index = Source
  function Source:stop()
    self.playing = false
  end
  function Source:isPlaying()
    return self.playing
  end
  function Source:setVolume(value)
    self.volume = value
  end
  function Source:setLooping() end
  function Source:clone()
    local copy = setmetatable({ input = self.input }, Source)
    allSources[#allSources + 1] = copy
    return copy
  end
  function Source:play()
    self.playing = true
    local id, pan, mono
    if type(self.input) == "string" then
      id = assert(tonumber(self.input:match("owned%-effect%-(%d+)%.wav")), "owned file identity")
      pan, mono = 0, false
    elseif native then
      local meta = assert(Audio._seMeta[self], "native source retains its actual sound metadata")
      id, pan, mono = meta.id, meta.pan, meta.mono and true or false
    else
      -- Measure the panorama at the actual output source. The owned M4A
      -- carrier has equal channels; every emitted sample must obey the gain.
      mono = self.input:getChannelCount() == 1
      for i = 0, self.input:getSampleCount() - 1 do
        local l, r = self.input:getSample(i, 1), self.input:getSample(i, 2)
        if mono then
          local original = carrier:getSample(i, 1)
          if math.abs(original) > 0.0001 then
            if l == original / 2 then
              pan = -64
            else
              assert(l == (original / 64 + original) / 2, "native panorama folds before mono output")
              pan = 63
            end
          end
        elseif math.abs(l) + math.abs(r) > 0.0001 then
          if r == 0 then
            assert(l ~= 0)
            pan = -64
          elseif l == r then
            pan = 0
          else
            assert(l == r / 64, "opponent sound must retain its native stereo gain")
            pan = 63
          end
        end
      end
      assert(pan ~= nil, "effect sound must be audible")
    end
    self.observed = { tick = currentTick, id = id, pan = pan, mono = mono }
    trace[#trace + 1] = self.observed
    lastSource = self
  end
  love.audio = {
    newSource = function(input)
      local source = setmetatable({ input = input }, Source)
      allSources[#allSources + 1] = source
      return source
    end,
  }
  local off, saved
  if native then
    saved = {
      ready = Audio._ready,
      pack = Audio._pack,
      mono = Audio._mono,
      modData = require("src.core.game3.mod_audio").data,
    }
    Audio._ready, Audio._pack = true, { index = { songs = {} } }
    for _, id in ipairs({ 141, 148, 164, 171 }) do
      Audio._pack.index.songs[id] = { kind = "sfx", player = 1 }
      Audio._seRawPut(id, false, { 0.25 }, { 0.25 })
    end
  else
    local bytes = {}
    for i = 1, 64 do
      bytes[i] = 0
    end
    bytes[1], bytes[2], bytes[11], bytes[12] = 1, 60, 15, 1
    for i, byte in ipairs({ 0xBD, 0, 0xBE, 127, 0xBF, 64, 0xD0, 60, 127, 0x81, 0xB1 }) do
      bytes[32 + i] = byte
    end
    local chars = {}
    for i, byte in ipairs(bytes) do
      chars[i] = string.char(byte)
    end
    love.filesystem.write("owned-effect-carrier.bin", table.concat(chars))
    f.data.audio = { sfx = {}, songs = {}, gen3 = { base = 0, file = "owned-effect-carrier.bin" } }
    for _, id in ipairs({ 141, 148, 164, 171 }) do
      f.data.audio.songs[("SONG_%03X"):format(id)] = {
        index = id,
        tracks = { 32 },
        voicegroup = 0,
        sfxName = "OWNED_NATIVE_" .. id,
      }
    end
    require("src.core.Sound").invalidate()
    carrier = assert(require("src.core.M4ASynth").renderEffect(f.data, f.data.audio.songs.SONG_08D))
    off = f.e.api.events:on("sound.played", function(event)
      local id = tonumber(event.name:match("^OWNED_NATIVE_(%d+)$")) or roleIds[event.name]
      if id then
        assert(trace[#trace]).id = id
        assert(lastSource).observed.id = id
      end
    end)
  end
  return {
    override = function(id, kind)
      local file = "owned-effect-" .. id .. ".wav"
      local def = kind == "file" and { file = file } or kind == "string" and file or false
      if native then
        local effects = {}
        for key, value in pairs(require("src.core.game3.se_ids")) do
          if value == id and key:match("^SE_") then
            effects[key] = def
          end
        end
        require("src.core.game3.mod_audio").install({ audio = { sfx = effects } })
      else
        local name = "OWNED_NATIVE_" .. id
        f.data.audio.sfx[name] = def
        require("src.core.Sound").invalidate(name)
      end
    end,
    role = function(id, name)
      if not native then
        roleIds[name] = id
        f.data.audio.sfx[name] = { m4a = id }
      end
    end,
    player = function(id, player)
      if native then
        Audio._pack.index.songs[id].player = player
      else
        f.data.audio.songs[("SONG_%03X"):format(id)].player = player
      end
    end,
    clear = function()
      if native then
        Audio.stopSe()
        require("src.core.Sound").invalidate()
        require("src.core.game3.mod_audio").reset()
      else
        require("src.core.Sound").invalidate()
        for key in pairs(f.data.audio.sfx) do
          f.data.audio.sfx[key] = nil
        end
      end
      -- The native PCM source cache survives stopSe. Keep stopped hardware
      -- objects in the inventory so reuse is observed on later commands.
      trace, lastSource = {}, nil
    end,
    active = function()
      local active = {}
      for _, source in ipairs(allSources) do
        if source.playing then
          local state = assert(source.observed)
          active[#active + 1] = { id = assert(state.id), pan = state.pan, mono = state.mono }
        end
      end
      table.sort(active, function(a, b)
        if a.id ~= b.id then
          return a.id < b.id
        end
        if a.pan ~= b.pan then
          return a.pan < b.pan
        end
        return tostring(a.mono) < tostring(b.mono)
      end)
      return active
    end,
    volumes = function()
      local out = {}
      for _, source in ipairs(allSources) do
        if source.playing then
          out[#out + 1] = source.volume
        end
      end
      return out
    end,
    stereo = function(value)
      if native then
        Audio._mono = not value
      else
        f.game.save.options.stereo = value
      end
    end,
    tick = function(value)
      currentTick = value
    end,
    reset = function()
      trace = {}
      currentTick = 0
    end,
    trace = function()
      return trace
    end,
    queries = function()
      local out = {}
      for _, id in ipairs({ 141, 148, 164, 171 }) do
        out[tostring(id)] = native and Audio.isSePlaying(id)
          or not native and require("src.core.Sound").isSePlaying(f.data, id)
          or false
      end
      out.any = native and Audio.isSePlaying()
        or not native and require("src.core.Sound").isSePlaying(f.data)
        or false
      return out
    end,
    close = function()
      if off then
        off()
      end
      if native then
        Audio._ready, Audio._pack, Audio._mono = saved.ready, saved.pack, saved.mono
        require("src.core.game3.mod_audio").data = saved.modData
        Audio._seRawClear()
      else
        require("src.core.Sound").invalidate()
        require("src.core.M4ASynth").invalidate()
      end
      love.audio = previousAudio
    end,
  }
end
return M
