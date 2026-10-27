-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observe and dismiss the actual native dungeon preview. No parallel timer
-- or preview flags are kept by compatibility consumers.
local Native=require('src.compat.gen1.NativeSession')
local Preview=require('src.world.Gen3MapPreviewFRLG')
local M={}
local function current()
 local game=Native.game();local stack=game and game.stack
 for i=#(stack and stack.states or{}),1,-1 do
  local state=stack.states[i]
  if getmetatable(state)==Preview and state.game==game then return state,game,stack end
 end
end
function M.isActive()return current()~=nil end
function M.dismiss()
 local state,game,stack=current()
 if not state then return false,'no native map preview'end
 if stack:top()~=state then return false,'native map preview is covered'end
 local done=state.onDone;state.onDone=nil
 stack:pop()
 if done then done()end
 return true
end
M.reset=M.dismiss
return M
