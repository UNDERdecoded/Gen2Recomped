-- Synthetic native map owners; no ROM, renderer creation or player profile.
local F={}
local function le(n,bytes)local out={}for i=1,bytes do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
function F.new(edition)
 local V=require('src.core.GameVersion');V.set(edition)
 local Native=require('src.world.Map');local Identity=require('src.compat.gen1.MapIdentity')
 local fr=edition=='firered'or edition=='leafgreen';local split=fr and 640 or 512
 local prefix=({firered='FR',leafgreen='FR',emerald='EM',ruby='RU',sapphire='SA'})[edition]
 local f={split=split,mapId=prefix..(fr and '_PALLET_TOWN'or'_LITTLEROOT_TOWN'),neighborId=prefix..(fr and'_ROUTE_1'or'_ROUTE101')}
 local data={maps={},tilesets={},map_tilesets={},constants={gen3Layout={metatilesInPrimary=split,tilesInPrimary=split,palettesInPrimary=fr and 7 or 6,metatileLayers=2}}}
 local attributes=le(0,2)..le(16,2)..le(2,2)
 for _,name in ipairs({'P','S','T'})do
  data.map_tilesets[name]={attributes=attributes,sourceAttributes=fr and(le(0,4)..le(16,4)..le(2,4))or nil,
   sourceAttributeBytes=fr and 4 or 2,sourceBehaviorMask=fr and 511 or 255}
 end
 local function map(id,canonical,other,secondary)
  local _,group,number=Identity.lookup(edition,canonical);assert(group,'fixture map absent from catalog')
  local ts={id='PAIR_'..id,blockTiles=2,blockCells=1,primaryKey='P',secondaryKey=secondary}
  local blocks='';local mids={0,split,1,2,split+1,split+2}
  for i,mid in ipairs(mids)do blocks=blocks..le(mid+(i%4)*1024+0x6000,2)end
  local def={id=id,group=group,number=number,width=3,height=2,blocks=blocks,blockPx=16,mapType='ROUTE',tileset=ts.id,
   collisionCells={1,2,3,0,1,2},elevationCells={6,6,6,6,6,6},sourceBorderWidth=1,sourceBorderHeight=2,sourceBorder=le(1,2)..le(2,2),
   sourceConnections={{dir='east',map=other,offset=-1},{dir='east',map=other,offset=3}},
   connections={east={map=other,offset=-1,list={{map=other,offset=-1},{map=other,offset=3}}}},warps={{x=0,y=1,destMap=other,destWarp=1}}}
  data.maps[id],data.tilesets[ts.id]=def,ts
  local result=Native.new(def,ts);result.renderer={owned=true};return result
 end
 f.map=map('NATIVE_A',f.mapId,'NATIVE_B','S');f.neighbor=map('NATIVE_B',f.neighborId,'NATIVE_A','T')
 f.world={isOverworld=true,map=f.map,neighbors={{map=f.neighbor,cx=3,cy=0},{map=f.neighbor,cx=-3,cy=0}}}
 f.game={data=data,overworld=f.world,stack={states={f.world}}};f.getGame=function()return f.game end
 data.constants.gen3SourceBehaviorFlags={version=1,romSha1=V.info(edition).sha1,raw=string.rep('\0',16)..string.char(2)..string.rep('\0',223)}
 f.views=require('src.compat.gen1.MapViews').new(f.getGame,function()return edition end)
 return f
end
return F
