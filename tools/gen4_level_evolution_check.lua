package.path = './?.lua;' .. package.path
love = require('tests.love_stub')
local T = require('tests.harness').suite('Gen4 level evolution')
local E = require('src.pokemon.Evolution')
local Species = require('src.import.Gen4Species')
local function word(n) return string.char(n % 256, math.floor(n / 256)) end
for _, version in ipairs({'diamond', 'pearl', 'platinum'}) do
  require('src.core.GameVersion').set(version)
  local rows = Species.parseEvolutions(word(4)..word(18)..word(388)..string.rep(string.char(0),36))
  local game = {data={pokemon={[387]={evolutions=rows}},items={}}}
  local mon = {species=387,level=17}
  T.eq(E.pendingFor(game,mon,{kind='levelup'}),nil,version..' below level')
  mon.level=18
  T.eq(E.pendingFor(game,mon,{kind='levelup'}),388,version..' imported Turtwig evolves')
  game.save={party={mon}}
  local original=E.evolve;local target,done
  E.evolve=function(_,_,into,callback)target=into;callback()end
  T.eq(E.checkParty(game,function()done=true end,{[mon]=true}),1,version..' battle queues an evolution')
  T.eq(target,388,version..' battle passes the numeric ROM species target')
  T.check(done,version..' battle completes the evolution queue')
  E.evolve=original
  T.eq(E.pendingFor(game,mon,{kind='manual'}),nil,version..' level-up trigger required')
  game.data.items[112]={key='EVERSTONE'}; mon.item=112
  T.eq(E.pendingFor(game,mon,{kind='levelup'}),nil,version..' Everstone blocks')
end
T.finish()
