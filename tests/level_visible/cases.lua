local M = {}
function M.run(f)
  local T, e, mon = f.T, f.exports, f.mon
  local api, rows = e.api, {}
  if api.supports then
    T.eq(api:supports("hooks", "pokemon.level_visible"), true, "native capability")
  end
  for _, where in ipairs({ "battle.enemy", "battle.player", "party", "summary" }) do
    local function observe(label, value)
      T.eq(f.visible(where), value, where .. " " .. label)
      rows[#rows + 1] = { where = where, label = label, visible = value }
    end
    observe("native", true)
    T.eq(e.seen.context.where, where, "surface context")
    T.eq(e.seen.mon.level, 42, "level in every callback format")
    if f.api < 3 and f.format ~= "unified" then
      T.eq(e.seen.mon, mon, "native mon identity")
      T.eq(e.seen.context.game, f.game, "native Game identity")
    else
      T.eq(e.seen.mon.species, "FIXMON_A", "normalized species")
      T.check(e.seen.mon ~= mon, "unified mon record")
    end
    e.hide(where, true)
    observe("hidden", false)
    local other = where == "party" and "summary" or "party"
    T.eq(f.visible(other), true, "per-surface decision")
    e.hide(where, false)
    observe("restored", true)
  end
  for _, case in ipairs({
    { name = "nil" },
    { name = "true", value = true },
    { name = "zero", value = 0 },
    { name = "string", value = "" },
    { name = "table", value = {} },
  }) do
    local off = api.hooks:wrap("pokemon.level_visible", function()
      return case.value
    end, 100)
    T.eq(f.visible("party"), true, case.name .. " remains visible")
    off()
  end
  local off = api.hooks:wrap("pokemon.level_visible", function()
    return false, true
  end, 100)
  T.eq(f.visible("party"), false, "only first return controls visibility")
  off()
  local order = {}
  local outer = api.hooks:wrap("pokemon.level_visible", function(next, m, ctx)
    order[#order + 1] = "outer"
    T.eq(ctx.where, "party", "outer context")
    local result = next(m, ctx)
    order[#order + 1] = "after"
    return result
  end, 20)
  local inner = api.hooks:wrap("pokemon.level_visible", function(next)
    order[#order + 1] = "inner"
    return next()
  end, 10)
  T.eq(f.visible("party"), true, "next() retains arguments")
  T.same(order, { "outer", "inner", "after" }, "priority and delegation")
  outer()
  inner()
  e.hide("party", true)
  for _, after in ipairs({ false, true }) do
    off = api.hooks:wrap("pokemon.level_visible", function(next)
      if after then
        next()
      end
      error("intentional level predicate failure")
    end, 100)
    T.eq(f.visible("party"), false, "error preserves downstream false")
    off()
  end
  if f.api >= 3 then
    off = api.hooks:wrap("pokemon.level_visible", function(next)
      next()
      return next()
    end, 100)
    local calls = e.seen.calls
    T.eq(f.visible("party"), false, "API 3 caches false")
    T.eq(e.seen.calls, calls + 1, "API 3 does not replay downstream")
    off()
  end
  e.stop()
  e.stop()
  local calls = e.seen.calls
  T.eq(f.visible("party"), true, "unsubscribe restores default")
  T.eq(e.seen.calls, calls, "idempotent unsubscribe")
  api.hooks:wrap("pokemon.level_visible", function()
    return false
  end)
  local peerCalls = 0
  local peer = f.result.loader.hooks:wrap("pokemon.level_visible", function(next, ...)
    peerCalls = peerCalls + 1
    return next(...)
  end, 10, "level_peer")
  f.result.loader.hooks:removeOwner("portable_level_visible")
  T.eq(f.visible("party"), true, "owner cleanup restores default")
  T.eq(peerCalls, 1, "owner cleanup preserves peer")
  peer()
  return rows
end
return M
