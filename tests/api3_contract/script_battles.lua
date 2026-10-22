local M = {}
function M.fixture(root, backend, version, modId)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_battles%.lua$")
  local f = dofile(codeRoot .. "/wild_battle.lua").fixture(root, backend, version, modId or "script_battles")
  f.loader.game = f.game
  f.ow.runner.update = function() end
  if f.field then
    function f.field.lock(token)
      f.field._locks[token] = true
    end
    function f.field.unlock(token)
      f.field._locks[token] = nil
    end
  end
  function f:tick()
    self.loader.hooks:call(backend == "gen1" and "core.update" or "input.step", function()
      if backend == "gen2" then
        self.ow.runner:update()
      end
    end, self.game, 1 / 60)
  end
  function f:drain()
    for _ = 1, 50 do
      if self.exports.result().done > 0 then
        return
      end
      self:tick()
    end
    error("battle script did not finish")
  end
  return f
end
function M.run(root, backend, version)
  local report = {}
  for _, outcome in ipairs({ "win", "lose", "run", "caught" }) do
    local f = M.fixture(root, backend, version)
    local beat = f.gen == 1 and "EVENT_BEAT_MEWTWO" or "mod:beat"
    assert(f.exports.queue({
      { "static_battle", "MEW", 5, beat },
      { "check_battle_result", outcome },
      { "jump_if_false", "end" },
      { "set_flag", "mod:result" },
    }))
    assert(f.exports.result().done == 0 and f.pushed == 1)
    f:complete(outcome)
    f:drain()
    assert(f.exports.result().success and f.exports.get("mod:result"))
    assert(
      f.exports.get(beat) == (outcome ~= "lose") and f.after == 1,
      outcome .. " beat=" .. tostring(f.exports.get(beat)) .. " cleanup=" .. f.after
    )
    report[outcome] = { beat = f.exports.get(beat), after = f.after, result = true }
    f.restore()
  end
  local f = M.fixture(root, backend, version)
  local value, why =
    f.exports.queue({ { "start_battle", "wild", "MEW", 5 }, { "static_battle", "UNKNOWN", 5 } })
  assert(value == nil and type(why) == "string" and f.constructed == 0)
  report.preflight = true
  f.restore()
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
