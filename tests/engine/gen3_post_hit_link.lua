package.path = "./?.lua;./?/init.lua;" .. package.path
local T, Copy = require("tests.modkit"), require("src.mods.Merge").deepCopy
for _, version in ipairs({ "firered", "emerald" }) do
  for _, hostKing in ipairs({ false, true }) do
    local f = dofile("tests/enemy_actions/post_hit_items.lua").fixture(".", "gen2", version)
    local H = require("src.link.Handshake")
    local current = H.hello(f.game, "battle")
    local old = Copy(current)
    old.nativeBattleRevision = 12
    T.check(current.nativeBattleRevision >= 13, "shared post-hit commands advertise at least revision thirteen")
    T.eq(H.checkCompat(current, old), "subset", "old command order cannot admit lockstep")
    for _, host in ipairs({ false, true }) do
      local state = setmetatable(
        { game = f.game, myHello = current, peerHello = old },
        { __index = require("src.link.LinkState") }
      )
      state:decideCompat("battle", host)
      T.eq(state.stage, "notice", "old ordering is refused before party exchange")
    end
    f.data.moves.MOVE_033.flags = 51
    f.data.moves.MOVE_033.gen3Effect = 0
    T.link.prepare(f.data)
    local ga = T.link.fakeGame(f.data, "CHARMANDER", { name = "HOST", level = 30 })
    local gb = T.link.fakeGame(f.data, "CHARMANDER", { name = "GUEST", level = 30 })
    local gs = T.link.fakeGame(f.data, "CHARMANDER", { name = "VIEWER", level = 30 })
    for i, game in ipairs({ ga, gb, gs }) do
      game.save.version, game.save.options.ruleset = version, "gen3_emerald"
      game.save.party[1].nickname = i == 1 and "HOST" or "GUEST"
      game.save.party[1].moves = { { id = "MOVE_033", pp = 10 } }
      game.save.party[1].item = (i == 1 and hostKing or i ~= 1 and not hostKing) and "ITEM_187" or "ITEM_219"
    end
    local seen, reads, draws, pending = {}, {}, {}, {}
    f.e.api.events:on("battle.move_used", function(ctx)
      local trace = seen[ctx.battle] or {}
      seen[ctx.battle] = trace
      trace[#trace + 1] = {
        user = ctx.user.mon.nickname,
        target = ctx.target.mon.nickname,
        move = ctx.move.id,
        pp = ctx.user.mon.moves[1].pp,
        called = ctx.isCalled or false,
      }
    end)
    f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
      local trace = reads[ctx.battle] or {}
      reads[ctx.battle] = trace
      local row = {
        user = ctx.mon.nickname,
        item = ctx.item,
        effect = ctx.effect,
        parameter = ctx.parameter,
        trigger = ctx.trigger,
      }
      trace[#trace + 1] = row
      if ctx.trigger == "flinch" then
        if pending[ctx.battle] then
          pending[ctx.battle] = false
          row.effectOut, row.parameterOut = "HELD_FLINCH", 256
          return row.effectOut, row.parameterOut
        end
        if ctx.effect == "HELD_FLINCH" then
          pending[ctx.battle] = true
        end
      end
      local effect, parameter = nextRead(ctx)
      row.effectOut, row.parameterOut = effect, parameter
      return effect, parameter
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
        actor.mon.hp, actor.mon.stats.hp = 500, 1000
        actor.curStats.speed = actor.mon.nickname == "HOST" and 200 or 100
      end
    end
    for _, battle in ipairs({ a, b, s }) do
      local random = battle.rng
      draws[battle] = {}
      battle.rng = function(lo, hi)
        local value = random(lo, hi)
        draws[battle][#draws[battle] + 1] = { lo, hi, value }
        return value
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
    T.same(reads[a], reads[b], "host and guest retain all stateful held reads")
    T.same(reads[a], reads[s], "spectator retains all stateful held reads")
    T.same(draws[a], draws[b], "host and guest retain every RNG draw")
    T.same(draws[a], draws[s], "spectator retains every RNG draw")
    for _, battle in ipairs({ a, b, s }) do
      T.eq(#(seen[battle] or {}), hostKing and 2 or 4, "moved targets resist flinch; waiting targets skip")
      local host = battle.linkRole == "guest" and battle.enemy or battle.player
      local guest = battle.linkRole == "guest" and battle.player or battle.enemy
      T.eq(host.mon.moves[1].pp, 8, "host acts on both turns")
      T.eq(guest.mon.moves[1].pp, hostKing and 10 or 8, "native flinch prevents the waiting action")
      local commandReads = 0
      for _, row in ipairs(reads[battle] or {}) do
        if row.trigger == "flinch" and row.parameterOut == 256 then
          commandReads = commandReads + 1
          T.eq(row.user, "HOST", "the second flinch read uses canonical host player on every role")
        end
      end
      T.eq(commandReads, 2, "one complete King's Rock command runs per turn")
      T.eq(battle.result, nil, "no hidden linked simulation failure")
    end
    T.eq(s.player.mon.hp, a.player.mon.hp, "spectator host HP agrees")
    T.eq(s.enemy.mon.hp, a.enemy.mon.hp, "spectator guest HP agrees")
    T.eq(#f.result.errors, 0, "public event callback has no swallowed errors")
    f.close()
  end
end
T.finish("native post-hit items in actual host guest and spectator")
