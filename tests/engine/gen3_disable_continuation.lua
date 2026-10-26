package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
local V, D = require("src.core.GameVersion"), require("src.battle.Gen3Disable")
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.disable").fixture(".", "gen2", version)
  T.link.prepare(f.data)
  local game = T.link.fakeGame(f.data, "CHARMANDER", { name = "PLAYER", level = 30 })
  game.stack.states, f.result.loader.game = game.stack.list, game
  game.save.options.ruleset = "gen3_emerald"
  local mon = game.save.party[1]
  mon.nickname, mon.moves =
    "PLAYER", {
      { id = f.ids.TACKLE, pp = 10 },
      { id = f.ids.DISABLE, pp = 10 },
      { id = f.ids.TACKLE, pp = 10 },
      { id = f.ids.SCRATCH, pp = 10 },
    }
  mon.hp, mon.stats.hp = 400, 400
  local b = require("src.battle.BattleState").newWild(game, "CHARMANDER", 30)
  b:syncSides()
  b.player.lastMove = f.ids.TACKLE
  b.enemy.mon.nickname, b.enemy.mon.hp, b.enemy.mon.stats.hp = "ENEMY", 400, 400
  b.enemy.curMoves = { { id = f.ids.DISABLE, pp = 10 } }
  b.enemy.mon.moves = b.enemy.curMoves
  b.phase, b.queue, b.frame, b.moveIndex = "moveSelect", {}, 0, 1
  b.player.curStats.speed, b.enemy.curStats.speed = 100, 200
  b.rng = function(_, hi)
    return hi
  end
  game.stack.list[1] = b
  local used, declared = {}, nil
  local off = f.e.api.events:on("battle.move_used", function(e)
    used[#used + 1] = e.move.id
  end)
  local offStart = f.e.api.events:on("battle.turn_started", function(e)
    declared = e.playerAction.id
  end)
  f.e.choose(function()
    return { move = "DISABLE" }
  end)
  local api = f.e.api.battle
  local snapshot = assert(api:snapshot())
  T.eq(snapshot.moves[1].disabled, false, "selected attack is initially available")
  local ok, why = api:submit({ id = 1, revision = snapshot.revision, kind = "move", slot = 1 })
  T.eq(ok, true, "public command queues the ordinary selected move: " .. tostring(why))
  for _ = 1, 18000 do
    if b.phase == "menu" and b.turnCount == 1 then
      break
    end
    require("src.core.Input").pressed = { a = true }
    game.stack:update(1 / 60)
  end
  T.eq(b.phase, "menu", "same-turn interruption returns to the native menu")
  T.eq(b.turnCount, 1, "Disable interruption consumes one full turn")
  T.eq(mon.moves[1].pp, 10, "already queued disabled action spends no PP")
  T.eq(b.enemy.curMoves[1].pp, 9, "Disable itself spends its real slot PP")
  T.eq(b.player.lastMove, nil, "cancellation clears last executed move")
  T.eq(b.player.disabledMove, f.ids.TACKLE, "same-turn Disable uses the previous executed move")
  T.eq(b.player.disabledTurns, 4, "five-phase timer ages once at end of turn")
  T.same(used, { "DISABLE" }, "cancelled action emits no move-used event")
  T.eq(declared, "TACKLE", "turn-start still reports the original declaration")
  off()
  offStart()
  b.phase = "moveSelect"
  snapshot = assert(api:snapshot())
  T.eq(snapshot.moves[1].disabled, true, "public snapshot reports native Disable")
  T.eq(snapshot.moves[3].disabled, true, "duplicate learned move is also disabled")
  T.eq(snapshot.moves[4].disabled, false, "a different learned move remains available")
  local timer, rng = b.player.disabledTurns, b.rng
  b.rng = function()
    error("read-only admission drew RNG")
  end
  for _, slot in ipairs({ 1, 3 }) do
    local accepted, reason = api:submit({ id = 2, revision = snapshot.revision, kind = "move", slot = slot })
    T.eq(accepted, nil, "public command rejects every disabled duplicate")
    T.eq(reason, "move is disabled", "native refusal explains the current restriction")
  end
  T.eq(b.player.disabledTurns, timer, "snapshot and admission never age the timer")
  b.rng = rng
  b:swapMoves(1, 4, b.player)
  local accepted = api:submit({ id = 2, revision = snapshot.revision, kind = "move", slot = 1 })
  T.eq(accepted, nil, "a real move reorder invalidates the old offered command")
  snapshot = assert(api:snapshot())
  T.eq(snapshot.moves[1].disabled, false, "reordered replacement is available")
  T.eq(snapshot.moves[4].disabled, true, "Disable follows the moved identity")
  b.player.disabledTurns = timer - 1
  accepted = api:submit({ id = 2, revision = snapshot.revision, kind = "move", slot = 1 })
  T.eq(accepted, nil, "changed timer invalidates the old offered context")
  snapshot = assert(api:snapshot())
  b.player.disabledMove = f.ids.SCRATCH
  accepted = api:submit({ id = 2, revision = snapshot.revision, kind = "move", slot = 3 })
  T.eq(accepted, nil, "changed disabled identity invalidates the old offered context")
  local ai = require("src.battle.Gen3AI").OPS
  local vm = { user = b.player, target = b.enemy, moveIndex = 1 }
  T.eq(
    ai.if_curr_move_disabled_or_encored(vm, { 0, 123 }),
    123,
    "native AI current-move predicate reads identity"
  )
  T.eq(
    ai.if_any_move_disabled_or_encored(vm, { 1, 0, 124 }),
    124,
    "native AI any-move predicate reads native marker"
  )
  b.player.curMoves[1].id = f.ids.TACKLE
  T.eq(D.slot(b.player), nil, "removal does not retain a stale slot")
  T.eq(
    ai.if_curr_move_disabled_or_encored(vm, { 0, 123 }),
    nil,
    "native AI current predicate sees removal immediately"
  )
  T.eq(
    ai.if_any_move_disabled_or_encored(vm, { 1, 0, 124 }),
    124,
    "native marker remains until its residual phase"
  )
  b:gen3BattlerCountersTick(b.player)
  T.eq(b.player.disabledMove, nil, "real native residual removes the now unknown move")
  local raw = require("src.battle.MoveEffects").RECORDS.DISABLE_EFFECT
  T.neq(f.data.move_effects.DISABLE_EFFECT.run, raw.run, "native adapter is installed per dataset")
  f.close()
  for _, mode in ipairs({ "override", "delegate" }) do
    -- Capture the actual public builtin during mod load, not after installation.
    local entry = 'return function(mod) local base = assert(mod.content.move_effects:get("DISABLE_EFFECT")); local run = base.run; base.run=function(ctx) '
      .. (mode == "delegate" and "return run(ctx)" or 'return {"CUSTOM"}')
      .. ' end; assert(mod.content.move_effects:override("DISABLE_EFFECT", base)); mod.exports.api=mod end'
    local g = require("tests.enemy_actions.disable").fixture(".", "gen2", version, entry)
    local c = g.fresh("TACKLE", { enemy = true })
    c.battle:syncSides()
    c.target.lastMove = g.ids.TACKLE
    c.user.curMoves = { { id = g.ids.DISABLE, pp = 10 } }
    c.user.mon.moves = c.user.curMoves
    c.battle.rng = function(_, hi)
      return hi
    end
    c.battle:executeAction(c.user, c.target, c.user.curMoves[1])
    T.eq(
      c.target.disabledMove,
      mode == "delegate" and g.ids.TACKLE or nil,
      "public override retains its native delegate or its own policy"
    )
    T.eq(
      c.target.disabledTurns,
      mode == "delegate" and 5 or nil,
      "public builtin delegate uses native duration"
    )
    T.eq(c.user.curMoves[1].pp, 9, "public override retains real PP ownership")
    T.eq(
      raw.run,
      require("src.battle.MoveEffects").RECORDS.DISABLE_EFFECT.run,
      "loads never mutate shared legacy statics"
    )
    g.close()
  end
  for _, mode in ipairs({ "switch", "baton" }) do
    local g = require("tests.enemy_actions.disable").fixture(".", "gen2", version)
    local c = g.fresh("TACKLE")
    local battle, donor = c.battle, c.user
    battle:syncSides()
    local bench = Copy(donor.mon)
    bench.nickname = "BENCH"
    battle.game.save.party[2] = bench
    donor.disabledMove, donor.disabledTurns = g.ids.TACKLE, 4
    if mode == "switch" then
      battle:switchPlayerInto(0, bench)
    else
      require("src.battle.Gen3BatonPass").switch(battle, donor, 2, battle.game.save.party)
    end
    T.eq(battle.player.mon, bench, "actual " .. mode .. " replaces the active Pokemon")
    T.eq(battle.player.disabledMove, nil, "actual " .. mode .. " never transfers Disable identity")
    T.eq(battle.player.disabledTurns, nil, "actual " .. mode .. " never transfers Disable duration")
    g.close()
  end
end
for _, key in ipairs({ "disabledMove", "disabledTurns" }) do
  T.neq(D.signature({ [key] = 1 }), D.signature({}), "native link signature includes " .. key)
end
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  V.set(version)
  local raw = require("src.battle.MoveEffects").RECORDS.DISABLE_EFFECT
  T.eq(D.builtin("DISABLE_EFFECT", raw), raw, "other generations keep the original builtin identity")
  local target = { name = "LEGACY", curMoves = { { id = "A", pp = 1 }, { id = "B", pp = 1 } } }
  raw.run({
    battle = {
      data = { moves = { A = { name = "A" }, B = { name = "B" } } },
      rng = function(_, hi)
        return hi
      end,
    },
    target = target,
  })
  T.eq(target.disabledSlot, 2, "older games retain random usable-slot selection")
  T.eq(target.disabledTurns, 8, "older games retain their legacy duration")
  T.eq(target.disabledMove, nil, "native identity does not leak to older games")
end
T.finish("native Disable public admission, queued execution and builtin delegation")
