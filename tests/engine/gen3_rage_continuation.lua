package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
local R, V = require("src.battle.Gen3Rage"), require("src.core.GameVersion")
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.rage").fixture(".", "gen2", version)
  T.link.prepare(f.data)
  local game = T.link.fakeGame(f.data, "CHARMANDER", { name = "PLAYER", level = 30 })
  game.save.options.ruleset = "gen3_emerald"
  game.stack.states = game.stack.list
  f.result.loader.game = game
  local mon = game.save.party[1]
  mon.nickname = "PLAYER"
  mon.hp, mon.stats.hp = 400, 400
  mon.moves = { { id = f.ids.RAGE, pp = 10 }, { id = f.ids.TACKLE, pp = 10 } }
  local b = require("src.battle.BattleState").newWild(game, "CHARMANDER", 30)
  b:syncSides()
  b.enemy.mon.nickname, b.enemy.mon.hp, b.enemy.mon.stats.hp = "ENEMY", 400, 400
  b.enemy.curMoves = { { id = f.ids.TACKLE, pp = 10 } }
  b.enemy.mon.moves = b.enemy.curMoves
  b.player.curStats.speed, b.enemy.curStats.speed = 100, 200
  b.phase, b.queue, b.frame, b.menuIndex, b.moveIndex = "moveSelect", {}, 0, 1, 1
  game.stack.list[1] = b
  b.rng = function(_, hi)
    return hi
  end
  f.e.choose(function()
    return { move = "TACKLE" }
  end)
  f.e.api.hooks:wrap("battle.crit", function()
    return false
  end)
  local started, used, stages = {}, {}, {}
  local off = f.e.api.events:on("battle.turn_started", function(e)
    started[#started + 1] = { id = e.playerAction.id, rage = not not b.player.rage }
  end)
  local offMove = f.e.api.events:on("battle.move_used", function(e)
    used[#used + 1] = { user = e.user.mon.nickname, move = e.move.id }
  end)
  local nativeHeld = b.holdItemTrigger
  b.holdItemTrigger = function(self, who, when)
    if when == "moveEnd" and who == self.player then
      stages[#stages + 1] = who.stages.attack or 0
    end
    return nativeHeld(self, who, when)
  end
  local api, command = f.e.api.battle, 0
  local function submit(raw)
    local snapshot = assert(api:snapshot())
    command = command + 1
    raw.id, raw.revision = command, snapshot.revision
    local ok, why = api:submit(raw)
    T.eq(ok, true, "public Rage command is accepted: " .. tostring(why))
  end
  local function complete(turn)
    for _ = 1, 18000 do
      if b.phase == "menu" and b.turnCount == turn then
        break
      end
      require("src.core.Input").pressed = { a = true }
      game.stack:update(1 / 60)
    end
    T.eq(b.phase, "menu", "native Rage turn returns to the actual menu")
    T.eq(b.turnCount, turn, "exactly one native turn completes")
  end
  submit({ kind = "move", slot = 1 })
  complete(1)
  T.eq(b.player.rage, true, "real Rage producer activates its native flag")
  T.eq(b.player.rageMove, nil, "real Rage does not install a legacy lock")
  T.eq(mon.moves[1].pp, 9, "first selected Rage spends PP")
  T.eq(b.player.stages.attack or 0, 0, "earlier attack before first Rage does not build rage")
  T.eq(assert(api:snapshot()).prompt, "menu", "native Rage leaves public menu actionable")
  submit({ kind = "menu", choice = "fight" })
  T.eq(b.phase, "moveSelect", "FIGHT opens the real move list after Rage")
  submit({ kind = "move", slot = 1 })
  complete(2)
  T.eq(mon.moves[1].pp, 8, "a separately selected repeat spends another PP")
  T.eq(b.player.stages.attack, 1, "faster foe builds Rage once before the second attack")
  T.eq(stages[3], 1, "Rage boost is present before the real move-end item read")
  submit({ kind = "menu", choice = "fight" })
  submit({ kind = "move", slot = 2 })
  complete(3)
  T.eq(mon.moves[1].pp, 8, "another selected move does not consume Rage PP")
  T.eq(mon.moves[2].pp, 9, "the independently selected alternative actually executes")
  T.eq(b.player.rage, nil, "alternative choice clears Rage before the faster opponent")
  T.eq(b.player.stages.attack, 1, "no stale Rage boost occurs on the alternative turn")
  T.same(
    started,
    { { id = "RAGE", rage = false }, { id = "RAGE", rage = true }, { id = "TACKLE", rage = false } },
    "turn-start observes Rage cleanup and original selected moves"
  )
  T.eq(#used, 6, "both real actions execute on all three turns")
  b.phase = "moveSelect"
  local offered = assert(api:snapshot())
  b.player.rage = true
  local stale = api:submit({ id = command + 1, revision = offered.revision, kind = "move", slot = 2 })
  T.eq(stale, nil, "changed Rage flag invalidates an old offered command")
  T.eq(
    require("src.battle.Gen3AI").OPS.if_status2({ user = b.player }, { 1, 0x800000, 71 }),
    71,
    "native AI sees produced Rage status bit"
  )
  off()
  offMove()
  f.close()
  for _, mode in ipairs({ "override", "delegate" }) do
    local entry = [[return function(mod)
   local base=assert(mod.content.move_effects:get('RAGE_EFFECT'));local run=base.afterDamage
   mod.exports.calls=0
   assert(mod.content.move_effects:override('RAGE_EFFECT',{kind='full',afterDamage=function(ctx)
    mod.exports.calls=mod.exports.calls+1
    ]] .. (mode == "delegate" and "return run(ctx)" or "return") .. [[
   end}));mod.exports.api=mod
  end]]
    local g = require("tests.enemy_actions.rage").fixture(".", "gen2", version, entry)
    local c = g.fresh("TACKLE", { enemy = true })
    c.battle:syncSides()
    c.user.curMoves = { { id = g.ids.RAGE, pp = 10 } }
    c.user.mon.moves = c.user.curMoves
    c.battle.rng = function(_, hi)
      return hi
    end
    c.battle:executeAction(c.user, c.target, c.user.curMoves[1])
    T.eq(g.e.calls, 1, "authored Rage handler runs once")
    T.eq(
      not not c.user.rage,
      mode == "delegate",
      "complete override retains its own policy or native delegate"
    )
    T.eq(c.user.rageMove, nil, "native delegate never installs the legacy lock")
    T.eq(c.user.curMoves[1].pp, 9, "authored Rage retains native PP ownership")
    g.close()
  end
  for _, mode in ipairs({ "item", "ball", "reply", "switch", "baton", "run" }) do
    local g = require("tests.enemy_actions.rage").fixture(".", "gen2", version)
    local c = g.fresh("TACKLE")
    local battle, donor = c.battle, c.user
    battle:syncSides()
    donor.rage, battle.enemy.rage = true, true
    local calls = 0
    g.e.choose(function()
      calls = calls + 1
      T.eq(donor.rage, true, "enemy selection sees the original pre-cleanup Rage state")
      return { move = "TACKLE" }
    end)
    battle.rng = function(_, hi)
      return hi
    end
    if mode == "item" then
      battle:itemUsed({})
    elseif mode == "run" then
      battle.player.curStats.speed, battle.enemy.curStats.speed = 200, 100
      battle:tryRun()
      T.eq(battle.result, "run", "actual successful escape finishes with the cleaned native state")
    elseif mode == "ball" then
      battle:throwBall("POKE_BALL")
    elseif mode == "reply" then
      local run = battle:nonMoveAction()
      g.e.choose(function()
        error("native reply selected twice")
      end)
      run()
      T.eq(donor.stages.attack or 0, 0, "non-move reply cannot build stale Rage")
    else
      local bench = Copy(donor.mon)
      bench.nickname = "BENCH"
      battle.game.save.party[2] = bench
      if mode == "switch" then
        battle:resolveSwitch(bench)
      else
        require("src.battle.Gen3BatonPass").switch(battle, donor, 2, battle.game.save.party)
      end
    end
    if mode ~= "baton" then
      T.eq(donor.rage, nil, "committed non-move action clears native Rage")
      T.eq(calls, 1, "native non-move action prepares exactly one enemy reply")
    else
      T.eq(battle.player.rage, nil, "Baton Pass never transfers Rage")
    end
    g.close()
  end
end
T.neq(R.signature({ rage = true }), R.signature({}), "native active hash includes Rage")
T.eq(R.signature({ rage = false }), R.signature({}), "false and absent flags share the same semantic hash")
local raw = require("src.battle.MoveEffects").RECORDS.RAGE_EFFECT
for _, v in ipairs({ "red", "gold", "diamond", "black" }) do
  V.set(v)
  T.eq(R.builtin("RAGE_EFFECT", raw), raw, "older generation retains original builtin identity")
  local user = {}
  local move = { id = "LEGACY" }
  raw.afterDamage({ user = user, moveInst = move })
  T.eq(user.rageMove, move, "older generation keeps the existing move lock")
  T.eq(user.rage, nil, "native marker does not leak to other generations")
end
T.finish("native Rage public commands, replies, composition and legacy behavior")
