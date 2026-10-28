package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Probe=dofile('tests/native_action_plan/turn.lua')
local Json=require('src.link.Json')
local G=require('src.core.Game3')
local B=require('src.core.game3.battle')
local Hooks=require('src.mods.Hooks')
local Runtime=require('src.mods.Runtime')
local saved={Runtime.events,Runtime.hooks,Runtime.errors,Hooks.lean}
local entry=[[
 local mod=...
 local B=require('src.core.game3.battle')
 local e=mod.exports;e.mode='identity'
 mod.hooks:wrap('core.update',function(nextFn,g,dt)local value=nextFn(g,dt);e.corePost=true;return value end)
 mod.hooks:wrap('battle.damage',function(nextFn,c)
  e.sameBattle=c.battle==B.getState();e.user=c.user.id;e.target=c.target.id
  e.rng=c.rng;e.moveNum=c.moveNum
  if e.mode=='yield-after'then
   local value=nextFn(c);coroutine.yield('contact')
   c.target.mon.hp=c.target.mon.hp-7;return value
  elseif e.mode=='yield-next'or e.mode=='yield-return'then
   coroutine.yield('contact')
   c.target.mon.hp=c.target.mon.hp-7
   if e.mode=='yield-return'then return 13 end
  elseif e.mode=='copy'then
   local copy={};for k,v in pairs(c)do copy[k]=v end
   copy.rng=function(lo,hi)e.wrapped=(e.wrapped or 0)+1;return c.rng(lo,hi)end
   local ok,value=pcall(nextFn,copy);e.copyOk=ok;e.copyError=not ok and tostring(value)or nil
   if not ok then error(value,0)end
   return value
  end
  return nextFn(c)
 end)
]]
local function open(edition,body)
 local f,b=Probe.open(edition);b:syncSides()
 local files={['mods/source_probe/manifest.json']=Json.encode({id='source_probe',name='Probe',version='1.0.0',
  api=3,entry='main.lua',games={'gen3'},permissions={'engine_internals'}}),['mods/source_probe/main.lua']=body or entry}
 local run=T.sdk.loadMods({'mods/source_probe'},{data=f.data,fs=T.sdk.memfs(files)})
 T.eq(#run.errors,0);f.game.mods=run.loader;run.loader.game=f.game
 local e=assert(run.loader.exports.source_probe)
 local rolls=0
 local c={battle=b,user=b.player,target=b.enemy,move=f.data.moves.MOVE_033,moveId='MOVE_033',
  rng=function(lo)rolls=rolls+1;return lo end}
 return f,b,run,e,c,function()return rolls end
end
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 local f,b,run,e,c,rolls=open(edition);local calls=0;local nativeRng=c.rng
 local function native(raw)
  calls=calls+1;T.eq(raw.battle,b);T.eq(raw.user,b.player);T.eq(raw.target,b.enemy)
  return raw.rng(2,5)
 end
 T.eq(run.loader.hooks:call('battle.damage',native,c),2)
 T.eq(e.sameBattle,true,'source callbacks share the actual admitted battle identity')
 T.eq(e.user,0,'source battler callback identifies the actual native player slot')
 T.eq(e.target,1,'source battler callback identifies the actual native enemy slot')
 T.eq(e.moveNum,33,'source move numbers come from the actual native imported definition')
 T.eq(calls,1);T.eq(rolls(),1)
 local count=rolls();T.eq(pcall(e.rng,1,2),false,'retained callback RNG closes with its transaction')
 T.eq(rolls(),count,'closed callback cannot advance native RNG')
 e.mode='copy';T.eq(run.loader.hooks:call('battle.damage',native,c),2)
 T.eq(e.copyOk,true,'a bound source context copy can decorate its native RNG')
 T.eq(e.wrapped,1);T.eq(calls,2)
 T.eq(c.rng,nativeRng,'source RNG replacement is scoped to its native invocation')
 f.game.stack:pop();B._service.release()
 local replacement=require('src.mods.Merge').deepCopy(f.game.save)
 T.eq(run.loader.hooks:call('core.update',function(raw)
  T.eq(raw,f.game);raw.save=replacement;return 29
 end,f.game,1/60),29,'native-handle callback permits a genuine native save transition')
 T.eq(e.corePost,true,'native save transition is not misreported as a record-transaction error')
 T.eq(f.game.save,replacement)

 Probe.close(f)
end
for _,lean in ipairs(Hooks.callLean and{false,true}or{false})do for _,mode in ipairs{'yield-next','yield-return','yield-after'}do
 Hooks.lean=lean
 local f,b,run,e,c,rolls=open('emerald');e.mode=mode
 local co;local calls=0
 G._withCallbackOwner('native-root',function()
  co=coroutine.create(function()
   local damage=run.loader.hooks:call('battle.damage',function(raw)
    calls=calls+1;raw.rng(0,1);return 10
   end,c)
   b.enemy.mon.hp=b.enemy.mon.hp-damage
   return damage
  end)
  local ok,value=coroutine.resume(co);T.eq(ok,true);T.eq(value,'contact')
 end)
 local hp=b.enemy.mon.hp;local count=rolls();local beforeCalls=calls
 T.eq(pcall(e.rng,1,2),false,'suspended callback RNG is unavailable to an independent caller')
 T.eq(rolls(),count)
 local ok,why=coroutine.resume(co)
 T.eq(ok,false,mode..' cannot complete an expired native hook')
 T.eq(tostring(why):find('retired',1,true)~=nil,true)
 T.eq(b.enemy.mon.hp,hp,'revoked source commit cannot write native HP')
 T.eq(rolls(),count,'revoked hook fallback cannot consume native RNG')
 T.eq(calls,beforeCalls,'revoked hook fallback cannot execute or retry the native body')
 Probe.close(f)
end end
-- Native API3 consumers and follower-only attribution keep their raw handles.
for _,kind in ipairs{'native','follower'}do
 local body=(kind=='follower'and"require('src.compat.game3.Follower')\n"or'')..[[
  local mod=...;local e=mod.exports
  mod.events:on('game.ready',function(p)e.event=p end)
  mod.hooks:wrap('battle.damage',function(nextFn,c)
   e.battle,e.user,e.rng=c.battle,c.user.id,c.rng;return nextFn(c)
  end)
 ]]
 local f,b,run,e,c,rolls=open('emerald',body)
 local nativeRng=c.rng
 run.loader.hooks:call('battle.damage',function(raw)T.eq(raw.battle,b);return raw.rng(0,1)end,c)
 T.eq(e.battle,b);T.eq(e.user,b.player.id,'native consumer battler ID ABI is preserved')
 T.eq(e.rng,nativeRng,'native consumer RNG handle ABI is preserved')
 T.eq(c.rng,nativeRng)
 local payload={game=f.game};run.loader.events:emit('game.ready',payload)
 T.eq(e.event,payload,'native/follower-only event payload identity is preserved')
 T.eq(e.event.game,f.game,'native/follower-only events keep native Game handles')
 Probe.close(f)
end
-- Complete native turns: the same Loader/API3 setup with a native versus
-- source namespace pass-through must retain every HP/PP/RNG/frame record.
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 local traces={}
 for _,source in ipairs{false,true}do
  Runtime.install(saved[1],saved[2],saved[3]);G.release()
  traces[#traces+1]=Probe.turn(edition,true,function(f,b)
   local body=source and entry or[[local mod=...;mod.hooks:wrap('battle.damage',function(nextFn,c)return nextFn(c)end)]]
   local files={['mods/turn_probe/manifest.json']=Json.encode({id='turn_probe',name='Turn probe',version='1.0.0',
    api=3,entry='main.lua',games={'gen3'},permissions={'engine_internals'}}),['mods/turn_probe/main.lua']=body}
   local run=T.sdk.loadMods({'mods/turn_probe'},{data=f.data,fs=T.sdk.memfs(files)})
   T.eq(#run.errors,0);f.game.mods=run.loader;run.loader.game=f.game
  end)
 end
 T.same(traces[1],traces[2],edition..' source pass-through retains complete native turn HP/PP/RNG/frame traces')
end
Runtime.install(saved[1],saved[2],saved[3]);Hooks.lean=saved[4]
T.finish('Actual source callback identities, bound context copies, RNG lifetime and pre-commit/fallback retirement')
