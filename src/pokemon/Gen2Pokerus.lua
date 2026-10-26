-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native GSC party-byte transitions. Imported cured bytes retain immunity.
local P={}
local function value(mon)
  local n=tonumber(mon and mon.pokerus)or 0
  if n~=n or math.abs(n)==math.huge then return 0 end
  return math.max(0,math.floor(n))%256
end
local function write(party,index,byte,source)
  local mon=party[index];mon.pokerus=byte
  local Runtime=require('src.mods.Runtime')
  if Runtime.wants("pokerus.infected")then
    Runtime.emit("pokerus.infected",{party=party,slot=index,mon=mon,
      strain=math.floor(byte/16),days=byte%16,source=source})
  end
  return index
end
function P.afterBattle(save,random)
  if not require('src.pokemon.Gen2Breeding').isVanilla()then return end
  local party=save and save.party or{}
  if #party==0 then return end
  random=random or function()return love.math.random(0,255)end
  local carrier
  for n,mon in ipairs(party)do if value(mon)%16>0 then carrier=n;break end end
  if carrier then
    if random()>=85 or #party==1 then return end
    local direction=carrier==#party and -1 or (random()<129 and -1 or 1)
    local byte=value(party[carrier])
    for target=carrier+direction,direction==1 and #party or 1,direction do
      local nextByte=value(party[target])
      if nextByte==0 then
        local strain=math.floor(byte/16)
        return write(party,target,strain*16+strain%4+1,'spread')
      end
      if nextByte%4==0 then return end
      byte=nextByte
    end
    return
  end
  local Flags=require('src.script.Flags')
  if not Flags.get(save,require('src.script.Gen2Flags').engineFlag(21))then return end
  if random()~=0 or random()>=3 then return end
  local index
  repeat index=random()%8+1 until index<=#party
  if value(party[index])>=16 then return end
  local roll
  repeat roll=random()until roll~=0
  local strain=roll<16 and 0 or roll%8+1
  return write(party,index,strain*16+strain%4+1,'contracted')
end
function P.advance(party,days)
  for _,mon in ipairs(party or{})do
    local byte=value(mon)
    if byte%16>0 then mon.pokerus=byte-byte%16+math.max(0,byte%16-days)end
  end
end
local monthDays={0,31,59,90,120,151,181,212,243,273,304,334}
local function day(save,now)
  local Clock=require('src.core.Gen2Clock')
  local date=Clock.calendarDate and Clock.calendarDate(save,now)or os.date('*t',now)
  local y=date.year-1
  local ordinal=365*y+math.floor(y/4)-math.floor(y/100)+math.floor(y/400)
    +monthDays[date.month]+date.day
  if date.month>2 and date.year%4==0 and(date.year%100~=0 or date.year%400==0)then ordinal=ordinal+1 end
  return ordinal
end
function P.poll(save,now)
  if not save or not require('src.pokemon.Gen2Breeding').isVanilla()then return end
  local today=day(save,now)
  local previous=save.g2PokerusDay
  save.g2PokerusDay=today
  if type(previous)~='number' or previous==today then return end
  P.advance(save.party,today<previous and 4 or math.min(4,today-previous))
end
return P
