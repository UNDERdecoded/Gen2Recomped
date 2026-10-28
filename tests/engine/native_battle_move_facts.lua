package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Probe=dofile('tests/native_action_plan/turn.lua')
local B=require('src.core.game3.battle')
local Engine=require('src.core.game3.battle.engine')
local Ownership=require('src.pokemon.Gen3Ownership')
local Json=require('src.link.Json')
local function open(edition)local f,b=Probe.open(edition);b:syncSides();return f,b end
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 local f,b=open(edition);local st=B.getState();local u=st.player;local raw=b.player;local mon=raw.mon
 local rolls=0;b.rng=function(lo)rolls=rolls+1;return lo or 0 end
 mon.ot,mon.otId='PROBE',1000
 T.eq(u.mon.otName,'PROBE');T.eq(Engine.isTradedMon(st,u.mon),false)
 mon.ot='OTHER';T.eq(Engine.isTradedMon(st,u.mon),true,'different OT name is foreign')
 mon.ot,mon.otId='PROBE',1001;T.eq(Engine.isTradedMon(st,u.mon),true,'matching names do not hide a foreign ID')
 mon.ot,mon.otId=nil,nil;T.eq(Engine.isTradedMon(st,u.mon),false,'retain the native historical missing-OT policy')
 T.eq(Engine.isTradedMon(st,{}),nil,'detached records cannot claim a battle resident')
 T.eq(Engine.isTradedMon({},u.mon),nil,'foreign battle views cannot borrow ownership')
 -- Merely reading native ownership must not commit a pending PP edit.
 local pp=u.mon.pp;pp[1]=8
 T.eq(Engine.isTradedMon(st,u.mon),false);T.eq(mon.moves[1].pp,10)
 pp[1]=10;B._flushNative(b)
 T.eq(u.expLockedMove,nil)
 raw.mustRecharge=true;T.eq(u.expLockedMove,'recharge');raw.mustRecharge=nil
 raw.charging=mon.moves[1];T.eq(u.expLockedMove,'MOVE_033');raw.charging=nil
 raw.thrashTurns,raw.thrashMove=2,mon.moves[1];T.eq(u.expLockedMove,'MOVE_033');raw.thrashTurns,raw.thrashMove=nil,nil
 raw.rageMove=mon.moves[1];T.eq(u.expLockedMove,'MOVE_033');raw.rageMove=nil
 raw.encoreTurns,raw.encoreMove,raw.encoreSlot=2,'MOVE_033',1
 T.eq(u.expEncoreMove,'MOVE_033','Encore observes the native forced move')
 local before=Json.encode(f.game.save);local frame=b.frame
 for _=1,30 do T.eq(u.expEncoreMove,'MOVE_033');T.eq(Engine.isTradedMon(st,u.mon),false)end
 T.eq(Json.encode(f.game.save),before);T.eq(b.frame,frame);T.eq(rolls,0)
 raw.encoreMove='MISSING';T.eq(u.expEncoreMove,nil);T.eq(raw.encoreTurns,2,'invalid Encore observation never performs native cleanup')
 raw.encoreTurns,raw.encoreMove,raw.encoreSlot=nil,nil,nil
 T.eq(u.mon.fatefulEncounter,nil,'an unknown native flag is not fabricated')
 mon.fatefulEncounter=false;T.eq(u.mon.fatefulEncounter,false)
 mon.fatefulEncounter=true;T.eq(u.mon.fatefulEncounter,true)
 mon.gen3Ribbons=0;T.eq(u.mon.fatefulEncounter,false,'native encoded ribbon word is authoritative')
 mon.gen3Ribbons=2147483648;T.eq(u.mon.fatefulEncounter,true)
 mon.gen3Ribbons=2147483647;T.eq(u.mon.fatefulEncounter,false,'other ribbons do not imply fateful encounter')
 mon.gen3Ribbons=nil;mon.fatefulEncounter=nil
 local facts={};for k,v in pairs(u)do facts[k]=v end;T.eq(facts.expLockedMove,nil)
 mon.ot='VISIBLE';T.eq(require('src.compat.gen1.TableIteration').snapshot(u.mon).otName,'VISIBLE')
 T.raises(function()u.expLockedMove='OTHER'end,'not directly writable')
 T.raises(function()u.mon.fatefulEncounter=true end,'not directly writable')
 local foreign,other=open(edition)
 T.eq(Engine.isTradedMon(B.getState(),u.mon),nil,'another live battle cannot accept the earlier resident')
 Probe.close(foreign);Probe.close(f)
 T.eq(Engine.isTradedMon(st,u.mon),nil,'retired battle cannot grant an ownership query')
end
-- Keep the summary's existing decision, including missing historical fields.
local Summary=require('src.ui.Gen3SummaryMenu')
for _,case in ipairs{
 {mon={},player={},own=true},
 {mon={ot='MAY',otId=123},player={name='MAY',id=123},own=true},
 {mon={ot='MAY',otId=123},player={name='MAY',id=124},own=false},
 {mon={ot='MAY',otId=123},player={name='BRENDAN',id=123},own=false},
 {mon={ot='MAY'},player={},own=true},
}do
 T.eq(Ownership.owns(case.mon,case.player),case.own)
 T.eq(Summary.memoOwnMon({mon=case.mon,game={save={player=case.player}}}),case.own)
end
for _,word in ipairs{-1,4294967296,0/0,.5}do T.eq(Ownership.fateful({gen3Ribbons=word}),nil,'malformed encoded flags remain unknown')end
T.finish('Native battle ownership, live move locks, Encore and fateful facts without combat or PP side effects')
