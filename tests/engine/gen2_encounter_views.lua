package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Views=require('src.core.Gen2EncounterViews')
local Encounter=require('src.world.Encounter')
local previous=Version.get()
local function band(species,rate)
  return {rate=rate,slots={{species=species,level=5}},buckets={100}}
end
local function fixture()
  local map={id='ROUTE_29',sourceId='ROUTE29'}
  local grass=band('DAYMON',20)
  grass.byTime={morn=band('MORNMON',10),nite=band('NITEMON',30)}
  return {maps={ROUTE29=map,ROUTE_29=map},
    encounters={ROUTE29={grass=grass,water=band('WATERMON',40)},
      EMPTY={grass={rate=0,slots={}},water={rate=0,slots={}}}}}
end
for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
  Version.set(edition)
  local data=fixture();local native=data.encounters
  T.eq(Views.publish(data),true,edition..' publishes source encounter vocabulary')
  local view=data.gen2Encounters
  T.eq(Views.forData(data),view,'world and data share the same published view')
  T.eq(data.encounters,native,'native encounter registry is never replaced')
  for _,name in ipairs({'ROUTE29','ROUTE_29'})do
    local row=view.grass[name]
    T.check(type(row)=='table','native and verified public map are addressable')
    for _,tod in ipairs({'MORN','DAY','NITE'})do
      local actual=Encounter.atTime(native.ROUTE29.grass,tod)
      T.eq(row.slots[tod],actual.slots,'time band exposes actual native slot array')
      T.eq(row.rates[tod],actual.rate,'time band exposes actual native rate')
    end
    T.eq(view.water[name].slots,native.ROUTE29.water.slots,'water uses actual native slots')
    T.eq(view.water[name].rate,40,'water preserves native rate')
  end
  T.eq(view.grass.EMPTY,nil,'empty imported placeholders do not advertise grass encounters')
  T.eq(view.water.EMPTY,nil,'empty imported placeholders do not advertise water encounters')
  local heldGrass,heldWater=view.grass.ROUTE_29,view.water.ROUTE_29
  native.ROUTE29={grass=band('PATCHMON',60),water=band('SURFPATCH',70)}
  T.eq(heldGrass.slots.NITE,native.ROUTE29.grass.slots,'held view follows native replacement and time fallback')
  T.eq(heldGrass.rates.MORN,60,'held view follows native rate replacement')
  T.eq(heldWater.slots,native.ROUTE29.water.slots,'held water view follows registry replacement')
  T.eq(heldWater.rate,70,'held water rate follows registry replacement')
  T.raises(function()heldGrass.slots={}end,'read-only','grass view cannot claim an independent table')
  T.raises(function()heldWater.rate=1 end,'read-only','water writes use native registry owner')
  native.ROUTE29=nil
  T.eq(heldGrass.slots,nil,'deleted native encounters cannot survive through held view')
  T.eq(heldWater.slots,nil,'deleted water encounters cannot survive through held view')
  native.ROUTE29={grass=band('RELOADMON',80)}
  data.encounters={ROUTE29={grass=band('NEWDATA',90)}}
  T.eq(heldGrass.rates.DAY,90,'view follows entire native encounter dataset replacement')
  local authored={id='AUTHORED',sourceId='ROUTE29'}
  data.maps.AUTHORED=authored
  T.eq(view.grass.AUTHORED,nil,'source provenance on an authored variant is not an alias')
  data.encounters.ROUTE_29=false
  T.eq(Views.forData(data).grass.ROUTE_29.slots,nil,'explicit false override blocks native fallback')
  Version.set('red')
  T.eq(heldGrass.slots,nil,'held source view retires on edition switch')
  T.eq(heldWater.slots,nil,'held water view cannot read another edition')
end
for _,edition in ipairs({'red','emerald','firered'})do
  Version.set(edition);local data=fixture()
  T.eq(Views.publish(data),false,edition..' has no Gold projection')
  T.eq(Views.forData(data),nil,'other generations keep their native vocabulary')
  T.eq(data.gen2Encounters,nil,'other generations gain no Gen2 encounter field')
end
T.eq(Views.publish(nil),false,'missing data cannot publish an encounter owner')
Version.set(previous)
T.finish('gen2_encounter_views')
