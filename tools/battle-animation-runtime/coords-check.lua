-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional local contract comparison. The oracle is supplied by the caller;
-- no external engine, private package or cartridge is distributed here.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local C=require('src.core.game3.battle.anim_coords')
local reference=assert(loadfile(assert(os.getenv('BATTLE_COORDS_ORACLE'))))()
for _,double in ipairs{false,true}do
  local st={double=double,battlers={}}
  C.setDouble(double);reference.setDouble(double)
  T.same(C.monDrawOrder(st),reference.monDrawOrder(st))
  T.same(C.ids(st),reference.ids(st))
  for id=0,3 do
    T.same(C.coords(st,id),reference.coords(st,id))
    T.eq(C.subpriority(id),reference.subpriority(id))
    T.eq(C.bgPriorityRank(id),reference.bgPriorityRank(id))
    T.eq(C.monBehindZ(id,st),reference.monBehindZ(id,st))
    T.eq(C.partner(id),reference.partner(id))
    for _,hp in ipairs{0,1}do
      st.battlers[id]={mon={hp=hp}}
      T.eq(C.spritePresent(st,id),reference.spritePresent(st,id))
    end
  end
  for k=0,5 do
    local a,b=C.particleBand(k,st);local x,y=reference.particleBand(k,st)
    T.eq(a,x);T.eq(b,y)
  end
  for sub=0,255 do
    for pri=0,3 do
      for _,vm in ipairs{{},{_monbg={[0]=true,[3]=true},_bgPrio={[1]=1,[2]=3}}}do
        T.eq(C.zFor(pri,sub,vm,st),reference.zFor(pri,sub,vm,st))
      end
    end
  end
end
C.setDouble(nil);reference.setDouble(nil)
for attacker=0,3 do for target=0,3 do
  C.bind(attacker,target);reference.bind(attacker,target)
  for _,side in ipairs{'player','enemy'}do T.eq(C.idOf(side),reference.idOf(side))end
end end
C.bind(nil);reference.bind(nil)
T.finish('authored battler coordinate contract')
