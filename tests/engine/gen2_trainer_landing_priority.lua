package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local oldVersion=V.get()
local W=require('src.world.OverworldController');local Map=require('src.world.Map')
local Music=require('src.core.Music');local oldPlay=Music.play;Music.play=function()end -- audio device only
for _,version in ipairs({'gold','silver','crystal','prism'})do
V.set(version)
local data=T.fixtures.fresh();local def={id='TRAINER_ROAD',label='TrainerRoad',tileset='FIX_OUT',width=4,height=4,generation=2,environment=2,blocks={}}
for i=1,16 do def.blocks[i]=1 end;data.maps[def.id]=def
data.tilesets.FIX_OUT.walkable={0,1,2};data.tilesets.FIX_OUT._walkableSet=nil -- native importer list format
data.tilesets.FIX_OUT.collision={};for i=1,16 do data.tilesets.FIX_OUT.collision[i]=0 end
data.tilesets.FIX_OUT.collision[16]=0x72;def.blocks[6]=3 -- actual Gen2 stair collision only on landing quadrant
def.warps={{x=3,y=3,destMap='OTHER',destWarp=1}}
local npc={id=def.id..'_obj_1',cellX=3,cellY=1,facing='down',def={index=1,trainerClass='OPP_LASS',trainerObject=true,sightRange=4}}
local p={cellX=3,cellY=3,facing='down',moving=false}
local world=setmetatable({map=Map.new(def,data.tilesets.FIX_OUT),player=p,npcs={npc},entities={npc,p},scriptMoves={},runner={isRunning=function()return false end}}, {__index=W})
local save={flags={},defeatedTrainers={},party={{hp=10}}}
local game={data=data,save=save,overworld=world,stack={}}
game.stack.top=function()return world end;game.stack.active=game.stack.top
local slot,oldGame
for i=1,100 do local name,value=debug.getupvalue(W.onStepComplete,i);if not name then break end;if name=='Game'then slot,oldGame=i,value;break end end
assert(slot);debug.setupvalue(W.onStepComplete,slot,game)
local advanced=false
world.gen4BankStep=function()advanced=true;error('downstream landing boundary reached')end
T.check(require('src.world.Warp').onArrive(world.map,3,3,'down')~=nil,'positive control: this real landing would otherwise activate a native warp')
W.checkTrainerSight(world)
T.eq(world.engaging,true,'positive control: real geometry/visibility/header scan can start the approach')
world.engaging,world.emote=nil,nil;npc.frozen=nil
local ok=W.onStepComplete and pcall(W.onStepComplete,world)
T.eq(ok,true,'real Gen2 landing is claimed by actual trainer sight before downstream step/warp/coord work')
T.eq(advanced,false,'no later landing phase runs after the trainer claims the cell')
T.eq(world.engaging,true,'actual native approach owns the player')
T.eq(npc.frozen,true,'actual spotted trainer is frozen for the approach')
T.eq(world.emote and world.emote.npc,npc,'native approach queues the correct trainer alert')
local function reset()
 world.engaging,world.emote=nil,nil;npc.frozen=false;advanced=false
end
reset();save.defeatedTrainers[npc.id]=true
pcall(W.onStepComplete,world)
T.eq(advanced,true,'beaten trainer leaves downstream native landing phases available')
T.eq(world.engaging,nil,'beaten trainer does not restart an approach')
save.defeatedTrainers={};reset();save.party={}
-- Direct native sight checks must also retain the cartridge's no-party gate.
W.checkTrainerSight(world)
T.eq(world.engaging,nil,'no-party player cannot be forced into a trainer battle')
reset();save.party={{hp=10}};npc.def.sightRange=0
pcall(W.onStepComplete,world)
T.eq(advanced,true,'talk-only trainer cannot swallow a landing')
T.eq(world.engaging,nil,'zero sight range does not engage')
reset();npc.def.sightRange=4;p.moving=true
T.eq(W.checkTrainerSight(world),false,'mid-step scan reports no claimed event')
p.moving=false
reset();world.runner.isRunning=function()return true end
local guarded=W.checkTrainerBattle and W.checkTrainerBattle(world)
T.eq(guarded,false,'public trainer landing seam refuses a running native script')
T.eq(world.engaging,nil,'scripted movement cannot start an unscripted approach')
world.runner.isRunning=function()return false end
reset();world.npcs={}
T.eq(W.checkTrainerSight(world),false,'empty sight scan returns a useful event verdict')
debug.setupvalue(W.onStepComplete,slot,oldGame)
end
Music.play=oldPlay;V.set(oldVersion)
T.finish('native Gen2 trainer priority at a completed landing')
