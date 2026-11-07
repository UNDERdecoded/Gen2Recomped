-- THE LINK HUB (docs/online-design.md 2.9, workstream WS9).
--
-- One process, any number of players, every service optional:
--
--   TCP  port      the pokeserver protocol: short codes (relay rooms) and
--                  tournaments -- what 0.7.x clients and today's SHORT CODE
--                  and TOURNAMENT screens speak (hub/Relay, hub/Tournaments)
--   UDP  udpPort   ENet (WS1 Transport): rendezvous for hub invite codes
--                  (hub/Rendezvous), the same relay rooms over ENet, and the
--                  GTS (hub/GtsEmbed, WS7)
--   UDP  world.port  an always-on world (hub/WorldEmbed, WS8)
--
--   local hub = Hub.new(cfg, { log = Log.new{...} })
--   assert(hub:start())
--   while not hub.stopping do hub:update() ; sleep a little end
--   hub:stop()
--
-- Every message is routed by its type: hub_* to the rendezvous (or admin),
-- gts_* to the GTS, the tournament types to the tournaments, and the rest
-- to the relay rooms.  A connection belongs to one service at a time
-- (conn.role), so a relayed pair never reaches the tournament code.

local Codes = require("src.online.hub.Codes")
local Conn = require("src.online.hub.Conn")
local Files = require("src.online.hub.Files")
local Relay = require("src.online.hub.Relay")
local Tournaments = require("src.online.hub.Tournaments")
local Rendezvous = require("src.online.hub.Rendezvous")
local Util = require("src.online.net.Util")

local Hub = {}
Hub.__index = Hub

Hub.VERSION = "1.0"
Hub.ADMIN_FAILS = 5          -- wrong keys from one address ...
Hub.ADMIN_LOCKOUT = 600      -- ... lock it out this long (seconds)

function Hub.new(cfg, opts)
  opts = opts or {}
  local self = setmetatable({
    cfg = cfg, opts = opts,
    log = opts.log or require("src.online.hub.Log").new({ file = false }),
    now = opts.now or Util.now,
    conns = {}, byIp = {}, count = 0,
    bans = {}, adminFails = {},
    stats = { accepted = 0, refused = 0, messages = 0, limited = 0 },
    started = nil, stopping = false, lastStatus = 0, lastSweep = 0,
  }, Hub)
  local rand = Util.rand32
  local now = self.now
  self.codes = Codes.new({ rand = rand, now = now })
  self.relay = Relay.new({ codes = self.codes, log = self.log, cfg = cfg.relay, now = now })
  self.tours = Tournaments.new({ codes = self.codes, log = self.log, cfg = cfg.tournaments,
                                 now = now, rand = rand })
  self.rdv = Rendezvous.new({ codes = self.codes, log = self.log, cfg = cfg.rendezvous, now = now,
                              rand = rand, test = cfg.test,
                              advertise = function() return self.advertiseIp end })
  return self
end

---------------------------------------------------------------- start / stop

function Hub:bansPath() return self.cfg.dataDir .. "/bans.json" end

function Hub:loadBans()
  local b = Files.readJson(self:bansPath())
  self.bans = type(b) == "table" and type(b.ips) == "table" and b.ips or {}
end

function Hub:saveBans()
  if self.opts.memory then return end
  Files.writeJson(self:bansPath(), { ips = self.bans })
end

function Hub:start()
  local cfg, log = self.cfg, self.log
  if not self.opts.memory then
    local okDir, whyDir = Files.mkdirs(cfg.dataDir)
    if not okDir then return false, whyDir end
    self:loadBans()
  end
  self.started = self.now()
  self.startedAt = os.time()
  local Version = require("src.core.Version")
  log:info("Link Hub %s (engine %s, link protocol %s) starting: %q", Hub.VERSION,
           tostring(Version.engine), tostring(Version.linkProtocol), cfg.name)
  for _, w in ipairs(cfg.warnings or {}) do log:warn("config: %s", w) end

  if (cfg.relay.enabled or cfg.tournaments.enabled) and not self.opts.noTcp and not self.opts.noListen then
    local LineServer = require("src.online.hub.LineServer")
    self.tcp = LineServer.new({ bind = cfg.bind, port = cfg.port, hub = self, now = self.now, log = log })
    local ok, err = self.tcp:listen()
    if not ok then return false, err end
    log:info("TCP %s:%d: pokeserver protocol (%s%s)", cfg.bind, self.tcp.boundPort,
             cfg.relay.enabled and "short codes" or "",
             cfg.tournaments.enabled and (cfg.relay.enabled and ", tournaments" or "tournaments") or "")
  end

  if (cfg.rendezvous.enabled or cfg.relay.enabled or cfg.gts.enabled) and not self.opts.noListen then
    local Transport = require("src.online.net.Transport")
    local t = Transport.new({ port = cfg.udpPort, bind = cfg.bind, maxPeers = cfg.caps.enetPeers,
                              receiveEvents = true, driver = self.opts.enetDriver })
    local ok, err = t:listen()
    if not ok then return false, err end
    self.enet, self.enetConns = t, {}
    log:info("UDP %s:%d: ENet (%s)", cfg.bind, t.boundPort or cfg.udpPort,
             table.concat((function()
               local s = {}
               if cfg.rendezvous.enabled then s[#s + 1] = "rendezvous" end
               if cfg.relay.enabled then s[#s + 1] = "relay" end
               if cfg.gts.enabled then s[#s + 1] = "GTS" end
               return s
             end)(), ", "))
  end

  if cfg.gts.enabled then
    local GtsEmbed = require("src.online.hub.GtsEmbed")
    local g, why = GtsEmbed.new({ cfg = cfg.gts, log = log, dataDir = cfg.dataDir, hubName = cfg.name,
                                  datasets = self.opts.datasets, clock = self.now,
                                  store = self.opts.gtsStore })
    if not g then return false, why end
    self.gts = g
  end

  if cfg.world.enabled then
    local WorldEmbed = require("src.online.hub.WorldEmbed")
    local w, why = WorldEmbed.new({ cfg = cfg.world, log = log, dataDir = cfg.dataDir, bind = cfg.bind,
                                    gts = self.gts, publicAddress = cfg.publicAddress,
                                    lanAddress = cfg.lanAddress, data = self.opts.worldData,
                                    transport = self.opts.worldTransport })
    if not w then return false, why end
    self.world = w
  end
  if cfg.admin.key == "" then log:info("admin commands are off (no admin.key)") end
  self:writeStatus()
  return true
end

function Hub:stop(reason)
  if self.stopped then return end
  self.stopped = true
  self.log:info("stopping (%s)", tostring(reason or "asked"))
  if self.world then pcall(self.world.close, self.world) end
  if self.tcp then self.tcp:close() end
  if self.enet then
    for _, conn in pairs(self.enetConns or {}) do
      if not conn.closed then conn:close("hub stopping") end
    end
    self.enet:close(0.5)
  end
  self:writeStatus(true)
  self.log:close()
end

---------------------------------------------------------------- connections

local function isLoopback(ip) return ip == "127.0.0.1" or ip == "::1" or ip == "localhost" end

-- may this connection in?  (bans, per-address and total caps)
function Hub:accept(conn)
  local caps = self.cfg.caps
  local ip = conn.ip or "?"
  if self.bans[ip] then
    self.stats.refused = self.stats.refused + 1
    return false
  end
  local lock = self.adminFails[ip]
  if lock and lock.untilAt and lock.untilAt > os.time() then return false end
  if (self.byIp[ip] or 0) >= caps.perIp and not isLoopback(ip) then
    self.stats.refused = self.stats.refused + 1
    self.log:warn("refused %s: %d connections from that address", self.log:addr(conn.address), caps.perIp)
    return false
  end
  if conn.kind == "tcp" and self.tcp and self.tcp.count >= caps.tcpConnections then
    self.stats.refused = self.stats.refused + 1
    self.log:warn("refused a TCP connection: %d open", caps.tcpConnections)
    return false
  end
  self.conns[conn.id] = conn
  self.byIp[ip] = (self.byIp[ip] or 0) + 1
  self.count = self.count + 1
  self.stats.accepted = self.stats.accepted + 1
  self.log:debug("%s connection %d from %s", conn.kind, conn.id, self.log:addr(conn.address))
  return true
end

function Hub:closed(conn)
  if not self.conns[conn.id] then return end
  self.conns[conn.id] = nil
  self.count = self.count - 1
  local ip = conn.ip or "?"
  self.byIp[ip] = (self.byIp[ip] or 1) - 1
  if self.byIp[ip] <= 0 then self.byIp[ip] = nil end
  conn.closed = true
  self.rdv:closed(conn)
  self.relay:closed(conn)
  self.tours:closed(conn)
  if self.gts then self.gts:closed(conn) end
  self.log:debug("%s connection %d closed (%s)", conn.kind, conn.id, tostring(conn.closeReason))
end

function Hub:canRead(conn) return self.relay:canRead(conn) end

---------------------------------------------------------------- routing

local GTS_DENIED = { type = "gts_denied", code = "pool", text = "This Link Hub has no GTS." }

function Hub:message(conn, msg, line)
  local now = self.now()
  conn.lastSeen = now
  conn.spoke = true
  self.stats.messages = self.stats.messages + 1
  local inRoom = conn.role == "room" and conn.room and conn.room.state == "paired"
  if not inRoom then
    local caps = self.cfg.caps
    if not Conn.allow(conn, now, caps.messagesPerSecond, caps.messageBurst) then
      self.stats.limited = self.stats.limited + 1
      if not conn.warnedSlow then
        conn.warnedSlow = true
        self.log:warn("%s connection %d over the message rate", conn.kind, conn.id)
      end
      return
    end
  end
  local ty = msg.type
  local cfg = self.cfg
  if ty == "hub_admin" then
    return self:admin(conn, msg)
  elseif ty == "hub_ping" then
    return conn:send(self:pong())
  elseif ty:sub(1, 4) == "hub_" then
    if cfg.rendezvous.enabled and conn.kind ~= "tcp" then
      if self.rdv:handle(conn, msg) then return end
    end
    return conn:send({ type = "hub_error", reason = "off" })
  elseif ty:sub(1, 4) == "gts_" then
    if self.gts and (conn.role == nil or conn.role == "gts") then return self.gts:receive(conn, msg) end
    if not self.gts then return conn:send(GTS_DENIED) end
    return
  end
  if cfg.tournaments.enabled and (conn.role == "tournament" or Tournaments.TYPES[ty]) then
    if self.tours:handle(conn, msg, line) then return end
  end
  if cfg.relay.enabled and (conn.role == "room" or Relay.TYPES[ty]) then
    if self.relay:handle(conn, msg, line) then return end
  end
  if ty == "host" or ty == "join" then
    conn:send({ type = "join_error", reason = "not_found" })
  elseif ty == "host_tournament" then
    conn:send({ type = "tournament_host_error", reason = "off" })
  elseif ty == "join_tournament" then
    conn:send({ type = "tournament_join_error", reason = "not_found" })
  end
end

function Hub:services()
  local cfg, s = self.cfg, {}
  if cfg.relay.enabled then s[#s + 1] = "relay" end
  if cfg.tournaments.enabled then s[#s + 1] = "tournaments" end
  if cfg.rendezvous.enabled then s[#s + 1] = "rendezvous" end
  if self.gts then s[#s + 1] = "gts" end
  if self.world then s[#s + 1] = "world" end
  return s
end

function Hub:pong()
  return { type = "hub_pong", name = self.cfg.name, version = Hub.VERSION, services = self:services(),
           gtsPools = self.gts and self.gts.pools or nil,
           worldCode = self.world and self.world.code or nil,
           worldGame = self.world and self.world.game or nil }
end

---------------------------------------------------------------- admin

-- same time whatever the first wrong character
local function sameKey(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #b == 0 then return false end
  local diff = (#a == #b) and 0 or 1
  for i = 1, #b do
    local x = a:byte(((i - 1) % math.max(1, #a)) + 1) or 0
    if x ~= b:byte(i) then diff = diff + 1 end
  end
  return diff == 0
end

function Hub:admin(conn, msg)
  local cfg = self.cfg.admin
  local function reply(ok, result)
    conn:send({ type = "hub_admin_reply", ok = ok, cmd = msg.cmd, result = result })
  end
  if cfg.key == "" then return reply(false, "admin is off on this hub") end
  if cfg.localOnly and not isLoopback(conn.ip) then
    self.log:warn("admin: refused a command from %s (admin.localOnly)", self.log:addr(conn.address))
    return reply(false, "admin commands are only taken from this machine")
  end
  local ip = conn.ip or "?"
  if not sameKey(msg.key, cfg.key) then
    local f = self.adminFails[ip] or { n = 0 }
    f.n = f.n + 1
    if f.n >= Hub.ADMIN_FAILS then
      f.untilAt = os.time() + Hub.ADMIN_LOCKOUT
      f.n = 0
      self.log:warn("admin: %s locked out after %d wrong keys", self.log:addr(conn.address), Hub.ADMIN_FAILS)
      conn:close("locked out")
    end
    self.adminFails[ip] = f
    return reply(false, "wrong key")
  end
  self.adminFails[ip] = nil
  local cmd, arg = msg.cmd, msg.arg
  self.log:info("admin: %s %s", tostring(cmd), arg ~= nil and tostring(arg) or "")
  if cmd == "status" then
    return reply(true, self:status())
  elseif cmd == "rooms" then
    return reply(true, { relay = self.relay:snapshot(), tournaments = self.tours:snapshot() })
  elseif cmd == "ban" or cmd == "unban" then
    if type(arg) ~= "string" or not Util.isIPv4(arg) then return reply(false, "give an IPv4 address") end
    if cmd == "ban" then
      self.bans[arg] = { at = os.time() }
      for _, c in pairs(self.conns) do if c.ip == arg then c:close("banned") end end
    else
      self.bans[arg] = nil
    end
    self:saveBans()
    return reply(true, cmd == "ban" and ("banned " .. arg) or ("unbanned " .. arg))
  elseif cmd == "world" then
    if not self.world then return reply(false, "no world on this hub") end
    return reply(true, self.world:snapshot())
  elseif cmd == "kick" or cmd == "worldban" then
    if not self.world then return reply(false, "no world on this hub") end
    local pid = tonumber(arg)
    if not pid then return reply(false, "give a player number (see: world)") end
    self.world.host:kick(pid, "removed by the hub", cmd == "worldban")
    return reply(true, (cmd == "worldban" and "banned " or "kicked ") .. tostring(pid))
  elseif cmd == "log" then
    local lines = self.log.lines
    local out = {}
    for i = math.max(1, #lines - 49), #lines do out[#out + 1] = lines[i] end
    return reply(true, out)
  elseif cmd == "stop" then
    reply(true, "stopping")
    self.stopping = true
    return
  end
  return reply(false, "commands: status, rooms, world, kick <pid>, worldban <pid>, ban <ip>, unban <ip>, log, stop")
end

---------------------------------------------------------------- update

function Hub:updateEnet(now)
  local t = self.enet
  t:update()
  for _, ev in ipairs(t:events()) do
    if ev.type == "connect" and not ev.outgoing then
      local conn = Conn.enet(t, ev.peer, ev.address, now)
      if self:accept(conn) then
        self.enetConns[ev.peer] = conn
      else
        t:disconnect(ev.peer, true)
      end
    elseif ev.type == "receive" then
      local conn = self.enetConns[ev.peer]
      if conn and not conn.closed then self:message(conn, ev.msg, nil) end
    elseif ev.type == "disconnect" then
      local conn = self.enetConns[ev.peer]
      if conn then
        self.enetConns[ev.peer] = nil
        conn.closed = true
        conn.closeReason = conn.closeReason or ev.reason
        self:closed(conn)
      end
    end
  end
end

-- connections that never said anything, and ones that have nothing to wait for
function Hub:sweep(now)
  local idle = self.cfg.caps.idleSeconds
  for _, conn in pairs(self.conns) do
    if not conn.closed and conn.role == nil and now - conn.lastSeen > idle then
      conn:close("idle")
    end
  end
  self.codes:sweep()
  local cutoff = os.time()
  for ip, f in pairs(self.adminFails) do
    if f.untilAt and f.untilAt < cutoff then self.adminFails[ip] = nil end
  end
end

function Hub:update()
  local now = self.now()
  if self.tcp then self.tcp:update() end
  if self.enet then self:updateEnet(now) end
  self.relay:update()
  self.tours:update()
  self.rdv:update()
  if self.gts then
    local ok, err = pcall(self.gts.update, self.gts)
    if not ok then self.log:error("gts: %s", tostring(err)) end
  end
  if self.world then
    local ok, err = pcall(self.world.update, self.world)
    if not ok then self.log:error("world: %s", tostring(err)) end
  end
  if self.tcp then self.tcp:update() end -- flush what this tick produced
  if now - self.lastSweep > 5 then
    self.lastSweep = now
    self:sweep(now)
  end
  if now - self.lastStatus > (self.cfg.statusSeconds or 30) then
    self:writeStatus()
  end
end

-- the main loop (LOVE's love.run and run.lua both call this)
function Hub:run(sleep)
  sleep = sleep or (Util.socket and Util.socket.sleep) or function() end
  while not self.stopping do
    local ok, err = xpcall(function() self:update() end, debug.traceback)
    if not ok then self.log:error("update failed: %s", tostring(err)) end
    sleep(0.004)
  end
  self:stop("admin stop")
end

---------------------------------------------------------------- status

function Hub:status()
  local s = {
    name = self.cfg.name, version = Hub.VERSION,
    uptime = self.started and math.floor(self.now() - self.started) or 0,
    startedAt = self.startedAt, services = self:services(),
    connections = { total = self.count, tcp = self.tcp and self.tcp.count or 0 },
    relay = { rooms = self.relay.count, paired = self.relay.paired, hosted = self.relay.stats.hosted,
              pairedTotal = self.relay.stats.pairedTotal, bytes = self.relay.stats.bytes,
              cut = self.relay.stats.cut },
    tournaments = { open = self.tours.count, hosted = self.tours.stats.hosted,
                    finished = self.tours.stats.finished, matches = self.tours.stats.matches },
    rendezvous = { tickets = self.rdv.count, registered = self.rdv.stats.registered,
                   introduced = self.rdv.stats.introduced },
    stats = self.stats,
    gts = self.gts and self.gts:snapshot() or nil,
    world = self.world and { members = self.world.host:count(), cap = self.world.world.cap,
                             code = self.world.code, game = self.world.game } or nil,
  }
  return s
end

function Hub:writeStatus(final)
  self.lastStatus = self.now()
  if self.opts.memory then return end
  local s = self:status()
  s.updated = os.time()
  s.running = not final
  Files.writeJson(self.cfg.dataDir .. "/status.json", s)
end

return Hub
