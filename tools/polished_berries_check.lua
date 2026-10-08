package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Polished berry use and held effects')
local V=require('src.core.GameVersion');V.set('polishedcrystal')
local D=require('src.core.Data')
D.items=dofile('G:/Gen2Recomped/polishedcrystal/data/generated/items.lua')
D.pokemon={TEST={name='TEST'}};D.moves={TACKLE={pp=35}};D.constants={}
package.loaded['src.core.Sound']={play=function()end}
local I=require('src.inventory.ItemEffects')
local H=require('src.battle.HoldItems')
local G=require('src.battle.HeldItems')
local byKey={};for id,d in pairs(D.items)do byKey[d.key]=id end
local function holder(key,hp,status)
  return {items=D.items,mon={species='TEST',hp=hp or 20,status=status,
    item=byKey[key],stats={hp=100},moves={{id='TACKLE',pp=0}}}}
end
for key,status in pairs({CHERI_BERRY='PAR',CHESTO_BERRY='SLP',PECHA_BERRY='PSN',RAWST_BERRY='BRN',ASPEAR_BERRY='FRZ'})do
  local b=holder(key,20,status)
  T.check(I.needsTarget(byKey[key],D.items[byKey[key]]),key..' opens party picker')
  T.eq(I.use(D,{player={name='TEST'}},byKey[key],b.mon),'consumed',key..' works from bag')
  T.eq(b.mon.status,nil,key..' cures its status')
  b.mon.status=status
  T.eq(H.trigger(b,'turn').kind,'cure',key..' held cure triggers')
  T.eq(G.effect(D,b),0,key..' does not collide with GSC enum')
end
for key,amount in pairs({ORAN_BERRY=10,SITRUS_BERRY=25,FIGY_BERRY=33})do
  local b=holder(key)
  T.eq(I.use(D,{player={name='TEST'}},byKey[key],b.mon),'consumed',key..' heals from bag')
  T.eq(b.mon.hp,20+amount,key..' correct bag amount')
  b.mon.hp=20
  T.eq(H.trigger(b,'hit').amount,amount,key..' correct held amount')
end
local b=holder('LEPPA_BERRY')
T.eq(I.use(D,{player={name='TEST'}},b.mon.item,b.mon,nil,1),'consumed','Leppa restores PP in bag')
T.eq(b.mon.moves[1].pp,10,'Leppa restores ten PP')
b.mon.moves[1].pp=0
T.eq(H.trigger(b,'turn').amount,10,'held Leppa restores ten PP')
for _,key in ipairs({'LIECHI_BERRY','GANLON_BERRY','SALAC_BERRY','PETAYA_BERRY','APICOT_BERRY','STARF_BERRY','LANSAT_BERRY'})do
  local b=holder(key,25)
  T.check(H.trigger(b,'turn')~=nil,key..' triggers at quarter HP')
  b.mon.hp=26;T.eq(H.trigger(b,'turn'),nil,key..' waits above threshold')
end
V.set('crystal')
T.eq(require('src.inventory.PolishedBerries').record({key='ORAN_BERRY'}),nil,'Polished field rules isolated')
T.eq(require('src.inventory.PolishedBerries').held({key='ORAN_BERRY'},b.mon),nil,'Polished held rules isolated')
T.finish()
