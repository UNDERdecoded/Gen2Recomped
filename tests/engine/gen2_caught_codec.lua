-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local S=require('src.save_convert.Gen2Save')
local C=require('src.compat.gen2.Mon')
local Pokemon=require('src.pokemon.Pokemon')
local Copy=require('src.mods.Merge').deepCopy
local ready=type(C.packCaughtData)=='function'and type(C.unpackCaughtData)=='function'
T.check(ready,'source APIs exist before actual SRAM export checks')
if not ready then T.finish('missing native caught-data import/export integration')end
local data=T.fixtures.fresh();data.constants.gen=2
data.pokemon.FIXMON_A.index=1
S.setCharmap({['128']='A'})
local function mon(word)
 local m=Pokemon.new(data,'FIXMON_A',10,nil,nil,{dvs={attack=1,defense=2,speed=3,special=4}})
 m.ot='A';m.caughtData=word;return m
end
local function caught(m,hi,lo,where)
 T.eq(m.caughtTime,math.floor(hi/64),where..' time')
 T.eq(m.caughtLevel,hi%64,where..' level')
 T.eq(m.caughtLocation,lo%128,where..' landmark')
 T.eq(m.caughtByGender,lo>=128 and 'girl'or 'boy',where..' player gender')
 T.eq(m.caughtData,nil,where..' canonical fields do not duplicate packed word')
end
for _,version in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 V.set(version);S.setLayout(version)
 for byte=0,255 do
  for _,word in ipairs{byte*256+19,213*256+byte}do
   local m=mon(word)
   local before=Copy(m)
   local record=S.pokemonRecord(m,data)
   T.eq(record:byte(30),math.floor(word/256),version..' physical caught byte zero')
   T.eq(record:byte(31),word%256,version..' physical caught byte one')
   T.same(m,before,'export does not migrate/mutate native mon')
  end
 end
 local word=213*256+147
 local save={player={name='A'},party={mon(word)},boxes={{mon(word)},{mon(word)}},
  daycare={breed={{mon=mon(word)},{mon=mon(word)},egg=mon(word)}}}
 save.daycare.breed.egg.isEgg=true;save.daycare.breed.egg.eggSteps=256
 local raw=S.encode(save,data)
 -- Compare real shared encodeMon users, not a fixture-only record encoder.
 for _,at in ipairs{S.OFFSETS.partyMons,0x4000+22,0x4450+22,
   S.OFFSETS.breedMon1,S.OFFSETS.breedMon2,S.OFFSETS.eggMon}do
  T.eq(raw:byte(at+30),213,version..' physical first byte in native owner')
  T.eq(raw:byte(at+31),147,version..' physical second byte in native owner')
 end
 local decoded=S.decode(raw,data)
 local owners={decoded.party[1],decoded.boxes[1][1],decoded.boxes[2][1],
  decoded.daycare.breed[1].mon,decoded.daycare.breed[2].mon,decoded.daycare.breed.egg}
 T.eq(#owners,6,'all actual party/box/daycare slots decode')
 for _,m in ipairs(owners)do
  if version=='crystal'then caught(m,213,147,'native Crystal import')
  else T.eq(m.caughtData,word,version..' reserved word remains opaque');T.eq(m.caughtTime,nil)end
 end
 if version=='crystal'then
  for _,m in ipairs(owners)do
   m.caughtLocation,m.caughtByGender,m.caughtLevel,m.caughtTime=94,'boy',63,1
  end
 else
  -- Gold/Silver and unreviewed hack layouts must ignore source metadata;
  -- their two opaque bytes are independent of those mod-authored fields.
  for _,m in ipairs(owners)do
   C.setCaughtData(m,{landmark=94,playerGender='girl',timeOfDay='NITE'})
   T.eq(m.caughtData,word,'public source setter cannot erase reserved native bytes')
   C.setGiftCaughtData(m,'girl')
   T.eq(m.caughtData,word,'public gift setter cannot erase reserved native bytes')
  end
 end
 local round=S.encode(decoded,data,raw)
 for _,at in ipairs{S.OFFSETS.partyMons,0x4000+22,0x4450+22,
   S.OFFSETS.breedMon1,S.OFFSETS.breedMon2,S.OFFSETS.eggMon}do
  T.eq(round:byte(at+30),version=='crystal'and 127 or 213,'source edit reaches exact native SRAM first byte')
  T.eq(round:byte(at+31),version=='crystal'and 94 or 147,'source edit reaches exact native SRAM second byte')
 end
 local back=S.decode(round,data)
 local checksumOk=true
 for _,w in ipairs(back.warnings)do if w:find('checksum',1,true)then checksumOk=false end end
 T.check(checksumOk,'native checksums remain valid after source caught-data edits')
 local legacy=mon(word);local stats,moves=legacy.stats,legacy.moves
 Pokemon.ensureIdentity(data,legacy)
 if version=='crystal'then caught(legacy,213,147,'actual old Lua-save validation boundary')
 else T.eq(legacy.caughtData,word,'other editions keep opaque historical word')end
 T.eq(legacy.stats,stats,'metadata hydration keeps native stats');T.eq(legacy.moves,moves,'metadata hydration keeps native moves')
 local authored=mon(word);authored.caughtLocation='AUTHORED LOCATION'
 Pokemon.ensureIdentity(data,authored)
 T.eq(authored.caughtLocation,'AUTHORED LOCATION','validation does not invent or overwrite authored source history')
 T.eq(authored.caughtData,word,'partially authored historical record remains untouched by validation')
end
-- Physical layout, not process-global edition, decides the export format.
V.set('gold');S.setLayout('crystal')
local m=mon(0);m.caughtLocation=19;m.caughtByGender='girl';m.caughtTime=2;m.caughtLevel=65
local record=S.pokemonRecord(m,data);T.eq(record:byte(30),129);T.eq(record:byte(31),147)
V.set('crystal');S.setLayout('gold')
record=S.pokemonRecord(m,data);T.eq(record:byte(30),0);T.eq(record:byte(31),0)
V.set(old);S.setLayout(old)
T.finish('native Crystal caught-data party/box/daycare import, edits, legacy hydration and reserved-layout preservation')
