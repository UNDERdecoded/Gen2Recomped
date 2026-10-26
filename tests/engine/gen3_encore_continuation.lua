package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
local Input = require("src.core.Input")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, selection in ipairs({ "fight", "late_move", "late_priority" }) do
    local f = require("tests.enemy_actions.encore").fixture(".", "gen2", version)
    T.link.prepare(f.data)
    local game = T.link.fakeGame(f.data, "CHARMANDER", { name = "PLAYER", level = 30 })
    game.stack.states = game.stack.list
    f.result.loader.game = game
    local mon = game.save.party[1]
    mon.nickname = "PLAYER"
    mon.moves =
      { { id = f.ids.TACKLE, pp = 10 }, { id = f.ids.ENCORE, pp = 10 }, { id = f.ids.SCRATCH, pp = 10 } }
    mon.hp, mon.stats.hp = 400, 400
    local b = require("src.battle.BattleState").newWild(game, "CHARMANDER", 30)
    b:syncSides()
    b.enemy.mon.nickname = "ENEMY"
    b.enemy.mon.hp, b.enemy.mon.stats.hp = 400, 400
    b.enemy.curMoves = { { id = f.ids.SCRATCH, pp = 10 } }
    b.enemy.mon.moves = b.enemy.curMoves
    b.player.encoreMove, b.player.encoreSlot, b.player.encoreTurns = f.ids.TACKLE, 1, 4
    b.player.lastMove = f.ids.TACKLE
    b.phase, b.queue, b.frame, b.menuIndex, b.moveIndex = "menu", {}, 0, 1, 1
    if selection ~= "fight" then
      b.phase = "moveSelect"
    end
    if selection == "late_priority" then
      f.data.moves[f.ids.TACKLE].priority = -1
      b.player.curStats.speed, b.enemy.curStats.speed = 200, 100
    end
    game.stack.list[1] = b
    f.e.choose(function()
      return { move = "SCRATCH" }
    end)
    local used = {}
    local declared
    local offStart = f.e.api.events:on("battle.turn_started", function(e)
      declared = e.playerAction.id
    end)
    local off = f.e.api.events:on("battle.move_used", function(e)
      used[#used + 1] = { user = e.user.mon.nickname, move = e.move.id }
    end)
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    local api = f.e.api.battle
    local before = assert(api:snapshot())
    local raw = { id = 1, revision = before.revision, kind = selection == "fight" and "menu" or "move" }
    if selection == "fight" then
      raw.choice = "fight"
    else
      raw.slot = 3
    end
    if selection == "late_move" then
      b.player.encoreSlot = 2
      local accepted, why = api:submit(raw)
      T.eq(accepted, nil, "a changed Encore slot invalidates the previously offered intent")
      T.check(type(why) == "string", "stale Encore context returns an explanation")
      b.player.encoreSlot = 1
      raw.revision = assert(api:snapshot()).revision
    end
    local accepted, why = api:submit(raw)
    T.eq(accepted, true, "public command reaches native Encore continuation: " .. tostring(why))
    for _ = 1, 18000 do
      if b.phase == "menu" and b.turnCount == 1 then
        break
      end
      Input.pressed = { a = true }
      game.stack:update(1 / 60)
    end
    T.eq(b.phase, "menu", "Encore returns to the normal native menu")
    T.eq(b.turnCount, 1, "forced continuation consumes exactly one turn")
    T.eq(mon.moves[1].pp, 9, "only the forced learned slot spends PP")
    T.eq(mon.moves[3].pp, 10, "the previously selected alternative keeps its PP")
    T.eq(b.player.encoreTurns, 3, "real end-of-turn processing ages Encore once")
    T.check(b.enemy.mon.hp < 400, "the forced move actually damages the opponent")
    T.eq(#used, 2, "both native actions execute once")
    T.eq(
      declared,
      selection == "fight" and "TACKLE" or "SCRATCH",
      "turn-start event retains the original declared choice"
    )
    if selection == "late_priority" then
      T.eq(
        used[1].user,
        "ENEMY",
        "turn order uses the forced move priority rather than the superseded choice"
      )
    end
    local playerMoves = 0
    for _, e in ipairs(used) do
      if e.user == mon.nickname then
        playerMoves = playerMoves + 1
        T.eq(e.move, "TACKLE", "public event names the actual forced move")
      end
    end
    T.eq(playerMoves, 1, "the player emits one actual move event")
    off()
    offStart()
    f.close()
  end
  for _, mode in ipairs({ "override", "delegate" }) do
    local f = require("tests.enemy_actions.encore").fixture(".", "gen2", version)
    local c = f.fresh("TACKLE", { enemy = true })
    local b = c.battle
    b:syncSides()
    c.target.lastMove = f.ids.TACKLE
    c.user.mon.moves = { { id = f.ids.ENCORE, pp = 10 } }
    c.user.curMoves = c.user.mon.moves
    local custom = Copy(b.data.move_effects.ENCORE_EFFECT)
    local builtin, calls = custom.run, 0
    custom.run = function(ctx)
      calls = calls + 1
      return mode == "delegate" and builtin(ctx) or { "CUSTOM" }
    end
    b.data.move_effects.ENCORE_EFFECT = custom
    b.rng = function(_, hi)
      return hi
    end
    b:executeAction(c.user, c.target, c.user.curMoves[1])
    T.eq(calls, 1, "authored Encore handler runs exactly once")
    T.eq(c.user.mon.moves[1].pp, 9, "authored handler keeps native PP ownership")
    T.eq(
      c.target.encoreTurns,
      mode == "delegate" and 6 or nil,
      "authored handler retains override or native delegation"
    )
    T.eq(c.target.encoreSlot, mode == "delegate" and 1 or nil, "native delegation retains slot binding")
    f.close()
  end
end
local E = require("src.battle.Gen3Encore")
for _, key in ipairs({ "encoreTurns", "encoreMove", "encoreSlot" }) do
  T.neq(E.signature({ [key] = 1 }), E.signature({}), "native hashes include " .. key)
end
for _, version in ipairs({ "red", "gold", "diamond", "black" }) do
  require("src.core.GameVersion").set(version)
  local target = { name = "TARGET", isPlayer = true, lastMove = "LEGACY" }
  require("src.battle.Gen3MoveEffects").primary.ENCORE_EFFECT({}, {}, target)
  T.eq(target.encoreTurns, 3, "older games keep their existing Encore duration")
  T.eq(target.encoreSlot, nil, "older games do not acquire native slot semantics")
end
T.finish("native Encore public commands, queued turns and legacy policies")
