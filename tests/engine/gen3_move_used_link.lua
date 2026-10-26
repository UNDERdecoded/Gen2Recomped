package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile("tests/enemy_actions/choice_band.lua").fixture(".", "gen2", version)
  local H = require("src.link.Handshake")
  local current = H.hello(f.game, "battle")
  local old = Copy(current)
  old.nativeBattleRevision = 11
  T.check(current.nativeBattleRevision >= 12, "PP command ordering advertises at least revision twelve")
  T.eq(H.checkCompat(current, old), "subset", "old command order cannot admit lockstep")
  for _, host in ipairs({ false, true }) do
    local state = setmetatable(
      { game = f.game, myHello = current, peerHello = old },
      { __index = require("src.link.LinkState") }
    )
    state:decideCompat("battle", host)
    T.eq(state.stage, "notice", "old ordering is refused before party exchange")
  end
  T.link.prepare(f.data)
  local ga = T.link.fakeGame(f.data, "CHARMANDER", { name = "HOST", level = 30 })
  local gb = T.link.fakeGame(f.data, "CHARMANDER", { name = "GUEST", level = 30 })
  local gs = T.link.fakeGame(f.data, "CHARMANDER", { name = "VIEWER", level = 30 })
  for i, game in ipairs({ ga, gb, gs }) do
    game.save.version, game.save.options.ruleset = version, "gen3_emerald"
    game.save.party[1].nickname = i == 1 and "HOST" or "GUEST"
    game.save.party[1].moves = { { id = f.ids.TACKLE, pp = 10 } }
    game.save.party[1].item = nil
  end
  local seen = setmetatable({}, { __mode = "k" })
  f.e.api.events:on("battle.move_used", function(ctx)
    local trace = seen[ctx.battle] or {}
    seen[ctx.battle] = trace
    local slot = ctx.user.mon.moves[1]
    trace[#trace + 1] = {
      user = ctx.user.mon.nickname,
      target = ctx.target.mon.nickname,
      move = ctx.move.id,
      pp = slot.pp,
      called = ctx.isCalled or false,
    }
  end)
  f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
    if ctx.trigger == "damage" and ctx.mon.nickname == "HOST" then
      local sum = 0
      for _, event in ipairs(seen[ctx.battle] or {}) do
        sum = sum + event.pp
      end
      return "HELD_NORMAL_BOOST", 10 + sum % 3
    end
    return nextRead(ctx)
  end)
  f.e.api.hooks:wrap("battle.crit", function()
    return false
  end)
  local P, N, L = require("src.link.Protocol"), require("src.link.Net"), require("src.link.LinkBattle")
  local na, nb = N.loopbackPair()
  local inbox = {}
  local sn = {
    update = function() end,
    poll = function()
      local got = inbox
      inbox = {}
      return got
    end,
  }
  for i, net in ipairs({ na, nb }) do
    local send, side = net.send, i == 1 and "host" or "guest"
    net.send = function(self, packet)
      inbox[#inbox + 1] = { type = "spectate", side = side, msg = Copy(packet) }
      return send(self, packet)
    end
  end
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
  local s = assert(L.newSpectator(gs, sn, {
    hostParty = pa,
    guestParty = pb,
    hostName = "HOST",
    guestName = "GUEST",
    seed = 327,
    verdict = "full",
    strict = true,
  }))
  ga.stack:push(a)
  gb.stack:push(b)
  gs.stack:push(s)
  for _, battle in ipairs({ a, b, s }) do
    T.eq(battle.ruleset.baseDamageStyle, "gba", "actual linked role uses native GBA rules")
    for _, actor in ipairs({ battle.player, battle.enemy }) do
      actor.mon.hp, actor.mon.stats.hp = 1000, 1000
    end
  end
  for _ = 1, 40000 do
    for i, game in ipairs({ ga, gb, gs }) do
      local battle = ({ a, b, s })[i]
      require("src.core.Input").pressed = (i == 3 or not battle.localHashes[2]) and { a = true } or {}
      game.stack:update(1 / 60)
    end
    if a.localHashes[2] and b.localHashes[2] and s.turnCount == 2 and s.phase == "waitBoth" then
      break
    end
  end
  for turn = 1, 2 do
    T.check(a.localHashes[turn] ~= nil and b.localHashes[turn] ~= nil, "both native menu turns complete")
    T.eq(a.localHashes[turn], b.localHashes[turn], "event mutations preserve paired completed hashes")
    T.same(a.localParts[turn], b.localParts[turn], "all active and bench state components agree")
  end
  T.same(seen[a], seen[b], "host and guest see all events with the same PP")
  T.same(seen[a], seen[s], "spectator sees every event with the same PP")
  for _, battle in ipairs({ a, b, s }) do
    T.eq(#(seen[battle] or {}), 4, "two actual turns emit four move events")
    for i, event in ipairs(seen[battle] or {}) do
      T.eq(event.pp, i <= 2 and 10 or 9, "event sees current PP before the command")
    end
    T.eq(battle.player.mon.moves[1].pp, 8, "each current PP command runs once")
    T.eq(battle.enemy.mon.moves[1].pp, 8, "each remote PP command runs once")
    T.eq(battle.result, nil, "no hidden linked simulation failure")
  end
  T.eq(s.player.mon.hp, a.player.mon.hp, "spectator host HP agrees")
  T.eq(s.enemy.mon.hp, a.enemy.mon.hp, "spectator guest HP agrees")
  T.eq(#f.result.errors, 0, "public event callback has no swallowed errors")
  f.close()
end
T.finish("native move-used PP events in actual host guest and spectator")
