-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local VM=require('src.core.game3.battle.anim_vm')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local launch,update=VM.launch,VM.update
local original=package.loaded['src.core.Game']
local function pack(...)return{n=select('#',...),...}end
T.eq(launch({}),nil);T.eq(update({}),nil)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 local game=f.game;package.loaded['src.core.Game']=game
 game.data.constants.gen3BattleAnimGfx={}
 game.data.moves.MOVE_033.anim={duration=4,shakes={{at=0,duration=4,x=2,y=1}}}
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b);b.phase='QA_IDLE'
 local native=b.gen3Anim;T.neq(native,nil)
 local l,u=0,0;local handle
 VM.launch=function(view)
  l=l+1;handle=view;T.neq(view,native);T.eq(view.data,nil);T.eq(view.game,nil)
  T.eq(launch(view),true);return launch(view)
 end
 T.eq(native:start('MOVE_033',true,0,1,nil,b),true);T.eq(l,1)
 T.eq(handle:attackerId(),0);T.eq(handle:targetId(),1);T.eq(handle.frame,0)
 T.raises(function()handle.frame=50 end,'read-only')
 local id=handle.attackerId;local frame=b.frame;local hp=b.enemy.mon.hp
 VM.update=function(view)u=u+1;T.eq(view,handle);update(view);return update(view)end
 native:update();T.eq(u,1);T.eq(native.frame,1);T.eq(b.frame,frame);T.eq(b.enemy.mon.hp,hp)
 T.eq(update(handle),nil);T.eq(native.frame,1,'source query between phases cannot tick')
 VM.update=function()return false end;native:update();T.eq(native.frame,1,'held callback preserves native animation time')
 VM.update=function()error('source vm update')end
 T.raises(function()native:update()end,'source vm update');T.eq(native.frame,1)
 VM.update=function(view)game.stack:push({});local a,why=update(view);game.stack:pop();return a,why end
 local a,why=native:update();T.eq(a,false);T.eq(why,'native animation admission changed');T.eq(native.frame,1)
 VM.update=function(view)
  local save=game.save;game.save={};local a,why=update(view);game.save=save;return a,why
 end
 a,why=native:update();T.eq(a,false);T.eq(why,'native animation admission changed');T.eq(native.frame,1)
 T.eq(handle.frame,nil,'old handle cannot observe a replacement session');T.eq(id(),nil)
 -- Rebind through the real player after a new native admission.
 VM.launch=function(view)handle=view;return launch(view)end
 T.eq(native:start('MOVE_033',false,1,0,nil,b),true)
 T.eq(handle:attackerId(),1);T.eq(handle:targetId(),0)
 local old=handle;local oldId=old.attackerId
 T.eq(native:start('MOVE_033',true,2,3,nil,b),true)
 T.neq(handle,old,'each native launch gets a fresh presentation identity')
 T.eq(old.frame,nil);T.eq(oldId(),nil);T.eq(handle:attackerId(),2);T.eq(handle:targetId(),3)
 VM.update=function()return update(old)end
 a,why=native:update();T.eq(a,false);T.eq(why,'native animation admission changed');T.eq(native.frame,0)
 -- Dispatch preserves return arity and makes native failures sticky even
 -- if a wrapper catches a failed base call and tries it again.
 VM.update=function(view)local r=pack(update(view));T.eq(r.n,3);return update(view)end
 local calls=0
 local r=pack(VM._nativeUpdate(native,function()calls=calls+1;return 7,nil,nil end))
 T.eq(r.n,3);T.eq(r[1],7);T.eq(calls,1)
 VM.update=function(view)pcall(update,view);pcall(update,view);return true end
 T.raises(function()VM._nativeUpdate(native,function()calls=calls+1;error('native vm failed')end)end,'native vm failed')
 T.eq(calls,2)
 VM.update=function(view)return update(view)end
 game.stack:push({});a,why=native:update();game.stack:pop()
 T.eq(a,false);T.eq(why,'native animation is covered')
 local seams=require('src.mods.ModSeams');local owner=G._callbackOwner()
 VM.update=function(view)T.eq(G._callbackOwner(),'vm_owner');return update(view)end
 seams._journal[#seams._journal+1]={tbl=VM,key='update',after=VM.update,owner='vm_owner'}
 native:update();table.remove(seams._journal);T.eq(G._callbackOwner(),owner)
 require('src.core.game3.asset_stream').cancelOwner('unrelated_vm_owner');T.neq(handle.frame,nil)
 require('src.core.game3.asset_stream').cancelOwner('vm_owner');T.eq(handle.frame,nil)
 VM.launch,VM.update=launch,update
 game.stack:pop();VM._service.release();Battle._service.release();f.close();G.release()
 local function trace(mode)
  if mode=='absent'then package.loaded['src.core.game3.battle.anim_vm']=nil
  else package.loaded['src.core.game3.battle.anim_vm']=VM end
  T.eq(package.loaded['src.core.game3.battle.anim_vm']==nil,mode=='absent','control actually excludes the source module')
  local fixture=require('tools.battle-source-runtime.fixture').new(edition)
  local game=fixture.game;package.loaded['src.core.Game']=game
  game.data.constants.gen3BattleAnimGfx={}
  game.data.moves.MOVE_033.anim={duration=4,shakes={{at=0,duration=4,x=2,y=1}}}
  local state=fixture.fresh('TACKLE').battle;state.enter=false;game.stack:push(state);state.phase='QA_IDLE'
  if mode=='wrapped'then
   VM.launch=function(v)launch(v);return launch(v)end
   VM.update=function(v)update(v);return update(v)end
  end
  local player=state.gen3Anim;local rows={}
  T.eq(player:start('MOVE_033',true,0,1,nil,state),true)
  for i=1,16 do
   player:update();rows[i]={frame=player.frame,done=player:isDone(),clock=state.frame,
    hp=state.player.mon.hp,pp=state.player.mon.moves[1].pp}
  end
  VM.launch,VM.update=launch,update;game.stack:pop();VM._service.release()
  Battle._service.release();fixture.close();G.release()
  return rows
 end
 local baseline=trace('absent');T.same(trace('default'),baseline,'default module preserves every native script frame')
 T.same(trace('wrapped'),baseline,'repeated base calls preserve every native script frame')
 package.loaded['src.core.game3.battle.anim_vm']=VM
end
VM.launch,VM.update=launch,update;package.loaded['src.core.Game']=original
local function retiredHandle()
 local f=require('tools.battle-source-runtime.fixture').new('firered');local game=f.game
 package.loaded['src.core.Game']=game;game.data.constants.gen3BattleAnimGfx={}
 game.data.moves.MOVE_033.anim={duration=4,shakes={{at=0,duration=4,x=2,y=1}}}
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b)
 local player=b.gen3Anim;local handle
 VM.launch=function(v)handle=v;return launch(v)end
 player:start('MOVE_033',true,0,1,nil,b)
 local id=handle.attackerId
 local weak=setmetatable({game,game.save,game.data,b,player},{__mode='v'})
 VM.launch=launch;game.stack:pop();VM._service.release();Battle._service.release();f.close();G.release()
 package.loaded['src.core.Game']=original
 return handle,id,weak
end
local retained,id,weak=retiredHandle()
-- Font.load intentionally retains its current dataset process-wide. Move
-- that unrelated fixture cache to a fresh dataset before testing ownership
-- through the retained VM handle; all five weak-owner checks still apply.
require('src.render.Font').load(T.fixtures.fresh())
for _=1,4 do collectgarbage('collect')end
for i=1,5 do T.eq(weak[i],nil,'retained animation handle releases native owner '..i)end
T.eq(retained.frame,nil);T.eq(id(),nil)
T.finish('native animation launch/update borrowing, handle retirement and single script clock')
