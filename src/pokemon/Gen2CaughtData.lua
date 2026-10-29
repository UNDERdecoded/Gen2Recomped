-- Original native integration by Roxas2712. See LICENSE-ROXAS2712.md.
-- Crystal MON_CAUGHTDATA: one time/level byte, one OT-gender/landmark byte.
-- Gold/Silver reserve these bytes; their opaque contents are not metadata.
local C={CAUGHT_TIME_MASK=192,CAUGHT_LEVEL_MASK=63,CAUGHT_GENDER_MASK=128,
 CAUGHT_LOCATION_MASK=127,CAUGHT_EGG_LEVEL=1,LANDMARK_EVENT=127,LANDMARK_GIFT=126,
 CAUGHT_BY={unknown=0,girl=1,boy=2}}
local fields={'caughtTime','caughtLevel','caughtLocation','caughtByGender'}
function C.hasCaughtData(version)
 return (version or require('src.core.GameVersion').get())=='crystal'
end
function C.caughtTimeOf(value)
 if type(value)=='string'then return ({MORN=1,DAY=2,NITE=3,DARK=3})[value]or 0 end
 if type(value)~='number'then return 0 end
 local n=math.floor(value)
 if n<0 or n>3 then return 0 end
 return math.min(n,2)+1
end
function C.caughtGenderOf(value)
 if value==true then return 'girl'elseif value==false then return 'boy'end
 if type(value)=='string'then
  return ({girl='girl',female='girl',boy='boy',male='boy'})[value:lower()]
 end
end
local function landmark(value)
 return type(value)=='number'and math.floor(value)%128 or 0
end
function C.setCaughtData(mon,opts)
 if type(mon)~='table'then return mon end
 opts=opts or{}
 mon.caughtTime=C.caughtTimeOf(opts.timeOfDay)
 mon.caughtLevel=math.max(0,math.floor(opts.level or mon.level or 0))
 mon.caughtLocation=landmark(opts.landmark)
 mon.caughtByGender=C.caughtGenderOf(opts.playerGender)or 'boy'
 return mon
end
function C.packCaughtData(mon)
 mon=type(mon)=='table'and mon or{}
 local time=math.floor(tonumber(mon.caughtTime)or 0)%4
 local level=math.floor(tonumber(mon.caughtLevel)or 0)%64
 return time*64+level,landmark(tonumber(mon.caughtLocation)or 0)
  +(C.caughtGenderOf(mon.caughtByGender)=='girl'and 128 or 0)
end
function C.unpackCaughtData(first,second)
 first,second=math.floor(first or 0)%256,math.floor(second or 0)%256
 return {caughtTime=math.floor(first/64),caughtLevel=first%64,
  caughtLocation=second%128,caughtByGender=second>=128 and 'girl'or 'boy'}
end
function C.setGiftCaughtData(mon,caughtBy)
 if type(mon)~='table'then return mon end
 local code=C.CAUGHT_BY[tostring(caughtBy):lower()]or 0
 local low=126+math.floor(code/2)+(code%2)*128
 local decoded=C.unpackCaughtData(0,low)
 for _,key in ipairs(fields)do mon[key]=decoded[key]end
 return mon
end
function C.hasFields(mon)
 for _,key in ipairs(fields)do if mon[key]~=nil then return true end end
 return false
end
-- Old native Lua saves stored only the packed word. Upgrade that shape once
-- on validation, without rerolling, rewriting history or changing any owner.
-- Existing source-shaped fields remain authoritative, including authored data.
function C.hydrate(mon,version)
 if type(mon)~='table'or not C.hasCaughtData(version)or C.hasFields(mon)
     or type(mon.caughtData)~='number'then return mon end
 local word=math.floor(mon.caughtData)%65536
 local decoded=C.unpackCaughtData(math.floor(word/256),word%256)
 for _,key in ipairs(fields)do mon[key]=decoded[key]end
 mon.caughtData=nil
 return mon
end
-- Codec and existing native consumers accept both historical and live source
-- records. The public pack API itself always reads the four source fields.
function C.word(mon)
 if C.hasFields(mon)then local hi,lo=C.packCaughtData(mon);return hi*256+lo end
 return mon.caughtData or 0
end
function C.location(mon)return C.word(mon)%128 end
function C.playerGender(mon)
 local low=C.word(mon)%256
 if low%128==0 then return nil end
 return low>=128 and 'girl'or 'boy'
end
-- Native arrival sites use the live overworld (and its world.tod hook), or
-- the same saved RTC while no overworld is attached. No second clock exists.
function C.record(game,mon,opts)
 if not C.hasCaughtData()then return mon end
 opts=opts or{}
 local save=game.save or{}
 local ow=opts.overworld or game.overworld
 local map=game.data and game.data.maps and game.data.maps[save.player and save.player.map]
 local place=opts.landmark
 if place==nil then place=map and tonumber(map.landmark)end
 if place==nil and ow and ow.map and ow.map.def then place=tonumber(ow.map.def.landmark)end
 local tod=ow and ow.timeOfDay and ow:timeOfDay()
 if tod==nil then
  local hour=require('src.core.Gen2Clock').hour(save)
  tod=hour<4 and 'NITE'or hour<10 and 'MORN'or hour<18 and 'DAY'or 'NITE'
 end
 return C.setCaughtData(mon,{level=opts.level,landmark=place,timeOfDay=tod,
  playerGender=save.player and save.player.gender})
end
return C
