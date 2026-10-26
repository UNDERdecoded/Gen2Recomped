-- Actual native world VM and host lowering/runner; only source hardware is owned.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local runtime, savedSession
  if native then
    runtime = require("src.core.game3.runtime")
    savedSession, runtime.session = runtime.session, { version = version }
    assert(require("src.core.game3.profile").forSession(nil).id == version)
  end
  local hardware = dofile(root .. "/tests/native_sound/fixture.lua").install(root, native, f)
  local audio = native and require("src.core.game3.audio") or require("src.core.Sound")
  local savedWaits = native and audio._waitSe
  local function audioTick()
    if native then
      audio.update(1 / 60)
    else
      audio.update()
    end
  end
  local function play(id, player)
    if player then
      hardware.player(id, player)
    end
    local opts = { pan = id == 141 and -64 or 63 }
    if native then
      audio.playSe(id, opts)
    else
      audio.playId(f.data, id, opts)
    end
  end
  local function stop(id)
    if native then
      audio.stopSe(id)
    else
      audio.stopSe(f.data, id)
    end
  end
  local rows = {}
  for _, case in ipairs({
    { name = "silent" },
    { name = "native-player-one", play = true },
    { name = "native-player-two", play = true, player = 2 },
    { name = "special-player-three", play = true, player = 3 },
    { name = "file-override", override = true },
    { name = "native-and-file-override", play = true, override = true },
    { name = "logic-only-cap", play = true, cap = true },
    { name = "normal-audio-cap", play = true, cap = true, audioEvery = 1, audioCount = 1 },
    { name = "double-audio-cap", play = true, cap = true, audioEvery = 1, audioCount = 2 },
    { name = "half-audio-cap", play = true, cap = true, audioEvery = 2, audioCount = 1 },
    { name = "latched-silence", play = true, latch = true, audioEvery = 1, audioCount = 1 },
    { name = "unlatched-silence", play = true, latch = true },
    { name = "replacement-keeps-waiting", play = true, replace = true },
    { name = "independent-player-keeps-waiting", play = true, other = 2 },
    { name = "special-player-after-regular", play = true, other = 3 },
    { name = "stop-native-keeps-file", play = true, override = true, stopEarly = true },
    { name = "consecutive-logic-waits", play = true, cap = true, twice = true },
    {
      name = "consecutive-audio-waits",
      play = true,
      cap = true,
      twice = true,
      audioEvery = 1,
      audioCount = 1,
    },
  }) do
    hardware.clear()
    audioTick()
    hardware.stereo(true)
    hardware.player(141, case.player or 1)
    hardware.player(164, 1)
    hardware.tick(0)
    if case.play then
      play(141)
    end
    if case.other then
      play(164, case.other)
    end
    if case.override then
      hardware.override(164, "file")
      if native then
        require("src.core.game3.audio").playSe(164)
      else
        require("src.core.Sound").playId(f.data, 164)
      end
    end
    local runner, advanced, firstAdvanced
    if native then
      local script = { { op = "waitse" }, { op = "setvar", 0x4001, 1 }, { op = "end" } }
      if case.twice then
        script = {
          { op = "waitse" },
          { op = "setvar", 0x4001, 1 },
          { op = "waitse" },
          { op = "setvar", 0x4002, 1 },
          { op = "end" },
        }
      end
      runner = require("src.core.game3.scripting.vm").new({
        scripts = {
          OWNED_WAIT = script,
        },
      })
      assert(runner:start("OWNED_WAIT"))
      advanced = function()
        return require("src.core.game3.scripting.flags").getVar(
          runner.store,
          runner.ctx,
          case.twice and 0x4002 or 0x4001
        ) == 1
      end
      firstAdvanced = function()
        return require("src.core.game3.scripting.flags").getVar(runner.store, runner.ctx, 0x4001) == 1
      end
    else
      local script = { { "waitse" }, { "setvar", 0x4001, 1 }, { "end" } }
      if case.twice then
        script = { { "waitse" }, { "setvar", 0x4001, 1 }, { "waitse" }, { "setvar", 0x4002, 1 }, { "end" } }
      end
      local data = {
        map_scripts = {
          source = "RomExtractorGen3",
          scripts = {
            OWNED_WAIT = script,
          },
        },
      }
      local commands = assert(require("src.script.Gen3ScriptVM").compile(data, "OWNED_WAIT"))
      runner = require("src.script.ScriptRunner").new(f.game, {})
      runner:run(commands)
      advanced = function()
        return require("src.script.Gen3Commands").getVar(f.game.save, case.twice and 0x4002 or 0x4001) == 1
      end
      firstAdvanced = function()
        return require("src.script.Gen3Commands").getVar(f.game.save, 0x4001) == 1
      end
    end
    local frames = {}
    local limit = case.twice and 365
      or case.cap and 183
      or (case.latch or case.replace or case.other or case.stopEarly) and 5
      or 4
    for tick = 0, limit do
      hardware.tick(tick)
      if case.replace and tick == 2 then
        play(164)
      end
      if (case.other or case.stopEarly) and tick == 2 or case.replace and tick == 3 then
        stop(141)
      end
      if not case.cap and tick == ((case.replace or case.other or case.latch) and 4 or 3) then
        stop()
      end
      if tick > 0 then
        if native then
          runner:tick()
        else
          runner:update()
        end
      end
      frames[#frames + 1] = {
        tick = tick,
        running = runner:isRunning(),
        advanced = advanced(),
        active = hardware.active(),
        queries = hardware.queries(),
      }
      if case.twice then
        frames[#frames].firstAdvanced = firstAdvanced()
      end
      if case.latch and tick == 1 then
        stop()
      end
      if case.audioEvery and tick % case.audioEvery == 0 then
        for _ = 1, case.audioCount do
          audioTick()
        end
      end
      if case.latch and tick == 1 then
        play(164)
      end
    end
    assert(frames[#frames].advanced, "actual script must reach its post-wait variable write")
    rows[#rows + 1] = { case = case.name, frames = frames, sounds = hardware.trace() }
    if not native then
      require("src.script.Gen3Commands").setVar(f.game.save, 0x4001, 0)
      require("src.script.Gen3Commands").setVar(f.game.save, 0x4002, 0)
    end
  end
  hardware.clear()
  audioTick()
  hardware.close()
  if native then
    audio._waitSe = savedWaits
    runtime.session = savedSession
  end
  f.close()
  return rows
end
return M
