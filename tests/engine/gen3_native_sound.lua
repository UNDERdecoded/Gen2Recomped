package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V, Sound = require("src.core.GameVersion"), require("src.core.Sound")
local previousAudio, sources = love.audio, {}
local Source = {}
Source.__index = Source
function Source:play()
  self.plays = self.plays + 1
end
function Source:stop() end
function Source:setVolume(value)
  self.volume = value
end
function Source:setLooping() end
love.audio = {
  newSource = function(input)
    local source = setmetatable({ input = input, plays = 0 }, Source)
    sources[#sources + 1] = source
    return source
  end,
}
V.set("firered")
-- An owned native M4A square-wave instrument and one finite note. Exercise
-- the real sequencer, sound construction, native-ID dispatch and pan cache.
local bytes = {}
for i = 1, 64 do
  bytes[i] = 0
end
bytes[1], bytes[2], bytes[11], bytes[12] = 1, 60, 15, 1
local program = { 0xBD, 0, 0xBE, 127, 0xBF, 64, 0xD0, 60, 127, 0x81, 0xB1 }
for i, byte in ipairs(program) do
  bytes[32 + i] = byte
end
local chars = {}
for i, byte in ipairs(bytes) do
  chars[i] = string.char(byte)
end
love.filesystem.write("owned-native-effect.bin", table.concat(chars))
local data = {
  audio = {
    sfx = {},
    songs = {
      SONG_08D = { index = 141, tracks = { 32 }, voicegroup = 0, sfxName = "OWNED_NATIVE_EFFECT" },
    },
    gen3 = { base = 0, file = "owned-native-effect.bin" },
  },
}
Sound.invalidate()
local plain = assert(Sound.playId(data, 141), "native effect without a role must play")
T.eq(plain.input:getChannelCount(), 2, "actual M4A carrier is stereo")
T.check(plain.input:getSampleCount() >= 64, "actual native effect is synthesized")
local audible = false
for i = 0, plain.input:getSampleCount() - 1 do
  if math.abs(plain.input:getSample(i, 1)) > 0.01 then
    audible = true
    break
  end
end
T.check(audible, "the carrier contains a real synthesized note")
for _, mono in ipairs({ false, true }) do
  for _, pan in ipairs({ -64, -32, 0, 32, 63 }) do
    local played = assert(Sound.playId(data, 141, { pan = pan, mono = mono }))
    T.eq(
      played,
      Sound.playId(data, 141, { pan = pan, mono = mono }),
      "identical controls reuse only their own source"
    )
    T.neq(played, plain, "panning leaves the unmodified carrier source independent")
    local pcm = played.input
    T.eq(pcm:getSampleCount(), plain.input:getSampleCount(), "pan preserves the actual effect length")
    T.eq(pcm:getSampleRate(), plain.input:getSampleRate(), "pan preserves the native carrier rate")
    T.eq(pcm:getChannelCount(), mono and 1 or 2, "mono folds after native panorama gains")
    for i = 0, pcm:getSampleCount() - 1 do
      local l = plain.input:getSample(i, 1) * (1 - math.max(0, pan / 64))
      local r = plain.input:getSample(i, 2) * (1 - math.max(0, -pan / 64))
      T.eq(pcm:getSample(i, 1), mono and (l + r) / 2 or l, "actual source retains native left/mono sample")
      if not mono then
        T.eq(pcm:getSample(i, 2), r, "actual source retains native right sample")
      end
    end
  end
end
T.eq(Sound.playId(data, 141), plain, "subsequent default playback retains its original cache")
for _, id in ipairs({ -1, 0.5, 65536, math.huge }) do
  T.eq(Sound.playId(data, id), nil, "invalid native sound numbers are refused")
end
local Pan = require("src.core.NativeSoundPan")
T.eq(Pan.value(0 / 0), 0, "invalid panorama cannot enter PCM output")
T.eq(Pan.value("63"), 63, "numeric control strings resolve consistently")
data.audio.sfx.ROLE = { m4a = 141 }
Sound.invalidate()
T.eq(Sound.playId(data, 141), Sound.play(data, "ROLE"), "existing named-role playback retains its path")
data.audio.sfx = { OWNED_NATIVE_EFFECT = { file = "owned-override.wav" } }
Sound.invalidate()
T.eq(
  Sound.playId(data, 141, { pan = 63 }).input,
  "owned-override.wav",
  "native-name file override retains priority"
)
data.audio.sfx.OWNED_NATIVE_EFFECT = "owned-string.wav"
Sound.invalidate()
T.eq(
  Sound.playId(data, 141, { pan = -64 }).input,
  "owned-string.wav",
  "native-name string file retains priority"
)
data.audio.sfx.OWNED_NATIVE_EFFECT = false
Sound.invalidate()
T.eq(Sound.playId(data, 141, { pan = -64 }), nil, "disabled native-name sound remains silent")
V.set("red")
data.audio.sfx = {}
T.eq(Sound.playId(data, 141), nil, "native song fallback does not alter legacy sound dispatch")
Sound.invalidate()
love.audio = previousAudio
T.finish("native GBA sound number dispatch and stereo control")
