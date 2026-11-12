-- THE LINK HUB IN THE LAUNCHER (docs/online-design.md 2.9; docs/launcher.md).
--
-- The launcher runs the hub (src/online/hub/*) in a love.thread, so it keeps
-- serving smoothly while the launcher draws, and keeps serving while a game
-- launched from the launcher is played (the game runs in this same process;
-- the thread is not touched by the hand-over).  It stops when the app quits
-- or the player presses STOP.  A mods restart (a new process) stops it too;
-- "Start hub when launcher opens" brings it back the next time the launcher
-- shows.
--
-- This module is the main-thread side:
--   * the launcher's hub config (save dir: online_hub/config.json) and how
--     it maps onto the hub's own config (src/online/hub/Config.lua)
--   * start / stop / status of the thread
--   * the ONE share code: an InviteCode kind "hub" with ticket 0 ("the hub
--     itself": no rendezvous ticket is ever 0) carrying the hub's internet
--     address (when the router mapped it) and its LAN address
--   * the friend side: a hub code from a friend -> probe it (hub_ping) ->
--     remember it as this player's hub
--   * games launched from here: LinkState.settings gets hubAddress filled
--     (127.0.0.1 for the host's own games, the friend's hub otherwise) when
--     the game's own settings name none, and a pending action (host / join a
--     code / join a world) is carried out once the game is on its map.
--
-- Nothing here contacts any host unless the player starts the hub, presses
-- JOIN, or turns on router mapping.

local Json = require("src.link.Json")

local LH = {}

LH.CONFIG_FILE = "online_hub/config.json"
LH.DATA_DIR = "online_hub/data"
LH.CMD = "pokeport_hub_cmd"
LH.STATUS = "pokeport_hub_status"
-- 7777 is the games' own ENet port and 7778 the LAN beacon's (LanBeacon):
-- a hub on 7778 would share its UDP port with every JOIN list opened on this
-- machine, so the launcher's hub defaults to 7780 (the standalone hub keeps
-- 7778, the old relay's port)
LH.DEFAULT_PORT = 7780
LH.DEFAULT_WORLD_PORT = 7779
LH.WORLD_CAP_MAX = 16

local state = {
  thread = nil, phase = "off", status = nil, error = nil, startedAt = nil,
  probe = nil, pending = nil, cfg = nil,
}
LH._state = state

---------------------------------------------------------------- helpers

local function fs() return love and love.filesystem end

local function randomKey(n)
  local Util = require("src.online.net.Util")
  local alphabet = "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789"
  local out = {}
  for i = 1, n or 24 do
    local r = Util.rand32() % #alphabet
    out[i] = alphabet:sub(r + 1, r + 1)
  end
  return table.concat(out)
end
LH.randomKey = randomKey

local function clamp(v, lo, hi, def)
  v = tonumber(v)
  if not v then return def end
  v = math.floor(v)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end

---------------------------------------------------------------- config

LH.DEFAULTS = {
  name = "LINK HUB",
  port = LH.DEFAULT_PORT,
  relay = true,          -- short codes (relay rooms)
  tournaments = true,
  rendezvous = true,     -- hub codes (always useful; not shown as a row)
  portMap = true,        -- ask the router to open the hub's ports
  lanBeacon = true,      -- friends on this Wi-Fi see the hub in JOIN FRIEND
  gts = { enabled = false, games = {}, expireDays = 30, maxDeposits = 500 },
  world = { enabled = false, name = "HUB WORLD", game = nil, cap = 8,
            port = LH.DEFAULT_WORLD_PORT, public = false, gts = true },
  adminKey = nil,        -- generated on first load
  caps = { perIp = 16, players = 256, tcp = 512, messagesPerSecond = 30 },
  log = { file = true, level = "info", maskIps = true, keepDays = 14 },
  autoStart = false,     -- start the hub when the launcher opens
  useInGames = true,     -- point games launched from here at the hub
  hostChoice = nil,      -- "hub" | "direct": HOST WITH FRIENDS' remembered pick
  friend = nil,          -- { address, name, services, worldCode, worldGame, code }
}

-- fill in defaults and fix ranges (pure; tests call it)
function LH.normalize(c)
  c = type(c) == "table" and copy(c) or {}
  local d = LH.DEFAULTS
  local out = {}
  out.name = type(c.name) == "string" and c.name:sub(1, 24) or d.name
  if not out.name:match("%S") then out.name = d.name end
  out.port = clamp(c.port, 1024, 65535, d.port)
  for _, k in ipairs({ "relay", "tournaments", "rendezvous", "portMap", "lanBeacon", "useInGames" }) do
    if c[k] == nil then out[k] = d[k] else out[k] = c[k] == true end
  end
  out.autoStart = c.autoStart == true
  out.hostChoice = (c.hostChoice == "hub" or c.hostChoice == "direct") and c.hostChoice or nil
  local g = type(c.gts) == "table" and c.gts or {}
  out.gts = { enabled = g.enabled == true, games = {},
              expireDays = clamp(g.expireDays, 0, 365, d.gts.expireDays),
              maxDeposits = clamp(g.maxDeposits, 10, 5000, d.gts.maxDeposits) }
  if type(g.games) == "table" then
    for k, v in pairs(g.games) do if type(k) == "string" and v == true then out.gts.games[k] = true end end
  end
  local w = type(c.world) == "table" and c.world or {}
  out.world = { enabled = w.enabled == true,
                name = type(w.name) == "string" and w.name:sub(1, 20) or d.world.name,
                game = type(w.game) == "string" and w.game or nil,
                cap = clamp(w.cap, 2, LH.WORLD_CAP_MAX, d.world.cap),
                port = clamp(w.port, 1024, 65535, d.world.port),
                public = w.public == true,
                gts = w.gts ~= false }
  if not out.world.name:match("%S") then out.world.name = d.world.name end
  if out.world.port == out.port then out.world.port = out.port == 65535 and 65534 or out.port + 1 end
  local cp = type(c.caps) == "table" and c.caps or {}
  out.caps = { perIp = clamp(cp.perIp, 1, 256, d.caps.perIp),
               players = clamp(cp.players, 2, 1024, d.caps.players),
               tcp = clamp(cp.tcp, 2, 4096, d.caps.tcp),
               messagesPerSecond = clamp(cp.messagesPerSecond, 5, 500, d.caps.messagesPerSecond) }
  local l = type(c.log) == "table" and c.log or {}
  local levels = { debug = true, info = true, warn = true, error = true }
  out.log = { file = l.file ~= false, level = levels[l.level] and l.level or "info",
              maskIps = l.maskIps ~= false, keepDays = clamp(l.keepDays, 0, 365, 14) }
  out.adminKey = (type(c.adminKey) == "string" and #c.adminKey >= 12) and c.adminKey or nil
  if type(c.friend) == "table" and type(c.friend.address) == "string" then
    out.friend = { address = c.friend.address, name = type(c.friend.name) == "string" and c.friend.name or nil,
                   services = type(c.friend.services) == "table" and c.friend.services or nil,
                   worldCode = type(c.friend.worldCode) == "string" and c.friend.worldCode or nil,
                   worldGame = type(c.friend.worldGame) == "string" and c.friend.worldGame or nil,
                   worlds = type(c.friend.worlds) == "table" and c.friend.worlds or nil,
                   code = type(c.friend.code) == "string" and c.friend.code or nil }
  end
  return out
end

function LH.load()
  local f = fs()
  local raw
  if f and f.getInfo and f.getInfo(LH.CONFIG_FILE) then
    local okR, text = pcall(f.read, LH.CONFIG_FILE)
    if okR and text then
      local okJ, t = pcall(Json.decode, text)
      if okJ and type(t) == "table" then raw = t end
    end
  end
  local cfg = LH.normalize(raw)
  if not cfg.adminKey then
    cfg.adminKey = randomKey(24)
    LH.save(cfg)
  end
  state.cfg = cfg
  return cfg
end

function LH.config()
  return state.cfg or LH.load()
end

function LH.save(cfg)
  cfg = LH.normalize(cfg or state.cfg)
  if not cfg.adminKey then cfg.adminKey = randomKey(24) end
  state.cfg = cfg
  local f = fs()
  if not (f and f.write) then return false end
  pcall(f.createDirectory, "online_hub")
  local ok, text = pcall(Json.encode, cfg)
  if not ok then return false end
  return pcall(f.write, LH.CONFIG_FILE, text)
end

---------------------------------------------------------------- installed games

-- where imported caches live: the chosen / portable folder, else the save dir
-- (POKEPORT_HUB_GAMES_ROOT: harnesses only, read-only use)
function LH.cacheRoot()
  local env = os.getenv("POKEPORT_HUB_GAMES_ROOT")
  if env and env ~= "" then return (env:gsub("\\", "/"):gsub("/+$", "")) end
  local root
  pcall(function() root = require("src.import.CacheFs").root() end)
  if not root and love and love.filesystem and love.filesystem.getSaveDirectory then
    root = love.filesystem.getSaveDirectory()
  end
  return root and (tostring(root):gsub("\\", "/"):gsub("/+$", "")) or nil
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- { { id, name, dir, pool }, ... } for every game whose cache is imported
function LH.installedGames()
  local GameVersion = require("src.core.GameVersion")
  local okP, GtsPools = pcall(require, "src.online.gts.GtsPools")
  local root = LH.cacheRoot()
  local out = {}
  if not root then return out end
  for _, id in ipairs(GameVersion.ORDER) do
    local info = GameVersion.VERSIONS[id]
    if info then
      local dir = root .. "/" .. (GameVersion.cachePrefix(id) or "") .. "data/generated"
      if fileExists(dir .. "/pokemon.lua") then
        local pool = okP and GtsPools.poolFor(id) or nil
        out[#out + 1] = { id = id, name = info.launcherName or info.label or id, dir = dir,
                          pool = type(pool) == "table" and pool.id or pool }
      end
    end
  end
  return out
end

---------------------------------------------------------------- hub config

-- the launcher's config -> the hub's (src/online/hub/Config.lua keys)
function LH.toHubConfig(cfg, games)
  cfg = LH.normalize(cfg)
  games = games or LH.installedGames()
  local byId = {}
  for _, g in ipairs(games) do byId[g.id] = g end
  local saveDir = (love and love.filesystem and love.filesystem.getSaveDirectory
                   and love.filesystem.getSaveDirectory() or "."):gsub("\\", "/")
  local h = {
    name = cfg.name, port = cfg.port, udpPort = cfg.port,
    dataDir = os.getenv("POKEPORT_HUB_DATA") or (saveDir .. "/" .. LH.DATA_DIR),
    relay = { enabled = cfg.relay },
    tournaments = { enabled = cfg.tournaments },
    rendezvous = { enabled = cfg.rendezvous },
    caps = { perIp = cfg.caps.perIp, enetPeers = cfg.caps.players, tcpConnections = cfg.caps.tcp,
             messagesPerSecond = cfg.caps.messagesPerSecond },
    admin = { key = cfg.adminKey or "", localOnly = true },
    log = { level = cfg.log.level, file = cfg.log.file, keepDays = cfg.log.keepDays,
            addresses = not cfg.log.maskIps },
    statusSeconds = 30,
  }
  -- harnesses: bind and advertise 127.0.0.1 only
  local bind = os.getenv("POKEPORT_HUB_BIND")
  if bind and bind ~= "" then h.bind = bind end
  local lanEnv = os.getenv("POKEPORT_HUB_LAN")
  if lanEnv and lanEnv ~= "" then h.lanAddress = lanEnv end
  local pools, n = {}, 0
  if cfg.gts.enabled then
    for id in pairs(cfg.gts.games) do
      local g = byId[id]
      if g and g.pool then
        pools[g.pool] = pools[g.pool] or {}
        pools[g.pool][id] = g.dir
        n = n + 1
      end
    end
  end
  h.gts = { enabled = cfg.gts.enabled and n > 0, pools = pools, dataMode = "lean",
            expireDays = cfg.gts.expireDays, maxDeposits = cfg.gts.maxDeposits, name = cfg.name }
  local wg = cfg.world.game and byId[cfg.world.game]
  h.world = { enabled = cfg.world.enabled and wg ~= nil, port = cfg.world.port, name = cfg.world.name,
              cap = cfg.world.cap, public = cfg.world.public, gts = cfg.world.gts,
              game = wg and wg.id or nil, data = wg and wg.dir or nil }
  -- what the player asked for but the hub can't do (shown on the page)
  local notes = {}
  if cfg.gts.enabled and n == 0 then notes[#notes + 1] = "GTS: pick at least one game below" end
  if cfg.world.enabled and not wg then notes[#notes + 1] = "World: pick a game for it" end
  return h, notes
end

---------------------------------------------------------------- the thread

local function channels()
  return love.thread.getChannel(LH.CMD), love.thread.getChannel(LH.STATUS)
end

function LH.available()
  if not (love and love.thread and love.thread.newThread) then return false, "no threads here" end
  local okP, Platform = pcall(require, "src.core.Platform")
  if okP and Platform.online then
    local okO, o = pcall(Platform.online)
    if okO and type(o) == "table" then
      if o.available == false then return false, o.reason or "online play isn't available here" end
      if o.canHost == false then return false, o.reason or "this device can't host" end
    end
  end
  return true
end

function LH.phase() return state.phase end
function LH.running() return state.phase == "running" end
function LH.status() return state.status end
function LH.lastError() return state.error end

function LH.start(opts)
  opts = opts or {}
  if state.thread and state.thread:isRunning() then return true end
  local ok, why = LH.available()
  if not ok then state.phase, state.error = "failed", why return false, why end
  local cfg = LH.config()
  local hubCfg, notes = LH.toHubConfig(cfg)
  state.notes = notes
  local cmd, st = channels()
  cmd:clear()
  st:clear()
  local okT, thread = pcall(love.thread.newThread, "src/online/hub/HubThread.lua")
  if not okT then state.phase, state.error = "failed", tostring(thread) return false, state.error end
  local args = {
    packagePath = package.path, config = Json.encode(hubCfg), cmd = LH.CMD, status = LH.STATUS,
    portMap = cfg.portMap and os.getenv("POKEPORT_HUB_NO_PORTMAP") ~= "1",
    stdout = os.getenv("POKEPORT_HUB_STDOUT") == "1",
    beacon = cfg.lanBeacon,
    -- harnesses: keep the beacon on 127.0.0.1 / a private port
    beaconPort = tonumber(os.getenv("POKEPORT_HUB_BEACON_PORT") or ""),
  }
  -- thread arguments stay flat (strings): the thread splits / decodes them
  local targets = os.getenv("POKEPORT_HUB_BEACON_TARGETS")
  if targets and targets ~= "" then args.beaconTargets = targets end
  local pmo = os.getenv("POKEPORT_HUB_PORTMAP_OPTS") -- json, harnesses (a fake IGD)
  if pmo and pmo ~= "" then args.portMapOpts = pmo end
  local okS, err = pcall(thread.start, thread, args)
  if not okS then state.phase, state.error = "failed", tostring(err) return false, state.error end
  state.thread, state.phase, state.error, state.status = thread, "starting", nil, nil
  state.startedAt = os.time()
  state.runningCfg = copy(cfg)
  return true
end

function LH.stop()
  if not state.thread then state.phase = "off" return end
  love.thread.getChannel(LH.CMD):push("stop")
  state.phase = "stopping"
end

-- quit: ask, then wait a moment (LOVE waits for live threads at exit)
function LH.shutdown(budget)
  if not (state.thread and state.thread:isRunning()) then return end
  love.thread.getChannel(LH.CMD):push("stop")
  local deadline = (love.timer and love.timer.getTime() or os.clock()) + (budget or 2.5)
  while state.thread:isRunning() do
    if (love.timer and love.timer.getTime() or os.clock()) > deadline then break end
    if love.timer then love.timer.sleep(0.02) end
  end
end

function LH.admin(cmd, arg)
  if not LH.running() then return false end
  love.thread.getChannel(LH.CMD):push(Json.encode({ op = "admin", cmd = cmd, arg = arg }))
  return true
end

-- does the running hub use an older config than the saved one?
function LH.needsRestart()
  if not (state.runningCfg and (LH.running() or state.phase == "starting")) then return false end
  local a = Json.encode(LH.toHubConfig(state.runningCfg))
  local b = Json.encode(LH.toHubConfig(LH.config()))
  return a ~= b or state.runningCfg.portMap ~= LH.config().portMap
end

-- once a frame (launcher update; the game's input.step hook while playing)
function LH.poll()
  if state.thread then
    local _, st = channels()
    local text = st:pop()
    local latest
    while text do latest = text; text = st:pop() end
    if latest then
      local okJ, s = pcall(Json.decode, latest)
      if okJ and type(s) == "table" then
        state.status = s
        if s.state == "running" then state.phase = "running"
        elseif s.state == "failed" then state.phase, state.error = "failed", s.error
        elseif s.state == "stopped" then state.phase = "off" end
      end
    end
    if not state.thread:isRunning() then
      local err = state.thread:getError()
      if err then state.phase, state.error = "failed", err
      elseif state.phase ~= "failed" then state.phase = "off" end
      state.thread = nil
    end
  end
  LH.pollProbe()
end

---------------------------------------------------------------- addresses

function LH.lanIp()
  local env = os.getenv("POKEPORT_HUB_LAN")
  if env and env ~= "" then return env end
  local s = state.status
  if s and s.lan then return s.lan end
  local okU, Util = pcall(require, "src.online.net.Util")
  return okU and Util.lanIP() or nil
end

-- the router's outside address for the hub, when the mapping worked
function LH.publicIp()
  local m = state.status and state.status.mapping
  if m and m.state == "ok" then
    local Util = require("src.online.net.Util")
    if Util.isPublic(m.ip) then return m.ip end
  end
  return nil
end

-- the router's outside port for the hub, when it is not the hub's own
function LH.publicPort()
  local m = state.status and state.status.mapping
  return m and m.state == "ok" and tonumber(m.publicPort) or nil
end

function LH.localAddress()
  return "127.0.0.1:" .. tostring(LH.config().port)
end

-- THE share code: display, raw | nil, why
function LH.shareCode()
  if not LH.running() then return nil, "the hub isn't running" end
  local InviteCode = require("src.online.InviteCode")
  local cfg = LH.config()
  local port = (state.status.ports and state.status.ports.udp) or cfg.port
  local lan, pub = LH.lanIp(), LH.publicIp()
  if not lan and not pub then return nil, "no network address (is Wi-Fi on?)" end
  local spec = { kind = "hub", hub = { ip = pub, port = port, publicPort = pub and LH.publicPort() or nil },
                 lan = lan, ticket = 0 }
  local display, raw = InviteCode.encode(spec)
  if not display then return nil, raw end
  return display, raw
end

-- the text a Copy / Share hands over
function LH.shareText(display)
  return ("Join my Pokemon Link Hub! Open Gen2Recomped > Online Hub > JOIN FRIEND and paste: %s")
    :format(tostring(display))
end

-- a friend's hub code (ticket 0)?
function LH.isHubDoor(invite)
  return type(invite) == "table" and invite.kind == "hub" and tonumber(invite.ticket or invite.nonce) == 0
end

-- what kind of code `text` holds: invite, what | nil, why
--   what: "hub" (a friend's hub), "session" (a game's direct or hub code),
--         "short" (a 6-character relay room), "world"
function LH.classify(text)
  local InviteCode = require("src.online.InviteCode")
  local inv, why = InviteCode.findInText(text, LH.lanIp())
  if not inv then return nil, why end
  if inv.type == "short" then return inv, "short" end
  if LH.isHubDoor(inv) then return inv, "hub" end
  if inv.kind == "world" then return inv, "world" end
  return inv, "session"
end

-- the clipboard, when it holds something that decodes
function LH.clipboardCode()
  if not (love and love.system and love.system.getClipboardText) then return nil end
  local ok, text = pcall(love.system.getClipboardText)
  if not ok or type(text) ~= "string" or text == "" or #text > 400 then return nil end
  local inv, what = LH.classify(text)
  if inv then return inv, what end
  return nil
end

---------------------------------------------------------------- friend's hub

-- ping a hub (ENet, then TCP) in a job; LH.probeState() reports
function LH.probe(invite)
  local Util = require("src.online.net.Util")
  local list = {}
  for _, e in ipairs(invite.endpoints or {}) do list[#list + 1] = e end
  if #list == 0 and invite.hub and invite.hub.ip then
    list[1] = { ip = invite.hub.ip, port = invite.hub.port or invite.port, path = "hub" }
  end
  local job = Util.job(function(job)
    local tried = {}
    for _, e in ipairs(list) do
      local addr = Util.endpoint(e.ip, e.port)
      job.trying = addr
      local pong, why = LH.pingEnet(addr, 2.5)
      if not pong then pong = LH.pingTcp(addr, 2.0) end
      if pong then
        pong.address = addr
        pong.path = e.path
        return pong
      end
      tried[#tried + 1] = ("%s (%s)"):format(addr, e.path == "hub-lan" and "same Wi-Fi" or "internet")
    end
    local msg = "no answer from " .. table.concat(tried, ", ")
    local okO, OH = pcall(require, "src.online.OfficialHub")
    return nil, okO and OH.mask(msg) or msg
  end)
  state.probe = { job = job, invite = invite, phase = "trying" }
  return job
end

function LH.pingEnet(addr, timeout)
  local Util = require("src.online.net.Util")
  local okT, Transport = pcall(require, "src.online.net.Transport")
  if not okT or not Transport.available() then return nil, "no ENet" end
  local t = Transport.new({ port = 0, maxPeers = 1 })
  local ok = t:listen()
  if not ok then return nil, "can't open a socket" end
  local id = t:connect(addr, 0, { timeout = timeout })
  if not id then t:close(0) return nil, "can't dial" end
  local ch = t:channelFor(id, { owns = true })
  ch:send({ type = "hub_ping" })
  local deadline = Util.time() + timeout
  while Util.time() < deadline do
    ch:update()
    for _, m in ipairs(ch:poll()) do
      if type(m) == "table" and m.type == "hub_pong" then
        ch:close()
        return m
      end
    end
    if ch.closed then break end
    Util.yield()
  end
  pcall(ch.close, ch)
  return nil, "no answer"
end

function LH.pingTcp(addr, timeout)
  local Util = require("src.online.net.Util")
  local socket = Util.socket
  if not socket then return nil, "no sockets" end
  local host, port = Util.splitEndpoint(addr, LH.DEFAULT_PORT)
  local tcp = Util.tcp()
  tcp:settimeout(0)
  local ok, err = tcp:connect(host, tonumber(port))
  local deadline = Util.time() + timeout
  if not ok and err ~= "timeout" and err ~= "Operation already in progress" then
    tcp:close()
    return nil, err
  end
  local sent, buf = false, ""
  while Util.time() < deadline do
    if not sent then
      local _, w = socket.select(nil, { tcp }, 0)
      if w and #w > 0 then
        local okS = tcp:send(Json.encode({ type = "hub_ping" }) .. "\n")
        if okS then sent = true end
      end
    else
      local data, e, partial = tcp:receive("*l")
      if data then
        tcp:close()
        local okJ, m = pcall(Json.decode, buf .. data)
        if okJ and type(m) == "table" and m.type == "hub_pong" then return m end
        return nil, "not a hub"
      end
      if partial and partial ~= "" then buf = buf .. partial end
      if e == "closed" then break end
    end
    Util.yield()
  end
  tcp:close()
  return nil, "no answer"
end

function LH.probeState() return state.probe end

-- A HUB WITH A WORLD PER GAME (hub config `worlds`): the one a game joins.
-- pong.worlds = { { game, code, name }, ... } (older hubs: worldCode /
-- worldGame only).  The same game first, then the same family.
function LH.hubWorlds(pong)
  if type(pong) ~= "table" then return {} end
  if type(pong.worlds) == "table" and #pong.worlds > 0 then return pong.worlds end
  if pong.worldCode then return { { game = pong.worldGame, code = pong.worldCode } } end
  return {}
end

function LH.worldFor(pong, version)
  local list = LH.hubWorlds(pong)
  if #list == 0 then return nil end
  if not version then return list[1].code, list[1] end
  for _, w in ipairs(list) do if w.game == version then return w.code, w end end
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  local fam = okV and GameVersion.family and GameVersion.family(version) or nil
  if fam then
    for _, w in ipairs(list) do
      if w.game and GameVersion.family(w.game) == fam then return w.code, w end
    end
  end
  -- an old hub that did not say its game: offer it
  if #list == 1 and not list[1].game then return list[1].code, list[1] end
  return nil
end

-- the version id the running game is
function LH.currentVersion()
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if not okV then return nil end
  local ok, id = pcall(GameVersion.get)
  return ok and id or nil
end

function LH.pollProbe()
  local p = state.probe
  if not (p and p.job and p.phase == "trying") then return end
  p.job:update()
  if p.job.state == "done" then
    local pong = p.job.result
    p.phase, p.pong = "ok", pong
    local cfg = LH.config()
    cfg.friend = { address = pong.address, name = pong.name, services = pong.services,
                   worldCode = pong.worldCode, worldGame = pong.worldGame, worlds = pong.worlds,
                   code = p.invite and p.invite.display or nil }
    LH.save(cfg)
  elseif p.job.state == "failed" then
    p.phase, p.why = "failed", p.job.reason
  end
end

function LH.forgetFriend()
  local cfg = LH.config()
  cfg.friend = nil
  LH.save(cfg)
  state.probe = nil
end

---------------------------------------------------------------- in the game

-- the hub a game launched from here uses when its own settings name none
function LH.gameHubAddress()
  local cfg = LH.config()
  if not cfg.useInGames then return nil end
  if LH.running() then return LH.localAddress() end
  if cfg.friend and cfg.friend.address then return cfg.friend.address end
  return nil
end

-- what the host's own HUB codes carry for the in-process hub
function LH.advertisedEndpoint(address)
  if not (LH.running() and address == LH.localAddress()) then return nil end
  local pub, lan = LH.publicIp(), LH.lanIp()
  local ip = pub or lan
  if not ip then return nil end
  local port = (state.status and state.status.ports and state.status.ports.udp) or LH.config().port
  -- with a public address, the LAN one rides beside it in the code
  return ip, port, pub and lan or nil, pub and LH.publicPort() or nil
end

-- LinkState (WS4) reads its settings through LinkState.settings and makes
-- HUB codes through LinkState.hubEndpoint; both are wrapped here, at run
-- time, so the game's file is untouched and its own settings still win
function LH.patchLinkState()
  local ok, LinkState = pcall(require, "src.link.LinkState")
  if not (ok and type(LinkState) == "table" and LinkState.settings) then return false end
  if LinkState._launcherHub then return true end
  local origSettings, origEndpoint = LinkState.settings, LinkState.hubEndpoint
  LinkState.settings = function(game, ...)
    local s = origSettings(game, ...)
    -- (the official server is only a fallback: the launcher's own or a
    -- friend's hub replaces it)
    if type(s) == "table" and (not s.hubAddress or s.hubOfficial) then
      local okA, addr = pcall(LH.gameHubAddress)
      if okA and addr then s.hubAddress, s.hubFromLauncher, s.hubOfficial = addr, true, nil end
    end
    return s
  end
  LinkState.hubEndpoint = function(address, ...)
    local okE, ip, port, lan, publicPort = pcall(LH.advertisedEndpoint, address)
    if okE and ip then return ip, port, lan, publicPort end
    return origEndpoint(address, ...)
  end
  LinkState._launcherHub = { settings = origSettings, hubEndpoint = origEndpoint }
  return true
end

-- a thing to do once the next game is on its map:
--   { kind = "host" } | { kind = "join", code = "..." } | { kind = "world", code = "..." }
function LH.setPending(action) state.pending = action end
function LH.pending() return state.pending end

-- run a pending action in `game` (true when one ran)
function LH.runPending(game)
  local a = state.pending
  if not (a and game and game.stack) then return false end
  state.pending = nil
  if a.kind == "host" then
    local LinkState = require("src.link.LinkState")
    local ls = LinkState.new(game)
    game.stack:push(ls)
    ls:chooseMenu("host")
  elseif a.kind == "join" then
    local LinkState = require("src.link.LinkState")
    game.stack:push(LinkState.newJoinOnline(game, a.code))
  elseif a.kind == "world" then
    local OnlineWorld = require("src.online.world.OnlineWorld")
    local okJ, why = OnlineWorld.joinWorld(game, a.code)
    if not okJ then
      local okT, TextBox = pcall(require, "src.ui.TextBox")
      if okT then game.stack:push(TextBox.new(game, tostring(why or "Can't join that world."))) end
    else
      pcall(OnlineWorld.openMenu, game)
    end
  else
    return false
  end
  return true
end

LH.HOOK_OWNER = "launcher-hub"

-- Game:load calls this (one pcall line): settings patch, the hub's status
-- kept fresh, the pending action, and the Discord join secret
function LH.installGame(game)
  LH.patchLinkState()
  if not (state.pending or state.thread or LH.config().friend) then return end
  local okR, Runtime = pcall(require, "src.mods.Runtime")
  if not okR then return end
  local entered, wait = false, 0
  if Runtime.events and Runtime.events.on then
    Runtime.events:on("map.entered", function() entered = true end, 0, LH.HOOK_OWNER)
  end
  local hooks = Runtime.hooks
  if hooks and hooks.wrap then
    hooks:wrap("input.step", function(nextFn, g, dt)
      pcall(LH.poll)
      if entered and state.pending then
        wait = wait + (dt or 0)
        if wait > 0.75 then
          local top = g.stack and g.stack.top and g.stack:top()
          if not (top and top.stage and top.net) then
            local okP, err = pcall(LH.runPending, g)
            if not okP then
              pcall(function() require("src.core.Logger").warn("launcher hub: %s", tostring(err)) end)
            end
          end
        end
      end
      return nextFn(g, dt)
    end, -900, LH.HOOK_OWNER)
  end
  -- Discord "Ask to Join": while the hub runs, the join secret is the hub's
  -- share code (LinkState replaces it with a session code while hosting)
  if LH.running() then
    local display = LH.shareCode()
    if display then
      pcall(function() require("src.core.DiscordPresence").setJoinCode(display, "match", 1, 16) end)
    end
  end
end

-- DiscordPresence: a join secret that is a friend's hub code is not a
-- session to dial: remember the hub (and open its world when it has one)
-- instead.  true when handled.
function LH.handleJoinSecret(game, code)
  local inv, what = LH.classify(code)
  if what ~= "hub" then return false end
  LH.probe(inv)
  local okU, Util = pcall(require, "src.online.net.Util")
  if okU then Util.runSync(state.probe.job, 6, nil) end
  LH.pollProbe()
  local p = state.probe
  local okT, TextBox = pcall(require, "src.ui.TextBox")
  if p and p.phase == "ok" then
    local wcode = game and LH.worldFor(p.pong, LH.currentVersion()) or nil
    if wcode and game then
      LH.setPending({ kind = "world", code = wcode })
      LH.runPending(game)
    elseif okT and game then
      game.stack:push(TextBox.new(game, ("Now using %s's\nLink Hub."):format(tostring(p.pong.name or "a friend"))))
    end
  elseif okT and game then
    game.stack:push(TextBox.new(game, "Couldn't reach\nthat Link Hub."))
  end
  return true
end

-- the launcher opened: autostart (games patch LinkState in installGame)
function LH.launcherOpened()
  local cfg = LH.config()
  if cfg.autoStart and not state.thread and state.phase ~= "failed" and not state.autoTried then
    state.autoTried = true
    LH.start()
  end
end

return LH
