-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Native=require('src.battle.Gen3Battle')
local Opening=require('src.core.game3.battle.ball_open')
local Ui=require('src.core.game3.battle.ui')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Assets=require('src.render.Assets')
local Ball=require('src.battle.Gen3BallAnim')
local Copy=require('src.mods.Merge').deepCopy
local originalGame=package.loaded['src.core.Game']
local originalApi,originalImage=Ui.presentation,Assets.image
local g=love.graphics;local saved={}
for _,name in ipairs{'push','pop','getStackDepth','translate','scale','draw','rectangle'}do saved[name]=g[name]end
local state,stack,calls
local function fresh()state={x=0,y=0,sx=1,sy=1};stack={};calls={}end
g.push=function()stack[#stack+1]=Copy(state)end
g.pop=function()state=assert(table.remove(stack))end
g.getStackDepth=function()return #stack end
g.translate=function(x,y)state.x=state.x+x*state.sx;state.y=state.y+y*state.sy end
g.scale=function(x,y)state.sx=state.sx*x;state.sy=state.sy*(y or x)end
local function record(kind,path,x,y,w,h)
 calls[#calls+1]={kind=kind,path=path,x=state.x+x*state.sx,y=state.y+y*state.sy,w=w*state.sx,h=h*state.sy}
end
g.draw=function(image,q,x,y)record('image',image.path,x,y,q.w,q.h)end
g.rectangle=function(kind,x,y,w,h)record(kind,false,x,y,w,h)end
Assets.image=function(path)return{path=path,getDimensions=function()return 48,192 end}end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 package.loaded['src.core.Game']=f.game
 local b=f.fresh('TACKLE').battle;b.enter=false;f.game.stack:push(b)
 f.game.data.constants.gen3BallAnim={size=16,frames=3,particleFrames=8,balls={},timing={},
  images={balls='owned-ball',particles='owned-particles'}}
 for _,kind in ipairs{'player','opponent','capture'}do
  local a=Ball.new(f.game.data,{ball=0,battler=kind=='player'and b.player or b.enemy,
   sendOut=kind~='capture'and kind or nil})
  b.gen3Ball,b.gen3BallPlaying=a,true;a.x,a.y=52,71
  a.particles={age=2,life=12,radius=20,count=3,x=52,y=71}
  a.shinyStars={age=20,made=2};a.stars={age=12}
  local before,frame=Copy(a),b.frame
  fresh();Native.drawBallEffects(b);local baseline=Copy(calls)
  T.check(#baseline>3,'actual ring, shiny and capture star painters are exercised')
  local requested=0
  Ui.presentation={ballPosition=function(view)
   requested=requested+1;T.eq(view.battler,kind=='player'and 0 or 1)
   return 120,88,.5
  end}
  fresh();Opening.draw()
  if kind=='capture'then
   T.eq(requested,0,'capture providers retain their existing whole-pass transform')
   T.same(calls,baseline)
  else
   T.eq(requested,1,'one current source projection per effect pass')
   T.eq(#calls,#baseline,'projection neither duplicates nor drops native effects')
   for i,row in ipairs(baseline)do
    local fitted=calls[i]
    T.eq(fitted.kind,row.kind);T.eq(fitted.path,row.path)
    T.eq(fitted.x,120+(row.x-a.x)*.5);T.eq(fitted.y,88+(row.y-a.y)*.5)
    T.eq(fitted.w,row.w*.5);T.eq(fitted.h,row.h*.5)
   end
   T.same(state,{x=0,y=0,sx=1,sy=1},'opening transform cannot leak to the HUD')
   Ui.presentation.ballPosition=function()return -10000,-10000,0 end
   fresh();Opening.draw();T.eq(#calls,0,'suppressed source cell suppresses its native opening too')
   Ui.presentation.ballPosition=function()return nil end
   fresh();Opening.draw();T.same(calls,baseline,'an absent projection preserves native geometry')
   Ui.presentation.ballPosition=function()return 120,88,0/0 end
   fresh();T.raises(Opening.draw,'invalid opening projection','nonfinite source projection is rejected');T.eq(#calls,0);T.eq(#stack,0)
   Ui.presentation.ballPosition=function()g.translate(7,9);error('source projection failed')end
   fresh();T.raises(Opening.draw,'source projection failed','source projection failure is reported')
   T.same(state,{x=0,y=0,sx=1,sy=1});T.eq(#stack,0)
   Ui.presentation.ballPosition=function()b.gen3Ball=nil;return 120,88,.5 end
   fresh();local ok,why=Opening.draw();T.eq(ok,false);T.eq(why,'native opening presentation admission changed')
   T.eq(#calls,0);b.gen3Ball=a
  end
  Ui.presentation.ballPosition=function()error('whole native ball must not borrow a source projection')end
  fresh();Native.drawBall(b)
  local count=0;for _,row in ipairs(calls)do if row.path=='owned-ball'then count=count+1 end end
  T.eq(count,1,'native whole-layer boundary keeps its own complete painter')
  T.same(a,before,'fitting cannot alter or advance the native ball');T.eq(b.frame,frame)
  Ui.presentation=nil
 end
 b.gen3Ball=nil;f.game.stack:pop();Battle._service.release();f.close();G.release()
end
for name,fn in pairs(saved)do g[name]=fn end
Assets.image,Ui.presentation=originalImage,originalApi;package.loaded['src.core.Game']=originalGame
T.finish('native opening effects share the fitted send-out cell while capture, native painting and graphics ownership remain intact')
