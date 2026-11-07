-- Multi-peer message transport over one ENet host (docs/online-design.md
-- 2.3).  One Transport = one UDP socket that can listen, dial out, and
-- carry any number of peers; every peer can be wrapped in a "channel" that
-- has exactly the Net API (src/link/Net.lua), so LinkState, LinkBattle,
-- TradeSession and Tournament run on it unchanged:
--
--   local t = Transport.new{ port = 7777, maxPeers = 1, nonce = 12345 }
--   assert(t:listen())
--   ... t:update(); for _, ev in ipairs(t:events()) do ... end
--   local net = t:channelFor(peerId)  -- send/poll/update/close, .paired ...
--
--   Transport.new{ port = 7777, ... }       bind *:7777 (0 = any free port,
--                                           nil = unbound client socket)
--   t:listen() -> ok, err                   open the socket
--   t:connect(endpoint, nonce) -> peerId    dial "ip:port" (a list dials
--                                           each and returns a list of ids)
--   t:update()                              pump the socket
--   t:events() -> { {type="connect"|"promote"|"acked"|"disconnect"|
--                    "reject"|"receive", peer=id, ...} }   (drained;
--                    "receive" only with receiveEvents = true)
--   t:receive(id) -> msgs                  messages for a channel-less peer
--   t:peer(id) -> record ; t:peerList()
--   t:send(id, msg, ch) ; t:disconnect(id) ; t:close()
--   t:channelFor(id, opts) -> netLike
--   Transport.loopbackHub(n) -> { t1, ..., tn }   in-memory star for tests
--
-- Session nonce: a joiner passes the 20-bit nonce from the invite as ENet's
-- connect data.  A transport created with `nonce` refuses any connect that
-- carries a different value, so a port scanner never gets a peer.
--
-- A transport with a nonce greets every peer it admits with `_hi`; the
-- dialling side marks that peer `acked` (Connector waits for it, since ENet
-- says "connect" even to a joiner the host refuses a moment later).
--
-- Inbound peers are "pending" until their first message (or an explicit
-- `_pick`); only promoted peers count toward maxPeers.  This lets a joiner
-- race its LAN and public attempts at the same host and keep one.
--
-- Channels: 0 reliable session, 1 unreliable-sequenced, 2 reliable bulk.
-- Every inbound packet goes through Wire.decode (size cap, depth cap, type
-- checks); a peer that keeps sending garbage is disconnected.

local Util = require("src.online.net.Util")
local Wire = require("src.online.net.Wire")
local Logger = require("src.core.Logger")

local hasEnet, enet = pcall(require, "enet")
if not hasEnet then enet = nil end

local Transport = {}
Transport.__index = Transport

Transport.DEFAULT_PORT = 7777
Transport.SLACK = 4            -- extra ENet slots for pending/outgoing peers
Transport.CONNECT_TIMEOUT = 8  -- seconds for an outgoing attempt
Transport.MAX_INBOX = 4096     -- queued messages per peer before "flooding"
Transport.MAX_EVENTS = 512
Transport.MAX_BAD = 16         -- malformed packets before a peer is dropped
Transport.MAX_SERVICE = 256    -- ENet events handled per update

function Transport.available() return enet ~= nil end

---------------------------------------------------------------- ENet driver

local EnetDriver = {}
EnetDriver.__index = EnetDriver

function Transport.enetDriver()
  return setmetatable({}, EnetDriver)
end

function EnetDriver:open(bind, port, peerCount, channels)
  if not enet then return false, "link needs lua-enet (run the game with LOVE)" end
  local addr = nil
  if port ~= nil then addr = ("%s:%d"):format(bind or "*", port) end
  local ok, h, err = pcall(enet.host_create, addr, peerCount, channels)
  if not ok or not h then
    return false, ("can't open UDP port %s (%s)"):format(tostring(port),
                                                        tostring(ok and err or h))
  end
  self.host = h
  return true
end

function EnetDriver:address()
  if not self.host then return nil end
  local ok, a = pcall(self.host.get_socket_address, self.host)
  if ok then return a end
  return nil
end

function EnetDriver:connect(addr, channels, data)
  local ok, peer = pcall(self.host.connect, self.host, addr, channels, data or 0)
  if not ok or not peer then return nil, "bad address " .. tostring(addr) end
  return peer
end

function EnetDriver:service()
  local ok, ev = pcall(self.host.service, self.host, 0)
  if not ok then return nil, tostring(ev) end
  return ev
end

function EnetDriver:flush()
  if self.host then pcall(self.host.flush, self.host) end
end

function EnetDriver:destroy()
  if self.host then
    pcall(self.host.flush, self.host)
    pcall(self.host.destroy, self.host)
    self.host = nil
  end
end

---------------------------------------------------------------- transport

function Transport.new(opts)
  opts = opts or {}
  local self = setmetatable({
    port = opts.port,                  -- nil: unbound client socket
    bind = opts.bind or "*",
    maxPeers = opts.maxPeers or 1,
    channels = opts.channels or 3,
    nonce = opts.nonce,                -- inbound gate (nil: accept any)
    allowTypes = opts.allowTypes,      -- nil: structural checks only
    receiveEvents = opts.receiveEvents,-- true: messages of channel-less peers
                                       -- come out of t:events(); otherwise
                                       -- they wait for channelFor / t:receive
    connectTimeout = opts.connectTimeout or Transport.CONNECT_TIMEOUT,
    driver = opts.driver,
    peers = {},                        -- id -> record
    byHandle = {},                     -- driver handle -> record
    nextId = 1,
    queue = {},                        -- events for t:events()
    closeHooks = {},
    closed = false,
    error = nil,
  }, Transport)
  return self
end

function Transport:listen()
  if self.open_ then return true end
  self.driver = self.driver or Transport.enetDriver()
  local slots = self.maxPeers + Transport.SLACK
  local ok, err = self.driver:open(self.bind, self.port, slots, self.channels)
  if not ok then
    self.error = err
    return false, err
  end
  self.open_ = true
  local addr = self.driver:address()
  local p = addr and tonumber(addr:match(":(%d+)$"))
  self.boundPort = p or self.port
  local lan = Util.lanIP()
  self.address = self.boundPort and Util.endpoint(lan or "?", self.boundPort) or nil
  return true
end
Transport.open = Transport.listen

function Transport:push(ev)
  local q = self.queue
  if #q >= Transport.MAX_EVENTS then table.remove(q, 1) end
  q[#q + 1] = ev
end

function Transport:events()
  local q = self.queue
  self.queue = {}
  return q
end

function Transport:peer(id) return self.peers[id] end

function Transport:peerList()
  local out = {}
  for _, rec in pairs(self.peers) do out[#out + 1] = rec end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function Transport:promotedCount()
  local n = 0
  for _, rec in pairs(self.peers) do
    if rec.promoted and not rec.outgoing and rec.state == "connected" then
      n = n + 1
    end
  end
  return n
end

local function newRecord(self, handle, address, outgoing)
  local rec = {
    id = self.nextId, handle = handle, address = address,
    ip = (Util.splitEndpoint(address or "")),
    outgoing = outgoing, state = "connecting", promoted = false,
    startedAt = Util.time(), bad = 0, claim = nil,
  }
  self.nextId = self.nextId + 1
  self.peers[rec.id] = rec
  self.byHandle[handle] = rec
  return rec
end

-- dial out.  `nonce` is the remote session's nonce (from its invite).
function Transport:connect(endpoint, nonce, opts)
  if type(endpoint) == "table" then
    local ids = {}
    for i, e in ipairs(endpoint) do ids[i] = self:connect(e, nonce, opts) end
    return ids
  end
  if not self.open_ then
    local ok, err = self:listen()
    if not ok then return nil, err end
  end
  local handle, err = self.driver:connect(endpoint, self.channels, nonce or 0)
  if not handle then return nil, err end
  local rec = newRecord(self, handle, endpoint, true)
  rec.deadline = Util.time() + ((opts and opts.timeout) or self.connectTimeout)
  rec.tag = opts and opts.tag
  return rec.id
end

local function finish(self, rec, reason)
  if rec.state == "closed" then return end
  local wasConnected = rec.state == "connected"
  rec.state = "closed"
  rec.reason = rec.reason or reason
  self.byHandle[rec.handle] = nil
  local ch = rec.channel
  if ch then
    ch.closed = true
    if not ch.paired then
      ch.error = ch.error or reason or "connection failed"
    end
  end
  self:push({ type = "disconnect", peer = rec.id, reason = rec.reason,
              wasConnected = wasConnected })
end

function Transport:disconnect(id, now)
  local rec = self.peers[id]
  if not rec or rec.state == "closed" then return end
  if now or rec.state ~= "connected" then
    pcall(function() rec.handle:disconnect_now() end)
  else
    pcall(function() rec.handle:disconnect_later() end)
  end
  if self.driver then self.driver:flush() end
  rec.reason = rec.reason or "closed locally"
  finish(self, rec, "closed locally")
end

function Transport:promote(rec)
  if rec.promoted then return true end
  if not rec.outgoing and self:promotedCount() >= self.maxPeers then
    rec.reason = "session full"
    self:disconnect(rec.id, true)
    return false
  end
  rec.promoted = true
  self:push({ type = "promote", peer = rec.id, address = rec.address })
  return true
end

local function deliver(self, rec, msg, channel)
  -- transport control ("_" types) is consumed here, never handed up
  if msg.type == "_hi" then
    rec.acked = true
    self:push({ type = "acked", peer = rec.id })
    return
  end
  if not rec.promoted and not self:promote(rec) then return end
  if msg.type == "_pick" then return end
  local ch = rec.channel
  if ch then
    local inbox = ch.inbox
    if #inbox >= Transport.MAX_INBOX then
      ch.error = "peer is flooding"
      rec.reason = "flooding"
      self:disconnect(rec.id, true)
      return
    end
    inbox[#inbox + 1] = msg
    if channel ~= 0 and ch.onChannel then ch.onChannel(msg, channel) end
  elseif self.receiveEvents then
    self:push({ type = "receive", peer = rec.id, channel = channel, msg = msg })
  else
    -- held for channelFor(id) / t:receive(id)
    local backlog = rec.backlog
    if not backlog then backlog = {} rec.backlog = backlog end
    if #backlog >= Transport.MAX_INBOX then
      rec.reason = "flooding"
      self:disconnect(rec.id, true)
      return
    end
    backlog[#backlog + 1] = msg
  end
end

-- drain messages held for a peer that has no channel
function Transport:receive(id)
  local rec = self.peers[id]
  if not rec or not rec.backlog then return {} end
  local b = rec.backlog
  rec.backlog = nil
  return b
end

function Transport:handleEvent(ev)
  local handle = ev.peer
  local rec = self.byHandle[handle]
  if ev.type == "connect" then
    if rec and rec.outgoing then
      rec.state = "connected"
      rec.connectedAt = Util.time()
      self:push({ type = "connect", peer = rec.id, address = rec.address,
                  outgoing = true })
      if rec.channel then rec.channel:_opened() end
      return
    end
    -- inbound
    local address = tostring(handle)
    if self.nonce and ev.data ~= self.nonce then
      pcall(function() handle:disconnect_now() end)
      self:push({ type = "reject", address = address, reason = "bad nonce" })
      return
    end
    if self:promotedCount() >= self.maxPeers and not self.acceptWhenFull then
      pcall(function() handle:disconnect_now() end)
      self:push({ type = "reject", address = address, reason = "session full" })
      return
    end
    if rec then finish(self, rec, "replaced") end
    rec = newRecord(self, handle, address, false)
    rec.state = "connected"
    rec.connectedAt = Util.time()
    rec.data = ev.data
    -- a gated host tells the joiner it was let in: ENet reports "connect"
    -- on the dialling side even when the host drops the peer straight
    -- after, so a Connector only trusts a connection once this arrives
    if self.nonce then self:send(rec.id, { type = "_hi" }) end
    self:push({ type = "connect", peer = rec.id, address = address,
                outgoing = false })
  elseif ev.type == "receive" then
    if not rec or rec.state ~= "connected" then return end
    local channel = ev.channel or 0
    local msg, why = Wire.decode(ev.data, channel, self.allowTypes)
    if not msg then
      rec.bad = rec.bad + 1
      if rec.bad == 1 then
        Logger.warn("online: dropped message from %s: %s", tostring(rec.address), why)
      end
      if rec.bad >= Transport.MAX_BAD then
        rec.reason = "too many bad messages"
        self:disconnect(rec.id, true)
      end
      return
    end
    deliver(self, rec, msg, channel)
  elseif ev.type == "disconnect" then
    if not rec then return end
    local reason = rec.state == "connected" and "peer disconnected"
                   or ("no answer from " .. tostring(rec.address))
    finish(self, rec, reason)
  end
end

function Transport:update()
  if not self.open_ or self.closed then return end
  for _ = 1, Transport.MAX_SERVICE do
    local ev, err = self.driver:service()
    if not ev then
      if err then
        -- an ICMP "port unreachable" from one dead target must not kill the
        -- other peers on this socket: note it and let deadlines decide
        self.serviceErrors = (self.serviceErrors or 0) + 1
        if self.serviceErrors == 1 then
          Logger.warn("online: socket service error: %s", tostring(err))
        end
      end
      break
    end
    self:handleEvent(ev)
  end
  local t = Util.time()
  for _, rec in pairs(self.peers) do
    if rec.state == "connecting" and rec.deadline and t > rec.deadline then
      pcall(function() rec.handle:disconnect_now() end)
      finish(self, rec, ("no answer from %s"):format(tostring(rec.address)))
    end
  end
end

function Transport:send(id, msg, channel)
  local rec = self.peers[id]
  if not rec or rec.state ~= "connected" then return false, "not connected" end
  channel = channel or 0
  local data, why = Wire.encode(msg, channel)
  if not data then
    Logger.warn("online: not sent (%s): %s", tostring(msg and msg.type), why)
    return false, why
  end
  local ok, err = pcall(function()
    rec.handle:send(data, channel, Wire.FLAGS[channel] or "reliable")
  end)
  if not ok then return false, tostring(err) end
  return true
end

-- tell a raced host which of our connections we kept
function Transport:pick(id)
  return self:send(id, { type = "_pick" }, 0)
end

function Transport:onClose(fn) self.closeHooks[#self.closeHooks + 1] = fn end

-- graceful: disconnect_later every live peer, pump briefly so the final
-- reliables (bye, confirm) leave, then destroy the socket
function Transport:close(budget)
  if self.closed then return end
  if self.open_ then
    local any = false
    for _, rec in pairs(self.peers) do
      if rec.state == "connected" then
        any = true
        pcall(function() rec.handle:disconnect_later() end)
      elseif rec.state == "connecting" then
        pcall(function() rec.handle:disconnect_now() end)
      end
    end
    if any then
      local deadline = Util.now() + (budget or 0.3)
      while Util.now() < deadline do
        local ev = self.driver:service()
        if ev and ev.type == "disconnect" then
          local rec = self.byHandle[ev.peer]
          if rec then finish(self, rec, "closed locally") end
        end
        local live = false
        for _, rec in pairs(self.peers) do
          if rec.state == "connected" then live = true break end
        end
        if not live then break end
        if not ev and Util.socket and Util.socket.sleep then Util.socket.sleep(0.005) end
      end
    end
    for _, rec in pairs(self.peers) do finish(self, rec, "closed locally") end
    self.driver:destroy()
  end
  self.closed = true
  self.open_ = false
  for _, fn in ipairs(self.closeHooks) do pcall(fn, self) end
  self.closeHooks = {}
end

---------------------------------------------------------------- channels

local Channel = {}
Channel.__index = Channel
Transport.Channel = Channel

-- a Net-API view of one peer.  opts.owns = true: closing the channel
-- closes the whole transport (a one-peer link session made by Connector).
function Transport:channelFor(id, opts)
  local rec = self.peers[id]
  if not rec then return nil, "no such peer" end
  if rec.channel then return rec.channel end
  opts = opts or {}
  local ch = setmetatable({
    transport = self, peerId = id, inbox = {}, outbox = {},
    paired = rec.state == "connected", closed = rec.state == "closed",
    error = nil, mode = rec.outgoing and "joining" or "hosting",
    address = self.address, target = rec.address, owns = opts.owns,
    path = opts.path, onChannel = opts.onChannel,
  }, Channel)
  if ch.closed then ch.error = rec.reason end
  rec.channel = ch
  if rec.state == "connected" then self:promote(rec) end
  -- anything that arrived before the channel existed moves into its inbox
  if rec.backlog then
    for _, m in ipairs(rec.backlog) do ch.inbox[#ch.inbox + 1] = m end
    rec.backlog = nil
  end
  local keep = {}
  for _, ev in ipairs(self.queue) do
    if ev.type == "receive" and ev.peer == id then
      ch.inbox[#ch.inbox + 1] = ev.msg
    else
      keep[#keep + 1] = ev
    end
  end
  self.queue = keep
  return ch
end

function Channel:_opened()
  self.paired = true
  local rec = self.transport.peers[self.peerId]
  if rec then self.transport:promote(rec) end
  local queued = self.outbox
  self.outbox = {}
  for _, m in ipairs(queued) do self:send(m[1], m[2]) end
end

function Channel:send(msg, channel)
  if self.closed then return end
  if not self.paired then
    self.outbox[#self.outbox + 1] = { msg, channel }
    return
  end
  local ok, err = self.transport:send(self.peerId, msg, channel)
  if not ok and err == "not connected" then
    self.closed = true
  end
end

function Channel:update()
  if self.closed then return end
  self.transport:update()
  local rec = self.transport.peers[self.peerId]
  if rec and rec.state == "connected" and not self.paired then self:_opened() end
end

function Channel:poll()
  local msgs = self.inbox
  self.inbox = {}
  return msgs
end

function Channel:close()
  if self.closedByUs then return end
  self.closedByUs = true
  if self.owns then
    self.transport:close()
  else
    self.transport:disconnect(self.peerId)
  end
  self.closed = true
end

-- round trip time in ms when the backend knows it
function Channel:rtt()
  local rec = self.transport.peers[self.peerId]
  if rec and rec.handle and rec.handle.round_trip_time then
    local ok, v = pcall(rec.handle.round_trip_time, rec.handle)
    if ok then return v end
  end
  return nil
end

---------------------------------------------------------------- loopback

-- n in-memory transports in a star: ends[1] is the hub, ends[k] (k >= 2)
-- is connected to it.  On the hub, client k is peer id k-1 in connect
-- order; on each client the hub is peer 1.  Traffic goes through the same
-- Wire encode/decode as real packets.
function Transport.loopbackHub(n, opts)
  opts = opts or {}
  local LoopNet = require("src.online.net.LoopNet")
  local net = LoopNet.new()
  local ends = {}
  local rev = opts.receiveEvents ~= false
  local hub = Transport.new{ port = 7777, maxPeers = math.max(1, n - 1),
                             driver = net:driver("10.0.0.1"),
                             allowTypes = opts.allowTypes, receiveEvents = rev }
  assert(hub:listen())
  ends[1] = hub
  for k = 2, n do
    local t = Transport.new{ driver = net:driver(("10.0.0.%d"):format(k)),
                             allowTypes = opts.allowTypes, receiveEvents = rev }
    assert(t:listen())
    t:connect("10.0.0.1:7777")
    ends[k] = t
  end
  -- settle the handshakes (zero delay: one pump each)
  for _ = 1, 3 do
    for _, t in ipairs(ends) do t:update() end
  end
  hub:events()
  for k = 2, n do ends[k]:events() end
  for _, rec in pairs(hub.peers) do hub:promote(rec) end
  hub:events()
  ends.net = net
  return ends
end

return Transport
