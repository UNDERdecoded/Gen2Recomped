-- QUICK CHAT: the controller / touch way to talk in an online world or a link
-- room.  Opened by the CHAT binding (default LT on a pad, the CHAT touch
-- button on a phone; T on a keyboard goes straight to the typed line in
-- ChatOverlay instead -- see src/core/HotActions.lua).
--
-- A small window over the field (the world keeps drawing and moving): the
-- canned phrases, the emotes, and TYPE A LINE, which opens ChatOverlay with
-- the platform's own text input (the on-screen keyboard on a phone).
-- A picks, B or the CHAT button again closes, LEFT / RIGHT page.

local WorldUi = require("src.ui.online.WorldUi")
local P = require("src.online.world.WorldProtocol")
local Chat = require("src.online.world.Chat")

local QuickChat = {}
QuickChat.__index = QuickChat
QuickChat.isOpaque = false
QuickChat.isWorldUi = true
QuickChat.VISIBLE = 6

local EMOTE_LABEL = { ["!"] = "EMOTE  !", ["?"] = "EMOTE  ?", heart = "EMOTE HEART",
                      note = "EMOTE NOTE", ["..."] = "EMOTE ...", smile = "EMOTE SMILE" }

-- the rows, in order: typed line first (a phone player's most likely want),
-- then phrases, then emotes
function QuickChat.rows()
  local rows = { { label = "TYPE A LINE...", type = true } }
  for _, ph in ipairs(Chat.PHRASES) do rows[#rows + 1] = { label = ph, say = ph } end
  for _, e in ipairs(P.EMOTES) do rows[#rows + 1] = { label = EMOTE_LABEL[e] or ("EMOTE " .. e), emote = e } end
  rows[#rows + 1] = { label = "CLOSE", close = true }
  return rows
end

-- opts.client: the chat surface (WorldClient, or LinkRoomPeer.chat's)
function QuickChat.open(game, opts)
  opts = opts or {}
  local self = setmetatable({}, QuickChat)
  self.game = game
  self.client = opts.client
  self.kind = opts.kind
  self.rows = QuickChat.rows()
  self.index = 2   -- the first phrase: one press of A says hello
  -- opened from HotActions.step BEFORE this step's stack:update: the CHAT
  -- press that opened the window must not also close it
  self.fresh = true
  self.width, self.height = WorldUi.surface()
  self.style = WorldUi.style(game)
  game.stack:push(self)
  WorldUi.sound(game, "Select")
  return self
end

function QuickChat:uiSize() return self.width, self.height end

function QuickChat:close()
  if self.game.stack:top() == self then self.game.stack:pop() end
end

function QuickChat:activate(row)
  local c = self.client
  if row.close then return self:close() end
  if row.type then
    self:close()
    require("src.ui.online.ChatOverlay").open(self.game,
      { client = self.kind == "room" and c or nil })
    return
  end
  if not (c and c.state == "in") then return self:close() end
  if row.say then
    local ok, why = c:say(row.say)
    if ok then return self:close() end
    self.notice = why
    self.noticeLeft = 1.6
    return
  end
  if row.emote then
    c:emote(row.emote)
    return self:close()
  end
end

function QuickChat:update(dt)
  dt = dt or 1 / 60
  local okW, W = pcall(require, "src.online.world.OnlineWorld")
  if okW then W.tick(dt) end
  local c = self.client
  if not (c and c.state == "in") then return self:close() end
  if self.noticeLeft then
    self.noticeLeft = self.noticeLeft - dt
    if self.noticeLeft <= 0 then self.notice, self.noticeLeft = nil, nil end
  end
  local input = self.game.input
  if not input then return end
  if self.fresh then self.fresh = nil return end
  if input:wasPressed("chat") or input:wasPressed("b") then return self:close() end
  self.index = WorldUi.nav(self.game, self.index, self.rows)
  local n = #self.rows
  if input:wasPressed("left") then self.index = math.max(1, self.index - QuickChat.VISIBLE) end
  if input:wasPressed("right") then self.index = math.min(n, self.index + QuickChat.VISIBLE) end
  if input:wasPressed("a") then
    WorldUi.sound(self.game, "Select")
    self:activate(self.rows[self.index])
  end
end

-- a keyboard player who opened this from a pad binding still types: any
-- printable key goes to the typed line
function QuickChat:onTextInput(t)
  if type(t) ~= "string" or t == "" then return end
  self:close()
  local overlay = require("src.ui.online.ChatOverlay").open(self.game,
    { client = self.kind == "room" and self.client or nil })
  if overlay and overlay.onTextInput then overlay:onTextInput(t) end
end

function QuickChat:draw()
  local st = self.style
  local W, H = self.width, self.height
  local lh = st:lineHeight()
  local boxW = math.min(W - 8, 156)
  local x = math.floor((W - boxW) / 2)
  local vis = QuickChat.VISIBLE
  local rowH = lh + 2
  local first = 1
  if self.index > vis then first = self.index - vis + 1 end
  local h = math.min(#self.rows, vis) * rowH + lh + 14
  WorldUi.drawList(st, x, H - h - 4, boxW, self.rows, self.index,
                   self.kind == "room" and "ROOM CHAT" or "QUICK CHAT",
                   { first = first, visible = vis, rowH = rowH })
  if self.notice then
    WorldUi.drawText(st, x, math.max(2, H - h - 4 - (lh + 14)), boxW, self.notice)
  end
end

return QuickChat
