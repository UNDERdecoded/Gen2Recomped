-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Live, typed source observations over one admitted native battle. Views own
-- their arrays; they never lend the native controller/save under source names.
local Ids=require('src.compat.gen1.BattleIds')
local Iteration=require('src.compat.gen1.TableIteration')
local M={}
local statNames={attack='attack',defense='defense',speed='speed',spAtk='spatk',spDef='spdef',hp='hp'}
local statusBits={PSN=8,BRN=16,FRZ=32,PAR=64,TOX=128}
local function status(mon)
 if mon.status=='SLP'then return math.max(1,math.min(7,tonumber(mon.sleepTurns)or 1))end
 if mon.status=='PSN'and mon.toxic then return 128 end
 return statusBits[mon.status]or 0
end
local function integer(v,lo,hi)return type(v)=='number'and v==v and v%1==0 and v>=lo and v<=hi end
local monKeys={'species','nickname','level','hp','maxHp','attack','defense','speed','spAtk','spDef',
 'moves','pp','maxPp','item','status','ability','personality','friendship','isEgg','otId','otSecretId'}
local battlerKeys={'id','side','flank','mon','species','type1','type2','ability','item','status','fainted','stages','partyIndex'}
local stateKeys={'player','enemy','battlers','party','playerParty','enemyParty','turn','wild','double','over','result',
 'weather','weatherTurns','session','playerIndex','enemyIndex','trainerClass','trainerName','trainerPicId',
 'link','safari','tutorial','oldManTutorial','pokedude','firstBattle','ghostBattle','kinds','rng'}
local reserved={}
for _,key in ipairs(stateKeys)do reserved[key]=true end
function M.new(game,screen,valid,identifiers)
 local e={context={game=game,screen=screen,data=game.data},entries=setmetatable({},{__mode='k'}),
  caches={},arrays={},valid=valid,retired=false}
 local ids=identifiers or Ids.new(game.data)
 local function at(pos)
  local s=e.context and e.context.screen;if not s then return end
  if pos==0 then return s.player elseif pos==1 then return s.enemy end
  return s.battlerAt and s:battlerAt(pos)
 end
 local read
 local function collection(name,values,convert)
  local a=e.arrays[name]
  if not a then a={view={}};e.arrays[name]=a end
  local out=a.view;local old=#out
  for i,value in ipairs(values or{})do out[i]=convert and convert(value,i)or value end
  for i=#(values or{})+1,old do out[i]=nil end
  return out
 end
 local function proxy(kind,raw)
  if not raw then return nil end
  local cache=e.caches[kind];if not cache then cache=setmetatable({},{__mode='kv'});e.caches[kind]=cache end
  local existing=cache[raw];if existing then return existing end
  local d={kind=kind,raw=raw};local view={};cache[raw]=view;e.entries[view]=d
  setmetatable(view,{__index=function(_,key)
   if d.snapshot then return d.snapshot[key]end
   if not e.context or not e.valid()then return nil end
   return read(d,key)
  end,__newindex=function(t,key,value)
   assert(e.context and e.valid(),'native battle view retired')
   if kind=='mon'and(key=='hp'or key=='nickname'or key=='item'or key=='status')then
    local mon=d.raw
    if key=='hp'then assert(integer(value,0,mon.stats.hp),'invalid native HP');mon.hp=value
    elseif key=='nickname'then assert(type(value)=='string'and#value<=32,'invalid native nickname');mon.nickname=value
    elseif key=='item'then
     local item=ids:native('items',value);assert(value==0 or item,'unknown native held item');mon.item=item
    else
     assert(integer(value,0,255),'invalid native status')
     local inverse={[8]='PSN',[16]='BRN',[32]='FRZ',[64]='PAR',[128]='PSN'}
     assert(value==0 or value<=7 or inverse[value],'unsupported combined native status')
     mon.status=value>0 and(value<=7 and'SLP'or inverse[value])or nil
     mon.sleepTurns=value>0 and value<=7 and value or nil;mon.toxic=value==128 or nil
    end
   elseif kind=='state'and not reserved[key]then
    -- Presentation extensions belong to this view; they cannot replace the
    -- controller's command queue, party aliases or completion result.
    rawset(t,key,value)
   else error('native battle '..kind..' '..tostring(key)..' is not directly writable',2)end
  end})
  -- LuaJIT does not consult __pairs. Keep registry values weak so its
  -- weak key cannot retain itself through this environment's public view.
  local observation=setmetatable({environment=e,entry=d},{__mode='v'})
  Iteration.register(view,function(spec,source)
   local environment,entry=spec.environment,spec.entry
   assert(environment and entry,'native battle view retired')
   local out={};for key,value in Iteration.rawPairs(source)do out[key]=value end
   if entry.snapshot then for key,value in pairs(entry.snapshot)do out[key]=value end;return out end
   assert(environment.context and environment.valid(),'native battle view retired')
   local keys=entry.kind=='state'and stateKeys or entry.kind=='battler'and battlerKeys or entry.kind=='mon'and monKeys
     or{'attack','defense','speed','spAtk','spDef','accuracy','evasion'}
   for _,key in ipairs(keys)do out[key]=environment.read(entry,key)end
   return out
  end,observation)
  return view
 end
 local function partyIndex(party,mon)for i,value in ipairs(party or{})do if value==mon then return i end end end
 local function party()local c=e.context;return c.screen.playerParty or c.game.save.party or{}end
 local function moveArrays(mon)
  local d=e.moveArrays and e.moveArrays[mon]
  if not d then
   e.moveArrays=e.moveArrays or{};d={moves={},pp={},maxPp={},baseline={}};e.moveArrays[mon]=d
  end
  -- PP edits use an explicit native transaction before the next native body.
  if not d.pending then
   for _,key in ipairs{'moves','pp','maxPp'}do for i in pairs(d[key])do d[key][i]=nil end end
   d.baseline={};d.ids={};d.maximum={}
   for i,mv in ipairs(mon.moves or{})do
    d.moves[i]=ids:read('moves',mv.id);d.pp[i]=mv.pp;d.baseline[i]=mv.pp
    local def=(e.context.data.moves or{})[mv.id]
    d.maxPp[i]=def and def.pp and def.pp+math.floor(def.pp/5)*(mv.ppUps or 0)or nil
    d.ids[i]=d.moves[i];d.maximum[i]=d.maxPp[i]
   end
   d.pending=true
  end
  return d
 end
 read=function(d,key)
  local raw=d.raw;local c=e.context
  if d.kind=='mon'then
   if key=='species'then return ids:read('pokemon',raw.species)end
   if key=='item'then return ids:read('items',raw.item)end
   if key=='ability'then
    local b;for pos=0,3 do local actual=at(pos);if actual and actual.mon==raw then b=actual;break end end
    return ids:read('abilities',b and b.ability or raw.ability)
   end
   if key=='hp'then return raw.hp end
   if key=='maxHp'then return raw.stats and raw.stats.hp end
   if statNames[key]then return raw.stats and raw.stats[statNames[key]]end
   if key=='status'then return status(raw)end
   if key=='moves'or key=='pp'or key=='maxPp'then return moveArrays(raw)[key]end
   if key=='otId'then return raw.otId or raw.otID end
   if key=='otSecretId'then return raw.otSecretId or raw.secretId end
   if key=='friendship'then return raw.friendship or raw.happiness end
   if key=='nickname'or key=='level'or key=='personality'or key=='isEgg'then return raw[key]end
  elseif d.kind=='battler'then
   local pos=raw.position
   if pos==nil then for i=0,3 do if at(i)==raw then pos=i;break end end end
   if key=='id'then return pos end
   if key=='side'then return pos and(pos%2==0 and'player'or'enemy')end
   if key=='flank'then return pos and(pos<2 and'left'or'right')end
   if key=='mon'then return proxy('mon',raw.mon)end
   if key=='species'then return ids:read('pokemon',raw.species or raw.mon.species)end
   if key=='ability'then return ids:read('abilities',raw.ability)end
   if key=='item'then return ids:read('items',raw.mon.item)end
   if key=='status'then return status(raw.mon)end
   if key=='fainted'then return raw.fainted==true or raw.mon.hp<=0 end
   if key=='partyIndex'then return partyIndex(pos and pos%2==0 and party()or c.screen.enemyParty,raw.mon)or 1 end
   if key=='stages'then return proxy('stages',raw.stages or{})end
   if key=='type1'or key=='type2'then return ids:read('types',(raw.curTypes or{})[key=='type1'and 1 or 2])end
  elseif d.kind=='stages'then return raw[statNames[key]or key]
  elseif d.kind=='state'then
   if key=='player'or key=='enemy'then return proxy('battler',raw[key])end
   if key=='battlers'then
    e.battlers=e.battlers or{};for pos=0,3 do e.battlers[pos]=proxy('battler',at(pos))end;return e.battlers
   end
   if key=='party'or key=='playerParty'then return collection('party',party(),function(mon)return proxy('mon',mon)end)end
   if key=='enemyParty'then
    e.wildParty=e.wildParty or{};e.wildParty[1]=raw.enemy and raw.enemy.mon
    return collection('enemyParty',raw.enemyParty or e.wildParty,function(mon)return proxy('mon',mon)end)
   end
   if key=='turn'then return raw.turnCount or 0 end
   if key=='wild'then return raw.kind=='wild'end
   if key=='double'then return raw.isDouble and raw:isDouble()or raw.double==true end
   if key=='over'then return raw.result~=nil or raw.dead==true end
   if key=='result'then return raw.result end
   if key=='weather'then return raw.field and raw.field.weather end
   if key=='weatherTurns'then return raw.field and raw.field.weatherTurns end
   if key=='playerIndex'then return partyIndex(party(),raw.player and raw.player.mon)end
   if key=='enemyIndex'then return raw.enemyIndex or(raw.enemy and 1)end
   if key=='trainerClass'then return raw.trainer and raw.trainer.class or raw.trainerClass end
   if key=='trainerName'then return raw.trainerName or raw.trainer and raw.trainer.name end
   if key=='trainerPicId'then return raw.trainer and(raw.trainer.picIndex or raw.trainer.index)end
   if key=='session'then return require('src.core.Game3').forNative(c.game).session end
   if key=='link'then return raw.kind=='link'end
   if key=='safari'then return raw.safari~=nil and raw.safari~=false end
   if key=='ghostBattle'then return raw.ghost==true end
   if key=='tutorial'or key=='oldManTutorial'then return raw.demo==true or raw.dudeDemo==true end
   if key=='pokedude'then return raw.pokedudeDemo~=nil and raw.pokedudeDemo~=false end
   if key=='firstBattle'then return raw.firstBattle==true end
   if key=='kinds'then
    e.kinds=e.kinds or{};e.kinds.tutorial=raw.pokedudeDemo and'pokedude'or(raw.demo and'oldMan'or nil);return e.kinds
   end
   if key=='rng'then return e.rng end
  end
 end
 e.read=read
 e.view=proxy('state',screen)
 e.rng=function(...)assert(e.context and e.valid(),'native battle RNG retired');return e.context.screen.rng(...)end
 function e:flush()
  if not self.context or not self.valid()then return false end
  local writes={}
  for mon,d in pairs(self.moveArrays or{})do
   for i,value in pairs(d.moves)do assert(value==d.ids[i],'source move replacement requires native move learning')end
   for i,value in pairs(d.ids)do assert(d.moves[i]==value,'source move replacement requires native move learning')end
   for i,value in pairs(d.maxPp)do assert(value==d.maximum[i],'source maximum PP is read-only')end
   for i,value in pairs(d.maximum)do assert(d.maxPp[i]==value,'source maximum PP is read-only')end
   for i in pairs(d.baseline)do assert(d.pp[i]~=nil,'source PP slot cannot be removed')end
   for i,value in pairs(d.pp)do
    assert(d.baseline[i]~=nil,'unknown source PP slot')
    if value~=d.baseline[i]then
     local mv=mon.moves and mon.moves[i];local maximum=d.maxPp[i]
     assert(mv and mv.pp==d.baseline[i],'native move PP changed during source edit')
     assert(integer(value,0,maximum or 99),'invalid source move PP')
     writes[#writes+1]={move=mv,value=value}
    end
   end
  end
  for _,write in ipairs(writes)do write.move.pp=write.value end
  for mon,d in pairs(self.moveArrays or{})do d.pending=false;moveArrays(mon)end
  return true
 end
 function e:retire()
  if self.retired then return end
  for mon,d in pairs(self.moveArrays or{})do d.pending=false;moveArrays(mon)end
  -- Populate only declared observations. No native queue, functions, save or
  -- data table is copied into the completed record or retained by its views.
  local seen={}
  repeat
   local pending=false
   for view,d in pairs(self.entries)do if not seen[view]then
   pending=true;seen[view]=true;local snapshot={}
   for _,key in ipairs(d.kind=='state'and stateKeys or d.kind=='battler'and battlerKeys or d.kind=='mon'and monKeys or{'attack','defense','speed','spAtk','spDef','accuracy','evasion'})do
    if key~='session'and key~='rng'then snapshot[key]=read(d,key)end
   end
   d.snapshot=snapshot
   end end
   if not pending then break end
  until false
  for _,d in pairs(self.entries)do d.raw=nil end
  self.context,self.moveArrays,self.wildParty,self.valid=nil,nil,nil,function()return false end
  self.retired=true;ids=nil
 end
 return e
end
return M
