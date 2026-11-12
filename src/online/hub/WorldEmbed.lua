-- The hub's always-on world: WS8's WorldHost with no local player, on its
-- own UDP port (world.port), so its admission rules never see the hub's
-- other traffic.
--
--   WorldHost.new{ transport = t, connector = false, ... }   (WS8's test seam)
--
-- The world keeps one identity across restarts (<dataDir>/world/identity.json:
-- the world id and the session nonce), so the code the operator posts stays
-- valid.  Members are the usual WS8 clients: WORLDS -> JOIN A WORLD with the
-- code printed at start and written to <dataDir>/world_code.txt.  With the
-- hub GTS on and world.gts true, the world offers it as its "gts" service
-- (same database as the hub port's GTS).

local Transport = require("src.online.net.Transport")
local Util = require("src.online.net.Util")
local WorldHost = require("src.online.world.WorldHost")
local WorldStore = require("src.online.world.WorldStore")
local MapSet = require("src.online.world.MapSet")
local Handshake = require("src.link.Handshake")
local InviteCode = require("src.online.InviteCode")
local GameData = require("src.online.hub.GameData")
local Files = require("src.online.hub.Files")

local WorldEmbed = {}
WorldEmbed.__index = WorldEmbed

-- the hello a member's game compares itself with: built from the world
-- game's data the way OnlineWorld.helloFor builds a player's
function WorldEmbed.hello(data, game, name)
  GameData.use(game)
  local fake = { data = data, save = { player = { name = name }, party = {} } }
  local h = Handshake.hello(fake, nil, { mapSet = MapSet.of(data) })
  h.features = h.features or {}
  local has = false
  for _, f in ipairs(h.features) do if f == "world" then has = true end end
  if not has then h.features[#h.features + 1] = "world" end
  return h
end

function WorldEmbed.new(opts)
  local cfg, log = opts.cfg, opts.log
  local game = cfg.game
  local data, why = opts.data, nil
  if not data then data, why = GameData.load(cfg.data, game, "full") end
  if not data then return nil, "world: " .. tostring(why) end
  if not MapSet.of(data) then return nil, "world: the game data has no maps" end
  local dir = opts.dataDir .. "/world"
  Files.mkdirs(dir)
  local idPath = dir .. "/identity.json"
  local ident = Files.readJson(idPath)
  if not (ident and type(ident.id) == "string" and tonumber(ident.nonce)) then
    ident = { id = ("hub%08x"):format(Util.rand32() % 4294967296), nonce = Util.newNonce(),
              created = os.time() }
    local ok, err = Files.writeJson(idPath, ident)
    if not ok then return nil, "world: can't write " .. idPath .. ": " .. tostring(err) end
  end
  local store = WorldStore.new({ fs = Files.worldFs(dir), root = "worlds" })
  local world = store:open(ident.id)
  if world then
    world.name = cfg.name or world.name
    world.cap = cfg.cap
    world.public = cfg.public and true or false
    if cfg.filter ~= nil then world.filter = cfg.filter and true or false end
    store:saveWorld(world)
  else
    world = store:create({ id = ident.id, name = cfg.name, cap = cfg.cap, public = cfg.public,
                           filter = cfg.filter })
  end
  -- the store keeps a player-hosted world's 16; a server hub may hold up to
  -- WorldProtocol.SERVER_MAX_CAP (config world.cap)
  local WP = require("src.online.world.WorldProtocol")
  world.cap = WP.clampCap(cfg.cap, WP.SERVER_MAX_CAP)
  local t = opts.transport
  if not t then
    t = Transport.new({ port = cfg.port, bind = opts.bind, maxPeers = world.cap,
                        nonce = tonumber(ident.nonce) })
    local ok, err = t:listen()
    if not ok then return nil, ("world: can't open UDP %d: %s"):format(cfg.port, tostring(err)) end
  end
  local hello = WorldEmbed.hello(data, game, world.name)
  GameData.use(game)
  local host = WorldHost.new({ world = world, store = store, hello = hello, data = data,
                               transport = t, connector = false, ownsTransport = true,
                               serverCap = true })
  local self = setmetatable({ host = host, transport = t, data = data, game = game, log = log,
                              world = world, nonce = tonumber(ident.nonce), cfg = cfg,
                              dataDir = opts.dataDir }, WorldEmbed)
  -- the 4-player multi's relay, as every world a game hosts has it
  local okM, MultiNet = pcall(require, "src.online.MultiNet")
  if okM then host:registerService("multi", MultiNet.relayService()) end
  -- RUN MODES: Soul Link partners can pair through the hub's world too
  local okS, SoulLinkService = pcall(require, "src.online.SoulLinkService")
  if okS then host:registerService(SoulLinkService.NAME, SoulLinkService.new()) end
  if cfg.gts and opts.gts then
    host:registerService("gts", opts.gts:worldService())
    log:info("world: the hub GTS is open to members")
  end
  self.code = self:inviteCode(opts.publicAddress, opts.lanAddress)
  if self.code then
    Files.writeAtomic(opts.dataDir .. "/world_code.txt", self.code .. "\n")
  end
  log:info("world: %q (%s, cap %d, %s) on UDP %d, code %s", world.name, game, world.cap,
           world.public and "public" or "private", t.boundPort or cfg.port, tostring(self.code))
  return self
end

-- a WS2 world code: the hub's public and LAN addresses, the world port and
-- its nonce (InviteCode kind "world")
function WorldEmbed:inviteCode(public, lan)
  local spec = { kind = "world", port = self.transport.boundPort or self.cfg.port, nonce = self.nonce }
  if Util.isIPv4(public) then spec.public = public end
  lan = lan or Util.lanIP()
  if Util.isIPv4(lan) then spec.lan = lan end
  if not spec.public and not spec.lan then return nil end
  local ok, display = pcall(InviteCode.encode, spec)
  if ok then return display end
  return nil
end

function WorldEmbed:update()
  GameData.use(self.game)
  self.host:update()
  -- nobody plays at the hub: what WorldHost tells its own (absent) player
  -- is thrown away
  self.host:localClientNet():poll()
  for _, ev in ipairs(self.host:drainEvents()) do
    if ev.kind == "join" then
      self.log:info("world: %s joined (%d/%d)", tostring(ev.name), self.host:count(), self.world.cap)
    elseif ev.kind == "left" then
      self.log:info("world: %s left (%s)", tostring(ev.name), tostring(ev.reason))
    elseif ev.kind == "refused" then
      self.log:info("world: refused %s (%s)", tostring(ev.name), tostring(ev.reason))
    elseif ev.kind == "kick" then
      self.log:info("world: kicked %s%s", tostring(ev.name), ev.ban and " (banned)" or "")
    elseif ev.kind == "session" then
      self.log:info("world: %s session %s <-> %s", tostring(ev.mode), tostring(ev.a), tostring(ev.b))
    elseif ev.kind == "cheat" then
      self.log:warn("world: stopped %s's session: %s", tostring(ev.name), tostring(ev.reason))
    end
  end
end

function WorldEmbed:snapshot()
  return { name = self.world.name, game = self.game, members = self.host:count(),
           cap = self.world.cap, code = self.code, roster = self.host:roster() }
end

function WorldEmbed:close()
  self.host:close("the hub is shutting down")
end

return WorldEmbed
