package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.modkit")
local root, backend, version = unpack(arg)
local native = backend == "gen1"
local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
local runtime, oldSession
if native then
  runtime = require("src.core.game3.runtime")
  oldSession, runtime.session = runtime.session, { version = version }
end
local rows = {}
for _, case in ipairs({
  { name = "default" },
  { name = "mode-one", options = { mode = 1 } },
  { name = "mode-six", options = { mode = 6 } },
  { name = "no-duck", options = { noDuck = true } },
  { name = "release", options = { release = true } },
  { name = "stop", stop = 3 },
  { name = "overlap", overlap = true },
  { name = "option-change", change = true },
}) do
  local h = dofile(root .. "/tests/native_cry/fixture.lua").install(native, f)
  local audio = native and require("src.core.game3.audio")
  local Music = require("src.core.Music")
  local bgm, originalBuilder = nil, love.audio.newSource
  love.audio.newSource = function(input, ...)
    local made = originalBuilder(input, ...)
    if input == "owned-cry-bgm.wav" then
      bgm = made
    end
    return made
  end
  local oldSource, oldLevel, oldFadeIn, oldFadeOut
  if native then
    oldSource, oldLevel, oldFadeIn, oldFadeOut =
      audio._bgmSource, audio._bgmVolume, audio._fadeIn, audio._fadeOut
    audio._fadeIn, audio._fadeOut = nil, nil
    bgm = love.audio.newSource("owned-cry-bgm.wav", "stream")
    audio._bgmSource = bgm
    audio.applyEngineOptions({ musicVol = 7, sfxVol = 7 })
    bgm:play()
  else
    Music.stop()
    Music.setVolumeLevel(7)
    f.data.audio.songs = { OWNED_CRY_BGM = { file = "owned-cry-bgm.wav" } }
    Music.play(f.data, "OWNED_CRY_BGM", true)
    assert(Music.current() == "OWNED_CRY_BGM")
  end
  assert(bgm and bgm:isPlaying())
  local initial, scale, frames = bgm.volume, 1, {}
  for tick = 0, 30 do
    h.tick(tick)
    if tick == 0 then
      h.play(4, case.options or {})
    end
    if tick == case.stop then
      h.stop()
    end
    if tick == 2 and case.overlap then
      h.play(277, { mode = 6 })
    end
    if case.change and (tick == 2 or tick == 4 or tick == 6) then
      local level = tick == 2 and 4 or tick == 4 and 0 or 7
      scale = level / 7
      if native then
        audio.applyEngineOptions({ musicVol = level, sfxVol = 7 })
      else
        Music.setVolumeLevel(level)
      end
    end
    local state = h.snapshot()
    -- Native sample-stream and shared music have different baseline gains.
    -- Retain both raw values and assert only this admitted attenuation factor.
    assert(
      math.abs(bgm.volume - initial * scale * state.mix.level) < 1e-12,
      "actual BGM source must receive the current native cry attenuation"
    )
    frames[#frames + 1] = {
      tick = tick,
      rawVolume = bgm.volume,
      baseGain = initial,
      optionScale = scale,
      level = state.mix.level,
      playing = bgm:isPlaying(),
    }
    h.update()
  end
  rows[#rows + 1] = { case = case.name, frames = frames }
  love.audio.newSource = originalBuilder
  if native then
    bgm:stop()
    audio._bgmSource, audio._bgmVolume, audio._fadeIn, audio._fadeOut =
      oldSource, oldLevel, oldFadeIn, oldFadeOut
  else
    Music.stop()
  end
  h.close()
end
if native then
  runtime.session = oldSession
end
f.close()
print("NATIVE_CRY_BGM_SOURCES " .. require("src.link.Json").encode(rows))
