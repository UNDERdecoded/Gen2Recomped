local C = {}

function C.run(f)
  local T, e, hooks, bridge = f.T, f.exports, f.exports.api.hooks, f.bridge
  local rows, nativeCalls = {}, 0
  T.check(type(bridge.quitToLauncher) == "function", "native quit decision bridge exists")
  if type(bridge.quitToLauncher) ~= "function" then
    return rows
  end
  local decision = false
  local function vanilla()
    nativeCalls = nativeCalls + 1
    return decision
  end
  local function observe(label, value)
    rows[#rows + 1] = {
      label = label,
      decision = value,
      nativeCalls = nativeCalls,
      calls = e.calls(),
      cleanups = e.cleanups(),
    }
  end
  for _, value in ipairs({ false, true }) do
    decision = value
    local before, calls = nativeCalls, e.calls()
    local result = bridge.quitToLauncher(vanilla)
    T.eq(result, value, "next retains the native quit decision")
    T.eq(nativeCalls, before + 1, "native decision runs once")
    T.eq(e.calls(), calls + 1, "public wrapper runs once")
    T.eq(e.argumentCount(), 0, "hook exposes only its continuation")
    T.eq(e.cleanups(), 1, "consumer resource disposal stays idempotent")
    observe("forward-" .. tostring(value), result)
  end
  if e.api.supports then
    T.eq(e.api:supports("hooks", "core.quit_to_launcher"), true, "native capability advertised")
  end
  for _, mode in ipairs({ "exit", "launcher" }) do
    e.mode(mode)
    local before = nativeCalls
    local result = bridge.quitToLauncher(vanilla)
    T.eq(result, mode == "launcher", "explicit mod decision overrides the host default")
    T.eq(nativeCalls, before, "override does not invoke native decision")
    observe(mode, result)
  end
  e.mode("forward")
  local order = {}
  local off = hooks:wrap("core.quit_to_launcher", function(next)
    order[#order + 1] = "outer"
    local value = next()
    order[#order + 1] = "after"
    return not value
  end, 20)
  local inner = hooks:wrap("core.quit_to_launcher", function(next)
    order[#order + 1] = "inner"
    return next()
  end, 10)
  decision = false
  T.eq(bridge.quitToLauncher(vanilla), true, "wrapper may postprocess the native decision")
  T.same(order, { "outer", "inner", "after" }, "descending wrapper priority")
  off()
  inner()
  for _, after in ipairs({ false, true }) do
    off = hooks:wrap("core.quit_to_launcher", function(next)
      if after then
        next()
      end
      error("intentional quit wrapper failure")
    end, 100)
    local before = nativeCalls
    T.eq(bridge.quitToLauncher(vanilla), false, "failed wrapper preserves native decision")
    T.eq(nativeCalls, before + 1, "failed wrapper does not duplicate native decision")
    off()
  end
  local attempts = 0
  T.raises(function()
    bridge.quitToLauncher(function()
      attempts = attempts + 1
      error("native quit decision failure")
    end)
  end, "native quit decision failure", "native failures propagate")
  T.eq(attempts, 1, "native failure is not retried")
  if f.api >= 3 then
    off = hooks:wrap("core.quit_to_launcher", function(next)
      next()
      return next()
    end, 100)
    local before = nativeCalls
    bridge.quitToLauncher(vanilla)
    T.eq(nativeCalls, before + 1, "API-3 continuation caches the downstream decision")
    off()
  end
  e.stop()
  e.stop()
  local calls = e.calls()
  T.eq(bridge.quitToLauncher(vanilla), false, "unsubscribed chain retains native decision")
  T.eq(e.calls(), calls, "unsubscribe is idempotent")
  observe("unsubscribed", false)
  return rows
end

return C
