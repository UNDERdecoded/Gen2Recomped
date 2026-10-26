-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Owned data, real Loader/buses and production state transitions. IO only is
-- controlled; no callback producer is replaced with a test implementation.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local oldVersion=V.get();V.set('crystal')
local Json=require('src.link.Json');local Runtime=require('src.mods.Runtime')
local data=T.fixtures.fresh()
local source=[[
local mod=...
local state={events={},odds=nil,nickname=nil,claim=false,quit=false,enemy=nil}
mod.exports.state=state
for _,name in ipairs({"happiness.changed","pokerus.infected","roamer.encountered","roamer.moved",
 "breeding.egg_created","egg.hatched","unown.unlocked","bug_contest.scored",
 "intro.boot.copyright","intro.boot.gamefreak","intro.boot.movie","intro.boot.movie_ended","intro.boot.title"})do
 mod.events:on(name,function(value)
  state.events[name]=state.events[name]or{};table.insert(state.events[name],value)
 end)
end
mod.hooks:wrap("breeding.compatibility",function(next,c)
 state.compatibility=c
 if state.odds~=nil then return state.odds end
 return next(c)
end)
mod.hooks:wrap("catch.nickname",function(next,mon,c)
 state.catch={mon=mon,context=c}
 if state.nickname~=nil then return state.nickname end
 return next(mon,c)
end)
mod.hooks:wrap("catch.party_full",function(next,c)
 state.full=c;return state.claim or next(c)
end)
mod.hooks:wrap("battle.style",function(next,battle)state.styleBattle=battle;return state.style or next(battle)end)
mod.hooks:wrap("battle.enemy_switch_or_item",function(next,battle)
 state.battle=battle;if state.enemy~=nil then return state.enemy end;return next(battle)
end)
mod.hooks:wrap("core.quit_to_launcher",function(next)if state.quit then return false end;return next()end)
]]
local run=T.sdk.loadMods({'mods/lifecycle'},{data=data,fs=T.sdk.memfs({
 ['mods/lifecycle/manifest.json']=Json.encode({id='lifecycle',name='Lifecycle',version='1.0.0',api=2,entry='main.lua',games={'gen2'}}),
 ['mods/lifecycle/main.lua']=source,
})})
T.eq(#run.errors,0,'lifecycle observer loads through ordinary API-2 registration')
local state=assert(run.loader.exports.lifecycle.state)
local function events(name)return state.events[name]or{}end
local function last(name)local list=events(name);return list[#list]end
local Pokemon=require('src.pokemon.Pokemon')
local mon=Pokemon.new(data,'FIXMON_A',10,function(a)return a end);mon.happiness=254
local Friendship=require('src.pokemon.Gen2Friendship')
Friendship.change(mon,'VITAMIN')
local changed=last("happiness.changed")
T.eq(changed.mon,mon,'friendship observer receives the live mon')
T.eq(changed.from,254,'friendship records the prior byte')
T.eq(changed.to,255,'friendship records the clamped byte')
T.eq(changed.delta,1,'friendship reports the actual change')
T.eq(changed.event,2,'vitamin maps to the public native event index')
T.eq(changed.reason,'event','friendship identifies event changes')
Friendship.change(mon,'VITAMIN');T.eq(#events("happiness.changed"),1,'clamped no-op does not announce a change')
mon.happiness=80
local save={party={mon},flags={},player={name='TEST',id=1},pokedex={seen={},owned={}},options={}}
Friendship.stepCycle(save);T.eq(#events("happiness.changed"),1,'first 256-step cycle cannot announce a point')
Friendship.stepCycle(save);T.eq(last("happiness.changed").reason,'step','actual second cycle announces its point')
T.eq(last("happiness.changed").event,nil,'step changes carry no event index')

local Roam=require('src.world.RoamMons')
save.g2RoamReleased=true;save.g2Roam={RAIKOU={mapId='OWN_MAP',active=true,level=40}}
T.eq(Roam.check(save,'OTHER_MAP',false,function()return 1 end),nil,'wrong map cannot announce a beast')
T.eq(#events("roamer.encountered"),0,'failed encounter stays silent')
T.eq(Roam.check(save,'OWN_MAP',false,function()return 1 end),'RAIKOU','real slot selection encounters the beast')
T.eq(last("roamer.encountered").slot,save.g2Roam.RAIKOU,'roamer record remains live')
T.eq(last("roamer.encountered").index,1,'roamer retains cartridge slot order')

local Commands=require('src.script.Gen2Commands')
save.g2Roam.RAIKOU.mapId='ROUTE_29';save.g2RoamLastMap='ROUTE_40'
local oldWorldRandom=love.math.random
love.math.random=function(low,high)if low==0 and high==31 then return 1 end;return low end
Commands.g2_update_roam_positions({save=save,game={data=data,overworld={map={id='ROUTE_32'}}}})
love.math.random=oldWorldRandom
T.eq(last("roamer.moved").from,'ROUTE_29','native route movement records the previous map')
T.eq(last("roamer.moved").to,'ROUTE_30','native route movement records its selected neighbor')
T.eq(last("roamer.moved").slot,save.g2Roam.RAIKOU,'movement observer sees the live native beast')

local Contest=require('src.world.BugContest')
save.g2BugContest={caught=mon,scores={[2]={score=1,species='FIXMON_B'}}}
local game={data=data,save=save}
local place,board=Contest.judge(game)
T.eq(last("bug_contest.scored").place,place or 0,'contest announces the actual placing')
T.eq(last("bug_contest.scored").results,board,'contest announces the native sorted board')
T.eq(last("bug_contest.scored").score,Contest.score(mon),'contest announces the native computed score')

local Virus=require('src.pokemon.Gen2Pokerus')
local party={{pokerus=0x32},{},{pokerus=0x20}}
local rolls={0,255};local cursor=0
local function random()cursor=cursor+1;return assert(rolls[cursor],'unexpected infection RNG')end
T.eq(Virus.afterBattle({party=party},random),2,'actual active-byte spread writes the clean neighbor')
T.eq(party[2].pokerus,0x34,'spread derives days from its carrier strain')
T.eq(last("pokerus.infected").mon,party[2],'infection observer sees the written party record')
T.eq(last("pokerus.infected").party,party,'infection observer retains party identity')
T.eq(last("pokerus.infected").source,'spread','infection identifies its source')
Virus.advance(party,4)
T.eq(party[2].pokerus,0x30,'daily expiry keeps the immune strain')
T.eq(party[3].pokerus,0x20,'expiry preserves an already cured byte')
T.eq(#events("pokerus.infected"),1,'expiry cannot announce an infection')
local Flags=require('src.script.Gen2Flags')
local contracted={party={{}},flags={[Flags.engineFlag(21)]=true}}
rolls={0,2,0,19};cursor=0
T.eq(Virus.afterBattle(contracted,random),1,'native rare roll contracts after the Goldenrod gate')
T.eq(last("pokerus.infected").source,'contracted','de novo infection has its own source')
T.eq(last("pokerus.infected").strain,4,'de novo strain comes from the sampled byte')
T.eq(last("pokerus.infected").days,1,'de novo countdown is stored before observer dispatch')
local start=os.time({year=2026,month=10,day=20,hour=12})
Virus.poll(contracted,start);T.eq(contracted.party[1].pokerus,0x41,'first clock poll only seeds the clock')
Virus.poll(contracted,start+86400*2);T.eq(contracted.party[1].pokerus,0x40,'elapsed days cure the actual party byte')
local shifted={party={{pokerus=0x34}},rtc={anchorTime=start,anchorMinute=1439,
 anchorDay=2,anchorDate='2026-10-20'}}
Virus.poll(shifted,start);Virus.poll(shifted,start+120)
T.eq(shifted.party[1].pokerus,0x33,'infection countdown follows saved midnight while the host is still at noon')
local Caps=require('src.mods.Capabilities')
T.eq(Caps.supports('events','happiness.changed','prism'),false,'unimplemented hack friendship is not advertised')
T.eq(Caps.supports('events','pokerus.infected','polishedcrystal'),false,'unimplemented hack infection is not advertised')


local DayCare=require('src.pokemon.DayCare')
local a=Pokemon.new(data,'FIXMON_A',10,function(n)return n end)
local b=Pokemon.new(data,'FIXMON_A',10,function(n)return n end)
a.otId,b.otId=1,2;a.dvs.defense,b.dvs.defense=1,2
DayCare.deposit(save,1,a);DayCare.deposit(save,2,b)
T.eq(DayCare.compatibility(data,save),4,'native text tier remains unchanged by a forwarding hook')
T.eq(state.compatibility.mon1,a,'compatibility context names the first resident')
T.eq(state.compatibility.mon2,b,'compatibility context names the second resident')
T.eq(state.compatibility.dayCare,true,'compatibility identifies a native Day Care query')
state.odds=1;local pen=DayCare.store(save);pen.stepsToEgg=1
local oldRandom=math.random
math.random=function(low,high)if low==0 and high==255 then return 0 end;return low or 0 end
local made=DayCare.step(data,save)
math.random=oldRandom
T.eq(made,true,'an authored non-stock byte reaches the real egg-producing step')
T.eq(last("breeding.egg_created").egg,pen.egg,'egg event identifies the actual pending egg')
T.eq(last("breeding.egg_created").compatibility,1,'egg event retains the exact authored probability')
T.eq(last("breeding.egg_created").mother,b,'egg event identifies the real mother')
state.odds=nil

-- Actual queue construction at the native catch boundary, before any UI IO.
local Battle=require('src.battle.BattleState')
local function caught()
 local foe=Pokemon.new(data,'FIXMON_B',10,function(n)return n end)
 return setmetatable({game=game,data=data,enemy={mon=foe,name='OWN FOE'},queue={},kind='wild'},Battle),foe
end
state.nickname='OWNED NAME EXCEEDS LIMIT'
local battle,foe=caught();battle:storeCaughtMon()
T.eq(foe.nickname,'OWNED NAME','nickname contract applies the native ten-character limit')
T.eq(state.catch.mon,foe,'nickname hook receives the actual caught record')
T.eq(state.catch.context.battle,battle,'nickname context identifies the actual battle')
state.claim=true;save.party={mon,mon,mon,mon,mon,mon}
battle,foe=caught();battle:storeCaughtMon()
T.eq(state.full.mon,foe,'full-party hook receives the caught record')
T.eq(#save.party,6,'claimed catch cannot overfill the party')
T.eq(save.boxes,nil,'claimed catch does not also deposit to a native box')
state.claim=false;state.nickname=nil

local unownDef=require('src.mods.Merge').deepCopy(data.pokemon.FIXMON_A)
unownDef.id,unownDef.dex,unownDef.evolutions='SPECIES_201',201,{}
unownDef.translationSourceName='UNOWN'
unownDef.forms={};for n=1,26 do unownDef.forms[n]={}end
data.pokemon.SPECIES_201=unownDef;data.unown_dex={words={'OWN WORD'}}
local unown=Pokemon.new(data,'SPECIES_201',10,function(n)return n end)
unown.dvs={attack=0,defense=0,speed=0,special=0}
battle=caught();battle.enemy.mon=unown;state.claim=true;battle:storeCaughtMon()
T.eq(last("unown.unlocked").letter,1,'first native Unown capture unlocks its actual DV letter')
T.eq(last("unown.unlocked").word,'OWN WORD','Unown event reads the current imported word table')
T.eq(last("unown.unlocked").count,1,'Unown event reports the native ordered dex count')
battle=caught();battle.enemy.mon=unown;battle:storeCaughtMon()
T.eq(#events("unown.unlocked"),1,'catching a duplicate letter cannot unlock it again')
state.claim=false

-- Dispatch the trainer decision through the real native enemy-action path.
battle,foe=caught();battle.player={mon=mon};battle.enemyParty={foe,Pokemon.new(data,'FIXMON_A',10,function(n)return n end)}
battle.enemyIndex=1;battle.trainer={id='OWN_AI'};battle.kind='trainer'
data.ai_classes=data.ai_classes or{};data.ai_classes.OWN_AI={}
state.enemy={kind='switch',index=2}
local action=battle:vanillaEnemyAction()
T.eq(action.special,'aiSwitch','canonical switch decisions enter the native action queue')
T.eq(action.index,2,'native switch retains the requested party slot')
T.eq(state.battle,battle,'enemy decision receives the actual battle')
state.enemy=true;action=battle:vanillaEnemyAction()
T.eq(action.special,'modEnemyTurn','a claimed enemy turn has an explicit native no-op action')
battle:executeAction(battle.enemy,battle.player,action)
T.eq(#battle.queue,0,'claimed enemy turn cannot also select a move')
state.enemy=nil
state.style='set';battle.expPaidPerSlot=true;battle.enemy.mon.hp=0
battle:enemyMonFainted()
T.eq(state.styleBattle,battle,'native trainer replacement asks the style hook')

-- Native hatching mutates the party record, then its real TextBox completion
-- boundary emits both old and new events. No producer is invoked directly.
local W=require('src.world.OverworldController');local slot,previous
for n=1,100 do local key,value=debug.getupvalue(W.hatchEgg,n)
 if not key then break end;if key=='Game'then slot,previous=n,value;break end
end
assert(slot)
game.stack={states={}};function game.stack:push(screen)table.insert(self.states,screen)end
local egg=Pokemon.new(data,'FIXMON_A',5,function(n)return n end)
egg.isEgg=true;egg.eggSteps=1;save.party={egg}
debug.setupvalue(W.hatchEgg,slot,game)
T.eq(W.hatchEgg({},egg),true,'native hatching admits the actual party egg')
T.eq(#events("egg.hatched"),0,'egg event waits for the actual completion boundary')
game.stack.states[1].onDone();game.stack.states[2].choice(false)
local hatched=last("egg.hatched")
T.eq(hatched.mon,egg,'hatch event identifies the live party mon')
T.check(hatched.egg~=egg and hatched.egg.isEgg,'hatch event retains the original egg state')
T.eq(hatched.slot,1,'hatch event retains its party slot')
debug.setupvalue(W.hatchEgg,slot,previous)

local Host=require('src.core.HostShell');local Music=require('src.core.Music')
local oldQuit,oldStop=Host.toLauncher,Music.stop;local quits=0
Host.toLauncher=function()quits=quits+1 end;Music.stop=function()end -- external process/audio IO
local NativeGame=require('src.core.Game')
state.quit=true;T.eq(NativeGame:returnToLauncher(),false,'quit hook may retain the current game')
T.eq(quits,0,'a swallowed quit never reaches the host')
state.quit=false;NativeGame:returnToLauncher();T.eq(quits,1,'a forwarded quit reaches the host exactly once')
Host.toLauncher,Music.stop=oldQuit,oldStop

local Intro=require('src.ui.Gen2Intro')
local stack={pop=function()end}
local introGame={data={field={intro={water='tests/fixture_data/assets/fixmon_a_front.png'}}},
 stack=stack,input={wasPressed=function()return false end}}
local intro=Intro.new(introGame,function()end);intro:enter()
T.eq(last("intro.boot.copyright").screen,intro,'first native branding stage announces copyright')
intro.scene=2;intro:enterScene()
T.eq(last("intro.boot.gamefreak").game,introGame,'second native branding stage identifies its game')
intro.scene=3;intro:enterScene()
T.eq(last("intro.boot.movie").screen,intro,'actual movie stage announces its screen')
intro._bootFrames=9;intro._bootSkipped=true;intro:finish();intro:finish()
T.eq(#events("intro.boot.movie_ended"),1,'movie completion cannot replay after a repeated finish')
T.eq(last("intro.boot.movie_ended").frames,9,'movie completion carries its frame count')
T.eq(last("intro.boot.movie_ended").skipped,true,'movie completion carries its skip decision')
local title=setmetatable({game=introGame,title={}},{__index=require('src.ui.TitleState')})
title:enter();T.eq(last("intro.boot.title").screen,title,'actual title enter announces its screen')


require('src.mods.Loader').teardown();run.release();V.set(oldVersion)
T.finish('native Gen2 lifecycle callbacks through public mod registrations')
