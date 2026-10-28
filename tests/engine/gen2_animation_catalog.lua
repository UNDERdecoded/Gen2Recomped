-- Actual synthetic ROM bytes -> complete native pool -> actual shared VM.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local E=require('src.import.RomExtractorGen2')
local Data=require('src.battle.Gen2AnimData')
local Catalog=require('src.battle.Gen2AnimCatalog')
local Runtime=require('src.battle.gen2.AnimRunner')
local Player=require('src.battle.Gen2AnimPlayer')
local V=require('src.core.GameVersion')
local previous=V.get()
for _,edition in ipairs{'gold','silver','crystal'}do
 V.set(edition)
 local constants={moveOrder={'PROBE','OTHER','ALIAS'}}
 local e=E.new(nil,edition,{symbols={BattleAnimations={1,0x4000}}})
 e.constants=function()return constants end
 local pointers={[0x4000]=0x4008,[0x4002]=0x5000,[0x4004]=0x5010,[0x4006]=0x5000}
 local bytes={
  [0x4008]=0xff,
  [0x5000]=0xfe,[0x5001]=0x00,[0x5002]=0x51,[0x5003]=3,[0x5004]=0xff,
  [0x5010]=1,[0x5011]=0xff,
  [0x5100]=2,[0x5101]=0xff,
 }
 e.rom={word=function(_,bank,pc)T.eq(bank,1);return assert(pointers[pc])end,
  byte=function(_,bank,pc)T.eq(bank,1);return assert(bytes[pc])end}
 local c=e:gen2BattleAnims()
 T.eq(Data.isNative(c),true,'actual ROM importer publishes native interpreter schema')
 T.eq(c.bank,1);T.eq(c.gameVersion,edition)
 T.eq(c.source,'ROM:BattleAnimations + data/battle_anims/*','ROM provenance remains explicit')
 T.eq(c.moves.PROBE,'5000');T.eq(c.moves.OTHER,'5010');T.eq(c.moves.ALIAS,'5000')
 T.eq(c.indices[0],'4008','cartridge dummy entry is part of the complete pool')
 T.same(c.scriptOrder,{'4008','5000','5100','5010'},'pool includes call-only blocks and unselected moves once')
 T.same(c.scripts['5000'],{{'call','5100'},{'wait',3},{'ret'}})
 T.same(c.scripts['5100'],{{'wait',2},{'ret'}})
 T.same(c.scripts['5010'],{{'wait',1},{'ret'}})
 T.eq(c.scripts['5000'],c.scripts[c.moves.ALIAS],'same ROM address has one real command owner')
 T.eq(Runtime.scriptForMove(c,'PROBE'),'5000','standalone native API uses the actual imported dataset')
 T.eq(Runtime.scriptForMove(c,'ABSENT'),nil,'absent move gets no invented animation')
 local view,orders=Data.tables(c,constants)
 T.eq(view,c,'native data does not get copied into a selected-program facade')
 local bodySlam=false
 for _,name in ipairs(orders.battleBgEffectOrder)do if name=='BATTLE_BG_EFFECT_BODY_SLAM'then bodySlam=true end end
 T.eq(bodySlam,edition=='crystal','import edition owns numeric BG-function order')
 local p=Player.new({battle_anims=c,constants=constants})
 T.eq(p.runtime.data,c,'idle native player already exposes all imported programs')
 T.check(p:start('PROBE',true));local first=p.runtime
 T.eq(first.data,c);T.eq(p.view.data,c,'the real OAM view reads the same complete native pool')
 T.eq(first.data.scripts['5010'],c.scripts['5010'],'unselected program stays available during another move')
 local steps=0
 repeat p:update();steps=steps+1;T.check(steps<20)until p:isDone()
 T.eq(p.frames,8,'real call, full waits, parent resume and ret preserve cartridge time')
 T.eq(p:scriptFor('ALIAS'),p:scriptFor('PROBE'))
 T.check(p:start('OTHER',false));T.eq(p.runtime.data,c,'next move does not replace the shared data owner')
 repeat p:update()until p:isDone()
 T.eq(p.frames,3);T.eq(first.frames,8,'retained runner keeps its original native clock')
 -- Native clients can edit an actual canonical program. The next start sees
 -- that same owner; it must not silently rebuild it from stale legacy data.
 c.scripts['5010'][1]={'wait',4}
 T.check(p:start('OTHER',false))
 repeat p:update()until p:isDone()
 T.eq(p.frames,6,'actual native source-program edit reaches the genuine VM')
 p:release()
 local source=require('src.import.LuaWriter').encodeSplit(c)
 local restored=assert(loadstring(source))()
 T.same(restored,c,'actual generated-cache writer preserves the complete native schema')
 T.eq(Data.tables(restored,constants),restored,'restored data remains the native owner')
 local fixtures=T.fixtures.fresh();fixtures.constants.gen=2;fixtures.battle_anims=restored
 require('src.render.Font').load(fixtures)
 local save=require('src.core.SaveData').newGame()
 save.party={require('src.pokemon.Pokemon').new(fixtures,'FIXMON_A',20)}
 local screen=require('src.battle.BattleState').newWild({data=fixtures,save=save,
  stack={top=function()end}},'FIXMON_C',15)
 restored.moves.ADDED='5010'
 T.eq(restored.moveAnims.ADDED,nil,'new native registration does not need a stale legacy index map')
 T.check(screen:animForMove('ADDED','player'),'actual native screen admits the canonical source registration')
 T.eq(screen.animPlayer.runtime.data,restored,'real screen, public data and VM share the restored owner')
 T.eq(screen.anims,restored,'real screen exposes the complete native dataset')
 screen.animPlayer:release()
 -- Gen1Recomp's native GSC schema has generation=2 and these real tables,
 -- without the old fork's private gen2/format/moveAnims/index markers.
 restored.gen2,restored.format,restored.moveAnims,restored.indices,restored.misc=nil,nil,nil,nil,nil
 T.eq(Data.isNative(restored),true,'source-native data needs no fork-only format flag')
 local native=require('src.battle.BattleState').newWild({data=fixtures,save=save,
  stack={top=function()end}},'FIXMON_C',15)
 T.check(native:animForMove('ADDED','player'),'real screen accepts the original source-native schema')
 T.eq(native.animPlayer.runtime.data,restored)
 T.eq(Runtime.scriptForMove(restored,'PROBE'),'5000')
 native.animPlayer:release()
 local missing=E.new(nil,edition,{symbols={}}):gen2BattleAnims()
 T.eq(Data.isNative(missing),false,'missing ROM animation table remains an explicit unsupported result')
end
do
 local c=Catalog.compile({gen2=true,scripts={[1]={entry=1,code={
  {op='ifparamequal',args={5,0,80},to=3},{op='ret'},{op='delay',frames=2},{op='ret'}}}},
  moveAnims={PROBE=1},objects={},framesets={},oam={},gfx={}},nil,'crystal')
 T.eq(c.moves.PROBE,'program:1:1','non-ROM registration has an explicit program namespace')
 T.eq(c.source,'Registered GSC animation programs','registered programs do not claim cartridge provenance')
 T.same(c.scripts['program:1:1'],{{'if_param_equal',5,'program:1:3'},{'ret'}},
  'canonical branch has one target key, not leftover cartridge pointer bytes')
 T.same(c.scripts['program:1:3'],{{'wait',2},{'ret'}})
 local loop=Catalog.compile({scripts={[1]={entry=1,addresses={0x5000},code={{op='jump',to=1}}}},
  moveAnims={PROBE=1}},nil,'gold')
 T.same(loop.scripts['5000'],{{'jump','5000'}},'self branch neither recurses forever nor duplicates the pool')
 T.same(loop.scriptOrder,{'5000'})
 T.raises(function()Catalog.compile({scripts={
  [1]={entry=1,addresses={0x5000,0x5001},code={{op='delay',frames=1},{op='ret'}}},
  [2]={entry=1,addresses={0x5000,0x5001},code={{op='delay',frames=2},{op='ret'}}}}},nil,'gold')end,
  'conflicting GSC program','different bytes cannot silently share a ROM program owner')
 T.same(Data.row({op='call',args={0,80},to=1},'5000'),{'call','5000'})
 T.same(Data.row({op='loop',args={3,0,80},to=1},'5000'),{'loop',3,'5000'})
end
V.set(previous)
T.finish('complete native GSC ROM animation pool, source API, actual VM and shared ownership')
