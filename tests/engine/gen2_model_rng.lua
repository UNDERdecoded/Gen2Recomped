-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Actual source consumers must share the native stream, including after its
-- function is replaced. No shadow generator, draws on lookup or saved closures.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Model=require('src.battle.gen2.Battle')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local before=V.get()
for _,edition in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 local run=T.sdk.loadMods({'mods/rng_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/rng_probe/manifest.json']='{"id":"rng_probe","name":"Native RNG probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/rng_probe/main.lua']=[[
   local mod=...
   local Battle=require('src.battle.gen2.Battle')
   mod.exports.love=function(model,lo,hi)return model.rng(lo,hi)end
   mod.exports.cart=function(model,n)return model.random(n)end
   mod.exports.method=function(model,n)return Battle.roller(model)(n)end
   mod.exports.decorate=function()
    local native=Battle.roller
    Battle.roller=function(model)
     mod.exports.lookups=(mod.exports.lookups or 0)+1
     return native(model)
    end
   end
  ]],
 })})
 T.eq(#run.errors,0,'actual API2 source RNG consumer loads')
 require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',25)}
 local b=Screen.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',30)
 local probe=run.loader.exports.rng_probe
 local trace={}
 local function stream(tag)
  return function(lo,hi)
   local first,last=lo,hi
   if hi==nil then lo,hi=1,lo end
   trace[#trace+1]={tag=tag,lo=first,hi=last}
   return lo+(#trace*37)%(hi-lo+1)
  end
 end
 local native=stream('initial');b.rng=native
 local model=b.battle
 T.eq(type(model.rng),'function',edition..' source LOVE RNG exists')
 T.eq(type(model.random),'function','source zero-based random exists')
 T.eq(type(model.roller),'function','source roller method exists')
 if type(model.rng)=='function'and type(model.random)=='function'and type(model.roller)=='function'then
  local loveRng,random,roller=model.rng,model.random,model:roller()
  T.eq(model.rng,loveRng,'LOVE adapter identity is stable')
  T.eq(model.random,random,'zero-based adapter identity is stable')
  T.eq(model:roller(),roller,'roller identity is stable')
  T.check(random~=roller,'source random field remains separate from the roller method wrapper')
  T.eq(#trace,0,'lookup and cache creation consume no native draws')
  for n=1,256 do
   local index=#trace+1
   T.eq(probe.love(model,n),1+(index*37)%n,'source LOVE result uses the next actual native draw')
   T.eq(#trace,index,'one actual draw for LOVE call')
   index=#trace+1
   T.eq(probe.cart(model,n),(index*37)%n,'source random uses zero-based native result')
   T.eq(#trace,index,'one actual draw for source random')
   index=#trace+1
   T.eq(probe.method(model,n),(index*37)%n,'public class roller uses the next same native draw')
   T.eq(#trace,index,'one actual draw for source roller')
  end
  for _,bounds in ipairs{{5,9},{9,5},{-3,2},{4,4}}do
   local lo,hi=math.min(bounds[1],bounds[2]),math.max(bounds[1],bounds[2])
   local index=#trace+1
   T.eq(probe.love(model,bounds[1],bounds[2]),lo+(index*37)%(hi-lo+1),'source range normalization uses native draw')
   T.eq(trace[index].lo,lo,'normalized native lower bound')
   T.eq(trace[index].hi,hi,'normalized native upper bound')
  end
  for _,bound in ipairs{0,-7}do
   local index=#trace+1
   T.eq(probe.love(model,bound),1,'source small bound normalizes to one')
   T.eq(#trace,index,'normalized one-point range still consumes one actual draw')
  end
  local index=#trace+1
  T.eq(probe.love(model),1,'source missing bound normalizes to one')
  T.eq(#trace,index,'missing bound uses one actual native draw')
  local replacement=stream('replacement');b.rng=replacement
  index=#trace+1
  T.eq(loveRng(2,8),2+(index*37)%7,'retained LOVE view follows replacement owner')
  T.eq(trace[index].tag,'replacement','retained LOVE view cannot draw from old function')
  index=#trace+1
  T.eq(random(256),(index*37)%256,'retained random follows replacement owner')
  T.eq(trace[index].tag,'replacement','retained zero-based view cannot draw from old function')
  index=#trace+1
  T.eq(roller(255),(index*37)%255,'retained roller follows replacement owner')
  T.eq(trace[index].tag,'replacement','retained roller cannot draw from old function')
  T.eq(b.rng,replacement,'adapters never replace the actual native function')
  b:switchPlayerInto(Screen.POS.PLAYER_LEFT,save.party[2])
  T.eq(b.battle,model,'real native switch retains its model')
  T.eq(model.rng,loveRng,'real native switch retains LOVE adapter')
  T.eq(model:roller(),roller,'real native switch retains source roller')
  index=#trace+1
  T.eq(probe.method(model,256),(index*37)%256,'incoming actor shares the same real stream')
  T.eq(#trace,index,'incoming actor does not create another generator')
  probe.decorate()
  local count=#trace
  T.eq(model.random,random,'decorating roller does not replace the source random field')
  T.eq(model.rng,loveRng,'decorating roller does not replace source LOVE field')
  T.eq(probe.lookups,nil,'source field lookup does not invoke a decorated roller method')
  index=#trace+1
  T.eq(probe.method(model,255),(index*37)%255,'actual API2 roller decoration keeps native draw ownership')
  T.eq(probe.lookups,1,'actual API2 consumer reaches the live class decoration')
  T.eq(#trace,count+1,'decoration lookup itself adds no draw')
  T.raises(function()model.rng=function()end end,'read-only','source view cannot replace native RNG authority')
  T.raises(function()model.random=function()end end,'read-only','source view cannot replace cart RNG authority')
  T.raises(function()model.roller=function()end end,'read-only','source metadata cannot replace the public method')
 end
 for _,mon in ipairs(save.party)do
  T.eq(mon.rng,nil,'no RNG function enters party mon')
  T.eq(mon.random,nil,'no random function enters party mon')
  T.eq(mon._nativeRoller,nil,'no adapter cache enters party mon')
 end
 run.release()
end
-- Internal adapter cycles must be collectible when their native owner and
-- caller references end. A global value closure retaining a weak key is not.
local weak=setmetatable({},{__mode='k'})
local function retired()
 local screen={rng=function(n)return n end};local model=Model.bind({},screen)
 Model.roller(model);weak[model]=true;weak[screen]=true
end
for _=1,12 do retired()end
collectgarbage('collect');collectgarbage('collect')
T.eq(next(weak),nil,'retired model/RNG adapters do not leak through module state')
V.set(before)
T.finish('native source model RNG fields, domains, replacement, switch and lifetime')
