-- Complete owned PCM/control observations through unchanged native rendering.
local M = {}
function M.run(root, backend, version)
  local T = require("tests.modkit")
  local native = backend == "gen1"
  local module = native and require("src.core.game3.m4a_sample") or require("src.core.NativeCryPcm")
  local rows = {}
  local function params(mode, volume)
    if native then
      return module.cryParams(mode, volume, version == "emerald" and { [6] = { volume = 70 } } or nil)
    end
    return module.params(mode, version, volume)
  end
  local function record(pcm, rate, mode, options, label)
    local controls = params(mode)
    local sound, info
    if native then
      sound, info = module.renderCry(pcm, rate, controls, options)
    else
      sound, info = module.render(pcm, rate, controls, options)
    end
    assert(sound and info)
    local samples = {}
    for i = 0, sound:getSampleCount() - 1 do
      local channels = {}
      for c = 1, sound:getChannelCount() do
        channels[c] = sound:getSample(i, c)
      end
      samples[#samples + 1] = channels
    end
    rows[#rows + 1] = {
      kind = "pcm",
      case = label,
      mode = mode,
      controls = controls,
      options = options,
      info = info,
      rate = sound:getSampleRate(),
      depth = sound:getBitDepth(),
      channels = sound:getChannelCount(),
      samples = samples,
    }
  end
  local bytes = {}
  for i = 0, 128 do
    bytes[#bytes + 1] = string.char((i * 73 + i * i * 11) % 256)
  end
  local short = table.concat(bytes)
  local long = short:rep(128):sub(1, 8192)
  for _, mode in ipairs({ -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 255 }) do
    for _, volume in ipairs({ 0, 70, 120, 127 }) do
      rows[#rows + 1] = { kind = "params", mode = mode, volume = volume, controls = params(mode, volume) }
    end
    for _, options in ipairs({
      { outRate = 44100 },
      { outRate = 22050, mono = true, pan = -64 },
      { outRate = 44100, pan = 0 },
      { outRate = 44100, pan = 63 },
    }) do
      record(short, 13379, mode, options, "asymmetric-short")
    end
    record(long, 4000, mode, { outRate = 8000 }, "envelope-and-tail")
  end
  for _, freq in ipairs({ -1, 0, 1, 499 * 1024, 500 * 1024, 13379 * 1024 + 512, 96000 * 1024 }) do
    rows[#rows + 1] = { kind = "rate", input = freq, rate = module.waveRate(freq) }
  end
  local compressed = {}
  for i = 0, 131 do
    compressed[#compressed + 1] = string.char((i * 37 + 191) % 256)
  end
  compressed = table.concat(compressed)
  for _, length in ipairs({ 0, 1, 2, 32, 33, 34, 65, 132 }) do
    for _, count in ipairs({ 0, 1, 2, 63, 64, 65, 127, 128, 129, 256 }) do
      local result = native and module.decodeGfdpcm(compressed:sub(1, length), count)
        or module.decodeDpcm(compressed:sub(1, length), count)
      local decoded = {}
      for i = 1, #result do
        decoded[i] = result:byte(i)
      end
      rows[#rows + 1] = { kind = "dpcm", length = length, count = count, decoded = decoded }
    end
  end
  return rows
end
return M
