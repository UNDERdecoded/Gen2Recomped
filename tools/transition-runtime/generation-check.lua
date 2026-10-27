package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local V=require('src.core.GameVersion')
local Native=require('src.render.BattleTransition')
local Source=require('src.core.game3.battle_transition')
local game={data={maps={},gen5_encounter_effects={}},save={},stack={top=function()end}}
for _,edition in ipairs({'red','crystal'})do
  V.set(edition);T.eq(getmetatable(Native.new(game,nil,{})),Native,'classic admission remains native')
  T.eq(Source.isActive(),false,'GBA observations decline another generation')
end
V.set('platinum')
T.eq(getmetatable(Native.new(game,nil,{})),require('src.render.Gen4BattleTransition'),'real Gen4 constructor still receives its admission')
for _,edition in ipairs({'black','white'})do
  V.set(edition)
  local state=Native.new(game,nil,{species=494})
  T.eq(getmetatable(state),require('src.render.Gen5BattleTransition'),'real Gen5 constructor remains authoritative')
  T.eq(state.frame,0);T.eq(Source.tick(),nil);T.eq(state.frame,0,'source queries do not tick a Gen5 admission')
  T.eq(Source.isActive(),false)
  T.eq(getmetatable(Native.new(game,nil,{forceClassic=true})),Native,'explicit classic mode remains available')
end
T.finish('native transition generation delegation')
