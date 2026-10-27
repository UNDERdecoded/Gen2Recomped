-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Tasks=require('src.core.game3.battle.anim_tasks')
local VM=require('src.core.game3.battle.anim_vm')
local Battle=require('src.core.game3.battle')
local Facts=require('src.import.Gen3VisualTaskFacts')
local G=require('src.core.Game3')
local spawn,draw,launch=Tasks.spawn,Tasks.draw,VM.launch
local original=package.loaded['src.core.Game']
local function pack(...)return{n=select('#',...),...}end
local function meta(kind,at,order,priority)
 return assert(Facts.fromTask(kind,{fn=0x1001+order*2,args={kind=='dig_up'and 1 or 0},
  at=at,order=order,priority=priority}))
end
T.eq(spawn('unknown'),nil);T.eq(draw(),false);T.eq(Tasks._pool,nil)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition);local game=f.game
 package.loaded['src.core.Game']=game;game.data.constants.gen3BattleAnimGfx={}
 local down={kind='dig_down',at=0,selector=0,visualTask=meta('dig_down',0,1,5)}
 local up={kind='dig_up',at=3,selector=0,visualTask=meta('dig_up',3,3,1)}
 local surf={at=3,life=134,waitLife=136,step=2,fade=13,hold=54,blendOf=16,
  player={image='owned wave',x=0,y=-48,dx=-2,dy=1},
  opponent={image='owned wave',x=-224,y=256,dx=2,dy=-1},visualTask=meta('surf',3,2,9)}
 game.data.moves.MOVE_033.anim={duration=150,scanlines={down,up},surf=surf}
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b)
 local native=b.gen3Anim;local births={};local parentVM
 VM.launch=function(view)parentVM=view;local first=launch(view);T.eq(first,true);T.eq(launch(view),true);return first end
 Tasks.spawn=function(name,priority,args,vm)
  T.eq(vm,parentVM,'child task borrows the enclosing native launch handle')
  local task=spawn(name,priority,args,vm);T.eq(spawn(name,priority,args,vm),task)
  T.eq(task.active,true);T.eq(task.name,name);T.eq(task.priority,priority)
  local arg=args[1];args[1]=99;T.eq(task.args[1],arg,'callback operands are detached')
  births[#births+1]=name;return task
 end
 T.eq(native:start('MOVE_033',true,0,1,nil,b),true)
 local pool=Tasks._pool;T.eq(pool,Tasks._pool,'pool view is stable without per-frame copies')
 T.eq(#pool,1);local digging=pool[1];T.eq(digging.name,'AnimTask_DigDownMovement');T.eq(digging.draw,nil)
 T.raises(function()digging.active=false end,'read-only');T.raises(function()digging.args[1]=2 end,'read-only')
 T.raises(function()Tasks._pool={}end,'read-only')
 native:update();T.eq(#pool,1);native:update();T.eq(#pool,1);native:update();T.eq(#pool,3)
 T.same(births,{'AnimTask_DigDownMovement','AnimTask_CreateSurfWave','AnimTask_DigUpMovement'},
  'birth notifications retain script order, independent of task priority')
 local wave,upTask=pool[2],pool[3]
 T.eq(wave.name,'AnimTask_CreateSurfWave');T.eq(wave.ga[0],0);T.eq(wave.ga.unknown,nil)
 T.eq(wave.data[2],0);T.eq(wave._scan[1],0x1000);T.eq(parentVM:attackerSide(),'player')
 native:update();T.eq(wave.data[2],1);T.eq(wave._scan[1]%32,1)
 local scriptFrame,battleFrame=native.frame,b.frame
 T.eq(wave.draw(wave,parentVM),false,'a retained draw function cannot paint between native phases')
 local paints=0
 Tasks.draw=function(vm)
  T.eq(vm,parentVM);local base=wave.draw
  wave.draw=function(task,view)base(task,view);return base(task,view)end
  local values=pack(draw(vm));T.eq(values.n,3);draw(vm);wave.draw=base
  return false,nil,'source task result'
 end
 local a,middle,last=Tasks._nativeDraw(native,b,function(player,screen)
  T.eq(player,native);T.eq(screen,b);paints=paints+1;return 7,nil,nil
 end)
 T.eq(a,false);T.eq(middle,nil);T.eq(last,'source task result');T.eq(paints,1)
 T.eq(native.frame,scriptFrame);T.eq(b.frame,battleFrame)
 local depth=love.graphics.getStackDepth and love.graphics.getStackDepth()
 Tasks.draw=function()love.graphics.push('all');error('task source draw failed')end
 T.raises(function()Tasks._nativeDraw(native,b,function()end)end,'task source draw failed')
 if depth then T.eq(love.graphics.getStackDepth(),depth)end
 Tasks.draw=function(vm)pcall(draw,vm);return true end
 T.raises(function()Tasks._nativeDraw(native,b,function()error('native task draw failed')end)end,'native task draw failed')
 Tasks.draw=function(vm)game.stack:push({});local a,why=draw(vm);game.stack:pop();return a,why end
 paints=0;a,last=Tasks._nativeDraw(native,b,function()paints=paints+1 end)
 T.eq(a,false);T.eq(last,'native task draw admission changed');T.eq(paints,0)
 -- An already covered battle can still paint below the existing bag/menu.
 Tasks.draw=function(vm)return draw(vm)end;game.stack:push({})
 Tasks._nativeDraw(native,b,function()paints=paints+1 end);game.stack:pop();T.eq(paints,1)
 for _=native.frame+1,up.at+native:scanlineTaskLife(up,b)do native:update()end
 T.eq(upTask.active,false,'upward task lifetime belongs to the actual native sampler')
 T.eq(wave.active,true,'the longer native wave is still active')
 local seam=require('src.mods.ModSeams');local owner=G._callbackOwner()
 Tasks.draw=function(vm)T.eq(G._callbackOwner(),'task_owner');return draw(vm)end
 seam._journal[#seam._journal+1]={tbl=Tasks,key='draw',after=Tasks.draw,owner='task_owner'}
 Tasks._nativeDraw(native,b,function()paints=paints+1 end);table.remove(seam._journal);T.eq(G._callbackOwner(),owner)
 Tasks._service.releaseOwner(nil,'unrelated_task_owner');T.eq(wave.active,true)
 Tasks._service.releaseOwner(nil,'task_owner');T.eq(wave.active,false);T.eq(Tasks._pool,nil)
 local held=native.frame;Tasks._nativeDraw(native,b,function()paints=paints+1 end)
 native:update();T.eq(native.frame,held+1,'source teardown cannot cancel the native effect')
 Tasks.spawn,Tasks.draw,VM.launch=spawn,draw,launch
 T.eq(native:start('MOVE_033',true,0,1,nil,b),true)
 for _=1,4 do native:update()end
 local replaced=Tasks._pool[2]
 Tasks.draw=function(vm)
  local save=game.save;game.save={};local a,why=draw(vm);game.save=save;return a,why
 end
 paints=0;a,last=Tasks._nativeDraw(native,b,function()paints=paints+1 end)
 T.eq(a,false);T.eq(last,'native task draw admission changed');T.eq(paints,0)
 T.eq(replaced.active,false);T.eq(Tasks._pool,nil,'a replaced cohort cannot retain the old task pool')
 Tasks.draw=draw
 -- The downward task is longer than the wave. Qualify its actual last
 -- active frame separately instead of assuming the wave is still drawing.
 surf.visualTask=nil;up.visualTask=nil
 T.eq(native:start('MOVE_033',true,0,1,nil,b),true)
 local falling=Tasks._pool[1];local life=native:scanlineTaskLife(down,b)
 for _=1,life-1 do native:update()end
 T.eq(falling.active,true,'downward task stays active until its native final step')
 native:update();T.eq(falling.active,false,'downward task retires on its native final step')
 -- No inferred priority/name is used for old or unsupported caches; their
 -- exact native painter remains available without a source task pool.
 surf.visualTask=nil;down.visualTask=nil;up.visualTask=nil
 T.eq(native:start('MOVE_033',false,nil,nil,nil,b),true);T.eq(Tasks._pool,nil)
 local view=VM._nativeView(native);T.eq(view:attackerId(),1);T.eq(view:targetId(),0)
 T.eq(view:attackerSide(),'enemy');T.eq(view:targetSide(),'player')
 paints=0;Tasks._nativeDraw(native,b,function()paints=paints+1 end);T.eq(paints,1)
 game.stack:pop();T.eq(digging.active,false);T.eq(wave.active,false)
 Tasks._service.release();VM._service.release();Battle._service.release();f.close();G.release()
end
Tasks.spawn,Tasks.draw,VM.launch=spawn,draw,launch;package.loaded['src.core.Game']=original
local function retiredTask()
 local f=require('tools.battle-source-runtime.fixture').new('firered');local game=f.game
 package.loaded['src.core.Game']=game;game.data.constants.gen3BattleAnimGfx={}
 local wave={at=0,life=134,waitLife=136,player={image='owned wave',dx=-2,dy=1},
  opponent={image='owned wave',dx=2,dy=-1},visualTask=meta('surf',0,1,2)}
 game.data.moves.MOVE_033.anim={surf=wave}
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b)
 local player=b.gen3Anim;player:start('MOVE_033',true,0,1,nil,b)
 local task=Tasks._pool[1];local ownedScene={}
 local function painter(scene)return function()return scene end end
 task.draw=painter(ownedScene)
 local weak=setmetatable({game,game.save,game.data,b,player,ownedScene},{__mode='v'})
 T.eq(task.active,true);game.stack:pop();T.eq(task.active,false,'real native exit retires a live task')
 T.eq(task.data[2],nil);T.eq(task.ga[0],nil);T.eq(task._scan[1],nil)
 task.draw=nil;T.raises(function()task.draw=function()end end,'retired')
 Tasks._service.release();VM._service.release();Battle._service.release();f.close();G.release()
 package.loaded['src.core.Game']=original
 return task,weak
end
local retained,weak=retiredTask()
require('src.render.Font').load(T.fixtures.fresh())
for _=1,4 do collectgarbage('collect')end
for i=1,6 do T.eq(weak[i],nil,'retained task releases native/scene owner '..i)end
T.eq(retained.active,false);T.eq(retained.name,'AnimTask_CreateSurfWave')
T.finish('decoded native task births, borrowed Surf drawing and shared lifetimes')
