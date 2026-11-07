-- The hub's GTS: WS7's GtsService behind its GtsHost, over GtsStore files in
-- <dataDir>/gts, validating against the operator's own game data
-- (requireData: a pool with no data refuses every deposit).
--
-- One GtsService serves every configured pool (dppt, bw, and the port pools
-- rby, gsc, rse, ...).  Clients reach it two ways, sharing one database:
--   * straight over the hub's UDP port: any gts_* message from a connection
--     (embed:receive / embed:closed), the shape GtsClient sends;
--   * from inside the hub's world, as its "gts" service (embed:worldService).
--
-- Config (gts):  pools = { dppt = { platinum = "<install>/data/generated",
--                                   heartgold = "..." }, bw = { black = "..." } },
--                dataMode, expireDays, maxDeposits, name

local GtsService = require("src.online.gts.GtsService")
local GtsHost = require("src.online.gts.GtsHost")
local GtsStore = require("src.online.gts.GtsStore")
local GtsPools = require("src.online.gts.GtsPools")
local GameData = require("src.online.hub.GameData")

local GtsEmbed = {}
GtsEmbed.__index = GtsEmbed

function GtsEmbed.new(opts)
  local cfg, log = opts.cfg, opts.log
  local datasets, gameOf, pools = {}, {}, {}
  for pool, games in pairs(cfg.pools) do
    if not GtsPools.POOLS[pool] then
      return nil, ("gts.pools.%s: no such pool (pools: dppt, bw, rby, gsc, rse, prism, polishedcrystal)")
        :format(tostring(pool))
    end
    local loaded = 0
    for game, dir in pairs(games) do
      if GtsPools.poolFor(game) ~= pool then
        return nil, ("gts.pools.%s: %s trades in pool %s, not %s"):format(pool, game,
          tostring(GtsPools.poolFor(game)), pool)
      end
      local data = opts.datasets and opts.datasets[game]
      local why
      if not data then data, why = GameData.load(dir, game, cfg.dataMode) end
      if not data then return nil, ("gts: %s data: %s"):format(game, tostring(why)) end
      datasets[game] = data
      gameOf[data] = game
      loaded = loaded + 1
      log:info("gts: %s data loaded from %s (%s)", game, dir, cfg.dataMode)
    end
    if loaded > 0 then pools[#pools + 1] = pool end
  end
  table.sort(pools)
  if #pools == 0 then return nil, "gts: no pool has game data" end
  local dir = opts.dataDir .. "/gts"
  local svc = GtsService.new({
    store = opts.store or GtsStore.new(GtsStore.dirFs(dir)),
    pools = pools,
    datasets = datasets,
    requireData = true,
    name = cfg.name or opts.hubName or "LINK HUB",
    expireSeconds = (cfg.expireDays or 0) > 0 and cfg.expireDays * 86400 or nil,
    maxDeposits = cfg.maxDeposits,
    now = opts.now and function() return math.floor(opts.now()) end or nil,
    clock = opts.clock,
    log = function(line) log:info("%s", tostring(line)) end,
  })
  -- validation reads GameVersion: point it at the dataset that will be used
  local baseValidate = GtsService.validate
  function svc:validate(packed, ctx)
    local data = self:_dataFor(ctx.game, ctx.pool)
    if data and gameOf[data] then GameData.use(gameOf[data]) end
    return baseValidate(self, packed, ctx)
  end
  local self = setmetatable({ svc = svc, host = GtsHost.new(svc), log = log, pools = pools,
                              datasets = datasets, attached = {}, lastTick = 0,
                              now = opts.now or os.time }, GtsEmbed)
  for _, pool in ipairs(pools) do
    svc:db(pool)
    local c = svc:counts(pool)
    log:info("gts: pool %s open (%d deposits, %d mail) in %s", pool, c.deposits, c.mail, dir)
  end
  return self
end

local function key(conn) return "c" .. tostring(conn.id) end

-- a gts_* message from a hub connection
function GtsEmbed:receive(conn, msg)
  local k = key(conn)
  if not self.attached[k] then
    self.attached[k] = conn
    self.host:attach(k, function(m, channel) conn:send(m, channel) end)
    conn.role = conn.role or "gts"
  end
  self.host:receive(k, msg)
end

function GtsEmbed:closed(conn)
  local k = key(conn)
  if self.attached[k] then
    self.attached[k] = nil
    self.host:detach(k)
  end
end

-- the "gts" service of the hub's world (WorldHost:registerService)
function GtsEmbed:worldService()
  local host = self.host
  return {
    open = function(channel, member)
      host:serveChannel(channel, "w" .. tostring(member.id or member.pid))
    end,
    update = function() host:update() end,
  }
end

function GtsEmbed:update()
  self.host:update()
  local now = self.now()
  if now - self.lastTick >= 60 then
    self.lastTick = now
    pcall(self.svc.tick, self.svc)
  end
end

function GtsEmbed:snapshot()
  local out = {}
  for _, pool in ipairs(self.pools) do
    local c = self.svc:counts(pool)
    out[pool] = { deposits = c.deposits, mail = c.mail }
  end
  return out
end

return GtsEmbed
