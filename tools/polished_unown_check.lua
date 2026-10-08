local Version=require("src.core.GameVersion")
Version.set("polishedcrystal")
local U=require("src.pokemon.PolishedUnown")
local S=require("src.pokemon.Sprites")
local Serializer=require("src.core.SaveSerializer")
local forms={}
for i=1,28 do forms[i]={spriteFront="front"..i,spriteBack="back"..i} end
local data={pokemon={SPECIES_201={forms=forms,spriteFront="base",spriteBack="base",name="UNOWN"}},constants={gen=2}}
local save={party={},player={name="TEST",id=123,map="RUINS_OF_ALPH_OUTSIDE"},pokedex={owned={SPECIES_201=true},seen={}},flags={}}
for group=0,3 do
 save.g2Wram={[U.address]=2^group}
 local expected=U.groups[group+1]
 for i=1,#expected do assert(U.choose(save,function(lo,hi)assert(lo==1 and hi==#expected);return i end)==expected[i])end
end
save.g2Wram={}
for i=0,3 do U.unlock(save,i);U.unlock(save,i)end
assert(save.g2Wram[U.address]==15)
for i=1,28 do assert(U.choose(save,function()return i end)==i)end
local B=require("src.battle.BattleState")
for _,form in ipairs({2,17,27,28})do
 local mon={species="SPECIES_201",form=form,level=5,dvs={attack=0,defense=0,speed=0,special=0},moves={},hp=20,stats={hp=20}}
 local game={data=data,save=save}
 local battle=setmetatable({game=game,enemy={mon=mon,name="UNOWN"},lastBall="POKE_BALL",restoreMimicked=function()end,
 sayNext=function()end,uiNext=function()end},{__index=B})
 battle:storeCaughtMon()
 assert(save.party[#save.party]==mon and mon.form==form,"capture changed form")
 assert(S.path(data,mon.species,"front",{mon=mon})=="front"..form)
 assert(S.path(data,mon.species,"back",{mon=mon})=="back"..form)
end
local reloaded=assert(Serializer.decode(Serializer.encode(save)))
for i,mon in ipairs(reloaded.party)do assert(mon.form==save.party[i].form); assert(S.formIndex(data.pokemon.SPECIES_201,mon)==mon.form)end
local boxed={species="SPECIES_201",form=28,dvs={attack=0,defense=0,speed=0,special=0}}
assert(require("src.pokemon.Boxes").deposit(save,boxed))
local loaded=assert(Serializer.decode(Serializer.encode(save)))
assert(loaded.boxes[1][1].form==28)
Version.set("crystal")
assert(S.formIndex(data.pokemon.SPECIES_201,{form=28,dvs={attack=0,defense=0,speed=0,special=0}})==1,"vanilla DV forms changed")
print("PASS ROM letter groups, all 28 forms, puzzle unlock persistence")
print("PASS real capture retains form, front/back sprites, party and box save roundtrip")
print("PASS vanilla Crystal retains DV-derived forms")
