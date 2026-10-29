-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source GSC volatile names must reach the actual native status/damage owner,
-- not a disconnected metadata table. All monsters below are ROM-free fixtures.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Model=require('src.battle.gen2.Battle')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Damage=require('src.battle.Damage')
local oldVersion=V.get()
local function fixture(version,chosen,effect)
 V.set(version)
 local data=T.fixtures.fresh();data.constants.gen=2;data.constants.generation=2
 for _,id in ipairs{'PROTECT','QA_GUARD'}do
  data.moves[id]={id=id,name=id,effect=effect or'PROTECT_EFFECT',power=0,type='NORMAL',accuracy=100,pp=10}
 end
 local run=T.sdk.loadMods({'mods/volatile_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/volatile_probe/manifest.json']='{"id":"volatile_probe","name":"Owned state probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/volatile_probe/main.lua']=[[
   local mod=...
   local Model=require('src.battle.gen2.Battle')
   mod.exports.write=function(model,mon,key,value)Model.volatile(model,mon)[key]=value end
   mod.exports.read=function(model,mon,key)return Model.volatile(model,mon)[key]end
  ]],
 })})
 T.eq(#run.errors,0,'actual API2 source consumer loads')
 require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',30)}
 if chosen then save.party[1].moves={{id=chosen,pp=10}}end
 local game={data=data,save=save,stack={top=function()end}}
 local b=Screen.newWild(game,'FIXMON_C',30)
 local rolls=0;b.rng=function(lo,hi)rolls=rolls+1;return hi or lo end
 return b,run,run.loader.exports.volatile_probe,function()return rolls end
end
local fields={
 {'flinched','flinched',true}, {'confuseCount','confusedTurns',3},
 {'endure','enduring',true}, {'recharge','mustRecharge',true},
 {'protectCount','protectRun',2}, {'focusEnergy','focusEnergy',true},
 {'xAccuracy','xAccuracy',true}, {'substitute','substituteHP',17},
 {'protect','protecting',true}, {'mist','mist',true},
}
for _,version in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 local b,run,probe,rolls=fixture(version)
 local model,mon=b.battle,b.player.mon
 local view=model:volatile(mon)
 T.eq(view,model:volatile(mon),'one stable source view for the same active battler')
 T.eq(view,model:volatile(b.player),'party and native-wrapper queries share the owner')
 for _,row in ipairs(fields)do
  probe.write(model,mon,row[1],row[3])
  T.eq(b.player[row[2]],row[3],version..' source write reaches native '..row[2])
  b.player[row[2]]=nil
  T.eq(probe.read(model,mon,row[1]),nil,'source read sees native clear: '..row[1])
  b.player[row[2]]=row[3]
  T.eq(probe.read(model,mon,row[1]),row[3],'native state reaches source read: '..row[1])
  probe.write(model,mon,row[1],nil)
  T.eq(b.player[row[2]],nil,'source clear retires native state: '..row[1])
  T.eq(mon[row[1]],nil,'transient source field is not written into party/save')
 end
 probe.write(model,mon,'flinched',true)
 local pp=mon.moves[1].pp
 T.eq(b:statusInterrupt(b.player,b.enemy,{id='FIX_TACKLE'}),true,'source flinch actually blocks native admission')
 T.eq(not not probe.read(model,mon,'flinched'),false,'native admission clears source flinch')
 T.eq(rolls(),0,'flinch does not consume battle RNG')
 T.eq(mon.moves[1].pp,pp,'blocked admission cannot spend PP')
 probe.write(model,mon,'confuseCount',2)
 T.eq(b:statusInterrupt(b.player,b.enemy,{id='FIX_TACKLE'}),false,'high native roll allows a confused attack')
 T.eq(b.player.confusedTurns,1,'actual native confusion decrements source counter')
 T.eq(probe.read(model,mon,'confuseCount'),1,'source sees the actual remaining counter')
 T.eq(rolls(),1,'confusion consumes exactly one actual byte roll')
 probe.write(model,mon,'confuseCount',nil)
 probe.write(model,mon,'recharge',true)
 local locked=b:lockedAction(b.player)
 T.eq(locked and locked.special,'recharge','source recharge reaches the real move lock')
 probe.write(model,mon,'recharge',nil)
 local hp=mon.hp
 probe.write(model,mon,'endure',true)
 b:applyDamage(b.player,100000,true)
 T.eq(mon.hp,1,'source Endure caps actual incoming damage at one HP')
 mon.hp=hp
 b:applyDamage(b.player,100000,false)
 T.eq(mon.hp,0,'Endure does not absorb native residual damage')
 probe.write(model,mon,'endure',nil);mon.hp=hp
 local low={id='QA_LOW_ACCURACY',accuracy=1,type='NORMAL'}
 local function accuracy()return Damage.accuracyRoll({oneIn256Miss=true},low,b.player,b.enemy,function()return 255 end,nil,b.data)end
 T.eq(accuracy(),false,'low accuracy misses before source override')
 probe.write(model,mon,'xAccuracy',true);T.eq(accuracy(),true,'source X Accuracy bypasses the real hit check')
 probe.write(model,mon,'xAccuracy',nil)
 local function critical()return Damage.critRoll({},b.player,'FIX_TACKLE',function()return 20 end,false,b.data,b)end
 T.eq(critical(),false,'fixed byte is outside the native base critical stage')
 probe.write(model,mon,'focusEnergy',true);T.eq(critical(),true,'source Focus Energy reaches native GSC critical stage')
 probe.write(model,mon,'focusEnergy',nil)
 local marker={owned=true};view._qaPresentation=marker
 collectgarbage('collect');T.eq(model:volatile(mon)._qaPresentation,marker,'consumer metadata persists while active')
 local old=b.player
 b:switchPlayerInto(Screen.POS.PLAYER_LEFT,b.game.save.party[2])
 local nextView=model:volatile(model.player)
 T.check(nextView~=view,'new native wrapper has a new volatile owner')
 T.eq(nextView._qaPresentation,nil,'source metadata does not leak to incoming actor')
 probe.write(model,model.player,'confuseCount',4)
 T.eq(b.player.confusedTurns,4,'incoming native battler owns the new source state')
 T.eq(old.confusedTurns,nil,'new state cannot change the withdrawn native wrapper')
 T.eq(mon.volatile,nil,'source view cannot create persistent party volatile data')
 run.release()
 for _,chosen in ipairs{'PROTECT','QA_GUARD'}do
  local battle,owner,source=fixture(version,chosen)
  source.write(battle.battle,battle.player.mon,'protectCount',2)
  battle:performMove(battle.player,battle.enemy,battle.player.curMoves[1],false,true)
  T.eq(battle.player.protecting,nil,'native repeated '..chosen..' fails its real odds roll')
  T.eq(source.read(battle.battle,battle.player.mon,'protectCount'),0,'native failed protection clears source counter')
  owner.release()
 end
 local battle,owner,source=fixture(version,'PROTECT','NO_ADDITIONAL_EFFECT')
 source.write(battle.battle,battle.player.mon,'protectCount',2)
 battle:performMove(battle.player,battle.enemy,battle.player.curMoves[1],false,true)
 T.eq(source.read(battle.battle,battle.player.mon,'protectCount'),nil,'non-protection effect resets run even with old PROTECT ID')
 owner.release()
end
-- A module-global weak-key map whose value closure retains its key is not
-- collectible on LuaJIT's Lua5.1 collector. No caller-held view remains here.
local weak=setmetatable({},{__mode='k'})
local function retired()
 local mon={};local b={mon=mon};local screen={player=b};local model={}
 Model.bind(model,screen);Model.volatile(model,mon)._owned=true
 T.eq(screen.player,b,'owner stays live during its actual view creation')
 weak[b]=true
end
for _=1,12 do retired()end
collectgarbage('collect');collectgarbage('collect')
T.eq(next(weak),nil,'module cache cannot retain retired battlers through view closures')
V.set(oldVersion)
T.finish('native source volatile state, real mechanics, switch and cache lifetime')
