package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Sound, V = require("src.core.Sound"), require("src.core.GameVersion")
local cache = assert(arg[1], "pass existing cache root")
local oldAudio, sources = love.audio, {}
local Source = {}
Source.__index = Source
function Source:play()
  self.playing = true
end
function Source:stop()
  self.playing = false
end
function Source:isPlaying()
  return self.playing or false
end
function Source:setVolume(v)
  self.volume = v
end
function Source:setLooping() end
love.audio = {
  newSource = function(input)
    assert(type(input) == "table" and input.getSampleCount, "real M4A PCM must reach source construction")
    assert(
      input:getSampleCount() >= 64
        and input:getSampleRate() == 44100
        and (input:getChannelCount() == 1 or input:getChannelCount() == 2)
    )
    local s = setmetatable({ input = input }, Source)
    sources[#sources + 1] = s
    return s
  end,
}
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  V.set(version)
  Sound.invalidate()
  require("src.core.M4ASynth").invalidate()
  sources = {}
  local audio = assert(dofile(cache .. "/" .. version .. "/data/generated/audio.lua"))
  local path = cache .. "/" .. version .. "/" .. audio.gen3.file
  local f = assert(io.open(path, "rb"))
  local blob = f:read("*a")
  f:close()
  assert(#blob == audio.gen3.size)
  local mounted = "owned-real-audio-" .. version .. ".bin"
  love.filesystem.write(mounted, blob)
  audio.gen3.file, audio.programPrefix = mounted, nil
  local data = { audio = audio }
  local seen = {}
  local function active()
    local out = {}
    for _, s in ipairs(sources) do
      if s.playing then
        out[#out + 1] = assert(seen[s])
      end
    end
    table.sort(out)
    return out
  end
  local function play(id, pan, mono)
    local src = assert(Sound.playId(data, id, { pan = pan, mono = mono }), version .. " native source " .. id)
    seen[src] = id
    local song = assert(audio.songs[("SONG_%03X"):format(id)])
    rows[#rows + 1] = {
      version = version,
      id = id,
      player = song.player,
      active = active(),
      samples = src.input:getSampleCount(),
      channels = src.input:getChannelCount(),
    }
    return src
  end
  local first = play(141, -64, false)
  local replacement = play(164, 63, false)
  assert(not first:isPlaying() and replacement:isPlaying(), "actual same-player source must be replaced")
  local ui = play(5, 0, false)
  assert(replacement:isPlaying() and ui:isPlaying(), "actual UI player stays independent")
  local changed = play(141, 63, true)
  assert(
    not replacement:isPlaying() and ui:isPlaying() and changed:isPlaying(),
    "actual pan/mono variant retains other player"
  )
  local specialId = version == "firered" and 74 or 81
  local special = play(specialId, 0, false)
  assert(
    ui:isPlaying() and changed:isPlaying() and special:isPlaying(),
    "actual special player remains independent"
  )
  Sound.stopSe(data, 5)
  assert(
    not ui:isPlaying() and changed:isPlaying() and special:isPlaying(),
    "actual stop-by-ID keeps other players"
  )
  Sound.stopSe(data)
  assert(#active() == 0 and not Sound.isSePlaying(data), "actual native stop-all releases every source")
  Sound.invalidate()
  require("src.core.M4ASynth").invalidate()
  love.filesystem.remove(mounted)
end
love.audio = oldAudio
print("IMPORTED_NATIVE_SOUND_SMOKE " .. require("src.link.Json").encode(rows))
