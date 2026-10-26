-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-apricorn-selection.md.
-- Authored IR, not cartridge scripts or dialogue. Exercise the real loader,
-- native VM, menus, flags, inventory and observer boundaries together.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local VM=require('src.script.Gen2ScriptVM');local Runner=require('src.script.ScriptRunner')
local Stack=require('src.core.StateStack');local Flags=require('src.script.Gen2Flags')
local P=require('src.world.Gen2ApricornPrograms');local Merge=require('src.mods.Merge')
local Commands=require('src.script.Commands');local Sound=require('src.core.Sound')
local oldText,oldSound=Commands.show_text,Sound.play
Commands.show_text=function()end;Sound.play=function()end -- external IO only
local function working(version)return version=='crystal' and 80 or 79 end
local function fixture(version)
 local d=T.fixtures.fresh()
 for i=1,7 do
  local key=string.format('ITEM_%03d',110+i)
  d.items[key]={id=key,name='APRICORN '..i,pocket='ITEM'}
 end
 d.items.ITEM_173={id='ITEM_173',name='BERRY',pocket='ITEM'}
 for i=201,202 do
  local key=string.format('ITEM_%03d',i)
  d.items[key]={id=key,name='BALL '..i,pocket='BALL',ball=true}
 end
 local ask={{'special',86,'SelectApricornForKurt'},{'ifequal',0,'CANCEL'}}
 local scripts={ASK=ask,GAVE={{'setflag',working(version)},{'end'}},CANCEL={{'setval',0},{'end'}},
  WAIT={{'setval',98},{'end'}},FULL={{'setval',99},{'end'}},DONE={{'end'}}}
 local pending,rows={},{}
 for i=1,7 do
  local key=string.format('ITEM_%03d',110+i)
  rows[i]={apricorn=key,ball='ITEM_201',index=i}
  if i>1 then ask[#ask+1]={'ifequal',110+i,'CHOOSE'..i}end
  scripts['CHOOSE'..i]={{'setevent',599+i},{'sjump','GAVE'}}
  pending[#pending+1]={'checkevent',599+i};pending[#pending+1]={'iftrue','DELIVER'..i}
  scripts['DELIVER'..i]={{'checkflag',working(version)},{'iftrue','WAIT'},
   version=='crystal' and {'verbosegiveitemvar',201,22} or {'verbosegiveitem',201,1},
   {'iffalse','FULL'},{'clearevent',599+i},{'sjump','DONE'}}
 end
 ask[#ask+1]={'setevent',600};ask[#ask+1]={'sjump','GAVE'}
 for i=1,7 do pending[#pending+1]={'checkitem',110+i};pending[#pending+1]={'iftrue','ASK'}end
 pending[#pending+1]={'end'}
 scripts.PENDING=pending;scripts.OVERLAPPING=Merge.deepCopy(pending)
 d.map_scripts={scripts=scripts,apricornBalls=rows,apricornInfo={complete=true},
  apricornPrograms={ask='ASK',pending='PENDING',gave='GAVE',cancel='CANCEL'}}
 return d
end
local function load(d,sources,mode)
 for root in pairs(require('src.mods.Builtins').namespaceRoots())do d[root]=nil end
 local files,paths={},{}
 for _,entry in ipairs(sources or{})do
  local id,source=entry[1],entry[2];local path='mods/'..id
  files[path..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=mode and mode[1] or 2,
   content_format=mode and mode[2] or 'native',entry='main.lua',affects_link=false})
  files[path..'/main.lua']='local mod=...;mod.exports.api=mod;'..source;paths[#paths+1]=path
 end
 return T.sdk.loadMods(paths,{data=d,fs=T.sdk.memfs(files)})
end
local function finish(r)Loader.teardown();r.release()end
local function game(d,inventory)
 local stack=setmetatable({},{__index=Stack});stack:init();stack:push({name='map'})
 return {data=d,save={inventory=inventory or{},flags={}},stack=stack,overworld={}}
end
local function run(g,key)
 local runner=Runner.new(g,g.overworld);runner:run(assert(VM.compile(g.data,key)));return runner
end
local function press(g,key)
 g.input={wasPressed=function(_,k)return k==key end};g.stack:update(0)
end
local recipe=[[{apricorn='BERRY',ball='BALL_202',event=5000,index=8}]]
local source=[[
 local p=mod.content["apricorns"]
 assert(p:supports())
 assert(p:get('APRICORN_1').apricorn=='APRICORN_1')
 local v=p:get('APRICORN_1');v.ball='LEAK'
 assert(p:get('APRICORN_1').ball=='BALL_201')
 local n=0;for id,row in p:each()do n=n+1;row.event=65534 end;assert(n==7)
 p:register('BERRY_RECIPE',]]..recipe..[[)
 p:patch('APRICORN_1',{ball='BALL_202',event=5100,index=1})
 mod.exports.seen={}
 mod.exports.stop=mod.events:on("apricorn.converted",function(e)
  mod.exports.seen[#mod.exports.seen+1]={apricorn=e.apricorn,ball=e.ball,event=e.event}
  e.apricorn='LEAK';e.ball='LEAK';e.event=123;return false
 end)
]]
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 for _,mode in ipairs({{1,'native'},{2,'native'}})do
  local d=fixture(version);local originalScripts=d.map_scripts.scripts
  local originalRows=d.map_scripts.apricornBalls
  local oldCompiled=assert(VM.compile(d,'PENDING'))
  local r=load(d,{{'recipes',source}},mode);local label=version..'/'..mode[1]..'/'..mode[2]
  T.eq(#r.errors,0,label..' native registry and event registration load')
  if #r.errors==0 then
   local e=r.loader.exports.recipes
   T.eq(#d.map_scripts.apricornBalls,8,label..' actual selector receives all eight native recipes')
   T.eq(d.map_scripts.apricornBalls[8].apricorn,'ITEM_173',label..' semantic input resolves to a real native item byte')
   T.check(d.map_scripts.scripts~=originalScripts,label..' projection changes VM cache identity')
   T.check(VM.compile(d,'PENDING')~=oldCompiled,label..' an already compiled root is recompiled')
   T.eq(originalScripts.ASK[3][2],112,label..' original native branches are not overwritten')
   local g=game(d,{ITEM_173=3})
   local runner=run(g,'OVERLAPPING')
   T.eq(g.stack:top().items[1].label,'BERRY x3',label..' overlapping native membership root accepts the eighth item')
   press(g,'a')
   if version=='crystal'then press(g,'down');press(g,'down');press(g,'a')end
   local quantity=version=='crystal' and 3 or 1
   T.eq(runner:isRunning(),false,label..' actual native selection finishes')
   T.eq(runner.ctx.g2Var,173,label..' VM retains actual item byte without fake ordinal remapping')
   T.eq(g.save.g2KurtApricorns,quantity,label..' native handover quantity survives projection')
   T.eq(g.save.flags[Flags.eventFlag(5000)],true,label..' native selection sets the authored word-sized event')
   T.eq(g.save.flags[Flags.scriptFlag(working(version))],true,label..' native GAVE working flag is preserved')
   run(g,'PENDING')
   T.eq(g.save.inventory.ITEM_202,nil,label..' working native branch defers delivery')
   T.eq(#e.seen,0,label..' waiting job cannot emit a converted event')
   require('src.script.Gen2Daily').onNewDay(g.save)
   T.eq(g.save.flags[Flags.scriptFlag(working(version))],nil,label..' actual daily reset clears native work')
   g.save.inventory.ITEM_202=99;run(g,'PENDING')
   T.eq(g.save.flags[Flags.eventFlag(5000)],true,label..' actual bag refusal retains the job event')
   T.eq(#e.seen,0,label..' refused native gift cannot emit a converted event')
   g.save.inventory.ITEM_202=nil;run(g,'PENDING')
   T.eq(g.save.inventory.ITEM_202,quantity,label..' actual VM gives the authored ball in confirmed quantity')
   T.eq(g.save.inventory.ITEM_201,nil,label..' template ball is not accidentally awarded')
   T.eq(g.save.flags[Flags.eventFlag(5000)],false,label..' real native clear precedes completion')
   T.eq(#e.seen,1,label..' successful native delivery emits exactly once')
   local observed=e.seen[1]
   T.eq(observed.apricorn,mode[1]==3 and 'BERRY' or 'ITEM_173',label..' observer receives the API-specific item identity')
   T.eq(observed.ball,mode[1]==3 and 'BALL_202' or 'ITEM_202',label..' observer receives the actual delivered ball')
   T.eq(observed.event,5000,label..' observer receives the actual cleared event')
   run(g,'PENDING');T.eq(#e.seen,1,label..' cleared event prevents duplicate completion')
   g=game(d,{ITEM_173=3});runner=run(g,'PENDING');press(g,'a')
   if version=='crystal'then
    press(g,'b');T.eq(g.save.inventory.ITEM_173,3,label..' quantity cancellation consumes nothing')
    press(g,'b')
   else -- Gold/Silver have already confirmed their one-item transaction
    T.eq(g.save.inventory.ITEM_173,2,label..' Gold/Silver remain one-at-a-time')
   end
   if version=='crystal'then
    T.eq(g.save.flags[Flags.eventFlag(5000)],nil,label..' cancellation cannot create a pending job')
   end
   local api=e.api.content.apricorns
   T.check(not pcall(function()api:patch('APRICORN_1',{event=5300})end),label..' frozen content refuses late writes')
  end
  finish(r)
  local clean=load(d)
  T.eq(#clean.errors,0,label..' unloading reloads cleanly')
  T.eq(d.map_scripts.scripts,originalScripts,label..' disabling restores original native script table')
  T.eq(d.map_scripts.apricornBalls,originalRows,label..' disabling restores original native recipe table')
  finish(clean)
 end
end
V.set('crystal')
for _,bad in ipairs({
 "p:register('BAD',{apricorn='BERRY',ball='BALL_202',event=65535,index=8})",
 "p:register('BAD',{apricorn='BERRY',ball='BALL_202',event=-1,index=8})",
 "p:register('BAD',{apricorn='BERRY',ball='BALL_202',event=0/0,index=8})",
 "p:register('BAD',{apricorn='BERRY',ball='BALL_202',event=5000,index=math.huge})",
 "p:register('BAD',{apricorn='BERRY',ball='BALL_202',event=601,index=8})",
 "p:register('BAD',{apricorn='APRICORN_2',ball='BALL_202',event=5000,index=8})",
 "p:register('BAD',{apricorn='MISSING',ball='BALL_202',event=5000,index=8})",
 "p:register('BAD',{apricorn='BERRY',ball='MISSING',event=5000,index=8})",
 "p:register('BAD',{apricorn='BERRY',ball='BALL_202',event=5000,index=8,typo=true})",
 "p:patch('APRICORN_1',{apricorn=mod.DELETE})",
 "local x={};x.apricorn=x;p:register('BAD',x)",
 "p:register('BAD',"..recipe..");error('entry failure')",
})do
 local d=fixture('crystal');local scripts,rows=d.map_scripts.scripts,d.map_scripts.apricornBalls
 local r=load(d,{{'broken',"local p=mod.content.apricorns;p:patch('APRICORN_1',{event=5100});"..bad}})
 T.check(#r.errors>0,'invalid authored recipe is attributed to its owner: '..bad)
 T.eq(d.map_scripts.scripts,scripts,'failed owner cannot leak projected native scripts')
 T.eq(d.map_scripts.apricornBalls,rows,'failed owner rolls back prior valid recipe patches')
 finish(r)
end
do
 local d=fixture('crystal')
 local r=load(d,{{'a_recipe',[[mod.content.apricorns:register('FORWARD',
  {apricorn='LATE_FRUIT',ball='BALL_202',event=5200,index=8})]]},
  {'z_item',[[mod.content.items:register('ITEM_174',{id='ITEM_174',name='LATE FRUIT',price=0,pocket='ITEM'})]]}})
 T.eq(#r.errors,0,'semantic native item references may be provided by a later mod')
 T.eq(d.map_scripts.apricornBalls[8] and d.map_scripts.apricornBalls[8].apricorn,'ITEM_174',
  'forward item reference resolves before actual native projection')
 local g=game(d,{ITEM_174=1});local runner=run(g,'PENDING');press(g,'a');press(g,'a')
 T.eq(runner.ctx.g2Var,174,'later native item executes through actual selection byte')
 T.eq(g.save.flags[Flags.eventFlag(5200)],true,'forward recipe enters its actual pending event')
 finish(r)
end
do
 local d=fixture('crystal');local scripts,rows=d.map_scripts.scripts,d.map_scripts.apricornBalls
 local r=load(d,{{'a_recipe',[[mod.content.apricorns:register('FORWARD',
  {apricorn='LATE_FRUIT',ball='BALL_202',event=5200,index=8})]]},
  {'z_item',[[mod.content.items:register('ITEM_174',{id='ITEM_174',name='LATE FRUIT',price=0,pocket='ITEM'});error('supplier failed')]]}})
 T.check(#r.errors>=2,'failed item supplier also attributes unresolved recipe to its owner')
 T.eq(d.items.ITEM_174,nil,'failed supplier leaves no actual native item behind')
 T.eq(d.map_scripts.scripts,scripts,'failed forward recipe leaves native script identity intact')
 T.eq(d.map_scripts.apricornBalls,rows,'failed forward recipe leaves native table intact')
 finish(r)
end
do
 local d=fixture('crystal');local r=load(d,{{'no_byte',[[
  mod.content.items:register('AUTHORED_FRUIT',{id='AUTHORED_FRUIT',name='Authored fruit',price=0,pocket='ITEM'})
  mod.content.apricorns:register('UNINDEXED',
   {apricorn='AUTHORED_FRUIT',ball='BALL_202',event=5200,index=8})
 ]]}})
 T.check(#r.errors>0,'an arbitrary semantic item cannot fabricate a native ROM byte')
 T.eq(d.items.AUTHORED_FRUIT,nil,'unindexed recipe failure rolls back its item registration')
 finish(r)
end
do
 local d=fixture('crystal');local r=load(d,{{'a_first',[[
  mod.content.apricorns:register('FIRST',{apricorn='BERRY',ball='BALL_202',event=5200,index=8})
 ]]},{'z_conflict',[[
  mod.content.apricorns:register('SECOND',{apricorn='ITEM_173',ball='ITEM_201',event=5300,index=9})
 ]]}})
 T.check(#r.errors>0,'semantic/native aliases cannot register the same byte twice')
 T.eq(d.map_scripts.apricornBalls[8] and d.map_scripts.apricornBalls[8].event,5200,
  'later conflicting owner rolls back without discarding the earlier valid owner')
 T.eq(#d.map_scripts.apricornBalls,8,'duplicate alias never enters native menu')
 finish(r)
end
do
 local d=fixture('crystal');local scripts,rows=d.map_scripts.scripts,d.map_scripts.apricornBalls
 local r=load(d,{{'a_supplier',[[
  mod.content.items:register('ITEM_174',{id='ITEM_174',name='LATE FRUIT',price=0})
  mod.content.apricorns:register('BAD',{apricorn='BERRY',ball='MISSING',event=5200,index=8})
 ]]},{'b_consumer',[[mod.content.apricorns:register('FORWARD',
  {apricorn='LATE_FRUIT',ball='BALL_202',event=5300,index=9})]]}})
 T.check(#r.errors>=2,'late recipe failure revalidates consumers after its item supplier rolls back')
 T.eq(d.items.ITEM_174,nil,'late validation rolls back supplier item content')
 T.eq(d.map_scripts.scripts,scripts,'cascading forward-reference failure leaves no projected script table')
 T.eq(d.map_scripts.apricornBalls,rows,'cascading failure leaves pristine native rows')
 finish(r)
end
do
 local d=fixture('crystal');local r=load(d,{{'removed',[[mod.content.apricorns:remove('APRICORN_1')
   mod.exports.count=0;mod.events:on("apricorn.converted",function()mod.exports.count=mod.exports.count+1 end)]]}})
 T.eq(#r.errors,0,'removal projects native membership and pending branches')
 T.eq(#d.map_scripts.apricornBalls,6,'removed recipe cannot be newly selected')
 local g=game(d,{ITEM_111=2});run(g,'PENDING')
 T.eq(g.stack:top().name,'map','removed item no longer opens the native selector')
 g.save.flags[Flags.eventFlag(600)]=true;g.save.g2KurtApricorns=2;run(g,'PENDING')
 T.eq(g.save.inventory.ITEM_201,2,'removed recipe still delivers an already pending native job')
 T.eq(r.loader.exports.removed.count,1,'retired pending job completes only after native gift')
 finish(r)
end
do
 local d=fixture('crystal');local r=load(d,{{'recipes',source}})
 local scripts=d.map_scripts.scripts;local label
 for key in pairs(scripts)do if key:match('^engine:apricorn:')then label=key;break end end
 scripts[label][1]={'setval',77};local external=scripts[label]
 d.map_scripts.apricornBalls[1].ball='ITEM_201'
 finish(r);local clean=load(d)
 T.eq(d.map_scripts.scripts[label],external,'reload preserves an externally edited generated label')
 T.eq(d.map_scripts.apricornBalls[1].ball,'ITEM_201','reload preserves externally edited native rows')
 T.eq(#d.map_scripts.apricornBalls,7,'one external edit cannot retain unchanged mod-only recipes on unload')
 T.eq(d.map_scripts.apricornBalls[2].event,nil,'unload restores unchanged original records beside external edits')
 finish(clean)
end
do
 local d=fixture('crystal');local r=load(d,{{'recipes',source}})
 local added=d.map_scripts.apricornBalls[8];added.ball='ITEM_201'
 table.remove(d.map_scripts.apricornBalls,2)
 finish(r);local clean=load(d)
 T.eq(#d.map_scripts.apricornBalls,7,'unload preserves external deletion and an externally edited addition')
 T.eq(d.map_scripts.apricornBalls[1].event,nil,'other authored edits still retire beside an external deletion')
 T.eq(d.map_scripts.apricornBalls[7],added,'external edit gives the added native record independent ownership')
 finish(clean)
end
for _,version in ipairs({'red','firered','emerald','heartgold'})do
 V.set(version);local d=fixture('crystal');local scripts,rows=d.map_scripts.scripts,d.map_scripts.apricornBalls
 local r=load(d,{{'isolation',[[local p=mod.content["apricorns"];assert(not p:supports())
  assert(p:get('APRICORN_1')==nil);p:register('NO_WRITE',]]..recipe..[[)
  assert(not p:supports())]]}})
 T.eq(#r.errors,0,version..' unsupported handle is readable and reports unavailable')
 T.eq(d.map_scripts.scripts,scripts,version..' cannot mutate a lookalike native script pool')
 T.eq(d.map_scripts.apricornBalls,rows,version..' cannot acquire Gen2 native recipes')
 finish(r)
end
V.set('crystal')
do
 local d=fixture('crystal');d.map_scripts.apricornPrograms=nil
 local r=load(d,{{'oldcache',"mod.content.apricorns:register('NEW',"..recipe..")"}})
 T.check(#r.errors>0,'old cache reports missing native Kurt bindings to the writing owner')
 finish(r)
 r=load(d,{{'observer',"mod.events:on('apricorn.converted',function()end)"}})
 T.eq(#r.errors,0,'an observer alone cannot prevent an older cache from booting')
 finish(r)
end
Commands.show_text=oldText;Sound.play=oldSound;V.set(original)
T.finish('native apricorn registry, actual Kurt VM transactions, completion observers and reload isolation')
