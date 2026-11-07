-- The star a 4-player multi battle runs on (src/online/MultiBattle.lua).
--
-- One machine is the HOST (seat 0, the leader who opened the room): every
-- other player has exactly one link, to the host, and the host relays.
-- Three ways the links come about, one shape for the battle:
--
--   MultiNet.host()                 the host's end: `add(seat, channel)` as
--                                   players arrive; poll() returns
--                                   { from = seat, msg } in seat order
--   MultiNet.guest(channel)         a player's end: one channel to the host
--   MultiNet.relayService()         a world service (WS8 WorldHost
--                                   registerService "multi"): members open
--                                   it and the world host forwards between
--                                   the room's leader and the others, so a
--                                   multi gathers inside a world with no
--                                   extra connection
--   MultiNet.fromRelay(channel)     the leader's end of that service: one
--                                   virtual channel per member (Net API)
--
-- Every channel is Net-like (src/link/Net.lua): send / poll / update /
-- close, `.closed`.  A WS1 Transport (src/online/net/Transport.lua) with
-- maxPeers = 3 gives the host one channel per joiner (channelFor); a
-- Connector.join job gives a guest its channel; Transport.loopbackHub(4)
-- is the in-memory star the tests use.

local MultiNet = {}

-- ------------------------------------------------------------ host

local Host = {}
Host.__index = Host
MultiNet.Host = Host

function MultiNet.host(links)
  local self = setmetatable({ role = "host", links = {}, gone = {}, seats = {} }, Host)
  for seat, ch in pairs(links or {}) do self:add(seat, ch) end
  return self
end

function Host:add(seat, ch)
  seat = tonumber(seat)
  if not seat then return end
  self.links[seat] = ch
  self.gone[seat] = nil
  local seats = {}
  for s in pairs(self.links) do seats[#seats + 1] = s end
  table.sort(seats)
  self.seats = seats
end

function Host:drop(seat, why)
  local ch = self.links[seat]
  if not ch then return end
  self.links[seat] = nil
  if ch.close then pcall(ch.close, ch) end
  local seats = {}
  for s in pairs(self.links) do seats[#seats + 1] = s end
  table.sort(seats)
  self.seats = seats
  self.gone[seat] = why or "left"
end

-- move a link from one seat to another (the lobby's team swap)
function Host:remap(map)
  local old = self.links
  self.links = {}
  for from, to in pairs(map) do
    if old[from] then self.links[to] = old[from] end
  end
  local seats = {}
  for s in pairs(self.links) do seats[#seats + 1] = s end
  table.sort(seats)
  self.seats = seats
end

function Host:update()
  for _, seat in ipairs(self.seats) do
    local ch = self.links[seat]
    if ch and ch.update then pcall(ch.update, ch) end
  end
end

-- { { from = seat, msg = msg }, ... }; a link that closed reports
-- { type = "mb_gone" } once
function Host:poll()
  local out = {}
  for _, seat in ipairs(self.seats) do
    local ch = self.links[seat]
    if ch then
      for _, msg in ipairs(ch:poll()) do
        if type(msg) == "table" then out[#out + 1] = { from = seat, msg = msg } end
      end
      if ch.closed and not self.gone[seat] then
        self.gone[seat] = ch.error or "closed"
        out[#out + 1] = { from = seat, msg = { type = "mb_gone", reason = self.gone[seat] } }
      end
    end
  end
  return out
end

function Host:sendTo(seat, msg)
  local ch = self.links[seat]
  if ch and not ch.closed then ch:send(msg) end
end

function Host:broadcast(msg, except)
  for _, seat in ipairs(self.seats) do
    if seat ~= except then self:sendTo(seat, msg) end
  end
end

function Host:isGone(seat) return self.gone[seat] ~= nil end

function Host:close()
  for _, seat in ipairs(self.seats) do
    local ch = self.links[seat]
    if ch and ch.close then pcall(ch.close, ch) end
  end
  if self.onClose then pcall(self.onClose) end
  self.closed = true
end

-- ------------------------------------------------------------ guest

local Guest = {}
Guest.__index = Guest
MultiNet.Guest = Guest

function MultiNet.guest(ch)
  return setmetatable({ role = "guest", ch = ch }, Guest)
end

function Guest:update() if self.ch and self.ch.update then pcall(self.ch.update, self.ch) end end

function Guest:poll()
  local out = {}
  if not self.ch then return out end
  for _, msg in ipairs(self.ch:poll()) do
    if type(msg) == "table" then out[#out + 1] = { from = 0, msg = msg } end
  end
  if self.ch.closed and not self.goneSent then
    self.goneSent = true
    out[#out + 1] = { from = 0, msg = { type = "mb_gone", reason = self.ch.error or "closed" } }
  end
  return out
end

function Guest:send(msg) if self.ch and not self.ch.closed then self.ch:send(msg) end end
function Guest:sendTo(_, msg) self:send(msg) end
function Guest:broadcast(msg) self:send(msg) end
function Guest:isGone() return self.ch == nil or self.ch.closed == true end

function Guest:close()
  if self.ch and self.ch.close then pcall(self.ch.close, self.ch) end
  if self.onClose then pcall(self.onClose) end
  self.closed = true
end

-- ------------------------------------------------------------ world relay

-- A WorldHost service.  The first member to open it leads the room; the
-- others' traffic reaches the leader as { type = "mb_fwd", from = pid, msg }
-- and the leader answers { type = "mb_to", to = pid, msg }.  The leader
-- hears { type = "mb_relay_join", pid, name } / { type = "mb_relay_leave",
-- pid }.  A second room starts when the leader leaves.
function MultiNet.relayService()
  local svc = { members = {}, leader = nil }
  local function leaderCh() return svc.leader and svc.members[svc.leader] and svc.members[svc.leader].ch end
  function svc.open(ch, member)
    local pid = member and member.pid or (#svc.members + 1)
    svc.members[pid] = { ch = ch, name = member and member.name or "?" }
    if not svc.leader or not leaderCh() or leaderCh().closed then
      svc.leader = pid
      ch:send({ type = "mb_relay_lead" })
    else
      leaderCh():send({ type = "mb_relay_join", pid = pid, name = member and member.name })
    end
  end
  function svc.update()
    local lead = leaderCh()
    for pid, m in pairs(svc.members) do
      local ch = m.ch
      for _, msg in ipairs(ch:poll()) do
        if type(msg) == "table" then
          if pid == svc.leader then
            if msg.type == "mb_to" and svc.members[tonumber(msg.to)] and type(msg.msg) == "table" then
              svc.members[tonumber(msg.to)].ch:send(msg.msg)
            end
          elseif lead and not lead.closed then
            lead:send({ type = "mb_fwd", from = pid, msg = msg })
          end
        end
      end
      if ch.closed then
        svc.members[pid] = nil
        if pid == svc.leader then
          svc.leader = nil
          for _, other in pairs(svc.members) do other.ch:send({ type = "mb_relay_gone" }) end
        elseif lead and not lead.closed then
          lead:send({ type = "mb_relay_leave", pid = pid })
        end
      end
    end
  end
  function svc.close()
    for _, m in pairs(svc.members) do pcall(m.ch.close, m.ch) end
    svc.members = {}
  end
  return svc
end

-- the leader's end of the relay: `take()` hands out a Net-like channel per
-- member as they join
function MultiNet.fromRelay(ch)
  local r = { ch = ch, subs = {}, fresh = {}, led = false }
  local Sub = {}
  Sub.__index = Sub
  function Sub:send(msg) if not self.closed then r.ch:send({ type = "mb_to", to = self.pid, msg = msg }) end end
  function Sub:poll() local m = self.inbox self.inbox = {} return m end
  function Sub:update() r:update() end
  function Sub:close() self.closed = true end
  function r:update()
    if self.ch.update then pcall(self.ch.update, self.ch) end
    for _, msg in ipairs(self.ch:poll()) do
      if msg.type == "mb_relay_lead" then
        self.led = true
      elseif msg.type == "mb_relay_join" then
        local sub = setmetatable({ pid = msg.pid, name = msg.name, inbox = {}, paired = true }, Sub)
        self.subs[msg.pid] = sub
        self.fresh[#self.fresh + 1] = sub
      elseif msg.type == "mb_relay_leave" then
        local sub = self.subs[msg.pid]
        if sub then sub.closed = true sub.error = "left" end
      elseif msg.type == "mb_fwd" then
        local sub = self.subs[msg.from]
        if sub and type(msg.msg) == "table" then sub.inbox[#sub.inbox + 1] = msg.msg end
      end
    end
    if self.ch.closed then
      for _, sub in pairs(self.subs) do sub.closed = true sub.error = "world closed" end
    end
  end
  function r:take()
    self:update()
    local out = self.fresh
    self.fresh = {}
    return out
  end
  function r:close() if self.ch.close then pcall(self.ch.close, self.ch) end end
  return r
end

-- ------------------------------------------------------------ joiners

-- Where a host's new players come from, as one `take()`: a WS1 Transport
-- (each newly promoted inbound peer), a relay (fromRelay), or a list.
function MultiNet.transportSource(t, exclude)
  local src = { t = t, seen = {} }
  function src:take()
    local out = {}
    if not self.t then return out end
    pcall(self.t.update, self.t)
    for _, rec in ipairs(self.t:peerList()) do
      if not rec.outgoing and rec.promoted and rec.state == "connected"
         and not self.seen[rec.id] and not (exclude and exclude[rec.id]) then
        self.seen[rec.id] = true
        local ch = self.t:channelFor(rec.id)
        if ch then out[#out + 1] = ch end
      end
    end
    return out
  end
  function src:close() if self.t then pcall(self.t.close, self.t) end end
  return src
end

function MultiNet.listSource(list)
  local src = { list = list or {} }
  function src:take()
    local out = self.list
    self.list = {}
    return out
  end
  function src:add(ch) self.list[#self.list + 1] = ch end
  function src:close() end
  return src
end

return MultiNet
