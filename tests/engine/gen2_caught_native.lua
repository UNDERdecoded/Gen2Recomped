-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Actual source SDK plus native arrival/consumer owners. Audio and menu input
-- are replaced at their IO boundaries; no retail ROM or mod is modified.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Boxes=require('src.pokemon.Boxes')
local Screen=require('src.battle.BattleState')
local Commands=require('src.script.Commands')
require('src.script.Gen2Commands')
local Breeding=require('src.pokemon.Gen2Breeding')
local Friend=require('src.pokemon.Gen2Friendship')
local Trade=require('src.ui.Gen2TradeAnim')
local Screens=require('src.ui.Screens')
local Sound=require('src.core.Sound');local play=Sound.play;Sound.play=function()end
local Music=require('src.core.Music');local restore=Music.restoreMap;Music.restoreMap=function()end
local function fields(mon,expected,label)
 T.same({mon.caughtTime,mon.caughtLevel,mon.caughtLocation,mon.caughtByGender},expected,label)
end
for _,version in ipairs{'gold','silver','crystal','red','emerald','firered','prism','polishedcrystal'}do
 V.set(version)
 local data=T.fixtures.fresh();data.constants.gen=V.generation()
 data.maps.FIX_TOWN.landmark=47
 data.pokemon.FIXMON_A.index=1;data.pokemon.FIXMON_B.index=2
 local loaded=T.sdk.loadMods({'mods/caught_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/caught_probe/manifest.json']='{"id":"caught_probe","name":"Caught-data probe","version":"1.0.0","api":2,"entry":"main.lua"}',
  ['mods/caught_probe/main.lua']=[[
   local mod=...
   mod.exports.Mon=require('src.battle.gen2.Mon')
   mod.events:on('pokemon.caught',function(ev)mod.exports.caught=ev.mon end)
  ]],
 })})
 T.eq(#loaded.errors,0,'actual source SDK imports caught-data APIs '..version)
 local probe=loaded.loader.exports.caught_probe
 local Mon=probe.Mon
 local ready=type(Mon.setCaughtData)=='function'and type(Mon.setGiftCaughtData)=='function'
 T.check(ready,'actual SDK exports source caught setters '..version)
 if ready then
  require('src.render.Font').load(data);Boxes.load(nil)
  local function game(count)
   local s=Save.newGame();s.player.map='FIX_TOWN';s.player.gender='girl'
   s.player.name='QA';s.player.id=73;s.party={}
   for _=1,count or 1 do s.party[#s.party+1]=Pokemon.new(data,'FIXMON_A',12)end
   local ow={tod='DAY',calls=0}
   function ow:timeOfDay()self.calls=self.calls+1;return self.tod end
   return {data=data,save=s,overworld=ow,stack={top=function()end,push=function()end}}
  end
  for _,count in ipairs{1,6}do
   local g=game(count)
   local b=Screen.newWild(g,'FIXMON_B',25)
   local mon=b.enemy.mon
   b.queue={};b.nextInsert=0;b:storeCaughtMon()
   local stored=count==6 and g.save.boxes[1][1]or g.save.party[2]
   T.eq(stored,mon,'native catch stores the original Pokemon')
   T.eq(probe.caught,mon,'real SDK event observes same stored Pokemon')
   if version=='crystal'then
    fields(mon,{2,25,47,'girl'},'real Crystal catch stamps actual world context before event/storage')
    T.eq(g.overworld.calls,1,'arrival reads live world.tod owner once')
   else
    T.eq(mon.caughtTime,nil,'other generations/layouts receive no Crystal caught metadata')
    T.eq(g.overworld.calls,0,'other generations do not query GSC arrival clock')
   end
  end
  local g=game(1)
  Commands.give_pokemon({game=g,save=g.save,overworld=g.overworld},'FIXMON_B',15,true)
  local gift=g.save.party[2]
  if version=='crystal'then fields(gift,{2,15,47,'girl'},'ordinary native GivePoke records location/time')
  else T.eq(gift.caughtTime,nil,'other layouts keep native gift rules')end
  if version=='gold'or version=='silver'or version=='crystal'then
   -- The caught level remains one at hatch, even when the egg is level five.
   g=game(1);g.overworld.tod='NITE'
   local egg=Pokemon.new(data,'FIXMON_B',5)
   Breeding.hatch(g,egg)
   if version=='crystal'then fields(egg,{3,1,47,'girl'},'native hatch uses egg caught-level sentinel')
   else T.eq(egg.caughtTime,nil,'Gold/Silver hatch does not consume reserved bytes')end
   -- Contest metadata is earned at the catch, before a later gate/map/time.
   g=game(1);g.save.g2BugContest={active=true}
   local b=Screen.newWild(g,'FIXMON_B',18)
   b.queue={};b.nextInsert=0;b:storeContestMon()
   local caught=g.save.g2BugContest.caught
   T.eq(caught,b.enemy.mon,'native contest keeps same real enemy')
   if version=='crystal'then fields(caught,{2,18,19,'girl'},'contest uses National Park constant, not current map label')end
   g.overworld.tod='NITE';g.save.player.map='FIX_ROUTE'
   Commands.g2_contest_party_full({game=g,save=g.save})
   T.eq(g.save.party[2],caught,'contest results transfer same earned catch')
   if version=='crystal'then fields(caught,{2,18,19,'girl'},'gate does not restamp park catch at later time')end
   g=game(1)
   local mon=g.save.party[1];mon.happiness=70
   Mon.setCaughtData(mon,{landmark=47,playerGender='girl',level=12,timeOfDay='DAY'})
   Friend.levelUp(data,g.save,mon)
   T.eq(mon.happiness,version=='crystal'and 80 or 75,'actual friendship reads edited source landmark')
   mon.happiness=70;mon.caughtLocation=48;Friend.levelUp(data,g.save,mon)
   T.eq(mon.happiness,75,'source landmark edit immediately changes actual native friendship rule')
   local movie=setmetatable({variant={otGender=true},game=g},{__index=Trade})
   mon.caughtLocation=47;mon.caughtByGender='girl'
   T.eq(movie:playerGenderMark(mon),'♀','native trade display reads canonical caught-by bit')
   mon.caughtByGender='boy';T.eq(movie:playerGenderMark(mon),'♂','native trade display follows source gender edit')
   mon.caughtLocation=0;T.eq(movie:playerGenderMark(mon),' ','unknown source landmark suppresses OT mark')
   T.eq(movie:playerGenderMark({caughtData=147}),'♀','legacy trade record remains readable')
   if version=='crystal'then
    for _,clock in ipairs{{5,1},{11,2},{21,3}}do
     local timed=game(1);timed.overworld=nil
     require('src.core.Gen2Clock').setTime(timed.save,clock[1],0)
     local b=Screen.newWild(timed,'FIXMON_B',7)
     b.queue={};b.nextInsert=0;b:storeCaughtMon()
     fields(timed.save.party[2],{clock[2],7,47,'girl'},'arrival without world reads actual saved RTC')
    end
    -- Retire only real display/audio/input IO; execute the unchanged native
    -- trade constructor, roster/OT/held-item writes and party transfer.
    for _,dialog in ipairs{0,3}do
     g=game(1)
     data.field=data.field or{};data.field.gen2Trades={trades={{give='FIXMON_A',get='FIXMON_B',
      dialog=dialog,nickname='TRADE',ot='NPC',otId=123,dvs={0x12,0x34}}}}
     local push,ask,say=Screens.push,Commands.ask,Commands.show_text
     Commands.ask=function(ctx)ctx.lastCheck=true end
     Commands.show_text=function()end
     Screens.push=function(_,id,opts)
      if id=='PartyMenu'then opts.onSwitch(g.save.party[1])
      elseif id=='Gen2TradeAnim'then T.eq(opts.received,g.save.party[1],'movie receives actual traded native mon')
      else error('unexpected native trade menu '..tostring(id))end
     end
     Commands.g2_trade({game=g,save=g.save,runner={yield=function()end,resume=function()end}},0)
     Screens.push,Commands.ask,Commands.show_text=push,ask,say
     local traded=g.save.party[1]
     fields(traded,{0,0,126,dialog==3 and 'girl'or 'boy'},'actual NPC trade uses unknown/girl gift codes')
     T.eq(traded.ot,'NPC');T.eq(traded.otId,123);T.eq(traded.traded,true)
    end
    g=game(1)
    data.pokemon.SPECIES_213=require('src.mods.Merge').deepCopy(data.pokemon.FIXMON_B)
    Commands.g2_give_shuckle({game=g,save=g.save})
    fields(g.save.party[2],{0,0,126,'boy'},'actual fixed-OT Shuckie gift uses unknown code')
    -- Save encoding/validation, without any file IO, preserves source edits.
    local bytes=Save.encode(g.save);local decoded=assert(Save.decode(bytes))
    local owned=decoded.party[2]
    Save.validate(decoded,data)
    T.eq(decoded.party[2],owned,'real save validation retains original decoded mon')
    fields(owned,{0,0,126,'boy'},'real Lua save preserves canonical caught history')
   end
  end
 end
 loaded.release()
end
Sound.play=play;Music.restoreMap=restore;V.set(old)
T.finish('source SDK and native catch/box/contest/gift/trade/hatch, friendship, OT display and save consumers')
