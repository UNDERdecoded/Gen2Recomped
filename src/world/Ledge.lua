-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- Native classification extracted from OverworldController; original notices retained.

-- Shared native ledge approach classification. No movement or collision hooks.
-- Existing dataset overrides win, including the later-edition jump distances.
local M={}
local directions={north='up',south='down',west='left',east='right',
  up='up',down='down',left='left',right='right'}
local gba={[0x38]='right',[0x39]='left',[0x3a]='up',[0x3b]='down',
  [0x3c]='up',[0x3d]='up',[0x3e]='down',[0x3f]='down'}
local bw={[0x72]='right',[0x73]='left',[0x74]='up',[0x75]='down'}
function M.approach(map,data,x,y,dir)
  local delta=require('src.world.Collision').DELTA[dir]
  if not(map and delta)then return true end
  local fx,fy=x+delta[1],y+delta[2]
  if not map:inBounds(fx,fy)then return true end
  local ts=map.tileset
  local rules=ts and ts.ledgeBehaviours or data and data.field and data.field.ledgeBehaviours
  if map.def and map.def.gen5 then rules=bw end
  if not rules and ts and tonumber(ts.blockTiles)==2 and tonumber(ts.blockCells)==1 and ts.collision then
    rules=gba
  end
  if not rules then return false end -- older pair/standing-cell rules remain native
  local behavior=map:cellBehaviour(fx,fy)
  if behavior and directions[rules[behavior]]==dir then
    if map.def and map.def.generation==4 and behavior>=0x5a and behavior<=0x5d then
      return true,fx,fy,3,true
    end
    return true,fx,fy
  end
  return true
end
return M
