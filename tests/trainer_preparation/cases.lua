local M = {}
function M.run(new)
  local rows, T = {}, nil
  for _, mode in ipairs({
    "no-mod",
    "observe",
    "false",
    "truthy",
    "nil",
    "defer",
    "cancel",
    "immediate",
    "error",
    "after error",
    "unsubscribe",
    "owner cleanup",
    "rollback",
    "invalid scope",
  }) do
    local f = new(mode == "no-mod", mode == "rollback")
    T = f.T
    local e, original = f.exports, f.game.save.party
    local members = { original[1], original[2], original[3] }
    if e then
      e.mode = (mode == "cancel" or mode == "invalid scope") and "defer" or mode
      e.options = { playerPartyIndices = { 3, 2 } }
      if mode == "unsubscribe" then
        e.stop()
        e.stop()
      end
      if mode == "owner cleanup" then
        f.result.loader.hooks:removeOwner("portable_trainer_preparation")
      end
    end
    local off
    if e and (mode == "truthy" or mode == "nil") then
      local api = e.api
      off = api.hooks:wrap("trainer.before_battle", function()
        if mode == "truthy" then
          return 1
        end
      end, 100)
    end
    f.start()
    local selected = mode == "defer" or mode == "immediate"
    if mode == "defer" or mode == "cancel" or mode == "invalid scope" then
      T.eq(f.starts(), 0, mode .. " constructs no battle before decision")
      T.eq(e.calls, 1, mode .. " native hook fires once")
      T.eq(type(e.context), "table", "data-only trainer context")
      T.eq(e.context.partyIndex, 1, "native party index")
      T.eq(e.extra, 0, "native hook arity")
      if f.backend == "gen2" or f.api < 3 then
        T.eq(e.game, f.game, "opaque original Game")
      else
        T.eq(e.game.sessionStartedAt, 1, "Gen1 API3 Game context boundary")
      end
      local options = mode == "cancel" and { cancel = true }
        or { playerPartyIndices = mode == "invalid scope" and { 1, 1 } or { 3, 2 } }
      T.eq(e.continue(options), true, "retained native continuation accepted")
      T.eq(e.continue(), false, "retained native continuation one-shot")
    end
    local cancelled = mode == "cancel"
    T.eq(f.starts(), cancelled and 0 or 1, mode .. " starts exactly once or cancels")
    T.eq(f.cancels(), cancelled and 1 or 0, mode .. " cancellation callback")
    T.eq(f.game.save.party, original, "save party table is never swapped")
    T.same(f.game.save.party, members, "save party order and references unchanged")
    for i, mon in ipairs(members) do
      T.eq(f.game.save.party[i], mon, "save mon identity retained")
    end
    if not cancelled then
      local party = assert(f.party(), "real native battle party")
      T.eq(#party, selected and 2 or 3, mode .. " native battle party size")
      T.eq(party[1].nickname, selected and "THREE" or "ONE", mode .. " native lead/order")
      if selected then
        T.eq(party[2].nickname, "TWO", "second selected member")
      end
    end
    rows[#rows + 1] =
      { mode = mode, starts = f.starts(), cancels = f.cancels(), size = f.party() and #f.party() or 0 }
    if off then
      off()
    end
    f.close()
  end
  return rows, T
end
return M
