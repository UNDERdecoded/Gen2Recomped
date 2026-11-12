-- The message vocabulary of a player-hosted world (docs/online-design.md
-- 2.8, workstream WS8).  Pure: no love, no game data.
--
-- TOPOLOGY.  A star.  Every member holds one connection, to the host, whose
-- running game is the authority for presence (who is online, which map,
-- cell, facing, avatar, emote), chat, invites and the two-player sessions
-- that invites open.  Each player keeps playing their own save.
--
-- CHANNELS (src/online/net/Transport.lua):
--   0  reliable     everything except movement
--   1  unreliable   `w_pos` while walking (sequenced by `s`; ENet drops
--                   stale packets, and the receiver drops any `s` it has
--                   already passed, so a late packet never walks a ghost
--                   backwards)
--
-- MEMBER -> HOST
--   w_hello   { hello = Handshake.hello v3 (+ mapSet), id = per-world
--               identity hash, name, look, pos }          (answer to w_info)
--   w_pos     { m = map id, x, y, f = facing, mv = mode, d = step frames,
--               s = seq }   ch 1 within a map, ch 0 when `m` changes
--   w_look    { look }      avatar changed (bike sheet, costume ...)
--   w_chat    { text }      <= CHAT_MAX characters, rate-limited on the host
--   w_emote   { e }         one of EMOTES, cooldown on the host
--   w_invite  { to = pid, mode = "trade"|"battle" }
--   w_answer  { iid, ok }   the invitee's yes / no
--   w_cancel  { iid }       the inviter gave up waiting
--   w_relay   { sid, m }    one message of a two-player session or service
--   w_end     { sid }       a session or service channel closed
--   w_svc     { svc, sid }  open a channel to a host service (the world GTS)
--   w_kick    { pid, ban, reason }   host's own client only
--   w_bye     {}            leaving
--
-- HOST -> MEMBER
--   w_info    { world = { id, name, cap, public, services } }  on connect
--   w_welcome { you = pid, world, roster = { member, ... } }
--   w_refuse  { reason, text }          then the host disconnects
--   w_join    { member }   w_left { pid, reason }
--   w_pos     { pid, m, x, y, f, mv, d, s }
--   w_look    { pid, look }
--   w_chat    { pid, name, text }       w_emote { pid, e }
--   w_notice  { text }                  "slow down", "invite expired" ...
--   w_invite  { iid, from = pid, name, mode }
--   w_invited { iid, to = pid }         the inviter's receipt
--   w_answer  { iid, ok, reason }       the inviter learns the outcome
--   w_session { sid, mode, peer = pid, peerName, role = "host"|"guest" }
--   w_relay   { sid, m }    w_end { sid, reason }
--   w_kicked  { reason, ban }
--
-- A member record on the wire:
--   { pid, name, tid, look = { walk, bike, surf, gender, av }, pos = {...},
--   (`av`, the chosen sheet + colour, since 2026-11: Avatar.lua; optional,
--   older builds strip it in cleanLook and draw the default sheet)
--     host = bool, busy = bool }

local P = {}

P.VERSION = 1

-- world player cap: the user's decision (docs 2.13 #4)
P.DEFAULT_CAP = 8
P.MAX_CAP = 16
-- a dedicated Link Hub on a server (VPS) may hold far more: only the hub's
-- own world uses this (hub config world.cap); player-hosted worlds keep 16
P.SERVER_MAX_CAP = 1000
-- above this many players on one map, their steps are forwarded less often
-- (WorldHost:onPos) so a crowd can't flood the server's single core
P.CROWD = 24
P.MIN_CAP = 2

P.HOST_PID = 1

P.CHAT_MAX = 60           -- characters per line
P.CHAT_BURST = 4          -- lines that may be said back to back ...
P.CHAT_REFILL = 2.5       -- ... then one more every this many seconds
P.EMOTE_COOLDOWN = 1.5    -- seconds between two emotes of one player
P.INVITE_COOLDOWN = 3     -- seconds between two invites of one player
P.INVITE_TTL = 30         -- an unanswered invite expires
P.HELLO_TIMEOUT = 15      -- a connection that never says w_hello is dropped
P.NAME_MAX = 12
P.WORLD_NAME_MAX = 20

P.POS_RATE = 10           -- Hz cap for w_pos while moving
P.POS_HEARTBEAT = 2       -- seconds: resend the standing position (ch 1 drops)

-- the emotes a player can raise.  The art is each game's own where it
-- has one (src/online/world/EmoteArt.lua); the rest are drawn bubbles.
P.EMOTES = { "!", "?", "heart", "note", "...", "smile" }
P.EMOTE_SET = {}
for _, e in ipairs(P.EMOTES) do P.EMOTE_SET[e] = true end

P.MODES = { trade = true, battle = true }
P.MOVE_MODES = { walk = true, run = true, bike = true, surf = true }
P.FACINGS = { up = true, down = true, left = true, right = true }

P.TYPES = {}
for _, t in ipairs({
  "w_hello", "w_pos", "w_look", "w_chat", "w_emote", "w_invite", "w_answer",
  "w_cancel", "w_relay", "w_end", "w_svc", "w_kick", "w_bye",
  "w_info", "w_welcome", "w_refuse", "w_join", "w_left", "w_notice",
  "w_invited", "w_session", "w_kicked",
}) do P.TYPES[t] = true end

P.REFUSALS = {
  full = "The world is full.",
  banned = "You can't join this world.",
  family = "That world is for another game.",
  mapset = "That world's maps are not this game's.",
  refused = "The two games can't link.",
  modded = "This world only lets in unmodded games.",
  version = "Update the game to join this world.",
  closed = "The host closed the world.",
  timeout = "No answer from the host.",
  name = "Bad trainer name.",
}

-- ------------------------------------------------------------ sanitizing

local function utf8chars(s)
  local out = {}
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len = c < 0x80 and 1 or (c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1
    local ch = s:sub(i, i + len - 1)
    -- a malformed lead or continuation byte is dropped, not passed on
    local ok = #ch == len
    for k = 2, len do
      local b = ch:byte(k)
      if not b or b < 0x80 or b > 0xBF then ok = false end
    end
    if len == 1 and c >= 0x80 then ok = false end
    if ok then out[#out + 1] = ch end
    i = i + (ok and len or 1)
  end
  return out
end
P.utf8chars = utf8chars

-- printable text, single spaces, at most `max` characters.  Control
-- characters (including newlines) become spaces; nil when nothing is left.
function P.cleanText(s, max)
  if type(s) ~= "string" then return nil end
  s = s:gsub("[%c]", " ")
  local chars = utf8chars(s)
  local out, prevSpace = {}, true
  for _, ch in ipairs(chars) do
    local space = ch == " "
    if not (space and prevSpace) then out[#out + 1] = ch end
    prevSpace = space
    if #out >= (max or P.CHAT_MAX) then break end
  end
  local text = table.concat(out):gsub("%s+$", "")
  if text == "" then return nil end
  return text
end

function P.clampCap(cap, max)
  cap = math.floor(tonumber(cap) or P.DEFAULT_CAP)
  max = max or P.MAX_CAP
  if cap < P.MIN_CAP then cap = P.MIN_CAP end
  if cap > max then cap = max end
  return cap
end

local function isInt(v, lo, hi)
  return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi
end

local function shortString(v, max)
  return type(v) == "string" and #v > 0 and #v <= (max or 64)
end

-- a w_pos payload, checked and copied; nil when it is not one
function P.cleanPos(m)
  if type(m) ~= "table" then return nil end
  if not (shortString(m.m, 48) and isInt(m.x, -4096, 4096) and isInt(m.y, -4096, 4096)) then
    return nil
  end
  local f = P.FACINGS[m.f] and m.f or "down"
  local mv = P.MOVE_MODES[m.mv] and m.mv or "walk"
  local d = isInt(m.d, 1, 64) and m.d or 16
  local s = isInt(m.s, 0, 2 ^ 31) and m.s or 0
  return { m = m.m, x = m.x, y = m.y, f = f, mv = mv, d = d, s = s }
end

-- a look (which sheets this player's avatar wears), checked and copied
function P.cleanLook(l)
  local out = {}
  if type(l) ~= "table" then return out end
  for _, k in ipairs({ "walk", "bike", "surf" }) do
    if shortString(l[k], 64) and l[k]:match("^[%w_%-:]+$") then out[k] = l[k] end
  end
  if l.gender == "boy" or l.gender == "girl" then out.gender = l.gender end
  -- the chosen online look (src/online/world/Avatar.lua): sheet + colour.
  -- Builds before it drop this key here, which is the whole of the
  -- back-compat story: an old viewer or host just never sees it.
  local av = require("src.online.world.Avatar").clean(l.av)
  if av then out.av = av end
  return out
end

function P.cleanName(s)
  return P.cleanText(s, P.NAME_MAX)
end

-- the public part of a member record (what other members are told)
function P.publicMember(m)
  return { pid = m.pid, name = m.name, tid = m.tid, look = m.look, pos = m.pos,
           host = m.pid == P.HOST_PID or nil, busy = m.busy or nil }
end

return P
