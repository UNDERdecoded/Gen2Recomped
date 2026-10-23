local M = {}
local function pack(...)
  return { n = select("#", ...), ... }
end
function M.run(f)
  local T, g, e, api = f.T, f.game, f.exports, f.public
  local rows = {}
  local function state(label)
    rows[#rows + 1] = { label = label, updates = g.calls, polls = e.polls(), hostPolls = f.hostPolls() }
  end
  for _, dt in ipairs({ 0, 1 / 60, 0.25, 2.5 }) do
    local n, polls = g.calls, e.polls()
    f.update(dt)
    T.eq(g.calls, n + 1, "interactive frame forwards exactly one native update")
    T.eq(e.polls(), polls + 1, "interactive frame invokes wrapper once")
    T.eq(e.seen.game, g, "original Game identity")
    T.eq(e.seen.dt, dt, "unmodified frame delta")
    T.eq(g.dts[#g.dts], dt, "native update receives frame delta")
  end
  state("forwarded")
  e.pause(true)
  local n, polls, host = g.calls, e.polls(), f.hostPolls()
  f.update(1 / 60)
  f.update(1 / 30)
  T.eq(g.calls, n, "pause suppresses Game:update")
  T.eq(e.polls(), polls + 2, "mod continues polling while simulation paused")
  T.eq(f.hostPolls(), host + 2, "host housekeeping continues while paused")
  state("paused")
  e.pause(false)
  f.update(1 / 60)
  T.eq(g.calls, n + 1, "resume forwards exactly one update")
  state("resumed")
  if api.supports then
    T.eq(api:supports("hooks", "core.update"), true, "native capability advertised")
  end
  -- next() forwards current args; explicit args route to another Game/delta.
  local alternate = { calls = 0 }
  function alternate:update(dt)
    self.calls = self.calls + 1
    self.dt = dt
  end
  local order = {}
  local outer = api.hooks:wrap("core.update", function(next, game, dt)
    T.eq(game, g, "outer sees original Game")
    order[#order + 1] = "outer"
    next(alternate, dt / 2)
    order[#order + 1] = "after"
    return nil, "wrapped", nil
  end, 20)
  local inner = api.hooks:wrap("core.update", function(next, game, dt)
    order[#order + 1] = "inner"
    T.eq(game, alternate, "rewritten Game reaches downstream wrapper")
    T.eq(dt, 0.125, "rewritten delta reaches downstream wrapper")
    return next()
  end, 10)
  n = g.calls
  T.same(pack(f.bridge.update(g, 0.25)), { n = 3, [2] = "wrapped" }, "wrapper nil-hole results preserved")
  T.same(order, { "outer", "inner", "after" }, "descending priority and postprocessing")
  T.eq(alternate.calls, 1, "native fallback uses replacement Game")
  T.eq(alternate.dt, 0.125, "native fallback uses replacement delta")
  T.eq(g.calls, n, "original Game not updated after explicit replacement")
  outer()
  inner()
  T.same(pack(f.bridge.update(g, 1 / 60)), { n = 0 }, "native Game:update results deliberately discarded")
  for _, after in ipairs({ false, true }) do
    local off = api.hooks:wrap("core.update", function(next)
      if after then
        next()
      end
      error("intentional core.update wrapper failure")
    end, 100)
    n = g.calls
    f.update(1 / 60)
    T.eq(g.calls, n + 1, "wrapper error preserves one native update")
    off()
  end
  local original = g.update
  local attempts = 0
  g.update = function()
    attempts = attempts + 1
    error("native update failure")
  end
  T.raises(function()
    f.update(1 / 60)
  end, "native update failure", "native failure escapes")
  T.eq(attempts, 1, "native failure is not retried")
  g.update = original
  if f.api >= 3 then
    local off = api.hooks:wrap("core.update", function(next)
      next()
      return next()
    end, 100)
    n = g.calls
    f.update(1 / 60)
    T.eq(g.calls, n + 1, "unified API-3 continuation caches downstream result")
    off()
  end
  -- Real love.update routing: non-game owners bypass the seam.
  for _, mode in ipairs({ "Importer", "TouchEditor", "editorMode", "noGame" }) do
    local owner = { calls = 0 }
    if mode == "Importer" then
      function owner:update()
        self.calls = self.calls + 1
      end
      f.set("Importer", owner)
    elseif mode == "TouchEditor" then
      owner.update = function()
        owner.calls = owner.calls + 1
      end
      f.set("TouchEditor", owner)
    elseif mode == "editorMode" then
      owner.update = function()
        owner.calls = owner.calls + 1
      end
      f.set("EditorApp", owner)
      f.set("editorMode", true)
    else
      f.set("Game", nil)
    end
    polls, n = e.polls(), g.calls
    f.update(1 / 60)
    T.eq(e.polls(), polls, mode .. " does not fire mod frame hook")
    T.eq(g.calls, n, mode .. " does not update game")
    if mode ~= "noGame" then
      T.eq(owner.calls, 1, mode .. " native owner still updates")
    end
    if mode == "editorMode" then
      f.set("editorMode", false)
      f.set("EditorApp", nil)
    elseif mode == "noGame" then
      f.set("Game", g)
    else
      f.set(mode, nil)
    end
  end
  state("non-game-routing")
  -- Scripted act+step loops remain deterministic and bypass core.update.
  f.set("speedOverride", 2)
  local acts = 0
  f.set("autopilot", {
    update = function()
      acts = acts + 1
    end,
  })
  polls, n = e.polls(), g.calls
  f.update(0.9)
  T.eq(acts, 2, "autopilot observes each deterministic step")
  T.eq(g.calls, n + 2, "autopilot runs both deterministic updates")
  T.eq(g.dts[#g.dts], 1 / 60, "autopilot retains fixed delta")
  T.eq(e.polls(), polls, "autopilot bypasses frame hook")
  f.set("autopilot", nil)
  acts = 0
  f.set(
    "driverCo",
    coroutine.create(function()
      while true do
        acts = acts + 1
        coroutine.yield()
      end
    end)
  )
  polls, n = e.polls(), g.calls
  f.update(0.9)
  T.eq(acts, 2, "driver observes each deterministic step")
  T.eq(g.calls, n + 2, "driver runs both deterministic updates")
  T.eq(g.dts[#g.dts], 1 / 60, "driver retains fixed delta")
  T.eq(e.polls(), polls, "driver bypasses frame hook")
  f.set("driverCo", nil)
  f.set("speedOverride", nil)
  state("scripted-routing")
  e.stop()
  e.stop()
  polls, n = e.polls(), g.calls
  f.update(1 / 60)
  T.eq(e.polls(), polls, "unsubscribe is idempotent")
  T.eq(g.calls, n + 1, "empty chain still forwards native update")
  state("unsubscribed")
  return rows
end
return M
