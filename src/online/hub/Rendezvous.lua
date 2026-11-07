-- Rendezvous (ladder rung L4, docs/online-design.md 2.1): the hub tells two
-- players each other's address as the hub saw it, and they connect
-- directly from the same sockets, so their NATs already have a mapping.
--
-- The client side is src/online/net/Connector.lua (Host:registerHub /
-- viaHub).  Its messages, over the hub's UDP (ENet) port:
--
--   host  -> {type="hub_register", nonce, lan}
--         <- {type="hub_registered", ticket, observed, code, expires}
--   guest -> {type="hub_join", ticket, nonce, lan}      (or `code` for ticket)
--   guest <- {type="hub_introduce", endpoint, lan, nonce, role="guest"}
--   host  <- {type="hub_introduce", endpoint, lan, nonce, role="host"}
--   either <- {type="hub_error", reason="not_found"|"limit"|"bad"|"busy"}
--
-- `ticket` is the 20-bit number a hub invite code carries (InviteCode kind
-- "hub"); `code` is the same room as a six-symbol short code.  `observed` is
-- the "ip:port" the hub saw the host's packets come from.  A ticket lives as
-- long as the host stays connected to the hub (and at most ticketTtl).
--
-- test.simulateBlockedPunch (harness only): introductions name an address
-- nobody answers on, as if both players were behind carrier-grade NAT, so
-- the Connector falls through to the relay rung.

local Rendezvous = {}
Rendezvous.__index = Rendezvous

Rendezvous.TYPES = { hub_register = true, hub_join = true }
Rendezvous.DEAD_ENDPOINT = "127.0.0.1:9"   -- discard port: nobody listens

function Rendezvous.new(opts)
  return setmetatable({
    codes = opts.codes, log = opts.log, cfg = opts.cfg, now = opts.now,
    rand = opts.rand or function() return math.random(0, 2147483646) end,
    test = opts.test or {},
    -- the hub's own outside address, when it knows one (the launcher's hub
    -- after its router mapping): a player on the hub's own machine is seen
    -- as 127.0.0.1, which means nothing to anyone else, so introductions
    -- name that address instead (with the player's own port)
    advertise = opts.advertise,
    tickets = {},       -- ticket -> room
    byIp = {},          -- ip -> count of live tickets
    count = 0,
    stats = { registered = 0, introduced = 0, refused = 0 },
  }, Rendezvous)
end

local function endpointOk(v)
  if type(v) ~= "string" or #v > 21 then return nil end
  local a, b, c, d, p = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+):(%d+)$")
  if not a then return nil end
  for _, x in ipairs({ a, b, c, d }) do if tonumber(x) > 255 then return nil end end
  p = tonumber(p)
  if p < 1 or p > 65535 then return nil end
  return v
end

local function nonceOk(v)
  v = tonumber(v)
  if not v or v ~= math.floor(v) or v < 0 or v > 1048575 then return nil end
  return v
end

local function isLoopback(ep)
  return type(ep) == "string" and ep:match("^127%.") ~= nil
end

-- the address the OTHER side should dial for `ep` (see opts.advertise)
function Rendezvous:visible(ep)
  if not isLoopback(ep) or not self.advertise then return ep end
  local ip = self.advertise()
  local port = ep:match(":(%d+)$")
  if type(ip) ~= "string" or not port or not ip:match("^%d+%.%d+%.%d+%.%d+$") then return ep end
  return ip .. ":" .. port
end

function Rendezvous:newTicket()
  for _ = 1, 64 do
    local t = self.rand() % 1048576
    if t ~= 0 and not self.tickets[t] then return t end
  end
  return nil
end

function Rendezvous:register(conn, msg)
  if conn.role and conn.role ~= "rendezvous" then
    conn:send({ type = "hub_error", reason = "busy" })
    return
  end
  if conn.ticket then
    -- the same host asking again: same answer
    local room = self.tickets[conn.ticket]
    if room then
      conn:send({ type = "hub_registered", ticket = room.ticket, observed = room.observed,
                  code = room.code, expires = room.expires })
      return
    end
  end
  local nonce = nonceOk(msg.nonce)
  if not nonce then
    conn:send({ type = "hub_error", reason = "bad" })
    return
  end
  local perIp = self.byIp[conn.ip or "?"] or 0
  if self.count >= self.cfg.maxTickets or perIp >= self.cfg.ticketsPerIp then
    self.stats.refused = self.stats.refused + 1
    conn:send({ type = "hub_error", reason = "limit" })
    self.log:warn("rendezvous: ticket limit for %s", self.log:addr(conn.address))
    return
  end
  local ticket = self:newTicket()
  if not ticket then
    conn:send({ type = "hub_error", reason = "limit" })
    return
  end
  local now = self.now()
  local room = { ticket = ticket, host = conn, nonce = nonce, lan = endpointOk(msg.lan),
                 observed = conn.address, created = now, expires = now + self.cfg.ticketTtl,
                 introductions = 0 }
  room.code = self.codes:allocate({ kind = "ticket", room = room })
  self.tickets[ticket] = room
  self.byIp[conn.ip or "?"] = perIp + 1
  self.count = self.count + 1
  self.stats.registered = self.stats.registered + 1
  conn.role, conn.ticket = "rendezvous", ticket
  conn:send({ type = "hub_registered", ticket = ticket, observed = room.observed,
              code = room.code, expires = room.expires })
  self.log:info("rendezvous: ticket %d (%s) for %s", ticket, tostring(room.code),
                self.log:addr(conn.address))
end

function Rendezvous:find(msg)
  local ticket = tonumber(msg.ticket)
  if ticket and self.tickets[ticket] then return self.tickets[ticket] end
  if msg.code ~= nil then
    local owner = self.codes:lookup(msg.code)
    if owner and owner.kind == "ticket" then return owner.room end
  end
  return nil
end

function Rendezvous:join(conn, msg)
  local room = self:find(msg)
  if not room or room.host.closed then
    self.stats.refused = self.stats.refused + 1
    conn:send({ type = "hub_error", reason = "not_found" })
    return
  end
  if room.host == conn then
    conn:send({ type = "hub_error", reason = "bad" })
    return
  end
  if room.introductions >= self.cfg.introductionsPerTicket then
    conn:send({ type = "hub_error", reason = "limit" })
    return
  end
  local nonce = nonceOk(msg.nonce)
  if not nonce then
    conn:send({ type = "hub_error", reason = "bad" })
    return
  end
  room.introductions = room.introductions + 1
  conn.role = conn.role or "rendezvous-guest"
  local guestEp, guestLan = conn.address, endpointOk(msg.lan)
  local hostEp, hostLan = room.observed, room.lan
  -- a player on the hub's own machine (only when the other one is not)
  if isLoopback(guestEp) ~= isLoopback(hostEp) then
    guestEp, hostEp = self:visible(guestEp), self:visible(hostEp)
  end
  if self.test.simulateBlockedPunch then
    guestEp, hostEp = Rendezvous.DEAD_ENDPOINT, Rendezvous.DEAD_ENDPOINT
    guestLan, hostLan = nil, nil
  end
  conn:send({ type = "hub_introduce", endpoint = hostEp, lan = hostLan, nonce = room.nonce,
              role = "guest" })
  room.host:send({ type = "hub_introduce", endpoint = guestEp, lan = guestLan, nonce = nonce,
                   role = "host" })
  self.stats.introduced = self.stats.introduced + 1
  self.log:info("rendezvous: ticket %d introduced %s to %s%s", room.ticket,
                self.log:addr(conn.address), self.log:addr(room.observed),
                self.test.simulateBlockedPunch and " (blocked punch simulated)" or "")
end

function Rendezvous:handle(conn, msg)
  if msg.type == "hub_register" then
    self:register(conn, msg)
    return true
  elseif msg.type == "hub_join" then
    self:join(conn, msg)
    return true
  end
  return false
end

function Rendezvous:drop(room)
  if self.tickets[room.ticket] ~= room then return end
  self.tickets[room.ticket] = nil
  self.count = self.count - 1
  local ip = room.host.ip or "?"
  self.byIp[ip] = math.max(0, (self.byIp[ip] or 1) - 1)
  if self.byIp[ip] == 0 then self.byIp[ip] = nil end
  self.codes:release(room.code)
end

function Rendezvous:closed(conn)
  local room = conn.ticket and self.tickets[conn.ticket]
  if room and room.host == conn then
    self.log:info("rendezvous: ticket %d closed (%d introductions)", room.ticket, room.introductions)
    self:drop(room)
  end
end

function Rendezvous:update()
  local now = self.now()
  for _, room in pairs(self.tickets) do
    if now > room.expires then
      self.log:info("rendezvous: ticket %d expired", room.ticket)
      self:drop(room)
      room.host:close("ticket expired")
    end
  end
end

return Rendezvous
