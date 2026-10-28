-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Probe=dofile('tests/native_action_plan/turn.lua')
local Ball=require('src.battle.Gen3BallAnim')
local Stage=require('src.core.game3.battle.stage')
local Observation=require('src.compat.gen1.NativeBallObservation')
local projectionTurn=(625/256)*math.pi*2
local function scalar(a)
 return {x=a.x,y=a.y,phase=a.phase,phaseFrame=a.phaseFrame,frame=a.frame,ballFrame=a.ballFrame,
  monScale=a.monScale,monBlend=a.monBlend,monHidden=a.monHidden,monRise=a.monRise,
  sound=a.sound,done=a.done,whiteout=a.whiteout,shakeOffset=a.shakeOffset}
end
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 local f,b=Probe.open(edition);b:syncSides()
 b.data.constants.gen3BallAnim={size=16,frames=3,timing={sendOut={frames=25}},sounds={}}
 local actual=Ball.new(b.data,{sendOut='player',battler=b.player,to={x=72,y=80}})
 local control=Ball.new(b.data,{sendOut='player',battler=b.player,to={x=72,y=80}})
 b.gen3Ball=actual;b.gen3BallPlaying=true
 local stage=Stage.current();local view=stage.ball;local previous=-1
 for tick=0,25 do
  local before=scalar(actual)
  local progress=(view.frame or 0)>0 and 1 or view.rot/projectionTurn
  T.check(progress>=previous,'the presentation driver advances during the closed-ball flight')
  T.check(math.abs(progress-tick/25)<1e-10,'the presentation driver tracks the actual native throw fraction')
  if tick>0 and tick<25 then T.check(view.rot>0,'a moving send-out cannot report a stationary angle')end
  for _=1,4 do T.eq(view.rot,Observation.read(b,actual,'rot'));T.eq(view.scale,1)end
  T.same(scalar(actual),before,'repeated presentation reads never advance native ball/mon/sound clocks')
  T.same(scalar(actual),scalar(control),'native timeline is unchanged by source observation')
  previous=progress
  if tick<25 then actual:update();control:update()end
 end
 T.eq(view.rot,0,'native opening resets the presentation orientation')
 T.eq(actual.phase,'release');T.eq(view.frame,2)
 for _,send in ipairs{'opponent','capture'}do
  local a=Ball.new(b.data,{sendOut=send=='opponent'and send or nil,battler=b.enemy})
  T.eq(Observation.read(b,a,'rot'),0,'opponent/capture do not borrow the player-send clock')
  for _=1,5 do a:update();T.eq(Observation.read(b,a,'rot'),0)end
 end
 b.gen3Ball=nil;T.eq(view.visible,false,'retired ball observations cannot project a new flight')
 Probe.close(f)
end
-- Imported timing still owns duration. A renderer's unwrapped angular range
-- follows that native duration even when a content record changes it.
for _,frames in ipairs{10,40}do
 local data={constants={gen3BallAnim={timing={sendOut={frames=frames}},sounds={}}}}
 local a=Ball.new(data,{sendOut='player'})
 for tick=1,frames-1 do
  a:update();local fraction=Observation.read({},a,'rot')/projectionTurn
  T.check(math.abs(fraction-tick/frames)<1e-10,'native imported duration owns the source flight fraction')
 end
end
T.finish('Actual native send-out progress, source angular projection, unchanged clocks and ball retirement')
