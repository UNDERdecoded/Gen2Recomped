-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Borrow native opening effects; source renderers paint their own ball cell.
-- A base call inside the native whole-layer boundary still borrows that layer.
local Battle=require('src.core.game3.battle')
local Coords=require('src.core.game3.battle.anim_coords')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local Scope=require('src.render.GraphicsScope')
local M={}
local shader,users
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function release()
 if shader then shader:release();shader=nil end
 users={}
end
release()
function M.ballIdForItem(value)
 local game=require('src.compat.gen1.NativeSession').game()
 if not(game and game.data)then return nil end
 local data=game.data
 local key=require('src.compat.gen1.BattleIds').new(data):native('items',value)
 local item=key and data.items[key]
 local record=require('src.battle.Gen3BallAnim').record(data)
 return item and record and record.itemToBall and record.itemToBall[item.index]or nil
end
function M.monBlend(side)
 local screen=Battle._screen();local id=Coords.idOf(side)
 local battler=screen and id and(id==0 and screen.player or id==1 and screen.enemy or screen:battlerAt(id))
 local anim=battler and screen:gen3BallFor(battler)
 if not anim then return 0 end
 local color=anim:colour()
 return (anim.monBlend or 0)*16,color[1]*31/255,color[2]*31/255,color[3]*31/255
end
function M.bgCoeff()
 local screen=Battle._screen()
 local anim=screen and screen.gen3AnimPlaying and screen.gen3Anim
 if anim and anim.flashState then return (anim:flashState()or 0)*16 end
 return 0
end
function M.setBlendShader(coeff,r,g,b)
 if coeff==nil then return false end
 assert(finite(coeff),'invalid native palette blend coefficient')
 if coeff<=0 then return false end
 assert(finite(r)and finite(g)and finite(b),'invalid native palette blend color')
 if not shader then
  shader=love.graphics.newShader([[
extern vec4 nativePaletteBlend;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
 vec4 pixel=Texel(tex,uv);
 vec3 source=floor(clamp(pixel.rgb,0.0,1.0)*31.0+0.5);
 vec3 mixed=source+floor((nativePaletteBlend.rgb-source)*nativePaletteBlend.a/16.0);
 return vec4(mixed/31.0,pixel.a)*color;
}
]])
 end
 local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
 local owner=host and host.currentMod or facade and facade._callbackOwner()or'engine'
 users[owner]=true
 local function channel(v)return math.max(0,math.min(31,math.floor(v+.5)))end
 shader:send('nativePaletteBlend',{channel(r),channel(g),channel(b),math.max(0,math.min(16,coeff))})
 love.graphics.setShader(shader)
 return true
end
local function draw()
 if Boundary.active('battle.ball.draw')then return Boundary.invoke('battle.ball.draw')end
 local screen=Battle._screen();if not screen then return false,'no admitted native battle'end
 return require('src.battle.Gen3Battle').drawBallEffects(screen)
end
M.draw=draw
function M._nativeDraw(screen,body)
 if M.draw==draw then return body(screen)end
 if Battle._screen()~=screen then return body(screen)end
 if Boundary.active('battle.ball.draw')then return Boundary.invoke('battle.ball.draw')end
 local stack=screen.game.stack;local top=stack:top()
 local result=pack(Scope.call(function()
  return Boundary.dispatch('battle.ball.draw',function()
   if Battle._screen()~=screen or screen.game.stack~=stack or stack:top()~=top then
    return false,'native ball presentation admission changed'
   end
   return body(screen)
  end,function()return Call.call(M,'draw')end)
 end))
 if not result[1]then error(result[2],0)end
 return unpack(result,2,result.n)
end
M._service={release=release,releaseOwner=function(_,owner)
 users[owner]=nil;if not next(users)then release()end
end}
require('src.core.game3.asset_stream').register(M._service)
return M
