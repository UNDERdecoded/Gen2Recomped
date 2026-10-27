-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Damage=require('src.core.game3.battle.damage')
local Merge=require('src.mods.Merge')
local original=package.loaded['src.core.Game']
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 local g=f.game;package.loaded['src.core.Game']=g
 local b=f.fresh('TACKLE').battle
 g.data.constants.types={NORMAL={index=0}};g.data.constants.typeOrder={'NORMAL'}
 g.data.move_effects=nil
 local mon={species=4,level=30,personality=7,friendship=255,moves={33},pp={10}}
 Damage.ensureStats(mon)
 local target=Merge.deepCopy(mon);target.hp=math.min(40,target.maxHp)
 local row=g.data.moves.MOVE_033
 local opts={noCrit=true,rng=function(lo,hi)return hi or lo end}
 local function query(effect,power)
  row.effect,row.power=effect,power
  return Damage.calc({mon=mon},{mon=target},33,opts)
 end
 local hp,pp=target.hp,mon.pp[1]
 row.fixedDamage=20
 local damage,info=query('SPECIAL_DAMAGE_EFFECT',1)
 T.eq(damage,20);T.eq(info.critical,false)
 row.fixedDamage='level';T.eq(query('SPECIAL_DAMAGE_EFFECT',1),30)
 row.fixedDamage=nil
 T.eq(query('SUPER_FANG_EFFECT',1),math.max(1,math.floor(hp/2)))
 T.eq(query('FALSE_SWIPE_EFFECT',1000),hp-1)
 mon.hp=1;T.eq(query('ENDEAVOR_EFFECT',1),hp-1)
 mon.hp=mon.maxHp;target.hp=1
 damage,info=query('ENDEAVOR_EFFECT',1);T.eq(damage,0);T.eq(info.failed,true)
 target.hp=hp
 local variable=query('RETURN_EFFECT',1)
 local ordinary=query('NO_ADDITIONAL_EFFECT',102)
 T.eq(variable,ordinary,'native dynamic power uses the same formula')
 local failedBefore=target.hp
 opts.rng=function(lo,hi)return hi or lo end
 damage,info=query('PRESENT_EFFECT',1)
 T.eq(damage,0);T.eq(info.failed,true);T.eq(target.hp,failedBefore,'a damage query cannot heal its target')
 -- Merged mod records receive detached operands and the actual native
 -- computeDamage callback. They cannot consume PP or HP on a resident.
 g.data.move_effects={QUERY={chooseDamage=function(ctx)
  ctx.user.mon.hp=1;ctx.user.mon.moves[1].pp=0
  ctx.target.mon.hp=0
  return 19,{crit=false,typeMult=10}
 end}}
 row.effect,row.power='QUERY',1
 g.stack:push(b)
 local st=require('src.core.game3.battle').getState()
 local residentHP,residentPP=b.player.mon.hp,b.player.mon.moves[1].pp
 T.eq(Damage.calc({mon=st.player.mon},{mon=st.enemy.mon},33,opts),19)
 T.eq(b.player.mon.hp,residentHP);T.eq(b.player.mon.moves[1].pp,residentPP)
 T.eq(mon.pp[1],pp)
 b.result='run';b:finish();f.close()
 require('src.core.Game3').release()
end
package.loaded['src.core.Game']=original
T.finish('native companion fixed, dynamic and detached effect damage')
