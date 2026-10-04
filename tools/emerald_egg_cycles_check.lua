package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald egg cycles')
local Version=require('src.core.GameVersion');Version.set('emerald')
local Eggs=require('src.pokemon.Gen3EggCycles')
local data={pokemon=assert(loadfile('G:/Gen2Recomped/emerald/data/generated/pokemon.lua'))()}
local function egg(cycles) return {species='TOGEPI',isEgg=true,eggSteps=cycles*256} end
local save={party={egg(1)}}
for i=1,254 do T.eq(Eggs.advance(data,save),nil,'no hatch before native cycle '..i) end
T.eq(save.party[1].eggSteps,256,'no per-step countdown')
T.eq(Eggs.advance(data,save),nil,'zero reached without immediate hatch')
T.eq(save.party[1].eggSteps,0,'first cycle decrements')
for i=1,255 do T.eq(Eggs.advance(data,save),nil,'next cycle not yet due '..i) end
T.eq(Eggs.advance(data,save),save.party[1],'zero hatches on next cycle')
for _,ability in ipairs({'FLAME_BODY','MAGMA_ARMOR'}) do
  local hotSpecies,slot
  for id,def in pairs(data.pokemon) do
    for i,name in ipairs(def.abilities or {}) do if name==ability then hotSpecies,slot=id,i;break end end
    if hotSpecies then break end
  end
  T.check(hotSpecies~=nil,'native species supplies '..ability)
  local hot={species=hotSpecies,abilitySlot=slot,hp=0}
  T.eq(Eggs.subtract(data,{hot}),2,'fainted helper still accelerates '..ability)
  T.eq(Eggs.subtract(data,{hot,hot}),2,'helpers do not stack '..ability)
  hot.isEgg=true;T.eq(Eggs.subtract(data,{hot}),1,'egg cannot supply '..ability)
  hot.isEgg=nil
  save={gen3EggStepCounter=254,party={egg(3),hot,egg(1)}}
  T.eq(Eggs.advance(data,save),nil,'boosted decrement does not hatch immediately')
  T.eq(save.party[1].eggSteps,256,'boost removes two cycles')
  T.eq(save.party[3].eggSteps,0,'one remaining cycle never underflows')
end
local first,last=egg(0),egg(5)
save={gen3EggStepCounter=254,party={first,last}}
T.eq(Eggs.advance(data,save),first,'party order selects first ready egg')
T.eq(last.eggSteps,1280,'ready egg ends scan before later eggs decrement')
first.isBadEgg=true;save.gen3EggStepCounter=254
T.eq(Eggs.advance(data,save),nil,'bad egg does not hatch')
T.eq(last.eggSteps,1024,'later valid egg still progresses')
save={gen3EggStepCounter=254,party={{species='TOGEPI',isEgg=true,eggSteps=257}}}
Eggs.advance(data,save);T.eq(save.party[1].eggSteps,256,'legacy partial steps round upward')
save={party={}}
for i=1,255 do Eggs.advance(data,save) end
T.eq(save.gen3EggStepCounter,255,'phase advances without eggs')
Eggs.advance(data,save);T.eq(save.gen3EggStepCounter,0,'byte wraps rather than reset at 255')
local OW=require('src.world.OverworldController')
local game={data=data,save={gen3EggStepCounter=254,party={egg(0)}}}
for i=1,100 do local n=debug.getupvalue(OW.stepEggs,i);if n=='Game' then debug.setupvalue(OW.stepEggs,i,game);break end end
local hatched
local ow=setmetatable({hatchEgg=function(_,mon) hatched=mon;return true end},{__index=OW})
T.eq(ow:stepEggs(),true,'overworld dispatches native ready egg')
T.eq(hatched,game.save.party[1],'overworld passes correct egg to hatch scene')
local Commands=require('src.script.Gen3Commands')
local DayCare=require('src.pokemon.DayCare')
local breed=DayCare.store(game.save,true);breed.egg=egg(20)
game.save.gen3EggStepCounter=170
Commands.SPECIALS[187]({save=game.save,game=game})
T.eq(game.save.gen3EggStepCounter,0,'daycare collection resets shared phase')
breed.egg=egg(20);game.save.gen3EggStepCounter=80
Commands.SPECIALS[186]({save=game.save,game=game})
T.eq(game.save.gen3EggStepCounter,0,'daycare rejection resets shared phase')
Version.set('firered');game.save.gen3EggStepCounter=79;breed.egg=egg(20)
Commands.SPECIALS[186]({save=game.save,game=game})
T.eq(game.save.gen3EggStepCounter,79,'FireRed behavior isolated')
Version.set('emerald')
T.finish()
