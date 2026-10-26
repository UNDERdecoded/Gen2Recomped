-- Apply platform mixing policy only when the audio backend admits it.
local AudioMix = {}
local sent
function AudioMix.set(value)
  value = value and true or false
  if sent == value then
    return false
  end
  if not (love and love.audio and love.audio.setMixWithSystem) then
    return false
  end
  if pcall(love.audio.setMixWithSystem, value) then
    sent = value
  end
  return true
end
function AudioMix.current()
  return sent
end
function AudioMix._resetForTest()
  sent = nil
end
return AudioMix
