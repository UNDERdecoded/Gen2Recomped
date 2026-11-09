-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LINK PLAY for the Zelda games: the runtime's own online screen (opened
-- from the Zelda system menu, or straight away when the launcher's Online
-- Hub asked to HOST WITH FRIENDS / JOIN FRIEND with this game).
--
--   HOST A ROOM   opens a room for 2-4 players and shows its code
--   JOIN A ROOM   type or paste a friend's code
--   (in a room)   the code, the players in their colours, LEAVE / CLOSE
--
-- Drawn in window space over the paused game, driven by the runtime's
-- Input (d-pad / A / B), the keyboard (typing, Enter, Backspace, Ctrl+V),
-- and touch (every row and button is a tap target). Errors are shown here,
-- in words, never only in a log.

local ZeldaNet = require("src.online.zelda.ZeldaNet")

local M = {}
M.__index = M

local function fontOf(size)
  M._fonts = M._fonts or {}
  size = math.max(10, math.floor(size))
  if not M._fonts[size] then M._fonts[size] = love.graphics.newFont(size) end
  return M._fonts[size]
end

function M.new(host)
  local self = setmetatable({ host = host, page = "menu", index = 1, code = "", t = 0 }, M)
  if host.sessionObj then self.page = "room" end
  return self
end

function M:input() return require("src.zelda.ZeldaRuntime").input end

function M:say(text) self.notice, self.noticeT = text, 3 end

function M:gameId() return self.host.version end

function M:myName()
  local save = self.host.gameOpts and self.host.gameOpts.save
  return ZeldaNet.playerName(save)
end

-- ------------------------------------------------------------- actions

function M:startHost()
  if self.host.sessionObj then self.page = "room" return end
  self.room = ZeldaNet.openRoom(self:gameId(), {
    name = self:myName(),
    maxPlayers = (self.host.info and self.host.info.onlinePlayers and self.host.info.onlinePlayers.max) or 4,
    connector = self.host.extra and self.host.extra.connector,
  })
  self.page = "opening"
end

function M:startJoin(code)
  if self.host.sessionObj then self.page = "room" return end
  if code and code ~= "" then
    self.code = code
    self.join = ZeldaNet.joinRoom(self:gameId(), code, {
      name = self:myName(),
      joinOptions = self.host.extra and self.host.extra.joinOptions,
    })
    self.page = "joining"
    return
  end
  self.page = "code"
  self.code = ""
  pcall(function() love.keyboard.setTextInput(true) end)
end

function M:fail(why)
  self.failure = tostring(why or "Something went wrong.")
  self.page = "failed"
  pcall(function() love.keyboard.setTextInput(false) end)
end

-- the launcher's Online Hub hands over { kind = "host" } / { kind = "join", code }
function M:runAction(a)
  if type(a) ~= "table" then return end
  if a.kind == "host" then self:startHost()
  elseif a.kind == "join" then self:startJoin(a.code)
  end
end

function M:close()
  pcall(function() love.keyboard.setTextInput(false) end)
  self.done = true
end

function M:leaveRoom()
  self.host:detachSession(self.host.sessionObj and self.host.sessionObj.isHost
    and "You closed the room." or "You left the room.")
  self.page = "menu"
  self.index = 1
end

function M:copyCode()
  local s = self.host.sessionObj
  local code = s and s.code
  if code and love.system and love.system.setClipboardText then
    pcall(love.system.setClipboardText, code)
    self:say("Code copied.")
  end
end

-- ------------------------------------------------------------- rows

function M:rows()
  if self.page == "menu" then
    return {
      { id = "host", label = "HOST A ROOM" },
      { id = "join", label = "JOIN A ROOM" },
      { id = "back", label = "BACK TO THE GAME" },
    }
  elseif self.page == "room" then
    local s = self.host.sessionObj
    local rows = {}
    if s and s.isHost and s.code then rows[#rows + 1] = { id = "copy", label = "COPY CODE" } end
    rows[#rows + 1] = { id = "back", label = "BACK TO THE GAME" }
    rows[#rows + 1] = { id = "leave", label = (s and s.isHost) and "CLOSE ROOM" or "LEAVE ROOM" }
    return rows
  elseif self.page == "code" then
    return {
      { id = "paste", label = "PASTE" },
      { id = "go", label = "JOIN" },
      { id = "cancel", label = "BACK" },
    }
  elseif self.page == "failed" then
    return { { id = "menu", label = "OK" } }
  else
    return { { id = "cancel", label = "CANCEL" } }
  end
end

function M:activate(row)
  local id = row and row.id
  if id == "host" then self:startHost()
  elseif id == "join" then self:startJoin(nil)
  elseif id == "back" then self:close()
  elseif id == "copy" then self:copyCode()
  elseif id == "leave" then self:leaveRoom()
  elseif id == "paste" then
    local ok, text = pcall(love.system.getClipboardText)
    if ok and type(text) == "string" then self.code = text:sub(1, 120) end
  elseif id == "go" then
    if self.code:match("%S") then self:startJoin(self.code) else self:say("Type or paste a code first.") end
  elseif id == "cancel" then
    if self.room then self.room:close(); self.room = nil end
    if self.join then self.join:cancel(); self.join = nil end
    pcall(function() love.keyboard.setTextInput(false) end)
    self.page = "menu"
    self.index = 1
  elseif id == "menu" then
    self.page = "menu"
    self.index = 1
  end
end

-- ------------------------------------------------------------- update

function M:update(dt)
  self.t = self.t + (dt or 0)
  if self.noticeT then
    self.noticeT = self.noticeT - (dt or 0)
    if self.noticeT <= 0 then self.notice, self.noticeT = nil, nil end
  end
  if self.page == "opening" and self.room then
    self.room:update(dt)
    if self.room.state == "failed" then
      local why = self.room.error
      self.room = nil
      return self:fail("Could not open a room.\n" .. tostring(why))
    elseif self.room.state == "open" and self.room.session then
      self.host:attachSession(self.room.session)
      self.room = nil
      self.page = "room"
      self.index = 1
    end
  elseif self.page == "joining" and self.join then
    self.join:update()
    if self.join.state == "failed" then
      local why = self.join.error
      self.join = nil
      return self:fail("Could not join.\n" .. tostring(why))
    elseif self.join.state == "open" then
      local s = self.join.session
      s.code = nil
      self.host:attachSession(s)
      self.join = nil
      self.page = "room"
      self.index = 1
      pcall(function() love.keyboard.setTextInput(false) end)
    end
  elseif self.page == "room" and not self.host.sessionObj then
    self.page = "menu"
  end
  local I = self:input()
  local rows = self:rows()
  if I.wasPressed("up") then self.index = (self.index - 2) % #rows + 1 end
  if I.wasPressed("down") then self.index = self.index % #rows + 1 end
  self.index = math.max(1, math.min(#rows, self.index))
  if self.page ~= "code" or not self.typing then
    if I.wasPressed("a") then self:activate(rows[self.index])
    elseif I.wasPressed("b") then
      if self.page == "menu" or self.page == "room" then self:close()
      else self:activate({ id = "cancel" }) end
    end
  end
end

-- keyboard: typing the code (consumes the key so it does not reach the game)
function M:keypressed(key)
  if self.page ~= "code" then return false end
  if key == "backspace" then
    self.code = self.code:sub(1, -2)
    return true
  elseif key == "return" or key == "kpenter" then
    self:activate({ id = "go" })
    return true
  elseif key == "v" and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then
    self:activate({ id = "paste" })
    return true
  end
  -- letters and digits are the code's, not the game's A / B
  if #key == 1 or key == "space" then return true end
  return false
end

function M:textinput(text)
  if self.page ~= "code" then return end
  if #self.code < 120 then self.code = self.code .. text end
  self.typing = true
end

-- ------------------------------------------------------------- draw

function M:layout()
  local w, h = love.graphics.getDimensions()
  local f = fontOf(math.max(14, math.min(26, h / 28)))
  local big = fontOf(math.max(18, math.min(40, h / 18)))
  local pw = math.min(w - 24, math.max(360, w * 0.6))
  return w, h, f, big, pw, (w - pw) / 2
end

local function wrapText(font, text, width)
  local _, lines = font:getWrap(text, width)
  return lines
end

function M:draw()
  local g = love.graphics
  local w, h, f, big, pw, px = self:layout()
  g.setColor(0, 0, 0, 0.72)
  g.rectangle("fill", 0, 0, w, h)
  local y = math.max(12, h * 0.06)
  local lineH = f:getHeight() * 1.35
  -- title
  g.setFont(big)
  g.setColor(0.95, 0.8, 0.35)
  local title = ({ menu = "LINK PLAY", room = "YOUR ROOM", code = "JOIN A ROOM", opening = "OPENING A ROOM",
                   joining = "JOINING", failed = "LINK PLAY" })[self.page] or "LINK PLAY"
  g.printf(title, px, y, pw, "center")
  y = y + big:getHeight() * 1.5
  g.setFont(f)
  g.setColor(1, 1, 1, 0.9)
  local body = {}
  local s = self.host.sessionObj
  if self.page == "menu" then
    body[#body + 1] = "Play with 2-4 friends who own this game. One player hosts a room and shares its code."
  elseif self.page == "opening" then
    local dots = ("..."):sub(1, 1 + math.floor(self.t * 2) % 3)
    body[#body + 1] = "Opening a port and asking your router" .. dots
  elseif self.page == "joining" then
    local dots = ("..."):sub(1, 1 + math.floor(self.t * 2) % 3)
    body[#body + 1] = ((self.join and self.join:progress()) or "Connecting") .. dots
  elseif self.page == "code" then
    body[#body + 1] = "Type or paste the room code your friend shared."
  elseif self.page == "failed" then
    for line in tostring(self.failure):gmatch("[^\n]+") do body[#body + 1] = line end
  end
  for _, para in ipairs(body) do
    for _, line in ipairs(wrapText(f, para, pw)) do
      g.printf(line, px, y, pw, "center")
      y = y + lineH
    end
  end
  -- the code
  if self.page == "room" and s then
    if s.isHost and s.code then
      g.setFont(big)
      g.setColor(1, 1, 1)
      g.printf(s.code, px, y, pw, "center")
      y = y + big:getHeight() * 1.3
      g.setFont(f)
      g.setColor(1, 1, 1, 0.75)
      g.printf("Share this code. Up to " .. tostring(s.maxPlayers or 4) .. " players.", px, y, pw, "center")
      y = y + lineH
    end
    -- players
    y = y + lineH * 0.3
    for _, p in ipairs(s:players()) do
      local c = p.color or { 1, 1, 1 }
      g.setColor(c[1], c[2], c[3])
      g.rectangle("fill", px + pw * 0.25, y + lineH * 0.2, lineH * 0.6, lineH * 0.6, 3, 3)
      g.setColor(1, 1, 1)
      local label = tostring(p.name) .. (p.isHost and "  (host)" or "") .. (p.me and "  - you" or "")
      g.print(label, px + pw * 0.25 + lineH, y)
      y = y + lineH
    end
  elseif self.page == "code" then
    g.setFont(big)
    g.setColor(0.12, 0.14, 0.2)
    g.rectangle("fill", px, y, pw, big:getHeight() * 1.4, 8, 8)
    g.setColor(1, 1, 1)
    local caret = (math.floor(self.t * 2) % 2 == 0) and "_" or " "
    g.printf(self.code .. caret, px + 8, y + big:getHeight() * 0.2, pw - 16, "center")
    y = y + big:getHeight() * 1.8
    g.setFont(f)
  end
  -- rows
  y = y + lineH * 0.4
  self.rects = {}
  local rowH = f:getHeight() * 2
  for i, row in ipairs(self:rows()) do
    local sel = i == self.index
    g.setColor(1, 1, 1, sel and 0.18 or 0.07)
    g.rectangle("fill", px + pw * 0.15, y, pw * 0.7, rowH - 6, 8, 8)
    g.setColor(1, 1, 1, sel and 1 or 0.8)
    g.printf(row.label, px, y + (rowH - 6 - f:getHeight()) / 2, pw, "center")
    self.rects[i] = { x = px + pw * 0.15, y = y, w = pw * 0.7, h = rowH - 6, row = row }
    y = y + rowH
  end
  if self.notice then
    g.setColor(0.6, 0.9, 0.6)
    g.printf(self.notice, px, math.min(h - lineH * 1.5, y + lineH * 0.5), pw, "center")
  end
end

function M:touchpressed(_, x, y)
  for i, r in ipairs(self.rects or {}) do
    if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h then
      self.index = i
      self:activate(r.row)
      return true
    end
  end
  if self.page == "code" then pcall(function() love.keyboard.setTextInput(true) end) end
  return true
end

return M
