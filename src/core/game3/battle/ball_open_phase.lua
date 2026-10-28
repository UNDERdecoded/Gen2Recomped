-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Notification of the actual native release, without another opening player.
local Battle=require('src.core.game3.battle')
local Clock=require('src.battle.PresentationClock')
local Coords=require('src.core.game3.battle.anim_coords')
local Coroutines=require('src.compat.gen1.CoroutineScopes')
local scopes=Coroutines.new()
local seen=setmetatable({},{__mode='k'})
local M={}
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function live(c)
 local r=c.refs;local s,a=r[1],r[2]
 return s and a and Battle._screen()==s and Battle.getState()==r[3]
  and s.gen3Ball==a and s.game.data==r[4]and s.game.save==r[5]
  and s.game.stack==r[6]and s.game.mods==r[7]and s.game.stack:top()==s
  and s.frame==c.frame and a.frame==c.ballFrame and a.phase=='release'
  and a.phaseFrame==0 and Clock.active(s)
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function M.open(key,x,y)
 local phase=scopes:find('native.ball.open');local c=phase and phase.value
 if not c or not live(c)then return false,'no admitted native opening'end
 if Coords.idOf(key)~=c.id then return false,'opening belongs to another native battler'end
 assert(finite(x)and finite(y),'invalid opening presentation origin')
 -- The native update already opened the ball and spawned its effects. The
 -- provider may observe/project this notification, never run that update again.
 return true
end
function M.notify(screen,anim,callback)
 if seen[anim]or not anim.sendOut or anim.phase~='release'or anim.phaseFrame~=0
  or screen.gen3Ball~=anim or not Clock.active(screen)or Battle._screen()~=screen
  or screen.game.stack:top()~=screen then return false end
 local id
 for i=0,3 do if screen:battlerAt(i)==anim.battler then id=i;break end end
 if id==nil then return false end
 seen[anim]=true
 local c={id=id,frame=screen.frame,ballFrame=anim.frame,
  refs=setmetatable({screen,anim,Battle.getState(),screen.game.data,screen.game.save,
   screen.game.stack,screen.game.mods},{__mode='v'})}
 local x,y=anim.x,anim.y
 screen,anim=nil,nil
 local phase=scopes:push('native.ball.open',c)
 local result=pack(pcall(callback,id,x,y))
 local retired=Coroutines.retired()or phase.closed
 scopes:close(phase);c.refs={}
 if not result[1]then error(result[2],0)end
 assert(not retired,'native opening phase retired while suspended')
 return unpack(result,2,result.n)
end
return M
