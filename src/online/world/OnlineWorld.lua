-- ONLINE WORLDS, the one door the rest of the game uses (workstream WS8,
-- docs/online-design.md 2.8).
--
--   OnlineWorld.openMenu(game)              the WORLDS screen (WS4's LINK
--                                           menu calls this for its WORLDS row)
--   OnlineWorld.hostWorld(game, spec)       spec: { name, cap (8, max 16),
--                                           public, gts (default on),
--                                           filter (chat filter; nil = on
--                                           when public),
--                                           worldId (re-host),
--                                           connector = Connector.host opts }
--   OnlineWorld.joinWorld(game, invite|code, opts)
--   OnlineWorld.current()                   the session, or nil
--   OnlineWorld.inviteCode()                the host's world code (display form)
--   OnlineWorld.leave()                     leave (a host closes its world)
--   OnlineWorld.tick(dt)                    pump everything; idempotent
--   OnlineWorld.serviceChannel(name, cb)    a member's channel to a host
--                                           service: cb(channel | nil, why)
--   OnlineWorld.serviceFactories[name] = function(host, game) -> service
--                                           WS7: the world GTS is attached to
--                                           every world this game hosts
--
-- TICKING.  A world must keep moving whatever screen is up -- a wild battle,
-- the bag, a trade -- or the host stops hearing from its members (ENet times
-- a silent peer out).  So the session is pumped from the engine's logic-step
-- seam `input.step` (Game:_step runs it every step, before the stack,
-- whatever state is on top), and also from every world screen and every
-- session channel's update.  tick() guards re-entry, and everything in it is
-- driven by the wall clock, so pumping twice in a step costs nothing.  The
-- chat HUD draws from the `render.hud` seam.  Both are wrapped only while a
-- world is open and re-wrapped if the mod loader reinstalls its buses.

local P = require("src.online.world.WorldProtocol")
local WorldHost = require("src.online.world.WorldHost")
local WorldClient = require("src.online.world.WorldClient")
local WorldStore = require("src.online.world.WorldStore")
local Identity = require("src.online.world.Identity")
local MapSet = require("src.online.world.MapSet")
local Presence = require("src.online.world.Presence")
local Logger = require("src.core.Logger")

local OnlineWorld = {}

OnlineWorld.session = nil
OnlineWorld.serviceFactories = {}
-- Connector.host options every hosted world starts from (a spec's own
-- `connector` table wins key by key).  WS10's online settings screen is the
-- place to fill these from the player's choices (port, UPnP, beacon).
OnlineWorld.connectorDefaults = { port = 7777, portMap = true, lanBeacon = true }
OnlineWorld.HOOK_OWNER = "online"

-- ------------------------------------------------------------ who we are

function OnlineWorld.helloFor(game)
  local Handshake = require("src.link.Handshake")
  local h = Handshake.hello(game, nil, { mapSet = MapSet.of(game and game.data) })
  -- the world feature on this copy (Handshake.FEATURES is WS3's list)
  local has = false
  for _, f in ipairs(h.features or {}) do if f == "world" then has = true end end
  if not has then
    h.features = h.features or {}
    h.features[#h.features + 1] = "world"
  end
  return h
end

-- Connector.host options from WS4's settings reader, when it is there
function OnlineWorld.settingsOptions(game)
  local ok, LinkState = pcall(require, "src.link.LinkState")
  if not (ok and type(LinkState) == "table" and LinkState.settings and LinkState.hostOptions) then
    return {}
  end
  local okS, opts = pcall(function() return LinkState.hostOptions(LinkState.settings(game)) end)
  if not (okS and type(opts) == "table") then return {} end
  opts.allowRelay, opts.relayHost = false, false   -- worlds are direct codes only
  return opts
end

-- the player's online options (save.options.online: WS4 reads them, WS10's
-- settings screen writes them)
local function onlineOptions(game)
  local o = game and game.save and game.save.options
  o = type(o) == "table" and o.online
  return type(o) == "table" and o or {}
end

-- the world size the player set (worldCap, 2..16, default 8)
function OnlineWorld.defaultCap(game)
  local cap = tonumber(onlineOptions(game).worldCap)
  if cap then return P.clampCap(cap) end
  return P.DEFAULT_CAP
end

-- the name a world shows for this player: the settings' displayName when
-- set, else the save's trainer name
function OnlineWorld.playerName(game)
  local shown = P.cleanName(onlineOptions(game).displayName)
  if shown then return shown end
  local p = game and game.save and game.save.player or {}
  return P.cleanName(p.name) or "PLAYER"
end

local function playerInfo(game)
  local p = game and game.save and game.save.player or {}
  local name = OnlineWorld.playerName(game)
  local tid = (tonumber(p.id) or 0) % 65536
  local ow = game and game.overworld
  return name, tid, Presence.localLook(game, ow), Presence.localPos(game, ow)
end

local function newClient(game, opts)
  local name, tid, look, pos = playerInfo(game)
  local hello = OnlineWorld.helloFor(game)
  local c = WorldClient.new({
    net = opts.net, job = opts.job, name = name, tid = tid, look = look, pos = pos,
    hello = function() return hello end,
    identity = function(worldId) return Identity.forWorld(worldId) end,
  })
  c.pump = function() OnlineWorld.tick() end
  return c, hello
end

-- ------------------------------------------------------------ start / stop

function OnlineWorld.current() return OnlineWorld.session end

function OnlineWorld.client()
  return OnlineWorld.session and OnlineWorld.session.client
end

function OnlineWorld.isHost()
  return OnlineWorld.session ~= nil and OnlineWorld.session.host ~= nil
end

function OnlineWorld.hostWorld(game, spec)
  spec = spec or {}
  if OnlineWorld.session then OnlineWorld.leave() end
  local store = spec.store or WorldStore.new()
  local world = spec.worldId and store:open(spec.worldId)
  if world then
    if spec.cap then world.cap = P.clampCap(spec.cap) end
    if spec.name then world.name = P.cleanText(spec.name, P.WORLD_NAME_MAX) or world.name end
    if spec.public ~= nil then world.public = spec.public and true or false end
    if spec.filter ~= nil then world.filter = spec.filter and true or false end
    store:saveWorld(world)
  else
    world = store:create({ name = spec.name, cap = spec.cap, public = spec.public, id = spec.worldId,
                           filter = spec.filter })
  end
  local client, hello = newClient(game, {})
  local copts = {}
  for k, v in pairs(OnlineWorld.connectorDefaults) do copts[k] = v end
  -- the player's own online settings (WS4: save.options.online), as the
  -- LINK screen's direct-code host uses them -- never the relay
  for k, v in pairs(OnlineWorld.settingsOptions(game)) do copts[k] = v end
  for k, v in pairs(spec.connector or {}) do copts[k] = v end
  local host = WorldHost.new({ world = world, store = store, hello = hello, data = game.data,
                               connector = copts })
  client.net = host:localClientNet()
  client.state = "greeting"
  for name, factory in pairs(OnlineWorld.serviceFactories) do
    if name == "gts" and spec.gts == false then factory = nil end
    local ok, svc = true, nil
    if factory then ok, svc = pcall(factory, host, game) end
    if ok and svc then host:registerService(name, svc)
    elseif not ok then Logger.warn("world: service %s did not start: %s", name, tostring(svc)) end
  end
  OnlineWorld.session = { game = game, host = host, client = client, store = store, world = world,
                          prompts = {}, startedAt = os.time() }
  OnlineWorld.ensureHooks()
  Logger.info("world: hosting %q (cap %d, id %s)", world.name, world.cap, world.id)
  return OnlineWorld.session
end

function OnlineWorld.joinWorld(game, invite, opts)
  opts = opts or {}
  if OnlineWorld.session then OnlineWorld.leave() end
  local InviteCode = require("src.online.InviteCode")
  local Util = require("src.online.net.Util")
  if type(invite) == "string" then
    local decoded, why = InviteCode.decode(invite, Util.lanIP())
    if not decoded then return nil, why end
    invite = decoded
  end
  if type(invite) ~= "table" then return nil, "no code" end
  if invite.kind ~= "world" and invite.kindId ~= 1 then
    return nil, "That is not a world code."
  end
  local Connector = require("src.online.net.Connector")
  local job = Connector.join(invite, { maxPeers = 1, port = opts.port, driver = opts.driver,
                                       timeouts = opts.timeouts })
  local client = newClient(game, { job = job })
  OnlineWorld.session = { game = game, client = client, invite = invite, prompts = {},
                          startedAt = os.time() }
  OnlineWorld.ensureHooks()
  return OnlineWorld.session
end

function OnlineWorld.inviteCode()
  local s = OnlineWorld.session
  if not (s and s.host) then return nil end
  local c = s.host.connector
  if not c or c.state == "starting" or c.pending then return nil, "starting" end
  if c.state == "failed" then return nil, c.reason end
  local fields = s.host:inviteFields()
  if not fields then return nil, "no address" end
  if s.codeFor ~= c then
    local InviteCode = require("src.online.InviteCode")
    local display, _, warning = InviteCode.encode(fields)
    s.code, s.codeWarning, s.codeFor = display, warning, c
  end
  return s.code, s.codeWarning
end

-- the session is over (left, kicked, lost): clean up and say why
function OnlineWorld.finish(text)
  local s = OnlineWorld.session
  if not s then return end
  OnlineWorld.session = nil
  Presence.shutdown()
  OnlineWorld.syncGtsProvider()
  if s.host then pcall(s.host.close, s.host) end
  if s.client and s.client.state ~= "closed" then pcall(s.client.close, s.client, "left") end
  OnlineWorld.lastEnded = { text = text, at = os.time() }
  if text and s.game and not s.quiet then OnlineWorld.say(s.game, text) end
end

function OnlineWorld.leave()
  local s = OnlineWorld.session
  if not s then return end
  s.quiet = true
  if s.client then pcall(s.client.leave, s.client) end
  OnlineWorld.tick()
  OnlineWorld.finish(nil)
end

-- a short message over the field, once the field is up
function OnlineWorld.say(game, text)
  OnlineWorld.notices = OnlineWorld.notices or {}
  table.insert(OnlineWorld.notices, text)
end

function OnlineWorld.serviceChannel(name, cb)
  local c = OnlineWorld.client()
  if not (c and c.state == "in") then
    if cb then cb(nil, "not in a world") end
    return nil
  end
  return c:openService(name, cb)
end

-- ------------------------------------------------------------ events

-- the world screens are popped before a link screen goes up over them
local function popWorldUi(game)
  local stack = game and game.stack
  while stack and stack:top() and stack:top().isWorldUi do stack:pop() end
end

-- a screen that stands in for the field (the link rooms' Union Room and
-- Wi-Fi Plaza lobbies, src/online/LinkRooms.lua / Plaza.lua) sets
-- `acceptsInvites = true`: invites and notices then come up over it
function OnlineWorld.canInterrupt(game)
  local stack = game and game.stack
  local top = stack and stack:top()
  if top and top.acceptsInvites then return true end
  local ow = game and game.overworld
  if not (top and ow and top == ow) then return false end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return false end
  if ow.player and ow.player.moving then return false end
  return true
end

function OnlineWorld.dispatch(s, ev)
  local game = s.game
  if ev.kind == "session" then
    popWorldUi(game)
    local ok, err = pcall(function()
      require("src.online.world.WorldLink").open(game, ev.channel, {
        mode = ev.mode, isHost = ev.role == "host", peerName = ev.peerName })
    end)
    if not ok then
      Logger.warn("world: could not open the link screen: %s", tostring(err))
      ev.channel:close()
    end
  elseif ev.kind == "invite" then
    s.prompts[#s.prompts + 1] = ev
  elseif ev.kind == "withdrawn" then
    for i = #s.prompts, 1, -1 do
      if s.prompts[i].iid == ev.iid then table.remove(s.prompts, i) end
    end
    s.withdrawn = s.withdrawn or {}
    s.withdrawn[ev.iid] = ev.reason or true
  elseif ev.kind == "answer" then
    s.lastAnswer = ev
  elseif ev.kind == "closed" then
    s.closedText = ev.text
  end
end

-- ------------------------------------------------------------ ticking

local ticking = false

function OnlineWorld.tick(dt)
  local s = OnlineWorld.session
  if not s or ticking then return end
  ticking = true
  local ok, err = pcall(function()
    OnlineWorld.ensureHooks()
    if s.host then s.host:update() end
    s.client:update()
    if s.host then s.host:update() end
    Presence.update(s.client, s.game)
    for _, ev in ipairs(s.client:events()) do
      OnlineWorld.dispatch(s, ev)
      if ev.kind == "welcome" then OnlineWorld.syncGtsProvider() end
    end
    if s.host and s.host.state == "failed" then
      s.client:close("failed", "Couldn't open the world:\n" .. tostring(s.host.reason))
    end
    if s.client.state == "closed" then
      OnlineWorld.finish(s.closedText or s.client.reason)
      return
    end
    -- an invite waits for the field to be free (not mid-script, not mid-step)
    if s.prompts[1] and OnlineWorld.canInterrupt(s.game) then
      local ev = table.remove(s.prompts, 1)
      if s.client.incoming[ev.iid] then
        require("src.ui.online.GhostInteract").openInvite(s.game, ev)
      end
    end
  end)
  ticking = false
  if not ok then
    Logger.warn("world: tick failed: %s", tostring(err))
    OnlineWorld.tickErrors = (OnlineWorld.tickErrors or 0) + 1
    if OnlineWorld.tickErrors > 30 then OnlineWorld.finish("The world stopped:\n" .. tostring(err)) end
  end
  -- messages for the field once it is up again
  local game = s.game
  if OnlineWorld.notices and OnlineWorld.notices[1] and OnlineWorld.canInterrupt(game) then
    local text = table.remove(OnlineWorld.notices, 1)
    local okT, TextBox = pcall(require, "src.render.TextBox")
    if okT then game.stack:push(TextBox.new(game, text)) end
  end
end

-- also flush a notice after the session has ended (nothing ticks then)
function OnlineWorld.flushNotices(game)
  if OnlineWorld.notices and OnlineWorld.notices[1] and OnlineWorld.canInterrupt(game) then
    local text = table.remove(OnlineWorld.notices, 1)
    local okT, TextBox = pcall(require, "src.render.TextBox")
    if okT then game.stack:push(TextBox.new(game, text)) end
  end
end

-- ------------------------------------------------------------ engine seams

function OnlineWorld.ensureHooks()
  local okR, Runtime = pcall(require, "src.mods.Runtime")
  if not okR then return end
  local hooks = Runtime.hooks
  if not (hooks and hooks.wrap) or hooks == OnlineWorld._hooks then return end
  OnlineWorld._hooks = hooks
  hooks:wrap("input.step", function(nextFn, game, dt)
    if OnlineWorld.session then
      OnlineWorld.tick(dt)
    elseif OnlineWorld.notices and OnlineWorld.notices[1] then
      OnlineWorld.flushNotices(game)
    end
    return nextFn(game, dt)
  end, -1000, OnlineWorld.HOOK_OWNER)
  hooks:wrap("render.hud", function(nextFn, game, viewport)
    local r = { nextFn(game, viewport) }
    if OnlineWorld.session then
      local okH, err = pcall(function()
        require("src.ui.online.ChatOverlay").drawHud(game, viewport)
      end)
      if not okH and not OnlineWorld.hudWarned then
        OnlineWorld.hudWarned = true
        Logger.warn("world: hud draw failed: %s", tostring(err))
      end
    end
    return (table.unpack or unpack)(r)
  end, -1000, OnlineWorld.HOOK_OWNER)
end

-- ------------------------------------------------------------ the world GTS

-- THE EMBED POINT (WS7).  A world this game hosts runs a GTS for its
-- members unless the host turned it off (spec.gts = false).  The service is
-- WS7's own GtsService behind its GtsHost, over GtsStore files in this
-- world's folder (online/worlds/<id>/gts), served one Net-API channel per
-- member (GtsHost:serveChannel, keyed by the member's per-world identity).
-- Replace OnlineWorld.serviceFactories.gts to change any of it; a factory
-- that throws only leaves the world without a GTS.
OnlineWorld.serviceFactories.gts = function(host, game)
  local GtsService = require("src.online.gts.GtsService")
  local GtsHost = require("src.online.gts.GtsHost")
  local GtsStore = require("src.online.gts.GtsStore")
  local GameVersion = require("src.core.GameVersion")
  local okP, GtsPools = pcall(require, "src.online.gts.GtsPools")
  local pool = okP and GtsPools.poolFor and GtsPools.poolFor(GameVersion.get()) or nil
  local svc = GtsService.new({
    store = GtsStore.new(GtsStore.loveFs("online/worlds/" .. tostring(host.world.id) .. "/gts")),
    pools = pool and { type(pool) == "table" and pool.id or pool } or nil,
    datasets = { [GameVersion.get()] = game.data },
    name = host.world.name,
    log = function(line) Logger.info("%s", tostring(line)) end,
  })
  local gh = GtsHost.new(svc)
  local lastTick = 0
  return {
    gtsHost = gh, gtsService = svc,
    open = function(ch, member)
      gh:serveChannel(ch, member.id or ("pid" .. tostring(member.pid)))
    end,
    update = function(now)
      gh:update()
      if (now or 0) - lastTick > 30 then
        lastTick = now or 0
        pcall(svc.tick, svc)
      end
    end,
  }
end

-- the 4-player multi battle's relay (src/online/MultiNet.lua): every world
-- this game hosts can carry a multi lobby between its members (the Union
-- Room's MULTI row, MultiBattle.open with { world = true })
OnlineWorld.serviceFactories.multi = function() return require("src.online.MultiNet").relayService() end

-- a member's GTS channel (paired once the host answers); the shape
-- GtsClient.setProvider wants
function OnlineWorld.gtsChannel()
  local c = OnlineWorld.client()
  if not (c and c.state == "in" and c:hasService("gts")) then return nil end
  return c:openService("gts")
end

local function gtsProvider() return OnlineWorld.gtsChannel() end
OnlineWorld.gtsProvider = gtsProvider

-- while this player is in a world with a GTS, the game's GTS counters open
-- that world's (GtsClient's provider), unless something else (a hub) is
-- already the provider; given back when the world ends
function OnlineWorld.syncGtsProvider()
  local okG, GtsClient = pcall(require, "src.online.gts.GtsClient")
  if not (okG and type(GtsClient) == "table" and GtsClient.setProvider and GtsClient.provider) then return end
  local current = GtsClient.provider()
  local c = OnlineWorld.client()
  local want = c and c.state == "in" and c:hasService("gts")
  if want and current == nil then
    GtsClient.setProvider(gtsProvider, "world")
  elseif not want and current == gtsProvider then
    GtsClient.setProvider(nil, nil)
  end
end

-- ------------------------------------------------------------ UI

-- WS4's LINK menu calls this for its WORLDS row
function OnlineWorld.openMenu(game)
  return require("src.ui.online.WorldMenu").open(game)
end

return OnlineWorld
