-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Door observations belong to the native world. Missing native artwork is
-- reported explicitly; a presentation consumer cannot create door timing.
local Native=require('src.compat.gen1.NativeSession')
local Map=require('src.core.game3.map')
local D={}
local function context(id)
 local game,world=Native.resolve()
 if not game then return nil,'no native door owner'end
 local def=Map.currentDef()
 if id~=nil and(not def or def.id~=id)then return nil,'door map is not current'end
 return world,game
end
function D.getActiveAnim(id)
 local world=context(id)
 if not world then return nil end
 -- Only a producer attached to this native world can expose a live pose.
 local pose=world.gen3DoorAnimation
 return pose and not pose.done and pose or nil
end
function D.getDoorEntryAt(id,x,y)
 local world,game=context(id)
 if not world then return nil,game end
 local records=game.data.constants and game.data.constants.gen3Doors
 if not records then return nil,'native door artwork has not been imported'end
 local layout=Map.currentDef().midLayout
 local mid=layout and layout:midAt(x,y)
 return records.by_mid and records.by_mid[mid]
end
function D.open(id,x,y,opts,done)
 local world,why=context(id)
 if not world then return false,why end
 if type(world.openDoorAt)~='function'then return false,'native door animation unavailable'end
 return world:openDoorAt(x,y,opts,done)
end
function D.draw(x,y)
 local world=context();local pose=world and world.gen3DoorAnimation
 if not(pose and not pose.done and type(pose.draw)=='function')then return false,'no active native door artwork'end
 return pose:draw(x,y)
end
return setmetatable(D,{__index=function(_,key)
 local _,game=context()
 if type(game)~='table'then return nil end
 if key=='_manifest'then return game.data.constants and game.data.constants.gen3Doors end
 if key=='SOUND_SLIDING'then return require('src.core.game3.se_ids').resolve('SE_DOOR')end
end})
