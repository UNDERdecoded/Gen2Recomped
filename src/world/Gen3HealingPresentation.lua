-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Native healing sprite selection extracted from OverworldController;
-- shared read-only projection by Roxas2712 (LICENSE-ROXAS2712.md).
local Assets=require('src.render.Assets')
local M={}
function M.snapshot(game,world,ha)
 if not require('src.core.GameVersion').isGen3()or not ha then return nil end
 local record=game.data.constants and game.data.constants.gen3HealMachine
 if not(record and record.monitor and record.glow)then return nil end
 world.gen3HealArt=world.gen3HealArt or{}
 local art=world.gen3HealArt
 local function picture(path)
  if art[path]==nil then
   local ok,img=pcall(Assets.image,path);art[path]=ok and img or false
  end
  return art[path]or nil
 end
 local out={}
 local frames=record.monitor.images or{}
 local frame=frames[ha.visible==false and 2 or 1]or frames[1]
 local monitor=frame and picture(frame)
 if monitor then out[#out+1]={kind='monitor',image=monitor,x=ha.px+record.monitor.x,y=ha.py+record.monitor.y}end
 local glow=record.glow.image and picture(record.glow.image)
 if glow then
  -- Keep the native cartridge offsets, scale and colour, in native order.
  for i=1,math.min(ha.lit or 0,#(record.glow.offsets or{}))do
   local at=record.glow.offsets[i]
   out[#out+1]={kind='ball',image=glow,x=ha.px+record.glow.x+at[1],y=ha.py+record.glow.y+at[2]}
  end
 end
 return out
end
return M
