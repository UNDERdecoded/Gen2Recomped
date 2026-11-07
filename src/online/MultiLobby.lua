-- THE MULTI BATTLE LOBBY (src/online/MultiBattle.lua's front door).
--
-- Four players gather, the leader sets the two teams, everyone picks their
-- Pokemon, the battle runs, the screen hands back the result:
--
--   MultiLobby.open(game, session, opts, onDone) -> lobby   (pushed)
--
--   session  nil                    the leader shows a HOST CODE (WS1
--                                   Connector.host, maxPeers 3, WS2 code);
--                                   a player types it (LongCodeEntry)
--            { role, transport }    an open WS1 Transport (the leader)
--            { role, channel }      a channel to the leader (a player)
--            { role, channels }     channels already open (the leader)
--            { role, world = true } the world's "multi" service (WS8,
--                                   MultiNet.relayService on the world host)
--            { role, invite }       a decoded invite to join
--   opts     role "host" | "join", rules (BattleRules; default the
--            generation's multi), preset, need (4; 2 for a co-op),
--            coop = { seats = { [1] = {...}, [3] = {...} } } (computer seats
--            the leader fills; the Subway's trainers), title, autoTeam
--            (drivers: the first n eligible), seed, onBattle(battle)
--   onDone(result, why)   "win" | "lose" | "draw" | "cancelled" | "failed"
--
-- Wire (all on the star, guest <-> leader):
--   -> mb_hello { hello, name }        <- mb_refuse { reason }
--   <- mb_roster { members = {{ name, seat, game }}, rules, need, phase }
--   <- mb_choose { rules }             -> mb_team { mons }
--   <- mb_start { seed, rules, seats, mySeat, strict, coop }
--   <- mb_cancel { reason }            -> mb_leave
-- A co-op lobby (the Subway) keeps its star after the battle: the caller
-- reads lobby.net / lobby.seat and runs more battles on it.

local BattleRules = require("src.online.BattleRules")
local MultiNet = require("src.online.MultiNet")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")

local MultiLobby = {}
MultiLobby.__index = MultiLobby
MultiLobby.isOpaque = true

-- default seats for the 2nd, 3rd and 4th player: the first to join is
-- the leader's partner (A+B vs C+D)
MultiLobby.JOIN_ORDER = { 2, 1, 3 }
MultiLobby.COOP_ORDER = { 2 }

local function gen()
  local GameVersion = require("src.core.GameVersion")
  return math.max(3, tonumber(GameVersion.generation and GameVersion.generation(GameVersion.get())) or 3)
end

local function playerName(game)
  return tostring(game and game.save and game.save.player and game.save.player.name or "PLAYER")
end

function MultiLobby.open(game, session, opts, onDone)
  opts = opts or {}
  session = session or {}
  local self = setmetatable({}, MultiLobby)
  self.game = game
  self.opts = opts
  self.onDone = onDone
  self.role = session.role or opts.role or "host"
  self.isHost = self.role == "host"
  self.rules = BattleRules.sanitize(opts.rules or BattleRules.multi(gen(), opts.preset), gen())
  self.coop = opts.coop
  self.need = tonumber(opts.need) or (self.coop and 2 or 4)
  self.members = {}
  self.pending = {}
  self.index = 1
  self.stage = "start"
  self.title = opts.title or (self.coop and "MULTI TRAIN" or "MULTI BATTLE")
  local okW, WorldUi = pcall(require, "src.ui.online.WorldUi")
  if okW then
    self.width, self.height = WorldUi.surface()
    self.style = WorldUi.style(game)
  end
  self.hello = require("src.link.Handshake").hello(game, "battle")
  if game and game.stack and not opts.headless then game.stack:push(self) end
  -- a counter that runs the whole room (the Colosseum receptionists, the
  -- Subway): LEADER (opens the room, shows the code) or JOIN (types it)
  local auto = os.getenv and os.getenv("MULTI_ROLE")
  if opts.askRole and not session.role and auto ~= "host" and auto ~= "join" then
    self.stage = "role"
    self.session = session
    self.index = 1
    return self
  end
  if opts.askRole and not session.role then
    self.role = auto
    self.isHost = auto == "host"
  end
  self:begin(session)
  return self
end

function MultiLobby:chooseRole(role)
  self.role = role
  self.isHost = role == "host"
  self.index = 1
  self:begin(self.session or {})
end

function MultiLobby:uiSize() return self.width or 256, self.height or 192 end

function MultiLobby:say(text) self.notice = text end

function MultiLobby:done(result, why)
  if self.finished then return end
  self.finished = true
  if not self.keep then self:closeNet() end
  -- (a battle's onFinish can run under its return transition: the lobby
  -- leaves the stack when it is on top again)
  if self.game.stack:top() == self then self.game.stack:pop() else self.popWhenTop = true end
  Logger.info("multi: lobby done (%s%s)", tostring(result), why and (": " .. tostring(why)) or "")
  if self.onDone then self.onDone(result, why) end
end

function MultiLobby:closeNet()
  if self.net then pcall(self.net.close, self.net) end
  for _, m in ipairs(self.pending) do if m.ch and m.ch.close then pcall(m.ch.close, m.ch) end end
  if self.source and self.source.close then pcall(self.source.close, self.source) end
  if self.hostJob then pcall(self.hostJob.close, self.hostJob) end
  if self.joinJob and self.joinJob.cancel and self.joinJob.state == "trying" then pcall(self.joinJob.cancel, self.joinJob) end
  if self.guestCh and self.guestCh.close and not self.net then pcall(self.guestCh.close, self.guestCh) end
end

function MultiLobby:cancel(why)
  if self.isHost then
    for _, m in ipairs(self.members) do
      if m.ch then m.ch:send({ type = "mb_cancel", reason = why or "The leader closed\nthe room." }) end
    end
  elseif self.guestCh then
    self.guestCh:send({ type = "mb_leave" })
  end
  self:done("cancelled", why)
end

-- ------------------------------------------------------------ starting

function MultiLobby:connectorOptions()
  local o = { port = 7777, portMap = true, lanBeacon = false, maxPeers = 3 }
  local ok, OW = pcall(require, "src.online.world.OnlineWorld")
  if ok and OW and OW.settingsOptions then
    local okS, s = pcall(OW.settingsOptions, self.game)
    if okS and type(s) == "table" then for k, v in pairs(s) do o[k] = v end end
  end
  for k, v in pairs(self.opts.connector or {}) do o[k] = v end
  o.maxPeers = math.max(2, self.need - 1)
  return o
end

function MultiLobby:begin(session)
  if self.isHost then
    self.members[1] = { seat = 0, name = playerName(self.game), me = true, hello = self.hello,
                        game = self.hello.game }
    if session.source then
      self.source = session.source
    elseif session.transport then
      self.source = MultiNet.transportSource(session.transport)
    elseif session.channels then
      self.source = MultiNet.listSource(session.channels)
    elseif session.world then
      local OW = require("src.online.world.OnlineWorld")
      self.stage = "opening"
      OW.serviceChannel("multi", function(ch, why)
        if not ch then self:done("failed", why or "no multi service") return end
        self.source = MultiNet.fromRelay(ch)
        self.stage = "gather"
      end)
      return
    else
      local Connector = require("src.online.net.Connector")
      self.hostJob = Connector.host(self:connectorOptions())
      self.stage = "opening"
      return
    end
    self.stage = "gather"
    return
  end
  -- a player
  if session.channel then
    self:attach(session.channel)
  elseif session.world then
    local OW = require("src.online.world.OnlineWorld")
    self.stage = "connecting"
    OW.serviceChannel("multi", function(ch, why)
      if not ch then self:done("failed", why or "no multi service") return end
      self:attach(ch)
    end)
  elseif session.invite or self.opts.invite then
    self:dial(session.invite or self.opts.invite)
  else
    self.stage = "code"
    local Util = require("src.online.net.Util")
    local lobby = self
    require("src.ui.online.LongCodeEntry").open(self.game, {
      title = "MULTI CODE", myLanIp = Util.lanIP(), allowShort = false,
      onDone = function(invite) lobby:dial(invite) end,
      onCancel = function() lobby:done("cancelled") end,
    })
  end
end

function MultiLobby:dial(invite)
  local Connector = require("src.online.net.Connector")
  local o = {}
  for k, v in pairs(self.opts.joinOptions or {}) do o[k] = v end
  self.joinJob = Connector.join(invite, o)
  self.stage = "connecting"
end

function MultiLobby:attach(ch)
  self.guestCh = ch
  self.stage = "hello"
  ch:send({ type = "mb_hello", hello = self.hello, name = playerName(self.game) })
end

-- ------------------------------------------------------------ the leader

function MultiLobby:seatTaken(seat)
  for _, m in ipairs(self.members) do if m.seat == seat then return m end end
  return nil
end

function MultiLobby:freeSeat()
  for _, s in ipairs(self.coop and MultiLobby.COOP_ORDER or MultiLobby.JOIN_ORDER) do
    if not self:seatTaken(s) then return s end
  end
  return nil
end

function MultiLobby:roster()
  local list = {}
  for _, m in ipairs(self.members) do
    list[#list + 1] = { name = m.name, seat = m.seat, game = m.game }
  end
  table.sort(list, function(a, b) return a.seat < b.seat end)
  return list
end

function MultiLobby:broadcastRoster()
  local msg = { type = "mb_roster", members = self:roster(), rules = self.rules, need = self.need,
                coop = self.coop and true or nil, phase = self.stage, leader = self.hello }
  for _, m in ipairs(self.members) do if m.ch then m.ch:send(msg) end end
end

function MultiLobby:admit(p, msg)
  local Handshake = require("src.link.Handshake")
  local LinkBattle = require("src.link.LinkBattle")
  local theirs = type(msg.hello) == "table" and msg.hello or {}
  local verdict, reason, pairInfo = Handshake.checkCompat(self.hello, theirs)
  local mode = LinkBattle.modeFor(verdict, pairInfo)
  local refuse
  if not mode then
    refuse = Strings("Can't battle with\nthat game.\n(%s)", tostring(reason or verdict))
  elseif tonumber(theirs.gen) ~= tonumber(self.hello.gen) then
    refuse = Strings("Multi battles need\ngames of one\ngeneration.")
  elseif self.stage ~= "gather" then
    refuse = Strings("The battle has\nalready begun.")
  end
  local seat = not refuse and self:freeSeat()
  if not refuse and not seat then refuse = Strings("The room is full.") end
  if refuse then
    p.ch:send({ type = "mb_refuse", reason = refuse })
    return false
  end
  local name = tostring(msg.name or theirs.name or "PLAYER"):sub(1, 12)
  self.members[#self.members + 1] = { seat = seat, name = name, ch = p.ch, hello = theirs,
                                      game = theirs.game, verdict = verdict }
  Logger.info("multi: %s joins as seat %d (%s, %s)", name, seat, tostring(theirs.game), tostring(verdict))
  self:broadcastRoster()
  return true
end

-- move a member to the other team (swapping with whoever stands there)
-- The leader keeps seat 0, so choosing the teams is choosing the leader's
-- partner: A on the partner (seat 2) sends them to team B (seat 1); A on
-- a team-B player makes them the partner.
function MultiLobby:swapTeam(member)
  if self.coop or not member or member.seat == 0 then return end
  local seat = member.seat
  local target = (seat == 2) and 1 or 2
  local other = self:seatTaken(target)
  if other then other.seat = seat end
  member.seat = target
  self:broadcastRoster()
end

function MultiLobby:canStart()
  return #self.members >= self.need
end

function MultiLobby:startChoosing()
  if not self:canStart() then return end
  self.stage = "choose"
  self.teams = {}
  for _, m in ipairs(self.members) do
    if m.ch then m.ch:send({ type = "mb_choose", rules = self.rules }) end
  end
  self:broadcastRoster()
  self:chooseTeam()
end

function MultiLobby:hostTeamIn(member, mons)
  if type(mons) ~= "table" then return end
  local ok, why = BattleRules.check(self.rules, BattleRules.team(self.rules, mons), self.game.data)
  if not ok then
    if member.ch then member.ch:send({ type = "mb_refuse", reason = why, retry = true }) end
    if member.me then self:say(why) self:chooseTeam() end
    return
  end
  member.team = mons
  self:hostMaybeStart()
end

function MultiLobby:hostMaybeStart()
  for _, m in ipairs(self.members) do if not m.team then return end end
  local seats = {}
  local Handshake = require("src.link.Handshake")
  local strict = true
  for _, m in ipairs(self.members) do
    seats[m.seat] = { name = m.name, party = m.team }
    if m.verdict and not Handshake.strict(m.verdict) then strict = false end
  end
  for seat, s in pairs((self.coop and self.coop.seats) or {}) do
    seats[seat] = { name = s.name, party = s.party, ai = true }
  end
  local seed = tonumber(self.opts.seed) or math.floor((os.time() % 100000) * 7 + (os.clock() * 1000) % 997) + 1
  local wireSeats = {}
  for c = 0, 3 do wireSeats[tostring(c)] = seats[c] end
  local links = {}
  -- opts.onReady: the caller runs its own battles on the star (the Battle
  -- Subway's train); everyone gets the teams instead of a battle
  local kind = self.opts.onReady and "mb_ready" or "mb_start"
  for _, m in ipairs(self.members) do
    if m.ch then
      links[m.seat] = m.ch
      m.ch:send({ type = kind, seed = seed, rules = self.rules, seats = wireSeats,
                  mySeat = m.seat, strict = strict })
    end
  end
  self.net = MultiNet.host(links)
  self.seat = 0
  self.startInfo = { seed = seed, rules = self.rules, seats = seats, strict = strict }
  if self.opts.onReady then
    self.stage = "after"
    self.keep = true
    return self.opts.onReady(self, self.startInfo)
  end
  self:startBattle(seats, 0, seed, self.rules, strict)
end

-- ------------------------------------------------------------ everyone

function MultiLobby:chooseTeam()
  local game = self.game
  local most = BattleRules.multiCount(self.rules)
  local party = game.save.party or {}
  local eligible = {}
  for i, mon in ipairs(party) do
    if not (mon.isEgg or mon.egg) then eligible[#eligible + 1] = i end
  end
  local n = math.min(most, #eligible)
  local lobby = self
  self.stage = "choose"
  local function picked(slots)
    if lobby.finished then return end
    if not slots or #slots == 0 then lobby:cancel() return end
    lobby:submitTeam(slots)
  end
  local auto = self.opts.autoTeam or (os.getenv and os.getenv("MULTI_AUTOPICK"))
  if auto or n == 0 then
    local slots = {}
    for k = 1, n do slots[k] = eligible[k] end
    return picked(slots)
  end
  local GameVersion = require("src.core.GameVersion")
  local ok = false
  if GameVersion.isGen4 and (GameVersion.isGen4() or (GameVersion.isGen5 and GameVersion.isGen5())) then
    ok = pcall(function()
      local PM = require("src.ui.Gen4PartyMenu")
      game.stack:push(PM.new(game, { select = { count = n, unique = self.rules.speciesClause or nil,
                                                 onDone = picked } }))
    end)
  else
    ok = pcall(function()
      require("src.ui.Screens").push(game, "PartyMenu", {
        chooseOrder = { most = n, least = n }, onOrder = picked,
      })
    end)
  end
  if not ok then
    local slots = {}
    for k = 1, n do slots[k] = eligible[k] end
    picked(slots)
  end
end

function MultiLobby:submitTeam(slots)
  local Protocol = require("src.link.Protocol")
  local peer = (not self.isHost) and self.leaderHello or nil
  local mons = Protocol.packParty(self.game.save.party, slots, { peerHello = peer })
  self.myTeam = mons
  self.stage = "wait"
  if self.isHost then
    self:hostTeamIn(self.members[1], mons)
  elseif self.guestCh then
    self.guestCh:send({ type = "mb_team", mons = mons })
  end
end

-- a battle on the lobby's star (the caller's own, after onReady)
function MultiLobby:battleOn(seats, seed, onResult, battleId)
  local MultiBattle = require("src.online.MultiBattle")
  local info = self.startInfo or {}
  local battle, why = MultiBattle.newBattle(self.game, self.net, {
    mySeat = self.seat, seats = seats, seed = seed, rules = info.rules or self.rules, strict = info.strict,
    keepNetOpen = true, replaceTimeout = self.opts.replaceTimeout, autoReplace = self.opts.autoReplace,
    battleId = battleId,
  })
  if not battle then return nil, why end
  battle.onFinish = function(result) if onResult then onResult(result, battle) end end
  if self.opts.onBattle then self.opts.onBattle(battle, self) end
  self.game.stack:push(battle)
  return battle
end

function MultiLobby:startBattle(seats, mySeat, seed, rules, strict)
  local MultiBattle = require("src.online.MultiBattle")
  local net = self.net
  local battle, why = MultiBattle.newBattle(self.game, net, {
    mySeat = mySeat, seats = seats, seed = seed, rules = rules, strict = strict,
    keepNetOpen = self.coop ~= nil or self.opts.keepNetOpen,
    replaceTimeout = self.opts.replaceTimeout, autoReplace = self.opts.autoReplace,
  })
  if not battle then
    self:done("failed", why)
    return
  end
  self.battle = battle
  self.stage = "battle"
  local lobby = self
  battle.onFinish = function(result)
    lobby.result = result
    lobby.lastBattle = battle
    if lobby.opts.onResult then lobby.opts.onResult(result, battle) end
    if not lobby.opts.stayOpen then lobby:done(result) end
  end
  if self.opts.onBattle then self.opts.onBattle(battle, self) end
  if self.game.stack.push then self.game.stack:push(battle) end
end

-- ------------------------------------------------------------ the loop

function MultiLobby:pump()
  if self.finished then return end
  -- the leader's code
  if self.hostJob then
    self.hostJob:update()
    if self.hostJob.state == "failed" then return self:done("failed", self.hostJob.reason) end
    if self.stage == "opening" and not self.hostJob.pending and self.hostJob.transport then
      local InviteCode = require("src.online.InviteCode")
      local okC, code = pcall(InviteCode.encode, self.hostJob:inviteFields())
      self.code = okC and code or nil
      self.source = MultiNet.transportSource(self.hostJob.transport)
      self.stage = "gather"
    end
  end
  if self.joinJob and self.stage == "connecting" then
    self.joinJob:update()
    if self.joinJob.state == "connected" then
      self:attach(self.joinJob.channel)
    elseif self.joinJob.state == "failed" then
      return self:done("failed", self.joinJob.reason)
    end
  end
  if self.isHost then self:pumpHost() else self:pumpGuest() end
end

function MultiLobby:pumpHost()
  if self.source and self.stage == "gather" then
    for _, ch in ipairs(self.source:take()) do
      self.pending[#self.pending + 1] = { ch = ch, since = os.clock() }
    end
  elseif self.source and self.source.update then
    pcall(self.source.update, self.source)
  end
  local keep = {}
  for _, p in ipairs(self.pending) do
    if p.ch.update then pcall(p.ch.update, p.ch) end
    local admitted
    for _, msg in ipairs(p.ch:poll()) do
      if msg.type == "mb_hello" and admitted == nil then admitted = self:admit(p, msg) end
    end
    if admitted == nil and not p.ch.closed then keep[#keep + 1] = p end
  end
  self.pending = keep
  if self.stage == "battle" or self.stage == "after" then return end
  for i = #self.members, 1, -1 do
    local m = self.members[i]
    if m.ch then
      if m.ch.update then pcall(m.ch.update, m.ch) end
      for _, msg in ipairs(m.ch:poll()) do
        if msg.type == "mb_team" and self.stage ~= "gather" then
          self:hostTeamIn(m, msg.mons)
        elseif msg.type == "mb_leave" then
          m.ch.closed = true
        end
      end
      if m.ch.closed then
        table.remove(self.members, i)
        Logger.info("multi: %s left the room", tostring(m.name))
        if self.stage ~= "gather" then
          -- someone left mid-choice: back to gathering
          self.stage = "gather"
          for _, o in ipairs(self.members) do o.team = nil end
          self:say(Strings("%s left.", m.name))
        end
        self:broadcastRoster()
      end
    end
  end
  if self.opts.autoStart and self.stage == "gather" and self:canStart() then self:startChoosing() end
end

function MultiLobby:pumpGuest()
  local ch = self.guestCh
  if not ch or self.stage == "battle" or self.stage == "after" then return end
  if ch.update then pcall(ch.update, ch) end
  local msgs = ch:poll()
  for i, msg in ipairs(msgs) do
    local t = msg.type
    if t == "mb_ready" or t == "mb_start" then
      -- what came after it belongs to the battle (or the caller's train):
      -- back into the channel for them
      local rest = {}
      for k = i + 1, #msgs do rest[#rest + 1] = msgs[k] end
      for _, m in ipairs(ch.inbox or {}) do rest[#rest + 1] = m end
      if ch.inbox then ch.inbox = rest end
    end
    if t == "mb_roster" then
      self.rosterList = msg.members
      if type(msg.leader) == "table" then self.leaderHello = msg.leader end
      if type(msg.rules) == "table" then self.rules = BattleRules.sanitize(msg.rules, gen()) end
      if self.stage == "hello" then self.stage = "gather" end
    elseif t == "mb_refuse" then
      if msg.retry then
        self:say(msg.reason)
        self:chooseTeam()
      else
        return self:done("failed", msg.reason)
      end
    elseif t == "mb_choose" then
      if type(msg.rules) == "table" then self.rules = BattleRules.sanitize(msg.rules, gen()) end
      self:chooseTeam()
    elseif t == "mb_cancel" then
      return self:done("cancelled", msg.reason)
    elseif t == "mb_ready" and self.opts.onReady then
      local seats = {}
      for c = 0, 3 do seats[c] = msg.seats and msg.seats[tostring(c)] end
      self.net = MultiNet.guest(ch)
      self.seat = tonumber(msg.mySeat) or 2
      self.startInfo = { seed = msg.seed, rules = BattleRules.sanitize(msg.rules, gen()), seats = seats,
                         strict = msg.strict == true }
      self.stage = "after"
      self.keep = true
      return self.opts.onReady(self, self.startInfo)
    elseif t == "mb_start" then
      local seats = {}
      for c = 0, 3 do seats[c] = msg.seats and msg.seats[tostring(c)] end
      self.net = MultiNet.guest(ch)
      self.seat = tonumber(msg.mySeat) or 2
      self.startInfo = { seed = msg.seed, rules = msg.rules, seats = seats, strict = msg.strict }
      return self:startBattle(seats, self.seat, tonumber(msg.seed) or 1,
                              BattleRules.sanitize(msg.rules, gen()), msg.strict == true)
    end
  end
  if ch.closed and not self.finished then self:done("failed", Strings("The link was\nlost.")) end
end

function MultiLobby:popIfDone()
  if self.finished then
    if self.popWhenTop and self.game.stack:top() == self then
      self.popWhenTop = nil
      self.game.stack:pop()
    end
    return true
  end
  return false
end

function MultiLobby:update(dt)
  if self:popIfDone() then return end
  self:pump()
  if self.finished then return end
  local input = self.game.input
  if not input then return end
  if self.stage == "role" then
    local WorldUi = require("src.ui.online.WorldUi")
    local rows = self:rows()
    self.index = WorldUi.nav(self.game, self.index, rows)
    if input:wasPressed("a") then
      local row = rows[self.index]
      if row.role then return self:chooseRole(row.role) end
      return self:cancel()
    elseif input:wasPressed("b") then
      return self:cancel()
    end
    return
  end
  if input:wasPressed("b") and (self.stage == "gather" or self.stage == "opening" or self.stage == "hello"
                                or self.stage == "connecting") then
    return self:cancel()
  end
  if self.isHost and self.stage == "gather" then
    local rows = self:rows()
    local WorldUi = require("src.ui.online.WorldUi")
    self.index = WorldUi.nav(self.game, self.index, rows)
    if input:wasPressed("a") then
      local row = rows[self.index]
      if row and row.start and self:canStart() then self:startChoosing()
      elseif row and row.member then self:swapTeam(row.member) end
    elseif input:wasPressed("start") and self:canStart() then
      self:startChoosing()
    elseif input:wasPressed("select") and self.code then
      pcall(function() love.system.setClipboardText(self.code) end)
      self:say("Code copied.")
    end
  end
end

-- ------------------------------------------------------------ drawing

function MultiLobby:rows()
  local rows = {}
  if self.stage == "role" then
    return { { label = "BECOME LEADER", role = "host" }, { label = "JOIN GROUP", role = "join" },
             { label = "CANCEL" } }
  end
  local list = self.isHost and self:roster() or (self.rosterList or {})
  local bySeat = {}
  for _, m in ipairs(list) do bySeat[m.seat] = m end
  local order = self.coop and { 0, 2 } or { 0, 2, 1, 3 }
  for _, seat in ipairs(order) do
    local m = bySeat[seat]
    local team = (seat % 2 == 0) and "A" or "B"
    local member
    if self.isHost and m then
      for _, x in ipairs(self.members) do if x.seat == seat then member = x end end
    end
    rows[#rows + 1] = { label = ("%s%d %s"):format(team, (seat < 2) and 1 or 2, m and m.name or "- - -"),
                        value = m and m.game or nil, member = member, disabled = not m }
  end
  if self.isHost then
    rows[#rows + 1] = { label = "START", start = true, disabled = not self:canStart() }
  end
  return rows
end

function MultiLobby:draw()
  local st = self.style
  if not st then return end
  local WorldUi = require("src.ui.online.WorldUi")
  local W, H = self:uiSize()
  st:clear(W, H)
  local text
  if self.stage == "opening" then
    text = "Opening the room..."
  elseif self.stage == "connecting" then
    text = "Connecting...\n" .. tostring(self.joinJob and self.joinJob.progress or "")
  elseif self.stage == "hello" then
    text = "Joining the room..."
  elseif self.stage == "choose" or self.stage == "wait" then
    text = self.stage == "wait" and "Waiting for the\nother players..." or "Choose your POKéMON."
  end
  local y = 4
  if text then
    y = y + WorldUi.drawText(st, 4, y, W - 8, text) + 2
  end
  if self.stage == "role" then
    WorldUi.drawList(st, 4, y, W - 8, self:rows(), self.index, self.title)
    return
  end
  if self.stage == "gather" or self.stage == "wait" or self.stage == "choose" then
    local extra = BattleRules.describe(self.rules):gsub("^MULTI%s*", "")
    local title = extra ~= "" and ("%s %s"):format(self.title, extra) or self.title
    local rows = self:rows()
    y = y + WorldUi.drawList(st, 4, y, W - 8, rows, self.isHost and self.index or 0, title) + 2
  end
  local foot
  if self.stage == "gather" then
    if self.isHost then
      foot = self.code and ("CODE " .. self.code) or nil
      local n = #self.members
      foot = (foot and (foot .. "\n") or "") .. ("%d/%d  A: team  START: go"):format(n, self.need)
    else
      foot = "Waiting for the leader..."
    end
  end
  if self.notice then foot = (foot and (foot .. "\n") or "") .. self.notice end
  if foot and y < H - 12 then WorldUi.drawText(st, 4, y, W - 8, foot) end
end

return MultiLobby
