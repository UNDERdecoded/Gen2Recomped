-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native arrivals synchronously hand control to their script, warp or screen.
-- Observe that owner; do not queue, advance or flush a second step pipeline.
local Native=require('src.compat.gen1.NativeSession')
local M={}
function M.busy()
 local game,world,player=Native.resolve()
 return game~=nil and not Native.acceptsInput(game,world,player)or false
end
return M
