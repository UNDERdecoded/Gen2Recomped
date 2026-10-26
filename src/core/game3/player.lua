-- Compatibility avatar operations on the live native actor. No second player,
-- collision simulator, event runner or on-disk save writer lives here.
local Session = require('src.compat.gen1.NativeSession')
local runtime = require('src.compat.gen1.PlayerRuntime').new()
local Player = {}
local directions = {up={0,-1},down={0,1},left={-1,0},right={1,0}}
local direct = {}
for name in ('cellX cellY px py facing moving progress targetX targetY turnTimer turnArmed animClock running surfing fishing spinning moveDir facingLocked'):gmatch('%S+') do direct[name]=name end
direct.currentElevation='elevation'; direct.elevation='elevation'
direct.walkInPlace='compatWalkInPlace';direct.walkInPlaceFast='compatWalkInPlaceFast'
local function owner(game)
  local c=runtime:scope()
  if not game and c then game=c.game end
  return Session.resolve(game)
end
local function inputOwner(game)
  local g,w,p=owner(game)
  if not g or not Session.acceptsInput(g,w,p) then return nil,'native field input is locked' end
  return g,w,p
end
local function finite(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end
local function withDirection(dir,run,input)
  return setmetatable({isDown=function(_,key)
    if directions[key] then return key==dir end
    if key=='b' and run~=nil then return run==true end
    return input and input.isDown and input:isDown(key) or false
  end,wasPressed=function()return false end,wasReleased=function()return false end},{__index=input})
end
function Player.tick(game)return runtime:tick(game)end
function Player.update(game,input)
  Player.tick(game)
  return runtime:input(input)
end
local baseUpdate=Player.update
function Player._dispatch(game,world,input)
  -- Mere imports do not change ordinary native gameplay. A source wrapper
  -- opts into this phase by wrapping the established update entry point.
  if Player.update==baseUpdate then return false end
  local g,w,p=owner(game)
  if g~=game or w~=world or not Session.acceptsInput(g,w,p) then return false end
  local facade=package.loaded['src.core.Game3']
  facade=type(facade)=='table' and type(facade.forNative)=='function' and facade.forNative(game) or game
  runtime:run(game,world,facade,input,Player.update)
  return true
end
function Player.tryMove(dir,game,run,input)
  if not directions[dir] then return nil end
  local g,w=inputOwner(game);if not g then return nil,w end
  local c=runtime:scope()
  if not c then return nil,'movement input belongs to the native fixed-step phase' end
  -- The real controller retains its ledges, gates, bikes, collision warps,
  -- sound and movement hooks; translating its input preserves those owners.
  c.inputPolled=false
  return runtime:input(withDirection(dir,run,input or g.input))
end
function Player.fieldTriggers(game,dir)
  if not directions[dir] then return nil end
  local g,w,p=inputOwner(game);if not g or p.moving or p.facing~=dir then return nil end
  for _,name in ipairs({'checkGen3ArrowWarp','checkEdgeExit','checkLedgeHop','checkBoulderPush','checkGen3Gate'})do
    if w[name] and w[name](w,dir) then return true end
  end
  return false
end
function Player.forcedStep(dir,frames,opts)
  local delta=directions[dir];if not delta then return false end
  local g,w,p=inputOwner();if not g or p.moving then return false end
  local c=runtime:scope()
  if not c or c.advanced then return false end
  opts=opts or {};frames=frames or p.stepFrames or 16
  if not finite(frames) or frames<1 or frames%1~=0 then return false end
  if (opts.ledgeX~=nil or opts.ledgeY~=nil) then
    -- Native ledge geometry/animation belongs to the native field handler.
    return w.checkLedgeHop and w:checkLedgeHop(dir) or false
  end
  if not opts.keepFacing then p.facing=dir end
  p.moveDir=dir;p.targetX=p.cellX+delta[1];p.targetY=p.cellY+delta[2]
  p.moving=true;p.progress=0;p.stepFramesCur=frames;p.bumpFrames=nil
  return true
end
function Player.setVisible(visible)
  local g,_,p=owner();if not g then return false end
  p.visible=visible~=false;p.hidden=not p.visible
  return true
end
function Player.isVisible()
  local g,_,p=owner();return g and not(p.hidden or p.invisible or p.visible==false) or false
end
function Player.syncSavePosition(game)
  local g,w,p=owner(game);if not(g and g.save and g.save.player)then return false end
  local saved=g.save.player
  saved.map,saved.x,saved.y,saved.facing=w.map.id,p.cellX,p.cellY,p.facing
  saved.surfing=p.surfing==true
  return true -- in-memory native state only; persistence remains SaveIO's job
end
function Player.runningDisallowed(x,y)
  local g,w=owner();if not g then return true end
  return not(w.map.def and w.map.def.allowRunning)
    or (w.map.runningBlockedAt and w.map:runningBlockedAt(x,y)) or false
end
function Player.canDash()
  local g,w,p=owner();if not g or p.surfing or w.map.def.mapType=='UNDERWATER' then return false end
  return w.runFrames and w:runFrames(true)~=nil or false
end
function Player.walkPhase()
  local g,_,p=owner();return g and p:walkPhase() or 0
end
function Player.runPose()
  local g,_,p=owner()
  if not g or not(p.moving and p.running)or(g.save and g.save.onBike)or p.surfing or(p.hopFrames or 0)>0 then return nil end
  return p:walkPhase()
end
function Player.drawFlip()
  local g,_,p=owner();return g and math.floor((p.animClock or 0)/16)%2==1 or false
end
function Player.startFieldMove(duration,kind)return require("src.compat.gen1.PlayerPose").start(duration,kind)end
function Player.release()runtime:release()end
-- Title/intro presentation can inspect the pending native spawn before a
-- world actor exists. Read its saved cells; all writes and motion still need
-- an admitted player. No fabricated avatar or independent boot position.
local function pendingPosition(key)
  local g=Session.game();local saved=g and g.save and g.save.player
  local def=saved and g.data and g.data.maps and g.data.maps[saved.map]
  if not def or not finite(saved.x)or not finite(saved.y)
    or saved.x%1~=0 or saved.y%1~=0 or saved.x<0 or saved.y<0
    or(type(def.width)=='number'and saved.x>=def.width)
    or(type(def.height)=='number'and saved.y>=def.height)then return nil end
  if key=='px'then return saved.x*16 end
  if key=='py'then return saved.y*16 end
  if key=='cellX'then return saved.x end
  if key=='cellY'then return saved.y end
  if key=='facing'then return saved.facing end
end
setmetatable(Player,{
  __index=function(_,key)
    local g,w,p=owner();if key=="running"then return g~=nil and p.running==true end
    if not g then return pendingPosition(key)end
    if direct[key]then return p[direct[key]]end
    if key=='stepFrames'then return p.stepFramesCur or p.stepFrames end
    if key=='biking'then return g.save and g.save.onBike==true end
    if key=='bikeType'then return p.acroBike and 'acro' or(g.save and g.save.bikeType)end
    if key=='underwater'then return w.map.def.mapType=='UNDERWATER'end
    if key=='jumping'then return (p.hopFrames or 0)>0 end
    if key=='visible'then return Player.isVisible()end
    if key=='fieldMoveAnim'then return p.fieldMove and(p.fieldMoveFrames or 1)or 0 end
    if key=='stepSerial'or key=='prevCellX'or key=='prevCellY'then return runtime:record(p)[key]end
  end,
  __newindex=function(t,key,value)
    if not(direct[key]or key=='stepFrames'or key=='biking'or key=='visible')then rawset(t,key,value);return end
    local g,_,p=owner();if not g then error('no active native player for '..key,2)end
    if type(value)=='number' and not finite(value)then error('non-finite player '..key,2)end
    if direct[key]then p[direct[key]]=value
    elseif key=='stepFrames'then
      assert(finite(value)and value>=1 and value%1==0,'invalid player step frames');p.stepFramesCur=value
    elseif key=='biking'then g.save.onBike=value==true
    elseif key=='visible'then Player.setVisible(value)end
  end,
})
return Player
