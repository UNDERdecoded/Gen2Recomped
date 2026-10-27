-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Battle=require('src.core.game3.battle')
local Background=require('src.core.game3.battle.bg')
local Ui=require('src.core.game3.battle.ui')
local baseUpdate,baseDraw=Battle.update,Battle.draw
local originalGame=package.loaded['src.core.Game']
local retained,weak
T.eq(Battle.isActive(),false)
T.eq(baseUpdate(),nil,'a source call cannot manufacture a native tick')
T.eq(baseDraw(),false)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  local f=require('tools.battle-source-runtime.fixture').new(edition)
  local game=f.game;
  package.loaded['src.core.Game']=game
  game.data.constants=game.data.constants or{}
  game.data.constants.speciesOrder={[4]='CHARMANDER'}
  game.data.constants.moveOrder={[33]=f.ids.TACKLE}
  game.data.constants.typeOrder={'NORMAL'}
  game.data.constants.abilityOrder={'NONE','PROBE_ABILITY'}
  game.data.constants.abilities={NONE={index=0},PROBE_ABILITY={index=1}}
  game.data.constants.types={NORMAL={index=0}}
  game.data.constants.itemOrder={[7]='PROBE_ITEM'}
  game.data.items.PROBE_ITEM={index=7}
  local b=f.fresh('TACKLE').battle
  b.player.ability='PROBE_ABILITY';b.player.mon.item='PROBE_ITEM'
  local starts=0;local start=Battle.start
  Battle.start=function(opts)starts=starts+1;T.eq(opts.wild,true);return start(opts)end
  game.stack:push(b);Battle.start=start;T.eq(starts,1,'real native entry notifies source start once')
  local st=assert(Battle.getState())
  T.eq(Battle.isActive(),true)
  T.eq(baseDraw({data=game.data,save=game.save,stack=game.stack}),false,'foreign capture cannot retire the active view')
  T.eq(Ui.bindState(nil),false)
  T.eq(st,Battle.getState(),'one identity for the native admission')
  T.eq(st.player.id,0);T.eq(st.enemy.id,1)
  T.eq(st.player.side,'player');T.eq(st.enemy.side,'enemy')
  T.eq(st.player.mon.species,4);T.eq(st.player.mon.moves[1],33)
  T.eq(st.player.mon.item,7);T.eq(st.player.ability,1);T.eq(st.player.type1,0)
  T.eq(st.player.mon.maxHp,400);T.eq(st.party[1],st.player.mon)
  T.neq(st.player.mon,b.player.mon);T.neq(st, b)
  st.player.mon.hp=399;T.eq(b.player.mon.hp,399)
  st.player.mon.status=128;T.eq(b.player.mon.status,'PSN');T.eq(b.player.mon.toxic,true)
  st.player.mon.status=0;T.eq(b.player.mon.status,nil)
  T.raises(function()st.player.mon.hp=-1 end,'invalid native HP')
  T.raises(function()st.weather='SUN'end,'not directly writable')
  T.raises(function()st.player={}end,'not directly writable')
  st.paperPresentation={enabled=true};T.eq(st.paperPresentation.enabled,true)
  local ticks=0;local tickFx=b.tickFx
  b.tickFx=function(self,...)ticks=ticks+1;return tickFx(self,...)end
  b.phase='menu';b.queue={};b.current=nil
  local pp=st.player.mon.pp
  pp[1]=9
  Battle.update=function(dt,view)
    T.eq(require('src.core.Game3').native(view),game)
    baseUpdate(dt,view);return baseUpdate(dt,view)
  end
  local pump=Ui.pump
  Ui.pump=function()pump();return pump()end
  b:update(1/60);Ui.pump=pump
  T.eq(pump(),nil,'UI calls outside the native input phase cannot tick combat')
  T.eq(Ui.bindState(st),true);T.eq(Ui.bindState({}),false)
  for _,method in ipairs{'statusHUDVisible','bottomUIVisible','moveGridNavigation'}do
    if type(b[method])=='function'then T.eq(Ui[method](),b[method](b))
    else local value,why=Ui[method]();T.eq(value,nil);T.check(why:find('native UI query unavailable',1,true)~=nil)end
  end
  T.eq(ticks,1,'two wrapper base calls consume the native tick once')
  T.eq(b.player.mon.moves[1].pp,9,'validated source PP edit reaches the actual native move')
  T.eq(baseUpdate(1/60),nil);T.eq(ticks,1,'direct source update outside native scope has no clock')
  local overlay={};game.stack:push(overlay)
  T.eq(Battle.getState(),st,'covered combat remains observable')
  T.eq(Battle.abort('run'),false,'abort cannot pop a foreign overlay')
  T.eq(b:update(1/60),false);T.eq(ticks,1)
  game.stack:pop()
  Battle.update=baseUpdate
  T.eq(Battle.statWindowPhase(),false)
  game.stack:push(b.StatBox.new(game,b.player.mon))
  T.eq(Battle.statWindowPhase(),true,'the actual native level-up window is observed')
  game.stack:pop()
  local Host=require('src.mods.Runtime');Host.currentMod='battle_owner'
  T.eq(Battle.getState(),st);Host.currentMod=nil
  require('src.core.game3.asset_stream').cancelOwner('other_owner');T.eq(Battle.getState(),st)
  require('src.core.game3.asset_stream').cancelOwner('battle_owner')
  T.raises(function()st.player.mon.hp=1 end,'retired')
  T.eq(Battle.isActive(),true,'mod teardown retires views while native combat continues')
  local fresh=Battle.getState();T.neq(fresh,st);st=fresh
  local draws,fields=0,0
  local NativeDraw=require('src.battle.Gen3Battle');local draw,field=NativeDraw.draw,NativeDraw.drawField
  NativeDraw.draw=function(screen)draws=draws+1;screen:drawBattleField()end
  NativeDraw.drawField=function()fields=fields+1 end
  local uiDraw=Ui.draw;local uiDraws=0
  Ui.draw=function(w,h)uiDraws=uiDraws+1;uiDraw(w,h);return uiDraw(w,h)end
  Battle.draw=function(view,w,h)T.eq(w,240);T.eq(h,160);baseDraw(view,w,h);return baseDraw(view,w,h)end
  b:draw();T.eq(uiDraws,1);T.eq(draws,1);T.eq(fields,1,'base draw consumes the field and native UI once')
  local bgDraw=Background.draw
  Background.draw=function()return true end
  b:draw();T.eq(draws,2);T.eq(fields,1,'background replacement leaves the native UI draw admitted')
  Background.draw=bgDraw
  Battle.draw=function()love.graphics.push();error('battle presentation error')end
  local push,pop=love.graphics.push,love.graphics.pop
  T.raises(function()b:draw()end,'battle presentation error')
  T.eq(love.graphics.push,push);T.eq(love.graphics.pop,pop)
  Battle.draw=baseDraw;Ui.draw=uiDraw;NativeDraw.draw,NativeDraw.drawField=draw,field
  local bad=st.player.mon.moves;bad[1]=99
  T.raises(function()b:update(1/60)end,'source move replacement')
  bad[1]=33;b:update(1/60)
  local rng=st.rng
  local nativeHp=b.player.mon.hp
  local callbacks=0;b.onFinish=function(result)T.eq(result,'lose');callbacks=callbacks+1 end
  b.result='lose';b:finish()
  T.eq(Battle.isActive(),false);T.eq(Battle.getState(),st)
  T.eq(st.result,'lose');T.eq(st.over,true);T.eq(callbacks,1)
  T.eq(st.player.mon.hp,nativeHp,'retired state has a detached final observation')
  T.raises(function()st.player.mon.hp=10 end,'retired')
  T.raises(function()rng(1,2)end,'retired')
  T.eq(Battle.abort('run'),false,'completion cannot pop a subsequent native screen')
  T.eq(Battle.reset(),true);T.eq(Battle.getState(),nil)
  retained={st,st.player,st.player.mon,rng}
  weak=setmetatable({game,game.save,b},{__mode='v'})
  f.close();require('src.core.Game3').release()
end
package.loaded['src.core.Game']=originalGame
for _=1,4 do collectgarbage('collect')end
T.eq(weak[3],nil,'retained completed views do not keep the native controller alive')
T.eq(retained[1].result,'lose');T.raises(function()retained[4](1,2)end,'retired')
-- Isolate this view's ownership from the host's process-wide Game3 facade cache.
local function retiredViews()
 local data={pokemon={},moves={},constants={}}
 local game={data=data,save={party={}}}
 local screen={kind='wild',result='run',rng=function(lo)return lo end}
 local weak=setmetatable({game,game.save,data,screen},{__mode='v'})
 local e=require('src.compat.gen1.BattleView').new(game,screen,function()return true end)
 local view,rng=e.view,e.rng;e:retire();return view,rng,weak
end
local view,rng,refs=retiredViews()
for _=1,4 do collectgarbage('collect')end
for i=1,4 do T.eq(refs[i],nil,'retired battle views release native owner '..i)end
T.eq(view.result,'run');T.raises(function()rng(1,2)end,'retired')
T.finish('native GBA battle admission, numeric views, once-only phases and teardown')
