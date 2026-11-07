-- An in-memory stand-in for ENet + the network, for headless tests of
-- Transport, Punch and the Connector ladder under plain LuaJIT.
--
--   local net = LoopNet.new()
--   local driver = net:driver("192.168.1.20")     -- one "machine"
--   Transport.new{ driver = driver, port = 7777 }
--   net:rule(function(fromIp, toAddr) return 0.05 end) -- delay, or "drop"
--
-- A driver has the same surface the Transport uses on an ENet host:
-- open/address/connect/service/flush/destroy, and handles that behave like
-- ENet peers (send, disconnect_now, disconnect_later, tostring = "ip:port").
-- Connection attempts to an address nobody listens on (or that the rule
-- drops) simply never answer, as UDP does; the Transport's own deadline
-- turns that into a failure.

local Util = require("src.online.net.Util")

local LoopNet = {}
LoopNet.__index = LoopNet

local Handle = {}
Handle.__index = Handle
Handle.__tostring = function(h) return h.remoteAddr end

local Driver = {}
Driver.__index = Driver

function LoopNet.new()
  return setmetatable({ listeners = {}, nextPort = 40000, queue = {},
                        seq = 0, ruleFn = nil }, LoopNet)
end

function LoopNet:rule(fn) self.ruleFn = fn end

function LoopNet:delay(fromIp, toAddr)
  if self.ruleFn then return self.ruleFn(fromIp, toAddr) end
  return 0
end

function LoopNet:schedule(driver, delay, ev, due)
  self.seq = self.seq + 1
  ev.due = due or (Util.time() + (delay or 0))
  ev.seq = self.seq
  local q = driver.queue
  q[#q + 1] = ev
end

function LoopNet:driver(ip)
  return setmetatable({ net = self, ip = ip or "127.0.0.1", queue = {},
                        open_ = false }, Driver)
end

function Driver:open(bind, port, peerCount, channels)
  local net = self.net
  if port == nil or port == 0 then
    net.nextPort = net.nextPort + 1
    port = net.nextPort
  end
  local addr = Util.endpoint(self.ip, port)
  if net.listeners[addr] then return false, "address in use" end
  self.port = port
  self.addr = addr
  self.open_ = true
  net.listeners[addr] = self
  return true
end

function Driver:address() return self.addr end

local function newHandle(driver, remoteAddr)
  return setmetatable({ driver = driver, remoteAddr = remoteAddr,
                        state = "connecting" }, Handle)
end

function Driver:connect(addr, channels, data)
  if not self.open_ then return nil, "not open" end
  local net = self.net
  local h = newHandle(self, addr)
  local d = net:delay(self.ip, addr)
  local target = net.listeners[addr]
  if d ~= "drop" and target and target.open_ then
    local remote = newHandle(target, self.addr)
    h.other, remote.other = remote, h
    net:schedule(target, d, { type = "connect", peer = remote, data = data or 0,
                              onDeliver = function()
                                remote.state = "connected"
                              end })
    net:schedule(self, 2 * d, { type = "connect", peer = h, data = 0,
                                onDeliver = function()
                                  h.state = "connected"
                                end })
    -- nothing the host sends can overtake the dialler's own "connect"
    h.lastDue = Util.time() + 2 * d
  end
  return h
end

function Driver:service()
  local q = self.queue
  if #q == 0 then return nil end
  local best, bi = nil, nil
  local t = Util.time()
  for i, ev in ipairs(q) do
    if ev.due <= t and (not best or ev.due < best.due
                        or (ev.due == best.due and ev.seq < best.seq)) then
      best, bi = ev, i
    end
  end
  if not best then return nil end
  table.remove(q, bi)
  if best.peer.dead and best.type ~= "disconnect" then
    return self:service()
  end
  if best.onDeliver then best.onDeliver() end
  return { type = best.type, peer = best.peer, data = best.data,
           channel = best.channel }
end

function Driver:flush() end

function Driver:destroy()
  if not self.open_ then return end
  self.open_ = false
  if self.net.listeners[self.addr] == self then
    self.net.listeners[self.addr] = nil
  end
end

function Handle:send(data, channel, flag)
  if self.dead or not self.other then return end
  local net = self.driver.net
  local d = net:delay(self.driver.ip, tostring(self.other.driver.addr))
  if d == "drop" then
    if flag == "reliable" then d = 0.2 else return end
  end
  -- reliable traffic keeps order: never deliver before an earlier packet
  local other = self.other
  local due = Util.time() + d
  if other.lastDue and other.lastDue > due then due = other.lastDue end
  net:schedule(other.driver, nil, { type = "receive", peer = other,
                                    data = data, channel = channel or 0 }, due)
  other.lastDue = due
end

-- the far side hears the disconnect after every packet already in flight
-- to it (ENet's disconnect_later drains the reliable queue first)
local function hangUp(self)
  if self.dead then return end
  self.dead = true
  self.state = "disconnected"
  local other = self.other
  if other and not other.dead and not other.hungUp then
    other.hungUp = true
    local net = self.driver.net
    local due = math.max(Util.time(), other.lastDue or 0)
    net:schedule(other.driver, nil, { type = "disconnect", peer = other, data = 0,
                                      onDeliver = function()
                                        other.dead = true
                                        other.state = "disconnected"
                                      end }, due)
  end
end

Handle.disconnect_now = hangUp

-- a graceful disconnect also reports back to the side that started it
local function hangUpLater(self)
  if self.dead then return end
  hangUp(self)
  self.driver.net:schedule(self.driver, 0, { type = "disconnect", peer = self, data = 0 })
end
Handle.disconnect_later = hangUpLater
Handle.disconnect = hangUpLater

function Handle:connect_id() return 0 end

return LoopNet
