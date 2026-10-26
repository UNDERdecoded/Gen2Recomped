-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Private PCM writes; the returned object is still an ordinary SoundData.
local Performance = require("src.core.Performance")
local ok, ffi = pcall(require, "ffi")
local M = {}
local float = ok and ffi.new("float[1]") or nil
local nativeFloat = false
function M.pointer(sound)
  if
    Performance.audioWorkerOptimization == false
    or not ok
    or not jit
    or not jit.status()
    or not sound.getFFIPointer
  then
    return nil
  end
  -- LÖVE's LuaJIT SoundData wrapper multiplies doubles; its C method takes
  -- and multiplies floats. Follow the installed method, including on 11.x.
  nativeFloat = debug.getinfo(sound.setSample, "S").what == "C"
  local found, pointer = pcall(sound.getFFIPointer, sound)
  if not found or pointer == nil then
    return nil
  end
  local cast, value = pcall(ffi.cast, "int16_t *", pointer)
  return cast and value ~= nil and value or nil
end
function M.sample(value)
  -- SoundData takes a float argument and multiplies in float precision.
  -- Keep both rounding points before the native signed-integer truncation.
  if not nativeFloat then
    return value * 32767
  end
  float[0] = value
  float[0] = float[0] * 32767
  return float[0]
end
function M.render(engine, count, channels, rate)
  local sound = love.sound.newSoundData(count, rate, 16, channels)
  local pointer = M.pointer(sound)
  if pointer then
    if channels == 2 then
      for n = 0, count - 1 do
        local left, right = engine:sampleStereo()
        pointer[n * 2], pointer[n * 2 + 1] = M.sample(left), M.sample(right)
      end
    else
      for n = 0, count - 1 do
        pointer[n] = M.sample(engine:sample())
      end
    end
  else
    for n = 0, count - 1 do
      if channels == 2 then
        local left, right = engine:sampleStereo()
        sound:setSample(n, 1, left)
        sound:setSample(n, 2, right)
      else
        sound:setSample(n, engine:sample())
      end
    end
  end
  return sound
end
function M.arrays(left, right, count, rate)
  local sound = love.sound.newSoundData(count, rate, 16, 2)
  local pointer = M.pointer(sound)
  if pointer then
    for n = 1, count do
      pointer[(n - 1) * 2], pointer[(n - 1) * 2 + 1] = M.sample(left[n]), M.sample((right or left)[n])
    end
  else
    for n = 1, count do
      sound:setSample(n - 1, 1, left[n])
      sound:setSample(n - 1, 2, (right or left)[n])
    end
  end
  return sound
end
return M
