-- Native GBA cry controls, independent of the music sequencer's instruments.
local Cry = {}
local FRAME_RATE = 16777216 / 280896
-- length, release, pitch, chorus, reverse, optional native volume
local MODES = {
  { 140, 0, 15360, 0, false },
  { 20, 225, 15360, 0, false },
  { 140, 225, 15600, 20, false, 90 },
  { 50, 200, 15800, 20, false, 90 },
  { 25, 100, 15600, 192, true, 90 },
  { 140, 200, 14440, 0, false },
  { 140, 220, 15555, 192, false, 90 },
  { 10, 100, 14848, 0, false },
  { 60, 225, 15616, 0, false },
  { 15, 125, 15200, 0, true },
  { 100, 225, 15200, 0, false },
  { 140, 0, 15000, 0, false },
  { 20, 225, 15000, 0, false },
}
function Cry.params(mode, version, volume)
  mode = tonumber(mode) or 0
  if not MODES[mode + 1] then
    mode = 0
  end
  local row = MODES[mode + 1]
  return {
    mode = mode,
    length = row[1],
    release = row[2],
    pitch = row[3],
    chorus = row[4],
    reverse = row[5],
    volume = version == "emerald" and mode == 6 and 70 or row[6] or tonumber(volume) or 120,
  }
end

function Cry.waveRate(freq)
  freq = tonumber(freq) or 0
  if freq <= 0 then
    return 13379
  end
  local rate = math.floor(freq / 1024 + 0.5)
  if rate < 500 then
    return 13379
  end
  return math.min(48000, rate)
end

-- Each compressed block starts with an absolute signed sample. The first
-- nibble is unused; subsequent nibbles add signed square-law deltas. Keep
-- the accumulator unbounded and clamp only the emitted sample.
function Cry.decodeDpcm(bytes, count)
  if type(bytes) ~= "string" or not count or count <= 0 then
    return ""
  end
  local out, written = {}, 0
  local function emit(value)
    written = written + 1
    out[written] = string.char((math.max(-128, math.min(127, value)) + 256) % 256)
  end
  local function delta(nibble)
    local signed = nibble < 8 and nibble or nibble - 16
    return signed < 0 and -(signed * signed) or signed * signed
  end
  for block = 0, math.ceil(count / 64) - 1 do
    local start = block * 33 + 1
    local first = bytes:byte(start)
    if not first then
      break
    end
    local value = first >= 128 and first - 256 or first
    emit(value)
    for sample = 1, 63 do
      if written >= count then
        break
      end
      local offset = math.floor(sample / 2) + 1
      local byte = bytes:byte(start + offset)
      if not byte then
        break
      end
      local nibble = sample % 2 == 1 and byte % 16 or math.floor(byte / 16)
      value = value + delta(nibble)
      emit(value)
    end
    if written >= count then
      break
    end
  end
  return table.concat(out)
end

function Cry.render(pcm, rate, params, options)
  options = options or {}
  if type(pcm) ~= "string" or #pcm == 0 then
    return nil
  end
  local outRate = options.outRate or rate or 13379
  rate = rate or 13379
  local length = math.max(0, math.floor(tonumber(params.length) or 0))
  local release = math.max(0, math.floor(tonumber(params.release) or 0))
  local tail, envelope = {}, 255
  while true do
    envelope = math.floor(envelope * release / 256)
    if envelope <= 0 then
      break
    end
    tail[#tail + 1] = envelope / 255
  end
  local endFrame = length + #tail
  local pitch = ((tonumber(params.pitch) or 15360) + 128) % 65536
  if pitch >= 32768 then
    pitch = pitch - 65536
  end
  local key, tune = math.floor(pitch / 256) % 128, math.floor(pitch / 2) % 128
  local tunes = { tune }
  local chorus = (tonumber(params.chorus) or 0) % 256
  if chorus ~= 0 then
    if chorus >= 128 then
      chorus = chorus - 256
    end
    tunes[2] = (chorus + tune) % 128
  end
  local voices, samples = {}, 0
  local envelopeSamples = math.ceil(endFrame * outRate / FRAME_RATE)
  for _, value in ipairs(tunes) do
    local multiplier = 2 ^ (((key - 60) * 64 + value - 64) / (64 * 12))
    local step = rate * multiplier / outRate
    local natural = math.ceil(#pcm / step)
    local count = math.min(natural, envelopeSamples)
    voices[#voices + 1] = { step = step, count = count, natural = natural }
    samples = math.max(samples, count)
  end
  local channels = options.pan and not options.mono and 2 or 1
  local info = {
    frames = math.min(endFrame, math.ceil(voices[1].natural * FRAME_RATE / outRate)),
    endFrame = endFrame,
    voices = #voices,
    outRate = outRate,
    seconds = samples / outRate,
  }
  if not (love and love.sound and love.sound.newSoundData) then
    return nil, info
  end
  local sound = love.sound.newSoundData(math.max(1, samples), outRate, 16, channels)
  local gain = (tonumber(params.volume) or 120) / 127
  local left, right = 1, 1
  if options.pan then
    left, right = (127 - options.pan) / 191, (128 + options.pan) / 191
  end
  for i = 0, samples - 1 do
    local frame = math.floor(i * FRAME_RATE / outRate)
    local env = frame < length and 1 or tail[frame - length + 1] or 0
    local value = 0
    if env * gain > 0 then
      for _, voice in ipairs(voices) do
        if i < voice.count then
          local index = math.floor(i * voice.step)
          if params.reverse then
            index = #pcm - 1 - index
          end
          local byte = pcm:byte(index + 1) or 0
          value = value + (byte >= 128 and byte - 256 or byte) / 128
        end
      end
      value = math.max(-1, math.min(1, value * (env * gain)))
    end
    if channels == 2 then
      sound:setSample(i, 1, value * left)
      sound:setSample(i, 2, value * right)
    else
      sound:setSample(i, value * (left + right) * 0.5)
    end
  end
  return sound, info
end
return Cry
