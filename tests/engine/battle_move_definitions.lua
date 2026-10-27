package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local oldVersion=Version.get()
for _,edition in ipairs({'red','gold','silver','crystal','prism','polishedcrystal','firered','emerald','platinum','black'})do
  Version.set(edition)
  local data=T.fixtures.fresh();data.constants.gen=Version.generation()
  local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
  local b=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
  local move=b.player.curMoves[1];local def=b:moveDef(move)
  local pp=move.pp
  T.eq(b:moveDef(move.id),def,edition..' ID and instance share the actual native definition')
  T.eq(b:moveDef('UNKNOWN_NATIVE_MOVE'),nil,'unknown ID has no invented move')
  T.eq(b:moveDef(nil),nil,'missing ID has no invented move')
  T.eq(b:moveDef({id='UNKNOWN_NATIVE_MOVE'}),nil,'unknown instance retains native behavior')
  local replacement={name='LIVE CATALOG',type='WATER',pp=17}
  data.moves[move.id]=replacement
  T.eq(b:moveDef(move.id),replacement,'ID reader follows the current catalog')
  T.eq(b:moveDef(move),replacement,'instance reader follows the same current catalog')
  data.moves[move.id]=def
  T.eq(move.pp,pp,'definition reads preserve the actual native move PP')
  if edition=='black' then
    local bw=b.bw
    b.bw={struggle={name='FIX BW STRUGGLE'}}
    T.eq(b:moveDef({id='UNKNOWN_NATIVE_MOVE',struggle=true}),b.bw.struggle,'native BW instance-specific Struggle retained')
    T.eq(b:moveDef('UNKNOWN_NATIVE_MOVE'),nil,'an unknown ID does not invent a Struggle action')
    b.bw=bw
  elseif edition=='platinum' then
    local row=data.moves[165]
    data.moves[165]={name='FIX G4 STRUGGLE',gen4Effect=254}
    T.eq(b:moveDef({id='UNKNOWN_NATIVE_MOVE',struggle=true}),data.moves[165],'native Gen4 instance-specific Struggle retained')
    data.moves[165]=row
  end
  -- Exercise the existing instance path through real native damage execution.
  local hp=b.enemy.mon.hp
  b:performMove(b.player,b.enemy,{id='FIX_TACKLE',pp=10})
  T.check(b.enemy.mon.hp<hp,'native instance resolution still executes actual damage')
end
Version.set(oldVersion)
T.finish('native move ID and instance definition authority')
