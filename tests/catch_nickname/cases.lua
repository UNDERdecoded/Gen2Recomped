local C = {}

function C.run(f)
  local T, e, rows = f.T, assert(f.exports), {}
  local cases = {
    { name = "forward", value = "forward", ask = true },
    { name = "skip", value = false, ask = false },
    { name = "supplied", value = "SCOUT", ask = false, nickname = "SCOUT" },
    { name = "ten bytes", value = "PORTABLE11EXTRA", ask = false, nickname = "PORTABLE11" },
    { name = "UTF8 within limit", value = "Café", ask = false, nickname = "Café" },
    { name = "empty", value = "", ask = false },
    { name = "true", value = true, ask = true },
    { name = "nil", ask = true },
    { name = "zero", value = 0, ask = true },
    { name = "table", value = {}, ask = true },
    { name = "error", value = "error", ask = true },
  }
  for _, destination in ipairs({ "party", "box" }) do
    for _, case in ipairs(cases) do
      e.set(case.value)
      local before = e.calls()
      local r = f.capture(destination)
      T.eq(e.calls(), before + 1, case.name .. " dispatches once for " .. destination)
      T.eq(r.stored, r.caught, "native recipient retains caught-mon identity")
      T.eq(r.caught.nickname, case.nickname, case.name .. " reaches stored nickname")
      T.eq(#r.ui, case.ask and 1 or 0, case.name .. " controls actual nickname UI queue")
      T.eq(r.event.mon, r.caught, "caught event retains native mon")
      T.eq(r.event.destination, destination, "native placement remains unchanged")
      T.eq(r.eventNickname, case.nickname, "caught event sees supplied name before UI")
      T.eq(r.battle.result, "caught", "catch result remains native")
      T.eq(r.battle.afterQueue, "finish", "catch queue still finishes")
      T.eq(r.save.pokedex.owned.FIXMON_B, true, "nickname decision retains dex ownership")
      local last = e.last()
      T.check(last ~= nil, "native catch dispatched the consumer arguments")
      if last then
        T.eq(last.mon.species, "FIXMON_B", "callback receives caught species")
        T.eq(last.context.name, f.data.pokemon.FIXMON_B.name, "callback receives display name")
        T.check(last.context.battle and last.context.game, "callback receives battle/game context")
      end
      rows[#rows + 1] = {
        name = case.name,
        destination = destination,
        nickname = r.caught.nickname or false,
        asked = #r.ui == 1,
        eventNickname = r.eventNickname or false,
        result = r.battle.result,
      }
    end
  end

  e.set("SCOUT")
  local before = e.calls()
  local full = f.capture("full")
  T.eq(e.calls(), before, "full storage never dispatches nickname decision")
  T.eq(full.caught.nickname, nil, "failed placement does not rename the mon")
  T.eq(#full.ui, 0, "full storage queues no nickname UI")
  local new = f.capture("party", true)
  T.eq(#new.ui, 1, "supplied nickname retains separate new-species dex page")
  T.eq(new.event.isNew, true, "new-species caught event remains native")

  local b = f.fresh("party")
  T.check(type(b.offerNickname) == "function", "native battle exposes offerNickname")
  if type(b.offerNickname) ~= "function" then
    return rows
  end
  b.enemy.mon.nickname = "KEEP"
  e.set("")
  T.eq(b:offerNickname(b.enemy.mon, b.enemy.name), false, "empty string bypasses question")
  T.eq(b.enemy.mon.nickname, "KEEP", "empty string preserves an existing name")

  e.set("forward")
  local queued = f.capture("party")
  local original = queued.caught
  queued.battle.enemy = { mon = {}, name = "CHANGED" }
  local box = queued.ui[1]()
  T.check(type(box.choice) == "function", "native AskName factory retains YES/NO callback")
  box.choice(true)
  local naming = queued.pushed[#queued.pushed]
  T.check(naming and type(naming.onDone) == "function", "native YES reaches naming screen")
  if naming and naming.onDone then
    naming.onDone("USER")
  end
  T.eq(original.nickname, "USER", "deferred native naming still updates original recipient")
  T.eq(queued.battle.enemy.mon.nickname, nil, "deferred naming never targets replacement enemy")

  e.off()
  before = e.calls()
  local native = f.capture("party")
  T.eq(#native.ui, 1, "unsubscribe restores actual native prompt")
  T.eq(e.calls(), before, "unsubscribed decision is never invoked")
  return rows
end

return C
