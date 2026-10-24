local M = {}
function M.run(f)
  local T, rows = f.T, {}
  local function fresh(name)
    local b = f.fresh(name, { enemy = true })
    b.move.pp = 2
    if f.backend == "gen1" then
      f.game.save.party = b.battle.party
      f.game.stack.states = { { screenId = "Gen2BattleState", battle = b.battle, phase = "menu" } }
    else
      b.battle.phase, b.battle.queue = "menu", {}
      f.game.stack.states = { b.battle }
    end
    return b
  end
  local function observe(label, b)
    local view = assert(f.e.read())
    T.eq(view.moves[1].id, f.ids.TACKLE, "public snapshot has canonical enemy move")
    T.eq(view.moves[1].pp, b.pp(), "same public consumer observes current native enemy PP")
    rows[#rows + 1] = { label = label, pp = view.moves[1].pp }
  end
  local function choose(b)
    if f.backend == "gen1" then
      return b.battle:enemyMove()
    end
    return b.battle:enemyAction().id
  end
  local b = fresh("TACKLE")
  observe("initial", b)
  for remaining = 1, 0, -1 do
    T.eq(choose(b), f.ids.TACKLE, "native AI selects remaining usable move")
    b.use()
    T.eq(b.pp(), remaining, "ordinary enemy move spends one PP")
    observe("remaining:" .. remaining, b)
  end
  local dry = choose(b)
  T.eq(dry == nil or dry == "STRUGGLE", true, "native enemy selection reaches depleted fallback")
  -- Run the actual full-turn substitution in Gold and the actual chosen action
  -- in the host. Neither PP accounting nor fallback execution is mocked.
  f.data.moves.STRUGGLE = {
    id = "STRUGGLE",
    name = "STRUGGLE",
    index = 165,
    type = "NORMAL",
    power = 50,
    accuracy = 100,
    accuracyRaw = 255,
    pp = 1,
    effect = f.backend == "gen1" and "EFFECT_RECOIL_HIT" or "RECOIL_EFFECT",
  }
  local hp = b.hp()
  if f.backend == "gen1" then
    b.battle:takeTurn({ kind = "skip" })
    T.eq(b.user.volatile.lastMove, "STRUGGLE", "native full turn executes Struggle")
  else
    local move = b.battle:enemyAction()
    b.battle:performMove(b.user, b.target, move)
    T.eq(move.struggle, true, "native AI produced Struggle action")
  end
  T.check(b.hp() < hp, "depleted enemy still deals native Struggle damage")
  T.eq(b.pp(), 0, "Struggle leaves depleted slot at zero")
  observe("struggle", b)
  T.check(f.e.read().choices >= 3, "public forwarding hook observed ordinary native AI choices")
  f.e.stop()
  local before = f.e.read().choices
  choose(b)
  T.eq(f.e.read().choices, before, "unsubscribe restores native choice without callback")
  rows[#rows + 1] = { label = "unsubscribe", pp = b.pp() }
  b = fresh("FLY")
  b.move.pp = 1
  b.use()
  T.eq(b.pp(), 0, "enemy charge spends its final PP")
  T.eq(b.charging(), true, "zero PP does not erase charged continuation")
  T.eq(choose(b), f.ids.FLY, "native AI retains stored release at zero PP")
  if f.backend == "gen2" then
    b.user.chargeReady = true
  end
  local hp = b.hp()
  b.use()
  T.eq(b.pp(), 0, "release spends no additional PP")
  T.eq(b.charging(), false, "release clears stored continuation")
  T.check(b.hp() < hp, "last-PP release executes native damage")
  rows[#rows + 1] = { label = "last PP release", pp = b.pp(), charging = b.charging() }
  b = fresh("FLY")
  b.move.pp = 1
  b.use(true)
  T.eq(b.pp(), 1, "called enemy move retains caller-owned PP")
  rows[#rows + 1] = { label = "called", pp = b.pp() }
  b = fresh("TACKLE")
  local alternate = { id = f.ids.FLY, pp = 0 }
  if f.backend == "gen1" then
    b.user.moves[2] = alternate
  else
    b.user.curMoves[2], b.user.mon.moves[2] = alternate, alternate
  end
  T.eq(choose(b), f.ids.TACKLE, "native AI skips depleted alternate slot")
  if f.backend == "gen1" then
    b.user.volatile.disabled = f.ids.TACKLE
  else
    b.user.disabledSlot = 1
  end
  local disabled = choose(b)
  T.eq(
    disabled == nil or disabled == "STRUGGLE",
    true,
    "disabled usable move plus dry alternate reaches fallback"
  )
  rows[#rows + 1] = { label = "disabled", pp = b.pp(), fallback = disabled == nil or disabled == "STRUGGLE" }
  return rows
end
return M
