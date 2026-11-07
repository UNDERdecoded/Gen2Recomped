-- The GTS service (docs/online-design.md 2.7a, workstream WS7).
--
-- A PURE service: no sockets, no love, no screen.  A host -- a player's
-- world (WS8) or the Link Hub (WS9) -- feeds it messages from its sessions
-- and sends back what it returns.  GtsHost.lua does that wiring for a
-- Transport or for Net-API channels.
--
--   local svc = GtsService.new{
--     store = GtsStore.new(GtsStore.loveFs("online/worlds/<id>/gts")),
--     pools = { "dppt" },            -- served pools (nil: every pool)
--     datasets = { platinum = Data },-- game id -> merged data, for validation
--     name = "RED'S WORLD",
--   }
--   svc:connect(key)                  -- a session opened
--   local replies = svc:handle(key, msg) -- -> { {msg=, channel=}, ... }
--   svc:disconnect(key)
--   svc:tick()                        -- expiry (call now and then)
--
-- ESCROW.  A deposited mon lives ONLY in the host's database: the client
-- takes it out of its save and writes the save BEFORE sending (GtsLedger),
-- and the host writes its database (GtsStore: .part + rename) BEFORE it
-- answers.  Every change of ownership is one database commit:
--
--   deposit   mon -> deposits[id]
--   offer     deposits[id] removed; the deposited mon -> the offerer's mail,
--             the offered mon -> the depositor's mail        (one commit)
--   withdraw  deposits[id] removed; mon -> the owner's mail
--   expire    as withdraw, kind "returned"
--   ack       mail item removed (the client has written it into its save)
--
-- Mail is how every mon leaves the host, and an item is only removed when
-- the client acknowledges it, AFTER it saved.  A claim leases the item to
-- one session, so two sessions of one player cannot both take it.  Every
-- mutating request carries a client token; the host remembers the answer
-- per owner, so a request resent after a crash or a lost reply gets the
-- same answer instead of a second effect.  Results waiting in mail are
-- listed in the welcome, so a player gets them on their next connect.
--
-- MESSAGES (client -> host; every request may carry `rid`, echoed back):
--   gts_hello   { player, name, game, tid, nationalDex }
--               -> gts_welcome { pool, label, port, host, status }
--                | gts_denied { code = "pool"|"hello", text }
--   gts_status  {}                          -> gts_status { status }
--   gts_deposit { token, mon, want }        -> gts_deposited { token, id }
--   gts_search  { dex, gender, band, page } -> gts_results { items, more }
--   gts_offer   { token, id, mon }          -> gts_offered { token, id, mailId }
--   gts_withdraw{ token, id }               -> gts_withdrawn { token, id, mailId }
--   gts_claim   { mailId }                  -> gts_mail { mailId, kind, mon, ... }
--   gts_ack     { mailId }                  -> gts_acked { mailId }
--   any failure                             -> gts_refused { code, text, token? }
--
-- `mon` is a MonCodec v3 packet; `want`/queries are { dex, gender, band }
-- (GtsRules).  Owners are "<player>|<game>|<tid>": the player id is the
-- Handshake identity, and one install's Platinum and HeartGold saves are
-- different owners.

local GtsPools = require("src.online.gts.GtsPools")
local GtsRules = require("src.online.gts.GtsRules")
local CompatRules = require("src.online.CompatRules")

local GtsService = {}
GtsService.__index = GtsService

GtsService.VERSION = 1
GtsService.SEARCH_LIMIT = 7          -- the cartridge shows seven
GtsService.MAX_DEPOSITS = 500        -- per pool
GtsService.TOKENS_KEPT = 64          -- remembered answers per owner
GtsService.RATE_BURST = 20           -- requests a session may send at once
GtsService.RATE_PER_SECOND = 4       -- and its refill rate
GtsService.LEASE_SECONDS = 8         -- a claim not acknowledged by then may be
                                     -- taken over (its session died silently)

GtsService.TYPES = {}
for _, t in ipairs({
  "gts_hello", "gts_welcome", "gts_denied", "gts_status", "gts_deposit",
  "gts_deposited", "gts_search", "gts_results", "gts_offer", "gts_offered",
  "gts_withdraw", "gts_withdrawn", "gts_claim", "gts_mail", "gts_mail_gone",
  "gts_ack", "gts_acked", "gts_refused",
}) do GtsService.TYPES[t] = true end

-- replies that may be large go on the bulk channel
GtsService.BULK = { gts_results = true, gts_mail = true, gts_welcome = true, gts_status = true }

function GtsService.isGtsMessage(msg)
  return type(msg) == "table" and type(msg.type) == "string" and msg.type:sub(1, 4) == "gts_"
end

GtsService.TEXT = {
  hello = "Please connect again.",
  pool = "This GTS trades with %s only.",
  already = "You already have a POKéMON deposited.",
  full = "The GTS is full. Please try again later.",
  invalid = "That POKéMON can't be deposited.",
  gone = "That POKéMON has already been traded.",
  own = "That is your own POKéMON.",
  nomatch = "That POKéMON doesn't meet the request.",
  compat = "That POKéMON can't go to that game.",
  busy = "Please wait a moment and try again.",
  slow = "Too many requests. Please slow down.",
  storage = "The GTS could not save. Nothing was traded.",
  bad = "The request was not understood.",
  egg = "An EGG can't be traded.",
}

local function isInt(v, lo, hi)
  return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end
GtsService.deepCopy = deepCopy

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

local function newId()
  local ok, Util = pcall(require, "src.online.net.Util")
  if ok and Util and Util.rand32 then
    return ("%08x"):format(Util.rand32() % 4294967296)
  end
  return ("%08x"):format(math.random(0, 2147483646))
end

-- a sub-second clock for rate limiting (seconds)
function GtsService.clock()
  local ok, Util = pcall(require, "src.online.net.Util")
  if ok and Util and Util.now then return Util.now() end
  return os.clock()
end

function GtsService.new(opts)
  opts = opts or {}
  local served
  if opts.pools then
    served = {}
    for _, id in ipairs(opts.pools) do served[id] = true end
  end
  local self = setmetatable({
    store = opts.store,
    served = served,
    datasets = opts.datasets or {},
    validator = opts.validator,
    requireData = opts.requireData,
    name = opts.name or "GTS",
    now = opts.now or os.time,
    newId = opts.newId or newId,
    maxDeposits = opts.maxDeposits or GtsService.MAX_DEPOSITS,
    expireSeconds = opts.expireSeconds,
    dbs = {},
    sessions = {},
    leases = {},        -- mailId -> { key = session, at = time }
    clock = opts.clock or GtsService.clock,
    rateBurst = opts.rateBurst or GtsService.RATE_BURST,
    ratePerSecond = opts.ratePerSecond or GtsService.RATE_PER_SECOND,
    log = opts.log,
  }, GtsService)
  return self
end

function GtsService:_log(fmt, ...)
  if self.log then self.log(fmt:format(...)) end
end

function GtsService:serves(pool)
  return pool ~= nil and GtsPools.POOLS[pool] ~= nil and (self.served == nil or self.served[pool] == true)
end

-- the served pool ids, sorted
function GtsService:poolList()
  local out = {}
  for id in pairs(GtsPools.POOLS) do if self:serves(id) then out[#out + 1] = id end end
  table.sort(out)
  return out
end

-- ------------------------------------------------------------ database

local function docName(pool) return "gts_" .. pool end

function GtsService:db(pool)
  local db = self.dbs[pool]
  if db then return db end
  if self.store then
    local doc, info = self.store:load(docName(pool))
    if doc then
      self:_log("gts: pool %s loaded from %s (seq %d)", pool, info.source, info.seq)
      db = doc
    end
  end
  db = db or {}
  db.v = db.v or GtsService.VERSION
  db.pool = pool
  db.dbId = db.dbId or self.newId()
  db.nextId = db.nextId or 1
  db.deposits = db.deposits or {}
  db.mail = db.mail or {}
  db.tokens = db.tokens or {}
  db.players = db.players or {}
  self.dbs[pool] = db
  return db
end

-- run fn(copy) on a copy of the pool's database, commit, and swap it in;
-- nothing changes in memory when the write fails
function GtsService:_mutate(pool, fn)
  local cur = self:db(pool)
  local nextDb = deepCopy(cur)
  local result = fn(nextDb)
  if self.store then
    local ok, err = self.store:commit(docName(pool), nextDb)
    if not ok then
      self:_log("gts: commit failed: %s", tostring(err))
      return nil, err
    end
  end
  self.dbs[pool] = nextDb
  return result or true
end

local function allocId(db, prefix)
  local n = db.nextId
  db.nextId = n + 1
  return ("%s-%s%d"):format(db.dbId, prefix, n)
end

local function rememberToken(db, owner, token, reply, now)
  local list = db.tokens[owner]
  if not list then list = {} db.tokens[owner] = list end
  list[token] = { reply = reply, at = now }
  if count(list) > GtsService.TOKENS_KEPT then
    local oldest, oldestAt
    for k, v in pairs(list) do
      if not oldestAt or (v.at or 0) < oldestAt then oldest, oldestAt = k, v.at or 0 end
    end
    if oldest then list[oldest] = nil end
  end
end

local function addMail(db, owner, item)
  local box = db.mail[owner]
  if not box then box = {} db.mail[owner] = box end
  box[item.id] = item
  return item.id
end

-- ------------------------------------------------------------ validation

-- the data set to check a mon from `game` against: that game's own, then a
-- same-family one, then any in the pool (held items it does not know are
-- then checked for shape only)
function GtsService:_dataFor(game, pool)
  local own = self.datasets[game]
  if own then return own, true end
  local fam = CompatRules.familyOf(game)
  for g, d in pairs(self.datasets) do
    if CompatRules.familyOf(g) == fam then return d, true end
  end
  for g, d in pairs(self.datasets) do
    if GtsPools.poolFor(g) == pool then return d, false end
  end
  return nil
end

local function relaxItems(packed, data)
  local p = nil
  for _, k in ipairs({ "item", "heldItem" }) do
    local v = packed[k]
    if v ~= nil and not (data.items and data.items[v] ~= nil) then
      if not (isInt(v, 0, 1023) or (type(v) == "string" and #v <= 32)) then return nil end
      p = p or deepCopy(packed)
      p[k] = nil
    end
  end
  return p or packed
end

-- shape-only: when the host has no data for the pool
local function structural(packed, pool)
  local p = GtsPools.POOLS[pool]
  if type(packed) ~= "table" then return nil, "not a POKéMON" end
  if not isInt(packed.wire, 3, 99) then return nil, "old wire format" end
  if not isInt(packed.dex, 1, (p and p.maxDex) or 1023) then return nil, "bad species" end
  if not isInt(packed.level, 1, 100) then return nil, "bad level" end
  if type(packed.moves) ~= "table" or #packed.moves < 1 or #packed.moves > 4 then
    return nil, "bad moves"
  end
  local g = type(packed.gender) == "string" and packed.gender:lower() or "none"
  return { dex = packed.dex, level = packed.level,
           gender = (g == "male" or g == "female") and g or "none",
           shiny = packed.shiny == true,
           nickname = type(packed.nickname) == "string" and packed.nickname:sub(1, 24) or nil,
           ot = type(packed.ot) == "string" and packed.ot:sub(1, 24) or nil }
end

-- info | nil, why
function GtsService:validate(packed, ctx)
  if self.validator then return self.validator(packed, ctx) end
  if type(packed) ~= "table" then return nil, "not a POKéMON" end
  local p = GtsPools.POOLS[ctx.pool]
  if not p or packed.gen ~= p.gen then return nil, "from another generation" end
  if packed.isEgg then return nil, "egg" end
  local data, own = self:_dataFor(ctx.game, ctx.pool)
  if not data then
    if self.requireData then return nil, "no data for this pool" end
    return structural(packed, ctx.pool)
  end
  local check = own and packed or relaxItems(packed, data)
  if not check then return nil, "bad held item" end
  local MonCodec = require("src.online.MonCodec")
  local mon, why = MonCodec.unpack(data, check, { strict = true })
  if not mon then return nil, why end
  local info = GtsRules.infoOf(data, mon)
  if packed.dex ~= nil and info.dex ~= packed.dex then return nil, "species number disagrees" end
  if p.maxDex and (not info.dex or info.dex > p.maxDex) then return nil, "bad species" end
  return info
end

-- ------------------------------------------------------------ views

local function depositView(dep)
  return { id = dep.id, info = dep.info, want = dep.want, name = dep.name,
           game = dep.game, createdAt = dep.createdAt }
end

local function mailView(item)
  return { id = item.id, kind = item.kind, info = item.info, sentInfo = item.sentInfo,
           from = item.from, fromGame = item.fromGame, at = item.at }
end

function GtsService:statusFor(pool, owner)
  local db = self:db(pool)
  local out = { mail = {} }
  for _, dep in pairs(db.deposits) do
    if dep.owner == owner then out.deposit = depositView(dep) break end
  end
  for _, item in pairs(db.mail[owner] or {}) do out.mail[#out.mail + 1] = mailView(item) end
  table.sort(out.mail, function(a, b)
    if (a.at or 0) ~= (b.at or 0) then return (a.at or 0) < (b.at or 0) end
    return a.id < b.id
  end)
  return out
end

-- ------------------------------------------------------------ sessions

function GtsService:connect(key)
  if self.sessions[key] then return end
  self.sessions[key] = { key = key }
end

function GtsService:disconnect(key)
  self.sessions[key] = nil
  for mailId, lease in pairs(self.leases) do
    if lease.key == key then self.leases[mailId] = nil end
  end
end

local function reply(list, msg, req)
  if req and req.rid ~= nil then msg.rid = req.rid end
  list[#list + 1] = { msg = msg, channel = GtsService.BULK[msg.type] and 2 or 0 }
  return list
end

local function refuse(list, req, code, text, extra)
  local m = { type = "gts_refused", code = code, text = text or GtsService.TEXT[code] or code,
              token = req and req.token, request = req and req.type }
  for k, v in pairs(extra or {}) do m[k] = v end
  return reply(list, m, req)
end

local function nameOk(v, max)
  if type(v) ~= "string" or v:find("[%z\1-\31\127]") then return false end
  local MonCodec = require("src.online.MonCodec")
  local n = MonCodec.utf8len(v)
  return n ~= nil and n <= max
end

local function tokenOk(t)
  return type(t) == "string" and #t >= 4 and #t <= 64 and t:match("^[%w%-_]+$") ~= nil
end

function GtsService:_hello(s, msg, out)
  local player = msg.player
  if type(player) ~= "string" or #player < 4 or #player > 80 or not player:match("^[%w%-_:.]+$") then
    return refuse(out, msg, "hello", nil, { type = "gts_denied" })
  end
  local game = type(msg.game) == "string" and msg.game:lower() or nil
  local family = CompatRules.familyOf(game)
  local pool = family and GtsPools.poolFor(family)
  if not pool or not self:serves(pool) then
    local labels = {}
    for _, id in ipairs(self:poolList()) do labels[#labels + 1] = GtsPools.POOLS[id].label end
    local text = (GtsService.TEXT.pool):format(#labels > 0 and table.concat(labels, ", ") or "no game")
    s.denied = true
    return reply(out, { type = "gts_denied", code = "pool", text = text,
                        pools = self:poolList() }, msg)
  end
  local tid = msg.tid
  if tid ~= nil and not isInt(tid, 0, 4294967295) then tid = nil end
  s.player = player
  s.game = game
  s.family = family
  s.gen = CompatRules.GEN[family]
  s.pool = pool
  s.tid = tid or 0
  s.name = nameOk(msg.name, 12) and msg.name or "?"
  s.nationalDex = msg.nationalDex == true
  s.owner = ("%s|%s|%d"):format(player, game, s.tid)
  s.hello = { gen = s.gen, game = game, family = family, nationalDex = s.nationalDex }
  self:_expire(pool)
  local p = GtsPools.POOLS[pool]
  return reply(out, { type = "gts_welcome", v = GtsService.VERSION, pool = pool,
                      label = p.label, port = p.port == true, host = self.name,
                      maxDex = p.maxDex, dbId = self:db(pool).dbId,
                      status = self:statusFor(pool, s.owner) }, msg)
end

-- deposits older than expireSeconds go back to their owner's mail
function GtsService:_expire(pool)
  if not self.expireSeconds then return end
  local now = self.now()
  local db = self:db(pool)
  local any = false
  for _, dep in pairs(db.deposits) do
    if now - (dep.createdAt or now) > self.expireSeconds then any = true break end
  end
  if not any then return end
  self:_mutate(pool, function(d)
    for id, dep in pairs(d.deposits) do
      if now - (dep.createdAt or now) > self.expireSeconds then
        d.deposits[id] = nil
        addMail(d, dep.owner, { id = allocId(d, "m"), kind = "returned", reason = "expired",
                                mon = dep.mon, info = dep.info, from = dep.name,
                                fromGame = dep.game, fromHello = dep.hello,
                                depositId = dep.id, at = now })
      end
    end
  end)
end

function GtsService:tick()
  for pool in pairs(self.dbs) do self:_expire(pool) end
end

-- the stored answer to a token this owner already used, re-sent
local function replay(db, s, msg, out)
  local list = db.tokens[s.owner]
  local seen = list and list[msg.token]
  if not seen then return false end
  local m = deepCopy(seen.reply)
  m.replayed = true
  reply(out, m, msg)
  return true
end

function GtsService:_deposit(s, msg, out)
  if not tokenOk(msg.token) then return refuse(out, msg, "bad") end
  local db = self:db(s.pool)
  if replay(db, s, msg, out) then return out end
  local okW, whyW = GtsRules.checkWant(msg.want, GtsPools.POOLS[s.pool].maxDex)
  if not okW then return refuse(out, msg, "bad", whyW) end
  for _, dep in pairs(db.deposits) do
    if dep.owner == s.owner then return refuse(out, msg, "already") end
  end
  if count(db.deposits) >= self.maxDeposits then return refuse(out, msg, "full") end
  if type(msg.mon) == "table" and msg.mon.isEgg then return refuse(out, msg, "egg") end
  local info, why = self:validate(msg.mon, { pool = s.pool, game = s.game, role = "deposit" })
  if not info then return refuse(out, msg, "invalid", GtsService.TEXT.invalid .. " (" .. tostring(why) .. ")") end
  local okSend, whySend = CompatRules.canSend(msg.mon, s.hello, s.hello)
  if not okSend then return refuse(out, msg, "invalid", whySend) end
  local now = self.now()
  local answer
  local ok, err = self:_mutate(s.pool, function(d)
    local id = allocId(d, "d")
    d.deposits[id] = {
      id = id, owner = s.owner, player = s.player, name = s.name, game = s.game,
      tid = s.tid, hello = s.hello, mon = msg.mon, info = info,
      want = GtsRules.normalizeWant(msg.want), token = msg.token,
      createdAt = now, updatedAt = now,
    }
    d.players[s.owner] = { name = s.name, game = s.game, lastSeen = now }
    answer = { type = "gts_deposited", token = msg.token, id = id, info = info }
    rememberToken(d, s.owner, msg.token, answer, now)
  end)
  if not ok then return refuse(out, msg, "storage", nil, { detail = tostring(err) }) end
  self:_log("gts: %s deposited %s (dex %s)", s.name, answer.id, tostring(info.dex))
  return reply(out, deepCopy(answer), msg)
end

function GtsService:_search(s, msg, out)
  local q = { dex = msg.dex, gender = msg.gender or "any", band = msg.band or 0 }
  local okQ, whyQ = GtsRules.checkWant(q, GtsPools.POOLS[s.pool].maxDex)
  if not okQ then return refuse(out, msg, "bad", whyQ) end
  local db = self:db(s.pool)
  local hits = {}
  for _, dep in pairs(db.deposits) do
    if dep.owner ~= s.owner and GtsRules.matches(dep.info, q)
       and CompatRules.canSend(dep.mon, dep.hello, s.hello) then
      hits[#hits + 1] = dep
    end
  end
  table.sort(hits, function(a, b)
    if a.createdAt ~= b.createdAt then return (a.createdAt or 0) > (b.createdAt or 0) end
    return a.id < b.id
  end)
  local page = isInt(msg.page, 0, 1000) and msg.page or 0
  local items = {}
  local first = page * GtsService.SEARCH_LIMIT + 1
  for i = first, math.min(#hits, first + GtsService.SEARCH_LIMIT - 1) do
    items[#items + 1] = depositView(hits[i])
  end
  return reply(out, { type = "gts_results", query = q, page = page, items = items,
                      total = #hits, more = #hits >= first + GtsService.SEARCH_LIMIT }, msg)
end

function GtsService:_offer(s, msg, out)
  if not tokenOk(msg.token) then return refuse(out, msg, "bad") end
  local db = self:db(s.pool)
  if replay(db, s, msg, out) then return out end
  local dep = type(msg.id) == "string" and db.deposits[msg.id] or nil
  if not dep then return refuse(out, msg, "gone") end
  if dep.owner == s.owner then return refuse(out, msg, "own") end
  if type(msg.mon) == "table" and msg.mon.isEgg then return refuse(out, msg, "egg") end
  local info, why = self:validate(msg.mon, { pool = s.pool, game = s.game, role = "offer" })
  if not info then return refuse(out, msg, "invalid", GtsService.TEXT.invalid .. " (" .. tostring(why) .. ")") end
  if not GtsRules.matches(info, dep.want) then return refuse(out, msg, "nomatch") end
  local ok1, why1 = CompatRules.canSend(msg.mon, s.hello, dep.hello)
  if not ok1 then return refuse(out, msg, "compat", why1) end
  local ok2, why2 = CompatRules.canSend(dep.mon, dep.hello, s.hello)
  if not ok2 then return refuse(out, msg, "compat", why2) end
  local now = self.now()
  local answer
  local ok, err = self:_mutate(s.pool, function(d)
    local live = d.deposits[dep.id]
    d.deposits[dep.id] = nil
    -- the depositor's result: what was offered for their mon
    addMail(d, live.owner, { id = allocId(d, "m"), kind = "traded", mon = msg.mon, info = info,
                             sentInfo = live.info, from = s.name, fromGame = s.game,
                             fromHello = s.hello, depositId = live.id, at = now })
    -- the offerer's: the deposited mon
    local mine = allocId(d, "m")
    addMail(d, s.owner, { id = mine, kind = "received", mon = live.mon, info = live.info,
                          sentInfo = info, from = live.name, fromGame = live.game,
                          fromHello = live.hello, depositId = live.id, at = now })
    d.players[s.owner] = { name = s.name, game = s.game, lastSeen = now }
    answer = { type = "gts_offered", token = msg.token, id = live.id, mailId = mine }
    rememberToken(d, s.owner, msg.token, answer, now)
  end)
  if not ok then return refuse(out, msg, "storage", nil, { detail = tostring(err) }) end
  self:_log("gts: %s traded for %s", s.name, dep.id)
  reply(out, deepCopy(answer), msg)
  -- a depositor who is online right now hears about it at once
  for key, other in pairs(self.sessions) do
    if other.owner == dep.owner and key ~= s.key then
      out[#out + 1] = { to = key, channel = 2,
                        msg = { type = "gts_status", status = self:statusFor(s.pool, dep.owner) } }
    end
  end
  return out
end

function GtsService:_withdraw(s, msg, out)
  if not tokenOk(msg.token) then return refuse(out, msg, "bad") end
  local db = self:db(s.pool)
  if replay(db, s, msg, out) then return out end
  local dep = type(msg.id) == "string" and db.deposits[msg.id] or nil
  if not dep or dep.owner ~= s.owner then return refuse(out, msg, "gone") end
  local now = self.now()
  local answer
  local ok, err = self:_mutate(s.pool, function(d)
    local live = d.deposits[dep.id]
    d.deposits[dep.id] = nil
    local mailId = allocId(d, "m")
    addMail(d, s.owner, { id = mailId, kind = "returned", mon = live.mon, info = live.info,
                          from = live.name, fromGame = live.game, fromHello = live.hello,
                          depositId = live.id, at = now })
    answer = { type = "gts_withdrawn", token = msg.token, id = live.id, mailId = mailId }
    rememberToken(d, s.owner, msg.token, answer, now)
  end)
  if not ok then return refuse(out, msg, "storage", nil, { detail = tostring(err) }) end
  return reply(out, deepCopy(answer), msg)
end

-- is this mail item held by another live session's unexpired claim?
function GtsService:_leasedElsewhere(mailId, key)
  local lease = self.leases[mailId]
  if not lease or lease.key == key then return false end
  if not self.sessions[lease.key] then return false end
  return self.now() - (lease.at or 0) < GtsService.LEASE_SECONDS
end

function GtsService:_claim(s, msg, out)
  local db = self:db(s.pool)
  local box = db.mail[s.owner]
  local item = type(msg.mailId) == "string" and box and box[msg.mailId] or nil
  if not item then
    return reply(out, { type = "gts_mail_gone", mailId = msg.mailId }, msg)
  end
  if self:_leasedElsewhere(item.id, s.key) then
    return refuse(out, msg, "busy", nil, { mailId = item.id })
  end
  self.leases[item.id] = { key = s.key, at = self.now() }
  return reply(out, { type = "gts_mail", mailId = item.id, kind = item.kind, mon = deepCopy(item.mon),
                      info = item.info, sentInfo = item.sentInfo, from = item.from,
                      fromGame = item.fromGame, fromHello = item.fromHello,
                      reason = item.reason }, msg)
end

function GtsService:_ack(s, msg, out)
  local db = self:db(s.pool)
  local box = db.mail[s.owner]
  local id = msg.mailId
  if type(id) ~= "string" or not (box and box[id]) then
    return reply(out, { type = "gts_acked", mailId = id }, msg)
  end
  if self:_leasedElsewhere(id, s.key) then
    return refuse(out, msg, "busy", nil, { mailId = id })
  end
  local ok, err = self:_mutate(s.pool, function(d)
    local b = d.mail[s.owner]
    if b then
      b[id] = nil
      if next(b) == nil then d.mail[s.owner] = nil end
    end
  end)
  if not ok then return refuse(out, msg, "storage", nil, { detail = tostring(err), mailId = id }) end
  self.leases[id] = nil
  return reply(out, { type = "gts_acked", mailId = id }, msg)
end

-- one request -> { {msg=, channel=, to=}, ... }   (`to`: another session's
-- key, for a push; nil: the asker)
function GtsService:handle(key, msg)
  local out = {}
  if type(msg) ~= "table" or type(msg.type) ~= "string" then return refuse(out, nil, "bad") end
  local s = self.sessions[key]
  if not s then
    self:connect(key)
    s = self.sessions[key]
  end
  -- per-session token bucket: a flooding session is refused (and nothing
  -- it asked for happens), the others are unaffected
  local now = self.clock()
  local tokens = math.min(self.rateBurst, (s.tokens or self.rateBurst)
                          + (now - (s.tokensAt or now)) * self.ratePerSecond)
  s.tokensAt = now
  if tokens < 1 then
    s.tokens = tokens
    s.limited = (s.limited or 0) + 1
    return refuse(out, msg, "slow", nil, { mailId = msg.mailId })
  end
  s.tokens = tokens - 1
  local t = msg.type
  if t == "gts_hello" then return self:_hello(s, msg, out) end
  if not s.owner then return refuse(out, msg, "hello") end
  if t == "gts_status" then
    return reply(out, { type = "gts_status", status = self:statusFor(s.pool, s.owner) }, msg)
  elseif t == "gts_deposit" then return self:_deposit(s, msg, out)
  elseif t == "gts_search" then return self:_search(s, msg, out)
  elseif t == "gts_offer" then return self:_offer(s, msg, out)
  elseif t == "gts_withdraw" then return self:_withdraw(s, msg, out)
  elseif t == "gts_claim" then return self:_claim(s, msg, out)
  elseif t == "gts_ack" then return self:_ack(s, msg, out)
  end
  return refuse(out, msg, "bad")
end

-- counts for reports and tests: { deposits = n, mail = n } in one pool
function GtsService:counts(pool)
  local db = self:db(pool)
  local mail = 0
  for _, box in pairs(db.mail) do mail = mail + count(box) end
  return { deposits = count(db.deposits), mail = mail }
end

return GtsService
