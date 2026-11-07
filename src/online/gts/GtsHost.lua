-- Puts a GtsService on the wire (docs/online-design.md 2.7a, WS7).
--
-- Three ways in, all feeding the same service:
--
--   local host = GtsHost.new(service)
--
--   -- 1. a host that already routes its own peers (WS8 WorldHost, WS9 hub):
--   host:attach(key, function(msg, channel) ... send ... end)
--   host:receive(key, msg)        -- any message with GtsService.isGtsMessage
--   host:detach(key)
--
--   -- 2. a Transport this host owns outright (a GTS-only hub, tests):
--   host:serveTransport(t)        -- t.receiveEvents must be true
--   host:update()                 -- pumps t and every served channel
--
--   -- 3. one Net-API channel (Transport:channelFor, Net.loopbackPair end):
--   host:serveChannel(ch, key)
--
-- Messages that are not gts_* are left alone in (1) and dropped with a log
-- line in (2)/(3).

local GtsService = require("src.online.gts.GtsService")

local GtsHost = {}
GtsHost.__index = GtsHost

function GtsHost.new(service, opts)
  opts = opts or {}
  return setmetatable({ service = service, senders = {}, channels = {},
                        transports = {}, log = opts.log or service.log,
                        onOther = opts.onOther }, GtsHost)
end

function GtsHost:attach(key, send)
  self.senders[key] = send
  self.service:connect(key)
end

function GtsHost:detach(key)
  self.senders[key] = nil
  self.service:disconnect(key)
end

function GtsHost:receive(key, msg)
  if not GtsService.isGtsMessage(msg) then
    if self.onOther then self.onOther(key, msg) end
    return false
  end
  local send = self.senders[key]
  local ok, replies = pcall(self.service.handle, self.service, key, msg)
  if not ok then
    if self.log then self.log("gts: handler error: " .. tostring(replies)) end
    -- "error", not "bad": the client must not assume nothing happened
    replies = { { msg = { type = "gts_refused", code = "error", text = GtsService.TEXT.bad,
                          token = msg.token, rid = msg.rid, request = msg.type }, channel = 0 } }
  end
  for _, r in ipairs(replies) do
    local to = r.to ~= nil and self.senders[r.to] or (r.to == nil and send) or nil
    if to then to(r.msg, r.channel) end
  end
  return true, replies
end

local function tkey(t, id) return "t" .. tostring(t) .. ":" .. tostring(id) end

function GtsHost:serveTransport(t)
  self.transports[#self.transports + 1] = t
  for _, rec in ipairs(t:peerList()) do
    if rec.state == "connected" then
      local id = rec.id
      self:attach(tkey(t, id), function(m, ch) t:send(id, m, ch) end)
    end
  end
end

function GtsHost:serveChannel(ch, key)
  key = key or ("c" .. tostring(ch))
  self.channels[#self.channels + 1] = { ch = ch, key = key }
  self:attach(key, function(m, channel) ch:send(m, channel) end)
  return key
end

function GtsHost:update()
  for _, t in ipairs(self.transports) do
    t:update()
    for _, ev in ipairs(t:events()) do
      local key = tkey(t, ev.peer)
      if ev.type == "connect" and not ev.outgoing then
        local id = ev.peer
        self:attach(key, function(m, ch) t:send(id, m, ch) end)
      elseif ev.type == "receive" then
        if not self.senders[key] then
          local id = ev.peer
          self:attach(key, function(m, ch) t:send(id, m, ch) end)
        end
        self:receive(key, ev.msg)
      elseif ev.type == "disconnect" then
        if self.senders[key] then self:detach(key) end
      end
    end
  end
  local keep = {}
  for _, e in ipairs(self.channels) do
    local ch = e.ch
    if ch.update then ch:update() end
    for _, msg in ipairs(ch:poll()) do self:receive(e.key, msg) end
    if ch.closed then
      self:detach(e.key)
    else
      keep[#keep + 1] = e
    end
  end
  self.channels = keep
end

return GtsHost
