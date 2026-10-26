package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Version = require('src.core.GameVersion')
local Env = require('src.core.Gen2Environment')
local Map = require('src.world.Map')
require('src.script.Gen2Commands')
local Commands = require('src.script.Commands')
local saved = Version.get()
local names = {'TOWN','ROUTE','INDOOR','CAVE','ENVIRONMENT_5','GATE','DUNGEON'}
for _, version in ipairs(Version.ORDER) do
  Version.set(version)
  local data = {maps={}}
  for id, name in ipairs(names) do
    local def={id='NATIVE'..id,environment=id,group=18,number=id}
    data.maps[def.id]=def
    T.eq(Env.id(def),id,'legacy byte '..version..' '..name)
  end
  local authored = {environment='CAVE',environmentId=2,outdoor=true}
  local custom = {environment='CUSTOM',environmentId=1}
  local missing = {environmentId=3}
  data.maps.AUTHORED, data.maps.CUSTOM, data.maps.MISSING = authored, custom, missing
  data.maps.INVALID={environment=99}; data.maps.FRACTION={environment=1.5}
  data.maps.BAD=false
  local accepted=Env.publish(data)
  T.eq(accepted,Version.isGen2(),'publication scoped to native Gen2 '..version)
  for id, name in ipairs(names) do
    local def=data.maps['NATIVE'..id]
    T.eq(def.environment,Version.isGen2() and name or id,'published native environment '..name)
    T.eq(def.environmentId,Version.isGen2() and id or nil,'original byte retained separately')
    T.eq(def.id,'NATIVE'..id,'map identity unchanged')
    T.eq(def.number,id,'numeric map number unchanged')
    T.eq(Env.id(def),id,'native byte remains readable')
    local ctx={overworld={map={def=def}},save={}}
    Commands.g2_readvar(ctx,15)
    T.eq(ctx.g2Var,id,'actual VM readvar returns original byte '..name)
    T.eq(Map.isOutdoor(def),id==1 or id==2,'actual world outdoor rule '..name)
  end
  T.eq(authored.environment,'CAVE','authored symbolic choice retained')
  T.eq(authored.environmentId,2,'authored native metadata not overwritten')
  T.eq(Env.id(authored),4,'active symbolic choice wins over stale byte')
  T.eq(authored.outdoor,true,'explicit outdoor override retained')
  T.eq(Env.id(custom),nil,'custom environment never inherits stale classification')
  T.eq(custom.environment,'CUSTOM','custom name unchanged')
  T.eq(data.maps.INVALID.environment,99,'unknown byte unchanged')
  T.eq(data.maps.FRACTION.environment,1.5,'fractional byte unchanged')
  T.eq(Env.id(data.maps.INVALID),nil,'unknown byte not guessed')
  T.eq(Env.id(data.maps.FRACTION),nil,'fractional byte not guessed')
  T.eq(Env.id(missing),3,'byte-only cache readable')
  T.eq(missing.environment,Version.isGen2() and 'INDOOR' or nil,'byte-only native cache publication')
  T.eq(Env.publish(data),accepted,'republication safe')
end
Version.set('crystal')
T.eq(Env.publish({}),false,'missing registry safe')
T.eq(Env.id(nil),nil,'missing definition safe')
T.eq(Env.id({environment='4'}),4,'older numeric string readable')
local numeric={maps={ROOM={environment='4'}}};Env.publish(numeric)
T.eq(numeric.maps.ROOM.environment,'CAVE','older numeric string published')
-- Exercise the actual native environment policy methods with a fixture Game;
-- only their shared Game dependency is injected, never the policy results.
local World = require('src.world.OverworldController')
local game = {data={maps={},map_scripts={spawns={centers={CENTER=true},points={DEST={x=5,y=6}}}}},save={}}
local bound = {}
for _, method in ipairs({'bikeAllowed','rememberDigWarp','noteGen2Spawn'}) do
  local fn=World[method]
  for i=1,100 do
    local name, value=debug.getupvalue(fn,i)
    if not name then break end
    if name=='Game' then
      bound[#bound+1]={fn=fn,index=i,previous=value}
      debug.setupvalue(fn,i,game)
      break
    end
  end
end
T.eq(#bound,3,'native Game dependencies found by name')
for _, format in ipairs({'legacy','public'}) do
  for id,name in ipairs(names) do
    game.data.maps.DEST={environment=format=='legacy' and id or name,environmentId=id}
    local world=setmetatable({map={id='DEST',def=game.data.maps.DEST}}, {__index=World})
    T.eq(world:bikeAllowed('DEST'),id==1 or id==2 or id==4 or id==6,'actual bicycle policy '..format..' '..name)
    game.save.lastHeal=nil
    world:noteGen2Spawn('CENTER')
    T.eq(game.save.lastHeal and game.save.lastHeal.map or nil,(id==1 or id==2) and 'DEST' or nil,'actual blackout spawn policy '..format..' '..name)
    if game.save.lastHeal then
      T.eq(game.save.lastHeal.x,5,'actual ROM spawn x retained')
      T.eq(game.save.lastHeal.y,6,'actual ROM spawn y retained')
    end
    for sourceId,sourceName in ipairs(names) do
      game.data.maps.SOURCE={environment=format=='legacy' and sourceId or sourceName,environmentId=sourceId}
      game.save.digWarp=nil;world.digWarp=nil
      world:rememberDigWarp('SOURCE',3,4,'DEST')
      local allowed=(sourceId==1 or sourceId==2) and (id==3 or id==4 or id==6 or id==7)
      T.eq(game.save.digWarp and game.save.digWarp.id or nil,allowed and 'SOURCE' or nil,'actual Dig entry policy '..format..' '..sourceName..' -> '..name)
      if allowed then T.eq(game.save.digWarp.x,3,'actual Dig departure x');T.eq(game.save.digWarp.y,4,'actual Dig departure y') end
    end
  end
end
-- These closures share one Game upvalue, so restore the first captured value.
for i=#bound,1,-1 do debug.setupvalue(bound[i].fn,bound[i].index,bound[i].previous) end
Version.set(saved)
T.finish('Gen2 public environment names and native byte readers')
