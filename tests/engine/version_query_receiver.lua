package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
for id, info in pairs(V.VERSIONS)do
 V.set(id)
 T.eq(V.generation(),info.generation,'dot active '..id)
 T.eq(V:generation(),info.generation,'method active '..id)
 T.eq(V:info(),info,'metadata receiver '..id)
 T.eq(V.info(id),info,'explicit metadata '..id)
 T.eq(V:info('crystal'),V.VERSIONS.crystal,'method explicit metadata '..id)
 T.eq(V:generation('crystal'),2,'method explicit generation '..id)
 for g=1,5 do
  T.eq(V['isGen'..g](V),g==info.generation,'method generation predicate '..id..' '..g)
  T.eq(V['isGen'..g](V,'emerald'),g==3,'method explicit predicate '..id..' '..g)
 end
 T.eq(V:isCrystal(),id=='crystal','method Crystal predicate '..id)
 T.eq(V:isCrystal('crystal'),true,'method explicit Crystal '..id)
 T.eq(V:family(),V.family(),'method family '..id)
 T.eq(V:isNds(),V.isNds(),'method NDS '..id)
 T.eq(V:isDualScreen(),V.isDualScreen(),'method dual display '..id)
 T.eq(V:saveSuffix(),V.saveSuffix(),'method save suffix '..id)
 T.eq(V:cachePrefix(),V.cachePrefix(),'method cache prefix '..id)
 -- Exact native-mod dispatcher calling convention: previously succeeded with
 -- a false Gen1 answer, preventing its no-receiver fallback from running.
 local ok,generation=pcall(V.generation,V)
 T.eq(ok and generation,info.generation,'dispatcher actual host '..id)
end
T.eq(V.info('unknown-id'),nil,'unknown explicit metadata unchanged')
T.eq(V.generation('unknown-id'),1,'unknown explicit generation fallback unchanged')
V.set(original)
T.finish('version query receiver')
