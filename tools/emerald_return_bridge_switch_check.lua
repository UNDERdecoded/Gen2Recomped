package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald return, bridge and switch regressions')
require('src.core.GameVersion').set('emerald')
local Map=require('src.world.Map')
local SB=require('src.world.Gen3SecretBase')
local map=setmetatable({def={width=4,elevationCells={1,15,0,3}},widthCells=4,heightCells=1},{__index=Map})
local z=1
for _,x in ipairs({1,2})do z=map:elevationAfter(z,x,0);T.eq(z,1,'surfer height survives wildcard '..x)end
T.check(map:elevationBlocks(z,3,0),'upper bridge bank blocks the surfer')
T.check(not map:elevationBlocks(3,3,0),'upper approach still works')
local Collision=require('src.world.Collision')
local shore={inBounds=function()return true end,isWalkableCell=function()return true end,
 isWaterCell=function()return false end,elevationBlocks=function()return true end,
 cellTile=function()return 0 end,cellElevation=function()return 4 end}
local surfer={surfing=true,elevation=1,cellX=0,cellY=0}
local bridgeNpc={cellX=1,cellY=0,gen3Elevation=4}
T.eq(Collision.occupied({bridgeNpc},1,0,surfer),nil,'bridge NPC does not block the river below')
T.eq(Collision.occupied({bridgeNpc},1,0,{elevation=4}),bridgeNpc,'same-deck NPC still blocks movement')
T.check(not Collision.mayEnter(shore,{},surfer,1,0,'right'),'Surf cannot dismount onto bridge elevation 4')
shore.cellElevation=function()return 3 end
T.check(Collision.mayEnter(shore,{},surfer,1,0,'right'),'ordinary shoreline still permits dismount')
local writes={}
local baseMap={def={signs={{x=2,y=3,secretBaseId=10},{x=5,y=6,secretBaseId=20}}},
 tileset={collision={0,144,145}},cellBehaviour=function()return 144 end,
 setBlock=function(_,x,y,tile,shut)writes[#writes+1]={x,y,tile,shut}end}
local save={gen3SecretBase={id=10}}
local data={constants={gen3SecretBases={kinds={[144]=1,[145]=1}}}}
SB.restoreEntrance(data,save,baseMap)
T.eq(#writes,1,'only occupied entrance restores');T.eq(writes[1][3],2,'open art from tileset');T.check(writes[1][4],'entrance remains impassable as ROM requires')
local G=require('src.core.Game');G.data=data;G.save=save
local C=require('src.script.Gen3Commands')
save.gen3DynamicWarp={map='MAP_G00_N22',x=4,y=5}
local ctx={game=G,save=save,g3SecretBaseId=10,overworld={map={id='MAP_G25_N00',def={}},player={cellX=1,cellY=3}}}
C.SPECIALS[6](ctx)
T.eq(save.gen3SecretBase.map,'MAP_G00_N22','claim inside room retains exterior map')
T.eq(save.gen3SecretBase.x,4,'claim retains exterior position')
local OW=require('src.world.OverworldController')
local seen
local ow=setmetatable({player={cellX=2,cellY=3},lastCellX=1,lastCellY=3,cellSerial=7,
 gen4BankStep=function(self)seen=self.cellSerial;error('STEP_CAPTURE')end},{__index=OW})
local ok,why=pcall(ow.onStepComplete,ow)
T.check(not ok and tostring(why):find('STEP_CAPTURE'),'step exercised before downstream state')
T.eq(seen,8,'completed cell is committed before coordinate scripts')
ow:noteCellChange();T.eq(ow.cellSerial,8,'next frame cannot create another visit')
local root='G:/Gen2Recomped/emerald/data/generated/'
local pool=dofile(root..'map_scripts.lua')
local constants=dofile(root..'constants.lua')
local VM=require('src.script.Gen3ScriptVM')
local scripts=require('src.script.MapScripts')
local triggerData={maps={BUG_MOSSDEEP={}},map_scripts={source=pool.source,scripts=pool.scripts,
 maps={BUG_MOSSDEEP={coords={{x=2,y=3,var=0,script='S0220C67'}}}}}}
VM.register(triggerData,'scenes')
local starts=0
ow.runner={isRunning=function()return false end,run=function()starts=starts+1 end}
local hook=scripts.get('BUG_MOSSDEEP').onStep
T.check(hook(G,ow,2,3),'actual Mossdeep switch script starts')
ow:noteCellChange();T.check(not hook(G,ow,2,3),'idle recheck cannot press the same switch again')
T.eq(starts,1,'one activation per landed step')
ow.player.cellX=1;ow:noteCellChange();ow.player.cellX=2;ow:noteCellChange()
T.check(hook(G,ow,2,3),'leaving and returning permits a new activation')
local npc={cellX=0,cellY=0,facing='right',def={index=1}}
local distance=0
local mover={map={blockAt=function()return constants.gen3RotatingTiles.gymBase end},npcs={npc},
 scriptMove=function(_,entity,dir,count,done)distance=distance+count;done()end}
local rotate={game={data={constants=constants,map_scripts=pool}},save={},overworld=mover,
 runner={resume=function()end}}
require('src.script.Commands').g3_rotate_init(rotate,0)
require('src.script.Commands').g3_rotate_move(rotate,0)
T.eq(distance,1,'native rotating-tile movement slides one square')
T.finish()
