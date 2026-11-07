-- THE WI-FI PLAZA (HeartGold / SoulSilver), as a player-hosted world lobby
-- (docs/online-design.md 2.7 / 2.8, WS6b + WS8).
--
-- On the cartridge the Plaza is not a map.  The Pokemon Center basement's
-- receptionist (pokeheartgold scr_seq_0164_003) checks ScrCmd_691 (120 s
-- since the last visit), saves, walks the player through the gate and warps
-- them to MAP_WIFI_PLAZA_WARP_ROOM; the warp room's attendant (scr_seq_HIROBA)
-- walks them to a pad and they warp out, the script puts them back at the
-- basement door (Warp VAR_UNK_4056, 5, 2) and runs ScrCmd_436 / 166 /
-- ScrCmd_663 -- the Plaza itself, a separate online lobby application with
-- its own 3D square, minigames and Nintendo's servers -- then RestoreOverworld
-- and the basement's frame script walks them out.
--
-- Here ScrCmd_663 opens this lobby, at the same point of the same script:
-- a WS8 world that one player hosts and friends join by its world code, so
-- the Plaza's people are real players.  The lobby shows who is here (with
-- the game each plays), the world chat (CHAT says a line; the latest lines
-- are on the screen), and a visitor's row offers TRADE / BATTLE through the
-- world's invite (GhostInteract -> a relayed link session).  The minigames,
-- the parade and the 3D square are not carried.
--
--   Plaza.open(game, onDone)     onDone("left" | "noconnect")
--
-- When the player was already in a world, the Plaza is that world and
-- leaving the Plaza keeps it; a Plaza world opened here closes when the
-- player leaves (the cartridge's Plaza ends when you walk out).

local Strings = require("src.core.Strings")

local Plaza = {}
Plaza.__index = Plaza
Plaza.isOpaque = true
-- the lobby stands in for the field: world invites come up over it
Plaza.acceptsInvites = true
-- every visitor stands in the Plaza (Presence.localPos): invites reach
Plaza.presenceRoom = "@plaza"
Plaza.COOLDOWN = 120          -- ScrCmd_691: GF_RTC_DateTimeToSec() - unkB4 >= 120
Plaza.CHAT_LINES = 4

local function world() return require("src.online.world.OnlineWorld") end
local function log(fmt, ...)
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok then Logger.info("plaza: " .. fmt, ...) end
end

Plaza.lastLeft = nil          -- os.time() the player last left the Plaza

-- ScrCmd_691: may the player go in again (two minutes after the last visit)
function Plaza.ready(now)
  now = now or os.time()
  return Plaza.lastLeft == nil or now - Plaza.lastLeft >= Plaza.COOLDOWN
end

function Plaza:uiSize()
  local ok, CodeStyle = pcall(require, "src.ui.online.CodeStyle")
  if ok then return CodeStyle.surface({}) end
  return 256, 192
end

function Plaza:rows()
  local W = world()
  local s = W.current()
  local c = s and s.client
  if not s then
    return {
      { label = Strings("OPEN A PLAZA"), act = "host" },
      { label = Strings("JOIN A PLAZA"), act = "join" },
      { label = Strings("LEAVE"), act = "leave" },
    }, "out"
  end
  if not (c and c.state == "in") then
    return { { label = Strings("LEAVE"), act = "leave" } }, "joining"
  end
  local rows = {}
  local pids = {}
  for pid in pairs(c.members or {}) do if pid ~= c.you then pids[#pids + 1] = pid end end
  table.sort(pids)
  for _, pid in ipairs(pids) do
    local m = c.members[pid]
    rows[#rows + 1] = { label = tostring(m.name or "?"), pid = pid,
                        value = m.busy and Strings("LINKED") or nil }
  end
  rows[#rows + 1] = { label = Strings("CHAT"), act = "chat" }
  if s.host then rows[#rows + 1] = { label = Strings("SHOW CODE"), act = "code" } end
  rows[#rows + 1] = { label = Strings("LEAVE THE PLAZA"), act = "leave" }
  return rows, "in"
end

function Plaza:host()
  local W = world()
  local name = (W.playerName(self.game) .. "'S PLAZA"):sub(1, 20)
  local ok, err = pcall(W.hostWorld, self.game, { name = name, gts = false })
  if not ok then
    self.notice = Strings("Couldn't open the Plaza:\n%s", tostring(err))
    return
  end
  self.opened = true
  self.showCodeWhenReady = true
end

function Plaza:showCode()
  local W = world()
  local code, warning = W.inviteCode()
  if not code then
    self.notice = warning == "starting" and Strings("Still opening the Plaza...")
      or Strings("No code yet:\n%s", tostring(warning))
    return false
  end
  local ShowCode = require("src.ui.online.ShowCode")
  ShowCode.open(self.game, {
    code = code, title = Strings("PLAZA CODE"),
    status = Strings("Friends enter this code to come to your Plaza."),
    onUpdate = function(screen, dt)
      W.tick(dt)
      local s = W.current()
      if not s then screen:close() return end
      if s.host then screen:setStatus(Strings("%d/%d in the Plaza", s.host:count(), s.world.cap)) end
    end,
    onCancel = function() end,
  })
  return true
end

function Plaza:join()
  local me = self
  local Util = require("src.online.net.Util")
  require("src.ui.online.LongCodeEntry").open(self.game, {
    title = Strings("PLAZA CODE"), myLanIp = Util.lanIP(), allowShort = false,
    onDone = function(invite)
      local s, why = world().joinWorld(me.game, invite)
      if not s then me.notice = tostring(why) return end
      me.opened = true
    end,
    onCancel = function() end,
  })
end

function Plaza:leave()
  if self.opened then pcall(world().leave) end
  Plaza.lastLeft = os.time()
  if self.game.stack:top() == self then self.game.stack:pop() end
  log("left the Plaza")
  self.onDone("left")
end

function Plaza:update(dt)
  local W = world()
  W.tick(dt)
  local input = self.game.input
  local rows, phase = self:rows()
  if self.showCodeWhenReady and phase == "in" then
    if self:showCode() then self.showCodeWhenReady = nil end
    return
  end
  if self.index > #rows then self.index = #rows end
  if input:wasPressed("down") then
    self.index = self.index % #rows + 1
    self.notice = nil
  elseif input:wasPressed("up") then
    self.index = (self.index - 2) % #rows + 1
    self.notice = nil
  elseif input:wasPressed("b") then
    if phase == "in" then
      self.index = #rows        -- onto LEAVE THE PLAZA
    else
      self:leave()
    end
  elseif input:wasPressed("a") then
    local row = rows[self.index]
    if row.act == "host" then self:host()
    elseif row.act == "join" then self:join()
    elseif row.act == "leave" then self:leave()
    elseif row.act == "chat" then require("src.ui.online.ChatOverlay").open(self.game)
    elseif row.act == "code" then self:showCode()
    elseif row.pid then
      local okG, GhostInteract = pcall(require, "src.ui.online.GhostInteract")
      if okG then GhostInteract.open(self.game, row.pid) end
    end
  end
end

function Plaza:draw()
  local ok, CodeStyle = pcall(require, "src.ui.online.CodeStyle")
  if not ok then return end
  local style = self.style or CodeStyle.new(CodeStyle.defaultKind(self.game))
  self.style = style
  local C = CodeStyle.colors
  local w, h = self:uiSize()
  local lh = style:lineHeight()
  style:clear(w, h)
  style:box(0, 0, w, h)
  local W = world()
  local s = W.current()
  local title = Strings("WI-FI PLAZA")
  if s and s.world and s.world.name then title = tostring(s.world.name)
  elseif s and s.client and s.client.worldName then title = tostring(s.client.worldName) end
  style:text(title, 12, 8)
  local rows, phase = self:rows()
  local y = 8 + lh + 6
  if phase == "in" then
    local n = 0
    for _ in pairs(s.client.members or {}) do n = n + 1 end
    style:text(Strings("%d in the Plaza", n), 12, y, C.dim)
    y = y + lh + 4
  end
  for i, row in ipairs(rows) do
    if i == self.index then
      style:setColor(C.ink)
      love.graphics.polygon("fill", 9, y + 1, 9, y + lh - 1, 9 + math.floor(lh / 2), y + lh / 2)
      love.graphics.setColor(1, 1, 1, 1)
    end
    style:text(row.label, 18, y)
    if row.value then style:text(row.value, w - 12 - style:width(row.value), y, C.dim) end
    y = y + lh + 2
  end
  -- the world's chat: its latest lines at the foot of the lobby
  local lines = {}
  if phase == "in" and s.client.log then
    local okC, Chat = pcall(require, "src.online.world.Chat")
    for _, e in ipairs(s.client.log:recent(Plaza.CHAT_LINES)) do
      lines[#lines + 1] = okC and Chat.format(e) or tostring(e.text)
    end
  end
  local foot
  if self.notice then foot = { self.notice }
  elseif phase == "out" then foot = { Strings("Open a Plaza for your friends, or enter a friend's Plaza code.") }
  elseif phase == "joining" then foot = { Strings("Going to the Plaza...") }
  elseif #lines == 0 then foot = { Strings("Pick a visitor to TRADE or BATTLE.") } end
  local wrapped = {}
  for _, l in ipairs(foot or lines) do
    for _, part in ipairs(style:wrap(l, w - 24)) do wrapped[#wrapped + 1] = part end
  end
  local fy = h - 8 - lh * #wrapped
  for i, l in ipairs(wrapped) do style:text(l, 12, fy + (i - 1) * lh, C.dim) end
end

function Plaza.open(game, onDone)
  onDone = onDone or function() end
  local okL, LinkRooms = pcall(require, "src.online.LinkRooms")
  if okL and LinkRooms.fake then return onDone(LinkRooms.fake("plaza", "plaza", {})) end
  if not (game and game.stack) or not (okL and LinkRooms.available()) then return onDone("noconnect") end
  local self = setmetatable({ game = game, index = 1, onDone = onDone }, Plaza)
  game.stack:push(self)
  log("entered the Plaza")
  return self
end

return Plaza
