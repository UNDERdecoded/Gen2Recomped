-- SOUL LINK: two Nuzlocke runs, one fate.
--
-- Partners meet in an online world (LINK -> WORLDS: host one and share its
-- invite code, join a friend's, or use the Link Hub's world) and the run
-- talks over the world's `soullink` relay (src/online/SoulLinkService.lua).
-- The first Soul Link run heard is bound as the partner, by its run id, and
-- stays bound in the save.
--
-- Pairing: an encounter is keyed by AREA when both play the same game, else
-- by encounter order (the n-th counted encounter of each run, caught or
-- missed), so a Red run can be linked to a Crystal run.
--
--   * my area result (caught / missed) goes to the partner;
--   * when one side MISSED an area (fled, knocked out) and the other caught
--     there, the caught one dies -- the pair is broken;
--   * when a paired mon dies, its partner's pair dies too.
--
-- Every event is queued in the save (rm.soul.outbox) and re-sent until the
-- partner acks it, so the two runs agree after any disconnect or reload; a
-- received event id is remembered (rm.soul.seen) so a resend never kills
-- twice.

local SoulLink = {}

-- `env`: { save = fn() -> save, now = fn() -> time, kill = fn(match, cause),
--          game = fn() -> game id, name = fn() -> player name, say = fn(text) }
function SoulLink.new(env)
  return setmetatable({ env = env, ch = nil, partnerPid = nil, online = false }, { __index = SoulLink })
end

local function soul(self)
  local save = self.env.save()
  local rm = save and save.runModes
  return rm and rm.soulLink and rm.soul or nil, rm, save
end

-- ------------------------------------------------------------ outgoing --
function SoulLink:queue(kind, fields)
  local s = soul(self)
  if not s then return end
  local ev = { type = "sl_ev", id = s.runId .. ":" .. s.nextId, kind = kind }
  s.nextId = s.nextId + 1
  for k, v in pairs(fields or {}) do ev[k] = v end
  s.outbox[#s.outbox + 1] = ev
  if self.ch and not self.ch.closed and self.partnerPid then self.ch:send(ev) end
  return ev
end

function SoulLink:hello()
  local s, rm = soul(self)
  if not (s and self.ch) then return end
  self.ch:send({ type = "sl_hello", runId = s.runId, name = self.env.name(),
                 game = self.env.game(), catches = rm.catches or 0 })
end

function SoulLink:flush()
  local s = soul(self)
  if not (s and self.ch and self.partnerPid) then return end
  for _, ev in ipairs(s.outbox) do self.ch:send(ev) end
end

-- my side's area result / a death of mine
function SoulLink:areaResult(area, state, mon, idx)
  local s = soul(self)
  if not s then return end
  idx = idx or (mon and mon.soulIdx) or nil
  self:queue("area", { area = area, state = state, idx = idx })
  local keys = { tostring(area) }
  if idx then keys[2] = "#" .. tostring(idx) end
  for _, key in ipairs(keys) do
    s.pairs[key] = s.pairs[key] or {}
    s.pairs[key].mine = state
    self:judge(key)
  end
end

function SoulLink:died(mon, cause)
  if not (mon and mon.soulPair) then return end
  if cause == "partner" then return end -- the partner already knows
  self:queue("death", { area = mon.soulPair, idx = mon.soulIdx })
end

-- ------------------------------------------------------------ pairing --
local function sameGame(s, env)
  return s.partner and s.partner.game ~= nil and s.partner.game == env.game()
end

-- the pair record for an event from the partner
function SoulLink:pairKey(area, idx)
  local s = soul(self)
  if s and not sameGame(s, self.env) and idx then return "#" .. tostring(idx) end
  return tostring(area)
end

local function matcher(self, key)
  local s = soul(self)
  local byIdx = key:sub(1, 1) == "#"
  local idx = byIdx and tonumber(key:sub(2)) or nil
  return function(mon)
    if byIdx then return tonumber(mon.soulIdx) == idx end
    return mon.soulPair == key and not (s and not sameGame(s, self.env))
  end
end

-- both halves of a pair known: a miss on one side breaks it
function SoulLink:judge(areaOrKey)
  local s, rm = soul(self)
  if not s then return end
  local key = tostring(areaOrKey)
  local p = s.pairs[key]
  if not p or p.broken then return end
  local mine = rm.areas and rm.areas[key]
  if not sameGame(s, self.env) and key:sub(1, 1) == "#" then mine = nil end
  if p.theirs == "missed" and (mine and mine.state == "caught" or p.mine == "caught") then
    p.broken = true
    self.env.kill(matcher(self, key), "partner")
    if self.env.say then self.env.say("SOUL LINK: your partner missed here.\nThe pair is broken.") end
  end
end

-- ------------------------------------------------------------ incoming --
function SoulLink:handle(msg, from)
  local s, rm = soul(self)
  if not s or type(msg) ~= "table" then return end
  if msg.type == "sl_hello" then
    local p = s.partner
    if p and p.runId ~= msg.runId then return end -- someone else's run
    if not p then
      s.partner = { runId = msg.runId, name = tostring(msg.name or "?"), game = msg.game }
      if self.env.say then self.env.say("SOUL LINK: bound to " .. s.partner.name .. "!") end
    end
    s.partner.name = tostring(msg.name or s.partner.name)
    s.partner.game = msg.game or s.partner.game
    local first = self.partnerPid == nil
    self.partnerPid = from
    if first then self:hello() end
    self:flush()
    return
  end
  if not (s.partner and from == self.partnerPid) then return end
  if msg.type == "sl_ack" then
    for i = #s.outbox, 1, -1 do
      if s.outbox[i].id == msg.id then table.remove(s.outbox, i) end
    end
    return
  end
  if msg.type ~= "sl_ev" or type(msg.id) ~= "string" then return end
  if self.ch then self.ch:send({ type = "sl_ack", id = msg.id }) end
  if s.seen[msg.id] then return end
  s.seen[msg.id] = true
  local key = self:pairKey(msg.area, msg.idx)
  s.pairs[key] = s.pairs[key] or {}
  local p = s.pairs[key]
  if msg.kind == "area" then
    p.theirs = msg.state
    self:judge(key)
  elseif msg.kind == "death" then
    p.theirs = "dead"
    if not p.broken then
      p.broken = true
      local hit = self.env.kill(matcher(self, key), "partner")
      if hit and self.env.say then self.env.say("SOUL LINK: its partner fell...\nyour POKéMON follows.") end
    end
  end
end

-- ------------------------------------------------------------ transport --
-- `open(cb)` opens the world's soullink service channel (OnlineWorld)
function SoulLink:attach(ch)
  self.ch = ch
  self.partnerPid = nil
  if ch then self:hello() end
end

function SoulLink:pump()
  local ch = self.ch
  if not ch then return end
  if ch.update then pcall(ch.update, ch) end
  for _, m in ipairs(ch:poll() or {}) do
    if type(m) == "table" then
      if m.type == "sl_fwd" then self:handle(m.msg, m.from)
      elseif m.type == "sl_join" then self:hello()
      elseif m.type == "sl_leave" and m.pid == self.partnerPid then self.partnerPid = nil end
    end
  end
  if ch.closed then self.ch = nil; self.partnerPid = nil end
end

function SoulLink:status()
  local s = soul(self)
  if not s then return "OFF" end
  local who = s.partner and s.partner.name or "no partner yet"
  local link = (self.ch and self.partnerPid) and "linked" or (self.ch and "waiting" or "offline")
  return ("%s (%s), %d to send"):format(who, link, #s.outbox)
end

return SoulLink
