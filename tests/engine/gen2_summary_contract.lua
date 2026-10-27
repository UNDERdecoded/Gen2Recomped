package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Screens=require('src.ui.Screens')
local Summary=require('src.ui.SummaryMenu')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local old=V.get()
local function fixture(version)
 V.set(version);Screens.invalidate()
 local data=T.fixtures.fresh();data.constants.gen=V.generation();require('src.render.Font').load(data)
 -- Imported audio is present in real sessions. Keep the cue in this device-free fixture too.
 data.audio=data.audio or{};data.audio.sfx=data.audio.sfx or{}
 data.audio.sfx.Sfx_SwitchPokemon='fixture-native-switch.wav'
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',20),Pokemon.new(data,'FIXMON_C',15)}
 for _,mon in ipairs(save.party)do mon.moves={{id='FIX_TACKLE',pp=17,ppUps=2},{id='FIX_SCRATCH',pp=13,ppUps=1}}end
 local input={pressed={}}
 function input:wasPressed(k)return self.pressed[k]==true end
 local stack={states={},pops=0}
 function stack:top()return self.states[#self.states]end
 function stack:push(s)self.states[#self.states+1]=s end
 function stack:pop()self.pops=self.pops+1;return table.remove(self.states)end
 local parent={};stack:push(parent)
 local game={data=data,save=save,input=input,stack=stack}
 local function press(menu,key)input.pressed={[key]=true};menu:update(1/60);input.pressed={}end
 return game,press,parent
end
for _,version in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
 local game,press,parent=fixture(version);local party=game.save.party
 local closed=0
 local ok,menu=pcall(Screens.push,game,'Gen2SummaryMenu',{party=party,index=2,page=2,onClose=function()closed=closed+1;game.stack:pop()end})
 T.check(ok,version..' actual screen resolver accepts native party/index constructor')
 T.eq(ok and menu.mon,party[2],'summary keeps the actual requested Pokemon')
 if ok and menu.mon==party[2]then
  T.eq(menu.party,party,'public native party is the same real selection')
  T.eq(menu.screenId,'Gen2SummaryMenu','native screen resolution retains its public identity')
  T.eq(menu.index,2,'public index is actual selected slot')
  T.eq(menu.page,2,'native requested page is honored')
  T.eq(menu:speciesDef(),game.data.pokemon[party[2].species],'species reader returns the actual catalog row')
  T.eq(menu:moveList(),party[2].moves,'move list is not a presentation copy')
  T.eq(menu:moveDef('FIX_TACKLE'),game.data.moves.FIX_TACKLE,'native move catalog reader')
  T.eq(menu:moveName(party[2].moves[1]),game.data.moves.FIX_TACKLE.name,'move name comes from native catalog')
  local tag,draw,wide={},function()return 'consumer-draw'end,function()return 512,288 end
  menu.presentationOwner=tag;menu.draw=draw;menu.uiSize=wide
  local callback
  menu.onMonChange=function(index,mon)callback={index,mon}end
  local hp,pp,exp=party[2].hp,party[2].moves[1].pp,party[2].exp
  press(menu,'down')
  T.eq(menu.mon,party[3],'normal native input changes the actual Pokemon')
  T.eq(menu.index,3,'public index advances with native selection')
  T.eq(menu.presentationOwner,tag,'Pokemon navigation preserves consumer ownership')
  T.eq(menu.draw,draw,'Pokemon navigation preserves installed draw method')
  T.eq(menu:draw(),'consumer-draw','retained consumer draw method still executes on the actual instance')
  T.eq(menu.uiSize,wide,'Pokemon navigation preserves installed surface owner')
  T.eq(menu.onMonChange~=nil,true,'native change continuation survives navigation')
  T.eq(callback[1],3,'native change continuation gets current slot')
  T.eq(callback[2],party[3],'native change continuation gets actual Pokemon')
  T.eq(menu.page,2,'Pokemon change preserves the status page')
  press(menu,'down');T.eq(menu.mon,party[3],'native party navigation does not wrap past end')
  press(menu,'up');T.eq(menu.mon,party[2],'up returns to actual prior Pokemon')
  T.eq(party[2].hp,hp,'browsing cannot heal or damage a Pokemon')
  T.eq(party[2].moves[1].pp,pp,'browsing cannot spend PP')
  T.eq(party[2].exp,exp,'browsing cannot award EXP')
  party[2].item='POTION';game.data.items.POTION={name='NATIVE POTION'}
  T.eq(menu:itemName(),'NATIVE POTION','held-item reader uses native catalog')
  party[2].ot='NATIVE OT';party[2].otId=9876
  T.eq(menu:otName(),'NATIVE OT','native OT is preserved')
  T.eq(menu:otId(),9876,'native OT identifier is preserved')
  local def=menu:speciesDef();def.types={'FIRE','FIRE'}
  local a,b=menu:typeNames();T.eq(a,require('src.battle.TypeChart').displayName('FIRE',game.data),'type display follows native type registry');T.eq(b,nil,'duplicate second type is suppressed')
  def.growthRate='QA_NATIVE_CURVE';game.data.growth_rates=game.data.growth_rates or{}
  game.data.growth_rates.QA_NATIVE_CURVE={expForLevel=function(n)return n*1000 end}
  T.eq(menu:growth(),game.data.growth_rates.QA_NATIVE_CURVE,'growth reader is the native registry row')
  T.eq(menu:expToNext(),math.max(0,21000-party[2].exp),'next EXP reads actual native growth curve')
  press(menu,'right');T.eq(menu.page,3,'right advances to blue page')
  press(menu,'right');T.eq(menu.page,1,'right wraps after blue page')
  press(menu,'left');T.eq(menu.page,3,'left wraps to blue page')
  press(menu,'a');T.eq(closed,1,'A on final Gen2 page calls native close once')
  T.eq(game.stack:top(),parent,'close callback owns exactly its screen pop')
  menu:close();T.eq(closed,1,'repeat close does not call an already-released owner')
  local single=Summary.new(game,{mon=party[2]})
  T.eq(single.mon,party[2],'native isolated-mon constructor selects the actual Pokemon')
  T.eq(#single.party,1,'isolated summary cannot browse unrelated save Pokemon')
  local manager=Screens.push(game,'Gen2SummaryMenu',{party=party,index=1,moveScreen=true})
  T.check(manager.moveDetail,'native MOVE request opens actual move-management mode')
  local first,second=party[1].moves[1],party[1].moves[2]
  press(manager,'a');T.eq(manager.swapFrom,1,'actual A picks up a move slot')
  press(manager,'down');T.eq(manager.moveIndex,2,'actual down chooses the destination')
  press(manager,'right');T.eq(manager.mon,party[1],'held move blocks party switching')
  local swapped,swapError=pcall(press,manager,'a')
  T.check(swapped,'native move swap with an imported sound cue must not call unavailable audio APIs: '..tostring(swapError))
  T.eq(party[1].moves[1],second,'native swap moves the whole destination slot')
  T.eq(party[1].moves[2],first,'native swap retains original PP and PP-Up record identity')
  T.eq(first.pp,17,'move rearrangement does not restore or spend PP')
  T.eq(first.ppUps,2,'move rearrangement preserves PP Ups')
  T.eq(manager.swapFrom,nil,'completed native swap releases its lift owner')
  press(manager,'a');press(manager,'up');press(manager,'b')
  T.eq(manager.moveIndex,2,'B while holding restores cursor to lifted row')
  T.eq(manager.swapFrom,nil,'B cancels only the lifted move')
  T.eq(game.stack:top(),manager,'cancelling a lift does not exit the manager')
  T.eq(party[1].moves[1],second,'cancel leaves actual move order intact')
  party[2].isEgg=true
  press(manager,'right');T.eq(manager.mon,party[3],'move-screen native party navigation skips eggs')
  press(manager,'right');T.eq(manager.mon,party[3],'move-screen party navigation does not wrap')
  press(manager,'left');T.eq(manager.mon,party[1],'move-screen left skips egg in reverse')
  local Font=require('src.render.Font');local nativeDraw=Font.draw;local unicodeFrame=false
  Font.draw=function(text,...)
   for _,edge in ipairs{'┌','─','┐','│','└'}do if tostring(text):find(edge,1,true)then unicodeFrame=true end end
   return nativeDraw(text,...)
  end
  local painted,paintError=pcall(manager.drawMoveDetail,manager);Font.draw=nativeDraw
  T.check(painted,'actual native move-screen drawer accepts live slots and descriptions: '..tostring(paintError))
  T.eq(unicodeFrame,false,'native border glyphs do not depend on Unicode text-font coverage')
  press(manager,'b');T.eq(game.stack:top(),parent,'B exits native standalone move screen')
  local status=Screens.push(game,'Gen2SummaryMenu',{party=party,index=1,page=2})
  press(status,'select');T.check(status.moveDetail,'SELECT enters move details from native green page')
  press(status,'b');T.eq(status.moveDetail,false,'B returns from detail to the original status page')
  T.eq(game.stack:top(),status,'detail return preserves status screen owner')
  press(status,'b');T.eq(game.stack:top(),parent,'next B releases status screen')
 end
end
for _,version in ipairs{'red','firered','emerald'}do
 local game,press,parent=fixture(version)
 local menu=Summary.new(game,game.save.party[1]);game.stack:push(menu)
 press(menu,'a');T.eq(menu.page,2,version..' keeps shared two-page navigation')
 press(menu,'a');T.eq(game.stack:top(),parent,version..' shared A closes second page')
end
V.set(old);Screens.invalidate()
T.finish('native Gen2 summary constructor, navigation and move-management ownership')
