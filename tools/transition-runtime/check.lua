package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Source=require('src.core.game3.battle_transition')
T.eq(package.loaded['src.core.Game'],nil,'requiring transition observations cannot bootstrap a game')
T.eq(Source.isActive(),false)
love=require('tests.love_stub')
local Version=require('src.core.GameVersion')
local Native=require('src.render.BattleTransition')
local Host=require('src.mods.Runtime')
local Catalog=require('src.compat.gen1.TransitionCatalog')
local initial={start=Source.start,tick=Source.tick,finish=Source.finish,draw=Source.draw,drawWorld=Source.drawWorld}
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  Source.release()
  local f=require('tools.session-runtime.fixture').new(edition)
  local game=f.game
  if edition=='ruby'or edition=='sapphire'then
    -- Exercise an existing relocated cache as well as the new import profile.
    local record={wild={{8,9},{5,10},{0,10},{7,6}},trainer={{4,11},{2,3},{0,10},{1,6}},
      names={[4]='pokeballsTrail',[8]='slice',[9]='whiteBarsFade',[12]='sidney',[16]='champion'},
      trainerClasses={eliteFour=31,champion=38},eliteFour={SIDNEY=12},championTransition=16}
    game.data.constants.gen3BattleTransitions=record
    local imported=require('src.import.Gen3TransitionProfile').classes(edition,record.trainerClasses)
    T.eq(imported.eliteFour,24);T.eq(imported.champion,32)
    T.eq(record.trainerClasses.eliteFour,31,'runtime fallback cannot rewrite a borrowed native profile')
    record.trainerClasses=imported
    local elite=Native.new(game,nil,{trainer=true,trainerClass=24,trainerName='SIDNEY'})
    T.eq(elite.style,'g3_mugshot','corrected RS import routes its actual Elite Four class')
    local ordinary=Native.new(game,nil,{trainer=true,trainerClass=31,weaker=true})
    T.eq(ordinary.style,'g3_pokeballsTrail','RS class31 does not inherit the Emerald Elite Four role')
    record.trainerClasses={eliteFour=31,champion=38}
    T.eq(Native.new(game,nil,{trainer=true,trainerClass=31}).style,'g3_mugshot','an authored Emerald-shaped profile remains authoritative at runtime')
    local custom={eliteFour=99,champion=100}
    T.eq(require('src.import.Gen3TransitionProfile').classes(edition,custom),custom,'authored profiles retain their chosen ordinals')
    game.data.constants.gen3BattleTransitions=nil
  end
  local notices={}
  package.loaded['src.ui.game3.presentation']={notify=function(event,ctx)notices[#notices+1]={event,ctx.finished}end}
  local ticks,starts,finished,callbacks=0,0,0,0
  Source.start=function(id,opts,cb)
    starts=starts+1
    local result=initial.start(id,opts,function()cb();cb()end)
    initial.start(id,opts,cb)
    return result
  end
  Source.tick=function()ticks=ticks+1;local result=initial.tick();initial.tick();return result end
  Source.finish=function()finished=finished+1;local result=initial.finish();initial.finish();return result end
  local ids=Source.ids();T.eq(ids.ID.SLICE,8)
  Host.currentMod='transition-owner'
  game.stack:push(Native.new(game,function()callbacks=callbacks+1 end,
    {style=Catalog.new(edition).styles[8],skipIntro=true}))
  T.eq(Source.isActive(),true)
  Host.currentMod=nil
  local state=game.stack:top()
  T.eq(getmetatable(state),Native);T.eq(Source.isActive(),true);T.eq(starts,1)
  T.eq(Source._phase,'main');T.eq(Source._transitionId,8);T.eq(Source._frame,0)
  local options=Source._opts
  Source.tick();Source.tick();T.eq(state.frame,0,'arbitrary calls cannot drive a second native clock')
  local beforeTicks=ticks
  state:update(1/60);T.eq(state.frame,1);T.eq(ticks,beforeTicks+1)
  T.eq(Source._opts,options,'sequence identity is stable through updates')
  local top={};game.stack:push(top)
  state:update(1/60);T.eq(state.frame,1,'covered native transitions cannot advance')
  Host.currentMod='transition-peer';T.eq(Source.abort(),false);Host.currentMod=nil
  T.eq(game.stack:top(),top,'abort cannot pop a foreign modal state')
  game.stack:pop()
  while Source.isActive()do game.stack:update(1/60)end
  T.eq(callbacks,1,'callback wrappers cannot invoke native continuation twice')
  T.eq(finished,1);T.eq(#notices,1);T.eq(notices[1][1],'battleTransitionEnd');T.eq(notices[1][2],true)
  T.eq(game.stack:top(),f.world)
  state:update(1/60);T.eq(callbacks,1,'retained finished state cannot finish again')
  T.eq(Source._phase,'done');T.eq(Source.isActive(),false)
  local aborts=0
  Host.currentMod='transition-owner'
  T.eq(Source.start(ids.ID.SLICE,{},function()aborts=aborts+1 end),true)
  local aborted=game.stack:top()
  T.eq(Source.abort(),true);Host.currentMod=nil
  T.eq(aborts,0);T.eq(aborted.onDone,nil);T.eq(notices[2][2],false)
  T.eq(game.stack:top(),f.world)
  -- Releasing observers must restore an engine-owned continuation.
  local vanillaCallbacks=0
  local plain=Native.new(game,function()vanillaCallbacks=vanillaCallbacks+1 end,{})
  game.stack:push(plain);Source.release()
  plain:complete(true);T.eq(vanillaCallbacks,1,'adapter teardown preserves native continuations')
  local customDraws=0
  game.data.transitions={native_peer_style={kind='wipe',frames=2,draw=function()customDraws=customDraws+1 end}}
  local peer=Native.new(game,nil,{style='native_peer_style'});game.stack:push(peer)
  peer.phase='wipe';peer.t=1;peer:draw()
  T.eq(customDraws,1,'a registered foreground style draws once')
  T.eq(Source._compositeWorld({worldOverride={}}),false,'foreground styles retain the native UI pass')
  T.eq(customDraws,1);peer:complete(false)
  local oldNotice=package.loaded['src.ui.game3.presentation'].notify
  package.loaded['src.ui.game3.presentation'].notify=function()error('intentional presentation failure')end
  local survived=0
  local finish=Native.new(game,function()survived=survived+1 end,{style=Catalog.new(edition).styles[8]})
  game.stack:push(finish);finish:finish()
  T.eq(survived,1,'a failed presentation notification cannot strand native battle continuation')
  T.eq(game.stack:top(),f.world)
  package.loaded['src.ui.game3.presentation'].notify=oldNotice
  local weak=setmetatable({},{__mode='v'})
  do
    local payload={owned='completed battle payload'};weak[1]=payload
    local callback=(function(value)return function()T.eq(value.owned,'completed battle payload')end end)(payload)
    local completed=Native.new(game,callback,{style=Catalog.new(edition).styles[8]})
    game.stack:push(completed);completed:finish()
  end
  collectgarbage('collect');collectgarbage('collect')
  T.eq(weak[1],nil,'retained transition observations release the completed callback payload')
  -- Source-owned teardown is restricted to its own admission and owner.
  Host.currentMod='transition-owner';Source.start(8,{},function()error('cancelled source callback ran')end)
  Host.currentMod='transition-peer';Source.cancelOwner('transition-peer');T.eq(Source.isActive(),true)
  Host.currentMod='transition-owner';Source.cancelOwner('transition-owner');Host.currentMod=nil
  T.eq(Source.isActive(),false)
  -- No partially completed script can finish a replacement save/loader.
  T.eq(Source.start(8,{},function()error('stale callback ran')end),true)
  local stale=game.stack:top();local frame=stale.frame
  game.save={};stale:update(1/60)
  T.eq(stale.frame,frame);T.eq(Source.isActive(),false);T.eq(Source.finish(),false)
  T.eq(game.stack:top(),stale);T.eq(Source._opts,nil)
  game.stack:pop()
  for k,v in pairs(initial)do Source[k]=v end
  Source.release()
end
package.loaded['src.ui.game3.presentation']=nil
-- Family tables are facts, with distinct RS enum limits and names.
local fr=Catalog.new('firered');local em=Catalog.new('emerald');local ru=Catalog.new('ruby')
T.eq(fr.ID.SPIRAL,17);T.eq(fr.ID.AQUA,nil);T.eq(em.ID.FRONTIER_SQUARES_SPIRAL,33)
T.eq(ru.ID.SYDNEY,12);T.eq(ru.ID.STEVEN,16);T.eq(ru.ID.AQUA,nil)
Version.set('crystal');T.eq(Source.isActive(),false)
T.finish('native transition phases and ownership')
