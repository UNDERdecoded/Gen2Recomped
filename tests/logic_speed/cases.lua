local M = {}
function M.run(f)
  local T, g, e, api = f.T, f.game, f.exports, f.public
  local rows = {}
  local function observe(label, expected)
    local value = g:logicSpeed()
    T.eq(value, expected, label)
    rows[#rows + 1] = { label = label, speed = value }
  end
  if api.supports then
    T.eq(api:supports("hooks", "core.logic_speed"), true, "native speed capability")
  end
  for _ = 1, 3 do
    observe("native saved option", 4)
  end
  T.eq(e.seen.calls, 3, "one hook call per unlocked resolution")
  T.eq(g.resolves, 3, "one native resolver per forwarded resolution")
  T.eq(e.seen.game, g, "original opaque Game identity")
  T.eq(e.seen.extra, 0, "no invented arguments")
  T.eq(e.seen.vanilla, 4, "next returns native resolution")
  for key in pairs(g.save.options) do
    g.save.options[key] = 10
  end
  observe("live saved option", 10)
  for key in pairs(g.save.options) do
    g.save.options[key] = 4
  end
  e.setSpeed(20)
  local resolves = g.resolves
  observe("mod override", 20)
  T.eq(g.resolves, resolves, "omitting next skips native resolver")
  e.setSpeed(nil)

  -- Clamp at the producer boundary, including nil/false and non-finite values.
  for _, case in ipairs({
    { name = "nil", expected = 1 },
    { name = "false", value = false, expected = 1 },
    { name = "NaN", value = 0 / 0, expected = 1 },
    { name = "infinity", value = math.huge, expected = 1 },
    { name = "negative infinity", value = -math.huge, expected = 1 },
    { name = "zero", value = 0, expected = 1 },
    { name = "negative", value = -20, expected = 1 },
    { name = "table", value = {}, expected = 1 },
    { name = "string", value = "20", expected = 20 },
    { name = "large", value = 1e9, expected = 200 },
  }) do
    local off = api.hooks:wrap("core.logic_speed", function()
      return case.value
    end, 100)
    observe(case.name .. " hook output", case.expected)
    off()
  end
  -- Each host retains its own ladder (Gen1 includes 3X; Gen2 does not).
  local off = api.hooks:wrap("core.logic_speed", function()
    return 3
  end, 100)
  T.eq(g:logicSpeed(), f.backend == "gen1" and 3 or 2, "native ladder preserved")
  off()
  local other = f.owner(10)
  off = api.hooks:wrap("core.logic_speed", function(next, game)
    T.eq(game, g, "outer wrapper sees original Game")
    return next(other)
  end, 100)
  resolves = g.resolves
  observe("replacement next target", 10)
  T.eq(other.resolves, 1, "native resolver uses replacement Game")
  T.eq(g.resolves, resolves, "original Game is not resolved after replacement")
  T.eq(e.seen.game, other, "replacement reaches downstream wrapper")
  off()
  local order = {}
  local outer = api.hooks:wrap("core.logic_speed", function(next)
    order[#order + 1] = "outer"
    local result = next()
    order[#order + 1] = "after"
    return result * 5
  end, 20)
  local inner = api.hooks:wrap("core.logic_speed", function(next, game)
    order[#order + 1] = "inner"
    T.eq(game, g, "next() retains current owner")
    return next()
  end, 10)
  observe("priority and postprocessing", 20)
  T.same(order, { "outer", "inner", "after" }, "descending wrapper priority")
  outer()
  inner()

  e.setSpeed(200)
  g.speedOverride = 20
  local calls = e.seen.calls
  resolves = g.resolves
  observe("explicit override wins", 20)
  T.eq(e.seen.calls, calls, "explicit override bypasses hook")
  T.eq(g.resolves, resolves, "explicit override bypasses saved option")
  for _, kind in ipairs({ "link", "fixed" }) do
    f.lock(kind)
    T.eq(g:speedLocked(), true, kind .. " native lock detected")
    observe(kind .. " wins over explicit override", 1)
    g.speedOverride = nil
    observe(kind .. " wins over hook", 1)
    T.eq(e.seen.calls, calls, kind .. " hook is never called")
    T.eq(g.resolves, resolves, kind .. " saved option is not resolved")
    f.lock(nil)
    observe(kind .. " unlock restores mod", 200)
    calls = e.seen.calls
    g.speedOverride = 20
  end
  g.speedOverride = nil
  f.lock(nil)
  e.setSpeed(nil)

  for _, after in ipairs({ false, true }) do
    off = api.hooks:wrap("core.logic_speed", function(next)
      if after then
        next()
      end
      error("intentional speed wrapper failure")
    end, 100)
    resolves, calls = g.resolves, e.seen.calls
    observe(after and "error after next" or "error before next", 4)
    T.eq(g.resolves, resolves + 1, "wrapper failure resolves native exactly once")
    T.eq(e.seen.calls, calls + 1, "wrapper failure traverses consumer once")
    off()
  end
  local original = g._resolveLogicSpeed
  local attempts = 0
  g._resolveLogicSpeed = function()
    attempts = attempts + 1
    error("native speed resolver failure")
  end
  T.raises(function()
    g:logicSpeed()
  end, "native speed resolver failure", "native errors escape")
  T.eq(attempts, 1, "native error is not retried")
  g._resolveLogicSpeed = original
  if f.api >= 3 then
    off = api.hooks:wrap("core.logic_speed", function(next)
      next()
      return next()
    end, 100)
    resolves = g.resolves
    observe("API-3 cached continuation", 4)
    T.eq(g.resolves, resolves + 1, "API-3 repeated next caches native result")
    off()
  end
  -- Gen1's GBA boot phases are a separate native restriction. Gen2's
  -- titles/attract screens retain their own timing; do not invent that host.
  if f.backend == "gen1" and f.generation == 3 then
    local Boot = require("src.ui.game3.boot")
    g.phase = "boot"
    calls = e.seen.calls
    for _, phase in ipairs({
      Boot.PHASE.INTRO,
      Boot.PHASE.TITLE,
      Boot.PHASE.TITLE_CRY,
      Boot.PHASE.TITLE_RESTART,
    }) do
      g.boot = { phase = phase }
      T.eq(g:logicSpeed(), 1, "Gen1 GBA boot cinematic lock")
      T.eq(e.seen.calls, calls, "Gen1 GBA boot bypasses hook")
    end
    g.speedOverride = 20
    T.eq(g:logicSpeed(), 20, "Gen1 GBA explicit override retains boot precedence")
    g.speedOverride, g.phase = nil, "field"
  end
  e.stop()
  e.stop()
  calls = e.seen.calls
  observe("unsubscribed native fallback", 4)
  T.eq(e.seen.calls, calls, "unsubscribe is idempotent")
  -- The actual unwrapped resolver and launch override keep host-native
  -- levels too. The shared contract does not add a 3X rung to Gen2.
  for key in pairs(g.save.options) do
    g.save.options[key] = 3
  end
  T.eq(g:logicSpeed(), f.backend == "gen1" and 3 or 2, "unsubscribed native ladder")
  g.speedOverride = 3
  T.eq(g:logicSpeed(), f.backend == "gen1" and 3 or 2, "explicit native ladder")
  g.speedOverride = nil
  for key in pairs(g.save.options) do
    g.save.options[key] = 4
  end
  local peerCalls = 0
  api.hooks:wrap("core.logic_speed", function()
    return 200
  end, 100)
  local peer = f.result.loader.hooks:wrap("core.logic_speed", function(next, ...)
    peerCalls = peerCalls + 1
    return next(...)
  end, 10, "other_speed_owner")
  f.result.loader.hooks:removeOwner("portable_logic_speed")
  observe("owner cleanup restores native option", 4)
  T.eq(peerCalls, 1, "owner cleanup preserves peer wrapper")
  peer()
  return rows
end
return M
