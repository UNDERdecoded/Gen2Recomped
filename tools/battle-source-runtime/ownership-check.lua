-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local S=require('src.core.game3.battle');local Ui=require('src.core.game3.battle.ui')
local Background=require('src.core.game3.battle.bg')
T.eq(package.loaded['src.core.Game'],nil);T.eq(S.isActive(),false)
local base={update=S.update,draw=S.draw,pump=Ui.pump,uiDraw=Ui.draw,bg=Background.draw}
local Gen3=require('src.battle.Gen3Battle');local originalDraw,originalField=Gen3.draw,Gen3.drawField
local Renderer=require('src.render.Renderer')
local G=require('src.core.Game3')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 S._service.release();local f=require('tools.battle-source-runtime.fixture').new(edition)
 local game=f.game;package.loaded['src.core.Game']=game
 local state=f.fresh('TACKLE').battle;state.enter=false;game.stack:push(state)
 state.phase='QA_IDLE';local ticks,draws,fields,sourceTicks=0,0,0,0
 state.tickFx=function()ticks=ticks+1;T.eq(G._callbackOwner(),nil)end
 Gen3.draw=function(screen)draws=draws+1;T.eq(G._callbackOwner(),nil);screen:drawBattleField()end
 Gen3.drawField=function()fields=fields+1;T.eq(G._callbackOwner(),nil)end
 local model=S.getState();T.eq(S.getState(),model)
 S.update=function(dt,view)
  sourceTicks=sourceTicks+1;T.eq(G.native(view),game)
  state:update(dt);base.update(dt,view);return base.update(dt,view)
 end
 state:update(1/60);T.eq(ticks,1);T.eq(sourceTicks,1)
 S.update=base.update
 local tick=state.tickFx;state.tickFx=function()error('native phase body failure')end
 S.update=function()pcall(base.update);return base.update()end
 T.raises(function()state:update(1/60)end,'native phase body failure')
 state.tickFx=tick;S.update=base.update;state:update(1/60);T.eq(ticks,2)
 local save=game.save
 S.update=function()game.save={};return base.update()end
 state:update(1/60);T.eq(ticks,2,'a changed save cancels the already queued native step')
 game.save=save;T.eq(S.isActive(),true)
 T.raises(function()model.player.mon.hp=1 end,'retired','restoring a prior save cannot revive a retired view')
 local overlay={}
 S.update=function()game.stack:push(overlay);return base.update()end
 state:update(1/60);T.eq(ticks,2);game.stack:pop();S.update=base.update
 Ui.pump=function()game.stack:push(overlay);return base.pump()end
 state:update(1/60);T.eq(ticks,2,'UI hooks must recheck the admission at the inner native body')
 game.stack:pop();Ui.pump=base.pump
 Ui.pump=function()game.save={};return base.pump()end
 state:update(1/60);T.eq(ticks,2,'UI hooks cannot retain a native step through save replacement')
 game.save=save;Ui.pump=base.pump
 local current=S.getState();local snap=require('src.compat.gen1.TableIteration').snapshot(current)
 T.eq(snap.player,current.player);T.eq(snap.player.mon,current.player.mon)
 local monSnap=require('src.compat.gen1.TableIteration').snapshot(current.player.mon)
 T.eq(monSnap.species,4);T.eq(monSnap.hp,state.player.mon.hp)
 monSnap.hp=1;T.neq(state.player.mon.hp,1)
 local P=require('src.core.game3.pokemon');local Motion=require('src.core.game3.mon_anim')
 T.eq(P.speciesFromName('CHARMANDER'),4)
 local moving=assert(Motion.newSprite(4))
 local order=game.data.constants.speciesOrder
 S.update=function()game.data.constants.speciesOrder={};return base.update()end
 state:update(1/60);T.eq(ticks,2,'replaced cartridge identity tables retire a pending native command')
 T.eq(Motion.step(moving),false,'a presentation player cannot retain a retired cartridge identity')
 game.data.pokemon.QA_SPARSE={index=277,name='QA_SPARSE'}
 game.data.constants.speciesOrder={[4]='CHARMANDER',[277]='QA_SPARSE'}
 T.eq(P.speciesFromName('QA_SPARSE'),277,'new Pokemon queries rebuild from the current cartridge order')
 game.data.constants.speciesOrder=order;game.data.pokemon.QA_SPARSE=nil;S.update=base.update
 T.eq(P.speciesFromName('CHARMANDER'),4)
 T.raises(function()current.player.mon.hp=1 end,'retired')
 Renderer.frameSerial=(Renderer.frameSerial or 0)+1
 T.eq(base.draw(game),true);T.eq(draws,1);T.eq(fields,1)
 state:draw();state:draw();T.eq(draws,1,'capturing a native frame suppresses its repeated screen pass')
 Renderer.frameSerial=Renderer.frameSerial+1;state:draw();T.eq(draws,2)
 Renderer.frameSerial=Renderer.frameSerial+1;T.eq(Ui.draw(),true);state:draw();T.eq(draws,3,'UI capture shares native frame ownership')
 Renderer.frameSerial=Renderer.frameSerial+1
 S.draw=function()game.save={};return base.draw()end
 state:draw();T.eq(draws,3,'a stale outer draw cannot reach the native UI')
 game.save=save;S.draw=base.draw
 Renderer.frameSerial=Renderer.frameSerial+1
 Ui.draw=function()game.save={};return base.uiDraw()end
 state:draw();T.eq(draws,3,'a stale inner UI draw cannot reach the native renderer')
 game.save=save;Ui.draw=base.uiDraw
 Renderer.frameSerial=Renderer.frameSerial+1
 Background.draw=function()game.save={};return base.bg()end
 state:draw();T.eq(fields,3,'a stale background hook cannot consume the native field pass')
 game.save=save;Background.draw=base.bg
 local live=S.getState();S._service.release()
 T.eq(game.stack:top(),state);T.raises(function()live.player.mon.hp=1 end,'retired')
 local final=S.getState();state.result='lose';game.stack:pop()
 T.eq(S.getResult(),'lose');T.eq(S.getState(),final)
 local finalSnapshot=require('src.compat.gen1.TableIteration').snapshot(final)
 T.eq(finalSnapshot.result,'lose');T.eq(finalSnapshot.player,final.player)
 f.close();G.release()
end
Gen3.draw,Gen3.drawField=originalDraw,originalField
-- A typed iterator registration cannot retain its own weak key through a
-- closure that reaches the environment's public view.
local weak=setmetatable({},{__mode='v'})
do
 local data={constants={},pokemon={},moves={}}
 local game={data=data,save={party={}}};local screen={kind='wild'}
 local e=require('src.compat.gen1.BattleView').new(game,screen,function()return true end)
 weak[1],weak[2],weak[3],weak[4]=e.view,game,data,screen
end
for _=1,4 do collectgarbage('collect')end
for i=1,4 do T.eq(weak[i],nil,'unused typed observations remain collectible: '..i)end
T.finish('native battle admission guards, capture ownership and typed iteration')
