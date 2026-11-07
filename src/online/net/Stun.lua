-- Optional STUN client (RFC 5389 Binding), for learning this machine's
-- public address without a router that speaks UPnP/NAT-PMP.  It contacts a
-- THIRD-PARTY server, so the online settings keep it OFF by default
-- (docs/online-design.md 2.13 decision 3); nothing calls it unless the
-- player turned the "public address finder" on.
--
-- It binds the SAME UDP port the ENet host is about to use, asks, then
-- closes the socket; the NAT mapping it created usually survives until
-- ENet rebinds the port a moment later.  Run inside a Util.job.
--
--   Stun.query{ server = "ip:port" | "name:port", bindPort = 7777,
--               timeout = 3 } -> ip, port | nil, why
--   Stun.request(txid) / Stun.parse(data, txid)   pure, fixture-tested

local Util = require("src.online.net.Util")
local Dns = require("src.online.net.Dns")
local bit = require("bit")

local Stun = {}

Stun.DEFAULT_SERVER = "stun.l.google.com:19302"
Stun.COOKIE = string.char(0x21, 0x12, 0xA4, 0x42)

function Stun.request(txid)
  return string.char(0, 1, 0, 0) .. Stun.COOKIE .. txid
end

local function attrAddress(v, xor)
  if #v < 8 or v:byte(2) ~= 1 then return nil end -- IPv4 only
  local port = Util.rd16(v, 3)
  local a, b, c, d = v:byte(5, 8)
  if xor then
    port = bit.bxor(port, 0x2112)
    a, b, c, d = bit.bxor(a, 0x21), bit.bxor(b, 0x12), bit.bxor(c, 0xA4), bit.bxor(d, 0x42)
  end
  return ("%d.%d.%d.%d"):format(a, b, c, d), port
end

-- Binding success response -> ip, port | nil, why
function Stun.parse(data, txid)
  if type(data) ~= "string" or #data < 20 then return nil, "short reply" end
  if data:sub(5, 8) ~= Stun.COOKIE then return nil, "not STUN" end
  if txid and data:sub(9, 20) ~= txid then return nil, "wrong transaction" end
  local mtype = Util.rd16(data, 1)
  if mtype == 0x0111 then return nil, "server returned an error" end
  if mtype ~= 0x0101 then return nil, "not a binding response" end
  local len = Util.rd16(data, 3)
  local i, stop = 21, math.min(#data, 20 + len)
  local mapped, mport
  while i + 3 <= stop do
    local at, al = Util.rd16(data, i), Util.rd16(data, i + 2)
    local v = data:sub(i + 4, i + 3 + al)
    if at == 0x0020 or at == 0x8020 then
      local ip, port = attrAddress(v, true)
      if ip then return ip, port end
    elseif at == 0x0001 then
      mapped, mport = attrAddress(v, false)
    end
    i = i + 4 + al + ((4 - al % 4) % 4)
  end
  if mapped then return mapped, mport end
  return nil, "no mapped address in reply"
end

function Stun.query(opts)
  opts = opts or {}
  local socket = Util.socket
  if not socket then return nil, "no luasocket" end
  local host, port = Util.splitEndpoint(opts.server or Stun.DEFAULT_SERVER, 3478)
  local timeout = opts.timeout or 3
  local ip, why = Dns.resolve(host, timeout)
  if not ip then return nil, "STUN server: " .. tostring(why) end
  local udp = Util.udp()
  udp:settimeout(0)
  if opts.bindPort then
    -- luasocket resolves "*" to an IPv6 wildcard here, which then can't
    -- sendto an IPv4 server; ENet's "*" means 0.0.0.0, so match it
    local bind = (opts.bind == nil or opts.bind == "*") and "0.0.0.0" or opts.bind
    local ok, err = udp:setsockname(bind, opts.bindPort)
    if not ok then
      udp:close()
      return nil, ("can't bind UDP %d for STUN (%s)"):format(opts.bindPort, tostring(err))
    end
  end
  local txid = Util.randomBytes(12)
  local req = Stun.request(txid)
  local deadline = Util.time() + timeout
  local nextSend, gap = 0, 0.25
  local lastWhy = "no answer from " .. host
  while Util.time() < deadline do
    if Util.time() >= nextSend then
      udp:sendto(req, ip, port)
      nextSend = Util.time() + gap
      gap = gap * 2
    end
    local data, from = udp:receivefrom()
    if data then
      if from == ip then
        local mip, mport = Stun.parse(data, txid)
        if mip then
          udp:close()
          return mip, mport
        end
        lastWhy = mport
      end
    else
      Util.yield()
    end
  end
  udp:close()
  return nil, lastWhy
end

return Stun
