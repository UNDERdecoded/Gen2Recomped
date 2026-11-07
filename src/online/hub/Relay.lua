-- The pokeserver relay protocol (short codes), served by the hub.
--
-- Matches what src/link/Net.lua's TCP backend and src/online/net/Relay.lua
-- speak, newline-delimited JSON:
--
--   -> {type="host"}                    <- {type="hosted", code="ABC234"}
--   -> {type="join", code="ABC234"}     <- {type="paired"} (both ends)
--                                       |  {type="join_error", reason=
--                                            "not_found"|"full"|"expired"}
--   after "paired", every message one end sends reaches the other verbatim;
--   when one end leaves the other gets {type="peer_gone"} and is closed.
--
-- The same rooms also take ENet connections (the hub's UDP port), so a
-- future client can relay without TCP; a TCP host and an ENet guest pair.
--
-- Each pair has a byte budget (token bucket: bytesPerSecond, burstBytes).
-- Traffic over it waits in the pair's queue; a TCP sender is simply not read
-- while its queue is long (backpressure), and a pair whose queue passes
-- queueBytes is cut, because a link session that far behind is dead anyway.

local Relay = {}
Relay.__index = Relay

function Relay.new(opts)
  return setmetatable({
    codes = opts.codes, log = opts.log, cfg = opts.cfg, now = opts.now,
    rooms = {},          -- code -> room
    count = 0, paired = 0,
    stats = { hosted = 0, pairedTotal = 0, bytes = 0, cut = 0 },
  }, Relay)
end

Relay.TYPES = { host = true, join = true }

local function msgBytes(msg, line)
  if line then return #line + 1 end
  local ok, Json = pcall(require, "src.link.Json")
  if ok then
    local okE, s = pcall(Json.encode, msg)
    if okE then return #s + 1 end
  end
  return 64
end

function Relay:host(conn)
  if conn.role then
    conn:send({ type = "join_error", reason = "busy" })
    return
  end
  if self.count >= self.cfg.maxRooms then
    self.log:warn("relay: room limit (%d) reached", self.cfg.maxRooms)
    conn:send({ type = "join_error", reason = "full" })
    conn:close("hub full")
    return
  end
  local room = { a = conn, state = "waiting", created = self.now(), pre = {}, q = {}, qBytes = 0,
                 tokens = self.cfg.burstBytes, tokensAt = self.now() }
  local code = self.codes:allocate({ kind = "room", room = room })
  if not code then
    conn:send({ type = "join_error", reason = "full" })
    conn:close("no codes left")
    return
  end
  room.code = code
  self.rooms[code] = room
  self.count = self.count + 1
  self.stats.hosted = self.stats.hosted + 1
  conn.role, conn.room = "room", room
  conn:send({ type = "hosted", code = code })
  self.log:info("relay: %s hosted room %s (%s)", conn.kind, code, self.log:addr(conn.address))
end

function Relay:join(conn, code)
  if conn.role then
    conn:send({ type = "join_error", reason = "busy" })
    return
  end
  local owner, why = self.codes:lookup(code)
  local room = owner and owner.kind == "room" and owner.room or nil
  if not room then
    local reason = why == "expired" and "expired" or "not_found"
    conn:send({ type = "join_error", reason = reason })
    self.log:info("relay: join %s refused (%s)", tostring(code), reason)
    return
  end
  if room.b or room.state ~= "waiting" then
    conn:send({ type = "join_error", reason = "full" })
    return
  end
  if room.a == conn then
    conn:send({ type = "join_error", reason = "not_found" })
    return
  end
  room.b = conn
  room.state = "paired"
  room.pairedAt = self.now()
  conn.role, conn.room = "room", room
  self.paired = self.paired + 1
  self.stats.pairedTotal = self.stats.pairedTotal + 1
  room.a:send({ type = "paired" })
  conn:send({ type = "paired" })
  -- what the host sent while it waited (a hello, usually) goes first
  for _, e in ipairs(room.pre) do self:enqueue(room, room.b, e.msg, e.line) end
  room.pre = {}
  self.log:info("relay: room %s paired (%s <-> %s)", room.code, room.a.kind, conn.kind)
end

function Relay:enqueue(room, to, msg, line)
  local n = msgBytes(msg, line)
  room.q[#room.q + 1] = { to = to, msg = msg, line = line, n = n }
  room.qBytes = room.qBytes + n
  if room.qBytes > self.cfg.queueBytes then
    self.stats.cut = self.stats.cut + 1
    self.log:warn("relay: room %s cut (%d bytes behind its budget)", room.code, room.qBytes)
    self:closeRoom(room, "over the bandwidth cap")
  end
end

-- a message from one end of a room
function Relay:forward(conn, msg, line)
  local room = conn.room
  if not room or room.closed then return end
  if room.state ~= "paired" then
    if conn == room.a and #room.pre < self.cfg.preQueue then
      room.pre[#room.pre + 1] = { msg = msg, line = line }
    end
    return
  end
  local to = (conn == room.a) and room.b or room.a
  self:enqueue(room, to, msg, line)
end

-- true for a message this module consumed
function Relay:handle(conn, msg, line)
  local t = msg.type
  if t == "host" and not conn.role then
    self:host(conn)
    return true
  elseif t == "join" and not conn.role then
    self:join(conn, msg.code)
    return true
  elseif conn.role == "room" then
    self:forward(conn, msg, line)
    return true
  end
  return false
end

-- may this TCP connection be read now? (backpressure)
function Relay:canRead(conn)
  local room = conn.role == "room" and conn.room
  if not room then return true end
  return room.qBytes < self.cfg.burstBytes
end

function Relay:closeRoom(room, reason)
  if room.closed then return end
  room.closed = true
  if room.code and self.rooms[room.code] == room then
    self.rooms[room.code] = nil
    self.count = self.count - 1
    self.codes:release(room.code)
  end
  if room.state == "paired" then self.paired = self.paired - 1 end
  for _, c in ipairs({ room.a, room.b }) do
    if c and not c.closed then
      c:send({ type = "peer_gone" })
      c:close(reason)
    end
    if c then c.room = nil end
  end
end

-- one end went away
function Relay:closed(conn)
  local room = conn.room
  if not room then return end
  if room.state == "paired" then
    -- deliver what is still queued for the end that stays, then tell it
    local other = (conn == room.a) and room.b or room.a
    for _, e in ipairs(room.q) do
      if e.to == other and not other.closed then other:forward(e.msg, e.line) end
    end
    room.q, room.qBytes = {}, 0
    self.log:info("relay: room %s ended (%s left)", room.code, conn == room.a and "host" or "guest")
  else
    self.log:info("relay: room %s closed before a guest came", room.code)
  end
  self:closeRoom(room, "peer gone")
end

function Relay:update()
  local now = self.now()
  local rate, burst = self.cfg.bytesPerSecond, self.cfg.burstBytes
  for code, room in pairs(self.rooms) do
    if room.state == "waiting" then
      if now - room.created > self.cfg.roomTtl then
        self.log:info("relay: room %s expired unjoined", code)
        self:closeRoom(room, "expired")
      end
    elseif #room.q > 0 then
      room.tokens = math.min(burst, room.tokens + (now - room.tokensAt) * rate)
      room.tokensAt = now
      local i = 1
      while i <= #room.q and room.tokens > 0 do
        local e = room.q[i]
        if not e.to.closed then
          e.to:forward(e.msg, e.line)
          self.stats.bytes = self.stats.bytes + e.n
        end
        room.tokens = room.tokens - e.n
        room.qBytes = room.qBytes - e.n
        i = i + 1
      end
      if i > 1 then
        local rest = {}
        for j = i, #room.q do rest[#rest + 1] = room.q[j] end
        room.q = rest
      end
    else
      room.tokens = math.min(burst, room.tokens + (now - room.tokensAt) * rate)
      room.tokensAt = now
    end
  end
end

function Relay:snapshot()
  local list = {}
  for code, room in pairs(self.rooms) do
    list[#list + 1] = { code = code, state = room.state, age = math.floor(self.now() - room.created),
                        queued = room.qBytes }
  end
  table.sort(list, function(a, b) return a.code < b.code end)
  return list
end

return Relay
