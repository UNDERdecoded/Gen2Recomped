package.path='./?.lua;./?/init.lua;'..package.path
local basePairs,baseNext=pairs,next
local T=require('tests.modkit') -- Loader installs iteration before mod journals.
local Iteration=require('src.compat.gen1.TableIteration')
local Views=require('src.compat.gen1.SessionView')
local Version=require('src.core.GameVersion')
local G3=require('src.script.Gen3Commands')
local function copy(v,seen)
  if type(v)~='table'then return v end
  seen=seen or{};if seen[v]then return seen[v]end
  local out={};seen[v]=out;for k,x in pairs(v)do out[copy(k,seen)]=copy(x,seen)end;return out
end
-- Ordinary tables retain the host semantics, including ignored __pairs.
local ordinary=setmetatable({a=1,b=false},{__pairs=function()return baseNext,{metamethod=true},nil end})
local function collect(iter,state,key)local out={};for k,v in iter,state,key do out[k]=v end;return out end
T.same(collect(pairs(ordinary)),collect(basePairs(ordinary)))
local first=baseNext(ordinary);T.eq(next(ordinary),first);T.eq(next(ordinary,first),baseNext(ordinary,first))
T.raises(function()pairs(17)end,'table expected','ordinary invalid pairs input keeps its native failure')
-- The registry cannot retain an otherwise unreachable view.
local weak=setmetatable({},{__mode='v'})
do local v={};weak[1]=v;Iteration.register(v,function()return{one=1}end)end
collectgarbage('collect');collectgarbage('collect');T.eq(weak[1],nil)
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  local f=require('tools.session-runtime.fixture').new(edition);local game=f.game
  game.save.flags={FLAG_G3_0807=true,FLAG_G3_0808=false,NATIVE_ONLY=true}
  game.save.gen3Vars={[0x4075]=37,[0x4076]=9,[0x8000]=12,[0x8015]=13}
  local s=assert(Views.new(game));local flags,vars=s.flags,s.vars
  T.check(flags~=game.save.flags);T.check(vars~=game.save.gen3Vars)
  T.eq(flags[0x807],true);T.eq(flags['2056'],false);T.eq(flags[0x809],nil)
  T.eq(vars[0x4075],37);T.eq(vars[0x8000],nil);T.eq(vars.unrecognized,nil)
  T.same(collect(pairs(flags)),{[0x807]=true,[0x808]=false},'source iteration exposes numeric flag state only')
  local frlg=edition=='firered'or edition=='leafgreen'
  local expected={[0x4075]=37,[0x4076]=9};if frlg then expected[0x8015]=13 end
  T.same(collect(pairs(vars)),expected)
  T.same(collect(next,flags,nil),collect(pairs(flags)),'direct next uses the native numeric flag cursor')
  T.same(collect(next,vars,nil),expected,'direct next skips context-owned special variables')
  flags[0x807]=nil;T.eq(game.save.flags.FLAG_G3_0807,false);T.eq(flags[0x807],false)
  flags['0x808']=true;T.eq(game.save.flags.FLAG_G3_0808,true)
  vars[0x4010]=89;T.eq(game.save.gen3ObjectSprites[0],89)
  vars[0x4010]=nil;T.eq(game.save.gen3ObjectSprites[0],nil)
  -- Deleting the current key while using next must retain the native cursor,
  -- rather than reconstructing an incompatible table on every call.
  local walked=0;local k=next(vars)
  while k do vars[k]=nil;walked=walked+1;k=next(vars,k)end
  T.eq(walked,frlg and 3 or 2);T.eq(vars[0x8000],nil);T.eq(game.save.gen3Vars[0x8000],12)
  vars[0x4075]=41;G3.setVar(game.save,0x4075,42);T.eq(vars[0x4075],42)
  local iter,state,start=pairs(vars);vars[0x4075]=43
  T.eq(collect(iter,state,start)[0x4075],42,'pairs freezes its own scalar iteration values')
  T.eq(vars[0x4075],43)
  -- Whole-field assignment is a typed native replacement, not a borrowed map.
  s.flags={[0x809]=true};T.eq(flags[0x807],false);T.eq(flags[0x808],false);T.eq(flags[0x809],true)
  T.eq(game.save.flags.NATIVE_ONLY,true,'replacing source flags preserves native-only names')
  s.vars={['0x4010']=7,[0x4076]=65537}
  T.eq(vars[0x4075],nil);T.eq(vars[0x4076],1);T.eq(game.save.gen3ObjectSprites[0],7)
  T.eq(game.save.gen3Vars[0x8000],12,'persistent replacements never clear native special variables')
  local before=copy(s.flags);local nativeVars=copy(game.save.gen3Vars)
  T.raises(function()s.flags={[0x809]=false,[0x810]='bad'}end,'invalid script flag','replacement validates before mutation')
  T.same(copy(s.flags),before)
  T.raises(function()s.vars={[0x4076]=2,[0x8000]=0}end,'invalid persistent','special variables cannot be persisted')
  T.same(game.save.gen3Vars,nativeVars)
  T.raises(function()vars[0x8000]=1 end,'invalid persistent','context variables reject persistent writes')
  T.raises(function()s.flags={[0x809]=true,['2057']=false}end,'conflicting','ambiguous aliases reject before mutation')
  local snapshot=copy(s)
  T.eq(snapshot.version,edition);T.eq(snapshot.flags[0x809],true);T.eq(snapshot.vars[0x4076],1)
  snapshot.flags[0x809]=false;snapshot.vars[0x4076]=999
  T.eq(flags[0x809],true);T.eq(vars[0x4076],1,'unchanged recursive-copy code obtains detached numeric state')
  s.previewMarker={value=1};T.eq(copy(s).previewMarker.value,1)
  local oldClock=copy(s).playTime;game.save.playTime=9000;T.eq(oldClock.hours,1,'enumerated playtime is detached')
  Views.release(s)
  T.raises(function()flags[0x809]=false end,'retired','retained maps cannot write after session release')
  T.raises(function()pairs(vars)end,'retired','retained maps cannot enumerate after session release')
end
-- A native peer may wrap pairs normally. Entry rollback must keep the engine
-- dispatcher and another mod's wrapper while taking back the failed wrapper.
local f=require('tools.session-runtime.fixture').new('emerald')
local session=assert(Views.new(f.game));f.game.save.gen3Vars={[0x4075]=37}
local J=require('src.link.Json');local files={}
local api=require('src.core.Version').modApi
local function mod(id,priority,body)
  files['mods/'..id..'/manifest.json']=J.encode({id=id,name=id,version='1.0.0',api=api,entry='main.lua',priority=priority,permissions={'engine_internals'}})
  files['mods/'..id..'/main.lua']=body
end
mod('native_pairs_peer',0,[[local mod=...;local old=pairs;mod.exports.old=old;pairs=function(...)return old(...)end]])
mod('failed_pairs',100,[[pairs=function()error('failed pairs wrapper survived')end;error('intentional iteration entry failure')]])
local enginePairs=pairs
local run=T.sdk.loadMods({'mods/native_pairs_peer','mods/failed_pairs'},{fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
T.eq(#run.errors,1);T.eq(copy(session.vars)[0x4075],37)
T.eq(run.loader.exports.native_pairs_peer.old,enginePairs,'mod snapshots see infrastructure as their baseline')
require('src.mods.Loader').teardown();T.eq(pairs,enginePairs,'native wrappers unwind back to the dispatcher')
T.same(collect(pairs(ordinary)),collect(basePairs(ordinary)))
run.release();Views.release(session)
Version.set('crystal')
T.finish('native numeric session schemas and view iteration')
