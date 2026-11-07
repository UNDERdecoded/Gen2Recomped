-- The hub's configuration: defaults, the operator's file, validation.
--
-- The file is Lua table syntax (comments allowed), read as DATA: it runs in
-- an empty environment, so it can't call functions, require modules or
-- touch files.  See hub_config.example.lua for every key.
--
--   local cfg, problems = Config.load(path)   -- nil, problems on a bad file
--   Config.defaults() -> a fresh default table

local Config = {}

local DEFAULTS = {
  name = "LINK HUB",
  bind = "*",                -- interface every socket binds ("127.0.0.1": this PC only)
  port = 7778,               -- TCP: the pokeserver protocol (short codes, tournaments)
  udpPort = nil,             -- UDP (ENet): rendezvous, ENet relay, GTS; default = port
  publicAddress = nil,       -- this hub's public IPv4, printed in the world code
  lanAddress = nil,          -- its LAN IPv4 (default: detected)
  dataDir = "hub-data",      -- relative to the config file's folder

  relay = {
    enabled = true,
    bytesPerSecond = 65536,  -- per pair, each direction combined
    burstBytes = 262144,
    queueBytes = 1048576,    -- a pair further behind than this is cut
    roomTtl = 1800,          -- seconds a hosted code waits for its guest
    maxRooms = 500,
    preQueue = 64,           -- messages a host may send before its guest arrives
  },
  rendezvous = {
    enabled = true,
    maxTickets = 2000,
    ticketTtl = 7200,
    ticketsPerIp = 8,
    introductionsPerTicket = 64,
  },
  tournaments = {
    enabled = true,
    max = 32,
    maxPlayers = 32,
    resultTimeout = 90,      -- seconds to wait for the second side's result
    lobbyTtl = 3600,         -- an unstarted tournament closes after this
  },
  gts = {
    enabled = false,
    name = nil,              -- shown in the GTS title (default: hub name)
    pools = {},              -- { dppt = { platinum = "<install>/data/generated", ... }, ... }
    dataMode = "lean",       -- "lean": species/moves/items only; "full": Data:load
    expireDays = 30,         -- deposits go back to their owner after this (0 = never)
    maxDeposits = 500,       -- per pool
  },
  world = {
    enabled = false,
    port = 7779,             -- its own UDP port
    name = "HUB WORLD",
    game = nil,              -- "platinum", "emerald", ...
    data = nil,              -- that game's <install>/data/generated
    cap = 16,                -- 2..16
    public = true,           -- unmodded games only, chat filter on
    filter = nil,            -- chat filter override (nil: on when public)
    gts = true,              -- members reach the hub GTS from inside the world
  },
  caps = {
    tcpConnections = 512,
    enetPeers = 256,
    perIp = 16,              -- connections from one address (TCP + UDP)
    messagesPerSecond = 30,  -- control messages per connection
    messageBurst = 120,
    idleSeconds = 60,        -- a connection that never says anything is dropped
  },
  admin = {
    key = "",                -- empty: admin commands off.  At least 12 characters.
    localOnly = true,        -- admin commands only from this machine
  },
  log = {
    level = "info",
    file = true,
    keepDays = 14,
    addresses = false,       -- full IPs in the log (default: last octet hidden)
  },
  statusSeconds = 30,        -- <dataDir>/status.json refresh
  test = {                   -- for the test harnesses only
    simulateBlockedPunch = false,
  },
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

function Config.defaults() return copy(DEFAULTS) end

-- keys whose default is "not set"
local OPTIONAL = { udpPort = true, publicAddress = true, lanAddress = true,
                   ["gts.name"] = true, ["world.game"] = true, ["world.data"] = true,
                   ["world.filter"] = true }

-- merge `over` into `base` key by key (tables recursively, except the pool
-- map, which the file replaces whole)
local function merge(base, over, path, problems)
  for k, v in pairs(over) do
    local here = path and (path .. "." .. tostring(k)) or tostring(k)
    local d = base[k]
    if here == "gts.pools" then
      if type(v) == "table" then base[k] = copy(v)
      else problems[#problems + 1] = "gts.pools: expected a table" end
    elseif type(d) == "table" and type(v) == "table" then
      merge(d, v, here, problems)
    elseif d == nil then
      if OPTIONAL[here] then
        base[k] = copy(v)
      else
        problems[#problems + 1] = ("%s: unknown key (ignored)"):format(here)
      end
    elseif type(d) ~= type(v) then
      problems[#problems + 1] = ("%s: expected %s, got %s (default kept)"):format(here, type(d), type(v))
    else
      base[k] = copy(v)
    end
  end
end

local function portOk(p) return type(p) == "number" and p % 1 == 0 and p >= 1 and p <= 65535 end

-- fatal problems make load() fail; warnings ride along
function Config.validate(cfg)
  local fatal, warn = {}, {}
  if not portOk(cfg.port) then fatal[#fatal + 1] = "port must be 1..65535" end
  cfg.udpPort = cfg.udpPort or cfg.port
  if not portOk(cfg.udpPort) then fatal[#fatal + 1] = "udpPort must be 1..65535" end
  if cfg.world.enabled then
    if not portOk(cfg.world.port) then fatal[#fatal + 1] = "world.port must be 1..65535" end
    if cfg.world.port == cfg.udpPort then fatal[#fatal + 1] = "world.port must differ from udpPort" end
    if type(cfg.world.game) ~= "string" or type(cfg.world.data) ~= "string" then
      fatal[#fatal + 1] = "world.game and world.data are needed when the world is on"
    end
    cfg.world.cap = math.max(2, math.min(16, math.floor(tonumber(cfg.world.cap) or 16)))
  end
  if cfg.gts.enabled then
    local n = 0
    for pool, games in pairs(cfg.gts.pools) do
      if type(games) ~= "table" then
        fatal[#fatal + 1] = ("gts.pools.%s must be { game = dataDir, ... }"):format(tostring(pool))
      else
        for game, dir in pairs(games) do
          if type(game) ~= "string" or type(dir) ~= "string" then
            fatal[#fatal + 1] = ("gts.pools.%s: entries are game = \"<dir>\""):format(tostring(pool))
          end
          n = n + 1
        end
      end
    end
    if n == 0 then fatal[#fatal + 1] = "gts is on but gts.pools names no game data (the hub refuses a GTS without data)" end
    if cfg.gts.dataMode ~= "lean" and cfg.gts.dataMode ~= "full" then
      fatal[#fatal + 1] = "gts.dataMode is \"lean\" or \"full\""
    end
  end
  local key = cfg.admin.key
  if type(key) ~= "string" then key = "" cfg.admin.key = "" end
  if key ~= "" and #key < 12 then
    fatal[#fatal + 1] = "admin.key must be at least 12 characters (or empty to turn admin off)"
  end
  if key == "change-me-please" then
    fatal[#fatal + 1] = "admin.key is still the example value; pick your own"
  end
  if cfg.publicAddress ~= nil and type(cfg.publicAddress) ~= "string" then
    fatal[#fatal + 1] = "publicAddress is a string"
  end
  if not (cfg.relay.enabled or cfg.rendezvous.enabled or cfg.tournaments.enabled
          or cfg.gts.enabled or cfg.world.enabled) then
    warn[#warn + 1] = "every service is off; the hub will do nothing"
  end
  return fatal, warn
end

-- the file as data: an empty environment, no functions
function Config.parse(text, name)
  local chunk, err = loadstring(text, "=" .. (name or "config"))
  if not chunk then return nil, err end
  local env = {}
  setfenv(chunk, env)
  local ok, result = pcall(chunk)
  if not ok then return nil, result end
  if type(result) ~= "table" then
    -- `key = value` lines without a `return { ... }` land in the env
    result = env
  end
  return result
end

-- cfg | nil, problems ; cfg.warnings holds the non-fatal ones
function Config.load(path, overrides)
  local cfg = Config.defaults()
  local problems = {}
  local base = "."
  if path then
    local f = io.open(path, "rb")
    if not f then return nil, { "can't open config file " .. tostring(path) } end
    local text = f:read("*a")
    f:close()
    local t, err = Config.parse(text, path)
    if not t then return nil, { "config file: " .. tostring(err) } end
    merge(cfg, t, nil, problems)
    base = (tostring(path):gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
  end
  if overrides then merge(cfg, overrides, nil, problems) end
  local Files = require("src.online.hub.Files")
  if not path then
    -- no config file: never drop runtime data into whatever folder the hub
    -- was started from (it may be the game's source tree)
    local home = os.getenv("POKEPORT_HUB_HOME") or os.getenv("APPDATA") or os.getenv("HOME")
    base = home and (Files.clean(home) .. "/pokeport-link-hub") or "."
  end
  cfg.dataDir = Files.join(base, cfg.dataDir)
  local fatal, warn = Config.validate(cfg)
  for _, p in ipairs(warn) do problems[#problems + 1] = p end
  if #fatal > 0 then
    for _, p in ipairs(problems) do fatal[#fatal + 1] = p end
    return nil, fatal
  end
  cfg.warnings = problems
  return cfg
end

return Config
