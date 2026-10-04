love=require("tests.love_stub")
local T=require("tests.harness").suite("Gen 2 egg inheritance and hatch")
local DC=require("src.pokemon.DayCare")
local B=require("src.pokemon.Gen2Breeding")
local Version=require("src.core.GameVersion")
local Stats=require("src.pokemon.Stats")
local Game=require("src.core.Game")
local OW=require("src.world.OverworldController")
for i=1,20 do
  local name=debug.getupvalue(OW.hatchEgg,i)
  if not name then break end
  if name=="Game" then debug.setupvalue(OW.hatchEgg,i,Game);break end
end
local TextBox=require("src.render.TextBox")
TextBox.new=function(_,text,done,opts) return {text=text,onDone=done,choice=opts and opts.choice} end
require("src.battle.BattleState").metHere=function() return "ROUTE34" end
local names,emits=0,0
require("src.ui.Screens").push=function(_,screen,opts)
  T.eq(screen,"NamingScreen","hatch opens naming screen")
  T.eq(opts.maxLen,10,"Gen 2 nickname limit")
  names=names+1;opts.onDone("BABY")
end
require("src.mods.Runtime").emit=function(event) if event=="pokemon.egg_hatched" then emits=emits+1 end end
for _,version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local root=(arg[1] or "G:/Gen2Recomped").."/"..version.."/data/generated/"
  local data={constants={gen=2}}
  for _,name in ipairs({"pokemon","moves"}) do data[name]=assert(loadfile(root..name..".lua"))() end
  require("src.core.Data").moves=data.moves
  local mother={species="SPECIES_152",dvs={attack=0,defense=3,special=7},moves={{id="GROWL"}},otId=1}
  local father={species="SPECIES_152",dvs={attack=15,defense=12,special=2},moves={{id="GROWL"}},otId=2}
  local save={flags={},player={name="GOLD",id=4242}}
  DC.deposit(save,1,mother);DC.deposit(save,2,father)
  for _,ditto in ipairs({0,1,2}) do
    local oldA,oldB=mother.species,father.species
    if ditto==1 then mother.species="SPECIES_132" elseif ditto==2 then father.species="SPECIES_132" end
    for atk=0,15 do for spc=0,15 do
      local egg={species="SPECIES_152",level=5,dvs={attack=atk,defense=0,speed=9,special=spc}}
      local parent=ditto==1 and mother or ditto==2 and father or DC.gender(data,egg)=="female" and father or mother
      T.eq(B.inheritDVs(data,save,egg),true,version.." inherits DVs")
      T.eq(egg.dvs.defense,parent.dvs.defense,version.." Defense from correct parent")
      T.eq(egg.dvs.special,math.floor(spc/8)*8+parent.dvs.special%8,version.." inherited low Special bits")
      T.eq(egg.dvs.attack,atk,version.." random Attack retained")
      T.eq(egg.dvs.speed,9,version.." random Speed retained")
      T.eq(egg.dvs.hp,atk%2*8+parent.dvs.defense%2*4+2+parent.dvs.special%2,version.." derived HP DV")
      T.eq(egg.stats.hp,Stats.calc(data.pokemon[egg.species],5,egg.dvs).hp,version.." stats follow inherited DVs")
    end end
    mother.species,father.species=oldA,oldB
  end
  local random=math.random
  mother.species="SPECIES_029";father.species="SPECIES_132"
  local females=0
  for byte=0,255 do
    math.random=function() return byte end
    local species=DC.eggSpecies(data,save)
    T.eq(species,byte<128 and "SPECIES_029" or "SPECIES_032",version.." Nidoran split")
    if species=="SPECIES_029" then females=females+1 end
  end
  T.eq(females,128,version.." Nidoran equal species odds")
  math.random=random;mother.species,father.species="SPECIES_152","SPECIES_152"
  -- A synthetic learnset separates the three inheritance categories while
  -- retaining real moves and parent genders from the extracted dataset.
  local original=data.pokemon.SPECIES_152
  local fixture={};for k,v in pairs(original) do fixture[k]=v end
  fixture.eggMoves={"LEECH_SEED"};fixture.tmhm={"TOXIC"}
  fixture.level1Moves={"GROWL"};fixture.learnset={{level=20,move="GROWL"}}
  data.pokemon.SPECIES_152=fixture
  father.moves={{id="GROWL"},{id="LEECH_SEED"},{id="TOXIC"},{id="GROWL"}}
  local egg={species="SPECIES_152",moves={{id="TACKLE"},{id="SCRATCH"},{id="POUND"},{id="TAIL_WHIP"}}}
  T.eq(DC.inheritMoves(data,save,egg),3,version.." each inherited move taught once")
  for i,id in ipairs({"TAIL_WHIP","GROWL","LEECH_SEED","TOXIC"}) do T.eq(egg.moves[i].id,id,version.." father's slot order retained") end
  data.pokemon.SPECIES_152=original
  local first={isEgg=true,eggSteps=256};local second={isEgg=true,eggSteps=256}
  local clock={party={first,second},g2EggCycleStep=0}
  for i=1,127 do T.eq(B.advanceEggs(clock),nil,version.." waits for hatch cycle") end
  T.eq(B.advanceEggs(clock),first,version.." first egg ready at phase 128")
  T.eq(second.eggSteps,256,version.." later egg not decremented after hatch")
  first.isEgg=nil
  for i=1,255 do T.eq(B.advanceEggs(clock),nil,version.." second egg waits next cycle") end
  T.eq(B.advanceEggs(clock),second,version.." second egg hatches next cycle")
  for _,yes in ipairs({false,true}) do
    local mon={species="SPECIES_175",level=5,isEgg=true,eggSteps=0,ot="OTHER",otId=1,
      nickname="EGG",dvs={hp=0,attack=4,defense=8,speed=8,special=8},moves={{id="GROWL",pp=0}}}
    local pushed={};Game.data=data;Game.save={flags={},party={mon},player={name="GOLD",id=4242}}
    Game.stack={push=function(_,box) pushed[#pushed+1]=box end}
    local beforeNames,beforeEmits=names,emits
    T.eq(OW.hatchEgg({},mon),true,version.." hatch starts")
    T.eq(mon.otId,4242,version.." hatch gets current trainer ID")
    T.eq(mon.ot,"GOLD",version.." hatch gets current trainer name")
    T.eq(Game.save.pokedex.owned.SPECIES_175,true,version.." hatch records caught species")
    T.eq(Game.save.pokedex.seen.SPECIES_175,true,version.." hatch records seen species")
    T.eq(Game.save.flags.EVENT_G2_0084,true,version.." Togepi hatch unlocks Elm call")
    T.eq(mon.hp,mon.stats.hp,version.." hatched mon healed")
    pushed[1].onDone();T.eq(#pushed,2,version.." hatch offers nickname")
    pushed[2].choice(yes)
    T.eq(names-beforeNames,yes and 1 or 0,version.." naming only when accepted")
    T.eq(emits-beforeEmits,1,version.." emits hatch completion once")
    T.eq(mon.nickname,yes and "BABY" or nil,version.." chosen nickname retained")
  end
end
T.finish()
