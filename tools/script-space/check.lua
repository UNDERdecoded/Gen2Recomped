package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Space=require('src.core.game3.scripting.space')
T.eq(package.loaded['src.core.Game'],nil,'requiring script space cannot bootstrap a game')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local calls=0
local a,b,c=Boundary.dispatch('probe',function()calls=calls+1;return 'a',nil,'c'end,function()
  local x,y,z=Boundary.invoke('probe');Boundary.invoke('probe');return x,y,z
end)
T.eq(calls,1);T.eq(a,'a');T.eq(b,nil);T.eq(c,'c')
T.eq(Boundary.invoke('probe'),nil,'no native scope cannot advance anything')
T.raises(function()
  Boundary.dispatch('probe',function()calls=calls+1;error('native failure')end,function()
    pcall(Boundary.invoke,'probe');pcall(Boundary.invoke,'probe')
  end)
end,'native failure','native errors cannot be hidden by wrappers')
T.eq(calls,2);T.eq(Boundary.active('probe'),false)
local nested={}
Boundary.dispatch('probe',function()nested[#nested+1]='outer'end,function()
  Boundary.dispatch('probe',function()nested[#nested+1]='inner'end,function()Boundary.invoke('probe')end)
  Boundary.invoke('probe');Boundary.invoke('probe')
end)
T.eq(table.concat(nested,','),'inner,outer','nested visits restore the correct native scope')
love=require('tests.love_stub')
local Version=require('src.core.GameVersion')
local Compiler=require('src.script.Gen3ScriptVM')
local Runner=require('src.script.ScriptRunner')
local MapScripts=require('src.script.MapScripts')
local Native=require('src.compat.gen1.NativeSession')
local Bundle=require('src.compat.gen1.ScriptBundle')
local HostRuntime=require('src.mods.Runtime')
local nativeEnter,nativeFrame=Space.runEnterScripts,Space.runOnFrame
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  Space.release();MapScripts.resetBase()
  local f=require('tools.session-runtime.fixture').new(edition)
  local game,world=f.game,f.world
  game.save.flags={};game.save.gen3Vars={}
  world.runner=Runner.new(game,world)
  local queued={};function world:queueScript(rows,extra)queued[#queued+1]={rows,extra}end
  game.data.map_scripts={source='RomExtractorGen3',sourceInterface={schema=1,edition=edition},scripts={
    S0001000={{'setvar',0x4075,42},{'end'}},
    S0001100={{'delay',2},{'setvar',0x4076,91},{'end'}},
    S0001200={{'setvar',0x4077,77},{'end'}},
    S0001300={{'setvar',0x4078,99},{'end'}},
    S0001400={{'setvar',0x4010,19},{'setobjectxyperm',2,9,7},{'setobjectmovementtype',2,7},{'end'}},
    S0001500={{'goto','S0001500'}},
    S0001600={{'setflag',0x807},{'setvar',0x4079,13},{'end'}},
  },maps={TEST={callbacks={{type=3,script='S0001000'},{type=5,script='S0001200'}},
    tables={{type=2,rows={{var=0x4078,value=0,script='S0001300'}}}},objects={},signs={}}}}
  local pool=game.data.map_scripts
  local canonical=({firered='FR_VIRIDIAN_CITY',leafgreen='FR_VIRIDIAN_CITY',emerald='EM_OLDALE_TOWN',ruby='RU_OLDALE_TOWN',sapphire='SA_OLDALE_TOWN'})[edition]
  local _,group,number=require('src.compat.gen1.MapIdentity').lookup(edition,canonical)
  local neighbor={group=group,number=number,id='NEXT',objects={}}
  game.data.maps.NEXT=neighbor
  world.neighbors={{map={id='NEXT',def=neighbor}}}
  T.eq(Space.isActive(),true);T.eq(Space.mapId,f.canonical)
  local vm,store,bundle=Space.vm,Space.store,Space.bundle
  T.check(vm~=nil);T.eq(vm:isRunning(),false)
  T.eq(Space.scriptKey('g3:08001000'),'g3:08001000')
  store.vars[0x4075]=3;T.eq(game.save.gen3Vars[0x4075],3)
  T.eq(Space.runEnterScripts(),nil,'queries cannot start native entry scripts')
  T.eq(Compiler.register(game.data,'scenes'),1)
  local scripts=assert(MapScripts.get('TEST'))
  local enterCalls,frameCalls=0,0
  Space.runEnterScripts=function(mod,id,view,observed)
    enterCalls=enterCalls+1
    T.eq(id,f.canonical);T.eq(view.generation,3);T.eq(observed,world)
    T.eq(select(2,Native.resolve()),world,'map entry sees native world before stack publication')
    T.eq(Space.vm,vm)
    nativeEnter(mod,id,view,observed);nativeEnter(mod,id,view,observed)
  end
  game.stack.states={}
  scripts.onEnter(game,world)
  game.stack.states={world}
  T.eq(enterCalls,1);T.eq(#queued,2,'wrapped entry queues each native callback once')
  T.eq(store.vars[0x4075],3,'callbacks remain on the native pending queue')
  for _,item in ipairs(queued)do world.runner:run(item[1],item[2])end
  T.eq(store.vars[0x4075],42);T.eq(store.vars[0x4077],77)
  Space.runOnFrame=function()
    frameCalls=frameCalls+1
    local result=nativeFrame();T.eq(nativeFrame(),result);return result
  end
  T.eq(scripts.onFrame(game,world),true);T.eq(frameCalls,1)
  T.eq(store.vars[0x4078],99);T.eq(scripts.onFrame(game,world),false)
  T.eq(Space.startScript('g3:08001100',2,'left'),true)
  T.eq(store.vars[0x4076],nil);T.eq(vm:isRunning(),true)
  T.eq(game.save.gen3Vars[0x800f],2);T.eq(vm.ctx.specialVars[0x800c],3,'source context observes native facing')
  vm:tick();vm:tick();T.eq(world.runner.waitingFrames,2,'render/extra queries cannot consume waits')
  local baseTick=vm.tick;local ticks=0
  vm.tick=function(self)ticks=ticks+1;baseTick(self);return baseTick(self)end
  world.runner:update();T.eq(world.runner.waitingFrames,1);T.eq(ticks,1)
  world.runner:update();T.eq(store.vars[0x4076],91);T.eq(vm:isRunning(),false);T.eq(ticks,2)
  vm.tick=baseTick
  -- Invalid arguments must not partly update the native talk context.
  local last=vm.ctx.specialVars[0x800f]
  T.raises(function()Space.startScript('g3:08001000',9,'bad')end,'invalid script facing')
  T.eq(vm.ctx.specialVars[0x800f],last)
  local oldVm,oldStore=Space.vm,Space.store
  Space.vm=nil;Space.store={flags={},vars={}}
  T.eq(Space.vm,nil);T.eq(Space.startScript('g3:08001000'),false)
  T.raises(function()oldStore.vars[0x4075]=900 end,'preview lease')
  T.raises(function()oldVm.ctx.specialVars[0x8000]=900 end,'preview lease')
  Space.vm=oldVm;Space.store=oldStore
  T.eq(Space.vm,oldVm);T.eq(Space.store,oldStore)
  HostRuntime.currentMod='preview-owner';Space.vm=nil;Space.store={flags={},vars={}}
  HostRuntime.currentMod='native-peer'
  T.raises(function()Space.vm=oldVm end,'another mod')
  Space.cancelOwner('native-peer');T.eq(Space.vm,nil,'retiring a peer preserves the active preview')
  require('src.mods.Loader').new({}):_rollback('preview-owner')
  HostRuntime.currentMod=nil
  T.eq(Space.vm,oldVm);T.eq(Space.store,oldStore,'failed-entry rollback releases only the owning preview')
  T.eq(Space.startScript('g3:08001000'),true)
  T.eq(Space.persistSession(),true)
  T.eq(Space.resolveObjectGraphicsId({graphics=240}),nil)
  store.vars[0x4010]=39;T.eq(Space.resolveObjectGraphicsId({graphics=240}),39)
  T.eq(Space.resolveObjectSprite({graphics=39}),'SPRITE_G3_039')
  store.flags[0x807]=true;T.eq(Space.objectVisible({flag=0x807}),false)
  T.eq(Space.objectVisible({flag=0}),true);T.eq(Space.objectVisible({flag=65535}),true)
  pool.maps.NEXT={callbacks={{type=3,script='S0001400'}}}
  local liveVars=game.save.gen3Vars
  local observed=assert(Space.neighborObjectState(canonical))
  T.eq(observed.store.vars[0x4010],19);T.eq(observed.perm[2].x,9);T.eq(observed.perm[2].y,7)
  T.eq(observed.movementType[2],7);T.eq(game.save.gen3Vars,liveVars);T.eq(store.vars[0x4010],39)
  T.eq(game.save.gen3ObjectHomes,nil,'neighbour commands cannot write live object homes')
  pool.maps.NEXT.callbacks[1].script='S0001500'
  local state,why=Space.neighborObjectState(canonical)
  T.eq(state,nil);T.check(why:find('budget exhausted',1,true)~=nil,'looping native previews are bounded')
  pool.maps.NEXT.callbacks[1].script='S0001600'
  local before=HostRuntime.call;local hookCalls=0
  local wants=HostRuntime.wantsHook;HostRuntime.wantsHook=function()return true end
  HostRuntime.call=function(...)hookCalls=hookCalls+1;return before(...)end
  local clean=assert(Space.neighborObjectState(canonical))
  HostRuntime.call=before;HostRuntime.wantsHook=wants
  T.eq(clean.store.vars[0x4079],13);T.eq(clean.store.flags[0x807],true,'preview cannot execute an unsupported flag write')
  T.eq(store.vars[0x4079],nil);T.eq(hookCalls,0)
  local projection=bundle.scripts['g3:08001000']
  T.eq(projection[1].op,'setvar');projection[1][2]=888
  local ran,reason=Space.startScript('g3:08001000')
  T.eq(ran,false);T.check(reason:find('overlay compiler',1,true)~=nil)
  T.eq(pool.scripts.S0001000[1][3],42,'editing a projection cannot edit native rows')
  projection[1][2]=42
  T.eq(Space.startScript('g3:08001100'),true)
  local owned=world.runner.ctx
  HostRuntime.currentMod='another-mod';T.eq(vm:halt(),false,'a peer cannot cancel another admission');HostRuntime.currentMod=nil
  T.eq(vm:halt(),true);T.eq(owned.scriptCancelled,true)
  T.eq(owned.trainerPreparationCancelled,nil);T.eq(owned.lastBattleResult,nil,'ordinary cancellation never fabricates a battle result')
  T.eq(vm:isRunning(),false)
  -- A retained source VM cannot drive a replacement runner/world/dataset.
  local nextWorld={isOverworld=true,map=f.map,player=f.player,npcs={}}
  nextWorld.runner=Runner.new(game,nextWorld);game.stack.states={nextWorld}
  T.eq(vm:isRunning(),false)
  T.raises(function()vm:start('g3:08001000')end,'retired')
  T.check(Space.vm~=vm);T.eq(Space.bundle,bundle,'map changes reuse immutable script projection')
  local hold=Space.vm;game.save={flags={},gen3Vars={}}
  T.eq(hold:isRunning(),false);T.check(Space.vm~=hold);T.check(Space.bundle~=bundle)
  Space.deactivate();T.eq(Space.isActive(),false);T.eq(Space.vm,nil)
  T.check(Space.activate(nil,f.canonical)~=nil);T.eq(Space.isActive(),true)
  Space.runEnterScripts,Space.runOnFrame=nativeEnter,nativeFrame
  Space.release()
end
-- Raw operands must survive native normalization, including trainer layouts.
local row=Bundle.row({'specialvar',0x8000,999,sourceOpcode=0x26,sourceSpecial=117,sourceSpec='ww',sourceBytes=string.char(0,128,117,0)},'ruby')
T.eq(row.op,'specialvar');T.eq(row[2],117);T.eq(row.id,117)
local pointer=Bundle.row({'loadword',0,'TEXT_001234',sourceSpec='bd',sourceBytes=string.char(0,0x34,0x12,0,8)},'firered')
T.eq(pointer.value,'g3:08001234');T.eq(pointer[2],pointer.value)
Version.set('crystal');T.eq(Space.isActive(),false);T.eq(Space.vm,nil)
T.finish('native script-space ownership and field phases')
