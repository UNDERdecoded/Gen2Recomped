package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.rage").fixture(".", "gen2", version)
  local H = require("src.link.Handshake")
  local current = H.hello(f.game, "battle")
  local older = Copy(current)
  older.nativeBattleRevision = 6
  T.eq(H.checkCompat(current, older), "subset", "pre-Rage rules cannot enter a full battle")
  T.eq(H.checkCompat(older, current), "subset", "native revision guard is symmetric")
  for _, host in ipairs({ false, true }) do
    local state = setmetatable(
      { game = f.game, myHello = current, peerHello = older },
      { __index = require("src.link.LinkState") }
    )
    state:decideCompat("battle", host)
    T.eq(state.stage, "notice", "actual controller refuses the old native rules")
    T.eq(state.noticeExits, true, "old native rules cannot enter party selection")
  end
  local def = f.data.pokemon.CHARMANDER
  def.evYield = {}
  def.baseStats.spatk, def.baseStats.spdef, def.baseStats.hp = 50, 50, 200
  T.link.prepare(f.data)
  local ga = T.link.fakeGame(f.data, "CHARMANDER", { name = "HOST", level = 30 })
  local gb = T.link.fakeGame(f.data, "CHARMANDER", { name = "GUEST", level = 30 })
  for _, game in ipairs({ ga, gb }) do
    game.save.options.ruleset = "gen3_emerald"
    game.save.party[1].moves = {
      { id = f.ids.RAGE, pp = 10 },
      { id = f.ids.DOUBLE_SLAP, pp = 10 },
      { id = f.ids.TACKLE, pp = 10 },
    }
  end
  f.e.api.hooks:wrap("battle.crit", function()
    return false
  end)
  local P, N, L = require("src.link.Protocol"), require("src.link.Net"), require("src.link.LinkBattle")
  local na, nb = N.loopbackPair()
  local pa, pb = P.packParty(ga.save.party), P.packParty(gb.save.party)
  local a = assert(
    L.newHost(
      ga,
      na,
      { myParty = pa, theirParty = pb, theirName = "GUEST", seed = 327, verdict = "full", strict = true }
    )
  )
  local b = assert(
    L.newGuest(
      gb,
      nb,
      { myParty = pb, theirParty = pa, theirName = "HOST", seed = 327, verdict = "full", strict = true }
    )
  )
  ga.stack:push(a)
  gb.stack:push(b)
  a.player.curStats.speed, a.enemy.curStats.speed = 200, 100
  b.player.curStats.speed, b.enemy.curStats.speed = 100, 200
  local seen = {}
  for _ = 1, 40000 do
    for i, game in ipairs({ ga, gb }) do
      local battle = i == 1 and a or b
      local turn = battle.turnCount or 0
      battle.moveIndex = turn < 2 and 1 or turn == 2 and (i == 1 and 2 or 1) or 3
      require("src.core.Input").pressed = { a = true }
      game.stack:update(1 / 60)
    end
    if a.localHashes[3] and b.localHashes[3] and not seen[3] then
      seen[3] = true
      T.eq(
        a.player.stages.attack,
        2,
        "choosing an alternative clears the faster owner's Rage before the reply"
      )
      T.eq(a.enemy.stages.attack, 2, "the whole incoming multi-hit builds Rage only once")
      T.eq(b.enemy.stages.attack, 2, "remote owner keeps the same completed stage")
      T.eq(b.player.stages.attack, 2, "guest observes one completed multi-hit boost")
    end
    if a.localHashes[4] and b.localHashes[4] then
      break
    end
  end
  T.check(seen[3], "the mixed Rage and multi-hit turn completes on both roles")
  for turn = 1, 4 do
    T.check(a.localHashes[turn] ~= nil and b.localHashes[turn] ~= nil, "native full linked turn completes")
    T.eq(a.localHashes[turn], b.localHashes[turn], "paired completed turn hashes agree")
    T.same(a.localParts[turn], b.localParts[turn], "all active, volatile and bench components agree")
  end
  for _, battle in ipairs({ a, b }) do
    local host = battle == a and battle.player or battle.enemy
    local guest = battle == a and battle.enemy or battle.player
    T.eq(host.mon.moves[1].pp, 8, "host's two separately selected Rage actions both spend PP")
    T.eq(guest.mon.moves[1].pp, 7, "guest's three Rage actions all spend their learned PP")
    T.eq(host.mon.moves[2].pp, 9, "host actually executes the independently selected multi-hit")
    T.eq(guest.mon.moves[2].pp, 10, "guest never spends the unselected multi-hit slot")
    for _, battler in ipairs({ host, guest }) do
      T.eq(battler.mon.moves[3].pp, 9, "last independently selected Tackle spends its own PP")
      T.eq(battler.rage, nil, "both native Rage flags clear before the last turn")
      T.eq(battler.stages.attack, 2, "no stale Rage boost occurs on the last turn")
    end
    T.eq(battle.result, nil, "no hidden input or hash failure ends the native mirror")
  end
  f.close()
end
T.finish("native Rage real link menus and completed turn hashes")
