-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Borrow the native queue-owned effect. The source facade owns no timer,
-- artwork, battle state or renderer resources.
local Battle=require('src.core.game3.battle')
local Streaks=require('src.battle.Gen3LevelUpStreaks')
local Scope=require('src.render.GraphicsScope')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local M={}
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function draw(state)
 if Boundary.active('battle.levelup.draw')then return Boundary.invoke('battle.levelup.draw')end
 local screen=Battle._screen(state)
 if not screen then return false,'no admitted native battle'end
 return Streaks.draw(screen)
end
M.draw=draw
function M._nativeDraw(screen,body)
 if M.draw==draw or Battle._screen()~=screen then return body(screen)end
 if Boundary.active('battle.levelup.draw')then return Boundary.invoke('battle.levelup.draw')end
 local stack=screen.game.stack;local top=stack:top()
 local result=pack(Scope.call(function()
  return Boundary.dispatch('battle.levelup.draw',function()
   if Battle._screen()~=screen or screen.game.stack~=stack or stack:top()~=top then
    return false,'native level-up presentation admission changed'
   end
   return body(screen)
  end,function()return Call.call(M,'draw',Battle.getState())end)
 end))
 if not result[1]then error(result[2],0)end
 return unpack(result,2,result.n)
end
return M
