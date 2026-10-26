local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local runtime, savedSession
  if native then
    runtime = require("src.core.game3.runtime")
    savedSession = runtime.session
    runtime.session = { version = version }
    assert(require("src.core.game3.profile").forSession(nil).id == version)
  end
  local rows = {}
  for _, case in ipairs({
    { name = "silent", silent = true },
    { name = "no-pack", noPack = true },
    { name = "mode-zero" },
    { name = "mode-one", mode = 1 },
    { name = "mode-two", mode = 2 },
    { name = "mode-three", mode = 3 },
    { name = "mode-four", mode = 4 },
    { name = "mode-five", mode = 5 },
    { name = "mode-six", mode = 6 },
    { name = "mode-seven", mode = 7 },
    { name = "mode-eight", mode = 8 },
    { name = "mode-nine", mode = 9 },
    { name = "mode-ten", mode = 10 },
    { name = "mode-eleven", mode = 11 },
    { name = "mode-twelve", mode = 12 },
    { name = "variables", variables = true, mode = 2 },
    { name = "hoenn", species = 277 },
    { name = "legacy-hoenn-cache", species = 277, legacyMapping = true },
    { name = "normal-audio", audioEvery = 1 },
    { name = "half-audio", audioEvery = 2 },
    { name = "early-source-end", finishAt = 2 },
    { name = "mono", mono = true },
    { name = "unknown-mode", mode = 255 },
    { name = "zero-species", species = 0 },
    { name = "old-unown-species", species = 252 },
    { name = "unsupported-species", species = 412 },
    { name = "overlapping", overlap = true },
    { name = "consecutive", consecutive = true },
    { name = "consecutive-no-pack", consecutive = true, noPack = true },
    { name = "file-override", override = "file", finishAt = 3 },
    { name = "string-override", override = "string", finishAt = 3 },
    { name = "disabled-override", override = "disabled" },
    { name = "disabled-after-native", overrideLater = "disabled" },
  }) do
    local h = dofile(root .. "/tests/native_cry/fixture.lua").install(native, f, case)
    if case.override then
      h.override(case.species or 4, case.override)
    end
    local commands = {}
    local function add(name, a, b)
      commands[#commands + 1] = native and { op = name, a, b } or { name, a, b }
    end
    local species, mode = case.species or 4, case.mode or 0
    if case.variables then
      add("setvar", 0x8004, species)
      add("setvar", 0x8005, mode)
      species, mode = 0x8004, 0x8005
    end
    if not case.silent then
      add("playmoncry", species, mode)
    end
    if case.overlap then
      add("playmoncry", 277, 6)
    end
    add("waitmoncry")
    if case.consecutive then
      add("setvar", 0x4002, 1)
      add("playmoncry", 277, 6)
      add("waitmoncry")
    end
    add("setvar", 0x4001, 1)
    add("end")
    local runner, value
    h.tick(0)
    if native then
      runner = require("src.core.game3.scripting.vm").new({ scripts = { OWNED_CRY = commands } })
      assert(runner:start("OWNED_CRY"))
      value = function()
        return require("src.core.game3.scripting.flags").getVar(runner.store, runner.ctx, 0x4001)
      end
    else
      local Cmd = require("src.script.Gen3Commands")
      Cmd.setVar(f.game.save, 0x4001, 0)
      local lowered = assert(require("src.script.Gen3ScriptVM").compile({
        map_scripts = {
          source = "RomExtractorGen3",
          scripts = { OWNED_CRY = commands },
        },
      }, "OWNED_CRY"))
      runner = require("src.script.ScriptRunner").new(f.game, {})
      runner:run(lowered, { source = { modId = "portable_held_item", strict = true } })
      value = function()
        return Cmd.getVar(f.game.save, 0x4001)
      end
    end
    local frames, completed = {}, nil
    for tick = 0, case.consecutive and 150 or 75 do
      h.tick(tick)
      if tick == case.finishAt then
        h.endSources()
      end
      if case.overrideLater and tick == 1 then
        h.override(4, case.overrideLater)
        h.play(4, { mode = 2 })
      end
      if tick > 0 then
        if native then
          runner:tick()
        else
          runner:update()
        end
      end
      local snapshot = h.snapshot()
      frames[#frames + 1] = {
        tick = tick,
        value = value(),
        running = runner:isRunning(),
        finished = snapshot.finished,
        clock = snapshot.clock,
        untilFrame = snapshot.untilFrame,
        mode = snapshot.mode,
        mix = snapshot.mix,
        sources = h.active(),
      }
      if value() == 1 and not completed then
        completed = tick
      end
      if case.audioEvery and tick % case.audioEvery == 0 then
        h.update()
      end
    end
    assert(completed ~= nil, "actual native cry command sequence completes")
    rows[#rows + 1] = { case = case.name, frames = frames, completed = completed, plays = h.trace() }
    h.close()
  end
  if native then
    runtime.session = savedSession
  end
  f.close()
  return rows
end
return M
