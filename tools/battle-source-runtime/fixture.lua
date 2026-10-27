-- Synthetic imported GBA records over the real native constructors. No
-- external pack, portable encounter API, player profile or ROM is required.
local F={}
function F.new(edition)
  local T=require('tests.modkit')
  require('src.core.GameVersion').set(edition)
  local data=T.fixtures.fresh()
  local row=require('src.mods.Merge').deepCopy(data.pokemon.FIXMON_A)
  row.id,row.name,row.dex,row.index='CHARMANDER','CHARMANDER',4,4
  row.types,row.level1Moves,row.learnset,row.evolutions={'NORMAL'},{'MOVE_033'},{},{}
  row.baseStats.spatk,row.baseStats.spdef=row.baseStats.special,row.baseStats.special
  row.trueColor=true
  data.pokemon.CHARMANDER=row
  data.moves.MOVE_033={id='MOVE_033',index=33,name='TACKLE',power=35,type='NORMAL',accuracy=100,
    accuracyRaw=255,pp=10,effect='NO_ADDITIONAL_EFFECT',effectChance=0,effectChanceRaw=0}
  data.constants=data.constants or{}
  data.constants.gen=3
  data.constants.speciesOrder={[4]='CHARMANDER'}
  data.constants.moveOrder={[33]='MOVE_033'}
  local game={data=data,mods={exports={}},save={party={},options={},player={name='PROBE',id=1000},
    flags={},inventory={},pokedex={seen={},caught={}},defeatedTrainers={},money=0},
    stack=setmetatable({},{__index=require('src.core.StateStack')}),
    input={wasPressed=function()return false end,isDown=function()return false end}}
  game.stack:init()
  require('src.render.Font').load(data);require('src.battle.TypeChart').load(data)
  local original=package.loaded['src.core.Game']
  local f={game=game,data=data,ids={TACKLE='MOVE_033'}}
  function f.fresh(name)
    assert(name=='TACKLE')
    local player=require('src.pokemon.Pokemon').new(data,'CHARMANDER',30,function(lo)return lo or 0 end)
    player.hp,player.stats.hp,player.moves=400,400,{{id='MOVE_033',pp=10}}
    game.save.party={player}
    local battle=require('src.battle.BattleState').newWild(game,'CHARMANDER',30)
    battle.enemy.mon.hp,battle.enemy.mon.stats.hp=400,400
    battle.rng=function(lo)return lo or 0 end
    return{battle=battle}
  end
  function f.close()
    for _,name in ipairs{'src.core.game3.battle','src.core.game3.pokemon','src.core.game3.mon_anim'}do
      local module=package.loaded[name]
      if module and module._service and module._service.release then module._service.release()end
    end
    if package.loaded['src.core.Game']==game then package.loaded['src.core.Game']=original end
  end
  return f
end
return F
