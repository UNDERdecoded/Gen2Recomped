-- One client connection, whatever carries it.  The relay, the tournaments
-- and the rendezvous only ever call these, so a TCP pokeserver client and an
-- ENet client can share a room:
--
--   conn.id, conn.kind ("tcp"|"enet"|"test"), conn.ip, conn.address
--   conn:send(msg[, channel])      a message table
--   conn:forward(msg, line)        relay a message; `line` is its original
--                                  JSON text when the sender was TCP
--   conn:close(reason)             after what is queued has gone out
--   conn.closed                    true once gone (either side)
--   conn.role                      nil | "room" | "tournament" | "rendezvous" | "gts"
--   conn.lastSeen                  time of its last message
--
-- Every connection also carries a token bucket for its control messages
-- (Conn.allow), so one client can't flood the hub with requests.

local Json = require("src.link.Json")

local Conn = {}

local nextId = 0
local function newId()
  nextId = nextId + 1
  return nextId
end

local function base(kind, ip, address, now)
  return { id = newId(), kind = kind, ip = ip, address = address, opened = now,
           lastSeen = now, tokens = nil, bytesIn = 0, bytesOut = 0 }
end

-- message-rate bucket: false when the connection is over its rate
function Conn.allow(conn, now, perSecond, burst)
  local t = conn.tokens
  if t == nil then
    t = burst
    conn.tokensAt = now
  else
    t = math.min(burst, t + (now - (conn.tokensAt or now)) * perSecond)
    conn.tokensAt = now
  end
  if t < 1 then
    conn.tokens = t
    return false
  end
  conn.tokens = t - 1
  return true
end

---------------------------------------------------------------- TCP

local Tcp = {}
Tcp.__index = Tcp
Conn.Tcp = Tcp

function Conn.tcp(sock, ip, port, now)
  local c = base("tcp", ip, ("%s:%s"):format(tostring(ip), tostring(port)), now)
  c.sock, c.rx, c.tx, c.txBytes = sock, "", {}, 0
  return setmetatable(c, Tcp)
end

function Tcp:sendLine(line)
  if self.closed or self.closing then return end
  self.tx[#self.tx + 1] = line .. "\n"
  self.txBytes = self.txBytes + #line + 1
  self.bytesOut = self.bytesOut + #line + 1
end

function Tcp:send(msg)
  local ok, line = pcall(Json.encode, msg)
  if ok then self:sendLine(line) end
end

function Tcp:forward(msg, line)
  if line then self:sendLine(line) else self:send(msg) end
end

function Tcp:close(reason)
  if self.closed then return end
  self.closing = true
  self.closeReason = self.closeReason or reason
end

-- write what is queued; true while something is still waiting
function Tcp:flush()
  if self.closed then return false end
  while #self.tx > 0 do
    local chunk = self.tx[1]
    local sent, err, last = self.sock:send(chunk)
    if sent then
      table.remove(self.tx, 1)
      self.txBytes = self.txBytes - #chunk
    elseif err == "timeout" then
      local n = last or 0
      if n > 0 then
        self.tx[1] = chunk:sub(n + 1)
        self.txBytes = self.txBytes - n
      end
      return true
    else
      self:drop(err or "send failed")
      return false
    end
  end
  return false
end

function Tcp:drop(reason)
  if self.closed then return end
  self.closed = true
  self.closeReason = self.closeReason or reason
  pcall(self.sock.close, self.sock)
end

---------------------------------------------------------------- ENet

local Enet = {}
Enet.__index = Enet
Conn.Enet = Enet

function Conn.enet(transport, peerId, address, now)
  local ip = tostring(address or ""):match("^([%d%.]+)")
  local c = base("enet", ip, address, now)
  c.t, c.peerId = transport, peerId
  return setmetatable(c, Enet)
end

function Enet:send(msg, channel)
  if self.closed then return end
  self.t:send(self.peerId, msg, channel or 0)
end

function Enet:forward(msg) self:send(msg, 0) end

function Enet:close(reason)
  if self.closed then return end
  self.closed = true
  self.closeReason = self.closeReason or reason
  self.t:disconnect(self.peerId)
end

---------------------------------------------------------------- test

-- an in-memory connection for the self-test: what the hub sends lands in
-- conn.out
local Test = {}
Test.__index = Test
Conn.Test = Test

function Conn.test(ip, now)
  local c = base("test", ip or "127.0.0.1", (ip or "127.0.0.1") .. ":1", now or 0)
  c.out = {}
  return setmetatable(c, Test)
end

function Test:send(msg)
  if self.closed then return end
  self.out[#self.out + 1] = Json.decode(Json.encode(msg))
end

function Test:forward(msg) self:send(msg) end

function Test:close(reason)
  self.closed = true
  self.closeReason = self.closeReason or reason
end

function Test:take()
  local out = self.out
  self.out = {}
  return out
end

return Conn
