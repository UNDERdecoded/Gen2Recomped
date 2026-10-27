-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Pokemon=require('src.pokemon.Pokemon')
local Effects=require('src.inventory.ItemEffects')
local Screens=require('src.ui.Screens')
local Chrome=require('src.ui.Gen2Chrome')
local Sound=require('src.core.Sound')
local Protocol=require('src.link.Protocol')
local oldVersion=V.get()
for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 V.set(version);Screens.invalidate()
 local data=T.fixtures.fresh();data.constants.gen=2;require('src.render.Font').load(data)
 local mon=Pokemon.new(data,'FIXMON_A',30)
 local game={data=data,save={party={mon}},input={pressed={}},stack={states={}}}
 function game.input:wasPressed(key)return self.pressed[key]==true end
 function game.stack:top()return self.states[#self.states]end
 function game.stack:push(state)self.states[#self.states+1]=state end
 function game.stack:pop()return table.remove(self.states)end
 mon.moves={{id='FIX_TACKLE',pp=9,ppUps=2},{id='FIX_SCRATCH',pp=3,ppUps=1}}
 local picked,cancelled=0,0
 local menu=Screens.build(game,'Gen2MoveDeleter',{mon=mon,moves=data.moves,
  onChoose=function(slot)picked=slot end,onCancel=function()cancelled=cancelled+1 end})
 T.eq(menu.mon,mon,version..' screen registry resolves the actual native move controller')
 T.eq(menu.list,mon.moves,'native selector reads the actual party move list')
 if menu.mon==mon and menu.list==mon.moves then
  local function press(key)game.input.pressed={[key]=true};menu:update(1/60);game.input.pressed={}end
  local hp,pp=mon.hp,mon.moves[1].pp
  press('up');T.eq(menu.row,1,'native PP selector stops at the first row')
  press('down');T.eq(menu.row,2,'ordinary native input selects the second actual move')
  press('down');T.eq(menu.row,2,'native PP selector stops at the last row')
  local trace={};local print,box,cursor=Chrome.print,Chrome.textbox,Chrome.cursor
  Chrome.print=function(text,x,y)trace[#trace+1]={text,x,y}end
  Chrome.textbox=function(...)trace.box={...}end
  Chrome.cursor=function(...)trace.cursor={...}end
  menu:draw()
  T.same(trace.box,{0,1,18,9},'native move list uses cartridge SetUpMoveList geometry')
  T.same(trace.cursor,{1,5},'native cursor tracks the actual selected second row')
  T.same(trace[1],{data.moves.FIX_TACKLE.name,2,3},'first move uses native name placement')
  T.same(trace[6],{data.moves.FIX_SCRATCH.name,2,5},'second move uses native name placement')
  Chrome.print,Chrome.textbox,Chrome.cursor=print,box,cursor
  T.eq(mon.hp,hp,'drawing a PP choice cannot heal')
  T.eq(mon.moves[1].pp,pp,'browsing a PP choice cannot spend or restore PP')
  data.audio=data.audio or{};data.audio.sfx=data.audio.sfx or{};data.audio.sfx.Sfx_ReadText2='fixture-native-select.wav'
  local cue=0;local play=Sound.play
  Sound.play=function(actual,name)T.eq(actual,data,'native selection uses actual imported audio');T.eq(name,'Sfx_ReadText2','native selection uses the real cue');cue=cue+1 end
  press('a');press('a');T.eq(picked,2,'selection returns actual move slot once');T.eq(cue,1,'completed selection cannot replay its cue')
  Sound.play=play
  menu=Screens.build(game,'Gen2MoveDeleter',{mon=mon,onCancel=function()cancelled=cancelled+1 end})
  game.input.pressed={b=true};menu:update(1/60);menu:update(1/60);game.input.pressed={}
  T.eq(cancelled,1,'native cancel continuation fires exactly once')
  menu=Screens.build(game,'Gen2MoveDeleter',{mon=mon,layout='forget'})
  game.input.pressed={up=true};menu:update(1/60);game.input.pressed={}
  T.eq(menu.row,2,'native forget layout alone wraps upward')
  game.input.pressed={down=true};menu:update(1/60);game.input.pressed={}
  T.eq(menu.row,1,'native forget layout alone wraps downward')
  T.check(pcall(function()menu:draw()end),'native forget layout draws its actual four-slot window')
 end
 for _,base in ipairs({5,10,15,20,25,30,35,40})do
  local def={pp=base};local bonus=math.min(math.floor(base/5),7)
  for ups=0,3 do
   local slot={pp=0,ppUps=ups};local expected=base+ups*bonus
   T.eq(Pokemon.maxPP(def,slot),expected,'native maximum follows ComputeMaxPP, including capped high-base bonus')
   T.eq(Pokemon.ppUps and Pokemon.ppUps(def,slot),ups,'native PP-Up reader uses the real counter')
   local stored={pp=0,maxPp=expected}
   T.eq(Pokemon.maxPP(def,stored),expected,'legacy stored maximum infers the existing native bonus')
   T.eq(stored.ppUps,nil,'maximum read never migrates or mutates the saved counter')
  end
 end
 data.moves.FIX_TACKLE.pp=40
 mon.moves={{id='FIX_TACKLE',pp=59,ppUps=3},{id='FIX_SCRATCH',pp=0}}
 local result=Effects.use(data,game.save,'ETHER',mon,nil,1)
 T.eq(result,'consumed','actual ETHER restores a partially depleted native move')
 T.eq(mon.moves[1].pp,61,'actual ETHER caps restoration at61 instead of64')
 T.eq(Effects.use(data,game.save,'ETHER',mon,nil,1),'failed','full native61PP refuses another ETHER')
 mon.moves[1].pp=58
 T.eq(Effects.use(data,game.save,'MYSTERYBERRY',mon,nil,1),'consumed','actual MysteryBerry restores the chosen native move')
 T.eq(mon.moves[1].pp,61,'MysteryBerry also clamps at the native61PP maximum')
 T.eq(mon.moves[2].pp,0,'single-move PP item cannot restore another slot')
 mon.moves[1].pp=0
 T.eq(Effects.use(data,game.save,'MAX_ETHER',mon,nil,1),'consumed','actual MAX ETHER restores the selected move')
 T.eq(mon.moves[1].pp,61,'actual MAX ETHER uses the same native maximum')
 mon.moves[1].pp=0
 Pokemon.restorePP(mon,data.moves)
 T.eq(mon.moves[1].pp,61,'actual party healing uses the same capped maximum')
 mon.moves[1]={id='FIX_TACKLE',pp=52,maxPp=54}
 T.eq(Effects.use(data,game.save,'PP_UP',mon,nil,1),'consumed','actual PP UP accepts a valid legacy two-bonus slot')
 T.eq(mon.moves[1].ppUps,3,'PP UP increments the real inferred native counter')
 T.eq(mon.moves[1].maxPp,61,'PP UP writes the actual native maximum')
 T.eq(mon.moves[1].pp,59,'PP UP adds seven to the actual remaining PP')
 T.eq(Effects.use(data,game.save,'PP_UP',mon,nil,1),'failed','native three-bonus slot refuses a fourth PP UP')
 data.moves.SKETCH={id='SKETCH',name='SKETCH',pp=1};mon.moves[1]={id='SKETCH',pp=1}
 T.eq(Effects.use(data,game.save,'PP_UP',mon,nil,1),'failed','native SKETCH refuses PP UP without consuming it')
 T.eq(mon.moves[1].ppUps,nil,'SKETCH refusal leaves its counter unchanged')
 mon.moves[1]={id='FIX_TACKLE',pp=61,maxPp=61}
 local packet=Protocol.packMon(mon);packet.moves[1].pp=64;packet.moves[1].ppUps=3
 local unpacked=Protocol.unpackMon(data,packet)
 T.check(unpacked~=nil,'actual native link reconstruction returns a valid Pokemon')
 T.eq(unpacked and unpacked.moves[1].pp,61,'actual link reconstruction clamps to native Gen2 maximum')
 T.eq(mon.moves[1].pp,61,'detached link reconstruction cannot rewrite the original party')
end
for _,version in ipairs({'red','firered','emerald','platinum','heartgold','black'})do
 V.set(version)
 T.eq(Pokemon.maxPP({pp=40},{ppUps=3}),64,'other editions retain their existing PP rule')
 T.eq(Pokemon.maxPP({pp=40},{ppUps=3},2),61,'explicit Gen2 target is independent of the current launcher game')
end
V.set(oldVersion);Screens.invalidate()
T.finish('native Gen2 PP selection, arithmetic, actual item effects, healing and link boundary')
