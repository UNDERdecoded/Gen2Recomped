package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Probe=dofile('tests/native_action_plan/turn.lua')
local B=require('src.core.game3.battle')
local E=require('src.core.game3.battle.engine')
local function open(edition)local f,b=Probe.open(edition);b:syncSides();return f,b end
local base=E.resolveMove
local function pack(...)return {n=select('#',...),...}end
local nothing,why=E.resolveMove();T.eq(nothing,nil);T.eq(type(why),'string')
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 -- The owned probe skips native enter; explicitly run its native slot placement.
 local baseline=Probe.turn(edition,true,function(_,b)b:syncSides();package.loaded['src.core.game3.battle.engine']=nil end)
 local calls=0
 local decorated=Probe.turn(edition,true,function(_,b)
  b:syncSides()
  package.loaded['src.core.game3.battle.engine']=E
  E.resolveMove=function(u,t,m,slot,adapter,st,out,...)
   calls=calls+1
   T.eq(st,B.getState());T.eq(u,st.battlers[u.id]);T.eq(t,st.battlers[t.id])
   T.eq(m,'MOVE_033');T.eq(slot,1);T.eq(adapter,nil);T.eq(out,nil)
   return base(u,t,m,slot,adapter,st,out,...)
  end
 end)
 E.resolveMove=base
 T.eq(calls,2,edition..' reaches the actual two native move invocations')
 T.same(baseline,decorated,edition..' native HP/PP/every RNG/frame/phase trace survives a pass-through resolver')
end
for _,changed in ipairs{'user','target','move','slot','state','extra'}do
 local f,b=open('emerald');local pp=b.player.mon.moves[1].pp;local rolls=0
 b.rng=function(lo)rolls=rolls+1;return lo or 0 end
 E.resolveMove=function(u,t,m,slot,ad,st,out)
  if changed=='user'then u=t elseif changed=='target'then t=u elseif changed=='move'then m='OTHER'
  elseif changed=='slot'then slot=2 elseif changed=='state'then st={}end
  if changed=='extra'then return base(u,t,m,slot,ad,st,out,true)end
  return base(u,t,m,slot,ad,st,out)
 end
 T.raises(function()b:performMove(b.player,b.enemy,b.player.mon.moves[1])end,'arguments changed')
 T.eq(b.player.mon.moves[1].pp,pp,'foreign resolver arguments cannot spend PP')
 T.eq(rolls,0,'foreign resolver arguments cannot consume RNG');T.eq(#b.queue,0)
 E.resolveMove=base;Probe.close(f)
end
for _,changed in ipairs{'data','save','mods','stack','queue','definition','actor','mon'}do
 local f,b=open('emerald');local pp=b.player.mon.moves[1].pp;local rolls=0
 b.rng=function(lo)rolls=rolls+1;return lo or 0 end
 local prior=changed=='definition'and b.data.moves.MOVE_033 or changed=='actor'and b.player or changed=='mon'and b.player.mon or changed=='queue'and b.queue or f.game[changed]
 E.resolveMove=function(...)
  if changed=='queue'then b.queue={}
  elseif changed=='definition'then b.data.moves.MOVE_033={}
  elseif changed=='actor'then local copy={};for k,v in pairs(b.player)do copy[k]=v end;b.player=copy
  elseif changed=='mon'then local copy={};for k,v in pairs(b.player.mon)do copy[k]=v end;b.player.mon=copy
  else f.game[changed]={}end
  return base(...)
 end
 local ok=pcall(b.performMove,b,b.player,b.enemy,b.player.mon.moves[1])
 T.eq(ok,false,'changed '..changed..' cannot start a retained move')
 T.eq(rolls,0,'cohort guard precedes native RNG')
 if changed=='definition'then b.data.moves.MOVE_033=prior elseif changed=='actor'then b.player=prior elseif changed=='mon'then b.player.mon=prior elseif changed=='queue'then b.queue=prior else f.game[changed]=prior end
 E.resolveMove=base;Probe.close(f)
end
-- Replacing the selected PP slot cannot redirect a lent native invocation.
do
 local f,b=open('emerald');local moves=b.player.curMoves;local original=moves[1];local calls=0
 E.resolveMove=function(...)moves[1]={id=original.id,pp=99};return base(...)end
 T.raises(function()E._native(b,b.player,b.enemy,original,false,false,false,function()calls=calls+1 end)end,'PP owner retired')
 T.eq(calls,0);T.eq(original.pp,10);moves[1]=original
 E.resolveMove=base;Probe.close(f)
end
-- Native nil tuples and the once-only result use the actual dispatch body.
do
 local f,b=open('ruby');local calls=0
 E.resolveMove=function(...)
  local one=pack(base(...));local two=pack(base(...));T.same(one,two)
  return unpack(two,1,two.n)
 end
 local result=pack(E._native(b,b.player,b.enemy,b.player.mon.moves[1],false,false,false,function()
  calls=calls+1;return nil,7,nil
 end))
 T.eq(calls,1);T.eq(result.n,3);T.eq(result[1],nil);T.eq(result[2],7);T.eq(result[3],nil)
 E.resolveMove=base;Probe.close(f)
end
-- A yielded source call is never a durable claim over a different native phase.
do
 local f,b=open('ruby');local co;local calls=0
 E.resolveMove=function(...)
  local args=pack(...)
  co=coroutine.create(function()coroutine.yield('pause');return base(unpack(args,1,args.n))end)
  T.eq(coroutine.resume(co),true)
 end
 E._native(b,b.player,b.enemy,b.player.mon.moves[1],false,false,false,function()calls=calls+1 end)
 local resumed,value,reason=coroutine.resume(co);T.eq(resumed,true);T.eq(value,nil);T.eq(type(reason),'string');T.eq(calls,0)
 E.resolveMove=base;Probe.close(f)
end
-- Failure after consuming the native body cannot replay it.
do
 local f,b=open('ruby');local calls=0
 E.resolveMove=function(...)base(...);error('owned resolver failure')end
 T.raises(function()E._native(b,b.player,b.enemy,b.player.mon.moves[1],false,false,false,function()calls=calls+1 end)end,'owned resolver failure')
 T.eq(calls,1);E.resolveMove=base;Probe.close(f)
end
T.finish('Actual native move resolver, exact arguments, once-only results and unchanged five-edition turns')
