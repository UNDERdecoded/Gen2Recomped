local F={}
function F.new(edition)
  require('src.core.GameVersion').set(edition)
  local Game=require('src.core.Game')
  local Native=require('src.world.Player')
  local OW=require('src.world.OverworldController')
  -- enter() normally binds this shared upvalue while loading a full world.
  -- This ROM-free fixture exercises the real phase without loading assets.
  for i=1,100 do
    local name=debug.getupvalue(OW.stepBody,i)
    if not name then break end
    if name=='Game'then debug.setupvalue(OW.stepBody,i,Game);break end
  end
  local input={held={},edges={}}
  function input:isDown(key)return self.held[key]==true end
  function input:wasPressed(key)return self.edges[key]==true end
  function input:wasReleased()return false end
  local map={id='TEST',def={mapType='ROUTE',allowRunning=true},blocked={}}
  function map:inBounds(x,y)return x>=0 and y>=0 and x<20 and y<20 end
  function map:isWalkableCell(x,y)return not self.blocked[x..':'..y]end
  function map:cellElevation()return 3 end
  function map:runningBlockedAt(x,y)return self.noRunning or false end
  local player=setmetatable({cellX=4,cellY=4,px=64,py=64,facing='right',moving=false,
    progress=0,stepFrames=16,bikeStepFrames=4,turnTimer=0,turnArmed=true,
    elevation=3,animClock=0,stepFlip=false},Native)
  local ow=setmetatable({isOverworld=true,player=player,map=map,npcs={},entities={},ghosts={},scriptMoves={},
    runner={isRunning=function()return false end},arrivals=0,casts=0,inputs=0},{__index=OW})
  function ow:updateCast()self.casts=self.casts+1 end
  function ow:updateScriptMoves()end
  function ow:checkTrainerSight()end
  function ow:onStepComplete()self.arrivals=self.arrivals+1;if self.onArrival then self:onArrival()end end
  for _,name in ipairs({'checkGen2Whirlpool','checkHgssLadder','checkGen2CarpetExit','checkGen3ArrowWarp',
    'checkGen4EntranceWarp','checkEdgeExit','checkLedgeHop','checkBoulderPush','checkGen3Gate',
    'checkAcroSideJump','canCollisionWarp','checkGen2Stairs','orbitalGroundFor','frlgPullDownHere'})do
    ow[name]=function()return false end
  end
  function ow:walkDirection(dir)return dir end
  function ow:handleInput()self.inputs=self.inputs+1;return OW.handleInput(self)end
  function ow:noteRunGate()end
  Game.data={maps={TEST=map.def},field={},constants={world={runStepFrames=8},gen3RunningShoesFlag=1}}
  Game.save={player={},flags={FLAG_G3_0001=true},party={},onBike=false}
  Game.input=input;Game.overworld=ow;Game.stack={states={ow}}
  return {game=Game,world=ow,player=player,input=input,map=map}
end
return F
