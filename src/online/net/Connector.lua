-- The reachability ladder (docs/online-design.md 2.1 and 2.3).
--
-- JOIN: one call walks every way of reaching a host's code and says which
-- one worked, or why each one failed:
--
--   local job = Connector.join(invite, opts)       -- alias Connector.connect
--   job:update() every frame
--   job.state   "trying" | "connected" | "failed"
--   job.rung    rung being tried now; job.progress = short text for the UI
--   job.log     { {rung=, state="trying"|"ok"|"failed"|"skipped", reason=}, ... }
--   job.path    winning rung; Connector.describe(job.path) = UI label
--   job.channel Net-API object for LinkState/LinkBattle (it owns the socket:
--               channel:close() tears everything down)
--   job.reason  every rung's failure, one per line, when state == "failed"
--   job:cancel()
--
-- Rungs, in order:
--   lan     L0  the host's LAN address (raced with the next two; LAN wins
--               ties: a public success waits LAN_GRACE s for the LAN one)
--   mapped  L1  the public address the host's router mapped (UPnP/NAT-PMP/PCP)
--   manual  L2  the public IP or DNS name the host typed in its settings
--   punch   L3  simultaneous open: BOTH players entered each other's code
--               (opts.hostJob = my own Connector.host job)
--   hub     L4  a Link Hub introduces the pair, then they punch directly
--   relay   L5  pokeserver-protocol TCP relay; ONLY if opts.allowRelay
--
-- invite (WS2's InviteCode.decode shape; extra fields optional):
--   { kind = 0|1|2|"room", lan = "a.b.c.d", public = "a.b.c.d", port = 7777,
--     publicPort = n, publicVia = "upnp"|"natpmp"|"pcp"|"manual"|"stun",
--     address = "name-or-ip[:port]", nonce = n,
--     hub = { ip|host|address, port, ticket } | "ip:port", ticket = n,
--     room = "ABC234" (short relay code; also invite.code) }
--
-- opts: allowRelay, relayAddress, hostJob, port, driver (tests), timeouts,
--       onProgress(job, entry), maxPeers
--
-- HOST:
--   local h = Connector.host{ port = 7777, portMap = true, stun = false,
--                             lanBeacon = true, beaconInfo = {...},
--                             manualAddress = nil, hub = nil,
--                             allowRelay = false, relayHost = false }
--   h:update() every frame
--   h.state "starting" | "listening" | "connected" | "failed" | "closed"
--   h.pending  true while the router mapping is still being asked for
--   h.info     { lan, port, nonce, public, publicPort, publicVia, note,
--                address, hubTicket, relayCode }
--   h:inviteFields() -> the table WS2's InviteCode.encode takes
--   h.channel / h.path once a guest is in (maxPeers == 1)
--   h:punchTo(theirInvite)  simultaneous open with a code they sent back
--   h:close()               unmaps the port, stops the beacon, closes all
--
-- Hub messages (WS9 implements the hub; this is the client side):
--   -> {type="hub_register", nonce, lan}        <- {type="hub_registered", ticket, observed}
--   -> {type="hub_join", ticket, nonce, lan}
--   <- {type="hub_introduce", endpoint, lan, nonce, role="guest"|"host"}
--   <- {type="hub_error", reason}

local Util = require("src.online.net.Util")
local Transport = require("src.online.net.Transport")
local Punch = require("src.online.net.Punch")
local PortMap = require("src.online.net.PortMap")
local Dns = require("src.online.net.Dns")
local Relay = require("src.online.net.Relay")
local LanBeacon = require("src.online.net.LanBeacon")

local Connector = {}

Connector.TIMEOUTS = { lan = 3, mapped = 6, manual = 6, punch = 10, hub = 12, relay = 10 }
Connector.LAN_GRACE = 0.6
Connector.RUNGS = { "lan", "mapped", "manual", "punch", "hub", "relay" }

Connector.LABELS = {
  lan = "Connected on your local network",
  mapped = "Connected directly (router mapping)",
  manual = "Connected directly (forwarded port)",
  public = "Connected directly",
  punch = "Connected directly (hole punch)",
  hub = "Connected directly (introduced by hub)",
  relay = "Connected via relay",
}

Connector.RUNG_NAMES = {
  lan = "Local network", mapped = "Router mapping", manual = "Forwarded port",
  punch = "Hole punch", hub = "Link Hub", relay = "Relay",
}

function Connector.describe(path) return Connector.LABELS[path] or "Connected" end

---------------------------------------------------------------- helpers

local function logEntry(job, rung, state, reason)
  local entry
  for _, e in ipairs(job.log) do
    if e.rung == rung then entry = e end
  end
  if not entry then
    entry = { rung = rung }
    job.log[#job.log + 1] = entry
  end
  entry.state, entry.reason = state, reason
  if state == "trying" then
    job.rung = rung
    job.progress = ("Trying %s..."):format(Connector.RUNG_NAMES[rung] or rung)
  end
  if job.onProgress then pcall(job.onProgress, job, entry) end
  return entry
end

local function hubEndpoint(invite)
  local hub = invite.hub
  if hub == nil then return nil end
  if type(hub) == "string" then return hub, invite.ticket end
  local host = hub.address or hub.ip or hub.host
  if not host then return nil end
  if not host:find(":") then host = Util.endpoint(host, hub.port or 7777) end
  return host, hub.ticket or invite.ticket, hub.key
end

-- every address a hub code names, LAN first: a friend on the same network
-- reaches the hub without the router's hairpin
local function hubCandidates(invite)
  local first = hubEndpoint(invite)
  local list = {}
  local hub = invite.hub
  if type(hub) == "table" and Util.isIPv4(hub.lan) then
    local ep = Util.endpoint(hub.lan, hub.lanPort or hub.port or 7777)
    if ep ~= first then list[1] = ep end
  end
  if first then list[#list + 1] = first end
  return list
end

local function roomCode(invite)
  local c = invite.room or invite.code or invite.relayCode
  if type(c) == "string" and #c > 0 then return c end
  return nil
end

-- the direct candidates in preference order
local function directCandidates(invite)
  local port = tonumber(invite.port) or Transport.DEFAULT_PORT
  local cands, seen = {}, {}
  -- a hub code's addresses are the HUB's (InviteCode puts them in the
  -- public/lan slots); they are reached through the hub rung, not dialled
  if invite.kind == "hub" or invite.kind == 2 or invite.kind == "short" then
    return cands, port
  end
  local function add(rung, ep)
    if ep and not seen[ep] then
      seen[ep] = true
      cands[#cands + 1] = { rung = rung, ep = ep }
      return true
    end
    return false
  end
  if Util.isIPv4(invite.lan) then add("lan", Util.endpoint(invite.lan, port)) end
  if Util.isIPv4(invite.public) then
    local rung = (invite.publicVia == "manual") and "manual" or "mapped"
    add(rung, Util.endpoint(invite.public, tonumber(invite.publicPort) or port))
  end
  return cands, port
end

-- wait for one of several outgoing attempts; LAN-first with a grace
local function raceDirect(job, t, cands, nonce, timeouts)
  for _, c in ipairs(cands) do
    local id, err = t:connect(c.ep, nonce, { timeout = timeouts[c.rung] })
    if id then
      c.id = id
      logEntry(job, c.rung, "trying", c.ep)
    else
      c.failed = true
      logEntry(job, c.rung, "failed", err)
    end
  end
  while true do
    t:update()
    local now = Util.time()
    local best, pendingBetter = nil, false
    for _, c in ipairs(cands) do
      if c.id and not c.failed then
        local rec = t:peer(c.id)
        local up = rec.state == "connected" and (rec.acked or not nonce)
        if up then
          c.upAt = c.upAt or now
          if not best then best = c end
        elseif rec.state == "closed" then
          c.failed = true
          logEntry(job, c.rung, "failed", rec.reason)
        elseif not best then
          pendingBetter = true
        end
      end
    end
    if best and (not pendingBetter or now - best.upAt >= Connector.LAN_GRACE) then
      for i, c in ipairs(cands) do
        if c ~= best and c.id and not c.failed then
          t:disconnect(c.id, true)
          local won = Connector.RUNG_NAMES[best.rung] or best.rung
          if c.upAt then
            logEntry(job, c.rung, "skipped", ("worked too; %s preferred"):format(won))
          else
            logEntry(job, c.rung, "skipped",
                     ("no answer within %.1f s of %s connecting"):format(Connector.LAN_GRACE, won))
          end
        end
      end
      t:pick(best.id) -- tell the host which connection we kept
      logEntry(job, best.rung, "ok", best.ep)
      return best
    end
    local alive = false
    for _, c in ipairs(cands) do
      if c.id and not c.failed then alive = true end
    end
    if not alive then return nil end
    Util.yield()
  end
end

local function runPunch(job, punch, rung, lanIps)
  while punch:update() == "trying" do Util.yield() end
  if punch.state ~= "connected" then return nil, punch.reason end
  local ip = Util.splitEndpoint(punch.endpoint or "")
  local path = rung
  if lanIps and ip and lanIps[ip] then path = "lan" end
  return punch.peerId, path
end

-- L4: ask a hub to introduce us, then punch from the same socket
local function viaHub(job, t, invite, myNonce, timeout)
  local _, ticket, key = hubEndpoint(invite)
  local candidates = hubCandidates(invite)
  local hubId, hub, err
  local lanIp = Util.lanIP()
  local intro
  for i, hubEp in ipairs(candidates) do
    local host, port = Util.splitEndpoint(hubEp, 7777)
    local ip, why = Dns.resolve(host, 5)
    if ip then
      -- a LAN address is either there at once or not on this network
      local isLast = i == #candidates
      hubId, why = t:connect(Util.endpoint(ip, port), key or 0, { timeout = isLast and 5 or 2.5 })
      if hubId then
        hub = t:channelFor(hubId)
        hub:send({ type = "hub_join", ticket = ticket, nonce = myNonce,
                   lan = (lanIp and t.boundPort) and Util.endpoint(lanIp, t.boundPort) or nil })
        local deadline = Util.time() + (isLast and timeout or 2.5)
        while not intro do
          hub:update()
          for _, m in ipairs(hub:poll()) do
            if m.type == "hub_introduce" and type(m.endpoint) == "string" then
              intro = m
            elseif m.type == "hub_error" then
              t:disconnect(hubId)
              return nil, "hub: " .. tostring(m.reason)
            end
          end
          if hub.closed and not intro then
            why = hub.error or "hub closed the connection"
            break
          end
          if Util.time() > deadline then
            t:disconnect(hubId)
            why = "hub didn't introduce us"
            break
          end
          if not intro then Util.yield() end
        end
      end
    end
    if intro then break end
    err = why or err
  end
  if not intro then return nil, err end
  local endpoints, lanIps = {}, {}
  if type(intro.lan) == "string" and intro.lan ~= intro.endpoint then
    endpoints[#endpoints + 1] = intro.lan
    lanIps[Util.splitEndpoint(intro.lan)] = true
  end
  endpoints[#endpoints + 1] = intro.endpoint
  local punch = Punch.start(t, { endpoints = endpoints, myNonce = myNonce,
                                 theirNonce = tonumber(intro.nonce), role = "guest",
                                 timeout = timeout })
  local peerId, path = runPunch(job, punch, "hub", lanIps)
  t:disconnect(hubId)
  return peerId, path
end

---------------------------------------------------------------- join

function Connector.join(invite, opts)
  opts = opts or {}
  invite = invite or {}
  local timeouts = setmetatable(opts.timeouts or {}, { __index = Connector.TIMEOUTS })
  local job
  job = Util.job(function()
    local hostJob = opts.hostJob
    local t, owned
    local myNonce
    if hostJob then
      t = hostJob.transport
      myNonce = hostJob.info and hostJob.info.nonce
    else
      myNonce = opts.myNonce or Util.newNonce()
      t = Transport.new{ port = opts.port or 0, bind = opts.bind, nonce = myNonce,
                         maxPeers = opts.maxPeers or 1, driver = opts.driver }
      owned = true
    end
    job.transport = t
    local enetOk, enetWhy = true, nil
    if not t then
      enetOk, enetWhy = false, "no host session to punch from"
    elseif not t.open_ then
      enetOk, enetWhy = t:listen()
    end
    local function done(peerId, path, net)
      job.path = path
      if net then
        job.channel = net
        if owned and t then t:close() end
      else
        job.channel = t:channelFor(peerId, { owns = owned or hostJob ~= nil, path = path })
        if hostJob then hostJob:adopt(job.channel, path) end
      end
      job.state = "connected"
      job.progress = Connector.describe(path)
      return job.channel
    end

    local cands, port = directCandidates(invite)
    -- L2 by name: resolve the host's typed address
    if type(invite.address) == "string" and invite.address ~= "" then
      local h, p = Util.splitEndpoint(invite.address, port)
      logEntry(job, "manual", "trying", invite.address)
      local ip, why = Dns.resolve(h, 5)
      if ip then
        local ep = Util.endpoint(ip, p)
        local dup = false
        for _, c in ipairs(cands) do if c.ep == ep then dup = true end end
        if not dup then cands[#cands + 1] = { rung = "manual", ep = ep } end
        if dup then logEntry(job, "manual", "skipped", "same address as above") end
      else
        logEntry(job, "manual", "failed", why)
      end
    end

    -- L0-L3: direct, or (with my own host session) simultaneous open
    if not enetOk then
      for _, c in ipairs(cands) do logEntry(job, c.rung, "failed", enetWhy) end
    elseif hostJob then
      if #cands == 0 then
        logEntry(job, "punch", "skipped", "their code has no address")
      else
        logEntry(job, "punch", "trying", "both sides dialling")
        local endpoints, lanIps = {}, {}
        for _, c in ipairs(cands) do
          endpoints[#endpoints + 1] = c.ep
          if c.rung == "lan" then lanIps[Util.splitEndpoint(c.ep)] = true end
        end
        local punch = hostJob:punchTo(invite, endpoints)
        while punch.state == "trying" and hostJob.state ~= "connected" do
          punch:update()
          if hostJob.state ~= "connected" then hostJob:update() end
          Util.yield()
        end
        if hostJob.state == "connected" then
          -- they joined our code (or our punch landed) first
          logEntry(job, "punch", "ok", hostJob.path)
          job.path, job.channel, job.state = hostJob.path, hostJob.channel, "connected"
          job.progress = Connector.describe(hostJob.path)
          return job.channel
        end
        if punch.state == "connected" then
          local ip = Util.splitEndpoint(punch.endpoint or "")
          local path = (ip and lanIps[ip]) and "lan" or "punch"
          logEntry(job, "punch", "ok", punch.endpoint)
          return done(punch.peerId, path)
        end
        logEntry(job, "punch", "failed", punch.reason)
      end
    else
      if #cands > 0 then
        local best = raceDirect(job, t, cands, invite.nonce, timeouts)
        if best then return done(best.id, best.rung) end
      else
        logEntry(job, "lan", "skipped", "code has no direct address")
      end
      logEntry(job, "punch", "skipped", "needs both players to enter each other's code")
    end

    -- L4: hub-introduced direct
    if invite.hub ~= nil then
      if not enetOk then
        logEntry(job, "hub", "failed", enetWhy)
      else
        logEntry(job, "hub", "trying", (hubEndpoint(invite)))
        local peerId, pathOrWhy = viaHub(job, t, invite, myNonce, timeouts.hub)
        if peerId then
          logEntry(job, "hub", "ok", pathOrWhy)
          return done(peerId, pathOrWhy)
        end
        logEntry(job, "hub", "failed", pathOrWhy)
      end
    else
      logEntry(job, "hub", "skipped", "code names no hub")
    end

    -- L5: relay, only when the settings allow it
    local code = roomCode(invite)
    if not opts.allowRelay then
      logEntry(job, "relay", "skipped", "relay is off in settings")
    elseif not code then
      logEntry(job, "relay", "skipped", "code has no relay room")
    else
      logEntry(job, "relay", "trying", code)
      local rj = Relay.join(opts.relayAddress, code, { pairTimeout = timeouts.relay })
      job.relayJob = rj
      while rj:update() == "running" do Util.yield() end
      if rj.state == "done" and rj.result then
        logEntry(job, "relay", "ok", code)
        return done(nil, "relay", rj.result)
      end
      logEntry(job, "relay", "failed", rj.reason)
    end

    if owned and t then t:close() end
    local lines = {}
    for _, e in ipairs(job.log) do
      if e.state == "failed" then
        lines[#lines + 1] = ("%s: %s"):format(Connector.RUNG_NAMES[e.rung] or e.rung,
                                              tostring(e.reason))
      end
    end
    job.state = "failed"
    job.reason = #lines > 0 and table.concat(lines, "\n") or "nothing to try in this code"
    job.progress = "Couldn't connect"
    return nil, job.reason
  end)
  job.state = "trying"
  job.onProgress = opts.onProgress
  job.invite = invite
  -- Util.job's "running" is reported as "trying"
  local resume = job.update
  function job:update()
    if self.state ~= "trying" then return self.state end
    self.state = "running"
    resume(self)
    if self.state == "running" then self.state = "trying" end
    if self.state == "done" then self.state = self.channel and "connected" or "failed" end
    return self.state
  end
  function job:cancel()
    if self.state ~= "trying" then return end
    self.co = nil
    self.state, self.reason, self.progress = "failed", "cancelled", "Cancelled"
    if self.relayJob and self.relayJob.net then pcall(self.relayJob.net.close, self.relayJob.net) end
    if self.transport and not opts.hostJob then self.transport:close() end
  end
  return job
end
Connector.connect = Connector.join

---------------------------------------------------------------- host

local Host = {}
Host.__index = Host
Connector.Host = Host

function Connector.host(opts)
  opts = opts or {}
  local self = setmetatable({
    opts = opts, state = "starting", pending = true, log = {}, punches = {},
    info = { nonce = opts.nonce or Util.newNonce(), kind = opts.kind or 0 },
    maxPeers = opts.maxPeers or 1,
  }, Host)
  self.onProgress = opts.onProgress
  self.setup = Util.job(function() return self:runSetup() end)
  self:update()
  return self
end

function Host:runSetup()
  local opts = self.opts
  local port = opts.port or Transport.DEFAULT_PORT
  -- optional public address finder (third party, off by default)
  if opts.stun then
    logEntry(self, "stun", "trying", opts.stunServer)
    local Stun = require("src.online.net.Stun")
    local ip, sport = Stun.query{ server = opts.stunServer, bindPort = port,
                                  bind = opts.bind, timeout = 3 }
    if ip then
      self.info.stun = Util.endpoint(ip, sport)
      logEntry(self, "stun", "ok", self.info.stun)
    else
      logEntry(self, "stun", "failed", sport)
    end
  end
  -- the ENet socket (try a few ports if the default is taken)
  local t, lastErr
  for p = port, port + (opts.portRetries or 9) do
    t = Transport.new{ port = p, bind = opts.bind, nonce = self.info.nonce,
                       maxPeers = self.maxPeers, driver = opts.driver,
                       allowTypes = opts.allowTypes }
    local ok, err = t:listen()
    if ok then break end
    lastErr, t = err, nil
    if opts.driver then break end
  end
  if not t then
    self.state = "failed"
    self.reason = lastErr
    self.pending = false
    return nil, lastErr
  end
  self.transport = t
  t:onClose(function() self:releaseMapping() end)
  self.info.port = t.boundPort
  self.info.lan = opts.lanIp or Util.lanIP()
  self.state = "listening"
  logEntry(self, "lan", "ok", self.info.lan and Util.endpoint(self.info.lan, t.boundPort))

  if opts.lanBeacon then
    local info = {}
    for k, v in pairs(opts.beaconInfo or {}) do info[k] = v end
    info.port, info.nonce, info.kind = t.boundPort, self.info.nonce, self.info.kind
    self.beacon = LanBeacon.newBroadcaster{ info = info, targets = opts.beaconTargets,
                                            port = opts.beaconPort }
  end
  if opts.allowRelay and opts.relayHost then
    self.relayJob = Relay.host(opts.relayAddress)
  end
  if opts.hub then self:registerHub() end

  -- L1 router mapping
  if opts.portMap ~= false then
    logEntry(self, "mapped", "trying", "asking the router")
    local pmOpts = {}
    for k, v in pairs(opts.portMapOpts or {}) do pmOpts[k] = v end
    pmOpts.port = t.boundPort
    pmOpts.lease = opts.lease or PortMap.DEFAULT_LEASE
    local gw, why = PortMap.discover(pmOpts)
    if gw then
      local ip, ext, note = PortMap.map(gw, t.boundPort, "UDP", pmOpts.lease, pmOpts)
      if ip then
        self.gateway = gw
        self.mapping = { ip = ip, port = ext, method = gw.kind, note = note,
                         internalPort = t.boundPort, proto = "UDP", lease = pmOpts.lease,
                         at = Util.time() }
        self.info.public, self.info.publicVia = ip, gw.kind
        if ext ~= t.boundPort then self.info.publicPort = ext end
        self.info.note = note
        logEntry(self, "mapped", "ok", ("%s:%d via %s%s"):format(ip, ext, gw.kind,
                                                                 note and (" (" .. note .. ")") or ""))
      else
        logEntry(self, "mapped", "failed", ext)
      end
    else
      logEntry(self, "mapped", "failed", why)
    end
  else
    logEntry(self, "mapped", "skipped", "router mapping is off in settings")
  end
  -- L2: what the player typed (public IP or DNS name of a forwarded port)
  if type(opts.manualAddress) == "string" and opts.manualAddress ~= "" then
    self.info.address = opts.manualAddress
    local h = Util.splitEndpoint(opts.manualAddress)
    if not self.info.public and Util.isIPv4(h) then
      self.info.public, self.info.publicVia = h, "manual"
    end
    logEntry(self, "manual", "ok", opts.manualAddress)
  end
  if not self.info.public and self.info.stun then
    self.info.public = Util.splitEndpoint(self.info.stun)
    self.info.publicVia = "stun"
  end
  self.pending = false
  return true
end

function Host:registerHub()
  local opts, t = self.opts, self.transport
  local hubEp, _, key = hubEndpoint({ hub = opts.hub })
  if not hubEp then return end
  logEntry(self, "hub", "trying", hubEp)
  local host, port = Util.splitEndpoint(hubEp, 7777)
  local ip, why = Dns.resolve(host, 5)
  if not ip then logEntry(self, "hub", "failed", why) return end
  local id, err = t:connect(Util.endpoint(ip, port), key or 0, { timeout = 5 })
  if not id then logEntry(self, "hub", "failed", err) return end
  self.hubId = id
  self.hub = t:channelFor(id)
  self.hub:send({ type = "hub_register", nonce = self.info.nonce,
                  lan = self.info.lan and Util.endpoint(self.info.lan, t.boundPort) })
end

function Host:updateHub()
  local hub = self.hub
  if not hub then return end
  if hub.closed then
    if not self.info.hubTicket then logEntry(self, "hub", "failed", hub.error or "hub closed") end
    self.hub = nil
    return
  end
  for _, m in ipairs(hub:poll()) do
    if m.type == "hub_registered" then
      self.info.hubTicket = tonumber(m.ticket)
      self.info.observed = m.observed
      logEntry(self, "hub", "ok", ("ticket %s"):format(tostring(m.ticket)))
    elseif m.type == "hub_introduce" and type(m.endpoint) == "string" then
      local endpoints, lanIps = {}, {}
      if type(m.lan) == "string" and m.lan ~= m.endpoint then
        endpoints[#endpoints + 1] = m.lan
        lanIps[Util.splitEndpoint(m.lan)] = true
      end
      endpoints[#endpoints + 1] = m.endpoint
      local p = Punch.start(self.transport, { endpoints = endpoints, myNonce = self.info.nonce,
                                              theirNonce = tonumber(m.nonce), role = "host" })
      p.rungName, p.lanIps = "hub", lanIps
      self.punches[#self.punches + 1] = p
    elseif m.type == "hub_error" then
      logEntry(self, "hub", "failed", tostring(m.reason))
    end
  end
end

-- simultaneous open with the other player's code (L3)
function Host:punchTo(invite, endpoints)
  if not endpoints then
    endpoints = {}
    for _, c in ipairs((directCandidates(invite))) do endpoints[#endpoints + 1] = c.ep end
  end
  local lanIps = {}
  if Util.isIPv4(invite.lan) then lanIps[invite.lan] = true end
  local p = Punch.start(self.transport, { endpoints = endpoints, myNonce = self.info.nonce,
                                          theirNonce = tonumber(invite.nonce) })
  p.rungName, p.lanIps, p.external = "punch", lanIps, true
  self.punches[#self.punches + 1] = p
  return p
end

function Host:adopt(channel, path)
  if self.state == "connected" then return end
  self.channel, self.path, self.state = channel, path, "connected"
  self:stopExtras()
end

function Host:stopExtras()
  if self.beacon then self.beacon:close() self.beacon = nil end
  if self.hubId and self.transport then self.transport:disconnect(self.hubId) end
  self.hub, self.hubId = nil, nil
  for _, p in ipairs(self.punches) do
    if p.state == "trying" and not p.external then p:cancel() end
  end
  if self.relayJob and self.path ~= "relay" then
    self.relayJob:cancel()
    if self.relayJob.net then pcall(self.relayJob.net.close, self.relayJob.net) end
    self.relayJob = nil
  end
end

function Host:update()
  if self.state == "closed" or self.state == "failed" then return self.state end
  if self.setup and self.setup.state == "running" then
    self.setup:update()
    if self.setup.state == "failed" and self.state ~= "failed" then
      self.state, self.reason, self.pending = "failed", self.setup.reason, false
    end
  end
  local t = self.transport
  if not t then return self.state end
  if self.state == "connected" then return self.state end
  t:update()
  if self.beacon then self.beacon:update() end
  self:updateHub()
  -- lease renewal at half-life
  if self.mapping and not self.renewJob
     and Util.time() - self.mapping.at > self.mapping.lease / 2 then
    local gw, m = self.gateway, self.mapping
    self.renewJob = Util.job(function() return PortMap.renew(gw, m) end)
  end
  if self.renewJob then
    self.renewJob:update()
    if self.renewJob.state ~= "running" then
      self.mapping.at = Util.time()
      self.renewJob = nil
    end
  end
  if self.relayJob then
    self.relayJob:update()
    if self.relayJob.code and not self.info.relayCode then
      self.info.relayCode = self.relayJob.code
      logEntry(self, "relay", "ok", "room " .. self.relayJob.code)
    end
    if self.relayJob.state == "done" and self.maxPeers == 1 then
      self.channel, self.path, self.state = self.relayJob.result, "relay", "connected"
      self:stopExtras()
      t:close()
      return self.state
    elseif self.relayJob.state == "failed" then
      logEntry(self, "relay", "failed", self.relayJob.reason)
      self.relayJob = nil
    end
  end
  if self.maxPeers ~= 1 then return self.state end
  for _, p in ipairs(self.punches) do
    if p.state == "trying" then
      p:update()
      if p.state == "connected" then
        local ip = Util.splitEndpoint(p.endpoint or "")
        local path = (ip and p.lanIps[ip]) and "lan" or p.rungName
        local rec = t:peer(p.peerId)
        if rec then rec.claim = "taken" end
        self:adopt(t:channelFor(p.peerId, { owns = true, path = path }), path)
        return self.state
      end
    end
  end
  -- a joiner who picked one of its connections (or said hello)
  for _, rec in ipairs(t:peerList()) do
    if not rec.outgoing and rec.promoted and rec.state == "connected"
       and rec.claim == nil and rec.id ~= self.hubId then
      rec.claim = "taken"
      local path = Util.isPrivate(rec.ip) and "lan" or (self.info.publicVia == "manual"
                   and "manual" or "mapped")
      self:adopt(t:channelFor(rec.id, { owns = true, path = path }), path)
      return self.state
    end
  end
  return self.state
end

function Host:inviteFields()
  local i = self.info
  local hub = nil
  if self.opts.hub and i.hubTicket then
    local ep = hubEndpoint({ hub = self.opts.hub })
    local h, p = Util.splitEndpoint(ep or "", 7777)
    hub = { ip = h, port = p, ticket = i.hubTicket }
  end
  return { kind = i.kind, public = i.public, lan = i.lan, port = i.port,
           publicPort = i.publicPort, nonce = i.nonce, hub = hub,
           room = i.relayCode, address = i.address, publicVia = i.publicVia }
end

function Host:releaseMapping()
  if self.gateway and self.mapping then
    local gw, m = self.gateway, self.mapping
    self.mapping = nil
    local job = Util.job(function()
      return PortMap.unmap(gw, gw.kind == "upnp" and m.port or m.internalPort, m.proto)
    end)
    Util.runSync(job, self.opts.unmapBudget or 0.75, self.opts.unmapTick)
    self.unmapResult = job.state
  end
end

function Host:close()
  if self.state == "closed" then return end
  if self.setup and self.setup.state == "running" then self.setup:cancel("closed") end
  self:stopExtras()
  for _, p in ipairs(self.punches) do if p.state == "trying" then p:cancel() end end
  if self.channel and self.channel.close then
    self.channel:close()
  elseif self.transport then
    self.transport:close()
  end
  self:releaseMapping()
  self.state = "closed"
end

return Connector
