-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get();V.set('crystal')
require('src.core.ModCompat').install()
local Radio=require('src.world.Gen2Radio')
local Wall=require('src.ui.gen2.MapRadio')
local Gear=require('src.ui.PokegearMenu')
local VM=require('src.script.Gen2ScriptVM')
local Runner=require('src.script.ScriptRunner')
local Runtime=require('src.mods.Runtime')
local oldEvents=Runtime.events;local events=require('src.mods.Events').new();Runtime.events=events
local emitted={};events:on("radio.channel",function(e)emitted[#emitted+1]=e end)
local data=T.fixtures.fresh();require('src.render.Font').load(data)
data.maps.PALLET_TOWN={landmark=47}
data.gen2RadioChannels=Radio.defaults();data.gen2RadioChannels.TEST_RADIO={channel=9,name='TEST RADIO'}
local game={data=data,save={},stack=setmetatable({},{__index=require('src.core.StateStack')}),overworld={map={def={landmark=1}}}}
game.stack:init()
function game.overworld:timeOfDay()return 'MORNING'end
local function press(screen,key)
  game.input={wasPressed=function(_,k)return k==key end,isDown=function()return false end}
  screen:update(1/60)
end
local parent={name='test parent'};game.stack:push(parent)
for _,channel in ipairs({0,1,9})do
  local completed=0
  local ir={map_scripts={scripts={probe={{'setval',channel},{'special',0,'MapRadio'},{'setval',77},{'end'}}}}}
  local rows=assert(VM.compile(ir,'probe'))
  local runner=Runner.new(game,game.overworld)
  local before=#emitted
  runner:run(rows,{lastCheck=false,onDone=function()completed=completed+1 end})
  local wall=game.stack:top()
  T.eq(getmetatable(wall),Wall,'actual special opens the native wall UI')
  T.check(runner:isRunning(),'native VM waits for wall radio input')
  T.eq(runner.ctx.g2Var,channel,'opening preserves the script dial byte')
  T.eq(runner.ctx.lastCheck,channel~=0,'opening retains the result of the preceding setval')
  T.eq(#emitted,before+1,'actual tune emits once')
  T.eq(emitted[#emitted].channel,channel,'event preserves actual script channel')
  T.eq(emitted[#emitted].source,'map_radio','event identifies native wall special')
  T.eq(wall.station,channel==0 and 'POKEDEX_SHOW' or channel==9 and 'TEST_RADIO' or 'OAKS_POKEMON_TALK','native imported-map/time resolution')
  T.eq(game.save.g2Roamers,nil,'opening wall radio does not initialize unrelated roaming state')
  wall:draw()
  for _=1,100 do press(wall,'b')end
  T.eq(game.stack:top(),wall,'hundred-frame station announcement ignores exit input')
  T.eq(completed,0,'announcement cannot resume script early')
  wall:draw()
  local cover={name='cover'};game.stack:push(cover)
  T.eq(wall:close(),false,'covered radio cannot pop another screen')
  T.eq(completed,0,'covered radio cannot resume its parent')
  T.eq(game.stack:top(),cover,'covered close preserves top owner')
  game.stack:pop();press(wall,channel==9 and 'a' or 'b')
  T.eq(game.stack:top(),parent,'closing returns to the existing parent')
  T.eq(completed,1,'native script resumes exactly once')
  T.eq(runner.ctx.g2Var,77,'real VM executes the instruction following the special')
  T.eq(runner:isRunning(),false,'real script terminates')
  wall:close();T.eq(completed,1,'repeated close cannot replay script continuation')
  T.eq(#emitted,before+1,'draw and close do not emit extra tuning events')
end
game.overworld.map.def.landmark=47
local wall=Wall.new(game,{channel=0})
T.eq(wall.station,'PLACES_AND_PEOPLE','real loaded map definition selects Kanto')
local alternate={flags={ENGINE_EXPN_CARD=true}}
wall=Wall.new(game,{channel=9,save=alternate})
T.eq(wall.game.save,alternate,'caller-owned save is retained')
T.eq(game.save==alternate,false,'alternate save does not replace player save')
data.gen2RadioChannels={}
local completed=0;local runner=Runner.new(game,game.overworld)
runner:run(assert(VM.compile({map_scripts={scripts={empty={{'setval',1},{'special',0,'MapRadio'},{'end'}}}}},'empty')),
  {lastCheck=false,onDone=function()completed=completed+1 end})
T.eq(game.stack:top(),parent,'empty station registry cannot strand an empty UI')
T.eq(completed,1,'unavailable station allows script to continue')
T.eq(runner.ctx.lastCheck,true,'unavailable station preserves preceding setval result')
data.gen2RadioChannels=Radio.defaults()
game.save.flags={ENGINE_RADIO_CARD=true}
local gear=Gear.new(game)
for i,card in ipairs(gear.cards)do if card.id=='RADIO' then gear.index=i end end
T.eq(gear:current().id,'RADIO','actual owned card selects native radio')
local before=#emitted
press(gear);press(gear)
T.eq(#emitted,before+1,'Pokegear emits initial tune once')
T.eq(emitted[#emitted].source,'pokegear','Pokegear identifies the other real producer')
press(gear,'up')
T.eq(#emitted,before+2,'changing native tuner emits once')
T.eq(emitted[#emitted].station,'POKEDEX_SHOW','tuner event carries station identity')
press(gear,'a');T.eq(#emitted,before+2,'advancing program text does not retune')
V.set('red');T.raises(function()Wall.new(game)end,'Gen2 host','wall radio rejects another host')
Runtime.events=oldEvents;V.set(original)
T.finish('native radio VM, station lifecycle, Pokegear input and events')
