-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native registered protection effects, RNG boundaries and real queued order.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local P=require('src.battle.Gen3MoveEffects').primary
local before=V.get()
local function fixture(edition)
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=V.generation()
 data.moves.QA_PROTECT={id='QA_PROTECT',name='QA PROTECT',power=0,type='NORMAL',accuracy=100,pp=20,effect='PROTECT_EFFECT'}
 data.moves.QA_ENDURE={id='QA_ENDURE',name='QA ENDURE',power=0,type='NORMAL',accuracy=100,pp=20,effect='ENDURE_EFFECT'}
 local run=T.sdk.loadNone({data=data});require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',30)}
 save.party[1].moves={{id='QA_PROTECT',pp=20}}
 local b=Screen.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',30)
 return b,run
end
for _,edition in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 local b,run=fixture(edition)
 for _,effect in ipairs{{'PROTECT_EFFECT','protecting'},{'ENDURE_EFFECT','enduring'}}do
  for count=0,9 do
   local threshold=math.floor(255/2^count)
   for _,byte in ipairs{0,1,62,63,126,127,253,254}do
    local draws,loSeen,hiSeen=0
    b.rng=function(lo,hi)draws=draws+1;loSeen,hiSeen=lo,hi;return lo+byte%(hi-lo+1)end
    b.player.protectRun=count;b.player[effect[2]]=nil
    P[effect[1]](b,b.player)
    local succeeds=threshold>0 and byte<threshold
    T.eq(not not b.player[effect[2]],succeeds,edition..' '..effect[1]..' count '..count..' byte '..byte)
    T.eq(b.player.protectRun,succeeds and count+1 or 0,'actual native consecutive count')
    T.eq(draws,threshold>0 and 1 or 0,'one nonzero-byte draw until threshold reaches zero')
    if threshold>0 then
     T.eq(loSeen,1,'native draw starts at one')
     T.eq(hiSeen,255,'native draw spans all nonzero bytes')
    end
   end
  end
  for _,reason in ipairs{'substitute','opponent-first'}do
   b.player.protectRun=3;b.player[effect[2]]=nil
   b.player.substituteHP=reason=='substitute'and 10 or nil
   b.turnCount=10;b._gen2ProtectionTurn=10
   b._gen2ProtectionFirst=reason=='opponent-first'and'enemy'or'player'
   local draws=0;b.rng=function(lo)draws=draws+1;return lo end
   P[effect[1]](b,b.player)
   T.eq(b.player[effect[2]],nil,reason..' prevents '..effect[1])
   T.eq(b.player.protectRun,0,reason..' resets actual counter')
   T.eq(draws,0,reason..' fails before the random draw')
  end
  b.player.substituteHP=nil;b._gen2ProtectionTurn=nil;b._gen2ProtectionFirst=nil
 end
 -- Both sides choose the same priority. The slower user's actual queued
 -- action must fail after the faster opponent has acted, without a draw.
 b.player.curStats.speed=1;b.enemy.curStats.speed=999
 local selected=b.player.curMoves[1]
 b.enemy.curMoves[1]={id='QA_ENDURE',pp=20}
 b.enemyAction=function()return b.enemy.curMoves[1]end
 b.queue={};local draws=0;b.rng=function(lo)draws=draws+1;return lo end
 b:resolveTurn(selected)
 local first,second=b.queue[1],b.queue[2]
 T.check(first and second and first.fn and second.fn,'real native actions are queued')
 b.nextInsert=0;first.fn()
 T.eq(b.enemy.enduring,true,'the faster opponent executes actual Endure first')
 local afterFirst=draws
 b.nextInsert=0;second.fn()
 T.eq(b.player.protecting,nil,'second actor cannot Protect after opponent')
 T.eq(b.player.protectRun,0,'second actor resets source-readable counter')
 T.eq(draws,afterFirst,'opponent-first failure consumes no protection RNG')
 T.eq(selected.pp,19,'failed protection still spends the actual move PP')
 -- A new round retires the previous first actor. Called effects remain in
 -- the same round and cannot change its first side.
 b.queue={};b:resolveTurn(b.player.curMoves[1]);b:executeAction(b.player,b.enemy,{special='recharge'})
 T.eq(b._gen2ProtectionFirst,'player','next round records its actual first side')
 -- First-side identity must survive replacement of that side's wrapper.
 b.queue={};b:resolveTurn(b.player.curMoves[1])
 local withdrawn=b.player
 b:executeAction(withdrawn,b.enemy,{special='playerSwitch',mon=b.game.save.party[2]})
 T.check(b.player~=withdrawn,'real native switch replaces the first wrapper')
 b.enemy.protectRun=2
 b:executeAction(b.enemy,b.player,{id='QA_ENDURE',pp=20})
 T.eq(b.enemy.enduring,nil,'second actor cannot Endure after opponent switches')
 T.eq(b.enemy.protectRun,0,'switch-first failure resets actual counter')
 run.release()
end
-- Existing Gen1/GBA behavior is deliberately untouched by the GSC owner.
for _,edition in ipairs{'red','firered','emerald'}do
 local b,run=fixture(edition);local draws=0
 b.rng=function(lo)draws=draws+1;return lo end
 b.player.substituteHP=10;b._gen2ProtectionTurn=b.turnCount;b._gen2ProtectionFirst='enemy'
 P.PROTECT_EFFECT(b,b.player)
 T.eq(b.player.protecting,true,edition..' retains its previous protection behavior')
 T.eq(draws,0,edition..' first use retains its old random protocol')
 run.release()
end
V.set(before)
T.finish('native GSC protection thresholds, restrictions, order, PP and RNG')
