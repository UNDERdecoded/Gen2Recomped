package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Version = require('src.core.GameVersion')
local Battle = require('src.battle.BattleState')
local Pokemon = require('src.pokemon.Pokemon')
local Save = require('src.core.SaveData')
local Hp = require('src.battle.Gen2HpPresentation')
local previous = Version.get()
local function fixture(version)
  Version.set(version or 'crystal')
  local data = T.fixtures.fresh()
  data.constants.gen = Version.generation(Version.get())
  require('src.render.Font').load(data)
  local save = Save.newGame()
  save.party = {Pokemon.new(data, 'FIXMON_A', 30), Pokemon.new(data, 'FIXMON_B', 18)}
  local game = {data=data, save=save, stack={top=function()end}}
  local screen = Battle.newWild(game, 'FIXMON_C', 23)
  screen.queue, screen.current, screen.waitFrames = {}, nil, nil
  return screen
end
local function start(screen, side, from, to, maximum, floor)
  local b = screen[side]
  b.mon.stats.hp, b.mon.hp, b.shownHP = maximum, to, from
  screen:drainNext(b, floor)
  T.eq(screen:updateQueue(), true, 'actual native queue dispatches the HP row')
  T.eq(screen._gen2HpDrainBattler, b, 'drain row owns its actual battler')
  return b
end
local function finish(screen)
  local frames = 0
  while screen:updateQueuePresentation() and frames < 2000 do frames=frames+1 end
  T.check(frames < 2000, 'native HP queue terminates')
  T.eq(screen.hpAnim, nil, 'completed native row retires its presentation')
  T.eq(screen._gen2HpDrainBattler, nil, 'completed row releases admission owner')
  return frames
end

T.eq(Hp.pixels(0, 19), 0, 'fainted bar is empty')
T.eq(Hp.pixels(1, 999), 1, 'living bar retains at least one pixel')
T.eq(Hp.pixels(191, 383), 24, 'high-HP one-byte divisor retains cartridge rounding')
T.eq(Hp.pixels(190, 383), 24, 'coarse high-HP divisor differs from exact ratio')

-- These are actual shared-engine battlers and queue rows, not a second HP
-- controller. The short loop advances pixels even while the number repeats.
do
  local s = fixture()
  local enemy = start(s, 'enemy', 19, 16, 19)
  local trace = {}
  for i=1,6 do
    T.eq(s:updateQueuePresentation(), true, 'native row holds each pixel beat')
    trace[i]=s.shownHp.enemy
  end
  T.same(trace, {19,19,19,19,18,18}, 'short bar preserves two-frame pixel cadence')
  finish(s)
  T.eq(enemy.shownHP, 16, 'short bar reaches exact authoritative HP')
  T.eq(enemy.mon.hp, 16, 'presentation never changes resolved damage')
end
for _, version in ipairs({'gold','silver','crystal','prism','polishedcrystal'}) do
  for _, case in ipairs({{383,0,383}, {0,383,383}, {1,0,19}, {16,19,19}, {255,256,256}}) do
    local s=fixture(version)
    local b=start(s,'enemy',case[1],case[2],case[3])
    local exp=s.player.mon.exp
    finish(s)
    T.eq(b.shownHP,case[2],version..' damage/heal/faint reaches exact target')
    T.eq(b.mon.hp,case[2],'animation does not resolve another damage command')
    T.eq(s.player.mon.exp,exp,'HP presentation cannot award EXP')
  end
end

-- Later damage may already be resolved. Each queued multi-hit beat must stop
-- at its own floor; the other side waits for its own row as well.
do
  local s=fixture()
  s.player.mon.hp,s.player.shownHP=2,10
  local b=s.enemy
  b.mon.stats.hp,b.mon.hp,b.shownHP=19,3,19
  s:drainNext(b,12)
  s:drainNext(b,3)
  s:drainNext(s.player)
  s:updateQueue()
  finish(s)
  T.eq(b.shownHP,12,'first multi-hit row stops at its queued floor')
  T.eq(s.player.shownHP,10,'enemy row cannot drain a later player row')
  s:updateQueue();finish(s)
  T.eq(b.shownHP,3,'next native row drains remaining multi-hit damage')
  s:updateQueue();finish(s)
  T.eq(s.player.shownHP,2,'player row owns its own drain')
end

-- A mod may choose a wider display step only during the real admitted HP
-- callback. Its write changes the display, never the saved Pokemon.
do
  local s=fixture()
  local b=start(s,'enemy',383,0,383)
  local calls=0
  s.stepHpAnim=function(self)
    calls=calls+1
    local anim=self.hpAnim
    T.eq(anim.side,'enemy','decorator sees the real queued side')
    T.eq(anim.to,0,'decorator sees authoritative target')
    T.raises(function() self.shownHp.player=0 end,'owned','cannot write another side')
    T.raises(function() self.shownHp.enemy=0/0 end,'invalid','cannot write NaN')
    T.raises(function() self.shownHp.enemy=384 end,'invalid','cannot exceed actual maximum')
    self.shownHp.enemy=math.max(anim.to,self.shownHp.enemy-383/72)
    if self.shownHp.enemy==anim.to then self.hpAnim=nil end
    return true
  end
  finish(s)
  T.check(calls>=72 and calls<=73,'wide display uses one native callback per frame')
  T.eq(b.shownHP,0,'fractional wide display ends exactly')
  T.eq(b.mon.hp,0,'wide display cannot undo resolved damage')
  T.raises(function() s.shownHp.enemy=1 end,'owned','no write admission after row')
end
do
  local s=fixture()
  local b=start(s,'enemy',19,3,19)
  local native=s.stepHpAnim
  s.stepHpAnim=function(self) self.hpAnim=nil;return false end
  T.eq(s:updateQueuePresentation(),true,'early decorator return cannot release damage row')
  T.eq(b.shownHP,19,'early return did not fabricate display progress')
  s.stepHpAnim=function() error('decorator fault') end
  T.raises(function() s:updateQueuePresentation() end,'decorator fault','callback error remains visible')
  T.raises(function() s.shownHp.enemy=3 end,'owned','error always releases write admission')
  s.stepHpAnim=native
  b.shownHP=18.5
  finish(s)
  T.eq(b.shownHP,3,'returning from fractional display to cartridge stepping terminates')
end
do
  local s=fixture()
  local outgoing=start(s,'player',19,3,19)
  s:updateQueuePresentation()
  s:switchPlayerInto(Battle.POS.PLAYER_LEFT,s.game.save.party[2])
  local incoming=s.player.shownHP
  finish(s)
  T.neq(s.player,outgoing,'native switch replaces the actual battler')
  T.eq(s.player.shownHP,incoming,'stale HP row cannot drain the incoming Pokemon')
end
for _,version in ipairs({'red','firered','emerald'}) do
  local s=fixture(version)
  local called=false
  s.stepHpAnim=function() called=true;error('Gen2 callback used by another generation') end
  s.enemy.shownHP=s.enemy.mon.hp
  s.enemy.mon.hp=s.enemy.mon.hp-3
  local frames=0
  while s:stepHPDrain() and frames<2000 do frames=frames+1 end
  T.check(frames>0 and frames<2000,version..' existing native drain completes')
  T.eq(called,false,version..' retains its native presentation owner')
  T.eq(s.shownHp,nil,version..' gets no Gen2 HP view')
end
Version.set(previous)
T.finish('native Gen2 admitted HP presentation and queue ownership')
