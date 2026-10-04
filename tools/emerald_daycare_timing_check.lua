package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald daycare timing')
local V=require('src.core.GameVersion');V.set('emerald')
local DC=require('src.pokemon.DayCare')
local P=require('src.pokemon.Pokemon')
local root='G:/Gen2Recomped/emerald/data/generated/'
local data={}
for _,key in ipairs({'constants','pokemon','moves'}) do data[key]=assert(loadfile(root..key..'.lua'))() end
require('src.pokemon.Growth').setTables(data.constants.experienceTables)
local function pair(species,ot)
  local save={flags={},party={}}
  local a=P.new(data,'PIKACHU',20);a.personality=0;a.otId=1
  local b=P.new(data,species or 'PIKACHU',20);b.personality=255;b.otId=ot or 1
  DC.deposit(save,1,a);DC.deposit(save,2,b)
  return save,DC.store(save,false)
end
local random=math.random
local calls=0
math.random=function() calls=calls+1;return 65535 end
local save,breed=pair()
calls=0
for step=1,254 do T.eq(DC.step(data,save),false,'no attempt before second-slot phase255') end
T.eq(calls,0,'walking before first boundary consumes no breeding random draw')
T.eq(DC.step(data,save),false,'failed roll at first boundary')
T.eq(calls,1,'first roll occurs at255')
for step=256,510 do DC.step(data,save) end
T.eq(calls,1,'no roll between boundaries')
DC.step(data,save);T.eq(calls,2,'next roll at511')
-- Exhaust the integer RNG boundary for each native compatibility tier.
for _,case in ipairs({{'MARILL',1,20},{'PIKACHU',1,50},{'PIKACHU',2,70}}) do
  local boundary=math.ceil(case[3]*65535/100)
  for _,draw in ipairs({0,boundary-1,boundary,65535}) do
    save,breed=pair(case[1],case[2])
    T.eq(DC.gen3Score(data,save),case[3],'real species and ownership yield native tier')
    breed[2].steps=254
    local first=true
    math.random=function(lo,hi)
      if first then first=false;T.eq(lo,0,'production draws16-bit random lower bound');T.eq(hi,65535,'production draws16-bit random upper bound');return draw end
      return lo or 0
    end
    T.eq(DC.step(data,save),draw<boundary,'strict integer compatibility threshold')
  end
end
save,breed=pair()
breed[1].steps=71;breed[2].steps=510
local waiting={isEgg=true,species='PICHU'};breed.egg=waiting
local remaining=breed[2];local removed=breed[1]
T.eq(DC.withdraw(save,1),removed,'withdraw returns selected resident')
T.eq(breed[1],remaining,'second resident shifts into first slot')
T.eq(breed[2],nil,'second slot available after shift')
T.eq(breed[1].steps,510,'earned steps retained on shift')
T.eq(breed.egg,waiting,'withdrawal retains pending egg')
DC.deposit(save,2,P.new(data,'PIKACHU',20))
T.eq(breed[2].steps,0,'replacement resident starts at zero')
T.eq(breed[1].steps,510,'replacement does not reset other resident experience')
T.eq(breed.egg,waiting,'deposit retains pending egg')
breed.egg=nil;breed[2].steps=254
-- A non-breeding pair must not consume an RNG draw even at the boundary.
breed[1].mon.species='DITTO';breed[2].mon.species='DITTO'
calls=0;math.random=function() calls=calls+1;return 0 end
T.eq(DC.step(data,save),false,'incompatible pair never produces egg')
T.eq(calls,0,'incompatible pair avoids production RNG')
-- Exercise the actual script specials used by the attendant, not only the model.
local G3=require('src.script.Gen3Commands')
save,breed=pair();save.vars={VAR_G3_8004=0}
local ctx={save=save,game={data=data}}
local resident=breed[1].mon;local survivor=breed[2]
breed.egg=waiting
G3.SPECIALS[195](ctx)
T.eq(save.party[1],resident,'script withdrawal returns resident to party')
T.eq(breed[1],survivor,'script withdrawal shifts second resident')
T.eq(G3.SPECIALS[185](ctx),1,'attendant still reports waiting egg after withdrawal')
save.gen3EggStepCounter=123
G3.SPECIALS[187](ctx)
T.eq(save.party[2],waiting,'attendant delivers retained egg')
T.eq(breed.egg,nil,'delivery clears waiting egg')
T.eq(save.gen3EggStepCounter,0,'delivery resets hatch cycle phase')
T.eq(G3.SPECIALS[185](ctx),2,'attendant reports one boarded resident after collection')
V.set('gold');save,breed=pair();breed.egg=waiting
DC.withdraw(save,1)
T.eq(breed[1],nil,'Gen2 retains separate pen identities')
T.check(breed[2]~=nil,'Gen2 second pen not shifted')
T.eq(breed.egg,nil,'Gen2 native withdrawal clears pending egg')
math.random=random;V.set('emerald')
T.finish()
