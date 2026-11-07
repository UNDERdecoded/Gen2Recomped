-- LAN discovery: a hosting game broadcasts a small UDP beacon once a
-- second on a fixed port, and the JOIN screen lists every host it hears.
-- (docs/online-design.md 2.6.)  The beacon is tagged with the link
-- protocol and engine series so the list can grey out games that can't
-- link, and it carries the host's port and session nonce: a host that
-- turns discovery on is inviting anyone on its LAN, exactly as a shown
-- code would.
--
--   local b = LanBeacon.newBroadcaster{ info = { name = "RED", game = "red",
--               family = "rby", port = 7777, nonce = 12345 } }
--   b:update() every frame ; b:close()
--   local l = LanBeacon.newListener{} ; l:update() ; l:hosts() ; l:close()
--
-- Platform notes: iOS needs NSLocalNetworkUsageDescription; Android
-- delivers broadcasts without a multicast lock on most devices but some
-- vendors filter them while the screen is off.  Tests point `targets` and
-- `bind` at 127.0.0.1.

local Util = require("src.online.net.Util")
local Json = require("src.link.Json")
local Wire = require("src.online.net.Wire")

local LanBeacon = {}

LanBeacon.PORT = 7778
LanBeacon.MAGIC = "G2RLINK1"
LanBeacon.INTERVAL = 1
LanBeacon.EXPIRE = 4
LanBeacon.MAX_SIZE = 512

function LanBeacon.tag()
  local ok, Version = pcall(require, "src.core.Version")
  if not ok then return "?" end
  local series = tostring(Version.engine or "?"):match("^(%d+%.%d+)") or "?"
  return ("p%s/e%s"):format(tostring(Version.linkProtocol), series)
end

-- pure: info table -> datagram
function LanBeacon.encode(info)
  local msg = { type = "beacon", v = LanBeacon.tag() }
  for k, v in pairs(info or {}) do
    if k ~= "type" then msg[k] = v end
  end
  local data = LanBeacon.MAGIC .. "\n" .. Json.encode(msg)
  if #data > LanBeacon.MAX_SIZE then return nil, "beacon too large" end
  return data
end

-- pure: datagram -> info | nil, why (strict: size, magic, shape, fields)
function LanBeacon.decode(data)
  if type(data) ~= "string" or #data > LanBeacon.MAX_SIZE then return nil, "bad size" end
  local magic, body = data:match("^([^\n]+)\n(.*)$")
  if magic ~= LanBeacon.MAGIC then return nil, "not a beacon" end
  local msg, why = Wire.decode(body, 1)
  if not msg then return nil, why end
  if msg.type ~= "beacon" then return nil, "not a beacon" end
  local port = tonumber(msg.port)
  if not port or port < 1 or port > 65535 or port % 1 ~= 0 then return nil, "bad port" end
  if msg.nonce ~= nil and (type(msg.nonce) ~= "number" or msg.nonce % 1 ~= 0) then
    return nil, "bad nonce"
  end
  if msg.name ~= nil and (type(msg.name) ~= "string" or #msg.name > 32) then
    return nil, "bad name"
  end
  return msg
end

---------------------------------------------------------------- broadcaster

local Broadcaster = {}
Broadcaster.__index = Broadcaster

function LanBeacon.newBroadcaster(opts)
  opts = opts or {}
  local socket = Util.socket
  local self = setmetatable({ info = opts.info or {}, port = opts.port or LanBeacon.PORT,
                              interval = opts.interval or LanBeacon.INTERVAL,
                              nextAt = 0, targets = opts.targets }, Broadcaster)
  if not socket then
    self.error = "no luasocket"
    return self
  end
  local udp = Util.udp()
  udp:settimeout(0)
  pcall(udp.setoption, udp, "broadcast", true)
  self.udp = udp
  if not self.targets then
    self.targets = { "255.255.255.255" }
    local a, b, c = Util.parseIPv4(Util.lanIP() or "")
    if a and a ~= 127 then
      -- directed /24 broadcast too: on a multi-homed PC the limited
      -- broadcast only leaves through one interface
      self.targets[2] = ("%d.%d.%d.255"):format(a, b, c)
    end
  end
  return self
end

function Broadcaster:setInfo(info) self.info = info; self.nextAt = 0 end

function Broadcaster:update()
  if not self.udp then return end
  if Util.time() < self.nextAt then return end
  self.nextAt = Util.time() + self.interval
  local data, why = LanBeacon.encode(self.info)
  if not data then self.error = why return end
  for _, tg in ipairs(self.targets) do
    local ok, err = self.udp:sendto(data, tg, self.port)
    if not ok then self.error = tostring(err) end
  end
  self.sent = (self.sent or 0) + 1
end

function Broadcaster:close()
  if self.udp then self.udp:close() self.udp = nil end
end

---------------------------------------------------------------- listener

local Listener = {}
Listener.__index = Listener

-- Android drops broadcast packets without a WifiManager.MulticastLock
-- (love.system.acquireMulticastLock, an Android bridge: GameActivity.java).
-- Held while any listener is open.  Anywhere else there is no such function.
local locksHeld = 0
local function lockMulticast()
  local sys = love and love.system
  if not (sys and type(sys.acquireMulticastLock) == "function") then return false end
  if locksHeld == 0 then pcall(sys.acquireMulticastLock) end
  locksHeld = locksHeld + 1
  return true
end
local function unlockMulticast()
  local sys = love and love.system
  if locksHeld <= 0 or not (sys and type(sys.releaseMulticastLock) == "function") then return end
  locksHeld = locksHeld - 1
  if locksHeld == 0 then pcall(sys.releaseMulticastLock) end
end

function LanBeacon.newListener(opts)
  opts = opts or {}
  local socket = Util.socket
  local self = setmetatable({ found = {}, ignoreNonce = opts.ignoreNonce,
                              expire = opts.expire or LanBeacon.EXPIRE }, Listener)
  if not socket then
    self.error = "no luasocket"
    return self
  end
  local udp = Util.udp()
  udp:settimeout(0)
  -- several games on one PC can all listen
  pcall(udp.setoption, udp, "reuseaddr", true)
  local ok, err = udp:setsockname(opts.bind or "0.0.0.0", opts.port or LanBeacon.PORT)
  if not ok then
    udp:close()
    self.error = ("can't listen for LAN games (%s)"):format(tostring(err))
    return self
  end
  self.udp = udp
  self.locked = lockMulticast()
  return self
end

function Listener:update()
  if not self.udp then return end
  local tag = LanBeacon.tag()
  for _ = 1, 64 do
    local data, ip = self.udp:receivefrom()
    if not data then break end
    local info = LanBeacon.decode(data)
    if info and Util.isIPv4(ip) and not (self.ignoreNonce and info.nonce == self.ignoreNonce) then
      local key = ip .. ":" .. info.port
      info.ip = ip
      info.address = key
      info.compatible = (info.v == tag)
      info.seenAt = Util.time()
      self.found[key] = info
    end
  end
  local t = Util.time()
  for k, info in pairs(self.found) do
    if t - info.seenAt > self.expire then self.found[k] = nil end
  end
end

-- newest first; each { ip, port, address, name, game, family, nonce, compatible }
function Listener:hosts()
  local out = {}
  for _, info in pairs(self.found) do out[#out + 1] = info end
  table.sort(out, function(a, b) return a.address < b.address end)
  return out
end

function Listener:close()
  if self.udp then self.udp:close() self.udp = nil end
  if self.locked then self.locked = false; unlockMulticast() end
end

-- a discovered host as a Connector invite
function LanBeacon.toInvite(info)
  return { kind = info.kind or 0, lan = info.ip, port = info.port, nonce = info.nonce }
end

return LanBeacon
