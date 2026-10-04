package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Emerald field menu and escape warps")
local root = "G:/Gen2Recomped/emerald/data/generated/"
local data = {}
for _, k in ipairs({"constants","maps","pokemon","text","field","tilesets","items","moves"}) do
  data[k] = assert(loadfile(root..k..".lua"))()
end
local Version = require("src.core.GameVersion")
Version.set("emerald")
local Rules = require("src.world.Gen3FieldRules")
local Party = require("src.ui.Gen3PartyMenu")
local OW = require("src.world.OverworldController")
local Map = require("src.world.Map")
local g = { data=data, save={party={},flags={},lastHeal={map="HOME"}},
  stack={push=function() end,pop=function() end} }
for i=1,100 do
  local n=debug.getupvalue(OW.rememberDigWarp,i)
  if n == "Game" then debug.setupvalue(OW.rememberDigWarp,i,g);break end
end
local ow = setmetatable({player={cellX=5,cellY=7,facing="up",
  facingCell=function() return 5,6 end},map={def={}}}, {__index=OW})
g.overworld=ow
local menu=setmetatable({game=g,index=1},Party)
local outdoor={TOWN=true,CITY=true,ROUTE=true,OCEAN_ROUTE=true}
local route,cave
for id,def in pairs(data.maps) do
  ow.map.def=def
  local travel=outdoor[def.mapType] == true
  T.eq(menu:teleportUsable(),travel,id.." Teleport map gate")
  ow.escapePoint=function() return {id="ROUTE",x=5,y=8} end
  T.eq(menu:digUsable(),def.allowEscaping==true,id.." Dig header gate")
  if def.mapType=="ROUTE" then route=id end
  if def.mapType=="UNDERGROUND" and def.allowEscaping then cave=id end
end
T.check(route and cave,"native outdoor and escapable cave exist")
ow.escapePoint=OW.escapePoint
g.save.digWarp=nil;ow.digWarp=nil
ow:rememberDigWarp(route,5,7,cave)
T.eq(g.save.digWarp.id,route,"cave records the outdoor entrance")
T.eq(g.save.digWarp.y,8,"escape lands south of the entrance")
local point=g.save.digWarp
ow:rememberDigWarp(cave,1,2,cave)
T.eq(g.save.digWarp,point,"cave floor transitions retain the entrance")
ow:rememberDigWarp(route,1,2,route)
T.eq(g.save.digWarp,point,"route transitions retain the entrance")
local arrived
ow.startWarpTo=function(_,id,x,y,facing,done) arrived={id,x,y,facing};if done then done() end end
ow.syncSurfingPikachu=function() end;ow.clearBikeFlags=function() end
ow:warpToEscapePoint()
T.eq(arrived[1],route,"escape routes to the entrance rather than heal point")
T.eq(arrived[3],8,"escape uses the recorded landing")
T.eq(ow.doorWarp,nil,"Emerald escape avoids an extra door step")
T.eq(ow.arriveWarp,"teleport","escape arrival plays the spin transition")
g.save.digWarp=nil;ow.digWarp=nil;ow.map.def=data.maps[cave]
T.eq(menu:digUsable(),false,"no escape destination is refused")
T.eq(Rules.allowsTravel({mapType="UNDERWATER"}),false,"Fly/Teleport refuse underwater")
T.eq(Rules.recordsEscape({mapType="UNDERWATER"},{mapType="UNDERGROUND"}),true,"underwater is outdoors for escape recording")

local mon={species="MUDKIP",nickname="SELECTED",moves={{id="SURF"},{id="WATERFALL"},{id="STRENGTH"}}}
g.save.party={mon}
ow.gen3HasBadge=function() return true end
ow.useSurfFieldMove=function() return "ok" end
ow.gen3WaterfallAhead=function() return 5,6,0x13 end
menu.regiUsableBy=function() end
local closed,used,sweep=0,nil,0
menu.close=function() closed=closed+1 end
menu.say=function(_,line) used=line end
local FieldMove=require("src.world.Gen3FieldMove")
local show=FieldMove.show
FieldMove.show=function(_,selected,after) sweep=sweep+1;T.eq(selected,mon,"field sweep uses selected party member");after();return true end
ow.trySurf=function(_,x,y,_,selected) used={"surf",x,y,selected} end
ow.player.surfing=false
menu:useFieldMove(mon,"SURF")
T.eq(closed,1,"Surf closes party")
T.eq(used[1],"surf","Surf menu starts mounting")
T.eq(used[3],6,"Surf uses both facing coordinates")
T.eq(used[4],mon,"Surf text uses selected mon")
ow.player.surfing=true
used=nil;menu:useFieldMove(mon,"SURF")
T.eq(closed,1,"Surf while already surfing leaves menu open")
ow.gen3UseWaterfall=function(_,x,y,b,selected) used={x,y,b,selected} end
menu:useFieldMove(mon,"WATERFALL")
T.eq(closed,2,"Waterfall closes party")
T.eq(used[4],mon,"Waterfall uses selected mon")
ow.player.facing="left";menu:useFieldMove(mon,"WATERFALL")
T.eq(closed,2,"Waterfall refuses sideways facing")
ow.player.facing="up";ow.gen3HasBadge=function() return false end
menu:useFieldMove(mon,"WATERFALL")
T.eq(closed,2,"Waterfall refuses missing badge")
ow.gen3HasBadge=function() return true end
ow.npcAtCell=function() return nil end
T.eq(menu:strengthUsableBy(mon),false,"Strength refuses without facing a boulder")
ow.npcAtCell=function() return {def={pushable=true}} end
T.eq(menu:strengthUsableBy(mon),true,"Strength accepts facing a boulder")
menu:useStrength(mon)
T.eq(g.save.flags[("FLAG_G3_%04X"):format(data.constants.gen3StrengthFlag)],true,"party Strength sets native use flag")
FieldMove.show=show

-- Sweet Scent must use Gen 3 encounter tiles, and never Gen 2's water levels.
local Battle=require("src.battle.BattleState")
local Encounter=require("src.world.Encounter")
local oldNew,oldFor=Battle.newWild,Encounter.forMap
local spawned
Battle.newWild=function(_,species,level) spawned={species,level};return {} end
Encounter.forMap=function() return {grass={rate=10,slots={{species="ZUBAT",level=12}},buckets={100},bucketSpan=100},
  water={rate=10,slots={{species="TENTACOOL",level=20}},buckets={100},bucketSpan=100}} end
ow.pushBattle=function() end
ow.map={id=cave,def=data.maps[cave],isWaterCell=function() return false end,
  isEncounterCell=function() return true end,isGrassCell=function() return false end}
ow.player.surfing=false
ow:gen2SweetScentEncounter()
T.eq(spawned[1],"ZUBAT","Sweet Scent encounters on nongrass cave floor")
ow.map.isEncounterCell=function() return false end
spawned=nil;ow:gen2SweetScentEncounter()
T.eq(spawned,nil,"Sweet Scent refuses nonencounter indoor tile")
ow.player.surfing=true;ow.map.isWaterCell=function() return true end
local waterRules=require("src.world.Gen2EncounterRules")
local oldWater=waterRules.waterLevel
waterRules.waterLevel=function() error("Gen 2 water-level rule must not run for Emerald") end
ow:gen2SweetScentEncounter()
T.eq(spawned[2],20,"Sweet Scent keeps Emerald water slot level")
waterRules.waterLevel=oldWater
Battle.newWild,Encounter.forMap=oldNew,oldFor
Version.set("gold")
ow.map={id="CAVE",def={environment=4},isWaterCell=function() return false end}
ow.player.surfing=false;ow.gen2IsIce=function() return false end
g.save.digWarp=nil;ow.digWarp=nil;g.data.maps.TEST_ROUTE={environment=2};g.data.maps.TEST_CAVE={environment=4}
ow:rememberDigWarp("TEST_ROUTE",5,7,"TEST_CAVE")
T.eq(g.save.digWarp.y,7,"Gen 2 retains entrance-cell landing")
Version.set("emerald")
-- Exercise the bag's actual use path, including consumption and escape option.
local BagMenu=require("src.ui.BagMenu")
g.save.player={name="BRENDAN"};g.save.inventory={ESCAPE_ROPE=3}
ow.map={id=cave,def=data.maps[cave]};g.save.digWarp={id=route,x=5,y=8}
local escapeOpts,bagClosed
ow.beginTeleportOut=function(_,_,opts) escapeOpts=opts end
local list={close=function() bagClosed=true end,items={},index=1}
BagMenu.useItem(g,nil,"ESCAPE_ROPE",list)
T.eq(g.save.inventory.ESCAPE_ROPE,2,"Escape Rope consumes exactly one item")
T.eq(bagClosed,true,"Escape Rope closes the bag")
T.eq(escapeOpts.escape,true,"Escape Rope selects entrance warp")
g.save.digWarp=nil;ow.digWarp=nil;escapeOpts=nil;bagClosed=nil
BagMenu.useItem(g,nil,"ESCAPE_ROPE",list)
T.eq(g.save.inventory.ESCAPE_ROPE,2,"missing entrance does not consume Rope")
T.eq(escapeOpts,nil,"missing entrance does not start an animation")
T.eq(bagClosed,nil,"refused Rope leaves bag open")
ow.map={id=route,def=data.maps[route]};g.save.digWarp={id=route,x=5,y=8}
BagMenu.useItem(g,nil,"ESCAPE_ROPE",list)
T.eq(g.save.inventory.ESCAPE_ROPE,2,"outdoor Rope refusal preserves inventory")
T.eq(escapeOpts,nil,"stale entrance cannot escape from outdoors")
T.finish()
