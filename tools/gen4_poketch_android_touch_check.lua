package.path='./?.lua;'..package.path
love={math={random=math.random},graphics={}}
package.loaded['src.render.Assets']={image=function() return nil end,register=function() end}
package.loaded['src.render.Font']={width=function(s) return #s*6 end,draw=function() end}
package.loaded['src.core.GameVersion']={generation=function() return 4 end,
 get=function() return 'platinum' end,isGen2=function() return false end,isGen3=function() return false end}
package.loaded['src.core.FrameProfile']={section=function() return function() end end,frame=function() end}
package.loaded['src.ui.SaveCompanion']={tick=function() end}
local overlay=0
package.loaded['src.core.TouchControls']={touchpressed=function() overlay=overlay+1 end,
 touchmoved=function() overlay=overlay+1 end,touchreleased=function() overlay=overlay+1 end}
local Renderer={uiPresentation={x=100,y=50,w=768,h=576,scaleX=3,scaleY=3}}
package.loaded['src.render.Renderer']=Renderer
local SS=require('src.ui.SecondScreen')
local events={}
SS._setTransport({available=function() return true end,pollTouch=function() local out=events;events={};return out end})
local Game=require('src.core.Game')
local Watch=require('src.ui.Gen4Poketch')
local apps={{name='Counter'},{name='Memo Pad'},{name='Coin Toss'}}
local top={}
local game=setmetatable({data={isGen4Cache=true,gen4_menus={poketch={apps=apps}}},
 save={options={secondScreenMode='display'},inventory={}},stack={top=function() return top end}}, {__index=Game})
game._draw=function(self) self.secondScreenDrawnThisFrame=false end
-- Exercise the real fallback owner selection without a graphics device.
SS.draw=function(g,body) g.secondScreenDrawnThisFrame=true;body() end
SS.flush=function() end
Watch.drawWatch=function(self) self.draws=(self.draws or 0)+1 end
game:draw()
local watch=game.secondScreenOverworldPoketch
assert(watch and game.secondScreenPointerOwner==watch and watch.draws==1)
game:touchpressed('window',440,434)
assert(not game.save.poketch.counter and overlay==1,'main window must not operate the other display')
local function tap(id,x,y)
 assert(SS.injectTouch(game,'touchpressed',id,x,y))
 assert(SS.injectTouch(game,'touchreleased',id,x,y))
end
tap('android',114,128)
assert(game.save.poketch.counter==1 and overlay==1,'Android lower display must reach the watch, not virtual buttons')
tap('android',240,120);assert(watch.index==2 and game.save.poketch.app==2)
assert(SS.injectTouch(game,'touchpressed',7,30,30))
assert(SS.injectTouch(game,'touchpressed',8,240,120))
assert(watch.index==2 and watch.pointer==7,'second finger stole a memo drag or switched apps')
SS.injectTouch(game,'touchreleased',8,240,120)
SS.injectTouch(game,'touchmoved',7,40,40)
assert(next(game.save.poketch.memo),'memo drag was lost')
-- Pointer release remains deliverable after crossing into the letterbox.
assert(SS.injectTouch(game,'touchreleased',7,-10,200))
assert(watch.pointer==nil and game.pointerOwners[7]==nil)
tap('android',240,60);assert(watch.index==1,'previous app button')
tap('android',240,60);assert(watch.index==3,'backward wrap')
tap('android',112,96);assert(watch.coinAnimation,'coin touch')
local ticks=watch.coinAnimation.ticks
watch:updatePresentation(1/60)
assert(watch.coinAnimation.ticks>ticks,'passive lower-panel coin animation does not advance')
-- A specialized bottom-screen state replaces the fallback after a draw.
local claimed=0
top={touchpressed=function() claimed=claimed+1;return true end,touchreleased=function() return true end}
game._draw=function(self) self.secondScreenDrawnThisFrame=true end
game:draw();assert(game.secondScreenPointerOwner==nil)
tap('battle',100,80);assert(claimed==1,'specialized lower screen input lost')
-- Window touch and mouse coordinates share the actual rendered transform.
top=watch;game.save.options.secondScreenMode='swap';watch.index=1
game:touchpressed('mouse',100+114*3,50+128*3)
local originalTop=top;top={}
assert(game:hasPointerScreen(),'mouse release routing lost when stack changed during a press')
game:touchreleased('mouse',100+114*3,50+128*3)
top=originalTop
assert(game.save.poketch.counter==2,'scaled main-window mouse/touch mapping')
game.save.options.secondScreenMode='inset'
local x,y,s=SS.rect(game)
game:touchpressed('finger',100+(x+240*s)*3,50+(y+120*s)*3)
game:touchreleased('finger',100+(x+240*s)*3,50+(y+120*s)*3)
assert(watch.index==2,'inset bezel input transform')
game.save.poketch.registered={[0]=true,[2]=true}
watch.index=1;watch:cycle(1);assert(watch.index==3,'cycle did not skip a locked app')
watch:cycle(-1);assert(watch.index==1,'backward cycle did not skip a locked app')
game.save.poketch.registered[1]=true
watch:cycle(1);assert(watch.index==2,'newly registered app was not immediately available')
game.save.poketch.registered={[0]=true}
watch:cycle(1);assert(watch.index==1)
watch:cycle(-1);assert(watch.index==1,'single unlocked app must stay selected')
game.save.poketch.app=2
local reopened=Watch.new(game)
assert(reopened.index==1,'saved selection stayed on a locked app')
game.save.options.secondScreenMode='display'
game.secondScreenPointerOwner=watch;top={};watch.index=1
game.secondScreenNativePanel=true;game.secondScreenSurfaceWidth=768;game.secondScreenSurfaceHeight=576
tap('high-dpi',114*3,128*3)
assert(game.save.poketch.counter==3,'native physical panel touch was not scaled to DS coordinates')
game.secondScreenNativePanel=nil
events={{kind='down',id=9,x=114,y=128},{kind='up',id=9,x=114,y=128}}
assert(SS.pumpInput(game)==2 and game.save.poketch.counter==4,'queued Android host taps did not reach displayed watch')
print('Android lower-panel fallback routing, both bezel buttons, wrap, memo/multitouch, letterbox release, coin ticks, state ownership, scaled swap/inset mouse and touch passed')
