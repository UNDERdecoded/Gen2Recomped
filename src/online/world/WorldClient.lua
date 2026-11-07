-- A WORLD MEMBER'S SIDE (docs/online-design.md 2.8, workstream WS8).
--
-- One connection to the host (a Connector.join channel, or the host's own
-- in-memory pair) and everything this player knows about the world: the
-- roster with each member's map, cell, facing and avatar; the chat log;
-- invites in and out; and the two-player sessions an accepted invite
-- opens, each one a Net-API channel (SessionChannel) that LinkState drives
-- exactly as it drives a cable.
--
--   local c = WorldClient.new{
--     net = channel,              -- connected Net-like, or
--     job = Connector.join(invite) -- a join in progress
--     hello = function(worldId) return Handshake.hello(...) end,
--     identity = function(worldId) return Identity.forWorld(worldId) end,
--     name = "RED", tid = 12345, look = { walk = "SPRITE_..." },
--   }
--   c:update()             every frame
--   c.state                "connecting" | "greeting" | "in" | "closed"
--   c.reason               why it closed (text)
--   c.you, c.world, c.members[pid] = { pid, name, tid, look, pos, host, busy }
--   c:setPosition{ m, x, y, f, mv, d } (Presence calls it each tick)
--   c:say(text) ; c:emote(e) ; c:invite(pid, mode) ; c:answer(iid, ok)
--   c:cancelInvite() ; c:openService(name[, cb]) -> channel ; c:kick(pid, reason, ban)
--   c:leave()
--   c:events() -> drained list of { kind = "chat"|"notice"|"join"|"left"|
--                 "emote"|"invite"|"answer"|"session"|"closed"|"welcome", ... }
--   c.log      Chat.log of what was said (and notices)

local P = require("src.online.world.WorldProtocol")
local Chat = require("src.online.world.Chat")
local Util = require("src.online.net.Util")
local Logger = require("src.core.Logger")

local WorldClient = {}
WorldClient.__index = WorldClient

-- ------------------------------------------------------------ session channel

-- The Net API (src/link/Net.lua) over the world: every message rides to the
-- host as w_relay{sid}, and the host forwards it to the one partner.  The
-- link code above it (LinkState, TradeSession, LinkBattle, a GTS client)
-- cannot tell it from a cable.
local SessionChannel = {}
SessionChannel.__index = SessionChannel
WorldClient.SessionChannel = SessionChannel

function SessionChannel:send(msg)
  if self.closed then return end
  if not self.sid then
    -- a service channel the host has not opened yet
    self.outbox[#self.outbox + 1] = msg
    return
  end
  self.client:send({ type = "w_relay", sid = self.sid, m = msg })
end

function SessionChannel:poll()
  local msgs = self.inbox
  self.inbox = {}
  return msgs
end

-- the link screen pumps its channel every frame; that pumps the whole
-- world, so presence and chat keep flowing while a trade screen is up
function SessionChannel:update()
  if self.pump then self.pump() else self.client:update() end
end

function SessionChannel:close()
  if self.closedByUs then return end
  self.closedByUs = true
  if not self.closed and self.sid then
    self.client:send({ type = "w_end", sid = self.sid })
  end
  self.closed = true
  if self.sid then self.client.sessions[self.sid] = nil end
  if self.ref then self.client.serviceWaits[self.ref] = nil end
end

function SessionChannel:rtt() return nil end

-- ------------------------------------------------------------ client

function WorldClient.new(opts)
  opts = opts or {}
  local self = setmetatable({}, WorldClient)
  self.opts = opts
  self.clock = opts.clock or Util.time
  self.net = opts.net
  self.job = opts.job
  self.state = self.net and "greeting" or "connecting"
  self.members = {}
  self.sessions = {}
  self.queue = {}
  self.log = Chat.log(60)
  self.chatBucket = Chat.bucket()
  self.seq = 0
  self.lastSent = nil
  self.lastSentAt = -math.huge
  self.pendingInvite = nil   -- the invite this player sent and waits on
  self.incoming = {}         -- iid -> { iid, from, name, mode, at }
  self.serviceWaits = {}     -- ref -> callback
  self.nextRef = 1
  return self
end

function WorldClient:now() return self.clock() end

function WorldClient:push(ev)
  ev.t = ev.t or self:now()
  local q = self.queue
  q[#q + 1] = ev
  while #q > 128 do table.remove(q, 1) end
end

function WorldClient:events()
  local q = self.queue
  self.queue = {}
  return q
end

function WorldClient:send(msg, channel)
  if self.net and not self.net.closed then self.net:send(msg, channel) end
end

function WorldClient:close(reason, text)
  if self.state == "closed" then return end
  self.state = "closed"
  self.reason = text or reason
  for _, s in pairs(self.sessions) do
    s.closed = true
    s.error = s.error or "world closed"
  end
  self.sessions = {}
  if self.net and self.net.close then pcall(self.net.close, self.net) end
  if self.job and self.job.cancel then pcall(self.job.cancel, self.job) end
  self:push({ kind = "closed", reason = reason, text = self.reason })
  Logger.info("world client: closed (%s)", tostring(self.reason))
end

function WorldClient:leave()
  if self.state == "in" then self:send({ type = "w_bye" }) end
  -- give the bye a moment on a real socket (Transport:close flushes)
  self:close("left", "You left the world.")
end

-- ------------------------------------------------------------ outgoing

function WorldClient:say(text)
  text = P.cleanText(text, P.CHAT_MAX)
  if not text or self.state ~= "in" then return false, "nothing to say" end
  local ok, wait = self.chatBucket:take(self:now())
  if not ok then
    local line = ("Slow down! (%ds)"):format(math.ceil(wait))
    self.log:add({ kind = "notice", text = line, t = self:now() })
    return false, line
  end
  self:send({ type = "w_chat", text = text })
  return true
end

function WorldClient:emote(e)
  if not P.EMOTE_SET[e] or self.state ~= "in" then return false end
  self:send({ type = "w_emote", e = e })
  return true
end

function WorldClient:invite(pid, mode)
  if self.state ~= "in" or self.pendingInvite then return false end
  self.pendingInvite = { to = pid, mode = mode, at = self:now() }
  self:send({ type = "w_invite", to = pid, mode = mode })
  return true
end

function WorldClient:cancelInvite()
  local inv = self.pendingInvite
  if not inv then return end
  if inv.iid then self:send({ type = "w_cancel", iid = inv.iid }) end
  self.pendingInvite = nil
end

function WorldClient:answer(iid, ok)
  local inv = self.incoming[iid]
  if not inv then return false end
  self.incoming[iid] = nil
  self:send({ type = "w_answer", iid = iid, ok = ok and true or false })
  return true
end

function WorldClient:kick(pid, reason, ban)
  self:send({ type = "w_kick", pid = pid, reason = reason, ban = ban and true or nil })
end

-- a channel to a host service (the world GTS), returned AT ONCE with
-- paired = false: what is sent before the host has opened it waits in the
-- channel, and it pairs (or closes with .error) when the host answers.
-- That makes it a plain Net-like for GtsClient.setProvider.  cb(channel |
-- nil, why) is optional and fires on the answer.
function WorldClient:openService(name, cb)
  local ref = self.nextRef
  self.nextRef = ref + 1
  local ch = setmetatable({ client = self, sid = nil, inbox = {}, outbox = {}, paired = false,
                            closed = false, mode = "joining", svc = name, ref = ref,
                            pump = self.pump }, SessionChannel)
  self.serviceWaits[ref] = { ch = ch, cb = cb }
  self:send({ type = "w_svc", svc = name, ref = ref })
  return ch
end

function WorldClient:hasService(name)
  for _, s in ipairs((self.world and self.world.services) or {}) do
    if s == name then return true end
  end
  return false
end

-- where this player stands now; sent when it changes (at most POS_RATE a
-- second) and as a heartbeat every POS_HEARTBEAT seconds
function WorldClient:setPosition(pos)
  if self.state ~= "in" or not pos or not pos.m then return end
  local now = self:now()
  local last = self.lastSent
  local changed = not last or last.m ~= pos.m or last.x ~= pos.x or last.y ~= pos.y
                  or last.f ~= pos.f or last.mv ~= pos.mv
  if changed and now - self.lastSentAt < 1 / P.POS_RATE and last and last.m == pos.m then return end
  if not changed and now - self.lastSentAt < P.POS_HEARTBEAT then return end
  self.seq = self.seq + 1
  local msg = { type = "w_pos", m = pos.m, x = pos.x, y = pos.y, f = pos.f, mv = pos.mv,
                d = pos.d, s = self.seq }
  -- a map change goes reliably: the old map's players must drop the ghost
  local channel = (last and last.m == pos.m) and 1 or 0
  self:send(msg, channel)
  self.lastSent = { m = pos.m, x = pos.x, y = pos.y, f = pos.f, mv = pos.mv }
  self.lastSentAt = now
  local me = self.members[self.you]
  if me then me.pos = { m = pos.m, x = pos.x, y = pos.y, f = pos.f, mv = pos.mv, d = pos.d, s = self.seq } end
end

function WorldClient:setLook(look)
  if self.state ~= "in" then return end
  self.opts.look = look
  self:send({ type = "w_look", look = look })
end

-- ------------------------------------------------------------ incoming

function WorldClient:member(pid) return self.members[pid] end

function WorldClient:nameOf(pid)
  local m = self.members[pid]
  return m and m.name or "?"
end

function WorldClient:isHost() return self.you == P.HOST_PID end

local function rosterSet(self, list)
  self.members = {}
  for _, m in ipairs(list or {}) do
    if type(m) == "table" and tonumber(m.pid) then
      m.look = P.cleanLook(m.look)
      m.pos = P.cleanPos(m.pos)
      self.members[m.pid] = m
    end
  end
end

function WorldClient:handle(msg)
  local t = msg.type
  if t == "w_info" then
    self.world = msg.world
    if self.state == "greeting" or self.state == "connecting" then
      local worldId = msg.world and msg.world.id
      local hello = self.opts.hello and self.opts.hello(worldId) or {}
      local id = self.opts.identity and self.opts.identity(worldId) or "0"
      self:send({ type = "w_hello", v = P.VERSION, hello = hello, id = id,
                  name = self.opts.name, tid = self.opts.tid, look = self.opts.look,
                  pos = self.opts.pos })
      self.state = "greeting"
    end
  elseif t == "w_welcome" then
    self.you = tonumber(msg.you)
    self.world = msg.world or self.world
    rosterSet(self, msg.roster)
    self.state = "in"
    self.log:add({ kind = "system", text = ("Joined %s."):format(tostring(self.world and self.world.name)),
                   t = self:now() })
    self:push({ kind = "welcome" })
  elseif t == "w_refuse" then
    self:close(msg.reason, msg.text or P.REFUSALS[msg.reason] or tostring(msg.reason))
  elseif t == "w_kicked" then
    local text = msg.reason == "closed" and P.REFUSALS.closed
      or (msg.ban and "You were banned from the world." or "You were removed from the world.")
    self:close(msg.ban and "banned" or "kicked", text)
  elseif t == "w_join" then
    local m = msg.member
    if type(m) == "table" and tonumber(m.pid) then
      m.look, m.pos = P.cleanLook(m.look), P.cleanPos(m.pos)
      self.members[m.pid] = m
      self.log:add({ kind = "system", text = ("%s joined."):format(tostring(m.name)), t = self:now() })
      self:push({ kind = "join", pid = m.pid, name = m.name })
    end
  elseif t == "w_left" then
    local m = self.members[msg.pid]
    if m then
      self.members[msg.pid] = nil
      self.log:add({ kind = "system", text = ("%s left."):format(tostring(m.name)), t = self:now() })
      self:push({ kind = "left", pid = msg.pid, name = m.name })
    end
  elseif t == "w_pos" then
    local m = self.members[msg.pid]
    local pos = P.cleanPos(msg)
    if m and pos and msg.pid ~= self.you then
      if not (m.pos and m.pos.s and pos.s <= m.pos.s) then m.pos = pos end
    end
  elseif t == "w_look" then
    local m = self.members[msg.pid]
    if m then
      m.look = P.cleanLook(msg.look)
      if msg.busy ~= nil then m.busy = msg.busy or nil end
    end
  elseif t == "w_chat" then
    local text = P.cleanText(msg.text, P.CHAT_MAX)
    if text then
      local e = self.log:add({ kind = "chat", pid = msg.pid, name = P.cleanName(msg.name) or "?",
                               text = text, t = self:now() })
      self:push({ kind = "chat", pid = msg.pid, name = e.name, text = text })
    end
  elseif t == "w_emote" then
    if P.EMOTE_SET[msg.e] then
      local m = self.members[msg.pid]
      if m then m.emote = { e = msg.e, at = self:now() } end
      self:push({ kind = "emote", pid = msg.pid, e = msg.e })
    end
  elseif t == "w_notice" then
    local text = P.cleanText(msg.text, 80)
    if text then
      self.log:add({ kind = "notice", text = text, t = self:now() })
      self:push({ kind = "notice", text = text })
    end
  elseif t == "w_invite" then
    local iid = tonumber(msg.iid)
    if iid and P.MODES[msg.mode] then
      local inv = { iid = iid, from = msg.from, name = P.cleanName(msg.name) or "?",
                    mode = msg.mode, at = self:now() }
      self.incoming[iid] = inv
      self:push({ kind = "invite", iid = iid, from = msg.from, name = inv.name, mode = msg.mode })
    end
  elseif t == "w_invited" then
    if self.pendingInvite then self.pendingInvite.iid = tonumber(msg.iid) end
  elseif t == "w_answer" then
    local iid = tonumber(msg.iid)
    if self.incoming[iid] then
      -- an invite to us that was withdrawn or ran out
      self.incoming[iid] = nil
      self:push({ kind = "withdrawn", iid = iid, reason = msg.reason })
    elseif self.pendingInvite and (self.pendingInvite.iid == iid or iid == 0 or self.pendingInvite.iid == nil) then
      local inv = self.pendingInvite
      if not msg.ok then self.pendingInvite = nil end
      self:push({ kind = "answer", iid = iid, ok = msg.ok and true or false, reason = msg.reason,
                  to = inv.to, mode = inv.mode })
    end
  elseif t == "w_session" then
    local sid = tonumber(msg.sid)
    if sid and msg.mode == "svc" then
      local ref = tonumber(msg.ref) or -1
      local wait = self.serviceWaits[ref]
      self.serviceWaits[ref] = nil
      if wait then
        local ch = wait.ch
        ch.sid, ch.paired = sid, true
        self.sessions[sid] = ch
        local queued = ch.outbox or {}
        ch.outbox = {}
        for _, m in ipairs(queued) do ch:send(m) end
        if wait.cb then pcall(wait.cb, ch) end
      else
        -- nobody asked (or they gave up): close it at the host
        self:send({ type = "w_end", sid = sid })
      end
    elseif sid then
      local ch = setmetatable({ client = self, sid = sid, inbox = {}, paired = true,
                                closed = false, error = nil,
                                mode = msg.role == "host" and "hosting" or "joining",
                                peer = msg.peer, peerName = msg.peerName,
                                linkMode = msg.mode, role = msg.role, pump = self.pump },
                               SessionChannel)
      self.sessions[sid] = ch
      self.pendingInvite = nil
      self:push({ kind = "session", sid = sid, channel = ch, mode = msg.mode,
                  role = msg.role, peer = msg.peer, peerName = ch.peerName })
    end
  elseif t == "w_relay" then
    local s = self.sessions[tonumber(msg.sid) or -1]
    if s and type(msg.m) == "table" then
      local inbox = s.inbox
      if #inbox < 1024 then inbox[#inbox + 1] = msg.m end
    end
  elseif t == "w_end" then
    local sid = tonumber(msg.sid) or -1
    local s = self.sessions[sid]
    if s then
      s.closed = true
      s.error = s.error or nil
      s.endReason = msg.reason
      self.sessions[sid] = nil
      if msg.reason and msg.reason ~= "partner left" and msg.reason ~= "closed" then
        self.log:add({ kind = "notice", text = ("Link stopped: %s"):format(tostring(msg.reason)),
                       t = self:now() })
      end
      self:push({ kind = "ended", sid = sid, reason = msg.reason })
    elseif tonumber(msg.ref) and self.serviceWaits[tonumber(msg.ref)] then
      -- a service that could not open
      local wait = self.serviceWaits[tonumber(msg.ref)]
      self.serviceWaits[tonumber(msg.ref)] = nil
      wait.ch.closed = true
      wait.ch.error = tostring(msg.reason or "closed")
      if wait.cb then pcall(wait.cb, nil, msg.reason) end
    end
  end
end

-- ------------------------------------------------------------ update

function WorldClient:update()
  if self.state == "closed" then return self.state end
  if self.job and not self.net then
    local st = self.job:update()
    if st == "connected" then
      self.net = self.job.channel
      self.state = "greeting"
      self.path = self.job.path
    elseif st == "failed" then
      self:close("timeout", self.job.reason and ("Couldn't reach the world.\n" .. self.job.reason)
                            or P.REFUSALS.timeout)
      return self.state
    else
      return self.state
    end
  end
  local net = self.net
  if not net then return self.state end
  net:update()
  for _, msg in ipairs(net:poll()) do
    self:handle(msg)
    if self.state == "closed" then return self.state end
  end
  if net.closed and self.state ~= "closed" then
    self:close("lost", self.state == "in" and "The connection to the world was lost."
                       or ("Couldn't join the world." .. (net.error and ("\n" .. tostring(net.error)) or "")))
  end
  -- an invite the host never answered (the host expires its own copy too)
  local inv = self.pendingInvite
  if inv and self:now() - inv.at > P.INVITE_TTL + 5 then
    self.pendingInvite = nil
    self:push({ kind = "answer", ok = false, reason = "no answer", to = inv.to, mode = inv.mode })
  end
  return self.state
end

return WorldClient
