-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Short field gestures use the native player's fixed step and pose owner.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local M={}
local active
local function release()
 local a=active;active=nil
 if a and a.player._gen3FieldMovePoseOwner==a then
  a.player.fieldMove,a.player.fieldMovePose,a.player.fieldMoveFrames=a.previous,a.pose,a.frames
  a.player._gen3FieldMovePoseOwner=a.previousOwner
 end
end
local function live(a)
 local g,w,p=Native.resolve()
 return a and g==a.game and w==a.world and p==a.player and w.map==a.map and g.data==a.data
  and g.save==a.save and g.mods==a.loader and Version.get()==a.edition
end
function M.start(duration,kind)
 if active and not live(active)then release()end
 local g,w,p=Native.resolve();if not g or p.moving or p._gen3FieldMovePoseOwner then return false end
 duration=duration or 28
 assert(type(duration)=='number'and duration%1==0 and duration>=1 and duration<=3600,'invalid field gesture duration')
 assert(kind==nil or type(kind)=='string','invalid field gesture kind')
 local host=require('src.mods.Runtime');local facade=require('src.core.Game3');local who=host.currentMod or facade._callbackOwner()
 if not who then return false end
 active={game=g,world=w,player=p,map=w.map,data=g.data,save=g.save,loader=g.mods,edition=Version.get(),who=who,
  remaining=duration,previous=p.fieldMove,pose=p.fieldMovePose,frames=p.fieldMoveFrames,previousOwner=p._gen3FieldMovePoseOwner}
 p._gen3FieldMovePoseOwner=active;p.fieldMove=true;p.fieldMovePose=kind or'field_move';p.fieldMoveFrames=duration
 return true
end
function M.tick(player)
 local a=active;if not a then return end
 if not live(a)or a.player._gen3FieldMovePoseOwner~=a then release();return end
 if player~=a.player then return end
 a.remaining=a.remaining-1;a.player.fieldMoveFrames=a.remaining
 if a.remaining<=0 then release()end
end
M.release=release
M.releaseOwner=function(_,who)if active and active.who==who then release()end end
M.poll=function()if active and not live(active)then release()end end
require('src.core.game3.asset_stream').register(M)
return M
