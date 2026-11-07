-- The Link Hub's in-process self test.  No sockets, no LOVE: the hub's UDP
-- side runs on WS1's LoopNet (an in-memory network with a fake clock), its
-- TCP side through in-memory connections.
--
--   python tools/run_lua_check.py tools/online-hub/selftest.lua    (repo root)
--   love tools/online-hub --selftest
--
-- Optional: POKEPORT_DATA_DIR=<a Gen 4 cache, e.g. .../platinum/data/generated>
-- adds the GTS section (a deposit validated against that game's data).

package.path = "./?.lua;./?/init.lua;./tools/online-hub/?.lua;" .. package.path

local T = {}

function T.run()
  local passed, failed = 0, 0
  local function check(cond, msg)
    if cond then
      passed = passed + 1
    else
      failed = failed + 1
      print("FAIL: " .. msg)
    end
  end
  local function eq(got, want, msg)
    check(got == want, ("%s (got %s, want %s)"):format(msg, tostring(got), tostring(want)))
  end

  local Util = require("src.online.net.Util")
  local LoopNet = require("src.online.net.LoopNet")
  local Transport = require("src.online.net.Transport")
  local Connector = require("src.online.net.Connector")
  local Config = require("src.online.hub.Config")
  local Codes = require("src.online.hub.Codes")
  local Conn = require("src.online.hub.Conn")
  local Hub = require("src.online.hub.Hub")
  local Log = require("src.online.hub.Log")

  local fakeT = 5000
  local realClock = Util.clock
  -- LoopNet machines have no real LAN address: under LOVE (luasocket
  -- present) the real one would ride in hub_join and mislead the punch
  local realLanIP = Util.lanIP
  Util.lanIP = function() return nil end
  Util.clock = function() return fakeT end
  local function tick(dt) fakeT = fakeT + (dt or 0.02) end
  local clock = function() return fakeT end
  local quiet = Log.new({ file = false, stdout = os.getenv("HUB_SELFTEST_VERBOSE") ~= nil })

  local function newHub(over, opts)
    local cfg = assert(Config.load(nil, over or {}))
    opts = opts or {}
    opts.log, opts.now, opts.memory, opts.noTcp = quiet, clock, true, true
    opts.noListen = opts.enetDriver == nil
    local hub = Hub.new(cfg, opts)
    return hub, cfg
  end

  local function first(conn, ty)
    for _, m in ipairs(conn:take()) do if m.type == ty then return m end end
    return nil
  end

  ---------------------------------------------------------------- config

  do
    local cfg = Config.load(nil, {})
    check(cfg ~= nil, "config: defaults load")
    eq(cfg and cfg.udpPort, 7778, "config: UDP port defaults to the TCP port")
    local bad, problems = Config.load(nil, { admin = { key = "short" } })
    check(bad == nil and problems and problems[1]:find("12 characters"), "config: short admin key refused")
    local t, err = Config.parse("return { name = os.getenv('X') }", "evil")
    check(t == nil and tostring(err):find("os"), "config: the file can't reach os/io (empty environment)")
    local p = Config.parse("name = 'A'\nport = 9000\n", "flat")
    check(p and p.name == "A" and p.port == 9000, "config: flat key = value files work")
    local c2 = Config.load(nil, { bogus = 1, relay = { bytesPerSecond = "lots" } })
    local warned = 0
    for _, w in ipairs(c2 and c2.warnings or {}) do
      if w:find("bogus") or w:find("bytesPerSecond") then warned = warned + 1 end
    end
    eq(warned, 2, "config: unknown keys and wrong types are reported")
    local c3 = Config.load(nil, { gts = { enabled = true } })
    check(c3 == nil, "config: a GTS without game data is refused")
    local c4 = Config.load(nil, { world = { enabled = true, port = 7778 } })
    check(c4 == nil, "config: world port clash refused")
  end

  ---------------------------------------------------------------- codes

  do
    local n = 0
    local codes = Codes.new({ rand = function() n = n + 7 return n end, now = clock })
    local a = codes:allocate({ x = 1 })
    local b = codes:allocate({ x = 2 })
    check(a and b and a ~= b and #a == 6, "codes: unique six-symbol codes")
    eq(Codes.normalize(" ab-c2 34 "), "ABC234", "codes: normalize")
    eq(Codes.normalize("ABC10O"), nil, "codes: 0/O/1 are not in the alphabet")
    check(codes:lookup(a:lower()).x == 1, "codes: lookup is case-blind")
    codes:release(a)
    local o, why = codes:lookup(a)
    check(o == nil and why == "expired", "codes: a released code answers expired")
  end

  ---------------------------------------------------------------- relay

  do
    local hub = newHub({ relay = { bytesPerSecond = 1000, burstBytes = 2000, queueBytes = 6000 } })
    assert(hub:start())
    local host, guest, third = Conn.test("10.0.0.1", fakeT), Conn.test("10.0.0.2", fakeT), Conn.test("10.0.0.3", fakeT)
    for _, c in ipairs({ host, guest, third }) do check(hub:accept(c), "relay: accept") end
    hub:message(host, { type = "host" })
    local hosted = first(host, "hosted")
    check(hosted and #hosted.code == 6, "relay: host -> hosted with a code")
    local code = hosted and hosted.code
    hub:message(host, { type = "hello", name = "RED" }, '{"type":"hello","name":"RED"}')
    hub:message(guest, { type = "join", code = "ZZZZZZ" })
    eq((first(guest, "join_error") or {}).reason, "not_found", "relay: unknown code")
    hub:message(guest, { type = "join", code = code:lower() })
    check(first(host, "paired") ~= nil, "relay: host told paired")
    local gmsgs = guest:take()
    eq(gmsgs[1] and gmsgs[1].type, "paired", "relay: guest told paired")
    tick() hub:update()
    local hello
    for _, m in ipairs(guest:take()) do if m.type == "hello" then hello = m end end
    eq(hello and hello.name, "RED", "relay: what the host sent before pairing reaches the guest")
    hub:message(third, { type = "join", code = code })
    eq((first(third, "join_error") or {}).reason, "full", "relay: a third player is refused")
    hub:message(guest, { type = "pick", index = 2 })
    tick() hub:update()
    eq((first(host, "pick") or {}).index, 2, "relay: guest -> host")
    -- the byte budget: 1000 B/s with a 2000 B burst
    local blob = string.rep("x", 900)
    for i = 1, 5 do hub:message(host, { type = "records", i = i, blob = blob }) end
    tick(0.001) hub:update()
    local got = #guest:take()
    check(got >= 1 and got <= 3, "relay: a burst over the budget waits (" .. got .. " of 5 now)")
    tick(3) hub:update()
    eq(#guest:take(), 5 - got, "relay: the rest arrives as the budget refills")
    for i = 1, 8 do hub:message(host, { type = "records", i = i, blob = blob }) end
    check(host.closed and guest.closed, "relay: a pair far over its queue is cut")
    hub:closed(host) hub:closed(guest)
    local r1 = Conn.test("10.0.0.4", fakeT)
    hub:accept(r1)
    hub:message(r1, { type = "join", code = code })
    eq((first(r1, "join_error") or {}).reason, "expired", "relay: a closed room's code answers expired")
    -- peer_gone
    local h2, g2 = Conn.test("10.0.0.5", fakeT), Conn.test("10.0.0.6", fakeT)
    hub:accept(h2) hub:accept(g2)
    hub:message(h2, { type = "host" })
    local c2 = first(h2, "hosted").code
    hub:message(g2, { type = "join", code = c2 })
    h2:take() g2:take()
    h2.closed = true
    hub:closed(h2)
    check(first(g2, "peer_gone") ~= nil and g2.closed, "relay: the guest hears peer_gone and is closed")
    -- an unjoined room expires
    local h3 = Conn.test("10.0.0.7", fakeT)
    hub:accept(h3)
    hub:message(h3, { type = "host" })
    tick(hub.cfg.relay.roomTtl + 1) hub:update()
    check(h3.closed, "relay: an unjoined room expires")
    eq(hub.relay.count, 0, "relay: no rooms left")
  end

  ---------------------------------------------------------------- tournaments

  do
    local hub = newHub()
    assert(hub:start())
    local A, B, C, D = Conn.test("10.1.0.1", fakeT), Conn.test("10.1.0.2", fakeT),
                       Conn.test("10.1.0.3", fakeT), Conn.test("10.1.0.4", fakeT)
    for _, c in ipairs({ A, B, C, D }) do hub:accept(c) end
    local party = { partySize = 1, partyMinLevel = 30, partyMaxLevel = 30 }
    local function with(t) local o = {} for k, v in pairs(party) do o[k] = v end for k, v in pairs(t) do o[k] = v end return o end
    hub:message(A, with({ type = "host_tournament", requiredPartySize = 2, name = "ALICE" }))
    local e = first(A, "tournament_host_error")
    check(e and e.reason == "party_ineligible" and e.requiredPartySize == 2, "tour: host's party checked")
    hub:message(A, with({ type = "host_tournament", requiredPartySize = 1, turnLimit = 6, name = "ALICE",
                          maxLevel = 50 }))
    local hosted = first(A, "tournament_hosted")
    check(hosted and #hosted.code == 6 and hosted.participating, "tour: hosted")
    local code = hosted.code
    hub:message(B, with({ type = "join_tournament", code = code, name = "BOB" }))
    hub:message(C, with({ type = "join_tournament", code = code, name = "BOB" }))
    hub:message(D, with({ type = "join_tournament", code = code, name = "DAN", partyMaxLevel = 70 }))
    eq((first(D, "tournament_join_error") or {}).reason, "party_ineligible", "tour: level cap enforced")
    local roster
    for _, m in ipairs(A:take()) do if m.type == "tournament_roster" then roster = m end end
    check(roster and #roster.players == 3 and roster.players[3] == "BOB2", "tour: roster, duplicate names made unique")
    B:take() C:take()
    hub:message(B, { type = "start_tournament" })
    check(#A.out == 0, "tour: only the creator starts")
    hub:message(A, { type = "start_tournament" })
    local function find(conn, ty)
      for _, m in ipairs(conn.out) do if m.type == ty then return m end end
    end
    local bu = find(A, "bracket_update")
    check(bu and bu.tournament.code == code and #bu.tournament.rounds[1].matches == 2, "tour: bracket, 2 matches in round 1")
    local ms = find(A, "match_start")
    check(ms and ms.role == "host" and ms.opponent == "BOB", "tour: ALICE hosts against BOB")
    eq((find(B, "match_start") or {}).role, "guest", "tour: BOB is the guest")
    check(find(C, "tournament_bye") ~= nil, "tour: BOB2 has a bye")
    check(find(C, "match_start_spectate") ~= nil, "tour: BOB2 watches")
    A:take() B:take() C:take()
    hub:message(A, { type = "hello", protocol = 3 }, '{"type":"hello","protocol":3}')
    eq(#B:take(), 0, "tour: traffic waits until the opponent has entered the match")
    hub:message(B, { type = "hello", protocol = 3 }, '{"type":"hello","protocol":3,"g":1}')
    eq((B:take()[1] or {}).type, "hello", "tour: held traffic delivered once the opponent says hello")
    eq((A:take()[1] or {}).type, "hello", "tour: and the opponent's hello goes straight through")
    local sp = C:take()[1]
    check(sp and sp.type == "spectate" and sp.side == "host" and sp.msg.type == "hello", "tour: onlookers get it wrapped")
    hub:message(A, { type = "tournament_result", result = "win" })
    hub:message(B, { type = "tournament_result", result = "lose" })
    local r2 = find(A, "match_start")
    check(r2 and r2.opponent == "BOB2" and r2.round == 2, "tour: round 2, ALICE vs BOB2")
    check(find(B, "match_start_spectate") ~= nil, "tour: the loser watches")
    A:take() B:take() C:take()
    -- BOB2 drops out mid-match: ALICE is told `forfeit` and wins
    C.closed = true
    hub:closed(C)
    check(find(A, "forfeit") ~= nil, "tour: a leaver's opponent gets forfeit")
    local over = find(A, "tournament_over")
    eq(over and over.champion, "ALICE", "tour: champion")
    check(find(B, "tournament_over") ~= nil, "tour: everyone hears who won")
    -- ALICE's battle ended on the forfeit: her late result is not misread
    hub:message(A, { type = "tournament_result", result = "win" })
    eq(hub.tours.count, 0, "tour: finished tournaments free their code")
    local E = Conn.test("10.1.0.5", fakeT)
    hub:accept(E)
    hub:message(E, with({ type = "join_tournament", code = code, name = "EVE" }))
    eq((first(E, "tournament_join_error") or {}).reason, "expired", "tour: an old code answers expired")
    -- undecided twice -> coin flip; creator leaving the lobby closes it
    local P, Q = Conn.test("10.1.0.6", fakeT), Conn.test("10.1.0.7", fakeT)
    hub:accept(P) hub:accept(Q)
    hub:message(P, with({ type = "host_tournament", requiredPartySize = 1, name = "P" }))
    local c2 = first(P, "tournament_hosted").code
    hub:message(Q, with({ type = "join_tournament", code = c2, name = "Q" }))
    hub:message(P, { type = "start_tournament" })
    P:take() Q:take()
    hub:message(P, { type = "tournament_result", result = "draw" })
    hub:message(Q, { type = "tournament_result", result = "draw" })
    check(find(P, "match_start") ~= nil, "tour: a draw is replayed")
    P:take()
    hub:message(P, { type = "tournament_result", result = "win" })
    tick(hub.cfg.tournaments.resultTimeout + 1) hub:update()
    eq((find(P, "tournament_over") or {}).champion, "P", "tour: one result + timeout decides")
    local L1, L2 = Conn.test("10.1.0.8", fakeT), Conn.test("10.1.0.9", fakeT)
    hub:accept(L1) hub:accept(L2)
    hub:message(L1, with({ type = "host_tournament", requiredPartySize = 1, name = "L1" }))
    local c3 = first(L1, "tournament_hosted").code
    hub:message(L2, with({ type = "join_tournament", code = c3, name = "L2" }))
    L1.closed = true
    hub:closed(L1)
    check(L2.closed, "tour: the creator leaving the lobby closes it")
  end

  ---------------------------------------------------------------- admin

  do
    local hub = newHub({ admin = { key = "correct horse battery" } })
    assert(hub:start())
    local local1, remote = Conn.test("127.0.0.1", fakeT), Conn.test("203.0.113.9", fakeT)
    hub:accept(local1) hub:accept(remote)
    hub:message(remote, { type = "hub_admin", key = "correct horse battery", cmd = "status" })
    eq((first(remote, "hub_admin_reply") or {}).ok, false, "admin: refused from another machine")
    hub:message(local1, { type = "hub_admin", key = "wrong", cmd = "status" })
    eq((first(local1, "hub_admin_reply") or {}).ok, false, "admin: wrong key refused")
    hub:message(local1, { type = "hub_admin", key = "correct horse battery", cmd = "status" })
    local r = first(local1, "hub_admin_reply")
    check(r and r.ok and r.result.name == "LINK HUB", "admin: status")
    hub:message(local1, { type = "hub_admin", key = "correct horse battery", cmd = "ban", arg = "203.0.113.9" })
    check(remote.closed, "admin: ban closes that address's connections")
    check(not hub:accept(Conn.test("203.0.113.9", fakeT)), "admin: a banned address can't connect")
    for _ = 1, Hub.ADMIN_FAILS do
      hub:message(local1, { type = "hub_admin", key = "nope", cmd = "status" })
    end
    check(local1.closed, "admin: repeated wrong keys lock the address out")
    local flood = Conn.test("10.2.0.1", fakeT)
    hub:accept(flood)
    for _ = 1, 400 do hub:message(flood, { type = "hub_ping" }) end
    check(#flood.out < 200 and hub.stats.limited > 0, "caps: a flooding connection is rate limited")
    local p = flood.out[1]
    check(p and p.type == "hub_pong" and p.name == "LINK HUB", "hub_ping answers hub_pong")
  end

  ---------------------------------------------------------------- rendezvous (L4) + ENet relay

  do
    local net = LoopNet.new()
    net:rule(function() return 0.03 end)
    local hub = newHub({ udpPort = 9000 }, { enetDriver = net:driver("192.0.2.50") })
    assert(hub:start())
    local function hostOn(ip, extra)
      local o = { port = 7777, driver = net:driver(ip), portMap = false, lanIp = ip }
      for k, v in pairs(extra or {}) do o[k] = v end
      return Connector.host(o)
    end
    local host = hostOn("198.51.100.20", { hub = "192.0.2.50:9000" })
    for _ = 1, 30 do tick() hub:update() host:update() end
    local ticket = host.info.hubTicket
    check(type(ticket) == "number" and ticket > 0 and ticket < 1048576, "rendezvous: host got a 20-bit ticket")
    local fields = host:inviteFields()
    eq(fields.hub and fields.hub.ticket, ticket, "rendezvous: the invite carries it")
    local job = Connector.join({ hub = fields.hub, nonce = fields.nonce },
                               { driver = net:driver("203.0.113.40") })
    for _ = 1, 800 do
      tick() hub:update() host:update() job:update()
      if job.state ~= "trying" then break end
    end
    for _ = 1, 10 do tick() hub:update() host:update() end
    eq(job.state, "connected", "rendezvous: joiner connected")
    eq(job.path, "hub", "rendezvous: path = hub (direct after the introduction)")
    eq(host.state, "connected", "rendezvous: host connected")
    eq(hub.rdv.stats.introduced, 1, "rendezvous: one introduction")
    job.channel:send({ type = "hello", who = "guest" })
    local heard
    for _ = 1, 40 do
      tick() hub:update() job.channel:update() host.channel:update()
      for _, m in ipairs(host.channel:poll()) do if m.type == "hello" then heard = m.who end end
      if heard then break end
    end
    eq(heard, "guest", "rendezvous: traffic flows directly")
    for _ = 1, 20 do tick() hub:update() end
    eq(hub.rdv.count, 0, "rendezvous: the ticket is gone once the host left the hub")
    local bad = Connector.join({ hub = { ip = "192.0.2.50", port = 9000, ticket = 5 }, nonce = 1 },
                               { driver = net:driver("203.0.113.41") })
    for _ = 1, 400 do tick() hub:update() bad:update() if bad.state ~= "trying" then break end end
    check(bad.state == "failed" and tostring(bad.reason):find("not_found"), "rendezvous: unknown ticket refused")

    -- the same relay rooms over ENet (no TCP): host on one Transport, join on another
    local function client(ip)
      local t = Transport.new({ driver = net:driver(ip) })
      assert(t:listen())
      local id = t:connect("192.0.2.50:9000", 0)
      return t:channelFor(id, { owns = true })
    end
    local a, b = client("198.51.100.30"), client("203.0.113.31")
    a:send({ type = "host" })
    local code
    for _ = 1, 40 do
      tick() hub:update() a:update()
      for _, m in ipairs(a:poll()) do if m.type == "hosted" then code = m.code end end
      if code then break end
    end
    check(code ~= nil, "enet relay: hosted")
    b:send({ type = "join", code = code })
    local paired, echo = 0, nil
    for _ = 1, 60 do
      tick() hub:update() a:update() b:update()
      for _, m in ipairs(a:poll()) do if m.type == "paired" then paired = paired + 1 end end
      for _, m in ipairs(b:poll()) do
        if m.type == "paired" then paired = paired + 1 b:send({ type = "party", n = 2 }) end
      end
      if paired >= 2 then break end
    end
    eq(paired, 2, "enet relay: both paired")
    for _ = 1, 40 do
      tick() hub:update() a:update() b:update()
      for _, m in ipairs(a:poll()) do if m.type == "party" then echo = m.n end end
      if echo then break end
    end
    eq(echo, 2, "enet relay: guest -> host through the hub")
    -- simulated carrier-grade NAT: the introduction leads nowhere
    local hub2 = newHub({ udpPort = 9100, test = { simulateBlockedPunch = true } },
                        { enetDriver = net:driver("192.0.2.60") })
    assert(hub2:start())
    local h2 = hostOn("198.51.100.21", { hub = "192.0.2.60:9100" })
    for _ = 1, 30 do tick() hub2:update() h2:update() end
    local f2 = h2:inviteFields()
    local j2 = Connector.join({ hub = f2.hub, nonce = f2.nonce },
                              { driver = net:driver("203.0.113.42"), timeouts = { hub = 2 } })
    for _ = 1, 600 do tick() hub2:update() h2:update() j2:update() if j2.state ~= "trying" then break end end
    eq(j2.state, "failed", "blocked punch: no direct path (as behind carrier NAT)")
    hub:stop() hub2:stop()
    h2:close() host:close()
  end

  ---------------------------------------------------------------- GTS (with game data)

  local dataDir = os.getenv("POKEPORT_DATA_DIR")
  if dataDir and dataDir ~= "" then
    local GameData = require("src.online.hub.GameData")
    local GtsStore = require("src.online.gts.GtsStore")
    local GtsPools = require("src.online.gts.GtsPools")
    local game = GameData.guessGame(dataDir)
    local pool = game and GtsPools.poolFor(game)
    if not pool then
      print("selftest: skip GTS (can't tell the game of " .. dataDir .. ")")
    else
      local data = assert(GameData.load(dataDir, game, "lean"))
      local hub = newHub({ gts = { enabled = true, pools = { [pool] = { [game] = dataDir } } } },
                         { datasets = { [game] = data }, gtsStore = GtsStore.new(GtsStore.memoryFs()) })
      assert(hub:start())
      local MonCodec = require("src.online.MonCodec")
      local Pokemon = require("src.pokemon.Pokemon")
      local species
      for id, def in pairs(data.pokemon) do
        if type(def) == "table" and def.baseStats and tonumber(def.dex or id) == 25 then species = id end
      end
      species = species or 25
      GameData.use(game)
      local seed = 99
      local function rng(lo, hi)
        seed = (seed * 1103515245 + 12345) % 2147483648
        if not lo then return (seed % 1000000) / 1000000 end
        if not hi then lo, hi = 1, lo end
        return lo + seed % (hi - lo + 1)
      end
      local mon = Pokemon.new(data, species, 20, rng)
      local packed = MonCodec.pack(data, mon)
      local c = Conn.test("10.3.0.1", fakeT)
      hub:accept(c)
      hub:message(c, { type = "gts_hello", player = "selftest-1", name = "TEST", game = game, tid = 1 })
      local w = first(c, "gts_welcome")
      check(w and w.pool == pool, "gts: welcome to pool " .. tostring(pool))
      hub:message(c, { type = "gts_deposit", token = "tok-0001", mon = packed, want = { dex = 1, gender = "any", band = 0 } })
      local d = first(c, "gts_deposited")
      check(d and d.id, "gts: a legal deposit is taken")
      local bad = MonCodec.pack(data, Pokemon.new(data, species, 20, rng))
      bad.level = 150
      local c2 = Conn.test("10.3.0.2", fakeT)
      hub:accept(c2)
      hub:message(c2, { type = "gts_hello", player = "selftest-2", name = "CHEAT", game = game, tid = 2 })
      c2:take()
      hub:message(c2, { type = "gts_deposit", token = "tok-0002", mon = bad, want = { dex = 1, gender = "any", band = 0 } })
      local r = first(c2, "gts_refused")
      check(r and r.code == "invalid", "gts: an impossible mon is refused (" .. tostring(r and r.text) .. ")")
      local other = (pool == "bw") and "platinum" or "black"
      local c3 = Conn.test("10.3.0.3", fakeT)
      hub:accept(c3)
      hub:message(c3, { type = "gts_hello", player = "selftest-3", name = "OTHER", game = other, tid = 3 })
      eq((first(c3, "gts_denied") or {}).code, "pool", "gts: another pool's game is denied")
      local hub0 = newHub()
      assert(hub0:start())
      local c4 = Conn.test("10.3.0.4", fakeT)
      hub0:accept(c4)
      hub0:message(c4, { type = "gts_hello", player = "selftest-4", game = game })
      eq((first(c4, "gts_denied") or {}).code, "pool", "gts: a hub without a GTS says so")
    end
  else
    print("selftest: GTS section skipped (set POKEPORT_DATA_DIR to a game cache)")
  end

  Util.clock = realClock
  Util.lanIP = realLanIP
  print(("LINK HUB SELFTEST: %d passed, %d failed"):format(passed, failed))
  if failed == 0 then print("LINK HUB SELFTEST: ALL PASSED") end
  return failed == 0
end

if HUB_SELFTEST_AS_MODULE then return T end
local ok = T.run()
if not ok then error("link hub selftest failed", 0) end
return T
