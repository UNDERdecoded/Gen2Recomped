-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Items=require('src.inventory.ItemEffects')
local Registry=require('src.battle.StatusRegistry')
local old=V.get()
local function fixture(edition)
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=V.generation()
 require('src.render.Font').load(data)
 local save=require('src.core.SaveData').newGame()
 save.party={Pokemon.new(data,'FIXMON_A',30)}
 local s=Screen.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',30)
 s.queue={};s.rng=function()return 1 end
 return s
end
local function sleep(b)
 b.mon.status,b.mon.sleepTurns,b.sleepTurns='SLP',3,3
end
for _,edition in ipairs{'gold','silver','crystal'}do
 for _,side in ipairs{'player','enemy'}do
  for _,effect in ipairs{13,15}do
   local s=fixture(edition);local b=s[side]
   s.data.items.PROBE_SLEEP_BERRY={name='Probe berry',heldEffect=effect,heldParam=0}
   b.mon.item='PROBE_SLEEP_BERRY'
   local msgs=Registry.inflict(s,b,'SLP',{})
   T.eq(b.mon.status,nil,'native held effect immediately cures inflicted sleep')
   T.eq(b.mon.sleepTurns,nil,'held cure clears the party counter written by native infliction')
   T.eq(b.sleepTurns,nil);T.eq(b.mon.item,nil,'actual held owner consumes the berry once')
   T.eq(#msgs,2,'infliction and held cure preserve their native caption order')
  end
  for _,id in ipairs{'AWAKENING','FULL_HEAL','MINT_BERRY','FULL_RESTORE','REVIVE','MAX_REVIVE'}do
   local s=fixture(edition);local b=s[side];sleep(b)
   s.data.items[id]={name=id}
   if id=='REVIVE'or id=='MAX_REVIVE'then b.mon.hp=0 end
   local result=Items.use(s.data,s.game.save,id,b.mon,s)
   T.eq(result,'consumed','actual native medicine succeeds')
   T.eq(b.mon.status,nil);T.eq(b.mon.sleepTurns,nil,'medicine clears persistent sleep count')
   T.eq(b.sleepTurns,nil,'same active wrapper is cleared immediately')
  end
 end
 local s=fixture(edition);local mon=s.player.mon;sleep(s.player)
 s.data.items.AWAKENING={name='AWAKENING'}
 T.eq(Items.use(s.data,s.game.save,'AWAKENING',mon), 'consumed')
 T.eq(mon.status,nil);T.eq(mon.sleepTurns,nil,'field medicine clears the actual party counter without a battle')
end
-- Gen1's unrelated dormant fields retain their previous shared-item behavior.
local s=fixture('red');local b=s.player;sleep(b)
s.data.items.AWAKENING={name='AWAKENING'}
T.eq(Items.use(s.data,s.game.save,'AWAKENING',b.mon,s),'consumed')
T.eq(b.mon.sleepTurns,3);T.eq(b.sleepTurns,3,'GSC counter cleanup does not reach Gen1')
V.set(old)
T.finish('native GSC held and medicine cures retire party and active sleep counters')
