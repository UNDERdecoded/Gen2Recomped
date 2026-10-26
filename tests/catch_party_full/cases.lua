local C = {}
function C.run(f)
  local T, e, rows = f.T, assert(f.exports), {}
  local cases = {
    { name = "forward", value = "forward", claim = false },
    { name = "false", value = false, claim = false },
    { name = "nil", claim = false },
    { name = "true", value = true, claim = true },
    { name = "zero", value = 0, claim = true },
    { name = "empty string", value = "", claim = true },
    { name = "string", value = "custody", claim = true },
    { name = "table", value = {}, claim = true },
    { name = "error", value = "error", claim = false },
  }
  for _, destination in ipairs({ "party", "box", "full" }) do
    for _, c in ipairs(cases) do
      e.set(c.value)
      local before, held = e.calls(), #e.custody
      local r = f.capture(destination)
      local dispatched = destination ~= "party"
      local claimed = dispatched and c.claim
      local expected = destination == "party" and "party" or claimed and "mod" or "box"
      local placed = destination == "party" or destination == "box" and not claimed
      T.eq(e.calls(), before + (dispatched and 1 or 0), c.name .. " full-party-only dispatch")
      T.eq(#e.custody, held + (claimed and 1 or 0), c.name .. " consumer custody")
      T.eq(r.event.destination, expected, c.name .. " caught destination")
      T.eq(r.event.mon, r.caught, "native caught event retains original mon")
      T.eq(r.occurrences, placed and 1 or 0, "exactly one native recipient or mod custody")
      if placed then
        T.eq(r.stored, r.caught, "native party/PC placement retains original mon")
      end
      T.eq(#r.ui, placed and 1 or 0, "only native placement queues nickname UI")
      T.eq(r.save.pokedex.owned.FIXMON_B, true, "caught dex ownership retained")
      T.eq(r.battle.result, "caught", "native catch result retained")
      T.eq(r.battle.afterQueue, "finish", "native catch still finishes")
      local fullMessage, transferMessage = false, false
      for _, item in ipairs(r.battle.queue) do
        local text = item.text or ""
        if text:find("every BOX", 1, true) then
          fullMessage = true
        end
        if text:find("transferred", 1, true) then
          transferMessage = true
        end
      end
      T.eq(
        fullMessage,
        destination == "full" and not claimed,
        "full-PC fallback message only without custody"
      )
      T.eq(transferMessage, destination == "box" and not claimed, "PC transfer text only for native deposit")
      if dispatched then
        local last = e.last()
        T.check(last and last.mon, "consumer receives caught context")
        if last and last.mon then
          T.eq(last.mon.species, "FIXMON_B", "consumer caught species")
          T.eq(last.name, f.data.pokemon.FIXMON_B.name, "consumer caught display name")
          T.check(last.battle and last.game, "consumer battle and game context")
        end
      end
      rows[#rows + 1] = {
        case = c.name,
        storage = destination,
        destination = r.event.destination,
        claimed = claimed,
        occurrences = r.occurrences,
        asksNickname = #r.ui == 1,
        calls = e.calls() - before,
        custody = #e.custody - held,
        result = r.battle.result,
      }
    end
  end
  e.set(true)
  local new = f.capture("box", true)
  T.eq(#new.ui, 1, "mod custody preserves separate new-species dex page")
  T.eq(new.event.isNew, true, "mod custody retains new-species event")
  T.eq(new.event.destination, "mod", "new-species mod destination")
  e.off()
  local before = e.calls()
  local normal = f.capture("box")
  T.eq(e.calls(), before, "unsubscribe removes consumer")
  T.eq(normal.event.destination, "box", "unsubscribe restores PC fallback")
  T.eq(normal.stored, normal.caught, "unsubscribe restores native PC recipient")
  return rows
end
return C
