-- Ladder rung L5: the pokeserver-compatible TCP relay, as an OPTIONAL
-- fallback.  It is only tried when the player's settings allow it
-- (opts.allowRelay), because it sends traffic through a third party
-- (docs/online-design.md 2.13 decision 1).
--
-- Net.lua already speaks this protocol (newline-delimited JSON; {type=
-- "host"} -> {type="hosted", code}; {type="join", code} -> "paired" |
-- "join_error" | "peer_gone"), but Net:connectTCP blocks for up to 5 s.
-- These jobs make the TCP connect non-blocking, then hand the socket to a
-- plain Net object, so the result IS a Net relay connection and LinkState,
-- LinkBattle and Tournament treat it exactly as before.
--
--   Relay.join(address, code, opts) -> job ; job.net once paired
--   Relay.host(address, opts) -> job ; job.code once the relay answers,
--                                      job.net (paired) when a guest joins

local Util = require("src.online.net.Util")
local Dns = require("src.online.net.Dns")
local Net = require("src.link.Net")

local Relay = {}

Relay.CONNECT_TIMEOUT = 5
Relay.PAIR_TIMEOUT = 10

-- non-blocking TCP connect (call inside a job)
function Relay.connect(address, timeout)
  local socket = Util.socket
  if not socket then return nil, "online play needs luasocket" end
  local host, port = Util.splitEndpoint(address or Net.defaultRelayAddress(), 7778)
  local ip, why = Dns.resolve(host, timeout)
  if not ip then return nil, why end
  local tcp = Util.tcp()
  tcp:settimeout(0)
  local ok, err = tcp:connect(ip, port)
  if not ok and err ~= "timeout" and err ~= "Operation already in progress" then
    tcp:close()
    return nil, ("can't reach relay %s:%d (%s)"):format(host, port, tostring(err))
  end
  if not ok then
    local deadline = Util.time() + (timeout or Relay.CONNECT_TIMEOUT)
    while true do
      local _, w = socket.select(nil, { tcp }, 0)
      if w and #w > 0 and tcp:getpeername() then break end
      if Util.time() > deadline then
        tcp:close()
        return nil, ("no answer from relay %s:%d"):format(host, port)
      end
      Util.yield()
    end
  end
  return tcp
end

local function wrap(tcp, mode)
  local net = Net.new()
  net.tcpSocket = tcp
  net.rxBuf, net.txBuf = "", ""
  net.mode = mode
  return net
end

function Relay.join(address, code, opts)
  opts = opts or {}
  return Util.job(function(job)
    local tcp, why = Relay.connect(address, opts.timeout)
    if not tcp then return nil, why end
    local net = wrap(tcp, "onlineJoining")
    net.target = code
    job.net = net
    net:send({ type = "join", code = code })
    local deadline = Util.time() + (opts.pairTimeout or Relay.PAIR_TIMEOUT)
    while true do
      net:update()
      if net.paired then return net end
      if net.closed or net.error then
        local e = net.error or "relay closed the connection"
        net:close()
        return nil, e
      end
      if Util.time() > deadline then
        net:close()
        return nil, "relay didn't pair us"
      end
      Util.yield()
    end
  end)
end

function Relay.host(address, opts)
  opts = opts or {}
  return Util.job(function(job)
    local tcp, why = Relay.connect(address, opts.timeout)
    if not tcp then return nil, why end
    local net = wrap(tcp, "onlineHosting")
    job.net = net
    net:send({ type = "host" })
    while true do
      net:update()
      if net.code and not job.code then job.code = net.code end
      if net.paired then return net end
      if net.closed or net.error then
        local e = net.error or "relay closed the connection"
        net:close()
        return nil, e
      end
      Util.yield()
    end
  end)
end

return Relay
