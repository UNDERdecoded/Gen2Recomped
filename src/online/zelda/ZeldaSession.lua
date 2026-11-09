-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A ZELDA ROOM: 2-4 players of ONE Zelda game, on the same transport the
-- Pokemon link uses (src/online/net: Connector ladder, hub rendezvous,
-- relay), shaped as a STAR -- the room's host has one channel per guest and
-- relays between them, which is what NAT traversal can actually give four
-- phones (MultiNet does the same for the multi battles).
--
-- What a game gets (through ZeldaRuntime, or directly in tests):
--
--   s:update(dt)                 pump; call every frame
--   for msg in s:messages() do   { kind = "event"|"snapshot"|"join"|"leave"|
--                                  "closed", peer = id, data = ... }
--   s:sendEvent(tbl)             RELIABLE, ordered, to every other player
--   s:sendEventTo(id, tbl)       reliable, to one player
--   s:sendSnapshot(tbl)          UNRELIABLE latest-wins state (<= ~400 bytes
--                                of JSON; larger goes reliable), to everyone
--   s:tick()                     the SHARED tick (host epoch, GBA 59.7275 Hz):
--                                every player reads within ~1 tick of the host
--   s.localId                    1 = the host, 2..4 guests (also the colour:
--                                1 green, 2 red, 3 blue, 4 purple)
--   s:players()                  { {id, name, color, isHost, me}, ... }
--   s:localIndex()               = localId
--   s.isHost, s.state            "joining" | "open" | "closed"
--   s:close(reason)              leave (guest) or close the room (host)
--
-- HOST LEAVING is a clean close, not a migration: every guest gets
-- { kind = "closed", data = { reason = "The host left." } }. A star has no
-- link between guests to migrate onto, and asking three NATs to re-punch to a
-- new host mid-game fails more often than it works. Guests leaving and
-- (re)joining mid-game are normal events.
--
-- WHO MAY JOIN: the joiner's hello must say series "zelda", the SAME game
-- id and the same Zelda protocol. Anything else is refused with a reason --
-- a Pokemon game typing a Zelda room's code gets the host's hello back (so
-- its own LinkState shows CAN'T LINK via CompatRules' cross-series rule)
-- and the channel closes; a Zelda game reaching a Pokemon host sees a
-- Pokemon hello and stops with "That code is for a Pokemon game."
--
-- WIRE (all JSON objects, Wire-checked; types <= 32 chars):
--   G->H hello  { protocol, engineVersion, series="zelda", game, family,
--                 zproto, name }                       (Handshake-shaped)
--   H->G z_welcome { id, hostId, players, tick, game, max }
--   H->G z_refuse  { reason }              H->* z_join { player } / z_leave
--   *->H z_ev { data, to? }                H->* z_ev { from, data }
--   *->H z_snap { tick, data } (channel 1) H->* z_snap { from, tick, data }
--   G->H z_ping { t }                      H->G z_pong { t, tick }
--   G->H z_bye { reason }                  H->* z_close { reason }

local Session = {}
Session.__index = Session

Session.PROTO = 1
Session.MAX_PLAYERS = 4
Session.TICK_HZ = 16777216 / 280896
Session.PING_EVERY = 1.0      -- guest -> host clock/rtt probe, seconds
Session.TIMEOUT = 12          -- silence before a peer is dropped, seconds
Session.SNAP_MAX = 400        -- bytes of JSON before a snapshot goes reliable
Session.HELLO_WAIT = 10       -- seconds a guest waits for the welcome
Session.COLORS = {
  { 0.20, 0.75, 0.30 },  -- 1 green
  { 0.90, 0.25, 0.25 },  -- 2 red
  { 0.25, 0.45, 0.95 },  -- 3 blue
  { 0.70, 0.35, 0.90 },  -- 4 purple
}

local function now(self)
  if self and self.clock then return self.clock() end
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function engineVersion()
  local ok, V = pcall(require, "src.core.Version")
  return ok and V and V.engine or "0"
end

local function linkProtocol()
  local ok, V = pcall(require, "src.core.Version")
  return ok and V and tonumber(V.linkProtocol) or 3
end

-- The hello this side sends: Handshake-shaped, so a Pokemon LinkState that
-- receives it computes a refusal (CompatRules cross_series) instead of
-- waiting forever.
function Session.hello(game, name)
  return {
    type = "hello",
    protocol = linkProtocol(),
    engineVersion = engineVersion(),
    series = "zelda",
    game = game,
    family = "zelda:" .. tostring(game),
    zproto = Session.PROTO,
    name = tostring(name or "LINK"):sub(1, 16),
    features = { "zelda" },
  }
end

-- Does a hello we received let that player into our room? ok, reason
function Session.admits(myGame, hello)
  if type(hello) ~= "table" then return false, "No hello." end
  if hello.series ~= "zelda" then
    return false, "That is a Pokemon game. Zelda rooms are for Zelda players only."
  end
  if hello.game ~= myGame then
    local function nameOf(id)
      local okG, GV = pcall(require, "src.core.GameVersion")
      local info = okG and GV.info(id)
      return info and (info.launcherName or info.displayName) or tostring(id)
    end
    return false, ("That room is playing %s. You are playing %s."):format(nameOf(myGame), nameOf(hello.game))
  end
  if tonumber(hello.zproto) ~= Session.PROTO then
    return false, "The other game is a different version of the app. Update both."
  end
  local function major(v) return tostring(v or ""):match("^(%d+)") end
  if major(hello.engineVersion) ~= major(engineVersion()) then
    return false, "The other game is a different version of the app. Update both."
  end
  return true
end

local function base(opts)
  local self = setmetatable({}, Session)
  self.game = assert(opts.game, "game id")
  self.name = opts.name or "LINK"
  self.clock = opts.clock
  self.inbox = {}
  self.peers = {}        -- id -> { id, name, ch, lastSeen }   (host)
  self.roster = {}       -- id -> { id, name }
  self.maxPlayers = math.max(2, math.min(Session.MAX_PLAYERS, tonumber(opts.maxPlayers) or 4))
  self.hello = Session.hello(self.game, self.name)
  self.lastSeq = 0
  self.stats = { sentEv = 0, sentSnap = 0, gotEv = 0, gotSnap = 0 }
  return self
end

local function push(self, kind, peer, data)
  self.inbox[#self.inbox + 1] = { kind = kind, peer = peer, data = data }
end

-- Which channel a snapshot goes on: 1 (unreliable, Wire caps it at 512
-- bytes) when it fits with room to spare, else 2 (reliable bulk) so a big
-- one is late rather than lost.
local function snapChannel(msg)
  local ok, Json = pcall(require, "src.link.Json")
  if not ok then return 2 end
  local okE, s = pcall(Json.encode, msg)
  if not (okE and type(s) == "string") then return 2 end
  return #s <= Session.SNAP_MAX and 1 or 2
end

-- --------------------------------------------------------------- host

-- opts: game, name, maxPlayers, source (MultiNet-style `take()` of new
-- channels: a Connector host's transport, a loopback, a list), clock
function Session.host(opts)
  local self = base(opts)
  self.isHost = true
  self.localId = 1
  self.hostId = 1
  self.state = "open"
  self.source = opts.source
  self.pending = {}
  self.epoch = now(self)
  self.roster[1] = { id = 1, name = self.name }
  self.lastClock = 0
  return self
end

function Session:addSource(src) self.source = src end

local function freeId(self)
  for id = 2, self.maxPlayers do
    if not self.roster[id] then return id end
  end
  return nil
end

function Session:rosterList()
  local out = {}
  for id = 1, Session.MAX_PLAYERS do
    local r = self.roster[id]
    if r then out[#out + 1] = { id = id, name = r.name } end
  end
  return out
end

local function send(ch, msg, channel)
  if ch and not ch.closed then pcall(ch.send, ch, msg, channel) end
end

function Session:_broadcast(msg, except, channel)
  for id, p in pairs(self.peers) do
    if id ~= except then send(p.ch, msg, channel) end
  end
end

function Session:_admit(p, hello)
  local ok, why = Session.admits(self.game, hello)
  local id = ok and freeId(self)
  if ok and not id then ok, why = false, "The room is full." end
  if not ok then
    -- a Pokemon game reads our hello and refuses on its side too
    if type(hello) ~= "table" or hello.series ~= "zelda" then send(p.ch, self.hello) end
    send(p.ch, { type = "z_refuse", reason = why })
    p.refused = now(self)
    return false
  end
  local name = tostring(hello.name or ("PLAYER " .. id)):sub(1, 16)
  self.peers[id] = { id = id, name = name, ch = p.ch, lastSeen = now(self) }
  self.roster[id] = { id = id, name = name }
  send(p.ch, { type = "z_welcome", id = id, hostId = 1, players = self:rosterList(),
               tick = self:tick(), game = self.game, max = self.maxPlayers })
  self:_broadcast({ type = "z_join", player = { id = id, name = name } }, id)
  push(self, "join", id, { name = name })
  return true
end

function Session:_dropPeer(id, reason)
  local p = self.peers[id]
  if not p then return end
  self.peers[id] = nil
  self.roster[id] = nil
  if p.ch and not p.ch.closed then pcall(p.ch.close, p.ch) end
  self:_broadcast({ type = "z_leave", id = id, reason = reason })
  push(self, "leave", id, { name = p.name, reason = reason })
end

function Session:_hostUpdate()
  local t = now(self)
  -- the Connector host job behind a real room: router lease, LAN beacon, hub
  if self.hostJob and self.hostJob.update then pcall(self.hostJob.update, self.hostJob) end
  if self.source and self.source.take then
    local ok, fresh = pcall(self.source.take, self.source)
    if ok and type(fresh) == "table" then
      for _, ch in ipairs(fresh) do
        self.pending[#self.pending + 1] = { ch = ch, since = t }
      end
    end
  end
  -- newcomers: wait for their hello
  local keep = {}
  for _, p in ipairs(self.pending) do
    if p.ch.update then pcall(p.ch.update, p.ch) end
    local done = false
    for _, msg in ipairs(p.ch:poll() or {}) do
      if not done and type(msg) == "table" and msg.type == "hello" then
        done = true
        self:_admit(p, msg)
        if p.refused then keep[#keep + 1] = p end
      end
    end
    if not done then
      if p.refused then
        if t - p.refused > 1.0 then pcall(p.ch.close, p.ch) else keep[#keep + 1] = p end
      elseif not p.ch.closed and t - p.since < Session.HELLO_WAIT then
        keep[#keep + 1] = p
      else
        pcall(p.ch.close, p.ch)
      end
    end
  end
  self.pending = keep
  -- members
  for id, p in pairs(self.peers) do
    if p.ch.update then pcall(p.ch.update, p.ch) end
    for _, msg in ipairs(p.ch:poll() or {}) do
      if type(msg) == "table" then
        p.lastSeen = t
        local ty = msg.type
        if ty == "z_ev" then
          self.stats.gotEv = self.stats.gotEv + 1
          local to = tonumber(msg.to)
          if to == nil or to == 1 then push(self, "event", id, msg.data) end
          if to == nil then
            self:_broadcast({ type = "z_ev", from = id, data = msg.data }, id)
          elseif to ~= 1 and self.peers[to] then
            send(self.peers[to].ch, { type = "z_ev", from = id, data = msg.data })
          end
        elseif ty == "z_snap" then
          self.stats.gotSnap = self.stats.gotSnap + 1
          push(self, "snapshot", id, msg.data)
          local out = { type = "z_snap", from = id, tick = msg.tick, data = msg.data }
          self:_broadcast(out, id, snapChannel(out))
        elseif ty == "z_ping" then
          send(p.ch, { type = "z_pong", t = msg.t, tick = self:tick() })
        elseif ty == "z_bye" then
          p.bye = msg.reason or "left"
        end
      end
    end
    if p.bye then
      self:_dropPeer(id, p.bye)
    elseif p.ch.closed then
      self:_dropPeer(id, "connection lost")
    elseif t - p.lastSeen > Session.TIMEOUT then
      self:_dropPeer(id, "timed out")
    end
  end
  if t - self.lastClock >= 1 then
    self.lastClock = t
    self:_broadcast({ type = "z_clock", tick = self:tick() }, nil, 1)
  end
end

-- --------------------------------------------------------------- guest

-- opts: game, name, channel (connected Net-like), clock
function Session.guest(opts)
  local self = base(opts)
  self.isHost = false
  self.ch = assert(opts.channel, "channel")
  self.state = "joining"
  self.joinedAt = now(self)
  self.lastPing = -1e9
  self.lastHeard = now(self)
  self.epoch = now(self)
  send(self.ch, self.hello)
  return self
end

function Session:_setClock(hostTick, rtt)
  local hz = Session.TICK_HZ
  local estimate = hostTick + (rtt or 0) / 2 * hz
  local mine = (now(self) - self.epoch) * hz
  local diff = estimate - mine
  if math.abs(diff) > 3 or not self.clockSet then
    self.epoch = self.epoch - diff / hz
    self.clockSet = true
  else
    -- nudge a fraction of the error: no visible jumps
    self.epoch = self.epoch - (diff / hz) * 0.25
  end
end

function Session:_guestUpdate()
  local t = now(self)
  local ch = self.ch
  if ch.update then pcall(ch.update, ch) end
  for _, msg in ipairs(ch:poll() or {}) do
    if type(msg) == "table" then
      self.lastHeard = t
      local ty = msg.type
      if ty == "hello" then
        if msg.series ~= "zelda" then
          self:_closed("That code is for a Pokemon game, not a Zelda room.")
          return
        end
      elseif ty == "z_refuse" then
        self:_closed(tostring(msg.reason or "The room refused us."))
        return
      elseif ty == "z_welcome" then
        self.localId = tonumber(msg.id)
        self.hostId = tonumber(msg.hostId) or 1
        self.maxPlayers = tonumber(msg.max) or self.maxPlayers
        self.roster = {}
        for _, p in ipairs(msg.players or {}) do
          local id = tonumber(p.id)
          if id then
            self.roster[id] = { id = id, name = tostring(p.name or "?") }
            if id ~= self.localId then push(self, "join", id, { name = self.roster[id].name }) end
          end
        end
        self:_setClock(tonumber(msg.tick) or 0, nil)
        self.state = "open"
      elseif ty == "z_join" and type(msg.player) == "table" then
        local id = tonumber(msg.player.id)
        if id then
          self.roster[id] = { id = id, name = tostring(msg.player.name or "?") }
          push(self, "join", id, { name = self.roster[id].name })
        end
      elseif ty == "z_leave" then
        local id = tonumber(msg.id)
        local r = id and self.roster[id]
        if id then self.roster[id] = nil end
        push(self, "leave", id, { name = r and r.name, reason = msg.reason })
      elseif ty == "z_ev" then
        self.stats.gotEv = self.stats.gotEv + 1
        push(self, "event", tonumber(msg.from) or 1, msg.data)
      elseif ty == "z_snap" then
        self.stats.gotSnap = self.stats.gotSnap + 1
        push(self, "snapshot", tonumber(msg.from) or 1, msg.data)
      elseif ty == "z_pong" then
        local sent = tonumber(msg.t)
        if sent then
          self.rtt = math.max(0, t - sent)
          self:_setClock(tonumber(msg.tick) or 0, self.rtt)
        end
      elseif ty == "z_clock" then
        if self.rtt then self:_setClock(tonumber(msg.tick) or 0, self.rtt) end
      elseif ty == "z_close" then
        self:_closed(tostring(msg.reason or "The host left."))
        return
      end
    end
  end
  if self.state == "joining" and t - self.joinedAt > Session.HELLO_WAIT then
    self:_closed("No answer from that room.")
    return
  end
  if ch.closed then
    self:_closed(self.state == "joining" and "Could not join the room." or "The host left.")
    return
  end
  if t - self.lastHeard > Session.TIMEOUT then
    self:_closed("Lost the connection to the host.")
    return
  end
  if self.state == "open" and t - self.lastPing >= Session.PING_EVERY then
    self.lastPing = t
    send(ch, { type = "z_ping", t = t })
  end
end

function Session:_closed(reason)
  if self.state == "closed" then return end
  self.state = "closed"
  self.closeReason = reason
  if self.ch and not self.ch.closed then pcall(self.ch.close, self.ch) end
  push(self, "closed", nil, { reason = reason })
end

-- ---------------------------------------------------------------- shared

function Session:update()
  if self.state == "closed" then return end
  if self.isHost then self:_hostUpdate() else self:_guestUpdate() end
end

function Session:messages()
  local list = self.inbox
  self.inbox = {}
  local i = 0
  return function()
    i = i + 1
    return list[i]
  end
end

function Session:tick()
  return math.floor((now(self) - self.epoch) * Session.TICK_HZ)
end

function Session:localIndex() return self.localId end

function Session:players()
  local out = {}
  for _, r in ipairs(self:rosterList()) do
    out[#out + 1] = { id = r.id, name = r.name, color = Session.COLORS[r.id],
                      isHost = r.id == (self.hostId or 1), me = r.id == self.localId }
  end
  return out
end

function Session:count()
  local n = 0
  for _ in pairs(self.roster) do n = n + 1 end
  return n
end

function Session:sendEvent(data)
  if self.state ~= "open" then return false end
  self.stats.sentEv = self.stats.sentEv + 1
  if self.isHost then
    self:_broadcast({ type = "z_ev", from = 1, data = data })
  else
    send(self.ch, { type = "z_ev", data = data })
  end
  return true
end

function Session:sendEventTo(id, data)
  if self.state ~= "open" then return false end
  id = tonumber(id)
  if not id or id == self.localId then return false end
  self.stats.sentEv = self.stats.sentEv + 1
  if self.isHost then
    local p = self.peers[id]
    if p then send(p.ch, { type = "z_ev", from = 1, data = data }) end
  else
    send(self.ch, { type = "z_ev", to = id, data = data })
  end
  return true
end


function Session:sendSnapshot(data)
  if self.state ~= "open" then return false end
  local msg = { type = "z_snap", tick = self:tick(), data = data }
  if self.isHost then msg.from = 1 end
  local channel = snapChannel(msg)
  self.stats.sentSnap = self.stats.sentSnap + 1
  if self.isHost then self:_broadcast(msg, nil, channel) else send(self.ch, msg, channel) end
  return true
end

function Session:close(reason)
  if self.state == "closed" then return end
  if self.isHost then
    self:_broadcast({ type = "z_close", reason = reason or "The host left." })
    for _, p in pairs(self.peers) do
      if p.ch and p.ch.update then pcall(p.ch.update, p.ch) end
    end
    for id in pairs(self.peers) do
      local p = self.peers[id]
      if p.ch and not p.ch.closed then pcall(p.ch.close, p.ch) end
    end
    self.peers = {}
    for _, p in ipairs(self.pending) do pcall(p.ch.close, p.ch) end
    self.pending = {}
    if self.source and self.source.close then pcall(self.source.close, self.source) end
    if self.hostJob and self.hostJob.close then pcall(self.hostJob.close, self.hostJob) end
  else
    send(self.ch, { type = "z_bye", reason = reason or "left" })
    if self.ch.update then pcall(self.ch.update, self.ch) end
  end
  self.state = "closed"
  self.closeReason = reason
  if self.ch and not self.ch.closed then pcall(self.ch.close, self.ch) end
end

return Session
