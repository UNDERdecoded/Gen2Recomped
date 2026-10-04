package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald field poison')
local V=require('src.core.GameVersion');V.set('emerald')
local OW=require('src.world.OverworldController')
local P=require('src.pokemon.Pokemon')
local root='G:/Gen2Recomped/emerald/data/generated/'
local data={}
for _,key in ipairs({'constants','pokemon','moves','audio'}) do data[key]=assert(loadfile(root..key..'.lua'))() end
require('src.pokemon.Growth').setTables(data.constants.experienceTables)
local game={data=data}
for i=1,100 do local name=debug.getupvalue(OW.applyFieldPoison,i);if name=='Game' then debug.setupvalue(OW.applyFieldPoison,i,game);break end end
local Text=require('src.render.TextBox');local new=Text.new
Text.new=function(_,line,done) return {line=line,onDone=done} end
local Sound=require('src.core.Sound');local play,named=Sound.play,Sound.playNamedEffect
local noises={}
Sound.play=function(_,name) noises[#noises+1]=name end
Sound.playNamedEffect=function(_,name) noises[#noises+1]=name end
local Data=require('src.core.Data');local previousMoves=Data.moves;Data.moves=data.moves
local messages={}
game.stack={push=function(_,state) messages[#messages+1]=state end}
local function mon(hp,status,happiness,name)
  local m=P.new(data,'PIKACHU',20);m.hp=hp;m.status=status;m.happiness=happiness or 70;m.nickname=name or 'TEST'
  return m
end
local ow=setmetatable({map={def={mapType='ROUTE'}},healPoint=function() return {map='HOME'} end,warpToHealPoint=function(self,_,opts) self.warped=opts.whiteout end},{__index=OW})
local function reset(party,phase)
  game.save={party=party,poisonSteps=phase or 0,money=1001,flags={},player={name='BRENDAN'}}
  messages={};noises={};ow.poisonFlash=nil;ow.warped=nil;ow.map.def.mapType='ROUTE'
end
for _,status in ipairs({'PSN','TOX'}) do
  local m=mon(3,status);reset({m})
  for step=1,3 do T.eq(ow:applyFieldPoison(),false,'first three steps do not interrupt');T.eq(m.hp,3,'first three steps cause no damage') end
  T.eq(ow:applyFieldPoison(),false,'nonfainting poison keeps movement available')
  T.eq(m.hp,2,'both poison types lose one HP on fourth step')
  T.eq(m.status,status,'surviving poison remains active in Emerald')
  T.eq(noises[1],'FIELD_POISON','native extracted field poison sound selected')
  T.eq(#messages,0,'damage alone does not show dialogue')
end
for happiness=0,255 do
  local m=mon(1,'TOX',happiness);reset({m,mon(5,nil)})
  game.save.poisonSteps=3
  T.eq(ow:applyFieldPoison(),true,'poison faint interrupts overworld')
  T.eq(m.hp,0,'Emerald poison can faint')
  T.eq(m.status,nil,'fainted poison status cleared')
  local loss=happiness<200 and 5 or 10
  T.eq(m.happiness,math.max(0,happiness-loss),'native friendship threshold and clamp')
  T.eq(messages[1].line,'TEST fainted…','native fainted text and punctuation')
  messages[1].onDone()
  T.eq(#messages,1,'healthy teammate prevents blackout')
end
local m=mon(2,'PSN');reset({m},3);ow.map.def.mapType='SECRET_BASE'
for step=1,20 do T.eq(ow:applyFieldPoison(),false,'Secret Base does not interrupt walking') end
T.eq(game.save.poisonSteps,3,'Secret Base preserves poison phase')
T.eq(m.hp,2,'Secret Base suppresses poison damage')
T.eq(#noises,0,'Secret Base suppresses poison effect sound')
ow.map.def.mapType='ROUTE';ow:applyFieldPoison();T.eq(m.hp,1,'leaving Secret Base resumes existing phase')
-- Native task also resolves an already-fainted poisoned resident, once.
m=mon(0,'PSN',200);reset({m,mon(5,nil)},3)
ow:applyFieldPoison();T.eq(m.status,nil,'already-fainted poison clears')
T.eq(m.happiness,190,'already-fainted poison penalty applied')
messages[1].onDone();game.save.poisonSteps=3;ow:applyFieldPoison()
T.eq(m.happiness,190,'cleared status prevents repeated friendship penalty')
local egg=mon(5,nil);egg.isEgg=true;egg.eggSteps=256
reset({mon(1,'PSN',70,'FIRST'),mon(1,'TOX',70,'SECOND'),egg},3)
ow:applyFieldPoison()
T.eq(messages[1].line,'FIRST fainted…','party faint messages start in slot order')
messages[1].onDone();T.eq(messages[2].line,'SECOND fainted…','second faint waits for first acknowledgement')
messages[2].onDone();T.eq(#messages,3,'healthy egg does not prevent blackout')
T.eq(ow.warped,nil,'blackout waits for acknowledgement')
messages[3].onDone();T.eq(ow.warped,true,'blackout warps to heal point')
T.eq(game.save.money,500,'ordinary Emerald blackout halves money')
T.eq(game.save.party[1].hp,game.save.party[1].stats.hp,'blackout restores party HP')
-- Other generations retain their previously tested poison rules.
V.set('gold');m=mon(1,'PSN',200);reset({m,mon(5,nil)},3)
ow:applyFieldPoison();T.eq(m.happiness,190,'Gold poison friendship penalty retained')
T.eq(noises[1],'Poisoned','Gold keeps shared poison sound')
T.eq(messages[1].line,'TEST\nfainted!','Gold keeps its fainted line')
V.set('platinum');m=mon(2,'TOX',200);reset({m},3)
ow:applyFieldPoison();T.eq(m.hp,1,'Platinum field poison does not faint')
T.eq(m.status,nil,'Platinum survives and clears poison')
T.eq(m.happiness,190,'Platinum survival penalty retained')
Text.new=new;Sound.play=play;Sound.playNamedEffect=named;Data.moves=previousMoves;V.set('emerald')
T.finish()
