package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local root = assert(arg[1])
local rows = {}
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, "gen1", version)
  local runtime = require("src.core.game3.runtime")
  local savedSession = runtime.session
  runtime.session = { version = version }
  assert(require("src.core.game3.profile").forSession(nil).id == version)
  local audio = require("src.core.game3.audio")
  local savedWait, savedSuspend = audio._waitSe, audio._suspended
  audio._suspended = false
  local hardware = dofile(root .. "/tests/native_sound/fixture.lua").install(root, true, f)
  for _, case in ipairs({
    { name = "logic-only", audioEvery = 0, count = 0, expected = 181 },
    { name = "normal-audio-after-logic", audioEvery = 1, count = 1, expected = 180 },
    { name = "two-audio-ticks-per-logic", audioEvery = 1, count = 2, expected = 90 },
    { name = "one-audio-tick-per-two-logic", audioEvery = 2, count = 1, expected = 181 },
    { name = "latched-silence-before-replacement", audioEvery = 1, count = 1, expected = 2, latch = true },
  }) do
    hardware.clear()
    audio._waitSe = {}
    hardware.tick(0)
    audio.playSe(141, { pan = -64 })
    local vm = require("src.core.game3.scripting.vm").new({
      scripts = { OWNED_WAIT = { { op = "waitse" }, { op = "setvar", 0x4001, 1 }, { op = "end" } } },
    })
    assert(vm:start("OWNED_WAIT"))
    local frames, completed = {}, nil
    for tick = 0, 183 do
      hardware.tick(tick)
      if tick > 0 then
        vm:tick()
      end
      local advanced = require("src.core.game3.scripting.flags").getVar(vm.store, vm.ctx, 0x4001) == 1
      frames[#frames + 1] = {
        tick = tick,
        advanced = advanced,
        running = vm:isRunning(),
        active = hardware.active(),
        queries = hardware.queries(),
        pendingCallbacks = #(audio._waitSe or {}),
      }
      if advanced then
        completed = tick
        break
      end
      if case.latch and tick == 1 then
        audio.stopSe()
      end
      if case.audioEvery > 0 and tick % case.audioEvery == 0 then
        for _ = 1, case.count do
          audio.update(1 / 60)
        end
      end
      if case.latch and tick == 1 then
        audio.playSe(164, { pan = 63 })
      end
    end
    assert(completed == case.expected, case.name .. " native completion was " .. tostring(completed))
    if case.latch then
      assert(audio.isSePlaying(164), "latched wait releases despite the replacement's active voice")
    end
    rows[#rows + 1] = {
      version = version,
      case = case.name,
      completed = completed,
      frames = frames,
      sounds = hardware.trace(),
    }
  end
  hardware.clear()
  hardware.close()
  audio._waitSe, audio._suspended = savedWait, savedSuspend
  runtime.session = savedSession
  f.close()
end
print("NATIVE_SOUND_WAIT_CLOCK_ORACLE " .. require("src.link.Json").encode(rows))
