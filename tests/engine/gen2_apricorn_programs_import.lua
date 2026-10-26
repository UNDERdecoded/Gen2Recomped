-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-apricorn-selection.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local E=require('src.import.RomExtractorGen2')
local V=require('src.core.GameVersion');local original=V.get()
local Importer=require('src.import.RomImporter');local P=require('src.world.Gen2ApricornPrograms')
local markerFor
for i=1,100 do local name,value=debug.getupvalue(Importer.readyReport,i)
 if name=='markerFor'then markerFor=value;break end;if not name then break end
end
assert(markerFor)
local names={'Kurt1.AskApricorn','Kurt1.GotLureBall','Kurt1.GaveKurtApricorns','Kurt1.Cancel'}
local function extractor(version,missing,outside)
 local symbols={}
 for i,name in ipairs(names)do if i~=missing then
  symbols[name]={1,outside==i and 0x8000 or outside==-i and 0x100 or 0x4000+i}
 end end
 return E.new(string.rep('\0',0x8000),version,{symbols=symbols})
end
local function pool()return{scripts={},queue={}}end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);local q=pool();local e=extractor(version)
 local roles=e:gen2QueueApricornPrograms(q)
 T.eq(#q.queue,4,version..' all native Kurt entry points enter the real decoder queue')
 for _,role in ipairs({'ask','pending','gave','cancel'})do
  T.check(type(roles[role])=='string',version..' '..role..' retains the actual native script key')
 end
 e:gen2QueueApricornPrograms(q)
 T.eq(#q.queue,4,version..' repeated roots do not duplicate native decode work')
 for i=1,4 do
  q=pool();T.eq(extractor(version,i):gen2QueueApricornPrograms(q),nil,version..' missing role cannot advertise partial bindings')
  T.eq(#q.queue,0,version..' missing role is discovered before any queue mutation')
  q=pool();T.eq(extractor(version,nil,i):gen2QueueApricornPrograms(q),nil,version..' invalid bank address is rejected')
  T.eq(#q.queue,0,version..' invalid role cannot add a partial native queue')
  q=pool();T.eq(extractor(version,nil,-i):gen2QueueApricornPrograms(q),nil,version..' home-bank engine code is not native script bytecode')
  T.eq(#q.queue,0,version..' home-bank rejection precedes queue mutation')
 end
 local marker=markerFor(version)
 T.check(marker:find('gen2%-apricorn%-programs%-v1:')~=nil,version..' cache includes decoded Kurt binding revision')
 love.filesystem.write(V.cachePrefix(version)..'rom-cache.complete',marker:gsub('gen2%-apricorn%-programs%-v1:',''))
 local report=Importer.readyReport(version)
 T.eq(report.ok,false,version..' old recipe-only cache cannot bypass native program reimport')
 T.check(report.why:find('another version',1,true)~=nil,version..' cache revision is checked before generated-file readiness')
end
for _,version in ipairs({'prism','polishedcrystal','red','emerald'})do
 local q=pool();T.eq(extractor(version):gen2QueueApricornPrograms(q),nil,version..' foreign layout has no guessed Kurt bindings')
 T.eq(#q.queue,0,version..' foreign decoder queue is unchanged')
 T.check(not markerFor(version):find('gen2%-apricorn%-programs%-v1:'),version..' unrelated import marker is unchanged')
end
for _,ask in ipairs({{},{{'special',86,'SelectApricornForKurt'},{'ifequal',0,'CANCEL'},false},
 {{'special',86,'SelectApricornForKurt'},{'ifequal',0,'CANCEL'},false,{'sjump','GAVE'}}})do
 local d={map_scripts={apricornPrograms={ask='ASK',pending='PENDING',gave='GAVE',cancel='CANCEL'},
  scripts={ASK=ask,PENDING={},GAVE={},CANCEL={}},apricornBalls={{apricorn='ITEM_111',ball='ITEM_201'}}}}
 local ok,description,why=pcall(P.describe,d)
 T.eq(ok,true,'malformed native selection reports a binding error without crashing mod-free load')
 T.eq(description,nil,'malformed native selection cannot produce a writable native projection')
 T.check(type(why)=='string','malformed selection explains the unavailable native target')
end
V.set(original)
T.finish('native Kurt program import queue, completeness, cache revisions and malformed signatures')
