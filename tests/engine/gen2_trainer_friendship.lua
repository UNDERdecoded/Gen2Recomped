-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Real native constructors and an API2 consumer, without ROMs or mod edits.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Model=require('src.battle.gen2.Battle')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local old=V.get()
local originalGym,originalKanto=Model.isGymLeader,Model.isKantoGymLeader
-- Independent cartridge class order; display names deliberately all agree.
local classes={'FALKNER','WHITNEY','BUGSY','MORTY','PRYCE','JASMINE','CHUCK','CLAIR',
 'RIVAL1','POKEMON_PROF','WILL','CAL','BRUNO','KAREN','KOGA','CHAMPION',
 'BROCK','MISTY','LT_SURGE','SCIENTIST','ERIKA','YOUNGSTER','SCHOOLBOY',
 'BIRD_KEEPER','LASS','JANINE','COOLTRAINERM','COOLTRAINERF','BEAUTY','POKEMANIAC',
 'GRUNTM','GENTLEMAN','SKIER','TEACHER','SABRINA','BUG_CATCHER','FISHER','SWIMMERM',
 'SWIMMERF','SAILOR','SUPER_NERD','RIVAL2','GUITARIST','HIKER','BIKER','BLAINE',
 'BURGLAR','FIREBREATHER','JUGGLER','BLACKBELT_T','EXECUTIVEM','PSYCHIC_T',
 'PICNICKER','CAMPER','EXECUTIVEF','SAGE','MEDIUM','BOARDER','POKEFANM',
 'KIMONO_GIRL','TWINS','POKEFANF','RED','BLUE','OFFICER','GRUNTF','MYSTICALMAN'}
local leaders={FALKNER=true,WHITNEY=true,BUGSY=true,MORTY=true,PRYCE=true,
 JASMINE=true,CHUCK=true,CLAIR=true,WILL=true,BRUNO=true,KAREN=true,KOGA=true,
 CHAMPION=true,RED=true,BROCK=true,MISTY=true,LT_SURGE=true,ERIKA=true,JANINE=true,
 SABRINA=true,BLAINE=true,BLUE=true}
local kanto={BROCK=true,MISTY=true,LT_SURGE=true,ERIKA=true,JANINE=true,
 SABRINA=true,BLAINE=true,BLUE=true}
local function fixture(edition)
 V.set(edition)
 local data=T.fixtures.fresh();data.constants.gen=V.generation(edition)
 local run=T.sdk.loadMods({'mods/friendship_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/friendship_probe/manifest.json']='{"id":"friendship_probe","name":"Native friendship probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/friendship_probe/main.lua']=[[
   local mod=...
   local Battle=require('src.battle.gen2.Battle')
   mod.exports.events={}
   mod.events:on('happiness.changed',function(ev)
    mod.exports.events[#mod.exports.events+1]=ev
   end)
   mod.exports.query=function(class)
    if type(Battle.isGymLeader)~='function' or type(Battle.isKantoGymLeader)~='function' then return end
    return Battle.isGymLeader(class),Battle.isKantoGymLeader(class)
   end
   mod.exports.decorate=function()
    local native=Battle.isGymLeader
    if type(native)~='function' then return end
    Battle.isGymLeader=function(class)
     mod.exports.lastClass=class
     if mod.exports.override~=nil then return mod.exports.override end
     return native(class)
    end
   end
  ]],
 })})
 T.eq(#run.errors,0,'real API2 friendship consumer loads: '..edition)
 require('src.render.Font').load(data)
 local save=Save.newGame();save.party={}
 for i=1,5 do save.party[i]=Pokemon.new(data,'FIXMON_A',15)end
 local game={data=data,save=save,stack={top=function()end}}
 data.trainers.OWN_FRIENDSHIP={id='OWN_FRIENDSHIP',index=1,name='LEADER',
  baseMoney=10,parties={{{level=5,species='FIXMON_C'}}}}
 return game,run,run.loader.exports.friendship_probe
end
local function prepare(game,h)
 for _,mon in ipairs(game.save.party)do
  mon.hp,mon.happiness,mon.isEgg,mon.eggSteps=mon.stats.hp,h,nil,nil
 end
 game.save.party[3].hp=0
 game.save.party[4].isEgg=true
 game.save.party[5].eggSteps=256
end
for _,edition in ipairs{'gold','silver','crystal'}do
 local game,run,probe=fixture(edition)
 T.eq(type(Model.isGymLeader),'function','public source class predicate exists')
 T.eq(type(Model.isKantoGymLeader),'function','public Kanto predicate exists')
 for i,class in ipairs(classes)do
  local gym,kgym=probe.query(class)
  T.eq(gym,leaders[class]==true,'API2 source predicate '..class)
  T.eq(kgym,kanto[class]==true,'API2 Kanto predicate '..class)
  for _,h in ipairs{0,99,100,199,200,254,255}do
   prepare(game,h);probe.events={}
   game.data.trainers.OWN_FRIENDSHIP.index=i
   local party=game.save.party
   local b=Screen.newTrainer(game,'OWN_FRIENDSHIP',1)
   local delta=h<100 and 3 or h<200 and 2 or 1
   local expected=leaders[class] and math.min(255,h+delta)or h
   for n=1,5 do
    T.eq(party[n].happiness,n<=2 and expected or h,
     edition..' constructor award '..class..' '..h..' slot '..n)
    T.eq(party[n].hp,n==3 and 0 or party[n].stats.hp,'bonus does not heal')
   end
   T.eq(b:playerPartyView(),party,'constructor keeps actual native party')
   T.eq(#probe.events,leaders[class]and 2 or 0,'one event per standing non-egg, including byte saturation')
   for n,ev in ipairs(probe.events)do
    T.eq(ev.mon,party[n],'API2 event retains actual native mon')
    T.eq(ev.event,'GYMBATTLE','source constructor event name')
    T.eq(ev.eventId,4,'native cartridge event index remains available')
    T.eq(ev.reason,'event','source reason')
    T.eq(ev.from,h,'event before value')
    T.eq(ev.to,expected,'event after value')
    T.eq(ev.delta,expected-h,'event clamped delta')
   end
   if h==100 then
    local events=#probe.events
    b:enter()
    T.eq(party[1].happiness,expected,'real enter does not award a second bonus')
    T.eq(#probe.events,events,'real enter does not publish duplicate friendship events')
   end
  end
 end
 for _,class in ipairs{'UNKNOWN','falkner','LEADER','',false,1}do
  local gym,kgym=probe.query(class)
  T.eq(gym,false,'unknown source class does not become a leader')
  T.eq(kgym,false,'unknown source class does not become a Kanto leader')
 end
 local gym,kgym=probe.query(nil)
 T.eq(gym,false,'nil source class is not a leader');T.eq(kgym,false,'nil Kanto class is not a leader')
 -- The native constructor must call the public source seam with canonical
 -- identity, rather than a frozen private boolean or localized display name.
 probe.decorate();probe.override=false;prepare(game,100);probe.events={}
 game.data.trainers.OWN_FRIENDSHIP.index=63
 Screen.newTrainer(game,'OWN_FRIENDSHIP',1)
 T.eq(probe.lastClass,'RED','API2 decorator observes actual native Red class')
 T.eq(game.save.party[1].happiness,100,'decorated rejection reaches native constructor')
 probe.override=true;prepare(game,100);probe.events={}
 game.data.trainers.OWN_FRIENDSHIP.index='22'
 local b=Screen.newTrainer(game,'OWN_FRIENDSHIP',1,{playerPartyIndices={2,3,4,5}})
 T.eq(probe.lastClass,'YOUNGSTER','ordinary imported numeric-string class resolves canonically')
 T.eq(game.save.party[1].happiness,100,'out-of-scope save party member earns no bonus')
 T.eq(game.save.party[2].happiness,102,'selected native standing member earns bonus')
 T.eq(#probe.events,1,'selected fainted and both native egg representations stay excluded')
 T.eq(probe.events[1]and probe.events[1].mon,game.save.party[2],'scoped event uses original selected mon')
 T.eq(b:playerPartyView()[1],game.save.party[2],'ordered scope remains live')
 -- Source ChangeHappiness reports applied zero-delta events, while its step
 -- loop suppresses unchanged saturated values. Keep the two sites distinct.
 prepare(game,255);probe.events={}
 local friendship=require('src.pokemon.Gen2Friendship')
 friendship.change(game.save.party[1],'XITEM')
 T.eq(#probe.events,1,'zero-delta event remains observable by the actual API2 consumer')
 T.eq(probe.events[1]and probe.events[1].delta,0,'zero-delta event is explicit')
 probe.events={};game.save.g2HappinessStepCount=1
 friendship.stepCycle(game.save)
 T.eq(#probe.events,0,'unchanged saturated step does not publish a change')
 Model.isGymLeader,Model.isKantoGymLeader=originalGym,originalKanto
 run.release()
end
for _,edition in ipairs{'red','blue','yellow','ruby','sapphire','emerald','firered','leafgreen','prism','polishedcrystal'}do
 local game,run,probe=fixture(edition)
 prepare(game,100)
 for _,index in ipairs{1,11,16,63,64}do
  game.data.trainers.OWN_FRIENDSHIP.index=index
  Screen.newTrainer(game,'OWN_FRIENDSHIP',1)
 end
 T.eq(game.save.party[1].happiness,100,edition..' keeps its own constructor friendship rules')
 T.eq(#probe.events,0,edition..' does not receive vanilla GSC award events')
 run.release()
end
V.set(old)
T.finish('native GSC trainer class predicates, constructor friendship, live events and scoped party')
