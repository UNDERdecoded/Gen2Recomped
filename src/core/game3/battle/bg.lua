-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- The background hook consumes only the native field pass, never its HUD.
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Scope=require('src.render.GraphicsScope')
local B={}
local function draw()return Boundary.invoke('battle.background')end
B.draw=draw
function B._nativeDraw(screen,body)
  if B.draw==draw then return body(screen)end
  if Boundary.active('battle.background')then return Boundary.invoke('battle.background')end
  local ok,result=Scope.call(function()
    return Boundary.dispatch('battle.background',function()return body(screen)end,function()
      local facade=require('src.core.Game3');local who=facade._callbackOwner()
      local seams=package.loaded['src.mods.ModSeams']
      for i=#(seams and seams._journal or{}),1,-1 do
        local change=seams._journal[i]
        if change.tbl==B and change.key=='draw'and change.after==B.draw then who=change.owner;break end
      end
      return facade._withCallbackOwner(who,B.draw,screen.gen3TerrainId or screen.terrainId,0,0,0)
    end)
  end)
  if not ok then error(result,0)end
  return result
end
return B
