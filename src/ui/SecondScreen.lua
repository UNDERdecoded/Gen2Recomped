-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SECOND SCREEN, and it is never a second window.
--
-- From the original brief: "Instead of having two screens for the poketch and
-- bottom screen allow users to switch between the two with a button or have the
-- choice of using a button to show the bottom screen in the top right corner
-- with a hotkey and change its size and interact with it there."
--
-- The game runs in ONE window, like every other version in this launcher, and
-- the player chooses how the bottom screen reaches them.  This module owns that
-- choice and nothing else: it answers WHERE the bottom screen is right now, in
-- the same 256x192 space every Gen 4 screen already draws in, and it wraps a
-- draw so a screen can be written once and appear in either place.
--
-- IT DOES NOT OWN THE STACK.  A screen that wants to be a bottom-screen screen
-- asks for the transform and draws itself; nothing here pushes, pops, or knows
-- what is on the stack.  That is deliberate: the alternative -- a manager that
-- decides which screens are "bottom screen" ones -- puts a second, invisible
-- stack next to the real one, and the first disagreement between them is a
-- screen that cannot be closed.
--
-- THE MODES
--
--   swap    the bottom screen takes the whole window when it is up.  Works at
--           any window size and on a phone, and the DS's own split costs
--           nothing here because the bottom screen is almost never needed
--           DURING an action -- it is a thing you stop to look at.
--   inset   a panel in the TOP-RIGHT corner over the main screen, raised and
--           lowered with a hotkey, interactive in place, and resizable.
--   display a REAL second panel -- the AYN Thor's lower screen, or any other
--           Android secondary display, or an HDMI one.  The window keeps the
--           top screen and never shows the bottom one at all.  Only offered
--           where the host can actually reach a second panel; see
--           `deviceReady` below for why that gate degrades to `swap` rather
--           than to nothing.
--   off     Gen 1-3, and Gen 4 for a player who wants no second surface at
--           all.  Every caller degrades to drawing on the main screen.
--
-- NOTHING HERE IS REACHABLE FOR GEN 1-3 and no Gen 1-3 draw path gains a
-- branch: `SecondScreen.mode` returns "off" for them, and "off" is the case
-- every caller already has to handle.

local SecondScreen = {}

-- The DS's own screen, which is also the space every Gen 4 screen in this port
-- is written in -- so an inset panel is a scale of the picture and not a
-- different layout.
local W, H = 256, 192

SecondScreen.MODES = { "swap", "inset", "display", "off" }

-- How big the inset panel is, as a fraction of the window.  The brief asks for
-- this to be adjustable, so it is a setting and not a constant; these are the
-- stops the options row cycles through.
SecondScreen.SCALES = { 0.35, 0.45, 0.55, 0.70 }
SecondScreen.DEFAULT_SCALE = 2          -- 0.45

-- How far the panel sits from the window's edge, in main-screen pixels.
local MARGIN = 6

-- THE DEVICE'S OWN SECOND SCREEN, which is the only mode that is not a
-- decision about the window.
--
-- `src/render/SecondScreen.lua` is the transport: an FFI bridge to three C
-- symbols in the love-android tree that answer whether a secondary display is
-- attached and take a 256x192 RGBA frame for it.  It is inert everywhere the
-- symbols do not resolve -- desktop LOVE, a plain phone -- and this module
-- treats that as the ordinary case rather than as a failure.
--
-- THE GATE IS NOT OPTIONAL, AND IT DEGRADES TO `swap` RATHER THAN TO NOTHING.
-- A save is portable: the same file opens on the handheld with two panels and
-- on a desktop with one.  A mode that only exists on one of them must not be
-- able to leave the other with no bottom screen anywhere -- which is what
-- returning "off" here would do, because "off" is every caller's cue to draw
-- nothing.  So the stored setting is left exactly as the player set it and only
-- the ANSWER changes; carrying the save back to the handheld brings the second
-- panel back with it, with nothing to set again.
local transportCache, transportTried = nil, false
local function transport()
  if not transportTried then
    transportTried = true
    local ok, T = pcall(require, "src.render.SecondScreen")
    if ok and type(T) == "table" then transportCache = T end
  end
  return transportCache
end

-- Swap the transport out, for the check tool.  Nothing in the game calls this;
-- it exists so `display` mode can be exercised without a second panel, which
-- is the only way any of it gets tested before it ships to the handheld.
function SecondScreen._setTransport(T)
  transportTried, transportCache = true, T
end

-- Whether a real second panel is attached RIGHT NOW.  Asked on every `mode`
-- call rather than probed once at boot, because a display can be plugged in or
-- pulled out mid-session and the fallback has to follow it.
function SecondScreen.deviceReady()
  local T = transport()
  if not (T and T.available) then return false end
  local ok, ready = pcall(T.available)
  return (ok and ready) and true or false
end

local function options(game)
  return (game and game.save and game.save.options) or {}
end

-- Whether this cartridge has a second screen at all.  One question, asked in
-- one place, so no caller has to know how it is answered.
function SecondScreen.available(game)
  -- AN EXPLICIT HOST OVERRIDES THE CARTRIDGE QUESTION. The launcher's own
  -- bottom screen (src/ui/LauncherSecondScreen.lua) runs before any cartridge
  -- is mounted, so there is no generation to answer on -- and a shelf of games
  -- is not a Gen 4 screen in the first place. Nothing else sets this flag, so
  -- every existing caller reaches the same two answers it always did.
  if game and game.secondScreenAlways then return true end
  local data = game and game.data
  if data and data.isGen4Cache then return true end
  local ok, V = pcall(require, "src.core.GameVersion")
  if not ok then return false end
  if V.isDualScreen then
    local okDual, dual = pcall(V.isDualScreen, V.get())
    if okDual then return dual and true or false end
  end
  return (V.generation and V.generation(V.get()) == 4) and true or false
end

function SecondScreen.mode(game)
  if not SecondScreen.available(game) then return "off" end
  local mode = options(game).secondScreenMode
  -- A DEVICE WITH TWO SCREENS USES BOTH, WITHOUT BEING ASKED FIRST.
  --
  -- Reported from play: "make sure platinum is detecting and using the second
  -- screen properly if it exists within android". It was detecting it -- the
  -- options row offers DEVICE only when a panel is really attached -- but
  -- nothing ever seeded this option, so a nil fell through to `swap` and a
  -- Sinnoh session on an AYN Thor opened with the bottom screen sharing the
  -- top one. The panel sat dark until the player found the setting, which
  -- reads exactly like a second screen that was never detected.
  --
  -- ONLY WHEN IT HAS NEVER BEEN SET. `nil` is the one value that means the
  -- player has not chosen, so this is a default and not an override: the
  -- moment they pick anything -- including `swap` -- it is written down and
  -- honoured, on this machine and on one with no panel at all.
  if mode == nil then
    return SecondScreen.deviceReady() and "display" or "swap"
  end
  for _, name in ipairs(SecondScreen.MODES) do
    if mode == name then
      -- see `deviceReady` above: with no panel attached this answers "swap",
      -- not "off", so the bottom screen still reaches the player somewhere
      if name == "display" and not SecondScreen.deviceReady() then
        return "swap"
      end
      return mode
    end
  end
  return "swap"
end

function SecondScreen.scale(game)
  local at = tonumber(options(game).secondScreenScale)
    or SecondScreen.DEFAULT_SCALE
  at = math.max(1, math.min(#SecondScreen.SCALES, math.floor(at)))
  return SecondScreen.SCALES[at], at
end

-- Where the bottom screen is, in main-screen pixels: x, y, and the scale its
-- own 256x192 is drawn at.  Nil when there is no second surface, which is the
-- caller's cue to draw on the main screen as usual.
function SecondScreen.rect(game)
  local mode = SecondScreen.mode(game)
  if mode == "off" then return nil end
  if mode == "swap" then return 0, 0, 1 end
  -- `display` draws into a 256x192 canvas of its own at 1:1 and the canvas is
  -- what goes out to the panel, so the transform is the identity -- the same
  -- answer `swap` gives, for an entirely different reason.  Callers do not have
  -- to know which: `draw` below is where the two part company.
  if mode == "display" then return 0, 0, 1 end
  local scale = SecondScreen.scale(game)
  local w = W * scale
  return W - w - MARGIN, MARGIN, scale
end

-- Is the bottom screen currently up?  On `swap` it is whatever the player last
-- toggled; on `inset` the same, because the panel is raised and lowered with
-- the same hotkey.  Stored on the game rather than the save: which screen you
-- were looking at is not a thing to persist across a load.
function SecondScreen.raised(game)
  return game and game.secondScreenUp and true or false
end

function SecondScreen.toggle(game)
  if not game or SecondScreen.mode(game) == "off" then return false end
  game.secondScreenUp = not game.secondScreenUp
  return game.secondScreenUp
end

-- PUT AWAY, WHICH IS NOT THE SAME QUESTION AS `raised`.
--
-- `raised` is transient and belongs to whatever is on the bottom surface right
-- now: the Poketch sets it when it opens and clears it when it closes. That is
-- the right shape for a screen you open, and the WRONG shape for a screen that
-- is simply on -- a battle's menu is not something the player opens, it is
-- where the menu lives until they say otherwise.
--
-- So this is the player's standing answer to "do I want the bottom screen at
-- all", kept in the SAVE rather than on the session because it is a preference
-- and not a state. `mode == "off"` is still the stronger statement -- no second
-- surface ever; this one is "not just now".
--
-- The two must not be folded together. They were, briefly, and the bug that
-- came out of it is worth remembering: a player who had opened the Poketch
-- once in the field left `secondScreenUp` false behind them, and every battle
-- afterwards came up with the menu stowed for no reason they could see.
function SecondScreen.stowed(game)
  if SecondScreen.mode(game) == "off" then return true end
  return options(game).secondScreenStowed and true or false
end

function SecondScreen.stow(game, away)
  if not (game and game.save and game.save.options) then return false end
  if SecondScreen.mode(game) == "off" then return true end
  game.save.options.secondScreenStowed = away and true or nil
  return SecondScreen.stowed(game)
end

function SecondScreen.toggleStow(game)
  return SecondScreen.stow(game, not SecondScreen.stowed(game))
end

-- Run `body` with the coordinate system moved onto the bottom screen.
--
-- The transform is pushed and popped around the call rather than left for the
-- caller to undo, because a screen that forgets to undo it moves everything
-- drawn after it -- including screens that have nothing to do with this one.
-- THE OFFSCREEN SURFACE for `display` mode.  One canvas, kept on the game so
-- it dies with the session rather than outliving it in a module local, at
-- exactly the DS's own 256x192: the panel it goes to is some other size and
-- scaling to it is the host's job, not a decision baked into the pixels.
local function surfaceSize(game)
  -- A native companion may latch a stable physical-panel size. The Android
  -- host heartbeat is asynchronous and can briefly report protocol fallback
  -- dimensions while Presentation reconnects; using those transient values
  -- here reallocates the framebuffer and visibly flashes the lower display.
  local pinnedW = game and tonumber(game.secondScreenSurfaceWidth)
  local pinnedH = game and tonumber(game.secondScreenSurfaceHeight)
  if pinnedW and pinnedH and pinnedW > 0 and pinnedH > 0 then
    return math.floor(pinnedW), math.floor(pinnedH)
  end
  if game and game.secondScreenNativePanel then
    local T = transport()
    if T and T.readHost then
      local ok, host = pcall(T.readHost)
      if ok and host then
        local w, h = tonumber(host.width), tonumber(host.height)
        if w and h and w > 0 and h > 0 then
          return math.floor(w), math.floor(h)
        end
      end
    end
  end
  return W, H
end

local function logicalSize(game)
  local w = game and tonumber(game.secondScreenLogicalWidth)
  local h = game and tonumber(game.secondScreenLogicalHeight)
  if w and h and w > 0 and h > 0 then
    return math.floor(w), math.floor(h)
  end
  return W, H
end

function SecondScreen.panelSize()
  local T = transport()
  if T and T.readHost then
    local ok, host = pcall(T.readHost)
    if ok and host then
      local w, h = tonumber(host.width), tonumber(host.height)
      if w and h and w > 0 and h > 0 then
        return math.floor(w), math.floor(h)
      end
    end
  end
  return W, H
end


local function surface(game)
  if not game then return nil end
  local sw, sh = surfaceSize(game)
  if game.secondScreenCanvas
     and game.secondScreenCanvasWidth == sw
     and game.secondScreenCanvasHeight == sh then
    return game.secondScreenCanvas
  end
  if game.secondScreenCanvas and game.secondScreenCanvas.release then
    pcall(game.secondScreenCanvas.release, game.secondScreenCanvas)
  end
  game.secondScreenCanvas = nil
  local g = love.graphics
  if not (g and g.newCanvas) then return nil end
  -- Offscreen DS pixels must be device-independent. On high-DPI Android,
  -- newCanvas(W,H) inherits the window DPI scale: on the AYN Thor a logical
  -- 256x192 canvas became a 591x443 backing texture. Canvas:newImageData()
  -- then returns those physical pixels, while the transport header still said
  -- 256x192, producing scrambled rows / rejected frame sizes.
  local ok, made = pcall(g.newCanvas, sw, sh, {
    format = "rgba8",
    dpiscale = 1,
    readable = true,
  })
  -- Older LOVE builds may not know readable/dpiscale settings. Preserve
  -- compatibility, though flush() below will use the actual readback size.
  if not (ok and made) then
    ok, made = pcall(g.newCanvas, sw, sh, { format = "rgba8", dpiscale = 1 })
  end
  if not (ok and made) then
    ok, made = pcall(g.newCanvas, sw, sh)
  end
  if not (ok and made) then return nil end
  if made.setFilter then pcall(made.setFilter, made, "nearest", "nearest") end
  game.secondScreenCanvas = made
  game.secondScreenCanvasWidth = sw
  game.secondScreenCanvasHeight = sh
  return made
end

function SecondScreen.canvas(game)
  return game and game.secondScreenCanvas or nil
end

function SecondScreen.draw(game, body)
  if game then game.secondScreenDrawnThisFrame = true end
  local g = love.graphics
  -- `display` is the one mode where the bottom screen is not in the window,
  -- so it cannot be a translate: the body is rendered to our own canvas and
  -- `flush` sends it on.  Everything the renderer had set is saved and put
  -- back -- canvas, scissor, colour, blend -- because this runs in the MIDDLE
  -- of somebody else's frame.  push("all") covers all of it except the canvas
  -- itself, which is not part of the graphics stack and is restored by hand;
  -- `getCanvas` answering nil is the default target and a fine thing to
  -- restore to.  A live scissor is the one that bites hardest if forgotten: it
  -- is in WINDOW space, and left set it clips the canvas to wherever the
  -- renderer happened to be drawing.
  if SecondScreen.mode(game) == "display" then
    local canvas = surface(game)
    if canvas then
      local previous = g.getCanvas()
      g.push("all")
      g.setCanvas(canvas)
      g.origin()
      g.setScissor()
      -- This target has no world stencil/depth buffer or palette shader.
      -- Inheriting those from the top screen can hide the watch shell.
      if g.setShader then g.setShader() end
      if g.setStencilTest then g.setStencilTest() end
      if g.setDepthMode then g.setDepthMode() end
      g.setColor(1, 1, 1, 1)
      g.clear(0, 0, 0, 1)
      if game.secondScreenNativePanel then
        local sw, sh = surfaceSize(game)
        local lw, lh = logicalSize(game)
        g.scale(sw / lw, sh / lh)
      end
      local ok, err = pcall(body)
      g.setCanvas(previous)
      g.pop()
      game.secondScreenDirty = true
      if not ok then error(err, 0) end
      return
    end
    -- no canvas at all (a headless run, or a GPU that refused one): fall
    -- through, which draws it in the window exactly as `swap` would
  end
  local x, y, scale = SecondScreen.rect(game)
  if not x then return body() end
  g.push()
  g.translate(x, y)
  g.scale(scale, scale)
  local ok, err = pcall(body)
  g.pop()
  if not ok then error(err, 0) end
end

-- SEND THE CANVAS TO THE PANEL.  Called once at the end of the frame, from
-- `Game:draw`, and a no-op in every mode but `display`.
--
-- THE READBACK IS THE EXPENSIVE PART: `newImageData` stalls the pipeline to
-- pull 192KB back off the GPU.  So it is gated twice -- on the frame having
-- drawn a bottom screen at all (`secondScreenDirty`, set by `draw` above) and
-- on a minimum interval.  The bottom screen is a menu surface: it changes
-- when the player does something, so in practice this costs nothing on the
-- frames in between, and the cap means a screen that redraws every frame
-- still cannot make the readback the frame budget.
SecondScreen.PUSH_INTERVAL = 1 / 30

-- THE PANEL'S OWN TAPS, COLLECTED BEFORE THE FRAME GOES OUT.
--
-- The file transport's host writes what it has seen into a file and this is
-- what reads it.  Above the dirty check on purpose: a frame that drew nothing
-- new still has to take the taps, or a panel the player is prodding while the
-- picture is still would be dead.
--
-- Each one goes in through `injectTouch`, which is the same door the native
-- bridge will use, so the battle, the mining screen and the Poketch keep
-- asking the question they already ask and neither transport gets a path of
-- its own.
local TOUCH_METHOD = { down = "touchpressed", move = "touchmoved",
                       up = "touchreleased" }

function SecondScreen.pumpInput(game)
  if not game or SecondScreen.mode(game) ~= "display" then return 0 end
  local T = transport()
  if not (T and T.pollTouch) then return 0 end
  local okPoll, events = pcall(T.pollTouch)
  if not (okPoll and type(events) == "table") then return 0 end
  local taken = 0
  for _, e in ipairs(events) do
    local method = TOUCH_METHOD[e.kind]
    if method and SecondScreen.injectTouch(game, method, e.id, e.x, e.y) then
      taken = taken + 1
    end
  end
  return taken
end

function SecondScreen.flush(game)
  if not game or SecondScreen.mode(game) ~= "display" then return false end
  SecondScreen.pumpInput(game)
  if not game.secondScreenDirty then return false end
  local canvas = SecondScreen.canvas(game)
  if not canvas then return false end
  local T = transport()
  if not (T and T.push) then return false end
  local now = 0
  if love and love.timer and love.timer.getTime then
    local okNow, t = pcall(love.timer.getTime)
    if okNow then now = t end
  end
  local last = game.secondScreenPushedAt
  if last and now - last < SecondScreen.PUSH_INTERVAL then return false end
  local okData, data = pcall(canvas.newImageData, canvas)
  if not (okData and data) then return false end
  -- newImageData reports physical pixel dimensions. Normally dpiscale=1
  -- above makes these exactly 256x192; using the actual dimensions here also
  -- keeps the wire header truthful on a backend which ignores that setting.
  local pushW, pushH = W, H
  if data.getDimensions then
    local okDims, dw, dh = pcall(data.getDimensions, data)
    if okDims and tonumber(dw) and tonumber(dh) and dw > 0 and dh > 0 then
      pushW, pushH = dw, dh
    end
  end
  local okPush, pushed = pcall(T.push, data, pushW, pushH)
  local sent = okPush and pushed and true or false
  if data.release then pcall(data.release, data) end

  -- Do not throw away the pending frame when Android has detected the second
  -- display but its Presentation/file bridge is not ready yet. This is common
  -- during startup on dual-screen Android hardware: keeping the dirty flag set
  -- lets the same bottom-screen state retry on the next eligible frame.
  if sent then
    game.secondScreenDirty = false
    game.secondScreenPushedAt = now
  end
  return sent
end

-- The panel's own frame, drawn around an inset so it reads as a second screen
-- rather than as part of the first.  Nothing on `swap`, where the bottom screen
-- IS the window.
function SecondScreen.drawFrame(game)
  local x, y, scale = SecondScreen.rect(game)
  if not x or scale >= 1 then return end
  local g = love.graphics
  local w, h = W * scale, H * scale
  g.setColor(0, 0, 0, 0.55)
  g.rectangle("fill", x - 2, y - 2, w + 4, h + 4)
  g.setColor(0.80, 0.84, 0.92, 1)
  g.rectangle("line", x - 1.5, y - 1.5, w + 3, h + 3)
  g.setColor(1, 1, 1, 1)
end

-- POINTER ROUTING.  A click inside the panel belongs to the bottom screen and
-- must arrive there in the BOTTOM SCREEN's coordinates, not the window's --
-- which is the whole of "interact with it there".  Returns nil when the point
-- is not the second screen's, so a caller can fall through to the field.
-- IT ANSWERS WHERE, NOT WHETHER, and the difference is a bug this had.
--
-- It used to refuse unless `raised(game)` -- and `draw` above does not ask that.
-- The battle's bottom screen is drawn on `stowed`, the player's standing answer,
-- precisely because a battle menu is not a thing you open; so the picture was on
-- screen and every tap on it was refused here. The two ends of one pipeline
-- disagreeing about when the surface exists.
--
-- WHETHER the surface should be taking input is the caller's question and the
-- callers answer it differently: the Poketch by `raised`, a battle by `stowed`,
-- the mining game by being open at all. So this one only maps the point, exactly
-- where `draw` put the picture -- including `draw`'s own fallback of running the
-- body untransformed when there is no rect, which makes the surface the window's
-- top-left 256x192. Nil means the point is outside that box and nothing else.
-- A POINT THAT CAME FROM THE PANEL, NOT FROM THE WINDOW.
--
-- In `display` mode the bottom screen is not in the window at all, so a window
-- click is never a bottom-screen click and `toLocal` has to refuse it -- or the
-- top-left 256x192 of the field silently doubles as the battle menu, and a tap
-- meant for a Pokemon standing there opens FIGHT.  The panel's own touches
-- arrive from the host already in 256x192 space and come in through here, which
-- sets the flag `toLocal` looks for, so every existing caller -- the battle, the
-- mining screen, the Poketch -- keeps asking exactly the question it already
-- asks and none of them learns a second coordinate space.
function SecondScreen.injectTouch(game, method, id, x, y)
  if not game or SecondScreen.mode(game) ~= "display" then return false end
  local lw, lh = logicalSize(game)
  if game.secondScreenNativePanel and x and y then
    local sw, sh = surfaceSize(game)
    x, y = x * lw / sw, y * lh / sh
  end
  if not (x and y) then return false end
  local captured=game.pointerOwners and game.pointerOwners[id]
  if (x<0 or y<0 or x>=lw or y>=lh)
     and not (captured and (method=='touchmoved' or method=='touchreleased')) then
    return false
  end
  local handler = game[method]
  if type(handler) ~= "function" then return false end
  local was = game.secondScreenInjecting
  game.secondScreenInjecting = true
  local ok = pcall(handler, game, id, x, y)
  game.secondScreenInjecting = was
  return ok
end

function SecondScreen.toLocal(game, px, py)
  if SecondScreen.mode(game) == "display"
     and not (game and game.secondScreenInjecting) then
    return nil
  end
  if not (game and game.secondScreenInjecting) then
    local renderer=package.loaded['src.render.Renderer']
    local rect=renderer and renderer.uiPresentation
    if type(rect)=='table' then
      if px<rect.x or py<rect.y or px>=rect.x+rect.w or py>=rect.y+rect.h then return nil end
      px,py=(px-rect.x)/rect.scaleX,(py-rect.y)/rect.scaleY
    end
  end
  local x, y, scale = SecondScreen.rect(game)
  if not x then x, y, scale = 0, 0, 1 end
  local lx, ly = (px - x) / scale, (py - y) / scale
  if lx < 0 or ly < 0 or lx >= W or ly >= H then return nil end
  return lx, ly
end

function SecondScreen.contains(game, px, py)
  return SecondScreen.toLocal(game, px, py) ~= nil
end

return SecondScreen
