-- Copyright (c) 2026 Roxas2712. See contribution permission: https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md.
-- Native clock/day selection over the shared saved RTC and native widgets.
-- Dialogue comes from the active ROM cache; this layout is engine-owned.
local Clock = require("src.core.Gen2Clock")
local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local InitClock = {}
InitClock.__index = InitClock
InitClock.isOpaque = true
local TEXT = {
  intro=Strings.source("SET THE CLOCK"), hour=Strings.source("CHOOSE HOUR"),
  minute=Strings.source("CHOOSE MINUTE"), day=Strings.source("CHOOSE DAY"),
  confirmHour=Strings.source("CONFIRM HOUR"), confirmMinute=Strings.source("CONFIRM MINUTE"),
  questionMark=Strings.source("?"), response=Strings.source("\nCLOCK SET"),
}
local function value(n, fallback, limit)
  n = tonumber(n)
  if not n or n ~= n or n == math.huge or n == -math.huge then return fallback end
  return math.floor(n) % limit
end
local function text(self, key, fallback)
  local bank = self.game and self.game.data and self.game.data.text or {}
  local found = bank[key] or bank["_" .. key:match("[^.]+$")]
  if type(found) == "string" and found ~= "" then return found end
  return Strings(fallback)
end
function InitClock.hourString(hour)
  hour = value(hour, 0, 24)
  local shown = hour % 12
  return ("%s %d"):format(Clock.daytimeLabel(hour), shown == 0 and 12 or shown)
end
function InitClock.oclockString(hour) return Strings("%s o'clock", InitClock.hourString(hour)) end
function InitClock.timeString(hour, minute)
  return ("%s:%02d"):format(InitClock.hourString(hour), value(minute, 0, 60))
end
function InitClock.responseKey(hour)
  hour = value(hour, 0, 24)
  if hour < 4 or hour >= 18 then return "soDark" end
  return hour <= 10 and "overslept" or "yikes"
end
function InitClock.new(game, opts)
  opts = opts or {}
  local day = opts.mode == "day"
  return setmetatable({ game=game, save=opts.save or game.save,
    mode=day and "day" or "clock", phase=day and "day" or "intro",
    isOpaque=not day, onDone=opts.onDone, autoConfirm=opts.autoConfirm == true,
    fades=opts.fades == true and not day and not opts.autoConfirm,
    hour=value(opts.hour, Clock.DEFAULT_HOUR, 24),
    minute=value(opts.minute, Clock.DEFAULT_MINUTE, 60), day=value(opts.day, 0, 7),
  }, InitClock)
end
function InitClock:wantsFillScale() return self.mode ~= "day" end
function InitClock:question()
  if self.phase == "intro" then return text(self, "OakTimeWokeUpText", TEXT.intro) end
  if self.phase == "hour" then return text(self, "OakTimeWhatTimeIsItText", TEXT.hour) end
  if self.phase == "minute" then return text(self, "OakTimeHowManyMinutesText", TEXT.minute) end
  if self.phase == "day" then return text(self, "SetDayOfWeek.OakTimeWhatDayIsItText", TEXT.day) end
  if self.phase == "confirm-hour" then
    local lines = { text(self, "OakTimeWhatHoursText", TEXT.confirmHour),
      InitClock.oclockString(self.hour)
        .. text(self, "OakTimeWhatHoursText.OakTimeHoursQuestionMarkText", TEXT.questionMark) }
    return table.concat(lines, "\n")
  end
  if self.phase == "confirm-minute" then
    local lines = { text(self, "OakTimeWhoaMinutesText", TEXT.confirmMinute),
      Strings("%d min.", self.minute)
        .. text(self, "OakTimeWhoaMinutesText.OakTimeMinutesQuestionMarkText", TEXT.questionMark) }
    return table.concat(lines, "\n")
  end
  if self.phase == "confirm-day" then
    return Clock.weekdayName(self.day + 1)
      .. text(self, "SetDayOfWeek.OakTimeIsItText", TEXT.questionMark)
  end
  local response = { soDark="OakTimeSoDarkText", overslept="OakTimeOversleptText", yikes="OakTimeYikesText" }
  if self.phase == "response" then
    return InitClock.timeString(self.hour, self.minute)
      .. text(self, "OakText_ResponseToSetTime." .. response[InitClock.responseKey(self.hour)], TEXT.response)
  end
  return ""
end
function InitClock:display()
  if self.phase == "hour" then return InitClock.oclockString(self.hour) end
  if self.phase == "minute" then return Strings("%d min.", self.minute) end
  if self.phase == "day" then return Clock.weekdayName(self.day + 1) end
end
function InitClock:confirming() return self.phase:match("^confirm%-") ~= nil end
function InitClock:showPhase()
  if self.autoConfirm or self.done then return end
  if self.phase == "intro" or self.phase == "response" then
    self.game.stack:push(TextBox.new(self.game, self:question(), function() self:accept() end))
  elseif self:confirming() then
    self.game.stack:push(TextBox.new(self.game, self:question(), nil, {
      choice=function(yes) if yes then self:accept() else self:decline() end end,
    }))
  end
end
function InitClock:enter()
  if self.fades then self.fade = { out=false, frame=0 } else self:showPhase() end
end
function InitClock:complete()
  if self.done then return end
  self.done = true
  if self.onDone then
    if self.mode == "day" then self.onDone(self.day) else self.onDone(self.hour, self.minute) end
  elseif self.game.stack:top() == self then
    self.game.stack:pop()
  end
end
function InitClock:finish()
  if self.done or self.finishing then return end
  local ok
  if self.mode == "day" then ok = Clock.setWeekday(self.save, self.day)
  else ok = Clock.setTime(self.save, self.hour, self.minute) end
  if not ok then return end
  self.finishing = true
  if self.fades then self.fade = { out=true, frame=0 } else self:complete() end
end
function InitClock:accept()
  if self.done or self.finishing then return end
  local nextPhase = { intro="hour", hour="confirm-hour", ["confirm-hour"]="minute",
    minute="confirm-minute", ["confirm-minute"]="response", day="confirm-day" }
  local next = nextPhase[self.phase]
  if next then self.phase=next;self:showPhase() else self:finish() end
end
function InitClock:decline()
  if self.done or self.finishing then return end
  local picker = self.phase:match("^confirm%-(.+)$")
  if picker then self.phase=picker;self:showPhase() end
end
function InitClock:value()
  if self.phase == "hour" then return self.hour, 23 end
  if self.phase == "minute" then return self.minute, 59 end
  return self.day, 6
end
function InitClock:step(delta)
  local current, last = self:value()
  local key = self.phase
  if key == "hour" or key == "minute" or key == "day" then self[key]=(current+delta)%(last+1) end
end
function InitClock:update()
  if self.done then return end
  if self.fade then
    local fade = self.fade
    fade.frame = fade.frame + 1
    if fade.frame >= 8 then
      self.fade = nil
      if fade.out then self:complete() else self:showPhase() end
    end
    return
  end
  if self.finishing then return end
  if self.autoConfirm then self:accept();return end
  local input = self.game.input
  if input:wasPressed("up") then self:step(1)
  elseif input:wasPressed("down") then self:step(-1)
  elseif input:wasPressed("a") then self:accept() end
end
function InitClock:sgbPalettes()
  local P = require("src.render.PaletteFX")
  if self.isOpaque then return { P.trueColorZone(0, 0, 19, 17) } end
  return { P.trueColorZone(1, 4, 18, 11), P.trueColorZone(0, 12, 19, 17) }
end
function InitClock:draw()
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  if self.isOpaque then G.rectangle("fill", 0, 0, 160, 144) end
  Font.drawBox(1, 4, 18, 8)
  local picker = self:display()
  local shown = picker or InitClock.timeString(self.hour, self.minute)
  Font.draw(shown, 16, 48)
  if picker then
    Font.draw(Strings("UP/DOWN: CHANGE"), 16, 64)
    Font.draw(Strings("A: CONFIRM"), 16, 80)
    Font.drawBox(0, 12, 20, 6)
    Font.draw(self:question(), 8, 105)
  end
  if self.fade then
    local alpha = self.fade.frame / 8
    G.setColor(0, 0, 0, self.fade.out and alpha or 1-alpha)
    G.rectangle("fill", 0, 0, 160, 144)
  end
  G.setColor(1, 1, 1, 1)
end
return InitClock
