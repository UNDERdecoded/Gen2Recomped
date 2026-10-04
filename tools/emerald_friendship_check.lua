package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald friendship')
local V=require('src.core.GameVersion');V.set('emerald')
local P=require('src.pokemon.Pokemon')
local F=require('src.pokemon.Gen3Friendship')
local root='G:/Gen2Recomped/emerald/data/generated/'
local data={}
for _,key in ipairs({'constants','pokemon','moves'}) do data[key]=assert(loadfile(root..key..'.lua'))() end
require('src.pokemon.Growth').setTables(data.constants.experienceTables)
for species,def in pairs(data.pokemon) do
  if type(def)=='table' and def.friendship~=nil then
    T.eq(P.new(data,species,5).happiness,def.friendship,'factory seeds native friendship for '..species)
  end
end
local function mon(hp,egg)
  local m=P.new(data,'PIKACHU',20);m.happiness=100;m.hp=hp or 20;m.isEgg=egg
  return m
end
local a,b,e=mon(),mon(0),mon(20,true)
local save={party={a,b,e}};local calls=0
local rng=function(lo,hi) T.eq(lo,0,'native friendship random lower bound');T.eq(hi,65535,'native friendship random upper bound');calls=calls+1;return calls%2==1 and 0 or 1 end
for step=1,127 do F.step(data,save,{},rng) end
T.eq(calls,0,'first127 steps do not roll friendship')
F.step(data,save,{},rng)
T.eq(calls,2,'each resident rolls independently, eggs excluded')
T.eq(a.happiness,101,'even random result gives native +1')
T.eq(b.happiness,100,'odd random result gives no friendship')
T.eq(e.happiness,100,'egg friendship untouched')
save.gen3FriendshipSteps=127;calls=0
F.step(data,save,{},function() calls=calls+1;return calls==1 and 1 or 0 end)
T.eq(a.happiness,101,'other resident can fail next independent roll')
T.eq(b.happiness,101,'fainted residents still gain walking friendship')
for _,bell in ipairs({false,true}) do
  for _,luxury in ipairs({false,true}) do
    for _,birthplace in ipairs({false,true}) do
      a=mon();a.item=bell and 'SOOTHE_BELL' or nil;a.ball=luxury and 'LUXURY_BALL' or 'POKE_BALL';a.metLocation=birthplace and 7 or 6
      save={party={a},gen3FriendshipSteps=127}
      F.step(data,save,{regionMapSection=7},function() return 0 end)
      T.eq(a.happiness,101+(luxury and 1 or 0)+(birthplace and 1 or 0),'native bonus order, including Soothe Bell rounding')
    end
  end
end
for h=253,255 do
  a=mon();a.happiness=h;a.ball='LUXURY_BALL';a.metLocation=7
  save={party={a},gen3FriendshipSteps=127};F.step(data,save,{regionMapSection=7},function() return 0 end)
  T.eq(a.happiness,255,'friendship caps at255')
end
a=mon();a.happiness=nil;save={party={a},gen3FriendshipSteps=127}
F.step(data,save,{},function() return 1 end)
T.eq(a.happiness,data.pokemon.PIKACHU.friendship,'legacy missing friendship seeds native species value')
-- Save serialization preserves the walking phase, unlike the old state-local counter.
a=mon();save={party={a}}
for step=1,70 do F.step(data,save,{},function() error('premature roll') end) end
local resumed={party=save.party,gen3FriendshipSteps=save.gen3FriendshipSteps}
for step=71,127 do F.step(data,resumed,{},function() error('premature roll after reload') end) end
F.step(data,resumed,{},function() return 0 end)
T.eq(a.happiness,101,'walking phase resumes across saved state')
V.set('gold');T.eq(P.new(data,'PIKACHU',5).happiness,70,'Gen2 factory friendship unchanged')
V.set('red');T.eq(P.new(data,'PIKACHU',5).happiness,nil,'Gen1 does not acquire friendship')
V.set('emerald');T.finish()
