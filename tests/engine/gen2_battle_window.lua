-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Chrome=require('src.ui.Gen2Chrome')
local UI=require('src.render.ScreenSpaceUI')
local before=V.get()
for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal','red','firered','emerald'})do
 V.set(version)
 local data=T.fixtures.fresh();require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
 local game={data=data,save=save,stack={states={}}}
 local b=Battle.newWild(game,'FIXMON_C',20);game.stack.states={b}
 T.eq(type(b.drawWidescreen),'function',version..' actual native battle exposes its window drawer')
 T.eq(type(b.drawsWidescreen),'function','window admission is explicit on the actual screen')
 if type(b.drawWidescreen)=='function'and type(b.drawsWidescreen)=='function'then
  T.eq(b:drawsWidescreen(),V.isGen2(),'only Gen2 opts into native window composition')
  T.eq(UI.select(game.stack,game.stack,1),V.isGen2()and b or nil,'actual compositor selection preserves other edition routes')
  if V.isGen2()then
   local native=b.drawScene;local scenes=0
   b.drawScene=function(self,...)scenes=scenes+1;T.eq(self,b,'window drawing retains the actual battle owner');return native(self,...)end
   b.colorMode=function()return false end
   local g=love.graphics;local dpi=g.getDPIScale
   for _,ratio in ipairs({1,2})do
    g.getDPIScale=function()return ratio end
    for _,layout in ipairs({'classic','wide'})do
     save.options.battleLayout=layout
     local pw,ph=b:uiSize()
     T.same({b:panelSize()},{pw,ph},'window uses the actual native layout dimensions')
     for _,size in ipairs({{1280,960},{900,1500},{640,480}})do
      local w,h=size[1],size[2]
      save.options.battleFit='fixed'
      T.eq(b:battlePanelScale(w,h),Chrome.fitScaleFor(w,h,pw/8,ph/8),'fixed native scale obeys physical pixel grid and layout')
      local count=scenes;b:drawWidescreen(w,h)
      T.eq(scenes,count+1,'actual classic/wide window enters the native scene exactly once')
      save.options.battleFit='fill'
      local _,_,fw,fh=Chrome.playfieldRect(w,h)
      T.eq(b:battlePanelScale(w,h),math.min(fw/pw,fh/ph),'existing fill option fits the real panel')
      count=scenes;b:drawWidescreen(w,h)
      T.eq(scenes,count+1,'fill keeps the same native scene owner')
     end
    end
   end
   g.getDPIScale=dpi
   save.options.battleLayout='classic';save.options.battleFit='fixed'
   local shader={};local canvas=g.newCanvas(17,19);local other=g.newCanvas(11,13)
   g.setCanvas(canvas);g.setShader(shader);g.setColor(.2,.3,.4,.5)
   b.drawScene=function()g.push('all');g.setCanvas(other);g.setShader();g.setColor(0,0,0,1);error('native window scene failure')end
   T.raises(function()b:drawWidescreen(1280,960)end,'native window scene failure','real native window propagates a failed scene')
   T.eq(g.getCanvas(),canvas,'failed scene releases its canvas and caller owner')
   T.eq(g.getShader(),shader,'failed scene restores caller shader')
   T.same({g.getColor()},{.2,.3,.4,.5},'failed scene restores caller tint despite a leaked push')
   g.setCanvas();g.setShader();g.setColor(1,1,1,1)
  end
 end
end
V.set(before)
T.finish('native Gen2 battle window, physical scale, scene owner and error boundary')
