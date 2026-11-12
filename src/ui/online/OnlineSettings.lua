-- ONLINE SETTINGS (docs/online-design.md 2.6 "SETTINGS", workstream WS10).
--
-- One screen for everything the online layer reads from save.options.online
-- (LinkState.settings is the reader; this is the writer):
--
--   PORT          the UDP port this game hosts on (7777)
--   ROUTER        ask the router to open that port: UPnP / NAT-PMP / PCP (on)
--   RELAY         short 6-letter codes and tournaments go through the relay
--                 (or the player's hub); direct codes never do (on)
--   ADDR FINDER   STUN: ask a public server for this machine's internet
--                 address.  It contacts a third party, so it is off
--   LAN LIST      lanBeacon: a host announces itself so JOIN lists it (on)
--   LINK HUB      a self-hosted Link Hub "host:port"; empty = default relay
--   MY ADDRESS    a forwarded port's public IP or DNS name; empty = auto
--   WORLD SIZE    players in a hosted world, 2..16 (8)
--   NAME          what other players see; empty = the trainer's name
--   PRIVACY       whether codes carry the internet address, and the note
--   CONN TEST     LAN address, the router's answer, the public IP it reports
--                 and whether friends should be able to get in (ConnTest.lua);
--                 talks to the router only
--   STATUS        Platform.online(): what this device can do, and why not
--   DEFAULTS / DONE
--
-- Driven by d-pad / gamepad (Input), keyboard (onKeyPressed / onTextInput:
-- text fields take typing, Ctrl+V pastes) and touch (touchpressed; tapping a
-- text field brings up a phone's keyboard).  Drawn through CodeStyle in the
-- loaded game's own font and frames ("game") or plain LÖVE ("neutral", for
-- the launcher and tests).
--
-- USE:
--   OnlineSettings.open(game)                  -- in game (OPTIONS -> ONLINE)
--   OnlineSettings.new(game_or_nil, {          -- any host
--     options = tbl,        -- the options table to edit (default game.save.options)
--     persist = fn(opts),   -- after each change (default game:writeOptions())
--     onClose = fn(),
--     style = "game" | "neutral", width = , height = ,
--     platform = Platform.online() result (tests),
--   })
--   A host without game.input feeds buttons through screen:press("up"|"down"|
--   "left"|"right"|"a"|"b"|"start"|"select") and keys through onKeyPressed.
--
-- OnlineSettings.Model is pure (no love), for tests.

local OnlineSettings = {}
OnlineSettings.__index = OnlineSettings
OnlineSettings.isOpaque = true

-- ===================================================================== model

local Model = {}
OnlineSettings.Model = Model

-- the shape LinkState.settings reads (src/link/LinkState.lua SETTING_DEFAULTS),
-- plus displayName, which WS8's worlds and the link hello may show
Model.DEFAULTS = {
  port = 7777, allowRelay = true, portMap = true, stun = true,
  manualAddress = nil, hubAddress = nil, worldCap = 8, lanBeacon = true,
  displayName = nil,
}
Model.KEYS = { "port", "allowRelay", "portMap", "stun", "manualAddress",
               "hubAddress", "worldCap", "lanBeacon", "displayName", "stunChosen" }
Model.PORT_MIN, Model.PORT_MAX = 1024, 65535
Model.CAP_MIN, Model.CAP_MAX = 2, 16
Model.NAME_MAX = 12      -- WorldProtocol.NAME_MAX
Model.ADDRESS_MAX = 64

local function trim(v)
  if type(v) ~= "string" then return nil end
  v = v:gsub("^%s+", ""):gsub("%s+$", "")
  if v == "" then return nil end
  return v
end

-- printable ASCII only, at most NAME_MAX, inner runs of space collapsed
function Model.cleanName(text)
  local t = trim(text)
  if not t then return nil end
  t = t:gsub("%s+", " "):gsub("[^\32-\126]", "")
  t = trim(t)
  if not t then return nil end
  return t:sub(1, Model.NAME_MAX)
end

-- "host" or "host:port"; host is a dotted IPv4 or a DNS name.
-- Returns the cleaned address, or nil and why (nil, nil for empty).
function Model.cleanAddress(text)
  local t = trim(text)
  if not t then return nil, nil end
  t = t:lower()
  if #t > Model.ADDRESS_MAX then return nil, "That address is too long." end
  if t:find("[^%w%.%-:]") then return nil, "Use letters, digits, dots and one colon." end
  local host, port = t:match("^([^:]+):(%d+)$")
  if not host then
    if t:find(":") then return nil, "Write it as name:port, e.g. hub.example.net:7777." end
    host = t
  end
  if port then
    local p = tonumber(port)
    if not p or p < 1 or p > 65535 then return nil, "The port must be 1 to 65535." end
  end
  if host:match("^[%d%.]+$") then
    local a, b, c, d = host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil, "An IP address has four numbers, e.g. 203.0.113.5." end
    for _, o in ipairs({ a, b, c, d }) do
      if tonumber(o) > 255 then return nil, "Each number of an IP address is 0 to 255." end
    end
  elseif host:find("^[%.%-]") or host:find("[%.%-]$") or host:find("%.%.") then
    return nil, "That is not a valid name."
  end
  return t
end

function Model.validPort(v)
  v = tonumber(v)
  return v ~= nil and v == math.floor(v) and v >= Model.PORT_MIN and v <= Model.PORT_MAX
end

-- the same normalisation as LinkState.settings, so this screen shows exactly
-- what a link session will use (tests check the two agree)
function Model.read(options)
  local raw = type(options) == "table" and type(options.online) == "table"
              and options.online or {}
  local s = {}
  for k, v in pairs(Model.DEFAULTS) do s[k] = v end
  for _, k in ipairs(Model.KEYS) do
    if raw[k] ~= nil then s[k] = raw[k] end
  end
  local port = tonumber(s.port)
  if not port or port ~= math.floor(port) or port < 0 or port > 65535 then port = 7777 end
  s.port = port
  s.allowRelay = s.allowRelay ~= false
  s.portMap = s.portMap ~= false
  -- saves written before STUN went on by default hold stun = false that
  -- nobody chose: only an OFF the player set themselves (stunChosen) counts
  s.stun = s.stun ~= false or s.stunChosen ~= true
  s.stunChosen = s.stunChosen == true or nil
  s.lanBeacon = s.lanBeacon ~= false
  s.manualAddress = trim(s.manualAddress)
  s.hubAddress = trim(s.hubAddress)
  local cap = math.floor(tonumber(s.worldCap) or 8)
  s.worldCap = math.max(Model.CAP_MIN, math.min(Model.CAP_MAX, cap))
  s.displayName = Model.cleanName(s.displayName)
  return s
end

-- write `s` into options.online, keeping every key this screen does not own
-- (test-only bind/lanIp, the one-time tip flags).  Returns options.online.
function Model.write(options, s)
  if type(options.online) ~= "table" then options.online = {} end
  local o = options.online
  for _, k in ipairs(Model.KEYS) do o[k] = s[k] end
  -- empty text is "not set", which the reader turns into the default
  if o.manualAddress == "" then o.manualAddress = nil end
  if o.hubAddress == "" then o.hubAddress = nil end
  if o.displayName == "" then o.displayName = nil end
  return o
end

function Model.reset(s)
  for k in pairs(s) do s[k] = nil end
  for k, v in pairs(Model.DEFAULTS) do s[k] = v end
  return s
end

-- does a direct code from this machine carry the internet address?  Only when
-- something can find it: the router, the finder, or a typed address.
function Model.codesShowIp(s)
  return s.portMap == true or s.stun == true or s.manualAddress ~= nil
end

-- ===================================================================== rows

local PRIVACY_NOTE = "A direct code holds the address your friends' games connect to. "
  .. "When the router, the address finder or MY ADDRESS can find your internet address, "
  .. "the code carries it, and anyone you give the code to can see it. "
  .. "Share codes only with people you trust. For a code that works on your own network only, "
  .. "turn ROUTER and ADDR FINDER off and leave MY ADDRESS empty. "
  .. "Short codes go through the relay or your hub and do not show your address."

OnlineSettings.PRIVACY_NOTE = PRIVACY_NOTE

OnlineSettings.SWITCH_WARNING = "Going online with homebrew on a Nintendo Switch can get the console "
  .. "banned from Nintendo's online services. Linking here talks only to other players' games, "
  .. "never to Nintendo, but the risk is yours. Continue only if you accept it."

OnlineSettings.FIREWALL_TIP = "Windows may ask whether this game can use the network the first "
  .. "time you host. Choose Allow on Private networks so friends can join. If you pressed Cancel, "
  .. "open Windows Security, Firewall, Allow an app, and tick Private for this game."

-- the same, short enough for the line under a host code
OnlineSettings.FIREWALL_TIP_SHORT = "If Windows asks about the firewall, choose Allow (Private networks)."

-- kind: toggle | number | text | info | action
local ROWS = {
  { id = "port", label = "PORT", kind = "number", key = "port",
    min = Model.PORT_MIN, max = Model.PORT_MAX,
    help = "The UDP port your game listens on when you host. Keep 7777 unless your router forwards another." },
  { id = "portMap", label = "ROUTER", long = "ROUTER OPENING", kind = "toggle", key = "portMap",
    help = "Ask your router to open the port (UPnP / NAT-PMP). Off: friends elsewhere need a port you forwarded." },
  { id = "allowRelay", label = "RELAY", long = "RELAY (SHORT CODES)", kind = "toggle", key = "allowRelay",
    help = "Short 6-letter codes and tournaments go through the relay, or your hub. Direct codes never use it." },
  { id = "stun", label = "ADDR FINDER", long = "ADDRESS FINDER (STUN)", kind = "toggle", key = "stun",
    help = "Ask a public STUN server for your internet address, so friends can reach you when the router won't open the port. Off: only router opening or a forwarded port." },
  { id = "lanBeacon", label = "LAN LIST", long = "LIST ON THIS NETWORK", kind = "toggle", key = "lanBeacon",
    help = "While you host, tell games on the same network, so their JOIN lists yours. Nothing leaves your network." },
  { id = "hubAddress", label = "LINK HUB", kind = "text", key = "hubAddress", charset = "address",
    max = Model.ADDRESS_MAX, empty = "RELAY",
    help = "Your own Link Hub as name:port. Short codes and tournaments use it instead of the default relay." },
  { id = "manualAddress", label = "MY ADDRESS", kind = "text", key = "manualAddress", charset = "address",
    max = Model.ADDRESS_MAX, empty = "AUTO",
    help = "Your public IP or name, if you forwarded the port yourself. Empty: found automatically." },
  { id = "worldCap", label = "WORLD SIZE", long = "WORLD PLAYERS", kind = "number", key = "worldCap",
    min = Model.CAP_MIN, max = Model.CAP_MAX,
    help = "The most players in a world you host, you included. 8 by default, at most 16." },
  { id = "displayName", label = "NAME", long = "DISPLAY NAME", kind = "text", key = "displayName", charset = "name",
    max = Model.NAME_MAX, empty = "TRAINER",
    help = "The name other players see. Empty: your trainer's name." },
  { id = "look", label = "MY LOOK", long = "MY ONLINE LOOK", kind = "action",
    help = "The character and colour other players see you as in worlds and link rooms." },
  { id = "connTest", label = "CONN TEST", long = "CONNECTION TEST", kind = "action",
    help = "Ask your router to open the port, then say whether friends should reach you. Talks to the router only." },
  { id = "privacy", label = "PRIVACY", long = "MY IP IN CODES", kind = "info",
    help = "Whether your direct codes show your internet address. A: read the note." },
  { id = "status", label = "STATUS", long = "THIS DEVICE", kind = "info",
    help = "What online play can do on this device. A: details." },
  { id = "defaults", label = "DEFAULTS", kind = "action",
    help = "Put every online setting back to its default." },
  { id = "done", label = "DONE", kind = "action", help = "Save and leave." },
}
OnlineSettings.ROWS = ROWS

local CHARSETS = {
  address = "abcdefghijklmnopqrstuvwxyz0123456789.-:",
  name = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -.",
  number = "0123456789",
}

-- what a keyboard may type into a field of `charset`
local function typable(charset, ch)
  if charset == "number" then return ch:match("^%d$") ~= nil end
  if charset == "address" then return ch:match("^[%w%.%-:]$") ~= nil end
  return ch:match("^[\32-\126]$") ~= nil
end

-- ===================================================================== key grid

local Grid = {}
OnlineSettings.Grid = Grid
Grid.COLS = 10

function Grid.cells(charsetName)
  local cs = CHARSETS[charsetName] or CHARSETS.name
  local cells = {}
  for i = 1, #cs do
    local ch = cs:sub(i, i)
    cells[#cells + 1] = { id = ch, label = ch == " " and "SP" or ch,
                          col = (i - 1) % Grid.COLS, row = math.floor((i - 1) / Grid.COLS), span = 1 }
  end
  local n = #cs
  cells[#cells + 1] = { id = "del", label = "DEL", col = n % Grid.COLS, row = math.floor(n / Grid.COLS),
                        span = (n % Grid.COLS == Grid.COLS - 1) and 1 or 2 }
  local last = math.floor(n / Grid.COLS) + 1
  cells[#cells + 1] = { id = "paste", label = "PASTE", col = 0, row = last, span = 3 }
  cells[#cells + 1] = { id = "clear", label = "CLEAR", col = 3, row = last, span = 3 }
  cells[#cells + 1] = { id = "ok", label = "OK", col = 6, row = last, span = 4 }
  return cells, last + 1
end

function Grid.move(cells, rows, index, dx, dy)
  local cur = cells[index]
  if dx ~= 0 then
    local row = {}
    for i, c in ipairs(cells) do if c.row == cur.row then row[#row + 1] = i end end
    table.sort(row, function(a, b) return cells[a].col < cells[b].col end)
    for k, i in ipairs(row) do
      if i == index then return row[(k - 1 + dx) % #row + 1] end
    end
    return index
  end
  local cx = cur.col + cur.span / 2
  local target = (cur.row + dy) % rows
  local best, bestD
  for i, c in ipairs(cells) do
    if c.row == target then
      local d = (cx >= c.col and cx < c.col + c.span) and 0 or math.abs(c.col + c.span / 2 - cx)
      if not bestD or d < bestD then best, bestD = i, d end
    end
  end
  return best or index
end

function Grid.find(cells, id)
  for i, c in ipairs(cells) do if c.id == id then return i end end
end

-- ===================================================================== screen

local function playSound(game, name)
  if not (game and game.data) then return end
  pcall(function() require("src.core.Sound").play(game.data, name) end)
end

local function platformInfo(opts)
  if opts and opts.platform then return opts.platform end
  local ok, Platform = pcall(require, "src.core.Platform")
  if ok and Platform and Platform.online then
    local okO, info = pcall(Platform.online)
    if okO and info then return info end
  end
  return { available = false, reason = "Could not check this device's network support." }
end

function OnlineSettings.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, OnlineSettings)
  self.game = game
  self.opts = opts
  self.options = opts.options or (game and game.save and game.save.options) or {}
  self.s = Model.read(self.options)
  self.rows = ROWS
  self.index = 1
  self.scroll = 0
  self.platform = platformInfo(opts)
  local CodeStyle = require("src.ui.online.CodeStyle")
  self.width, self.height = CodeStyle.surface(opts)
  self.styleKind = opts.style or CodeStyle.defaultKind(game)
  self.osName = opts.osName or self.platform.os
    or (love and love.system and love.system.getOS and love.system.getOS())
  -- the Switch: say the ban risk before anything else, once per install
  local o = type(self.options.online) == "table" and self.options.online or {}
  if self.platform.consent == "homebrew" and not o.homebrewRiskAccepted then
    self:showSwitchWarning()
  end
  return self
end

function OnlineSettings.open(game, opts)
  local screen = OnlineSettings.new(game, opts)
  game.stack:push(screen)
  return screen
end

function OnlineSettings:uiSize() return self.width, self.height end

function OnlineSettings:persist()
  Model.write(self.options, self.s)
  if self.opts.persist then
    pcall(self.opts.persist, self.options)
  elseif self.game and self.game.writeOptions then
    pcall(self.game.writeOptions, self.game)
  end
end

function OnlineSettings:close()
  if self.softKeyboard and love and love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, false)
    self.softKeyboard = nil
  end
  self.closed = true
  local game = self.game
  if game and game.stack and game.stack.top and game.stack:top() == self then game.stack:pop() end
  if self.opts.onClose then self.opts.onClose() end
end

-- ------------------------------------------------------------ values

function OnlineSettings:statusWord()
  local p = self.platform
  if p.available then
    if p.consent == "homebrew" then return "AT RISK" end
    return "READY"
  end
  if p.relayOnly then return "RELAY ONLY" end
  return "OFF"
end

function OnlineSettings:valueText(row)
  local s = self.s
  if row.kind == "toggle" then return s[row.key] and "ON" or "OFF" end
  if row.kind == "number" then return tostring(s[row.key]) end
  if row.kind == "text" then
    local v = s[row.key]
    local okO, OH = pcall(require, "src.online.OfficialHub")
    if okO and v then v = OH.mask(v) end
    return v or row.empty
  end
  if row.id == "privacy" then return Model.codesShowIp(s) and "IN CODES" or "LAN ONLY" end
  if row.id == "status" then return self:statusWord() end
  return ""
end

-- the row is shown but cannot change on this device
function OnlineSettings:rowDisabled(row)
  local p = self.platform
  if row.id == "portMap" then return p.canPortMap == false end
  -- the beacon is broadcast UDP: iOS has no multicast entitlement and a
  -- build without LuaSocket has no UDP socket.  (Android without a
  -- multicast lock can still announce; only its own listing goes deaf.)
  if row.id == "lanBeacon" then
    return p.hasSocket == false or (p.canBroadcast == false and p.os ~= "Android")
  end
  return false
end

function OnlineSettings:helpText(row)
  if row.id == "status" then
    local p = self.platform
    return p.reason or "Hosting, joining and worlds all work here."
  end
  if row.id == "lanBeacon" and self:rowDisabled(row) then
    return "This device cannot broadcast on the network. Friends can still join with your code."
  end
  if row.id == "portMap" and self:rowDisabled(row) then
    return "This device cannot ask the router (no LuaSocket). Forward the port by hand and fill MY ADDRESS."
  end
  return row.help
end

-- ------------------------------------------------------------ changes

function OnlineSettings:changed()
  self:persist()
end

function OnlineSettings:step(row, dir)
  local s = self.s
  if row.kind == "toggle" then
    if self:rowDisabled(row) then playSound(self.game, "Wrong") return false end
    s[row.key] = not s[row.key]
    if row.key == "stun" then s.stunChosen = true end
  elseif row.kind == "number" then
    local v = (tonumber(s[row.key]) or row.min) + dir
    if v > row.max then v = row.min elseif v < row.min then v = row.max end
    s[row.key] = v
  else
    return false
  end
  self:changed()
  return true
end

function OnlineSettings:activate(row)
  if row.kind == "toggle" then return self:step(row, 1) end
  if row.kind == "number" or row.kind == "text" then return self:beginEdit(row) end
  if row.id == "look" then
    local game = self.game
    if not (game and game.data and game.data.sprites and game.stack) then
      return self:showInfo("MY LOOK", "Open a game first: the characters come from its own ROM.")
    end
    require("src.ui.online.AvatarScreen").open(game)
    return
  elseif row.id == "connTest" then
    return self:startConnTest()
  elseif row.id == "privacy" then
    return self:showInfo("MY IP IN CODES", PRIVACY_NOTE)
  elseif row.id == "status" then
    return self:showStatus()
  elseif row.id == "defaults" then
    Model.reset(self.s)
    self:changed()
    self.flash = { text = "Defaults restored.", timer = 2 }
    playSound(self.game, "Press_AB")
  elseif row.id == "done" then
    playSound(self.game, "Press_AB")
    self:persist()
    self:close()
  end
end

-- ------------------------------------------------------------ info popups

function OnlineSettings:showInfo(title, text, buttons, onChoice)
  self.info = { title = title, text = text, buttons = buttons or { "OK" }, index = 1, onChoice = onChoice }
end

-- ------------------------------------------------------------ connection test

function OnlineSettings:startConnTest()
  local okC, ConnTest = pcall(require, "src.online.net.ConnTest")
  if not okC or not self.platform.available then
    return self:showInfo("CONNECTION TEST", self.platform.reason or "This device has no network support.")
  end
  Model.write(self.options, self.s)
  local raw = type(self.options.online) == "table" and self.options.online or {}
  local s = self.s
  self.connJob = ConnTest.start({
    port = s.port, portMap = self.platform.canPortMap ~= false and s.portMap ~= false,
    manualAddress = s.manualAddress ~= "" and s.manualAddress or nil,
    hubAddress = s.hubAddress ~= "" and s.hubAddress or nil,
    -- test-only keys, as LinkState.settings reads them
    portMapOpts = raw.portMapOpts, lanIp = raw.lanIp, bind = raw.bind,
  })
  self.connInfo = true
  self:showInfo("CONNECTION TEST", "Looking at this device...", { "OK" }, function() self.connInfo = nil end)
  self.connTestInfo = self.info
end

-- every frame until it answers (even with the window closed, so the router's
-- port is shut again)
function OnlineSettings:pumpConnTest()
  local job = self.connJob
  if not job then return end
  job:update()
  local info = self.info == self.connTestInfo and self.info or nil
  if job.state == "running" then
    if info and job.step then info.text = job.step end
    return
  end
  self.connJob = nil
  local ConnTest = require("src.online.net.ConnTest")
  local text
  if job.state == "done" and job.result then
    local verdict
    text, verdict = ConnTest.report(job.result)
    self.connResult = { text = text, verdict = verdict, result = job.result }
  else
    text = "The test could not run: " .. tostring(job.reason or "?")
    self.connResult = { text = text, verdict = "error" }
  end
  if info then
    info.text = text
    info.top = 0
    info.buttons, info.index = { "AGAIN", "OK" }, 2
    local me = self
    info.onChoice = function(i)
      me.connInfo = nil
      if i == 1 then me:startConnTest() end
    end
  end
end

function OnlineSettings:showStatus()
  local p = self.platform
  local parts = {}
  parts[#parts + 1] = p.reason or "Hosting, joining and worlds all work on this device."
  local function yn(v) return v and "yes" or "no" end
  parts[#parts + 1] = ("Host: %s. Router opening: %s. LAN beacon: %s."):format(
    yn(p.canHost), yn(p.canPortMap), yn(p.canBroadcast))
  if self.osName == "Windows" then parts[#parts + 1] = OnlineSettings.FIREWALL_TIP end
  if self.osName == "OS X" then
    parts[#parts + 1] = "macOS may ask to accept incoming connections the first time you host. Choose Allow."
  end
  if self.osName == "iOS" then
    parts[#parts + 1] = "iOS asks once to find devices on your local network. Allow it, or same-network links fail."
  end
  if self.osName == "Android" or self.osName == "iOS" then
    parts[#parts + 1] = "On mobile data, friends usually cannot reach you: let them host, or use a hub."
  end
  self:showInfo("THIS DEVICE", table.concat(parts, " "))
end

function OnlineSettings:showSwitchWarning()
  self:showInfo("WARNING", OnlineSettings.SWITCH_WARNING, { "I ACCEPT", "BACK" }, function(choice)
    if choice == 1 then
      local o = self.options
      if type(o.online) ~= "table" then o.online = {} end
      o.online.homebrewRiskAccepted = true
      self:persist()
    else
      self:close()
    end
  end)
end

function OnlineSettings:chooseInfo(i)
  local info = self.info
  if not info then return end
  self.info = nil
  playSound(self.game, "Press_AB")
  if info.onChoice then info.onChoice(i) end
end

-- ------------------------------------------------------------ text editing

function OnlineSettings:beginEdit(row)
  local charset = row.kind == "number" and "number" or row.charset
  local cells, gridRows = Grid.cells(charset)
  local current = self.s[row.key]
  local text = current ~= nil and tostring(current) or ""
  self.edit = {
    row = row, charset = charset, cells = cells, gridRows = gridRows, index = 1,
    text = text, max = row.kind == "number" and 5 or row.max, message = nil,
  }
  playSound(self.game, "Press_AB")
  return true
end

function OnlineSettings:editSay(text, bad)
  if self.edit then self.edit.message = text and { text = text, bad = bad, timer = 4 } or nil end
end

function OnlineSettings:editType(text)
  local e = self.edit
  if not e then return false end
  local okAll = true
  for ch in tostring(text or ""):gmatch(".") do
    if e.charset == "address" then ch = ch:lower() end
    if e.charset == "name" and #e.text == 0 and ch == " " then
      -- no leading space
    elseif typable(e.charset, ch) and #e.text < e.max then
      e.text = e.text .. ch
    else
      okAll = false
    end
  end
  if not okAll then
    self:editSay(#e.text >= e.max and ("At most %d characters."):format(e.max) or "That character is not allowed here.", true)
  else
    e.message = nil
  end
  return okAll
end

function OnlineSettings:editBackspace()
  local e = self.edit
  if e and #e.text > 0 then e.text = e.text:sub(1, -2); e.message = nil end
end

function OnlineSettings:editPaste()
  local text
  if self.opts.clipboard then
    text = self.opts.clipboard()
  elseif love and love.system and love.system.getClipboardText then
    local ok, t = pcall(love.system.getClipboardText)
    if ok then text = t end
  end
  text = trim(text)
  if not text then self:editSay("The clipboard is empty.", true) return end
  self.edit.text = ""
  self:editType(text:gsub("[\r\n].*$", ""))
end

function OnlineSettings:editCancel()
  self.edit = nil
  if self.softKeyboard and love and love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, false)
    self.softKeyboard = nil
  end
  playSound(self.game, "Press_AB")
end

-- OK: validate, store, leave the editor (or say what is wrong and stay)
function OnlineSettings:editCommit()
  local e = self.edit
  if not e then return false end
  local row = e.row
  local value
  if row.kind == "number" then
    local v = tonumber(e.text)
    if not v or v ~= math.floor(v) or v < row.min or v > row.max then
      self:editSay(("Enter a number from %d to %d."):format(row.min, row.max), true)
      playSound(self.game, "Wrong")
      return false
    end
    value = v
  elseif e.charset == "address" then
    local why
    value, why = Model.cleanAddress(e.text)
    if not value and why then
      self:editSay(why, true)
      playSound(self.game, "Wrong")
      return false
    end
  else
    value = Model.cleanName(e.text)
  end
  self.s[row.key] = value
  self:changed()
  self:editCancel()
  return true
end

function OnlineSettings:editPressCell(i)
  local e = self.edit
  local cell = e and e.cells[i]
  if not cell then return end
  e.flash = { index = i, timer = 0.12 }
  if cell.id == "del" then self:editBackspace()
  elseif cell.id == "paste" then self:editPaste()
  elseif cell.id == "clear" then e.text = ""; e.message = nil
  elseif cell.id == "ok" then self:editCommit()
  else self:editType(cell.id) end
end

-- ------------------------------------------------------------ input

-- one button, from Input (in game) or a host's own mapping (the launcher)
function OnlineSettings:press(btn)
  if self.info then
    local info = self.info
    if btn == "up" then
      info.top = math.max(0, (info.top or 0) - 1)
    elseif btn == "down" then
      local L = self:infoLayout()
      info.top = math.max(0, math.min(#L.lines - L.room, (info.top or 0) + 1))
    elseif btn == "left" then
      info.index = (info.index - 2) % #info.buttons + 1
    elseif btn == "right" then
      info.index = info.index % #info.buttons + 1
    elseif btn == "a" or btn == "start" then
      self:chooseInfo(info.index)
    elseif btn == "b" then
      self:chooseInfo(#info.buttons) -- the last button is the way back
    end
    return
  end
  local e = self.edit
  if e then
    if btn == "left" then e.index = Grid.move(e.cells, e.gridRows, e.index, -1, 0)
    elseif btn == "right" then e.index = Grid.move(e.cells, e.gridRows, e.index, 1, 0)
    elseif btn == "up" then e.index = Grid.move(e.cells, e.gridRows, e.index, 0, -1)
    elseif btn == "down" then e.index = Grid.move(e.cells, e.gridRows, e.index, 0, 1)
    elseif btn == "a" then self:editPressCell(e.index)
    elseif btn == "b" then
      if #e.text == 0 then self:editCancel() else self:editBackspace() end
    elseif btn == "start" then self:editCommit()
    elseif btn == "select" then self:editPaste()
    end
    return
  end
  local n = #self.rows
  local row = self.rows[self.index]
  if btn == "up" then
    self.index = self.index > 1 and self.index - 1 or n
    playSound(self.game, "Select")
  elseif btn == "down" then
    self.index = self.index < n and self.index + 1 or 1
    playSound(self.game, "Select")
  elseif btn == "left" or btn == "right" then
    self:step(row, btn == "left" and -1 or 1)
  elseif btn == "a" then
    self:activate(row)
  elseif btn == "b" or btn == "start" then
    playSound(self.game, "Press_AB")
    self:persist()
    self:close()
  end
end

local BUTTONS = { "up", "down", "left", "right", "a", "b", "start", "select" }

function OnlineSettings:update(dt)
  dt = dt or 1 / 60
  self:pumpConnTest()
  if self.flash then
    self.flash.timer = self.flash.timer - dt
    if self.flash.timer <= 0 then self.flash = nil end
  end
  local e = self.edit
  if e then
    if e.flash then
      e.flash.timer = e.flash.timer - dt
      if e.flash.timer <= 0 then e.flash = nil end
    end
    if e.message and e.message.timer then
      e.message.timer = e.message.timer - dt
      if e.message.timer <= 0 then e.message = nil end
    end
  end
  local input = self.game and self.game.input
  if not input then return end
  for _, b in ipairs(BUTTONS) do
    if input:wasPressed(b) and not self.closed then self:press(b) end
  end
end

local function modifierDown()
  if not (love and love.keyboard and love.keyboard.isDown) then return false end
  return love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
end

-- Game:keypressed hands every key here while this screen is on top.  In a
-- text field the keyboard types (textinput brings the character); anywhere
-- else keys go on to Input, so rebinds and the gamepad work as usual.
-- Returns true when the key was used here (hosts without Input use that).
function OnlineSettings:onKeyPressed(key)
  if self.edit then
    if modifierDown() and key == "v" then self:editPaste() return true end
    if key == "backspace" or key == "delete" then self:editBackspace() return true end
    if key == "escape" then self:editCancel() return true end
    if key == "return" or key == "kpenter" then self:editCommit() return true end
    if #key == 1 or key == "space" then return true end -- textinput delivers it
  elseif self.info then
    if key == "escape" then self:press("b") return true end
    if key == "return" or key == "kpenter" then self:press("a") return true end
  elseif key == "escape" then
    self:press("b")
    return true
  end
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) return true end
  return false
end

function OnlineSettings:onTextInput(text)
  if self.edit then self:editType(text) end
end

-- ------------------------------------------------------------ layout

function OnlineSettings:styleObj()
  if not self.style then
    self.style = require("src.ui.online.CodeStyle").new(self.styleKind)
  end
  return self.style
end

function OnlineSettings:layout()
  local style = self:styleObj()
  local W, H = self.width, self.height
  local L = { margin = 6, lh = style:lineHeight() }
  L.titleY = 2
  L.banner = self.platform.consent == "homebrew"
  L.listY = L.titleY + L.lh + 3 + (L.banner and L.lh or 0)
  L.rowH = L.lh + 3
  L.helpLines = 3
  L.step = L.lh + (L.lh <= 8 and 1 or 0) -- running text: a pixel of leading on 8 px faces
  L.helpY = H - 2 - L.helpLines * L.step
  L.visible = math.max(1, math.floor((L.helpY - 2 - L.listY) / L.rowH))
  L.rowW = W - 2 * L.margin
  return L
end

function OnlineSettings:clampScroll(L)
  local n = #self.rows
  if self.index <= self.scroll then self.scroll = self.index - 1 end
  if self.index > self.scroll + L.visible then self.scroll = self.index - L.visible end
  self.scroll = math.max(0, math.min(self.scroll, math.max(0, n - L.visible)))
end

function OnlineSettings:rowRect(L, slot)
  return L.margin, L.listY + (slot - 1) * L.rowH, L.rowW, L.rowH - 1
end

function OnlineSettings:editLayout()
  local style = self:styleObj()
  local W, H = self.width, self.height
  local e = self.edit
  local L = { margin = 6, lh = style:lineHeight() }
  L.titleY = 2
  local function tile(v) return math.ceil(v / 8) * 8 end
  L.fieldX, L.fieldY = L.margin, tile(L.titleY + L.lh + 1)
  L.fieldW, L.fieldH = W - 2 * L.margin, tile(L.lh + 16)
  L.step = L.lh + (L.lh <= 8 and 1 or 0)
  L.msgY = L.fieldY + L.fieldH + 1
  local remaining = H - 2 - L.msgY
  local keyH = math.floor((remaining - 2 * L.lh) / e.gridRows)
  keyH = math.max(math.max(10, L.lh - 2), math.min(L.lh + 6, keyH))
  local keyW = math.floor((W - 8) / Grid.COLS)
  L.keyW, L.keyH = keyW, keyH
  L.gridX = math.floor((W - keyW * Grid.COLS) / 2)
  L.gridY = H - 2 - keyH * e.gridRows
  L.msgLines = math.max(1, math.floor((L.gridY - L.msgY) / L.step))
  return L
end

function OnlineSettings:cellRect(L, cell)
  return L.gridX + cell.col * L.keyW, L.gridY + cell.row * L.keyH, cell.span * L.keyW, L.keyH
end

function OnlineSettings:infoLayout()
  local style = self:styleObj()
  local W, H = self.width, self.height
  local info = self.info
  local L = { margin = 8, lh = style:lineHeight() }
  L.boxX, L.boxY, L.boxW, L.boxH = 0, 0, W, H
  L.textW = W - 2 * L.margin - 4
  -- a line break in the text is a new paragraph (the connection test's report)
  L.lines = {}
  for para in tostring(info.text):gmatch("[^\n]+") do
    for _, l in ipairs(style:wrap(para, L.textW)) do L.lines[#L.lines + 1] = l end
  end
  L.buttonH = math.max(12, L.lh + 3)
  L.buttonY = H - 6 - L.buttonH
  local nb = #info.buttons
  L.buttonW = math.floor((W - (nb + 1) * L.margin) / nb)
  L.textY = 8 + L.lh + 4
  L.step = L.lh + (L.lh <= 8 and 1 or 0)
  L.room = math.max(1, math.floor((L.buttonY - 2 - L.textY) / L.step))
  return L
end

function OnlineSettings:buttonRect(L, i)
  return L.margin + (i - 1) * (L.buttonW + L.margin), L.buttonY, L.buttonW, L.buttonH
end

-- ------------------------------------------------------------ touch

function OnlineSettings:touchpressed(_, px, py)
  local x, y = px, py
  if not self.opts.surfacePointer then
    x, y = require("src.ui.online.CodeStyle").toSurface(px, py)
  end
  if not x then return false end
  return self:tap(x, y)
end

local function inside(x, y, rx, ry, rw, rh)
  return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

-- a tap in surface pixels (also what tests drive)
function OnlineSettings:tap(x, y)
  if self.info then
    local L = self:infoLayout()
    for i = 1, #self.info.buttons do
      if inside(x, y, self:buttonRect(L, i)) then
        self.info.index = i
        self:chooseInfo(i)
        return true
      end
    end
    -- a tap on the text pages it (back to the top after the last page)
    if #L.lines > L.room then
      local top = (self.info.top or 0) + L.room
      if top >= #L.lines then top = 0 end
      self.info.top = math.min(top, #L.lines - L.room)
    end
    return true
  end
  local e = self.edit
  if e then
    local L = self:editLayout()
    for i, cell in ipairs(e.cells) do
      if inside(x, y, self:cellRect(L, cell)) then
        e.index = i
        self:editPressCell(i)
        return true
      end
    end
    if inside(x, y, L.fieldX, L.fieldY, L.fieldW, L.fieldH) then
      if love and love.keyboard and love.keyboard.hasScreenKeyboard
         and love.keyboard.hasScreenKeyboard() and love.keyboard.setTextInput then
        pcall(love.keyboard.setTextInput, true)
        self.softKeyboard = true
      end
    end
    return true
  end
  local L = self:layout()
  self:clampScroll(L)
  -- the more-arrows scroll the list
  if y < L.listY and self.scroll > 0 then
    self.index = math.max(1, self.scroll)
    return true
  end
  for slot = 1, L.visible do
    local i = self.scroll + slot
    local row = self.rows[i]
    if not row then break end
    local rx, ry, rw, rh = self:rowRect(L, slot)
    if inside(x, y, rx, ry, rw, rh) then
      local was = self.index == i
      self.index = i
      if row.kind == "number" and was then
        -- the arrows either side of the value step it; elsewhere edits
        local a = self._arrows
        if a and a.row == i and x >= a.rightX then self:step(row, 1)
        elseif a and a.row == i and x >= a.leftX and x < a.leftEnd then self:step(row, -1)
        else self:activate(row) end
      elseif row.kind == "toggle" or was then
        self:activate(row)
      end
      return true
    end
  end
  if y >= L.helpY - 2 and self.scroll + L.visible < #self.rows then
    self.index = math.min(#self.rows, self.scroll + L.visible + 1)
  end
  return true
end

-- ------------------------------------------------------------ draw

-- a small filled triangle (cartridge fonts have no < > ^ glyphs):
-- dir "left" | "right" | "up" | "down", inside a size x size box at (x, y)
local function arrow(x, y, size, dir, color)
  local g = love.graphics
  g.setColor(color[1], color[2], color[3], color[4] or 1)
  local h = size / 2
  if dir == "left" then g.polygon("fill", x + size - 1, y, x + size - 1, y + size, x + 1, y + h)
  elseif dir == "right" then g.polygon("fill", x + 1, y, x + 1, y + size, x + size - 1, y + h)
  elseif dir == "up" then g.polygon("fill", x, y + size - 1, x + size, y + size - 1, x + h, y + 1)
  else g.polygon("fill", x, y + 1, x + size, y + 1, x + h, y + size - 1) end
  g.setColor(1, 1, 1, 1)
end
OnlineSettings.arrow = arrow

local function fit(style, text, maxW)
  if style:width(text) <= maxW then return text end
  while #text > 1 and style:width(text .. "..") > maxW do text = text:sub(1, -2) end
  return text .. ".."
end

function OnlineSettings:drawList()
  local style = self:styleObj()
  local C = require("src.ui.online.CodeStyle").colors
  local L = self:layout()
  self:clampScroll(L)
  local W = self.width
  style:clear(self.width, self.height)
  style:text("ONLINE SETTINGS", L.margin, L.titleY)
  if L.banner then
    style:text(fit(style, "HOMEBREW: BAN RISK", W - 2 * L.margin), L.margin, L.titleY + L.lh + 1, C.bad)
  end
  local aw = math.max(5, math.floor(L.lh * 0.6))
  if self.scroll > 0 then arrow(W - L.margin - aw, L.titleY + 1, aw, "up", C.dim) end
  for slot = 1, L.visible do
    local i = self.scroll + slot
    local row = self.rows[i]
    if not row then break end
    local x, y, w, h = self:rowRect(L, slot)
    local selected = i == self.index
    if selected then style:key(x, y, w, h, true, false) end
    local value = self:valueText(row)
    local disabled = self:rowDisabled(row)
    local valueColor = disabled and C.dim or C.ink
    if row.kind == "text" and self.s[row.key] == nil then valueColor = C.dim end
    if row.id == "status" then
      valueColor = self.platform.available and (self.platform.consent and C.bad or C.good) or C.bad
    elseif row.id == "privacy" then
      valueColor = Model.codesShowIp(self.s) and C.bad or C.good
    end
    local label = row.label
    if row.long and style:width(row.long) + style:width(value) + 24 <= w then label = row.long end
    local ty = y + math.floor((h - L.lh) / 2) + 1
    style:text(label, x + 3, ty, disabled and C.dim or C.ink)
    local labelW = style:width(label) + 8
    local arrows = selected and row.kind == "number"
    local room = w - labelW - 6 - (arrows and 2 * aw + 6 or 0)
    value = fit(style, value, math.max(8, room))
    local vx = x + w - 3 - style:width(value) - (arrows and aw + 3 or 0)
    if arrows then
      local lx = vx - aw - 3
      local rx = x + w - 3 - aw
      local ay = y + math.floor((h - aw) / 2)
      arrow(lx, ay, aw, "left", C.dim)
      arrow(rx, ay, aw, "right", C.dim)
      -- generous touch targets: the "<" and the gap after it, the ">" to the edge
      self._arrows = { row = i, leftX = lx - 4, leftEnd = vx, rightX = rx - 3 }
    elseif selected then
      self._arrows = nil
    end
    if row.kind == "action" then value = "" end
    style:text(value, vx, ty, valueColor)
  end
  if self.scroll + L.visible < #self.rows then
    -- in the gap under the last row when there is one, else in the margin
    local below = L.listY + L.visible * L.rowH
    if L.helpY - below >= aw + 1 then
      arrow(math.floor((W - aw) / 2), below, aw, "down", C.dim)
    else
      arrow(W - L.margin + 1, below - L.rowH + math.floor((L.rowH - 5) / 2), 5, "down", C.dim)
    end
  end
  -- the help for the selected row (or the flash of the moment)
  local text, color = self:helpText(self.rows[self.index]), C.dim
  if self.flash then text, color = self.flash.text, C.good end
  local lines = style:wrap(text, W - 2 * L.margin)
  for i = 1, math.min(#lines, L.helpLines) do
    style:text(lines[i], L.margin, L.helpY + (i - 1) * L.step, color)
  end
end

function OnlineSettings:drawEdit()
  local style = self:styleObj()
  local C = require("src.ui.online.CodeStyle").colors
  local e = self.edit
  local L = self:editLayout()
  local W = self.width
  style:clear(self.width, self.height)
  style:text(e.row.long or e.row.label, L.margin, L.titleY)
  local counter = ("%d/%d"):format(#e.text, e.max)
  style:text(counter, W - L.margin - style:width(counter), L.titleY, C.dim)
  style:box(L.fieldX, L.fieldY, L.fieldW, L.fieldH)
  -- the tail of the text when it is wider than the field
  local shown = e.text
  local maxW = L.fieldW - 16 - 6
  while #shown > 0 and style:width(shown) > maxW do shown = shown:sub(2) end
  local tx = L.fieldX + 8
  local ty = L.fieldY + math.floor((L.fieldH - L.lh) / 2) + 1
  style:text(shown, tx, ty)
  local blink = not (love and love.timer and love.timer.getTime) or math.floor(love.timer.getTime() * 2) % 2 == 0
  if blink then style:rect("fill", tx + style:width(shown) + 1, ty + L.lh - 2, 5, 1) end
  local msg, color = nil, C.dim
  if e.message then
    msg, color = e.message.text, e.message.bad and C.bad or C.good
  elseif #e.text == 0 and e.row.kind == "text" then
    msg = ("Empty: %s."):format(e.row.empty == "RELAY" and "the default relay"
      or e.row.empty == "AUTO" and "found automatically" or "your trainer's name")
  else
    msg = "A types, B deletes, START saves."
  end
  local lines = style:wrap(msg, W - 2 * L.margin)
  for i = 1, math.min(#lines, L.msgLines) do
    style:text(lines[i], L.margin, L.msgY + (i - 1) * L.step, color)
  end
  for i, cell in ipairs(e.cells) do
    local x, y, w, h = self:cellRect(L, cell)
    style:key(x, y, w, h, i == e.index, e.flash and e.flash.index == i)
    local label = cell.label
    if style:width(label) > w - 2 then label = ({ paste = "PST", clear = "CLR", del = "DL" })[cell.id] or label end
    style:text(label, x + math.floor((w - style:width(label)) / 2), y + math.floor((h - L.lh) / 2) + 1)
  end
end

function OnlineSettings:drawInfo()
  local style = self:styleObj()
  local C = require("src.ui.online.CodeStyle").colors
  local info = self.info
  local L = self:infoLayout()
  style:clear(self.width, self.height)
  style:box(L.boxX, L.boxY, L.boxW, L.boxH)
  local warn = info.title == "WARNING"
  style:text(info.title, L.margin + 2, 8, warn and C.bad or C.ink)
  local top = math.max(0, math.min(info.top or 0, #L.lines - L.room))
  for i = 1, math.min(#L.lines - top, L.room) do
    style:text(L.lines[top + i], L.margin + 2, L.textY + (i - 1) * L.step, C.ink)
  end
  local W = self.width
  local aw = math.max(5, math.floor(L.lh * 0.6))
  if top > 0 then arrow(W - L.margin - aw, 9, aw, "up", C.dim) end
  if top + L.room < #L.lines then
    arrow(W - L.margin - aw, L.buttonY - aw - 3, aw, "down", C.dim)
  end
  for i, label in ipairs(info.buttons) do
    local x, y, w, h = self:buttonRect(L, i)
    style:key(x, y, w, h, i == info.index, false)
    style:text(fit(style, label, w - 4), x + math.floor((w - style:width(fit(style, label, w - 4))) / 2),
               y + math.floor((h - L.lh) / 2) + 1)
  end
end

function OnlineSettings:draw()
  if self.info then self:drawInfo()
  elseif self.edit then self:drawEdit()
  else self:drawList() end
  if love and love.graphics then love.graphics.setColor(1, 1, 1, 1) end
end

return OnlineSettings
