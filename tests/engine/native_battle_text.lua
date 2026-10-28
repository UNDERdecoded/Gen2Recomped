-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local X=require('src.import.RomExtractorGen3')
local Rom=require('src.import.RomGba')
local Catalog=require('src.import.Gen3BattleTextCatalog')
local Text=require('src.core.game3.battle.battle_text')
local original,version=package.loaded['src.core.Game'],V.get()
local function reader(raw)
 return setmetatable({rom=Rom.new(raw),manifest={charmap={[0xBB]='A',[0xBC]='B'}}},X)
end
local function word(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
local p=Catalog.profile('firered')
local spec={count=3,placeholders=p.placeholders}
local rows={string.char(0xFD,0x24,0xFF),string.char(0xFD,0,0xFD,1,0xFD,48,0xFF),string.char(0xFD,0,0xFD,1,0xFF)}
local tableBytes=word(0x08000040)..word(0x08000060)..word(0x08000080)
local raw=tableBytes..string.rep('\0',64-#tableBytes)..rows[1]
raw=raw..string.rep('\0',96-#raw)..rows[2]
raw=raw..string.rep('\0',128-#raw)..rows[3]..string.rep('\0',24)
T.eq(Catalog.locate(reader(raw),spec),0,'table at offset zero is valid')
local ambiguous=raw:sub(1,12)..tableBytes..raw:sub(25)
local found,why=Catalog.locate(reader(ambiguous),spec)
T.eq(found,nil);T.eq(why,'ambiguous native battle string table')
local mini={first=12,count=3,ids={STRINGID_TRAINER1LOSETEXT=12,STRINGID_PKMNGAINEDEXP=13,STRINGID_PKMNGREWTOLV=14},placeholders=p.placeholders}
local priorProfile=Catalog.profile
Catalog.profile=function()return mini end
local bound={edition='firered',named={},records={}}
local ok,count=Catalog.append(reader(raw),{},bound)
Catalog.profile=priorProfile
T.eq(ok,true);T.eq(count,3,'named battle label count includes every appended static row')
T.eq(bound.battle.tableOffset,0);T.eq(bound.records[bound.named.STRINGID_PKMNGAINEDEXP].ir[1].code,0)
local bad=raw:sub(1,4)..word(0x0A000000)..raw:sub(9)
T.eq(Catalog.locate(reader(bad),spec),nil,'invalid pointers cannot authorize a table')
T.eq(Catalog.locate(reader(raw:sub(1,130)),spec),nil,'truncated target is rejected')
for _,pair in ipairs{{0x5B,'%'},{0x5C,'('},{0x5D,')'}}do
 local encoded=reader(string.char(pair[1],0xFF))
 T.eq(encoded:readText(0,2,nil,true),pair[2],'structured native punctuation is decoded')
 T.eq(encoded:readText(0,2),nil,'ordinary scan acceptance is unchanged')
end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 V.set(edition);local profile=Catalog.profile(edition)
 local cache={schema=1,edition=edition,romSha1=V.info().sha1,named={},records={}}
 local data={text={},text_pointers={namedIR=cache},constants={speciesOrder={'BIRD'},moveOrder={'MOVE'},abilityOrder={'NONE','ABILITY'}},
  pokemon={BIRD={name='Native bird'}},moves={MOVE={name='Native move'}},abilities={ABILITY={name='Native ability'}}}
 local game={data=data,save={player={name='Native player'}}};package.loaded['src.core.Game']=game
 local function add(label,nodes)
  cache.named[label]=label;cache.records[label]={plain='template',ir=nodes}
 end
 for code,name in pairs(profile.placeholders)do
  add('probe',{{t='ph',code=code},{t='eos'}})
  T.eq(Text.get('probe',{[name]='explicit '..code}),'explicit '..code,'each edition resolves its own raw placeholder namespace')
 end
 local codes={};for code,name in pairs(profile.placeholders)do codes[name]=code end
 add('STRINGID_PKMNGAINEDEXP',{{t='ph',code=codes.B_BUFF1},{t='text',s=' / '},
  {t='ph',code=codes.B_BUFF2},{t='text',s=' / '},{t='ph',code=codes.B_BUFF3},{t='eos'}})
 local fill={buff1='A',buff2=12,buff3=34}
 T.eq(Text.get(13,fill),'A / 12 / 34','battle buffers do not expand as field player/rival variables')
 T.eq(Text.expand,Text.get,'wrappers can preserve the public expansion alias')
 T.eq(fill.buff2,12,'formatter does not rewrite caller values')
 data.text.sText_WildPkmnPrefix='Wild ';data.text.sText_FoePkmnPrefix='Foe '
 local foe={side='enemy',mon={species=1,nickname='Named'}}
 add('prompt',{{t='ph',code=codes.B_ACTIVE_NAME_WITH_PREFIX},{t='ext',cmd=12,args={0xBB},literal='A'},
  {t='nl'},{t='ph',code=codes.B_CURRENT_MOVE},{t='para'},{t='ph',code=codes.B_ATK_ABILITY},{t='eos'}})
 foe.ability=1
 T.eq(Text.get('prompt',{active=foe,atk=foe,move=1}),'Wild NamedA\nNative move\fNative ability')
 T.eq(Text.get('prompt',{active=foe,atk=foe,move=1,trainer=true}),'Foe NamedA\nNative move\fNative ability')
 T.eq(foe.mon.nickname,'Named','formatting cannot mutate native actors')
 add('needs-context',{{t='ph',code=codes.B_BUFF1},{t='eos'}})
 T.raises(function()Text.get('needs-context')end,'native battle placeholder B_BUFF1 is unavailable')
 T.eq(Text.has('missing'),false);T.eq(Text.has(13),true)
 local detached=require('src.core.game3.rom_text').ir('needs-context');detached[1].code=-1
 T.eq(Text.get('needs-context',{buff1='live'}),'live')
 package.loaded['src.core.Game']={data={text={}}}
 T.eq(Text.has(13),false,'replacement dataset cannot reuse old battle records')
 V.set('gold');T.eq(Text.has(13),false,'native Gen2 strings keep their own owner')
end
V.set(version);package.loaded['src.core.Game']=original
T.finish('native battle text namespaces, bounded pointer tables and current data ownership')
