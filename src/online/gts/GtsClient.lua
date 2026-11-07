-- The GTS client (docs/online-design.md 2.7a, WS7): the protocol half that
-- talks to a GtsService over any Net-API channel, and the entry point every
-- game's GTS counter opens.
--
-- ENTRY POINT (WS6b's Global Terminal hooks, the LINK menu, a world menu):
--
--   GtsClient.open(game, {
--     channel = netLike,        -- a connected channel to a GTS host; or
--     connect = fn() -> netLike,-- made on open; or neither: the provider
--     style = "game"|"neutral", width = , height = ,
--     noConnectText = "...",    -- the cartridge's own "could not connect"
--     onDone = fn(result)       -- "done" | "noconnect" | "denied" | "closed"
--   }) -> screen
--
--   GtsClient.setProvider(fn(game) -> netLike | nil, label)
--     WS8 (the world the player is in) / WS9 (the configured hub) register
--     here; open() with no channel asks the provider.
--
-- PROTOCOL OBJECT (headless; the screen drives one):
--
--   local c = GtsClient.new{ channel =, data =, save =, persist = fn(save),
--                            player =, name =, game = "platinum", tid =,
--                            nationalDex =, onEvent = fn(ev), gameRef = game }
--   c:update(dt)                 pump; sends the hello once the channel pairs
--   c.state                      "connecting"|"hello"|"ready"|"denied"|"closed"
--   c.status                     { deposit = view|nil, mail = { ... } }
--   c:deposit(source, want, cb)  source { where="party", index=i }
--   c:search(query, cb)          query { dex, gender, band, page }
--   c:offer(depositView, source, cb)
--   c:withdraw(cb) ; c:refresh(cb)
--   cb(ok, reply)
--
-- On welcome the client RESUMES: it resends every outbox entry it holds for
-- this host (GtsLedger) and claims every waiting mail item, so a result
-- that landed while the player was away arrives on their next connect.
--
-- Events (onEvent): { type = "received", mon, kind, from, mailId, evolveTo, evolveRow }
--                   { type = "returned", token, where }   (a refused mon came home)
--                   { type = "welcome" } { type = "denied", text } { type = "closed", text }
--                   { type = "mail_error", mailId, text }

local GtsLedger = require("src.online.gts.GtsLedger")
local GtsRules = require("src.online.gts.GtsRules")
local GtsPools = require("src.online.gts.GtsPools")

local GtsClient = {}
GtsClient.__index = GtsClient

GtsClient.REQUEST_TIMEOUT = 30
GtsClient.HELLO_TIMEOUT = 15
GtsClient.CLAIM_RETRY = 1.0

-- ------------------------------------------------------------ identity

-- The player id: the Handshake identity when the world stream's Identity
-- module is present (WS8), else this install's own random id, kept in the
-- save directory.  Only a hash of the secret ever leaves the machine.
local cachedIdentity

local function hashHex(s)
  if love and love.data and love.data.hash then
    local ok, d = pcall(love.data.hash, "sha256", s)
    if ok and d then
      return (d:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
    end
  end
  -- FNV-1a over 4 seeds: a stand-in outside LOVE (tests)
  local out = {}
  for seed = 1, 4 do
    local h = 2166136261 + seed
    for i = 1, #s do
      h = (h * 16777619 + s:byte(i) * (seed + 1)) % 4294967296
    end
    out[#out + 1] = ("%08x"):format(h)
  end
  return table.concat(out)
end
GtsClient.hashHex = hashHex

function GtsClient.identity(opts)
  if opts and opts.player then return opts.player end
  local ok, Identity = pcall(require, "src.online.world.Identity")
  if ok and type(Identity) == "table" then
    for _, fn in ipairs({ "playerId", "hash", "id" }) do
      if type(Identity[fn]) == "function" then
        local okC, v = pcall(Identity[fn])
        if okC and type(v) == "string" and #v >= 4 then return v end
      end
    end
  end
  if cachedIdentity then return cachedIdentity end
  local secret
  local fs = love and love.filesystem
  local path = "online/gts_identity.txt"
  if fs and fs.read then
    local okR, s = pcall(fs.read, path)
    if okR and type(s) == "string" and s:match("^%x+$") and #s >= 32 then secret = s end
  end
  if not secret then
    secret = GtsLedger.newToken() .. GtsLedger.newToken()
    if fs and fs.write then
      pcall(fs.createDirectory, "online")
      pcall(fs.write, path, secret)
    end
  end
  cachedIdentity = "g" .. hashHex(secret):sub(1, 32)
  return cachedIdentity
end

-- ------------------------------------------------------------ provider

local provider, providerLabel

function GtsClient.setProvider(fn, label)
  provider, providerLabel = fn, label
end

function GtsClient.provider() return provider, providerLabel end

-- ------------------------------------------------------------ the client

function GtsClient.new(opts)
  local save = assert(opts.save, "GtsClient needs a save")
  local self = setmetatable({
    channel = opts.channel,
    data = assert(opts.data, "GtsClient needs data"),
    save = save,
    gameRef = opts.gameRef,
    ledger = GtsLedger.new{ save = save, data = opts.data, persist = opts.persist, now = opts.now },
    player = opts.player,
    name = opts.name,
    game = opts.game,
    tid = opts.tid,
    nationalDex = opts.nationalDex,
    onEvent = opts.onEvent,
    state = "connecting",
    pending = {},       -- rid -> { cb, at, type }
    nextRid = 1,
    clock = 0,
    claiming = {},      -- mailId -> true while a claim is out
    retry = {},         -- mailId -> clock time to claim again
    log = opts.log,
  }, GtsClient)
  return self
end

-- a client for the running game: save, data, identity and version from it
function GtsClient.forGame(game, opts)
  opts = opts or {}
  local GameVersion = require("src.core.GameVersion")
  local CompatRules = require("src.online.CompatRules")
  local save = game.save
  local player = save and save.player or {}
  return GtsClient.new{
    channel = opts.channel, data = game.data, save = save, gameRef = game,
    persist = opts.persist or function()
      if game.writeSave then return game:writeSave() end
      return true
    end,
    player = GtsClient.identity(opts),
    name = player.name,
    game = opts.game or GameVersion.get(),
    tid = tonumber(player.id) or tonumber(player.trainerId) or 0,
    nationalDex = CompatRules.hasNationalDex(save),
    onEvent = opts.onEvent, log = opts.log,
  }
end

function GtsClient:_emit(ev)
  if self.onEvent then self.onEvent(ev) end
end

function GtsClient:_send(msg)
  if not self.channel or self.channel.closed then return false end
  self.channel:send(msg, 0)
  return true
end

function GtsClient:request(msg, cb)
  local rid = self.nextRid
  self.nextRid = rid + 1
  msg.rid = rid
  self.pending[rid] = { cb = cb, at = self.clock, type = msg.type }
  if not self:_send(msg) then
    self.pending[rid] = nil
    if cb then cb(false, { type = "gts_refused", code = "closed", text = "Not connected." }) end
    return nil
  end
  return rid
end

function GtsClient:hello()
  self.state = "hello"
  self.helloAt = self.clock
  self:_send({ type = "gts_hello", player = self.player, name = self.name,
               game = self.game, tid = self.tid, nationalDex = self.nationalDex == true })
end

function GtsClient:ready() return self.state == "ready" end

function GtsClient:update(dt)
  dt = dt or 0
  self.clock = self.clock + dt
  local ch = self.channel
  if not ch then return end
  if self.state == "closed" or self.state == "denied" then return end
  if ch.update then ch:update() end
  if self.state == "connecting" and ch.paired then self:hello() end
  for _, msg in ipairs(ch:poll()) do self:_handle(msg) end
  if ch.closed and self.state ~= "closed" then
    self.state = "closed"
    local text = ch.error or "The connection was lost."
    for rid, p in pairs(self.pending) do
      self.pending[rid] = nil
      if p.cb then p.cb(false, { type = "gts_refused", code = "closed", text = text }) end
    end
    self:_emit({ type = "closed", text = text })
    return
  end
  if self.state == "hello" and self.clock - (self.helloAt or 0) > GtsClient.HELLO_TIMEOUT then
    self.state = "closed"
    self:_emit({ type = "closed", text = "The GTS did not answer." })
  end
  if self.state == "ready" then
    for id, at in pairs(self.retry) do
      if self.clock >= at then
        self.retry[id] = nil
        self:claim(id)
      end
    end
  end
  for rid, p in pairs(self.pending) do
    if self.clock - p.at > GtsClient.REQUEST_TIMEOUT then
      self.pending[rid] = nil
      if p.cb then p.cb(false, { type = "gts_refused", code = "timeout", text = "The GTS did not answer." }) end
    end
  end
end

-- ------------------------------------------------------------ inbound

local SETTLE = { gts_deposited = true, gts_offered = true, gts_withdrawn = true }
-- refusals after which the host certainly did nothing with the mon
local ROLLBACK = { already = true, full = true, invalid = true, gone = true, own = true,
                   nomatch = true, compat = true, storage = true, bad = true, egg = true,
                   slow = true }

function GtsClient:_handle(msg)
  local t = msg.type
  if t == "gts_welcome" then
    self.state = "ready"
    self.welcome = msg
    self.pool = msg.pool
    self.status = msg.status
    self:_emit({ type = "welcome" })
    self:_resume()
  elseif t == "gts_denied" then
    self.state = "denied"
    self.deniedText = msg.text
    self:_emit({ type = "denied", text = msg.text, code = msg.code })
    return
  end
  if t == "gts_status" and msg.status then
    self.status = msg.status
    -- a push (a trade done while we are here) or a refresh: take what waits
    if msg.rid == nil then
      for _, item in ipairs(msg.status.mail or {}) do self:claim(item.id) end
    end
  end

  -- settle the ledger first, whoever asked (a resumed request has no cb)
  if SETTLE[t] and msg.token then
    self.ledger:finish(msg.token)
    if msg.mailId then self:claim(msg.mailId) end
  elseif t == "gts_refused" and msg.token
         and (msg.request == "gts_deposit" or msg.request == "gts_offer")
         and ROLLBACK[msg.code] then
    local ok, where = self.ledger:rollback(msg.token)
    if ok then self:_emit({ type = "returned", token = msg.token, where = where, text = msg.text }) end
  elseif t == "gts_mail" then
    self:_receive(msg)
  elseif t == "gts_acked" or t == "gts_mail_gone" then
    if msg.mailId then
      self.claiming[msg.mailId] = nil
      self.ledger:forget(msg.mailId)
      self:_dropMail(msg.mailId)
    end
  elseif t == "gts_refused" and msg.mailId then
    -- another session of this player holds it: try again shortly (its
    -- lease ends when that session acks or goes away)
    self.claiming[msg.mailId] = nil
    if msg.code == "busy" or msg.code == "slow" then
      self.retry[msg.mailId] = self.clock + GtsClient.CLAIM_RETRY
    end
  end

  if msg.rid ~= nil then
    local p = self.pending[msg.rid]
    if p then
      self.pending[msg.rid] = nil
      if p.cb then p.cb(t ~= "gts_refused" and t ~= "gts_denied", msg) end
    end
  end
end

function GtsClient:_dropMail(id)
  local st = self.status
  if not (st and st.mail) then return end
  for i = #st.mail, 1, -1 do
    if st.mail[i].id == id then table.remove(st.mail, i) end
  end
end

-- everything this save still owes or is owed by this host
function GtsClient:_resume()
  for _, e in ipairs(self.ledger:pending()) do
    if e.dbId == self:hostKey() then
      if e.kind == "deposit" then
        self:_send({ type = "gts_deposit", token = e.token, mon = e.packed, want = e.want })
      elseif e.kind == "offer" then
        self:_send({ type = "gts_offer", token = e.token, id = e.depositId, mon = e.packed })
      end
    end
  end
  for _, item in ipairs((self.status and self.status.mail) or {}) do
    self:claim(item.id)
  end
end

-- the id the ledger files this host's entries under: the pool database's
-- id (stable across restarts of the same world or hub)
function GtsClient:hostKey()
  local w = self.welcome
  return w and w.dbId or nil
end

function GtsClient:claim(mailId)
  if self.claiming[mailId] then return end
  self.claiming[mailId] = true
  self:_send({ type = "gts_claim", mailId = mailId })
end

function GtsClient:_receive(msg)
  local id = msg.mailId
  if self.ledger:hasApplied(id) then
    self:_send({ type = "gts_ack", mailId = id })
    return
  end
  -- the receiver's own check: rebuilt from this game's data, and the
  -- cartridge's per-game gates from the other end
  local MonCodec = require("src.online.MonCodec")
  local CompatRules = require("src.online.CompatRules")
  local myHello = { gen = MonCodec.genOf(self.data), game = self.game,
                    family = CompatRules.familyOf(self.game), nationalDex = self.nationalDex }
  if type(msg.fromHello) == "table" then
    local okR, whyR = CompatRules.canReceive(msg.mon, myHello, msg.fromHello)
    if not okR then
      self.claiming[id] = nil
      self:_emit({ type = "mail_error", mailId = id, text = whyR })
      return
    end
  end
  local mon, why = MonCodec.unpack(self.data, msg.mon, { strict = true })
  if not mon then
    self.claiming[id] = nil
    self:_emit({ type = "mail_error", mailId = id, text = why })
    return
  end
  if msg.kind ~= "returned" then mon.traded = true end
  pcall(function()
    require("src.mods.Runtime").emit("pokemon.received", { mon = mon, from = "gts", peerName = msg.from })
  end)
  local where, whyA = self.ledger:apply(id, mon)
  if not where then
    self.claiming[id] = nil
    self:_emit({ type = "mail_error", mailId = id, text = whyA })
    return
  end
  local evolveTo, evolveRow
  if msg.kind ~= "returned" and self.gameRef then
    local ok, a, b = pcall(function()
      return require("src.pokemon.Evolution").pendingFor(self.gameRef, mon, { kind = "trade" })
    end)
    if ok then evolveTo, evolveRow = a, b end
  end
  self:_send({ type = "gts_ack", mailId = id })
  self:_emit({ type = "received", mon = mon, kind = msg.kind, from = msg.from, mailId = id,
               where = where, sentInfo = msg.sentInfo, reason = msg.reason,
               evolveTo = evolveTo, evolveRow = evolveRow })
end

-- ------------------------------------------------------------ operations

local function fail(cb, text, code)
  if cb then cb(false, { type = "gts_refused", code = code or "local", text = text }) end
  return nil, text
end

function GtsClient:poolInfo()
  return self.pool and GtsPools.get(self.pool) or nil
end

-- can this save ask for / seek `dex`? (the cartridge: species you've seen)
function GtsClient:canSeek(dex)
  return GtsRules.hasSeen(self.save, self.data, dex)
end

function GtsClient:depositBlocker(source)
  local mon = self.ledger:monAt(source)
  return GtsRules.depositBlocker(self.save, self.data, mon,
                                 source and source.where == "party" and source.index or nil)
end

function GtsClient:deposit(source, want, cb)
  if not self:ready() then return fail(cb, "Not connected.") end
  if self.status and self.status.deposit then
    return fail(cb, "You already have a POKéMON deposited.")
  end
  if #self.ledger:pending(self:hostKey()) > 0 then return fail(cb, "Please wait...") end
  local why = self:depositBlocker(source)
  if why then return fail(cb, why) end
  local pool = self:poolInfo()
  local okW, whyW = GtsRules.checkWant(want, pool and pool.maxDex)
  if not okW then return fail(cb, whyW) end
  if not self:canSeek(want.dex) then return fail(cb, "You haven't seen that POKéMON.") end
  local MonCodec = require("src.online.MonCodec")
  local mon = self.ledger:monAt(source)
  local packed = MonCodec.pack(self.data, mon)
  want = GtsRules.normalizeWant(want)
  local token, whyT = self.ledger:take(source, "deposit",
    { packed = packed, want = want, dbId = self:hostKey() })
  if not token then return fail(cb, whyT) end
  return self:request({ type = "gts_deposit", token = token, mon = packed, want = want },
    function(ok, reply)
      if ok then
        self.status = self.status or { mail = {} }
        self.status.deposit = { id = reply.id, info = reply.info, want = want }
      end
      if cb then cb(ok, reply) end
    end)
end

function GtsClient:search(query, cb)
  if not self:ready() then return fail(cb, "Not connected.") end
  if not self:canSeek(query.dex) then return fail(cb, "You haven't seen that POKéMON.") end
  return self:request({ type = "gts_search", dex = query.dex, gender = query.gender or "any",
                        band = query.band or 0, page = query.page or 0 }, cb)
end

-- does the mon at `source` meet this deposit's wants?  true | false, why
function GtsClient:offerBlocker(dep, source)
  local mon = self.ledger:monAt(source)
  local why = GtsRules.depositBlocker(self.save, self.data, mon,
                                      source and source.where == "party" and source.index or nil)
  if why then return why end
  if not GtsRules.matches(GtsRules.infoOf(self.data, mon), dep.want) then
    return "That POKéMON doesn't meet the request."
  end
  return nil
end

function GtsClient:offer(dep, source, cb)
  if not self:ready() then return fail(cb, "Not connected.") end
  if #self.ledger:pending(self:hostKey()) > 0 then return fail(cb, "Please wait...") end
  if not self.ledger:hasRoom() then return fail(cb, "There's no room for another POKéMON.") end
  local why = self:offerBlocker(dep, source)
  if why then return fail(cb, why) end
  local MonCodec = require("src.online.MonCodec")
  local packed = MonCodec.pack(self.data, self.ledger:monAt(source))
  local token, whyT = self.ledger:take(source, "offer",
    { packed = packed, depositId = dep.id, dbId = self:hostKey() })
  if not token then return fail(cb, whyT) end
  return self:request({ type = "gts_offer", token = token, id = dep.id, mon = packed }, cb)
end

function GtsClient:withdraw(cb)
  if not self:ready() then return fail(cb, "Not connected.") end
  local dep = self.status and self.status.deposit
  if not dep then return fail(cb, "Nothing is deposited.") end
  if not self.ledger:hasRoom() then return fail(cb, "There's no room for it.") end
  return self:request({ type = "gts_withdraw", token = GtsLedger.newToken(), id = dep.id },
    function(ok, reply)
      if ok and self.status then self.status.deposit = nil end
      if cb then cb(ok, reply) end
    end)
end

function GtsClient:refresh(cb)
  if not self:ready() then return fail(cb, "Not connected.") end
  return self:request({ type = "gts_status" }, cb)
end

-- requests still out (the screen shows "Please wait...")
function GtsClient:busy()
  if next(self.pending) ~= nil then return true end
  if next(self.claiming) ~= nil then return true end
  if next(self.retry) ~= nil then return true end
  return false
end

function GtsClient:close()
  if self.channel and not self.channel.closed and self.channel.close then self.channel:close() end
  self.state = "closed"
end

-- ------------------------------------------------------------ open

-- the screen, on top of `game.stack` (see the header)
function GtsClient.open(game, opts)
  opts = opts or {}
  local GtsScreen = require("src.ui.online.GtsScreen")
  local channel = opts.channel
  if not channel and opts.connect then
    local ok, ch = pcall(opts.connect)
    if ok then channel = ch end
  end
  if not channel and provider then
    local ok, ch = pcall(provider, game)
    if ok then channel = ch end
  end
  return GtsScreen.open(game, opts, channel)
end

return GtsClient
