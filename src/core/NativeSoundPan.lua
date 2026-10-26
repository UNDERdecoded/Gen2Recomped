-- GBA PlaySE12PanpotControl: trim the opposite channel without recentering
-- the track's original stereo mix. Mono folds the trimmed channels together.
local M = {}
function M.value(pan)
  pan = tonumber(pan) or 0
  if pan ~= pan or pan == math.huge or pan == -math.huge then
    return 0
  end
  return math.max(-64, math.min(63, pan))
end
function M.apply(source, pan, mono)
  pan = M.value(pan) / 64
  local left, right = 1 - math.max(0, pan), 1 - math.max(0, -pan)
  local count, channels = source:getSampleCount(), source:getChannelCount()
  local result = love.sound.newSoundData(count, source:getSampleRate(), source:getBitDepth(), mono and 1 or 2)
  local function bounded(value)
    return math.max(-1, math.min(1, value))
  end
  for i = 0, count - 1 do
    local l = bounded(source:getSample(i, 1) * left)
    local r = bounded(source:getSample(i, channels > 1 and 2 or 1) * right)
    if mono then
      result:setSample(i, (l + r) / 2)
    else
      result:setSample(i, 1, l)
      result:setSample(i, 2, r)
    end
  end
  return result
end
return M
