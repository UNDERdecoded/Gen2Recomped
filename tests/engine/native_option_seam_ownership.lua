package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Runtime=require('src.mods.Runtime')
local Seams=require('src.mods.ModSeams')
local B=require('src.core.game3.battle')
local E=require('src.core.game3.battle.engine')
local G=require('src.core.Game3')
local Call=require('src.compat.gen1.SourceCall')
local Manager=require('src.mods.ManagerState')
local Json=require('src.link.Json')
local originalB,originalE,originalDraw=B.update,E.resolveMove,B.draw
local body=[[
 local mod=...;local e=mod.exports
 mod.options:define{{key='enabled',type='toggle',default=false},{key='fault',type='action',label='FAULT'}}
 local function install()
  local B=require('src.core.game3.battle');local E=require('src.core.game3.battle.engine')
  if e.update then return end
  local oldB,oldE=B.update,E.resolveMove
  e.oldB,e.oldE=oldB,oldE
  e.update=function(...)e.calls=(e.calls or 0)+1;return oldB(...)end
  e.resolve=function(...)return oldE(...)end
  B.update,E.resolveMove=e.update,e.resolve
 end
 mod.events:on('mod.options_changed',function(p)
  if p.mod~=mod.id or p.key~='enabled'then return end
  e.thread=coroutine.running()
  if p.value then install()
  else
   local B=require('src.core.game3.battle');local E=require('src.core.game3.battle.engine')
   if B.update==e.update then B.update=e.oldB end
   if E.resolveMove==e.resolve then E.resolveMove=e.oldE end
   e.update,e.resolve=nil,nil
  end
 end)
 mod.events:on('mod.option_action',function(p)
  if p.mod~=mod.id or p.key~='fault'then return end
  local B=require('src.core.game3.battle');local previous=B.draw
  e.draw=function(...)return previous(...)end;B.draw=e.draw
  error('owned option failure')
 end)
]]
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald','crystal'}do
 Version.set(edition)
 local api=edition=='crystal'and 2 or 3
 local files={['mods/option_probe/manifest.json']=Json.encode{id='option_probe',name='Option probe',version='1.0.0',api=api,entry='main.lua'},['mods/option_probe/main.lua']=body}
 local run=T.sdk.loadMods({'mods/option_probe'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
 T.eq(#run.errors,0)
 local e=assert(run.loader.exports.option_probe)
 local writes=0
 local game={mods=run.loader,save={options={}},writeOptions=function()writes=writes+1 end}
 local manager=Manager.new(game)
 local before=Seams.summary().option_probe or 0
 T.eq(B.update,originalB,'entry itself installs no battle wrapper')
 manager:setOption('option_probe','enabled',true)
 T.eq(e.thread,coroutine.running(),'synchronous native option callbacks keep the caller coroutine')
 T.eq(B.update,e.update);T.eq(E.resolveMove,e.resolve)
 T.eq(Call.owner(B,'update'),'option_probe','late native update wrapper has its actual SDK owner')
 T.eq(Call.owner(E,'resolveMove'),'option_probe','late resolver wrapper has its actual SDK owner')
 T.eq(writes,1,'the real manager producer invokes only the owned persistence seam')
 if api==3 then T.eq(G._usesSourceRecords('option_probe'),true,'late namespace imports declare the source ABI')end
 manager:setOption('option_probe','enabled',false)
 T.eq(B.update,originalB);T.eq(E.resolveMove,originalE)
 manager:setOption('option_probe','enabled',true)
 local rows=manager:buildOptionRows({id='option_probe'},{{key='fault',type='action',label='FAULT'}})
 local action
 for _,row in ipairs(rows)do if row.id=='fault'then action=row end end
 T.check(action and type(action.activate)=='function')
 T.eq(action.activate(),true,'real native action row contains callback failures')
 T.eq(B.draw,e.draw);T.eq(#run.errors,1,'existing diagnostics retain the option failure')
 Seams.unwindOwner('option_probe')
 T.eq(B.draw,originalDraw,'a partial option action remains attributable for cleanup')
 T.eq(B.update,originalB);T.eq(E.resolveMove,originalE)
 -- A later foreign replacement cannot be torn off by this owner's unwind.
 manager:setOption('option_probe','enabled',false)
 manager:setOption('option_probe','enabled',true)
 local own=e.update;local foreign=function(...)return own(...)end;B.update=foreign
 Seams.unwindOwner('option_probe')
 T.eq(B.update,foreign,'owner retirement preserves a foreign later replacement')
 -- Both functions here belong only to this owned fixture.
 B.update,E.resolveMove=originalB,originalE
 run.release()
end
-- Native load-time events also retain the real subscriber, rather than a
-- shared lifecycle label that would mask a later installed battle controller.
Version.set('emerald')
do
 local run=T.sdk.loadMods({'mods/init_probe'},{data=T.fixtures.fresh(),fs=T.sdk.memfs({
  ['mods/init_probe/manifest.json']=Json.encode{id='init_probe',name='Init probe',version='1.0.0',api=3,entry='main.lua'},
  ['mods/init_probe/main.lua']=[[
   local mod=...;local e=mod.exports
   mod.events:on('mods.loaded',function()
    local B=require('src.core.game3.battle');local old=B.update
    e.update=function(...)return old(...)end;B.update=e.update
   end)
   mod.events:on('game.ready',function()
    local E=require('src.core.game3.battle.engine');local old=E.resolveMove
    e.resolve=function(...)return old(...)end;E.resolveMove=e.resolve
    e.thread=coroutine.running()
   end)
  ]],
 })})
 T.eq(#run.errors,0)
 T.eq(Call.owner(B,'update'),'init_probe','real Loader mods.loaded producer preserves subscriber ownership')
 run.loader.events:emit('game.ready',{})
 T.eq(Call.owner(E,'resolveMove'),'init_probe','game.ready subscriber owns its actual late resolver')
 T.eq(run.loader.exports.init_probe.thread,coroutine.running())
 Seams.unwindOwner('init_probe');T.eq(B.update,originalB);T.eq(E.resolveMove,originalE)
 run.release()
end
-- A retained require has no authority after its snapshot window closes, and
-- must not retain the engine snapshot it originally captured.
Version.set('emerald')
local marker={};local weak=setmetatable({marker},{__mode='v'})
local module={anchor=marker};package.loaded['src.qa.OptionWindowProbe']=module
local token=Seams.open('expired-window');local retained=require
module.anchor=nil;marker=nil
Seams.close(token);T.eq(Seams.close(token),0,'window close is idempotent');token=nil
for _=1,5 do collectgarbage('collect')end
T.eq(weak[1],nil,'retained require does not root closed native snapshot bytes')
G._retireMod('expired-window');retained('src.core.game3.battle.engine')
T.eq(G._usesSourceRecords('expired-window'),false,'closed require cannot re-admit a retired owner')
package.loaded['src.qa.OptionWindowProbe']=nil
local closing
local closeName='src.core.game3.battle.qa_close_during_require'
package.preload[closeName]=function()Seams.close(closing);return{}end
G._retireMod('close-in-require');closing=Seams.open('close-in-require')
local result=require(closeName)
T.eq(type(result),'table');T.eq(G._usesSourceRecords('close-in-require'),false,'require completion cannot re-admit a window closed during module loading')
package.preload[closeName],package.loaded[closeName]=nil,nil
local function pack(...)return{n=select('#',...),...}end
local r=pack(Seams.run('tuple',function()return nil,7,nil end))
T.eq(r.n,4);T.eq(r[1],true);T.eq(r[2],nil);T.eq(r[3],7);T.eq(r[4],nil)
-- Frame buses and coroutine callbacks keep their original paths and ABI.
local Events=require('src.mods.Events');local bus=Events.new();local errors={}
Runtime.install(bus,Runtime.hooks,errors)
local opens=0;local open=Seams.open
Seams.open=function(...)opens=opens+1;return open(...)end
local same
bus:on('world.tick',function()end,0,'plain')
for _=1,20 do bus:emit('world.tick',{})end
T.eq(opens,0,'frame events never open a module snapshot')
bus:on('mod.option_action',function()same=coroutine.running()end,0,'plain')
local co=coroutine.create(function()bus:emit('mod.option_action',{})end)
T.eq(coroutine.resume(co),true);T.eq(same,co);T.eq(opens,0,'non-main callbacks retain their existing coroutine ABI')
Seams.open=open
Seams.unwindOwner('tuple');G.release()
T.finish('Native option producer ownership, late namespace imports, partial failure cleanup and closed require lifetime')
