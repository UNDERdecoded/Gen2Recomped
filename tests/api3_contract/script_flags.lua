local M = {}
function M.fixture(root, backend, version, modId)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_flags%.lua$")
  local f = dofile(codeRoot .. "/warp.lua").fixture(root, backend, version, modId or "script_flags")
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
    if backend == "gen1" then
      self.loader.hooks:call("core.update", function() end, self.game, 1 / 60)
    else
      self.loader.hooks:call("input.step", function()
        self.ow.runner:update()
      end, self.game, 1 / 60)
    end
  end
  function f:drain()
    for _ = 1, 100 do
      self:tick()
      if self.exports.result().done > 0 then
        return
      end
    end
    error("script did not complete")
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local rows = {
    { "set_flag", "mod:ready" },
    { "check_flag", "mod:ready" },
    { "jump_if_false", "failed" },
    { "clearflag", "mod:ready" },
    { "check_flag", "mod:ready" },
    { "jump_if_true", "failed" },
    { "setflag", "mod:result" },
    { "jump", "end" },
    { "label", "failed" },
    { "set_flag", "mod:failure" },
  }
  assert(f.exports.queue(rows))
  f:drain()
  assert(f.exports.get("mod:result") == true and f.exports.get("mod:failure") == false)
  assert(f.exports.get("mod:ready") == false and f.exports.result().success == true)
  local report = { branch = true }
  f = M.fixture(root, backend, version)
  assert(f.exports.queue({
    { "wait_flag", "mod:signal", 20 },
    { "jump_if_false", "end" },
    {
      "set_flag",
      "mod:resumed",
    },
  }))
  f:tick()
  assert(f.exports.result().done == 0)
  assert(f.exports.set("mod:signal", true))
  f:drain()
  assert(f.exports.get("mod:resumed") == true)
  report.resumed = f.exports.result()
  f = M.fixture(root, backend, version)
  assert(f.exports.queue({
    { "wait_flag", "mod:signal", 2 },
    { "jump_if_true", "end" },
    {
      "set_flag",
      "mod:timeout",
    },
  }))
  f:drain()
  assert(f.exports.get("mod:timeout") == true)
  report.timeout = f.exports.result()
  f = M.fixture(root, backend, version)
  local value, why = f.exports.queue({ { "set_flag", "mod:prefix" }, { "set_flag", "not_a_real_flag" } })
  assert(value == nil and type(why) == "string")
  assert(f.exports.get("mod:prefix") == false and f.exports.result().done == 0)
  report.preflight = true
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
