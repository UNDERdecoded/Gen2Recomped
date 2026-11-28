-- THREE BINDABLE ACTIONS THAT ARE NOT CARTRIDGE BUTTONS: CHAT, ZOOM IN and
-- ZOOM OUT.  They ride Input's ordinary maps (so CONTROLS rebinds them with
-- the same capture, swap and reset as A or START) and are read once per
-- logic step by `HotActions.step`, from Game:_step, while the overworld is
-- the top screen.
--
--   CHAT      keyboard T, pad LT (the left trigger, read as an axis past
--             Input's STICK_ON with release under STICK_OFF -- an edge, not
--             a level), touch: the CHAT button (src/ui/online/ChatTouch.lua).
--             Only does anything in an online world or a link room whose
--             friend's build hears room chat; everywhere else the press is
--             simply unused, which is what keeps LT free for a player who
--             binds it to something else.
--             Keyboard -> the typed line (ChatOverlay).  The T that opened
--             it never types a "t": the press is read on the step AFTER the
--             event that carried both keypressed and its textinput, and the
--             overworld under it takes no text.  While the line is open, T is
--             just a letter (ChatOverlay owns every printable key).
--             Pad / touch -> QuickChat (phrases, emotes, TYPE A LINE).
--   ZOOM IN   pad R3 (rightstick), ZOOM OUT pad L3 (leftstick): exactly the
--             mouse wheel (Game:wheelmoved) -- the survey zoom on a flat map
--             (Zoom.lua's integer steps, saved as options.zoom), the free
--             camera's dolly on a Gen 4/5 3D rung (Gen4View:zoomBy).  No
--             keyboard default: '-' / '=' and the wheel already zoom.
--             Both clicks together reset the zoom (HotActions.resetZoom);
--             the OPTIONS ZOOM row resets the flat survey zoom too.
--
--   TOUCH     pad RT (the right trigger, an axis edge like LT): the lower-
--             screen cursor of src/core/PadPointer.lua, handled at event time
--             in Game:gamepadpressed / gamepadaxis rather than per step, so
--             it works over every menu.  Dual-screen games only.
--
-- Defaults are layered by Input:applyBindings UNDER the player's overlay, so
-- a rebind of any other row onto LT / L3 / R3 wins that button.

local HotActions = {}

HotActions.ACTIONS = { "chat", "zoomin", "zoomout", "touch" }
HotActions.IS_ACTION = { chat = true, zoomin = true, zoomout = true, touch = true }
HotActions.KEY_DEFAULTS = { t = "chat" }
HotActions.PAD_DEFAULTS = { triggerleft = "chat", rightstick = "zoomin", leftstick = "zoomout", triggerright = "touch" }

-- where a chat would go right now: (client, "world"|"room") or nil
function HotActions.chatTarget(game)
  local W = package.loaded["src.online.world.OnlineWorld"]
  local c = W and W.client and W.client()
  if c and c.state == "in" then return c, "world" end
  local LR = package.loaded["src.online.LinkRooms"]
  local s = LR and LR.session
  if s then
    local RoomPeer = require("src.online.LinkRoomPeer")
    if RoomPeer.chatAvailable(s) then return RoomPeer.chat(s), "room" end
  end
  return nil
end

-- source: "key" opens the typed line, anything else the quick list
function HotActions.openChat(game, source)
  local c, kind = HotActions.chatTarget(game)
  if not c then return false end
  if source == "key" then
    require("src.ui.online.ChatOverlay").open(game, { client = kind == "room" and c or nil })
  else
    require("src.ui.online.QuickChat").open(game, { client = c, kind = kind })
  end
  return true
end

local function sourceKind(input, btn)
  local src = input.lastSource and input.lastSource[btn]
  if type(src) ~= "string" then return "key" end
  if src:sub(1, 4) == "key:" then return "key" end
  if src:sub(1, 6) == "touch:" then return "touch" end
  return "pad"
end

local function freeRoam(game, top)
  local ow = game.overworld
  if not ow or top ~= ow then return false end
  if ow.transitioning then return false end
  if ow.runner and ow.runner.isRunning and ow.runner:isRunning() then return false end
  return true
end

-- the zoom back to where a fresh game starts: survey FIT (options.zoom 0)
-- and the 3D dolly at 1 (options.camZoom3d cleared)
function HotActions.resetZoom(game)
  local view = game.zoomView and game:zoomView()
  if view then
    view.zoom = 1
    if view.remember then view:remember() end
    if game.rememberViewZoom then game:rememberViewZoom(view) end
  end
  local Zoom = require("src.render.Zoom")
  Zoom.reset()
  local o = game.save and game.save.options
  if o then
    o.zoom = 0
    if game.writeOptions then game:writeOptions() end
  end
  return true
end

-- once per logic step, after Input:step
function HotActions.step(game)
  local input = game and game.input
  if not (input and input.wasPressed) then return end
  local stack = game.stack
  local top = stack and stack:top()
  if not top or top ~= game.overworld then return end
  if input:wasPressed("chat") and freeRoam(game, top) then
    HotActions.openChat(game, sourceKind(input, "chat"))
    return
  end
  -- L3 + R3 together: back to the default view (FIT, and the 3D camera's
  -- own distance).  The first click of the pair has already stepped once;
  -- the reset makes that moot.
  local zin, zout = input:wasPressed("zoomin"), input:wasPressed("zoomout")
  if (zin or zout) and input.isDown and input:isDown("zoomin") and input:isDown("zoomout") then
    HotActions.resetZoom(game)
    return
  end
  -- the wheel's own entry point, so the two can never differ
  if input:wasPressed("zoomin") and game.wheelmoved then
    game:wheelmoved(0, 1)
  elseif input:wasPressed("zoomout") and game.wheelmoved then
    game:wheelmoved(0, -1)
  end
end

return HotActions
