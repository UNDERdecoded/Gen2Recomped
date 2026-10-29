-- Copyright (c) 2026 Roxas2712. See contribution permission: https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md.
-- Shared native GSC RTC reads. The public Clock spelling follows the
-- reference contract; no private mod implementation or clock is embedded.
local Clock = { MINUTES_PER_DAY = 1440, DAYS = 7, DEFAULT_HOUR = 10, DEFAULT_MINUTE = 0 }
local Strings = require("src.core.Strings")
Clock.DAY_NAMES = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY" }
local observed = setmetatable({}, { __mode = "k" })
local function integer(value)
  local n = tonumber(value)
  if n and n == n and n ~= math.huge and n ~= -math.huge then return math.floor(n) end
end
local function rtc(save)
  return type(save) == "table" and type(save.rtc) == "table" and save.rtc or nil
end
function Clock.hostMinutes(now)
  return ((integer(os.date("%H", now)) or 0) * 60 + (integer(os.date("%M", now)) or 0)) % 1440
end
function Clock.hostWeekday(now)
  return (integer(os.date("%w", now)) or 0) % 7
end
-- Newly set clocks advance by elapsed RTC seconds, including while closed.
-- The old host-local offsets remain readable without migrating a save. Host
-- DST/time-zone changes must not silently change an explicitly set game clock.
local function anchored(state, now)
  if not state then return nil end
  local at, minute, day = integer(state.anchorTime), integer(state.anchorMinute), integer(state.anchorDay)
  if not at or not minute or minute < 0 or minute >= 1440 or not day or day < 0 or day >= 7 then return nil end
  now = integer(now or os.time())
  if not now then return nil end
  return minute + math.floor((now - at) / 60), day
end
function Clock.minutes(save, now)
  local state = rtc(save)
  local total = anchored(state, now)
  if total then return total % 1440 end
  return (Clock.hostMinutes(now) + (state and integer(state.startMinute) or 0)) % 1440
end
function Clock.hour(save, now) return math.floor(Clock.minutes(save, now) / 60) end
function Clock.minute(save, now) return Clock.minutes(save, now) % 60 end
function Clock.isSet(save)
  local state = rtc(save)
  return state ~= nil and integer(state.startMinute) ~= nil
end
function Clock.setTime(save, hour, minute)
  if type(save) ~= "table" then return false end
  hour, minute = integer(hour or 0), integer(minute or 0)
  if not hour or not minute then return false end
  local now = os.time()
  local day, date = Clock.weekday(save, now), Clock.dateKey(save, now)
  local wanted = (hour % 24) * 60 + minute % 60
  save.rtc = rtc(save) or {}
  save.rtc.startMinute = (wanted - Clock.hostMinutes(now)) % 1440
  save.rtc.startDay = (day - Clock.hostWeekday(now)) % 7
  save.g2DayOffset = save.rtc.startDay
  save.rtc.anchorTime, save.rtc.anchorMinute = now, wanted
  save.rtc.anchorDay, save.rtc.anchorDate = day, date
  return true
end
local function note(save, day, reason, now)
  if type(save) ~= "table" then return day end
  local Runtime = require("src.mods.Runtime")
  if not require("src.core.GameVersion").isGen2() or not Runtime.wants("clock.day_changed") then
    observed[save] = nil
    return day
  end
  local previous, date = observed[save], Clock.dateKey(save, now)
  observed[save] = { day=day, date=date } -- Commit before dispatch; reentrant reads are silent.
  if previous ~= nil and (previous.day ~= day or previous.date ~= date) then
    Runtime.emit("clock.day_changed", { day = day, previous = previous.day, reason = reason })
  end
  return day
end
function Clock.weekday(save, now)
  local state = rtc(save)
  local total, day = anchored(state, now)
  if total then return note(save, (day + math.floor(total / 1440)) % 7, "rollover", now) end
  local offset = state and integer(state.startDay)
  if offset == nil then offset = type(save) == "table" and integer(save.g2DayOffset) or 0 end
  return note(save, (Clock.hostWeekday(now) + (offset or 0)) % 7, "rollover", now)
end
function Clock.setWeekday(save, day)
  day = integer(day)
  if type(save) ~= "table" or not day then return false end
  local now = os.time()
  save.rtc = rtc(save) or {}
  day = day % 7
  save.rtc.startDay = (day - Clock.hostWeekday(now)) % 7
  save.rtc.dayOfWeek = day
  local total = anchored(save.rtc, now)
  if total then save.rtc.anchorDay = (day - math.floor(total / 1440)) % 7 end
  -- Keep the existing native field in sync for older native consumers/saves.
  save.g2DayOffset = save.rtc.startDay
  note(save, day, "set", now)
  return true
end
-- Calendar identity for daily/weekly timers. Only date arithmetic uses the
-- host calendar library; elapsed game days come from the same RTC as minutes
-- and weekday. Noon normalization avoids missing/duplicated local DST hours.
function Clock.calendarDate(save, now)
  local state = rtc(save)
  local total = anchored(state, now)
  local year, month, day
  if total and type(state.anchorDate) == "string" then
    year, month, day = state.anchorDate:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
  end
  if year and month >= 1 and month <= 12 and day >= 1 and day <= 31 then
    local ok, stamp = pcall(os.time, { year=year, month=month,
      day=day + math.floor(total / 1440), hour=12, min=0, sec=0, isdst=nil })
    if ok and stamp then return os.date("*t", stamp) end
  end
  return os.date("*t", now)
end
function Clock.dateKey(save, now)
  local date = Clock.calendarDate(save, now)
  return ("%04d-%02d-%02d"):format(date.year, date.month, date.day)
end
function Clock.weekdayName(day)
  local name = Clock.DAY_NAMES[day]
  return name and Strings(name)
end
function Clock.daytimeLabel(hour)
  hour = integer(hour) or Clock.hour()
  hour = hour % 24
  return Strings(hour < 4 and "NITE" or hour < 10 and "MORN" or hour < 18 and "DAY" or "NITE")
end
function Clock.resetObservations() observed = setmetatable({}, { __mode = "k" }) end
return Clock
