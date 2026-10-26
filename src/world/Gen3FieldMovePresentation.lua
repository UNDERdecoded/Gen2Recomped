-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- An optional cartridge presentation on the native field-move state. The
-- StateStack owns its updates; rendering never advances these observations.
local Art=require('src.import.Gen3FieldMoveArt')
local M={}
local OUTDOORS={TOWN=true,CITY=true,ROUTE=true,UNDERWATER=true,OCEAN_ROUTE=true,[1]=true,[2]=true,[3]=true,[5]=true,[6]=true}
function M.outdoors(game,world)
  world=world or game.overworld
  local map=world and world.map
  return OUTDOORS[map and map.def and map.def.mapType]==true
end
function M.new(mon,opts,game,world)
  return{species=mon.species,personality=mon.personality,noDuck=opts.noDuck==true,
    outdoors=M.outdoors(game,world),phase=opts.pose and'pose'or 1,posed=opts.pose==true,
    poseWait=24,hofs=0,winL=240,winT=80,winB=81,revealed=0,cleared=0}
end
function M.advance(fx,cry)
  if fx.phase=='pose'then
    fx.poseWait=fx.poseWait-1
    if fx.poseWait>0 then return false end
    fx.phase=1
  end
  local phase=fx.phase
  if phase<3 then fx.phase=phase+1
  elseif phase==7 then return true
  else
    -- Every active band phase scrolls except the outdoor hide frame.
    if not(fx.outdoors and phase==6)then fx.hofs=fx.hofs-16 end
    if phase==3 then
      local ready
      if fx.outdoors then
        fx.winL=math.max(0,fx.winL-16);fx.winT=math.max(40,fx.winT-2);fx.winB=math.min(120,fx.winB+2)
        ready=fx.winL==0 and fx.winT==40 and fx.winB==120
      else
        ready=fx.revealed>=16
        if not ready then fx.revealed=fx.revealed+1 end
      end
      if ready then fx.sprite={x=320,y=80,state='on'};fx.phase=4 end
    elseif phase==4 then
      if fx.sprite and fx.sprite.done then fx.phase=5 end
    elseif phase==5 then
      if fx.outdoors then
        fx.winT=math.min(80,fx.winT+6);fx.winB=math.max(81,fx.winB-6)
        if fx.winT==80 and fx.winB==81 then fx.phase=6 end
      else fx.phase=6 end
    elseif phase==6 then
      if fx.outdoors then fx.hidden=true;fx.phase=7
      elseif fx.cleared>=16 then fx.phase=7 else fx.cleared=fx.cleared+1 end
    end
  end
  local s=fx.sprite
  if s and not s.done then
    if s.state=='on'then
      s.x=s.x-20
      if s.x<=120 then s.x=120;s.wait=30;s.state='wait';if cry then cry()end end
    elseif s.state=='wait'then s.wait=s.wait-1;if s.wait==0 then s.state='off'end
    elseif s.x < -64 then s.done=true else s.x=s.x-20 end
  end
  return false
end
function M.rgba(game,kind)
  local facade=package.loaded['src.core.game3.field_effects']
  local cache=require('src.compat.gen1.NativeSession').game()==game and facade and facade._cache
  if cache then
    local extract=package.loaded['src.import.gba.extract_island1']
    local path=((extract and extract.CACHE_ROOT)or'data/generated/gba')..'/field_effects/field_move_streaks_'..kind..'.rgba'
    local bytes=cache:read(path)
    if bytes~=nil then assert(type(bytes)=='string'and#bytes==256*80*4,'invalid field move streak payload');return bytes end
    return nil,'installed field move streak artwork is unavailable'
  end
  local record=game.data.constants and game.data.constants.gen3FieldMovePresentation
  local Version=require('src.core.GameVersion');local edition=Version.get()
  if not(record and record.schema==Art.SCHEMA and record.edition==edition
      and Version.acceptsSha1(edition,record.romSha1)and record.strips and record.strips[kind])then
    return nil,'native field move artwork requires a current import'
  end
  return Art.rgba(record.strips[kind])
end
function M.draw(fx,resources,front)
  if fx.phase=='pose'then return end
  local g=love.graphics;g.setColor(1,1,1,1)
  local x0,x1,y0,y1
  if fx.outdoors then
    if not fx.hidden and fx.phase>=3 then x0,x1,y0,y1=fx.winL,240,math.max(fx.winT,40),math.min(fx.winB,120)end
  elseif fx.phase>=3 and fx.phase<=5 then
    local revealing=fx.phase==3 and fx.revealed<16
    x0,x1,y0,y1=revealing and 16 or 0,revealing and math.min(240,16*(fx.revealed+1))or 240,40,120
  elseif fx.phase==6 then x0,x1,y0,y1=math.min(240,16*fx.cleared),240,40,120 end
  if x0 and x1>x0 and y1>y0 then
    local x=x0
    while x<x1 do
      local u=(x+fx.hofs)%256;local width=math.min(x1-x,256-u)
      resources.quad:setViewport(u,y0-40,width,y1-y0,256,80)
      g.draw(resources.band,resources.quad,x,y0);x=x+width
    end
  end
  local s=fx.sprite
  if s and not s.done then
    local w,h=front:getDimensions();g.draw(front,math.floor(s.x-w/2),math.floor(s.y-h/2))
  end
end
return M
