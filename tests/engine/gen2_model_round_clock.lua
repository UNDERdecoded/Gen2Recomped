-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- An actual API2 consumer observes the native round clock at execution edges.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local old=V.get()
for _,edition in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 data.moves.QA_CLOCK={id='QA_CLOCK',name='CLOCK',power=0,type='NORMAL',accuracy=100,pp=20,effect='ENDURE_EFFECT'}
 local run=T.sdk.loadMods({'mods/round_clock'},{data=data,fs=T.sdk.memfs({
  ['mods/round_clock/manifest.json']='{"id":"round_clock","name":"Round clock","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/round_clock/main.lua']=[[
   local mod=...
   mod.exports.rows={}
   for _,name in ipairs{'battle.turn_started','battle.move_used','battle.turn_ended'}do
    local eventName=name
    mod.events:on(name,function(event)
     local b=event.battle
     mod.exports.rows[#mod.exports.rows+1]={name=eventName,turn=b.battle.turn,native=b.turnCount,eventTurn=event.turn}
    end)
   end
   mod.exports.read=function(model)return model.turn end
  ]],
 })})
 T.eq(#run.errors,0,'real API2 round observer loads')
 require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',30)}
 save.party[1].moves={{id='QA_CLOCK',pp=20}}
 local b=Screen.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',30)
 b.enemy.curMoves={{id='QA_CLOCK',pp=20}}
 b.enemyAction=function()return b.enemy.curMoves[1]end
 local probe=run.loader.exports.round_clock
 local model=b.battle
 T.eq(probe.read(model),0,edition..' starts at source round zero')
 T.eq(b.turnCount,nil,'reading initial round does not initialize native state')
 for round=1,3 do
  local pp=b.player.mon.moves[1].pp
  b.queue={};b:resolveTurn(b.player.curMoves[1])
  T.eq(probe.read(model),round,'actual queued native round reaches public model')
  local queued=#b.queue
  for _=1,10 do T.eq(probe.read(model),round,'repeated observations never advance a round')end
  T.eq(#b.queue,queued,'clock observation cannot drain native actions')
  T.eq(b.player.mon.moves[1].pp,pp,'clock observation cannot spend PP')
  -- Run the actual two chosen moves; their callback reads must see the same
  -- round as the earlier turn-start callback, not a per-move/frame counter.
  local first,second=b.queue[1],b.queue[2]
  T.check(first and second and first.fn and second.fn,'native planner queues both actual actions')
  -- This older host executes action rows inline in updateQueue; the newer
  -- runQueueAction helper belongs to a separately offered prerequisite.
  -- Execute the actual planner-owned closures with that host's insertion
  -- context, rather than adding a fake helper or a second move executor.
  for _,item in ipairs{first,second}do
   b.nextInsert=0;item.fn();b.nextInsert=nil;b.current=nil
  end
  T.eq(b.player.mon.moves[1].pp,pp-1,'actual native move spends PP once')
  T.eq(probe.read(model),round,'both actual moves share one round')
  b:endOfTurn()
  T.eq(probe.read(model),round,'residual processing does not create a new round')
 end
 local starts,moves,ends=0,0,0
 for _,row in ipairs(probe.rows)do
  T.eq(row.turn,row.native,'API2 execution event sees actual native round')
  if row.eventTurn then T.eq(row.turn,row.eventTurn,'public model agrees with native event round')end
  if row.name=='battle.turn_started'then starts=starts+1
  elseif row.name=='battle.move_used'then moves=moves+1
  elseif row.name=='battle.turn_ended'then ends=ends+1 end
 end
 T.eq(starts,3,'one real start callback per chosen round')
 T.eq(moves,6,'both sides execute in every real round')
 T.eq(ends,3,'one real residual completion callback per round')
 T.eq(save.party[1].turn,nil,'round state never enters a party Pokemon')
 T.eq(save.turn,nil,'round state never enters persistent save data')
 local incoming=save.party[2]
 b:switchPlayerInto(Screen.POS.PLAYER_LEFT,incoming)
 T.eq(model.player,incoming,'native switch really replaces the player')
 T.eq(probe.read(model),3,'native switch does not reset battle-wide clock')
 T.eq(#run.errors,0,'no swallowed source callback error')
 run.release()
end
V.set(old)
T.finish('native GSC source model round clock at actual queue and API2 event edges')
