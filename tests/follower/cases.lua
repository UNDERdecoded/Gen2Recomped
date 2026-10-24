local M = {}
function M.run(f)
  local T, state, rows = f.T, f.e.state, {}
  local function observe(label)
    local n = f.current()
    rows[#rows + 1] = { label = label, present = n ~= nil }
  end
  f.tick()
  T.eq(f.current() ~= nil, f.version == "yellow", "native default remains Yellow-only")
  observe("native")
  state.mode = "deny"
  f.tick()
  T.eq(f.current(), nil, "public predicate removes companion")
  state.mode = "allow"
  f.tick()
  local npc = f.current()
  T.check(npc ~= nil, "public predicate spawns actual native companion")
  T.eq(npc.passable, true, "native follower never blocks player")
  T.eq(state.game, f.game, "hook receives original opaque Game")
  T.eq(state.world.player, f.player, "hook receives native player")
  T.eq(state.world.map.id, f.world.map.id, "hook receives active map")
  if not (f.backend == "gen1" and f.gen == 3) then
    T.eq(state.world, f.world, "opaque world identity is preserved")
    T.eq(f.world.npcs[#f.world.npcs], npc, "native update list owns follower")
    T.eq(f.world.entities[#f.world.entities], npc, "native draw list owns follower")
  end
  observe("allow")
  -- A moving player commits before the NPC controller. Check each native
  -- interpolated frame, not a hand-called Runtime hook or a fake follower.
  for _, dir in ipairs({ { "right", 1, 0 }, { "down", 0, 1 }, { "left", -1, 0 }, { "up", 0, -1 } }) do
    local p = f.player
    p.facing, p.targetX, p.targetY, p.moving = dir[1], p.cellX + dir[2], p.cellY + dir[3], true
    for frame = 1, 4 do
      f.tick()
      npc = f.current()
      T.check(npc ~= nil, "native companion survives movement")
      rows[#rows + 1] = { dir = dir[1], frame = frame, x = npc.px, y = npc.py, moving = npc.moving == true }
    end
    p.cellX, p.cellY, p.px, p.py = p.targetX, p.targetY, p.targetX * 16, p.targetY * 16
    p.targetX, p.targetY, p.moving = nil, nil, false
  end
  state.mode = "deny"
  f.tick()
  T.eq(f.current(), nil, "denial removes follower during native update")
  if not (f.backend == "gen1" and f.gen == 3) then
    T.eq(#f.world.npcs, 0, "removal clears update list")
    T.eq(#f.world.entities, 1, "removal retains player draw entry")
  end
  observe("deny")
  state.mode = "allow"
  f.enter()
  T.check(f.current() ~= nil, "native map entry honors predicate")
  observe("map entry")
  if f.gen <= 2 then
    local keep = f.current()
    local x, y = keep.px, keep.py
    f.enter({ keepPikachu = keep })
    T.eq(f.current(), keep, "native connection keeps companion identity")
    f.controller.rebase(f.world, -2, 1)
    T.eq(keep.px, x - 32, "native connection rebases companion x")
    T.eq(keep.py, y + 16, "native connection rebases companion y")
    rows[#rows + 1] = { label = "connection", dx = keep.px - x, dy = keep.py - y }
  elseif f.gen == 3 then
    f.player.cellX, f.player.cellY, f.player.px, f.player.py = 20, 20, 320, 320
    f.tick()
    T.eq(f.current().cellX, 20, "GBA same-map teleport resets companion x")
    T.eq(f.current().cellY, 20, "GBA same-map teleport resets companion y")
    rows[#rows + 1] = { label = "teleport", x = f.current().px, y = f.current().py }
  end
  local off = f.e.api.hooks:wrap("world.follower.spawn", function()
    return false
  end, 100)
  f.tick()
  T.eq(f.current(), nil, "higher-priority wrapper controls native lifecycle")
  off()
  f.tick()
  T.check(f.current() ~= nil, "unsubscribe restores consumer")
  f.e.stop()
  f.e.stop()
  f.tick()
  T.eq(f.current() ~= nil, f.version == "yellow", "unsubscribe restores native predicate")
  observe("unsubscribed")
  for _, value in ipairs({ false, true, 0, "", {} }) do
    local restore = f.e.api.hooks:wrap("world.follower.spawn", function()
      return value
    end, 100)
    f.tick()
    T.eq(f.current() ~= nil, not not value, "native predicate uses Lua truthiness")
    observe("truthiness:" .. type(value) .. ":" .. tostring(not not value))
    restore()
  end
  local nilResult = f.e.api.hooks:wrap("world.follower.spawn", function()
    return nil
  end, 100)
  f.tick()
  T.eq(f.current(), nil, "nil predicate result removes follower")
  observe("nil")
  nilResult()
  for _, after in ipairs({ false, true }) do
    local failing = f.e.api.hooks:wrap("world.follower.spawn", function(next, game, world)
      if after then
        next(game, world)
      end
      error("intentional wrapper failure")
    end, 100)
    f.tick()
    T.eq(f.current() ~= nil, f.version == "yellow", "wrapper failure preserves downstream native default")
    observe("failure:" .. tostring(after))
    failing()
  end
  if f.api >= 3 then
    local calls = 0
    local count = f.e.api.hooks:wrap("world.follower.spawn", function()
      calls = calls + 1
      return true
    end, 50)
    local replay = f.e.api.hooks:wrap("world.follower.spawn", function(next, game, world)
      local before = calls
      local a, b = next(game, world), next(game, world)
      T.eq(a, true, "first next returns downstream predicate")
      T.eq(b, a, "API-3 repeated next preserves result")
      T.eq(calls, before + 1, "API-3 repeated next calls downstream once")
      return a
    end, 100)
    f.tick()
    T.check(f.current() ~= nil, "replayed next still drives native spawning")
    replay()
    count()
    observe("replay")
  end
  return rows
end
return M
