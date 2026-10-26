-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observe the native Petalburg slide and paint its actual resident metatiles.
-- General cartridge door sheets and mod-started door tasks are separate APIs.
local Native=require('src.compat.gen1.NativeSession')
local Identity=require('src.compat.gen1.MapIdentity')
local Version=require('src.core.GameVersion')
local Scope=require('src.render.GraphicsScope')
local M={}
local function current(mapId,x,y)
 local game,world=Native.resolve()
 local slide=world and world.gymDoorSlide
 if not(slide and slide.mapId==world.map.id)then return end
 local canonical=Identity.bind(game.data.maps,Version.get()):legacyId(slide.mapId)
 if not canonical or mapId~=nil and mapId~=canonical and mapId~=slide.mapId then return end
 local P=require('src.script.Gen3Commands').PETALBURG_DOORS
 for _,cell in ipairs(P.ROOMS[slide.room]or{})do
  if(x==nil or x==cell[1])and(y==nil or y==cell[2])then
   return{mapId=canonical,x=cell[1],y=cell[2],frame=math.max(0,math.min(4,slide.step-1))/2,
    nativeFrame=math.max(0,slide.step-1),kind='sliding',timer=slide.timer,opening=true},world
  end
 end
end
function M.getActiveAnim(mapId,x,y)local pose=current(mapId,x,y);return pose end
function M.isBusy()return current()~=nil end
function M.draw(camX,camY)
 local pose,world=current()
 local renderer=world and world.map.renderer
 if not(renderer and renderer.drawMapOnly and renderer.drawAbove)then return false end
 camX,camY=camX or 0,camY or 0
 local ok,why=Scope.call(function()
  local g=love.graphics
  if g.intersectScissor then g.intersectScissor(pose.x*16-camX,pose.y*16-camY,16,32)
  else g.setScissor(pose.x*16-camX,pose.y*16-camY,16,32)end
  renderer:drawMapOnly(camX,camY,64,32)
  renderer:drawAbove(camX,camY,64,32)
 end)
 if not ok then error(why,0)end
 return true
end
return M
