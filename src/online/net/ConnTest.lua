-- THE CONNECTION TEST (ONLINE settings -> CONNECTION TEST): what can be found
-- out about reaching this game WITHOUT any server.
--
--   LAN address     what the outbound interface says
--   the port        can this game's port be opened here at all?
--   the router      PortMap's UPnP / NAT-PMP / PCP: ask it to open the port for
--                   a short lease, read back the outside port and the router's
--                   own idea of its public address, close it again
--   the verdict     whether friends SHOULD be able to reach this game
--
-- It contacts the router only.  It cannot prove the last step (a firewall above
-- the router, or a router that says yes and does nothing): nothing short of a
-- friend's game can, and the report says so.
--
--   ConnTest.start(opts) -> job    a Util.job; resume with job:update() per frame
--     opts: port, portMap (false: not asked), portMapOpts (PortMap's), bind,
--           lanIp, manualAddress, hubAddress, lease
--     job.step      what it is doing now (text)
--     job.result    the result table, once job.state == "done"
--   ConnTest.report(result) -> text, verdict     pure, for the screen and tests
--     verdict: "offline" | "internet" | "manual" | "blocked" | "lan"

local Util = require("src.online.net.Util")

local ConnTest = {}

ConnTest.LEASE = 300  -- seconds: the test's own mapping dies by itself if it is left

-- is this process already holding this port open on the router (a world or a
-- host running)?  Then the test must not close it afterwards.
local function alreadyMapped(PortMap, port)
  for _, m in pairs(PortMap.active or {}) do
    if m.port == port then return true end
  end
  return false
end

local function portFree(port, bind)
  local okU, u = pcall(Util.udp)
  if not okU or not u then return nil end
  local ok, why = u:setsockname(bind or "0.0.0.0", port)
  pcall(u.close, u)
  if ok then return true end
  return false, tostring(why)
end

function ConnTest.start(opts)
  opts = opts or {}
  local port = math.floor(tonumber(opts.port) or 7777)
  return Util.job(function(job)
    local r = { port = port, manualAddress = opts.manualAddress, hubAddress = opts.hubAddress }
    job.step = "Looking at this device..."
    r.lan = opts.lanIp or Util.lanIP()
    Util.yield()
    if not r.lan or r.lan == "127.0.0.1" and not opts.lanIp then
      r.lan = nil
    end
    local free, why = portFree(port, opts.bind)
    r.portFree, r.portWhy = free, why

    if opts.portMap == false then
      r.router = { state = "off" }
      return r
    end
    job.step = "Asking the router..."
    local okP, PortMap = pcall(require, "src.online.net.PortMap")
    if not okP then
      r.router = { state = "none", why = "no sockets on this build" }
      return r
    end
    local pm = {}
    for k, v in pairs(opts.portMapOpts or {}) do pm[k] = v end
    pm.port = port
    local gw, whyGw = PortMap.discover(pm)
    if not gw then
      r.router = { state = "none", why = tostring(whyGw or "no router answered") }
      return r
    end
    job.step = "Asking the router to open the port..."
    local had = alreadyMapped(PortMap, port)
    pm.description = "Link connection test"
    local ip, ext, note = PortMap.map(gw, port, "UDP", tonumber(opts.lease) or ConnTest.LEASE, pm)
    if not ip then
      r.router = { state = "refused", method = gw.kind, why = tostring(ext) }
      return r
    end
    r.router = { state = "ok", method = gw.kind, ip = ip, port = ext, note = note,
                 public = Util.isPublic(ip) }
    if not had then
      job.step = "Closing the port again..."
      pcall(PortMap.unmap, gw, port, "UDP", { externalPort = ext })
    end
    return r
  end)
end

local METHOD = { upnp = "UPnP", natpmp = "NAT-PMP", pcp = "PCP" }

-- the lines the player reads, and the verdict
function ConnTest.report(r)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  local verdict
  add("LAN ADDRESS: " .. (r.lan or "none"))
  if r.portFree == true then
    add(("PORT %d: free on this device."):format(r.port))
  elseif r.portFree == false then
    add(("PORT %d: already in use (fine if you are hosting; otherwise change PORT)."):format(r.port))
  end
  local router = r.router or {}
  if router.state == "off" then
    add("ROUTER: not asked (ROUTER OPENING is off).")
  elseif router.state == "none" then
    add("ROUTER: no answer (" .. tostring(router.why) .. ").")
  elseif router.state == "refused" then
    add(("ROUTER: %s said no (%s)."):format(METHOD[router.method] or tostring(router.method), tostring(router.why)))
  elseif router.state == "ok" then
    add(("ROUTER: %s opened port %d as outside port %d."):format(
      METHOD[router.method] or tostring(router.method), r.port, router.port))
    add("PUBLIC IP (from the router): " .. tostring(router.ip))
    if router.note then add("NOTE: " .. router.note .. ".") end
  end
  if r.manualAddress then add("MY ADDRESS is set: friends are told " .. tostring(r.manualAddress) .. ".") end

  if not r.lan then
    verdict = "offline"
    add("RESULT: no network. Join a Wi-Fi or wired network first.")
  elseif router.state == "ok" and router.public then
    verdict = "internet"
    add("RESULT: friends on this network can join, and friends on the internet SHOULD be able to reach you.")
    add("Your router agreed; only a friend's game can prove it. If they can't get in, let them host instead.")
  elseif r.manualAddress then
    verdict = "manual"
    add("RESULT: friends on this network can join. Friends elsewhere use MY ADDRESS, if your port forward is set up.")
  elseif router.state == "ok" then
    verdict = "blocked"
    add("RESULT: friends on this network can join. Your router's own address isn't public, so friends elsewhere probably can't reach you.")
    add("Let them host, use a Link Hub, or a short code through the relay.")
  else
    verdict = "lan"
    add("RESULT: friends on this network can join. Friends elsewhere probably can't reach you.")
    add(("Forward UDP port %d on your router, let them host, or use a Link Hub."):format(r.port))
  end
  return table.concat(lines, "\n"), verdict
end

return ConnTest
