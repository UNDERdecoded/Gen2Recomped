-- THE LINK SCREEN (docs/online-design.md 2.6, workstream WS4).
--
--   HOST        a DIRECT invite code (src/online/InviteCode.lua) for this
--               game's own socket (Connector.host: LAN address, the router
--               mapping, a typed public address), shown big by ShowCode with
--               the live state of the session under it.
--   JOIN        LongCodeEntry takes a direct code OR a six-symbol short code;
--               Connector.join walks the reachability ladder with progress,
--               and a failure lists why each way failed and offers the swap
--               ("you host instead": only the host has to be reachable).
--   SHORT CODE  a six-symbol room on the relay (the pokeserver protocol, or
--               the player's own Link Hub when one is set).
--   TOURNAMENT  the relay's brackets (src/link/Tournament.lua).
--   ADVANCED    the old way: show / type a LAN address.
--
-- THE RELAY CARRIES ONLY SHORT CODES AND TOURNAMENTS.  A direct code is
-- joined with the relay rung switched off and is never sent to it (it holds
-- the host's address); the relay rows vanish when `allowRelay` is off.
--
-- Once connected, the two hellos (handshake v3) decide what the pair may do,
-- the host picks TRADE or BATTLE, and the session runs over whatever channel
-- won -- Transport, the relay's TCP or the old Net -- through the same Net
-- API.  Settings come from save.options.online (LinkState.settings); the
-- SETTINGS screen that edits them is WS10's.

local DiscordPresence = require("src.core.DiscordPresence")
local Font = require("src.render.Font")
local Handshake = require("src.link.Handshake")
local Net = require("src.link.Net")
local Protocol = require("src.link.Protocol")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local TextBox = require("src.render.TextBox")
local Strings = require("src.core.Strings")

local LinkState = {}
LinkState.__index = LinkState
LinkState.isOpaque = true

local CURSOR = 0xED
local ANY = "ANY" -- sentinel: a leading nil array entry breaks ipairs under
                  -- LuaJIT even though # still reports the full size, so
                  -- the level picker cycles this string instead of nil,
                  -- converted to nil only on the wire (see levelForWire)
local FORCE_LEVEL_STEPS = { ANY, 50, 100 }

-- A cartridge line squeezed onto one row: its own break becomes a space, and
-- what will not fit is dropped rather than drawn past the edge.
local HINT_MAX = 30

local function oneLine(text)
  if not text or text == "" then return "" end
  text = tostring(text):gsub("[\n\v\f]+", " "):gsub("%s+$", "")
  if #text > HINT_MAX then text = text:sub(1, HINT_MAX) end
  return text
end

local function indexOf(list, value)
  for i, v in ipairs(list) do
    if v == value then return i end
  end
  return 1
end

-- THE TRADE SCREEN'S OWN WORDS.
--
-- Reported from play: "ensure the trading menus and text are extracted and
-- presented properly".  Every line on this screen was the engine's English,
-- including at an Emerald save that has all of them written down in its own
-- wording -- "The trade has been canceled." rather than "The trade was
-- cancelled.", "Choose a POKéMON." rather than "Pick one to trade".
--
-- `say` takes the cartridge's line when the dataset carries one and the
-- engine's otherwise, so a Gen 1 or Gen 2 dataset reads exactly as it did.
local function say(data, role, fallback, ...)
  local TradeText = require("src.link.TradeText")
  local text = TradeText.line(data, role)
  if text then return text end
  return Strings(fallback, ...)
end

local function levelForWire(v)
  -- ANY ("use each mon's real level") goes on the wire as nil (no forced
  -- level).  An explicit guard, not `v == ANY and nil or v`: that idiom's
  -- true branch is nil, so it falls through to `or v` and returned the
  -- literal "ANY" string, which then crashed math.floor in unpackMon (#204).
  if v == ANY then return nil end
  return v
end

local function forceLevelLabel(v)
  return (v == ANY or v == nil) and "ANY" or ("AUTO " .. tostring(v))
end

-- stages before any Net object is meaningfully "this session's link" --
-- .net can still be a leftover failed attempt sitting on self, so error/
-- closed checks below skip these rather than keying off self.net's
-- presence alone
local PRE_CONNECT_STAGES = { menu = true, lanMenu = true, onlineMenu = true,
                             hostPrep = true, hostWait = true, relayPrep = true,
                             relayWait = true, joining = true, joinFailed = true,
                             failed = true, joinList = true }

-- -------------------------------------------------------------------
-- ONLINE SETTINGS.  save.options.online, read here with defaults until the
-- SETTINGS screen (WS10, src/ui/online/OnlineSettings.lua) writes them:
--   port          UDP port to host on (7777)
--   allowRelay    the relay for short codes and tournaments (on: decision
--                 1 of the design keeps it as an opt-out fallback)
--   portMap       ask the router to open the port (UPnP / NAT-PMP / PCP)
--   stun          the public address finder (a third party; off)
--   manualAddress a forwarded port's public IP or name (nil)
--   hubAddress    the player's Link Hub "host:port"; short codes and
--                 tournaments use it in place of the default relay (nil)
--   worldCap      players in a hosted world: 8, at most 16 (WS8 reads it)
--   lanBeacon     a host announces itself on the LAN so JOIN lists it (on)
--   displayName   the name the other player sees (nil: the save's name)
-- bind / lanIp / timeouts / beaconTargets / beaconPort / beaconBind are for
-- tests on 127.0.0.1 and are not shown anywhere.
-- -------------------------------------------------------------------
LinkState.SETTING_DEFAULTS = {
  port = 7777, allowRelay = true, portMap = true, stun = false,
  manualAddress = nil, hubAddress = nil, worldCap = 8, lanBeacon = true,
}
LinkState.WORLD_CAP_MAX = 16

local function nonEmpty(v)
  if type(v) == "string" and v:match("%S") then return (v:gsub("^%s+", ""):gsub("%s+$", "")) end
  return nil
end

function LinkState.settings(game)
  local options = game and game.save and game.save.options
  local raw = type(options) == "table" and type(options.online) == "table"
              and options.online or {}
  local s = {}
  for k, v in pairs(LinkState.SETTING_DEFAULTS) do s[k] = v end
  for k, v in pairs(raw) do s[k] = v end
  local port = tonumber(s.port)
  if not port or port ~= math.floor(port) or port < 0 or port > 65535 then port = 7777 end
  s.port = port
  s.allowRelay = s.allowRelay ~= false
  s.portMap = s.portMap ~= false
  s.stun = s.stun == true
  s.lanBeacon = s.lanBeacon ~= false
  s.manualAddress = nonEmpty(s.manualAddress)
  s.hubAddress = nonEmpty(s.hubAddress)
  s.displayName = nonEmpty(s.displayName)
  local cap = math.floor(tonumber(s.worldCap) or 8)
  s.worldCap = math.max(2, math.min(LinkState.WORLD_CAP_MAX, cap))
  return s
end

-- what Connector.host is given for a DIRECT code: never the relay
function LinkState.hostOptions(s)
  return { port = s.port, bind = s.bind, lanIp = s.lanIp, portMap = s.portMap,
           stun = s.stun, stunServer = s.stunServer, manualAddress = s.manualAddress,
           portMapOpts = s.portMapOpts, allowRelay = false, relayHost = false,
           lanBeacon = s.lanBeacon, beaconTargets = s.beaconTargets,
           beaconPort = s.beaconPort,
           -- a Link Hub (WS9) introduces the pair: the shown code is then a
           -- HUB code (the hub's address and a room ticket, never the host's
           -- own address); this is rendezvous, not the relay
           hub = s.hubAddress }
end

LinkState.HUB_WAIT = 6 -- seconds HOST waits for the hub's ticket

-- the hub's "host[:port]" as an IPv4 and port (a name is resolved)
function LinkState.hubEndpoint(address)
  if type(address) ~= "string" or address == "" then return nil end
  local okU, Util = pcall(require, "src.online.net.Util")
  if not okU then return nil end
  local host, port = Util.splitEndpoint(address, 7778)
  if not Util.isIPv4(host) then
    local okD, Dns = pcall(require, "src.online.net.Dns")
    local ip = okD and Dns.resolve(host, 3) or nil
    host = ip
  end
  if not host then return nil end
  return host, tonumber(port) or 7778
end

-- what a host says about itself in its LAN beacon (LanBeacon: name <= 32)
-- the name this player links under: the SETTINGS display name when one is
-- set, else the save's trainer name
function LinkState.linkName(game)
  local s = LinkState.settings(game)
  if s.displayName then return s.displayName end
  local player = game and game.save and game.save.player or {}
  return player.name
end

-- a hello with the link name in it (Handshake.hello reads the save's)
local function helloFor(game, mode, opts)
  local hello = Handshake.hello(game, mode, opts)
  local name = LinkState.linkName(game)
  if name then hello.name = tostring(name):sub(1, 16) end
  return hello
end

function LinkState.beaconInfo(game)
  local info = { name = tostring(LinkState.linkName(game) or "PLAYER"):sub(1, 12) }
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if okV then
    local okG, id = pcall(GameVersion.get)
    if okG and type(id) == "string" then info.game = id:sub(1, 16) end
  end
  return info
end

-- what Connector.join is given: the relay rung exists only for a short code
function LinkState.joinOptions(s, invite)
  local short = type(invite) == "table" and invite.type == "short"
  return { allowRelay = short and s.allowRelay or false,
           relayAddress = short and s.hubAddress or nil,
           bind = s.bind, timeouts = s.timeouts }
end

-- the gate every link session ends on: give the router its port back
local function closeJob(job)
  if not job then return end
  if job.close then pcall(job.close, job) return end
  if job.cancel then pcall(job.cancel, job) end
  local net = job.channel or job.net or job.result
  if type(net) == "table" and net.close then pcall(net.close, net) end
end

-- how long the host waits for a v2 hello before deciding the peer predates
-- the handshake (a pre-mod guest sends nothing until it hears the mode)
local HELLO_GRACE = 2

-- the joiner edits an IPv4 address as 12 digits (three per octet),
-- prefilled with our own LAN IP so usually only the tail needs changing
local function ipDigits(ip)
  local digits = {}
  local a, b, c, d = (ip or ""):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  local octets = { tonumber(a) or 192, tonumber(b) or 168,
                   tonumber(c) or 0, tonumber(d) or 1 }
  for _, o in ipairs(octets) do
    o = math.min(255, o)
    table.insert(digits, math.floor(o / 100))
    table.insert(digits, math.floor(o / 10) % 10)
    table.insert(digits, o % 10)
  end
  return digits
end

-- opts (all optional; the in-game link rooms, src/online/LinkRooms.lua):
--   holdOnConnect(self) -> bool   called every update once the two games are
--                                 connected and the mode is still open (the
--                                 host's "modeSelect", the guest's "waitMode");
--                                 true = this update is the caller's (it took
--                                 the screen off the stack to hold the link,
--                                 or picked the mode with self:chooseMode)
--   expectMode "trade"|"battle"   a guest whose host picks the other mode
--                                 leaves with self.mismatch set
--   onExit(self, message, reason) every exitWith, before the screen goes
--   ignore { [type] = true|fn }   message types this screen never sees (a
--                                 function is handed the message first)
--   onRoundEnd(self, kind)        a battle / trade is over: true keeps the
--                                 channel for another (a link room's session;
--                                 kind "battle" | "trade")
function LinkState.new(game, opts)
  local self = setmetatable({}, LinkState)
  opts = opts or {}
  self.holdOnConnect = opts.holdOnConnect
  self.expectMode = opts.expectMode
  self.onExit = opts.onExit
  self.ignoreTypes = opts.ignore
  self.onRoundEnd = opts.onRoundEnd
  self.game = game
  -- a link session runs at 1X on both machines whatever either player set
  -- GAME SPEED to (see Game:logicSpeed); cleared in exitWith
  game.linkSession = true
  self.stage = "menu"
  self.index = 1
  self.addr = ipDigits(Net.lanIP())
  self.addrPos = 12 -- the last octet is what usually differs
  self.status = ""
  self.settings = LinkState.settings(game)
  return self
end

-- entry point for a Discord "Ask to Join" click (see DiscordPresence.lua):
-- skips the menu and jumps straight to "connecting with this code", same as
-- if the player had typed it in.  The secret is either kind of code: a
-- six-symbol relay room or a direct invite.  The join starts on the first
-- update, once the caller has pushed this state.
function LinkState.newJoinOnline(game, code)
  local self = LinkState.new(game)
  local invite, why = require("src.online.InviteCode").decode(code, self:myLanIp())
  if invite then
    self.pendingJoin = invite
  else
    self.failure = { title = Strings("CAN'T JOIN"), lines = { tostring(why or "?") } }
    self.stage = "failed"
  end
  return self
end

-- A SESSION THAT IS ALREADY CONNECTED (WS8: an accepted invite in a world,
-- relayed by the world's host).  No connect or mode menus: the two sides
-- have agreed on the mode, so the host side sends its hello with it and
-- waits for the peer's ("waitHello" runs the handshake and starts the
-- mode), the guest side announces itself and waits for the host's
-- ("waitMode") -- the stages a LAN pairing reaches after "connected".
--   opts: { mode = "trade"|"battle", isHost = bool, peerName, source }
-- Returns the LinkState it pushed.
function LinkState.openWithChannel(game, channel, opts)
  opts = opts or {}
  local self = LinkState.new(game)
  self.net = channel
  self.peerName = opts.peerName
  self.source = opts.source
  self.fromWorld = opts.source == "world"
  self.linkPath = opts.source
  self.isHost = opts.isHost and true or false
  if self.isHost then
    local mode = opts.mode == "battle" and "battle" or "trade"
    self:sendHello(mode)
    self.pendingMode = mode
    self.helloWait = 0
    self.stage = "waitHello"
  else
    self.stage = "waitMode"
    self:sendHello(nil)
  end
  game.stack:push(self)
  return self
end

function LinkState:myLanIp()
  return self.settings and self.settings.lanIp or Net.lanIP()
end

-- every socket, mapping and pending job this screen opened
function LinkState:closeLinkJobs(keepNet)
  closeJob(self.joinJob); self.joinJob = nil
  closeJob(self.relayJob); self.relayJob = nil
  if self.punchJob then pcall(self.punchJob.cancel, self.punchJob); self.punchJob = nil end
  self.punchInvite = nil
  if self.lanListener then pcall(self.lanListener.close, self.lanListener); self.lanListener = nil end
  if self.hostJob then
    -- Host:close closes the guest's channel too and unmaps the router port
    if keepNet and self.net and self.hostJob.channel == self.net then
      pcall(self.hostJob.releaseMapping, self.hostJob)
    else
      pcall(self.hostJob.close, self.hostJob)
    end
    self.hostJob = nil
  end
  if self.codeScreen then self.codeScreen:close(); self.codeScreen = nil end
end

function LinkState:exitWith(message, reason)
  if self.onExit then self.onExit(self, message, reason) end
  DiscordPresence.setJoinCode(nil)
  self.game.linkSession = nil -- back to the player's own GAME SPEED
  Runtime.emit("link.ended", { reason = reason or (message and "error" or "bye") })
  self:closeLinkJobs()
  if self.net then self.net:close() end
  self.game.stack:pop()
  if message then
    self.game.stack:push(TextBox.new(self.game, message))
  end
end

-- Online play meets strangers, so it requires a vanilla simulation on both
-- ends (Handshake.onlineAllowed).  Mods merge into the shared Data
-- registries at boot and there is no unmerge, so switching them off has to
-- go through a relaunch -- but the player should not have to go find the
-- mod manager and work out which mods count.  This turns the blocking mods
-- off, records them so the mod manager can put them back, and relaunches.
-- Verified translations are not blockers (#501), so a player keeps their
-- language across the restart and only the gameplay mods go.  The restart
-- is confirmed rather than silent: it drops unsaved progress.
function LinkState:offerVanillaRestart()
  local game = self.game
  local loader = game.mods
  local mods = Handshake.onlineBlockers(game)
  local names = {}
  for i, mod in ipairs(mods) do
    if i > 2 then break end
    names[#names + 1] = tostring(mod.id):upper():sub(1, 12)
  end
  local list = table.concat(names, ", ")
  if #mods > #names then list = list .. (" +%d"):format(#mods - #names) end
  local text = Strings(
    "Online play runs\nvanilla for both\nplayers.\fTurn off %s\nand restart?", list)
  self.game.linkSession = nil
  Runtime.emit("link.ended", { reason = "error" })
  self:closeLinkJobs()
  if self.net then self.net:close() end
  game.stack:pop()
  game.stack:push(TextBox.new(game, text, nil, { choice = function(yes)
    if not yes then return end
    -- setEnabled persists the toggle itself (Loader:_saveState), so the
    -- relaunch comes up vanilla and the mod manager lists them as disabled
    -- for the player to switch back on afterwards
    for _, mod in ipairs(mods) do
      if loader and loader.setEnabled then loader:setEnabled(mod.id, false) end
    end
    if game.restartWithMods then
      game:restartWithMods()
    elseif love.event and love.event.quit then
      love.event.quit("restart")
    end
  end }))
end

-- -------------------------------------------------------------------
-- handshake v2 (D8): both peers announce engine version, api version and
-- a fingerprint of their link surface, and the verdict comes from the two
-- hellos rather than from whoever picked the mode.  The guest announces
-- itself the moment it pairs; the host's hello still carries the mode, so
-- a pre-mod build reads it exactly as it always did.
-- -------------------------------------------------------------------

-- take the peer's hello out of the inbox without eating anything that
-- shares the batch with it
function LinkState:pollHello()
  local msgs = self.net:poll()
  local keep, got = {}, false
  for _, msg in ipairs(msgs) do
    if msg.type == "hello" and not self.peerHello then
      self.peerHello = msg
      self.peerName = msg.name
      got = true
    else
      keep[#keep + 1] = msg
    end
  end
  for i = #keep, 1, -1 do
    table.insert(self.net.inbox, 1, keep[i])
  end
  return got, #keep > 0
end

function LinkState:sendHello(mode)
  -- v3: the invite's nonce rides in the hello (the session secret)
  self.myHello = helloFor(self.game, mode, { nonce = self.sessionNonce })
  self.net:send(self.myHello)
end

-- the host's pick of TRADE or BATTLE (the mode menu's A, or a caller that
-- already knows the mode: a link room's counter): announce it, then the
-- compat check once the peer's hello is in
function LinkState:chooseMode(mode)
  self:sendHello(mode)
  if self.peerHello then
    self:decideCompat(mode, true)
  else
    self.pendingMode = mode
    self.helloWait = 0
    self.stage = "waitHello"
  end
end

-- the verdict's notice heading
local NOTICE_TITLES = {
  subset = "CHECK YOUR MODS", family = "A DIFFERENT GAME",
  timecapsule = "TIME CAPSULE", transfer = "ONE-WAY TRANSFER",
  refused = "CAN'T LINK",
}

function LinkState:decideCompat(mode, isHost)
  self.isHost = isHost
  self.pendingMode = mode
  self.myHello = self.myHello or helloFor(self.game, isHost and mode or nil,
                                                 { nonce = self.sessionNonce })
  local peer = self.peerHello
  self.verdict, self.verdictReason, self.pair = Handshake.checkCompat(self.myHello, peer)
  Runtime.emit("link.connected", {
    role = isHost and "host" or "guest",
    remote = { name = peer and peer.name or self.peerName, mode = mode,
               mods = peer and peer.mods, fingerprint = peer and peer.fingerprint },
  })
  -- a battle goes ahead whenever WS5's LinkBattle.modeFor gives it a mode:
  -- lockstep for matching games, host-authoritative for two games of one
  -- family (E <-> FR/LG, Pt <-> HG/SS) -- no notice for either
  self.battleMode = nil
  if mode == "battle" then
    local okLB, LinkBattle = pcall(require, "src.link.LinkBattle")
    if okLB and type(LinkBattle.modeFor) == "function" then
      self.battleMode = LinkBattle.modeFor(self.verdict, self.pair)
    end
  end
  if self.verdict == "full" or self.verdict == "vanilla_peer"
     or (mode == "battle" and self.battleMode ~= nil) then
    if isHost and mode == "battle" then
      -- host picks the level rule now, before the parties are exchanged
      self.stage = "battleOptions"
    else
      self:startMode(mode, isHost)
    end
    return
  end
  -- naming the difference up front is the whole point: the old behaviour
  -- was a silent draw three turns into a battle that could never work
  self.noticeLines = Handshake.describe(self.myHello, peer, self.verdict, mode)
  self.noticeTitle = NOTICE_TITLES[self.verdict] or "CHECK YOUR MODS"
  self.noticeExits = self.verdict == "refused" or mode ~= "trade"
  -- a TRANSFER pair (Pal Park 3->4, Poke Transfer 4->5) never swaps: A
  -- opens the one-way gift instead of the trade
  self.noticeTransfer = self.verdict == "transfer" and mode == "trade"
    and (Handshake.transferAllowed == nil or Handshake.transferAllowed(self.verdict))
  self.stage = "notice"
end

-- -------------------------------------------------------------------
-- update
-- -------------------------------------------------------------------

function LinkState:update(dt)
  local input = self.game.input
  if self.net then
    self.net:update()
    if self.ignoreTypes and self.net.inbox then
      local inbox = self.net.inbox
      for i = #inbox, 1, -1 do
        local m = inbox[i]
        local ig = type(m) == "table" and self.ignoreTypes[m.type]
        if type(ig) == "function" then ig(m) end
        if ig then table.remove(inbox, i) end
      end
    end
    if self.net.error and not PRE_CONNECT_STAGES[self.stage] then
      self:exitWith(Strings("Link error:\n%s", self.net.error:sub(1, 60)))
      return
    end
    -- the peer vanished without a bye (only once the inbox is drained,
    -- so a final message travelling with the disconnect still counts)
    if self.net.closed and #self.net.inbox == 0
       and not PRE_CONNECT_STAGES[self.stage] and self.stage ~= "addrEntry"
       and self.stage ~= "codeEntry" and self.stage ~= "notice"
       and self.stage ~= "battleRunning" then
      self:exitWith(Strings("The link was\nbroken."))
      return
    end
  end

  if self.pendingJoin then
    local invite = self.pendingJoin
    self.pendingJoin = nil
    self:startJoin(invite)
    return
  end

  if self.holdOnConnect and (self.stage == "modeSelect" or self.stage == "waitMode")
     and self.holdOnConnect(self) then
    return
  end

  if self.stage == "menu" then
    self.settings = LinkState.settings(self.game)
    local items = self:menuItems()
    local n = #items
    if self.index > n then self.index = 1 end
    if input:wasPressed("down") then
      self.index = self.index % n + 1
    elseif input:wasPressed("up") then
      self.index = (self.index - 2) % n + 1
    elseif input:wasPressed("b") then
      self:exitWith(nil)
    elseif input:wasPressed("a") then
      self:chooseMenu(items[self.index].id)
    end

  elseif self.stage == "hostPrep" then -- the socket and the router mapping
    local h = self.hostJob
    if input:wasPressed("b") then self:backToMenu(1) return end
    h:update()
    if h.state == "failed" or h.state == "closed" then
      self:fail(Strings("CAN'T HOST"), h.reason)
    elseif not h.pending and (h.state == "listening" or h.state == "connected") then
      -- with a hub set, its ticket (or its failure) first
      self.hubWait = (self.hubWait or 0) + (dt or 1 / 60)
      local hubDone = not self.settings.hubAddress or (h.info and h.info.hubTicket)
        or self.hubWait > LinkState.HUB_WAIT
      if not hubDone then
        for _, e in ipairs(h.log or {}) do
          if e.rung == "hub" and e.state == "failed" then hubDone = true end
        end
      end
      if hubDone then self:showHostCode() end
    end

  elseif self.stage == "relayPrep" then -- the relay hands out a room
    local job = self.relayJob
    if input:wasPressed("b") then self:backToMenu(self:menuIndexOf("short")) return end
    job:update()
    if job.state == "failed" then
      self:fail(Strings("CAN'T REACH THE RELAY"), job.reason)
    elseif job.code then
      self:showRelayCode(job.code)
    end

  elseif self.stage == "hostWait" or self.stage == "relayWait" then
    -- ShowCode is on top and polls (pollHost / pollRelay); this only runs
    -- if the code screen went away without a decision
    self:backToMenu(1)

  elseif self.stage == "joining" and not self.joinJob then
    -- a state handed an already-dialled Net (the old address join, and the
    -- link tests' Net.loopbackPair): wait for the pairing as before
    if input:wasPressed("b") then self:exitWith(nil) return end
    if self.net and self.net.error then
      self:exitWith(Strings("Link error:\n%s", tostring(self.net.error):sub(1, 60)))
      return
    end
    if self.net and self.net.paired then
      self.stage = "waitMode"
      self:sendHello(nil) -- the host owns the mode; this is just who we are
    end

  elseif self.stage == "joining" then -- Connector.join walks the ladder
    local job = self.joinJob
    if input:wasPressed("b") then
      if job then job:cancel() end
      self:backToMenu(self:menuIndexOf("join"))
      return
    end
    job:update()
    if job.state == "connected" and job.channel then
      self.net = job.channel
      self.linkPath = job.path
      self.joinJob = nil
      Runtime.emit("link.path", { path = job.path, role = "guest" })
      self.stage = "waitMode"
      self:sendHello(nil) -- the host owns the mode; this is just who we are
    elseif job.state == "failed" then
      self.failReason = job.reason
      self.failLog = job.log
      self.joinJob = nil
      self.stage = "joinFailed"
      self.index = 1
    end

  elseif self.stage == "joinFailed" then
    -- the swap: only the host needs to be reachable, so the side that
    -- could not get in often can be got into
    local n = #LinkState.JOIN_FAILED_ITEMS
    if input:wasPressed("down") then
      self.index = self.index % n + 1
    elseif input:wasPressed("up") then
      self.index = (self.index - 2) % n + 1
    elseif input:wasPressed("b") then
      self:backToMenu(self:menuIndexOf("join"))
    elseif input:wasPressed("a") then
      local id = LinkState.JOIN_FAILED_ITEMS[self.index]
      local last = self.lastInvite
      if id == "swap" then
        self:startHost(Strings("Ask your friend to enter this code."))
      elseif id == "both" then
        -- simultaneous open: host, show my code, and keep dialling theirs
        -- while they enter mine (both sides then call each other at once)
        local punch = last and last.type ~= "short" and last or nil
        self:startHost(Strings("They enter this code; you already entered theirs."))
        self.punchInvite = punch
      elseif id == "retry" then
        if last and last.raw then self:openJoinEntry(last.raw) else self:openJoinList() end
      else
        self:backToMenu(self:menuIndexOf("join"))
      end
    end

  elseif self.stage == "joinList" then -- LAN games nearby, or a code
    local l = self.lanListener
    if l then l:update() end
    local items = self:joinListItems()
    local n = #items
    if self.index > n then self.index = n end
    if input:wasPressed("down") then
      self.index = self.index % n + 1
    elseif input:wasPressed("up") then
      self.index = (self.index - 2) % n + 1
    elseif input:wasPressed("b") then
      self:backToMenu(self:menuIndexOf("join"))
    elseif input:wasPressed("a") then
      local item = items[self.index]
      if item.id == "code" then
        self:openJoinEntry()
      elseif item.host and item.host.compatible then
        local invite = require("src.online.net.LanBeacon").toInvite(item.host)
        invite.type, invite.kind = "direct", "session"
        invite.display = item.host.address
        self:startJoin(invite)
      end
    end

  elseif self.stage == "hubDoor" then -- pinging a friend's Link Hub
    if input:wasPressed("b") then self.hubDoor = nil self:backToMenu(self:menuIndexOf("join")) return end
    local LH = require("src.online.LauncherHub")
    LH.pollProbe()
    local p = LH.probeState()
    if p and p.phase == "ok" and p.pong then
      self:hubDoorReady(p.pong)
    elseif not p or p.phase == "failed" then
      self.hubDoor = nil
      self:fail(Strings("CAN'T REACH THE HUB"), p and p.why or "?")
    end

  elseif self.stage == "hubDoorReady" then
    local items = self:hubDoorItems()
    if self.index > #items then self.index = 1 end
    if input:wasPressed("down") then
      self.index = self.index % #items + 1
    elseif input:wasPressed("up") then
      self.index = (self.index - 2) % #items + 1
    elseif input:wasPressed("b") then
      self:backToMenu(self:menuIndexOf("join"))
    elseif input:wasPressed("a") then
      local id = items[self.index].id
      if id == "world" then
        local game, code = self.game, self.hubDoor.pong.worldCode
        self:exitWith(nil)
        local OnlineWorld = require("src.online.world.OnlineWorld")
        local okJ, why = OnlineWorld.joinWorld(game, code)
        if okJ then pcall(OnlineWorld.openMenu, game)
        else game.stack:push(TextBox.new(game, tostring(why or Strings("Can't join that world.")))) end
      elseif id == "host" then
        self:chooseMenu("host")
      else
        self:backToMenu(self:menuIndexOf("join"))
      end
    end

  elseif self.stage == "failed" then
    if input:wasPressed("a") or input:wasPressed("b") then self:backToMenu(1) end

  elseif self.stage == "lanMenu" then -- ADVANCED: the old address link
    if input:wasPressed("up") or input:wasPressed("down") then
      self.index = self.index == 1 and 2 or 1
    elseif input:wasPressed("b") then
      self:backToMenu(self:menuIndexOf("advanced"))
    elseif input:wasPressed("a") then
      self.net = Net.new()
      if self.index == 1 then
        if self.net:host() then
          self.stage = "hosting"
        else
          self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
        end
      else
        self.stage = "addrEntry"
      end
    end

  elseif self.stage == "hosting" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if self.net.paired then
      self.linkPath = "lan"
      self.stage = "modeSelect"
      self.index = 1
    end

  elseif self.stage == "addrEntry" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if input:wasPressed("up") then
      self.addr[self.addrPos] = (self.addr[self.addrPos] + 1) % 10
    elseif input:wasPressed("down") then
      self.addr[self.addrPos] = (self.addr[self.addrPos] - 1) % 10
    elseif input:wasPressed("left") then
      self.addrPos = math.max(1, self.addrPos - 1)
    elseif input:wasPressed("right") then
      self.addrPos = math.min(12, self.addrPos + 1)
    elseif input:wasPressed("a") then
      local octets = {}
      for i = 1, 4 do
        local base = (i - 1) * 3
        octets[i] = math.min(255, self.addr[base + 1] * 100
                                  + self.addr[base + 2] * 10
                                  + self.addr[base + 3])
      end
      if self.net:join(table.concat(octets, ".")) then
        self.stage = "lanJoining"
      else
        self:exitWith(Strings("Link error:\n%s", self.net.error or "?"))
      end
    end

  elseif self.stage == "lanJoining" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    if self.net.paired then
      self.linkPath = "lan"
      self.stage = "waitMode"
      self:sendHello(nil) -- the host owns the mode; this is just who we are
    end

  elseif self.stage == "modeSelect" then -- host picks
    self:pollHello()
    if input:wasPressed("up") or input:wasPressed("down") then
      self.index = self.index == 1 and 2 or 1
    elseif input:wasPressed("a") then
      self:chooseMode(self.index == 1 and "trade" or "battle")
    elseif input:wasPressed("b") then
      self:exitWith(nil)
    end

  elseif self.stage == "battleOptions" and LinkState.rulesGen() >= 3 then
    -- Gen 3+: the host deals the BattleRules (WS5) before the parties go
    self:updateRulesPicker(input)

  elseif self.stage == "battleOptions" then -- host picks the level rule,
                                             -- once compat is confirmed and
                                             -- before parties are exchanged
    self.levelChoice = self.levelChoice or ANY
    if input:wasPressed("b") then
      self:exitWith(nil)
    elseif input:wasPressed("up") or input:wasPressed("down")
        or input:wasPressed("left") or input:wasPressed("right") then
      local delta = (input:wasPressed("down") or input:wasPressed("left")) and -1 or 1
      local i = indexOf(FORCE_LEVEL_STEPS, self.levelChoice)
      i = ((i - 1 + delta) % #FORCE_LEVEL_STEPS) + 1
      self.levelChoice = FORCE_LEVEL_STEPS[i]
    elseif input:wasPressed("a") then
      self.forceLevel = levelForWire(self.levelChoice)
      self:startMode(self.pendingMode, true)
    end

  elseif self.stage == "waitHello" then -- host waits for the peer's hello
    if input:wasPressed("b") then self:exitWith(nil) return end
    local got, other = self:pollHello()
    self.helloWait = self.helloWait + (dt or 0)
    -- a pre-mod peer never sends one: it just gets on with the mode, so
    -- its first message -- or the grace period -- is the answer
    if got or other or self.helloWait > HELLO_GRACE then
      self:decideCompat(self.pendingMode, true)
    end

  elseif self.stage == "waitMode" then -- guest waits for host's pick
    if input:wasPressed("b") then self:exitWith(nil) return end
    local msgs = self.net:poll()
    for i, msg in ipairs(msgs) do
      if msg.type == "hello" then
        self.peerHello = msg
        self.peerName = msg.name
        -- the host's next messages (party, ...) can share this batch;
        -- put them back so the new stage's poll sees them
        for j = #msgs, i + 1, -1 do
          table.insert(self.net.inbox, 1, msgs[j])
        end
        if self.expectMode and msg.mode and msg.mode ~= self.expectMode then
          -- the host picked the other mode: not the room this guest is in
          self.mismatch = true
          self.net:send({ type = "bye" })
          self:exitWith(nil, "error")
          return
        end
        self:decideCompat(msg.mode, false)
        break
      end
    end

  elseif self.stage == "notice" then
    if input:wasPressed("b") or (self.noticeExits and input:wasPressed("a")) then
      self.net:send({ type = "bye" })
      self:exitWith(nil, "error")
    elseif input:wasPressed("a") then
      self:startMode(self.pendingMode, self.isHost)
    end

  elseif self.stage == "trade" then
    self:updateTrade(input)

  elseif self.stage == "transfer" then
    self:updateTransfer(input)

  elseif self.stage == "battleWait" then
    if input:wasPressed("b") then self:exitWith(nil) return end
    local msgs = self.net:poll()
    for i, msg in ipairs(msgs) do
      if msg.type == "party" then
        -- the host owns this rule (same as mode); the guest only learns
        -- it here, off the host's own party message
        if not self.isHost then
          self.forceLevel = msg.forceLevel
          self.battleRules = msg.rules -- LinkBattle sanitizes it
        end
        local LinkBattle = require("src.link.LinkBattle")
        local opts = {
          myParty = Protocol.packParty(self.game.save.party, nil, self:packOpts()),
          theirParty = msg.mons,
          -- v3: what WS5's battle rules read (host-authoritative mode for
          -- two games of one family, generation level rules)
          myHello = self.myHello, peerHello = self.peerHello, pair = self.pair,
          theirName = self.peerName or "FOE",
          seed = self.isHost and self.linkSeed or msg.seed,
          verdict = self.verdict,
          strict = Handshake.strict(self.verdict),
          forceLevel = self.forceLevel,
          rules = self.battleRules,
          mode = self.battleMode,
          -- a link room plays on: its channel outlives this battle
          keepNetOpen = self.onRoundEnd ~= nil and self.keepRounds or nil,
        }
        local battle, why
        if self.isHost then
          battle, why = LinkBattle.newHost(self.game, self.net, opts)
        else
          battle, why = LinkBattle.newGuest(self.game, self.net, opts)
        end
        if not battle then
          self.net:send({ type = "bye" })
          self:exitWith(why or Strings("Link battle\ncan't start."), "error")
          return
        end
        self.game.stack:push(battle)
        self.battle = battle
        self.stage = "battleRunning"
        for j = #msgs, i + 1, -1 do
          table.insert(self.net.inbox, 1, msgs[j])
        end
        break
      end
    end

  elseif self.stage == "battleRunning" then
    if self.game.stack:top() == self then
      if self.onRoundEnd and self.onRoundEnd(self, "battle") then return end
      self:exitWith(nil) -- battle finished
    end
  end
end

function LinkState:startMode(mode, isHost)
  self.isHost = isHost
  if mode == "trade" then
    self.stage = "trade"
    -- a subset session settles which mons both games rebuild identically
    -- before either party goes out, so a pick can't land on a mon the
    -- other side would reconstruct differently
    if self.verdict == "transfer" then return self:startTransfer() end
    -- v3: the two hellos go in explicitly (the CompatRules per-mon gates,
    -- the MonCodec version), not through the global Handshake.session
    self.trade = Protocol.TradeSession.new(self.game.data, self.game.save.party, {
      subset = self.verdict == "subset",
      strict = Handshake.strict(self.verdict),
      peerName = self.peerName,
      verdict = self.verdict,
      myHello = self.myHello,
      peerHello = self.peerHello,
    })
    self.net:send(self.trade:opening())
    self.index = 1
  else
    self.stage = "battleWait"
    -- the host deals the shared RNG seed for the lockstep simulation
    if isHost then
      self.linkSeed = love.math.random(1, 2 ^ 30)
    end
    self.net:send({ type = "party",
                    mons = Protocol.packParty(self.game.save.party, nil, self:packOpts()),
                    seed = self.linkSeed,
                    forceLevel = isHost and self.forceLevel or nil,
                    rules = isHost and self.battleRules or nil })
  end
end

-- -------------------------------------------------------------------
-- the LINK menu, HOST / JOIN / SHORT CODE
-- -------------------------------------------------------------------

-- packParty's options: this game's data and the peer's hello decide the
-- wire (MonCodec v3 for Gen 3+, or for a Gen 1/2 peer that reads it)
LinkState.JOIN_FAILED_ITEMS = { "swap", "both", "retry", "back" }
LinkState.JOIN_FAILED_LABELS = {
  swap = "SWAP: I'LL HOST", both = "BOTH ENTER CODES", retry = "TRY AGAIN", back = "BACK",
}

function LinkState:packOpts()
  return { data = self.game.data, peerHello = self.peerHello or false }
end

LinkState.MENU_HELP = {
  host = "Make a code for a friend.",
  join = "Enter a friend's code.",
  short = "A 6-letter code. Uses the relay.",
  tournament = "Brackets. Uses the relay.",
  advanced = "Link by network address.",
  worlds = "Play together in a hosted world.",
  settings = "Port, router, relay and your name.",
  gts = "Trade through the Global Trade Station.",
}

function LinkState.gtsAvailable(game, s)
  local okG, GtsClient = pcall(require, "src.online.gts.GtsClient")
  if not (okG and type(GtsClient) == "table" and GtsClient.open) then return false end
  if s and s.hubAddress then return true end
  local okW, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
  if okW and type(OnlineWorld) == "table" and OnlineWorld.gtsChannel then
    local okC, ch = pcall(function()
      local c = OnlineWorld.client and OnlineWorld.client()
      return c and c.state == "in" and c.hasService and c:hasService("gts")
    end)
    return okC and ch and true or false
  end
  return false
end

function LinkState.settingsAvailable()
  local ok, OnlineSettings = pcall(require, "src.ui.online.OnlineSettings")
  return ok and type(OnlineSettings) == "table" and type(OnlineSettings.open) == "function"
end

-- the WORLDS row shows once WS8's module is there to open
function LinkState.worldsAvailable()
  local ok, OnlineWorld = pcall(require, "src.online.world.OnlineWorld")
  return ok and type(OnlineWorld) == "table" and type(OnlineWorld.openMenu) == "function"
end

function LinkState:menuItems()
  local items = {
    { id = "host", label = Strings("HOST") },
    { id = "join", label = Strings("JOIN") },
  }
  -- WORLDS (WS8): a player-hosted world, reached the same direct way
  if LinkState.worldsAvailable() then
    items[#items + 1] = { id = "worlds", label = Strings("WORLDS") }
  end
  -- the relay carries short codes and tournaments only, and only while
  -- the settings allow it
  if self.settings.allowRelay then
    items[#items + 1] = { id = "short", label = Strings("SHORT CODE") }
    items[#items + 1] = { id = "tournament", label = Strings("TOURNAMENT") }
  end
  items[#items + 1] = { id = "advanced", label = Strings("ADVANCED (IP)") }
  -- GTS (WS7) through the configured hub or the world this player is in
  if LinkState.gtsAvailable(self.game, self.settings) then
    items[#items + 1] = { id = "gts", label = Strings("GTS") }
  end
  -- SETTINGS (WS10's screen), when it is there
  if LinkState.settingsAvailable() then
    items[#items + 1] = { id = "settings", label = Strings("SETTINGS") }
  end
  return items
end

function LinkState:menuIndexOf(id)
  for i, item in ipairs(self:menuItems()) do
    if item.id == id then return i end
  end
  return 1
end

function LinkState:backToMenu(index)
  self:closeLinkJobs()
  if self.net then self.net:close(); self.net = nil end
  DiscordPresence.setJoinCode(nil)
  self.stage = "menu"
  self.index = index or 1
end

function LinkState:fail(title, reason)
  self:closeLinkJobs()
  local lines = {}
  for line in tostring(reason or "?"):gmatch("[^\n]+") do lines[#lines + 1] = line end
  self.failure = { title = title, lines = lines }
  self.stage = "failed"
end

function LinkState:chooseMenu(id)
  if id == "host" then
    self:startHost()
  elseif id == "join" then
    self:openJoinList()
  elseif id == "short" or id == "tournament" then
    -- the relay meets strangers: vanilla play on both ends
    if not Handshake.onlineAllowed(self.game) then
      self:offerVanillaRestart()
      return
    end
    if id == "short" then
      self:startShortHost()
    else
      local Tournament = require("src.link.Tournament")
      self.game.stack:pop()
      self.game.stack:push(Tournament.new(self.game))
    end
  elseif id == "advanced" then
    self.stage = "lanMenu"
    self.index = 1
  elseif id == "gts" then
    -- GtsClient asks its provider (src/online/HubGts.lua): the world's
    -- GTS when in one, else the configured hub's
    local game = self.game
    self:exitWith(nil)
    pcall(function() require("src.online.HubGts").install() end) -- Game:load did; harmless twice
    local ok, err = pcall(function() return require("src.online.gts.GtsClient").open(game, {}) end)
    if not ok then
      require("src.core.Logger").warn("link: GTS failed to open (%s)", tostring(err))
    end
  elseif id == "settings" then
    -- over this screen; the menu re-reads the settings when it comes back
    -- (the relay rows follow allowRelay)
    local ok, err = pcall(function()
      return require("src.ui.online.OnlineSettings").open(self.game, {
        onClose = function() self.settings = LinkState.settings(self.game) end,
      })
    end)
    if not ok then
      require("src.core.Logger").warn("link: SETTINGS failed to open (%s)", tostring(err))
    end
  elseif id == "worlds" then
    local game = self.game
    self:exitWith(nil)
    local ok, err = pcall(function()
      return require("src.online.world.OnlineWorld").openMenu(game)
    end)
    if not ok then
      game.stack:push(TextBox.new(game, Strings("Worlds aren't\navailable.")))
      require("src.core.Logger").warn("link: WORLDS failed to open (%s)", tostring(err))
    end
  end
end

-- HOST: this game's own socket, a direct code, no relay
function LinkState:startHost(note)
  self:closeLinkJobs()
  local okC, Connector = pcall(require, "src.online.net.Connector")
  if not okC then return self:fail(Strings("CAN'T HOST"), Connector) end
  local hopts = LinkState.hostOptions(self.settings)
  hopts.beaconInfo = LinkState.beaconInfo(self.game)
  local ok, host = pcall(Connector.host, hopts)
  if not ok then return self:fail(Strings("CAN'T HOST"), host) end
  self.hostJob = host
  self.hubWait = 0
  self.hubCode = nil
  self.hostNote = note
  self.isHost = true
  self.stage = "hostPrep"
end

function LinkState:hostStatus(dt)
  local h = self.hostJob
  self.dots = ((self.dots or 0) + (dt or 0)) % 2
  local dots = ("..."):sub(1, 1 + math.floor(self.dots * 1.5))
  local text = Strings("Waiting for a friend") .. dots
  if self.hostNote then text = self.hostNote .. " " .. text end
  local info = h and h.info or {}
  if self.hubCode then
    text = text .. " " .. Strings("Through your Link Hub.")
  elseif info.publicVia == "upnp" or info.publicVia == "natpmp" or info.publicVia == "pcp" then
    text = text .. " " .. Strings("Your router opened the port.")
  elseif info.publicVia == "manual" then
    text = text .. " " .. Strings("Using your forwarded port.")
  elseif not info.public then
    text = text .. " " .. Strings("Same network only.")
  end
  if self.punchJob then
    text = text .. " " .. Strings("Calling their code too...")
  else
    text = text .. " " .. Strings("START: enter their code.")
  end
  return text
end

function LinkState:showHostCode()
  local h = self.hostJob
  local InviteCode = require("src.online.InviteCode")
  local fields = h:inviteFields()
  -- a direct code carries the host's addresses and nothing for a relay
  fields.room = nil
  local display, raw
  -- (the launcher's own hub also gives its LAN address and the router's
  -- outside port: LauncherHub.advertisedEndpoint)
  local hubIp, hubPort, hubLan, hubPublicPort = LinkState.hubEndpoint(self.settings.hubAddress)
  if h.info and h.info.hubTicket and hubIp then
    display, raw = InviteCode.encode({ kind = "hub", lan = hubLan,
                                       hub = { ip = hubIp, port = hubPort, publicPort = hubPublicPort },
                                       ticket = h.info.hubTicket })
    self.hubCode = display ~= nil
  end
  if not display then display, raw = InviteCode.encode(fields) end
  if not display then return self:fail(Strings("CAN'T HOST"), raw) end
  self.hostCode = display
  self.sessionNonce = h.info and h.info.nonce
  DiscordPresence.setJoinCode(raw) -- a Discord join secret carries the code
  self.stage = "hostWait"
  if self.punchInvite then
    local invite = self.punchInvite
    self.punchInvite = nil
    self:startPunch(invite)
  end
  local ShowCode = require("src.ui.online.ShowCode")
  self.codeScreen = ShowCode.open(self.game, {
    code = display,
    title = Strings("YOUR LINK CODE"),
    status = self:hostStatus(0),
    onUpdate = function(screen, dt) self:pollHost(screen, dt) end,
    onCancel = function()
      self.codeScreen = nil
      self:backToMenu(1)
    end,
  })
end

-- SIMULTANEOUS OPEN (ladder rung L3): both players host and each enters
-- the other's code; both games dial at once from their own socket and the
-- first connection that lands is kept (Connector.join with hostJob)
function LinkState:startPunch(invite)
  if not (self.hostJob and invite) or invite.type == "short" then return end
  local okC, Connector = pcall(require, "src.online.net.Connector")
  if not okC then return end
  self.theirNonce = tonumber(invite.nonce)
  self.punchJob = Connector.join(invite, { hostJob = self.hostJob, allowRelay = false,
                                           bind = self.settings.bind,
                                           timeouts = self.settings.timeouts })
end

function LinkState:openPunchEntry()
  local LongCodeEntry = require("src.ui.online.LongCodeEntry")
  LongCodeEntry.open(self.game, {
    title = Strings("THEIR CODE"),
    myLanIp = self:myLanIp(),
    allowShort = false, allowDirect = true,
    onDone = function(invite) self:startPunch(invite) end,
  })
end

-- connected from the code screen: who picks TRADE / BATTLE?  The host,
-- unless both hosted (a simultaneous open), where the smaller session
-- nonce hosts -- both games work out the same answer
function LinkState:connectedFromHost(screen, channel, path)
  DiscordPresence.setJoinCode(nil)
  self.net = channel
  self.linkPath = path
  local mine = self.hostJob and self.hostJob.info and tonumber(self.hostJob.info.nonce)
  local theirs = self.theirNonce
  local host = true
  if theirs and mine and theirs ~= mine then host = mine < theirs end
  if self.punchJob and self.punchJob.state == "trying" then pcall(self.punchJob.cancel, self.punchJob) end
  self.punchJob = nil
  Runtime.emit("link.path", { path = path, role = host and "host" or "guest" })
  self.codeScreen = nil
  screen:close()
  self.isHost = host
  if host then
    self.stage = "modeSelect"
    self.index = 1
  else
    self.stage = "waitMode"
    self:sendHello(nil)
  end
end

function LinkState:pollHost(screen, dt)
  local h = self.hostJob
  if not h then return end
  h:update()
  local p = self.punchJob
  if p and p.state == "trying" then p:update() end
  if p and p.state == "connected" and p.channel then
    return self:connectedFromHost(screen, p.channel, p.path)
  end
  if h.state == "connected" and h.channel then
    return self:connectedFromHost(screen, h.channel, h.path)
  end
  if p and p.state == "failed" then
    -- their side can still get in through my code
    self.punchFailed = p.reason
    self.punchJob = nil
  end
  local input = self.game and self.game.input
  if input and not self.punchJob and input:wasPressed("start") then
    self:openPunchEntry()
    return
  end
  if h.state == "failed" or h.state == "closed" then
    self.codeScreen = nil
    screen:close()
    return self:fail(Strings("CAN'T HOST"), h.reason or "closed")
  end
  screen:setStatus(self:hostStatus(dt))
end

-- SHORT CODE: a room on the relay (or the player's hub)
function LinkState:startShortHost()
  self:closeLinkJobs()
  local okR, Relay = pcall(require, "src.online.net.Relay")
  if not okR then return self:fail(Strings("CAN'T REACH THE RELAY"), Relay) end
  self.relayJob = Relay.host(self.settings.hubAddress)
  self.isHost = true
  self.stage = "relayPrep"
end

function LinkState:showRelayCode(code)
  self.stage = "relayWait"
  DiscordPresence.setJoinCode(code)
  local ShowCode = require("src.ui.online.ShowCode")
  self.codeScreen = ShowCode.open(self.game, {
    code = code,
    title = Strings("SHORT CODE"),
    status = Strings("Waiting for a friend..."),
    detail = Strings("Room %s on the relay.", code),
    privacy = false,
    onUpdate = function(screen, dt) self:pollRelay(screen, dt) end,
    onCancel = function()
      self.codeScreen = nil
      self:backToMenu(self:menuIndexOf("short"))
    end,
  })
end

function LinkState:pollRelay(screen)
  local job = self.relayJob
  if not job then return end
  job:update()
  if job.state == "done" and job.result then
    DiscordPresence.setJoinCode(nil)
    self.net = job.result
    self.linkPath = "relay"
    self.relayJob = nil
    self.codeScreen = nil
    screen:close()
    self.stage = "modeSelect"
    self.index = 1
  elseif job.state == "failed" then
    self.codeScreen = nil
    screen:close()
    self:fail(Strings("CAN'T REACH THE RELAY"), job.reason)
  end
end

-- JOIN: either kind of code
function LinkState:openJoinEntry(text)
  local LongCodeEntry = require("src.ui.online.LongCodeEntry")
  if self.stage ~= "joinList" then self.stage = "menu" end
  LongCodeEntry.open(self.game, {
    title = Strings("ENTER A CODE"),
    myLanIp = self:myLanIp(),
    allowShort = true, allowDirect = true,
    text = text,
    onDone = function(invite) self:startJoin(invite) end,
    onCancel = function()
      if self.lanListener then
        self.stage, self.index = "joinList", 1
      else
        self.stage, self.index = "menu", self:menuIndexOf("join")
      end
    end,
  })
end

-- JOIN's first page: the games this one hears on the LAN (LanBeacon), and
-- ENTER A CODE
function LinkState:openJoinList()
  self:closeLinkJobs()
  local okB, LanBeacon = pcall(require, "src.online.net.LanBeacon")
  if okB then
    local s = self.settings
    local ok, l = pcall(LanBeacon.newListener, { bind = s.beaconBind, port = s.beaconPort })
    if ok then self.lanListener = l end
  end
  self.stage = "joinList"
  self.index = 1
end

function LinkState:joinListItems()
  local items = { { id = "code", label = Strings("ENTER A CODE") } }
  local l = self.lanListener
  for _, host in ipairs(l and l:hosts() or {}) do
    local label = tostring(host.name or host.ip or "?")
    if host.game then label = label .. " (" .. tostring(host.game):upper() .. ")" end
    items[#items + 1] = { id = "lan", host = host, label = label, dim = not host.compatible }
  end
  return items
end

-- A FRIEND'S LINK HUB CODE (the launcher's hub share code: an InviteCode
-- kind "hub" with ticket 0, src/online/LauncherHub.lua) is not a session to
-- dial -- dialled, the hub answers "not found".  JOIN takes it the way the
-- launcher's JOIN FRIEND does: ping the hub, keep it (the launcher's friend
-- hub, and this save's hubAddress), then offer what it has: its world, or
-- HOST for a code friends join through it.
function LinkState.isHubDoor(invite)
  local okH, LH = pcall(require, "src.online.LauncherHub")
  if okH and type(LH) == "table" and LH.isHubDoor then return LH.isHubDoor(invite) end
  return type(invite) == "table" and invite.kind == "hub"
    and tonumber(invite.ticket or invite.nonce) == 0
end

function LinkState:startHubDoor(invite)
  local okH, LH = pcall(require, "src.online.LauncherHub")
  if not (okH and LH.probe) then
    return self:fail(Strings("CAN'T JOIN"), Strings("That is a Link Hub code."))
  end
  local okP, err = pcall(LH.probe, invite)
  if not okP then return self:fail(Strings("CAN'T REACH THE HUB"), tostring(err)) end
  self.hubDoor = { invite = invite }
  self.stage = "hubDoor"
end

-- the hub answered: keep it as this game's hub, then its options
function LinkState:hubDoorReady(pong)
  local save = self.game.save
  if save then
    save.options = save.options or {}
    save.options.online = save.options.online or {}
    save.options.online.hubAddress = pong.address
  end
  self.settings = LinkState.settings(self.game)
  self.hubDoor = { pong = pong }
  self.index = 1
  self.stage = "hubDoorReady"
end

function LinkState:hubDoorItems()
  local pong = self.hubDoor and self.hubDoor.pong or {}
  local items = {}
  if pong.worldCode then items[#items + 1] = { id = "world", label = Strings("JOIN THEIR WORLD") } end
  items[#items + 1] = { id = "host", label = Strings("HOST") }
  items[#items + 1] = { id = "back", label = Strings("BACK") }
  return items
end

function LinkState:startJoin(invite)
  self:closeLinkJobs()
  self.lastInvite = invite
  if LinkState.isHubDoor(invite) then return self:startHubDoor(invite) end
  if invite.type == "short" then
    if not self.settings.allowRelay then
      return self:fail(Strings("CAN'T JOIN"),
        Strings("Short codes use the relay, and the relay is off in the settings."))
    end
    if not Handshake.onlineAllowed(self.game) then
      self:offerVanillaRestart()
      return
    end
  end
  local okC, Connector = pcall(require, "src.online.net.Connector")
  if not okC then return self:fail(Strings("CAN'T JOIN"), Connector) end
  self.sessionNonce = invite.type ~= "short" and invite.nonce or nil
  -- a direct code is joined with no relay rung (joinOptions)
  self.joinJob = Connector.join(invite, LinkState.joinOptions(self.settings, invite))
  self.isHost = false
  self.stage = "joining"
end

-- -------------------------------------------------------------------
-- THE ONE-WAY MOVIE.  A transfer is half a trade, so it is half of the
-- generation's own trade movie: the SENDER (Gen 3 or Gen 4) watches its
-- mon leave and the movie stops before anything comes back (TradeAnim
-- after "X went to Y", Gen4TradeSequence before the wormhole, Gen5's
-- after its intro); the RECEIVER (Gen 4 or Gen 5) starts the movie where
-- the incoming ball arrives (Gen4TradeSequence's ARRIVAL phase, Gen5's
-- outro).  Without the art the message alone is shown.
-- -------------------------------------------------------------------
local TRADEANIM_AFTER_SEND = { for_sends = true, farewell = true, transfer_rl = true,
                               show_enemy = true, will_trade = true, cleanup = true, done = true }

function LinkState.oneWayMovie(game, direction, mon, peerName, onDone)
  local GameVersion = require("src.core.GameVersion")
  local data = game.data or {}
  local fired = false
  local function done()
    if fired then return end
    fired = true
    if onDone then onDone() end
  end
  local name, opts, cut, start
  if GameVersion.isGen5() and data.gen5_trade_art then
    name = "Gen5TradeSequence"
    opts = { sending = mon, receiving = mon, otName = peerName }
    if direction == "send" then
      cut = function(s) return s.phase ~= "intro" end
    else
      start = function(s) s.phase, s.t = "outro", 0 end
    end
  elseif GameVersion.isGen4() and data.gen4_trade_art then
    name = "Gen4TradeSequence"
    opts = { sending = mon, receiving = mon, otName = peerName }
    if direction == "send" then
      cut = function(s) return (s.phaseIndex or 1) >= 4 end
    else
      start = function(s) s.phaseIndex, s.phase = 5, nil end
    end
  elseif GameVersion.isGen3() then
    name = "TradeAnim"
    opts = { sent = mon, received = mon, enemyName = peerName,
             playerOt = game.save and game.save.player and game.save.player.name,
             playerOtId = mon.otId, enemyOtId = mon.otId }
    if direction == "send" then
      cut = function(s) return TRADEANIM_AFTER_SEND[s.phase] == true end
    end
  else
    return done()
  end
  LinkState.lastTradeMovie = name .. (direction == "send" and ":send" or ":receive")
  opts.onDone = done
  pcall(function() require("src.core.Sound").play(data, "Trade_Machine") end)
  local ok = pcall(Screens.push, game, name, opts)
  local screen = game.stack:top()
  if not ok or not screen or screen.update == nil then return done() end
  if start then pcall(start, screen) end
  if cut then
    local update = screen.update
    screen.update = function(s, ...)
      local r = update(s, ...)
      if not fired and not s.finished and cut(s) then
        if s.finish then
          s:finish()
        else
          if game.stack:top() == s then game.stack:pop() end
          pcall(function() require("src.core.Music").restoreMap(data) end)
        end
        done()
      end
      return r
    end
  end
end

-- -------------------------------------------------------------------
-- THE BATTLE RULES (Gen 3+, src/online/BattleRules.lua).  The host picks
-- the format (SINGLE / DOUBLE), the level rule (NORMAL or LV.50 FLAT, the
-- Colosseum / B/W "Flat" scale-down) and the clauses; the table rides in
-- its party message and the guest's LinkBattle reads the same one.
-- -------------------------------------------------------------------
LinkState.RULE_ROWS = { "format", "level", "species", "item", "sleep", "start" }

function LinkState.rulesGen()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  local gen = ok and tonumber(GameVersion.generation()) or 1
  return gen or 1
end

function LinkState:ruleChoices()
  local c = self.ruleChoice
  if not c then
    c = { format = "single", flat = false, species = false, item = false, sleep = false }
    self.ruleChoice = c
  end
  return c
end

-- the picks as a BattleRules table (named after the cartridge's preset when
-- one matches)
function LinkState:currentRules()
  local BattleRules = require("src.online.BattleRules")
  local gen = LinkState.rulesGen()
  local c = self:ruleChoices()
  local r = BattleRules.defaults(gen)
  r.format = c.format
  if c.flat then r.level = { mode = "flat", value = 50 } end
  r.speciesClause, r.itemClause, r.sleepClause = c.species, c.item, c.sleep
  for _, p in ipairs(BattleRules.PRESETS[gen] or {}) do
    local plevel = type(p.level) == "table" and p.level.mode == "flat"
    if (p.format or "single") == c.format and plevel == c.flat then r.preset = p.id; break end
  end
  return BattleRules.sanitize(r, gen)
end

function LinkState:updateRulesPicker(input)
  local c = self:ruleChoices()
  self.ruleIndex = self.ruleIndex or 1
  local n = #LinkState.RULE_ROWS
  if input:wasPressed("b") then
    self.net:send({ type = "bye" })
    self:exitWith(nil)
    return
  elseif input:wasPressed("down") then
    self.ruleIndex = self.ruleIndex % n + 1
  elseif input:wasPressed("up") then
    self.ruleIndex = (self.ruleIndex - 2) % n + 1
  elseif input:wasPressed("left") or input:wasPressed("right") or input:wasPressed("a") then
    local row = LinkState.RULE_ROWS[self.ruleIndex]
    if row == "start" then
      if input:wasPressed("a") then
        self.battleRules = self:currentRules()
        self:startMode(self.pendingMode, true)
      end
    elseif row == "format" then
      c.format = c.format == "double" and "single" or "double"
    elseif row == "level" then
      c.flat = not c.flat
    else
      c[row] = not c[row]
    end
  end
end

function LinkState:drawRulesPicker()
  local C = require("src.ui.online.CodeStyle").colors
  local c = self:ruleChoices()
  local on = function(v) return v and Strings("ON") or Strings("OFF") end
  local labels = {
    Strings("FORMAT: %s", c.format == "double" and Strings("DOUBLE") or Strings("SINGLE")),
    Strings("LEVEL: %s", c.flat and Strings("LV.50 FLAT") or Strings("NORMAL")),
    Strings("SPECIES CLAUSE: %s", on(c.species)),
    Strings("ITEM CLAUSE: %s", on(c.item)),
    Strings("SLEEP CLAUSE: %s", on(c.sleep)),
    Strings("START"),
  }
  local okR, BattleRules = pcall(require, "src.online.BattleRules")
  local desc = okR and BattleRules.describe(self:currentRules()) or ""
  local how = self.battleMode == "host" and Strings("The host runs this battle.") or nil
  local lines = { { desc, C.dim } }
  if how then lines[2] = { how, C.dim } end
  self:drawPage({ title = Strings("BATTLE RULES"), items = labels, index = self.ruleIndex or 1,
                  lines = lines })
end

-- -------------------------------------------------------------------
-- transfer flow (verdict "transfer"): Pal Park 3->4 or Poke Transfer 4->5
-- across the link, a one-way gift from the older game to the newer one
-- -------------------------------------------------------------------

function LinkState:startTransfer()
  self.stage = "transfer"
  self.transfer = Protocol.TransferSession.new(self.game.data, self.game.save.party, {
    myHello = self.myHello, peerHello = self.peerHello, pair = self.pair,
    peerName = self.peerName,
  })
  local opening = self.transfer:opening()
  if opening then self.net:send(opening) end
  self.index = 1
end

-- what the receiver can call an offered mon: the nickname the packet
-- carries, else its own records by species
function LinkState:offeredName(packed)
  if type(packed) ~= "table" then return "?" end
  if type(packed.nickname) == "string" and packed.nickname ~= "" then return packed.nickname end
  local def = (self.game.data.pokemon or {})[packed.species]
  if def and def.name then return def.name end
  return tostring(packed.speciesName or packed.species or "?")
end

function LinkState:monName(mon)
  local def = (self.game.data.pokemon or {})[mon.species]
  return mon.nickname or (def and def.name) or tostring(mon.species)
end

function LinkState:updateTransfer(input)
  local t = self.transfer
  for _, msg in ipairs(self.net:poll()) do
    local reply = t:handle(msg)
    if reply then self.net:send(reply) end
  end
  if t.stage == "cancelled" then
    self:exitWith(t.error and Strings("The transfer stopped:\n%s.", tostring(t.error))
                  or Strings("The transfer was\ncancelled."))
    return
  end
  if t.stage == "done" then
    local game = self.game
    local mon = t:apply(game)
    -- saved at once, as a trade is: the sender's mon is already gone
    if game.writeSave then game:writeSave() end
    LinkState.lastTransfer = { direction = t.direction, mon = mon }
    local name = mon and self:monName(mon) or "?"
    local peer = self.peerName or "THEM"
    local text = t.direction == "send" and Strings("%s was sent\nto %s.", name, peer)
                 or Strings("%s sent\n%s over!", peer, name)
    Runtime.emit("link.ended", { reason = "done" })
    game.linkSession = nil -- this path pops without exitWith
    DiscordPresence.setJoinCode(nil)
    self:closeLinkJobs()
    self.net:close()
    game.stack:pop()
    if not mon then
      game.stack:push(TextBox.new(game, text))
      return
    end
    LinkState.oneWayMovie(game, t.direction, mon, peer, function()
      game.stack:push(TextBox.new(game, text))
    end)
    return
  end
  local count = t.direction == "send" and #self.game.save.party or #(t.offer or {})
  if t.stage == "picking" then
    if input:wasPressed("up") then
      self.index = math.max(1, self.index - 1)
    elseif input:wasPressed("down") then
      self.index = math.min(math.max(1, count), self.index + 1)
    elseif input:wasPressed("a") and t:canPick(self.index) then
      local msg = t:pick(self.index)
      if msg then self.net:send(msg) end
      return
    end
  elseif t.stage == "confirming" then
    if input:wasPressed("a") then
      self.net:send(t:accept(true))
      return
    elseif input:wasPressed("b") then
      self.net:send(t:accept(false))
      return
    end
  end
  if input:wasPressed("b") and (t.stage == "picking" or t.stage == "waitOffer"
                                or t.stage == "waitGift") then
    self.net:send({ type = "bye" })
    self:exitWith(Strings("The transfer was\ncancelled."))
  end
end

-- -------------------------------------------------------------------
-- trade flow
-- -------------------------------------------------------------------

function LinkState:updateTrade(input)
  for _, msg in ipairs(self.net:poll()) do
    local reply = self.trade:handle(msg)
    if reply then self.net:send(reply) end
  end
  local t = self.trade

  if t.stage == "cancelled" then
    self:exitWith(t.error and Strings("The trade stopped:\n%s.", t.error)
                  or say(self.game.data, "cancelled",
                         Strings.source("The trade was\ncancelled.")))
    return
  end
  if t.stage == "done" then
    local sent = t.party[t.myPick]
    local received, evoTo, evoRow = t:apply(self.game)
    -- Autosave the instant the swap commits into game.save.party, matching the
    -- Cable Club: pokered engine/link/cable_club.asm calls SaveSAVtoSRAM
    -- (engine/menus/save.asm) right after every trade so the trade is on the
    -- cartridge before the animation runs.  Without this the received mon
    -- lives only in memory until a manual START-menu save, so a force-quit
    -- would lose it and a reset would clone the sent mon (#222).  Guarded so
    -- headless LinkBattle-style fake games with no writeSave are unaffected.
    if self.game.writeSave then self.game:writeSave() end
    local name = received.nickname or self.game.data.pokemon[received.species].name
    -- a link room plays on: the channel stays for the next trade
    if not (self.onRoundEnd and self.onRoundEnd(self, "trade")) then
      Runtime.emit("link.ended", { reason = "done" })
      self.game.linkSession = nil -- this path pops without exitWith
      self:closeLinkJobs()
      self.net:close()
      self.game.stack:pop()
    end
    local game = self.game
    require("src.core.Sound").play(game.data, "Trade_Machine")
    -- Each generation's own cable movie: Gen 2's TradeAnimation
    -- (Gen2TradeAnim) on a Gen 2 dataset, Red's InternalClockTradeAnim
    -- everywhere else (Gen 3+ keep it, with their own TradeText lines).
    -- On the cartridge the side that drives the clock plays the
    -- "player first" sequence and the other side the mirrored one
    -- (ExternalClockTradeAnim / TradeAnimationPlayer2); the host stands in
    -- for the internally clocked side.
    --
    -- Gen 4 and Gen 5 play their own trade movie (Gen4TradeSequence /
    -- Gen5TradeSequence, the ones the in-game NPC trades already use) when
    -- the cache carries its art; Gen 3 keeps Red's cable movie.
    local GameVersion = require("src.core.GameVersion")
    local classic = GameVersion.isGen1() or GameVersion.isGen2()
    local data = game.data or {}
    local movie, movieOpts = GameVersion.isGen2() and "Gen2TradeAnim" or "TradeAnim", nil
    if GameVersion.isGen5() and data.gen5_trade_art then
      movie = "Gen5TradeSequence"
    elseif GameVersion.isGen4() and data.gen4_trade_art then
      movie = "Gen4TradeSequence"
    end
    local afterMovie
    if movie == "Gen4TradeSequence" or movie == "Gen5TradeSequence" then
      movieOpts = { sending = sent, receiving = received, otName = self.peerName or "TRAINER" }
    else
      movieOpts = {
        externalClock = classic and not self.isHost or nil,
        sent = sent, received = received,
        enemyName = (self.peerName or "TRAINER"),
        playerOt = game.save.player.name,
        playerOtId = sent.otId or game.save.player.id,
        enemyOtId = received.otId,
      }
    end
    LinkState.lastTradeMovie = movie
    movieOpts.onDone = function() afterMovie() end
    afterMovie = function()
        game.stack:push(TextBox.new(game,
          Strings("Trade completed!\f%s received\n%s!", game.save.player.name, name),
          function()
            if evoTo then
              -- via="TRADE": a trade evolution cannot be B-cancelled
              -- (pokered LINK_STATE_TRADING skips the flash B-poll) (#213).
              -- Re-save once the evolution movie finishes so the evolved
              -- species (not the pre-evo landed by t:apply) is what persists,
              -- keeping disk in step with the autosave above (#222).
              -- evoRow rides along so an item-gated evolution consumes the
              -- METAL COAT / KING'S ROCK / DRAGON SCALE / UP-GRADE it needed
              require("src.pokemon.Evolution").evolve(game, received, evoTo,
                function() if game.writeSave then game:writeSave() end end,
                "TRADE", evoRow)
            end
          end))
    end
    Screens.push(game, movie, movieOpts)
    return
  end

  if t.stage == "picking" and input:wasPressed("up") then
    self.index = math.max(1, self.index - 1)
  elseif t.stage == "picking" and input:wasPressed("down") then
    self.index = math.min(#self.game.save.party, self.index + 1)
  elseif self.confirmed == nil and input:wasPressed("b") then
    -- once confirm=true has been sent to the peer, backing out here
    -- would desync the two sides (the peer may already be committing
    -- the trade) -- B is dead after that, matching the A branch's own
    -- self.confirmed == nil guard
    self.net:send({ type = "bye" })
    self:exitWith(say(self.game.data, "cancelled",
                      Strings.source("The trade was\ncancelled.")))
  elseif t.stage == "picking" and input:wasPressed("a") then
    if t:canPick(self.index) then
      self.net:send(t:pick(self.index))
    end
  elseif t.stage == "confirming" and self.confirmed == nil then
    if input:wasPressed("a") then
      self.confirmed = true
      self.net:send(t:confirm(true))
    end
  end
end

-- -------------------------------------------------------------------
-- draw
--
-- In the game's own look: its font and its window frame (CodeStyle "game",
-- the same kit ShowCode and LongCodeEntry draw with), on the surface this
-- game's screens use -- 160x144 on the Game Boy, 240x160 on the GBA,
-- 256x192 on the DS.  A dataset with no font gets the neutral look.
-- -------------------------------------------------------------------

function LinkState:uiSize()
  if not self.surfaceW then
    self.surfaceW, self.surfaceH = require("src.ui.online.CodeStyle").surface({})
  end
  return self.surfaceW, self.surfaceH
end

function LinkState:getStyle()
  if not self.style then
    local CodeStyle = require("src.ui.online.CodeStyle")
    self.style = CodeStyle.new(CodeStyle.defaultKind(self.game))
  end
  return self.style
end

local function tileUp(v) return math.ceil(v / 8) * 8 end

function LinkState:metrics()
  local st = self:getStyle()
  local W, H = self:uiSize()
  local lh = st:lineHeight()
  local M = { W = W, H = H, lh = lh }
  M.titleH = tileUp(lh + 16)
  M.left = 8
  M.top = M.titleH + 8
  M.itemX = 24
  -- the small screens (GB 160x144, GBA 240x160) set rows tight so the
  -- help line under them still fits
  M.pitch = math.max(12, lh + (H > 160 and 4 or 0))
  M.lineStep = math.max(10, lh + 2)
  M.bottom = H - 8 -- the last text row ends here
  return M
end

function LinkState:drawCursorAt(x, y)
  local st = self:getStyle()
  if st.kind == "game" then
    local ok, Theme = pcall(require, "src.ui.Theme")
    local code = (ok and Theme.cursor) or CURSOR
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawCode(code, x, y)
    love.graphics.setColor(1, 1, 1, 1)
  else
    st:text(">", x, y)
  end
end

-- one framed page: title window, then a body window holding the items (a
-- cursor on `index`), the text lines and a footer row
function LinkState:drawPage(page)
  local st = self:getStyle()
  local M = self:metrics()
  local C = require("src.ui.online.CodeStyle").colors
  st:clear(M.W, M.H)
  st:box(0, 0, M.W, M.titleH)
  st:text(page.title or "", M.left, math.floor((M.titleH - M.lh) / 2))
  st:box(0, M.titleH, M.W, M.H - M.titleH)
  local y = M.top
  for i, label in ipairs(page.items or {}) do
    st:text(label, M.itemX, y, page.dim and page.dim[i] and C.dim or nil)
    if i == page.index then self:drawCursorAt(M.itemX - 12, y) end
    y = y + M.pitch
  end
  if page.items and #page.items > 0 then y = y + math.floor(M.pitch / 4) end
  local footerY = M.bottom - M.lh
  local lastY = (page.footer and footerY - 2 or M.bottom) - M.lh
  for _, line in ipairs(page.lines or {}) do
    local text, color = line, nil
    if type(line) == "table" then text, color = line[1], line[2] end
    for _, w in ipairs(st:wrap(text, M.W - 2 * M.left)) do
      if y > lastY then break end
      st:text(w, M.left, y, color)
      y = y + M.lineStep
    end
  end
  if page.footer then st:text(page.footer, M.left, footerY, C.dim) end
  love.graphics.setColor(1, 1, 1, 1)
end

local RUNG_STATE = { trying = "...", ok = "OK", failed = "no", skipped = "-" }

function LinkState:draw()
  local C = require("src.ui.online.CodeStyle").colors
  local stage = self.stage
  if stage == "menu" then
    local items, labels = self:menuItems(), {}
    for i, item in ipairs(items) do labels[i] = item.label end
    local cur = items[self.index] or items[1]
    self:drawPage({ title = Strings("LINK"), items = labels, index = self.index,
                    lines = { { Strings(LinkState.MENU_HELP[cur.id] or ""), C.dim } } })

  elseif stage == "hostPrep" then
    local h = self.hostJob
    local lines = { Strings("Opening the link...") }
    if h and h.pending and h.state == "listening" then
      lines[#lines + 1] = Strings("Asking your router to open the port...")
    end
    self:drawPage({ title = Strings("HOST"), lines = lines, footer = Strings("B: back") })

  elseif stage == "relayPrep" then
    self:drawPage({ title = Strings("SHORT CODE"),
                    lines = { Strings("Asking the relay for a room...") },
                    footer = Strings("B: back") })

  elseif stage == "hostWait" or stage == "relayWait" then
    self:drawPage({ title = Strings("HOST"), lines = { Strings("Waiting for a friend...") } })

  elseif stage == "joining" then
    local job = self.joinJob
    local lines = {}
    if job then
      for _, e in ipairs(job.log or {}) do
        local name = e.rung
        local okC, Connector = pcall(require, "src.online.net.Connector")
        if okC then name = Connector.RUNG_NAMES[e.rung] or e.rung end
        lines[#lines + 1] = { ("%s: %s"):format(name, RUNG_STATE[e.state] or e.state),
                              e.state == "ok" and C.good or (e.state == "failed" and C.bad or nil) }
      end
      if job.progress then lines[#lines + 1] = { job.progress, C.dim } end
    else
      lines[1] = Strings("Calling...")
    end
    self:drawPage({ title = Strings("CONNECTING..."), lines = lines, footer = Strings("B: cancel") })

  elseif stage == "joinFailed" then
    local lines = {}
    for line in tostring(self.failReason or ""):gmatch("[^\n]+") do
      lines[#lines + 1] = { line, C.dim }
    end
    local labels = {}
    for i, id in ipairs(LinkState.JOIN_FAILED_ITEMS) do
      labels[i] = Strings(LinkState.JOIN_FAILED_LABELS[id])
    end
    local help = {
      swap = "You host; they join you.",
      both = "You host too; both enter codes.",
      retry = "Enter the code again.", back = "",
    }
    lines[#lines + 1] = { Strings(help[LinkState.JOIN_FAILED_ITEMS[self.index]] or ""), C.dim }
    self:drawPage({ title = Strings("COULDN'T CONNECT"), items = labels,
                    index = self.index, lines = lines })

  elseif stage == "joinList" then
    local items, labels, dim = self:joinListItems(), {}, {}
    for i, item in ipairs(items) do labels[i] = item.label; dim[i] = item.dim end
    local l = self.lanListener
    local lines = {}
    if l and l.error then
      lines[1] = { tostring(l.error), C.dim }
    elseif #items == 1 then
      lines[1] = { Strings("Looking for games on your network..."), C.dim }
    else
      lines[1] = { Strings("Games on your network."), C.dim }
    end
    self:drawPage({ title = Strings("JOIN"), items = labels, dim = dim,
                    index = self.index, lines = lines })

  elseif stage == "hubDoor" then
    self:drawPage({ title = Strings("LINK HUB"), lines = { Strings("Calling your friend's Link Hub...") },
                    footer = Strings("B: back") })

  elseif stage == "hubDoorReady" then
    local pong = self.hubDoor and self.hubDoor.pong or {}
    local labels = {}
    for i, item in ipairs(self:hubDoorItems()) do labels[i] = item.label end
    local lines
    if pong.worldCode then
      lines = { { Strings("Hub saved. %s has a world open.", tostring(pong.name or "Your friend")), C.dim } }
    else
      lines = { { Strings("Hub saved: now HOST to get a code friends can join through it."), C.dim } }
    end
    self:drawPage({ title = Strings("LINK HUB"), items = labels, index = self.index, lines = lines })

  elseif stage == "failed" then
    local f = self.failure or {}
    local lines = {}
    for _, l in ipairs(f.lines or {}) do lines[#lines + 1] = { l, C.bad } end
    self:drawPage({ title = f.title or Strings("LINK"), lines = lines, footer = Strings("A: back") })

  elseif stage == "lanMenu" then
    self:drawPage({ title = Strings("ADVANCED (IP)"),
                    items = { Strings("HOST A GAME"), Strings("JOIN A GAME") }, index = self.index,
                    lines = { { Strings("UDP port %s", Net.defaultPort()), C.dim } } })

  elseif stage == "hosting" then
    self:drawPage({ title = Strings("HOSTING"),
                    lines = { Strings("Friend joins at:"), (self.net and self.net.address) or "?",
                              Strings("Waiting for join...") } })

  elseif stage == "addrEntry" then
    self:drawPage({ title = Strings("ENTER HOST ADDRESS"), footer = Strings("A: connect  B: back") })
    local st, M = self:getStyle(), self:metrics()
    local y = M.top + M.pitch
    for i = 1, 12 do
      local octet = math.floor((i - 1) / 3) -- 0..3
      local x = 16 + (i - 1) * 8 + octet * 8 -- gap for the dots
      st:text(tostring(self.addr[i]), x, y)
      if i == self.addrPos then st:text("^", x, y + M.lh) end
    end
    for octet = 1, 3 do st:text(".", 16 + octet * 32 - 8, y) end
    st:text(Strings("Port: %s", Net.defaultPort()), 16, y + M.pitch * 2)
    love.graphics.setColor(1, 1, 1, 1)

  elseif stage == "lanJoining" or stage == "onlineJoining" then
    self:drawPage({ title = Strings("JOINING..."),
                    lines = { Strings("Calling..."), (self.net and self.net.target) or "" } })

  elseif stage == "modeSelect" then
    local lines = {}
    if self.linkPath then
      local okC, Connector = pcall(require, "src.online.net.Connector")
      lines[1] = { okC and Connector.describe(self.linkPath) or self.linkPath, C.dim }
    end
    self:drawPage({ title = Strings("CONNECTED!"),
                    items = { Strings("TRADE"), Strings("BATTLE") }, index = self.index,
                    lines = lines })

  elseif stage == "battleOptions" and LinkState.rulesGen() >= 3 then
    self:drawRulesPicker()

  elseif stage == "battleOptions" then
    self:drawPage({ title = Strings("BATTLE OPTIONS"),
                    lines = { Strings("LEVELS: %s", forceLevelLabel(self.levelChoice or ANY)) },
                    footer = Strings("A: continue  B: back") })

  elseif stage == "waitMode" or stage == "waitHello" then
    self:drawPage({ title = Strings("CONNECTED!"), lines = {
      stage == "waitHello" and Strings("Checking the other game...")
        or Strings("Waiting for the host to choose...") } })

  elseif stage == "notice" then
    local lines = {}
    for _, l in ipairs(self.noticeLines or {}) do lines[#lines + 1] = l end
    local footer
    if self.noticeExits then footer = "A: back"
    elseif self.noticeTransfer then footer = Strings("A: transfer  B: back")
    else footer = Strings("A: trade anyway") end
    self:drawPage({ title = Strings(self.noticeTitle or "CHECK YOUR MODS"), lines = lines,
                    footer = footer })

  elseif stage == "trade" then
    self:drawTrade()

  elseif stage == "transfer" then
    self:drawTransfer()

  elseif stage == "battleWait" or stage == "battleRunning" then
    self:drawPage({ title = Strings("LINK BATTLE"), lines = { Strings("Exchanging data...") } })
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- two lists side by side, YOURS and THEIRS, and one hint row under them
function LinkState:drawTrade()
  local st, M = self:getStyle(), self:metrics()
  local C = require("src.ui.online.CodeStyle").colors
  local data = self.game.data
  local t = self.trade
  self:drawPage({ title = say(data, "trade", "TRADE") })
  local half = math.floor(M.W / 2)
  local maxChars = math.max(6, math.floor((half - 20) / math.max(6, st:width("M"))))
  local y0 = M.top
  st:text(Strings("YOURS"), M.left, y0, C.dim)
  st:text(Strings("THEIRS"), half + 4, y0, C.dim)
  local step = math.max(M.lh + 2, math.floor((M.bottom - M.lh - 4 - y0 - M.lh) / 6))
  for i, mon in ipairs(self.game.save.party) do
    local label = self:monName(mon):sub(1, maxChars)
    local y = y0 + i * step
    st:text(label, M.left + 8, y, (not t:canPick(i)) and C.dim or nil)
    if not t:canPick(i) then st:text("x", M.left + 8 + st:width(label) + 2, y, C.bad) end
    if i == self.index then self:drawCursorAt(M.left - 4, y) end
  end
  for i, mon in ipairs(t.theirParty or {}) do
    local y = y0 + i * step
    st:text(self:monName(mon):sub(1, maxChars), half + 12, y)
    if t.theirPick == i then self:drawCursorAt(half + 2, y) end
  end
  -- ONE LINE, AND IT HAS TO FIT.  The cartridge's own lines are written
  -- for a two-row window and carry their own break; this is a single row
  -- under the two lists, so a break becomes a space and the line is
  -- trimmed rather than drawn off the edge of the screen.
  local hint
  if t.stage == "waitRecords" then hint = "Comparing games..."
  elseif t.stage == "waitParty" then
    hint = say(data, "standby", "Exchanging data...")
  elseif t.stage == "picking" then
    hint = t:canPick(self.index)
           and say(data, "choose", "Pick one to trade")
           or ((t.reasons and t.reasons[self.index]) and tostring(t.reasons[self.index]))
           or say(data, "monRefused", "X: not on theirs")
  elseif t.stage == "waitPick" then
    hint = say(data, "waiting", "Waiting for them...")
  elseif t.stage == "confirming" then
    hint = self.confirmed and say(data, "waiting", "Waiting...")
           or say(data, "confirmTrade", "A: trade  B: cancel")
  end
  local text = oneLine(hint)
  while #text > 1 and st:width(text) > M.W - 2 * M.left do text = text:sub(1, -2) end
  st:text(text, M.left, M.bottom - M.lh)
  love.graphics.setColor(1, 1, 1, 1)
end

-- the one-way gift: the sender's party (refused mons greyed, with the
-- reason on the hint row), or the receiver's view of the offer
function LinkState:drawTransfer()
  local st, M = self:getStyle(), self:metrics()
  local C = require("src.ui.online.CodeStyle").colors
  local t = self.transfer
  local palPark = t.route == "palpark"
  self:drawPage({ title = palPark and Strings("PAL PARK") or Strings("POKÃ© TRANSFER") })
  local y0 = M.top
  local step = math.max(M.lh + 2, math.floor((M.bottom - 2 * M.lh - 6 - y0) / 6))
  local hint
  if t.direction == "send" then
    st:text(Strings("Send one to %s:", self.peerName or "THEM"), M.left, y0, C.dim)
    for i, mon in ipairs(self.game.save.party) do
      local y = y0 + i * step
      st:text(self:monName(mon), M.left + 8, y, (not t:canPick(i)) and C.dim or nil)
      if i == self.index then self:drawCursorAt(M.left - 4, y) end
    end
    if t.stage == "picking" then
      hint = t:canPick(self.index) and Strings("A: send  B: cancel")
             or tostring(t.reasons[self.index] or Strings("It can't go."))
    else
      hint = Strings("Waiting for them...")
    end
  else
    st:text(Strings("%s is sending:", self.peerName or "THEY"), M.left, y0, C.dim)
    for i, packed in ipairs(t.offer or {}) do
      st:text(self:offeredName(packed), M.left + 8, y0 + i * step)
    end
    if t.stage == "confirming" and t.gift then
      hint = Strings("Take %s? A: yes B: no", self:monName(t.gift))
    elseif t.stage == "waitCommit" then
      hint = Strings("Receiving...")
    else
      hint = Strings("Waiting for them to choose...")
    end
  end
  for i, w in ipairs(st:wrap(hint or "", M.W - 2 * M.left)) do
    if i > 2 then break end
    st:text(w, M.left, M.bottom - (3 - i) * M.lh)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return LinkState
