-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Cartridge-numbered observations over native imported Pokemon data and art.
-- This module does not create another party, save, extractor or battle engine.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Pokemon=require('src.pokemon.Pokemon')
local Sprites=require('src.pokemon.Sprites')
local Assets=require('src.render.Assets')
local Version=require('src.core.GameVersion')
local P={}
local current,cache,users=nil,{},{}
local function release()
  for _,entry in pairs(cache)do if entry.image and entry.image.release then entry.image:release()end end
  current,cache,users=nil,{},{}
end
local function context()
  local game=Native.game()
  if not(game and game.data and type(game.data.pokemon)=='table')then release();return end
  if not current or current.game~=game or current.data~=game.data or current.loader~=game.mods or current.edition~=Version.get()or not current.ids:valid()then
    release();current={game=game,data=game.data,loader=game.mods,edition=Version.get(),ids=Ids.new(game.data)}
  end
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  local who=host and host.currentMod or facade and facade._callbackOwner()
  if who then users[who]=true end
  return current
end
local function copy(value,seen)
  if type(value)~='table'then return type(value)~='function'and value or nil end
  seen=seen or{};if seen[value]then return seen[value]end
  local out={};seen[value]=out;for k,v in pairs(value)do out[k]=copy(v,seen)end;return out
end
local function species(value)
  local c=context();if not c then return end
  local key=c.ids:native('pokemon',value)
  return key and c.data.pokemon[key],key,c
end
function P.ready()return context()~=nil end
function P.speciesOf(mon)
  if type(mon)~='table'then return nil end
  local _,key,c=species(mon.species)
  return key and c.ids:read('pokemon',key)
end
function P.name(value)local row=species(value);return row and row.name end
function P.keyName(value)local row,key=species(value);return row and(row.key or row.id or key)end
function P.speciesFromName(value)
  local c=context();if not c or type(value)~='string'then return nil end
  local found
  for key,row in pairs(c.data.pokemon)do
    if value==key or value==row.id or value==row.name or value==row.key then
      local id=c.ids:read('pokemon',key)
      if found and found~=id then return nil,'ambiguous imported species name'end
      found=id
    end
  end
  return found
end
function P.national(value)local row=species(value);return row and row.dex end
function P.speciesFromNational(number)
  local c=context();if not c then return nil end
  local found
  for key,row in pairs(c.data.pokemon)do if row.dex==number and not row.unused then
    local id=c.ids:read('pokemon',key)
    if found and found~=id then return nil,'ambiguous imported National Dex entry'end
    found=id
  end end
  return found
end
function P.types(value)
  local row,_,c=species(value);if not row then return nil end
  local types=row.types or{row.type1,row.type2}
  return{c.ids:read('types',types[1]),c.ids:read('types',types[2]or types[1])}
end
function P.stats(value)
  local row=species(value);local s=row and row.baseStats;if not s then return nil end
  return{hp=s.hp,atk=s.attack,def=s.defense,spe=s.speed,spa=s.spatk or s.special,spd=s.spdef or s.special}
end
function P.speciesMeta(value)
  local row=species(value);if not row then return nil end
  return{genderRatio=row.genderRatio,eggGroups=copy(row.eggGroups),eggCycles=row.eggCycles,
    catchRate=row.catchRate,baseFriendship=row.friendship,growthRate=row.growthRate,
    bodyColor=row.bodyColor,safariFleeRate=row.safariFleeRate}
end
function P.dexEntry(value)
  if type(value)=='table'then value=P.speciesOf(value)end
  local row=species(value);if not row then return nil end
  -- Native imports store metres/kilograms; this source contract uses the
  -- cartridge's decimetres/hectograms. Never pass metres as sprite height.
  return{height=type(row.height)=='number'and math.floor(row.height*10+.5)or nil,
    weight=type(row.weight)=='number'and math.floor(row.weight*10+.5)or nil,
    category=row.category,description=type(row.dexEntry)=='string'and row.dexEntry or nil}
end
function P.abilities(value)
  local row,_,c=species(value);if not row then return nil end
  local a=row.abilities or{};return{c.ids:read('abilities',a[1]),c.ids:read('abilities',a[2])}
end
function P.abilityId(value,personality)
  local a=P.abilities(value);if not a then return nil end
  return a[(tonumber(personality)or 0)%2+1]or a[1]
end
function P.gender(value,personality)
  local row,key,c=species(value);if not row then return nil end
  local gender=Pokemon.genderOf(c.data,{species=key,personality=personality})
  return({male='M',female='F',none='U',unknown='U'})[gender]
end
function P.isShiny(mon)
  if type(mon)~='table'then return false end
  local c=context();local key=c and c.ids:native('pokemon',mon.species)
  local native={};for k,v in pairs(mon)do native[k]=v end
  -- Typed live views intentionally store their fields behind __index.
  for _,k in ipairs{'species','personality','otId','otSecretId','trainerId','isShiny','shiny','dvs','ivs','level'}do
    native[k]=mon[k]
  end
  if key then native.species=key end
  return Pokemon.isShiny(native)
end
function P.isEgg(mon)return type(mon)=='table'and(mon.isEgg==true or mon.egg==true)or false end
function P.displayName(mon)
  if type(mon)~='table'then return nil end
  if mon.nickname and mon.nickname~=''then return mon.nickname end
  return P.name(P.speciesOf(mon))
end
function P.moveName(value)
  local c=context();local key=c and c.ids:native('moves',value)
  return key and c.data.moves[key].name
end
function P.movePp(value)
  local c=context();local key=c and c.ids:native('moves',value)
  return key and c.data.moves[key].pp
end
function P.movesAtLevel(value,level)
  local row,_,c=species(value);if not row then return nil end
  local moves,pp,maximum={},{},{}
  for i,key in ipairs(Pokemon.movesAtLevel(row,level))do
    moves[i]=c.ids:read('moves',key);pp[i]=c.data.moves[key]and c.data.moves[key].pp;maximum[i]=pp[i]
  end
  return moves,pp,maximum
end
function P.movesLearnedAt(value,level)
  local row,_,c=species(value);if not row then return nil end
  local out={};for _,entry in ipairs(row.learnset or{})do
    if entry.level==level then out[#out+1]=c.ids:read('moves',entry.move)end
  end;return out
end
function P.moveIdAt(mon,slot)
  local value=mon and mon.moves and mon.moves[slot]
  if type(value)=='number'then return value end
  local c=context();return c and type(value)=='table'and c.ids:read('moves',value.id)or nil
end
function P.moveSlotCount(mon)return mon and mon.moves and#mon.moves or 0 end
function P.knowsMove(mon,number)
  for slot=1,P.moveSlotCount(mon)do if P.moveIdAt(mon,slot)==number then return true end end;return false
end
local function picture(side,value,form,shiny,personality)
  local row,key,c=species(value);if not row then return nil,'imported native species unavailable'end
  if form~=nil and form~=0 then return nil,'native alternate-form picture binding unavailable'end
  local mon={species=key,personality=personality,isShiny=shiny==true}
  local path=Sprites.path(c.data,key,side,{mon=mon,kind='battle'})
  if not path then return nil,'native species picture unavailable'end
  local old=cache[path];if old then return old end
  local ok,image=pcall(love.graphics.newImage,Assets.resolve(path))
  if not ok then return nil,tostring(image)end
  local w,h=image:getDimensions()
  local entry={image=image,w=w,h=h};cache[path]=entry;return entry
end
function P.frontPic(value,form,shiny,personality)return picture('front',value,form,shiny,personality)end
function P.backPic(value,form,shiny)return picture('back',value,form,shiny)end
P.frontSprite=P.frontPic
P.flushPicCaches=release
P.invalidate=release
local service={release=release,poll=function()if current then context()end end,
  releaseOwner=function(_,who)if users[who]then users[who]=nil;if not next(users)then release()end end end}
P._service=service
require('src.core.game3.asset_stream').register(service)
Assets.register(release)
return P
