-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Extractor=require('src.import.RomExtractorGen3')
local Rom=require('src.import.RomGba')
local Catalog=require('src.import.Gen3TextCatalog')
local Text=require('src.core.game3.rom_text')
local Version=require('src.core.GameVersion')
local oldGame,oldVersion,oldService=package.loaded['src.core.Game'],Version.get(),package.loaded['src.translation.Service']
local map={[0]=' ',[0xBB]='A',[0xBC]='B',[0xBD]='é',[0x53]='PK',[0x54]='MN'}
local function reader(bytes)
 return setmetatable({rom=Rom.new(bytes),manifest={charmap=map}},Extractor)
end
local function bytes(...)return string.char(...)end
local source=bytes(0xBB,0xFC,0x13,72,0xBC,0xFE,0xBD,0xFD,1,0xFB,0xBB,0xFA,0xBC,0xFF)
local e=reader(source)
local legacy,used=e:readText(0,4096)
local plain,irUsed,nodes=e:readText(0,4096,nil,true)
T.eq(plain,legacy);T.eq(irUsed,used);T.eq(used,#source)
T.eq(select('#',e:readText(0,4096)),2,'ordinary native decoder return arity stays unchanged')
T.eq(select('#',e:readText(0,4096,nil,true)),3)
T.eq(nodes[1].s,'A');T.eq(nodes[2].t,'ext');T.eq(nodes[2].cmd,19);T.eq(nodes[2].args[1],72)
T.eq(nodes[3].s,'B');T.eq(nodes[4].t,'nl');T.eq(nodes[5].s,'é');T.eq(nodes[6].code,1)
T.eq(nodes[7].t,'para');T.eq(nodes[9].t,'scroll');T.eq(nodes[#nodes].t,'eos')
-- Keep both native text-reader ABIs across all cartridge dialects.
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local test=reader(source);test.version=edition
 local a,n=test:readText(0,#source)
 local b,m,nodes=test:readText(0,#source,nil,{structured=true})
 T.eq(a,b);T.eq(n,m);T.eq(nodes[2].cmd,19)
 T.eq(select('#',test:readText(0,#source,nil,{})),2)
 local name=reader(bytes(0xBB,0xFC,0,0xBC,0xFF));name.version=edition
 T.eq(name:readText(0,5),nil);T.eq(name:readText(0,5,nil,true),nil)
 local allowed=edition=='ruby'or edition=='sapphire'
 local text,used,ir=name:readText(0,5,nil,{structured=true,rsNameEnd=true})
 T.eq(text,allowed and 'AB'or nil)
 if allowed then
  T.eq(used,5);T.eq(ir[2].cmd,0);T.eq(#ir[2].args,0)
  T.eq(name:readText(0,5,nil,{rsNameEnd=true}),'AB')
 end
 for limit=1,4 do T.eq(name:readText(0,limit,nil,{structured=true,rsNameEnd=true}),nil)end
end
for _,edition in ipairs{'ruby','sapphire'}do
 local named=reader(bytes(0xBB,0xFC,0,0xBC,0xFF));named.version=edition
 local options={rsNameEnd=true}
 local value,consumed=named:readText(0,5,nil,options)
 T.eq(value,'AB',edition..' native section-name options survive structured-text integration')
 T.eq(consumed,5)
 T.eq(select('#',named:readText(0,5,nil,options)),2,'legacy options retain ordinary return arity')
 local value2,size2,records=named:readText(0,5,nil,true,options)
 T.eq(value2,value);T.eq(size2,consumed)
 T.eq(records[2].cmd,0,'explicit structured name reads retain the cartridge separator')
 T.eq(#records[2].args,0)
 T.eq(named:readText(0,5,nil,true),nil,'ordinary named-text probes do not widen their dialect')
 named.version='firered'
 T.eq(named:readText(0,5,nil,options),nil,'RS name options cannot authorize another cartridge dialect')
 T.eq(options.rsNameEnd,true,'caller options are not rewritten')
end
local widths={1,1,1,3,1,1,0,1,0,0,2,1,1,1,0,2,1,1,1,1,0,0,0,0}
for cmd,count in ipairs(widths)do
 local encoded={0xBB,0xFC,cmd}
 for n=1,count do encoded[#encoded+1]=cmd==12 and 0xBC or n end
 encoded[#encoded+1]=0xBC;encoded[#encoded+1]=0xFF
 local test=reader(string.char(unpack(encoded)))
 local old,n=test:readText(0,4096)
 local current,m,ir=test:readText(0,4096,nil,true)
 T.eq(current,old,'structured extraction preserves native plain decoding')
 T.eq(m,n);T.eq(ir[2].cmd,cmd);T.eq(#ir[2].args,count)
 for length=1,2+count do
  T.eq(test:readText(0,length,nil,true),nil,'a control cannot read beyond its byte budget')
 end
end
for id=0,13 do
 local test=reader(bytes(0xFD,id,0xFF))
 local a=test:readText(0,3);local b,_,ir=test:readText(0,3,nil,true)
 T.eq(a,b);T.eq(ir[1].t,'ph');T.eq(ir[1].code,id)
end
local battle=reader(bytes(0xFD,0x12,0xFF))
T.eq(battle:readText(0,3),nil,'native dialogue probes keep rejecting unknown field placeholders')
local b,_,raw=battle:readText(0,3,nil,true)
T.eq(b,'{PH:12}');T.eq(raw[1].code,0x12,'structured battle consumers retain the raw placeholder identity')
for _,invalid in ipairs{bytes(0xFD),bytes(0xFC),bytes(0xFC,4,1,2),bytes(0xFC,0xFE,0xFF),bytes(0x80,0xFF)}do
 local test=reader(invalid);local ok,value=pcall(test.readText,test,0,#invalid,nil,true)
 T.eq(ok,true,'malformed input is rejected without an out-of-range operand read');T.eq(value,nil)
end
T.eq(reader(bytes(0x53,0x54,0xFF)):readText(0,3,nil,true),'PKMN','native ligatures remain native glyphs')
for _,glyph in ipairs{{0xF8,0,'{A_BUTTON}'},{0xF8,2,'{L_BUTTON}'},{0xF8,3,'{R_BUTTON}'},
 {0xF8,4,'{START_BUTTON}'},{0xF8,5,'{SELECT_BUTTON}'},{0xF8,11,'{DPAD_LEFTRIGHT}'},
 {0xF9,0,'↑'},{0xF9,1,'↓'},{0xF9,2,'←'},{0xF9,3,'→'},{0xF9,4,'+'},
 {0xF9,5,'Lv'},{0xF9,6,'PP'},{0xF9,7,'ID'},{0xF9,8,'№'},{0xF9,9,'_'},
 {0xF9,10,'①'},{0xF9,11,'②'},{0xF9,12,'③'},{0xF9,13,'④'},{0xF9,14,'⑤'},
 {0xF9,15,'⑥'},{0xF9,16,'⑦'},{0xF9,17,'⑧'},{0xF9,18,'⑨'},
 {0xF9,19,'('},{0xF9,20,')'},{0xF9,21,'◎'},{0xF9,22,'△'},{0xF9,23,'✕'}}do
 local test=reader(bytes(glyph[1],glyph[2],0xFF))
 local value,_,ir=test:readText(0,3,nil,true)
 T.eq(value,glyph[3]);T.eq(ir[1].t,'tag');T.eq(ir[1].code,glyph[2]);T.eq(test:readText(0,1,nil,true),nil)
end
for _,code in ipairs{13,255}do
 T.eq(reader(bytes(0xF8,code,0xFF)):readText(0,3,nil,true),nil,'unknown button control stays rejected')
end
T.eq(reader(bytes(0xF9,24,0xFF)):readText(0,3,nil,true),nil,'unsupported extended bank cells stay rejected')
local header,count=Catalog.bind(e,{}, {gString_Help=0,gString_NotText=0})
T.eq(count,1);T.neq(header.named.gString_Help,nil);T.eq(header.named.gString_NotText,nil)
local dataStages,assetStages=Extractor.DATA_STAGES,Extractor.ASSET_STAGES
Extractor.DATA_STAGES={'initial','later'};Extractor.ASSET_STAGES={}
local finish=reader(source);local emitted
function finish:initial()
 self._text={};self._textPointers={namedIR=Catalog.bind(self,self._text,{gText_Late=0})}
end
function finish:later()self._text.TEXT_000000=plain end
function finish:write(name,value)if name=='text_pointers'then emitted=value end end
-- This reader intentionally contains only a short text string, not the ROM
-- tables used by newer required UI stages. Model their late text writes while
-- retaining the actual run/final-publication owner and restore every stub.
local required={}
for _,name in ipairs{'src.import.Gen3StatGrowthAssets','src.import.Gen3SafariAssets'}do
 local ok,owner=pcall(require,name)
 if ok then
  required[#required+1]={owner,owner.extract}
  owner.extract=function(x)x._text.TEXT_000000=x._text.TEXT_000000..'\nQA late native stage'end
 end
end
local completed,why=pcall(finish.run,finish)
for _,row in ipairs(required)do row[1].extract=row[2]end
Extractor.DATA_STAGES,Extractor.ASSET_STAGES=dataStages,assetStages
T.eq(completed,true,why);T.eq(emitted.namedIR.records.TEXT_000000.nativePlain,finish._text.TEXT_000000,
 'final cache publication snapshots text added by later native stages')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Version.set(edition);package.loaded['src.translation.Service']=nil
 local native={TEXT_000000=plain}
 local catalog,count=Catalog.bind(e,native,{gText_Greeting=0,gText_Alias=0,gText_Bad=999999,[1]=0,NotATextLabel=0})
 catalog.edition=edition;catalog.romSha1=Version.info(edition).sha1
 T.eq(count,2);T.eq(catalog.named.gText_Alias,catalog.named.gText_Greeting)
 T.eq(catalog.records.TEXT_000000.nativePlain,plain)
 local data={text=native,text_pointers={namedIR=catalog},constants={},strings={}}
 package.loaded['src.core.Game']={data=data,save={player={name='NATIVE',rival='RIVAL'}}}
 T.eq(Text.has('gText_Greeting'),true);T.eq(Text.has('unknown'),false)
 catalog.edition='other';T.eq(Text.has('gText_Greeting'),false,'foreign cartridge metadata cannot bind this native session')
 catalog.edition=edition
 T.eq(Text.plain('gText_Greeting'),(plain:gsub('{PLAYER}','NATIVE')))
 T.eq(Text.plain('gText_Greeting',{playerName='SOURCE'}),(plain:gsub('{PLAYER}','SOURCE')))
 T.eq(Text._expand('{PLAYER}/{VAR1}/{RIVAL}',{stringVars={'BUFFER'}}),'NATIVE/BUFFER/RIVAL')
 data._portableScriptText={gText_Greeting={value='private VM prose'}}
 T.eq(Text.plain('gText_Greeting'),(plain:gsub('{PLAYER}','NATIVE')),'VM text does not replace native prose')
 data._romTextGeneration=3;data.romText={gText_Greeting='Native prose override'}
 T.eq(Text.plain('gText_Greeting'),'Native prose override')
 data._romTextTouched={gText_Greeting=true};data.romText.gText_Greeting=nil
 T.eq(Text.has('gText_Greeting'),false);T.raises(function()Text.ir('gText_Greeting')end,'native ROM text is unavailable')
 data.romText=nil;data._romTextTouched=nil;data._romTextGeneration=nil
 local detached=Text.ir('gText_Greeting');detached[2].args[1]=-1
 T.eq(Text.ir('gText_Alias')[2].args[1],72,'a caller cannot edit the cached layout operands')
 native.TEXT_000000='Changed {VAR1}\n{RIVAL}'
 T.eq(Text.plain('gText_Greeting',{stringVars={'slot'}}),'Changed slot\nRIVAL')
 T.eq(Text.ir('gText_Greeting')[3].t,'nl','a current registry edit wins over stale cartridge IR')
 data.strings[native.TEXT_000000]='Translated\fline'
 T.eq(Text.ir('gText_Alias')[2].t,'para');T.eq(Text.plain('gText_Alias'),'Translated\fline')
 native.gText_Greeting='Direct label override';T.eq(Text.plain('gText_Greeting'),'Direct label override')
 native.gText_Greeting=nil;native.TEXT_000000=nil
 T.eq(Text.has('gText_Greeting'),false,'removed native prose is not resurrected from its IR snapshot')
 T.raises(function()Text.ir('gText_Greeting')end,'native ROM text is unavailable')
 data.constants.gen3BattleMenu={rows={{'First','Second'},{'Third','Fourth'}},columnX=88}
 local menu=Text.ir('gText_BattleMenu');T.eq(menu[1].s,'First');T.eq(menu[2].args[1],88);T.eq(menu[4].t,'nl');T.eq(menu[7].s,'Fourth')
 menu[1].s='mutated';T.eq(Text.ir('gText_BattleMenu')[1].s,'First')
 data.constants.gen3BattleMenu.rows[1][1]='Localized';T.eq(Text.ir('gText_BattleMenu')[1].s,'Localized')
 local styled={{t='ext',cmd=1,args={7}},{t='text',s='Localized'},
  {t='ext',cmd=19,args={88}},{t='text',s='Second'},{t='nl'},
  {t='text',s='Third'},{t='ext',cmd=19,args={88}},{t='text',s='Fourth'},{t='eos'}}
 catalog.named.gText_BattleMenu='MENU_TEXT';catalog.records.MENU_TEXT={plain='Native menu',ir=styled}
 local original=Text.ir('gText_BattleMenu');T.eq(original[1].cmd,1);T.eq(original[1].args[1],7)
 data.constants.gen3BattleMenu.rows[1][1]='New label';data.constants.gen3BattleMenu.columnX=96
 local edited=Text.ir('gText_BattleMenu');T.eq(edited[1].cmd,1);T.eq(edited[1].args[1],7)
 T.eq(edited[2].s,'New label');T.eq(edited[3].args[1],96,'live native menu changes preserve unrelated cartridge controls')
 edited[1].args[1]=0;T.eq(styled[1].args[1],7,'adapted menu controls remain detached')
 native.gText_BattleMenu='Custom menu';T.eq(Text.ir('gText_BattleMenu')[1].s,'Custom menu')
 T.eq(Text.key('gTypeNames',0),'gTypeNames[0]');native['gTypeNames[0]']='Native type'
 T.eq(Text.at('gTypeNames',0),'Native type');T.raises(function()Text.key('table',-.5)end,'invalid native text table index')
 e.version=edition;e.manifest.romSha1=Version.info(edition).sha1
 local rejected=Catalog.extract(e,native);T.eq(rejected,nil,'an expected manifest digest cannot authorize different actual bytes')
 package.loaded['src.core.Game']={data={text={fresh='new session'}}}
 T.eq(Text.has('gText_Greeting'),false);T.eq(Text.plain('fresh'),'new session')
 Version.set('gold');T.eq(Text.has('fresh'),false,'native Gen2 text retains its own owner')
end
package.loaded['src.core.Game']=nil;T.eq(Text.has('fresh'),false);T.eq(package.loaded['src.core.Game'],nil)
package.loaded['src.core.Game']=oldGame;package.loaded['src.translation.Service']=oldService;Version.set(oldVersion)
T.finish('native structured cartridge text, byte bounds, current prose and detached layout ownership')
