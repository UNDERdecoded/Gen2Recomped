local M = {}
function M.run(f)
  local T, e, api = f.T, f.exports, f.public
  local rows = {}
  local function observe(label, claimed)
    e.claim(claimed and f.npc.id or nil)
    local before, eventCount = #f.calls, #f.events
    f.interact()
    local native = #f.calls - before
    T.eq(native, claimed and 0 or 1, label .. " native continuation count")
    T.eq(#f.events - eventCount, 1, label .. " native interaction event remains")
    local event = f.events[#f.events]
    T.eq(event.target, f.npc, label .. " event keeps resolved original actor")
    T.eq(event.kind, "npc", label .. " event keeps NPC kind")
    T.eq(event.mapId, "FIX_ROUTE", label .. " event keeps native map")
    T.eq(e.seen.owner, f.owner, label .. " opaque native owner")
    T.eq(e.seen.target, f.npc, label .. " original actor identity")
    T.eq(e.seen.extra, 0, label .. " no extra arguments")
    rows[#rows + 1] = { label = label, native = native }
  end
  if api.supports then
    T.eq(api:supports("hooks", "world.talk"), true, "capability at mod entry")
  end
  observe("unclaimed", false)
  observe("claimed", true)
  T.eq(e.seen.claimed, 1, "same consumer can answer its NPC")
  f.counter(true)
  observe("counter claimed", true)
  observe("counter default", false)
  f.counter(false)
  f.npc.def.runtime = true
  observe("runtime claimed", true)
  observe("runtime default", false)
  f.npc.def.runtime = nil
  -- Returning false does not mean fall through: calling next controls dispatch.
  local off = api.hooks:wrap("world.talk", function()
    return false
  end, 100)
  local before = #f.calls
  f.interact()
  T.eq(#f.calls, before, "false without next claims the interaction")
  off()
  local order = {}
  local outer = api.hooks:wrap("world.talk", function(next)
    order[#order + 1] = "outer"
    local value = next()
    order[#order + 1] = "after"
    return value
  end, 20)
  local inner = api.hooks:wrap("world.talk", function(next, owner, target)
    order[#order + 1] = "inner"
    T.eq(owner, f.owner, "next() retains owner")
    T.eq(target, f.npc, "next() retains actor")
    return next()
  end, 10)
  before = #f.calls
  f.interact()
  T.eq(#f.calls, before + 1, "chained next reaches native once")
  T.same(order, { "outer", "inner", "after" }, "descending priority")
  outer()
  inner()
  for _, after in ipairs({ false, true }) do
    off = api.hooks:wrap("world.talk", function(next)
      if after then
        next()
      end
      error("intentional talk hook failure")
    end, 100)
    before = #f.calls
    f.interact()
    T.eq(#f.calls, before + 1, "failure before/after next does not duplicate native talk")
    off()
  end
  local replacement = { id = "REPLACEMENT" }
  off = api.hooks:wrap("world.talk", function(next, owner)
    return next(owner, replacement)
  end, 100)
  f.interact()
  T.eq(e.seen.target, replacement, "explicit next arguments reach downstream opaque")
  off()
  if f.api >= 3 then
    local savedNext
    off = api.hooks:wrap("world.talk", function(next)
      savedNext = next
      local value = next()
      T.eq(next(), value, "API 3 repeated continuation retains result")
      return value
    end, 100)
    before = #f.calls
    f.interact()
    T.eq(#f.calls, before + 1, "API 3 next is cached")
    T.eq(pcall(savedNext), f.backend == "gen1", "native continuation lifetime boundary")
    T.eq(#f.calls, before + 1, "late continuation never repeats native talk")
    off()
  end
  observe("restored", false)
  e.stop()
  e.stop()
  local polls = e.seen.calls
  before = #f.calls
  f.interact()
  T.eq(#f.calls, before + 1, "unsubscribe restores native route")
  T.eq(e.seen.calls, polls, "unsubscribe idempotent")
  api.hooks:wrap("world.talk", function() end)
  local peerCalls = 0
  local peer = f.result.loader.hooks:wrap("world.talk", function(next, ...)
    peerCalls = peerCalls + 1
    return next(...)
  end, 10, "other_talk_owner")
  f.result.loader.hooks:removeOwner("portable_world_talk")
  before = #f.calls
  f.interact()
  T.eq(#f.calls, before + 1, "owner cleanup restores native talk")
  T.eq(peerCalls, 1, "another owner's callback survives cleanup")
  peer()
  return rows
end
return M
