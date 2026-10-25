package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.encore").fixture(".", "gen2", version)
  local H = require("src.link.Handshake")
  local current = H.hello(f.game, "battle")
  local older = Copy(current)
  older.nativeBattleRevision = 3
  T.eq(H.checkCompat(current, older), "subset", "pre-Encore rules cannot enter a full battle")
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
    game.save.party[1].moves =
      { { id = f.ids.TACKLE, pp = 10 }, { id = f.ids.ENCORE, pp = 10 }, { id = f.ids.SCRATCH, pp = 10 } }
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
      battle.moveIndex = turn == 0 and 1 or turn == 1 and 2 or 3
      require("src.core.Input").pressed = { a = true }
      game.stack:update(1 / 60)
    end
    if a.localHashes[2] and b.localHashes[2] and not seen[2] then
      seen[2] = true
      T.eq(a.enemy.encoreMove, f.ids.TACKLE, "host retains the remote forced move")
      T.eq(b.player.encoreMove, f.ids.TACKLE, "guest retains its own forced move")
      T.eq(a.enemy.encoreSlot, 1, "host retains the native original slot")
      T.eq(b.player.encoreSlot, 1, "guest retains the native original slot")
      T.eq(a.enemy.encoreTurns, b.player.encoreTurns, "native duration agrees after a real full turn")
    end
    if a.localHashes[3] and b.localHashes[3] then
      break
    end
  end
  T.check(seen[2], "the native Encore application turn completes on both roles")
  for turn = 1, 3 do
    T.check(a.localHashes[turn] ~= nil and b.localHashes[turn] ~= nil, "native full linked turn completes")
    T.eq(a.localHashes[turn], b.localHashes[turn], "paired completed turn hashes agree")
    T.same(a.localParts[turn], b.localParts[turn], "all active, volatile and bench components agree")
  end
  for _, battle in ipairs({ a, b }) do
    local guest = battle == a and battle.enemy or battle.player
    T.eq(guest.mon.moves[1].pp, 7, "remote and local forced Tackle consume their real slot three times")
    T.eq(guest.mon.moves[2].pp, 10, "Encore prevents the slower already-selected Encore action")
    T.eq(guest.mon.moves[3].pp, 10, "Encore prevents the next independently selected Scratch action")
    T.eq(battle.result, nil, "no hidden choice or hash failure ends the native mirror")
  end
  f.close()
end
T.finish("native Encore real link menus and completed turn hashes")
