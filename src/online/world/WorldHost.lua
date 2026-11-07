-- THE WORLD HOST (docs/online-design.md 2.8, workstream WS8).
--
-- A player's running game is the authority for one world: who is in it,
-- which map each of them stands on, at which cell, facing where, wearing
-- which avatar, raising which emote; chat; trade and battle invites; the
-- two-player sessions an accepted invite opens; and any service the host
-- runs for its members (the world GTS, WS7).  Each member keeps playing
-- their own save -- the world is an overlay, like the Union Room, not a
-- shared save -- so nothing here touches anyone's progress.
--
-- TOPOLOGY: a star over one Transport (src/online/net/Transport.lua).
-- Members connect to the host only; the host forwards.  The host's OWN
-- player is a member too, joined over an in-memory pair (WorldHost.localPair)
-- through exactly the same w_hello path, and always gets pid 1.
--
--   local host = WorldHost.new{
--     world = store:create{ name = "RED's world", cap = 8 },  -- or store:open(id)
--     store = WorldStore.new(),
--     hello = Handshake.hello(game, nil, { mapSet = MapSet.of(data) }),
--     data = game.data,                -- for MonCodec checks (anti-cheat)
--     connector = { port = 7777, ... } -- Connector.host opts, or
--     transport = t,                   -- an already listening Transport (tests)
--   }
--   host:update()                      -- every frame (OnlineWorld does it)
--   host:localClientNet()              -- the Net-like the host's WorldClient uses
--   host:inviteFields()                -- for InviteCode.encode (kind = world)
--   host:kick(pid, reason, ban) ; host:unban(idHash) ; host:close()
--   host:registerService(name, service)   -- the GTS embed point, see below
--   host:storage(name)                    -- { read(), write(text) } in the world folder
--
-- SERVICES (the WS7 embed point).  A service is a table
--   { open = function(channel, member) end,   -- a member opened it
--     update = function(dt) end, close = function() end }   -- optional
-- `channel` is Net-like (send/poll/update/close, .closed): what a member's
-- GtsClient sends arrives on it, and what the service sends goes to that
-- member alone.  `member` = { pid, name, id (per-world identity hash),
-- family, game }.  Persist with host:storage("gts").
--
-- ANTI-CHEAT (2.8): joins are refused unless the handshake verdict (WS3:
-- Handshake.checkCompat / CompatRules) allows a link, the family and the
-- map set match the host's, the player is not banned, and -- in a PUBLIC
-- world -- the game is unmodded (translations excepted).  Inside a session
-- the host checks every `party` the two players exchange with MonCodec's
-- range checks (Protocol.unpackMon strict for a Gen 1/2 v2 packet) and a
-- `pick` against the size of the party it saw, and ends the session with
-- the reason before an illegal mon reaches the other player.  Chat, emotes
-- and invites are rate-limited here, whatever the client does.

local P = require("src.online.world.WorldProtocol")
local Chat = require("src.online.world.Chat")
local Wire = require("src.online.net.Wire")
local Util = require("src.online.net.Util")
local Logger = require("src.core.Logger")

local WorldHost = {}
WorldHost.__index = WorldHost

-- ------------------------------------------------------------ local pair

-- Two in-memory ends with the Net API.  Every message is encoded and
-- decoded on the way, so neither side can alias the other's tables, and a
-- message the wire would refuse is refused here too.
local LocalEnd = {}
LocalEnd.__index = LocalEnd

function WorldHost.localPair()
  local a = setmetatable({ inbox = {}, paired = true, closed = false, mode = "local" }, LocalEnd)
  local b = setmetatable({ inbox = {}, paired = true, closed = false, mode = "local" }, LocalEnd)
  a.other, b.other = b, a
  return a, b
end

function LocalEnd:send(msg, channel)
  if self.closed or self.other.closed then return end
  local data = Wire.encode(msg, channel)
  if not data then return end
  local copy = Wire.decode(data, channel)
  if copy then
    local inbox = self.other.inbox
    inbox[#inbox + 1] = copy
  end
end

function LocalEnd:poll()
  local msgs = self.inbox
  self.inbox = {}
  return msgs
end

function LocalEnd:update() end

function LocalEnd:close()
  self.closed = true
  self.other.closed = true
end

-- ------------------------------------------------------------ host-side
-- service channel: what one member exchanges with one host service

local SvcChannel = {}
SvcChannel.__index = SvcChannel

function SvcChannel:send(msg)
  if self.closed then return end
  self.host:sendTo(self.member, { type = "w_relay", sid = self.sid, m = msg })
end

function SvcChannel:poll()
  local msgs = self.inbox
  self.inbox = {}
  return msgs
end

function SvcChannel:update() end

function SvcChannel:close()
  if self.closed then return end
  self.closed = true
  self.host:endSession(self.sid, "closed", nil)
end

-- ------------------------------------------------------------ construction

function WorldHost.new(opts)
  opts = opts or {}
  local self = setmetatable({}, WorldHost)
  self.opts = opts
  self.clock = opts.clock or Util.time
  self.store = opts.store
  self.world = opts.world or { id = "local", name = "WORLD", cap = P.DEFAULT_CAP, public = false }
  self.world.cap = P.clampCap(self.world.cap)
  -- the chat filter (ChatFilter): the world's own setting, else on exactly
  -- when the world is public
  if opts.filterChat ~= nil then
    self.filterChat = opts.filterChat and true or false
  elseif self.world.filter ~= nil then
    self.filterChat = self.world.filter and true or false
  else
    self.filterChat = self.world.public and true or false
  end
  self.hello = opts.hello or {}
  self.data = opts.data
  self.members = {}        -- pid -> member (state "in")
  self.byPeer = {}         -- transport peer id -> member (pending or in)
  self.nextPid = P.HOST_PID + 1
  self.invites = {}        -- iid -> { iid, from, to, mode, at }
  self.sessions = {}       -- sid -> { sid, a, b, mode } | { sid, svc, pid, channel }
  self.services = {}
  self.nextId = 1
  self.events = {}         -- for the host UI: { kind = "join"|"left"|"refused"|"kick", ... }
  self.memberBook = (self.store and self.world.id and self.store:members(self.world.id))
                    or { members = {}, bans = {} }
  self.hostEnd, self.clientEnd = WorldHost.localPair()
  self.localMember = { isLocal = true, state = "pending", at = self.clock() }
  self.state = "starting"
  if opts.transport then
    self.transport = opts.transport
    self.state = "open"
  elseif opts.connector ~= false then
    local Connector = require("src.online.net.Connector")
    local copts = {}
    for k, v in pairs(opts.connector or {}) do copts[k] = v end
    copts.kind = 1                                  -- InviteCode kind "world"
    -- the host's own player is local, so cap - 1 remote peers; never 1, which
    -- is the Connector's one-guest link-session mode (it would adopt the
    -- first joiner and stop pumping the socket).  The cap itself is checked
    -- at w_hello (admission), so a 2-player world still turns a third away.
    copts.maxPeers = math.max(2, self.world.cap - 1)
    copts.beaconInfo = copts.beaconInfo or { world = self.world.name }
    self.connector = Connector.host(copts)
  end
  -- greet the local player like any other
  self:sendTo(self.localMember, self:infoMessage())
  return self
end

function WorldHost:now() return self.clock() end

function WorldHost:newId()
  local id = self.nextId
  self.nextId = id + 1
  return id
end

function WorldHost:localClientNet() return self.clientEnd end

function WorldHost:infoMessage()
  local services = {}
  for name in pairs(self.services) do services[#services + 1] = name end
  table.sort(services)
  return { type = "w_info", world = { id = self.world.id, name = self.world.name,
                                      cap = self.world.cap, public = self.world.public or false,
                                      services = services } }
end

function WorldHost:inviteFields()
  if self.connector and self.connector.inviteFields then
    local f = self.connector:inviteFields()
    f.kind = 1
    return f
  end
  return nil
end

function WorldHost:count()
  local n = 0
  for _ in pairs(self.members) do n = n + 1 end
  return n
end

function WorldHost:roster()
  local list = {}
  for _, m in pairs(self.members) do list[#list + 1] = P.publicMember(m) end
  table.sort(list, function(a, b) return a.pid < b.pid end)
  return list
end

function WorldHost:emit(ev)
  local q = self.events
  q[#q + 1] = ev
  while #q > 64 do table.remove(q, 1) end
end

function WorldHost:drainEvents()
  local q = self.events
  self.events = {}
  return q
end

-- ------------------------------------------------------------ sending

function WorldHost:sendTo(member, msg, channel)
  if not member then return end
  if member.isLocal then
    self.hostEnd:send(msg, channel)
  elseif member.channel and not member.channel.closed then
    member.channel:send(msg, channel)
  end
end

-- to every member in the world, except `skip` (a member) and anyone
-- `filter(member)` refuses
function WorldHost:broadcast(msg, channel, skip, filter)
  for _, m in pairs(self.members) do
    if m ~= skip and (not filter or filter(m)) then self:sendTo(m, msg, channel) end
  end
end

-- ------------------------------------------------------------ joining

local function modded(hello)
  for _, mod in ipairs((hello and hello.mods) or {}) do
    if not (mod.language and not mod.affectsLink) then return true end
  end
  return false
end

-- the WS3 verdict without disturbing Handshake.session (a trade the host's
-- own player has open reads it)
function WorldHost.verdict(mine, theirs)
  local ok, Handshake = pcall(require, "src.link.Handshake")
  if not ok then return "full" end
  local saved = Handshake.session
  local okC, verdict, reason = pcall(Handshake.checkCompat, mine, theirs)
  Handshake.session = saved
  if not okC then return "refused", "bad hello" end
  return verdict, reason
end

function WorldHost:refuse(member, code, detail)
  self:sendTo(member, { type = "w_refuse", reason = code,
                        text = detail or P.REFUSALS[code] or code })
  self:emit({ kind = "refused", reason = code, name = member.name })
  Logger.info("world: refused %s (%s)", tostring(member.name or member.peerId), tostring(code))
  if member.peerId and self.transport then
    self.transport:disconnect(member.peerId)
  end
  if member.peerId then self.byPeer[member.peerId] = false end
end

-- why this hello may not join, or nil
function WorldHost:admission(member, msg)
  local h = msg.hello
  if type(h) ~= "table" then return "version" end
  local mine = self.hello
  if (tonumber(msg.v) or 0) ~= P.VERSION then return "version" end
  local verdict = WorldHost.verdict(mine, h)
  member.verdict = verdict
  if verdict == "refused" then return "refused" end
  if mine.family and h.family ~= mine.family then return "family" end
  if mine.mapSet and h.mapSet ~= mine.mapSet then return "mapset" end
  if self.world.public and modded(h) then return "modded" end
  if type(msg.id) ~= "string" or not msg.id:match("^%x+$") or #msg.id > 64 then return "version" end
  if self.memberBook.bans[msg.id] then return "banned" end
  if self:count() >= self.world.cap then return "full" end
  return nil
end

function WorldHost:onHello(member, msg)
  if member.state ~= "pending" then return end
  local name = P.cleanName(msg.name)
  if not name then return self:refuse(member, "name") end
  member.name = name
  if not member.isLocal then
    local why = self:admission(member, msg)
    if why then return self:refuse(member, why) end
  else
    member.verdict = "full"
  end
  -- the same player again (a dropped connection they came back on): the
  -- old record goes, so nobody is in the world twice
  local id = type(msg.id) == "string" and msg.id or nil
  for _, other in pairs(self.members) do
    if id and other.id == id and other ~= member and not other.isLocal then
      self:remove(other, "replaced")
    end
  end
  member.id = id
  member.pid = member.isLocal and P.HOST_PID or self.nextPid
  if not member.isLocal then self.nextPid = self.nextPid + 1 end
  member.tid = tonumber(msg.tid) and (math.floor(tonumber(msg.tid)) % 65536) or 0
  member.look = P.cleanLook(msg.look)
  member.pos = P.cleanPos(msg.pos)
  member.hello = msg.hello
  member.family = type(msg.hello) == "table" and msg.hello.family or nil
  member.game = type(msg.hello) == "table" and msg.hello.game or nil
  member.chat = Chat.bucket()
  member.emoteCd = Chat.cooldown(P.EMOTE_COOLDOWN)
  member.inviteCd = Chat.cooldown(P.INVITE_COOLDOWN)
  member.state = "in"
  self.members[member.pid] = member
  self:sendTo(member, { type = "w_welcome", you = member.pid,
                        world = self:infoMessage().world, roster = self:roster() })
  self:broadcast({ type = "w_join", member = P.publicMember(member) }, 0, member)
  self:emit({ kind = "join", pid = member.pid, name = member.name })
  Logger.info("world: %s joined as %d (%d/%d)", member.name, member.pid, self:count(), self.world.cap)
  if id then
    local book = self.memberBook.members[id] or { first = os.time(), visits = 0 }
    book.name, book.last = member.name, os.time()
    book.visits = (book.visits or 0) + 1
    self.memberBook.members[id] = book
    self:saveBook()
  end
end

function WorldHost:saveBook()
  if self.store and self.world.id then
    self.store:saveMembers(self.world.id, self.memberBook)
  end
end

-- ------------------------------------------------------------ leaving

function WorldHost:remove(member, reason)
  if member.removed then return end
  member.removed = true
  if member.peerId then self.byPeer[member.peerId] = false end
  if member.state ~= "in" then return end
  member.state = "gone"
  self.members[member.pid] = nil
  -- sessions and invites it was part of end with it
  for sid, s in pairs(self.sessions) do
    if s.a == member.pid or s.b == member.pid or s.pid == member.pid then
      self:endSession(sid, "partner left", member.pid)
    end
  end
  for iid, inv in pairs(self.invites) do
    if inv.from == member.pid or inv.to == member.pid then
      self.invites[iid] = nil
      local other = self.members[inv.from == member.pid and inv.to or inv.from]
      if other then self:sendTo(other, { type = "w_answer", iid = iid, ok = false, reason = "left" }) end
    end
  end
  self:broadcast({ type = "w_left", pid = member.pid, reason = reason })
  self:emit({ kind = "left", pid = member.pid, name = member.name, reason = reason })
  if member.id and self.memberBook.members[member.id] then
    self.memberBook.members[member.id].last = os.time()
    self:saveBook()
  end
  Logger.info("world: %s left (%s)", tostring(member.name), tostring(reason))
end

function WorldHost:kick(pid, reason, ban)
  local m = self.members[pid]
  if not m or m.isLocal then return false end
  self:sendTo(m, { type = "w_kicked", reason = reason, ban = ban and true or nil })
  if ban and m.id then
    self.memberBook.bans[m.id] = { name = m.name, at = os.time(), reason = reason }
    self:saveBook()
  end
  self:emit({ kind = "kick", pid = pid, name = m.name, ban = ban and true or false })
  self:remove(m, ban and "banned" or "kicked")
  if m.peerId and self.transport then self.transport:disconnect(m.peerId) end
  return true
end

function WorldHost:bans()
  local list = {}
  for id, b in pairs(self.memberBook.bans) do
    list[#list + 1] = { id = id, name = b.name, at = b.at, reason = b.reason }
  end
  table.sort(list, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return list
end

function WorldHost:unban(id)
  if self.memberBook.bans[id] then
    self.memberBook.bans[id] = nil
    self:saveBook()
    return true
  end
  return false
end

-- ------------------------------------------------------------ presence

function WorldHost:onPos(member, msg)
  local pos = P.cleanPos(msg)
  if not pos then return end
  local old = member.pos
  local mapChanged = not old or old.m ~= pos.m
  -- every w_pos carries the sender's running count: an unreliable packet
  -- that arrives after a newer one (even a reliable map change) is stale
  if old and old.s and pos.s <= old.s then return end
  member.pos = pos
  local out = { type = "w_pos", pid = member.pid, m = pos.m, x = pos.x, y = pos.y,
                f = pos.f, mv = pos.mv, d = pos.d, s = pos.s }
  if mapChanged then
    -- everyone learns where everyone is (the member list shows it), and the
    -- old map's players drop the ghost
    self:broadcast(out, 0, member)
    -- ...and the arrival learns where the players already on that map
    -- stand now (their in-map steps only went to that map)
    for _, m in pairs(self.members) do
      local p = m.pos
      if m ~= member and p and p.m == pos.m then
        self:sendTo(member, { type = "w_pos", pid = m.pid, m = p.m, x = p.x, y = p.y,
                              f = p.f, mv = p.mv, d = p.d, s = p.s })
      end
    end
  else
    -- interest filter: only the players standing on that map, and not
    -- while they sit in a trade or battle screen
    self:broadcast(out, 1, member, function(m)
      return m.pos and m.pos.m == pos.m and not m.busy
    end)
  end
end

function WorldHost:onLook(member, msg)
  member.look = P.cleanLook(msg.look)
  self:broadcast({ type = "w_look", pid = member.pid, look = member.look }, 0, member)
end

function WorldHost:onChat(member, msg)
  local text = P.cleanText(msg.text, P.CHAT_MAX)
  if not text then return end
  local ok, wait = member.chat:take(self:now())
  if not ok then
    self:sendTo(member, { type = "w_notice", text = ("Slow down! (%ds)"):format(math.ceil(wait)) })
    return
  end
  if self.filterChat then
    text = require("src.online.world.ChatFilter").censor(text)
  end
  self:broadcast({ type = "w_chat", pid = member.pid, name = member.name, text = text })
  self:emit({ kind = "chat", pid = member.pid, name = member.name, text = text })
end

function WorldHost:onEmote(member, msg)
  if not P.EMOTE_SET[msg.e] then return end
  if not member.emoteCd:take(self:now()) then return end
  self:broadcast({ type = "w_emote", pid = member.pid, e = msg.e })
end

-- ------------------------------------------------------------ invites

local function setBusy(self, member, busy)
  if not member or (member.busy or false) == busy then return end
  member.busy = busy or nil
  self:broadcast({ type = "w_look", pid = member.pid, look = member.look, busy = busy })
end

function WorldHost:onInvite(member, msg)
  local to = self.members[tonumber(msg.to) or -1]
  local function no(reason)
    self:sendTo(member, { type = "w_answer", iid = 0, ok = false, reason = reason })
  end
  if not P.MODES[msg.mode] then return no("bad mode") end
  if not to or to == member then return no("not here") end
  if member.busy or to.busy then return no("busy") end
  if not (member.pos and to.pos and member.pos.m == to.pos.m) then return no("too far") end
  for _, inv in pairs(self.invites) do
    if inv.from == member.pid then return no("already asking") end
    if inv.to == to.pid then return no("busy") end
  end
  if not member.inviteCd:take(self:now()) then return no("too soon") end
  local iid = self:newId()
  self.invites[iid] = { iid = iid, from = member.pid, to = to.pid, mode = msg.mode, at = self:now() }
  self:sendTo(to, { type = "w_invite", iid = iid, from = member.pid, name = member.name, mode = msg.mode })
  self:sendTo(member, { type = "w_invited", iid = iid, to = to.pid })
end

function WorldHost:onCancel(member, msg)
  local inv = self.invites[tonumber(msg.iid) or -1]
  if not inv or inv.from ~= member.pid then return end
  self.invites[inv.iid] = nil
  self:sendTo(self.members[inv.to], { type = "w_answer", iid = inv.iid, ok = false, reason = "cancelled" })
end

function WorldHost:onAnswer(member, msg)
  local inv = self.invites[tonumber(msg.iid) or -1]
  if not inv or inv.to ~= member.pid then return end
  self.invites[inv.iid] = nil
  local from = self.members[inv.from]
  if not from then return end
  if not msg.ok then
    self:sendTo(from, { type = "w_answer", iid = inv.iid, ok = false, reason = "declined" })
    return
  end
  if from.busy or member.busy then
    self:sendTo(from, { type = "w_answer", iid = inv.iid, ok = false, reason = "busy" })
    self:sendTo(member, { type = "w_answer", iid = inv.iid, ok = false, reason = "busy" })
    return
  end
  local sid = self:newId()
  self.sessions[sid] = { sid = sid, a = from.pid, b = member.pid, mode = inv.mode, seen = {} }
  setBusy(self, from, true)
  setBusy(self, member, true)
  self:sendTo(from, { type = "w_answer", iid = inv.iid, ok = true })
  -- the inviter picked the mode, so it is the link session's host side
  self:sendTo(from, { type = "w_session", sid = sid, mode = inv.mode, peer = member.pid,
                      peerName = member.name, role = "host" })
  self:sendTo(member, { type = "w_session", sid = sid, mode = inv.mode, peer = from.pid,
                        peerName = from.name, role = "guest" })
  self:emit({ kind = "session", sid = sid, mode = inv.mode, a = from.name, b = member.name })
end

-- ------------------------------------------------------------ sessions

-- the mon checks the host can make with its own data (2.8 anti-cheat)
function WorldHost.validateMon(data, packed)
  if type(packed) ~= "table" then return false, "not a POKéMON" end
  if not data then return true end
  if (tonumber(packed.wire) or 0) >= 3 then
    local ok, MonCodec = pcall(require, "src.online.MonCodec")
    if not ok then return true end
    local okV, valid, why = pcall(MonCodec.validate, data, packed)
    if not okV then return false, "unreadable POKéMON" end
    return valid, why
  end
  local okP, Protocol = pcall(require, "src.link.Protocol")
  if not okP then return true end
  local okU, mon, why = pcall(Protocol.unpackMon, data, packed, { strict = true })
  if not okU then return false, "unreadable POKéMON" end
  if mon then return true end
  return false, why
end

function WorldHost:inspect(sess, from, msg)
  if type(msg) ~= "table" or type(msg.type) ~= "string" then return false, "bad message" end
  if msg.type == "party" then
    local mons = msg.mons
    if type(mons) ~= "table" or #mons > 6 then return false, "bad party" end
    -- only when both players read the host's data the same way (verdict
    -- "full"); a family pair is still checked by the receiving game itself
    local a, b = self.members[sess.a], self.members[sess.b]
    local checkable = a and b and a.verdict == "full" and b.verdict == "full"
    if checkable then
      for i, packed in ipairs(mons) do
        local ok, why = WorldHost.validateMon(self.data, packed)
        if not ok then
          return false, ("party slot %d: %s"):format(i, tostring(why or "illegal POKéMON"))
        end
      end
    end
    sess.seen[from] = #mons
  elseif msg.type == "pick" then
    local n = sess.seen[from]
    local i = msg.index
    if n and not (type(i) == "number" and i == math.floor(i) and i >= 1 and i <= n) then
      return false, "bad pick"
    end
  end
  return true
end

function WorldHost:onRelay(member, msg)
  local sid = tonumber(msg.sid)
  local s = sid and self.sessions[sid]
  if not s then return end
  if s.svc then
    if s.pid ~= member.pid or not s.channel then return end
    local inbox = s.channel.inbox
    if #inbox < 512 and type(msg.m) == "table" then inbox[#inbox + 1] = msg.m end
    return
  end
  local other
  if s.a == member.pid then other = s.b elseif s.b == member.pid then other = s.a else return end
  local ok, why = self:inspect(s, member.pid, msg.m)
  if not ok then
    Logger.warn("world: session %d stopped: %s from %s", sid, tostring(why), tostring(member.name))
    self:emit({ kind = "cheat", pid = member.pid, name = member.name, reason = why })
    self:endSession(sid, ("%s sent %s"):format(member.name, tostring(why)), nil)
    return
  end
  self:sendTo(self.members[other], { type = "w_relay", sid = sid, m = msg.m })
end

-- byPid: the side that ended it (it is not told again)
function WorldHost:endSession(sid, reason, byPid)
  local s = self.sessions[sid]
  if not s then return end
  self.sessions[sid] = nil
  if s.svc then
    if s.channel then s.channel.closed = true end
    if byPid ~= s.pid then
      self:sendTo(self.members[s.pid], { type = "w_end", sid = sid, reason = reason })
    end
    return
  end
  for _, pid in ipairs({ s.a, s.b }) do
    local m = self.members[pid]
    if m then
      if pid ~= byPid then self:sendTo(m, { type = "w_end", sid = sid, reason = reason }) end
      setBusy(self, m, false)
    end
  end
end

function WorldHost:onEnd(member, msg)
  local sid = tonumber(msg.sid)
  local s = sid and self.sessions[sid]
  if not s then return end
  if s.a == member.pid or s.b == member.pid or s.pid == member.pid then
    self:endSession(sid, s.svc and "closed" or "partner left", member.pid)
  end
end

-- ------------------------------------------------------------ services

function WorldHost:registerService(name, service)
  self.services[name] = service
  -- members already in learn it exists
  self:broadcast(self:infoMessage())
end

function WorldHost:storage(name)
  if not (self.store and self.world.id) then return nil end
  return self.store:file(self.world.id, name)
end

function WorldHost:onService(member, msg)
  local svc = type(msg.svc) == "string" and self.services[msg.svc]
  if not svc then
    self:sendTo(member, { type = "w_end", sid = 0, ref = tonumber(msg.ref), reason = "no such service" })
    return
  end
  local sid = self:newId()
  local ch = setmetatable({ host = self, member = member, sid = sid, inbox = {},
                            paired = true, closed = false, mode = "hosting" }, SvcChannel)
  self.sessions[sid] = { sid = sid, svc = msg.svc, pid = member.pid, channel = ch }
  self:sendTo(member, { type = "w_session", sid = sid, mode = "svc", svc = msg.svc,
                        ref = msg.ref, role = "guest" })
  local ok, err = pcall(svc.open, ch, { pid = member.pid, name = member.name, id = member.id,
                                        family = member.family, game = member.game })
  if not ok then
    Logger.warn("world: service %s failed to open: %s", tostring(msg.svc), tostring(err))
    self:endSession(sid, "service failed", nil)
  end
end

-- ------------------------------------------------------------ dispatch

local HANDLERS = {
  w_pos = WorldHost.onPos, w_look = WorldHost.onLook, w_chat = WorldHost.onChat,
  w_emote = WorldHost.onEmote, w_invite = WorldHost.onInvite, w_answer = WorldHost.onAnswer,
  w_cancel = WorldHost.onCancel, w_relay = WorldHost.onRelay, w_end = WorldHost.onEnd,
  w_svc = WorldHost.onService,
}

function WorldHost:handle(member, msg)
  local t = msg.type
  if t == "w_hello" then return self:onHello(member, msg) end
  if member.state ~= "in" then return end
  if t == "w_bye" then return self:remove(member, "left") end
  if t == "w_kick" then
    if member.isLocal then self:kick(tonumber(msg.pid) or -1, P.cleanText(msg.reason, 40), msg.ban) end
    return
  end
  local fn = HANDLERS[t]
  if fn then fn(self, member, msg) end
end

-- ------------------------------------------------------------ update

function WorldHost:update()
  if self.state == "closed" then return self.state end
  local now = self:now()
  local c = self.connector
  if c then
    c:update()
    -- the Connector pumps the socket only while it is "listening"
    if c.state == "connected" and self.transport then self.transport:update() end
    if c.state == "failed" then
      self.state, self.reason = "failed", c.reason
      return self.state
    end
    if c.transport and not self.transport then self.transport = c.transport end
    if self.transport and self.state == "starting" then self.state = "open" end
  elseif self.transport then
    self.transport:update()
  end
  local t = self.transport
  if t then
    -- the Connector does not drain these in multi-peer mode
    for _, ev in ipairs(t:events()) do
      if ev.type == "disconnect" then
        local m = self.byPeer[ev.peer]
        if m then self:remove(m, "connection lost") end
      end
    end
    -- a new joiner: promoted (it picked this connection or spoke)
    for _, rec in ipairs(t:peerList()) do
      if not rec.outgoing and rec.state == "connected" and rec.promoted
         and self.byPeer[rec.id] == nil then
        local ch = t:channelFor(rec.id)
        local m = { peerId = rec.id, channel = ch, state = "pending", at = now,
                    address = rec.address }
        self.byPeer[rec.id] = m
        self:sendTo(m, self:infoMessage())
      end
    end
    for peerId, m in pairs(self.byPeer) do
      if m then
        if m.channel.closed then
          self:remove(m, "connection lost")
        else
          for _, msg in ipairs(m.channel:poll()) do
            self:handle(m, msg)
            if m.removed then break end
          end
          if m.state == "pending" and now - m.at > P.HELLO_TIMEOUT then
            self:refuse(m, "timeout")
          end
        end
      end
    end
  end
  for _, msg in ipairs(self.hostEnd:poll()) do self:handle(self.localMember, msg) end
  -- invites nobody answered
  for iid, inv in pairs(self.invites) do
    if now - inv.at > P.INVITE_TTL then
      self.invites[iid] = nil
      self:sendTo(self.members[inv.from], { type = "w_answer", iid = iid, ok = false, reason = "no answer" })
      self:sendTo(self.members[inv.to], { type = "w_answer", iid = iid, ok = false, reason = "expired" })
    end
  end
  for name, svc in pairs(self.services) do
    if svc.update then
      local ok, err = pcall(svc.update, now)
      if not ok then Logger.warn("world: service %s: %s", name, tostring(err)) end
    end
  end
  return self.state
end

function WorldHost:close(reason)
  if self.state == "closed" then return end
  for _, m in pairs(self.members) do
    if not m.isLocal then self:sendTo(m, { type = "w_kicked", reason = reason or "closed" }) end
  end
  for _, svc in pairs(self.services) do
    if svc.close then pcall(svc.close) end
  end
  if self.connector then
    self.connector:close()
  elseif self.transport and self.opts.ownsTransport then
    self.transport:close()
  elseif self.transport then
    for _, m in pairs(self.byPeer) do
      if m and m.peerId then self.transport:disconnect(m.peerId) end
    end
  end
  self.hostEnd:close()
  self.state = "closed"
end

return WorldHost
