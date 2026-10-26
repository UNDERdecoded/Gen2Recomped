local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/assist.lua").fixture(root, backend, version)
  local cases = {
    {
      name = "plain-out",
      build = function(a, b, c)
        return { { "fadeoutbgm", 4 }, { "end" } }
      end,
    },
    {
      name = "speed-zero",
      build = function(a, b, c)
        return { { "fadeoutbgm", 0 }, { "end" } }
      end,
    },
    {
      name = "keep-and-save",
      build = function(a, b, c)
        return { { "playbgm", b, 1 }, { "savebgm", c }, { "end" } }
      end,
    },
    {
      name = "keep-two",
      build = function(a, b, c)
        return { { "savebgm", c }, { "playbgm", b, 2 }, { "end" } }
      end,
    },
    {
      name = "new-music",
      build = function(a, b, c)
        return { { "fadenewbgm", b }, { "end" } }
      end,
    },
    {
      name = "default-file-only",
      build = function(a, b, c)
        return { { "playbgm", b, 0 }, { "fadedefaultbgm" }, { "end" } }
      end,
    },
    {
      name = "incoming",
      build = function(a, b, c)
        return { { "playbgm", b, 0 }, { "fadeinbgm", 8 }, { "end" } }
      end,
    },
    {
      name = "silence",
      build = function(a, b, c)
        return { { "playbgm", 0, 0 }, { "end" } }
      end,
    },
    {
      name = "clear-saved",
      build = function(a, b, c)
        return { { "savebgm", b }, { "savebgm", 0xFFFF }, { "end" } }
      end,
    },
    {
      name = "out-options",
      options = true,
      build = function(a, b, c)
        return { { "fadeoutbgm", 1 }, { "end" } }
      end,
    },
  }
  cases[#cases + 1] = {
    name = "restart-same-mid-out",
    replaceAt = 3,
    replacement = "same",
    build = function(a, b, c)
      return { { "fadeoutbgm", 4 }, { "end" } }
    end,
  }
  cases[#cases + 1] = {
    name = "out-and-in",
    build = function(a, b, c)
      return { { "fadeoutbgm", 4 }, { "fadeinbgm", 4 }, { "end" } }
    end,
  }
  cases[#cases + 1] = {
    name = "in-and-out",
    build = function(a, b, c)
      return { { "fadeinbgm", 4 }, { "fadeoutbgm", 4 }, { "end" } }
    end,
  }
  cases[#cases + 1] = {
    name = "in-options",
    options = true,
    build = function(a, b, c)
      return { { "fadeinbgm", 4 }, { "end" } }
    end,
  }
  cases[#cases + 1] = {
    name = "incoming-replaced",
    replaceAt = 3,
    replacement = "other",
    build = function(a, b, c)
      return { { "fadeinbgm", 4 }, { "end" } }
    end,
  }
  cases[#cases + 1] = {
    name = "stopped-fades",
    replaceAt = 3,
    replacement = "stop",
    build = function(a, b, c)
      return { { "fadeinbgm", 4 }, { "fadeoutbgm", 4 }, { "end" } }
    end,
  }
  local rows = {}
  for _, case in ipairs(cases) do
    local h = dofile(root .. "/tests/native_bgm/fixture.lua").install(root, backend, version, f)
    local runner = h.start(case.build(unpack(h.ids)))
    local frames = {}
    for tick = 0, 80 do
      h.tick(tick)
      if tick == case.replaceAt then
        local id = case.replacement == "same" and h.ids[1] or case.replacement == "other" and h.ids[2] or 0
        runner = h.start({ { "playbgm", id, 0 }, { "end" } })
      end
      if case.options and (tick == 2 or tick == 4 or tick == 6) then
        h.options(tick == 2 and 4 or tick == 4 and 0 or 7)
      end
      local state = h.state()
      state.tick, state.running = tick, runner:isRunning()
      frames[#frames + 1] = state
      h.update()
    end
    rows[#rows + 1] = { case = case.name, frames = frames, plays = h.trace() }
    h.close()
  end
  f.close()
  return rows
end
return M
