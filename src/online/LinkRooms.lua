-- THE IN-GAME LINK ROOMS (docs/online-design.md 2.7, workstreams WS6a/WS6b).
--
-- One door every cartridge script uses to reach link play.  The script keeps
-- its own success and failure branches and its own text: this module only
-- answers "did it link", and the caller writes that answer into whatever
-- variable its script reads (wScriptVar, VAR_RESULT, a Gen 4 dest var).
--
--   LinkRooms.open(game, room, opts, onDone)
--       room   "trade" | "battle" | "timecapsule" | "any"
--              ("any": the host picks TRADE or BATTLE, as on the LINK menu)
--       opts.role   "host" | "join" | nil     (nil: the LINK menu's HOST/JOIN)
--       opts.phase  "full" (default)  the whole link runs here and ends
--                   "connect"         stop once the two games are connected
--                                     and have told each other which room
--                                     they asked for; the session is held
--                                     (ticked) until LinkRooms.resume
--       onDone(result)   "done"      a trade / battle finished
--                        "linked"    (connect) connected, same room
--                        "mismatch"  (connect) connected, different rooms
--                        "cancelled" the player backed out
--                        "failed"    the link broke / errored
--                        "noconnect" no link stack on this build
--
--   LinkRooms.resume(game, onDone)   at the seat: the held session goes on
--                                    into its trade or battle ("nosession"
--                                    when nothing is held)
--                                    A room's session stays held after a
--                                    battle or trade (more than one per visit):
--                                    the next seat goes round again, and leaving
--                                    the room ends it (src/online/LinkRoomPeer.lua
--                                    also walks the other player's avatar).
--   LinkRooms.close()                CloseLink: drop a held session
--   LinkRooms.pending()              the held session, or nil
--   LinkRooms.gts(game, opts, onDone)    WS7's GtsClient.open
--                                        ("done"|"noconnect"|"denied"|"closed")
--   LinkRooms.union(game, onDone)    the Union Room: the players of the world
--                                    you are in (WS8 invites), or a link code
--   LinkRooms.await(ctx, fn)         run fn(onDone) and park the script's
--                                    coroutine until it answers
--
-- THE CARTRIDGE'S FLOW, KEPT.  A receptionist links ("connect"), the script
-- walks the player into the Trade Center / Colosseum on its own rows, and
-- the seat's special resumes the session, so the trade or battle runs in the
-- room.  Where the room is beyond the port (Gen 4/5 colosseums are C-driven),
-- the receptionist runs the whole link ("full") and the script goes on from
-- its own answer.
--
-- LinkState (WS4) is used through its API: LinkState.new(game, opts) with
-- opts.holdOnConnect (hold the connected session for the seat, or pick the
-- host's TRADE / BATTLE from the room with LinkState:chooseMode),
-- opts.expectMode, opts.onExit and opts.ignore (the room exchange's own
-- messages).
--
-- Tests: LinkRooms.fake = function(kind, room, opts) -> result answers every
-- open/resume/gts/union at once, with no screen.

local Strings = require("src.core.Strings")
local RoomPeer = require("src.online.LinkRoomPeer")

local LinkRooms = {}

LinkRooms.fake = nil
LinkRooms.session = nil        -- the held ("connect") session
LinkRooms.last = nil           -- { room, peerRoom, result, peerGen } of the last connect
LinkRooms.EXCHANGE_TIMEOUT = 45
LinkRooms.HELLO_GRACE = 3      -- a peer that is not in a room says nothing
LinkRooms.HOOK_OWNER = "linkrooms"

-- the mode a room's session runs
LinkRooms.ROOM_MODE = {
  trade = "trade", timecapsule = "trade", battle = "battle", colosseum = "battle",
  battle2 = "battle",   -- a DOUBLE BATTLE room (Gen 3+: WS5's rules picker)
}

local function log(fmt, ...)
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and Logger then Logger.info("linkrooms: " .. fmt, ...) end
end

function LinkRooms.available()
  local ok, Net = pcall(require, "src.link.Net")
  if not ok then return false end
  local okA, yes = pcall(Net.available)
  return okA and yes and true or false
end

-- two rooms that may meet: the same room, or either side not in one
function LinkRooms.compatible(mine, theirs)
  if mine == nil or theirs == nil or mine == "any" or theirs == "any" then return true end
  if mine == theirs then return true end
  -- a peer that is not in a room but has already picked a mode on its LINK
  -- screen ("mode:trade") meets the room of that mode
  local m = type(theirs) == "string" and theirs:match("^mode:(%a+)$")
  if m then return (LinkRooms.ROOM_MODE[mine] or mine) == m end
  return false
end

-- -------------------------------------------------------------- the waiter
--
-- An invisible state under the LinkState.  When everything the link pushed
-- has come off the stack (the screen, its closing text, a trade movie, an
-- evolution) the waiter is the top again and answers.  It also holds the
-- room exchange of a "connect" session, drawn as one small window.

local Waiter = {}
Waiter.__index = Waiter
Waiter.isOpaque = false

local function newWaiter(game, finish)
  return setmetatable({ game = game, finish = finish, mode = "link", t = 0 }, Waiter)
end

function Waiter:uiSize()
  local ok, CodeStyle = pcall(require, "src.ui.online.CodeStyle")
  if ok then return CodeStyle.surface({}) end
  return 160, 144
end

function Waiter:update(dt)
  LinkRooms.tick(dt)
  if self.mode == "exchange" then return self:exchange(dt or 0) end
  if self.mode == "ready" then return self:waitReady(dt or 0) end
  if self.game.stack:top() ~= self then return end
  self.game.stack:pop()
  self.finish()
end

-- the second round on: the friend is still on their last battle's closing
-- screens.  Nothing goes out until they are back in the room, so their
-- battle's loop can't swallow this round's hello.
function Waiter:waitReady(dt)
  self.t = self.t + dt
  local s = self.session
  if LinkRooms.session ~= s then
    self.game.stack:pop()
    return self.finish("failed")
  end
  self.peerName = s.ls and s.ls.peerName
  if (s.peerRound or 0) >= (s.round or 0) then
    LinkRooms.session = nil
    self.mode = "link"
    self.game.stack:push(s.ls)
    return
  end
  local input = self.game.input
  if input and input.wasPressed and input:wasPressed("b") then
    self.game.stack:pop()
    return self.finish("cancelled")
  end
end

function Waiter:draw()
  if self.mode ~= "exchange" and self.mode ~= "ready" then return end
  local ok, CodeStyle = pcall(require, "src.ui.online.CodeStyle")
  if not ok then return end
  local style = self.style or CodeStyle.new(CodeStyle.defaultKind(self.game))
  self.style = style
  local w, h = self:uiSize()
  local lh = style:lineHeight()
  local boxH = lh * 2 + 16
  local y = h - boxH
  style:box(0, y, w, boxH)
  local dots = ("..."):sub(1, 1 + math.floor((self.t * 2) % 3))
  style:text(Strings("Waiting for %s", self.peerName or Strings("your friend")) .. dots,
             8, y + 8)
  style:text(Strings("B: cancel"), 8, y + 8 + lh, CodeStyle.colors.dim)
end

-- the two rooms are compared before the walk in, as CheckBothSelectedSameRoom
-- / LINKUP_DIFF_SELECTIONS do on the cartridge
function Waiter:exchange(dt)
  self.t = self.t + dt
  local s = self.session
  local net = s and s.ls and s.ls.net
  if not net then return self:endExchange("failed") end
  if not s.sentRoom then
    s.sentRoom = true
    pcall(net.send, net, { type = "lr_room", room = s.room, v = RoomPeer.VERSION })
  end
  pcall(net.update, net)
  -- take only our own messages; everything else stays queued, in order, for
  -- the LinkState that resumes at the seat
  local inbox = net.inbox or {}
  local keep = {}
  for _, msg in ipairs(inbox) do
    if type(msg) == "table" and msg.type == "lr_room" then
      s.peerRoom = msg.room or "any"
      s.peerV = tonumber(msg.v) or 1
    else
      if type(msg) == "table" and msg.type == "hello" then
        s.peerHelloAt = s.peerHelloAt or self.t
        s.ls.peerName = s.ls.peerName or msg.name
        if msg.mode and s.peerRoom == nil then s.peerRoom = "mode:" .. tostring(msg.mode) end
      end
      keep[#keep + 1] = msg
    end
  end
  if net.inbox then
    for i = #net.inbox, 1, -1 do net.inbox[i] = nil end
    for i, msg in ipairs(keep) do net.inbox[i] = msg end
  end
  self.peerName = s.ls.peerName
  if s.peerRoom == nil and s.peerHelloAt and self.t - s.peerHelloAt > LinkRooms.HELLO_GRACE then
    s.peerRoom = "any" -- a LINK-menu peer, not standing at a counter
  end
  if s.peerRoom ~= nil then
    return self:endExchange(LinkRooms.compatible(s.room, s.peerRoom) and "linked" or "mismatch")
  end
  if net.closed or net.error then return self:endExchange("failed") end
  local input = self.game.input
  if (input and input.wasPressed and input:wasPressed("b")) or self.t > LinkRooms.EXCHANGE_TIMEOUT then
    return self:endExchange(self.t > LinkRooms.EXCHANGE_TIMEOUT and "failed" or "cancelled")
  end
end

function Waiter:endExchange(result)
  local s = self.session
  local ls = s and s.ls
  LinkRooms.last = {
    room = s and s.room, peerRoom = s and s.peerRoom, result = result,
    peerGen = ls and ls.peerHello and tonumber(ls.peerHello.gen) or nil,
    isHost = ls and ls.isHost or false, peerName = ls and ls.peerName,
  }
  if result ~= "linked" then LinkRooms.close() end
  if result == "linked" then RoomPeer.linked(s) end
  self.mode = "done"
  if self.game.stack:top() == self then self.game.stack:pop() end
  self.finish(result)
end

-- -------------------------------------------------------------- LinkState

-- the host's pick, made for it from the room (LinkState:chooseMode, what its
-- mode menu's A does)
function LinkRooms.chooseMode(ls, mode)
  return ls:chooseMode(mode)
end

-- what the session came to, read off the screen's own fields
local function outcome(ls)
  if ls._lrResult then return ls._lrResult end
  if ls.mismatch then return "mismatch" end
  if ls.trade and ls.trade.stage == "done" then return "done" end
  if ls.transfer and ls.transfer.stage == "done" then return "done" end
  if ls._lrExit then
    local e = ls._lrExit
    if e.reason == "done" then return "done" end
    if e.stage == "battleRunning" then return "done" end
    if e.message == nil then return "cancelled" end
    if ls.trade and ls.trade.stage == "cancelled" and not ls.trade.error then return "cancelled" end
    if e.stage == "notice" then return "cancelled" end
    return "failed"
  end
  return "cancelled"
end

-- LinkState's hooks for a room session (LinkState.new opts)
local function hooksFor(session)
  return {
    -- the room exchange is ours: never let a LinkState stage swallow it
    ignore = {
      -- (the friend's can beat this side's hold by a frame: it still counts)
      lr_room = function(m)
        session.peerRoom = m.room or "any"
        session.peerV = tonumber(m.v) or 1
      end,
      lr_pos = function(m) RoomPeer.take(session, m) end,
      lr_ready = function(m) RoomPeer.take(session, m) end,
      lr_leave = function(m) RoomPeer.take(session, m) end,
      lr_chat = function(m) RoomPeer.take(session, m) end,
      lr_emote = function(m) RoomPeer.take(session, m) end,
    },
    -- a guest whose host picked the other mode: the rooms differ
    expectMode = session.mode,
    onExit = function(self, message, reason)
      self._lrExit = { message = message, reason = reason, stage = self.stage }
    end,
    -- connected: a "connect" session is held for the seat; otherwise the
    -- host's TRADE / BATTLE is the room's
    holdOnConnect = function(self)
      if session.phase == "connect" then
        LinkRooms._hold(self, session)
        return true
      end
      if self.stage == "modeSelect" and session.mode then
        self:chooseMode(session.mode)
        return true
      end
      return false
    end,
    -- a battle or trade ended: a room's session stays for the next
    onRoundEnd = function(self, kind)
      if not self.keepRounds or LinkRooms.session then return false end
      if not self.net or self.net.closed or self.net.error then return false end
      LinkRooms._rearm(self, session, kind)
      return true
    end,
  }
end

-- connected, and this is a "connect" session: off the stack, and the waiter
-- under it takes the room exchange
function LinkRooms._hold(ls, session)
  local game = ls.game
  if game.stack:top() == ls then game.stack:pop() end
  session.phase = "held"
  LinkRooms.session = session
  LinkRooms.ensureHooks()
  local w = session.waiter
  w.mode = "exchange"
  w.session = session
  w.t = 0
  log("connected (%s); room %s, waiting for the other room", ls.isHost and "host" or "guest",
      tostring(session.room))
end

-- the round is over and both games are still linked: back under the seat's
-- waiter (which answers "done" once the closing screens are off), held for
-- the next round
function LinkRooms._rearm(ls, session, kind)
  local game = ls.game
  -- what the battle's own loop caught while it was closing
  for _, msg in ipairs(ls.battle and ls.battle.pendingTournamentMessages or {}) do
    if type(msg) == "table" then RoomPeer.take(session, msg) end
  end
  ls.battle, ls.trade, ls.confirmed = nil, nil, nil
  ls.index = 1
  ls._lrResult = "done"
  ls.stage = ls.isHost and "modeSelect" or "waitMode"
  session.round = (session.round or 0) + 1
  session.phase = "held"
  LinkRooms.session = session
  LinkRooms.ensureHooks()
  RoomPeer.roundOver(session)
  if game.stack:top() == ls then game.stack:pop() end
  log("%s over; the link stays (round %d)", tostring(kind), session.round)
end

function LinkRooms.open(game, room, opts, onDone)
  opts = opts or {}
  onDone = onDone or function() end
  room = room or "any"
  if LinkRooms.fake then
    local r = LinkRooms.fake("open", room, opts)
    if r == "linked" then
      LinkRooms.session = { room = room, fake = true, mode = LinkRooms.ROOM_MODE[room] }
      LinkRooms.last = { room = room, peerRoom = room, result = r, isHost = opts.role ~= "join",
                         peerGen = opts.fakePeerGen }
    end
    return onDone(r)
  end
  if not (game and game.stack) or not LinkRooms.available() then return onDone("noconnect") end
  if LinkRooms.session then LinkRooms.close() end
  local okL, LinkState = pcall(require, "src.link.LinkState")
  if not okL then
    log("no LinkState: %s", tostring(LinkState))
    return onDone("noconnect")
  end
  local session = { room = room, mode = LinkRooms.ROOM_MODE[room], phase = opts.phase or "full",
                    game = game, arrivalShift = opts.arrivalShift, noGhost = opts.noGhost }
  local ls = LinkState.new(game, hooksFor(session))
  session.ls = ls
  local answered = false
  local waiter = newWaiter(game, function(result)
    if answered then return end
    answered = true
    if LinkRooms.session == session and result ~= "linked" then LinkRooms.session = nil end
    onDone(result or outcome(ls))
  end)
  session.waiter = waiter
  -- the battle format the room stands for, preset on the host's rules
  -- picker (LinkState's own `ruleChoice`, read by ruleChoices())
  local format = opts.format or (room == "battle2" and "double") or nil
  if format then
    ls.ruleChoice = { format = format, flat = false, species = false, item = false, sleep = false }
  end
  game.stack:push(waiter)
  game.stack:push(ls)
  if opts.role == "host" then
    ls:startHost(opts.note)
  elseif opts.role == "join" then
    -- JOIN's first page: nearby games, or ENTER A CODE
    if ls.openJoinList then ls:openJoinList() else ls:openJoinEntry() end
  end
  return ls
end

function LinkRooms.pending() return LinkRooms.session end

function LinkRooms.resume(game, onDone)
  onDone = onDone or function() end
  local s = LinkRooms.session
  if LinkRooms.fake then
    LinkRooms.session = nil
    if not s then return onDone("nosession") end
    return onDone(LinkRooms.fake("resume", s.room, {}))
  end
  if not (s and s.ls and game and game.stack) then return onDone("nosession") end
  local ls = s.ls
  s.phase = "full"
  ls._lrResult, ls._lrExit = nil, nil
  local answered = false
  local waiter = newWaiter(game, function()
    if answered then return end
    answered = true
    onDone(outcome(ls))
  end)
  s.waiter = waiter
  game.stack:push(waiter)
  -- again: wait for the friend to be back from the last round
  if (s.round or 0) > (s.peerRound or 0) then
    waiter.mode, waiter.session, waiter.t = "ready", s, 0
    return ls
  end
  LinkRooms.session = nil
  game.stack:push(ls)
  return ls
end

function LinkRooms.close()
  local s = LinkRooms.session
  LinkRooms.session = nil
  LinkRooms.watch = nil
  if not s or s.fake then return end
  local ls = s.ls
  if not ls then return end
  RoomPeer.clear(s)
  if ls.net then
    RoomPeer.sayLeaving(s)
    pcall(ls.net.send, ls.net, { type = "bye" })
    pcall(ls.net.close, ls.net)
  end
  pcall(ls.closeLinkJobs, ls)
  if ls.game then ls.game.linkSession = nil end
  local okR, Runtime = pcall(require, "src.mods.Runtime")
  if okR then pcall(Runtime.emit, "link.ended", { reason = "bye" }) end
end

-- keep a held session's socket serviced (ENet times a silent peer out), and
-- watch the room's battle spots
function LinkRooms.tick(dt)
  local s = LinkRooms.session
  if s and s.ls and s.ls.net then pcall(s.ls.net.update, s.ls.net) end
  if s then
    local ok, err = pcall(RoomPeer.tick, s, dt or 1 / 60, LinkRooms)
    if not ok then log("room peer: %s", tostring(err)) end
  end
  if LinkRooms.watch then LinkRooms.checkSpots() end
  if LinkRooms.notice then LinkRooms.showNotice() end
end

-- ------------------------------------------------------------ the room's spots
--
-- Gen 4's colosseums have no seat script: the field's comm task
-- (pokeplatinum field_comm_manager.c, FieldCommTask_WaitBattleRoomMovement /
-- comm_player_manager.c sub_020590C4) starts the battle once the players
-- stand on the room's spots -- (4,7) and (11,7) in the two-player room.
-- Here the held session resumes when this player steps onto a spot: the
-- other side's screen waits for its partner's hello or party as the
-- cartridge's waits for its partner to take position.
--   LinkRooms.watchSpots(game, { map = id, spots = { {x, y}, ... },
--                                onSeat = function(result) end })

LinkRooms.SPOTS_2P = { { 4, 7 }, { 11, 7 } }

function LinkRooms.watchSpots(game, spec)
  LinkRooms.watch = { game = game, map = spec.map, spots = spec.spots or LinkRooms.SPOTS_2P,
                      onSeat = spec.onSeat, stepOff = spec.stepOff }
  LinkRooms.ensureHooks()
  log("watching the battle spots of %s", tostring(spec.map))
end

function LinkRooms.checkSpots()
  local w = LinkRooms.watch
  local game = w and w.game
  local ow = game and game.overworld
  if not (ow and ow.map and ow.player and game.stack) then return end
  if ow.map.id ~= w.map then
    if w.arrived then LinkRooms.watch = nil end   -- left the room
    return
  end
  w.arrived = true
  if not LinkRooms.session then return end
  if game.stack:top() ~= ow then return end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return end
  local p = ow.player
  if p.moving or (p.isMoving and p:isMoving()) then return end
  for _, spot in ipairs(w.spots) do
    if p.cellX == spot[1] and p.cellY == spot[2] then
      -- the round just played: step off and back on for the next
      if w.stepOff then return end
      LinkRooms.watch = nil
      log("on the battle spot (%d,%d)", spot[1], spot[2])
      LinkRooms.resume(game, function(result)
        if w.onSeat then w.onSeat(result) end
      end)
      return
    end
  end
  w.stepOff = nil
end

-- a line for the player, when the field is free to show it (the friend left
-- the room while this player was walking around it)
function LinkRooms.showNotice()
  local n = LinkRooms.notice
  local game = n and n.game
  local ow = game and game.overworld
  if not (ow and game.stack) or (ow.map and ow.map.id ~= n.map) then LinkRooms.notice = nil return end
  if game.stack:top() ~= ow or (ow.runner and ow.runner.isRunning and ow.runner:isRunning()) then return end
  LinkRooms.notice = nil
  game.stack:push(require("src.render.TextBox").new(game, n.text))
end

function LinkRooms.ensureHooks()
  local okR, Runtime = pcall(require, "src.mods.Runtime")
  if not okR then return end
  local hooks = Runtime.hooks
  if not (hooks and hooks.wrap) or hooks == LinkRooms._hooks then return end
  LinkRooms._hooks = hooks
  hooks:wrap("input.step", function(nextFn, game, dt)
    if LinkRooms.session or LinkRooms.watch or LinkRooms.notice then LinkRooms.tick(dt) end
    return nextFn(game, dt)
  end, -999, LinkRooms.HOOK_OWNER)
end

-- -------------------------------------------------------------- GTS

function LinkRooms.gts(game, opts, onDone)
  opts = opts or {}
  onDone = onDone or function() end
  if LinkRooms.fake then return onDone(LinkRooms.fake("gts", "gts", opts)) end
  local okG, GtsClient = pcall(require, "src.online.gts.GtsClient")
  if not (okG and game and game.stack) then return onDone("noconnect") end
  local answered = false
  local ok, err = pcall(GtsClient.open, game, {
    noConnectText = opts.noConnectText,
    onDone = function(result)
      if answered then return end
      answered = true
      onDone(result or "closed")
    end,
  })
  if not ok then
    log("GTS failed to open: %s", tostring(err))
    if not answered then answered = true; onDone("noconnect") end
  end
end

-- -------------------------------------------------------------- Union Room
--
-- The cartridge's Union Room is a room of other players to walk up to.  Here
-- it is the players of the world you are in (WS8: the invite goes through
-- their GhostInteract window and becomes a relayed link session), or a link
-- code for a friend, TRADE or BATTLE picked by the host.

local Union = {}
Union.__index = Union
Union.isOpaque = true
-- in the Union Room this screen IS the field: a world invite comes up over
-- it (OnlineWorld.canInterrupt)
Union.acceptsInvites = true
-- ...and it is one room for every player on it, whatever map their game is
-- on (the Gen 3 Union Room is a map of its own, the Gen 4 one is the 2F):
-- the world's "near enough to invite" is this room (Presence.localPos)
Union.presenceRoom = "@union"

function Union:uiSize()
  local ok, CodeStyle = pcall(require, "src.ui.online.CodeStyle")
  if ok then return CodeStyle.surface({}) end
  return 160, 144
end

function Union:rows()
  local rows = {}
  local okW, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
  local client = okW and OnlineWorld.client and OnlineWorld.client() or nil
  if client and client.members then
    -- the world overlay scoped to this room (docs/online-design.md 2.8): the
    -- members standing in a Union Room; the rest of the world is out there
    local pids = {}
    for pid, m in pairs(client.members) do
      if pid ~= client.you and m.pos and m.pos.m == self.presenceRoom then pids[#pids + 1] = pid end
    end
    table.sort(pids)
    for _, pid in ipairs(pids) do
      rows[#rows + 1] = { label = tostring(client.members[pid].name or "?"), pid = pid }
    end
  end
  if client and LinkRooms.multiAvailable(self.game) then
    -- the 4-player multi battle over the world's "multi" relay service
    -- (src/online/MultiBattle.lua): LEAD opens the lobby, JOIN finds it
    rows[#rows + 1] = { label = Strings("MULTI: LEAD"), multi = "host" }
    rows[#rows + 1] = { label = Strings("MULTI: JOIN"), multi = "join" }
  end
  rows[#rows + 1] = { label = Strings("LINK CODE"), code = true }
  rows[#rows + 1] = { label = Strings("EXIT"), exit = true }
  return rows, client ~= nil
end

function Union:update(dt)
  -- the world goes on while the room is up, as every world screen pumps it
  -- (a hook reinstalled by a map change must not leave it silent)
  local okW, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
  if okW and OnlineWorld.tick then pcall(OnlineWorld.tick, dt or 1 / 60) end
  local input = self.game.input
  local rows = self:rows()
  if self.index > #rows then self.index = #rows end
  if input:wasPressed("down") then
    self.index = self.index % #rows + 1
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % #rows + 1
  elseif input:wasPressed("b") then
    self.game.stack:pop(); self.onDone("closed")
  elseif input:wasPressed("a") then
    local row = rows[self.index]
    if row.exit then
      self.game.stack:pop(); self.onDone("closed")
    elseif row.code then
      LinkRooms.open(self.game, "any", {}, function(r) self.lastResult = r end)
    elseif row.multi then
      local okM, MultiBattle = pcall(require, "src.online.MultiBattle")
      if okM then
        local me = self
        local okO, err = pcall(MultiBattle.open, self.game, { world = true, role = row.multi },
          { role = row.multi }, function(r) me.lastResult = r end)
        if not okO then log("multi did not open: %s", tostring(err)) end
      end
    elseif row.pid then
      local okG, GhostInteract = pcall(require, "src.ui.online.GhostInteract")
      if okG then GhostInteract.open(self.game, row.pid) end
    end
  end
end

-- a multi needs the Gen 3-5 multi battle and a world that relays it
function LinkRooms.multiAvailable(game)
  local okM, MultiBattle = pcall(require, "src.online.MultiBattle")
  if not (okM and type(MultiBattle) == "table" and MultiBattle.open) then return false end
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if okV and GameVersion.isGen3 and not (GameVersion.isGen3() or GameVersion.isGen4()
                                         or GameVersion.isGen5()) then
    return false
  end
  return true
end

function Union:draw()
  local ok, CodeStyle = pcall(require, "src.ui.online.CodeStyle")
  if not ok then return end
  local style = self.style or CodeStyle.new(CodeStyle.defaultKind(self.game))
  self.style = style
  local w, h = self:uiSize()
  local lh = style:lineHeight()
  style:clear(w, h)
  style:box(0, 0, w, h)
  style:text(Strings("UNION ROOM"), 12, 10)
  local rows, inWorld = self:rows()
  local y = 10 + lh * 2
  for i, row in ipairs(rows) do
    if i == self.index then
      -- a drawn pointer: not every cartridge font has a ">" glyph
      style:setColor(CodeStyle.colors.ink)
      love.graphics.polygon("fill", 9, y + 1, 9, y + lh - 1, 9 + math.floor(lh / 2), y + lh / 2)
      love.graphics.setColor(1, 1, 1, 1)
    end
    style:text(row.label, 18, y)
    y = y + lh + 2
  end
  local note = inWorld and (rows[1] and rows[1].pid and Strings("Pick a player to TRADE or BATTLE.")
                            or Strings("Nobody else from your world is in a Union Room yet."))
    or Strings("Join a world to meet players here, or use a link code.")
  local lines = style:wrap(note, w - 24)
  local ny = h - 10 - lh * #lines
  for i, line in ipairs(lines) do style:text(line, 12, ny + (i - 1) * lh, CodeStyle.colors.dim) end
end

function LinkRooms.union(game, onDone)
  onDone = onDone or function() end
  if LinkRooms.fake then return onDone(LinkRooms.fake("union", "union", {})) end
  if not (game and game.stack) or not LinkRooms.available() then return onDone("noconnect") end
  local self = setmetatable({ game = game, index = 1, onDone = onDone }, Union)
  game.stack:push(self)
  return self
end
LinkRooms.Union = Union

-- -------------------------------------------------------------- scripts

-- fn(onDone) starts something that answers once; the script waits for it.
-- An answer given at once (a fake, no link stack) does not yield at all.
function LinkRooms.await(ctx, fn)
  local runner = ctx and ctx.runner
  local done, result, parked = false, nil, false
  fn(function(r)
    if done then return end
    done, result = true, r
    if parked and runner then runner:resume() end
  end)
  if not done and runner then
    parked = true
    runner:yield()
  end
  return result
end

return LinkRooms
