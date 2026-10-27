-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
local root=assert(os.getenv('NATIVE_BALL_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local g=love.graphics
local checks=0
local function check(ok,why)checks=checks+1;assert(ok,why)end
function love.load()
 check(love.filesystem.getIdentity():match('^oasc%-gen2recomp%-qa%-'),'owned QA identity')
 local renderer=g.getRendererInfo()
 check(renderer:lower():find(assert(os.getenv('POKEPORT_GRAPHICS_BACKEND')),1,true),'actual requested backend')
 local Tasks=require('src.core.game3.battle.anim_tasks');local draw=Tasks.draw
 local f=require('tools.battle-source-runtime.fixture').new('firered');local game=f.game
 package.loaded['src.core.Game']=game;game.data.constants.gen3BattleAnimGfx={}
 local desc=assert(require('src.import.Gen3VisualTaskFacts').fromTask('surf',
  {fn=0x1001,priority=2,args={0},at=3,order=1}))
 local shape={at=3,life=134,waitLife=136,fade=13,hold=54,step=2,blendOf=16,width=16,height=8,
  player={image='owned test wave',x=5,y=3,dx=-2,dy=1},
  opponent={image='owned test wave',x=-5,y=7,dx=2,dy=-1},
  scanline={player={top=48,bottom=112,topStep=-1,limit=112},
   opponent={top=0,bottom=0,bottomStep=1,limit=112}},visualTask=desc}
 game.data.moves.MOVE_033.anim={surf=shape}
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b)
 local player=b.gen3Anim;local GB=require('src.battle.Gen3Battle')
 local pixels=love.image.newImageData(16,8)
 for y=0,7 do for x=0,15 do pixels:setPixel(x,y,(x%5)/4,(y%3)/2,((x+y)%7)/6,(x+y)%5==0 and 0 or 1)end end
 local image=g.newImage(pixels);image:setFilter('nearest','nearest')
 local assets={image=function(key)check(key=='owned test wave','native wave image identity');return image end}
 local shader=g.newShader('vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){return Texel(t,uv)*c;}')
 local selected={[4]=true,[16]=true,[60]=true,[110]=true,[135]=true,[138]=true,[142]=true}
 for _,dpi in ipairs{1,2}do
  local target=g.newCanvas(240,160,{format='rgba8',dpiscale=dpi,msaa=0})
  for _,side in ipairs{true,false}do
   Tasks.draw=draw;check(player:start('MOVE_033',side,side and 0 or 1,side and 1 or 0,nil,b),'native wave start')
   for frame=1,142 do
    player:update()
    if selected[frame]then
     local function render(mode)
      Tasks.draw=draw
      g.setCanvas(target);g.origin();g.setScissor();g.setShader();g.setColor(1,1,1,1)
      g.setBlendMode('alpha','alphamultiply');g.clear(.2,.3,.4,1)
      g.setShader(shader);g.setScissor(2,1,236,110)
      local clock,script,depth=b.frame,player.frame,g.getStackDepth()
      if mode=='base'then player:drawSurfNative(b,GB,assets)
      else
       if mode=='wrapped'or mode=='shifted'then
        Tasks.draw=function(vm)
         local pool=Tasks._pool;local task=pool and pool[1];local original=task and task.draw
         if mode=='shifted'then g.translate(1,0)end
         if task then task.draw=function(t,view)original(t,view);return original(t,view)end end
         draw(vm);draw(vm)
         if task then task.draw=original end
        end
       end
       Tasks._nativeDraw(player,b,player.drawSurfNative,GB,assets)
      end
      check(b.frame==clock and player.frame==script,'painting has no native clock')
      check(g.getCanvas()==target and g.getShader()==shader and g.getStackDepth()==depth,'borrowed target/shader/stack retained')
      g.setCanvas();g.setShader();g.setScissor()
      local readback=g.readbackTexture(target);local bytes=readback:getString();readback:release()
      return bytes
     end
     local base=render('base')
     check(render('present')==base,('default task surface dpi%d side%s frame%d'):format(dpi,tostring(side),frame))
     check(render('wrapped')==base,('wrapped task surface dpi%d side%s frame%d'):format(dpi,tostring(side),frame))
     if frame==60 then check(render('shifted')~=base,'positive control detects a displaced task surface')end
    end
   end
  end
  -- Failure after switching to another DPI must preserve the caller's
  -- physical scissor, not merely the logical tuple reported by the API.
  Tasks.draw=draw;player:start('MOVE_033',true,0,1,nil,b);for _=1,4 do player:update()end
  local foreign=g.newCanvas(8,4,{format='rgba8',dpiscale=1,msaa=0})
  g.setCanvas(target);g.origin();g.setScissor();g.setShader();g.clear(.2,.3,.4,1)
  g.setScissor(2,1,236,110);g.setShader(shader)
  local depth=g.getStackDepth()
  Tasks.draw=function()g.push('all');g.setCanvas(foreign);g.setScissor(1,1,2,2);error('intentional task target failure')end
  local ok,why=pcall(Tasks._nativeDraw,player,b,player.drawSurfNative,GB,assets)
  check(not ok and tostring(why):find('intentional task target failure',1,true),'task callback error retained')
  check(g.getCanvas()==target and g.getShader()==shader and g.getStackDepth()==depth,'error restores borrowed state')
  g.setShader();g.setColor(1,0,1,1);g.rectangle('fill',0,0,240,160)
  g.setCanvas();g.setScissor()
  local readback=g.readbackTexture(target)
  for _,point in ipairs{{0,0},{1,1},{3,2},{4,2},{6,4},{237*dpi,110*dpi},{239*dpi,112*dpi}}do
   local x,y=point[1],point[2];local r,green,blue=readback:getPixel(x,y)
   local inside=x>=2*dpi and x<238*dpi and y>=dpi and y<111*dpi
   local expected=inside and 1 or .2
   check(math.abs(r-expected)<=1.01/255,
    ('physical clip after task error dpi%d x%d y%d got%.5f expected%.5f'):format(dpi,x,y,r,expected))
  end
  readback:release();foreign:release();target:release()
 end
 Tasks.draw=draw;game.stack:pop();Tasks._service.release();f.close();require('src.core.Game3').release()
 g.setCanvas();g.setShader();g.setScissor();shader:release();image:release();pixels:release()
 print('NATIVE_ANIMATION_TASKS_GPU_OK',renderer,checks);love.event.quit(0)
end
