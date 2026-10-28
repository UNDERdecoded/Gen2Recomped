-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local G=require('src.core.Game3');local V=require('src.core.GameVersion')
local Doors=require('src.core.game3.doors');local Map=require('src.core.game3.map')
local Json=require('src.link.Json');local prior=package.loaded['src.core.Game']
local function le(n,bytes)local out={}for i=1,bytes do out[i]=string.char(n%256);n=math.floor(n/256)end;return table.concat(out)end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 G.release();Map.release()
 local f=require('tools.map-runtime.fixture').new(edition);local g=f.game
 package.loaded['src.core.Game']=g;f.world.player={};g.save={};g.mods={}
 local fr=V.isFRLG();local p=g.data.map_tilesets.P
 p.attributes=le(0,2)..le(0x69,2)..le(2,2)
 if fr then p.sourceAttributes=le(0,4)..le(0x69,4)..le(2,4)end
 local row={index=0,mid=1,tile='native_door_0',sound='sliding',sound_type=1,size_type=fr and 0 or 1}
 local facts={schema=1,edition=edition,romSha1=V.info(edition).sha1,family=fr and'frlg'or'rse',
  entries={row},by_mid={[1]=row},doors={native_door_0={frame_width=16,frame_height=fr and 16 or 32}}}
 g.data.constants.gen3DoorMetadata=facts
 local before=Json.encode({save=g.save,blocks=f.map.def.blocks,warps=f.map.def.warps,metadata=facts})
 local entry,info=Doors.getDoorEntryAt(f.mapId,2,0)
 T.check(entry~=nil,'a real native door cell resolves through the canonical map identity')
 T.eq(entry.sound,'sliding');T.eq(info.frame_height,fr and 16 or 32)
 T.eq(Doors.getDoorEntryAt(f.map.id,2,0).mid,1,'native identity resolves the same actual cell')
 entry.sound='edited';info.frame_height=999;Doors._manifest.by_mid[1].sound='edited'
 T.eq(Doors.getDoorEntryAt(f.mapId,2,0).sound,'sliding','source metadata edits never change cartridge facts')
 T.eq(Doors.getDoorEntryAt(f.mapId,0,0),nil,'a floor tile cannot inherit an unrelated door descriptor')
 for _,xy in ipairs{{-1,0},{3,0},{4,0},{0,2},{0/0,0},{math.huge,0},{.5,0}}do T.eq(Doors.getDoorEntryAt(f.mapId,xy[1],xy[2]),nil)end
 T.eq(Doors.getDoorEntryAt('UNKNOWN',2,0),nil)
 T.eq(Json.encode({save=g.save,blocks=f.map.def.blocks,warps=f.map.def.warps,metadata=facts}),before,'queries leave saves, native cells, warps and imported descriptors exact')
 g.data.constants.gen3DoorMetadata=nil
 T.eq(Doors.getDoorEntryAt(f.mapId,2,0),nil);T.eq(Doors._manifest,nil,'a missing or retired import is not a fabricated empty manifest')
 g.data.constants.gen3DoorMetadata=facts;g.stack.states={};g.stack.worldState=nil
 T.eq(Doors.getDoorEntryAt(f.mapId,2,0),nil);T.eq(Doors._manifest,nil,'retired world drops the metadata projection')
 f.views:release();Map.release();G.release()
end
package.loaded['src.core.Game']=prior
T.finish('native door metadata, canonical cells, detached queries and retirement')
