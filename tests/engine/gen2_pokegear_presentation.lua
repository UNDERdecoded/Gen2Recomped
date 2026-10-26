-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get();V.set('crystal')
local Gear=require('src.ui.PokegearMenu')
local Radio=require('src.world.Gen2Radio')
local data=T.fixtures.fresh();data.gen2RadioChannels=Radio.defaults()
data.gen2RadioChannels.OAKS_POKEMON_TALK.name='AUTHORED RADIO'
local stack=setmetatable({},{__index=require('src.core.StateStack')});stack:init()
local game={data=data,save={flags={ENGINE_RADIO_CARD=true}},stack=stack}
local function press(menu,key)
 game.input={wasPressed=function(_,k)return k==key end,isDown=function()return false end}
 menu:update(1/60)
end
-- A source renderer must observe the card reached through native input,
-- not an independent presentation cursor defaulting to CLOCK.
local menu=Gear.new(game);stack:push(menu)
T.eq(menu:card(),menu:current(),'source and native consumers share selected row')
T.eq(menu:cardLabel(),'CLOCK','source label resolves actual selected native card')
for _=1,#menu.cards do if menu:current().id~='RADIO' then press(menu,'right')end end
T.eq(menu:card().id,'RADIO','native card navigation reaches the source renderer')
local stations=menu:stations()
T.eq(stations[1].name,'AUTHORED RADIO','source tuner consumes mounted authored name')
T.eq(stations[1].station,'OAKS_POKEMON_TALK','source tuner receives stable station identity')
T.eq(stations[1].frequency,'04.5','frequency derives from existing native knob units')
T.eq(menu:currentStation().station,'OAKS_POKEMON_TALK','source selection reads native tuner cursor')
T.check(menu.radio and menu.radio.top=='PROF.OAK: Hello!','source panel sees the actual native program line')
local view=menu.radio;press(menu,'a')
T.eq(menu.radio,view,'advancing a program retains its live presentation object')
T.eq(menu.radio.top,'Wild #MON habits.','native line advancement reaches source panel')
press(menu,'up')
T.eq(menu:currentStation().station,'POKEDEX_SHOW','native retune changes source selection')
T.eq(menu.radio.station,'POKEDEX_SHOW','native retune changes the presented broadcast')
T.eq(menu.radio.top,'DJ MARY: Hi!','retune resets visible program text')
stations[1].name='LEAK';stations[1].lines[1]='LEAK'
T.eq(menu:stations()[1].name,'AUTHORED RADIO','source station rows are detached')
T.eq(menu:stations()[1].lines[1],'PROF.OAK: Hello!','source line snapshots cannot corrupt program text')
press(menu,'left');T.eq(menu.radio,nil,'leaving radio clears its active display')
press(menu,'right');T.check(menu.radio~=nil,'returning to radio restores a current program view')
press(menu,'b');T.eq(menu.radio,nil,'closing stops presenting a stale broadcast')
T.eq(stack:top(),nil,'native close retains its original stack ownership')
T.eq(menu:drawsWidescreen(),false,'unmodified native presentation stays on its original canvas')
local wide=menu.drawWidescreen
menu.drawWidescreen=function()end
T.eq(menu:drawsWidescreen(),true,'replacement window drawer opts into source presentation')
menu.drawWidescreen=wide
T.eq(menu:drawsWidescreen(),false,'removing replacement restores native composition')
data.gen2RadioChannels={};menu=Gear.new(game)
for _=1,#menu.cards do if menu:current().id~='RADIO' then press(menu,'right')end end
T.eq(#menu:stations(),0,'removed stations stay absent from source presentation')
T.eq(menu:currentStation(),nil,'empty tuner has no invented source selection')
T.eq(menu.radio,nil,'empty tuner has no fabricated broadcast')
V.set('red');menu=Gear.new(game)
T.eq(#menu:stations(),0,'other generation cannot expose native GSC stations')
V.set(original)
T.finish('native Pokegear input and source presentation agree')
