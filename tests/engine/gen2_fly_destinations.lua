package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Data = require("src.core.Data")
local Fields = require("src.world.Gen2FieldMoves")
local Fly = require("src.world.Gen2Fly")
local Flags = require("src.script.Flags")
local TownMap = require("src.ui.TownMap")
local oldVersion, oldMaps, oldField = Version.get(), Data.maps, Data.field
local function fixture()
  Data.maps = {}
  Data.field = {flyWarps={}, townMap={johto="fixture/johto.png",landmarks={}}}
  local byMap = {}
  for i, row in ipairs(Fly.FLYPOINTS) do
    local id = row.map
    local landmark = i < Fly.KANTO_FLYPOINT and i or i+40
    if i==12 then landmark=Version.isCrystal() and 46 or 45 end
    if i==13 then landmark=Version.isCrystal() and 47 or 46 end
    Data.maps[id] = {id=id,landmark=landmark}
    Data.field.flyWarps[id] = {x=i,y=i+1}
    Data.field.townMap.landmarks[landmark] = {name="Town "..i,x=16+i,y=24+i}
    byMap[id] = {landmark=landmark,name="Town "..i,region=i<13 and "johto" or "kanto"}
  end
  return {data=Data,save={flags={},visited={}},overworld={map={id="NEW_BARK_TOWN"}}}, byMap
end
for _, version in ipairs({"gold","silver","crystal"}) do
  Version.set(version)
  local game, byMap = fixture()
  local save = game.save
  T.eq(Fields.FLYPOINTS,Fly.FLYPOINTS,"native and legacy callers share destination definitions")
  T.eq(#Fields.FLYPOINTS,24,"only cartridge cursor destinations, not every spawn")
  T.eq(#Fields.flyPoints(save),0,"unvisited towns are unavailable")
  local key, raw = Fly.flagKey("SPAWN_CHERRYGROVE")
  T.eq(raw, version=="crystal" and 66 or 65,"Crystal engine-flag insertion")
  T.eq(key,string.format("FLAG_G2_%04d",raw),"same opaque key used by native script lowering")
  local vm=require("src.script.Gen2ScriptVM")
  local scripts={map_scripts={source="RomExtractorGen2",scripts={
    OPEN={{"setflag",raw},{"end"}},CLOSE={{"clearflag",raw},{"end"}}}}}
  local runner=require("src.script.ScriptRunner").new(game,game.overworld)
  runner:run(vm.compile(scripts,"OPEN"))
  T.eq(runner:isRunning(),false,"real native flag script completes")
  T.eq(Fields.hasVisitedSpawn(save,"SPAWN_CHERRYGROVE"),true,"actual native set_flag opens fly point")
  local points,region=Fields.flyPoints(save)
  T.eq(region,"johto","default region")
  T.eq(#points,1,"only explicitly opened destination")
  T.eq(points[1].spawn,"SPAWN_CHERRYGROVE","legacy spawn identity")
  T.eq(points[1].name,"Town 2","native imported landmark name")
  T.eq(points[1].index,2,"native imported landmark index")
  save.visited.CHERRYGROVE_CITY=true
  save.visitedSpawns={SPAWN_CHERRYGROVE=true}
  save.engineFlags={[raw]=true}
  runner:run(vm.compile(scripts,"CLOSE"))
  T.eq(Fields.hasVisitedSpawn(save,"SPAWN_CHERRYGROVE"),false,"actual native clear dominates all stale visited fallbacks")
  save.flags[key]=nil;save.engineFlags[raw]=false
  T.eq(Fields.hasVisitedSpawn(save,"SPAWN_CHERRYGROVE"),false,"explicit reference engine flag clear dominates legacy sets")
  save.engineFlags=nil;save.visitedSpawns=nil
  T.eq(Fields.hasVisitedSpawn(save,"SPAWN_CHERRYGROVE"),true,"existing native visited saves remain readable")
  save.visited={};save.visitedSpawns={SPAWN_CHERRYGROVE=true}
  T.eq(Fields.hasVisitedSpawn(save,"SPAWN_CHERRYGROVE"),true,"reference spawn-name fallback remains readable")
  T.eq(Fields.hasVisitedSpawn(save,"SPAWN_UNKNOWN"),false,"unknown destinations stay closed")
  T.eq(Fields.hasVisitedSpawn(nil,"SPAWN_CHERRYGROVE"),false,"no save does not unlock towns")
  -- Public and native map ids share a registry record. Reading a visited
  -- alias must not create a new save key or choose another landing spot.
  local def=Data.maps.ROUTE10_NORTH
  def.sourceId,def.id="ROUTE10_NORTH","ROUTE_10_NORTH"
  Data.maps.ROUTE_10_NORTH=def
  save.visited={ROUTE10_NORTH=true};save.visitedSpawns=nil
  T.eq(Fly.mapId(Data,"SPAWN_ROCK_TUNNEL"),"ROUTE_10_NORTH","exact registered native alias")
  T.eq(Fields.hasVisitedSpawn(save,"SPAWN_ROCK_TUNNEL"),true,"native-key visited fallback across alias")
  -- Kanto is withheld until Indigo is visited, even when a Kanto point is set.
  save.visited.NEW_BARK_TOWN=true;save.visited.PALLET_TOWN=true
  points,region=Fields.flyPoints(save,nil,"kanto")
  T.eq(region,"johto","Indigo gate keeps premature Kanto request on Johto")
  T.eq(points[1].spawn,"SPAWN_NEW_BARK","gated list contains actual Johto visits")
  local indigo=Fly.flagKey("SPAWN_INDIGO");Flags.set(save,indigo)
  points,region=Fields.flyPoints(save,nil,"kanto")
  T.eq(region,"kanto","native Indigo flag opens Kanto picker")
  T.eq(points[1].spawn,"SPAWN_PALLET","Kanto order starts with Pallet")
  T.eq(points[#points].spawn,"SPAWN_INDIGO","Indigo remains a real selectable destination")
  game.overworld.map.id="PALLET_TOWN"
  local locs, ids=Fly.picker(game,byMap,Fields)
  T.eq(ids[1],"PALLET_TOWN","native picker consumes public regional query")
  T.eq(ids[2],"ROUTE_10_NORTH","picker uses proven live alias")
  T.eq(ids[#ids],"ROUTE23","native Indigo landing map rather than guessed map name")
  -- A genuine external wrapper can combine regions. Native map coordinates
  -- and warp validation remain the engine's; malformed/missing spots cannot
  -- become selectable or redirect to an unrelated arbitrary id.
  local original=Fields.flyPoints
  Fields.flyPoints=function(s,landmarks,r)
    local joined={};for _,v in ipairs(original(s,landmarks,"johto"))do joined[#joined+1]=v end
    for _,v in ipairs(original(s,landmarks,"kanto"))do joined[#joined+1]=v end
    joined[#joined+1]={spawn="SPAWN_UNKNOWN"}
    return joined
  end
  locs,ids=Fly.picker(game,byMap,Fields)
  T.eq(ids[1],"NEW_BARK_TOWN","actual native picker honors public combined-region wrapper")
  T.eq(ids[#ids],"ROUTE23","combined native picker retains Kanto")
  Data.field.flyWarps.PALLET_TOWN=nil
  locs,ids=Fly.picker(game,byMap,Fields)
  for _,id in ipairs(ids)do T.neq(id,"PALLET_TOWN","missing actual landing spot is not offered")end
  Fields.flyPoints=original
  -- Actual TownMap controller, including cursor A/B, with only art/input as
  -- fixtures. Selection and cancellation must reach its native callbacks.
  game.overworld.map.id="NEW_BARK_TOWN"
  local pressed,chosen,popped
  game.input={wasPressed=function(_,key)return key==pressed end}
  game.stack={pop=function()popped=(popped or 0)+1 end}
  local screen=TownMap.new(game,{fly=true,onFly=function(id)chosen=id end})
  T.eq(screen.fly,true,"actual native TownMap opens the facade-backed flight list")
  T.eq(screen.flyMapIds[1],"NEW_BARK_TOWN","controller cursor uses visited destination")
  T.eq(screen.byMap.SILVER_CAVE_OUTSIDE.region,"johto","actual cartridge boundary keeps Silver Cave on Johto")
  T.eq(screen.byMap.PALLET_TOWN.region,"kanto","Pallet header starts Kanto on Gold/Silver/Crystal")
  -- An actual visited Silver Cave cursor follows the Johto painting. Native
  -- imported headers, not the reference's or another cartridge's literal id.
  Flags.set(save,Fly.flagKey("SPAWN_MT_SILVER"))
  local silverScreen=TownMap.new(game,{fly=true})
  for _=1,30 do
    if silverScreen.flyMapIds[silverScreen.sel]=="SILVER_CAVE_OUTSIDE" then break end
    pressed="down";silverScreen:update(1)
  end
  T.eq(silverScreen.flyMapIds[silverScreen.sel],"SILVER_CAVE_OUTSIDE","native input reaches visited Silver Cave")
  T.eq(silverScreen.region,"johto","Silver Cave cursor does not switch to wrong region")
  pressed="a";screen:update(1)
  T.eq(chosen,"NEW_BARK_TOWN","A returns native destination to existing flyTo owner")
  T.eq(popped,1,"A closes actual native picker")
  chosen=nil;pressed="b";screen=TownMap.new(game,{fly=true,onFly=function(id)chosen=id end});screen:update(1)
  T.eq(chosen,nil,"B never starts flight")
  T.eq(popped,2,"B closes actual native picker")
end
-- Actual SDK loading/unloading: the query seen by the native screen is the
-- wrapped native module table, and teardown restores it without stale calls.
Version.set("crystal")
local game,byMap=fixture()
game.save.visited.NEW_BARK_TOWN=true;game.save.visited.PALLET_TOWN=true
Flags.set(game.save,Fly.flagKey("SPAWN_INDIGO"))
local original=Fields.flyPoints
local result=T.sdk.loadMods({"mods/fly_query"},{data=T.fixtures.fresh(),fs=T.sdk.memfs({
 ["mods/fly_query/manifest.json"]=[[{"id":"fly_query","name":"Fly query contract","version":"1.0.0","api":2,"entry":"main.lua","affects_link":false}]],
 ["mods/fly_query/main.lua"]=[[
  local mod=...
  local F=require("src.world.gen2.FieldMoves")
  local previous=F.flyPoints
  mod.exports.calls=0
  F.flyPoints=function(save,landmarks,region)
   mod.exports.calls=mod.exports.calls+1
   local joined=previous(save,landmarks,"johto")
   for _,row in ipairs(previous(save,landmarks,"kanto"))do joined[#joined+1]=row end
   return joined
  end
 ]],
})})
T.eq(#result.errors,0,"real legacy query mod loads")
local locs,ids=Fly.picker(game,byMap,Fields)
T.eq(ids[1],"NEW_BARK_TOWN","actual loaded mod is consumed by native picker")
T.eq(ids[#ids],"ROUTE23","loaded mod can expose real visited destination in other region")
T.eq(result.loader.exports.fly_query.calls,1,"native query dispatched through loaded wrapper")
require("src.mods.Loader").teardown();result.release()
T.eq(Fields.flyPoints,original,"loader teardown restores actual native query")
for _,version in ipairs({"red","yellow","firered","prism","polishedcrystal"})do
  Version.set(version)
  local game=fixture();game.save.visited.NEW_BARK_TOWN=true
  T.eq(Fly.supported(),false,"GSC flag layout is not guessed for "..version)
  T.eq(Fields.hasVisitedSpawn(game.save,"SPAWN_NEW_BARK"),false,"unsupported layout stays closed")
  T.eq(#Fields.flyPoints(game.save),0,"no fabricated destinations on another cartridge")
end
Data.maps,Data.field=oldMaps,oldField;Version.set(oldVersion)
T.finish("native GSC flight destinations and picker")
