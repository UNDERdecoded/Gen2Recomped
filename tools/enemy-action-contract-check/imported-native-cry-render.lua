package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local backend, version, cache, romPath = assert(arg[1]), assert(arg[2]), assert(arg[3]), assert(arg[4])
local native = backend == "gen1"
local audio = assert(dofile(cache .. "/" .. version .. "/data/generated/audio.lua"))
local file = assert(io.open(cache .. "/" .. version .. "/" .. audio.gen3.file, "rb"))
local image = file:read("*a")
file:close()
local romFile = assert(io.open(romPath, "rb"))
local rom = romFile:read("*a")
romFile:close()
assert(
  image == rom:sub(audio.gen3.base + 1, audio.gen3.base + #image),
  "actual imported M4A bytes match source ROM"
)
local function uint(offset, bytes)
  local value = 0
  for i = 0, bytes - 1 do
    value = value + assert(rom:byte(offset + i + 1)) * 256 ^ i
  end
  return value
end
local mounted = "owned-real-cry-" .. version .. ".bin"
love.filesystem.write(mounted, image)
audio.gen3.file, audio.programPrefix = mounted, nil
local rows = {}
for _, index in ipairs({ 0, 3, 273, 387 }) do
  local wave = uint(audio.gen3Cries.table + index * 12 + 4, 4) - 0x08000000
  local kind, count, frequency = uint(wave, 2), uint(wave + 12, 4), uint(wave + 4, 4)
  assert(kind == 0 or kind == 1)
  local bytes = kind == 1 and math.ceil(count / 64) * 33 or count
  local encoded = rom:sub(wave + 17, wave + 16 + bytes)
  for _, mode in ipairs({ 0, 1, 4, 6, 9, 12 }) do
    local sound, info, controls
    if native then
      local sample = require("src.core.game3.m4a_sample")
      local pcm = kind == 1 and sample.decodeGfdpcm(encoded, count) or encoded
      controls = sample.cryParams(mode, nil, version == "emerald" and { [6] = { volume = 70 } } or nil)
      sound, info = sample.renderCry(pcm, sample.waveRate(frequency), controls, { outRate = 44100 })
    else
      sound, info, controls = require("src.core.M4ASynth").renderNativeCry(
        { audio = audio },
        index,
        { version = version, mode = mode }
      )
    end
    assert(sound and info and controls)
    local samples = {}
    for i = 0, sound:getSampleCount() - 1 do
      local values = {}
      for c = 1, sound:getChannelCount() do
        values[c] = sound:getSample(i, c)
      end
      samples[#samples + 1] = values
    end
    rows[#rows + 1] = {
      version = version,
      index = index,
      mode = mode,
      wave = wave,
      inputType = kind,
      inputSamples = count,
      frequency = frequency,
      controls = controls,
      info = info,
      rate = sound:getSampleRate(),
      channels = sound:getChannelCount(),
      depth = sound:getBitDepth(),
      samples = samples,
    }
  end
end
love.filesystem.remove(mounted)
print("REAL_NATIVE_CRY_PCM " .. require("src.link.Json").encode(rows))
