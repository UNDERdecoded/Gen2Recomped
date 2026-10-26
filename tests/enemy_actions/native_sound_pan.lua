-- Common PCM carrier isolates native stereo/mono control from synthesis.
-- Every resulting sample and all format metadata participate in comparison.
local M = {}
function M.run(root, backend)
  local T = require("tests.modkit")
  local native = backend == "gen1"
  local apply = native and require("src.core.game3.audio")._buildSeSoundData
    or require("src.core.NativeSoundPan").apply
  local left = { -1, -0.75, -0.25, 0, 0.125, 0.5, 0.75, 1 }
  local other = { 1, 0.25, -0.5, 0.75, -0.125, 0, -1, 0.5 }
  local rows = {}
  for _, channels in ipairs({ 1, 2 }) do
    local right = channels == 1 and left or other
    for _, mono in ipairs({ false, true }) do
      for _, pan in ipairs({ -100, -64, -32, 0, 32, 63, 100 }) do
        local source = love.sound.newSoundData(#left, 44100, 16, channels)
        for i = 1, #left do
          source:setSample(i - 1, 1, left[i])
          if channels == 2 then
            source:setSample(i - 1, 2, right[i])
          end
        end
        local result = native and apply(left, right, 1, pan, mono) or apply(source, pan, mono)
        local samples = {}
        for i = 0, result:getSampleCount() - 1 do
          local frame = {}
          for c = 1, result:getChannelCount() do
            frame[c] = result:getSample(i, c)
          end
          samples[#samples + 1] = frame
          T.eq(source:getSample(i, 1), left[i + 1], "panning retains original carrier samples")
          if channels == 2 then
            T.eq(source:getSample(i, 2), right[i + 1], "panning retains original right channel")
          end
        end
        rows[#rows + 1] = {
          inputChannels = channels,
          mono = mono,
          pan = pan,
          sampleRate = result:getSampleRate(),
          bitDepth = result:getBitDepth(),
          channels = result:getChannelCount(),
          samples = samples,
        }
      end
    end
  end
  return rows
end
return M
