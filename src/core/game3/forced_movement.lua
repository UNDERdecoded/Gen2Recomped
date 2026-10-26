-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Classify the existing semantic terrain IDs. Native controllers retain
-- all forced steps, collision, facing, sound and script continuations.
local Version=require('src.core.GameVersion')
local MB=require('src.compat.gen1.MetatileBehavior')
local common={}
for name in ('WALK_EAST WALK_WEST WALK_NORTH WALK_SOUTH SLIDE_EAST SLIDE_WEST SLIDE_NORTH SLIDE_SOUTH TRICK_HOUSE_PUZZLE_8_FLOOR EASTWARD_CURRENT WESTWARD_CURRENT NORTHWARD_CURRENT SOUTHWARD_CURRENT WATERFALL ICE'):gmatch('%S+')do
 common[MB.require(name)]=true
end
local rse,frlg={},{}
for key in pairs(common)do rse[key],frlg[key]=true,true end
for name in ('MUDDY_SLOPE CRACKED_FLOOR SECRET_BASE_JUMP_MAT SECRET_BASE_SPIN_MAT'):gmatch('%S+')do rse[MB.require(name)]=true end
for name in ('SPIN_RIGHT SPIN_LEFT SPIN_UP SPIN_DOWN'):gmatch('%S+')do frlg[MB.require(name)]=true end
local M={}
function M.isRse()
 local edition=Version.get();return edition=='emerald'or edition=='ruby'or edition=='sapphire'
end
function M.isForcedMovementTile(behavior)
 if type(behavior)~='number'or behavior%1~=0 then return false end
 local set=M.isRse()and rse or Version.isFRLG()and frlg
 return set and set[behavior]==true or false
end
return M
