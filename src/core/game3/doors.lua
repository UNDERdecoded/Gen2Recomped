-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observe the native Petalburg slide and paint its actual resident metatiles.
-- Cartridge metadata is read-only; mod-started door tasks are separate APIs.
local Native=require('src.compat.gen1.NativeSession')
local Identity=require('src.compat.gen1.MapIdentity')
local Version=require('src.core.GameVersion')
local Scope=require('src.render.GraphicsScope')
local M={}
local function copy(value)
 if type(value)~='table'then return value end
 local out={};for k,v in pairs(value)do out[k]=copy(v)end;return out
end
local cohort=setmetatable({},{__mode='v'})
local doorCollision
local function manifest(game)
 local data=game and game.data;local constants=data and data.constants
 local facts=constants and constants.gen3DoorMetadata
 local edition=Version.get()
 if not(type(facts)=='table'and facts.schema==1 and facts.edition==edition and Version.acceptsSha1(edition,facts.romSha1)
  and type(facts.by_mid)=='table'and type(facts.doors)=='table')then
  M._manifest=nil;cohort=setmetatable({},{__mode='v'});return
 end
 if not M._manifest or cohort[1]~=game or cohort[2]~=data or cohort[3]~=facts or cohort[4]~=game.save or cohort[5]~=game.mods then
  M._manifest=copy(facts);cohort=setmetatable({game,data,facts,game.save,game.mods},{__mode='v'})
 end
 return facts
end
function M.getDoorEntryAt(mapId,x,y)
 local game=Native.resolve();local facts=manifest(game);if not facts then return nil,'native door metadata unavailable'end
 if type(x)~='number'or type(y)~='number'or x~=x or y~=y or x%1~=0 or y%1~=0 then return nil end
 local maps=require('src.core.game3.map')._context(game);if not maps then return nil end
 local def=maps:definition(mapId);if not def then return nil end
 local layout=maps:layout(def.id,def)
 if not layout or x<0 or y<0 or x>=def.width or y>=def.height then return nil end
 doorCollision=doorCollision or require('src.compat.gen1.CollisionRuntime').new()
 local behavior=doorCollision:behaviorMid(def,layout:midAt(x,y),game)
 local MB=require('src.compat.gen1.MetatileBehavior')
 if behavior~=MB.require('WARP_DOOR')and not(facts.family=='rse'and behavior==MB.require('PETALBURG_GYM_DOOR'))then return nil end
 local row=facts.by_mid[layout:midAt(x,y)]
 if row then return copy(row),copy(facts.doors[row.tile])end
end
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
