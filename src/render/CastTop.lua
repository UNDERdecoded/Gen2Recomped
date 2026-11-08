-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- TV / CAST = TOP: THE MAIN PICTURE GOES TO THE OTHER DISPLAY.
--
-- See src/ui/CastDisplay.lua for the option.  This is the frame plumbing: the
-- whole frame -- launcher or game, exactly as it would have reached the phone
-- -- is drawn into a canvas the size of the window instead of the window, a
-- downscaled copy goes to the host through the same frame.bin the bottom
-- screen uses, and then the phone's window gets:
--
--   * a dual-screen game (Gen 4/5): the bottom screen, letterboxed to fill
--     the window, with the touch pad over it.  `SecondScreen.mode` answers
--     `display` in TOP, so every screen already draws its lower half into
--     the offscreen canvas; this just shows that canvas on the phone.  Taps
--     that are not the pad's are mapped into the bottom screen's 256x192 and
--     injected through `SecondScreen.injectTouch` -- the door the host's own
--     taps use in BOTTOM -- so no screen learns a new coordinate space.
--   * anything else (the launcher, Gen 1-3): the same picture it always had.
--     The TV gets a copy.  The launcher deliberately stays whole on the phone
--     so its settings -- and the way back out of TOP -- stay in reach.
--
-- WHY A FILE AND NOT A STREAM: it is the transport the host already polls,
-- it needs no native rebuild, and the cost is measurable.  Measured on the
-- dev desktop with JIT off (as the phone-emulation kit runs) and a DPI-3
-- source canvas, per pushed frame: GPU readback 0.98 ms + getString 0.75 ms
-- at 640x360 (0.58 + 0.17 ms at 256x192).  The WRITE is the expensive part --
-- love.filesystem.write of 0.7-0.9 MB took 45-85 ms here -- so it happens on
-- a writer thread (below) with stdio, and the frame keeps only the readback:
-- a stand-in dual-screen frame in TOP measured 0.39 ms avg / 2.8 ms max over
-- 6000 frames, with 19.5 TV frames a second actually written (cap 20).  The
-- size is capped at MAX_W x MAX_H with the window's aspect.  None of it runs
-- unless TOP is live.

local CastTop = {}

CastTop.MAX_W, CastTop.MAX_H = 640, 360
CastTop.PUSH_INTERVAL = 1 / 20
-- write frames from a love.thread (below); false = synchronously, as BOTTOM does
CastTop.THREADED = true

local state = {
  on = false,          -- a frame is being redirected right now
  target = nil,        -- the window-sized canvas the frame is drawn into
  tv = nil,            -- the downscaled copy that is read back
  pushedAt = nil,
  rect = nil,          -- where the bottom screen is on the phone: {x, y, s}
  owned = {},          -- touch ids this module routed into the bottom screen
  saved = nil,
}
CastTop._state = state

local W, H = 256, 192

local function UI()
  local ok, SS = pcall(require, "src.ui.SecondScreen")
  return ok and SS or nil
end

function CastTop.active()
  local SS = UI()
  if not (SS and SS.castTop) then return false end
  local ok, yes = pcall(SS.castTop)
  return (ok and yes) and true or false
end

-- Whether this game's lower screen is what the phone should show.
local function bottomOnPhone(game)
  if not game then return false end
  local SS = UI()
  if not SS then return false end
  local ok, avail = pcall(SS.available, game)
  return (ok and avail) and not game.secondScreenAlways and true or false
end

-- The TV copy's size: the window's aspect, inside MAX_W x MAX_H, never larger
-- than the window itself.  Even numbers, which some scalers prefer.
function CastTop.tvSize(pw, ph)
  pw, ph = tonumber(pw) or 0, tonumber(ph) or 0
  if pw <= 0 or ph <= 0 then return CastTop.MAX_W, CastTop.MAX_H end
  local s = math.min(CastTop.MAX_W / pw, CastTop.MAX_H / ph, 1)
  local w = math.max(2, math.floor(pw * s / 2) * 2)
  local h = math.max(2, math.floor(ph * s / 2) * 2)
  return w, h
end

-- The bottom screen, letterboxed into a w x h window.
function CastTop.fit(w, h)
  local s = math.min(w / W, h / H)
  return (w - W * s) / 2, (h - H * s) / 2, s
end

-- Start a frame.  Returns true when the frame is being redirected, and then
-- `finish` must be called once it is drawn.
function CastTop.begin(game)
  state.on = false
  if not CastTop.active() then
    state.rect = nil
    return false
  end
  local g = love.graphics
  local w, h = g.getDimensions()
  local dpi = g.getDPIScale and g.getDPIScale() or 1
  local t = state.target
  if not (t and state.targetW == w and state.targetH == h and state.targetDpi == dpi) then
    if t and t.release then pcall(t.release, t) end
    local ok, made = pcall(g.newCanvas, w, h, { dpiscale = dpi })
    if not (ok and made) then state.target = nil return false end
    made:setFilter("linear", "linear")
    state.target, state.targetW, state.targetH, state.targetDpi = made, w, h, dpi
  end
  local target = state.target
  -- THE SCREEN IS THE CANVAS for the length of the frame: the Renderer ends
  -- its passes with a bare setCanvas(), which would otherwise draw the rest
  -- straight onto the phone (src/import/LauncherBackdrop.lua does the same).
  local setCanvas = g.setCanvas
  local TC = package.loaded["src.core.TouchControls"]
  state.saved = { setCanvas = setCanvas, TC = TC, tcDraw = TC and TC.draw }
  g.setCanvas = function(c, ...)
    if c == nil and state.on then
      return setCanvas({ target, depthstencil = true })
    end
    return setCanvas(c, ...)
  end
  -- The pad belongs to the phone, not to the TV's picture: drawn after.
  if TC then TC.draw = function() end end
  state.on = true
  setCanvas({ target, depthstencil = true })
  g.clear(0, 0, 0, 1)
  return true
end

local function restore()
  local s = state.saved
  state.saved = nil
  state.on = false
  if not s then return end
  love.graphics.setCanvas = s.setCanvas
  if s.TC then s.TC.draw = s.tcDraw end
end

-- THE WRITE LEAVES THE FRAME.  A synchronous love.filesystem.write of ~700 KB
-- sat inside the draw: on the dev desktop that measured 45-85 ms a push
-- (Windows scans a file on close), and nothing promises a phone's storage is
-- always quick either.  So the main thread only reads the canvas back and
-- hands the ImageData to a thread that builds the packet and writes it; the
-- frame pays the readback (~1 ms) and nothing else.  One frame in flight at a
-- time: a TV that cannot keep up gets the newest frame, never a queue.
local WRITER = [[
require("love.filesystem")
require("love.image")
local jobs = love.thread.getChannel("g2_cast_top_jobs")
local done = love.thread.getChannel("g2_cast_top_done")
while true do
  local job = jobs:demand()
  if job == "quit" then return end
  local ok = pcall(function()
    local body = job.data:getString()
    -- straight to the real file when its path is known: PhysFS's write
    -- measured 4-6x slower than stdio for the same bytes
    local f = job.real and io.open(job.real, "wb")
    if f then
      f:write(job.header, body)
      f:close()
    else
      love.filesystem.write(job.path, job.header .. body)
    end
  end)
  if job.data.release then pcall(job.data.release, job.data) end
  done:push(ok and true or false)
end
]]

local writer = { thread = nil, failed = false, busy = false }

local function threadWrite(data, header, path)
  if writer.failed or not (love.thread and love.thread.newThread) then return nil end
  if not writer.thread then
    local ok, th = pcall(love.thread.newThread, WRITER)
    if not (ok and th) then writer.failed = true return nil end
    local okStart = pcall(th.start, th)
    if not okStart then writer.failed = true return nil end
    writer.thread = th
  end
  local err = writer.thread:getError()
  if err then
    writer.failed = true
    pcall(function() require("src.core.Logger").warn("cast writer thread: %s", err) end)
    return nil
  end
  local done = love.thread.getChannel("g2_cast_top_done")
  while done:pop() ~= nil do writer.busy = false end
  if writer.busy then return false end      -- previous frame still going out
  writer.busy = true
  -- The real path, only when the save directory is the place PhysFS writes
  -- (it is, on every platform LOVE runs: setIdentity's save dir is the write
  -- dir); otherwise nil and the thread uses love.filesystem.
  if writer.real == nil then
    local ok, dir = pcall(love.filesystem.getSaveDirectory)
    writer.real = (ok and type(dir) == "string" and dir ~= "") and (dir .. "/" .. path) or false
  end
  love.thread.getChannel("g2_cast_top_jobs"):push({ data = data, header = header,
    path = path, real = writer.real or nil })
  return true
end
CastTop._writer = writer

local function push(target)
  local now = love.timer and love.timer.getTime() or 0
  if state.pushedAt and now - state.pushedAt < CastTop.PUSH_INTERVAL
     and now >= state.pushedAt then
    return false
  end
  local g = love.graphics
  local pw, ph = target:getPixelDimensions()
  local tw, th = CastTop.tvSize(pw, ph)
  local tv = state.tv
  if not (tv and tv:getWidth() == tw and tv:getHeight() == th) then
    if tv and tv.release then pcall(tv.release, tv) end
    local ok, made = pcall(g.newCanvas, tw, th, { dpiscale = 1, format = "rgba8" })
    if not (ok and made) then state.tv = nil return false end
    state.tv = made
    tv = made
  end
  local lw, lh = target:getDimensions()
  g.push("all")
  g.origin()
  g.setScissor()
  if g.setShader then g.setShader() end
  g.setCanvas(tv)
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  g.setBlendMode("replace")
  g.draw(target, 0, 0, 0, tw / lw, th / lh)
  g.pop()
  local okT, T = pcall(require, "src.render.SecondScreen")
  if not (okT and T) then return false end
  -- the writer is still on the last frame: skip the readback as well
  if writer.busy and not writer.failed and writer.thread then
    local done = love.thread.getChannel("g2_cast_top_done")
    while done:pop() ~= nil do writer.busy = false end
    if writer.busy then return false end
  end
  local okData, data = pcall(tv.newImageData, tv)
  if not (okData and data) then return false end
  local sent = false
  if T.frameHeader and CastTop.THREADED then
    local queued = threadWrite(data, T.frameHeader(tw, th), T.FRAME)
    if queued ~= nil then
      -- the thread owns `data` now (it releases it)
      if queued then state.pushedAt = now end
      return queued
    end
  end
  if T.filePush then
    local okPush, r = pcall(T.filePush, data, tw, th)
    sent = okPush and r and true or false
  end
  if data.release then pcall(data.release, data) end
  if sent then state.pushedAt = now end
  return sent
end

-- End a frame begun with `begin`: send the TV its copy, then give the phone
-- its own picture.
function CastTop.finish(game, began)
  if not began then return end
  local target = state.target
  restore()
  local g = love.graphics
  g.setCanvas()
  if not target then return end
  pcall(push, target)

  g.push("all")
  g.origin()
  g.setScissor()
  if g.setShader then g.setShader() end
  g.setColor(1, 1, 1, 1)
  local canvas = bottomOnPhone(game) and game.secondScreenCanvas or nil
  if canvas then
    local w, h = g.getDimensions()
    local x, y, s = CastTop.fit(w, h)
    g.clear(0, 0, 0, 1)
    g.draw(canvas, x, y, 0, s * W / canvas:getWidth(), s * H / canvas:getHeight())
    state.rect = { x = x, y = y, s = s }
  else
    g.setBlendMode("alpha", "premultiplied")
    g.draw(target, 0, 0)
    state.rect = nil
  end
  g.pop()
  -- ...and the pad, over whichever picture the phone got.  It was held back
  -- from the redirected frame (begin), so this is its only draw.
  if game then
    local TC = package.loaded["src.core.TouchControls"]
    if TC and TC.draw then pcall(TC.draw, TC) end
  end
end

-- Should this window touch go to the bottom screen?  Called from the top of
-- Game:touchpressed/moved/released; true means it was taken.
local METHOD_OK = { touchpressed = true, touchmoved = true, touchreleased = true }

function CastTop.routeTouch(game, method, id, x, y)
  if not METHOD_OK[method] or not game then return false end
  local r = state.rect
  local owned = state.owned[id]
  if not r then
    if owned then state.owned[id] = nil end
    return false
  end
  if not (owned or CastTop.active()) then return false end
  local TC = package.loaded["src.core.TouchControls"]
  if method == "touchpressed" then
    -- the pad's own buttons win, as they do on the normal screen
    if TC and TC.visible and TC:visible() and TC.hitTest and TC:hitTest(x, y) then
      return false
    end
    local lx, ly = (x - r.x) / r.s, (y - r.y) / r.s
    if lx < 0 or ly < 0 or lx >= W or ly >= H then return false end
    state.owned[id] = true
  elseif not owned then
    return false
  end
  local lx, ly = (x - r.x) / r.s, (y - r.y) / r.s
  if method == "touchreleased" then state.owned[id] = nil end
  local SS = UI()
  if SS and SS.injectTouch then pcall(SS.injectTouch, game, method, id, lx, ly) end
  return true
end

return CastTop
