package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local V = require('src.core.GameVersion')
local Battle = require('src.battle.BattleState')
local Pokemon = require('src.pokemon.Pokemon')
local Save = require('src.core.SaveData')
local before = V.get()
local function fixture(version)
  V.set(version)
  local data = T.fixtures.fresh(); data.constants.gen = V.generation(version)
  require('src.render.Font').load(data)
  local save = Save.newGame()
  save.party = {Pokemon.new(data, 'FIXMON_A', 30), Pokemon.new(data, 'FIXMON_B', 18)}
  local game = {data=data, save=save, stack={top=function()end}}
  return Battle.newWild(game, 'FIXMON_C', 23), game
end
for _, version in ipairs({'gold','silver','crystal','prism','polishedcrystal'}) do
  local b, game = fixture(version)
  local model, hp = rawget(b,'battle'), b.shownHp
  T.check(model ~= b, version .. ' publishes a distinct native model view')
  T.eq(model.player, game.save.party[1], 'model player is the actual saved Pokemon')
  T.eq(model.enemy, b.enemy.mon, 'model enemy is actual generated wild Pokemon')
  T.eq(model.enemy.level, 23, 'enemy level is live, not a wrapper default')
  T.eq(model.player.level, 30, 'player level is live')
  T.eq(model.party, game.save.party, 'no copied party')
  T.eq(model.save, game.save, 'actual save owner')
  T.eq(model.data, game.data, 'actual data owner')
  T.eq(model.wild, true, 'native wild classification')
  T.eq(model.playerIndex, 1, 'actual active party index')
  T.eq(b:activeMon('enemy'), model.enemy, 'presentation follows current native slot')
  T.eq(b:activeMon('unknown'), nil, 'unknown side is not another active mon')
  T.eq(hp.enemy, b.enemy.shownHP, 'shown HP reads native drain')
  local initial = b.enemy.mon.hp
  b:performMove(b.player, b.enemy, {id='FIX_TACKLE',pp=10})
  T.check(b.enemy.mon.hp < initial, 'actual native move reduces HP')
  T.eq(model.enemy.hp, b.enemy.mon.hp, 'model exposes resolved HP')
  T.eq(hp.enemy, initial, 'presentation retains pre-drain HP')
  local frames = 0
  while b:stepHPDrain() and frames < 2000 do
    frames=frames+1
    T.eq(hp.enemy, b.enemy.shownHP, 'every displayed HP step is native owned')
  end
  T.check(frames > 0 and frames < 2000, 'actual drain completes')
  T.eq(hp.enemy, model.enemy.hp, 'shown HP reaches actual HP')
  local old = b.player
  b:switchPlayerInto(Battle.POS.PLAYER_LEFT, game.save.party[2])
  T.eq(b.battle, model, 'model identity survives actual native switch')
  T.eq(b.shownHp, hp, 'HP view identity survives switch')
  T.eq(model.player, game.save.party[2], 'model follows incoming actual Pokemon')
  T.eq(model.playerIndex, 2, 'live party index follows switch')
  T.eq(b:activeMon('player'), game.save.party[2], 'drawn mon follows native deployment')
  T.eq(hp.player, b.player.shownHP, 'new slot uses its own HP drain')
  T.neq(b.player, old, 'wrapper actually replaced')
  T.eq(game.save.party[1].shownHP, nil, 'no presentation fields added to saved Pokemon')
  T.raises(function() model.player = old.mon end, 'read-only', 'model cannot write a detached Pokemon')
  T.raises(function() hp.player = 0 end, 'stepHPDrain', 'view cannot race native HP clock')
  b.result='run'
  T.eq(model.over, true, 'actual result closes model')
  T.eq(model.outcome, 'run', 'actual outcome exposed')
end

-- The new render boundary must use front art for isolated player captures
-- without changing the native rear, slot identity, or animation ownership.
do
  local b = fixture('crystal'); b.introSlide=0; b.sendingOut=false
  local original, player = b.player.sprite, b.player
  local draws, draw = {}, love.graphics.draw
  love.graphics.draw=function(...) draws[#draws+1]={...} end -- output only
  b:drawPic(player.mon, false)
  T.eq(#draws, 1, 'player front capture draws real native sprite')
  local front, _, path = b:pic(player.mon, false)
  T.eq(draws[1][1], front, 'front capture uses actual front image')
  T.check(path:find('front',1,true) ~= nil, 'front request resolves front asset')
  T.eq(b.player, player, 'rendering preserves native battler identity')
  T.eq(player.sprite, original, 'native rear image is retained')
  T.eq(draws[1][3] + front:getHeight(), 56, 'front feet end at native seven-tile baseline')
  draws={}; b:drawPic(player.mon, true)
  T.eq(draws[1][1], b:picImage(original), 'native rear remains available')
  local pf=b:picFxFor(player);pf.hidden=true
  draws={};b:drawPic(player.mon,false)
  T.eq(#draws,0,'native vanish effect hides isolated front too')
  pf.hidden=nil;b.fx={blink={target=player,frames=10}};b.frame=0
  draws={};b:drawPic(player.mon,false)
  T.eq(#draws,0,'native damage blink stays keyed to real player')
  b.fx={faint={battler=player,frames=7}};player.fainted=true
  draws={};b:drawPic(player.mon,false)
  T.eq(#draws,1,'real native faint sink can still draw its remaining rows')
  b.fx.faint.frames=0;draws={};b:drawPic(player.mon,false)
  T.eq(#draws,0,'completed native faint stays hidden')
  player.fainted=nil;b.fx=nil;pf.kind='shakeBF'
  local intersect,get=love.graphics.intersectScissor,love.graphics.getScissor
  local clips={}
  love.graphics.intersectScissor=function(...)clips[#clips+1]={...}end
  love.graphics.getScissor=function()end
  b:drawPic(player.mon,false)
  T.check(#clips>0,'effect capture has an actual bounded picture window')
  for _,clip in ipairs(clips)do
    T.check(clip[1]>=96,'front player effect is never clipped by native rear-side window')
  end
  love.graphics.intersectScissor,love.graphics.getScissor=intersect,get
  love.graphics.draw=draw
end
for _, version in ipairs({'red','firered','emerald'}) do
  local b = fixture(version)
  T.eq(b.battle,b,version .. ' retains its existing model identity')
  T.eq(b.shownHp,nil,'other generations retain existing HP presentation')
end
V.set(before)
T.finish('native Gen2 live battle model and sprite capture')
