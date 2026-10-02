package.path='./?.lua;'..package.path
love={}
local Forms=require('src.pokemon.Gen4Forms')
local Sprites=require('src.pokemon.Sprites')
local mons,counts={},{}
for _,row in ipairs(require('src.import.Gen4Otherpoke').FORMS) do
 if row.species>0 then
  local id,key=row.species,row.form
  mons[id]=mons[id] or {forms={},trueColor=true}
  mons[id].forms[key]={species=id,front=key..'_front',back=key..'_back',shiny_front=key..'_shiny_front',shiny_back=key..'_shiny_back',picAnim={sheet=key..'_anim',shinySheet=key..'_shiny_anim',play={{frame=1,dur=4}},count=2}}
 end
end
local data={constants={gen=4},pokemon=mons}
local checked=0
for _,row in ipairs(require('src.import.Gen4Otherpoke').FORMS) do
 if row.species>0 then
  local id,key=row.species,row.form
  local index=counts[id] or 0;counts[id]=index+1
  for _,value in ipairs({index,key}) do
   local mon={species=id,form=value,shiny=false}
   assert(Sprites.formIndex(mons[id],mon)==key,'wrong native form '..id..':'..key)
   for _,side in ipairs({'front','back'}) do
    local path,tc=Sprites.path(data,id,side,{mon=mon})
    assert(path==key..'_'..side and tc,'wrong '..side..' art')
    mon.shiny=true
    assert(Sprites.path(data,id,side,{mon=mon})==key..'_shiny_'..side,'wrong shiny form art')
    mon.shiny=false
   end
  end
  checked=checked+1
 end
end
assert(checked>60,'must cover the native archive form set')
assert(Sprites.formIndex(mons[487],{species='SPECIES_487',form=1})=='origin')
assert(Sprites.formIndex(mons[479],{species=479,gen4Form=5})=='mow')
assert(Sprites.formIndex(mons[201],{species=201})=='base')
assert(Sprites.formIndex(mons[201],{species=201,form=99})=='base','bad form must degrade safely')
-- Johto's DV-derived, one-based Unown form lookup is unchanged.
local johto={forms={[1]={spriteFront='A'},[26]={spriteFront='Z'}}}
assert(Sprites.formIndex(johto,{dvs={attack=0,defense=0,speed=0,special=0}})==1)
assert(Sprites.formIndex(johto,{dvs={attack=6,defense=6,speed=6,special=6}})==26)
local game={data=data,save={pokedex={seen={},owned={}}}}
Forms.record(game,201,{species=201,form=27})
Forms.record(game,201,{species=201,form=0})
Forms.record(game,201,{species=201,form=27})
assert(#Forms.seen(game.save.pokedex,201)==2 and Forms.seen(game.save.pokedex,201)[1]=='que','record unique forms in encounter order')
Forms.record(game,201,{species=201,form=26,isEgg=true})
Forms.record(game,201,{species=201,form=99})
Forms.record({data={constants={gen=2},pokemon=mons},save=game.save},201,{species=201,form=26})
assert(#Forms.seen(game.save.pokedex,201)==2,'eggs, invalid forms and other generations must not count')
Forms.record(game,487,{species=487,form=1})
assert(#Forms.seen(game.save.pokedex,201)==2 and #Forms.seen(game.save.pokedex,487)==1)
Forms.record(game,493,{species=493,form=1})
assert(#Forms.seen(game.save.pokedex,493)==0,'ROM does not track Arceus forms in the dex')
local C=require('src.script.Commands');require('src.script.Gen4Commands')
local ctx={save=game.save,g4Compare=2,lastCheck=false}
C.g4_unown_forms_seen(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==2 and ctx.g4Compare==2 and ctx.lastCheck==false)
for i=0,27 do Forms.record(game,201,{species=201,form=i}) end
C.g4_unown_forms_seen(ctx,0x8000);assert(ctx.save.gen4Vars[0x8000]==28,'all 28 letters and punctuation must count')
C.g4_enable_dex_form_detection(ctx);assert(ctx.save.pokedex.canDetectForms and #Forms.seen(ctx.save.pokedex,201)==28)
local VM=require('src.script.Gen4ScriptVM')
local rows=VM.lower({{name='getunownformsseencount',args={0x8000}},{name='turnonpokedexformdetection',args={}}})
assert(rows[1][1]=='g4_unown_forms_seen' and rows[2][1]=='g4_enable_dex_form_detection')
local Dex=require('src.ui.Gen4Pokedex')
local page=setmetatable({game=game,species=function() return 201 end,def=function() return mons[201] end},{__index=Dex})
local list=page:forms();assert(#list==28 and list[1]=='que' and list[2]=='base','dex must show observed order, without duplicate base')
page.species=function() return 487 end;page.def=function() return mons[487] end
list=page:forms();assert(#list==1 and list[1]=='origin','dex cannot reveal unseen forms')
local Anim=require('src.pokemon.PicAnim')
local anim=Anim.forMon(data,{species=487,form=1,shiny=true})
assert(anim and anim.anim.sheet=='origin_anim' and Anim.sheetFor(anim.anim,anim.mon)=='origin_shiny_anim')
mons[487].forms.origin.picAnim.shinySheet=nil
assert(Anim.forMon(data,{species=487,form=1,shiny=true})==nil,'old normal-only strips cannot change shiny colours')
print(checked..' native forms: numeric/named/front/back/shiny sprite paths, form animation strips and Johto isolation passed')
print('Seen-form encounter order/deduplication, all 28 Unown forms, egg/invalid exclusions, NPC query and dex display checks passed')
local Battle=require('src.battle.BattleState')
local observed={data=data,save={pokedex={seen={},owned={}}}}
Battle.markSeen(observed,201,{species=201,form=26})
assert(observed.save.pokedex.seen[201] and #Forms.seen(observed.save.pokedex,201)==1)
assert(not observed.save.pokedex.owned[201],'seeing a form must not require or imply capture')
Battle.markSeen(observed,201,{species=201,form=26})
assert(#Forms.seen(observed.save.pokedex,201)==1)
assert(loadfile('src/import/RomExtractorGen4.lua'))
print('Battle sightings record forms before capture; modified extractor syntax passed')
-- Exercise the actual extraction path against the supplied Platinum ROM.
local ROM=require('src.import.NdsRom')
local rom=assert(ROM.open(arg[1] or 'Pokemon - Platinum Version (USA) (Rev 1).nds'))
local archive=assert(require('src.import.NarcArchive').parse(rom:read(require('src.import.Gen4Otherpoke').PATH)))
local pictures={}
local extractor={archive=function() return archive end,saveImage=function(_,path,pic)
 assert(pic and pic.width>0 and pic.height>0 and #pic.rgba==pic.width*pic.height*4,path)
 local visible=false
 for i=4,#pic.rgba,4 do if pic.rgba:byte(i)>0 then visible=true;break end end
 assert(visible,'empty native form art '..path)
 pictures[path]=pic
 return {path=path,width=pic.width,height=pic.height}
end}
local index={forms={},counts={}}
local nativeMons={}
for id in pairs(mons) do nativeMons[id]={trueColor=true} end
require('src.import.RomExtractorGen4').extractFormSprites(extractor,index,nativeMons)
local nativeData={constants={gen=4},pokemon=nativeMons}
local nativeCount=0
for _,row in ipairs(require('src.import.Gen4Otherpoke').FORMS) do
 if row.species>0 then
  local mon={species=row.species,form=row.form,shiny=true}
  for _,side in ipairs({'front','back'}) do
   local path=Sprites.path(nativeData,row.species,side,{mon=mon})
   assert(pictures[path],'native sprite path cannot resolve '..row.form)
  end
  local animation=Anim.forMon(nativeData,mon)
  assert(animation and pictures[Anim.sheetFor(animation.anim,mon)],'missing native shiny form animation '..row.form)
  nativeCount=nativeCount+1
 end
end
rom:close()
assert(nativeCount==checked)
print(nativeCount..' ROM-extracted forms verified: nonempty normal/shiny art and selected shiny animation strips')
local corpus=assert(loadfile('G:/Gen2Recomped/platinum/data/generated/map_scripts.lua'))()
local queries,enable=0,0
for label,block in pairs(corpus.scripts) do
 for _,ins in ipairs(block.instructions or {}) do
  if ins.name=='getunownformsseencount' then
   queries=queries+1;local row=VM.lower({ins})[1]
   assert(row[1]=='g4_unown_forms_seen' and row[2]==ins.args[1],'wrong Unown query at '..label)
  elseif ins.name=='turnonpokedexformdetection' then
   enable=enable+1;assert(VM.lower({ins})[1][1]=='g4_enable_dex_form_detection')
  end
 end
end
assert(queries>0 and enable>0)
print(queries..' real Unown query sites and '..enable..' form-detection event sites use working handlers')
