-- The hub's TCP port: newline-delimited JSON, the pokeserver relay protocol
-- (src/link/Net.lua's TCP backend).  Non-blocking luasocket; every line is
-- size-, depth- and shape-checked by WS1's Wire.decode before the hub sees
-- it.
--
--   local s = LineServer.new{ bind = "*", port = 7778, hub = hub, now = fn }
--   s:listen() -> ok, err ; s:update() ; s:close()
--
-- hub:accept(conn) -> bool, hub:message(conn, msg, line), hub:closed(conn),
-- hub:canRead(conn) -> bool (relay backpressure).

local Conn = require("src.online.hub.Conn")
local Wire = require("src.online.net.Wire")

local LineServer = {}
LineServer.__index = LineServer

LineServer.MAX_LINE = Wire.MAX_RELIABLE   -- 64 KB
LineServer.MAX_BAD = 16
LineServer.READS_PER_UPDATE = 8

function LineServer.new(opts)
  return setmetatable({ bind = opts.bind or "*", port = opts.port, hub = opts.hub,
                        now = opts.now, log = opts.log, conns = {}, count = 0 }, LineServer)
end

function LineServer:listen()
  local ok, socket = pcall(require, "socket")
  if not ok or not socket then return false, "the TCP port needs luasocket" end
  local srv = (socket.tcp4 or socket.tcp)()
  pcall(srv.setoption, srv, "reuseaddr", true)
  local bindIp = (self.bind == "*" or self.bind == nil) and "0.0.0.0" or self.bind
  local okB, err = srv:bind(bindIp, self.port)
  if not okB then
    srv:close()
    return false, ("can't open TCP %s:%d (%s)"):format(bindIp, self.port, tostring(err))
  end
  local okL, errL = srv:listen(64)
  if not okL then
    srv:close()
    return false, tostring(errL)
  end
  srv:settimeout(0)
  self.srv = srv
  local _, port = srv:getsockname()
  self.boundPort = tonumber(port) or self.port
  return true
end

function LineServer:remove(conn)
  if self.conns[conn.id] then
    self.conns[conn.id] = nil
    self.count = self.count - 1
    conn:drop(conn.closeReason or "closed")
    self.hub:closed(conn)
  end
end

function LineServer:acceptAll(now)
  for _ = 1, 64 do
    local sock = self.srv:accept()
    if not sock then break end
    sock:settimeout(0)
    pcall(sock.setoption, sock, "tcp-nodelay", true)
    local ip, port = sock:getpeername()
    local conn = Conn.tcp(sock, ip, port, now)
    if self.hub:accept(conn) then
      self.conns[conn.id] = conn
      self.count = self.count + 1
    else
      pcall(sock.close, sock)
    end
  end
end

function LineServer:readConn(conn)
  for _ = 1, LineServer.READS_PER_UPDATE do
    if conn.closed or conn.closing or not self.hub:canRead(conn) then return end
    local data, err, partial = conn.sock:receive(8192)
    local chunk = data or partial
    if chunk and #chunk > 0 then
      conn.rx = conn.rx .. chunk
      conn.bytesIn = conn.bytesIn + #chunk
    end
    -- whole lines out, one at a time (the relay may stop reading mid-way)
    while not conn.closed do
      local nl = conn.rx:find("\n", 1, true)
      if not nl then break end
      local line = conn.rx:sub(1, nl - 1):gsub("\r$", "")
      conn.rx = conn.rx:sub(nl + 1)
      if #line > LineServer.MAX_LINE then
        conn:drop("line too long")
        return
      end
      if #line > 0 then
        local msg, why = Wire.decode(line, 0)
        if msg then
          self.hub:message(conn, msg, line)
        else
          conn.bad = (conn.bad or 0) + 1
          if conn.bad == 1 and self.log then
            self.log:debug("tcp: dropped a message from %s: %s", self.log:addr(conn.address), tostring(why))
          end
          if conn.bad >= LineServer.MAX_BAD then
            conn:drop("too many bad messages")
            return
          end
        end
      end
    end
    if #conn.rx > LineServer.MAX_LINE then
      conn:drop("line too long")
      return
    end
    if err == "closed" then
      conn:drop("peer closed")
      return
    elseif err and err ~= "timeout" then
      conn:drop(tostring(err))
      return
    end
    if not data then return end
  end
end

function LineServer:update()
  if not self.srv then return end
  local now = self.now()
  self:acceptAll(now)
  for _, conn in pairs(self.conns) do
    if not conn.closed then self:readConn(conn) end
    if not conn.closed then conn:flush() end
    if conn.closing and not conn.closed and #conn.tx == 0 then conn:drop(conn.closeReason) end
    if conn.closed then self:remove(conn) end
  end
end

function LineServer:close()
  for _, conn in pairs(self.conns) do
    conn:flush()
    self:remove(conn)
  end
  if self.srv then pcall(self.srv.close, self.srv) end
  self.srv = nil
end

return LineServer
