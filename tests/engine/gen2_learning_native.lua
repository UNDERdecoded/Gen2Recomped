-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local Pokemon=require('src.pokemon.Pokemon')
local Native=require('src.battle.BattleState')
local Save=require('src.core.SaveData')
local ids={'FIX_TACKLE','FIX_SCRATCH','FIX_EMBERISH','FIX_CUT','QA_FIVE'}
for _,edition in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 data.moves.QA_FIVE={name='SYNTHETIC FIVE',pp=7,type='NORMAL',power=1,accuracy=100,effect='NO_ADDITIONAL_EFFECT'}
 local def=data.pokemon.FIXMON_A
 def.level1Moves={ids[1],ids[2],ids[3],ids[4]}
 def.learnset={{level=2,move=ids[5]},{level=3,move=ids[1]}}
 local loaded=T.sdk.loadMods({'mods/learning_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/learning_probe/manifest.json']='{"id":"learning_probe","name":"Learning probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/learning_probe/main.lua']=[[
   local mod=...
   mod.exports.Mon=require('src.battle.gen2.Mon');mod.exports.events={}
   mod.events:on('pokemon.move_learned',function(ev)
    mod.exports.events[#mod.exports.events+1]={mon=ev.mon,id=ev.moveId,slot=ev.mon.moves[#ev.mon.moves]}
   end)
  ]],
 })})
 T.eq(#loaded.errors,0,'source learner consumer loads')
 local probe=loaded.loader.exports.learning_probe
 local Mon=probe.Mon
 T.eq(type(Mon.learnMove),'function','actual SDK supplies source learnMove')
 if type(Mon.learnMove)~='function'then loaded.release();V.set(old);T.finish('missing source learning API')end
 local expected={ids[3],ids[4],ids[5],ids[1]}
 T.same(Pokemon.movesAtLevel(def,3),expected,'actual native rolling window can relearn a forgotten move')
 local mon=Pokemon.new(data,'FIXMON_A',3)
 local learned={};for _,slot in ipairs(mon.moves)do learned[#learned+1]=slot.id end
 T.same(learned,expected,'actual native arrival constructor uses the corrected rolling window')
 local source={levelMoves={}}
 for i,id in ipairs{ids[1],ids[2],ids[3],ids[4],ids[5],ids[1]}do source.levelMoves[i]={level=i,move=id}end
 local slots=Mon.movesAtLevel(source,6,data.moves)
 T.eq(#slots,4)
 for i,id in ipairs(expected)do T.same(slots[i],{id=id,pp=data.moves[id].pp,maxPp=data.moves[id].pp})end
 local unknown=Mon.movesAtLevel(source,6)
 for i,id in ipairs(expected)do T.same(unknown[i],{id=id,pp=0,maxPp=0},'source no-definition query still returns slots, not bare IDs')end
 T.same(Mon.movesAtLevel({levelMoves={{level=1,move=ids[1]},{level=1,move=ids[1]}}},1,data.moves),
  {{id=ids[1],pp=data.moves[ids[1]].pp,maxPp=data.moves[ids[1]].pp}},'currently known duplicate is skipped')
 T.same(Mon.movesAtLevel(nil,5),{})
 local owned=Pokemon.new(data,'FIXMON_A',1);owned.moves={{id=ids[1],pp=1}}
 local original=owned.moves
 T.eq(Mon.learnMove(owned,ids[2],data),true,'source learner appends when free')
 T.eq(owned.moves,original,'learner retains actual native moves table')
 T.eq(#probe.events,1)
 T.eq(probe.events[1].mon,owned);T.eq(probe.events[1].slot,owned.moves[2],'event sees actual newly stored native slot')
 T.same(owned.moves[2],{id=ids[2],pp=data.moves[ids[2]].pp,maxPp=data.moves[ids[2]].pp})
 local ok,reason=Mon.learnMove(owned,ids[2],data)
 T.eq(ok,false);T.eq(reason,'known');T.eq(#probe.events,1,'known move emits nothing')
 owned.moves[3]={id=ids[3],pp=1};owned.moves[4]={id=ids[4],pp=1}
 local entry;ok,reason,entry=Mon.learnMove(owned,ids[5],data)
 T.eq(ok,false);T.eq(reason,'full')
 T.same(entry,{id=ids[5],pp=7,maxPp=7});T.eq(#owned.moves,4);T.eq(#probe.events,1)
 T.neq(entry,owned.moves[4],'pending full-slot choice is not silently installed')
 local literal={}
 T.eq(Mon.learnMove(literal,'SOURCE_UNKNOWN',{}),true,'source learner permits an explicit undefined move with zero PP')
 T.same(literal.moves,{{id='SOURCE_UNKNOWN',pp=0,maxPp=0}})
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',10)}
 local g={data=data,save=save,stack={top=function()end}}
 require('src.render.Font').load(data)
 local battle=Native.newWild(g,'FIXMON_B',5)
 local real=battle.player.mon;real.moves={{id=ids[1],pp=1}}
 probe.events={};battle.queue={};battle.nextInsert=0
 battle:learnMove(real,ids[2])
 T.same(real.moves[2],{id=ids[2],pp=data.moves[ids[2]].pp,maxPp=data.moves[ids[2]].pp},'actual native battle free-slot teaching shares source slot shape')
 T.eq(#probe.events,1,'native message/presentation path does not duplicate learned event')
 T.eq(probe.events[1].mon,real);T.eq(probe.events[1].slot,real.moves[2])
 battle:learnMove(real,ids[2]);T.eq(#probe.events,1,'native duplicate policy agrees with public source learner')
 loaded.release()
end
-- Other generations retain the existing native globally unique arrival list.
for _,edition in ipairs{'red','emerald','firered'}do
 V.set(edition)
 local d={level1Moves={'A','B','C','D'},learnset={{level=2,move='E'},{level=3,move='A'}}}
 T.same(Pokemon.movesAtLevel(d,3),{'B','C','D','E'},'non-GSC arrival rules remain selected by their native owner')
end
V.set(old)
T.finish('actual source and native GSC rolling moves, relearning, free/known/full slots and single learned events')
