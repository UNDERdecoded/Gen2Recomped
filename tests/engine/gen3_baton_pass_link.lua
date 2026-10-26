package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Copy = require("src.mods.Merge").deepCopy
local Input = require("src.core.Input")
for _, version in ipairs({ "firered", "emerald" }) do
  local f = require("tests.enemy_actions.baton_pass").fixture(".", "gen2", version)
  local def = f.data.pokemon.CHARMANDER
  def.evYield = {}
  def.baseStats.spatk, def.baseStats.spdef = 50, 50
  T.link.prepare(f.data)
  local games = {}
  for i, name in ipairs({ "HOST", "GUEST", "VIEWER" }) do
    local game = T.link.fakeGame(f.data, "CHARMANDER", { name = name, level = 30 })
    game.stack.states = game.stack.list
    games[i] = game
    local mon = game.save.party[1]
    mon.nickname = name:sub(1, 1) .. "_ALPHA"
    mon.moves =
      { { id = f.ids.BATON_PASS, pp = 20 }, { id = f.ids.TACKLE, pp = f.data.moves[f.ids.TACKLE].pp } }
    for j = 2, 3 do
      game.save.party[j] = Copy(mon)
      game.save.party[j].nickname = name:sub(1, 1) .. (j == 2 and "_BETA" or "_GAMMA")
      game.save.party[j].moves = { { id = f.ids.TACKLE, pp = f.data.moves[f.ids.TACKLE].pp } }
    end
  end
  local Net, P, Link = require("src.link.Net"), require("src.link.Protocol"), require("src.link.LinkBattle")
  local na, nb = Net.loopbackPair()
  local inbox, packets = {}, {}
  local sn = {
    update = function() end,
    poll = function()
      local out = inbox
      inbox = {}
      return out
    end,
  }
  for i, net in ipairs({ na, nb }) do
    local send, side = net.send, i == 1 and "host" or "guest"
    net.send = function(self, packet)
      if packet.type == "baton_pass" then
        packets[#packets + 1] = Copy(packet)
      end
      inbox[#inbox + 1] = { type = "spectate", side = side, msg = Copy(packet) }
      return send(self, packet)
    end
  end
  local pa, pb = P.packParty(games[1].save.party), P.packParty(games[2].save.party)
  local a = assert(
    Link.newHost(
      games[1],
      na,
      { myParty = pa, theirParty = pb, theirName = "GUEST", seed = 327, verdict = "full", strict = true }
    )
  )
  local b = assert(
    Link.newGuest(
      games[2],
      nb,
      { myParty = pb, theirParty = pa, theirName = "HOST", seed = 327, verdict = "full", strict = true }
    )
  )
  local s = assert(Link.newSpectator(games[3], sn, {
    hostParty = pa,
    guestParty = pb,
    hostName = "HOST",
    guestName = "GUEST",
    seed = 327,
    verdict = "full",
    strict = true,
  }))
  local battles, chosen, intentId = { a, b, s }, {}, 0
  for i, battle in ipairs(battles) do
    games[i].stack:push(battle)
    battle.player.stages.attack, battle.enemy.stages.attack = 2, 2
  end
  local seen = {}
  for frame = 1, 30000 do
    for i, game in ipairs(games) do
      f.result.loader.game = game
      local top = game.stack:top()
      if top ~= battles[i] then
        local view = f.e.api.ui:snapshot()
        if view and view.kind == "party" then
          T.check(i < 3, "spectator never opens a personal party chooser")
          intentId = intentId + 1
          local ok, why =
            f.e.api.ui:submit({ id = intentId, revision = view.revision, kind = "select", index = 3 })
          assert(ok, why)
          chosen[i] = (chosen[i] or 0) + 1
        end
      end
      Input.pressed = { a = true }
      game.stack:update(1 / 60)
    end
    if a.localHashes[1] and b.localHashes[1] and not seen[1] then
      seen[1] = true
      for i, battle in ipairs(battles) do
        T.eq(
          battle.player.mon.nickname,
          (i == 2 and "G" or "H") .. "_GAMMA",
          "selected non-first local replacement survives the complete turn"
        )
        T.eq(
          battle.enemy.mon.nickname,
          (i == 2 and "H" or "G") .. "_GAMMA",
          "selected remote replacement survives the complete turn"
        )
        T.eq(battle.player.stages.attack, 2, "local stages pass through wire continuation")
        T.eq(battle.enemy.stages.attack, 2, "remote stages pass through wire continuation")
      end
    end
    if a.localHashes[2] and b.localHashes[2] then
      break
    end
  end
  T.check(seen[1], "both native peers complete the Baton Pass turn")
  T.eq(chosen[1], 1, "host makes exactly one real UI selection")
  T.eq(chosen[2], 1, "guest makes exactly one real UI selection")
  T.eq(chosen[3], nil, "spectator consumes transmitted choices")
  T.eq(#packets, 2, "both owners send their selected replacement")
  for _, packet in ipairs(packets) do
    T.eq(packet.index, 3, "wire retains the non-first selection")
  end
  for turn = 1, 2 do
    T.check(a.localHashes[turn] ~= nil and b.localHashes[turn] ~= nil, "full linked turn completes")
    T.eq(a.localHashes[turn], b.localHashes[turn], "paired full turn hashes agree")
    T.same(a.localParts[turn], b.localParts[turn], "all native state components agree")
  end
  T.eq(a.result, nil, "host does not silently terminate on a choice mismatch")
  T.eq(b.result, nil, "guest does not silently terminate on a choice mismatch")
  T.eq(s.result, nil, "spectator continues after both real choices")
  T.eq(games[1].save.party[1].moves[1].pp, 20, "link choices do not mutate the persistent save party")
  -- A disconnect must still be polled while the native party screen owns input.
  local game = T.link.fakeGame(f.data, "CHARMANDER", { name = "DROP", level = 30 })
  game.save.party = Copy(games[1].save.party)
  game.stack.states = game.stack.list
  local nc, nd = Net.loopbackPair()
  local dropped = assert(
    Link.newHost(
      game,
      nc,
      { myParty = pa, theirParty = pb, theirName = "GUEST", seed = 327, verdict = "full", strict = true }
    )
  )
  game.stack:push(dropped)
  dropped.player.curStats.speed, dropped.enemy.curStats.speed = 200, 100
  nd:send({ type = "action", kind = "move", slot = 1 })
  local picker
  f.result.loader.game = game
  for _ = 1, 15000 do
    local view = f.e.api.ui:snapshot()
    if view and view.kind == "party" then
      picker = game.stack:top()
      break
    end
    Input.pressed = { a = true }
    game.stack:update(1 / 60)
  end
  T.check(picker ~= nil, "real linked picker is active before disconnect")
  assert(picker)
  nc.closed = true
  Input.pressed = {}
  game.stack:update(1 / 60)
  T.eq(dropped.result, "draw", "link loss is handled while picker owns the stack")
  T.eq(game.stack:top(), dropped, "disconnect retires the native picker")
  T.eq(dropped._gen3BatonPending, nil, "disconnect clears the pending continuation")
  T.eq(dropped.player.mon.nickname, "H_ALPHA", "disconnect never silently selects the first bench")
  f.close()
end
T.finish("native Baton Pass link choices and spectator continuation")
