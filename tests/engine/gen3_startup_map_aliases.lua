-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Data=require('src.core.Data')
local Identity=require('src.compat.gen1.MapIdentity')
local original=Version.get()
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Version.set(edition)
 local data=T.fixtures.fresh()
 data.maps={}
 local frlg=Version.isFRLG()
 local slots=frlg and{{4,1},{1,75}}or{{1,0},{0,0}}
 for _,slot in ipairs(slots)do
  local g,n=slot[1],slot[2];local id=('MAP_G%02d_N%02d'):format(g,n)
  data.maps[id]={id=id,group=g,number=n,width=4,height=4,tileset='FIX_OUT',blocks={0},objects={}}
 end
 Data.seedDefaults(data)
 local binding=Identity.bind(data.maps,edition)
 for _,slot in ipairs(slots)do
  local g,n=slot[1],slot[2];local id=('MAP_G%02d_N%02d'):format(g,n)
  local canonical=assert(Identity.lookup(edition,g,n))
  T.eq(binding:legacyId(id),canonical,'actual startup retains unambiguous ROM header')
  T.eq(binding:nativeId(canonical),id,'source observations reach original native address')
  local alias=id:gsub('([A-Z])(%d)','%1_%2')
  T.eq(data.maps[alias],data.maps[id],'automatic normalized spelling shares actual header')
  T.eq(data.maps[alias].id,id,'automatic alias preserves native storage identity')
 end
 if frlg then
  T.eq(data.maps.LORELEIS_ROOM,data.maps.MAP_G01_N75,'story spelling shares physical header')
  T.eq(data.maps.LORELEIS_ROOM.id,'MAP_G01_N75','story alias cannot change native address')
 end
 local id=('MAP_G%02d_N%02d'):format(slots[1][1],slots[1][2])
 data.maps.FOREIGN=require('src.mods.Merge').deepCopy(data.maps[id])
 T.eq(Identity.bind(data.maps,edition):legacyId(id),nil,'authored duplicate slots remain rejected')
end
Version.set(original)
T.finish('GBA automatic startup aliases retain one physical map header')
