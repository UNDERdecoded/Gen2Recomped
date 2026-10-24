local M = {}
function M.run(f)
  local T, e, rows = f.T, f.e, {}
  local function observe(label, want, calls)
    local before = e.state.calls
    local got = f.visible()
    T.eq(got, want, label .. " verdict")
    T.eq(e.state.calls - before, calls, label .. " dispatch count")
    if calls > 0 then
      T.eq(e.state.battle.publicTag, "caught_context", "callback carries native context fields")
      if f.api >= 3 or (f.backend == "gen2" and f.api == 2 and f.format == "unified") then
        T.check(e.state.battle ~= f.battle, "unified callback has a boundary view")
      else
        T.eq(e.state.battle, f.battle, "legacy native callback retains identity")
      end
    end
    rows[#rows + 1] = { label = label, visible = got, calls = e.state.calls - before }
  end
  for _, spec in ipairs({
    { "native", f.gen > 1 },
    { "show", true },
    { "hide", false },
    { "nil", false },
    { "zero", false },
    { "native", f.gen > 1 },
  }) do
    f.reset()
    e.state.mode = spec[1]
    observe(spec[1], spec[2], 1)
  end
  e.state.mode = "show"
  for _, opts in ipairs({ { caught = false }, { trainer = true }, { noDex = true } }) do
    f.reset(opts)
    observe(opts.caught == false and "not caught" or opts.trainer and "trainer" or "no dex", false, 0)
  end
  if f.gen == 2 then
    f.reset({ latched = false })
    observe("entry latch", false, 0)
  elseif f.gen == 3 then
    for _, opts in ipairs({ { tutorial = true }, { ghost = true }, { player = true } }) do
      f.reset(opts)
      observe(opts.tutorial and "tutorial" or opts.ghost and "ghost" or "player", false, 0)
    end
  end
  e.state.mode = "native"
  for _, after in ipairs({ false, true }) do
    local off = e.api.hooks:wrap("battle.caught_marker_visible", function(next, battle)
      if after then
        next(battle)
      end
      error("intentional marker wrapper failure")
    end, 100)
    f.reset()
    observe("error:" .. tostring(after), f.gen > 1, 1)
    off()
  end
  if f.api >= 3 then
    local off = e.api.hooks:wrap("battle.caught_marker_visible", function(next, battle)
      local a, b = next(battle), next(battle)
      T.eq(a, b, "API-3 repeated next retains verdict")
      return a
    end, 100)
    f.reset()
    observe("replay", f.gen > 1, 1)
    off()
  end
  e.stop()
  e.stop()
  f.reset()
  observe("unsubscribed", f.gen > 1, 0)
  return rows
end
return M
