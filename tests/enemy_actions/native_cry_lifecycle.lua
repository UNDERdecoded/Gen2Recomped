-- Actual native/host cry ownership, controls and complete rendered outputs.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local runtime, oldSession
  if native then
    runtime = require("src.core.game3.runtime")
    oldSession, runtime.session = runtime.session, { version = version }
  end
  local cases = {
    { name = "default" },
    { name = "no-duck", first = { noDuck = true } },
    { name = "release", first = { release = true } },
    { name = "multi-release", first = { release = true, multi = true } },
    { name = "mode-one-release", first = { mode = 1, release = true } },
    { name = "explicit-pan", first = { pan = -64 } },
    { name = "numeric-zero-pan", first = { pan = 0 } },
    { name = "string-zero-pan", first = { pan = "0" } },
    { name = "right-pan-mono", first = { pan = 63 }, mono = true },
    { name = "volume-zero", first = { volume = 0 } },
    { name = "volume-ninety", first = { volume = 90 } },
    { name = "boolean-controls-only", first = { release = 1, noDuck = "true", multi = 0 } },
    { name = "overlap", second = { mode = 6 } },
    { name = "overlap-same-buffer", same = true, second = { mode = 0 } },
    { name = "overlap-no-duck", second = { noDuck = true } },
    { name = "overlap-mode-one", second = { mode = 1 } },
    { name = "overlap-release", second = { release = true } },
    { name = "stop-latest-only", second = { mode = 6 }, stop = 3 },
    { name = "restart-after-stop", second = { mode = 2 }, stop = 1 },
    { name = "speaker-ends-early", endAt = 2 },
    { name = "file-override-after-native", override = "file", endAt = 3 },
    { name = "disabled-after-native", override = "disabled" },
  }
  local rows = {}
  for _, case in ipairs(cases) do
    local h = dofile(root .. "/tests/native_cry/fixture.lua").install(native, f, case)
    local frames = {}
    for tick = 0, 80 do
      h.tick(tick)
      if tick == 0 then
        h.play(4, case.first or {})
      end
      if tick == case.stop then
        h.stop()
      end
      if tick == 2 and case.second then
        h.play(case.same and 4 or 277, case.second)
      end
      if tick == 2 and case.override then
        h.override(4, case.override)
        h.play(4, { mode = 2 })
      end
      if tick == case.endAt then
        h.endSources()
      end
      local snapshot = h.snapshot()
      snapshot.tick, snapshot.sources = tick, h.active()
      frames[#frames + 1] = snapshot
      h.update()
    end
    rows[#rows + 1] = { case = case.name, frames = frames, plays = h.trace() }
    h.close()
  end
  if native then
    runtime.session = oldSession
  end
  f.close()
  return rows
end
return M
