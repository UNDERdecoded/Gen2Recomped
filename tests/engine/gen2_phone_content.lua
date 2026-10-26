-- Copyright (c) 2026 Roxas2712. See the offered PR contribution permission in docs/native-gen2-phone-content.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
local Json=require('src.link.Json');local Loader=require('src.mods.Loader')
local C=require('src.script.Gen2Commands');local Gear=require('src.ui.PokegearMenu')
local function fixture()
  local d=T.fixtures.fresh()
  d.constants.phoneContactOrder={'PHONE_00','PHONE_MOM','PHONE_JOEY','PHONE_UNUSED'}
  d.constants.trainerClassOrder={'YOUNGSTER'}
  d.constants.trainerClassMembers={YOUNGSTER={'JOEY1'}}
  d.maps.PALLET_TOWN={group=1,number=1};d.maps.ROUTE_31={group=1,number=2}
  d.trainers={OPP_LOCALIZED={index=1,name='LOCAL CLASS',partyNames={'LOCAL JOEY'}}}
  d.map_scripts={phoneInfo={size=4},phone={
    [1]={name='NATIVE MOM',contactNumber=1,group=1,number=1,call='OUT',callTime=7,receive='IN',receiveTime=0},
    [2]={class=1,trainer=1,group=1,number=2,call='OUT',callTime=7,receive='IN',receiveTime=7},
  },scripts={OUT={{'setval',41},{'end'}},IN={{'setval',42},{'end'}}}}
  return d
end
local function load(d,source,api,format)
  for root in pairs(require('src.mods.Builtins').namespaceRoots()) do d[root]=nil end
  local files={}
  if source then
    files['mods/phone/manifest.json']=Json.encode({id='phone',name='Phone content',version='1.0.0',
      api=api or 2,content_format=format or 'native',entry='main.lua',affects_link=false})
    files['mods/phone/main.lua']='local mod=...;mod.exports.api=mod;'..source
  end
  return T.sdk.loadMods(source and {'mods/phone'} or {},{data=d,fs=T.sdk.memfs(files)})
end
local function finish(r) Loader.teardown();r.release() end
for _,version in ipairs({'gold','silver','crystal'}) do
 V.set(version)
 for _,mode in ipairs({{1,'native'},{2,'native'}}) do
  local d=fixture();local native=d.map_scripts.phone[2]
  local r=load(d,[[
    assert(mod.content.phone_contacts:supports())
    local p=mod.content["phone_contacts"]
    assert(p:get('PHONE_MOM').number==1)
    assert(p:get('PHONE_MOM').map=='PALLET_TOWN')
    assert(p:get('PHONE_MOM').callee=='OUT' and p:get('PHONE_MOM').caller=='IN')
    assert(p:get('PHONE_JOEY').class=='YOUNGSTER')
    assert(p:get('PHONE_JOEY').member=='JOEY1')
    local row=p:get('PHONE_MOM');row.name='LEAK'
    assert(p:get('PHONE_MOM').name=='NATIVE MOM')
    for id,value in p:each() do value.name='LEAK' end
    assert(p:get('PHONE_MOM').name=='NATIVE MOM')
    p:patch('PHONE_MOM',{name='AUTHORED MOM',map='ROUTE_31',callerTime=7})
    p:register('PHONE_EXTRA',{name='EXTRA',map='PALLET_TOWN',calleeTime=7,callerTime=7,calleeKey='OUT',callerKey='IN'})
    mod.exports.index=p:get('PHONE_EXTRA').index
    p:remove('PHONE_JOEY')
  ]],mode[1],mode[2])
  local label=version..'/'..mode[1]..'/'..mode[2]
  T.eq(#r.errors,0,label..' real loader accepts semantic contacts')
  local e=r.loader.exports.phone;local index=e and e.index
  T.eq(index,4,label..' added contact skips all native holes')
  T.eq(C.phoneName(d,1),'AUTHORED MOM',label..' native name consumer uses authored row')
  T.eq(d.map_scripts.phone[1].contactNumber,1,label..' contact number stays separate')
  T.eq(d.map_scripts.phone[1].number,2,label..' actual map number changes')
  T.eq(d.map_scripts.phone[1].receiveTime,7,label..' native incoming time changes')
  T.eq(C.phoneName(d,2),nil,label..' native removed contact stays absent')
  T.eq(native.trainer,1,label..' source row remains unchanged')
  if index then
    local game={data=d,save={g2Phone={[index]=true}},overworld={}}
    local gear=setmetatable({game=game},{__index=Gear})
    T.eq(#gear:contacts(),10,label..' actual native phone book preserves ten physical slots')
    T.eq(gear:contacts()[1].id,index,label..' registered addition occupies the first native slot')
    T.eq(gear:contacts()[2].id,0,label..' unused native slot cannot invent a callable contact')
    for _,direction in ipairs({'call','receive'}) do
      local rows=direction=='call' and C.phoneCallScript(d,index) or C.phoneReceiveScript(d,index)
      T.check(rows~=nil,label..' '..direction..' compiles through native VM')
      local runner=require('src.script.ScriptRunner').new(game,game.overworld);runner:run(rows or {})
      T.eq(runner.ctx.g2Var,direction=='call' and 41 or 42,label..' '..direction..' executes correct native direction')
    end
    T.eq(C.availableCallers(d,game.save,d.maps.ROUTE_31,'DAY')[1],index,label..' native incoming selector sees added contact')
    T.eq(#C.availableCallers(d,game.save,d.maps.PALLET_TOWN,'DAY'),0,label..' same-map incoming suppression remains native')
  end
  finish(r)
  local clean=load(d)
  T.eq(#clean.errors,0,label..' disabling/reloading succeeds')
  T.eq(C.phoneName(d,1),'NATIVE MOM',label..' disabling restores base name')
  T.eq(C.phoneName(d,2),'LOCAL JOEY',label..' disabling restores native trainer')
  T.eq(d.map_scripts.phone[4],nil,label..' disabling removes added numeric row')
  finish(clean)
 end
end
V.set('crystal')
do
 local d=fixture();local r=load(d,[[local p=mod.content.phone_contacts
   local row=p:get('PHONE_MOM');row.calleeKey='IN';p:override('PHONE_MOM',row)
 ]])
 T.eq(#r.errors,0,'read/edit/write accepts an explicit script key alongside the prior alias')
 T.eq(d.map_scripts.phone[1].call,'IN','explicit calleeKey owns the effective outgoing script')
 finish(r)
end
do
 local d=fixture();local r=load(d,[[local p=mod.content.phone_contacts
   p:patch('PHONE_MOM',{callee='IN',caller='OUT',callerTime=7})
 ]])
 T.eq(#r.errors,0,'caller and callee aliases are accepted')
 T.eq(d.map_scripts.phone[1].call,'IN','callee alias replaces previous outgoing key')
 T.eq(d.map_scripts.phone[1].receive,'OUT','caller alias replaces previous incoming key')
 local p=r.loader.exports.phone.api.content.phone_contacts
 T.eq(p:get('PHONE_MOM').callee,'IN','public callee alias reflects the effective native key')
 T.eq(p:get('PHONE_MOM').caller,'OUT','public caller alias reflects the effective native key')
 finish(r)
end
do
 local d=fixture();local r=load(d,[[local p=mod.content.phone_contacts
   p:register('FIRST',{name='FIRST',index=255})
   p:register('SECOND',{name='SECOND'})
   assert(p:get('SECOND').index==4)
   p:remove('SECOND')
   p:register('THIRD',{name='THIRD'})
   assert(p:get('THIRD').index==5)
   p:patch('PHONE_JOEY',{name='TRANSLATED'})
 ]])
 T.eq(#r.errors,0,'explicit high index and removed additions retain reservations')
 T.eq(C.phoneName(d,255),'FIRST','native byte upper bound can be used explicitly')
 T.eq(C.phoneName(d,4),nil,'added then removed contact leaves no callable row')
 T.eq(C.phoneName(d,5),'THIRD','next addition cannot steal removed contact index')
 T.eq(d.map_scripts.phone[2].class,1,'display override retains canonical trainer identity')
 T.eq(d.map_scripts.phone[2].trainer,1,'display override retains trainer member')
 local api=r.loader.exports.phone.api.content.phone_contacts
 T.check(not pcall(function() api:patch('PHONE_MOM',{name='LATE'}) end),'frozen content rejects late mutation')
 T.eq(C.phoneName(d,1),'NATIVE MOM','late mutation cannot change native data')
 d.map_scripts.phone[2].name='EXTERNAL AFTER LOAD'
 finish(r)
 local clean=load(d)
 T.eq(C.phoneName(d,2),'EXTERNAL AFTER LOAD','reload preserves an externally edited native contact')
 T.eq(d.map_scripts.phone[255],nil,'reload retires unchanged added high-index contact')
 finish(clean)
end
do
 local d=fixture();d.map_scripts=nil
 local r=load(d,"mod.content.phone_contacts:register('NEW',{name='NEW'})")
 T.eq(#r.errors,0,'a named silent contact needs no native script pool')
 T.eq(C.phoneName(d,4),'NEW','new native book respects explicit metadata floor')
 finish(r)
 local clean=load(d)
 T.eq(d.map_scripts,nil,'reload removes an exclusively owned empty pool namespace')
 finish(clean)
end
for _,source in ipairs({
 "p:register('BAD',{name='BAD',index=3})",
 "p:register('BAD',{name='BAD',index=2})",
 "p:patch('PHONE_MOM',{index=7})",
 "p:register('BAD',{name='BAD',callerTime=7})",
 "p:register('BAD',{name='BAD',callerTime=7,callerKey='MISSING'})",
 "p:register('BAD',{class='YOUNGSTER',member='MISSING'})",
 "p:register('BAD',{name='BAD',map='MISSING'})",
 "p:register('BAD',{name='BAD',callerTime=0/0})",
 "local x={};x.x=x;p:register('BAD',x)",
 "p:register('BAD',{name='BAD',index=256})",
 "p:register('BAD',{name='BAD',index=0})",
 "p:register('BAD',{name='BAD',unknownField=true})",
 "p:register('BAD',{class='YOUNGSTER',member='JOEY1',number=1})",
 "p:patch('PHONE_MOM',{name='FAILED'});error('entry failure')",
}) do
 local d=fixture();local r=load(d,'local p=mod.content.phone_contacts;'..source)
 T.check(#r.errors>0,'invalid entry is rejected and attributed: '..source)
 T.eq(C.phoneName(d,1),'NATIVE MOM','failed entry rolls back earlier phone operations')
 T.eq(d.map_scripts.phone[4],nil,'failed entry cannot leak a native numeric contact')
 finish(r)
end
for _,version in ipairs({'red','firered','emerald','heartgold'}) do
 V.set(version);local d=fixture();local originalRow=d.map_scripts.phone[1]
 local r=load(d,[[local p=mod.content.phone_contacts;assert(not p:supports());assert(p:get('PHONE_MOM')==nil);p:register('OTHER',{name='NO WRITE'})]])
 T.eq(#r.errors,0,version..' unsupported target reports through capability handle')
 T.eq(d.map_scripts.phone[1],originalRow,version..' other generations retain native-looking data unchanged')
 T.eq(d.map_scripts.phone[4],nil,version..' cannot acquire a Gen2 phone book')
 finish(r)
end
V.set(original)
T.finish('semantic native phone contacts, actual VM/phone book, rollback and isolation')
