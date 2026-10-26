package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
for _, version in ipairs({ "firered", "emerald" }) do
  local f = dofile("tests/enemy_actions/choice_band.lua").fixture(".", "gen2", version)
  local H = require("src.link.Handshake")
  local current = H.hello(f.game, "battle")
  local older = Copy(current)
  older.nativeBattleRevision = 10
  T.eq(current.nativeBattleRevision, 11, "native Choice Band advertises revised commands")
  T.eq(H.checkCompat(current, older), "subset", "old held commands cannot enter a full battle")
  T.eq(H.checkCompat(older, current), "subset", "revised held commands reject symmetrically")
  for _, host in ipairs({ false, true }) do
    local state = setmetatable(
      { game = f.game, myHello = current, peerHello = older },
      { __index = require("src.link.LinkState") }
    )
    state:decideCompat("battle", host)
    T.eq(state.stage, "notice", "actual link controller refuses before party exchange")
    T.eq(state.noticeExits, true, "revision mismatch cannot start a battle")
  end
  T.link.prepare(f.data)
  local ga = T.link.fakeGame(f.data, "CHARMANDER", { name = "HOST", level = 30 })
  local gb = T.link.fakeGame(f.data, "CHARMANDER", { name = "GUEST", level = 30 })
  local gs = T.link.fakeGame(f.data, "CHARMANDER", { name = "VIEWER", level = 30 })
  gs.save.version, gs.save.options.ruleset = version, "gen3_emerald"
  for i, game in ipairs({ ga, gb }) do
    game.save.version, game.save.options.ruleset = version, "gen3_emerald"
    local mon = game.save.party[1]
    mon.nickname = i == 1 and "HOST" or "GUEST"
    mon.moves = { { id = f.ids.TACKLE, pp = 10 }, { id = f.ids.SCRATCH, pp = 10 } }
    mon.item = "ITEM_186"
  end
  local seen = setmetatable({}, { __mode = "k" })
  f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
    local trace = seen[ctx.battle] or {}
    seen[ctx.battle] = trace
    trace[#trace + 1] = {
      holder = ctx.mon.nickname,
      item = ctx.item,
      effect = ctx.effect,
      parameter = ctx.parameter,
      trigger = ctx.trigger,
    }
    -- A stateful consumer uses every earlier read, including entry/priority
    -- and residual calls. Reordering cannot be hidden by equal final counts.
    if ctx.trigger == "damage" and ctx.mon.nickname == "HOST" then
      return "HELD_NORMAL_BOOST", 10 + #trace % 3
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
      local messages = inbox
      inbox = {}
      return messages
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
    T.eq(battle.ruleset.baseDamageStyle, "gba", "actual linked battle uses the GBA damage profile")
    for _, actor in ipairs({ battle.player, battle.enemy }) do
      actor.mon.hp, actor.mon.stats.hp = 1000, 1000
      actor.curStats.attack, actor.curStats.defense, actor.curTypes = 51, 51, { "NORMAL" }
      actor.stages.attack, actor.stages.defense = 1, -1
    end
  end
  local firstTurn = false
  for _ = 1, 40000 do
    for i, game in ipairs({ ga, gb, gs }) do
      local battle = ({ a, b, s })[i]
      battle.moveIndex = firstTurn and 2 or 1
      require("src.core.Input").pressed = (i == 3 or firstTurn or not battle.localHashes[1]) and { a = true }
        or {}
      game.stack:update(1 / 60)
    end
    if
      a.localHashes[1]
      and b.localHashes[1]
      and s.turnCount == 1
      and s.phase == "waitBoth"
      and not firstTurn
    then
      firstTurn = true
      for _, battle in ipairs({ a, b, s }) do
        for _, actor in ipairs({ battle.player, battle.enemy }) do
          T.eq(actor.choicedMove, 33, "completed native move binds the current learned move")
          actor.mon.item = nil
        end
      end
    end
    if a.localHashes[2] and b.localHashes[2] and s.turnCount == 2 and s.phase == "waitBoth" then
      break
    end
  end
  for turn = 1, 2 do
    T.check(a.localHashes[turn] ~= nil and b.localHashes[turn] ~= nil, "both menu-driven turns complete")
    T.eq(a.localHashes[turn], b.localHashes[turn], "paired completed turn hashes agree")
    T.same(a.localParts[turn], b.localParts[turn], "every active/volatile/bench component agrees")
  end
  print("CHOICE_LINK_TRACES " .. require("src.link.Json").encode({
    version = version,
    host = seen[a],
    guest = seen[b],
    spectator = seen[s],
  }))
  T.same(seen[a], seen[b], "both real link roles see the same complete ordered held reads")
  T.same(seen[a], seen[s], "real spectator sees the same complete ordered held reads")
  T.check(#(seen[a] or {}) > 8, "complete held traces include planning and move-end consumers")
  T.eq(s.player.mon.hp, a.player.mon.hp, "spectator retains the stateful host damage result")
  T.eq(s.enemy.mon.hp, a.enemy.mon.hp, "spectator retains the stateful guest damage result")
  for _, battle in ipairs({ a, b, s }) do
    T.eq(battle.player.mon.moves[1].pp, 9, "first native menu spends Tackle PP")
    T.eq(battle.player.mon.moves[2].pp, 9, "lost physical item admits Scratch on the next native menu")
    T.eq(battle.player.choicedMove, 33, "item loss retains the learned choice identity")
    T.check(battle.player.mon.hp < 1000 and battle.enemy.mon.hp < 1000, "real attacks damage both battlers")
    T.eq(battle.result, nil, "no hidden link or choice failure ends the mirror")
  end
  T.eq(#f.result.errors, 0, "all real callback chains remain error-free")
  f.close()
end
T.finish("native Choice Band real link menus, item loss and command compatibility")
