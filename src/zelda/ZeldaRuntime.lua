-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ZELDA RUNTIME: what runs when the player presses Play on a Zelda game.
--
-- main.lua's bootGame hands the version here instead of to Game.lua, and the
-- object `boot` returns stands in for `Game` -- main.lua forwards every LÖVE
-- callback to it, exactly as it does to the Pokemon engine. This object:
--
--   * loads the game module (ZeldaRegistry) and its imported cache
--     (ZeldaCache) and calls module.newGame(opts);
--   * ticks it at the GBA's own frame rate (16777216 / 280896 = 59.7275 Hz)
--     with a fixed step, polling input once per tick;
--   * draws it into a 240x160 canvas, scaled to the window (integer by
--     default, FIT on request), at the top of a portrait phone so the touch
--     controls sit below it;
--   * maps keyboard, gamepad and the touch overlay to A/B/L/R/START/SELECT/
--     D-pad through the SAME Input + TouchControls the Pokemon games use, so
--     a player's CONTROLS rebinds and touch layout carry over;
--   * owns a SYSTEM menu (Escape / the gamepad's guide button / SELECT+START
--     held / the touch MENU button) with RESUME, SAVE, LINK PLAY, OPTIONS and
--     QUIT TO LAUNCHER, so START stays the game's own button;
--   * writes saves into the launcher's save slots (ZeldaSaves);
--   * pumps a ZeldaSession when the player is online and hands the game its
--     snapshots and events (netSnapshot / netApply / netEvent);
--   * shows any error ON SCREEN (Android players cannot read log files) with
--     a way back to the launcher.

local Input = require("src.core.Input")
local GameVersion = require("src.core.GameVersion")

local R = {}

R.W, R.H = 240, 160
R.TICK_HZ = 16777216 / 280896
R.DT = 1 / R.TICK_HZ
R.BUTTONS = { "a", "b", "l", "r", "start", "select", "up", "down", "left", "right" }
-- online: snapshots go out every SNAPSHOT_EVERY ticks (~30 Hz)
R.SNAPSHOT_EVERY = 2

-- THE INPUT FACADE the game modules read (docs/zelda/CONTRACT.md). Button
-- names are the lower-case GBA ones above.
R.input = {}
function R.input.isDown(b) return Input:isDown(b) and true or false end
function R.input.wasPressed(b) return Input:wasPressed(b) and true or false end
function R.input.isTouchDown(b) return Input:isTouchDown(b) end
-- every button's held state as a bitmask (bit i-1 = R.BUTTONS[i]); handy for
-- lockstep netcode
function R.input.mask()
  local m, bit = 0, 1
  for _, b in ipairs(R.BUTTONS) do
    if Input:isDown(b) then m = m + bit end
    bit = bit * 2
  end
  return m
end
function R.input.fromMask(m, b)
  local bit = 1
  for _, name in ipairs(R.BUTTONS) do
    if name == b then return math.floor((m or 0) / bit) % 2 == 1 end
    bit = bit * 2
  end
  return false
end

-- --------------------------------------------------------------- options

local function loadOptions()
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if not ok then return {} end
  local okO, opts = pcall(SaveData.loadOptions)
  return okO and type(opts) == "table" and opts or {}
end

local function saveOptions(opts)
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok then pcall(SaveData.saveOptions, opts) end
end

-- options.zelda = { scale = "integer" | "fit" }; volumes are the shared
-- musicVol / sfxVol (0-7) every game uses.
local function zeldaOptions(opts)
  local z = type(opts.zelda) == "table" and opts.zelda or {}
  if z.scale ~= "fit" then z.scale = "integer" end
  return z
end

-- ------------------------------------------------------------------ host

local Host = {}
Host.__index = Host

local function fontOf(size)
  R._fonts = R._fonts or {}
  size = math.max(8, math.floor(size))
  if not R._fonts[size] then R._fonts[size] = love.graphics.newFont(size) end
  return R._fonts[size]
end

local function logWarn(fmt, ...)
  local okL, Logger = pcall(require, "src.core.Logger")
  if okL and Logger and Logger.warn then pcall(Logger.warn, fmt, ...) end
end

-- Boot a Zelda version. Returns the host object main.lua treats as `Game`.
-- `extra` (tests): { module = <game module>, slot = id, save = table,
-- noSaves = bool }
function R.boot(version, extra)
  extra = extra or {}
  local self = setmetatable({}, Host)
  self.version = version
  self.info = GameVersion.info(version) or {}
  self.acc = 0
  self.ticks = 0
  self.menu = nil
  self.error = nil
  self.notice = nil
  self.noticeT = 0
  self.chordTicks = 0
  self.extra = extra
  self.options = loadOptions()
  self.zopts = zeldaOptions(self.options)
  GameVersion.set(version)

  -- the same input stack the Pokemon games use
  Input:init()
  pcall(function() Input:applyBindings(self.options.bindings) end)
  Input:setButtonMode(1)
  local okT, TC = pcall(require, "src.core.TouchControls")
  if okT then
    self.touch = TC
    pcall(function() TC:init(); TC:applyOptions(self.options) end)
  end

  self.canvas = love.graphics.newCanvas(R.W, R.H)
  self.canvas:setFilter("nearest", "nearest")

  if love.window and love.window.setTitle then
    pcall(function()
      love.window.setTitle(require("src.core.Version").title(
        (self.info.displayName or version) .. " (RetroRecomped)"))
    end)
  end

  local ok, err = xpcall(function() self:_start() end, debug.traceback)
  if not ok then self:_fail("could not start", err) end
  return self
end

function Host:_start()
  local Registry = require("src.zelda.ZeldaRegistry")
  local mod = self.extra.module
  if not mod and os.getenv("POKEPORT_ZELDA_PLACEHOLDER") == "1" then
    mod = require("src.zelda.ZeldaPlaceholder")
  end
  if not mod then
    local why
    mod, why = Registry.require(self.version, "play")
    if not mod then error(why, 0) end
  end
  self.module = mod
  self.cache = require("src.zelda.ZeldaCache").open(self.version)
  local Saves = require("src.zelda.ZeldaSaves")
  local save, slot = self.extra.save, self.extra.slot
  if not self.extra.noSaves and save == nil then
    save, slot = Saves.load(self.version, slot)
  end
  self.slot = slot
  self.gameOpts = {
    version = self.version,
    root = self.cache, cache = self.cache,
    slot = slot, save = save,
    online = nil,
    options = { scale = self.zopts.scale,
                musicVol = self:volume("music"), sfxVol = self:volume("sfx") },
    input = R.input,
    host = self,
    W = R.W, H = R.H, tickHz = R.TICK_HZ,
  }
  self.game = mod.newGame(self.gameOpts)
  assert(type(self.game) == "table", "newGame did not return a game object")
  self:_launcherHub()
end

-- The launcher's Online Hub: its settings patch (hub address for a player's
-- own hub) and the HOST WITH FRIENDS / JOIN FRIEND it asked this game to do.
function Host:_launcherHub()
  local okH, LH = pcall(require, "src.online.LauncherHub")
  if not (okH and type(LH) == "table") then return end
  self.hub = LH
  if LH.patchLinkState then pcall(LH.patchLinkState) end
  local a = LH.pending and LH.pending()
  if not a then return end
  LH.setPending(nil)
  if a.kind == "host" or a.kind == "join" then
    self:openLink()
    if self.link and self.link.runAction then self.link:runAction(a) end
  else
    self:toast("Online worlds are for the Pokemon games.")
  end
end

-- An error from the game or the runtime: kept on screen with the traceback.
function Host:_fail(what, err)
  self.error = { what = what, text = tostring(err) }
  logWarn("zelda %s: %s", tostring(what), tostring(err))
  self.menu = nil
end

-- Call a game method if it has one; an error stops the game and is shown.
function Host:_call(name, ...)
  local g = self.game
  if self.error or not g or type(g[name]) ~= "function" then return nil end
  local args = { n = select("#", ...), ... }
  local ok, a, b = xpcall(function() return g[name](g, unpack(args, 1, args.n)) end, debug.traceback)
  if not ok then self:_fail(name, a) return nil end
  return a, b
end

-- ------------------------------------------------------- the game's host API

-- 0..1, from the shared 0-7 sliders
function Host:volume(kind)
  local v = kind == "sfx" and self.options.sfxVol or self.options.musicVol
  v = tonumber(v) or 7
  return math.max(0, math.min(1, v / 7))
end

-- Persist a save table now (into the active slot). ok, err.
function Host:save(tbl)
  if self.extra.noSaves then self.lastSave = tbl return true end
  local Saves = require("src.zelda.ZeldaSaves")
  if not self.slot then self.slot = Saves.activeSlot(self.version) end
  local ok, err = Saves.write(self.version, self.slot, tbl)
  self:toast(ok and "Saved." or ("Save failed: " .. tostring(err)))
  return ok, err
end

-- Ask the game for its save table (game:save()) and write it.
function Host:requestSave()
  if not (self.game and self.game.save) then
    self:toast("This game cannot save yet.")
    return false
  end
  local tbl = self:_call("save")
  if type(tbl) ~= "table" then
    if not self.error then self:toast("Nothing to save.") end
    return false
  end
  return self:save(tbl)
end

function Host:toast(text)
  self.notice, self.noticeT = text, 2.5
end

function Host:session() return self.sessionObj end

-- Attach / detach a ZeldaSession (src/online/zelda). The game sees it as
-- opts.online and through host:session().
function Host:attachSession(session)
  self.sessionObj = session
  self.gameOpts.online = session
  if session and session.colorIndex == nil and session.localIndex then
    session.colorIndex = session:localIndex()
  end
  self:_call("netAttached", session)
end

function Host:detachSession(reason)
  local s = self.sessionObj
  if not s then return end
  self.sessionObj = nil
  self.gameOpts.online = nil
  pcall(s.close, s)
  self:_call("netDetached", reason)
  if reason then self:toast(reason) end
end

-- Leave the game for the launcher. The game gets quit() first.
function Host:quit()
  self:_call("quit")
  self:detachSession()
  pcall(function() love.audio.stop() end)
  pcall(function() if self.touch then self.touch:reset() end end)
  self.quitting = true
  local HostShell = require("src.core.HostShell")
  if self.extra.onQuit then return self.extra.onQuit() end
  HostShell.toLauncher()
end

function Host:openLink()
  local ok, Menu = pcall(require, "src.online.zelda.ZeldaLinkMenu")
  if not ok then self:toast("Online play is not available: " .. tostring(Menu)) return end
  self.menu = nil
  self.link = Menu.new(self)
end

-- -------------------------------------------------------------- the frame

function Host:_pumpSession()
  local s = self.sessionObj
  if not s then return end
  local ok, err = pcall(s.update, s)
  if not ok then self:detachSession("Link lost: " .. tostring(err)) return end
  for msg in s:messages() do
    if msg.kind == "snapshot" then self:_call("netApply", msg.peer, msg.data)
    elseif msg.kind == "event" then self:_call("netEvent", msg.peer, msg.data)
    elseif msg.kind == "join" then
      self:_call("netPeerJoined", msg.peer, msg.data)
      self:toast((msg.data and msg.data.name or ("Player " .. tostring(msg.peer))) .. " joined")
    elseif msg.kind == "leave" then
      self:_call("netPeerLeft", msg.peer, msg.data)
      self:toast((msg.data and msg.data.name or ("Player " .. tostring(msg.peer))) .. " left")
    elseif msg.kind == "host" then
      self:_call("netHostChanged", msg.peer)
    elseif msg.kind == "closed" then
      self:detachSession(msg.data and msg.data.reason or "The room closed.")
      return
    end
  end
end

function Host:_tick()
  Input:step()
  -- the system-menu chord: SELECT + START held together, nothing else
  if Input:isDown("select") and Input:isDown("start") and not Input:isDown("a")
     and not Input:isDown("b") then
    self.chordTicks = self.chordTicks + 1
    if self.chordTicks == 30 then self:openMenu() return end
  else
    self.chordTicks = 0
  end
  -- paused (system menu / LINK PLAY): a game that keeps audio buffers fed or
  -- animates its pause screen can have pausedUpdate(dt)
  if (self.link or self.menu) and self.game and self.game.pausedUpdate then
    self:_call("pausedUpdate", R.DT)
  end
  if self.link then
    local ok, err = pcall(self.link.update, self.link, R.DT)
    if not ok then self.link = nil; self:toast("Link menu error: " .. tostring(err)) end
    if self.link and self.link.done then self.link = nil end
    return
  end
  if self.menu then return self:_menuTick() end
  self.ticks = self.ticks + 1
  self:_call("update", R.DT)
  local s = self.sessionObj
  if s and self.game and self.game.netSnapshot and self.ticks % R.SNAPSHOT_EVERY == 0 then
    local snap = self:_call("netSnapshot")
    if snap ~= nil then pcall(s.sendSnapshot, s, snap) end
  end
end

function Host:update(dt)
  if self.quitting then return end
  if self.touch then pcall(self.touch.pollTouches, self.touch) end
  if self.noticeT > 0 then self.noticeT = self.noticeT - dt end
  -- the session runs even while paused, so a room does not time us out
  self:_pumpSession()
  if self.hub and self.hub.poll then
    self.hubPollT = (self.hubPollT or 0) + dt
    if self.hubPollT > 0.5 then self.hubPollT = 0; pcall(self.hub.poll) end
  end
  if self.error then
    Input:step()
    if Input:wasPressed("a") or Input:wasPressed("start") then self:quit() end
    return
  end
  self.acc = self.acc + math.min(dt, 0.25)
  local steps = 0
  while self.acc >= R.DT and steps < 8 do
    self.acc = self.acc - R.DT
    steps = steps + 1
    self:_tick()
    if self.quitting or self.error then return end
  end
end

-- Where the 240x160 picture goes in the window: x, y, scale.
function Host:viewport()
  local w, h = love.graphics.getDimensions()
  local sx, sy, sw, sh = 0, 0, w, h
  local okS, SafeArea = pcall(require, "src.core.SafeArea")
  if okS then sx, sy, sw, sh = SafeArea.rect() end
  local fit = math.min(sw / R.W, sh / R.H)
  local scale = fit
  if self.zopts.scale ~= "fit" then scale = math.max(1, math.floor(fit)) end
  if fit < 1 then scale = fit end
  local dw, dh = R.W * scale, R.H * scale
  local x = sx + math.floor((sw - dw) / 2)
  local y
  if sh > sw * 1.2 then
    -- portrait phone: the picture at the top, the touch pad under it
    y = sy + math.floor(math.min((sh - dh) / 2, sh * 0.06))
  else
    y = sy + math.floor((sh - dh) / 2)
  end
  return x, y, scale
end

-- The touch MENU button, top centre of the window.
function Host:menuButtonRect()
  local w = love.graphics.getDimensions()
  local sx, sy, sw = 0, 0, w
  local okS, SafeArea = pcall(require, "src.core.SafeArea")
  if okS then sx, sy, sw = SafeArea.rect() end
  local size = math.max(36, math.floor(math.min(sw, 900) * 0.07))
  return { x = sx + math.floor(sw / 2 - size / 2), y = sy + 6, w = size, h = math.floor(size * 0.7) }
end

local function touchUI()
  local okT, TC = pcall(require, "src.core.TouchControls")
  return okT and TC.visible and TC:visible()
end

function Host:draw()
  local g = love.graphics
  g.push("all")
  g.setCanvas(self.canvas)
  g.clear(0, 0, 0, 1)
  g.origin()
  g.setColor(1, 1, 1, 1)
  if not self.error then
    local ok, err = xpcall(function() if self.game and self.game.draw then self.game:draw() end end,
      debug.traceback)
    if not ok then self:_fail("draw", err) end
  end
  g.pop()
  g.push("all")
  g.origin()
  g.clear(0, 0, 0, 1)
  local x, y, scale = self:viewport()
  g.setColor(1, 1, 1, 1)
  g.draw(self.canvas, x, y, 0, scale, scale)
  if self.touch and not self.error then pcall(self.touch.draw, self.touch) end
  if touchUI() and not self.menu and not self.link then
    local r = self:menuButtonRect()
    g.setColor(1, 1, 1, 0.22)
    g.rectangle("fill", r.x, r.y, r.w, r.h, 8, 8)
    g.setColor(1, 1, 1, 0.85)
    for i = 0, 2 do
      g.rectangle("fill", r.x + r.w * 0.25, r.y + r.h * (0.28 + i * 0.2), r.w * 0.5, math.max(2, r.h * 0.08))
    end
  end
  if self.link then pcall(self.link.draw, self.link) end
  if self.menu then self:_drawMenu() end
  if self.error then self:_drawError() end
  if self.notice and self.noticeT > 0 then
    local f = fontOf(math.max(12, 9 * scale))
    g.setFont(f)
    local tw = f:getWidth(self.notice) + 24
    local ww = g.getWidth()
    g.setColor(0, 0, 0, 0.7)
    g.rectangle("fill", ww / 2 - tw / 2, y + 8, tw, f:getHeight() + 12, 6, 6)
    g.setColor(1, 1, 1)
    g.print(self.notice, ww / 2 - tw / 2 + 12, y + 14)
  end
  g.pop()
end

function Host:_drawError()
  local g = love.graphics
  local w, h = g.getDimensions()
  g.setColor(0.06, 0.07, 0.10, 0.94)
  g.rectangle("fill", 0, 0, w, h)
  local f = fontOf(math.max(10, math.floor(h / 48)))
  g.setFont(f)
  g.setColor(1, 0.6, 0.4)
  local pad = math.max(12, math.floor(w * 0.03))
  local head = (self.info.displayName or self.version) .. " stopped (" .. tostring(self.error.what) .. ")"
  g.printf(head .. "\n\n" .. self.error.text, pad, pad, w - pad * 2, "left")
  g.setColor(0.6, 0.75, 1)
  g.printf("A / START / Enter / tap: back to the launcher", pad, h - pad - f:getHeight() * 2, w - pad * 2, "left")
end

-- ------------------------------------------------------------ system menu

function Host:_menuRows()
  local rows = {
    { id = "resume", label = "RESUME" },
  }
  if self.game and self.game.save then rows[#rows + 1] = { id = "save", label = "SAVE GAME" } end
  rows[#rows + 1] = { id = "link", label = self.sessionObj and "LINK PLAY (online)" or "LINK PLAY" }
  if self.sessionObj then rows[#rows + 1] = { id = "leave", label = "LEAVE ROOM" } end
  rows[#rows + 1] = { id = "scale", label = "SCALE", value = self.zopts.scale == "fit" and "FIT" or "INTEGER" }
  rows[#rows + 1] = { id = "music", label = "MUSIC VOLUME", value = tostring(math.floor(self:volume("music") * 7 + 0.5)) }
  rows[#rows + 1] = { id = "sfx", label = "SOUND VOLUME", value = tostring(math.floor(self:volume("sfx") * 7 + 0.5)) }
  local okC, Cast = pcall(require, "src.ui.CastDisplay")
  if okC and Cast.supported() then
    rows[#rows + 1] = { id = "cast", label = Cast.ROW_LABEL, value = Cast.label() }
  end
  rows[#rows + 1] = { id = "quit", label = "QUIT TO LAUNCHER" }
  return rows
end

function Host:openMenu()
  if self.error then return end
  self.menu = { index = 1 }
  pcall(function() if self.touch then self.touch:reset() end end)
  self:_call("pause", true)
end

function Host:closeMenu()
  self.menu = nil
  self:_call("pause", false)
end

function Host:_menuStep(row, dir)
  if row.id == "scale" then
    self.zopts.scale = self.zopts.scale == "fit" and "integer" or "fit"
    self.options.zelda = self.zopts
    saveOptions(self.options)
  elseif row.id == "music" or row.id == "sfx" then
    local key = row.id == "music" and "musicVol" or "sfxVol"
    local v = tonumber(self.options[key]) or 7
    v = math.max(0, math.min(7, v + (dir or 1)))
    self.options[key] = v
    saveOptions(self.options)
    self.gameOpts.options.musicVol = self:volume("music")
    self.gameOpts.options.sfxVol = self:volume("sfx")
    self:_call("optionsChanged", self.gameOpts.options)
  elseif row.id == "cast" then
    pcall(function() require("src.ui.CastDisplay").step(dir or 1) end)
  end
end

function Host:_menuActivate(row)
  if row.id == "resume" then self:closeMenu()
  elseif row.id == "save" then self:closeMenu(); self:requestSave()
  elseif row.id == "link" then self:openLink()
  elseif row.id == "leave" then self:detachSession("You left the room."); self:closeMenu()
  elseif row.id == "quit" then self.menu = nil; self:quit()
  else self:_menuStep(row, 1) end
end

function Host:_menuTick()
  local rows = self:_menuRows()
  local m = self.menu
  if Input:wasPressed("up") then m.index = (m.index - 2) % #rows + 1 end
  if Input:wasPressed("down") then m.index = m.index % #rows + 1 end
  m.index = math.max(1, math.min(#rows, m.index))
  local row = rows[m.index]
  if Input:wasPressed("left") then self:_menuStep(row, -1) end
  if Input:wasPressed("right") then self:_menuStep(row, 1) end
  if Input:wasPressed("a") then self:_menuActivate(row)
  elseif Input:wasPressed("b") or Input:wasPressed("start") then self:closeMenu() end
end

function Host:_menuLayout()
  local w, h = love.graphics.getDimensions()
  local rows = self:_menuRows()
  local f = fontOf(math.max(14, math.min(28, h / 26)))
  local rowH = math.floor(f:getHeight() * 1.9)
  local pw = math.min(w - 32, math.max(320, f:getWidth("MUSIC VOLUME   7") * 1.9))
  local ph = rowH * #rows + rowH * 1.6
  return rows, f, rowH, (w - pw) / 2, math.max(16, (h - ph) / 2), pw, ph
end

function Host:_drawMenu()
  local g = love.graphics
  local w, h = g.getDimensions()
  g.setColor(0, 0, 0, 0.6)
  g.rectangle("fill", 0, 0, w, h)
  local rows, f, rowH, px, py, pw, ph = self:_menuLayout()
  g.setColor(0.10, 0.12, 0.18, 0.96)
  g.rectangle("fill", px, py, pw, ph, 12, 12)
  g.setFont(f)
  g.setColor(0.95, 0.8, 0.35)
  g.print(self.info.label or self.version, px + 20, py + rowH * 0.35)
  self._menuRects = {}
  for i, row in ipairs(rows) do
    local ry = py + rowH * (i + 0.4)
    local sel = self.menu and self.menu.index == i
    if sel then
      g.setColor(1, 1, 1, 0.12)
      g.rectangle("fill", px + 10, ry, pw - 20, rowH - 4, 8, 8)
    end
    g.setColor(1, 1, 1, sel and 1 or 0.8)
    g.print(row.label, px + 22, ry + (rowH - f:getHeight()) / 2)
    if row.value then
      local vw = f:getWidth(row.value)
      g.print(row.value, px + pw - 22 - vw, ry + (rowH - f:getHeight()) / 2)
    end
    self._menuRects[i] = { x = px + 10, y = ry, w = pw - 20, h = rowH - 4, row = row }
  end
end

local function inRect(r, x, y)
  return r and x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end

-- --------------------------------------------------------------- callbacks

function Host:keypressed(key)
  if self.error then
    if key == "return" or key == "escape" or key == "space" or key == "z" then self:quit() end
    return
  end
  if self.link and self.link.keypressed and self.link:keypressed(key) then return end
  if key == "escape" then
    if self.link then self.link.done = true; self.link = nil; return end
    if self.menu then self:closeMenu() else self:openMenu() end
    return
  end
  Input:keypressed(key)
end

function Host:keyreleased(key) Input:keyreleased(key) end

function Host:textinput(text)
  if self.link and self.link.textinput then self.link:textinput(text) end
end

local function noteGamepad(self)
  if self.touch then pcall(self.touch.noteGamepad, self.touch) end
end

function Host:gamepadpressed(joystick, button)
  noteGamepad(self)
  if button == "guide" then
    if self.menu then self:closeMenu() else self:openMenu() end
    return
  end
  Input:gamepadpressed(joystick, button)
end
function Host:gamepadreleased(joystick, button) Input:gamepadreleased(joystick, button) end
function Host:gamepadaxis(joystick, axis, value)
  if math.abs(value or 0) > 0.5 then noteGamepad(self) end
  Input:gamepadaxis(joystick, axis, value)
end
function Host:joystickpressed(j, b) Input:joystickpressed(j, b) end
function Host:joystickreleased(j, b) Input:joystickreleased(j, b) end
function Host:joystickaxis(j, a, v) Input:joystickaxis(j, a, v) end
function Host:joystickhat(j, h, d) Input:joystickhat(j, h, d) end
function Host:joystickremoved()
  Input:reset()
  if self.touch then pcall(self.touch.joystickremoved, self.touch) end
end

function Host:focus(f)
  if not f then
    Input:reset()
    if self.touch then pcall(self.touch.reset, self.touch) end
  end
  self:_call("focus", f)
end
function Host:visible(v)
  if not v then
    Input:reset()
    if self.touch then pcall(self.touch.reset, self.touch) end
  end
end

-- TouchControls falls back to require("src.core.Game") for the Gen 4 free
-- camera when a touch misses every control; with the Pokemon engine not
-- loaded that would load it. A stub stands in for the duration of the call.
local function withoutPokemonGame(fn, ...)
  local had = package.loaded["src.core.Game"]
  if had == nil then package.loaded["src.core.Game"] = {} end
  local ok, a = pcall(fn, ...)
  if had == nil then package.loaded["src.core.Game"] = nil end
  return ok and a
end

function Host:touchpressed(id, x, y)
  if self.error then self:quit() return end
  if self.link and self.link.touchpressed then self.link:touchpressed(id, x, y) return end
  if self.menu then
    for _, r in ipairs(self._menuRects or {}) do
      if inRect(r, x, y) then
        local rows = self:_menuRows()
        for i, row in ipairs(rows) do
          if row.id == r.row.id then self.menu.index = i end
        end
        self:_menuActivate(r.row)
        return
      end
    end
    self:closeMenu()
    return
  end
  if touchUI() and inRect(self:menuButtonRect(), x, y) then self:openMenu() return end
  if self.touch then
    if withoutPokemonGame(self.touch.touchpressed, self.touch, id, x, y) then return end
  end
  self:_call("touchpressed", id, x, y)
end

function Host:touchmoved(id, x, y)
  if self.touch then withoutPokemonGame(self.touch.touchmoved, self.touch, id, x, y) end
  self:_call("touchmoved", id, x, y)
end

function Host:touchreleased(id, x, y)
  if self.link and self.link.touchreleased then self.link:touchreleased(id, x, y) end
  if self.touch then withoutPokemonGame(self.touch.touchreleased, self.touch, id, x, y) end
  self:_call("touchreleased", id, x, y)
end

function Host:wheelmoved() end
function Host:hasPointerScreen() return self.menu ~= nil or self.link ~= nil or self.error ~= nil end
function Host:mousereleased() end
function Host:restartWithMods() end

-- The 240x160 canvas, for harnesses (screenshot of the native picture).
function Host:nativeCanvas() return self.canvas end

R.Host = Host
return R
