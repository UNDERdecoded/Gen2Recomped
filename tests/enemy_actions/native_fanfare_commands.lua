local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local cases = {
    { name = "ordinary", speed = 1 },
    { name = "fast", speed = 10 },
    { name = "four-times", speed = 4 },
    { name = "logic-paused", speed = 0 },
    { name = "variable", speed = 1, variable = true },
    { name = "fallback", speed = 1, unknown = true },
    { name = "no-table", speed = 1, unknown = true, noTable = true, ticks = 180 },
    { name = "song-timer", speed = 1, songFrames = 6 },
    { name = "empty-table", speed = 1, emptyTable = true, ticks = 180 },
    { name = "no-fanfare", speed = 1, silent = true },
    { name = "bgm-dispatch", speed = 1, asBgm = true },
    { name = "audio-paused", speed = 1, noAudio = true, ticks = 370 },
    { name = "long", speed = 1, frames = 400, ticks = 420 },
    { name = "long-fast", speed = 10, frames = 400, ticks = 420 },
    { name = "replacement", speed = 1, action = "replace" },
    { name = "new-bgm", speed = 1, action = "new" },
    { name = "same-bgm", speed = 1, action = "same" },
    { name = "stop-bgm", speed = 1, action = "stop" },
    { name = "deferred-default", speed = 1, action = "default", cycle = true },
    { name = "latched-completion", speed = 1, action = "latched", actionAt = 4 },
  }
  local rows = {}
  for _, case in ipairs(cases) do
    local h = dofile(root .. "/tests/native_bgm/fanfares.lua").install(root, backend, version, f, case)
    h.clear()
    local script = {}
    if case.cycle then
      script[#script + 1] = { "playbgm", h.bgmIds[2], 0 }
    end
    local id = case.unknown and 999 or h.ids[1]
    if case.variable then
      script[#script + 1] = { "setvar", 0x8004, id }
      id = 0x8004
    end
    if not case.silent then
      script[#script + 1] = { case.asBgm and "playbgm" or "playfanfare", id, 1 }
    end
    script[#script + 1] = { "setvar", 0x4002, 1 }
    script[#script + 1] = { "waitfanfare" }
    script[#script + 1] = { "setvar", 0x4001, 1 }
    script[#script + 1] = { "end" }
    local runner = h.start(script)
    local frames, completed = {}, nil
    for tick = 0, case.ticks or 14 do
      h.tick(tick)
      if tick == (case.actionAt or 2) then
        local action
        if case.action == "replace" or case.action == "latched" then
          action = { "playfanfare", h.ids[2] }
        elseif case.action == "new" then
          action = { "playbgm", h.bgmIds[2], 0 }
        elseif case.action == "same" then
          action = { "playbgm", h.bgmIds[1], 0 }
        elseif case.action == "stop" then
          action = { "playbgm", 0, 0 }
        elseif case.action == "default" then
          action = { "fadedefaultbgm" }
        end
        if action then
          h.start({ action, { "end" } })
        end
      end
      if tick > 0 then
        for _ = 1, case.speed do
          f.game.save.playTime = (f.game.save.playTime or 0) + 1 / 60
          if native then
            runner:tick()
          else
            runner:update()
          end
        end
      end
      local state = h.state()
      state.tick, state.running, state.value = tick, runner:isRunning(), h.value(runner)
      state.startedValue = h.value(runner, 0x4002)
      if state.value == 1 then
        completed = completed or tick
      end
      frames[#frames + 1] = state
      if not case.noAudio then
        h.update()
      end
    end
    rows[#rows + 1] = { case = case.name, completed = completed, frames = frames, plays = h.trace() }
    h.close()
  end
  f.close()
  return rows
end
return M
