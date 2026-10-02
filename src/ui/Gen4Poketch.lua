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

function Gen4Poketch:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4Poketch:cycle(delta)
  self.activeMapMarker=nil
  local count = #self.apps
  if count == 0 then return end
  local index=self.index
  for _=1,count do
    index=(index-1+delta)%count+1
    if self:isRegistered(index) then
      self.index=index
      self:store().app=index
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
  self.elapsed = (self.elapsed or 0) + (dt or 1 / 60)
  if self.scan then self.scan = math.max(0, self.scan - 1) end
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
    if (s.timer or 0) <= 0 then s.timer = s.timerDuration or 60 end
    s.timerRunning = not s.timerRunning; s.timerFinished = false
  elseif name == "Roulette" then s.roulette = love.math.random(0, 359)
  elseif name == "Color Changer" then s.color = ((s.color or 0) + 1) % 8
  elseif name == "Dowsing Machine" then self:startDowsing(112,101)
  elseif name == "Alarm Clock" then s.alarmEnabled = not s.alarmEnabled
  end
end

local CALC_KEYS = { { '7', '8', '9', 'C' }, { '4', '5', '6', '+', '-' },
                    { '1', '2', '3', '*', '/' }, { '0', '.', '=' } }

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

function Gen4Poketch:touchpressed(id, px, py)
  local x, y = SecondScreen.toLocal(self.game, px, py)
  if not x then return false end
  if self.pointer~=nil then return true end
  self.pointer = id
  if x >= 224 and y >= 32 and y < 160 then self:cycle(y < 96 and -1 or 1); return true end
  if x < FACE.x or x >= FACE.x + FACE.w or y < FACE.y or y >= FACE.y + FACE.h then return true end
  local name = (self:app() or {}).name
  local s = self:store()
  if name == 'Calculator' then
    local row = math.floor((y - 48) / 32) + 1
    local col = math.floor((x - 32) / 32) + 1
    if row == 4 then col = x < 96 and 1 or x < 128 and 2 or 3 end
    local key = CALC_KEYS[row] and CALC_KEYS[row][col]
    if key then self:calculate(key) end
  elseif name=='Memo Pad' and y>=144 then
    if x>=152 then s.memo={}
    elseif x>=80 then s.memoErasing=not s.memoErasing end
  elseif name == 'Memo Pad' or name == 'Dot Artist' then
    self:doodle(x, y)
  elseif name == 'Calendar' then
    local col, row = math.floor((x - FACE.x - 12) / 20), math.floor((y - FACE.y - 22) / 14)
    local now = os.date('*t')
    local first = ((now.wday - 1) - (now.day - 1) % 7) % 7
    local day = row * 7 + col - first + 1
    local days = os.date('*t', os.time({year = now.year, month = now.month + 1, day = 1, hour = 12}) - 86400).day
    if col >= 0 and col < 7 and row >= 0 and day >= 1 and day <= days then
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
  elseif name == 'Pedometer' and x >= 80 and x < 148 and y >= 104 and y < 152 then s.steps = 0
  elseif name=='Counter' then
    if x>=80 and x<148 and y>=104 and y<152 then self:activate() end
  elseif name == 'Stopwatch' then
    if y>=136 and y<160 then s.stopwatch=0; s.stopwatchRunning=false
    elseif y>=104 and y<128 then self:activate() end
  elseif name == 'Kitchen Timer' then
    if not s.timerRunning and y>=88 and y<128 then
      s.timerDuration=((s.timerDuration or 60)+(x<112 and 60 or 1))%6000; s.timer=s.timerDuration
    elseif y>=136 and y<168 then self:activate() end
  elseif name == 'Alarm Clock' and y>=96 and y<128 then
    if x < 112 then s.alarmHour = ((s.alarmHour or 0) + 1) % 24
    else s.alarmMinute = ((s.alarmMinute or 0) + 1) % 60 end
  elseif name == 'Move Tester' then
    s.moveTester = s.moveTester or {1,1,18}
    local slot,delta
    if y>=112 and y<144 then
      if x<40 then slot,delta=1,-1 elseif x>=104 and x<128 then slot,delta=1,1 end
    elseif y>=24 and y<88 then
      slot=y<56 and 2 or 3
      if x>=96 and x<120 then delta=-1 elseif x>=184 then delta=1 end
    end
    if slot and delta then s.moveTester[slot]=(s.moveTester[slot]-1+delta)%(slot==3 and 18 or 17)+1 end
  elseif name == 'Color Changer' and x >= 48 and x < 184 and y >= 136 and y < 160 then
    s.color = math.min(7, math.floor((x - 48) / 17))
  elseif name == 'Matchup Checker' then self:matchupTouch(x, y)
  elseif name == 'Dowsing Machine' then
    if x>=24 and x<200 and y>=24 and y<168 then self:startDowsing(x,y) end
  elseif name=='Pokémon List' or name=='Pokémon History' or name=='Friendship Checker' then
    local index
    if name~='Pokémon History' then
      local ox,oy,cw=name=='Friendship Checker' and 24 or 32,name=='Friendship Checker' and 28 or 32,
        name=='Friendship Checker' and 92 or 96
      local col,row=math.floor((x-ox)/cw),math.floor((y-oy)/48)
      if col>=0 and col<2 and row>=0 and row<3 then index=row*2+col+1 end
    else
      local col,row=math.floor((x-24)/44),math.floor((y-24)/48)
      if col>=0 and col<4 and row>=0 and row<3 then index=row*4+col+1 end
    end
    local mon=index and (name~='Pokémon History' and (self.game.save.party or {}) or (s.history or {}))[index]
    if mon and not mon.isEgg then
      require('src.core.Sound').playCry(self.game.data,mon.species)
      if name=='Friendship Checker' then self.friendshipTouch={slot=index,frames=60} end
    end
  else self:activate() end
  return true
end

function Gen4Poketch:doodle(x, y)
  if x < FACE.x or x >= FACE.x + FACE.w or y < FACE.y or y >= FACE.y + FACE.h then return end
  local s = self:store(); local name = (self:app() or {}).name
  if name=='Memo Pad' and y>=144 then return end
  local key = name == 'Dot Artist' and 'dots' or 'memo'
  s[key] = s[key] or {}
  local cell = name == 'Dot Artist' and 8 or 2
  local index = math.floor((y - FACE.y) / cell) * 96 + math.floor((x - FACE.x) / cell)
  if name == 'Dot Artist' then
    if self.lastDot ~= index then
      local old = s[key][index]
      s[key][index] = ((type(old) == 'number' and old or 0) + 1) % 4
      self.lastDot = index
    end
  else s[key][index] = not s.memoErasing and true or nil end
end

function Gen4Poketch:touchmoved(id, px, py)
  if self.pointer ~= id then return false end
  local x, y = SecondScreen.toLocal(self.game, px, py)
  local name = (self:app() or {}).name
  if x and name=='Marking Map' and self.activeMapMarker then
    local markers=self:mapMarkers()
    local marker=markers[self.activeMapMarker]
    marker.x=math.max(24,math.min(200,x)); marker.y=math.max(24,math.min(168,y))
  end
  if x and (name == 'Memo Pad' or name == 'Dot Artist') then self:doodle(x, y) end
  if x and name == 'Color Changer' and x >= 48 and x < 184 and y >= 136 and y < 160 then
    self:store().color = math.min(7, math.floor((x - 48) / 17))
  end
  return true
end

function Gen4Poketch:touchreleased(id)
  if self.pointer ~= id then return false end
  self.pointer, self.lastDot, self.activeMapMarker = nil, nil, nil; return true
end

-- ------------------------------------------------------------------ apps --

local function clockNow()
  local ok, t = pcall(os.date, "*t")
  if ok and type(t) == "table" then return t end
  return { hour = 0, min = 0, day = 1, month = 1, year = 2000, wday = 1 }
end

function Gen4Poketch:drawDigit(value, x, y)
  local image = self:img(("poketch/digits_%02d"):format(value % 10))
  if image then
    local iw, ih = image:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x, y, 0, DIGIT.w / iw, DIGIT.h / ih)
    return
  end
  Font.draw(tostring(value % 10), x + 6, y + 10)
end

function Gen4Poketch:drawDigitalWatch()
  local now = clockNow()
  local x = DIGIT.x
  for _, value in ipairs({ math.floor(now.hour / 10), now.hour % 10 }) do
    self:drawDigit(value, x, DIGIT.y)
    x = x + DIGIT.w + DIGIT.gap
  end
  -- The colon blinks once a second on hardware; the frame clock is what this
  -- port has, so it blinks on the half-second of a sixty-frame cycle.
  if self.flash < 30 then
    Font.draw(":", x + 2, DIGIT.y + 10)
  end
  x = x + DIGIT.colon
  for _, value in ipairs({ math.floor(now.min / 10), now.min % 10 }) do
    self:drawDigit(value, x, DIGIT.y)
    x = x + DIGIT.w + DIGIT.gap
  end
end

function Gen4Poketch:drawAnalogWatch()
  local g = love.graphics
  local now = clockNow()
  local cx, cy = FACE.x + FACE.w / 2, FACE.y + FACE.h / 2
  local radius = math.min(FACE.w, FACE.h) / 2 - 8
  g.setColor(0.18, 0.22, 0.18, 1)
  for tick = 0, 11 do
    local a = tick * math.pi / 6
    g.rectangle("fill", cx + math.sin(a) * radius - 1,
                cy - math.cos(a) * radius - 1, 2, 2)
  end
  -- The minute hand from the minute, and the hour hand from BOTH -- an hour
  -- hand that jumps on the hour instead of creeping is the tell that it was
  -- drawn from the hour alone.
  local minuteAngle = (now.min / 60) * math.pi * 2
  local hourAngle = ((now.hour % 12) / 12 + now.min / 720) * math.pi * 2
  g.setLineWidth(2)
  g.line(cx, cy, cx + math.sin(hourAngle) * radius * 0.55,
         cy - math.cos(hourAngle) * radius * 0.55)
  g.setLineWidth(1)
  g.line(cx, cy, cx + math.sin(minuteAngle) * radius * 0.85,
         cy - math.cos(minuteAngle) * radius * 0.85)
  g.setColor(1, 1, 1, 1)
end

local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                 "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

function Gen4Poketch:drawCalendar()
  local g = love.graphics
  local now = clockNow()
  local month = math.max(1, math.min(12, now.month or 1))
  centered(("%s %d"):format(MONTHS[month], now.year or 0),112,20,176)

  -- Which weekday the first of the month falls on, from the weekday of today
  -- and today's date -- no calendar arithmetic of this port's own, because
  -- `os.date` already knows and a hand-rolled day-of-week is a bug waiting for
  -- a leap year.
  local firstCol = ((now.wday or 1) - 1 - ((now.day or 1) - 1) % 7) % 7
  local daysIn = os.date("*t", os.time({ year = now.year, month = month + 1,
                                         day = 1, hour = 12 }) - 86400).day

  local cw, ch = 20, 14
  local ox, oy = FACE.x + 12, FACE.y + 22
  for day = 1, daysIn do
    local cell = firstCol + day - 1
    local col, row = cell % 7, math.floor(cell / 7)
    local x, y = ox + col * cw, oy + row * ch
    local marked = (self:store().calendar or {})[('%04d-%02d-%02d'):format(now.year, month, day)]
    if day == now.day or marked then
      g.setColor(0.98, 0.83, 0.30, 0.8)
      g.rectangle("fill", x - 1, y - 1, cw - 2, ch - 2)
      g.setColor(1, 1, 1, 1)
    end
    Font.draw(tostring(day), x + (day < 10 and 5 or 1), y)
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawCount(value, count, firstX, button)
  local g = love.graphics
  value = math.max(0, math.min(10 ^ count - 1, math.floor(value or 0)))
  for i = 0, count - 1 do
    local digit = math.floor(value / 10 ^ (count - 1 - i)) % 10
    local image = self:img(("poketch/digits_%02d"):format(digit))
    if image then
      g.setColor(1, 1, 1, 1)
      g.draw(image, firstX + i * 16 - image:getWidth() / 2, 64 - image:getHeight() / 2)
    else Font.draw(tostring(digit), firstX + i * 16 - 4, 56) end
  end
  local reset = self:img('poketch/' .. button .. '_sprite_00')
  if reset then
    g.setColor(1, 1, 1, 1)
    g.draw(reset, 114 - reset:getWidth() / 2, 128 - reset:getHeight() / 2)
  end
end

function Gen4Poketch:drawCounter()
  self:drawCount(self:store().counter, 4, 88, 'counter')
end

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

function Gen4Poketch:drawCoinToss()
  local face = self:store().coin
  local coin=(self.game.data.constants or {}).gen4PoketchCoin
  local cell=coin and coin[face=='tails' and 'tails' or 'heads'] or (face=='tails' and 1 or 0)
  local a=self.coinAnimation
  if a and coin then cell=require('src.import.Gen4PoketchSprites').spinCell(coin.spin,a.ticks) or cell end
  local sprite = self:img(('poketch/coin_toss_sprite_%02d'):format(cell))
  if sprite then
    local w, h = sprite:getDimensions()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(sprite,112-w/2,(a and a.y or 144)-h/2)
    return
  end
  local label = (face == "heads") and Strings("HEADS")
    or (face == "tails") and Strings("TAILS") or Strings("A TO TOSS")
  local width = Font.width(label)
  Font.draw(label, FACE.x + math.floor((FACE.w - width) / 2),
            FACE.y + FACE.h / 2 - 6)
end

function Gen4Poketch:drawCalculator()
  local text=(self:store().calculator or {}).display or '0'
  love.graphics.setColor(115/255,181/255,115/255,1)
  love.graphics.rectangle('fill',40,24,152,16)
  love.graphics.setColor(1,1,1,1)
  Font.draw(text,192-Font.width(text),24)
end

function Gen4Poketch:drawStopwatch()
  local t = math.floor((self:store().stopwatch or 0) * 100)
  centered(('%02d:%02d.%02d'):format(math.floor(t / 6000) % 100, math.floor(t / 100) % 60, t % 100),112,40,176)
  centered(self:store().stopwatchRunning and 'STOP' or 'START',112,112,160)
  centered('RESET',112,144,160)
end

function Gen4Poketch:drawTimer()
  local t = math.ceil(self:store().timer or self:store().timerDuration or 60)
  centered(('%02d:%02d'):format(math.floor(t / 60), t % 60),112,96,160)
  centered(self:store().timerFinished and 'TIME UP' or self:store().timerRunning and 'STOP' or 'START',112,144,160)
end

function Gen4Poketch:drawDoodle()
  local dot = (self:app() or {}).name == 'Dot Artist'
  local cell = dot and 8 or 2
  love.graphics.setColor(16 / 255, 41 / 255, 25 / 255, 1)
  for index, value in pairs(self:store()[dot and 'dots' or 'memo'] or {}) do
    if dot then
      local shades = { {115,181,115}, {82,140,82}, {49,99,49}, {16,41,25} }
      local c = shades[(type(value) == 'number' and value or 3) + 1]
      love.graphics.setColor(c[1]/255, c[2]/255, c[3]/255, 1)
    end
    love.graphics.rectangle('fill', FACE.x + index % 96 * cell, FACE.y + math.floor(index / 96) * cell, cell, cell)
  end
  if not dot then
    love.graphics.setColor(115/255,181/255,115/255,1)
    love.graphics.rectangle('fill',16,144,192,32)
    love.graphics.setColor(1,1,1,1)
    centered(self:store().memoErasing and 'DRAW' or 'ERASE',112,152,64)
    centered('CLEAR',176,152,48)
  end
  love.graphics.setColor(1, 1, 1, 1)
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

function Gen4Poketch:drawMapCell(cell,x,y)
  local sprite=cell and self:img(('poketch/map_%02d'):format(cell))
  if not sprite then return false end
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(sprite,x-sprite:getWidth()/2,y-sprite:getHeight()/2)
  return true
end

function Gen4Poketch:drawMarkers()
  local cells=(self.game.data.constants or {}).gen4PoketchMapCells or {}
  love.graphics.setColor(16 / 255, 41 / 255, 25 / 255, 1)
  for _,at in ipairs(require('src.import.Gen4PoketchMap').roamers(self.game)) do
    if not self:drawMapCell(cells.roamer,at.x,at.y) then love.graphics.circle('line',at.x,at.y,3) end
  end
  local markers,order=self:mapMarkers()
  for _,index in ipairs(order) do
    local marker=markers[index]
    local list=index==self.activeMapMarker and cells.markerBig or cells.markers
    if not self:drawMapCell(list and list[index],marker.x,marker.y) then
      love.graphics.setColor(16/255,41/255,25/255,1)
      love.graphics.rectangle('fill',marker.x-2,marker.y-2,4,4)
    end
  end
  love.graphics.setColor(16 / 255, 41 / 255, 25 / 255, 1)
  love.graphics.setColor(16 / 255, 41 / 255, 25 / 255, 1)
  for key, marked in pairs(self:store().markers or {}) do
    local x, y = key:match('^(%d+):(%d+)$')
    if marked and x then love.graphics.rectangle('fill', tonumber(x) * 8 + 2, tonumber(y) * 8 + 2, 4, 4) end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawRoulette()
  local a = (self:store().roulette or 0) * math.pi / 180
  love.graphics.setColor(16 / 255, 41 / 255, 25 / 255, 1)
  love.graphics.line(112, 96, 112 + math.sin(a) * 44, 96 - math.cos(a) * 44)
  love.graphics.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawFriendship()
  for i, mon in ipairs((self.game.save or {}).party or {}) do
    local x, y = FACE.x + 8 + (i - 1) % 2 * 92, FACE.y + 12 + math.floor((i - 1) / 2) * 48
    local def = (self.game.data.pokemon or {})[mon.species]
    local icon=self:drawMonIcon(mon,x,y)
    if not icon then Font.draw(((def or {}).name or tostring(mon.species)):sub(1, 10),x,y) end
    Font.draw(tostring(mon.friendship or mon.happiness or 0), icon and x+36 or x, y+16)
    if self.friendshipTouch and self.friendshipTouch.slot==i then
      love.graphics.setColor(16/255,41/255,25/255,1)
      love.graphics.rectangle('line',x-2,y-2,36,36)
      love.graphics.setColor(1,1,1,1)
    end
  end
end

function Gen4Poketch:drawDaycare()
  local dc = (self.game.save or {}).daycare or {}
  local breed = dc.breed or {}
  local party = {}
  for i = 1, 2 do if breed[i] and breed[i].mon then party[#party + 1] = breed[i].mon end end
  if #party == 0 and dc.mon then party[1] = dc.mon end
  for i, mon in ipairs(party) do
    local def = (self.game.data.pokemon or {})[mon.species]
    local x=24+(i-1)*96
    self:drawMonIcon(mon,x+16,60)
    Font.draw(((def or {}).name or tostring(mon.species)):sub(1, 10),x,96)
    Font.draw(tostring(mon.level or 1),x+24,36)
  end
  if breed.egg then Font.draw('EGG', 80, 144) end
end

function Gen4Poketch:drawPedometer()
  self:drawCount(self:store().steps, 5, 80, 'pedometer')
end

function Gen4Poketch:drawPartyStatus()
  local g = love.graphics
  local party = (self.game.save or {}).party or {}
  local mons = (self.game.data or {}).pokemon or {}
  for i = 1, 6 do
    local mon = party[i]
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local x = FACE.x + 16 + col * 96
    local y = FACE.y + 16 + row * 48
    if mon then
      local def = mons[mon.species]
      local icon=self:drawMonIcon(mon,x,y)
      if not icon then Font.draw(((def and def.name) or tostring(mon.species)):sub(1,9),x,y) end
      local hp = math.max(0, tonumber(mon.hp) or 0)
      local max = math.max(1, tonumber((mon.stats or {}).hp) or hp)
      local ratio = math.min(1, hp / max)
      g.setColor(0.12, 0.14, 0.12, 1)
      local barX,barY,barWidth=x,y+32,64
      g.rectangle("fill", barX, barY, barWidth, 6)
      -- Green, amber, red at the cartridge's own thresholds: a bar that is
      -- one colour is a bar that tells you nothing at a glance, which is the
      -- entire point of this app.
      if ratio > 0.5 then g.setColor(0.36, 0.82, 0.36, 1)
      elseif ratio > 0.2 then g.setColor(0.94, 0.78, 0.24, 1)
      else g.setColor(0.90, 0.30, 0.28, 1) end
      g.rectangle("fill", barX, barY, math.floor(barWidth * ratio), 6)
      g.setColor(1, 1, 1, 1)
    end
  end
  g.setColor(1, 1, 1, 1)
end

function Gen4Poketch:drawAlarm()
  local s = self:store()
  centered(('%02d:%02d'):format(s.alarmHour or 0, s.alarmMinute or 0),112,104,160)
  local now = os.date('*t')
  local ringing = s.alarmEnabled and now.hour == (s.alarmHour or 0) and now.min == (s.alarmMinute or 0)
  centered(ringing and 'ALARM' or s.alarmEnabled and 'ON' or 'OFF',112,152,160)
end

function Gen4Poketch:drawBerrySearcher()
  local cells=(self.game.data.constants or {}).gen4PoketchMapCells or {}
  local sprite=cells.berry and self:img(('poketch/map_%02d'):format(cells.berry))
  local g=love.graphics
  for _,at in ipairs(require('src.world.Gen4BerryPatches').ready(self.game)) do
    local x,y=26+6*at.x,6*at.y-6
    if sprite then
      g.setColor(1,1,1,1)
      g.draw(sprite,x-sprite:getWidth()/2,y-sprite:getHeight()/2)
    else
      g.setColor(16/255,41/255,25/255,1)
      g.rectangle('fill',x-2,y-2,4,4)
    end
  end
  g.setColor(1,1,1,1)
end

function Gen4Poketch:startDowsing(x,y)
  self.scan=60
  self.dowsingResult=require('src.pokemon.Gen4PoketchState').dowsing(self.game,x,y)
end

function Gen4Poketch:drawDowsing()
  if not self.scan or self.scan <= 0 then return end
  local result=self.dowsingResult
  if not result then return end
  local g = love.graphics
  g.setColor(16 / 255, 41 / 255, 25 / 255, 1)
  g.circle('line',result.x,result.y,4+(60-self.scan)%24)
  for _,item in ipairs(result.items) do
    g.rectangle('fill',item.x-2,item.y-2,4,4)
  end
  if result.kind==1 then centered('FAINT SIGNAL',112,152,176) end
  g.setColor(1, 1, 1, 1)
end

function Gen4Poketch:moveEffectiveness()
  local selected = self:store().moveTester or {1,1,18}
  local atk, first, second = TYPES[selected[1]], TYPES[selected[2]], TYPES[selected[3]]
  local result = 1
  for _, row in ipairs((self.game.data.type_chart or {}).matchups or {}) do
    if row.attacker == atk and (row.defender == first or row.defender == second) then
      result = result * row.multiplier / 10
    end
  end
  return result
end

function Gen4Poketch:drawMoveTester()
  local selected = self:store().moveTester or {1,1,18}
  centered(TYPES[selected[1]],72,120,64)
  centered(TYPES[selected[2]],152,32,64)
  centered(TYPES[selected[3]] or 'NONE',152,64,64)
  centered('x' .. tostring(self:moveEffectiveness()),112,152,176)
end

function Gen4Poketch:matchupParty()
  local party = {}
  for _, mon in ipairs((self.game.save or {}).party or {}) do
    if not mon.isEgg then party[#party+1] = mon end
  end
  return party
end

function Gen4Poketch:matchupTouch(x, y)
  if y < 128 or y >= 168 then return end
  local party, s = self:matchupParty(), self:store()
  local pair = s.matchup or {1,2}; s.matchup = pair
  if x >= 92 and x < 132 then
    s.compatibility = require('src.pokemon.Gen4PoketchState').compatibility(
      self.game.data, party[pair[1]], party[pair[2]])
  elseif #party > 2 and (x >= 24 and x < 72 or x >= 152 and x < 200) then
    local slot = x < 112 and 1 or 2
    repeat pair[slot] = (pair[slot] or slot) % #party + 1
    until pair[slot] ~= pair[3-slot]
    s.compatibility = nil
  end
end

function Gen4Poketch:drawMonIcon(mon, x, y)
  if not mon then return end
  local data = self.game.data
  local icons = data.icons or {}
  local entry = (icons.bySpecies or {})[mon.species] or ((data.pokemon or {})[mon.species] or {}).icon
  local path = type(entry) == 'table' and entry.image or entry
  if type(path) ~= 'string' then return end
  if self.cache[path] == nil then
    local ok, img = pcall(Assets.image, path); self.cache[path] = ok and img or false
    if self.cache[path] then self.cache[path]:setFilter('nearest','nearest') end
  end
  local image = self.cache[path]
  if image then
    local w,h = image:getDimensions()
    local frameH = type(entry) == 'table' and entry.frameHeight or icons.frameHeight or 32
    self.iconQuads = self.iconQuads or {}
    self.iconQuads[path] = self.iconQuads[path] or love.graphics.newQuad(0,0,w,math.min(h,frameH),w,h)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image,self.iconQuads[path],x,y)
    return true
  end
end

function Gen4Poketch:drawMatchup()
  local party, s = self:matchupParty(), self:store()
  local pair = s.matchup or {1,2}
  for i=1,2 do
    local mon = party[pair[i]]
    local x = i == 1 and 24 or 144
    if mon then
      self:drawMonIcon(mon, x+8, 64)
      Font.draw(((self.game.data.pokemon[mon.species] or {}).name or tostring(mon.species)):sub(1,9),x,104)
    end
  end
  if s.compatibility ~= nil then centered(tostring(s.compatibility)..'%',112,40,176) end
end

function Gen4Poketch:drawHistory()
  local history = self:store().history or {}
  for i, mon in ipairs(history) do
    local x,y = 24+(i-1)%4*44,24+math.floor((i-1)/4)*48
    self:drawMonIcon(mon,x,y)
    Font.draw(tostring(i),x+10,y+32)
  end
  if #history == 0 then centered('NO RECORDS',112,80,176) end
end

function Gen4Poketch:applyLCDPalette()
  local g = love.graphics
  local hex = (((self.game.data or {}).gen4_graphics or {}).palettes or {})['poketch/generic']
  if not (hex and g.newShader and g.setShader) then return end
  local G = require('src.import.Gen4Graphics')
  local source = G.slotFromHex(hex, 0)
  local target = G.slotFromHex(hex, (self:store().color or 0) * 2)
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
}

-- ------------------------------------------------------------------- draw --

function Gen4Poketch:drawWatch()
  local g = love.graphics
  local app = self:app()
  local oldShader = g.getShader and g.getShader()
  self:applyLCDPalette()
  local oldScissor = g.getScissor and { g.getScissor() } or {}
  local sx, sy, ex, ey = FACE.x, FACE.y, FACE.x + FACE.w, FACE.y + FACE.h
  if g.transformPoint then
    sx, sy = g.transformPoint(sx, sy); ex, ey = g.transformPoint(ex, ey)
  end

  -- Colour zero is transparent in the extracted BG, revealing the LCD's
  -- backdrop colour on hardware. Without this fill it reveals a black canvas.
  g.setColor(115 / 255, 181 / 255, 115 / 255, 1)
  g.rectangle('fill', FACE.x, FACE.y, FACE.w, FACE.h)
  g.setScissor(sx, sy, ex - sx, ey - sy)

  -- APP LCD FIRST. The extracted Poketch app tilemaps are full 256x192
  -- compositions and may contain opaque pixels outside the LCD. Drawing one
  -- after the shell used to cover the cartridge's bezel and buttons entirely.
  local face = app and app.art and self:img(app.art)
  if face then
    -- App tilemaps are composed as full 256x192 screens. Only the LCD hole
    -- belongs to the app; pixels outside it must never cover the device shell.
    g.setScissor(sx, sy, ex - sx, ey - sy)
    g.setColor(1, 1, 1, 1)
    g.draw(face, 0, 0)
  else
    -- Only apps which genuinely have no composed face use the cartridge's
    -- unavailable screen. Do not put this over an existing app merely because
    -- its interactive behaviour has not been implemented yet.
    local blank = not (app and DRAW[app.name]) and self:img(self.unavailable)
    if blank then
      g.setColor(1, 1, 1, 1)
      g.draw(blank, 0, 0)
    else
      g.setColor(0.55, 0.72, 0.42, 1)
      g.rectangle("fill", FACE.x, FACE.y, FACE.w, FACE.h)
    end
  end

  -- Live overlays belong on the LCD, above the app's cartridge background.
  if app then
    local body = app.name and DRAW[app.name]
    if body then
      body(self)
    elseif not face then
      -- Only a truly missing face gets a textual fallback. A valid extracted
      -- app remains visually faithful even before its behaviour is emulated.
      local label = app.name or Strings("APP")
      Font.draw(label, FACE.x + 8, FACE.y + 8)
      Font.draw(Strings("NOT BUILT YET"), FACE.x + 8, FACE.y + 24)
    end
  end

  g.setScissor(unpack(oldScissor))
  if g.setShader then g.setShader(oldShader) end

  -- SHELL LAST. Platinum composes the Poketch device around the LCD; this
  -- extracted full-screen border contains the bezel and physical app-change
  -- buttons and must mask the edges of every app tilemap.
  local border = self:img(self.border)
  if border then
    g.setColor(1, 1, 1, 1)
    g.draw(border, 0, 0)
  else
    -- Keep a visible frame if an old cache predates border extraction.
    g.setColor(0.10, 0.13, 0.18, 1)
    g.setLineWidth(2)
    g.rectangle("line", FACE.x - 2, FACE.y - 2, FACE.w + 4, FACE.h + 4)
    g.setLineWidth(1)
  end

  g.setColor(1, 1, 1, 1)
end

function Gen4Poketch:draw()
  if SecondScreen.mode(self.game) == "off" then return self:drawWatch() end
  SecondScreen.drawFrame(self.game)
  SecondScreen.draw(self.game, function() self:drawWatch() end)
end

return Gen4Poketch
