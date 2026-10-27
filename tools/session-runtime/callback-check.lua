package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Json=require('src.link.Json')
local F=require('tools.session-runtime.fixture')
local f=F.new('emerald');local native=f.game
local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
assert(api==2 or api==3,'session callback probe requires API 2 or 3')
T.eq(package.loaded['src.core.Game3'],nil,'first runtime import also exercises automatic facade journaling')
local files={}
local function mod(id,priority,body)
 files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,
   entry='main.lua',games={'gen3'},priority=priority,permissions={'engine_internals'}})
 files['mods/'..id..'/main.lua']=body
end
mod('bad_source',200,[[
 local mod=...
 require('src.core.game3.runtime')
 require('src.core.Game3').update=function()error('rolled back source wrapper')end
 error('intentional source entry failure')
]])
mod('source_game',100,[[
 local mod=...
 local R=require('src.core.game3.runtime')
 local G=require('src.core.Game3')
 local base=G.update;mod.exports.base=base;mod.exports.frames=0
 G.update=function(g,dt)mod.exports.frames=mod.exports.frames+1;return base(g,dt)end
 mod.events:on('game.ready',function(p)
  mod.exports.payload=p;mod.exports.game=p.game;mod.exports.phase=p.phase
  R.defer(function()
   R.defer(function()error('nested source deferred failure')end)
  end)
 end)
 mod.events:on('save.created',function(p)mod.exports.save=p.save end)
 mod.events:on('save.loading',function(p)mod.exports.raw=p.raw end)
 mod.events:on('mod.native_peer.probe',function(p)mod.exports.custom=p end)
 mod.hooks:wrap('core.update',function(nextFn,game,dt,...)
  assert(game==mod.exports.game,'source hook game differs from source ready handle')
  local value,a,b=nextFn(game,dt,...)
  assert(value==game and a==nil and b=='native result','source next did not project native results')
  return value,a,b
 end,100)
 mod.hooks:wrap('input.step',function(nextFn,game,dt)
  nextFn(game,dt)
  error('intentional source post-next failure')
 end,100)
]])
mod('native_peer',0,[[
 local mod=...
 mod.events:on('game.ready',function(p)mod.exports.payload=p;mod.exports.game=p.game end)
 mod.events:on('save.created',function(p)mod.exports.save=p.save end)
 mod.hooks:wrap('core.update',function(nextFn,game,...)
  mod.exports.hookGame=game
  return nextFn(game,...)
 end,0)
]])
local run=T.sdk.loadMods({'mods/bad_source','mods/source_game','mods/native_peer'},
 {data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
T.eq(#run.errors,1,'intentional failed source mod is the only entry error')
T.check(run.loader.exports.source_game~=nil)
local G=require('src.core.Game3');local R=require('src.core.game3.runtime')
T.eq(G._usesCallbacks('bad_source'),false,'rollback retires namespace callback selection')
T.eq(G._usesCallbacks('source_game'),true);T.eq(G._usesCallbacks('native_peer'),false)
native.mods=run.loader;run.loader.game=native
local src,peer=run.loader.exports.source_game,run.loader.exports.native_peer
local payload=setmetatable({game=native},{__index=native})
run.loader.events:emit('game.ready',payload)
local view=G.forNative(native)
T.eq(src.game,view);T.eq(src.phase,'field');T.eq(src.payload.input,native.input)
T.eq(peer.game,native);T.eq(peer.payload,payload,'native peer receives the exact original event object')
T.eq(payload.game,native);T.eq(rawget(payload,'phase'),nil,'projection cannot rewrite a shared payload')
local copies={save=native.save};run.loader.events:emit('save.created',copies)
T.eq(src.save,view.session);T.eq(peer.save,native.save);T.eq(copies.save,native.save)
local loaded={player={map='TEST',name='LOADED',id=51},playTime=12,options={}}
run.loader.events:emit('save.loading',{raw=loaded})
T.eq(src.raw.name,'LOADED');src.raw.money=7;T.eq(loaded.money,7,'typed loading view targets only its supplied raw save')
T.eq(native.save.money,300)
local custom={game=native};run.loader.events:emit('mod.native_peer.probe',custom)
T.eq(src.custom,custom,'custom event payload contracts remain unchanged')
local resource={gpu='not a game'};local vanilla=0
local value,a,b=run.loader.hooks:call('core.update',function(game,dt,empty,texture)
 T.eq(game,native);T.eq(dt,.125);T.eq(empty,nil);T.eq(texture,resource)
 T.eq(G._callbackOwner(),nil,'native downstream code does not inherit a source callback owner')
 vanilla=vanilla+1;return game,nil,'native result'
end,native,.125,nil,resource)
T.eq(value,native);T.eq(a,nil);T.eq(b,'native result');T.eq(vanilla,1);T.eq(peer.hookGame,native)
local calls=0
value,a,b=run.loader.hooks:call('input.step',function(game)
 T.eq(game,native);calls=calls+1;return 41,nil,9
end,native,1/60)
T.eq(value,41);T.eq(a,nil);T.eq(b,9);T.eq(calls,1,'a source post-next error cannot retry the native body')
T.eq(G._callbackOwner(),nil,'callback failures restore owner context')
T.eq(G._dispatch('update',native,function(owner,dt)T.eq(owner,native);return dt end,.25),.25)
T.eq(src.frames,1,'a failed first runtime import did not leave its facade wrapper installed')
-- The real Game:_step boundary preserves callback attribution across batches.
local Touch=require('src.core.TouchControls');local poll=Touch.pollTouches;Touch.pollTouches=function()end
local errors=#run.errors
native:_step(1/60);native:_step(1/60)
T.eq(#run.errors,errors+1);T.check(run.errors[#run.errors]:find('source_game:',1,true)~=nil)
T.check(run.errors[#run.errors]:find('nested source deferred failure',1,true)~=nil)
-- Native desktop touch synthesis must not become a second source touch.
local baseTouch,baseMouse=G.touchpressed,G.mousepressed
local visible,press=Touch.visible,Touch.touchpressed
local nativeTouches,sourceTouches,sourceMouse=0,0,0
Touch.visible=function()return false end
Touch.touchpressed=function()nativeTouches=nativeTouches+1 end
G.touchpressed=function(game,...)sourceTouches=sourceTouches+1;return baseTouch(game,...)end
G.mousepressed=function(game,...)sourceMouse=sourceMouse+1;return baseMouse(game,...)end
G._pointer('mousepressed',native,function(x,y)native:touchpressed('mouse',x,y)end,10,11,1,false)
T.eq(nativeTouches,1);T.eq(sourceMouse,1);T.eq(sourceTouches,0)
native:touchpressed(42,10,11);T.eq(nativeTouches,2);T.eq(sourceTouches,1)
T.raises(function()G._pointer('mousepressed',native,function()error('intentional native pointer failure')end,1,2,1,false)end,'intentional native pointer failure')
native:touchpressed('mouse',10,11);T.eq(sourceTouches,2,'pointer failure cannot leak synthetic-touch suppression')
G.touchpressed,G.mousepressed=baseTouch,baseMouse
Touch.visible,Touch.touchpressed,Touch.pollTouches=visible,press,poll
require('src.mods.Loader').teardown()
T.eq(G._usesCallbacks('source_game'),false);T.eq(G.update,src.base)
T.eq(R.isActive(),false)
run.release()
T.finish('source game callbacks with a native peer through SDK API '..api)
