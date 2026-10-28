-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Battle=require('src.core.game3.battle')
local Ball=require('src.core.game3.battle.ball_open')
local Native=require('src.battle.Gen3Battle')
local Timeline=require('src.battle.Gen3BallAnim')
local originalGame=package.loaded['src.core.Game']
local G=require('src.core.Game3');local base=Ball.draw
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition);local game=f.game
 package.loaded['src.core.Game']=game
 local c=game.data.constants;c.itemOrder={[4]='BALL_KEY'};game.data.items.BALL_KEY={index=4}
 c.gen3BallAnim={timing={},balls={[4]={colour={255,66,0}}},itemToBall={[4]=3}}
 T.eq(Ball.ballIdForItem(4),3);T.eq(Ball.ballIdForItem('BALL_KEY'),3)
 T.eq(Ball.ballIdForItem(9),nil,'unknown cartridge items cannot choose a guessed ball')
 T.eq(base(),false,'a source painter cannot invent a battle')
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b)
 local anim=Timeline.new(game.data,{ball=3,battler=b.player,sendOut='player'})
 b.gen3Ball=anim;b.gen3BallPlaying=true;anim.monBlend=.5
 local t,r,g,blue=Ball.monBlend('player');T.eq(t,8);T.eq(r,31);T.eq(g,66*31/255);T.eq(blue,0)
 T.eq(Ball.monBlend(1),0,'the native send-out never tints the other actor')
 local frame,ballFrame=b.frame,anim.frame
 for i=1,8 do Ball.monBlend(0);Ball.bgCoeff()end
 T.eq(b.frame,frame);T.eq(anim.frame,ballFrame,'observation cannot advance the native ball clock')
 T.eq(Ball.bgCoeff(),0)
 local move=require('src.battle.Gen3MoveAnim')
 b.gen3Anim=setmetatable({whiteout={at=0},frame=0},{__index=move});b.gen3AnimPlaying=true
 T.eq(Ball.bgCoeff(),16,'background coefficient reads the existing native flash timeline')
 b.gen3Anim.frame=10;local white=b.gen3Anim:flashState();T.eq(Ball.bgCoeff(),white*16)
 b.gen3AnimPlaying=false;T.eq(Ball.bgCoeff(),0)
 local calls,wrappers=0,0
 Ball.draw=function()wrappers=wrappers+1;base();base();return false,nil,'native ball result'end
 local a,middle,z=Ball._nativeDraw(b,function(owner)T.eq(owner,b);calls=calls+1;return true end)
 T.eq(calls,1);T.eq(wrappers,1);T.eq(a,false);T.eq(middle,nil);T.eq(z,'native ball result')
 T.eq(anim.frame,ballFrame);T.eq(b.frame,frame)
 local depth=love.graphics.getStackDepth and love.graphics.getStackDepth()
 Ball.draw=function()love.graphics.push();error('ball source error')end
 T.raises(function()Ball._nativeDraw(b,function()end)end,'ball source error')
 if depth then T.eq(love.graphics.getStackDepth(),depth)end
 Ball.draw=function()local ok=pcall(base);T.eq(ok,false);return true end
 T.raises(function()Ball._nativeDraw(b,function()error('ball native error')end)end,'ball native error')
 local paints=0
 Ball.draw=function()game.stack:push({});local a,why=base();game.stack:pop();return a,why end
 local painted,why=Ball._nativeDraw(b,function()paints=paints+1 end)
 T.eq(painted,false);T.eq(why,'native ball presentation admission changed');T.eq(paints,0,'a new covering owner cannot consume the old resolved painter')
 local seams=require('src.mods.ModSeams');local previous=G._callbackOwner()
 Ball.draw=function()T.eq(G._callbackOwner(),'ball_owner');return base()end
 seams._journal[#seams._journal+1]={tbl=Ball,key='draw',after=Ball.draw,owner='ball_owner'}
 Ball._nativeDraw(b,function()return true end);T.eq(G._callbackOwner(),previous);table.remove(seams._journal)
 Ball.draw=base
 -- Exercise the real native dispatch, including ordinary callers retaining
 -- the actual painter when no source replacement is installed.
 anim.whiteout=1;anim.shinyStars=nil;anim.particles=nil;anim.stars=nil
 Native.drawBall(b);T.eq(anim.frame,ballFrame)
 b.gen3Ball=nil;T.eq(Ball.monBlend(0),0);b.gen3Anim=nil
 game.stack:pop();Battle._service.release();f.close();G.release();Ball._service.release()
end
local graphics=love.graphics;local before=graphics.getShader()
T.eq(Ball.setBlendShader(nil),false);T.eq(Ball.setBlendShader(0),false);T.eq(graphics.getShader(),before)
T.raises(function()Ball.setBlendShader(0/0,0,0,0)end,'invalid native palette blend coefficient')
T.raises(function()Ball.setBlendShader(1,math.huge,0,0)end,'invalid native palette blend color')
package.loaded['src.core.Game']=originalGame
T.finish('native ball timeline observations, once-only painter, callback scope and item identities')
