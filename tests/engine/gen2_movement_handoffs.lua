package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local Map = require("src.world.Map")
local W = require("src.world.OverworldController")
local Player = require("src.world.Player")
local NPC = require("src.world.NPC")
local Stack = require("src.core.StateStack")
local Transition = require("src.render.Transition")
local Sound = require("src.core.Sound")
local originalVersion, oldSound = V.get(), Sound.play
Sound.play = function() end -- audio device only
local eventProbe=T.sdk.loadMods({"mods/handoff_probe"},{fs=T.sdk.memfs({
  ["mods/handoff_probe/manifest.json"]='{"id":"handoff_probe","name":"Handoff probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ["mods/handoff_probe/main.lua"]=[[
    local mod=...
    mod.exports.moves={}
    mod.events:on("world.boulder_moved",function(ev)
      mod.exports.moves[#mod.exports.moves+1]=ev
    end)
  ]],
})})
T.eq(#eventProbe.errors,0,"native boulder observer loads through the public mod API")
local observed=eventProbe.loader.exports.handoff_probe
local gameSlot, oldGame
for i=1,100 do
  local name,value=debug.getupvalue(W.crossConnection,i)
  if not name then break end
  if name=="Game" then gameSlot,oldGame=i,value;break end
end
assert(gameSlot)
local scriptsSlot,oldScripts
for i=1,100 do
  local name,value=debug.getupvalue(W.checkBoulderPush,i)
  if not name then break end
  if name=="mapScripts"then scriptsSlot,oldScripts=i,value;break end
end
assert(scriptsSlot)
debug.setupvalue(W.checkBoulderPush,scriptsSlot,require("src.script.MapScripts"))
local compass={up="north",down="south",left="west",right="east"}
local opposite={up="down",down="up",left="right",right="left"}
local wall={right=0xB0,left=0xB1,up=0xB2,down=0xB3}
local function fixture(version,x,y)
  V.set(version)
  local data=T.fixtures.fresh()
  data.field.ledges={}
  data.field.ledgeHops={[0xA0]={"right"},[0xA1]={"left"},[0xA2]={"up"},[0xA3]={"down"}}
  local ts={id="HANDOFF",collision={},walkable={0,0xA0,0xA1,0xA2,0xA3},waterTiles={0x29},blocks={}}
  for i=1,76 do ts.collision[i]=0 end
  for byte=0xB0,0xCF do ts.walkable[#ts.walkable+1]=byte end
  local from={id="HANDOFF_FROM",tileset=ts.id,generation=2,width=3,height=3,blocks={1,2,3,4,5,6,7,8,9},connections={},warps={}}
  local dest={id="HANDOFF_TO",tileset=ts.id,generation=2,width=3,height=3,blocks={10,11,12,13,14,15,16,17,18},warps={}}
  for _,c in pairs(compass)do from.connections[c]={map=dest.id,offset=0}end
  data.maps[from.id]=from;data.maps[dest.id]=dest;data.tilesets[ts.id]=ts
  local p=setmetatable({cellX=x or 2,cellY=y or 2,facing="right",moving=false,progress=0,stepFrames=16,turnTimer=0},{__index=Player})
  p.px,p.py=p.cellX*16,p.cellY*16
  local w=setmetatable({map=Map.new(from,ts),player=p,npcs={},ghosts={},entities={p},scriptMoves={},pendingScripts={},runner={isRunning=function()return false end},mapChanges=0},{__index=W})
  local game={data=data,save={onBike=false,flags={},party={}},overworld=w,stack=setmetatable({states={}},{__index=Stack})}
  debug.setupvalue(W.crossConnection,gameSlot,game)
  -- Only renderer/map materialization is replaced. Connection selection,
  -- eligibility, movement queues, actor interpolation and callbacks are real.
  function w:setMap(id,cx,cy,facing)
    self.mapChanges=self.mapChanges+1;self.map=Map.new(data.maps[id],ts)
    p.cellX,p.cellY,p.px,p.py,p.facing=cx,cy,cx*16,cy*16,facing
    p.targetX,p.targetY,p.moving=nil,nil,false
  end
  function w:followCamera()end
  local function put(def,cx,cy,byte)
    local block=def.blocks[math.floor(cy/2)*def.width+math.floor(cx/2)+1]
    ts.collision[block*4+(cy%2)*2+cx%2+1]=byte
  end
  return w,game,from,dest,put
end
local function edge(dir)
  if dir=="up" then return 2,0,2,5 end
  if dir=="down" then return 2,5,2,0 end
  if dir=="left" then return 0,2,5,2 end
  return 5,2,0,2
end
-- Regressions for the native grid entry point as well as its new public seam.
for _,version in ipairs({"gold","silver","crystal","prism"})do
  for _,dir in ipairs({"up","down","left","right"})do
    local x,y,tx,ty=edge(dir)
    for _,side in ipairs({"source","destination"})do
      local w,game,from,dest,put=fixture(version,x,y)
      if side=="source" then put(from,x,y,wall[dir]) else put(dest,tx,ty,wall[opposite[dir]]) end
      T.eq(w:crossConnection(dir,from.connections[compass[dir]]),false,version.." native seam refuses "..side.." side wall")
      T.eq(w.mapChanges,0,"refused seam does not load another map")
      T.eq(w.player.moving,false,"refused seam cannot start a step")
    end
  end
end
for _,name in ipairs({"tryConnection","tryLedgeJump","tryPushBoulder"})do T.eq(type(W[name]),"function","public native handoff exists: "..name)end
for _,version in ipairs({"gold","silver","crystal","prism"})do
  -- All four real seam interpolations, including a caller arriving off-grid.
  for _,dir in ipairs({"up","down","left","right"})do
    local x,y,tx,ty=edge(dir)
    local w,game,from,dest=fixture(version,x,y)
    w.player.px=w.player.px+3;w.player.py=w.player.py-2
    T.eq(w:tryConnection(dir),true,version.." public seam uses native crossing")
    T.eq(w.mapChanges,1,"one native map swap")
    T.eq(w.map.id,dest.id,"actual selected destination")
    T.eq(w.player.moving,true,"native seam owns interpolation")
    T.eq(w.player.targetX,tx,"native seam target x")
    T.eq(w.player.targetY,ty,"native seam target y")
    T.eq(w:tryConnection(dir),false,"ongoing seam rejects reentry")
    for _=1,20 do w.player:update()end
    T.eq(w.player.cellX,tx,"native player completes seam x")
    T.eq(w.player.cellY,ty,"native player completes seam y")
    T.eq(w.player.px,tx*16,"native player completes centered pixels")
    T.eq(w.player.moving,false,"seam releases actor")
  end
  -- Real ledge queue and player interpolation; the landing is two cells away.
  local w,game,from,dest,put=fixture(version)
  put(from,2,2,0xA0);put(from,3,2,0x07)
  w.player.px=w.player.px+4
  T.eq(w:tryLedgeJump("right"),true,"public ledge hands off to native queue")
  T.eq(#w.scriptMoves,1,"one native ledge move")
  T.eq(w.player.hopFrames,32,"native ledge arc")
  T.eq(w:tryLedgeJump("right"),false,"queued ledge rejects reentry")
  for _=1,40 do w:updateScriptMoves();w.player:update()end
  T.eq(w.player.cellX,4,"real two-cell hop lands")
  T.eq(w.player.moving,false,"real ledge interpolation ends")
  T.eq(#w.scriptMoves,0,"native ledge queue drains")
  -- Boulders retain their own native animation, callback and event owner.
  w,game,from,dest,put=fixture(version)
  local b=setmetatable({id="HANDOFF_BOULDER",def={index=1,pushable=true},cellX=3,cellY=2,px=48,py=32,moving=false,progress=0,frozen=true,stepFrames=16},{__index=NPC})
  w.npcs={b};w.entities={w.player,b};w.strengthActive=true
  observed.moves={}
  T.eq(w:tryPushBoulder("right",4,2),false,"remote cell cannot be supplied as faced boulder")
  T.eq(w:tryPushBoulder("right",3,2),true,"native Strength queue accepts adjacent boulder")
  T.eq(w:tryPushBoulder("right",3,2),false,"queued push rejects duplicate handoff")
  T.eq(#observed.moves,0,"push event waits for native completion")
  for _=1,24 do w:updateScriptMoves();b:update(w.map,w.entities)end
  T.eq(b.cellX,4,"real NPC interpolation settles the boulder")
  T.eq(w.player.cellX,2,"pushing player stays in their cell")
  T.eq(#observed.moves,1,"public observer receives native push completion once")
  T.eq(observed.moves[1].x,4,"settled boulder event has native x")
  T.eq(observed.moves[1].y,2,"settled boulder event has native y")
  T.eq(observed.moves[1].npcId,b.id,"settled boulder event identifies actual native actor")
  T.eq(observed.moves[1].mapId,from.id,"settled boulder event identifies actual native map")
  T.eq(#w.scriptMoves,0,"native boulder queue drains")
  T.check(w.dustAnim~=nil,"native boulder completion owns its dust animation")
  -- Both the standing side and destination side must permit the boulder.
  for _,side in ipairs({"player","source","destination"})do
    w,game,from,dest,put=fixture(version)
    b=setmetatable({id="BOULDER",def={index=1,pushable=true},cellX=3,cellY=2,moving=false},{__index=NPC})
    w.npcs={b};w.entities={w.player,b};w.strengthActive=true
    if side=="player"then put(from,2,2,0xB0)
    elseif side=="source"then put(from,3,2,0xB0)else put(from,4,2,0xB1)end
    T.eq(w:checkBoulderPush("right"),false,"native push refuses "..side.." side wall")
    T.eq(#w.scriptMoves,0,"blocked boulder never joins the script queue")
    T.eq(w:tryPushBoulder("right",3,2),false,"public push retains native directional fence")
  end
end
-- Water is still decided by native passability after directional fences.
for _,surfing in ipairs({false,true})do
 local w,g,from,dest,put=fixture("crystal",5,2)
 put(dest,0,2,0x29);w.player.surfing=surfing
 T.eq(w:tryConnection("right"),surfing,"native seam retains land/surf admission")
 T.eq(w.mapChanges,surfing and 1 or 0,"water refusal cannot materialize destination")
end
-- Wrong-way exit-mat probes cannot warp; the right direction takes the real
-- native fade even when standingOnWarp is false for that carpet.
do
 local w,g,from,dest,put=fixture("crystal",2,5)
 put(from,2,5,0x70)
 from.warps={{x=2,y=5,destMap=dest.id,destWarp=1}}
 dest.warps={{x=1,y=1,destMap=from.id,destWarp=1}}
 w.map=Map.new(from,g.data.tilesets[from.tileset])
 w.standingOnWarp=false
 T.eq(w:tryConnection("right"),false,"sideways carpet probe cannot exit")
 T.eq(#g.stack.states,0,"wrong-way carpet retains empty overlay stack")
 T.eq(w:tryConnection("down"),true,"directional carpet takes native input-side warp")
 local fade=g.stack:top()
 T.eq(getmetatable(fade),Transition,"public exit acquires the actual native transition")
 T.eq(w:tryConnection("down"),false,"native transition blocks same-tick carpet reentry")
 for _=1,fade.frames+fade.framesIn+2 do if g.stack:top()==fade then fade:update(1/60)end end
 T.eq(w.mapChanges,1,"native carpet fade materializes once")
 T.eq(w.map.id,dest.id,"native carpet reaches resolved destination")
 T.eq(w.transitioning,false,"native fade releases transition ownership")
end
-- Native cutscenes keep their explicitly collision-free seam path.
do
 local w,game,from,dest,put=fixture("crystal",5,2);put(from,5,2,0xB0);put(dest,0,2,0xB1)
 T.eq(w:crossConnection("right",from.connections.east,true),true,"scripted seam retains deliberate collision bypass")
end
-- Each owner/lock is checked before a special can be started, on all three APIs.
local methods={
 function(w)return w:tryConnection("right")end,
 function(w)return w:tryLedgeJump("right")end,
 function(w)return w:tryPushBoulder("right",3,2)end,
}
for _,call in ipairs(methods)do
 local w,g=fixture("crystal")
 local calls=0
 w.checkEdgeExit=function()calls=calls+1;return true end
 w.checkLedgeHop=function()calls=calls+1;return true end
 w.checkBoulderPush=function()calls=calls+1;return true end
 w.checkGen2CarpetExit=function()return false end
 for _,key in ipairs({"transitioning","flyAnim","teleportOut","engaging","emote","whirlSpin","battleActive","fieldMove","fishing","headbutt","mapSetup","moveState","iceSlide"})do
  w[key]=true;T.eq(call(w),false,"native owner refuses handoff: "..key);w[key]=nil
 end
 for _,key in ipairs({"moving","inputLocked","stairExit","spinning","fieldMove"})do
  w.player[key]=true;T.eq(call(w),false,"native actor owner refuses handoff: "..key);w.player[key]=nil
 end
 g.stack.states={{}};T.eq(call(w),false,"overlay keeps input ownership");g.stack.states={}
 w.runner.isRunning=function()return true end;T.eq(call(w),false,"native VM retains ownership");w.runner.isRunning=function()return false end
 w.scriptMoves={{}};T.eq(call(w),false,"script queue retains ownership");w.scriptMoves={}
 w.pendingScripts={{}};T.eq(call(w),false,"pending map script retains ownership");w.pendingScripts={}
 for _,direction in ipairs({"diagonal","",false,17,{}})do
  T.eq(w:tryConnection(direction),false,"invalid connection direction cannot enter native handler")
  T.eq(w:tryLedgeJump(direction),false,"invalid ledge direction cannot enter native handler")
  T.eq(w:tryPushBoulder(direction,3,2),false,"invalid boulder direction cannot enter native handler")
 end
 local owner=g.overworld;g.overworld={};T.eq(call(w),false,"stale world cannot mutate current owner");g.overworld=owner
 g.linkSession={};T.eq(call(w),false,"link session keeps ownership");g.linkSession=nil
 T.eq(calls,0,"all refusals happen before native special dispatch")
 w.whirlHold=1;T.eq(call(w),false,"unexpired whirlpool hold retains control")
 w.whirlHold=0;T.eq(call(w),true,"expired numeric hold permits native handoff")
 T.eq(calls,1,"expired hold dispatches exactly once");w.whirlHold=nil
 for _,version in ipairs({"red","emerald","platinum"})do V.set(version);T.eq(call(w),false,"Gen2 facade cannot mutate another generation")end
end
-- A synchronous native handler callback cannot queue a second public special.
do
 local w=fixture("crystal");local nested=0
 w.checkLedgeHop=function()nested=nested+1;return true end
 w.checkGen2CarpetExit=function()return false end
 w.checkEdgeExit=function(self)
  T.eq(self:tryLedgeJump("right"),false,"native callback cannot reenter public handoff")
  return true
 end
 T.eq(w:tryConnection("right"),true,"outer native handler completes")
 T.eq(nested,0,"nested handler was never entered")
 w.checkEdgeExit=function()error("native handoff fixture error")end
 T.raises(function()w:tryConnection("right")end,"native handoff fixture error","native failures remain observable")
 T.eq(w:tryLedgeJump("right"),true,"error cannot leave an admission lock behind")
 T.eq(nested,1,"next valid native handler is admitted once")
end
eventProbe.release();Sound.play=oldSound;debug.setupvalue(W.crossConnection,gameSlot,oldGame)
debug.setupvalue(W.checkBoulderPush,scriptsSlot,oldScripts);V.set(originalVersion)
T.finish("native Gen2 special movement handoffs")
