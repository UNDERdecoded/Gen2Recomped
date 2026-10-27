-- Copyright (c) 2026 Roxas2712. Contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Save=require('src.core.SaveData')
local Pokemon=require('src.pokemon.Pokemon')
local Battle=require('src.battle.BattleState')
local Defaults=require('src.battle.RulesetDefaults')
local old=V.get()
local function fixture(version,choice)
 V.set(version)
 local data=T.fixtures.fresh();data.constants.gen=V.generation()
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
 if choice~=nil then save.options.ruleset=choice end
 local game={data=data,save=save,input={wasPressed=function()return false end},stack={top=function()end}}
 return game,Battle.newWild(game,'FIXMON_C',3)
end
T.eq(Save.defaultOptions().ruleset,false,'new settings retain automatic cartridge selection')
for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 local game,b=fixture(version)
 T.eq(Defaults.defaultFor(game),'gen2_finite_pp','native generation has a bounded PP compatibility default')
 T.eq(b.ruleset.name,'gen2_finite_pp','actual fresh battle constructor chooses native finite PP')
 local move=b.enemy.curMoves[1];move.pp=1
 b:executeAction(b.enemy,b.player,move)
 T.eq(move.pp,0,'actual native enemy spends its final PP')
 T.eq(b:enemyAction().id,'STRUGGLE','actual enemy selection falls back after PP exhaustion')
 game,b=fixture(version,'gen1_faithful')
 T.eq(b.ruleset.name,'gen1_faithful','an explicitly saved Gen1 rule remains selected')
 move=b.enemy.curMoves[1];move.pp=1;b:executeAction(b.enemy,b.player,move)
 T.eq(move.pp,1,'explicit unlimited enemy PP choice is honored')
 game,b=fixture(version,'modern_clean')
 T.eq(b.ruleset.name,'modern_clean','explicit alternative rule remains selected')
 move=b.enemy.curMoves[1];move.pp=1;b:executeAction(b.enemy,b.player,move)
 T.eq(move.pp,0,'explicit finite alternative still spends native PP')
 local Options=require('src.ui.OptionsMenu');game,b=fixture(version)
 local menu=Options.new(game);local row
 for _,r in ipairs(menu.rows)do if r.id=='ruleset'then row=r end end
 T.check(row~=nil,'actual options screen retains ruleset selection')
 if row then
  T.eq(row.value(game),'AUTO','automatic choice is displayed honestly')
  row.step(game,1);T.check(game.save.options.ruleset~=false,'ordinary option input reaches explicit rules')
  row.step(game,-1);T.eq(game.save.options.ruleset,false,'ordinary option input can return to automatic')
 end
end
local game,b=fixture('red');T.eq(b.ruleset.name,'gen1_faithful','native Gen1 keeps its original default behavior')
local move=b.enemy.curMoves[1];move.pp=1;b:executeAction(b.enemy,b.player,move)
T.eq(move.pp,1,'native Gen1 retains unlimited enemy PP')
V.set(old)
T.finish('native upstream Gen2 finite enemy PP defaults and explicit choices')
