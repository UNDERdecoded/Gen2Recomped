package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local V=require('src.core.GameVersion')
local J=require('src.link.Json')
local X=require('src.import.RomExtractorGen3')
local f=assert(io.open('tools/rom_manifest_ruby.json'));local m=J.decode(f:read('*a'));f:close()
local v=V.info('ruby')
T.eq(v.sha1,m.romSha1,'registered cartridge matches manifest')
T.eq(v.cachePrefix,'ruby/','own imported data namespace')
T.eq(v.saveSuffix,'_ruby','own save namespace')
T.eq(v.generation,3,'Ruby is a native Gen3 cartridge')
T.eq(m.specialRemap[157],159,'native starter special maps to canonical handler')
T.eq(m.specialIndexMap['159'],156,'canonical extractor reads native starter slot')
T.eq(m.specialIndexMap['158'],155,'read-only wall clock has its own handler')
T.eq(m.typeIds[2],'FIGHTING','short cartridge FIGHT name retains canonical battle type')
T.eq(m.typeIds[14],'ELECTRIC','short cartridge ELECTR name retains canonical battle type')
local raw={}
local target=m.provenance.symbolIdentities.ScrSpecial_ChooseStarter
raw[m.symbols.gSpecials+156*4]=0x08000000+target+1
local x=setmetatable({manifest=m,symbols=m.symbols,rom={u32=function(_,a) return raw[a] or 0 end}},X)
T.eq(x:specialAddress(159),target,'extractor reads the same native special that scripts call')
T.eq(x:specialAddress(529),nil,'unmapped special never reads a different native slot')
T.finish('Ruby registration, type ids and special address spaces')
