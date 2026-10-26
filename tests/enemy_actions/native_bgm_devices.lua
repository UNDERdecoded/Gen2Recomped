-- No-output hardware retains real native logical command state.
local M = {}
function M.run(root, backend, version)
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local rows = {}
  for _, mode in ipairs({ "missing", "nil" }) do
    for _, command in ipairs({ "fadeoutbgm", "fadeinbgm", "shared-to-native" }) do
      local h = dofile(root .. "/tests/native_bgm/streams.lua").install(
        root,
        backend,
        version,
        f,
        { queueFailure = mode, initialShared = command == "shared-to-native" }
      )
      local frames = { h.state() }
      local runner = h.start({
        command == "shared-to-native" and { "playbgm", h.ids[2], 0 } or { command, 4 },
        { "end" },
      })
      for tick = 0, 3 do
        local state = h.state()
        state.tick, state.running = tick, runner:isRunning()
        frames[#frames + 1] = state
        h.update()
      end
      rows[#rows + 1] = { mode = mode, command = command, frames = frames, trace = h.trace() }
      h.close()
    end
  end
  f.close()
  return rows
end
return M
