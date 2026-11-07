-- The online screens' platform gate (docs/online-design.md 2.10, WS10).
--
-- Every online screen -- the LINK menu, a tournament, the world menu, the
-- GTS -- is opened by code other workstreams own, from several places (START
-- menus, a Cable Club receptionist, a Discord join).  Rather than each of them
-- asking Platform.online() and wording its own refusal, this module listens
-- to the state stack's `screen.pushed` event and answers for all of them:
--
--   * a device that cannot go online (no lua-enet, no LuaSocket, the web
--     build) gets a clear notice the moment the screen opens; dismissing it
--     leaves the screen the way the screen itself leaves (exitWith / finish /
--     close), so link-session state is cleaned up as usual;
--   * a build with LuaSocket but no enet may still use the relay: the LINK
--     menu and tournaments open after a one-line note, worlds and the GTS
--     are refused;
--   * on the Switch, the first online screen asks the player to accept the
--     ban risk of going online with homebrew (remembered in
--     save.options.online.homebrewRiskAccepted); BACK leaves;
--   * on Windows, the first host code shown carries a one-time tip about the
--     firewall prompt (save.options.online.firewallTipShown).  It is put in
--     the code screen's own notice line, not a modal, so the host keeps
--     polling for a guest underneath.
--
--   OnlineGate.install(game)  -- once per Game:load (idempotent per event bus)
--   OnlineGate.check(game, state) -> verdict  -- what install's listener runs
--   OnlineGate.verdict(kind, platform, onlineOpts) -> "ok"|"block"|"note"|"consent"
--
-- Tests swap OnlineGate.platform (a function returning a Platform.online()
-- shaped table) and OnlineGate.osName.

local OnlineGate = {}

local SCREENS = {
  -- module path -> what the screen needs: "link" (enet, or the relay over
  -- LuaSocket), "relay" (LuaSocket), "enet"
  ["src.link.LinkState"] = "link",
  ["src.link.Tournament"] = "relay",
  ["src.ui.online.WorldMenu"] = "enet",
  ["src.ui.online.GtsScreen"] = "enet",
}
OnlineGate.SCREENS = SCREENS

OnlineGate.platform = function()
  local ok, Platform = pcall(require, "src.core.Platform")
  if ok and Platform and Platform.online then
    local okO, info = pcall(Platform.online)
    if okO and info then return info end
  end
  return { available = true }
end

OnlineGate.osName = function()
  return love and love.system and love.system.getOS and love.system.getOS() or "Unknown"
end

local function onlineOptions(game)
  local options = game and game.save and game.save.options
  if type(options) ~= "table" then return nil, {} end
  if type(options.online) ~= "table" then options.online = {} end
  return options, options.online
end

local function persist(game)
  if game and game.writeOptions then pcall(game.writeOptions, game) end
end

-- the screen kind a pushed state is, or nil
function OnlineGate.kindOf(state)
  if type(state) ~= "table" then return nil end
  local mt = getmetatable(state)
  if not mt then return nil end
  for path, kind in pairs(SCREENS) do
    local mod = package.loaded[path]
    if type(mod) == "table" and mt == mod then return kind end
  end
  return nil
end

-- pure: what to do for a screen of `kind` on `p`
--   "ok"       nothing to say
--   "block"    cannot work here: notice, then leave
--   "note"     works, with a limitation to say once (relay only)
--   "consent"  the Switch homebrew warning, not yet accepted
function OnlineGate.verdict(kind, p, o)
  o = o or {}
  p = p or {}
  local works
  if kind == "enet" then works = p.available
  elseif kind == "relay" then works = p.available or p.relayOnly or p.hasSocket
  else works = p.available or p.relayOnly end
  if not works then return "block" end
  if p.consent == "homebrew" and not o.homebrewRiskAccepted then return "consent" end
  if kind == "link" and not p.available and p.relayOnly then return "note" end
  return "ok"
end

-- leave `state` the way it leaves by itself
local function leave(game, state)
  if game.stack:top() ~= state then return end
  if type(state.exitWith) == "function" then
    pcall(state.exitWith, state)
  elseif type(state.finish) == "function" then
    pcall(state.finish, state, "unavailable")
  elseif type(state.close) == "function" then
    pcall(state.close, state)
  else
    game.stack:pop()
  end
  if game.stack:top() == state then game.stack:pop() end
end

-- a small modal: title, wrapped text (pages with up/down or a tap), buttons
local Notice = {}
Notice.__index = Notice
Notice.isOpaque = true
OnlineGate.Notice = Notice

function Notice.new(game, title, text, buttons, onChoice)
  local CodeStyle = require("src.ui.online.CodeStyle")
  local self = setmetatable({ game = game, title = title, text = text,
                              buttons = buttons or { "OK" }, index = 1, top = 0,
                              onChoice = onChoice, isOnlineGateNotice = true }, Notice)
  self.width, self.height = CodeStyle.surface()
  self.style = CodeStyle.new(CodeStyle.defaultKind(game))
  return self
end

function Notice:uiSize() return self.width, self.height end

function Notice:layout()
  local style = self.style
  local W, H = self.width, self.height
  local L = { margin = 8, lh = style:lineHeight() }
  L.lines = style:wrap(self.text, W - 2 * L.margin - 4)
  L.buttonH = math.max(12, L.lh + 3)
  L.buttonY = H - 6 - L.buttonH
  L.buttonW = math.floor((W - (#self.buttons + 1) * L.margin) / #self.buttons)
  L.textY = 8 + L.lh + 4
  L.step = L.lh + (L.lh <= 8 and 1 or 0)
  L.room = math.max(1, math.floor((L.buttonY - 2 - L.textY) / L.step))
  return L
end

function Notice:choose(i)
  if self.chosen then return end
  self.chosen = true
  if self.game.stack:top() == self then self.game.stack:pop() end
  if self.game.data then
    pcall(function() require("src.core.Sound").play(self.game.data, "Press_AB") end)
  end
  if self.onChoice then self.onChoice(i) end
end

function Notice:press(btn)
  if btn == "up" then self.top = math.max(0, self.top - 1)
  elseif btn == "down" then
    local L = self:layout()
    self.top = math.max(0, math.min(#L.lines - L.room, self.top + 1))
  elseif btn == "left" then self.index = (self.index - 2) % #self.buttons + 1
  elseif btn == "right" then self.index = self.index % #self.buttons + 1
  elseif btn == "a" or btn == "start" then self:choose(self.index)
  elseif btn == "b" then self:choose(#self.buttons) end
end

function Notice:update()
  local input = self.game and self.game.input
  if not input then return end
  for _, b in ipairs({ "up", "down", "left", "right", "a", "b", "start" }) do
    if not self.chosen and input:wasPressed(b) then self:press(b) end
  end
end

function Notice:touchpressed(_, px, py)
  local x, y = require("src.ui.online.CodeStyle").toSurface(px, py)
  if not x then return false end
  local L = self:layout()
  for i = 1, #self.buttons do
    local bx = L.margin + (i - 1) * (L.buttonW + L.margin)
    if x >= bx and x < bx + L.buttonW and y >= L.buttonY and y < L.buttonY + L.buttonH then
      self.index = i
      self:choose(i)
      return true
    end
  end
  if #L.lines > L.room then
    local top = self.top + L.room
    if top >= #L.lines then top = 0 end
    self.top = math.min(top, #L.lines - L.room)
  end
  return true
end

function Notice:draw()
  local style = self.style
  local C = require("src.ui.online.CodeStyle").colors
  local L = self:layout()
  local W, H = self.width, self.height
  style:clear(W, H)
  style:box(0, 0, W, H)
  style:text(self.title, L.margin + 2, 8, self.warn and C.bad or C.ink)
  local top = math.max(0, math.min(self.top, #L.lines - L.room))
  for i = 1, math.min(#L.lines - top, L.room) do
    style:text(L.lines[top + i], L.margin + 2, L.textY + (i - 1) * L.step)
  end
  if top + L.room < #L.lines then
    local aw = math.max(5, math.floor(L.lh * 0.6))
    require("src.ui.online.OnlineSettings").arrow(W - L.margin - aw, L.buttonY - aw - 3, aw, "down", C.dim)
  end
  for i, label in ipairs(self.buttons) do
    local x = L.margin + (i - 1) * (L.buttonW + L.margin)
    style:key(x, L.buttonY, L.buttonW, L.buttonH, i == self.index, false)
    style:text(label, x + math.floor((L.buttonW - style:width(label)) / 2),
               L.buttonY + math.floor((L.buttonH - L.lh) / 2) + 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- ------------------------------------------------------------ the gate

OnlineGate.TITLES = { block = "ONLINE IS OFF", note = "RELAY ONLY", consent = "WARNING" }

function OnlineGate.check(game, state)
  local kind = OnlineGate.kindOf(state)
  if not kind or not (game and game.stack) then return nil end
  local p = OnlineGate.platform() or {}
  local _, o = onlineOptions(game)
  local v = OnlineGate.verdict(kind, p, o)
  if v == "ok" then return v end
  if v == "note" and OnlineGate._relayNoted then return "ok" end
  local Settings = require("src.ui.online.OnlineSettings")
  local text, buttons, onChoice
  if v == "block" then
    local why = p.reason or "This device cannot go online."
    if kind == "enet" and p.relayOnly then
      why = "Worlds and the GTS need lua-enet, which this build lacks. Short codes from LINK still work."
    end
    text, buttons = why, { "OK" }
    onChoice = function() leave(game, state) end
  elseif v == "note" then
    OnlineGate._relayNoted = true
    text, buttons = p.reason, { "OK" }
  else
    text, buttons = Settings.SWITCH_WARNING, { "I ACCEPT", "BACK" }
    onChoice = function(i)
      if i == 1 then
        local _, oo = onlineOptions(game)
        oo.homebrewRiskAccepted = true
        persist(game)
      else
        leave(game, state)
      end
    end
  end
  local notice = Notice.new(game, OnlineGate.TITLES[v], text, buttons, onChoice)
  notice.warn = v ~= "note"
  game.stack:push(notice)
  return v
end

-- the first host code on Windows: the firewall tip, in the code screen's own
-- notice line (ShowCode draws `notice` first and counts it down)
function OnlineGate.firewallTip(game, state)
  local ShowCode = package.loaded["src.ui.online.ShowCode"]
  if not (ShowCode and type(state) == "table" and getmetatable(state) == ShowCode) then return false end
  if OnlineGate.osName() ~= "Windows" then return false end
  local options, o = onlineOptions(game)
  if not options or o.firewallTipShown then return false end
  -- a code someone else gave us is not ours to host
  -- (a short code is the relay's: this machine listens on nothing)
  local inv = state.invite
  if inv and inv.type == "short" then return false end
  o.firewallTipShown = true
  persist(game)
  state.notice = { text = require("src.ui.online.OnlineSettings").FIREWALL_TIP_SHORT, timer = 10 }
  return true
end

local installedOn = setmetatable({}, { __mode = "k" })

function OnlineGate.install(game)
  local Runtime = require("src.mods.Runtime")
  local events = Runtime.events
  if not (events and events.on) or installedOn[events] then return false end
  installedOn[events] = true
  events:on("screen.pushed", function(ev)
    local state = ev and ev.state
    if type(state) ~= "table" or state.isOnlineGateNotice then return end
    local ok, err = pcall(function()
      if not OnlineGate.check(game, state) then OnlineGate.firewallTip(game, state) end
    end)
    if not ok then
      pcall(function() require("src.core.Logger").warn("online gate: %s", tostring(err)) end)
    end
  end, 0, "online")
  return true
end

return OnlineGate
