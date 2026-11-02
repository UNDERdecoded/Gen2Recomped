-- HEARTGOLD / SOULSILVER'S POKeGEAR (overlay 100's shell, overlay 101's
-- apps), over the art src/import/Gen4HgssPokegearArt.lua (+ ...Extra.lua)
-- writes as `gen4_hgss_pokegear_art`.
--
-- THE SHELL (pokeheartgold src/application/pokegear/main):
--   * the apps, GEAR_APP_*: 0 CONFIGURE (the card / skins), 1 RADIO, 2 MAP,
--     3 PHONE, 4 CANCEL; the bar on the touch screen's BG MAIN_0 at row 20,
--     one 6-tile button per app at x = 6 app + 1 (CANCEL at 26), its pressed
--     state from atlas row 4, a missing card's button masked by the blank at
--     atlas (0, 8) (PokegearApp_DrawAppButtons / _UpdateAppSwitchButtonBGState);
--     the open app's button stays pressed
--   * touch: the five rects y 160-192, x 8-56 / 56-104 / 104-152 / 152-200 /
--     206-254 (sTouchscreenButtonHitboxes); a blank button, the open app or a
--     missing card answers nothing; SEQ_SE_GS_GEARAPPLICHANGE (CANCEL
--     SEQ_SE_GS_GEARCANCEL) (PokegearApp_HandleTouchInput_SwitchApps)
--   * keys: the cursor starts IN THE BAR (cursorInAppSwitchZone = 1 at
--     Pokegear_Init) on the open app's button; LEFT / RIGHT walk the buttons
--     the cards allow (sAppButtonSpec_*: x 32 / 80 / 128 / 176 / 230, y 176,
--     corners at -16 / +16, -10 / +10), A opens that app (the open one:
--     back into it), B closes the Pokegear (PokegearApp_HandleKeyInput_SwitchApps);
--     inside an app B puts the cursor back in the bar
--   * opening: the last used app (SavePokegear lastUsedApp, 3 PHONE on a new
--     save), CONFIGURE when that app's card is missing; a scripted call opens
--     the PHONE with the cursor in the list
--   * the top screen: SUB_0 (pgear_gra NSCR 42 + skin), the clock -- hour and
--     minute digits at (70 / 86 / 110 / 126, 46), the colon at (98, 46), the
--     weekday at (173, 48), the signal at (197, 48), frame 1 where the map
--     cannot place calls (PokegearApp_LoadGraphics / _UpdateClockSprites)
--   * switching apps fades layers 1-3 to black and back two steps a frame
--     (Pokegear_RunFadeLayers123); leaving fades both screens over 6 frames
--
-- THE SCREENS. The touch screen (the DS's MAIN engine) is drawn through
-- src/ui/SecondScreen.lua when a second surface shows (display, inset,
-- vertical, horizontal) and the top screen is the window; on one screen the
-- touch screen is the window and L / SELECT shows the top screen instead.
--
-- THE APPS are their own modules: HgssGearPhone, HgssGearMap, HgssGearRadio,
-- HgssGearConfig. Each has new(gear), keys(input) (inside the app), touch(x, y)
-- (a tap off the bar), update(), drawTouch(), drawTop(), and may set
-- gear.busy while it owns every input (a menu, a call, a drag).
--
-- `panel(sub)` is kept for src/ui/HgssPhoneCall.lua: panel(false) the touch
-- screen, panel(true) the top screen.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local SecondScreen = require("src.ui.SecondScreen")

local Gear = {}
Gear.__index = Gear
Gear.isOpaque = true

local W, H = 256, 192
local floor = math.floor
Gear.APP = { config = 0, radio = 1, map = 2, phone = 3, cancel = 4 }
local APP_NAME = { [0] = "config", "radio", "map", "phone" }
local APP_MODULE = { [0] = "src.ui.HgssGearConfig", "src.ui.HgssGearRadio", "src.ui.HgssGearMap", "src.ui.HgssGearPhone" }
local CANCEL = 4
-- sTouchscreenButtonHitboxes (top, bottom, left, right), by app id
local BUTTON_RECT = { [0] = { 160, 192, 8, 56 }, { 160, 192, 56, 104 }, { 160, 192, 104, 152 },
  { 160, 192, 152, 200 }, { 160, 192, 206, 254 } }
-- sAppButtonSpec_* by registered cards (bit 0 map, bit 1 radio): app, x
local BAR = {
  [0] = { { 0, 32 }, { 3, 176 }, { 4, 230 } },
  [1] = { { 0, 32 }, { 2, 128 }, { 3, 176 }, { 4, 230 } },
  [2] = { { 0, 32 }, { 1, 80 }, { 3, 176 }, { 4, 230 } },
  [3] = { { 0, 32 }, { 1, 80 }, { 2, 128 }, { 3, 176 }, { 4, 230 } },
}
local FADE_STEPS = 9   -- fadeCounter 0, 2, ... 16
local CLOSE_FRAMES = 6

function Gear:uiSize() return W, H end
function Gear:wantsFillScale() return true end
function Gear:wantsEdgeBleed() return false end

local function appId(v)
  if type(v) == "number" then return v end
  return Gear.APP[tostring(v or "")]
end

function Gear.new(game, opts)
  opts = opts or {}
  local self = setmetatable({ game = game, onCancel = opts.onCancel, cache = {}, t = 0,
    showTop = false, apps = {} }, Gear)
  local pg = self:save()
  self.skin = (tonumber(pg.skin) or 0) % 6
  local app = appId(opts.app)
  if app == nil then
    app = tonumber(pg.lastApp) or 3
    if app == 2 and not self:hasCard(1) then app = 0 end
    if app == 1 and not self:hasCard(2) then app = 0 end
    if app < 0 or app > 3 then app = 3 end
  end
  self.app = app
  -- Pokegear_Init: cursorInAppSwitchZone = 1; a scripted call's phone opens
  -- with it in the list (PokegearPhone_LoadContactsAndInitFromArgs)
  self.zone = opts.zone ~= false and not opts.call
  self.zoneIndex = self:buttonIndex(app)
  -- Pokegear_Init plays no sound effect of its own (the menu's press did)
  self.fade = { kind = "open", n = 0 }
  -- FieldSystem_InitPokegearArgs: opened from the field menu while the phone
  -- rings (src/world/HgssPhoneRing.lua), the Pokegear launches on the call
  if opts.app == nil and not opts.silent and not opts.call then
    local okR, Ring = pcall(require, "src.world.HgssPhoneRing")
    if okR then self.ringCall = Ring.answer(game) end
  end
  return self
end

-- --------------------------------------------------------------- save / art

function Gear:save()
  local save = self.game.save or {}
  save.hgssPokegear = save.hgssPokegear or { cards = {}, numbers = {}, mapLevel = 0 }
  local pg = save.hgssPokegear
  pg.cards, pg.numbers = pg.cards or {}, pg.numbers or {}
  return pg
end

function Gear:hasCard(card) return self:save().cards[card] == true end

function Gear:registered()
  return (self:hasCard(1) and 1 or 0) + (self:hasCard(2) and 2 or 0)
end

function Gear:art() return (self.game.data or {}).gen4_hgss_pokegear_art or {} end

function Gear:image(rec)
  local path = type(rec) == "table" and rec.path or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(Assets.image, path)
    self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- a skinned picture (`key_<skin>`), or a plain one
function Gear:img(key, plain)
  local art = self:art()
  local rec = (not plain) and art[key .. "_" .. self.skin] or art[key]
  return self:image(rec), rec
end

function Gear:picture(key, x, y, plain)
  local img = self:img(key, plain)
  if img then love.graphics.setColor(1, 1, 1, 1); love.graphics.draw(img, x or 0, y or 0) end
  return img
end

-- a tile rectangle of a picture (CopyToBgTilemapRect): src tile (sx, sy),
-- w x h tiles, to tile (dx, dy)
function Gear:tiles(img, sx, sy, w, h, dx, dy)
  if not img then return end
  local iw, ih = img:getDimensions()
  self.quads = self.quads or {}
  local k = table.concat({ tostring(img), sx, sy, w, h }, ":")
  local q = self.quads[k]
  if not q then q = love.graphics.newQuad(sx * 8, sy * 8, w * 8, h * 8, iw, ih); self.quads[k] = q end
  love.graphics.draw(img, q, dx * 8, dy * 8)
end

-- an OBJ frame at its sprite position: obj_<set>_<seq>_<frame>[_<skin>]
function Gear:obj(set, seq, frame, x, y, skinned)
  local key = ("obj_%s_%d_%d"):format(set, seq, frame or 0)
  local img, rec = self:img(key, not skinned)
  if not img then return false end
  love.graphics.draw(img, floor(x + (tonumber(rec.originX) or 0)), floor(y + (tonumber(rec.originY) or 0)))
  return true
end

function Gear:text(bank, index)
  local ok, T = pcall(require, "src.import.Gen4Text")
  if not ok then return nil end
  local s = T.resolve(self.game.data, bank, index, self.game)
  if type(s) ~= "string" then return nil end
  return s
end

function Gear:se(name)
  local data = self.game and self.game.data
  local ok, Sound = pcall(require, "src.core.Sound")
  if ok and type(Sound) == "table" and Sound.playSe and data then pcall(Sound.playSe, data, name) end
end

-- the ink an app prints in: a palette row (0-15) picked by index
function Gear:ink(which, index, fallback)
  local row = ((self:art().ink or {})[self.skin] or {})[which]
  local c = row and row[index]
  if type(c) ~= "table" then return fallback or { 1, 1, 1 } end
  return { (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255 }
end

-- ------------------------------------------------------------- the player

-- the overworld under the Pokegear (the field the player opened it from)
function Gear:overworld()
  for i = #self.game.stack.states, 1, -1 do
    local st = self.game.stack.states[i]
    if type(st) == "table" and st.player and st.map then return st end
  end
  return nil
end

-- THE MAP HEADERS (gen4_map_headers: outgoingCalls, radioSignal, region,
-- worldMapX / Y, momCallIntro, matrix, label). Not one of the modules the
-- loader puts on `game.data` -- it is the cache's Gen 4 marker -- so it is
-- read the way the loader read it: from package.loaded, through require, or
-- from POKEPORT_DATA_DIR. Kept per data table.
local headerCache = setmetatable({}, { __mode = "k" })
function Gear.headers(data)
  data = data or {}
  if data.gen4_map_headers then return data.gen4_map_headers end
  local got = headerCache[data]
  if got ~= nil then return got or nil end
  local t = package.loaded["data.generated.gen4_map_headers"]
  if type(t) ~= "table" then
    local ok, m = pcall(require, "data.generated.gen4_map_headers")
    t = ok and type(m) == "table" and m or nil
  end
  if not t then
    local dir = os.getenv("POKEPORT_DATA_DIR")
    local chunk = dir and loadfile(dir .. "/gen4_map_headers.lua")
    local ok, m = false, nil
    if chunk then ok, m = pcall(chunk) end
    t = ok and type(m) == "table" and m or nil
  end
  if t and t.headers and not t[0] then t = t.headers end
  headerCache[data] = t or false
  return t
end

-- the map header the player is on, and its id
function Gear:header()
  local data = self.game.data or {}
  local ow = self:overworld()
  local mapId = (ow and ow.map and ow.map.id) or ((self.game.save or {}).player or {}).map
  local def = mapId and (data.maps or {})[mapId]
  local id = def and tonumber(def.header)
  local headers = Gear.headers(data) or {}
  return id and headers[id], id, def
end

-- FieldSystem_InitPokegearArgs: the player's world-map cell -- on the main
-- matrix their position / 32, else the header's world-map coordinates
function Gear:matrixCell()
  local header, _, def = self:header()
  local ow = self:overworld()
  if header and header.matrix == 0 and ow and ow.player and def then
    local x = (tonumber(def.originX) or 0) + (ow.player.cellX or 0)
    local y = (tonumber(def.originY) or 0) + (ow.player.cellY or 0)
    return floor(x / 32), floor(y / 32)
  end
  if header and ((header.worldMapX or 0) ~= 0 or (header.worldMapY or 0) ~= 0) then
    return header.worldMapX, header.worldMapY
  end
  return 21, 12 -- New Bark Town (MAP_NEW_BARK's flypoint) when nothing is known
end

-- --------------------------------------------------------------- the bar

function Gear:buttonIndex(app)
  for i, b in ipairs(BAR[self:registered()]) do if b[1] == app then return i end end
  return 1
end

function Gear:app_(id)
  id = id or self.app
  if id == CANCEL then return nil end
  local a = self.apps[id]
  if not a then
    local ok, M = pcall(require, APP_MODULE[id])
    if ok and M and M.new then
      local okN, inst = pcall(M.new, self)
      if okN then a = inst else print("[pokegear] " .. tostring(inst)) end
    else
      print("[pokegear] " .. tostring(M))
    end
    a = a or {}
    self.apps[id] = a
  end
  return a
end

function Gear:current() return self:app_(self.app) end

-- PokegearApp_HandleTouchInput_SwitchApps's checks, then the switch
function Gear:tapBar(x, y)
  for app = 0, 4 do
    local r = BUTTON_RECT[app]
    if y >= r[1] and y < r[2] and x >= r[3] and x < r[4] then
      if app == self.app then return true end
      if (app == 1 and not self:hasCard(2)) or (app == 2 and not self:hasCard(1)) then return true end
      self.zone = false
      self:switchTo(app)
      return true
    end
  end
  return y >= 160
end

function Gear:switchTo(app)
  if app == CANCEL then
    self:se("SEQ_SE_GS_GEARCANCEL")
    self.leaving = true
    self.fade = { kind = "close", n = 0 }
    return
  end
  self:se("SEQ_SE_GS_GEARAPPLICHANGE")
  local a = self:current()
  if a and a.leave then a:leave() end
  self.fade = { kind = "out", n = 0, to = app }
end

function Gear:keysBar(input)
  local bar = BAR[self:registered()]
  if input:wasPressed("b") then
    self:se("SEQ_SE_GS_GEARCANCEL")
    self.leaving = true
    self.fade = { kind = "close", n = 0 }
    return
  end
  if input:wasPressed("a") then
    local app = (bar[self.zoneIndex] or bar[1])[1]
    if app == self.app then
      -- the reselect callback: back into the open app
      self:se("SEQ_SE_GS_GEARAPPLICHANGE")
      self.zone = false
      local a = self:current()
      if a and a.reselect then a:reselect() end
      return
    end
    self.zone = false
    return self:switchTo(app)
  end
  if input:wasPressed("left") then
    self:se("SEQ_SE_GS_GEARCURSOR")
    self.zoneIndex = (self.zoneIndex - 2) % #bar + 1
  elseif input:wasPressed("right") then
    self:se("SEQ_SE_GS_GEARCURSOR")
    self.zoneIndex = self.zoneIndex % #bar + 1
  end
end

-- an app's "B": the cursor goes back to the bar, on the open app's button
function Gear:toBar()
  self:se("SEQ_SE_GS_GEARCANCEL")
  self.zone = true
  self.zoneIndex = self:buttonIndex(self.app)
end

function Gear:close()
  local pg = self:save()
  pg.lastApp = self.app
  local a = self:current()
  if a and a.leave then a:leave() end
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- ----------------------------------------------------------------- update

function Gear:update(dt)
  if self.ringCall then
    local call = self.ringCall
    self.ringCall = nil
    local okC, Call = pcall(require, "src.ui.HgssPhoneCall")
    if okC and Call.available(self.game) then
      self.game.stack:pop()
      self.game.stack:push(Call.new(self.game, call, self.onCancel))
      return
    end
  end
  self.t = self.t + 1
  local fade = self.fade
  if fade then
    fade.n = fade.n + 1
    if fade.kind == "open" then
      if fade.n >= CLOSE_FRAMES then self.fade = nil end
    elseif fade.kind == "close" then
      if fade.n >= CLOSE_FRAMES then return self:close() end
    elseif fade.kind == "out" then
      if fade.n >= FADE_STEPS then
        self.app = fade.to
        self.zoneIndex = self:buttonIndex(self.app)
        local a = self:current()
        if a and a.enter then a:enter() end
        self.fade = { kind = "in", n = 0 }
      end
    elseif fade.kind == "in" then
      if fade.n >= FADE_STEPS then self.fade = nil end
    end
    self.tapAt = nil
    return
  end
  local a = self:current()
  if a and a.update then a:update() end
  local input = self.game.input
  local tap = self.tapAt
  self.tapAt = nil
  if a and a.busy then
    -- the app owns every input (a context menu, a call, a drag)
    if a.busyUpdate then a:busyUpdate(input, tap) end
    return
  end
  if input and (input:wasPressed("l") or input:wasPressed("select")) then
    self.showTop = not self.showTop
    return
  end
  if tap then
    if tap.y >= 160 then
      self:tapBar(tap.x, tap.y)
    elseif a and a.touch then
      if a:touch(tap.x, tap.y) and self.zone then self.zone = false end
    end
    return
  end
  if not input then return end
  if self.zone then return self:keysBar(input) end
  if a and a.keys then a:keys(input) end
end

-- ------------------------------------------------------------------- touch

function Gear:touchpressed(id, x, y)
  local px, py = SecondScreen.toLocal(self.game, x, y)
  if not px then
    if SecondScreen.separate(self.game) then return false end
    local rect = require("src.render.Renderer").uiPresentation
    if rect then px, py = (x - rect.x) / rect.scaleX, (y - rect.y) / rect.scaleY else px, py = x, y end
  end
  if px < 0 or py < 0 or px >= W or py >= H then return false end
  if not SecondScreen.separate(self.game) and self.showTop then return true end
  self.tapAt = { x = floor(px), y = floor(py) }
  self.touchHeld = true
  local a = self:current()
  if a and a.touchDown then a:touchDown(self.tapAt.x, self.tapAt.y) end
  return true
end

function Gear:touchmoved(id, x, y)
  if not self.touchHeld then return false end
  local px, py = SecondScreen.toLocal(self.game, x, y)
  if not px then
    local rect = require("src.render.Renderer").uiPresentation
    if rect then px, py = (x - rect.x) / rect.scaleX, (y - rect.y) / rect.scaleY else px, py = x, y end
  end
  local a = self:current()
  if a and a.touchMove and px then a:touchMove(floor(px), floor(py)) end
  return true
end

function Gear:touchreleased(id)
  if not self.touchHeld then return false end
  self.touchHeld = false
  local a = self:current()
  if a and a.touchUp then a:touchUp() end
  return true
end

-- ------------------------------------------------------------------- draw

function Gear:drawBar()
  local g = love.graphics
  local atlas = self:img("buttons")
  local reg = self:registered()
  if atlas then
    self:tiles(atlas, 0, 0, 32, 4, 0, 20)
    if not self:hasCard(1) then self:tiles(atlas, 0, 8, 6, 4, 13, 20) end
    if not self:hasCard(2) then self:tiles(atlas, 0, 8, 6, 4, 7, 20) end
    local shown = (self.fade and self.fade.kind == "close") and CANCEL or self.app
    local x = shown == CANCEL and 26 or shown * 6 + 1
    self:tiles(atlas, x, 4, 6, 4, x, 20)
  else
    -- a cache from before the button states were imported: the bar alone,
    -- missing cards dimmed and the open app outlined
    local frame = self:img("frame_top")
    if frame then g.setColor(1, 1, 1, 1); g.draw(frame, 0, 0) end
    g.setColor(0, 0, 0, 0.6)
    if not self:hasCard(1) then g.rectangle("fill", 104, 160, 48, 32) end
    if not self:hasCard(2) then g.rectangle("fill", 56, 160, 48, 32) end
    local r = BUTTON_RECT[self.app]
    g.setColor(1, 0.85, 0.2, 1)
    g.rectangle("line", r[3] + 1.5, r[1] + 1.5, r[4] - r[3] - 3, r[2] - r[1] - 3)
    g.setColor(1, 1, 1, 1)
  end
  if self.zone and not self.fade then
    local b = BAR[reg][self.zoneIndex]
    if b then self:corners(b[2], 176, -16, 16, -10, 10) end
  end
end

-- the four cursor corners (the shell's OBJ seqs 4-7: top-left, bottom-left,
-- top-right, bottom-right)
function Gear:corners(x, y, l, r, t, b, set, first)
  set, first = set or "gear", first or 4
  local skinned = set == "gear"
  local ok = self:obj(set, first, 0, x + l, y + t, skinned)
  if ok then
    self:obj(set, first + 1, 0, x + l, y + b, skinned)
    self:obj(set, first + 2, 0, x + r, y + t, skinned)
    self:obj(set, first + 3, 0, x + r, y + b, skinned)
  else
    local g = love.graphics
    g.setColor(0.9, 0.1, 0.1, 1)
    g.rectangle("line", x + l - 3.5, y + t - 3.5, r - l + 7, b - t + 7)
    g.setColor(1, 1, 1, 1)
  end
end

function Gear:drawClock()
  local now = os.date("*t")
  local digits = { floor(now.hour / 10), now.hour % 10, floor(now.min / 10), now.min % 10 }
  local xs = { 70, 86, 110, 126 }
  local drawn = true
  for i = 1, 4 do drawn = self:obj("gear", 0, digits[i], xs[i], 46, true) and drawn end
  if not drawn then
    Font.pushStyle({ text = { 1, 0.75, 0.1 }, shadow = { 0.4, 0.25, 0 } })
    Font.draw(("%02d:%02d"):format(now.hour, now.min), 72, 40)
    Font.popStyle()
    return
  end
  self:obj("gear", 1, 0, 98, 46, true)
  self:obj("gear", 2, (now.wday or 1) - 1, 173, 48, true)
  local header = self:header()
  local canCall = not header or header.outgoingCalls ~= false
  self:obj("gear", 3, canCall and 0 or 1, 197, 48, true)
end

-- the touch screen (MAIN): the app, then the bar over it
function Gear:drawTouch()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  g.setColor(1, 1, 1, 1)
  local a = self:current()
  local fade = self.fade
  if a and a.drawTouch then a:drawTouch() end
  local k = 0
  if fade and fade.kind == "out" then k = math.min(1, fade.n / (FADE_STEPS - 1))
  elseif fade and fade.kind == "in" then k = 1 - math.min(1, fade.n / (FADE_STEPS - 1)) end
  if k > 0 then g.setColor(0, 0, 0, k); g.rectangle("fill", 0, 0, W, 160); g.setColor(1, 1, 1, 1) end
  self:drawBar()
  if a and a.drawTouchOver then a:drawTouchOver() end
end

-- the top screen (SUB): the shell's face, the app's layers, the clock
function Gear:drawTop()
  local g = love.graphics
  g.setColor(0, 0, 0, 1)
  g.rectangle("fill", 0, 0, W, H)
  self:picture("frame_bottom")
  local a = self:current()
  if a and a.drawTop then a:drawTop() end
  self:drawClock()
end

function Gear:panel(sub)
  if sub then return self:drawTop() end
  return self:drawTouch()
end

function Gear:draw()
  local g = love.graphics
  local dual = SecondScreen.separate(self.game)
  local fade = self.fade
  local k = 0
  if fade and fade.kind == "open" then k = 1 - math.min(1, fade.n / CLOSE_FRAMES)
  elseif fade and fade.kind == "close" then k = math.min(1, fade.n / CLOSE_FRAMES) end
  local function dim()
    if k > 0 then g.setColor(0, 0, 0, k); g.rectangle("fill", 0, 0, W, H); g.setColor(1, 1, 1, 1) end
  end
  if dual then
    self:drawTop()
    dim()
    SecondScreen.draw(self.game, function() self:drawTouch(); dim() end)
  elseif self.showTop then
    self:drawTop()
    dim()
  else
    self:drawTouch()
    dim()
  end
end

return Gear
