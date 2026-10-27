-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Mod-owned presentation players reuse the native procedural motions and
-- imported frame strips. They never tick a battler or consume a command.
local Session=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Motion=require('src.pokemon.MonAnim')
local Pictures=require('src.pokemon.PicAnim')
local Version=require('src.core.GameVersion')
local M={nativeMotion=true}
local records=setmetatable({},{__mode='k'})
local function owner()
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return host and host.currentMod or facade and facade._callbackOwner()
end
local function retire(c)
  c.game,c.data,c.loader,c.motion,c.pictures,c.ids=nil,nil,nil,nil,nil,nil;c.stopped=true
end
local function valid(c)
  if not c or c.stopped then return false end
  if Session.game()~=c.game or c.game.data~=c.data or c.game.mods~=c.loader or Version.get()~=c.edition or not c.ids:valid()then retire(c);return false end
  return true
end
function M.enabled()
  local game=Session.game();local record=game and game.data and game.data.constants and game.data.constants.gen3MonAnim
  return type(record)=='table'and type(record.anims)=='table'and next(record.anims)~=nil or false
end
function M.newSprite(species)
  local game=Session.game();if not(game and game.data)then return nil,'no native Pokemon data'end
  local ids=Ids.new(game.data);local key=ids:native('pokemon',species)
  if not key then return nil,'unknown cartridge species'end
  local sprite={frames=0}
  records[sprite]={game=game,data=game.data,loader=game.mods,edition=Version.get(),key=key,owner=owner(),ids=ids}
  return sprite
end
function M.summary(sprite,species,oneFrame)
  local c=records[sprite];if not valid(c)then return nil,'native presentation player retired'end
  if species~=nil and Ids.new(c.data):native('pokemon',species)~=c.key then return nil,'presentation species changed'end
  c.motion=Motion.new(c.data,c.key)
  if c.motion then c.motion:restart()end
  c.pictures=not oneFrame and Pictures.new(c.data,c.key)or nil
  if c.pictures then c.pictures:start()end
  sprite.frames=0;return sprite
end
function M.step(sprite)
  local c=records[sprite];if not valid(c)then return false,'native presentation player retired'end
  if c.motion then c.motion:update(1/60)end
  if c.pictures then c.pictures:update(1/60)end
  sprite.frames=sprite.frames+1;return true
end
function M.done(sprite)
  local c=records[sprite]
  return not valid(c)or(not c.motion or not c.motion:active())
    and(not c.pictures or c.pictures.paused or c.pictures.steps==nil)
end
function M.busy(sprite)return not M.done(sprite)end
function M.stop(sprite)local c=records[sprite];if c then retire(c)end end
function M.transform(sprite)
  local c=records[sprite];local t=valid(c)and c.motion and c.motion:transform()or Motion.IDENTITY
  local tint=t.tint;local color,coeff=0,0
  if tint then
    color=math.floor(tint[1]*31+.5)+math.floor(tint[2]*31+.5)*32+math.floor(tint[3]*31+.5)*1024
    coeff=(tint[4]or 0)*16
  end
  return{x2=t.dx,y2=t.dy,sx=t.sx,sy=t.sy,rotation=t.rot,alpha=t.alpha,
    invisible=t.alpha==0,frame=valid(c)and c.pictures and c.pictures:frame()or 0,
    blendColor=color,blendCoeff=coeff}
end
function M.framePic(species,frame,shiny)
  if type(frame)~='number'or frame%1~=0 or frame<=0 then return nil end
  local game=Session.game();if not(game and game.data)then return nil end
  local key=Ids.new(game.data):native('pokemon',species);if not key then return nil end
  local mon={species=key,isShiny=shiny==true}
  local record=Pictures.record(game.data,key,mon)
  if shiny and record and not record.shinySheet then return nil,'native shiny frame strip unavailable'end
  -- Borrow the native frame cache. Only its native owner may retire it.
  local image=Pictures.frameImage(record,frame,mon)
  if not image then return nil end
  local w,h=image:getDimensions();return{image=image,w=w,h=h}
end
local service={release=function()for _,c in pairs(records)do retire(c)end end,
  poll=function()for _,c in pairs(records)do valid(c)end end,
  releaseOwner=function(_,who)for _,c in pairs(records)do if c.owner==who then retire(c)end end end}
M._service=service
require('src.core.game3.asset_stream').register(service)
return M
