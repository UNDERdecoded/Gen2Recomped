package.path='tools/save-editor/?.lua;tools/save-editor/panels/?.lua;'..package.path
local version='platinum'
package.loaded['src.core.GameVersion']={get=function() return version end,isGen4=function() return version=='platinum' end,isGen3=function() return version=='emerald' end,isGen2=function() return false end}
love={math={random=math.random},graphics={setColor=function() end,rectangle=function() end,
 newImage=function() error('asset not mounted') end}}
local Catalog=require('Catalog')
local Ops=require('Ops')
local MonOps=require('MonOps')
local MonEditor=require('MonEditor')
local root=arg[1] or 'G:/Gen2Recomped/platinum/data/generated/'
local data={constants={gen=4},isGen4Cache=true,
 pokemon=assert(loadfile(root..'pokemon.lua'))(),moves=assert(loadfile(root..'moves.lua'))(),items=assert(loadfile(root..'items.lua'))()}
local growth={'MEDIUM_FAST','ERRATIC','FLUCTUATING','MEDIUM_SLOW','FAST','SLOW'}
for _,def in pairs(data.pokemon) do
 local b=def.baseStats;b.spatk=b.spAttack;b.spdef=b.spDefense;b.special=b.spAttack
 def.evYield=def.evYields;def.evYield.spatk=def.evYield.spAttack;def.evYield.spdef=def.evYield.spDefense
 def.growthRate=growth[def.expRate+1];def.level1Moves={}
 for _,row in ipairs(def.learnset or {}) do if row.level<=1 then table.insert(def.level1Moves,row.move) end end
end
local cat=Catalog.build(data)
assert(#cat.species==493 and cat.species[1]==1 and cat.species[493]==493,'Platinum picker exposes empty/egg/form personal records')
data.pokemon.CUSTOM={name='Custom'}
data.pokemon[600]={name='Custom numeric'}
local modded=Catalog.build(data)
assert(#modded.species==495,'native filtering removed custom species')
local S={data=data,cat=cat,save={party={},player={name='Test',id=123},inventory={}},selectedBox=1}
local add=true
local labels={}
local Kit=setmetatable({scale=1,textHeight=function() return 12 end,
 textWidth=function(_,s) return #tostring(s)*6 end,ellipsize=function(_,s) return tostring(s) end,
 textCenter=function(_,s) labels[#labels+1]=s end,
 button=function(_,_,_,_,label) if label=='+ Add mon' and add then add=false;return true end;return false end},
 {__index=function() return function() return false end end})
local Party=require('Party')
-- Real Add button, creation, selection and inspector draw in the same frame.
Party.draw(S,Kit,0,0,1400,900)
assert(#S.save.party==1 and S.editingMon==S.save.party[1] and S.editingMon.species==1)
assert(S.editingMon.level==5 and S.editingMon.otId==123 and S.editingMon.ivs)
assert(S.editingMon.stats.hp>0 and S.dirty)
Party.draw(S,Kit,0,0,1400,900)
for _,id in ipairs({0,1,387,999,'CUSTOM'}) do MonEditor.drawSprite(S,Kit,id,0,0,96) end
assert(labels[#labels]=='CUS','numeric/missing sprite fallback failed')
local Boxes=require('src.pokemon.Boxes');Boxes.load(data)
assert(Ops.boxAdd(S) and S.editingMon.species==1,'box Add uses invalid species')
local empty={data=data,cat={species={}},save={party={},player={},inventory={}},selectedBox=1}
assert(not Ops.partyAdd(empty) and not Ops.boxAdd(empty),'empty species catalog must refuse Add safely')
-- Form recalculation uses the same native stat row as gameplay.
local rotom=require('src.pokemon.Pokemon').new(data,479,50,nil,5)
MonOps.setIv(data,rotom,'defense',31)
assert(rotom.stats.defense==require('src.pokemon.Stats').calcGen3(data.pokemon[507],50,rotom.ivs,rotom.evs,rotom.nature).defense)
local loads,drawn=0,0
love.graphics.newImage=function(path) loads=loads+1;return {path=path,getDimensions=function() return 80,80 end} end
love.graphics.draw=function() drawn=drawn+1 end
local function fixture()
 return {data={constants={gen=4},pokemon={[487]={trueColor=true,spriteFront='normal',spriteShiny='shiny',
  forms={base={species=487,front='normal'},origin={front='origin',shiny_front='origin_shiny'}}}}}}
end
local a,b=fixture(),fixture()
local normal=MonEditor.sprite(a,487,{species=487,form=0})
assert(normal.path=='normal' and MonEditor.sprite(a,487,{species=487,form=0})==normal and loads==1)
assert(MonEditor.sprite(a,487,{species=487,form=1}).path=='origin')
assert(MonEditor.sprite(a,487,{species=487,form=1,shiny=true}).path=='origin_shiny')
assert(MonEditor.sprite(b,487,{species=487,form=0})~=normal and loads==4,'sprite cache crosses datasets')
MonEditor.drawSprite(a,Kit,487,0,0,96,{species=487,form=1,shiny=true});assert(drawn==1)
version='emerald'
local legacy=Catalog.build({constants={gen=3},pokemon={BULBASAUR={},CUSTOM={}},moves={},items={}})
assert(#legacy.species==2 and legacy.species[1]=='BULBASAUR','Gen3 catalog changed')
print('Platinum real Add button + inspector, missing numeric sprites, valid species picker, party/box Add, empty catalogs, form stats/art, shiny selection and dataset cache isolation passed')
