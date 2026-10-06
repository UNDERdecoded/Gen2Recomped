-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The POKETCH, which is the thing the bottom screen mostly shows -- and the
-- first line of the original brief: "Instead of having two screens for the
-- poketch and bottom screen allow users to switch between the two with a
-- button".  `SecondScreen` answers where it goes; this is what goes there.
--
-- Apps use the ROM's backgrounds and cell sprites. Touch is routed through
-- SecondScreen, including the bezel buttons and dragging on drawing apps;
-- keyboard/controller actions remain available as alternatives.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local SecondScreen = require("src.ui.SecondScreen")
local Strings = require("src.core.Strings")

local Gen4Poketch = {}
Gen4Poketch.__index = Gen4Poketch

local W, H = 256, 192

-- The watch face inside the bottom screen.  The cartridge's own `poketch_border`
-- is a full-screen picture with the face cut out of it, so the apps draw into
-- the hole rather than being placed against nothing.
local FACE = { x = 16, y = 16, w = 192, h = 160 }
local TYPES = {'NORMAL','FIRE','WATER','ELECTRIC','GRASS','ICE','FIGHTING','POISON',
  'GROUND','FLYING','PSYCHIC','BUG','ROCK','GHOST','DRAGON','DARK','STEEL'}
local function centered(text,cx,y,width)
  text=tostring(text)
  if width and Font.fit then text=Font.fit(text,width) end
  Font.draw(text,cx-math.floor(Font.width(text)/2),y)
end

-- Where the digital watch's four digits sit, and the colon between them.
local DIGIT = { x = 66, y = 74, w = 24, h = 32, gap = 4, colon = 12 }

-- NOT OPAQUE.  The Poketch is a second screen, not a screen that replaces the
-- first: on the corner mode the world is still there behind it, and on swap the
-- world is what the main screen is still showing.
Gen4Poketch.isOpaque = false

function Gen4Poketch:uiSize() return W, H end
function Gen4Poketch:wantsFillScale() return true end
function Gen4Poketch:wantsEdgeBleed() return false end

function Gen4Poketch.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4Poketch)
  self.game = game
  self.onCancel = opts.onCancel
  self.cache = {}
  self.art = ((game.data or {}).gen4_graphics or {}).screens or {}

  local record = ((game.data or {}).gen4_menus or {}).poketch
  self.apps = (record and record.apps) or nil
  if not self.apps then
    Logger.warn("gen4 poketch: this cache carries no poketch record -- "
                .. "re-import to get the app list")
    self.apps = {}
  end
  self.border = record and record.border or "poketch/poketch_border"
  self.unavailable = record and record.unavailable or "poketch/unavailable"

  -- WHERE IT WAS LAST TIME.  Which app you had up is a thing to keep, and it
  -- is kept on the save rather than on the session for the same reason the
  -- counter is: closing the watch is not meant to reset it.
  local store = self:store()
  self.index = math.max(1, math.min(#self.apps, tonumber(store.app) or 1))
  if not self:isRegistered(self.index) then self:cycle(1) end
  self.flash = 0
  return self
end

-- The Poketch's own corner of the save.  Created on demand so a save from
-- before this screen existed grows it the first time the watch is opened.
function Gen4Poketch:store()
  local save = self.game.save
  if not save then return {} end
  save.poketch = save.poketch or {}
  return save.poketch
end

-- ---------------------------------------------------------------- pictures --

function Gen4Poketch:img(key)
  local rec = self.art[key]
  local path = (type(rec) == "table" and rec.path) or rec
  if type(path) ~= "string" then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil
end

-- ------------------------------------------------------ the apps' own art --
--
-- `gen4_poketch_art` (src/import/Gen4PoketchArt.lua): every app's cells
-- assembled against the OBJ VRAM that app builds, each with its origin, and
-- the apps' BG tile sheets; `gen4_poketch_ink`: the NANR sequences and the
-- tilemaps apps copy rectangles out of. Everything is in LCD theme 0 -- the
-- colour changer's shader (applyLCDPalette) recolours the finished LCD.

-- Theme 0's four LCD shades by palette index (generic_bg_tiles.NCLR row 0):
-- 1 darkest, 8 dark, 15 light, 4 lightest (the backdrop).
local LCD = { [1] = { 16, 41, 25 }, [8] = { 58, 82, 49 }, [15] = { 82, 132, 82 }, [4] = { 115, 181, 115 } }
Gen4Poketch.LCD = LCD
local function lcd(index, a)
  local c = LCD[index] or LCD[1]
  love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
end

function Gen4Poketch:artImage(key)
  local rec = ((self.game.data or {}).gen4_poketch_art or {})[key]
  local path = type(rec) == "table" and rec.path or nil
  if not path then return nil end
  if self.cache[path] == nil then
    local ok, image = pcall(Assets.image, path)
    self.cache[path] = ok and image or false
    if self.cache[path] then self.cache[path]:setFilter("nearest", "nearest") end
  end
  return self.cache[path] or nil, rec
end

function Gen4Poketch:ink()
  return (self.game.data or {}).gen4_poketch_ink or {}
end

-- One cell of a set, placed by its translation point the way
-- NNS_G2dMakeCellToOams places it: OAM offsets relative to (x, y); a flip
-- mirrors the whole cell about that point (PoketchAnimation flipH/flipV), a
-- rotation (the analog watch's affine hands) turns it about it.
function Gen4Poketch:drawCell(set, cell, x, y, opts)
  local image, rec = self:artImage(("%s_%02d"):format(set, cell or 0))
  if not image then return false end
  local ox, oy = rec.originX or 0, rec.originY or 0
  local g = love.graphics
  if not (opts and opts.keepColour) then g.setColor(1, 1, 1, 1) end
  if opts and opts.rot then
    g.draw(image, x, y, opts.rot, 1, 1, -ox, -oy)
  elseif opts and (opts.flipH or opts.flipV) then
    local sx, sy = opts.flipH and -1 or 1, opts.flipV and -1 or 1
    g.draw(image, x + (opts.flipH and -ox or ox), y + (opts.flipV and -oy or oy), 0, sx, sy)
  else
    g.draw(image, x + ox, y + oy)
  end
  return true
end

-- The frame of NANR sequence `seq` showing `ticks` frames after it started:
-- a one-shot (mode 1, 3) holds its last frame, a loop (2, 4) wraps.
function Gen4Poketch:animFrame(set, seq, ticks)
  local anims = (self:ink().anims or {})[set]
  local s = anims and anims[(seq or 0) + 1]
  if not (s and s.frames and #s.frames > 0) then return { cell = seq or 0 } end
  local total = 0
  for _, f in ipairs(s.frames) do total = total + math.max(1, f.duration or 1) end
  local t = math.max(0, math.floor(ticks or 0))
  if s.mode == 2 or s.mode == 4 then t = t % total end
  for _, f in ipairs(s.frames) do
    local d = math.max(1, f.duration or 1)
    if t < d then return f end
    t = t - d
  end
  return s.frames[#s.frames]
end

-- A PoketchAnimation sprite: `id` keeps when its sequence (re)started --
-- PoketchAnimation_UpdateAnimationIdx restarts it from frame 0.
function Gen4Poketch:sprite(id, set, seq, x, y, opts)
  self.spriteClock = self.spriteClock or {}
  local clock = self.spriteClock[id]
  if not clock or clock.set ~= set or clock.seq ~= seq then
    clock = { set = set, seq = seq, start = self.ticks or 0 }
    self.spriteClock[id] = clock
  end
  local f = self:animFrame(set, seq, (self.ticks or 0) - clock.start)
  local o = opts or {}
  if f.rot then
    o = { rot = -f.rot * 2 * math.pi / 65536, keepColour = o.keepColour }
  end
  return self:drawCell(set, f.cell, x + (f.x or 0), y + (f.y or 0), o)
end

-- Tiles of an app's BG sheet (`<sheet>_bgtiles`, 32 to a row) at tile
-- (tx, ty): `words` are tilemap entries (tile | hflip 0x400 | vflip 0x800).
function Gen4Poketch:drawTiles(sheet, words, w, tx, ty)
  local image = self:artImage(sheet .. "_bgtiles")
  if not image then return false end
  self.tileQuads = self.tileQuads or {}
  local iw, ih = image:getDimensions()
  local g = love.graphics
  g.setColor(1, 1, 1, 1)
  for i, word in ipairs(words) do
    local tile = word % 1024
    local key = sheet .. ":" .. tile
    local q = self.tileQuads[key]
    if not q then
      q = g.newQuad((tile % 32) * 8, math.floor(tile / 32) * 8, 8, 8, iw, ih)
      self.tileQuads[key] = q
    end
    local fx, fy = math.floor(word / 1024) % 2 == 1, math.floor(word / 2048) % 2 == 1
    local px, py = (tx + (i - 1) % w) * 8, (ty + math.floor((i - 1) / w)) * 8
    g.draw(image, q, px + (fx and 8 or 0), py + (fy and 8 or 0), 0, fx and -1 or 1, fy and -1 or 1)
  end
  return true
end

-- A rectangle of one of the cartridge's own tilemaps (Bg_CopyToTilemapRect's
-- source side): `name`'s cells (sx..sx+w, sy..sy+h) drawn at tile (tx, ty).
function Gen4Poketch:copyRect(sheet, name, sx, sy, w, h, tx, ty)
  local map = (self:ink().tilemaps or {})[name]
  if not map then return false end
  local words = {}
  for row = 0, h - 1 do
    for col = 0, w - 1 do
      words[#words + 1] = map.cells[(sy + row) * map.width + sx + col + 1] or 0
    end
  end
  return self:drawTiles(sheet, words, w, tx, ty)
end

function Gen4Poketch:app()
  return self:isRegistered(self.index) and self.apps[self.index] or nil
end

function Gen4Poketch:isRegistered(index)
  local app=self.apps[index]
  if not app then return false end
  local store=self:store()
  local registry=store.registered or store.apps
  -- Older runtime saves didn't retain the registry. Keep their app access
  -- until story scripts supply one, without inventing acquisition flags.
  if type(registry)~='table' then return true end
  local id=tonumber(app.id) or index-1
  return registry[id]==true or registry[id]==1
end

-- ------------------------------------------------------------------ input --

local function clockNow()
  local ok, t = pcall(os.date, "*t")
  if ok and type(t) == "table" then return t end
  return { hour = 0, min = 0, day = 1, month = 1, year = 2000, wday = 1 }
end
Gen4Poketch.clockNow = clockNow

-- party_status sMonPosition: the six icons' points (also the touch targets).
local PARTY_AT = { { 64, 36 }, { 160, 36 }, { 64, 84 }, { 160, 84 }, { 64, 132 }, { 160, 132 } }

function Gen4Poketch:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

-- THE APP CHANGE (poketch_system.c PoketchEvent_UpdateApp): the shutter
-- closes over the old app (TASK_CONCEAL_SCREEN, five 30 Hz ticks), the app
-- changes, and it opens again over the new one (TASK_REVEAL_SCREEN_2, four).
-- The index changes at once -- the watch's state is the new app's -- and the
-- picture catches up through `self.shutter`.
function Gen4Poketch:cycle(delta)
  self.activeMapMarker=nil
  local count = #self.apps
  if count == 0 then return end
  local index=self.index
  for _=1,count do
    index=(index-1+delta)%count+1
    if self:isRegistered(index) then
      if index ~= self.index then
        local sh = self.shutter
        if sh then
          -- pressed again while the shutter is down: the app number shows
          -- and the shutter stays shut thirty ticks from now
          sh.skip = true
          sh.t = math.min(sh.t, 10)
        else
          self.shutter = { from = self.index, t = 0 }
        end
      end
      self.index=index
      self:store().app=index
      self.appState = nil
      self.spriteClock = nil
      return
    end
  end
end

function Gen4Poketch:updatePresentation(dt)
  self:updateCoin(dt or 1/60)
  if self.friendshipTouch then
    self.friendshipTouch.frames=self.friendshipTouch.frames-1
    if self.friendshipTouch.frames<=0 then self.friendshipTouch=nil end
  end
  self.flash = (self.flash + 1) % 60
  -- the frame clock every cartridge animation here is timed against (NANR
  -- durations are 60 Hz frames; the apps' own task counters run at 30 Hz)
  self.ticks = (self.ticks or 0) + 1
  if self.shutter then
    self.shutter.t = self.shutter.t + 1
    if self.shutter.t >= 2 * (5 + (self.shutter.skip and 30 or 3) + 4) then self.shutter = nil end
  end
  self:updateApp()
  self.elapsed = (self.elapsed or 0) + (dt or 1 / 60)
end

function Gen4Poketch:update(dt)
  self:updatePresentation(dt)
  local input = self.game.input
  if not input then return end

  if input:wasPressed("r") or input:wasPressed("right") then return self:cycle(1) end
  if input:wasPressed("left") then return self:cycle(-1) end
  if input:wasPressed("b") or input:wasPressed("l")
     or input:wasPressed("start") then
    return self:close()
  end

  local app = self:app()
  local name = app and app.name
  if not app then return end

  if input:wasPressed("a") then
    self:activate()
  elseif input:wasPressed("select") then
    if name == "Counter" then self:store().counter = 0
    elseif name == "Pedometer" then self:store().steps = 0
    elseif name == "Stopwatch" then self:store().stopwatch = 0; self:store().stopwatchRunning = false
    elseif name == "Memo Pad" then self:store().memo = {}
    elseif name == "Dot Artist" then self:store().dots = {} end
  end
end

-- The keyboard's stand-in for the app's main touch target.
function Gen4Poketch:activate()
  local app, s = self:app(), self:store()
  local name = app and app.name
  if name == "Counter" then s.counter = ((s.counter or 0) + 1) % 10000
  elseif name == "Coin Toss" then
    if not self.coinAnimation then
      s.coin=love.math.random(2)==1 and 'heads' or 'tails'
      self.coinAnimation={y=144,speed=-10.5,ticks=0,accumulator=0}
    end
  elseif name == "Stopwatch" then s.stopwatchRunning = not s.stopwatchRunning
  elseif name == "Kitchen Timer" then
    if s.timerRunning then self:timerButton(2) else self:timerButton(1) end
  elseif name == "Roulette" then
    local r = self:rouletteState()
    if r.phase == 'idle' then self:rouletteButton(1) elseif r.phase == 'spin' then self:rouletteButton(2) end
  elseif name == "Color Changer" then s.color = ((s.color or 0) + 1) % 8
  elseif name == "Dowsing Machine" then self:startDowsing(112,101)
  elseif name == "Alarm Clock" then s.alarmEnabled = not s.alarmEnabled
  elseif name == "Matchup Checker" then self:matchupTouch(112, 148)
  end
end

local CALC_KEYS = { '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '-', '+', '*', '/', '=', 'C' }

function Gen4Poketch:calculate(key)
  local s = self:store()
  local c = s.calculator or { display = '0' }; s.calculator = c
  if key == 'C' then c.display, c.left, c.op, c.fresh = '0', nil, nil, false
  elseif key:match('^[%d.]$') then
    if c.fresh or c.display == '0' or c.display == 'ERROR' then c.display = key == '.' and '0.' or key; c.fresh = false
    elseif #c.display < 10 and (key ~= '.' or not c.display:find('.', 1, true)) then c.display = c.display .. key end
  else
    local value = tonumber(c.display) or 0
    if c.op and c.left then
      if c.op == '+' then value = c.left + value
      elseif c.op == '-' then value = c.left - value
      elseif c.op == '*' then value = c.left * value
      elseif value == 0 then value = nil else value = c.left / value end
    end
    c.display = value and ('%.8g'):format(value) or 'ERROR'
    c.left, c.op, c.fresh = value, key ~= '=' and key or nil, true
  end
end

-- calculator.c sButtonPositions, in tiles: the keys' rectangles, in
-- CALC_KEYS order (0..9, decimal point, minus, plus, times, divide, equals,
-- clear) -- and so also their hit boxes.
local CALC_RECTS = {
  { 4, 18, 8, 4 }, { 4, 14, 4, 4 }, { 8, 14, 4, 4 }, { 12, 14, 4, 4 }, { 4, 10, 4, 4 },
  { 8, 10, 4, 4 }, { 12, 10, 4, 4 }, { 4, 6, 4, 4 }, { 8, 6, 4, 4 }, { 12, 6, 4, 4 },
  { 12, 18, 4, 4 }, { 20, 10, 4, 4 }, { 16, 10, 4, 4 }, { 16, 14, 4, 4 }, { 20, 14, 4, 4 },
  { 16, 18, 8, 4 }, { 16, 6, 8, 4 },
}
-- The glyph tile of each key's PRESSED picture (sPressed*Tiles' second row).
local CALC_GLYPH = { 85, 87, 89, 91, 93, 95, 97, 99, 101, 103, 105, 107, 109, 111, 113, 115, 117 }
Gen4Poketch.CALC_RECTS = CALC_RECTS

local function inRect(x, y, l, t, r, b) return x >= l and x < r and y >= t and y < b end

function Gen4Poketch:touchpressed(id, px, py)
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x then return false end
  if self.pointer~=nil then return true end
  self.pointer = id
  self.held = { x = x, y = y, start = self.ticks or 0, tapped = true }
  if x >= 224 and y >= 32 and y < 160 then self.held = nil; self:cycle(y < 96 and -1 or 1); return true end
  if x < FACE.x or x >= FACE.x + FACE.w or y < FACE.y or y >= FACE.y + FACE.h then return true end
  local name = (self:app() or {}).name
  local s = self:store()
  if name == 'Calculator' then
    for i, r in ipairs(CALC_RECTS) do
      if inRect(x, y, r[1] * 8, r[2] * 8, (r[1] + r[3]) * 8, (r[2] + r[4]) * 8) then
        self.calcPressed = i
        self:calculate(CALC_KEYS[i])
        break
      end
    end
  elseif name == 'Memo Pad' and x >= 180 and x < 204 and y >= 24 and y < 88 then
    s.memoErasing = true
  elseif name == 'Memo Pad' and x >= 180 and x < 204 and y >= 104 and y < 168 then
    s.memoErasing = false
  elseif name == 'Memo Pad' or name == 'Dot Artist' then
    self:doodle(x, y)
  elseif name == 'Color Changer' then
    self:colorTouch(x, y)
  elseif name == 'Calendar' then
    local cell = self:calendarCellAt(x, y)
    if cell then
      local now = clockNow()
      local day = cell - self:calendarFirst() + 1
      s.calendar = s.calendar or {}; local key = ('%04d-%02d-%02d'):format(now.year, now.month, day)
      s.calendar[key] = not s.calendar[key]
    end
  elseif name == 'Marking Map' then
    local markers,order=self:mapMarkers()
    for i=#order,1,-1 do
      local index=order[i]; local marker=markers[index]
      if math.abs(marker.x-x)<=8 and math.abs(marker.y-y)<=8 then
        self.activeMapMarker=index
        table.remove(order,i); order[#order+1]=index
        marker.x,marker.y=x,y
        break
      end
    end
  elseif name == 'Pedometer' then
    if x >= 80 and x < 148 and y >= 104 and y < 152 then s.steps = 0; self.buttonDown = true end
  elseif name=='Counter' then
    if x>=80 and x<148 and y>=104 and y<152 then s.counter = ((s.counter or 0) + 1) % 10000; self.buttonDown = true end
  elseif name == 'Stopwatch' then
    -- stopwatch/main.c: one circular button, centre (112, 112), radius 39
    if (x - 112) ^ 2 + (y - 112) ^ 2 < 39 * 39 then self:stopwatchPress() end
  elseif name == 'Kitchen Timer' then
    self:timerTouch(x, y)
  elseif name == 'Alarm Clock' then
    self:alarmTouch(x, y)
  elseif name == 'Move Tester' then
    self:moveTesterTouch(x, y)
  elseif name == 'Matchup Checker' then self:matchupTouch(x, y)
  elseif name == 'Dowsing Machine' then
    if x>=24 and x<200 and y>=24 and y<168 then self:startDowsing(x,y) end
  elseif name == 'Roulette' then
    self:rouletteTouch(x, y)
  elseif name == 'Coin Toss' then
    self:activate()
  elseif name == 'Friendship Checker' then
    local fc = self:friendshipState()
    fc.tapped = true
    local index = self:friendshipMonAt(x, y - 8)
    local mon = index and fc.mons[index]
    if mon then
      require('src.core.Sound').playCry(self.game.data, mon.species)
      self.friendshipTouch = { slot = index, frames = 60 }
    end
  elseif name=='Pokémon List' or name=='Pokémon History' then
    local index
    if name == 'Pokémon List' then
      for i, at in ipairs(PARTY_AT) do
        if math.abs(x - at[1]) < 24 and math.abs(y - at[2]) < 24 then index = i end
      end
    else
      local col,row=math.floor((x-28)/40),math.floor((y-24)/48)
      if col>=0 and col<4 and row>=0 and row<3 then index=row*4+col+1 end
    end
    local mon=index and (name~='Pokémon History' and (self.game.save.party or {}) or (s.history or {}))[index]
    if mon and not mon.isEgg then
      require('src.core.Sound').playCry(self.game.data,mon.species)
    end
  elseif name == 'Digital Watch' or name == 'Analog Watch' then
    -- digital_watch/main.c ToggleBacklight: the light is on while the
    -- screen is held
    self.backlight = true
  end
  return true
end

function Gen4Poketch:doodle(x, y)
  if x < FACE.x or x >= FACE.x + FACE.w or y < FACE.y or y >= FACE.y + FACE.h then return end
  local s = self:store(); local name = (self:app() or {}).name
  local dot = name == 'Dot Artist'
  local key = dot and 'dots' or 'memo'
  s[key] = s[key] or {}
  if dot then
    local index = math.floor((y - FACE.y) / 8) * 96 + math.floor((x - FACE.x) / 8)
    if self.lastDot ~= index then
      local old = s[key][index]
      s[key][index] = ((type(old) == 'number' and old or 0) + 1) % 4
      self.lastDot = index
    end
    return
  end
  -- memo_pad: the canvas is 160 x 152 at (16, 16) in 2x2 pixels; the pencil
  -- sets one, the eraser clears an ERASER_SIZE (4)-cell square about it
  if x >= FACE.x + 160 or y >= FACE.y + 152 then return end
  local cx, cy = math.floor((x - FACE.x) / 2), math.floor((y - FACE.y) / 2)
  if s.memoErasing then
    for yy = cy - 2, cy + 1 do
      for xx = cx - 2, cx + 1 do
        if xx >= 0 and yy >= 0 then s[key][yy * 96 + xx] = nil end
      end
    end
  else
    s[key][cy * 96 + cx] = true
  end
end

function Gen4Poketch:touchmoved(id, px, py)
  if self.pointer ~= id then return false end
  local x, y = SecondScreen.toLocal(self.game, px, py)
  local name = (self:app() or {}).name
  if x and self.held then
    if math.abs(x - self.held.x) > 2 or math.abs(y - self.held.y) > 2 then self.held.moved = true end
    self.held.x, self.held.y = x, y
  end
  if x and name=='Marking Map' and self.activeMapMarker then
    local markers=self:mapMarkers()
    local marker=markers[self.activeMapMarker]
    marker.x=math.max(24,math.min(200,x)); marker.y=math.max(24,math.min(168,y))
  end
  if x and (name == 'Memo Pad' or name == 'Dot Artist') and not (name == 'Memo Pad' and x >= 176) then self:doodle(x, y) end
  if x and name == 'Color Changer' then self:colorTouch(x, y) end
  if x and name == 'Roulette' then self:rouletteDraw(x, y) end
  return true
end

-- THE COLOR CHANGER (applications/poketch/color_changer): a held touch on the
-- slider, 136 <= y < 160 and 48 <= x < 184, picks colour (x - 48) / 16, the
-- last of the eight being 7 (POKETCH_SCREEN_COLOR_MAX - 1). The whole LCD takes
-- that theme -- `applyLCDPalette` reads it.
function Gen4Poketch:colorTouch(x, y)
  if y >= 136 and y < 160 and x >= 48 and x < 184 then
    self:store().color = math.min(7, math.floor((x - 48) / 16))
  end
end

function Gen4Poketch:touchreleased(id)
  if self.pointer ~= id then return false end
  local name = (self:app() or {}).name
  if self.held then
    if name == 'Stopwatch' then self:stopwatchRelease() end
    if name == 'Kitchen Timer' then self:timerRelease() end
    if name == 'Roulette' then self:rouletteRelease() end
  end
  self.pointer, self.lastDot, self.activeMapMarker = nil, nil, nil
  self.held, self.calcPressed, self.buttonDown, self.backlight = nil, nil, nil, nil
  self.lastRoulette = nil
  return true
end

-- ------------------------------------------------------------------ apps --


-- One digit of the shared OBJ digit strip (digits_cell / digits_anim, the
-- sequence IS the digit), placed by its translation point.
function Gen4Poketch:digit(value, x, y)
  return self:drawCell("digits", (value or 0) % 10, x, y)
end

-- Text on the LCD: FONT_SYSTEM in TEXT_COLOR(1, 8, 4) -- the darkest shade
-- over the dark one, as every Poketch window prints.
function Gen4Poketch:lcdText(text, x, y)
  if not text or text == "" then return end
  local faced = Font.pushFace and Font.pushFace("system")
  local ink, shadow = LCD[1], LCD[8]
  local two = Font.beginTwoTone and Font.beginTwoTone(
    { ink[1] / 255, ink[2] / 255, ink[3] / 255, 1 }, { shadow[1] / 255, shadow[2] / 255, shadow[3] / 255, 1 })
  love.graphics.setColor(1, 1, 1, 1)
  Font.draw(text, x, y)
  if two and Font.endTwoTone then Font.endTwoTone() end
  if faced and Font.popFace then Font.popFace() end
end

function Gen4Poketch:lcdTextWidth(text)
  local faced = Font.pushFace and Font.pushFace("system")
  local w = Font.width(text)
  if faced and Font.popFace then Font.popFace() end
  return w
end

function Gen4Poketch:textBank(bank, index, fallback)
  local text = (self.game.data or {}).text or {}
  return text[("TEXT_B%04d_%05d"):format(bank, index)] or fallback
end

-- ------------------------------------------------------------ the watches --

-- digital_watch: the digit strip (digital_watch_digits.NSCR over the watch's
-- generic solid BG tiles, four tiles a digit, nine high) copied to (3, 7) and (8, 7)
-- for the hour and (15, 7), (20, 7) for the minute. The colon is the
-- background's own and does not blink.
function Gen4Poketch:drawDigitalWatch()
  local now = clockNow()
  -- Copy the native map against its actual generic tile bank. This also
  -- repairs existing caches whose composed strip used watch decoration tiles.
  if self:ink().tilemaps and self:ink().tilemaps.digital_watch_digits and self:artImage("generic_bgtiles") then
    local source=self:ink().tilemaps.digital_watch_digits
    if self.digitalWatchSource~=source then
      self.digitalWatchSource=source
      self.digitalWatchMap=require("src.import.Gen4PoketchArt").digitalWatchMap(source)
    end
    local function put(d,tx)
      local words={}
      for y=0,8 do for x=0,3 do words[#words+1]=self.digitalWatchMap.cells[y*40+d*4+x+1] end end
      self:drawTiles("generic",words,4,tx,7)
    end
    put(math.floor(now.hour/10),3);put(now.hour%10,8)
    put(math.floor(now.min/10),15);put(now.min%10,20)
    return
  end
  local strip = self:artImage("digital_watch_digits")
  if not strip then return end
  self.digitQuads = self.digitQuads or {}
  local iw, ih = strip:getDimensions()
  local function put(d, tx)
    local q = self.digitQuads[d]
    if not q then q = love.graphics.newQuad(d * 32, 0, 32, 72, iw, ih); self.digitQuads[d] = q end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(strip, q, tx * 8, 7 * 8)
  end
  put(math.floor(now.hour / 10), 3); put(now.hour % 10, 8)
  put(math.floor(now.min / 10), 15); put(now.min % 10, 20)
end

-- analog_watch: two affine hand sprites at (116, 100); the minute hand's
-- sequence is the minute, the hour hand's 60 + 30 * (hour % 12) + minute / 2
-- (one of 360 angles, a step every two minutes).
function Gen4Poketch:drawAnalogWatch()
  local now = clockNow()
  self:sprite("hour", "analog_watch", 60 + (now.hour % 12) * 30 + math.floor(now.min / 2), 116, 100)
  self:sprite("minute", "analog_watch", now.min, 116, 100)
end

-- ----------------------------------------------------------- the calendar --
--
-- calendar/graphics.c: BG3 is calendar.NSCR with each marked day's 2x2 cell
-- filled with tile 143 (an unmarked one is 131); BG2 holds the month's number
-- (a 4x2 block of the tile sheet at (12, 2)) and each day's digits (tiles
-- 96.. or, on a Sunday, 120.., with the lower half 12 tiles on); the OBJ box
-- marks today at ((3 * col + 5) * 8, (3 * row + 6) * 8).

function Gen4Poketch:calendarFirst()
  local now = clockNow()
  return ((now.wday or 1) - 1 - ((now.day or 1) - 1) % 7) % 7
end

function Gen4Poketch:calendarCellAt(x, y)
  local col, row = math.floor((x - 32) / 24), math.floor((y - 40) / 24)
  if col < 0 or col > 6 or row < 0 then return nil end
  if (x - 32) % 24 >= 16 or (y - 40) % 24 >= 16 then return nil end
  local cell = row * 7 + col
  local now = clockNow()
  local days = os.date("*t", os.time({ year = now.year, month = now.month + 1, day = 1, hour = 12 }) - 86400).day
  local day = cell - self:calendarFirst() + 1
  if day < 1 or day > days then return nil end
  return cell
end

local MONTH_TILES = { 0, 4, 8, 24, 28, 32, 48, 52, 56, 72, 76, 80 }

function Gen4Poketch:drawCalendar()
  local now = clockNow()
  local month = math.max(1, math.min(12, now.month or 1))
  local first = self:calendarFirst()
  local days = os.date("*t", os.time({ year = now.year, month = month + 1, day = 1, hour = 12 }) - 86400).day
  local marks = self:store().calendar or {}
  for day = 1, days do
    local cell = first + day - 1
    if marks[('%04d-%02d-%02d'):format(now.year, month, day)] then
      local x, y = 4 + 3 * (cell % 7), 5 + 3 * math.floor(cell / 7)
      self:drawTiles("calendar", { 143, 143, 143, 143 }, 2, x, y)
    end
  end
  -- the month: tiles t..t+3 over t+12..t+15 at (12, 2)
  local t = MONTH_TILES[month]
  self:drawTiles("calendar", { t, t + 1, t + 2, t + 3, t + 12, t + 13, t + 14, t + 15 }, 4, 12, 2)
  for day = 1, days do
    local cell = first + day - 1
    local x, y = 4 + 3 * (cell % 7), 5 + 3 * math.floor(cell / 7)
    local base = (cell % 7 == 0) and 120 or 96
    local tens, ones = math.floor(day / 10), day % 10
    if tens > 0 then self:drawTiles("calendar", { base + tens, base + tens + 12 }, 1, x, y) end
    self:drawTiles("calendar", { base + ones, base + ones + 12 }, 1, x + 1, y)
  end
  local today = first + (now.day or 1) - 1
  self:drawCell("calendar", 0, (3 * (today % 7) + 5) * 8, (3 * math.floor(today / 7) + 6) * 8)
end

-- ------------------------------------------------ counter and pedometer --

-- counter: four OBJ digits at x = 88 + 16i, y = 64 (leading zeroes shown),
-- and the button at (114, 128) -- sequence 1 while it is held.
function Gen4Poketch:drawCount(value, count, firstX, set)
  value = math.max(0, math.min(10 ^ count - 1, math.floor(value or 0)))
  for i = 0, count - 1 do
    self:digit(math.floor(value / 10 ^ (count - 1 - i)) % 10, firstX + i * 16, 64)
  end
  self:drawCell(set, self.buttonDown and 1 or 0, 114, 128)
end

function Gen4Poketch:drawCounter()
  self:drawCount(self:store().counter, 4, 88, 'counter')
end

-- pedometer: five digits from x = 80.
function Gen4Poketch:drawPedometer()
  self:drawCount(self:store().steps, 5, 80, 'pedometer')
end

-- ------------------------------------------------------------ coin toss --

function Gen4Poketch:updateCoin(dt)
  local a=self.coinAnimation
  if not a then return end
  a.accumulator=a.accumulator+math.max(0,tonumber(dt) or 0)*60
  while a.accumulator>=1 do
    a.accumulator=a.accumulator-1; a.ticks=a.ticks+1
    a.y=a.y+a.speed; a.speed=a.speed+0.6875
    if a.speed>0 and a.y>=144 then
      a.speed=-a.speed*0.56; a.y=144
      if a.speed>=-2 then self.coinAnimation=nil; break end
    end
  end
end

-- coin_toss: the coin rests at (COIN_REST_POSITION_X, _Y) = (112, 144) on
-- sequence 1 (heads) or 2 (tails), and spins on sequence 0 while in the air.
function Gen4Poketch:drawCoinToss()
  local face = self:store().coin
  local a = self.coinAnimation
  local y = a and a.y or 144
  if a then
    local f = self:animFrame('coin_toss', 0, a.ticks)
    self:drawCell('coin_toss', f.cell, 112, y)
  else
    local f = self:animFrame('coin_toss', face == 'tails' and 2 or 1, 0)
    self:drawCell('coin_toss', f.cell, 112, y)
  end
end

-- ----------------------------------------------------------- calculator --

-- calculator/graphics.c: ten 2x2 display cells from tile (5, 3), each blank
-- (43) or symbol n at 165 + 2n (0-9, then 10 the point, 11 the minus sign, 12
-- the error bar); the pending operator's 2x2 at (3, 3), blank 41 or 240 +
-- 2 * (minus, plus, times, divide); the sheet is 40 tiles wide, so a cell's
-- lower half is 40 tiles on.
local CALC_OPS = { ['-'] = 0, ['+'] = 1, ['*'] = 2, ['/'] = 3 }

function Gen4Poketch.calculatorSymbols(display)
  local symbols = {}
  if display == 'ERROR' then
    for i = 1, 10 do symbols[i] = 12 end
    return symbols
  end
  for ch in tostring(display):gmatch('.') do
    if ch:match('%d') then symbols[#symbols + 1] = tonumber(ch)
    elseif ch == '.' then symbols[#symbols + 1] = 10
    elseif ch == '-' then symbols[#symbols + 1] = 11 end
  end
  while #symbols > 10 do table.remove(symbols) end
  return symbols
end

function Gen4Poketch:drawCalculator()
  local c = self:store().calculator or { display = '0' }
  local symbols = Gen4Poketch.calculatorSymbols(c.display or '0')
  local function cell2(t, tx) self:drawTiles('calculator', { t, t + 1, t + 40, t + 41 }, 2, tx, 3) end
  local blank = 10 - #symbols
  for i = 0, 9 do
    local sym = symbols[i - blank + 1]
    cell2(i < blank and 43 or (165 + sym * 2), 5 + i * 2)
  end
  local op = c.op and CALC_OPS[c.op]
  cell2(op and (240 + op * 2) or 41, 3)
  local pressed = self.calcPressed
  if pressed then
    local r, g = CALC_RECTS[pressed], CALC_GLYPH[pressed]
    local bottom = (pressed == 1 or pressed == 11 or pressed == 16) and { 337, 338, 339 } or { 331, 332, 333 }
    -- top: 251 252.. 253; glyph rows: 291 g g+1 292.. 293; bottom
    local top = { 251 }; for _ = 1, r[3] - 2 do top[#top + 1] = 252 end; top[#top + 1] = 253
    local g1, g2 = { 291, g, g + 1 }, { 291, g + 40, g + 41 }
    for _ = 1, r[3] - 4 do g1[#g1 + 1] = 292; g2[#g2 + 1] = 292 end
    g1[#g1 + 1] = 293; g2[#g2 + 1] = 293
    local bot = { bottom[1] }; for _ = 1, r[3] - 2 do bot[#bot + 1] = bottom[2] end; bot[#bot + 1] = bottom[3]
    local words = {}
    for _, list in ipairs({ top, g1, g2, bot }) do for _, w in ipairs(list) do words[#words + 1] = w end end
    self:drawTiles('calculator', words, r[3], r[1], r[2])
  end
end

-- ------------------------------------------------------------ stopwatch --
--
-- stopwatch/main.c + graphics.c. Eight OBJ digits at y = 40 (hours at 32 and
-- 48, minutes 80/96, seconds 128/144, hundredths 176/192); Voltorb, the one
-- button, is BG tiles at (9, 9) -- 5 x 11, mirrored to ten wide, out of seven
-- groups (unpressed, pressed, bright, normal, dark, exploding x2) -- with the
-- OBJ face over it at (112, 96) while it runs (sequence 12), blinks (13, 14),
-- explodes (15) or recovers (16). A press pauses or arms it; the release
-- starts it; held 15 ticks it starts blinking, held 75 the reset sequence
-- runs: 90 ticks fast-blinking, 60 exploding, then zero and 80 to recover.

local SW_FACE = { [1] = 11, [2] = 12, [3] = 13, [4] = 14, [5] = 15, [6] = 16 }

function Gen4Poketch:swState()
  self.appState = self.appState or {}
  local st = self.appState
  if not st.sequence then st.sequence = self:store().stopwatchRunning and 2 or 0; st.t = 0; st.blink = 0 end
  return st
end

function Gen4Poketch:stopwatchPress()
  local s, st = self:store(), self:swState()
  if st.sequence >= 4 then return end
  st.wasRunning = s.stopwatchRunning
  s.stopwatchRunning = false
  st.sequence, st.t, st.holding, st.held = 1, 0, true, 0
end

function Gen4Poketch:stopwatchRelease()
  local s, st = self:store(), self:swState()
  if not st.holding then return end
  st.holding = false
  if st.sequence >= 4 then return end
  if st.wasRunning then st.sequence = 0
  else s.stopwatchRunning = true; st.sequence = 2 end
end

function Gen4Poketch:updateStopwatch(tick30)
  local s, st = self:store(), self:swState()
  if not st.holding and st.sequence < 4 then st.sequence = s.stopwatchRunning and 2 or (st.sequence == 2 and 0 or st.sequence) end
  if not tick30 then return end
  if st.holding and st.sequence < 4 then
    st.held = st.held + 1
    if st.held == 15 then st.sequence, st.blink, st.blinkT = 3, 0, 0 end
    if st.held == 75 then st.sequence, st.t, st.blink, st.blinkT = 4, 0, 0, 0 end
  end
  if st.sequence == 3 or st.sequence == 4 then
    st.blinkT = (st.blinkT or 0) + 1
    if st.blinkT > (st.sequence == 3 and 6 or 3) then st.blinkT = 0; st.blink = ((st.blink or 0) + 1) % 3 end
  end
  if st.sequence == 4 then
    st.t = st.t + 1
    if st.t >= 90 then st.sequence, st.t, st.blinkT, st.blink = 5, 0, 0, 0 end
  elseif st.sequence == 5 then
    st.t = st.t + 1
    st.blinkT = (st.blinkT or 0) + 1
    if st.blinkT > 2 then st.blinkT = 0; st.blink = 1 - (st.blink or 0) end
    if st.t >= 60 then st.sequence, st.t = 6, 0; s.stopwatch = 0; s.stopwatchRunning = false end
  elseif st.sequence == 6 then
    st.t = st.t + 1
    if st.t > 80 then st.sequence = 0 end
  end
end

-- the button's BG tile group: UpdateButtonTiles
function Gen4Poketch:drawStopwatchButton(group)
  local words = {}
  for row = 0, 10 do
    local first = group * 5 + 2 + row * 37
    local line = {}
    for x = 0, 4 do
      line[x + 1] = first + x
      line[10 - x] = (first + x) + 0x400
    end
    for _, w in ipairs(line) do words[#words + 1] = w end
  end
  self:drawTiles('stopwatch', words, 10, 9, 9)
end

function Gen4Poketch:drawStopwatch()
  local st = self:swState()
  local t = math.floor((self:store().stopwatch or 0) * 100 + 0.5)
  local cs, sec, min, hour = t % 100, math.floor(t / 100) % 60, math.floor(t / 6000) % 60, math.floor(t / 360000) % 24
  local xs = { 32, 48, 80, 96, 128, 144, 176, 192 }
  local values = { math.floor(hour / 10), hour % 10, math.floor(min / 10), min % 10,
                   math.floor(sec / 10), sec % 10, math.floor(cs / 10), cs % 10 }
  for i, v in ipairs(values) do self:digit(v, xs[i], 40) end
  local group = 0
  if st.sequence == 1 then group = 1
  elseif st.sequence == 3 or st.sequence == 4 then group = ({ 2, 3, 4 })[(st.blink or 0) + 1]
  elseif st.sequence == 5 then group = 5 + (st.blink or 0)
  elseif st.sequence == 6 then group = 6 end
  self:drawStopwatchButton(group)
  if st.sequence ~= 0 and SW_FACE[st.sequence] then
    self:sprite("voltorb", "stopwatch", SW_FACE[st.sequence], 112, 96)
  end
end

-- -------------------------------------------------------- kitchen timer --
--
-- kitchen_timer/main.c + graphics.c. Four OBJ digits at (80, 112), (96, 112),
-- (128, 112), (144, 112) each with an up arrow 24 above and a flipped one 24
-- below while the time can be set; START, STOP and RESET at (48, 160),
-- (112, 160), (176, 160), each up or down; Snorlax's hands (48, 56) and
-- (176, 56) down while the timer runs and beating every 8 ticks while it
-- sounds. Store: timerDuration (the set time), timer (left), timerRunning,
-- timerPaused, timerFinished (sounding), timerSilenced (sounding, stopped).

local KT_BUTTONS = { { 16, 144, 80, 176 }, { 80, 144, 144, 176 }, { 144, 144, 208, 176 } }
local KT_ARROWS = {
  { 72, 80, 88, 96, 600, 1 }, { 88, 80, 104, 96, 60, 1 }, { 120, 80, 136, 96, 10, 1 }, { 136, 80, 152, 96, 1, 1 },
  { 72, 128, 88, 144, 600, -1 }, { 88, 128, 104, 144, 60, -1 }, { 120, 128, 136, 144, 10, -1 }, { 136, 128, 152, 144, 1, -1 },
}

function Gen4Poketch:timerMode()
  local s = self:store()
  if s.timerFinished and not s.timerSilenced then return 'sounding' end
  if s.timerFinished then return 'silenced' end
  if s.timerRunning then return 'running' end
  if s.timerPaused then return 'paused' end
  return 'edit'
end

-- The set time's digits change one at a time and each wraps on its own
-- (minutes' tens 0-9, ones 0-9, seconds' tens 0-5, ones 0-9).
function Gen4Poketch.timerAdjust(duration, unit, dir)
  local m, sec = math.floor(duration / 60), duration % 60
  local d = { math.floor(m / 10), m % 10, math.floor(sec / 10), sec % 10 }
  local idx = ({ [600] = 1, [60] = 2, [10] = 3, [1] = 4 })[unit]
  local max = idx == 3 and 6 or 10
  d[idx] = (d[idx] + dir) % max
  return (d[1] * 10 + d[2]) * 60 + d[3] * 10 + d[4]
end

function Gen4Poketch:timerButton(which)
  local s, mode = self:store(), self:timerMode()
  if which == 1 then          -- START
    if mode == 'edit' then
      local total = s.timerDuration or 0
      if total > 0 then s.timer = total; s.timerRunning = true; s.timerPaused = false end
    elseif mode == 'paused' then s.timerRunning = true; s.timerPaused = false
    elseif mode == 'silenced' then s.timerSilenced = false end
  elseif which == 2 then      -- STOP
    if mode == 'running' then s.timerRunning = false; s.timerPaused = true
    elseif mode == 'sounding' then s.timerSilenced = true end
  else                        -- RESET
    s.timerRunning, s.timerPaused, s.timerFinished, s.timerSilenced = false, false, false, false
    s.timer = nil
    if mode ~= 'edit' then s.timerDuration = 0 end
  end
end

function Gen4Poketch:timerTouch(x, y)
  self.appState = self.appState or {}
  for i, r in ipairs(KT_BUTTONS) do
    if inRect(x, y, r[1], r[2], r[3], r[4]) then
      self.appState.ktPressed = i
      return self:timerButton(i)
    end
  end
  if self:timerMode() ~= 'edit' then return end
  local s = self:store()
  for _, a in ipairs(KT_ARROWS) do
    if inRect(x, y, a[1], a[2], a[3], a[4]) then
      s.timerDuration = Gen4Poketch.timerAdjust(s.timerDuration or 0, a[5], a[6])
      s.timer = s.timerDuration
      return
    end
  end
end

function Gen4Poketch:timerRelease()
  if self.appState then self.appState.ktPressed = nil end
end

function Gen4Poketch:drawTimer()
  local s, mode = self:store(), self:timerMode()
  local t = (mode == 'edit') and (s.timerDuration or 0) or math.ceil(s.timer or 0)
  if mode == 'sounding' or mode == 'silenced' then t = 0 end
  local m, sec = math.floor(t / 60) % 100, t % 60
  local xs = { 80, 96, 128, 144 }
  local d = { math.floor(m / 10), m % 10, math.floor(sec / 10), sec % 10 }
  for i = 1, 4 do self:digit(d[i], xs[i], 112) end
  if mode == 'edit' then
    for i = 1, 4 do
      self:sprite("ktup" .. i, "kitchen_timer", 4, xs[i], 88)
      self:sprite("ktdn" .. i, "kitchen_timer", 4, xs[i], 136, { flipV = true })
    end
  end
  -- hands: 0 edit (up, up), 1 running/paused (down, down), 2 sounding
  -- (beating), 3 silenced (left up, right down)
  local left, right = 2, 0
  if mode == 'running' or mode == 'paused' then left, right = 3, 1
  elseif mode == 'silenced' then left, right = 2, 1
  elseif mode == 'sounding' then
    local beat = math.floor((self.ticks or 0) / 16) % 2 == 1
    left, right = beat and 2 or 3, beat and 1 or 0
  end
  self:sprite("kthl", "kitchen_timer", left, 48, 56)
  self:sprite("kthr", "kitchen_timer", right, 176, 56)
  -- buttons: START down while running/sounding, STOP down while it cannot stop
  local pressed = self.appState and self.appState.ktPressed
  local startDown = (mode == 'running' or mode == 'sounding') or pressed == 1
  local stopDown = (mode == 'edit' or mode == 'paused' or mode == 'silenced') or pressed == 2
  self:sprite("kts", "kitchen_timer", startDown and 6 or 5, 48, 160)
  self:sprite("ktp", "kitchen_timer", stopDown and 8 or 7, 112, 160)
  self:sprite("ktr", "kitchen_timer", pressed == 3 and 10 or 9, 176, 160)
end

-- ---------------------------------------------------------- alarm clock --
--
-- alarm_clock: the switch at (192, 104) -- sequence 2 (setting) or 3 (set);
-- Loudred's ears (48, 48) and (144, 48, mirrored), eyes (56, 80) and
-- (136, 80, mirrored), four arrows while setting, four OBJ digits at
-- (64, 144), (80, 144), (112, 144), (128, 144): the alarm time while setting,
-- the time now while set. Ringing: eyes 4, ears 1, digits blinking every 15
-- ticks and Loudred's cry.

function Gen4Poketch:alarmRinging()
  local s = self:store()
  local now = clockNow()
  return s.alarmEnabled and now.hour == (s.alarmHour or 0) and now.min == (s.alarmMinute or 0)
end

function Gen4Poketch:alarmTouch(x, y)
  local s = self:store()
  if inRect(x, y, 176, 72, 208, 104) then s.alarmEnabled = true; return end
  if inRect(x, y, 176, 104, 208, 136) then s.alarmEnabled = false; return end
  if s.alarmEnabled then return end
  if inRect(x, y, 64, 112, 80, 128) then s.alarmHour = ((s.alarmHour or 0) + 1) % 24
  elseif inRect(x, y, 64, 160, 80, 176) then s.alarmHour = ((s.alarmHour or 0) - 1) % 24
  elseif inRect(x, y, 112, 112, 128, 128) then s.alarmMinute = ((s.alarmMinute or 0) + 1) % 60
  elseif inRect(x, y, 112, 160, 128, 176) then s.alarmMinute = ((s.alarmMinute or 0) - 1) % 60 end
end

function Gen4Poketch:drawAlarm()
  local s = self:store()
  local set = s.alarmEnabled and true or false
  local ringing = self:alarmRinging()
  self:sprite("aset", "alarm_clock", set and 3 or 2, 192, 104)
  self:sprite("aearl", "alarm_clock", ringing and 1 or 0, 48, 48)
  self:sprite("aearr", "alarm_clock", ringing and 1 or 0, 144, 48, { flipH = true })
  local eyeL, eyeR = 5, set and 5 or 4
  if ringing then eyeL, eyeR = 4, 4 end
  self:sprite("aeyel", "alarm_clock", eyeL, 56, 80)
  self:sprite("aeyer", "alarm_clock", eyeR, 136, 80, { flipH = true })
  if not set then
    self:sprite("ahu", "alarm_clock", 6, 72, 120)
    self:sprite("ahd", "alarm_clock", 6, 72, 164, { flipV = true })
    self:sprite("amu", "alarm_clock", 6, 120, 120)
    self:sprite("amd", "alarm_clock", 6, 120, 164, { flipV = true })
  end
  local now = clockNow()
  local h, m = set and now.hour or (s.alarmHour or 0), set and now.min or (s.alarmMinute or 0)
  local hidden = ringing and math.floor((self.ticks or 0) / 30) % 2 == 1
  if not hidden then
    self:digit(math.floor(h / 10), 64, 144); self:digit(h % 10, 80, 144)
    self:digit(math.floor(m / 10), 112, 144); self:digit(m % 10, 128, 144)
  end
end

-- ------------------------------------------------- memo pad, dot artist --

-- memo_pad: the drawing is a window on BG3 at tile (2, 2), 20 x 19, filled
-- with colour 4 and drawn in 2x2 pixels of colour 1, BEHIND the app's own
-- BG2 (which frames it); the eraser (192, 56) and pencil (192, 136) sprites
-- show which tool is held (eraser 0/1, pencil 2/3, the odd one pressed).
function Gen4Poketch:drawMemoWindow()
  lcd(4)
  love.graphics.rectangle('fill', 16, 16, 160, 152)
  lcd(1)
  for index, on in pairs(self:store().memo or {}) do
    local cx, cy = index % 96, math.floor(index / 96)
    if on and cx < 80 and cy < 76 then love.graphics.rectangle('fill', 16 + cx * 2, 16 + cy * 2, 2, 2) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawMemoPad()
  local erasing = self:store().memoErasing
  self:sprite("eraser", "memo_pad", erasing and 1 or 0, 192, 56)
  self:sprite("pencil", "memo_pad", erasing and 2 or 3, 192, 136)
end

-- dot_artist: 24 x 20 cells of one solid tile each over the whole LCD, a
-- cell's value 1-4 (stored here 0-3) being colour 4, 15, 8 or 1.
local DOT_SHADES = { 4, 15, 8, 1 }
function Gen4Poketch:drawDotArtist()
  lcd(4)
  love.graphics.rectangle('fill', FACE.x, FACE.y, FACE.w, FACE.h)
  for index, value in pairs(self:store().dots or {}) do
    local v = type(value) == 'number' and value or 0
    if v > 0 then
      lcd(DOT_SHADES[v + 1])
      love.graphics.rectangle('fill', FACE.x + index % 96 * 8, FACE.y + math.floor(index / 96) * 8, 8, 8)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawDoodle()
  if (self:app() or {}).name == 'Dot Artist' then return self:drawDotArtist() end
  return self:drawMemoPad()
end

-- ---------------------------------------------------- the marking map --

-- poketch_map.c PoketchMap_GetPositionOnMap: a matrix cell's dot.
local MAP_X = { 26, 32, 38, 44, 50, 56, 62, 68, 74, 80, 86, 92, 98, 104, 110, 116, 122, 128, 134, 140,
                146, 152, 158, 164, 170, 176, 182, 188, 194, 200 }
local MAP_Y = { 0, 0, 0, 0, 0, 24, 30, 36, 42, 48, 54, 60, 66, 72, 78, 84, 90, 96, 102, 108, 114, 120,
                126, 132, 138, 144, 150, 156, 162, 168, 174, 180, 186 }
local HIDDEN_AT = { { 32, 42 }, { 50, 42 }, { 168, 122 }, { 194, 58 } }
Gen4Poketch.MAP_X, Gen4Poketch.MAP_Y = MAP_X, MAP_Y

function Gen4Poketch:playerOnMap()
  local ok, TownMap = pcall(require, 'src.ui.Gen4TownMap')
  if not ok then return nil end
  local okCell, x, z = pcall(TownMap.playerCell, self.game)
  if not okCell or not x then return nil end
  return MAP_X[x + 1] or MAP_X[1], MAP_Y[z + 1] or MAP_Y[1]
end

-- The four hidden locations (Gen4HiddenPaths), each shown once unlocked.
function Gen4Poketch:drawHiddenLocations(firstSeq)
  local ok, H = pcall(require, 'src.world.Gen4HiddenPaths')
  if not ok then return end
  for i = 0, 3 do
    local okU, open = pcall(H.unlocked, self.game.save, i)
    if okU and open then self:sprite('hidden' .. i, 'map', firstSeq + i, HIDDEN_AT[i + 1][1], HIDDEN_AT[i + 1][2]) end
  end
end

function Gen4Poketch:mapMarkers()
  local s=self:store()
  if not s.mapMarkers then
    s.mapMarkers={}
    for i=1,6 do s.mapMarkers[i]={x=32+(i-1)*28,y=164} end
  end
  s.mapMarkerOrder=s.mapMarkerOrder or {1,2,3,4,5,6}
  return s.mapMarkers,s.mapMarkerOrder
end

-- marking_map: the player's cursor (sequence 0, blinking), the six markers
-- (1-6, 8-13 while one is dragged), the hidden locations (14-17) and the
-- roamers (18).
function Gen4Poketch:drawMarkers()
  self:drawHiddenLocations(14)
  for _, at in ipairs(require('src.import.Gen4PoketchMap').roamers(self.game)) do
    self:sprite('roamer' .. (at.slot or 0), 'map', 18, at.x, at.y)
  end
  local px, py = self:playerOnMap()
  if px then self:sprite('cursor', 'map', 0, px, py) end
  local markers, order = self:mapMarkers()
  for _, index in ipairs(order) do
    local marker = markers[index]
    local seq = (index == self.activeMapMarker and 8 or 1) + index - 1
    self:sprite('marker' .. index, 'map', seq, marker.x, marker.y)
  end
end

-- berry_searcher: the same map, every ripe berry patch (sequence 7) and the
-- player, with "BERRIES" (TEXT_BANK_POKETCH_BERRY_SEARCHER) in a window at
-- tile (18, 20).
function Gen4Poketch:drawBerrySearcher()
  self:drawHiddenLocations(14)
  for i, at in ipairs(require('src.world.Gen4BerryPatches').ready(self.game)) do
    self:sprite('berry' .. i, 'map', 7, MAP_X[at.x + 1] or (26 + 6 * at.x), MAP_Y[at.y + 1] or (6 * at.y - 6))
  end
  local px, py = self:playerOnMap()
  if px then self:sprite('cursor', 'map', 0, px, py) end
  lcd(4); love.graphics.rectangle('fill', 144, 160, 64, 16)
  self:lcdText(self:textBank(459, 0, 'BERRIES'), 144, 160)
end

-- -------------------------------------------------------- party status --
--
-- party_status: the BG is tile 5 everywhere; each member's HP bar is an 8 x 1
-- tile window at (4, 8), (16, 8), (4, 14), (16, 14), (4, 20), (16, 20) framed
-- by tiles 1, 2 and 6 (mirrored round the other sides), filled with colour 4
-- and, from the left, colour 15 for 2 x (hp / max x 32) pixels (at least one
-- step while alive, one short while not full). The icon (sequence 4, i.e.
-- twice size) at (64, 36), (160, 36) ... ; a fainted or statused member's in
-- solid colour 15; a held item (sequence 0) or mail (1) at icon + (28, 21).

local HP_AT = { { 4, 8 }, { 16, 8 }, { 4, 14 }, { 16, 14 }, { 4, 20 }, { 16, 20 } }
Gen4Poketch.PARTY_AT = PARTY_AT

function Gen4Poketch.hpBarWidth(hp, max)
  hp, max = tonumber(hp) or 0, math.max(1, tonumber(max) or 1)
  if hp <= 0 then return 0 end
  if hp >= max then return 64 end
  local w = math.floor(hp * 32 / max)
  if w == 0 then w = 1 elseif w == 32 then w = 31 end
  return w * 2
end

function Gen4Poketch:drawPartyStatus()
  local g = love.graphics
  local fill = {}
  for i = 1, 32 * 24 do fill[i] = 5 end
  self:drawTiles('party_status', fill, 32, 0, 0)
  local party = (self.game.save or {}).party or {}
  local items = (self.game.data or {}).items or {}
  for i = 1, math.min(6, #party) do
    local mon = party[i]
    local hx, hy = HP_AT[i][1], HP_AT[i][2]
    self:drawTiles('party_status', { 1, 2, 2, 2, 2, 2, 2, 2, 2, 1 + 0x400 }, 10, hx - 1, hy - 1)
    self:drawTiles('party_status', { 6 }, 1, hx - 1, hy)
    self:drawTiles('party_status', { 6 + 0x400 }, 1, hx + 8, hy)
    self:drawTiles('party_status', { 1 + 0x800, 2 + 0x800, 2 + 0x800, 2 + 0x800, 2 + 0x800, 2 + 0x800,
      2 + 0x800, 2 + 0x800, 2 + 0x800, 1 + 0x800 + 0x400 }, 10, hx - 1, hy + 1)
    lcd(4); g.rectangle('fill', hx * 8, hy * 8, 64, 8)
    local hp = math.max(0, tonumber(mon.hp) or 0)
    local max = tonumber((mon.stats or {}).hp) or tonumber(mon.maxHp) or hp
    local w = Gen4Poketch.hpBarWidth(hp, max)
    if w > 0 then lcd(15); g.rectangle('fill', hx * 8, hy * 8, w, 8) end
    g.setColor(1, 1, 1, 1)
    local at = PARTY_AT[i]
    local downed = (hp == 0) or (mon.status ~= nil and mon.status ~= '' and mon.status ~= 'OK')
    self:drawMonIcon(mon, at[1], at[2], { seq = 4, solid = downed and not mon.isEgg and 15 or nil, id = 'party' .. i })
    local item = mon.item or mon.heldItem
    if item and item ~= 0 then
      local rec = items[item]
      local mail = type(rec) == 'table' and (rec.pocket == 'MAIL' or rec.mail)
      self:sprite('item' .. i, 'party_status', mail and 1 or 0, at[1] + 28, at[2] + 21)
    end
  end
  g.setColor(1, 1, 1, 1)
end

-- ----------------------------------------------------------- mon icons --
--
-- Every Poketch app draws its party in the LCD's four shades:
-- PoketchTask_MapToActivePaletteFromLuminance turns each icon colour into
-- ((r*299 + g*587 + b*114) / 1000) >> 3 of its 5-bit components, and that 0-3
-- into palette entry 1, 8, 15 or 4. The icon is a poke_icon cell -- the
-- sprite's two frames, 32 x 32, centred on its point -- through the
-- sequence's SRT: sequences 0-3 at 1.5x, 4-7 at 2x, the odd ones mirrored,
-- 2/3/6/7 alternating the frames every 20 frames.

local iconShader
local function lumShader()
  if iconShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern vec3 shades[4];
      extern float solid;
      extern vec3 solidColour;
      vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        if (p.a < 0.5) return vec4(0.0);
        if (solid > 0.5) return vec4(solidColour, colour.a);
        vec3 q = floor(p.rgb * 31.0 + 0.5);
        float l = floor((q.r * 299.0 + q.g * 587.0 + q.b * 114.0) / 1000.0);
        l = min(floor(l / 8.0), 3.0);
        vec3 c = shades[3];
        if (l < 0.5) c = shades[0]; else if (l < 1.5) c = shades[1]; else if (l < 2.5) c = shades[2];
        return vec4(c, colour.a);
      }
    ]])
    iconShader = ok and sh or false
  end
  return iconShader or nil
end
Gen4Poketch.lumShader = lumShader

function Gen4Poketch:iconImage(mon)
  local data = self.game.data
  local icons = data.icons or {}
  local species = mon.isEgg and 'EGG' or mon.species
  local entry = (icons.bySpecies or {})[species] or ((data.pokemon or {})[mon.species] or {}).icon
  if mon.isEgg and not entry then entry = (icons.bySpecies or {})[mon.species] end
  local path = type(entry) == 'table' and entry.image or entry
  if type(path) ~= 'string' then return nil end
  if self.cache[path] == nil then
    local ok, img = pcall(Assets.image, path); self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter('nearest','nearest') end
  end
  return self.cache[path] or nil, type(entry) == 'table' and entry.frameHeight or icons.frameHeight or 32
end

function Gen4Poketch:drawMonIcon(mon, x, y, opts)
  if not mon then return end
  opts = opts or {}
  local image, frameH = self:iconImage(mon)
  if not image then return end
  local g = love.graphics
  local w, h = image:getDimensions()
  local seq = opts.seq or 4
  self.spriteClock = self.spriteClock or {}
  local id = opts.id or ('icon' .. tostring(mon.species))
  local clock = self.spriteClock[id]
  if not clock or clock.seq ~= seq then clock = { seq = seq, start = self.ticks or 0 }; self.spriteClock[id] = clock end
  local f = self:animFrame('poke_icon', seq, (self.ticks or 0) - clock.start)
  local sx, sy = f.sx or 2, f.sy or 2
  if opts.flip then sx = -sx end
  local frame = math.min(f.cell or 0, math.max(0, math.floor(h / frameH) - 1))
  self.iconQuads = self.iconQuads or {}
  local qk = tostring(image) .. ':' .. frame
  local q = self.iconQuads[qk]
  if not q then q = g.newQuad(0, frame * frameH, w, math.min(h, frameH), w, h); self.iconQuads[qk] = q end
  local sh = g.getShader and lumShader()
  local prev = sh and g.getShader()
  if sh then
    pcall(sh.send, sh, 'shades', { LCD[1][1] / 255, LCD[1][2] / 255, LCD[1][3] / 255 },
      { LCD[8][1] / 255, LCD[8][2] / 255, LCD[8][3] / 255 }, { LCD[15][1] / 255, LCD[15][2] / 255, LCD[15][3] / 255 },
      { LCD[4][1] / 255, LCD[4][2] / 255, LCD[4][3] / 255 })
    local solid = opts.solid and LCD[opts.solid]
    pcall(sh.send, sh, 'solid', solid and 1 or 0)
    pcall(sh.send, sh, 'solidColour', solid and { solid[1] / 255, solid[2] / 255, solid[3] / 255 } or { 0, 0, 0 })
    g.setShader(sh)
  end
  g.setColor(1, 1, 1, 1)
  g.draw(image, q, x, y + (opts.offsetY or 0), 0, sx, sy, w / 2, math.min(h, frameH) / 2)
  if sh then g.setShader(prev) end
  return true
end

-- --------------------------------------------------- friendship checker --
--
-- friendship_checker/graphics.c, run as it is: the party's icons (sequence 6,
-- or 7 facing right) wander the LCD at one pixel a tick, bounce off the edges
-- (-10, 217, -22, 183) and off each other (radius 16), gather round a held
-- touch within 48 pixels or flee it if they dislike you, and show hearts
-- (sequences 0-2 by how much they like you) when the touch is on them. A
-- double tap makes them all jump (a 20-pixel sine hop under a shadow,
-- sequence 3). Friendship tiers: <1, <35, <70 dislike (3, 2, 1), <150
-- neutral, <200, <255, 255 like (1, 2, 3).

local FC_LIKE, FC_NEUTRAL, FC_HATE = 0, 2, 1
local FC_START = { { 48, 44 }, { 176, 44 }, { 48, 92 }, { 176, 92 }, { 48, 140 }, { 176, 140 } }

local function friendshipLevel(f)
  local tiers = { 1, 35, 70, 150, 200, 255 }
  for i, t in ipairs(tiers) do if f < t then return i - 1 end end
  return 6
end

local function unit(x, y)
  local m = math.sqrt(x * x + y * y)
  if m == 0 then return 0, 0 end
  return x / m, y / m
end

function Gen4Poketch:friendshipState()
  self.appState = self.appState or {}
  local fc = self.appState.friendship
  if fc then return fc end
  fc = { mons = {}, tap = 'idle', tapT = 0 }
  local rng = love.math and love.math.random or math.random
  for _, mon in ipairs((self.game.save or {}).party or {}) do
    if not mon.isEgg and #fc.mons < 6 then
      local level = friendshipLevel(tonumber(mon.friendship or mon.happiness) or 0)
      local kind, intensity = FC_NEUTRAL, 0
      if level <= 2 then kind, intensity = FC_HATE, 3 - level
      elseif level >= 4 then kind, intensity = FC_LIKE, level - 3 end
      local at = FC_START[#fc.mons + 1]
      local vx, vy = unit(rng(0, 63) - 32, rng(0, 63) - 32)
      fc.mons[#fc.mons + 1] = { species = mon.species, mon = mon, kind = kind, intensity = intensity,
        x = at[1], y = at[2], vx = vx / 16, vy = vy / 16, action = 'wander', cooldown = 0,
        offset = 0, jump = 0 }
    end
  end
  self.appState.friendship = fc
  return fc
end

function Gen4Poketch:friendshipMonAt(x, y)
  local fc = self:friendshipState()
  for i, m in ipairs(fc.mons) do
    if (x - m.x) ^ 2 + (y - m.y) ^ 2 < 16 * 16 then return i end
  end
end

local function near(x, y, d, m) return (x - m.x) ^ 2 + (y - m.y) ^ 2 < d * d end
local SPEED = { [0] = 100, 150, 175, 200 }

function Gen4Poketch:updateFriendship()
  local fc = self:friendshipState()
  local held = self.held
  local tx, ty = held and held.x, held and (held.y - 8)
  local touched = held and self:friendshipMonAt(tx, ty)
  -- the tap state machine: a double tap off the icons makes everyone jump
  local tapped = fc.tapped; fc.tapped = false
  if fc.tap == 'idle' then
    if tapped then fc.tapOnMon = touched ~= nil; fc.tap, fc.tapT = 'first', 0 end
  elseif fc.tap == 'first' then
    if held then fc.tapT = fc.tapT + 1; if fc.tapT > 6 then fc.tap = 'long' end
    else fc.tap, fc.tapT = fc.tapOnMon and 'idle' or 'released', 0 end
  elseif fc.tap == 'long' then
    if not held then fc.tap = 'idle' end
  elseif fc.tap == 'released' then
    if not tapped then fc.tapT = fc.tapT + 1; if fc.tapT > 6 then fc.tap = 'idle' end
    elseif touched then fc.tapOnMon, fc.tap, fc.tapT = true, 'first', 0
    else
      fc.tap = 'jump'
      for _, m in ipairs(fc.mons) do m.action, m.jump, m.jumpPhase, m.cooldown = 'jump', 0, 0, 0 end
      fc.jumping = #fc.mons
    end
  elseif fc.tap == 'jump' then
    if (fc.jumping or 0) <= 0 then fc.tap = 'idle' end
  end
  local function setAction(m, a) m.action = a; m.offset = 0 end
  local rng = love.math and love.math.random or math.random
  for i, m in ipairs(fc.mons) do
    if m.cooldown > 0 then m.cooldown = m.cooldown - 1
    elseif m.action == 'wander' then
      if not held then
        local sp = math.sqrt(m.vx ^ 2 + m.vy ^ 2)
        if sp > 768 / 4096 then local k = sp * 0.96; local ux, uy = unit(m.vx, m.vy); m.vx, m.vy = ux * k, uy * k end
      elseif not touched then
        if near(tx, ty, 48, m) then setAction(m, m.kind ~= FC_HATE and 'gather' or 'flee') end
      elseif touched == i and near(tx, ty, 8, m) then
        setAction(m, m.kind ~= FC_HATE and 'like' or 'dislike')
      end
    end
    if m.cooldown == 0 then
      if m.action == 'gather' or m.action == 'flee' then
        if held and near(tx, ty, 64, m) then
          if m.action == 'gather' and (not touched or touched == i) and near(tx, ty, 8, m) then
            setAction(m, 'like')
          elseif m.action == 'flee' or not touched or touched == i then
            local ux, uy = unit(tx - m.x, ty - m.y)
            if m.action == 'flee' then ux, uy = -ux, -uy end
            local k = SPEED[m.intensity] / 100 / 16
            m.vx, m.vy = ux * k, uy * k
          end
        else setAction(m, 'wander') end
      elseif m.action == 'like' then
        if held and near(tx, ty, 8, m) then
          local dx, dy = tx - m.x, ty - m.y
          if math.sqrt(dx * dx + dy * dy) > 0.375 then dx, dy = 0, 0 end
          m.vx, m.vy = dx / 16, dy / 16
        elseif held and near(tx, ty, 64, m) then setAction(m, 'gather')
        else setAction(m, 'wander') end
      elseif m.action == 'dislike' then
        if held and near(tx, ty, 8, m) then m.vx, m.vy = 0, 0
        elseif held and near(tx, ty, 64, m) then setAction(m, 'flee')
        else
          if m.vx == 0 and m.vy == 0 then local ux, uy = unit(rng(0, 63) - 32, rng(0, 63) - 32); m.vx, m.vy = ux / 16, uy / 16 end
          setAction(m, 'wander')
        end
      elseif m.action == 'jump' then
        if m.jump == 0 then m.vx, m.vy = 0, 0 end
        m.jump = m.jump + 8
        if (m.jumpPhase or 0) == 0 and m.jump > 140 then m.jumpPhase = 1 end
        if m.jump > 180 then
          m.jump = 180
          local ux, uy = unit(rng(0, 63) - 32, rng(0, 63) - 32); m.vx, m.vy = ux / 16, uy / 16
          setAction(m, 'wander'); fc.jumping = (fc.jumping or 1) - 1
        end
        m.offset = -20 * math.sin(math.rad(m.jump))
      end
    end
  end
  if fc.tap ~= 'jump' then
    -- 16 time steps a tick, the earliest collision first (UpdateIconPositions)
    local remaining = 16
    for _ = 1, 32 do
      if remaining <= 0 then break end
      local used, hit = remaining, nil
      for i, m in ipairs(fc.mons) do
        local nx, ny = m.x + m.vx * used, m.y + m.vy * used
        local function edge(p, lim, v, kind)
          if v ~= 0 then
            local t = used - (p - lim) / v
            if t < used then used, hit = t, { kind = kind, a = i } end
          end
        end
        if nx < -10 then edge(nx, -10, m.vx, 'x') end
        if nx > 217 then edge(nx, 217, m.vx, 'x') end
        if ny < -22 then edge(ny, -22, m.vy, 'y') end
        if ny > 183 then edge(ny, 183, m.vy, 'y') end
      end
      for j = 1, #fc.mons do
        for i = 1, j - 1 do
          local a, b = fc.mons[i], fc.mons[j]
          local dx = (a.x + a.vx * used) - (b.x + b.vx * used)
          local dy = (a.y + a.vy * used) - (b.y + b.vy * used)
          local d = math.sqrt(dx * dx + dy * dy)
          if d < 32 then
            local nx, ny = unit(dx, dy)
            local closing = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
            if closing < 0 then
              local t = used - (32 - d) / -closing
              if t < used then used, hit = t, { kind = 'pair', a = i, b = j } end
            end
          end
        end
      end
      if used <= 0 then break end
      for _, m in ipairs(fc.mons) do m.x, m.y = m.x + m.vx * used, m.y + m.vy * used end
      if hit then
        if hit.kind == 'x' then fc.mons[hit.a].vx = -fc.mons[hit.a].vx
        elseif hit.kind == 'y' then fc.mons[hit.a].vy = -fc.mons[hit.a].vy
        else
          local a, b = fc.mons[hit.a], fc.mons[hit.b]
          local function bump(still, other)
            if (still.vx == 0 and still.vy == 0) or still.bumped then
              local ux, uy = unit(still.x - other.x, still.y - other.y)
              still.vx, still.vy, still.bumped = ux * 0.1, uy * 0.1, true
            else still.vx, still.vy = -still.vx, -still.vy end
            still.cooldown = 20
          end
          if a.action == 'like' then bump(b, a)
          elseif b.action == 'like' then bump(a, b)
          else
            local nx, ny = unit(a.x - b.x, a.y - b.y)
            local closing = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
            a.vx, a.vy = a.vx - closing * nx, a.vy - closing * ny
            b.vx, b.vy = b.vx + closing * nx, b.vy + closing * ny
            a.cooldown, b.cooldown, a.bumped, b.bumped = 20, 20, false, false
          end
        end
      end
      remaining = remaining - used
      if not hit then break end
    end
  end
end

function Gen4Poketch:drawFriendship()
  local fc = self:friendshipState()
  local fill = {}
  for i = 1, 32 * 24 do fill[i] = 0 end
  self:drawTiles('generic', fill, 32, 0, 0)
  for i, m in ipairs(fc.mons) do
    if m.action == 'jump' and (m.jumpPhase or 0) == 0 then
      self:sprite('fcshadow' .. i, 'friendship_checker', 3, m.x, m.y + 8)
    end
  end
  for i, m in ipairs(fc.mons) do
    local right = m.vx > 0
    self:drawMonIcon(m.mon, m.x, m.y + (m.offset or 0), { seq = right and 7 or 6, id = 'fc' .. i })
  end
  for i, m in ipairs(fc.mons) do
    if m.action == 'like' and m.kind == FC_LIKE and m.intensity > 0 then
      self:sprite('fcheart' .. i, 'friendship_checker', m.intensity - 1, m.x, m.y + 8)
    end
  end
end

-- ---------------------------------------------------- day-care checker --
--
-- daycare_checker: the two Pokemon's icons (sequence 7 -- or 6 if the species
-- faces the other way -- at (56, 128); 6 at (168, 128)), an egg's (4) at
-- (112, 136) once there is one, and each one's level in OBJ digits at
-- (48..80, 40) and (152..184, 40) with leading zeroes hidden, its gender
-- (10 male, 11 female, 12 none) at (96, 40) and (200, 40).
function Gen4Poketch:daycareMons()
  local dc = (self.game.save or {}).daycare or {}
  local breed = dc.breed or {}
  local mons = {}
  for i = 1, 2 do if breed[i] and breed[i].mon then mons[#mons + 1] = breed[i].mon end end
  if #mons == 0 and dc.mon then mons[1] = dc.mon end
  return mons, breed.egg or dc.egg
end

function Gen4Poketch:drawDaycare()
  local mons, egg = self:daycareMons()
  local spots = { { 56, 128, 7, 48, 96 }, { 168, 128, 6, 152, 200 } }
  for i, mon in ipairs(mons) do
    local at = spots[i]
    self:drawMonIcon(mon, at[1], at[2], { seq = at[3], id = 'dc' .. i })
    local level = math.max(1, math.min(100, tonumber(mon.level) or 1))
    local d = { math.floor(level / 100), math.floor(level / 10) % 10, level % 10 }
    for k = 1, 3 do
      if (k == 1 and level >= 100) or (k == 2 and level >= 10) or k == 3 then
        self:sprite('dclv' .. i .. k, 'daycare_checker', d[k], at[4] + (k - 1) * 16, 40)
      end
    end
    local gender = mon.gender
    local seq = (gender == 'male' or gender == 0) and 10 or (gender == 'female' or gender == 1) and 11 or 12
    self:sprite('dcg' .. i, 'daycare_checker', seq, at[5], 40)
  end
  if egg then self:drawMonIcon({ species = 'EGG', isEgg = true }, 112, 136, { seq = 4, id = 'dcegg' }) end
end

-- ----------------------------------------------------- Pokemon history --
--
-- pokemon_history: tile 0 filled with colour 4, "OBTAINED POKéMON"
-- (TEXT_BANK_POKETCH_POKEMON_HISTORY) centred in a 24 x 2 window at (2, 2),
-- and up to twelve icons (sequence 4) at (48 + 40c, 48 + 48r).
function Gen4Poketch:drawHistory()
  lcd(4); love.graphics.rectangle('fill', FACE.x, FACE.y, FACE.w, FACE.h)
  local title = self:textBank(458, 0, 'OBTAINED POKéMON')
  self:lcdText(title, 16 + math.floor((192 - self:lcdTextWidth(title)) / 2), 16)
  local history = self:store().history or {}
  for i = math.min(12, #history), 1, -1 do
    local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
    self:drawMonIcon(history[i], 48 + 40 * c, 48 + 48 * r, { seq = 4, id = 'hist' .. i })
  end
end

-- ------------------------------------------------------ dowsing machine --
--
-- dowsing_machine: a tap pings (sequence 0, the rings from the touch); a
-- faint signal pings again and again; a hit shows each item in range
-- (sequence 1 + its range, at most 3) after each ping. Cells 6 and 7 are
-- drawn in OBJ rows 13 and 14: the theme's row with colour 1 replaced by 8
-- and by 15 -- the importer bakes that in.
function Gen4Poketch:startDowsing(x,y)
  self.dowsingResult=require('src.pokemon.Gen4PoketchState').dowsing(self.game,x,y)
  self.dowsingStart = self.ticks or 0
  self.spriteClock = self.spriteClock or {}
  self.spriteClock.radar, self.spriteClock.items = nil, nil
end

local PING_FRAMES = 36

function Gen4Poketch:drawDowsing()
  local result = self.dowsingResult
  if not (result and self.dowsingStart) then return end
  local t = (self.ticks or 0) - self.dowsingStart
  if result.kind == 0 then
    if t < PING_FRAMES then self:drawCell('dowsing_machine', self:animFrame('dowsing_machine', 0, t).cell, result.x, result.y) end
    return
  end
  if result.kind == 1 then
    self:drawCell('dowsing_machine', self:animFrame('dowsing_machine', 0, t % PING_FRAMES).cell, result.x, result.y)
    return
  end
  local cycle = PING_FRAMES + 61
  local within = t % cycle
  if within < PING_FRAMES then
    self:drawCell('dowsing_machine', self:animFrame('dowsing_machine', 0, within).cell, result.x, result.y)
  else
    for _, item in ipairs(result.items or {}) do
      local seq = math.min(3, 1 + (item.range or 0))
      self:drawCell('dowsing_machine', self:animFrame('dowsing_machine', seq, within - PING_FRAMES).cell, item.x, item.y)
    end
  end
end

-- -------------------------------------------------------------- roulette --
--
-- roulette: a drawing window like the memo pad's (BG3 at (2, 2), behind the
-- board), the arrow (sequence 0, affine) at (96, 96), and START (187, 50),
-- STOP (187, 96), CLEAR (187, 142) -- sequences 1/2, 3/4, 5/6, the even one
-- pressed. START spins the arrow up by 336 a tick to 12288; STOP caps it at
-- 6656 and lets it run down by 80 a tick (angles in 65536ths of a turn).
-- Drawing: 2x2 pixels of colour 1 inside 156 x 150 from (16, 16).
local ROUL_BUTTONS = { { 167, 34, 207, 66 }, { 167, 80, 207, 112 }, { 167, 126, 207, 158 } }

function Gen4Poketch:rouletteState()
  self.appState = self.appState or {}
  local r = self.appState.roulette
  if not r then
    local s = self:store()
    s.roulette = s.roulette or 0
    r = { phase = 'idle', angle = s.roulette * 65536 / 360, speed = 0 }
    self.appState.roulette = r
  end
  return r
end

function Gen4Poketch:rouletteButton(which)
  local r, s = self:rouletteState(), self:store()
  if which == 1 and r.phase == 'idle' then
    r.phase, r.speed = 'spinup', 336; r.angle = r.angle + 336
  elseif which == 2 and (r.phase == 'spin' or r.phase == 'spinup') then
    r.phase = 'stopping'; if r.speed > 6656 then r.speed = 6656 end
  elseif which == 3 and r.phase == 'idle' then
    r.clearArmed = true
  end
  s.roulette = (r.angle * 360 / 65536) % 360
end

function Gen4Poketch:rouletteTouch(x, y)
  for i, b in ipairs(ROUL_BUTTONS) do
    if inRect(x, y, b[1], b[2], b[3], b[4]) then self:rouletteState().pressed = i; return self:rouletteButton(i) end
  end
  self:rouletteDraw(x, y)
end

function Gen4Poketch:rouletteRelease()
  local r = self:rouletteState()
  if r.clearArmed and r.pressed == 3 and not (self.held and self.held.moved) then self:store().rouletteDots = {} end
  r.clearArmed, r.pressed = nil, nil
end

function Gen4Poketch:rouletteDraw(x, y)
  local r = self:rouletteState()
  if r.phase ~= 'idle' or r.pressed then return end
  if x - 16 >= 155 or y - 16 >= 149 or x < 16 or y < 16 then self.lastRoulette = nil; return end
  local s = self:store()
  s.rouletteDots = s.rouletteDots or {}
  local cx, cy = math.floor((x - 16) / 2), math.floor((y - 16) / 2)
  local last = self.lastRoulette
  if last then
    local steps = math.max(math.abs(cx - last[1]), math.abs(cy - last[2]))
    for k = 1, steps do
      local px = math.floor(last[1] + (cx - last[1]) * k / steps + 0.5)
      local py = math.floor(last[2] + (cy - last[2]) * k / steps + 0.5)
      s.rouletteDots[py * 96 + px] = true
    end
  end
  s.rouletteDots[cy * 96 + cx] = true
  self.lastRoulette = { cx, cy }
end

function Gen4Poketch:updateRoulette()
  local r = self:rouletteState()
  if r.phase == 'spinup' then
    r.angle = r.angle + r.speed; r.speed = r.speed + 336
    if r.speed >= 12288 then r.speed, r.phase = 12288, 'spin' end
  elseif r.phase == 'spin' then
    r.angle = r.angle + r.speed
  elseif r.phase == 'stopping' then
    if r.speed > 80 then r.speed = r.speed - 80; r.angle = r.angle + r.speed
    else r.speed, r.phase = 0, 'idle' end
  end
  r.angle = r.angle % 65536
  self:store().roulette = r.angle * 360 / 65536
end

function Gen4Poketch:drawRouletteWindow()
  lcd(4)
  love.graphics.rectangle('fill', 16, 16, 160, 152)
  lcd(1)
  for index, on in pairs(self:store().rouletteDots or {}) do
    if on then love.graphics.rectangle('fill', 16 + (index % 96) * 2, 16 + math.floor(index / 96) * 2, 2, 2) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawRoulette()
  local r = self:rouletteState()
  self:drawCell('roulette', 0, 96, 96, { rot = -r.angle * 2 * math.pi / 65536 })
  local spinning = r.phase ~= 'idle'
  local p = r.pressed
  self:drawCell('roulette', self:animFrame('roulette', (spinning or p == 1) and 2 or 1, 0).cell, 187, 50)
  self:drawCell('roulette', self:animFrame('roulette', (not spinning or r.phase == 'stopping') and 4 or 3, 0).cell, 187, 96)
  self:drawCell('roulette', self:animFrame('roulette', (spinning or p == 3) and 6 or 5, 0).cell, 187, 142)
end

-- ---------------------------------------------------------- move tester --
--
-- move_tester: the attacking type's name centred in a 6 x 2 window at (6, 15),
-- the defending types' at (16, 4) and (16, 8) ("None" for an empty second
-- type), the verdict (TEXT_BANK_POKETCH_MOVE_TESTER by the number of "!"s)
-- at (3, 19); five "!" sprites at (44 + 8i, 48), lit (4) or not (5); the six
-- arrow buttons (sequence 0 left, 2 right, +1 while pressed).

local TYPE_TEXT = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5, BUG = 6,
  GHOST = 7, STEEL = 8, FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14, ICE = 15,
  DRAGON = 16, DARK = 17 }
local MT_ARROWS = {
  { 16, 112, 40, 144, 1, -1, 28, 128, 0 }, { 104, 112, 128, 144, 1, 1, 116, 128, 2 },
  { 96, 24, 120, 56, 2, -1, 108, 40, 0 }, { 184, 24, 208, 56, 2, 1, 196, 40, 2 },
  { 96, 56, 120, 88, 3, -1, 108, 72, 0 }, { 184, 56, 208, 88, 3, 1, 196, 72, 2 },
}

function Gen4Poketch:moveTesterTouch(x, y)
  local s = self:store()
  s.moveTester = s.moveTester or {1,1,18}
  for i, a in ipairs(MT_ARROWS) do
    if inRect(x, y, a[1], a[2], a[3], a[4]) then
      local slot, delta = a[5], a[6]
      s.moveTester[slot] = (s.moveTester[slot] - 1 + delta) % (slot == 3 and 18 or 17) + 1
      self.appState = self.appState or {}
      self.appState.mtPressed = i
      return
    end
  end
end

function Gen4Poketch:moveEffectiveness()
  local selected = self:store().moveTester or {1,1,18}
  local atk, first, second = TYPES[selected[1]], TYPES[selected[2]], TYPES[selected[3]]
  if second == first then second = nil end
  local result = 1
  for _, row in ipairs((self.game.data.type_chart or {}).matchups or {}) do
    if row.attacker == atk and (row.defender == first or row.defender == second) then
      result = result * row.multiplier / 10
    end
  end
  return result
end

-- GetExclamationCount: 0 for no effect, else 3 + one per doubling.
function Gen4Poketch:moveExclamations()
  local m = self:moveEffectiveness()
  if m == 0 then return 0 end
  return math.max(1, math.min(5, 3 + math.floor(math.log(m) / math.log(2) + 0.5)))
end

function Gen4Poketch:drawMoveTester()
  local selected = self:store().moveTester or {1,1,18}
  local function typeName(i)
    if not TYPES[i] then return self:textBank(456, 6, 'None') end
    return self:textBank(624, TYPE_TEXT[TYPES[i]], TYPES[i])
  end
  local function window(text, tx, ty)
    lcd(4); love.graphics.rectangle('fill', tx * 8, ty * 8, 48, 16)
    self:lcdText(text, tx * 8 + math.floor((48 - self:lcdTextWidth(text)) / 2), ty * 8)
  end
  window(typeName(selected[1]), 6, 15)
  window(typeName(selected[2]), 16, 4)
  window(typeName(selected[3]), 16, 8)
  local n = self:moveExclamations()
  lcd(4); love.graphics.rectangle('fill', 24, 152, 176, 16)
  self:lcdText(self:textBank(456, n, ''), 24, 152)
  for i = 0, 4 do self:drawCell('move_tester', self:animFrame('move_tester', i < n and 4 or 5, 0).cell, 44 + 8 * i, 48) end
  local pressed = self.held and self.appState and self.appState.mtPressed
  for i, a in ipairs(MT_ARROWS) do
    self:drawCell('move_tester', self:animFrame('move_tester', a[9] + (pressed == i and 1 or 0), 0).cell, a[7], a[8])
  end
end

-- ------------------------------------------------------ matchup checker --
--
-- matchup_checker: two party members' icons (left 5 -- 4 if the species faces
-- the other way -- at (48, 140), right 4 at (176, 140)), their Luvdisc (5 and
-- 6 at (48, 88) and (176, 88)), the heart meter (112, 32) and the button
-- (112, 148, sequence 9; 10 while pressed). CHECK runs the command list for
-- the compatibility: the two Luvdisc swim 16 pixels together per 16 ticks,
-- one step for low, two for medium, three and the hearts (7, 8, meter 4) for
-- the best; an incompatible pair meets, turns tail and swims back.

function Gen4Poketch:matchupParty()
  local party = {}
  for _, mon in ipairs((self.game.save or {}).party or {}) do
    if not mon.isEgg then party[#party+1] = mon end
  end
  return party
end

local MATCHUP_LEVEL = { [70] = 0, [50] = 1, [20] = 2, [0] = 3 }
local MATCHUP_SCRIPTS = {
  [3] = { { 'fwd', 16, 16 }, { 'wait', 16 }, { 'flip' }, { 'back', 16, 16 } },
  [2] = { { 'fwd', 16, 16 } },
  [1] = { { 'fwd', 16, 16 }, { 'fwd', 16, 16 } },
  [0] = { { 'fwd', 16, 16 }, { 'fwd', 16, 16 }, { 'fwd', 16, 16 }, { 'wait', 16 },
          { 'set', 'left', 7 }, { 'set', 'right', 8 }, { 'set', 'meter', 4 }, { 'wait', 16 } },
}

function Gen4Poketch:matchupTouch(x, y)
  if y < 128 or y >= 168 then return end
  local party, s = self:matchupParty(), self:store()
  local pair = s.matchup or {1,2}; s.matchup = pair
  if x >= 92 and x < 132 then
    s.compatibility = require('src.pokemon.Gen4PoketchState').compatibility(
      self.game.data, party[pair[1]], party[pair[2]])
    local level = MATCHUP_LEVEL[s.compatibility] or 3
    self.appState = self.appState or {}
    self.appState.matchup = { script = MATCHUP_SCRIPTS[level], pc = 1, offset = 0, timer = 0,
      left = 5, right = 6, meter = ({ [0] = 3, 2, 1, 0 })[level] }
    self.appState.matchupPressed = true
  elseif #party > 2 and (x >= 24 and x < 72 or x >= 152 and x < 200) and y >= 130 and y < 164 then
    local slot = x < 112 and 1 or 2
    repeat pair[slot] = (pair[slot] or slot) % #party + 1
    until pair[slot] ~= pair[3-slot]
    s.compatibility = nil
    if self.appState then self.appState.matchup = nil end
  end
end

function Gen4Poketch:updateMatchup()
  local m = self.appState and self.appState.matchup
  if not m or m.done then return end
  for _ = 1, 16 do
    if m.state == 'move' then
      m.timer = m.timer - 1
      if m.timer > 0 then m.offset = m.offset + m.step else m.offset = m.target end
      if m.timer <= 0 then m.state = nil else return end
    elseif m.state == 'wait' then
      if m.timer > 0 then m.timer = m.timer - 1; return end
      m.state = nil
    end
    local cmd = m.script[m.pc]
    if not cmd then m.done = true; return end
    m.pc = m.pc + 1
    if cmd[1] == 'fwd' or cmd[1] == 'back' then
      local dist = cmd[1] == 'fwd' and cmd[3] or -cmd[3]
      m.state, m.timer, m.target, m.step = 'move', cmd[2], m.offset + dist, dist / cmd[2]
    elseif cmd[1] == 'wait' then m.state, m.timer = 'wait', cmd[2]
    elseif cmd[1] == 'flip' then m.left, m.right = 6, 5
    elseif cmd[1] == 'set' then m[cmd[2]] = cmd[3] end
  end
end

function Gen4Poketch:drawMatchup()
  local party, s = self:matchupParty(), self:store()
  local pair = s.matchup or {1,2}
  local m = self.appState and self.appState.matchup
  self:sprite('meter', 'matchup_checker', m and m.meter or 0, 112, 32)
  local off = m and m.offset or 0
  self:sprite('luvl', 'matchup_checker', m and m.left or 5, 48 + off, 88)
  if party[pair[2]] then self:sprite('luvr', 'matchup_checker', m and m.right or 6, 176 - off, 88) end
  self:sprite('mbutton', 'matchup_checker', (self.held and self.appState and self.appState.matchupPressed) and 10 or 9, 112, 148)
  if party[pair[1]] then self:drawMonIcon(party[pair[1]], 48, 140, { seq = 5, id = 'mul' }) end
  if party[pair[2]] then self:drawMonIcon(party[pair[2]], 176, 140, { seq = 4, id = 'mur' }) end
end

-- -------------------------------------------------------- color changer --

-- The slider: its sprite at (56 + 16 x colour, 148) -- COLOR_SLIDER_LEFT_X,
-- COLOR_SLIDER_WIDTH, COLOR_SLIDER_Y.
function Gen4Poketch:drawColorChanger()
  local c = self:store().color or 0
  self:drawCell('color_changer', 0, 56 + 16 * c, 148)
end

function Gen4Poketch:applyLCDPalette(backlight)
  local g = love.graphics
  local hex = (((self.game.data or {}).gen4_graphics or {}).palettes or {})['poketch/generic']
  if not (hex and g.newShader and g.setShader) then return end
  local G = require('src.import.Gen4Graphics')
  local source = G.slotFromHex(hex, 0)
  local target = G.slotFromHex(hex, (self:store().color or 0) * 2 + (backlight and 1 or 0))
  if not (source and target) then return end
  if not self.lcdShader then
    self.lcdShader = g.newShader([[
      extern vec3 sourceColors[16];
      extern vec3 targetColors[16];
      vec4 effect(vec4 color, Image image, vec2 uv, vec2 screen) {
        vec4 pixel = Texel(image, uv) * color;
        for (int i = 0; i < 16; i++) {
          if (distance(pixel.rgb, sourceColors[i]) < 0.005) {
            pixel.rgb = targetColors[i]; break;
          }
        }
        return pixel;
      }
    ]])
  end
  self.lcdShader:send('sourceColors', unpack(source))
  self.lcdShader:send('targetColors', unpack(target))
  g.setShader(self.lcdShader)
end

-- ------------------------------------------------------ trainer counter --

-- THE TRAINER COUNTER (applications/poketch/trainer_counter): the Poke Radar's
-- chain now running and the three best ever, each a Pokemon icon and a
-- three-digit count with leading zeroes hidden (UpdateChainCountDigits).
-- Icons at (96, 32), (112, 80), (176, 96), (48, 104); their digits from
-- (144, 40), (100, 144), (164, 160), (36, 168), eight pixels apart.
local COUNTER_ICONS = { { 96, 32 }, { 112, 80 }, { 176, 96 }, { 48, 104 } }
local COUNTER_DIGITS = { { 144, 40 }, { 100, 144 }, { 164, 160 }, { 36, 168 } }
Gen4Poketch.COUNTER_ICONS, Gen4Poketch.COUNTER_DIGITS = COUNTER_ICONS, COUNTER_DIGITS

function Gen4Poketch.counterDigits(n)
  n = math.max(0, math.min(999, math.floor(tonumber(n) or 0)))
  local out, started = {}, false
  local div = 100
  for i = 1, 3 do
    local d = math.floor(n / div)
    if started or d ~= 0 or i == 3 then out[i] = d; started = true else out[i] = false end
    n = n - d * div
    div = div / 10
  end
  return out
end

function Gen4Poketch:drawTrainerCounter()
  local rows = {}
  local ow = self.game.overworld
  local chain = ow and ow.gen4Radar
  rows[1] = (chain and chain.active and chain.species ~= 0)
            and { species = chain.species, count = chain.count } or nil
  for i, r in ipairs((self.game.save or {}).gen4RadarRecords or {}) do
    if i <= 3 then rows[i + 1] = r end
  end
  for i = 1, 4 do
    local r = rows[i]
    if r and r.species and r.species ~= 0 then
      self:drawMonIcon({ species = r.species }, COUNTER_ICONS[i][1], COUNTER_ICONS[i][2], { seq = 4, id = 'tc' .. i })
      for k, d in ipairs(Gen4Poketch.counterDigits(r.count)) do
        if d then self:drawCell('trainer_counter', d, COUNTER_DIGITS[i][1] + 8 * (k - 1), COUNTER_DIGITS[i][2]) end
      end
    end
  end
end

-- ------------------------------------------------------- per-frame logic --

function Gen4Poketch:updateApp()
  local name = (self:app() or {}).name
  local tick30 = (self.ticks or 0) % 2 == 0
  if name == 'Stopwatch' then self:updateStopwatch(tick30)
  elseif name == 'Friendship Checker' then if tick30 then self:updateFriendship() end
  elseif name == 'Roulette' then if tick30 then self:updateRoulette() end
  elseif name == 'Matchup Checker' then if tick30 then self:updateMatchup() end
  end
end

local DRAW = {
  ["Digital Watch"] = Gen4Poketch.drawDigitalWatch,
  ["Analog Watch"] = Gen4Poketch.drawAnalogWatch,
  ["Calendar"] = Gen4Poketch.drawCalendar,
  ["Counter"] = Gen4Poketch.drawCounter,
  ["Coin Toss"] = Gen4Poketch.drawCoinToss,
  ["Pedometer"] = Gen4Poketch.drawPedometer,
  ["Pokémon List"] = Gen4Poketch.drawPartyStatus,
  ["Calculator"] = Gen4Poketch.drawCalculator,
  ["Stopwatch"] = Gen4Poketch.drawStopwatch,
  ["Kitchen Timer"] = Gen4Poketch.drawTimer,
  ["Memo Pad"] = Gen4Poketch.drawDoodle,
  ["Dot Artist"] = Gen4Poketch.drawDoodle,
  ["Marking Map"] = Gen4Poketch.drawMarkers,
  ["Roulette"] = Gen4Poketch.drawRoulette,
  ["Friendship Checker"] = Gen4Poketch.drawFriendship,
  ["Day-Care Checker"] = Gen4Poketch.drawDaycare,
  ["Alarm Clock"] = Gen4Poketch.drawAlarm,
  ["Dowsing Machine"] = Gen4Poketch.drawDowsing,
  ["Berry Searcher"] = Gen4Poketch.drawBerrySearcher,
  ["Move Tester"] = Gen4Poketch.drawMoveTester,
  ["Matchup Checker"] = Gen4Poketch.drawMatchup,
  ["Pokémon History"] = Gen4Poketch.drawHistory,
  ["Color Changer"] = Gen4Poketch.drawColorChanger,
  ["Trainer Counter"] = Gen4Poketch.drawTrainerCounter,
}

-- What sits BEHIND an app's own BG2 (a BG3 window the board frames).
local UNDER = {
  ["Memo Pad"] = Gen4Poketch.drawMemoWindow,
  ["Roulette"] = Gen4Poketch.drawRouletteWindow,
}

-- Apps with no tilemap of their own: their whole LCD is drawn above.
local NO_FACE = {
  ["Pokémon List"] = true, ["Friendship Checker"] = true, ["Dot Artist"] = true, ["Pokémon History"] = true,
}

-- ------------------------------------------------------------------- draw --

-- THE SHUTTER (poketch_graphics.c TASK_CONCEAL_SCREEN / TASK_REVEAL_SCREEN_2)
-- on BG1, in the border sheet's tile 164 under the border's palette: closing
-- two tile rows a tick from the top (row 2 down) and the bottom (row 21 up)
-- for five ticks, held shut three (thirty, with the app number up, when the
-- button is pressed again meanwhile), then opening from row 12 outwards
-- three rows a tick. Ticks are 30 Hz, so two frames each.
Gen4Poketch.SHUTTER_FRAMES = 2 * (5 + 3 + 4)

function Gen4Poketch:shutterCover()
  local sh = self.shutter
  if not sh then return nil end
  local tick = math.floor(sh.t / 2)
  local shut = sh.skip and 30 or 3
  if tick < 5 then return 'close', 2 * (tick + 1) end
  if tick < 5 + shut then return 'shut', 10 end
  return 'open', math.min(10, 3 * (tick - 4 - shut))
end

function Gen4Poketch:drawShutter()
  local phase, amount = self:shutterCover()
  if not phase then return end
  local rows = {}
  if phase == 'close' then
    for r = 2, 1 + amount do rows[r] = true end
    for r = 22 - amount, 21 do rows[r] = true end
  elseif phase == 'shut' then
    for r = 2, 21 do rows[r] = true end
  else
    for r = 2, 21 do rows[r] = not (r >= 12 - amount and r < 12 + amount) end
  end
  local line = {}
  for i = 1, 24 do line[i] = 164 end
  for r = 2, 21 do
    if rows[r] and not self:drawTiles('border', line, 24, 2, r) then
      lcd(1); love.graphics.rectangle('fill', 16, r * 8, 192, 8); love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

function Gen4Poketch:drawLCD(app)
  local g = love.graphics
  -- Colour zero is transparent in the extracted BG, revealing the LCD's
  -- backdrop colour (palette entry 0 of the theme -- the lightest shade
  -- shows wherever no BG covers).
  lcd(4)
  g.rectangle('fill', FACE.x, FACE.y, FACE.w, FACE.h)
  g.setColor(1, 1, 1, 1)
  local under = app and UNDER[app.name]
  if under then under(self) end
  local face = app and not NO_FACE[app.name] and app.art and self:img(app.art)
  if face then
    g.setColor(1, 1, 1, 1)
    g.draw(face, 0, 0)
  elseif not (app and DRAW[app.name]) then
    -- Only apps which genuinely have no composed face use the cartridge's
    -- unavailable screen.
    local blank = self:img(self.unavailable)
    if blank then g.setColor(1, 1, 1, 1); g.draw(blank, 0, 0) end
  end
  if app then
    local body = app.name and DRAW[app.name]
    if body then
      body(self)
    elseif not face then
      local label = app.name or Strings("APP")
      Font.draw(label, FACE.x + 8, FACE.y + 8)
      Font.draw(Strings("NOT BUILT YET"), FACE.x + 8, FACE.y + 24)
    end
  end
end

function Gen4Poketch:drawWatch()
  local g = love.graphics
  local app = self:app()
  local oldShader = g.getShader and g.getShader()
  local oldScissor = g.getScissor and { g.getScissor() } or {}
  local sx, sy, ex, ey = FACE.x, FACE.y, FACE.x + FACE.w, FACE.y + FACE.h
  if g.transformPoint then
    sx, sy = g.transformPoint(sx, sy); ex, ey = g.transformPoint(ex, ey)
  end
  g.setScissor(sx, sy, ex - sx, ey - sy)

  -- THE LCD IS COMPOSED FIRST, THEN RECOLOURED AS ONE PICTURE: the apps draw
  -- in theme 0 (their icons and text through shaders of their own), and the
  -- colour changer's theme -- and the watches' backlight -- is applied to the
  -- finished LCD, the way the hardware loads one palette under everything.
  local backlight = self.backlight and app and (app.name == 'Digital Watch' or app.name == 'Analog Watch')
  local shown = app
  local phase = self:shutterCover()
  if self.shutter and phase == 'close' then shown = self.apps[self.shutter.from] or app end
  if g.newCanvas and g.setCanvas and g.getCanvas then
    self.lcdCanvas = self.lcdCanvas or g.newCanvas(W, H)
    local prevCanvas = g.getCanvas()
    g.push('all')
    g.setCanvas(self.lcdCanvas)
    g.origin()
    g.setScissor()
    g.clear(0, 0, 0, 0)
    self:drawLCD(shown)
    self:drawShutter()
    g.pop()
    if prevCanvas then g.setCanvas(prevCanvas) end
    self:applyLCDPalette(backlight)
    g.setColor(1, 1, 1, 1)
    g.draw(self.lcdCanvas, 0, 0)
    if g.setShader then g.setShader(oldShader) end
  else
    self:applyLCDPalette(backlight)
    self:drawLCD(shown)
    if g.setShader then g.setShader(oldShader) end
  end

  g.setScissor(unpack(oldScissor))

  -- SHELL LAST. Platinum composes the Poketch device around the LCD; this
  -- extracted full-screen border contains the bezel and physical app-change
  -- buttons and must mask the edges of every app tilemap.
  local border = self:img(self.border)
  if border then
    g.setColor(1, 1, 1, 1)
    g.draw(border, 0, 0)
  else
    g.setColor(0.10, 0.13, 0.18, 1)
    if g.setLineWidth then g.setLineWidth(2) end
    g.rectangle("line", FACE.x - 2, FACE.y - 2, FACE.w + 4, FACE.h + 4)
    if g.setLineWidth then g.setLineWidth(1) end
  end
  -- the app number while the shutter is shut (TASK_LOAD_APP_COUNTER: two
  -- digits at (176, 40) in the theme's row with 1/4 and 8/15 swapped)
  if self.shutter and phase == 'shut' then
    local n = (tonumber(((self.apps[self.index] or {}).id)) or (self.index - 1)) + 1
    local digits = { math.floor(n / 10) % 10, n % 10 }
    for i, d in ipairs(digits) do self:drawCell('digits_inverse', d, 176 + 16 * (i - 1), 40) end
  end

  g.setColor(1, 1, 1, 1)
end

function Gen4Poketch:draw()
  if SecondScreen.mode(self.game) == "off" then return self:drawWatch() end
  SecondScreen.drawFrame(self.game)
  SecondScreen.draw(self.game, function() self:drawWatch() end)
end

return Gen4Poketch
