-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native healing keeps its task, sound and continuation; these are sprite reads.
local Native=require('src.compat.gen1.NativeSession')
local Presentation=require('src.world.Gen3HealingPresentation')
local M={}
function M.isActive()local _,world=Native.resolve();return world~=nil and world.healAnim~=nil end
function M.spriteSnapshot()
 local game,world,player=Native.resolve()
 if not(game and world.healAnim)then return{}end
 local sprites=Presentation.snapshot(game,world,world.healAnim)or{}
 -- The published source snapshot is anchored at the native 240x160 player's
 -- (112,72), independently of the window or a source supersampling texture.
 for _,sprite in ipairs(sprites)do sprite.x=sprite.x-player.px+112;sprite.y=sprite.y-player.py+72 end
 return sprites
end
return M
