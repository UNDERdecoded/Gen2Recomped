-- The Link Hub inside the game: this file is the body of a love.thread the
-- launcher starts (src/online/LauncherHub.lua).  A thread has its own Lua
-- state, so the hub's game data (GameVersion, Data tables for the GTS and
-- the world) never touches the game the player is running, and it keeps
-- serving while the launcher hands over to a game and back.
--
--   args = { packagePath, config = <json of a hub config table>,
--            cmd = <channel name>, status = <channel name>,
--            portMap = bool, portMapOpts = {...}, stdout = bool,
--            statusEvery = seconds }
--
-- Commands (cmd channel, strings or json): "stop", "status",
--   {"op":"admin","cmd":...,"arg":...} (kick / worldban / ban / unban).
-- Status (status channel, json, newest only):
--   { state = "starting"|"running"|"failed"|"stopped", error, hub = hub:status(),
--     world = snapshot, lan, mapping = { state, ip, method, why, ports },
--     log = { last lines }, at }

local args = ...
require("love.filesystem")
require("love.timer")
pcall(require, "love.system")
if type(args) == "table" and args.packagePath then package.path = args.packagePath end

local Json = require("src.link.Json")
-- flat arguments (see LauncherHub.start)
if type(args.beaconTargets) == "string" then
  local list = {}
  for t in args.beaconTargets:gmatch("[^,]+") do list[#list + 1] = t end
  args.beaconTargets = list
end
if type(args.portMapOpts) == "string" then
  local okO, o = pcall(Json.decode, args.portMapOpts)
  args.portMapOpts = okO and type(o) == "table" and o or nil
end
local cmdCh = love.thread.getChannel(args.cmd)
local statusCh = love.thread.getChannel(args.status)

local function publish(t)
  t.at = os.time()
  local ok, text = pcall(Json.encode, t)
  if not ok then text = Json.encode({ state = t.state, error = "status: " .. tostring(text) }) end
  statusCh:clear()
  statusCh:push(text)
end

publish({ state = "starting" })

local Util = require("src.online.net.Util")
local Config = require("src.online.hub.Config")
local Log = require("src.online.hub.Log")
local Hub = require("src.online.hub.Hub")

local okCfg, overrides = pcall(Json.decode, args.config or "{}")
if not okCfg or type(overrides) ~= "table" then
  publish({ state = "failed", error = "bad config: " .. tostring(overrides) })
  return
end
local cfg, problems = Config.load(nil, overrides)
if not cfg then
  publish({ state = "failed", error = table.concat(problems or { "bad config" }, "; ") })
  return
end

local log = Log.new({ dir = cfg.dataDir .. "/logs", level = cfg.log.level, file = cfg.log.file,
                      keepDays = cfg.log.keepDays, addresses = cfg.log.addresses,
                      stdout = args.stdout == true })
local hub = Hub.new(cfg, { log = log })
local okStart, started, why = pcall(hub.start, hub)
if not okStart or not started then
  local err = okStart and why or started
  log:error("can't start: %s", tostring(err))
  pcall(hub.stop, hub, "start failed")
  publish({ state = "failed", error = tostring(err) })
  return
end
log:info("running in the launcher; services: %s", table.concat(hub:services(), ", "))

local lan = cfg.lanAddress or Util.lanIP()

---------------------------------------------------------------- router mapping

local mapping = { state = args.portMap and "trying" or "off", ports = {} }
local mapJob, mapAgainAt

local function startMapping()
  local PortMap = require("src.online.net.PortMap")
  local opts = args.portMapOpts or {}
  local wanted = {}
  if hub.tcp then wanted[#wanted + 1] = { cfg.port, "TCP" } end
  if hub.enet then wanted[#wanted + 1] = { cfg.udpPort, "UDP" } end
  if hub.world then wanted[#wanted + 1] = { cfg.world.port, "UDP" } end
  mapping.state = "trying"
  mapJob = Util.job(function()
    local o = {}
    for k, v in pairs(opts) do o[k] = v end
    o.timeout = o.timeout or 3
    local gw, whyGw = PortMap.discover(o)
    if not gw then return nil, whyGw end
    local ip, note, publicPort
    local done = {}
    for _, w in ipairs(wanted) do
      local got, ext, n = PortMap.map(gw, w[1], w[2], PortMap.DEFAULT_LEASE,
                                      { description = "Link Hub " .. w[2] .. " " .. w[1] })
      if got then
        ip, note = got, note or n
        -- the hub's own UDP port, as seen from outside: it goes in share codes
        if w[2] == "UDP" and not publicPort then publicPort = ext end
        done[#done + 1] = ("%s %d->%d"):format(w[2], w[1], ext or w[1])
      else
        done[#done + 1] = ("%s %d: %s"):format(w[2], w[1], tostring(ext))
      end
    end
    if not ip then return nil, table.concat(done, "; ") end
    return { ip = ip, method = gw.kind, note = note, ports = done, publicPort = publicPort }
  end)
end

local function pollMapping(now)
  if mapJob then
    mapJob:update()
    if mapJob.state == "done" then
      local r = mapJob.result
      mapping = { state = "ok", ip = r.ip, method = r.method, note = r.note, ports = r.ports,
                  publicPort = r.publicPort }
      log:info("router: %s opened the hub's ports (%s), outside address %s", tostring(r.method),
               table.concat(r.ports or {}, ", "), log:addr(r.ip))
      if Util.isPublic(r.ip) then
        hub.advertiseIp = r.ip
        if hub.world then
          local code = hub.world:inviteCode(r.ip, lan)
          if code then
            hub.world.code = code
            pcall(require("src.online.hub.Files").writeAtomic, cfg.dataDir .. "/world_code.txt", code .. "\n")
          end
        end
      end
      mapJob = nil
      mapAgainAt = now + 50 * 60 -- the lease is an hour
    elseif mapJob.state == "failed" then
      mapping = { state = "failed", why = mapJob.reason, ports = {} }
      log:warn("router: couldn't open the hub's ports: %s", tostring(mapJob.reason))
      mapJob = nil
      mapAgainAt = now + 10 * 60
    end
  elseif mapAgainAt and now >= mapAgainAt then
    mapAgainAt = nil
    startMapping()
  end
end

if args.portMap then startMapping() end

---------------------------------------------------------------- LAN beacon

-- friends on the same Wi-Fi see the hub in the launcher's JOIN FRIEND list.
-- The tag is not a game's, so a game's own JOIN list greys it out.
local beacon
if args.beacon and hub.enet then
  local okB, LanBeacon = pcall(require, "src.online.net.LanBeacon")
  if okB then
    local okN, b = pcall(LanBeacon.newBroadcaster, {
      info = { name = tostring(cfg.name):sub(1, 32), kind = "hub", hub = true,
               port = hub.enet.boundPort or cfg.udpPort, nonce = 0,
               v = "hub:" .. LanBeacon.tag(),
               world = hub.world and true or nil, gts = hub.gts and true or nil },
      targets = args.beaconTargets, port = args.beaconPort })
    if okN then beacon = b end
  end
end

---------------------------------------------------------------- status

local function snapshot(state)
  local okS, st = pcall(hub.status, hub)
  local world
  if hub.world then
    local okW, w = pcall(hub.world.snapshot, hub.world)
    if okW then world = w end
  end
  local lines = {}
  local all = log.lines or {}
  for i = math.max(1, #all - 11), #all do lines[#lines + 1] = all[i] end
  return { state = state, hub = okS and st or nil, world = world, lan = lan,
           mapping = mapping, log = lines, dataDir = cfg.dataDir,
           ports = { tcp = hub.tcp and hub.tcp.boundPort or nil,
                     udp = hub.enet and (hub.enet.boundPort or cfg.udpPort) or nil,
                     world = hub.world and (hub.world.transport.boundPort or cfg.world.port) or nil } }
end

local function adminCommand(c)
  local fake = { ip = "127.0.0.1", address = "127.0.0.1:0", kind = "thread", closed = false }
  local reply
  function fake:send(m) reply = m end
  function fake:close() end
  hub:admin(fake, { type = "hub_admin", key = cfg.admin.key, cmd = c.cmd, arg = c.arg })
  return reply
end

---------------------------------------------------------------- the loop

local every = tonumber(args.statusEvery) or 0.5
local lastPublish = -1
local stopReason
while true do
  local now = Util.now()
  local okU, err = xpcall(function() hub:update() end, debug.traceback)
  if not okU then log:error("update failed: %s", tostring(err)) end
  pollMapping(now)
  if beacon then pcall(beacon.update, beacon) end
  local c = cmdCh:pop()
  while c do
    if c == "stop" then stopReason = "stopped from the launcher" break end
    if c == "status" then lastPublish = -1 end
    if type(c) == "string" and c:sub(1, 1) == "{" then
      local okJ, m = pcall(Json.decode, c)
      if okJ and type(m) == "table" and m.op == "admin" then
        local okA, r = pcall(adminCommand, m)
        log:info("launcher admin %s: %s", tostring(m.cmd), okA and r and tostring(r.ok) or tostring(r))
      end
    end
    c = cmdCh:pop()
  end
  if stopReason or hub.stopping then break end
  if now - lastPublish >= every then
    lastPublish = now
    publish(snapshot("running"))
  end
  love.timer.sleep(0.004)
end

if beacon then pcall(beacon.close, beacon) end
pcall(hub.stop, hub, stopReason or "admin stop")
if package.loaded["src.online.net.PortMap"] then
  pcall(package.loaded["src.online.net.PortMap"].releaseAll, 1.5)
end
local final = snapshot("stopped")
final.error = nil
publish(final)
