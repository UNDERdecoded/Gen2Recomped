-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Shared scalar projection of the actual native ball, not another timeline.
local M={keys={'visible','x','y','frame','ballId','side','battler','rot','scale','alpha'}}
function M.read(screen,ball,key)
 if key=='visible'then return not ball.done or ball.caught==true end
 if key=='x'then return ball.x+(ball.shakeOffset or 0)end
 if key=='y'then return ball.y end
 if key=='frame'then return math.max(0,(ball.ballFrame or 1)-1)end
 if key=='ballId'then return ball.ball end
 if key=='battler'or key=='side'then
  local id=1
  for i=0,3 do
   local b=i==0 and screen.player or i==1 and screen.enemy or screen:battlerAt(i)
   if b and ball.battler==b then id=i;break end
  end
  return key=='battler'and id or(id%2==0 and'player'or'enemy')
 end
 if key=='rot'then
  -- Presentation consumers use the unwrapped send-out angle as their flight
  -- coordinate. Project the actual native throw clock; never advance a second
  -- animation or infer progress from a screen-space position.
  if ball.sendOut=='player'and ball.phase=='throw'then
   local duration=ball.send and ball.send.frames or 25
   if type(duration)=='number'and duration>0 and duration<math.huge then
    return math.min(1,(ball.phaseFrame or 0)/duration)*(625/256)*math.pi*2
   end
  end
  return 0
 end
 if key=='scale'then return 1 end -- Native ball cells draw at their own size.
 if key=='alpha'then return 1-(ball.whiteout or 0)end
end
return M
