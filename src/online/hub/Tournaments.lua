-- Tournaments over the pokeserver protocol, served by the hub.
--
-- The client is src/link/Tournament.lua (with LinkBattle as the match and
-- LinkBattle.newSpectator for onlookers).  The server side, as that client
-- expects it:
--
--   -> host_tournament { turnLimit, requiredPartySize, minLevel, maxLevel,
--                        forceLevel, participating, name, partySize,
--                        partyMinLevel, partyMaxLevel }
--   <- tournament_hosted { code, turnLimit, forceLevel, participating }
--    | tournament_host_error { reason = "party_ineligible", requiredPartySize,
--                              minLevel, maxLevel }
--   -> join_tournament { code, name, partySize, partyMinLevel, partyMaxLevel }
--   <- tournament_join_error { reason = "not_found"|"already_started"|"expired"
--                              |"party_ineligible"|"full", ... }
--   <- tournament_roster { players, spectators, turnLimit, requiredPartySize,
--                          minLevel, maxLevel, forceLevel }        (to everyone)
--   -> start_tournament                          (creator, two players or more)
--   <- bracket_update { tournament = { code, rounds = { { round, matches =
--        { { a, b, bye, state = "pending"|"live"|"done", winner } } } } } }
--   <- match_start { role = "host"|"guest", opponent, round, turnLimit }
--   <- match_start_spectate { round, playerHost, playerGuest }   (the others)
--   <- tournament_bye { round }
--      during a match, whatever one player sends reaches the other, and every
--      onlooker gets { type = "spectate", side = "host"|"guest", msg = ... }
--   -> tournament_result { result = "win"|"lose"|"draw" }   (each player)
--   <- tournament_over { champion }
--
-- Single elimination, matches one at a time in bracket order, the creator's
-- party rule is "exactly requiredPartySize Pokemon inside the level range".
-- A player who leaves mid-match loses it: the opponent is sent `forfeit`
-- (their LinkBattle ends as a win).  Disagreeing or drawn results replay the
-- match once; a second draw is settled by a coin flip.

local Tournaments = {}
Tournaments.__index = Tournaments

Tournaments.TYPES = { host_tournament = true, join_tournament = true,
                      start_tournament = true, tournament_result = true }

function Tournaments.new(opts)
  return setmetatable({
    codes = opts.codes, log = opts.log, cfg = opts.cfg, now = opts.now,
    rand = opts.rand or function() return math.random(0, 2147483646) end,
    list = {},          -- code -> tournament
    count = 0,
    stats = { hosted = 0, finished = 0, matches = 0 },
  }, Tournaments)
end

local function int(v, lo, hi)
  v = tonumber(v)
  if not v or v ~= v then return nil end
  v = math.floor(v)
  if v < lo or v > hi then return nil end
  return v
end

local function cleanName(v)
  if type(v) ~= "string" then return "PLAYER" end
  local s = v:gsub("[%z\1-\31\127]", ""):sub(1, 24)
  if s == "" then return "PLAYER" end
  return s
end

local function eligible(st, msg)
  local size = int(msg.partySize, 0, 6) or 0
  local lo = int(msg.partyMinLevel, 0, 100) or 0
  local hi = int(msg.partyMaxLevel, 0, 100) or 0
  if size ~= st.requiredPartySize then return false end
  if st.minLevel and lo < st.minLevel then return false end
  if st.maxLevel and hi > st.maxLevel then return false end
  return true
end

local function ineligible(st, kind)
  return { type = kind, reason = "party_ineligible", requiredPartySize = st.requiredPartySize,
           minLevel = st.minLevel, maxLevel = st.maxLevel }
end

-- every connection of a tournament that is still open
local function everyone(t)
  local out = {}
  for _, p in ipairs(t.players) do if not p.conn.closed then out[#out + 1] = p.conn end end
  for _, s in ipairs(t.spectators) do if not s.conn.closed then out[#out + 1] = s.conn end end
  return out
end

local function broadcast(t, msg, except)
  for _, c in ipairs(everyone(t)) do
    if c ~= except then c:send(msg) end
  end
end

local function names(list)
  local out = {}
  for _, p in ipairs(list) do out[#out + 1] = p.name end
  return out
end

function Tournaments:roster(t)
  local st = t.settings
  broadcast(t, { type = "tournament_roster", players = names(t.players),
                 spectators = names(t.spectators), turnLimit = st.turnLimit,
                 requiredPartySize = st.requiredPartySize, format = st.format, minLevel = st.minLevel,
                 maxLevel = st.maxLevel, forceLevel = st.forceLevel })
end

local function uniqueName(t, want)
  local taken = {}
  for _, p in ipairs(t.players) do taken[p.name] = true end
  for _, s in ipairs(t.spectators) do taken[s.name] = true end
  if not taken[want] then return want end
  for i = 2, 99 do
    local n = want:sub(1, 22) .. tostring(i)
    if not taken[n] then return n end
  end
  return want .. "?"
end

---------------------------------------------------------------- lobby

function Tournaments:host(conn, msg)
  if conn.role then return end
  if self.count >= self.cfg.max then
    conn:send({ type = "tournament_host_error", reason = "full" })
    return
  end
  local st = {
    turnLimit = int(msg.turnLimit, 1, 300) or 6,
    requiredPartySize = int(msg.requiredPartySize, 1, 6) or 3,
    format = msg.format == "double" and "double" or nil,
    minLevel = int(msg.minLevel, 1, 100),
    maxLevel = int(msg.maxLevel, 1, 100),
    forceLevel = int(msg.forceLevel, 1, 100),
  }
  local participating = msg.participating ~= false
  if participating and not eligible(st, msg) then
    conn:send(ineligible(st, "tournament_host_error"))
    return
  end
  local t = { creator = conn, settings = st, players = {}, spectators = {}, state = "lobby",
              created = self.now(), rounds = {} }
  local code = self.codes:allocate({ kind = "tournament", t = t })
  if not code then
    conn:send({ type = "tournament_host_error", reason = "full" })
    return
  end
  t.code = code
  self.list[code] = t
  self.count = self.count + 1
  self.stats.hosted = self.stats.hosted + 1
  local entry = { conn = conn, name = cleanName(msg.name) }
  if participating then t.players[1] = entry else t.spectators[1] = entry end
  conn.role, conn.tournament, conn.entry = "tournament", t, entry
  conn:send({ type = "tournament_hosted", code = code, turnLimit = st.turnLimit,
              forceLevel = st.forceLevel, participating = participating })
  self.log:info("tournament %s: created by %s (%d mons, turn %ds%s)", code, entry.name,
                st.requiredPartySize, st.turnLimit, participating and "" or ", organizer only")
end

function Tournaments:join(conn, msg)
  if conn.role then return end
  local owner, why = self.codes:lookup(msg.code)
  local t = owner and owner.kind == "tournament" and owner.t or nil
  if not t then
    conn:send({ type = "tournament_join_error", reason = why == "expired" and "expired" or "not_found" })
    return
  end
  if t.state ~= "lobby" then
    conn:send({ type = "tournament_join_error", reason = "already_started" })
    return
  end
  if #t.players >= self.cfg.maxPlayers then
    conn:send({ type = "tournament_join_error", reason = "full" })
    return
  end
  if not eligible(t.settings, msg) then
    conn:send(ineligible(t.settings, "tournament_join_error"))
    return
  end
  local entry = { conn = conn, name = uniqueName(t, cleanName(msg.name)) }
  t.players[#t.players + 1] = entry
  conn.role, conn.tournament, conn.entry = "tournament", t, entry
  self.log:info("tournament %s: %s joined (%d players)", t.code, entry.name, #t.players)
  self:roster(t)
end

---------------------------------------------------------------- bracket

function Tournaments:bracket(t)
  local rounds = {}
  for _, r in ipairs(t.rounds) do
    local ms = {}
    for _, m in ipairs(r.matches) do
      ms[#ms + 1] = { a = m.pa and m.pa.name, b = m.pb and m.pb.name, bye = m.bye or nil,
                      state = m.state, winner = m.winner and m.winner.name or nil }
    end
    rounds[#rounds + 1] = { round = r.round, matches = ms }
  end
  broadcast(t, { type = "bracket_update", tournament = { code = t.code, rounds = rounds } })
end

function Tournaments:buildRound(t, entrants)
  local r = { round = #t.rounds + 1, matches = {} }
  t.rounds[#t.rounds + 1] = r
  local i = 1
  while i <= #entrants do
    local a, b = entrants[i], entrants[i + 1]
    if b then
      r.matches[#r.matches + 1] = { pa = a, pb = b, state = "pending", results = {}, replays = 0 }
    else
      r.matches[#r.matches + 1] = { pa = a, bye = true, state = "done", winner = a }
      if not a.conn.closed then a.conn:send({ type = "tournament_bye", round = r.round }) end
    end
    i = i + 2
  end
  return r
end

function Tournaments:start(conn)
  local t = conn.tournament
  if not t or t.creator ~= conn or t.state ~= "lobby" then return end
  if #t.players < 2 then return end
  t.state = "running"
  self.log:info("tournament %s: started with %d players", t.code, #t.players)
  self:buildRound(t, t.players)
  self:bracket(t)
  self:advance(t)
end

function Tournaments:startMatch(t, r, m)
  m.state = "live"
  m.results, m.firstAt = {}, nil
  m.ready, m.held = {}, { a = {}, b = {} }
  t.live = m
  m.round = r.round
  self.stats.matches = self.stats.matches + 1
  self:bracket(t)
  local st = t.settings
  m.pa.conn:send({ type = "match_start", role = "host", opponent = m.pb.name, round = r.round,
                   turnLimit = st.turnLimit })
  m.pb.conn:send({ type = "match_start", role = "guest", opponent = m.pa.name, round = r.round,
                   turnLimit = st.turnLimit })
  local spec = { type = "match_start_spectate", round = r.round, playerHost = m.pa.name,
                 playerGuest = m.pb.name }
  for _, c in ipairs(everyone(t)) do
    if c ~= m.pa.conn and c ~= m.pb.conn then c:send(spec) end
  end
  self.log:info("tournament %s: round %d, %s vs %s", t.code, r.round, m.pa.name, m.pb.name)
end

function Tournaments:finishMatch(t, m, winner, why)
  m.state = "done"
  m.winner = winner
  t.live = nil
  local loser = (winner == m.pa) and m.pb or m.pa
  loser.out = true
  self.log:info("tournament %s: %s beat %s (%s)", t.code, winner.name, loser.name, why)
  self:bracket(t)
  self:advance(t)
end

-- run the next match, close the round, or end the tournament
function Tournaments:advance(t)
  if t.state ~= "running" or t.live then return end
  local r = t.rounds[#t.rounds]
  for _, m in ipairs(r.matches) do
    if m.state == "pending" then
      local aGone, bGone = m.pa.conn.closed, m.pb.conn.closed
      if aGone or bGone then
        -- a walkover (both gone: the host side goes through)
        local winner = (aGone and not bGone) and m.pb or m.pa
        m.state = "done"
        m.winner = winner
        local loser = winner == m.pa and m.pb or m.pa
        loser.out = true
        self.log:info("tournament %s: %s goes through (opponent left)", t.code, winner.name)
      else
        self:startMatch(t, r, m)
        return
      end
    end
  end
  local winners = {}
  for _, m in ipairs(r.matches) do winners[#winners + 1] = m.winner end
  if #winners <= 1 then
    t.state = "over"
    local champ = winners[1]
    self:bracket(t)
    broadcast(t, { type = "tournament_over", champion = champ and champ.name or nil })
    self.stats.finished = self.stats.finished + 1
    self.log:info("tournament %s: over, champion %s", t.code, champ and champ.name or "?")
    self:retire(t)
    return
  end
  self:buildRound(t, winners)
  self:bracket(t)
  self:advance(t)
end

-- the code stops answering; the tournament object lives on until its last
-- connection goes (they may still be reading the final screen)
function Tournaments:retire(t)
  if t.retired then return end
  t.retired = true
  if self.list[t.code] == t then
    self.list[t.code] = nil
    self.count = self.count - 1
    self.codes:release(t.code)
  end
end

---------------------------------------------------------------- matches

local function decide(m)
  local ra, rb = m.results.a, m.results.b
  if ra == "win" and rb ~= "win" then return m.pa end
  if rb == "win" and ra ~= "win" then return m.pb end
  if ra == "lose" and rb == nil then return m.pb end
  if rb == "lose" and ra == nil then return m.pa end
  if ra == "lose" and rb == "draw" then return m.pb end
  if rb == "lose" and ra == "draw" then return m.pa end
  return nil -- both win, both lose, a draw, or nothing yet
end

function Tournaments:settle(t, m, timedOut)
  -- a side that has not reported yet will, later, about THIS match: that
  -- answer must not be read as one for its next match
  if not m.results.a then m.pa.staleResult = true end
  if not m.results.b then m.pb.staleResult = true end
  local winner = decide(m)
  if winner then return self:finishMatch(t, m, winner, timedOut and "one result, timed out" or "results") end
  if m.replays < 1 then
    m.replays = m.replays + 1
    m.state = "pending"
    t.live = nil
    self.log:info("tournament %s: %s vs %s undecided, replaying", t.code, m.pa.name, m.pb.name)
    return self:advance(t)
  end
  local coin = (self.rand() % 2 == 0) and m.pa or m.pb
  return self:finishMatch(t, m, coin, "undecided twice: coin flip")
end

function Tournaments:result(conn, msg)
  if conn.entry and conn.entry.staleResult then
    conn.entry.staleResult = nil
    return
  end
  local t = conn.tournament
  local m = t and t.live
  if not m then return end
  local side = (conn == m.pa.conn) and "a" or (conn == m.pb.conn) and "b" or nil
  if not side or m.results[side] then return end
  local r = msg.result
  if r ~= "win" and r ~= "lose" and r ~= "draw" then r = "draw" end
  m.results[side] = r
  m.firstAt = m.firstAt or self.now()
  if m.results.a and m.results.b then self:settle(t, m, false) end
end

-- match traffic: to the opponent as is, to everyone else wrapped
function Tournaments:relay(conn, msg, line)
  local t = conn.tournament
  local m = t and t.live
  if not m then
    if t then self.log:debug("tournament %s: %s outside a match dropped", t.code, tostring(msg.type)) end
    return
  end
  local side, other
  if conn == m.pa.conn then side, other = "host", m.pb.conn
  elseif conn == m.pb.conn then side, other = "guest", m.pa.conn
  else
    self.log:debug("tournament %s: %s from an onlooker dropped", t.code, tostring(msg.type))
    return
  end
  -- Tournament.lua reads the opponent's hello only once it has itself
  -- entered the match (its hello is sent from enterMatch); anything that
  -- reaches it earlier -- in the same batch as match_start, or while it is
  -- still watching the previous match -- goes to handleMessage and is lost.
  -- So a player's traffic is held until its opponent has said hello.
  local mine, theirs = side == "host" and "a" or "b", side == "host" and "b" or "a"
  if msg.type == "hello" and not m.ready[mine] then
    m.ready[mine] = true
    for _, e in ipairs(m.held[mine]) do
      if not conn.closed then conn:forward(e.msg, e.line) end
    end
    m.held[mine] = {}
  end
  if other.closed then
    -- gone: nothing to do
  elseif m.ready[theirs] then
    other:forward(msg, line)
  elseif #m.held[theirs] < 64 then
    m.held[theirs][#m.held[theirs] + 1] = { msg = msg, line = line }
  end
  self.log:debug("tournament %s: %s %s -> %s", t.code, side, tostring(msg.type),
                 other.closed and "(gone)" or (m.ready[theirs] and "opponent" or "held"))
  local wrapped = { type = "spectate", side = side, msg = msg }
  for _, c in ipairs(everyone(t)) do
    if c ~= m.pa.conn and c ~= m.pb.conn then c:send(wrapped) end
  end
end

---------------------------------------------------------------- dispatch

function Tournaments:handle(conn, msg, line)
  local ty = msg.type
  if ty == "host_tournament" then
    if not conn.role then self:host(conn, msg) end
    return true
  elseif ty == "join_tournament" then
    if not conn.role then self:join(conn, msg) end
    return true
  end
  if conn.role ~= "tournament" then return false end
  if ty == "start_tournament" then
    self:start(conn)
  elseif ty == "tournament_result" then
    self:result(conn, msg)
  else
    self:relay(conn, msg, line)
  end
  return true
end

function Tournaments:closed(conn)
  local t = conn.tournament
  if not t then return end
  local entry = conn.entry
  if t.state == "lobby" then
    if conn == t.creator then
      self.log:info("tournament %s: creator left, closed", t.code)
      for _, c in ipairs(everyone(t)) do c:close("tournament closed") end
      t.state = "over"
      self:retire(t)
    else
      for i, p in ipairs(t.players) do if p == entry then table.remove(t.players, i) break end end
      for i, s in ipairs(t.spectators) do if s == entry then table.remove(t.spectators, i) break end end
      self:roster(t)
    end
  elseif t.state == "running" then
    local m = t.live
    if m and (entry == m.pa or entry == m.pb) then
      local winner = entry == m.pa and m.pb or m.pa
      local side = winner == m.pa and "host" or "guest"
      if not m.results[winner == m.pa and "a" or "b"] then winner.staleResult = true end
      if not winner.conn.closed then winner.conn:send({ type = "forfeit" }) end
      local wrapped = { type = "spectate", side = side == "host" and "guest" or "host",
                        msg = { type = "forfeit" } }
      for _, c in ipairs(everyone(t)) do
        if c ~= m.pa.conn and c ~= m.pb.conn then c:send(wrapped) end
      end
      self:finishMatch(t, m, winner, "opponent disconnected")
    end
  end
  if #everyone(t) == 0 then
    if t.state ~= "over" then self.log:info("tournament %s: everyone left", t.code) end
    t.state = "over"
    self:retire(t)
  end
end

function Tournaments:update()
  local now = self.now()
  for code, t in pairs(self.list) do
    if t.state == "lobby" and now - t.created > self.cfg.lobbyTtl then
      self.log:info("tournament %s: never started, closed", code)
      for _, c in ipairs(everyone(t)) do c:close("tournament expired") end
      t.state = "over"
      self:retire(t)
    elseif t.state == "running" and t.live and t.live.firstAt
           and now - t.live.firstAt > self.cfg.resultTimeout then
      self:settle(t, t.live, true)
    end
  end
end

function Tournaments:snapshot()
  local out = {}
  for code, t in pairs(self.list) do
    out[#out + 1] = { code = code, state = t.state, players = #t.players,
                      round = #t.rounds, live = t.live and (t.live.pa.name .. " vs " .. t.live.pb.name) or nil }
  end
  table.sort(out, function(a, b) return a.code < b.code end)
  return out
end

return Tournaments
