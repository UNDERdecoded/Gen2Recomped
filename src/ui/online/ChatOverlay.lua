-- WORLD CHAT on screen (docs/online-design.md 2.8 "chat").
--
--   ChatOverlay.open(game)            the compose window: the recent log over
--                                     a line you type (keyboard / the phone's
--                                     own keyboard) or a canned phrase picked
--                                     with the d-pad; A or Enter says it
--   ChatOverlay.drawHud(game, vp)     the last few lines, fading, over the
--                                     field (OnlineWorld draws it from the
--                                     engine's render.hud seam)
--
-- Lines are WorldProtocol.CHAT_MAX characters at most; the host rate-limits
-- and the client says "Slow down!" before it sends a line the host would drop.

local WorldUi = require("src.ui.online.WorldUi")
local P = require("src.online.world.WorldProtocol")
local Chat = require("src.online.world.Chat")

local ChatOverlay = {}
ChatOverlay.__index = ChatOverlay
ChatOverlay.isOpaque = true
ChatOverlay.isWorldUi = true

ChatOverlay.HUD_LINES = 4
ChatOverlay.HUD_SECONDS = 9

local function world() return require("src.online.world.OnlineWorld") end

function ChatOverlay.open(game)
  local self = setmetatable({}, ChatOverlay)
  self.game = game
  self.text = ""
  self.index = 0          -- 0: the typed line; 1..n: Chat.PHRASES
  self.width, self.height = WorldUi.surface()
  self.style = WorldUi.style(game)
  if love and love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, true)
    self.softKeyboard = true
  end
  game.stack:push(self)
  return self
end

function ChatOverlay:uiSize() return self.width, self.height end

function ChatOverlay:close()
  if self.softKeyboard and love and love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, false)
  end
  if self.game.stack:top() == self then self.game.stack:pop() end
end

function ChatOverlay:current()
  if self.index == 0 then return self.text end
  return Chat.PHRASES[self.index]
end

function ChatOverlay:send()
  local c = world().client()
  local line = self:current()
  if not c or not line or line == "" then return end
  local ok = c:say(line)
  if ok then
    self.text = ""
    self.index = 0
    self:close()
  end
end

function ChatOverlay:update(dt)
  world().tick(dt)
  local c = world().client()
  if not (c and c.state == "in") then self:close() return end
  local input = self.game.input
  if not input then return end
  local n = #Chat.PHRASES
  if input:wasPressed("up") then self.index = (self.index - 1) % (n + 1) end
  if input:wasPressed("down") then self.index = (self.index + 1) % (n + 1) end
  if input:wasPressed("a") or input:wasPressed("start") then
    self:send()
  elseif input:wasPressed("b") then
    if self.index == 0 and #self.text > 0 then
      self.text = self.text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
    else
      self:close()
    end
  end
end

-- typed keys come in as text; steering keys go on to Input
function ChatOverlay:onKeyPressed(key)
  if key == "backspace" then
    self.text = self.text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
    self.index = 0
    return
  end
  if key == "escape" then self:close() return end
  if key == "return" or key == "kpenter" then self:send() return end
  if #key == 1 or key == "space" then return end
  local input = self.game and self.game.input
  if input and input.keypressed then input:keypressed(key) end
end

function ChatOverlay:onTextInput(t)
  local next = (self.text .. tostring(t or "")):gsub("[%c]", "")
  if #P.utf8chars(next) <= P.CHAT_MAX then self.text = next end
  self.index = 0
end

function ChatOverlay:draw()
  local st = self.style
  local W, H = self.width, self.height
  local lh = st:lineHeight()
  local C = require("src.ui.online.CodeStyle").colors
  local c = world().client()
  st:clear(W, H)
  -- the log
  local lines = {}
  if c then
    for _, e in ipairs(c.log:recent(6)) do lines[#lines + 1] = Chat.format(e) end
  end
  local logH = math.max(1, #lines) * (lh + 1) + 12
  st:box(4, 4, W - 8, logH)
  for i, l in ipairs(lines) do
    local wrapped = st:wrap(l, W - 24)[1] or l
    st:text(wrapped, 12, 10 + (i - 1) * (lh + 1))
  end
  -- the line being said
  local y = H - (lh * 2 + 18)
  st:box(4, y, W - 8, lh * 2 + 14)
  local shown = self:current() or ""
  local label = self.index == 0 and "SAY:" or ("%d/%d"):format(self.index, #Chat.PHRASES)
  st:text(label, 12, y + 6, C.dim)
  local tail = shown
  while #tail > 0 and st:width(tail) > W - 24 do tail = tail:sub(2) end
  local blink = (math.floor((love.timer and love.timer.getTime() or 0) * 2) % 2 == 0) and self.index == 0
  st:text(tail .. (blink and "_" or ""), 12, y + 7 + lh)
end

-- ------------------------------------------------------------ the HUD

local hudStyle

function ChatOverlay.drawHud(game, vp)
  local s = world().current()
  local c = s and s.client
  if not (c and vp and love and love.graphics) then return end
  local stack = game and game.stack
  local top = stack and stack:top()
  if top and top.isWorldUi and getmetatable(top) == ChatOverlay then return end
  local now = c:now()
  -- the lines only over the field; a world window or another screen keeps
  -- just the status pill
  local overField = top and top == game.overworld
  local recent = overField and c.log:recent(ChatOverlay.HUD_LINES, now, ChatOverlay.HUD_SECONDS) or {}
  local status
  if s.host then
    local code = world().inviteCode()
    status = ("WORLD %d/%d"):format(s.host:count(), s.world and s.world.cap or 0)
    if not code and s.host.connector and s.host.connector.pending then status = status .. " ..." end
  elseif c.state ~= "in" then
    status = (c.job and c.job.progress) or "Joining..."
  else
    local n = 0 for _ in pairs(c.members) do n = n + 1 end
    status = ("WORLD %d"):format(n)
  end
  local g = love.graphics
  local scale = math.max(1, math.floor((vp.scale or 1) + 0.5))
  local x0, y0 = vp.gameX or 0, vp.gameY or 0
  local w0, h0 = vp.gameWidth or g.getWidth(), vp.gameHeight or g.getHeight()
  g.push("all")
  g.origin()
  hudStyle = hudStyle or g.newFont(11)
  g.setFont(hudStyle)
  local fh = hudStyle:getHeight()
  local pad = 3
  -- status pill, top-right
  local sw = hudStyle:getWidth(status) + pad * 2
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", x0 + w0 - sw - 4, y0 + 4, sw, fh + 2, 3, 3)
  g.setColor(1, 1, 1, 0.95)
  g.print(status, x0 + w0 - sw - 4 + pad, y0 + 5)
  -- recent lines, bottom-left
  local maxW = math.floor(w0 * 0.7)
  local y = y0 + h0 - 6
  for i = #recent, 1, -1 do
    local e = recent[i]
    local line = Chat.format(e)
    while #line > 1 and hudStyle:getWidth(line) > maxW - pad * 2 do line = line:sub(1, -2) end
    local age = now - (e.t or now)
    local alpha = age > ChatOverlay.HUD_SECONDS - 2 and math.max(0, (ChatOverlay.HUD_SECONDS - age) / 2) or 1
    y = y - fh - 2
    g.setColor(0, 0, 0, 0.55 * alpha)
    g.rectangle("fill", x0 + 4, y, hudStyle:getWidth(line) + pad * 2, fh + 1, 2, 2)
    if e.kind == "chat" then g.setColor(1, 1, 1, alpha)
    elseif e.kind == "notice" then g.setColor(1, 0.85, 0.4, alpha)
    else g.setColor(0.7, 0.9, 1, alpha) end
    g.print(line, x0 + 4 + pad, y)
  end
  g.pop()
  local _ = scale
end

return ChatOverlay
