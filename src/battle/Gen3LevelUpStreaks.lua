-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Pure samples of the native 18-sprite sequence, driven by BattleState.frame.
-- No RNG, timer, GPU object, battle or save is retained here.
-- Interface/timing facts: pinned pret/pokefirered pokemon_special_anim_scene.c
-- and random.h (ce6406d8). Integer low bits avoid floating LCG overflow.
local M={}
local finish=0
for index=1,18 do
 local speed=(45*index+51)%64+32
 finish=math.max(finish,2*(index-1)+math.floor(1024/speed)+1)
end
function M.busy(frame)return frame<finish end
function M.queue(battle,user)
 if not require('src.core.GameVersion').isGen3()or not battle.data.constants.gen3LevelUpStreaks then return false end
 battle.nextInsert=(battle.nextInsert or 0)+1
 table.insert(battle.queue,battle.nextInsert,{gbaLevelUpStreaks=true,position=user.position,
  isPlayer=user.isPlayer})
 return true
end
function M.start(battle,row)
 if not require('src.core.GameVersion').isGen3()then return false end
 local user=row.position~=nil and battle:battlerAt(row.position)
  or(row.isPlayer and battle.player or battle.enemy)
 local hidden=battle.picFx and user and battle.picFx[user]and battle.picFx[user].hidden
 if not(user and user.mon and user.mon.hp>0 and not user.fainted and not hidden
  and battle.data.constants.gen3LevelUpStreaks)then return false end
 battle._levelUpStreaks={user=user,startFrame=battle.frame}
 local options=battle.game and battle.game.save and battle.game.save.options or{}
 require('src.core.Sound').playSe(battle.data,'SE_RS_SHOP',{mono=options.stereo==false})
 return true
end
function M.update(battle)
 local state=battle._levelUpStreaks
 if not state then return false end
 if M.busy(battle.frame-state.startFrame)then return true end
 battle._levelUpStreaks=nil
 return false
end
function M.sample(frame,visit)
 assert(type(frame)=='number'and frame==frame and frame>=0 and frame%1==0,'invalid native streak frame')
 assert(type(visit)=='function','native streak visitor must be callable')
 local alive=0
 -- Reverse OAM order: the first-created sprite remains in front of siblings.
 for index=18,1,-1 do
  local age=frame-2*(index-1)
  if age>=0 then
   local speed=(45*index+51)%64+32
   local y=math.floor(-speed*age/16)
   if y>=-64 then
    alive=alive+1;visit((index*219)%64-32,32+y,index,speed)
   end
  end
 end
 return alive>0 or frame<34,alive
end
function M.release(battle)
 if battle._levelUpBlend then battle._levelUpBlend:release();battle._levelUpBlend=nil end
 battle._levelUpStreaks=nil
end
function M.draw(battle)
 local state=battle._levelUpStreaks
 if not state then return false end
 local record=battle.data.constants.gen3LevelUpStreaks
 if not record then return false,'native vertical-streak resource unavailable'end
 local x,y=require('src.battle.Gen3Battle').battlerCentre(battle,state.user)
 if not x then return false,'native vertical-streak battler has no drawn sprite'end
 local image=require('src.render.Assets').image(record.image)
 local blend=battle._levelUpBlend
 if not blend then blend=require('src.render.NativeGbaAlpha').new();battle._levelUpBlend=blend end
 local ok,why=blend:paint(12,6,function()
  M.sample(battle.frame-state.startFrame,function(dx,dy)
   love.graphics.draw(image,x+dx,y+dy,0,1,1,4,8)
  end)
 end)
 if not ok then error(why,0)end
 return true
end
return M
