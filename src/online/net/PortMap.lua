-- Router port mapping with no server: UPnP-IGD, NAT-PMP and PCP (ladder
-- rung L1, docs/online-design.md 2.1).
--
--   UPnP-IGD  SSDP M-SEARCH to 239.255.255.250:1900 (UDP), HTTP GET of the
--             device description, SOAP AddPortMapping / DeletePortMapping /
--             GetExternalIPAddress on the WAN*Connection control URL.
--   NAT-PMP   RFC 6886, unicast UDP to gateway:5351.
--   PCP       RFC 6887 MAP/ANNOUNCE, unicast UDP to gateway:5351.
--
-- Every network step yields between polls (Util.yield), so run these
-- inside a Util.job and resume it once per frame; nothing here blocks a
-- frame.  Called outside a job they nap instead (tools, exit-time unmap).
--
--   PortMap.discover(opts|timeout) -> gw | nil, why
--   PortMap.map(gw, port, "UDP", lease, opts) -> externalIp, extPort, note | nil, why
--   PortMap.unmap(gw, port, "UDP") -> true | nil, why
--   PortMap.externalIp(gw) -> ip | nil, why
--   PortMap.open(opts) -> job   (discover + map in a coroutine job;
--                                job.mapping = { ip, port, method, note })
--   PortMap.releaseAll(budget)  synchronous unmap of everything this
--                                process mapped, bounded by `budget` s
--
-- opts (tests point these at a fake local IGD; nothing else is contacted):
--   gateways = { "192.168.1.1" | "ip:port", ... }  NAT-PMP/PCP targets
--                 (default: <lan>.1 and <lan>.254 of the outbound interface)
--   ssdpAddress = "239.255.255.250", ssdpPort = 1900
--   upnp / natpmp / pcp = false to skip a method
--   timeout = seconds for discovery (default 3)
--
-- The parse/build functions are pure and fixture-tested in
-- tests/online_portmap_test.lua.

local Util = require("src.online.net.Util")
local HttpLite = require("src.online.net.HttpLite")

local PortMap = {}

PortMap.PMP_PORT = 5351
PortMap.SSDP_ADDRESS = "239.255.255.250"
PortMap.SSDP_PORT = 1900
PortMap.DEFAULT_LEASE = 3600
PortMap.DESCRIPTION = "Gen2Recomped link"

PortMap.active = {} -- key -> { gw, port, proto, extPort }

---------------------------------------------------------------- SSDP

PortMap.SEARCH_TARGETS = {
  "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
  "urn:schemas-upnp-org:device:InternetGatewayDevice:2",
  "urn:schemas-upnp-org:service:WANIPConnection:1",
  "urn:schemas-upnp-org:service:WANPPPConnection:1",
}

function PortMap.ssdpRequest(st, mx)
  return table.concat({
    "M-SEARCH * HTTP/1.1",
    "HOST: 239.255.255.250:1900",
    'MAN: "ssdp:discover"',
    "MX: " .. tostring(mx or 2),
    "ST: " .. st,
    "", "",
  }, "\r\n")
end

-- an SSDP search reply -> { location, st, usn, server } | nil
function PortMap.parseSsdp(data)
  if type(data) ~= "string" then return nil end
  if not data:match("^HTTP/%d%.%d%s+200") then return nil end
  local h = {}
  for line in data:gmatch("[^\r\n]+") do
    local k, v = line:match("^([^:]+):%s*(.-)%s*$")
    if k then h[k:lower()] = v end
  end
  if not h.location or not HttpLite.parseUrl(h.location) then return nil end
  return { location = h.location, st = h.st, usn = h.usn, server = h.server }
end

---------------------------------------------------------------- device XML

local function tagText(xml, tag)
  local v = xml:match("<" .. tag .. "[^>]*>%s*(.-)%s*</" .. tag .. ">")
  if not v then
    v = xml:match("<[%w_]+:" .. tag .. "[^>]*>%s*(.-)%s*</[%w_]+:" .. tag .. ">")
  end
  return v
end

local SERVICE_RANK = {
  ["urn:schemas-upnp-org:service:WANIPConnection:2"] = 1,
  ["urn:schemas-upnp-org:service:WANIPConnection:1"] = 2,
  ["urn:schemas-upnp-org:service:WANPPPConnection:1"] = 3,
}

-- device description -> { controlURL (absolute), serviceType, friendlyName }
function PortMap.parseDescription(xml, location)
  if type(xml) ~= "string" then return nil, "no description" end
  local base = tagText(xml, "URLBase")
  if not base or base == "" then base = location end
  local best, bestRank
  for block in xml:gmatch("<service>(.-)</service>") do
    local st = tagText(block, "serviceType")
    local ctl = tagText(block, "controlURL")
    local rank = st and SERVICE_RANK[st]
    if rank and ctl and ctl ~= "" and (not bestRank or rank < bestRank) then
      best, bestRank = { serviceType = st, controlURL = ctl }, rank
    end
  end
  if not best then return nil, "router has no WAN connection service" end
  best.controlURL = HttpLite.resolve(base, best.controlURL)
  best.friendlyName = tagText(xml, "friendlyName")
  return best
end

---------------------------------------------------------------- SOAP

local function xmlEscape(s)
  return (tostring(s):gsub("[<>&\"']", {
    ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ['"'] = "&quot;", ["'"] = "&apos;",
  }))
end

-- args: ordered list of { name, value } (UPnP requires argument order)
function PortMap.soapBody(serviceType, action, args)
  local parts = {
    '<?xml version="1.0"?>',
    '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" ',
    's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>',
    ('<u:%s xmlns:u="%s">'):format(action, serviceType),
  }
  for _, a in ipairs(args or {}) do
    parts[#parts + 1] = ("<%s>%s</%s>"):format(a[1], xmlEscape(a[2]), a[1])
  end
  parts[#parts + 1] = ("</u:%s></s:Body></s:Envelope>"):format(action)
  return table.concat(parts)
end

function PortMap.soapHeaders(serviceType, action)
  return {
    ["Content-Type"] = 'text/xml; charset="utf-8"',
    ["SOAPAction"] = ('"%s#%s"'):format(serviceType, action),
  }
end

-- response -> fields table | nil, errorCode, errorDescription
function PortMap.parseSoap(status, body)
  body = body or ""
  if status == 200 then
    local fields = {}
    for k, v in body:gmatch("<(New[%w_]+)[^>]*>(.-)</%1>") do fields[k] = v end
    for k in body:gmatch("<(New[%w_]+)%s*/>") do fields[k] = "" end
    return fields
  end
  local code = tonumber(tagText(body, "errorCode") or "")
  local desc = tagText(body, "errorDescription")
  return nil, code or status, desc or ("HTTP " .. tostring(status))
end

PortMap.UPNP_ERRORS = {
  [402] = "invalid arguments", [501] = "action failed",
  [606] = "not authorized", [714] = "no such mapping",
  [715] = "wildcard source not allowed", [716] = "wildcard port not allowed",
  [718] = "port already mapped by another device",
  [724] = "router needs equal internal and external ports",
  [725] = "router only allows permanent mappings",
  [726] = "remote host must be a wildcard", [727] = "external port must be a wildcard",
  [728] = "router's mapping table is full",
}

local function soapCall(gw, action, args, timeout)
  local body = PortMap.soapBody(gw.serviceType, action, args)
  local res, why = HttpLite.request{
    method = "POST", url = gw.controlURL, body = body, timeout = timeout or 3,
    headers = PortMap.soapHeaders(gw.serviceType, action),
  }
  if not res then return nil, nil, why end
  return PortMap.parseSoap(res.status, res.body)
end

---------------------------------------------------------------- NAT-PMP

PortMap.PMP_RESULTS = {
  [0] = "ok", [1] = "unsupported version", [2] = "not authorized (NAT-PMP disabled?)",
  [3] = "network failure", [4] = "out of resources", [5] = "unsupported opcode",
}

-- op 0 = external address; 1 = map UDP; 2 = map TCP
function PortMap.natpmpRequest(op, internalPort, externalPort, lifetime)
  if op == 0 then return string.char(0, 0) end
  return string.char(0, op, 0, 0) .. Util.u16(internalPort)
      .. Util.u16(externalPort or internalPort) .. Util.u32(lifetime or 0)
end

function PortMap.parseNatpmp(data)
  if type(data) ~= "string" or #data < 8 then return nil, "short reply" end
  local ver, op = data:byte(1, 2)
  if ver ~= 0 then return nil, "not NAT-PMP" end
  if op < 128 then return nil, "not a reply" end
  local r = { op = op - 128, result = Util.rd16(data, 3), epoch = Util.rd32(data, 5) }
  -- error replies (e.g. "unsupported version" to a PCP packet) are 8 bytes
  if r.result ~= 0 then return r end
  if r.op == 0 then
    if #data < 12 then return nil, "short reply" end
    r.ip = Util.ipFromBytes(data, 9)
  else
    if #data < 16 then return nil, "short reply" end
    r.internalPort = Util.rd16(data, 9)
    r.externalPort = Util.rd16(data, 11)
    r.lifetime = Util.rd32(data, 13)
  end
  return r
end

---------------------------------------------------------------- PCP

PortMap.PCP_RESULTS = {
  [0] = "ok", [1] = "unsupported version", [2] = "not authorized",
  [3] = "malformed request", [4] = "unsupported opcode", [5] = "unsupported option",
  [6] = "malformed option", [7] = "network failure", [8] = "no resources",
  [9] = "unsupported protocol", [10] = "user quota exceeded",
  [11] = "cannot provide external address", [12] = "address mismatch (double NAT?)",
  [13] = "excessive remote peers",
}

local function mappedV4(ip)
  return string.rep("\0", 10) .. "\255\255" .. (Util.ipBytes(ip) or "\0\0\0\0")
end

function PortMap.pcpAnnounce(clientIp)
  return string.char(2, 0, 0, 0) .. Util.u32(0) .. mappedV4(clientIp)
end

-- MAP request (60 bytes)
function PortMap.pcpMapRequest(o)
  local proto = (o.proto == "TCP") and 6 or 17
  return string.char(2, 1, 0, 0) .. Util.u32(o.lifetime or 0) .. mappedV4(o.clientIp)
      .. o.nonce .. string.char(proto, 0, 0, 0)
      .. Util.u16(o.internalPort) .. Util.u16(o.externalPort or o.internalPort)
      .. mappedV4(o.externalIp or "0.0.0.0")
end

function PortMap.parsePcp(data)
  if type(data) ~= "string" or #data < 24 then return nil, "short reply" end
  local ver, rop = data:byte(1, 2)
  if ver ~= 2 then return nil, "not PCP", ver end
  if rop < 128 then return nil, "not a reply" end
  local r = { op = rop - 128, result = data:byte(4), lifetime = Util.rd32(data, 5),
              epoch = Util.rd32(data, 9) }
  if r.op == 1 and #data >= 60 then
    r.nonce = data:sub(25, 36)
    r.proto = data:byte(37)
    r.internalPort = Util.rd16(data, 41)
    r.externalPort = Util.rd16(data, 43)
    r.ip = Util.ipFromBytes(data, 57)
  end
  return r
end

---------------------------------------------------------------- UDP exchange

-- send `request` to host:port, retransmitting (RFC 6886: 250 ms doubling)
-- until `accept(data)` returns a value or the deadline passes
local function udpExchange(host, port, request, accept, timeout)
  local socket = Util.socket
  if not socket then return nil, "no luasocket" end
  local udp = Util.udp()
  udp:settimeout(0)
  local ok, err = udp:setpeername(host, port)
  if not ok then udp:close() return nil, tostring(err) end
  local deadline = Util.time() + (timeout or 1.5)
  local nextSend, gap = 0, 0.25
  local lastWhy = "no answer"
  while Util.time() < deadline do
    if Util.time() >= nextSend then
      udp:send(request)
      nextSend = Util.time() + gap
      gap = gap * 2
    end
    local data, rerr = udp:receive()
    if data then
      local v, why = accept(data)
      if v then udp:close() return v end
      lastWhy = why or lastWhy
    elseif rerr and rerr ~= "timeout" then
      -- ICMP port unreachable: nothing listens on 5351 there
      udp:close()
      return nil, "nothing answers on " .. host .. ":" .. port .. " (" .. tostring(rerr) .. ")"
    else
      Util.yield()
    end
  end
  udp:close()
  return nil, lastWhy
end

local function gatewayCandidates(opts)
  if opts.gateways then return opts.gateways end
  local lan = Util.lanIP()
  local a, b, c = Util.parseIPv4(lan or "")
  if not a or not Util.isPrivate(lan) or a == 127 then return {} end
  return { ("%d.%d.%d.1"):format(a, b, c), ("%d.%d.%d.254"):format(a, b, c) }
end

-- probe NAT-PMP/PCP on every candidate gateway in parallel on one socket
local function probePmp(opts, timeout)
  local socket = Util.socket
  if not socket then return nil, "no luasocket" end
  local cands = gatewayCandidates(opts)
  if #cands == 0 then return nil, "no gateway address to ask" end
  local udp = Util.udp()
  udp:settimeout(0)
  udp:setsockname("0.0.0.0", 0)
  local targets = {}
  for _, c in ipairs(cands) do
    local host, port = Util.splitEndpoint(c, PortMap.PMP_PORT)
    if Util.isIPv4(host) then
      targets[#targets + 1] = { host = host, port = port,
                                clientIp = Util.lanIP(host) or "0.0.0.0" }
    end
  end
  local deadline = Util.time() + timeout
  local nextSend, gap = 0, 0.25
  local found = {}
  local settleAt = nil
  while Util.time() < deadline do
    if Util.time() >= nextSend then
      for _, tg in ipairs(targets) do
        if opts.pcp ~= false then
          udp:sendto(PortMap.pcpAnnounce(tg.clientIp), tg.host, tg.port)
        end
        if opts.natpmp ~= false then
          udp:sendto(PortMap.natpmpRequest(0), tg.host, tg.port)
        end
      end
      nextSend = Util.time() + gap
      gap = gap * 2
    end
    local data, ip, port = udp:receivefrom()
    if data then
      for _, tg in ipairs(targets) do
        if tg.host == ip and tg.port == port then
          local first = data:byte(1)
          if first == 2 then
            local r = PortMap.parsePcp(data)
            tg.pcpAnswered = true
            if r and r.op == 0 and r.result == 0 then tg.pcp = true end
          elseif first == 0 then
            local r = PortMap.parseNatpmp(data)
            if r and r.op == 0 and r.result == 1 then
              -- a NAT-PMP-only box rejecting our PCP packet
              tg.pcpAnswered = true
            elseif r and r.op == 0 and r.result == 0 then
              tg.pmpAnswered = true
              tg.natpmp = true
              tg.externalIp = r.ip
            elseif r and r.result then
              tg.pmpAnswered = true
              tg.pmpWhy = PortMap.PMP_RESULTS[r.result] or ("error " .. r.result)
            end
          end
          if (tg.pcp or tg.natpmp) and not found[tg] then
            found[tg] = true
            settleAt = settleAt or (Util.time() + 0.3)
          end
        end
      end
    else
      if settleAt and Util.time() >= settleAt then break end
      Util.yield()
    end
    -- stop early once every gateway has answered both questions
    local all = true
    for _, tg in ipairs(targets) do
      if not ((tg.pcpAnswered or opts.pcp == false) and (tg.pmpAnswered or opts.natpmp == false)) then
        all = false
      end
    end
    if all then break end
  end
  udp:close()
  local prefer = opts.prefer or "pcp"
  for _, tg in ipairs(targets) do
    if found[tg] then
      local kind = (tg.pcp and (prefer == "pcp" or not tg.natpmp)) and "pcp" or "natpmp"
      return { kind = kind, host = tg.host, port = tg.port, clientIp = tg.clientIp,
               localIp = tg.clientIp, externalIp = tg.externalIp,
               pcp = tg.pcp, natpmp = tg.natpmp }
    end
  end
  for _, tg in ipairs(targets) do
    if tg.pmpWhy then return nil, "NAT-PMP: " .. tg.pmpWhy end
  end
  return nil, "no NAT-PMP/PCP answer from " .. table.concat(cands, ", ")
end

local function probeUpnp(opts, timeout)
  local socket = Util.socket
  if not socket then return nil, "no luasocket" end
  local udp = Util.udp()
  udp:settimeout(0)
  udp:setsockname("0.0.0.0", 0)
  pcall(udp.setoption, udp, "ip-multicast-ttl", 2)
  local addr = opts.ssdpAddress or PortMap.SSDP_ADDRESS
  local port = opts.ssdpPort or PortMap.SSDP_PORT
  local deadline = Util.time() + timeout
  local nextSend, sends = 0, 0
  local tried, lastWhy = {}, nil
  while Util.time() < deadline do
    if Util.time() >= nextSend and sends < 2 then
      for _, st in ipairs(PortMap.SEARCH_TARGETS) do
        udp:sendto(PortMap.ssdpRequest(st, 2), addr, port)
      end
      sends = sends + 1
      nextSend = Util.time() + 1
    end
    local data = udp:receivefrom()
    if data then
      local r = PortMap.parseSsdp(data)
      if r and not tried[r.location] then
        tried[r.location] = true
        local left = math.max(0.5, deadline - Util.time())
        local res, why = HttpLite.request{ method = "GET", url = r.location,
                                           timeout = math.min(3, left) }
        if res and res.status == 200 then
          local svc, perr = PortMap.parseDescription(res.body, r.location)
          if svc then
            udp:close()
            local host = HttpLite.parseUrl(svc.controlURL).host
            svc.kind = "upnp"
            svc.location = r.location
            svc.host = host
            svc.localIp = Util.lanIP(host)
            return svc
          end
          lastWhy = perr
        else
          lastWhy = "description: " .. tostring(why or (res and ("HTTP " .. res.status)))
        end
      end
    else
      Util.yield()
    end
  end
  udp:close()
  return nil, lastWhy or "no UPnP router answered"
end

-- find something that can map a port.  Tries NAT-PMP/PCP first (a quick
-- unicast question), then UPnP (multicast search + HTTP).
function PortMap.discover(opts)
  if type(opts) == "number" then opts = { timeout = opts } end
  opts = opts or {}
  local total = opts.timeout or 3
  local whys = {}
  if opts.natpmp ~= false or opts.pcp ~= false then
    local gw, why = probePmp(opts, math.min(1.5, total))
    if gw then return gw end
    whys[#whys + 1] = why
  end
  if opts.upnp ~= false then
    local gw, why = probeUpnp(opts, math.max(1, total - 1))
    if gw then return gw end
    whys[#whys + 1] = "UPnP: " .. tostring(why)
  end
  return nil, table.concat(whys, "; ")
end

---------------------------------------------------------------- map / unmap

local function key(gw, port, proto)
  return ("%s|%s|%d|%s"):format(gw.kind, gw.host or gw.controlURL, port, proto)
end

function PortMap.externalIp(gw)
  if gw.kind == "upnp" then
    local f, code, desc = soapCall(gw, "GetExternalIPAddress", {})
    if not f then return nil, ("GetExternalIPAddress failed: %s"):format(tostring(desc or code)) end
    local ip = f.NewExternalIPAddress
    if not Util.isIPv4(ip) then return nil, "router reported no external address" end
    return ip
  elseif gw.kind == "natpmp" or gw.kind == "pcp" then
    if gw.externalIp then return gw.externalIp end
    local r, why = udpExchange(gw.host, gw.port, PortMap.natpmpRequest(0), function(d)
      local p = PortMap.parseNatpmp(d)
      if p and p.op == 0 then return p end
    end)
    if not r then return nil, why end
    if r.result ~= 0 then return nil, PortMap.PMP_RESULTS[r.result] end
    gw.externalIp = r.ip
    return r.ip
  end
  return nil, "unknown gateway kind"
end

local function noteFor(ip)
  if Util.isCgnat(ip) then
    return "router's own address is carrier-grade NAT; others can't reach this mapping"
  elseif Util.isPrivate(ip) then
    return "router is behind another router (double NAT); mapping may not be reachable"
  end
  return nil
end

function PortMap.map(gw, port, proto, lease, opts)
  proto = proto or "UDP"
  lease = lease or PortMap.DEFAULT_LEASE
  opts = opts or {}
  local ext = opts.externalPort or port
  if gw.kind == "upnp" then
    local localIp = gw.localIp or Util.lanIP(gw.host)
    if not localIp then return nil, "can't tell this machine's LAN address" end
    local lastWhy
    for _ = 1, 6 do
      local f, code, desc = soapCall(gw, "AddPortMapping", {
        { "NewRemoteHost", "" }, { "NewExternalPort", ext },
        { "NewProtocol", proto }, { "NewInternalPort", port },
        { "NewInternalClient", localIp }, { "NewEnabled", 1 },
        { "NewPortMappingDescription", opts.description or PortMap.DESCRIPTION },
        { "NewLeaseDuration", lease },
      })
      if f then
        local ip, why = PortMap.externalIp(gw)
        if not ip then return nil, why end
        PortMap.active[key(gw, ext, proto)] = { gw = gw, port = port, proto = proto,
                                                extPort = ext }
        return ip, ext, noteFor(ip)
      end
      lastWhy = ("UPnP %s: %s"):format(tostring(code), PortMap.UPNP_ERRORS[code] or tostring(desc))
      if code == 725 and lease ~= 0 then
        lease = 0
      elseif code == 718 then
        ext = ext + 1
      elseif code == 724 and ext ~= port then
        ext = port
      else
        return nil, lastWhy
      end
    end
    return nil, lastWhy
  elseif gw.kind == "natpmp" then
    local op = (proto == "TCP") and 2 or 1
    local r, why = udpExchange(gw.host, gw.port, PortMap.natpmpRequest(op, port, ext, lease),
      function(d)
        local p = PortMap.parseNatpmp(d)
        if p and p.op == op and p.internalPort == port then return p end
      end)
    if not r then return nil, "NAT-PMP: " .. tostring(why) end
    if r.result ~= 0 then
      return nil, "NAT-PMP: " .. (PortMap.PMP_RESULTS[r.result] or ("error " .. r.result))
    end
    local ip, ierr = PortMap.externalIp(gw)
    if not ip then return nil, ierr end
    PortMap.active[key(gw, r.externalPort, proto)] = { gw = gw, port = port, proto = proto,
                                                       extPort = r.externalPort }
    return ip, r.externalPort, noteFor(ip)
  elseif gw.kind == "pcp" then
    gw.nonces = gw.nonces or {}
    local nonce = gw.nonces[port .. proto] or Util.randomBytes(12)
    gw.nonces[port .. proto] = nonce
    local req = PortMap.pcpMapRequest{ clientIp = gw.clientIp, nonce = nonce, proto = proto,
                                       internalPort = port, externalPort = ext,
                                       lifetime = lease }
    local r, why = udpExchange(gw.host, gw.port, req, function(d)
      local p = PortMap.parsePcp(d)
      if p and p.op == 1 and p.nonce == nonce then return p end
    end)
    if not r then return nil, "PCP: " .. tostring(why) end
    if r.result ~= 0 then
      return nil, "PCP: " .. (PortMap.PCP_RESULTS[r.result] or ("error " .. r.result))
    end
    PortMap.active[key(gw, r.externalPort, proto)] = { gw = gw, port = port, proto = proto,
                                                       extPort = r.externalPort }
    return r.ip, r.externalPort, noteFor(r.ip)
  end
  return nil, "unknown gateway kind"
end

-- `port` is the EXTERNAL port for UPnP (what map returned) and the
-- internal port for NAT-PMP/PCP; the same value when the router kept it
function PortMap.unmap(gw, port, proto)
  proto = proto or "UDP"
  local entry
  for k, e in pairs(PortMap.active) do
    if e.gw == gw and e.proto == proto and (e.extPort == port or e.port == port) then
      entry = e
      PortMap.active[k] = nil
    end
  end
  local ext = entry and entry.extPort or port
  local internal = entry and entry.port or port
  if gw.kind == "upnp" then
    local f, code, desc = soapCall(gw, "DeletePortMapping", {
      { "NewRemoteHost", "" }, { "NewExternalPort", ext }, { "NewProtocol", proto },
    }, 1.5)
    if f or code == 714 then return true end
    return nil, ("UPnP %s: %s"):format(tostring(code), tostring(desc))
  elseif gw.kind == "natpmp" then
    local op = (proto == "TCP") and 2 or 1
    local r, why = udpExchange(gw.host, gw.port, PortMap.natpmpRequest(op, internal, 0, 0),
      function(d)
        local p = PortMap.parseNatpmp(d)
        if p and p.op == op then return p end
      end, 1)
    if not r then return nil, why end
    return r.result == 0 or nil, PortMap.PMP_RESULTS[r.result]
  elseif gw.kind == "pcp" then
    local nonce = gw.nonces and gw.nonces[internal .. proto]
    if not nonce then return nil, "unknown mapping" end
    local req = PortMap.pcpMapRequest{ clientIp = gw.clientIp, nonce = nonce, proto = proto,
                                       internalPort = internal, externalPort = 0, lifetime = 0 }
    local r, why = udpExchange(gw.host, gw.port, req, function(d)
      local p = PortMap.parsePcp(d)
      if p and p.op == 1 and p.nonce == nonce then return p end
    end, 1)
    if not r then return nil, why end
    return r.result == 0 or nil, PortMap.PCP_RESULTS[r.result]
  end
  return nil, "unknown gateway kind"
end

---------------------------------------------------------------- jobs

-- discover + map as one frame-friendly job
function PortMap.open(opts)
  opts = opts or {}
  return Util.job(function(job)
    local gw, why = PortMap.discover(opts)
    if not gw then return nil, why end
    job.gateway = gw
    local ip, ext, note = PortMap.map(gw, opts.port or 7777, opts.proto or "UDP",
                                      opts.lease or PortMap.DEFAULT_LEASE, opts)
    if not ip then return nil, ext end
    job.mapping = { ip = ip, port = ext, method = gw.kind, note = note,
                    internalPort = opts.port or 7777, proto = opts.proto or "UDP",
                    lease = opts.lease or PortMap.DEFAULT_LEASE, at = Util.time() }
    return job.mapping
  end)
end

-- re-map before the lease runs out (call from a job)
function PortMap.renew(gw, mapping)
  return PortMap.map(gw, mapping.internalPort, mapping.proto, mapping.lease,
                     { externalPort = mapping.port })
end

-- unmap everything this process mapped; synchronous, bounded (exit path)
function PortMap.releaseAll(budget, tick)
  local list = {}
  for _, e in pairs(PortMap.active) do list[#list + 1] = e end
  if #list == 0 then return 0 end
  local job = Util.job(function()
    for _, e in ipairs(list) do
      pcall(PortMap.unmap, e.gw, e.gw.kind == "upnp" and e.extPort or e.port, e.proto)
    end
  end)
  Util.runSync(job, budget or 1.5, tick)
  return #list
end

return PortMap
