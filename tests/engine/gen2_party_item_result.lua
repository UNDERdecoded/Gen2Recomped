-- Contract adapted from Gen1Recomp 535a5ec0 native PartyMenu/HpBar.
-- Existing project rights/licences remain applicable. Contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Party=require('src.ui.PartyMenu')
local Pokemon=require('src.pokemon.Pokemon')
local Font=require('src.render.Font')
local Chrome=require('src.ui.Gen2Chrome')
local Hud=require('src.render.HudTiles')
local Overlay=require('src.render.NativeScreenOverlay')
local UI=require('src.render.ScreenSpaceUI')
local Stack=require('src.core.StateStack')
local Sound=require('src.core.Sound')
local oldVersion=V.get();V.set('crystal')
local data=T.fixtures.fresh();Font.load(data)
data.audio=data.audio or{};data.audio.sfx=data.audio.sfx or{}
data.audio.sfx.Sfx_Potion='fixture-native-potion.wav'
local input={pressed={}}
function input:wasPressed(k)return self.pressed[k]==true end
local game={data=data,save={party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',20)}},input=input}
game.stack=setmetatable({},{__index=Stack});game.stack:init()
local menu=Party.new(game,{pickOnly=true,keepOpen=true});game.stack:push(menu)
T.eq(type(menu.showItemResult),'function','actual PartyMenu offers native result owner')
if type(menu.showItemResult)=='function'then
 for _,maxHp in ipairs({19,47,48,49,96,301})do
  local mon=menu.party[1];mon.stats.hp=maxHp;mon.hp=maxHp
  local pp=mon.moves[1].pp;local done=0
  menu:showItemResult(1,{fromHp=0,toHp=maxHp,text='NATIVE RESULT',onDone=function()done=done+1 end})
  local result=menu.itemResult
  T.eq(menu.heal,result,'one actual HP hold prevents a second animation/input clock')
  T.eq(menu:shownHpFor(1,mon),0,'zero pre-revive HP is a real display value')
  local ticks=0;local stride=maxHp>=48 and math.ceil(maxHp/48)or 1
  input.pressed={a=true}
  while menu:itemResultClimbing()and ticks<400 do
   local before=result.shown;menu:update(1/60);ticks=ticks+1
   T.eq(result.shown,math.min(maxHp,before+stride),'native HP step matches reference at this max HP')
   T.eq(mon.hp,maxHp,'bar stepping never fabricates gameplay HP')
   T.eq(mon.moves[1].pp,pp,'bar stepping cannot spend PP')
   T.eq(done,0,'early A cannot acknowledge a climbing bar')
  end
  T.eq(ticks,math.ceil(maxHp/stride),'native fill duration follows HP step count')
  T.eq(menu.itemResult.delay,50,'fill does not spend any native message hold')
  T.eq(menu:wantsNativeOverlay(),true,'result text becomes visible after the bar lands')
  for i=1,50 do menu:update(1/60)end
  T.eq(done,0,'A during the 50-frame delay cannot skip the hold')
  input.pressed={};menu:update(1/60)
  T.eq(done,0,'elapsed delay alone does not confirm')
  input.pressed={b=true};menu:update(1/60);input.pressed={}
  T.eq(done,1,'native B acknowledges once after the full delay')
  T.eq(menu.itemResult,nil,'acknowledgment retires native result owner')
  T.eq(menu.heal,nil,'same acknowledgment retires shared HP hold')
  T.eq(game.stack:top(),menu,'controller callback alone owns screen lifetime')
 end
 local done=0
 menu.party[1].stats.hp=19;menu.party[1].hp=19 -- this case requires one-HP native steps
 menu:showItemResult(1,{fromHp=5,toHp=2,auto=true,onDone=function()done=done+1 end})
 for i=1,3 do menu:update(1/60)end
 T.eq(done,0,'auto result still waits for all downward HP steps')
 menu:update(1/60);T.eq(done,1,'auto result completes on the tick after fill')
 menu:showItemResult(2,{text='STATUS RESULT',delay=0,holdSlot=1,holdHp=0,onDone=function()done=done+1 end})
 T.eq(menu:shownHpFor(1,menu.party[1]),0,'held other slot preserves explicit zero')
 T.eq(menu:shownHpFor(2,menu.party[2]),menu.party[2].hp,'status result uses actual HP when no animation requested')
 input.pressed={a=true};menu:update(1/60);input.pressed={}
 T.eq(done,2,'zero delay respects immediate native confirmation')
 local pages=0
 menu:showItemResult(1,{text='FIRST ROW\nSECOND ROW\nTHIRD ROW',delay=0,onDone=function()pages=pages+1 end})
 input.pressed={a=true};menu:update(1/60);input.pressed={}
 T.eq(pages,0,'long native result cannot lose its final rows or release the enemy early')
 T.eq(menu.itemResult.line,3,'native result acknowledgment advances to remaining text')
 T.eq(menu.itemResult.delay,50,'remaining native page receives its own confirmation hold')
 for i=1,50 do menu:update(1/60)end
 input.pressed={b=true};menu:update(1/60);input.pressed={}
 T.eq(pages,1,'last native page acknowledgment releases exactly one continuation')
 local played={};local soundPlay=Sound.play
 Sound.play=function(actual,name)T.eq(actual,data,'native cue uses actual imported data');played[#played+1]=name end
 menu:showItemResult(1,{text='HP RESTORED',sfx='Sfx_Potion'})
 T.same(played,{'Sfx_Potion'},'native result cue uses existing Sound.play with no invented resolver')
 menu:playSfx('missing');T.eq(#played,1,'missing optional native cue is not invented')
 Sound.play=soundPlay
 -- Native party rows must consume the real result's shown HP, not change the mon.
 local hp=menu.party[1].hp
 menu:showItemResult(1,{fromHp=0,toHp=hp,text='HP RESTORED'})
 local bars={};local drawBar=Hud.drawHPBar
 Hud.drawHPBar=function(d,x,y,mon,...)bars[#bars+1]=mon.hp;return drawBar(d,x,y,mon,...)end
 menu:draw();Hud.drawHPBar=drawBar
 T.eq(bars[1],0,'actual native row draws zero displayed HP during revive')
 T.eq(menu.party[1].hp,hp,'drawing cannot replace real HP')
 -- A replaceable view may reset origin and omit feedback. The engine's
 -- controller-owned pass must still paint it once, before modal children.
 menu:showItemResult(1,{text='HP RESTORED\nNATIVE CONFIRM'})
 local print=Chrome.print;local box=Chrome.textbox;local panel=Chrome.withOverlayPanel
 local trace={};Chrome.print=function(text)trace[#trace+1]=text end
 Chrome.textbox=function()trace[#trace+1]='native-box'end
 menu.draw=function()trace[#trace+1]='custom-view';love.graphics.origin()end
 menu.uiSize=function()return 512,288 end
 local dimensions={};Chrome.withOverlayPanel=function(w,h,draw)dimensions={w,h};draw()end
 Overlay.screen(menu)
 T.same(trace,{'custom-view','native-box','HP RESTORED','NATIVE CONFIRM'},'engine paints native confirmation after the replaceable party view')
 T.same(dimensions,{512,288},'classic expanded view uses its actual declared surface')
 trace={};game.stack:draw()
 T.same(trace,{'custom-view','native-box','HP RESTORED','NATIVE CONFIRM'},'actual state stack paints feedback exactly once')
 local front={draw=function()trace[#trace+1]='modal-child'end};game.stack:push(front)
 trace={};game.stack:draw()
 T.eq(trace[#trace],'modal-child','native modal children stay above controller feedback')
 game.stack:pop()
 local viewport={width=1280,height=960}
 local renderer={WIDTH=512,HEIGHT=288,uiPresentation={x=0,y=0,scaleX=1,scaleY=1}}
 function renderer:uiSize()return 512,288 end
 trace={};UI.drawNativeStack(game.stack,game.stack,1,nil,renderer,viewport,false)
 T.same(dimensions,{1280,960},'native full-resolution pass uses actual window dimensions')
 T.same(trace,{'custom-view','native-box','HP RESTORED','NATIVE CONFIRM'},'native full-resolution pass paints feedback once')
 menu.drawWidescreen=function()trace[#trace+1]='custom-window'end
 trace={};UI.draw(menu,renderer,viewport,nil,false)
 T.same(trace,{'custom-window','native-box','HP RESTORED','NATIVE CONFIRM'},'window-resolution owner cannot drop native confirmation')
 trace={};local hidden={renderVisible=function()return false end}
 UI.drawNativeStack(hidden,game.stack,1,nil,renderer,viewport,false)
 T.eq(#trace,0,'hidden owner cannot resurrect feedback')
 -- Guard both view leaks and native feedback errors, including leaked pushes.
 local g=love.graphics;local canvas=g.newCanvas(9,11);local other=g.newCanvas(5,7)
 g.setCanvas(canvas);g.setColor(.2,.3,.4,.5)
 menu.draw=function()g.push('all');g.setCanvas(other);g.setColor(0,0,0,1)end
 Overlay.screen(menu)
 T.eq(g.getCanvas(),canvas,'view leaking a canvas cannot steal confirmation output')
 T.same({g.getColor()},{.2,.3,.4,.5},'view tint/push cannot leak into caller')
 menu.drawWidescreen=menu.draw
 Overlay.window(menu,1280,960)
 T.eq(g.getCanvas(),canvas,'window view leaking a canvas cannot steal native feedback')
 T.same({g.getColor()},{.2,.3,.4,.5},'window view restores tint and leaked pushes')
 Chrome.textbox=function()g.push('all');g.setCanvas(other);error('native result draw failure')end
 T.raises(function()Overlay.screen(menu)end,'native result draw failure','native feedback errors remain observable')
 T.raises(function()UI.draw(menu,renderer,viewport,nil,false)end,'native result draw failure','window feedback errors remain observable')
 T.eq(g.getCanvas(),canvas,'failed feedback restores actual caller target')
 T.same({g.getColor()},{.2,.3,.4,.5},'failed feedback restores tint and leaked pushes')
 Chrome.print=print;Chrome.textbox=box;Chrome.withOverlayPanel=panel
 g.setCanvas();g.setColor(1,1,1,1)
end
V.set(oldVersion)
T.finish('native Gen2 party item result, timing, input and render ownership')
