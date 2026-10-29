-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
T.eq(_G.love,nil,'caught-data arithmetic does not require LOVE')
local Mon=require('src.compat.gen2.Mon')
local V=require('src.core.GameVersion');local old=V.get()
local ready=true
for _,key in ipairs{'hasCaughtData','caughtTimeOf','caughtGenderOf','setCaughtData',
 'setGiftCaughtData','packCaughtData','unpackCaughtData'}do
 T.eq(type(Mon[key]),'function','actual source caught-data method '..key)
 ready=ready and type(Mon[key])=='function'
end
for key,value in pairs{CAUGHT_TIME_MASK=192,CAUGHT_LEVEL_MASK=63,CAUGHT_GENDER_MASK=128,
 CAUGHT_LOCATION_MASK=127,CAUGHT_EGG_LEVEL=1,LANDMARK_EVENT=127,LANDMARK_GIFT=126}do
 T.eq(Mon[key],value,'source caught-data constant '..key)
end
T.same(Mon.CAUGHT_BY,{unknown=0,girl=1,boy=2},'source gift codes are independent of player genders')
if not ready then T.finish('missing source caught-data API')end
for _,version in ipairs{'red','gold','silver','crystal','prism','polishedcrystal','emerald','firered'}do
 V.set(version)
 T.eq(Mon.hasCaughtData(),version=='crystal','active version owns caught data '..version)
 T.eq(Mon.hasCaughtData(version),version=='crystal','explicit version owns caught data '..version)
end
V.set('crystal');T.eq(Mon.hasCaughtData('unknown'),false,'unknown edition does not inherit active Crystal format')
for _,row in ipairs{{'MORN',1},{'DAY',2},{'NITE',3},{'DARK',3},{'morn',0},{'NIGHT',0},
 {0,1},{1,2},{2,3},{3,3},{-1,0},{4,0},{1.9,2},{false,0}}do
 T.eq(Mon.caughtTimeOf(row[1]),row[2],'source time normalization '..tostring(row[1]))
end
T.eq(Mon.caughtTimeOf(nil),0)
for _,row in ipairs{{true,'girl'},{false,'boy'},{'FEMALE','girl'},{'male','boy'},
 {'Girl','girl'},{'BOY','boy'},{'unknown'},{0},{1}}do
 T.eq(Mon.caughtGenderOf(row[1]),row[2],'source player gender '..tostring(row[1]))
end
T.eq(Mon.caughtGenderOf(nil),nil)
-- Every possible pair must round-trip, including all reserved/time-zero
-- combinations. Expected fields are derived independently from physical bits.
for word=0,65535 do
 local hi,lo=math.floor(word/256),word%256
 local decoded=Mon.unpackCaughtData(hi,lo)
 T.eq(decoded.caughtTime,math.floor(hi/64),'time bits')
 T.eq(decoded.caughtLevel,hi%64,'level bits')
 T.eq(decoded.caughtLocation,lo%128,'landmark bits')
 T.eq(decoded.caughtByGender,lo>=128 and 'girl'or 'boy','OT gender bit')
 local a,b=Mon.packCaughtData(decoded)
 T.eq(a,hi,'first packed byte');T.eq(b,lo,'second packed byte')
end
T.same(Mon.unpackCaughtData(-1,511),{caughtTime=3,caughtLevel=63,caughtLocation=127,caughtByGender='girl'},'source byte normalization')
local mon={level=75,custom={retained=true},caughtData=48879}
local identity=mon.custom
T.eq(Mon.setCaughtData(mon,{timeOfDay='DAY',landmark=259,playerGender=true}),mon,'setter retains actual Pokemon')
T.eq(mon.custom,identity,'setter does not copy native/custom fields')
T.eq(mon.caughtData,48879,'source setter preserves any opaque historical word')
T.same({mon.caughtTime,mon.caughtLevel,mon.caughtLocation,mon.caughtByGender},{2,75,3,'girl'},'source level is full before physical packing')
local hi,lo=Mon.packCaughtData(mon);T.eq(hi,139);T.eq(lo,131)
Mon.setCaughtData(mon,{level=-3,landmark='19',playerGender='unknown'})
T.same({mon.caughtTime,mon.caughtLevel,mon.caughtLocation,mon.caughtByGender},{0,0,0,'boy'},'source landmark setter accepts numeric identity only')
for _,case in ipairs{{'unknown',126,'boy'},{'girl',126,'girl'},{'boy',127,'boy'},
 {'GIRL',126,'girl'},{'female',126,'boy'},{1,126,'boy'}}do
 T.eq(Mon.setGiftCaughtData(mon,case[1]),mon,'gift retains same mon')
 T.eq(mon.caughtData,48879,'source gift setter preserves opaque historical bytes')
 T.same({mon.caughtTime,mon.caughtLevel,mon.caughtLocation,mon.caughtByGender},
  {0,0,case[2],case[3]},'gift byte rotation '..tostring(case[1]))
end
T.eq(Mon.setCaughtData(nil),nil);T.eq(Mon.setGiftCaughtData(false),false)
hi,lo=Mon.packCaughtData(nil);T.eq(hi,0);T.eq(lo,0)
hi,lo=Mon.packCaughtData({caughtTime=-1,caughtLevel='65',caughtLocation='129',caughtByGender='female'})
T.eq(hi,193);T.eq(lo,129,'pack accepts source numeric strings without changing setter semantics')
V.set(old);T.eq(_G.love,nil)
T.finish('source GSC caught-data signatures, constants, exhaustive two-byte codec and gift semantics')
