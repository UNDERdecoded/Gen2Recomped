-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local old=Version.get()
local Pokemon=require('src.pokemon.Pokemon')
local Experience=require('src.battle.Experience')
local Native=require('src.battle.BattleState')
local Save=require('src.core.SaveData')
local Stats=require('src.pokemon.Stats')
local Battler=require('src.battle.Battler')
for _,edition in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 Version.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=2
 for _,def in pairs(data.pokemon)do def.baseStats.spatk,def.baseStats.spdef=31,199 end
 data.pokemon.growthRates={CUSTOM_SOURCE={numerator=1,denominator=1}}
 data.pokemon.FIXMON_A.growthRate='CUSTOM_SOURCE'
 data.pokemon.FIXMON_A.learnset={{level=1,move='FIX_TACKLE'},
  {level=6,move='FIX_SCRATCH'},{level=7,move='FIX_EMBERISH'},{level=8,move='FIX_CUT'}}
 data.items.QA_SHARE={id='QA_SHARE',name='EXP.SHARE',key='EXP_SHARE'}
 data.items.QA_LUCKY={id='QA_LUCKY',name='LUCKY EGG',key='LUCKY_EGG'}
 local loaded=T.sdk.loadMods({'mods/progression_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/progression_probe/manifest.json']='{"id":"progression_probe","name":"Progression probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/progression_probe/main.lua']=[[
   local mod=...
   local e=mod.exports
   e.Mon=require('src.battle.gen2.Mon');e.events={};e.awards={};e.mode='delegate';e.effortBefore={}
   mod.content.growth_rates:override('CUSTOM_SOURCE',{expForLevel=function(n)return 2*n*n*n+.9 end})
   mod.events:on('pokemon.level_up',function(ev)
    e.events[#e.events+1]={mon=ev.mon,level=ev.level,previous=ev.prevLevel,
      seen=ev.mon.level,experience=ev.mon.experience,hp=ev.mon.hp,learnable=ev.learnable}
   end)
   mod.hooks:wrap('exp.gain',function(next,ctx)
    e.awards[#e.awards+1]=ctx
    e.effortBefore[#e.effortBefore+1]=ctx.mon.statExp.special
    if e.mode=='infect'then ctx.mon.pokerus=32 end
    if e.mode=='override'then return 7 end
    if e.mode=='suppress_egg'then ctx.luckyEgg=false end
    return next(ctx)
   end)
  ]],
 })})
 T.eq(#loaded.errors,0,'native coefficient builtin and actual SDK override load '..edition)
 local probe=loaded.loader.exports.progression_probe
 T.check(probe~=nil,'actual consumer entry runs')
 if not probe then loaded.release();Version.set(old);T.finish('native coefficient registry integration failed')end
 local Mon=probe.Mon
 local ready=true
 for _,name in ipairs{'gainExperience','experienceForLevel','growthFor','writeStats','gainStatExp'}do
  T.eq(type(Mon[name]),'function','source progression function reaches actual SDK')
  ready=ready and type(Mon[name])=='function'
 end
 if not ready then loaded.release();Version.set(old);T.finish('missing actual source progression surface')end
 local mon=Pokemon.new(data,'FIXMON_A',5)
 T.eq(mon.exp,250,'actual native constructor evaluates merged custom coefficient-registry winner')
 T.eq(mon.experience,mon.exp,'source experience is actual native experience field')
 T.eq(rawget(mon,'experience'),nil,'source alias is not a duplicated persistent value')
 mon.experience=251;T.eq(mon.exp,251,'source experience write reaches native HUD/save input')
 mon.exp=250;T.eq(mon.experience,250,'native writes immediately reach source read')
 local regular=Battler.new(data,mon,false)
 local transformed=Battler.new(data,mon,false)
 local shadow={hp=90,attack=199,spatk=200,spdef=201};transformed.curStats=shadow
 mon.hp=0
 local previous=mon.stats.hp
 local result=Mon.gainExperience(mon,2*8^3-250,data)
 T.same(result,{levels=3,learned={'FIX_SCRATCH','FIX_EMBERISH','FIX_CUT'},from=5,to=8},'source award report and crossed move order')
 T.eq(mon.level,8);T.eq(mon.exp,1024);T.eq(mon.experience,1024)
 T.eq(mon.hp,mon.stats.hp-previous,'source HP delta semantics include a fainted zero')
 T.eq(regular.curStats,mon.stats,'real native wrapper follows source level recalculation')
 T.eq(transformed.curStats,shadow,'actual separate Transform statistics survive source progression')
 T.eq(#probe.events,3,'exactly one real SDK event per crossed level')
 for i,event in ipairs(probe.events)do
  T.eq(event.mon,mon,'actual SDK retains same native mon')
  T.eq(event.level,5+i);T.eq(event.previous,4+i)
  T.eq(event.seen,8,'source events observe final level and stats, not an intermediate snapshot')
  T.eq(event.experience,1024);T.eq(event.hp,mon.hp)
 end
 local beforeStats=mon.stats;probe.events={}
 T.same(Mon.gainExperience(mon,-20,data),{levels=0,learned={}},'negative source award adds zero')
 T.eq(mon.stats,beforeStats,'no level change does not refresh native stats');T.eq(#probe.events,0)
 local native=Pokemon.new(data,'FIXMON_A',5)
 local active=Battler.new(data,native,false)
 probe.events={}
 local levels,amount=Experience.add(data,native,774)
 T.same(levels,{6,7,8});T.eq(amount,774);T.eq(native.exp,1024)
 T.eq(active.curStats,native.stats,'actual ordinary native level-up also updates tracked combat stats')
 T.eq(#probe.events,3)
 for _,event in ipairs(probe.events)do T.eq(event.seen,8,'native owner shares source final-state publication order')end
 data.constants.levelCap=6
 native=Pokemon.new(data,'FIXMON_A',5)
 levels=Experience.add(data,native,999999)
 T.same(levels,{6});T.eq(native.level,6);T.eq(native.exp,432,'native configurable cap uses same curve')
 local source=Pokemon.new(data,'FIXMON_A',5)
 Mon.gainExperience(source,99999999,data)
 T.eq(source.level,100);T.eq(source.exp,2000000,'public source fixed cap remains 100')
 data.constants.levelCap=100
 local foe={baseExp=101,baseStats={hp=19,attack=21,defense=23,speed=25,spatk=31,spdef=199}}
 for _,pokerus in ipairs{0,0x21,0x20}do
  native=Pokemon.new(data,'FIXMON_A',40);native.pokerus=pokerus;native.item='QA_LUCKY'
  local exp=native.exp;probe.awards={};probe.effortBefore={};probe.mode='delegate'
  levels,amount=Experience.apply(data,native,foe,15,true,2,true,{halved=true})
  -- floor(101/2)*15/7 ->107; /2->53; trade79; trainer118; egg177.
  T.eq(amount,177,'actual native pool halves before level/participant/trade/trainer/egg rounding')
  T.eq(native.exp-exp,177)
  T.eq(native.statExp.special,7*(pokerus~=0 and 2 or 1),'actual active/cured Pokerus doubles shared Special Attack yield')
  T.eq(native.statExp.hp,4*(pokerus~=0 and 2 or 1))
  T.eq(#probe.awards,1,'one native exp.gain dispatch per award')
  T.eq(probe.effortBefore[1],0,'actual source hook observes effort before this award')
  T.eq(probe.awards[1].mon,native);T.eq(probe.awards[1].participants,2)
  T.eq(probe.awards[1].halved,true);T.eq(probe.awards[1].luckyEgg,true)
  probe.mode='suppress_egg'
  _,amount=Experience.apply(data,native,foe,15,true,2,true,{halved=true})
  T.eq(amount,118,'actual hook can suppress Lucky Egg inside shared award owner')
  probe.mode='override'
  _,amount=Experience.apply(data,native,foe,15,true,2,true,{halved=true})
  T.eq(amount,7,'explicit final hook return is not boosted again outside the owner')
 end
 local infected=Pokemon.new(data,'FIXMON_A',40)
 probe.mode='infect';Experience.apply(data,infected,foe,15,false,2,false,{halved=true})
 T.eq(infected.statExp.special,14,'real exp.gain Pokerus edit precedes native effort award')
 -- Execute the real battle EXP.SHARE distribution, retaining actual party,
 -- source model, loser and per-recipient callback identities.
 require('src.render.Font').load(data)
 local save=Save.newGame();save.party={}
 for i=1,3 do save.party[i]=Pokemon.new(data,'FIXMON_A',40)end
 save.party[2].item='QA_SHARE'
 local game={data=data,save=save,stack={top=function()end}}
 local battle=Native.newWild(game,'FIXMON_B',15)
 battle.enemy.def.baseExp=101
 battle.enemy.def.baseStats={hp=19,attack=21,defense=23,speed=25,spatk=31,spdef=199}
 battle.participants={[save.party[1]]=true,[save.party[2]]=true}
 battle.queue={};battle.nextInsert=0;probe.awards={};probe.mode='delegate'
 local before={};for i,m in ipairs(save.party)do before[i]=m.exp end
 battle:awardExp()
 T.eq(save.party[1].exp-before[1],53,'real participant receives correctly rounded half pool')
 T.eq(save.party[2].exp-before[2],160,'real participating holder receives both correctly rounded pools')
 T.eq(save.party[3].exp-before[3],0,'unexposed bench without holder receives no award')
 T.eq(#probe.awards,3,'actual battle pays two participants and one holder')
 for i,ctx in ipairs(probe.awards)do
  T.eq(ctx.halved,true);T.eq(ctx.participants,i==3 and 1 or 2,'hook receives recipient count, not a fake doubled count')
  T.eq(ctx.luckyEgg,false);T.eq(ctx.battle,battle.battle);T.eq(ctx.loser,battle.enemy.mon)
 end
 local encoded=Save.encode(save);local decoded=assert(Save.decode(encoded));Save.validate(decoded,data)
 for i,m in ipairs(decoded.party)do
  T.eq(m.exp,save.party[i].exp);T.eq(m.experience,m.exp,'normal Lua decode/validation restores source experience view')
  T.eq(rawget(m,'experience'),nil,'persistent format still has one canonical experience member')
 end
 loaded.release()
end
Version.set(old)
T.finish('actual source SDK and native GSC growth overrides, shared level/stat ownership, EXP.SHARE, Pokerus, Lucky Egg and persistence')
