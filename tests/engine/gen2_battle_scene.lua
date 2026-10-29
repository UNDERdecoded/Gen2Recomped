package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Wide=require('src.battle.WideBattle')
local Runtime=require('src.mods.Runtime')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local before=Version.get()
local wants,call=Runtime.wantsHook,Runtime.call
local overlays,expected=0
Runtime.wantsHook=function(name)if name=='battle.overlay'then return true end;return wants(name)end
Runtime.call=function(name,vanilla,screen,...)
 if name=='battle.overlay'then overlays=overlays+1;T.eq(screen,expected,'overlay receives actual native screen');return vanilla(screen)end
 return call(name,vanilla,screen,...)
end
for _,edition in ipairs({'gold','silver','crystal'})do
 Version.set(edition)
 local data=T.fixtures.fresh();require('src.render.Font').load(data)
 local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',30)}
 local s=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
 expected=s
 local layers={};local scene,body=s.drawScene,s.drawSceneBody
 s.drawScene=function(self,...)layers[#layers+1]='scene';return scene(self,...)end
 s.drawSceneBody=function(self,...)layers[#layers+1]='body';return body(self,...)end
 s.drawPicsLayer=function()layers[#layers+1]='pics'end
 s.drawHUDs=function()layers[#layers+1]='hud'end
 s.drawTextArea=function()layers[#layers+1]='text'end
 s.drawAnimLayer=function()layers[#layers+1]='objects'end
 s.colorMode=function()return false end
 local count=overlays;s:draw()
 T.same(layers,{'scene','body','pics','hud','text','objects'},'actual classic draw reaches native scene/BG/OAM owners once')
 T.eq(overlays,count+1,'actual scene emits one final overlay')
 layers={};count=overlays
 s:drawSceneBody(function()layers[#layers+1]='custom'end)
 T.same(layers,{'body','custom','objects'},'replacement panel retains native object pass')
 T.eq(overlays,count,'scene body does not emit duplicate final overlay')
 layers={};s:drawScene(function()s:drawSceneBody(function()layers[#layers+1]='supplied'end)end)
 T.same(layers,{'scene','body','supplied','objects'},'supplied scene body stays inside actual outer owner')
 layers={};s.blankForAskName=true;s:drawSceneBody()
 T.same(layers,{'body'},'native naming blank suppresses battle pictures and objects')
 s.blankForAskName=nil
 local g=love.graphics;local sentinel={};g.setShader(sentinel);g.setColor(.2,.3,.4,.5)
 T.raises(function()s:drawSceneBody(function()g.setShader();g.setColor(0,0,0,1);error('panel draw failed')end)end,'panel draw failed','native scene propagates panel error')
 T.eq(g.getShader(),sentinel,'failed panel restores graphics owner')
 T.same({g.getColor()},{.2,.3,.4,.5},'failed panel restores caller tint')
 g.setShader();g.setColor(1,1,1,1)
 local nativeBody=s.drawSceneBody;local widths={};layers={};count=overlays
 s.drawSceneBody=function(self,panel,objects,w,h)
  widths={w,h};return nativeBody(self,panel,objects,w,h)
 end
 Wide.draw(s)
 T.same(widths,{304,144},'actual native widescreen enters same composition owner with real surface')
 T.eq(layers[1],'scene','wide layout enters native outer scene')
 T.eq(layers[2],'body','wide layout enters native BG/OAM scene')
 T.eq(overlays,count+1,'wide layout emits one final overlay')
 -- Red keeps its existing layout route. Presence of a Gen2 method must not
 -- redirect other games simply because they share the native screen class.
 Version.set('red');layers={};s:drawClassic()
 T.check(layers[1]~='scene'and layers[1]~='body','Gen1 classic route remains native original route')
 layers={};Wide.draw(s)
 T.check(layers[1]~='scene'and layers[1]~='body','Gen1 wide route remains native original route')
end
Runtime.wantsHook,Runtime.call=wants,call;Version.set(before)
T.finish('native Gen2 classic/wide scene owner, panel replacement and layer lifecycle')
