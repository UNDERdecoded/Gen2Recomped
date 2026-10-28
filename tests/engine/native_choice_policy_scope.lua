-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Probe=dofile('tests/native_action_plan/turn.lua')
local B=require('src.core.game3.battle')
local E=require('src.core.game3.battle.engine')
local base=E.resolveMove
local function open(edition)local f,b=Probe.open(edition);b:syncSides();return f,b end
local function native(b,fn)
 return E._native(b,b.player,b.enemy,b.player.mon.moves[1],false,false,false,fn)
end
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 local f,b=open(edition);local st=B.getState()
 T.eq(st.interactiveChoices,nil)
 T.raises(function()st.interactiveChoices=false end,'native move invocation')
 T.eq(rawget(st,'interactiveChoices'),nil,'choice policy cannot become a persistent view extension')
 b.interactiveChoices=true
 T.eq(st.interactiveChoices,true,'default reads the native owner')
 E.resolveMove=function(...)
  local args={...};local prior=st.interactiveChoices
  st.interactiveChoices=false
  T.eq(st.interactiveChoices,false);T.eq(b.interactiveChoices,true)
  T.eq(require('src.compat.gen1.TableIteration').snapshot(st).interactiveChoices,false)
  T.raises(function()st.interactiveChoices='off'end,'boolean or nil')
  local result=base(unpack(args,1,7))
  st.interactiveChoices=prior
  return result
 end
 local calls=0
 native(b,function()calls=calls+1;T.eq(E._interactiveChoices(b),false);return 7 end)
 T.eq(calls,1);T.eq(st.interactiveChoices,true);T.eq(b.interactiveChoices,true)
 E.resolveMove=base
 T.raises(function()st.interactiveChoices=false end,'native move invocation')
 -- An exception does not leak a false override into the next actual move.
 E.resolveMove=function(...)st.interactiveChoices=false;error('owned choice failure')end
 T.raises(function()native(b,function()error('unreachable native body')end)end,'owned choice failure')
 E.resolveMove=base
 native(b,function()T.eq(E._interactiveChoices(b),true)end)
 T.eq(st.interactiveChoices,true)
 Probe.close(f)
end
-- Default and pass-through decoration preserve all five complete native turns.
for _,edition in ipairs{'firered','leafgreen','ruby','sapphire','emerald'}do
 E.resolveMove=base
 local before=Probe.turn(edition,true,function(_,b)b:syncSides()end)
 E.resolveMove=function(u,t,m,slot,ad,st,out)
  local prior=st.interactiveChoices;st.interactiveChoices=false
  local result=base(u,t,m,slot,ad,st,out)
  st.interactiveChoices=prior;return result
 end
 local after=Probe.turn(edition,true,function(_,b)b:syncSides()end)
 T.same(after,before,edition..' no-op choice scope keeps every native HP/PP/RNG/frame/phase')
end
E.resolveMove=base
-- A child may borrow the active invocation, but a suspended child lends no
-- choice policy to the main body or a sibling, and cannot use a later phase.
do
 local f,b=open('ruby');b.interactiveChoices=true;local st=B.getState();local child
 E.resolveMove=function(...)
  child=coroutine.create(function()
   st.interactiveChoices=false;T.eq(E._interactiveChoices(b),false)
   local grand=coroutine.create(function()T.eq(E._interactiveChoices(b),false)end)
   T.eq(coroutine.resume(grand),true)
   coroutine.yield('choice pause')
   st.interactiveChoices=false
  end)
  T.eq(coroutine.resume(child),true)
  T.eq(st.interactiveChoices,true,'suspended sibling cannot lend its choice policy')
  local sibling=coroutine.create(function()T.eq(E._interactiveChoices(b),true)end)
  T.eq(coroutine.resume(sibling),true)
  return base(...)
 end
 native(b,function()T.eq(E._interactiveChoices(b),true)end)
 E.resolveMove=base
 native(b,function()
  local ok,why=coroutine.resume(child);T.eq(ok,false);T.eq(type(why),'string')
  T.eq(E._interactiveChoices(b),true,'retired child cannot change a fresh invocation')
 end)
 Probe.close(f)
end
-- A called move borrows its live ancestor policy; its own override is local.
do
 local f,b=open('emerald');b.interactiveChoices=true;local st=B.getState();local depth=0
 E.resolveMove=function(...)
  depth=depth+1
  if depth==1 then
   st.interactiveChoices=false
   native(b,function()T.eq(E._interactiveChoices(b),nil,'nested override can restore a nil native choice')end)
   T.eq(st.interactiveChoices,false,'nested completion retains the outer dynamic policy')
  else
   T.eq(st.interactiveChoices,false,'called move inherits its visible ancestor policy')
   st.interactiveChoices=nil
  end
  local result=base(...);depth=depth-1;return result
 end
 native(b,function()T.eq(E._interactiveChoices(b),false)end)
 E.resolveMove=base;T.eq(st.interactiveChoices,true)
 Probe.close(f)
end
T.finish('Native invocation-local choice policy and coroutine visibility')
