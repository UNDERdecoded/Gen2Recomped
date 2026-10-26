-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-phone-received-event.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local Calls=require('src.script.Gen2Commands');local Runner=require('src.script.ScriptRunner')
local World=require('src.world.OverworldController')
local gameSlot,oldGame
for i=1,100 do
 local name,value=debug.getupvalue(World.checkIncomingPhoneCall,i)
 if name=='Game' then gameSlot=i;oldGame=value;break end
 if not name then break end
end
assert(gameSlot,'actual native controller Game upvalue')
local function load(d,source,mode)
 for root in pairs(require('src.mods.Builtins').namespaceRoots())do d[root]=nil end
 local fs={['mods/phone_event/manifest.json']=Json.encode({id='phone_event',name='Phone event',version='1.0.0',
  api=mode and mode[1] or 2,content_format=mode and mode[2] or 'native',entry='main.lua',affects_link=false}),
  ['mods/phone_event/main.lua']='local mod=...;mod.exports.api=mod;'..source}
 return T.sdk.loadMods({'mods/phone_event'},{data=d,fs=T.sdk.memfs(fs)})
end
local function fixture()
 local d=T.fixtures.fresh();d.constants.trainerClassOrder={'YOUNGSTER'}
 d.constants.trainerClassMembers={YOUNGSTER={'JOEY1'}}
 d.trainers={OPP_LOCAL={index=1,name='LOCAL CLASS',partyNames={'LOCAL JOEY'}}}
 d.map_scripts={phone={[7]={class=1,trainer=1,call='OUT',callTime=7,receive='IN',receiveTime=7,group=2,number=1},
  [4]={name='LOCAL ELM',contactNumber=4,receive='ELM',receiveTime=0}},
  specialCalls={[1]={caller=4,script='SPECIAL',outside=true}},
  scripts={OUT={{'setval',74},{'end'}},IN={{'setval',71},{'end'}},ELM={{'setval',72},{'end'}},
   SPECIAL={{'setval',73},{'specialphonecall',0},{'end'}}}}
 return d
end
local function gameFor(d)
 local g={data=d,save={playTime=1800,g2LastCallMinute=0,g2Phone={[7]=true}}}
 local w=setmetatable({map={id='HERE',def={group=1,number=1,phoneService=true,environment=1},
  warpAtCell=function()return nil end},player={cellX=0,cellY=0},scriptMoves={},
  timeOfDay=function()return 'DAY'end},{__index=World})
 w.runner=Runner.new(g,w);g.overworld=w
 debug.setupvalue(World.checkIncomingPhoneCall,gameSlot,g)
 return g,w
end
-- Upstream controller methods return no admission value. Observe their
-- actual queue growth without changing that native return protocol.
local function incoming(w)
 local count=#(w.pendingScripts or {})
 w:checkIncomingPhoneCall()
 return #(w.pendingScripts or {})>count
end
local function special(w)
 local count=#(w.pendingScripts or {})
 w:checkSpecialPhoneCall()
 return #(w.pendingScripts or {})>count
end
local Sound=require('src.core.Sound');local oldSound=Sound.play;Sound.play=function()end
local oldRandom=math.random;math.random=function()return 0 end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 for _,mode in ipairs({{1,'native'},{2,'native'}})do
  local d=fixture()
  T.eq(Calls.phoneName(d,7),'LOCAL JOEY','unmodified contact still reads the actual native roster')
  local r=load(d,[[
   mod.exports.seen={}
   mod.content.phone_contacts:patch('phone:7',{name='AUTHORED JOEY'})
   mod.exports.stop=mod.events:on("phone.call_received",function(e)
    mod.exports.seen[#mod.exports.seen+1]={contact=e.contact,name=e.name,className=e.className,
     special=e.special,scriptKey=e.scriptKey,call={kind=e.call.kind,contact=e.call.contact,
      direction=e.call.direction,class=e.call.class,member=e.call.member,scriptKey=e.call.scriptKey}}
    e.contact=255;e.call.contact=255;e.call.scriptKey='MUTATED';return false
   end)
  ]],mode)
  local label=version..'/'..mode[1]..'/'..mode[2]
  T.eq(#r.errors,0,label..' public event registration succeeds')
  local e=r.loader.exports.phone_event;local g,w=gameFor(d)
  T.eq(incoming(w),true,label..' actual native controller admits a random call')
  T.eq(#e.seen,1,label..' admitted random call emits exactly once')
  local seen=e.seen[1]
  T.eq(seen.contact,7,label..' notification exposes the selected native contact ID')
  T.eq(seen.name,'AUTHORED JOEY',label..' caller name consumes the actual native content override')
  T.eq(seen.className,'LOCAL CLASS',label..' caller class uses native display text')
  T.eq(seen.special,nil,label..' random call has no fabricated special ID')
  T.eq(seen.scriptKey,'IN',label..' notification names the actual compiled native key')
  T.eq(seen.call.contact,7,label..' descriptor and notification agree')
  T.eq(seen.call.direction,'incoming',label..' descriptor retains incoming direction')
  T.eq(seen.call.class,'YOUNGSTER',label..' descriptor class uses explicit canonical metadata')
  T.eq(seen.call.member,'JOEY1',label..' descriptor member uses explicit canonical metadata')
  T.eq(g.save.g2CurCaller,7,label..' observer mutation cannot change the real caller')
  T.eq(w.pendingScripts[1].extra.phoneCaller,7,label..' observer mutation cannot redirect the queued call')
  w.runner:run(w.pendingScripts[1].script,w.pendingScripts[1].extra)
  T.eq(w.runner.ctx.g2Var,71,label..' actual selected receive program still executes')
  T.eq(g.save.g2CurCaller,nil,label..' actual completion clears caller ownership')
  T.eq(d.map_scripts.phone[7].receive,'IN',label..' observer mutation cannot rewrite imported contact')
  g,w=gameFor(d);g.save.g2SpecialCall=1
  T.eq(special(w),true,label..' actual controller admits the queued outside special')
  T.eq(#e.seen,2,label..' admitted special emits exactly once')
  seen=e.seen[2]
  T.eq(seen.contact,4,label..' special exposes its actual caller')
  T.eq(seen.name,'LOCAL ELM',label..' non-trainer name comes from actual contact data')
  T.eq(seen.className,nil,label..' non-trainer has no fabricated trainer class')
  T.eq(seen.special,1,label..' special ID survives disarming of its pending queue')
  T.eq(seen.scriptKey,'SPECIAL',label..' wrapper script overrides contact receive key')
  T.eq(w.pendingScripts[1].extra.phoneCaller,4,label..' observer mutation cannot redirect the special')
  w.runner:run(w.pendingScripts[1].script,w.pendingScripts[1].extra)
  T.eq(w.runner.ctx.g2Var,73,label..' actual special receive program executes')
  T.eq(g.save.g2SpecialCallActive,nil,label..' native specialphonecall NONE clears active ownership')
  T.eq(g.save.g2CurCaller,nil,label..' special completion clears real caller ownership')
  T.eq(special(w),false,label..' completed special cannot notify twice')
  T.eq(#e.seen,2,label..' completed queue has no phantom event')
  g,w=gameFor(d);w.transitioning=true
  T.eq(incoming(w),false,label..' transition rejects a random candidate')
  g.save.g2SpecialCall=1
  T.eq(special(w),false,label..' transition rejects a special candidate')
  g,w=gameFor(d);g.save.g2SpecialCall=1;w.map.def.environment=3
  T.eq(special(w),false,label..' indoor map keeps an outside-only call pending')
  T.eq(g.save.g2SpecialCall,1,label..' rejected special remains queued')
  T.eq(#e.seen,2,label..' rejected candidates never notify')
  g,w=gameFor(d)
  local gear=setmetatable({game=g},{__index=require('src.ui.PokegearMenu')})
  T.eq(gear:runCallScript(7),true,label..' actual outgoing native call executes')
  T.eq(#e.seen,2,label..' outgoing call cannot raise an incoming notification')
  e.stop();g,w=gameFor(d)
  T.eq(incoming(w),true,label..' unsubscribe preserves native incoming behavior')
  T.eq(#e.seen,2,label..' unsubscribe stops event delivery')
  Loader.teardown();r.release()
 end
end
for _,version in ipairs({'red','firered','emerald','heartgold'})do
 V.set(version);local d=fixture();local r=load(d,[[
  mod.exports.count=0
  mod.events:on("phone.call_received",function()mod.exports.count=mod.exports.count+1 end)
 ]])
 T.eq(#r.errors,0,version..' native listener registration remains available without a native target')
 local g,w=gameFor(d);g.save.g2SpecialCall=1
 T.eq(incoming(w),false,version..' native random call gate remains isolated')
 T.eq(special(w),false,version..' native special call gate remains isolated')
 T.eq(r.loader.exports.phone_event.count,0,version..' no unrelated generation event')
 Loader.teardown();r.release()
end
do
 V.set('crystal');local d=fixture();local r=load(d,[[
  mod.events:on("phone.call_received",function()error('rolled-back listener ran')end)
  error('entry failure')
 ]])
 T.check(#r.errors>0,'failed entry is reported')
 T.eq(require('src.mods.Runtime').wants("phone.call_received"),false,'failed entry rolls back its actual event listener')
 local g,w=gameFor(d)
 T.eq(incoming(w),true,'failed listener cannot block the actual native incoming call')
 Loader.teardown();r.release()
end
debug.setupvalue(World.checkIncomingPhoneCall,gameSlot,oldGame)
Sound.play=oldSound;math.random=oldRandom;V.set(original)
T.finish('native phone.call_received from actual random/special controller queues and receive programs')
