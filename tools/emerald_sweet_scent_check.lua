package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald Sweet Scent encounters')
local Version=require('src.core.GameVersion');Version.set('emerald')
local root='G:/Gen2Recomped/emerald/data/generated/'
local data={}
for _,k in ipairs({'constants','text','field'}) do data[k]=assert(loadfile(root..k..'.lua'))() end
local OW=require('src.world.OverworldController')
local Battle=require('src.battle.BattleState')
local Encounter=require('src.world.Encounter')
local Roam=require('src.world.Gen3Roamers')
local savedNew,savedFor,savedRandom=Battle.newWild,Encounter.forMap,love.math.random
local g={data=data,save={party={{level=100,hp=200,stats={hp=200}}},repelSteps=100,flags={}},stack={push=function() end}}
for i=1,100 do
  local name=debug.getupvalue(OW.gen2SweetScentEncounter,i)
  if name=='Game' then debug.setupvalue(OW.gen2SweetScentEncounter,i,g);break end
end
local spawned,opts,safari,pushed
Battle.newWild=function(_,species,level,options)
  spawned={species,level};opts=options
  return {makeSafari=function(_,state) safari=state end}
end
Encounter.forMap=function() return {grass={rate=0,slots={{species='ZUBAT',level=12}},buckets={100},bucketSpan=100},
 water={rate=0,slots={{species='TENTACOOL',level=20}},buckets={100},bucketSpan=100}} end
love.math.random=function(lo) return lo end
local ow=setmetatable({player={cellX=5,cellY=5},map={id='ROUTE',def={},
  isWaterCell=function() return true end,isEncounterCell=function() return true end}}, {__index=OW})
ow.timeOfDay=function() return 'day' end
ow.pushBattle=function(_,battle) pushed=battle end
for _,water in ipairs({false,true}) do
  ow.player.surfing=water;spawned=nil;opts=nil;safari=nil
  ow:gen2SweetScentEncounter()
  T.eq(spawned[1],water and 'TENTACOOL' or 'ZUBAT','native slot chosen regardless of walking rate')
  T.eq(spawned[2],water and 20 or 12,'native slot level retained')
  T.eq(opts,nil,'ordinary wild battle has no roamer metadata')
  T.eq(g.save.repelSteps,100,'Sweet Scent ignores and preserves Repel')
  g.save.gen3Roamer={active=true,species='LATIAS',map='ROUTE',level=40,hp=37,status='sleep',personality=123,ivs={hp=4}}
  T.check(Roam.at(g.save,'ROUTE'),'test roamer is on the current map')
  ow:gen2SweetScentEncounter()
  T.eq(spawned[1],'LATIAS','roamer checked before regular slot on land/water')
  T.eq(opts and opts.battleType,'roaming','roaming battle rules enabled')
  T.eq(opts and opts.roamer,'gen3','Gen 3 roamer persistence selected')
  T.eq(opts and opts.roamerHP,37,'persistent HP retained')
  T.eq(opts and opts.roamerStatus,'sleep','persistent status retained')
  T.eq(opts and opts.roamerSeed.personality,123,'persistent personality retained')
  g.save.gen3Roamer.map='ELSEWHERE';ow:gen2SweetScentEncounter()
  T.eq(spawned[1],water and 'TENTACOOL' or 'ZUBAT','roamer elsewhere does not replace slot')
  g.save.gen3Roamer=nil
end
g.save.safari={balls=30,steps=500};ow:gen2SweetScentEncounter()
T.eq(safari,g.save.safari,'Safari rules and stock attached to Sweet Scent battle')
T.eq(g.save.safari.steps,500,'Sweet Scent spends no walking steps')
T.check(pushed.onFinish~=nil,'battle retains normal completion handler')
g.save.safari=nil;ow.player.surfing=false
ow.map.isEncounterCell=function() return false end
spawned=nil;ow:gen2SweetScentEncounter()
T.eq(spawned,nil,'nonencounter tile refuses')
Version.set('gold');ow.gen2IsIce=function() return false end
ow.map.isGrassCell=function() return true end
spawned=nil;ow:gen2SweetScentEncounter()
T.eq(spawned,nil,'Gen 2 zero-rate gate preserved')
Version.set('emerald')
Battle.newWild,Encounter.forMap,love.math.random=savedNew,savedFor,savedRandom
local Scent=require('src.world.Gen3SweetScent')
local Sound=require('src.core.Sound')
local named=Sound.playNamedEffect
local effect
Sound.playNamedEffect=function(_,name) effect=name end
for _,success in ipairs({false,true}) do
  local states={}
  local calls=0
  local testGame={data=data,stack={push=function(_,s) states[#states+1]=s end,
    pop=function() table.remove(states) end}}
  local world={gen2SweetScentEncounter=function(_,deferred)
    calls=calls+1;T.eq(deferred,true,'failure dialogue deferred until fade ends')
    if success then testGame.stack:push({battle=true});return true end
    return false
  end}
  local s=Scent.show(testGame,world)
  T.eq(effect,'M_SWEET_SCENT','native effect name dispatched')
  for i=1,39 do s:update() end
  T.eq(s.blend,7,'red fade approaches half blend')
  T.eq(calls,0,'no encounter during fade')
  s:update();T.eq(s.phase,'hold','full fade enters hold')
  T.eq(s.blend,8,'native target blend')
  for i=1,64 do s:update() end
  T.eq(calls,0,'64-frame hold precedes encounter')
  s:update();T.eq(calls,1,'encounter runs once at native hold boundary')
  if success then
    T.check(s.done,'successful sequence terminates')
    T.check(states[1].battle,'battle survives effect stack cleanup')
  else
    T.eq(s.phase,'out','failure restores colors')
    T.eq(states[1],s,'effect remains on top during restoration')
    for i=1,40 do s:update() end
    T.check(s.done,'failed sequence terminates')
    T.eq(s.blend,0,'failure clears red blend')
    T.check(states[1]~=s,'failure dialogue replaces effect')
  end
  s:update();T.eq(calls,1,'finished state cannot repeat encounter')
end
T.eq(Scent.failureText(data),data.text.TEXT_290CB7,'failure text uses extracted Emerald string')
local audio=assert(loadfile(root..'audio.lua'))()
T.eq(audio.songs.SONG_0EC.sfxName,'M_SWEET_SCENT','native effect metadata is in extracted cache')
Sound.playNamedEffect=named
T.finish()
