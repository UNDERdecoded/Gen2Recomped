-- Owned waveform hardware and native M4A carrier. This does not replace
-- either engine's sound functions or assert equality of their synthesizers.
local M = {}
function M.install(root, native, f)
  local previousAudio, currentTick = love.audio, 0
  local trace, carrier = {}, nil
  local Audio = native and require("src.core.game3.audio")
  local Source = {}
  Source.__index = Source
  function Source:stop()
    self.playing = false
  end
  function Source:isPlaying()
    return self.playing
  end
  function Source:setVolume() end
  function Source:setLooping() end
  function Source:clone()
    return setmetatable({ input = self.input }, Source)
  end
  function Source:play()
    self.playing = true
    local id, pan, mono
    if native then
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
          else
            assert(l == r / 64, "opponent sound must retain its native stereo gain")
            pan = 63
          end
        end
      end
      assert(pan ~= nil, "effect sound must be audible")
    end
    trace[#trace + 1] = { tick = currentTick, id = id, pan = pan, mono = mono }
  end
  love.audio = {
    newSource = function(input)
      return setmetatable({ input = input }, Source)
    end,
  }
  local off, saved
  if native then
    saved = { ready = Audio._ready, pack = Audio._pack, mono = Audio._mono }
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
      local id = tonumber(event.name:match("^OWNED_NATIVE_(%d+)$"))
      if id then
        assert(trace[#trace]).id = id
      end
    end)
  end
  return {
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
    close = function()
      if off then
        off()
      end
      if native then
        Audio._ready, Audio._pack, Audio._mono = saved.ready, saved.pack, saved.mono
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
