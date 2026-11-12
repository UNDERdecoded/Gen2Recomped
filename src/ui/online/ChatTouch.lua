-- THE CHAT BUTTON ON A TOUCH SCREEN (Android / iOS).  Shown only while the
-- on-screen controls are, an online world or link room can hear chat, and
-- the overworld is the top screen.  It presses Input's "chat" button through
-- the overlay path (source "touch:chat"), so HotActions opens QuickChat
-- exactly as LT does -- and QuickChat's TYPE A LINE raises the phone's own
-- keyboard through ChatOverlay.
--
-- Game hooks: touchpressed / touchreleased (before the virtual controls'
-- hit test) and the frame's end, after TouchControls:draw.

local ChatTouch = {}

ChatTouch.held = nil   -- touch id holding the button

local function enabled(game)
  local TC = package.loaded["src.core.TouchControls"]
  if not (TC and TC.visible and TC:visible()) then return false end
  local stack = game and game.stack
  local top = stack and stack:top()
  if not top or top ~= game.overworld then return false end
  local HotActions = require("src.core.HotActions")
  return HotActions.chatTarget(game) ~= nil
end

-- the button's rectangle in window pixels: top-left of the safe area, sized
-- off the shorter screen side so it is a finger wide on any phone
function ChatTouch.rect()
  local x0, y0, w, h = 0, 0, 800, 600
  local okS, SafeArea = pcall(require, "src.core.SafeArea")
  if okS and SafeArea and SafeArea.rect then
    local ok, a, b, c, d = pcall(SafeArea.rect)
    if ok and c then x0, y0, w, h = a, b, c, d end
  elseif love and love.graphics then
    w, h = love.graphics.getDimensions()
  end
  local side = math.max(36, math.floor(math.min(w, h) * 0.11))
  return x0 + 8, y0 + 8, side * 1.6, side * 0.75
end

local function inside(x, y)
  local rx, ry, rw, rh = ChatTouch.rect()
  return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

function ChatTouch.touchpressed(game, id, x, y)
  if ChatTouch.held or not enabled(game) or not inside(x, y) then return false end
  ChatTouch.held = id
  local Input = require("src.core.Input")
  Input:overlayPressed("chat")
  return true
end

function ChatTouch.touchreleased(game, id, x, y)
  if ChatTouch.held == nil or ChatTouch.held ~= id then return false end
  ChatTouch.held = nil
  require("src.core.Input"):overlayReleased("chat")
  return true
end

function ChatTouch.draw(game)
  if not enabled(game) then return end
  local g = love.graphics
  local rx, ry, rw, rh = ChatTouch.rect()
  g.push("all")
  g.origin()
  g.setColor(0, 0, 0, ChatTouch.held and 0.75 or 0.5)
  g.rectangle("fill", rx, ry, rw, rh, rh * 0.3, rh * 0.3)
  g.setColor(1, 1, 1, 0.9)
  g.setLineWidth(2)
  g.rectangle("line", rx, ry, rw, rh, rh * 0.3, rh * 0.3)
  ChatTouch.font = ChatTouch.font or {}
  local size = math.max(10, math.floor(rh * 0.45))
  local f = ChatTouch.font[size]
  if not f then
    f = g.newFont(size)
    ChatTouch.font[size] = f
  end
  g.setFont(f)
  local label = "CHAT"
  g.print(label, math.floor(rx + (rw - f:getWidth(label)) / 2),
          math.floor(ry + (rh - f:getHeight()) / 2))
  g.pop()
end

return ChatTouch
