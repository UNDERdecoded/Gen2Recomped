-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Actual native status records, infliction, action and move-effect owners.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Status=require('src.battle.Status')
local Registry=require('src.battle.StatusRegistry')
local Screen=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local old=V.get()
local function fixture(edition,id,side)
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=V.generation()
 for key,definition in pairs({
  SNORE={id='SNORE',name='SNORE',index=173,power=40,type='NORMAL',accuracy=100,pp=15,effect='SNORE_EFFECT'},
  SLEEP_TALK={id='SLEEP_TALK',name='SLEEP TALK',index=214,power=0,type='NORMAL',accuracy=100,pp=10,effect='SLEEP_TALK_EFFECT'},
  REST={id='REST',name='REST',index=156,power=0,type='PSYCHIC',accuracy=100,pp=10,effect='HEAL_EFFECT'},
 })do data.moves[key]=definition end
 require('src.render.Font').load(data)
 local save=require('src.core.SaveData').newGame()
 save.party={Pokemon.new(data,'FIXMON_A',30)}
 local s=Screen.newWild({data=data,save=save,stack={top=function()end},
  input={isDown=function()return true end,wasPressed=function()return true end}},'FIXMON_C',30)
 s.queue,s.current,s.waitFrames={},nil,nil
 s.rng=function(lo,hi)return hi and lo+math.floor((hi-lo)/2)or lo end
 local b=s[side or 'player'];local t=s[(side or 'player')=='player'and'enemy'or'player']
 b.curMoves={{id=id or 'FIX_TACKLE',pp=10},{id='FIX_TACKLE',pp=0}}
 b.mon.moves=b.curMoves
 return s,b,t
end
local function asleep(b,turns)
 b.mon.status,b.sleepTurns,b.mon.sleepTurns='SLP',turns,turns
end
local function texts(s)
 local out={};for _,row in ipairs(s.queue)do if row.text then out[#out+1]=row.text end end
 return table.concat(out,'|')
end
for _,edition in ipairs{'gold','silver','crystal'}do
 for _,side in ipairs{'player','enemy'}do
  local s,b,t=fixture(edition,'FIX_TACKLE',side)
  local ppCost=side=='player'and 1 or 0
  asleep(b,1);b.nightmare,b.expNightmare=true,true
  local hp,pp=t.mon.hp,b.curMoves[1].pp
  s:executeAction(b,t,b.curMoves[1])
  T.eq(b.mon.status,nil,'native wake clears persistent status')
  T.eq(b.sleepTurns,nil);T.eq(b.mon.sleepTurns,nil)
  T.eq(b.nightmare,nil);T.eq(b.expNightmare,nil)
  T.eq(b.curMoves[1].pp,pp-ppCost,'Gen2 acts on the same turn it wakes')
  T.check(t.mon.hp<hp,'actual native move pipeline deals damage after waking')
  T.check(texts(s):find('woke up!',1,true)~=nil,'native wake caption precedes the move')
  for _,row in ipairs(s.queue)do T.neq(row.anim,'ANIM_SLP','waking has no still-asleep animation')end

  s,b,t=fixture(edition,'FIX_TACKLE',side);asleep(b,3)
  b.charging={id='FLY'};b.chargeReady=true;b.invulnerable=true;b.hiddenAs='air'
  b.bideTurns,b.bideDamage,b.thrashTurns,b.rampRun=2,8,2,3
  b.rampMove='ROLLOUT'
  require('src.battle.Gen2VanishPresentation').charge(s,b,nil)
  T.eq(s:fxHidden(b),true,'real native picture owner observes a charged Fly')
  local allowed=Status.beforeMove(b,s.rng,s,{id='FLY'})
  T.eq(allowed,false);T.eq(b.sleepTurns,2);T.eq(b.mon.sleepTurns,2)
  T.eq(b.charging,nil);T.eq(b.chargeReady,nil);T.eq(b.invulnerable,nil);T.eq(b.hiddenAs,nil)
  T.eq(b.bideTurns,nil);T.eq(b.bideDamage,nil);T.eq(b.thrashTurns,nil);T.eq(b.rampRun,nil)
  T.eq(s:fxHidden(b),false,'cancelled Fly cannot leave the real native picture hidden')
  s,b,t=fixture(edition,'FIX_TACKLE',side);asleep(b,3)
  pp,hp=b.curMoves[1].pp,t.mon.hp
  s:executeAction(b,t,b.curMoves[1])
  T.eq(b.sleepTurns,2);T.eq(b.mon.sleepTurns,2)
  T.eq(b.curMoves[1].pp,pp,'blocked sleeping move spends no PP')
  T.eq(t.mon.hp,hp,'blocked sleeping move cannot deal damage')
  T.check(texts(s):find('fast asleep!',1,true)~=nil)

  for _,id in ipairs{'SNORE','SLEEP_TALK'}do
   s,b,t=fixture(edition,id,side);asleep(b,3)
   pp,hp=b.curMoves[1].pp,t.mon.hp
   local calledPP=b.curMoves[2].pp
   s:executeAction(b,t,b.curMoves[1])
   T.eq(b.mon.status,'SLP');T.eq(b.sleepTurns,2);T.eq(b.mon.sleepTurns,2)
   T.eq(b.curMoves[1].pp,pp-ppCost,'sleep bypass reaches the existing native move owner once')
   T.check(t.mon.hp<hp,id..' actually attacks through the native action pipeline')
   T.eq(b.curMoves[2].pp,calledPP,'called move spends no additional learned PP')
   T.check(texts(s):find('fast asleep!',1,true)~=nil,'allowed sleeping move retains its actual status presentation')
   -- The move's own awake guard still runs after a waking status check.
   s,b,t=fixture(edition,id,side);asleep(b,1)
   hp,pp=t.mon.hp,b.curMoves[1].pp;s:executeAction(b,t,b.curMoves[1])
   T.eq(b.mon.status,nil);T.eq(b.curMoves[1].pp,pp-ppCost)
   T.eq(t.mon.hp,hp,'wake permits the selected move, whose awake-only failure remains native')
   T.check(texts(s):find('failed!',1,true)~=nil)
  end

  for _,turns in ipairs{1,3}do
   s,b,t=fixture(edition,'SNORE',side);asleep(b,turns);b.flinched=true
   local can,msgs=Status.beforeMove(b,s.rng,s,b.curMoves[1])
   T.eq(can,false,'flinch still blocks a wake or sleep-bypass move')
   local expectedStatus,expectedTurns
   if turns>1 then expectedStatus,expectedTurns='SLP',turns-1 end
   T.eq(b.mon.status,expectedStatus)
   T.eq(b.sleepTurns,expectedTurns,'GSC sleep is processed before flinch')
   T.eq(#msgs,2,'sleep/wake caption then flinch caption')
   T.check(msgs[2]:find('flinched!',1,true)~=nil)
  end

  s,b,t=fixture(edition,'FIX_TACKLE',side);asleep(b,3)
  b.mustRecharge,b.flinched=true,true
  local rolls=0;s.rng=function()rolls=rolls+1;return 0 end
  s:executeAction(b,t,{special='recharge'})
  T.eq(b.mustRecharge,nil,'GSC recharge is consumed before sleep/flinch')
  T.eq(b.sleepTurns,3);T.eq(b.mon.sleepTurns,3,'recharge does not advance a second sleep clock')
  T.eq(b.flinched,true,'recharge never consumes the later flinch check')
  T.eq(rolls,0);T.check(texts(s):find('must recharge!',1,true)~=nil)
 end

 -- Exercise actual StatusRegistry infliction for every possible ROM byte,
 -- including zero/seven rejection and the Tower's two-bit mask.
 for _,tower in ipairs{false,true}do
  local s,b=fixture(edition);s.inBattleTowerBattle=tower
  for byte=0,255 do
   b.mon.status,b.sleepTurns,b.mon.sleepTurns=nil,nil,nil
   local calls=0
   s.rng=function(lo,hi)
    calls=calls+1;T.eq(lo,0);T.eq(hi,255,'native sleep reads a full battle byte')
    return calls==1 and byte or 1
   end
   local msgs=Registry.inflict(s,b,'SLP',{})
   local value=byte%(tower and 4 or 8)
   local rejected=value==0 or value==7
   local expected=rejected and 2 or value+1
   T.eq(b.sleepTurns,expected,'actual byte/mask/rejection determines sleep duration')
   T.eq(b.mon.sleepTurns,expected,'party counter is owned by the same native infliction')
   T.eq(calls,rejected and 2 or 1,'rejected byte consumes another real battle draw')
   T.eq(#msgs,1)
  end
 end
 local s,b=fixture(edition);s.ruleset={sleepTurnsMin=3,sleepTurnsMax=9}
 s.rng=function(lo,hi)T.eq(lo,3);T.eq(hi,9);return 9 end
 Registry.inflict(s,b,'SLP',{});T.eq(b.sleepTurns,9);T.eq(b.mon.sleepTurns,9,'explicit custom sleep rules retain their own range')

 s,b=fixture(edition,'REST');b.mon.hp=math.floor(b.mon.stats.hp/2)
 s:executeAction(b,s.enemy,b.curMoves[1])
 T.eq(b.mon.hp,b.mon.stats.hp);T.eq(b.sleepTurns,3);T.eq(b.mon.sleepTurns,3,'Rest initializes two lost turns plus waking turn')
 for turn=1,2 do
  local can=Status.beforeMove(b,s.rng,s,{id='FIX_TACKLE'})
  T.eq(can,false);T.eq(b.sleepTurns,3-turn)
 end
 T.eq(Status.beforeMove(b,s.rng,s,{id='FIX_TACKLE'}),true,'Rest wakes and acts on the third subsequent attempt')
 s,b=fixture(edition);asleep(b,3);Status.beforeMove(b,s.rng,s,b.curMoves[1])
 local nextBattle=Screen.newWild(s.game,'FIXMON_C',30)
 T.eq(nextBattle.player.mon,b.mon,'reconstruction retains the actual party Pokemon')
 T.eq(nextBattle.player.sleepTurns,2,'new native wrapper reads the remaining party sleep counter')
end

-- Shared native record behavior must remain unchanged outside Gen2.
for _,edition in ipairs{'red','yellow','emerald','firered'}do
 local s,b=fixture(edition);asleep(b,1)
 local allowed=Status.beforeMove(b,s.rng,s,b.curMoves[1])
 T.eq(allowed,false,'other-generation wake behavior retains the upstream baseline')
 s,b=fixture(edition,'SNORE');asleep(b,3);b.flinched=true
 local can=Status.beforeMove(b,s.rng,s,b.curMoves[1])
 T.eq(can,false)
 T.eq(b.sleepTurns,3,'other-generation flinch/status order retains the upstream baseline')
end
V.set('crystal')
local s,b=fixture('crystal');asleep(b,3)
local custom={id='SLP',beforeMovePriority=40,beforeMove=function()
 return true,{'custom status'},false,'custom-native-result'
end}
s.data.statuses={SLP=custom}
local can,msgs,selfHit,reason=Status.beforeMove(b,s.rng,s,b.curMoves[1])
T.eq(can,true);T.eq(msgs[1],'custom status');T.eq(selfHit,nil);T.eq(reason,nil)
T.eq(b.sleepTurns,3,'registered custom status retains its actual handler and counter')
V.set(old)
T.finish('native GSC sleep duration, wake/bypass admission, ordering, Rest and persistent counter')
