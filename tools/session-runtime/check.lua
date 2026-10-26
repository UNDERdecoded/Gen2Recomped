package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local R=require('src.core.game3.runtime')
local G=require('src.core.Game3')
local NativeSession=require('src.compat.gen1.NativeSession')
local Views=require('src.compat.gen1.SessionView')
local NativeRuntime=require('src.mods.Runtime')
T.eq(package.loaded['src.core.Game'],nil,'queries never bootstrap the native Game')
T.eq(R.isActive(),false);T.eq(R.getSession(),nil);T.eq(R.defer(function()end),false)
T.eq(R.update(),nil);T.eq(R.drainDeferred(),0)
T.eq(G.new(),nil,'a source constructor cannot silently share another live game')
local F=require('tools.session-runtime.fixture')
local Touch=require('src.core.TouchControls');local poll=Touch.pollTouches;Touch.pollTouches=function()end
local baseUpdate,baseFixed,baseRuntime,baseReset,baseDraw=G.update,G.fixedUpdate,R.update,G.reset,G.draw
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  R.release();G.release()
  local f=F.new(edition);local native=f.game;local view=assert(G.forNative(native))
  T.check(G~=native and view~=native,'source class/instance are distinct from the native Game')
  T.eq(G.forNative(native),view);T.eq(G.native(view),native);T.eq(NativeSession.game(view),native)
  T.eq(view.input,native.input);T.eq(view.generation,3);T.eq(view.phase,'field')
  view.speedOverride=3;T.eq(native.speedOverride,3)
  T.raises(function()view.speedOverride=0/0 end,'invalid native speed override')
  view.speedOverride=nil;T.eq(native.speedOverride,nil)
  local s=assert(R.getSession());T.eq(s,view.session);T.eq(s,view.save)
  T.eq(s.map,f.canonical);T.eq(s.x,4);T.eq(s.y,4);T.eq(s.name,'NATIVE')
  T.eq(s.trainerId,37);T.eq(s.gender,0);T.eq(s.money,300);T.eq(s.coins,4)
  local before=native.save.playTime
  for _=1,10 do
    local clock=R.pumpRtc(native,10)
    T.eq(clock.hours,1);T.eq(clock.minutes,1);T.eq(clock.seconds,1);T.eq(R._playTimeAcc,.25)
    T.eq(R.tickVblank(s),0,'repeated clock queries cannot tick another owner')
  end
  T.eq(native.save.playTime,before,'clock projection never rewrites the native save')
  s.money=91;s.name='SOURCE';s.gender=1
  T.eq(native.save.money,91);T.eq(native.save.player.name,'SOURCE');T.eq(native.save.player.gender,1)
  T.raises(function()s.money=0/0 end,'invalid session');T.raises(function()s.x=99 end,'native command owner')
  T.eq(f.player.cellX,4,'source session writes cannot teleport the native actor')
  s.presentation={foo=1};T.eq(native.save.presentation,nil,'presentation extensions stay detached')
  T.eq(s.party,nil,'a differently shaped native party is never lent as a source party')
  native.save.playTime={hours=2,mins=2,secs=3,vblanks=15}
  T.eq(Views.seconds(native.save),7323.25);T.eq(R._playTimeAcc,.25)
  T.eq(type(native.save.playTime),'table','old save clocks are observed without normalization writes')
  native.save.playTime=before
  -- Preview leases shadow even nil, without touching the real stack/save.
  local nativeStack=native.stack
  view.stack=nil;T.eq(view.stack,nil);T.eq(native.stack,nativeStack)
  view.stack=nativeStack
  local scratch={name='PREVIEW'};R.session=scratch;T.eq(R.getSession(),scratch)
  R.session=s;T.eq(R.getSession(),s);T.eq(native.save.player.name,'SOURCE')
  local seq={}
  T.eq(R.defer(function()
    seq[#seq+1]='first';T.eq(R.drainDeferred(),0,'nested drains cannot run the next batch')
    R.defer(function()seq[#seq+1]='next'end)
  end),true)
  R.defer(function()seq[#seq+1]='second'end)
  T.eq(R.drainDeferred(),0,'only a native fixed step can drain callbacks')
  local clock=native.save.playTime;native:_step(1/60)
  T.same(seq,{'first','second'});T.eq(f.nativeUpdates,1);T.eq(f.inputSteps,1)
  T.eq(native.save.playTime,clock+1/60);T.eq(R.tickVblank(),1)
  native:_step(1/60);T.same(seq,{'first','second','next'});T.eq(R.tickVblank(),2)
  NativeRuntime.errors={};NativeRuntime.currentMod='runtime_probe'
  R.defer(function()error('intentional deferred failure')end)
  R.defer(function()seq[#seq+1]='after failure'end)
  NativeRuntime.currentMod=nil
  native:_step(1/60)
  T.eq(seq[#seq],'after failure');T.check(NativeRuntime.errors[1]:find('runtime_probe:',1,true)~=nil)
  -- A callback may replace the save. No later callback from its old cohort runs.
  R.defer(function()native.save={player=native.save.player,playTime=7,options={}}end)
  R.defer(function()error('old save callback escaped retirement')end)
  local old=s;native:_step(1/60)
  T.eq(native.save.playTime,7,'a retired callback phase cannot tick the replacement save')
  T.eq(old.map,nil);T.raises(function()old.money=200 end,'retired')
  T.check(R.getSession()~=old,'replacement save receives a fresh source session view')
  -- Runtime wrappers can hold the native field, then resume its single owner.
  local updates=f.nativeUpdates;clock=native.save.playTime;local serial=R.tickVblank()
  R.update=function()end;native:_step(1/60)
  T.eq(f.nativeUpdates,updates);T.eq(native.save.playTime,clock);T.eq(R.tickVblank(),serial)
  R.update=baseRuntime;native:_step(1/60);T.eq(f.nativeUpdates,updates+1)
  -- The actual native fixed-step entry invokes its source wrapper. Calling
  -- the captured base twice cannot double input, player, script or clock work.
  G.fixedUpdate=function(game,dt)T.eq(game,view);baseFixed(game,dt);return baseFixed(game,dt)end
  updates=f.nativeUpdates;clock=native.save.playTime;local steps=f.inputSteps
  native:_step(1/60)
  T.eq(f.nativeUpdates,updates+1);T.eq(f.inputSteps,steps+1);T.eq(native.save.playTime,clock+1/60)
  G.fixedUpdate=baseFixed
  -- Real native modal ownership, including the start/save focus exceptions.
  native.stack:push({screenId='StartMenu',update=function()end})
  T.eq(R.uiBusy(),true);T.eq(R.fieldScreenOpen(),false)
  native.stack:push({screenId='SummaryMenu',update=function()end})
  T.eq(R.fieldScreenOpen(),true)
  R.setUi({preview=true});T.eq(R.uiBusy(),true);R.setUi(nil)
  native.stack:pop();native.stack:pop();T.eq(R.uiBusy(),false)
  local menus=0;local lighting=package.loaded['src.core.game3.league_lighting']
  package.loaded['src.core.game3.league_lighting']={stop=function()menus=menus+1 end}
  R.noteFieldFocus(true);R.noteFieldFocus(true);T.eq(menus,1)
  R.noteFieldFocus(false);package.loaded['src.core.game3.league_lighting']=lighting
  -- Holding a batch across source preview leases preserves its attribution.
  R.defer(function()seq[#seq+1]='restored lease'end)
  local deferred=R._deferred;R._deferred={};native:_step(1/60)
  T.check(seq[#seq]~='restored lease');R._deferred=deferred;native:_step(1/60)
  T.eq(seq[#seq],'restored lease')
  R.defer(function()error('exit callback should be cancelled')end)
  local calls=0
  require('src.mods.ModSeams').run('runtime_probe',function()
    G.reset=function(game)calls=calls+1;T.eq(game.mods,native.mods);return baseReset(game)end
    G.update=function(...)return baseUpdate(...)end
  end)
  require('src.mods.Loader').teardown()
  T.eq(calls,1,'native teardown invokes source cleanup before wrappers unwind')
  T.eq(G.update,baseUpdate);T.eq(G.reset,baseReset);T.eq(R.isActive(),false)
  T.eq(NativeSession.game(view),nil,'retired views cannot fall through to a new native owner')
  T.eq(G.forNative(view),nil)
  T.raises(function()baseFixed(view,1/60)end,'retired')
end
Touch.pollTouches=poll
NativeRuntime.errors=nil
T.finish('native source session lifecycle and fixed-step runtime')
