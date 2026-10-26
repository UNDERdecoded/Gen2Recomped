-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local old=V.get()
local E=require('src.import.RomExtractorGen2');local Native=require('src.world.Gen2Decorations')
local S=require('src.save_convert.Gen2Save');local Json=require('src.link.Json')
local function fixture(version,edit)
 local raw=string.rep('\0',0x8000)
 local function put(at,bytes)raw=raw:sub(1,at)..bytes..raw:sub(at+#bytes+1)end
 local symbols={DecorationAttributes={1,0x4000},DecorationNames={1,0x401e},
  PokemonNames={1,0x4300},InitDecorations={1,0x4100},DecorationIDs={1,0x4200},
  wDecoBed={1,0xd000},wDecoPoster={1,0xd003},DecorationDesc_PosterPointers={1,0x4400},
  ['DecorationDesc_OrnamentOrConsole.OrnamentConsoleScript']={1,0x4500},
  ['DecorationDesc_GiantOrnament.BigDollScript']={1,0x4501},DecorationDesc_NullPoster={1,0x4502},
  PutAwayTheDecoText={1,0x4600},NothingToPutAwayText={1,0x4602},SetUpTheDecoText={1,0x4604}}
 -- Authored test cartridge, not a retail attribute catalogue.
 put(0x4000,string.char(1,0,0,0,0,0,1,1,2,0,0,0,2,2,1,0x34,0x12,0,
  1,1,8,0,0,0,4,1,7,0x35,0x12,77))
 put(0x401e,string.char(128,0x50,129,0x50,130,0x50))
 put(0x4100,string.char(0x3e,2,0xea,0,0xd0,0x3e,4,0xea,3,0xd0,0xc9))
 put(0x4200,string.char(2,4,255));put(0x4300,string.char(131,0x50))
 put(0x4400,string.char(4,3,0x45,255));put(0x4500,string.char(0x91,0x91,0x91,0x91))
 if edit then edit(symbols,put)end
 local e=E.new(raw,version,{symbols=symbols})
 function e:readSourceTable(k)assert(k=='charmap');return{['128']='X',['129']='Y',['130']='Z',['131']='Q'}end
 return e
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);local e=fixture(version);local rows,info=e:gen2Decorations()
 T.check(info.complete,version..' native attribute boundary defines valid table')
 T.eq(info.rowsRead,5,version..' reader imports exact authored row count')
 T.eq(rows[0].name,'X',version..' DECO zero remains in actual native table')
 T.eq(rows[2].name,'Z',version..' names use actual character decoder')
 T.eq(rows[2].flag,0x1234,version..' event identity is native little-endian word')
 T.eq(rows[2].sprite,0,version..' block zero survives real import')
 T.eq(rows[4].name,'Q',version..' species name comes from cartridge indexed table')
 T.eq(info.species[4],'SPECIES_001',version..' raw species identity has no National Dex inference')
 T.eq(info.defaults.bed,2,version..' bed default comes from native init operands')
 T.eq(info.defaults.poster,4,version..' poster default comes from native init operands')
 T.eq(#info.gifts,2,version..' gift ordinal table is ROM-derived')
 T.eq(info.gifts[2],4,version..' gift ordinal retains actual DECO byte')
 local q={scripts={},queue={},movements={},instructions=0,desyncs=0,failures=0}
 local roles=e:gen2QueueDecorationPrograms(q)
 T.eq(#q.queue,4,version..' actual queue includes three description roles and poster')
 T.check(roles.texts.setup:match('^TEXT_S'),version..' native feedback enters shared text import')
 T.check(e._gen2ScriptTexts[roles.texts.setup]~=nil,version..' feedback text is registered for actual extractor')
 e:gen2QueueDecorationPrograms(q);T.eq(#q.queue,4,version..' duplicate queue calls are idempotent')
 local n=1;while n<=#q.queue do local job=q.queue[n];e:gen2DecodeScript(job[1],job[2],job[3],q);n=n+1 end
 T.eq(q.desyncs,0,version..' actual bytecode decoder accepts queued description programs')
 for _,edit in ipairs({
  function(s)s.DecorationNames[2]=0x401f end,
  function(s)s.DecorationNames[1]=2 end,
  function(s)s.DecorationAttributes=nil end,
  function(s,put)put(0x4000,string.char(0))end,
  function(s,put)put(0x4002,string.char(15))end,
  function(s,put)put(0x4003,string.char(255,255))end,
  function(s,put)put(0x401e,string.rep(string.char(128),129))end,
  function(s)s.PokemonNames=nil end,
 })do
  local bad,why=fixture(version,edit):gen2Decorations()
  T.eq(why.complete,false,version..' malformed attribute/name input cannot become ready')
  T.eq(next(bad),nil,version..' malformed attribute/name input publishes no prefix')
 end
 local _,missing=fixture(version,function(s)s.InitDecorations=nil end):gen2Decorations()
 T.eq(missing.complete,true,version..' missing init does not erase valid attribute table')
 T.eq(missing.defaultsComplete,false,version..' missing init cannot invent retail defaults')
 local _,wrong=fixture(version,function(s)s.wDecoBed[2]=0xd100 end):gen2Decorations()
 T.eq(wrong.defaultsComplete,false,version..' init stores must target actual WRAM symbols')
 local _,badGifts=fixture(version,function(_,put)put(0x4200,string.rep(string.char(2),256))end):gen2Decorations()
 T.eq(badGifts.giftsComplete,false,version..' unterminated gifts cannot be claimed complete')
 T.eq(badGifts.gifts,nil,version..' malformed gifts publish no prefix')
 q={scripts={},queue={}}
 T.eq(fixture(version,function(s)s.DecorationDesc_NullPoster=nil end):gen2QueueDecorationPrograms(q),nil,version..' missing description role declines whole binding')
 T.eq(#q.queue,0,version..' missing role is rejected before queue mutation')
 q={scripts={},queue={}}
 T.eq(fixture(version,function(_,put)put(0x4400,string.char(4,0,0))end):gen2QueueDecorationPrograms(q),nil,version..' invalid poster pointer declines binding')
 T.eq(#q.queue,0,version..' invalid poster table leaves queue untouched')
 -- Resolve the precise native NONE pair, without accepting an unknown map.
 e=fixture(version);function e:gen2MapIndex()return{}end;function e:gen2Trainers()return{}end
 local p={scripts={TEST={{'warp',0,0,0,0},{'warpfacing',2,0,0,0,0},{'warp',0,1,0,0},{'blackoutmod',0,0}}}}
 e:gen2ResolveScriptMapIds({}, {},p)
 T.eq(p.scripts.TEST[1][2],'NONE',version..' only actual NONE warp becomes reload')
 T.eq(p.scripts.TEST[2][3],'NONE',version..' warpfacing uses its own map-pair slot')
 T.eq(p.scripts.TEST[3][2],0,version..' unknown map is not turned into a reload')
 T.eq(p.scripts.TEST[4][2],0,version..' non-warp zero pair is not reinterpreted')
 -- Independent manifest WRAM addresses verify the save codec's physical order.
 local f=assert(io.open('tools/rom_manifest_'..version..'.json','rb'));local manifest=assert(Json.decode(f:read('*a')));f:close()
 S.setLayout(version);S.setCharmap({['128']='A'})
 local d=T.fixtures.fresh();local save={player={name='A'},decorations={bed=1,carpet=2,plant=3,poster=4,
  console=5,leftOrnament=6,rightOrnament=7,bigDoll=255}}
 local raw=S.encode(save,d)
 local anchor=version=='crystal'and 0xd47b or 0xd1a1
 for _,key in ipairs(Native.slots)do
  local symbol='wDeco'..key:sub(1,1):upper()..key:sub(2)
  local address=manifest.symbols[symbol][2];local offset=0x2009+address-anchor
  T.eq(raw:byte(offset+1),save.decorations[key],version..' export matches independent '..symbol..' address')
 end
 local decoded=S.decode(raw,d)
 for _,key in ipairs(Native.slots)do T.eq(decoded.decorations[key],save.decorations[key],version..' import preserves exact '..key..' byte')end
 local round=S.encode(decoded,d,raw);local warnings=S.decode(round,d).warnings
 local checksumOk=true;for _,w in ipairs(warnings)do if w:match('checksum')then checksumOk=false end end
 T.check(checksumOk,version..' decoration export retains valid native checksum')
 local saved=decoded.decorations;decoded.decorations=nil
 local untouched=S.encode(decoded,d,raw)
 for i=0,7 do T.eq(untouched:byte(S.OFFSETS.decorations+i+1),raw:byte(S.OFFSETS.decorations+i+1),version..' absent legacy state preserves imported decoration template')end
 decoded.decorations=saved;decoded.decorations.bed=256
 T.check(not pcall(S.encode,decoded,d,raw),version..' invalid placed byte cannot wrap and corrupt native export')
end
for _,version in ipairs({'red','emerald','prism','polishedcrystal'})do
 V.set(version);T.eq(fixture(version):gen2Decorations(),nil,version..' unreviewed layout imports no stock catalogue')
 S.setLayout(version);T.eq(S.OFFSETS.decorations,nil,version..' unknown save layout has no guessed decoration offset')
end
V.set(old);S.setLayout(old);T.finish('native Gen2 decoration ROM producers and eight-byte SRAM codec')
