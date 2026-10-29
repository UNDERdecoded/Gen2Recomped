-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- GSC's GetMovePriority precedes Speed. Exercise the shared comparator, the
-- actual native queued turn, and the public live-model query together.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Order=require('src.battle.TurnOrder')
local Save=require('src.core.SaveData')
local saved=Version.get()
local cases={
 {id='QA_PROTECT',effect='PROTECT_EFFECT',priority=3},
 {id='QA_ENDURE',effect='ENDURE_EFFECT',priority=3},
 {id='QA_COUNTER',effect='COUNTER_EFFECT',priority=-1},
 {id='QA_MIRROR',effect='MIRROR_COAT_EFFECT',priority=-1},
 {id='VITAL_THROW',effect='ALWAYS_HIT_EFFECT',priority=-1},
 {id='ROAR',effect='SWITCH_AND_TELEPORT_EFFECT',priority=-1},
 {id='WHIRLWIND',effect='SWITCH_AND_TELEPORT_EFFECT',priority=-1},
 {id='TELEPORT',effect='SWITCH_AND_TELEPORT_EFFECT',priority=0},
}
local function fixture(version,chosen)
 Version.set(version)
 local data=T.fixtures.fresh();data.constants.gen=2
 for _,row in ipairs(cases)do
  data.moves[row.id]={id=row.id,name=row.id,effect=row.effect,power=0,type='NORMAL',accuracy=100,pp=10}
 end
 local run=T.sdk.loadNone({data=data})
 require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',25)}
 save.party[1].moves={{id=chosen or 'QA_PROTECT',pp=10}}
 local game={data=data,save=save,stack={top=function()end}}
 local b=Screen.newWild(game,'FIXMON_B',25)
 b.rng=function(lo)return lo end
 return b,run
end
for _,version in ipairs{'gold','silver','crystal'}do
 local b,run=fixture(version)
 local a,z=b.player,b.enemy
 local plain=b.data.moves.FIX_TACKLE
 for _,row in ipairs(cases)do
  local move=b.data.moves[row.id]
  a.curStats.speed=row.priority>0 and 1 or 999
  z.curStats.speed=row.priority>0 and 999 or 1
  local expect=row.priority>=0
  T.eq(Order.firstMover(a,move,z,plain,b.rng,false,b,b.data),expect,
   version..' native effect priority for '..row.id)
  T.eq(b.battle:movePriority(row.id),row.priority,'public live-model priority agrees: '..row.id)
 end
 local explicit={id='QA_EXPLICIT',effect='PROTECT_EFFECT',priority=-7}
 T.eq(Order.firstMover(a,explicit,z,plain,b.rng,false,b,b.data),false,'explicit native mod priority still wins')
 b.data.moves[explicit.id]=explicit
 T.eq(b.battle:movePriority(explicit.id),-7,'model uses the same explicit override')
 T.eq(b.battle:movePriority('UNKNOWN_NATIVE_MOVE'),0,'missing priority stays neutral')
 run.release()
 for _,id in ipairs{'QA_PROTECT','QA_ENDURE'}do
  local battle,owner=fixture(version,id)
  battle.player.curStats.speed=1;battle.enemy.curStats.speed=999
  local selected=battle.player.curMoves[1]
  local enemyMove=battle.enemy.curMoves[1]
  -- Fix only the legal AI choice; the turn planner, queue closures, move
  -- execution, PP and protection handlers below are the genuine owners.
  battle.enemyAction=function()return enemyMove end
  battle.queue={}
  local hp=battle.player.mon.hp
  battle:resolveTurn(selected)
  local first,second=battle.queue[1],battle.queue[2]
  T.check(first and second and first.fn and second.fn,'native turn queued both actual actions')
  battle.nextInsert=0;first.fn();battle.nextInsert=nil
  local field=id=='QA_PROTECT'and'protecting'or'enduring'
  T.eq(battle.player[field],true,'slow '..id..' really executes before the faster enemy')
  T.eq(selected.pp,9,'actual first move spends one PP')
  if id=='QA_PROTECT'then
   battle.nextInsert=0;second.fn();battle.nextInsert=nil
   T.eq(battle.player.mon.hp,hp,'faster enemy attack is blocked by the actual protection state')
  end
  owner.release()
 end
end
-- The added effect fallback belongs only to the GSC controller. Preserve
-- other generations' explicit imported priorities and legacy ID behavior.
for _,version in ipairs{'red','firered','emerald','heartgold','black'}do
 Version.set(version)
 local a={curStats={speed=1},stages={},mon={hp=100,stats={speed=1}}}
 local z={curStats={speed=999},stages={},mon={hp=100,stats={speed=999}}}
 T.eq(Order.firstMover(a,{id='QA_OTHER',effect='PROTECT_EFFECT'},z,{id='PLAIN'},function(lo)return lo end),false,
  version..' retains its own priority contract')
end
Version.set(saved)
T.finish('native GSC priority, live model queries and actual protection turns')
