-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-phone-call-selection.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Calls=require('src.script.Gen2Commands')
local V=require('src.core.GameVersion');local original=V.get()
local bit=require('bit')
local consumed=0
local function unused()consumed=consumed+1;return 0 end
T.eq(Calls.chooseRandomCaller(nil,unused),nil,'missing candidate list has no caller')
T.eq(Calls.chooseRandomCaller({},unused),nil,'empty candidate list has no caller')
T.eq(consumed,0,'empty selection consumes no random byte')
for n=1,10 do
 local callers={};for i=1,n do callers[i]=100+i end
 for byte=0,255 do
  local used=0
  local got=Calls.chooseRandomCaller(callers,function()used=used+1;return byte end)
  -- Independent bytewise SWAP / AND $1f / division remainder oracle.
  local swapped=bit.band(bit.bor(bit.lshift(byte,4),bit.rshift(byte,4)),255)
  local expected=callers[bit.band(swapped,31)%n+1]
  T.eq(got,expected,'native byte mapping n='..n..' byte='..byte)
  T.eq(used,1,'native choice consumes exactly one byte')
 end
end
local old=math.random
for _,version in ipairs({'gold','silver','crystal'}) do
 V.set(version)
 local data={map_scripts={scripts={},phone={}}}
 local ids={9,7,11}
 for i,id in ipairs(ids) do
  local label='NATIVE_RECEIVE_'..version..'_'..id
  data.map_scripts.phone[id]={receive=label,receiveTime=2,group=2,number=1}
  data.map_scripts.scripts[label]={{'setval',80+i},{'end'}}
 end
 local function save()
  return {g2LastCallMinute=0,g2Phone={[9]=true,[7]=true,[11]=true},
   g2PhoneSlots={9,7,11,0,0,0,0,0,0,0}}
 end
 local map={group=1,number=1,phoneService=true}
 local function randomBytes(bytes)
  local used=0
  math.random=function(a,b)
   T.eq(a,0,'phone RNG requests an unsigned byte lower bound')
   T.eq(b,255,'phone RNG requests an unsigned byte upper bound')
   used=used+1;assert(bytes[used]~=nil,'unexpected phone RNG draw')
   return bytes[used]
  end
  return function()return used end
 end
 -- Byte $10 swaps to $01, choosing slot two, not sorted numeric ID order.
 local draws=randomBytes({0,16});local s=save()
 local id,rows=Calls.rollIncomingCall(data,s,map,'DAY',30,false)
 T.eq(id,7,version..' actual incoming path selects the native saved-slot sample')
 T.eq(draws(),2,version..' gate and caller choice consume one byte each')
 T.eq(s.g2CallCycles,0,version..' accepted call resets the receive cycle')
 T.eq(s.g2LastCallMinute,30,version..' accepted call restarts at the actual minute')
 local runner=require('src.script.ScriptRunner').new({data=data,save=s},{})
 runner:run(rows)
 T.eq(runner.ctx.g2Var,82,version..' selected native receive program actually executes')
 draws=randomBytes({128});s=save()
 T.eq(Calls.rollIncomingCall(data,s,map,'DAY',30,false),nil,version..' failed coin flip suppresses choice')
 T.eq(draws(),1,version..' failed coin flip consumes no caller-choice byte')
 T.eq(s.g2CallCycles,1,version..' failed coin flip still consumes timer expiry')
 draws=randomBytes({0});s=save()
 T.eq(Calls.rollIncomingCall(data,s,{phoneService=false,mapPalette=0x10},'DAY',30,false),nil,version..' missing service suppresses choice')
 T.eq(draws(),1,version..' missing service consumes no caller-choice byte')
 draws=randomBytes({0});s=save();s.g2Phone={};s.g2PhoneSlots={}
 T.eq(Calls.rollIncomingCall(data,s,map,'DAY',30,false),nil,version..' empty native book suppresses choice')
 T.eq(draws(),1,version..' empty native book consumes no caller-choice byte')
 draws=randomBytes({});s=save()
 T.eq(Calls.rollIncomingCall(data,s,map,'DAY',30,true),nil,version..' entrance blocks before timer and RNG')
 T.eq(draws(),0,version..' entrance consumes no random bytes')
 T.eq(s.g2LastCallMinute,0,version..' entrance preserves pending timer')
 draws=randomBytes({});s=save()
 T.eq(Calls.rollIncomingCall(data,s,map,'DAY',1,false),nil,version..' unexpired timer suppresses gate and selection')
 T.eq(draws(),0,version..' unexpired timer consumes no random bytes')
end
math.random=old;V.set(original)
T.finish('native phone caller byte selection, saved order, timer gates and actual receive programs')
