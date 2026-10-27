-- Native calculation and completion paths, decorated through the real SDK.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Version = require('src.core.GameVersion')
local Screen = require('src.battle.BattleState')
local Model = require('src.battle.gen2.Battle')
local Read = require('src.battle.Gen2BattleRead')
local Pokemon = require('src.pokemon.Pokemon')
local Save = require('src.core.SaveData')
local Order = require('src.battle.TurnOrder')
local Status = require('src.battle.StatusRegistry')
local Effects = require('src.battle.MoveEffects')
local savedVersion = Version.get()
local nativeStat, nativeDef, nativeEnd = Model.battleStat, Model.speciesDef, Model.endBattle

local function fixture(version)
  Version.set(version)
  local data = T.fixtures.fresh()
  data.constants.gen, data.constants.generation = Version.generation(version), Version.generation(version)
  data.type_chart.matchups[#data.type_chart.matchups+1] = {
    attacker='NORMAL', defender='GHOST', multiplier=0,
  }
  local run = T.sdk.loadMods({'mods/model_probe'}, {
    data=data, fs=T.sdk.memfs({
      ['mods/model_probe/manifest.json']=[[{
        "id":"model_probe","name":"Native model probe","version":"1.0.0",
        "api":2,"entry":"main.lua","affects_link":true
      }]],
      ['mods/model_probe/main.lua']=[[
        local mod=...
        local Model=require('src.battle.gen2.Battle')
        local stat,def,finish=Model.battleStat,Model.speciesDef,Model.endBattle
        mod.exports.scale=1
        Model.battleStat=function(model,mon,key)
          local value=stat(model,mon,key)
          if mon==model.player and (key=='attack' or key=='speed') then
            return value*mod.exports.scale
          end
          return value
        end
        Model.speciesDef=function(model,mon)
          local value=def(model,mon)
          if not (value and mon==model.enemy and mod.exports.types) then return value end
          local result={};for key,item in pairs(value)do result[key]=item end
          result.types=mod.exports.types
          return result
        end
        Model.endBattle=function(model,...)
          if model.player then model.player._probeTransient=nil end
          mod.exports.endCalls=(mod.exports.endCalls or 0)+1
          return finish(model,...)
        end
        mod.events:on('battle.ended',function(event)
          mod.exports.ended=(mod.exports.ended or 0)+1
          mod.exports.event=event
          mod.exports.cleanAtEvent=not(event.model and event.model.player
            and event.model.player._probeTransient)
        end)
      ]],
    }),
  })
  T.eq(#run.errors,0,version..' real SDK model decorator loads')
  require('src.render.Font').load(data)
  local save=Save.newGame()
  save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',18)}
  local game={data=data,save=save}
  local stack={states={},pops=0}
  function stack:top()return self.states[#self.states]end
  function stack:pop()self.pops=self.pops+1;return table.remove(self.states)end
  function stack:push(state)self.states[#self.states+1]=state end
  game.stack=stack
  local battle=Screen.newWild(game,'FIXMON_C',23)
  stack.states={{},battle}
  return battle,game,run,assert(run.loader.exports.model_probe)
end

for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
  local b,game,run,probe=fixture(version)
  local model=b.battle
  local supported=type(model.battleStat)=='function' and type(model.speciesDef)=='function'
  T.check(supported,version..' actual model resolves the genuine model class')
  T.check(model~=b,version..' screen and model stay distinct')
  T.eq(model.player,game.save.party[1],'model retains live party identity')
  T.eq(model.moveDef,Model.moveDef,'method lookup retains the class decoration seam')
  if supported then
    T.eq(model:speciesDef(model.player),game.data.pokemon[model.player.species],'actual species catalog row')
    T.eq(model:speciesDef(nil),nil,'no invented missing species')
    T.eq(model:battleStat(model.player,'attack'),b.player.curStats.attack,'native raw stat authority')
    T.eq(model:battleStat({},'attack'),nil,'unknown stat stays absent')
    T.eq(model:sideOf(model.player),'player','native player side')
    T.eq(model:sideOf(model.enemy),'enemy','native enemy side')
  end
  T.eq(Read.stats(b.player).attack,b.player.curStats.attack,'default decorated read keeps native values')
  local playerStats,enemyStats=b.player.curStats,b.enemy.curStats
  local partyStats,types=b.player.mon.stats,b.enemy.def.types
  local pp=b.player.curMoves[1].pp
  local move=b:moveDef(b.player.curMoves[1])
  local function damage()
    return b:computeDamage(b.player,b.enemy,move,{forceCrit=false,rng=function(lo,hi)return hi or lo end})
  end
  local normal=damage()
  local speed=Order.effectiveSpeed(b.player,b)
  probe.scale=4
  local boosted=damage()
  T.check(boosted>normal,version..' actual native damage consumes decorated model stat')
  T.check(Order.effectiveSpeed(b.player,b)>speed,'actual native speed consumes same model stat')
  T.eq(b.player.curStats,playerStats,'native stat table identity is retained')
  T.eq(b.enemy.curStats,enemyStats,'native opposing stat table is retained')
  T.eq(b.player.mon.stats,partyStats,'save stats are not replaced')
  T.eq(b.player.curMoves[1].pp,pp,'queries cannot spend PP')
  T.eq(Read.stats(b.player).attack,partyStats.attack*4,'live value has no frame cache')
  probe.scale=1
  T.eq(damage(),normal,'removing presentation-owned stat override restores native damage')
  probe.types={'GHOST'}
  T.eq(damage(),0,'actual damage honors model species type immunity')
  T.eq(b.enemy.def.types,types,'species registry type list is not replaced')
  T.eq(b.enemy.curTypes,types,'native volatile type list is not replaced')
  probe.types={'FIRE'}
  b.enemy.mon.status=nil
  Status.inflict(b,b.enemy,'BRN',{})
  T.eq(b.enemy.mon.status,nil,'actual native status immunity honors model type')
  probe.types={'NORMAL'}
  Status.inflict(b,b.enemy,'BRN',{})
  T.eq(b.enemy.mon.status,'BRN','removing immunity restores native status path')
  b.enemy.mon.status=nil
  b.enemy.curTypes={'WATER'}
  probe.types={'GHOST'}
  T.eq(Read.types(b.enemy)[1],'WATER','native Conversion list wins over a species decoration')
  T.check(damage()>0,'volatile type override reaches actual damage')
  b.enemy.curTypes=types
  probe.types=nil
  local old=b.player
  b:switchPlayerInto(Screen.POS.PLAYER_LEFT,game.save.party[2])
  T.eq(model.player,game.save.party[2],'model follows actual native switch')
  probe.scale=2
  T.eq(Read.stats(b.player).attack,b.player.curStats.attack*2,'new native battler is bound')
  T.neq(b.player,old,'native wrapper really changed')
  probe.scale=1
  -- Native Transform keeps temporary stats on its wrapper, never the save.
  -- Link/scaffold owners use the public factory without a screen argument,
  -- then place/synchronize their actual wrappers on the native controller.
  local placed=Screen.makeBattler(game.data,game.save.party[1],true,nil)
  b:placeBattler(Screen.POS.PLAYER_LEFT,placed)
  probe.scale=3
  T.eq(Read.stats(placed).attack,placed.curStats.attack*3,'native placement binds a public-factory wrapper')
  local rebound=Screen.makeBattler(game.data,game.save.party[2],true,nil)
  b.player=rebound
  b:syncSides()
  T.eq(Read.stats(rebound).attack,rebound.curStats.attack*3,'native side synchronization binds external wrappers')
  T.eq(model.player,game.save.party[2],'external native replacement retains live model identity')
  probe.scale=1
  local source=b.enemy.curStats.attack
  Effects.primary.TRANSFORM_EFFECT(b,b.player,b.enemy)
  if supported then T.eq(model:battleStat(model.player,'attack'),source,'Transform uses actual native volatile stat')end
  T.eq(model.player.stats,game.save.party[2].stats,'Transform does not replace saved stats')
  model.player._probeTransient=true
  b.result=({gold='ended',silver='hostWin',crystal='guestWin',prism='draw'})[version]
  local outcome=b.result
  local complete=type(b.completeBattle)=='function'
  T.check(complete,'native Gen2 completion seam exists')
  if complete then
    b:completeBattle()
    T.eq(probe.ended,1,'actual native finish emits one ended event')
    T.eq(probe.event.result,outcome or 'run','notification retains the native event fallback')
    T.eq(b.result,outcome,'notification does not persist an event-only fallback')
    T.eq(probe.event.battle,b,'existing native consumers retain their screen owner')
    T.eq(probe.event.model,model,'notification also exposes actual live model')
    T.check(probe.cleanAtEvent,'model end decoration cleans before native end notification')
    T.eq(game.stack.pops,1,'completion uses native stack return once')
    b:completeBattle()
    T.eq(game.stack.pops,1,'repeated completion cannot pop another screen')
    if type(model.endBattle)=='function'then model:endBattle('run')end
    T.eq(probe.ended,1,'repeated model completion cannot re-emit ended event')
  end
  require('src.mods.Loader').teardown()
  run.release()
  T.eq(Model.battleStat,nativeStat,'loader retirement restores model stat method')
  T.eq(Model.speciesDef,nativeDef,'loader retirement restores model species method')
  T.eq(Model.endBattle,nativeEnd,'loader retirement restores model end method')
  T.eq(Read.stats(b.player),b.player.curStats,'undecorated read returns original stat table')
  T.eq(Read.types(b.enemy),b.enemy.curTypes,'undecorated read returns original type list')
end
for _,version in ipairs({'red','firered','emerald'})do
  local b,game,run,probe=fixture(version)
  T.eq(b.battle,b,version..' keeps its original shared native identity')
  probe.scale=9;probe.types={'GHOST'}
  T.eq(Read.stats(b.player),b.player.curStats,'other generation retains exact raw stat table')
  T.eq(Read.types(b.enemy),b.enemy.curTypes,'other generation retains exact raw type list')
  require('src.mods.Loader').teardown()
  run.release()
end
Version.set(savedVersion)
T.finish('native Gen2 model calculation and completion boundary')
