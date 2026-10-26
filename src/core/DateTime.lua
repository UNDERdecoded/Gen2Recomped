-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Presentation preferences belong to the installation, never a save payload.
local D={}
D.DATE_FORMATS={{'device','DEVICE'},{'dmy','DD-MM-YYYY'},{'mdy','MM-DD-YYYY'},{'ymd','YYYY-MM-DD'}}
D.TIME_FORMATS={{'device','DEVICE'},{'24h','24 HOUR'},{'12h','12 HOUR'}}
local function parts(timestamp)
  if type(timestamp)~='number' or timestamp~=timestamp or timestamp<0 or timestamp>253402300799 then return nil end
  local ok,value=pcall(os.date,'*t',math.floor(timestamp))
  return ok and type(value)=='table' and value or nil
end
local function options(game)
  return type(game)=='table' and type(game.save)=='table' and type(game.save.options)=='table'
    and game.save.options or {}
end
local function selection(choices,value)
  for index,choice in ipairs(choices) do if choice[1]==value then return index end end
  return 1
end
local function localized(format,timestamp)
  if type(os.setlocale)~='function' then return nil end
  local ok,locale=pcall(os.setlocale,nil,'time')
  if not ok or not locale or locale=='C' or locale=='POSIX' then return nil end
  local formatted,value=pcall(os.date,format,math.floor(timestamp))
  return formatted and type(value)=='string' and value~='' and value or nil
end
function D.date(game,timestamp)
  local t=parts(timestamp);if not t then return '----' end
  local mode=D.DATE_FORMATS[selection(D.DATE_FORMATS,options(game).dateFormat)][1]
  if mode=='device' then
    local value=localized('%x',timestamp);if value then return value end
  end
  if mode=='ymd' then return ('%04d-%02d-%02d'):format(t.year,t.month,t.day) end
  if mode=='mdy' then return ('%02d-%02d-%04d'):format(t.month,t.day,t.year) end
  return ('%02d-%02d-%04d'):format(t.day,t.month,t.year)
end
function D.time(game,timestamp)
  local t=parts(timestamp);if not t then return '----' end
  local mode=D.TIME_FORMATS[selection(D.TIME_FORMATS,options(game).timeFormat)][1]
  if mode=='device' then
    local value=localized('%X',timestamp);if value then return value end
  end
  if mode=='12h' then
    local hour=t.hour%12;if hour==0 then hour=12 end
    return ('%02d:%02d %s'):format(hour,t.min,t.hour<12 and 'AM' or 'PM')
  end
  return ('%02d:%02d'):format(t.hour,t.min)
end
function D.dateTime(game,timestamp)
  if not parts(timestamp) then return '----' end
  return D.date(game,timestamp)..' '..D.time(game,timestamp)
end
function D.rows(strings)
  local rows={}
  for _,spec in ipairs({{'dateFormat','DATE FORMAT',D.DATE_FORMATS},{'timeFormat','TIME FORMAT',D.TIME_FORMATS}}) do
    local key,label,choices=spec[1],spec[2],spec[3]
    rows[#rows+1]={id=key,label=strings(label),
      value=function(game)return strings(choices[selection(choices,options(game)[key])][2])end,
      step=function(game,direction)
        local opts=options(game)
        opts[key]=choices[(selection(choices,opts[key])-1+((tonumber(direction) or 1)<0 and -1 or 1))%#choices+1][1]
        return true
      end}
  end
  return rows
end
return D
