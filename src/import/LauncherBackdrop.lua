-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LAUNCHER'S BACKGROUND: an imported game's own title / main menu, running
-- behind the launcher -- or a video the player picked, or nothing.
--
-- It is the real game, booted the way main.lua's bootGame boots it (mount the
-- version's cache, evict the last game's generated modules and images,
-- Game:load), and drawn into a canvas the launcher lays its panels over. It
-- never sees input: main.lua hands every event to the launcher while the
-- launcher is up, and Game reads input only from those events.
--
-- ONE VERSION CAN BE MOUNTED AT A TIME, so the backdrop gives its mount up --
-- `stop` -- before anything else wants one: pressing Play (bootGame mounts its
-- own), opening the map or save editor, and a ROM import. Switching games
-- waits for the selection to settle (SETTLE seconds) so walking the game list
-- does not reload a cartridge per step.

local B = {}

B.SETTLE = 0.45
B.VIDEO_FILE = "launcher_background.ogv"
-- Convert YUV video once per background frame, then composite a bounded
-- RGBA canvas at the UI's full frame rate. Window/DPI size never multiplies
-- video conversion cost; NX gets a lighter decorative frame cadence.
B.VIDEO_MAX_WIDTH,B.VIDEO_MAX_HEIGHT=960,540
B.VIDEO_FPS=30
B.PREVIEW_FPS=30
local function handheld()
  return love.system and love.system.getOS and love.system.getOS()=="NX"
end
local function previewFPS()return handheld() and 15 or B.PREVIEW_FPS end
local function backdropSize(w,h)
  local maxW,maxH=B.VIDEO_MAX_WIDTH,B.VIDEO_MAX_HEIGHT
  if handheld() then maxW,maxH=math.min(maxW,640),math.min(maxH,360) end
  local scale=math.min(1,maxW/w,maxH/h)
  return math.max(1,math.floor(w*scale)),math.max(1,math.floor(h*scale))
end

local state = {
  current = nil,        -- the version whose menu is running, or "video"
  want = nil,
  wantSince = 0,
  game = nil,
  canvas = nil,
  video = nil,
  failed = {},          -- version -> why it would not boot (not retried)
  music = true,
}
B._state = state

local function log(fmt, ...)
  local args = { ... }
  pcall(function() require("src.core.Logger").info("launcher backdrop: " .. fmt, unpack(args)) end)
end

-- what the background should be: a version id, "video", or nil
function B.request(want, musicOn)
  if want ~= state.want then
    state.want = want
    state.wantSince = love.timer and love.timer.getTime() or 0
  end
  state.music = musicOn ~= false
end

function B.current() return state.current end

-- PAUSED (the launcher's Settings page is open): the game neither ticks nor
-- plays music, a video holds its frame, and no switch to another game happens
-- -- so walking the BACKGROUND list does not boot a cartridge per step. The
-- last frame stays on screen; unpausing picks up whatever is wanted by then.
function B.setPaused(on)
  on = on and true or false
  if on == (state.paused or false) then return end
  state.paused = on
  if on then
    if state.video then pcall(function() state.video:pause() end) end
    if state.game then pcall(function() require("src.core.Music").suspend() end) end
  else
    if state.video then pcall(function() state.video:play() end) end
    if state.game then
      local data = state.game.data
      pcall(function() require("src.core.Music").resume(data) end)
    end
    -- the selection settles afresh from here
    state.wantSince = love.timer and love.timer.getTime() or 0
  end
end
function B.paused() return state.paused == true end
function B.failedFor(v) return state.failed[v] end

-- let the mount go: before Play, an editor, an import -- and on every switch
function B.stop()
  local was = state.current
  if state.video then
    pcall(function() state.video:pause() end)
    if state.video.release then pcall(state.video.release,state.video) end
    state.video = nil
  end
  if state.game then
    pcall(function() require("src.core.Music").stop() end)
    pcall(function() require("src.core.Sound").stopAll() end)
  end
  if was and was ~= "video" then
    pcall(function() require("src.import.CacheFs").unmountVersion(was) end)
    pcall(function() require("src.core.Data"):unloadGenerated() end)
    pcall(function() require("src.render.Assets").invalidate() end)
  end
  if state.game then state.game.launcherPreview = nil end
  for _,key in ipairs({"videoCanvas","canvas"})do
    local canvas=state[key]
    if canvas and canvas.release then pcall(canvas.release,canvas) end
    state[key]=nil
  end
  state.videoNext,state.videoVolume,state.videoCacheFailed=nil,nil,nil
  state.previewNext,state.previewDt=nil,nil
  state.game, state.current, state.paused = nil, nil, nil
  if was then log("stopped %s", tostring(was)) end
end

local function startVideo()
  if not (love.graphics and love.graphics.newVideo and love.filesystem.getInfo(B.VIDEO_FILE)) then
    return false, "no video chosen"
  end
  local ok, video = pcall(love.graphics.newVideo, B.VIDEO_FILE, { audio = true })
  if not ok or not video then return false, tostring(video) end
  state.video = video
  video:play()
  state.current = "video"
  return true
end

local function startGame(version)
  local GameVersion = require("src.core.GameVersion")
  local CacheFs = require("src.import.CacheFs")
  GameVersion.set(version)
  pcall(function() require("src.core.Data"):unloadGenerated() end)
  local mounted, why = CacheFs.mountVersion(version)
  if not mounted then return false, "could not mount: " .. tostring(why) end
  pcall(function() require("src.render.Assets").invalidate() end)
  -- the window belongs to the launcher: FAITHFUL RES may not resize it
  local FR = require("src.core.FaithfulRes")
  local frApply = FR.applyOptions
  FR.applyOptions = function() end
  local Game = require("src.core.Game")
  -- ...and without mods: the preview is the cartridge's own menu, and a mod
  -- loaded here would be loaded AGAIN by Play in the same process (see
  -- Game:load). Cleared straight after, so Play loads them as always.
  Game.loadWithoutMods = true
  local ok, err = pcall(Game.load, Game)
  Game.loadWithoutMods = nil
  FR.applyOptions = frApply
  if not ok then
    pcall(CacheFs.unmountVersion, version)
    pcall(function() require("src.core.Data"):unloadGenerated() end)
    return false, tostring(err)
  end
  Game.launcherPreview = true
  state.game, state.current = Game, version
  log("running %s's menu", version)
  return true
end

-- A NATIVE FILE PICKER IS ABOUT TO OPEN (RomImporter's pickFile / pickFolder /
-- createFile). On a phone it is another activity, and Android reclaims the
-- memory of the one behind it: a launcher holding a running game's menu
-- (over 100 MB of Lua heap with a DS title) is the first thing killed, and the
-- app then simply closes instead of installing the pick. So the game goes,
-- with everything rebuildable it left behind, and does not come back until the
-- picker has returned (releaseHold, from RomImporter:focus) or `seconds` have
-- passed (an in-process iOS sheet that was cancelled raises nothing).
function B.holdForPicker(seconds)
  state.holdUntil = (love.timer and love.timer.getTime() or 0) + (seconds or 120)
  if state.current then B.stop() end
  -- the backdrop game's supersampled screen and smoothed glyph pages
  pcall(function()
    local SS = package.loaded["src.render.SuperSample"]
    if SS and SS.canvas then
      if SS.canvas.release then SS.canvas:release() end
      SS.canvas, SS.key = nil, nil
    end
  end)
end
function B.releaseHold()
  if state.holdUntil then
    state.holdUntil = nil
    state.wantSince = love.timer and love.timer.getTime() or 0
  end
end

function B.update(dt, busy)
  -- an import owns the cache paths while it runs
  if busy then
    if state.current then B.stop() end
    return
  end
  if state.paused then return end
  local now = love.timer and love.timer.getTime() or 0
  if state.holdUntil then
    if now < state.holdUntil then return end
    state.holdUntil = nil
  end
  if state.want ~= state.current and (now - state.wantSince) >= B.SETTLE then
    B.stop()
    local want = state.want
    if want == "video" and not state.failed.video then
      local ok, why = startVideo()
      if not ok then state.failed.video = why end
    elseif want and not state.failed[want] then
      local ok, why = startGame(want)
      if not ok then
        state.failed[want] = why
        log("%s would not boot: %s", want, tostring(why))
        state.current = nil
      end
    end
    -- nothing to show, or it failed: remember the answer so this does not
    -- retry every frame
    if state.current == nil then state.current = nil; state.want = state.want end
  end
  if state.video then
    local v = state.video
    if not v:isPlaying() then pcall(function() v:rewind(); v:play() end) end
    local src = v.getSource and v:getSource()
    local volume=state.music and 0.6 or 0
    if src and volume~=state.videoVolume then
      pcall(src.setVolume,src,volume);state.videoVolume=volume
    end
  end
  if state.game then
    state.previewDt=(state.previewDt or 0)+math.min(dt or 0,0.1)
    if state.previewDt<1/previewFPS() then return end
    local step=state.previewDt;state.previewDt=0
    local ok, err = pcall(state.game.update, state.game, step)
    if not ok then
      state.failed[state.current] = tostring(err)
      log("%s stopped: %s", tostring(state.current), tostring(err))
      B.stop()
      return
    end
    if not state.music then pcall(function() require("src.core.Music").stop() end) end
  end
end

local function videoFrame(g)
  local video=state.video
  if state.videoCacheFailed or not (g.newCanvas and g.getCanvas) then return video end
  local now=love.timer and love.timer.getTime() or 0
  local vw,vh=video:getDimensions()
  if not state.videoCanvas then
    local cw,ch=backdropSize(vw,vh)
    local ok,canvas=pcall(g.newCanvas,cw,ch,{dpiscale=1})
    if not ok then state.videoCacheFailed=true;return video end
    state.videoCanvas=canvas
    if canvas.setFilter then canvas:setFilter("linear","linear") end
  elseif state.paused or now<(state.videoNext or 0) then return state.videoCanvas end
  local canvas=state.videoCanvas
  local previous=g.getCanvas()
  g.push("all")
  local ok,err=pcall(function()
    g.setCanvas(canvas);g.origin();g.setScissor();g.setShader()
    g.setColor(1,1,1,1);g.setBlendMode("alpha","alphamultiply")
    g.clear(0,0,0,1)
    g.draw(video,0,0,0,canvas:getWidth()/vw,canvas:getHeight()/vh)
  end)
  g.setCanvas(previous);g.pop()
  if not ok then
    canvas:release();state.videoCanvas=nil;state.videoCacheFailed=true
    log("video cache unavailable: %s",tostring(err));return video
  end
  local osName=love.system and love.system.getOS and love.system.getOS()
  state.videoNext=now+1/(osName=="NX" and 15 or B.VIDEO_FPS)
  return canvas
end

-- draw it into `area` ({x, y, w, h}: the launcher's content beside the
-- sidebar), or over the whole window; false when there is nothing to draw
function B.draw(w, h, area)
  local g = love.graphics
  local ax, ay, aw, ah = 0, 0, w, h
  if area then ax, ay, aw, ah = area.x, area.y, area.w, area.h end
  if state.video then
    local frame=videoFrame(g)
    local vw, vh = frame:getDimensions()
    local sc = math.max(aw / vw, ah / vh)
    g.setColor(1, 1, 1, 1)
    g.setScissor(ax, ay, aw, ah)
    g.draw(frame, ax + (aw - vw * sc) / 2, ay + (ah - vh * sc) / 2, 0, sc, sc)
    g.setScissor()
    return true
  end
  if not state.game then return false end
  local cw,chh=backdropSize(aw,ah)
  local now=love.timer and love.timer.getTime() or 0
  local function composite(target)
    g.push("all");g.origin();g.setColor(1,1,1,1)
    g.setBlendMode("alpha","premultiplied")
    g.draw(target,ax,ay,0,aw/cw,ah/chh);g.pop()
  end
  if state.canvas and state.canvas:getWidth()==cw and state.canvas:getHeight()==chh
      and (state.paused or now<(state.previewNext or 0)) then
    composite(state.canvas);return true
  end
  -- STRAIGHT TO THE SCREEN, first thing in the launcher's frame: the game's
  -- Renderer ends its own frame by binding the screen (setCanvas()), so a
  -- canvas set around it here is left empty and the picture lands on the
  -- screen anyway. The launcher draws everything else over it.
  local TC = package.loaded["src.core.TouchControls"]
  local tcDraw = TC and TC.draw
  if TC then TC.draw = function() end end
  -- FITTED TO THE AREA. The game's Renderer ends its frame by binding the
  -- screen (setCanvas()) and sizes its letterbox from the window, so for the
  -- length of the draw "the screen" is a canvas the size of the area: a
  -- bare setCanvas() binds it, and the window measures as the area. The
  -- canvas then goes where the area is.
  local Renderer = require("src.render.Renderer")
  local prevSplit = Renderer.splitViewport
  local saved, target
  do
    local dpi=1
    if not (state.canvas and state.canvas:getWidth() == cw and state.canvas:getHeight() == chh) then
      if state.canvas and state.canvas.release then state.canvas:release() end
      state.canvas = g.newCanvas(cw, chh,{dpiscale=1})
    end
    target = state.canvas
    Renderer.splitViewport = { w = cw, h = chh }
    saved = {}
    local function swap(name, fn) saved[name] = g[name]; g[name] = fn end
    local setCanvas = g.setCanvas
    swap("setCanvas", function(c, ...)
      if c == nil then return setCanvas({ target, depthstencil = true }) end
      return setCanvas(c, ...)
    end)
    swap("getDimensions", function() return cw, chh end)
    if g.getDPIScale then swap("getDPIScale",function()return 1 end) end
    swap("getWidth", function() return cw end)
    swap("getHeight", function() return chh end)
    if g.getPixelDimensions then
      swap("getPixelDimensions", function() return math.floor(cw * dpi), math.floor(chh * dpi) end)
      swap("getPixelWidth", function() return math.floor(cw * dpi) end)
      swap("getPixelHeight", function() return math.floor(chh * dpi) end)
    end
    setCanvas({ target, depthstencil = true })
    g.clear(0, 0, 0, 1)
  end
  -- A DS GAME: THE TOP SCREEN, AND ITS SINGLE-SCREEN TITLE.
  --  * on a title screen (Gen4Title / HgssTitle / Gen5Title) SecondScreen
  --    answers `swap`, a single-screen mode, so the title draws its own
  --    one-screen composition -- the lower screen's Pokemon behind the logo;
  --  * everywhere else (the intro, the opening movie) it answers `display`
  --    -- the screens are separate -- and the lower screen's drawing is
  --    dropped, so only the top screen shows rather than both squeezed onto
  --    one.
  -- For the backdrop's game only, whatever layout the player picked for play.
  local SS, ssMode, ssDraw
  local info = require("src.core.GameVersion").info(state.current)
  if info and (tonumber(info.generation) or 0) >= 4 then
    local okSS, mod = pcall(require, "src.ui.SecondScreen")
    if okSS and mod and mod.mode and mod.draw then
      SS, ssMode, ssDraw = mod, mod.mode, mod.draw
      local game = state.game
      local stack = game.stack and game.stack.states
      local top = stack and stack[#stack]
      local onTitle = false
      if top then
        local mt = getmetatable(top)
        for _, name in ipairs({ "src.ui.Gen4Title", "src.ui.HgssTitle", "src.ui.Gen5Title" }) do
          local T = package.loaded[name]
          if T and (mt == T or (mt and mt.__index == T)) then onTitle = true end
        end
      end
      local want = onTitle and "swap" or "display"
      SS.mode = function(gm, ...)
        if gm == game then return want end
        return ssMode(gm, ...)
      end
      if not onTitle then
        SS.draw = function(gm, body, ...)
          if gm == game then gm.secondScreenDrawnThisFrame = true; return end
          return ssDraw(gm, body, ...)
        end
      end
    end
  end
  g.push("all")
  local ok, err = pcall(state.game._draw, state.game)
  g.pop()
  if SS then SS.mode, SS.draw = ssMode, ssDraw end
  if saved then for name, fn in pairs(saved) do g[name] = fn end end
  g.setCanvas()
  Renderer.splitViewport = prevSplit
  if target then composite(target) end
  state.previewNext=now+1/previewFPS()
  if TC then TC.draw = tcDraw end
  if not ok then
    state.failed[state.current] = tostring(err)
    log("%s could not draw: %s", tostring(state.current), tostring(err))
    B.stop()
    return false
  end
  return true
end

return B
