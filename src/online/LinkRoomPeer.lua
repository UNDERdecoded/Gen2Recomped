-- THE OTHER PLAYER IN A LINK ROOM (docs/online-design.md 2.7).
--
-- The cartridges' Trade Centers and Colosseums show the friend walking around:
-- Gen 3's link overworld moves real link player objects, Gen 4's comm player
-- manager the same.  Here a held LinkRooms session sends where this player
-- stands and shows the friend as a ghost NPC (src/online/world/Presence.lua's:
-- in `overworld.entities` only, passable, no script), over the session's own
-- channel while both games are in the room.
--
-- It also keeps the session's rounds: a room plays on after a battle or a
-- trade (LinkRooms._rearm), and this says when each game is back in the room
-- ("lr_ready"), and when one has left for good ("lr_leave").
--
-- Wire (all on the session's reliable channel, all with `lr_` so a LinkState
-- that resumes never sees them; see LinkRooms hooksFor.ignore):
--   lr_room  { room, v }             LinkRooms' exchange; v >= 2 speaks this file
--   lr_pos   { x, y, f, d, look }    this player's cell in the room
--   lr_ready { round }               back in the room after round - 1
--   lr_leave {}                      gone from the room, the link is ending
--   lr_chat  { text }                a chat line (v >= 3 peers only)
--   lr_emote { e }                   an emote (v >= 3 peers only)
-- `look` may carry `av` (the chosen sheet + colour, Avatar.lua); a v2 peer
-- runs no cleanLook on it and its Presence ignores the key.
--
-- A peer that does not speak it (a LINK-menu player, not in a room; an older
-- build, v = 1) gets none of these messages and the session ends after one
-- round, as it always did.
--
-- The room's map is told apart by the walk: `linked` happens at the counter,
-- so the first other map is the room and the next one after it is the way out.
-- Map ids are not compared across games, so a family link (Emerald and
-- FireRed, Platinum and HeartGold) still meets; the rooms share their layouts.
-- Gen 2's Trade Center and Colosseum seat a sprite for the friend on the
-- script's own rows (CableClubCheckWhichChris), so they say `noGhost`.

local RoomPeer = {}

RoomPeer.VERSION = 3        -- what this build says in lr_room
RoomPeer.MIN_VERSION = 2    -- the oldest peer that walks in the room
RoomPeer.CHAT_VERSION = 3   -- the oldest peer that hears lr_chat / lr_emote
RoomPeer.PID = 990          -- synthetic: Presence.INDEX + this is the ghost's object index
RoomPeer.HEARTBEAT = 1.0    -- seconds between repeats of an unchanged position
RoomPeer.GONE_TEXT = "%s has left\nthe room."

local function send(s, msg)
  local net = s.ls and s.ls.net
  if not net or net.closed then return false end
  return pcall(net.send, net, msg)
end

local function speaks(s)
  return (tonumber(s.peerV) or 1) >= RoomPeer.MIN_VERSION
end

-- ------------------------------------------------------------ room chat
--
-- The same surface WorldClient gives ChatOverlay / QuickChat (state, log,
-- say, emote, now), over the held session.  Lines are cleaned and capped by
-- WorldProtocol, rate-limited by the same bucket; both sides log locally.
function RoomPeer.chatAvailable(s)
  return s ~= nil and s.roomMap ~= nil and not s.peerLeft
     and (tonumber(s.peerV) or 1) >= RoomPeer.CHAT_VERSION
end

function RoomPeer.chat(s)
  if s.chatClient then return s.chatClient end
  local P = require("src.online.world.WorldProtocol")
  local Chat = require("src.online.world.Chat")
  local Util = require("src.online.net.Util")
  local c = { log = Chat.log(30), chatBucket = Chat.bucket(), emoteCd = Chat.cooldown(P.EMOTE_COOLDOWN),
              members = {}, room = true }
  function c:now() return Util.time() end
  c.state = "in"
  local function myName()
    local okW, W = pcall(require, "src.online.world.OnlineWorld")
    return okW and W.playerName and W.playerName(s.game) or "YOU"
  end
  function c:say(text)
    text = P.cleanText(text, P.CHAT_MAX)
    if not text or not RoomPeer.chatAvailable(s) then return false, "nothing to say" end
    local ok, wait = self.chatBucket:take(self:now())
    if not ok then
      local line = ("Slow down! (%ds)"):format(math.ceil(wait))
      self.log:add({ kind = "notice", text = line, t = self:now() })
      return false, line
    end
    send(s, { type = "lr_chat", text = text })
    self.log:add({ kind = "chat", pid = 0, name = myName(), text = text, t = self:now() })
    return true
  end
  function c:emote(e)
    if not (P.EMOTE_SET[e] and RoomPeer.chatAvailable(s)) then return false end
    if not self.emoteCd:take(self:now()) then return false end
    send(s, { type = "lr_emote", e = e })
    return true
  end
  s.chatClient = c
  return c
end

-- the exchange said "same room" at the counter
function RoomPeer.linked(s)
  local ls = s.ls
  local game = s.game
  local ow = game and game.overworld
  s.homeMap = ow and ow.map and tostring(ow.map.id) or nil
  s.round = 0
  s.noGhost = s.noGhost or false
  -- a room peer plays on; a LINK-menu player is not in a room at all
  ls.keepRounds = speaks(s) and type(s.peerRoom) == "string"
    and not s.peerRoom:match("^mode:") and s.peerRoom ~= "any"
end

-- a message of ours, wherever it surfaced
function RoomPeer.take(s, msg)
  if msg.type == "lr_pos" then
    s.peerPos = { m = "@room", x = tonumber(msg.x) or 0, y = tonumber(msg.y) or 0,
                  f = msg.f, d = tonumber(msg.d) or 16, mv = "walk" }
    if type(msg.look) == "table" then
      s.peerLook = require("src.online.world.WorldProtocol").cleanLook(msg.look)
    end
  elseif msg.type == "lr_chat" then
    local P = require("src.online.world.WorldProtocol")
    local text = P.cleanText(msg.text, P.CHAT_MAX)
    if text then
      local c = RoomPeer.chat(s)
      local name = s.ls and s.ls.peerName or "?"
      local e = c.log:add({ kind = "chat", pid = RoomPeer.PID, name = name, text = text, t = c:now() })
      s.peerSaid = { text = text, at = c:now(), seq = (e and e.seq) or 0 }
    end
  elseif msg.type == "lr_emote" then
    local P = require("src.online.world.WorldProtocol")
    if P.EMOTE_SET[msg.e] then
      s.peerEmote = { e = msg.e, at = require("src.online.net.Util").time() }
    end
  elseif msg.type == "lr_ready" then
    s.peerRound = math.max(tonumber(s.peerRound) or 0, tonumber(msg.round) or 0)
  elseif msg.type == "lr_leave" then
    s.peerLeft = true
  end
end

-- out of the inbox, in order, leaving everything else queued for the LinkState.
-- Until the friend's lr_ready comes in, what else arrives is the closing words
-- of the last battle (a game says lr_ready after them, and sends nothing of the
-- next round before it has both), which a held session has no one to read.
RoomPeer.LEFTOVER = { bye = true, hash = true, action = true, state = true, replace = true, forfeit = true }

function RoomPeer.drain(s)
  local net = s.ls and s.ls.net
  local inbox = net and net.inbox
  if not inbox then return end
  for i = 1, #inbox do
    local m = inbox[i]
    if type(m) == "table" and (m.type == "lr_pos" or m.type == "lr_ready" or m.type == "lr_leave"
                               or m.type == "lr_chat" or m.type == "lr_emote") then
      RoomPeer.take(s, m)
      inbox[i] = false
    elseif type(m) == "table" and RoomPeer.LEFTOVER[m.type]
           and (tonumber(s.peerRound) or 0) < (tonumber(s.round) or 0) then
      inbox[i] = false
    end
  end
  local w = 1
  for i = 1, #inbox do
    local m = inbox[i]
    inbox[i] = nil
    if m then
      inbox[w] = m
      w = w + 1
    end
  end
end

-- the round is over on this side
function RoomPeer.roundOver(s)
  send(s, { type = "lr_ready", round = s.round })
  s.lastSent = nil
end

function RoomPeer.sayLeaving(s)
  if speaks(s) then send(s, { type = "lr_leave" }) end
end

function RoomPeer.clear(s)
  local g = s.ghost
  s.ghost = nil
  if not g then return end
  local ow = g.ow
  local list = ow and ow.entities
  for i = #(list or {}), 1, -1 do
    if list[i] == g.npc then table.remove(list, i) end
  end
end

local function inList(list, e)
  for _, x in ipairs(list or {}) do if x == e then return true end end
  return false
end

function RoomPeer.updateGhost(s, game, ow)
  local Presence = require("src.online.world.Presence")
  local pos = s.peerPos
  if not pos or s.noGhost then return RoomPeer.clear(s) end
  local g = s.ghost
  if g and g.ow ~= ow then RoomPeer.clear(s); g = nil end
  if g and g.mapId ~= ow.map.id then RoomPeer.clear(s); g = nil end
  local member = { pos = pos, look = s.peerLook, name = s.ls and s.ls.peerName or "?",
                   emote = s.peerEmote }
  if not g then
    g = Presence.makeRoomGhost(game, ow, RoomPeer.PID, member)
    if not g then return end
    g.mapId = ow.map.id
    s.ghost = g
  end
  g.member = member
  if s.peerSaid then g.said = s.peerSaid end
  pcall(Presence.refreshGhostSprite, game, g, pos.mv)
  local t = require("src.online.net.Util").time()
  Presence.steerGhost(g, pos, t)
  Presence.animateGhost(g, t)
  ow.entities = ow.entities or {}
  if not inList(ow.entities, g.npc) then table.insert(ow.entities, g.npc) end
end

-- the arrival: the two players do not stand on one cell (the cartridge starts
-- them a cell apart by link id; the scripts name the host's)
local function arrivalShift(s, ow)
  local dx = tonumber(s.arrivalShift)
  s.arrivalShift = nil
  if not dx or not s.ls or s.ls.isHost then return end
  local p = ow.player
  if p and p.cellX and not p.moving then
    p.cellX = p.cellX + dx
    p.px = p.cellX * 16
  end
end

-- one tick of a held session
function RoomPeer.tick(s, dt, LinkRooms)
  RoomPeer.drain(s)
  local game = s.game
  local ow = game and game.overworld
  if not (ow and ow.map and ow.player and s.homeMap) then return end
  local id = tostring(ow.map.id)
  if not s.roomMap then
    if id == s.homeMap then return end
    s.roomMap = id
    arrivalShift(s, ow)
  elseif id ~= s.roomMap then
    -- out of the room: the link ends here whichever way they went
    RoomPeer.clear(s)
    if LinkRooms.session == s then LinkRooms.close() end
    return
  end
  local net = s.ls and s.ls.net
  if s.peerLeft or (net and (net.closed or net.error)) then
    local Strings = require("src.core.Strings")
    local name = s.ls and s.ls.peerName or Strings("Your friend")
    RoomPeer.clear(s)
    if LinkRooms.session == s then LinkRooms.close() end
    LinkRooms.notice = { game = game, map = ow.map.id, text = Strings(RoomPeer.GONE_TEXT, name) }
    return
  end
  if not speaks(s) then return end
  -- publish
  local Presence = require("src.online.world.Presence")
  local pos = Presence.localPos(game, ow)
  if pos then
    local key = ("%d,%d,%s"):format(pos.x, pos.y, tostring(pos.f))
    s.sentAge = (s.sentAge or 0) + (dt or 0)
    if key ~= s.lastSent or s.sentAge > RoomPeer.HEARTBEAT then
      s.lastSent, s.sentAge = key, 0
      send(s, { type = "lr_pos", x = pos.x, y = pos.y, f = pos.f, d = pos.d,
                look = Presence.localLook(game, ow) })
    end
  end
  RoomPeer.updateGhost(s, game, ow)
end

return RoomPeer
