package.path='./?.lua;'..package.path
love=require('tests.love_stub')
love.system={getOS=function() return 'Android' end}
love.graphics.newImage=function() return {setFilter=function() end} end
local sizeW,sizeH=390,844
package.loaded['src.core.SafeArea']={rect=function() return 0,0,sizeW,sizeH end}
local T=require('tests.harness').suite('Mobile control gestures')
local V=require('src.core.GameVersion')
local Input=require('src.core.Input')
local TC=require('src.core.TouchControls')
local Game=require('src.core.Game')
Game.freeView=function() return true end
local top,claimed={},0
local game=setmetatable({input=Input,stack={top=function() return top end}}, {__index=Game})
local function init(version)
 V.set(version);Input:init();TC:init();TC.active=true;TC.enabled=true;TC.img={}
 for _,name in ipairs({'a','b','start','select','l','r','dpad'}) do TC.img[name]={} end
 top={touchpressed=function() claimed=claimed+1;return true end,touchmoved=function() claimed=claimed+1;return true end,touchreleased=function() claimed=claimed+1;return true end}
 game.pointerOwners={}
 return TC:layout()
end
local function tap(control,id)
 local z=TC:layout()[control];game:touchpressed(id or 1,z.cx,z.cy);game:touchreleased(id or 1,z.cx,z.cy);Input:step()
end
for _,version in ipairs({'red','yellow','gold','silver','crystal','emerald','firered','platinum'}) do
 local L=init(version)
 for _,btn in ipairs({'a','b','start','select'}) do
  tap(btn);T.check(Input:wasPressed(btn),version..' '..btn..' reaches input');T.check(not Input:isDown(btn),version..' '..btn..' releases before fixed step')
 end
 local before=claimed
 for _,dir in ipairs({'up','down','left','right'}) do
  local dx=dir=='left' and -L.dpad.w*0.4 or dir=='right' and L.dpad.w*0.4 or 0
  local dy=dir=='up' and -L.dpad.w*0.4 or dir=='down' and L.dpad.w*0.4 or 0
  game:touchpressed(2,L.dpad.cx+dx,L.dpad.cy+dy)
  T.eq(TC.touches[2].control,'dpad',version..' free camera cannot steal dpad')
  Input:step();T.check(Input:wasPressed(dir),version..' fresh direction edge')
  top={touchreleased=function() claimed=claimed+1;return true end}
  game:touchreleased(2,250,200);Input:step();T.check(not Input:isDown(dir),version..' release survives state switch')
 end
 T.eq(claimed,before,version..' controls bypass screen capture')
end
local L=init('platinum')
T.eq(L.a.cy,L.y.cy,'A/Y horizontal');T.eq(L.b.cx,L.x.cx,'B/X vertical')
T.check(L.x.cy<L.a.cy and L.b.cy>L.a.cy and L.y.cx<L.a.cx,'Nintendo DS diamond positions')
for _,entry in ipairs({{'x','start'},{'y','select'}}) do
 tap(entry[1]);T.check(Input:wasPressed(entry[1]) and Input:wasPressed(entry[2]),entry[1]..' native action')
end
local Start=require('src.ui.Gen4StartMenu')
local menu=setmetatable({game=game,rows={{},{},{},{},{},{}},index=1},{__index=Start})
for i=1,5 do
 game:touchpressed(3,L.dpad.cx,L.dpad.cy+L.dpad.w*0.4);Input:step();menu:update()
 game:touchreleased(3);Input:step();T.eq(menu.index,i+1,'repeated start-menu down tap '..i)
end
local Starter=require('src.ui.Gen4StarterSelect')
local starter=setmetatable({game=game,rows={{},{},{}},index=1,camStep=6,phase='choosing',pages={'choose'},page=1},{__index=Starter})
for _,dir in ipairs({'right','right','left','left'}) do
 local dx=dir=='right' and L.dpad.w*0.4 or -L.dpad.w*0.4
 game:touchpressed(4,L.dpad.cx+dx,L.dpad.cy);Input:step();starter:update();game:touchreleased(4);Input:step()
end
T.eq(starter.index,1,'starter moves left and right through all three choices')
-- Sliding off the D-pad and missing OS releases cannot leave a hold.
game:touchpressed(5,L.dpad.cx,L.dpad.cy+L.dpad.w*0.4);Input:step()
game:touchmoved(5,250,200);T.check(not Input:isDown('down'),'leaving dpad releases movement')
game:touchreleased(5)
game:touchpressed(6,L.b.cx,L.b.cy);game:touchpressed(6,L.a.cx,L.a.cy)
T.check(not Input:isDown('b') and Input:isDown('a'),'reused pointer releases old button')
love.touch={getTouches=function() return {} end};TC:pollTouches();Input:step()
T.check(not Input:isDown('a') and next(TC.touches)==nil,'OS cancellation recovered')
-- Separate fingers continue to own A until the last one lifts.
game:touchpressed(7,L.a.cx,L.a.cy);game:touchpressed(8,L.a.cx,L.a.cy);game:touchreleased(7)
T.check(Input:isDown('a'),'second finger retains A');game:touchreleased(8);T.check(not Input:isDown('a'),'last finger releases A')
-- A lower-display gesture with the same numeric id cannot release the
-- primary screen's control; the two panels have separate coordinate spaces.
game:touchpressed(9,L.b.cx,L.b.cy)
game.secondScreenInjecting=true;game:touchreleased(9,100,100);game.secondScreenInjecting=nil
T.check(Input:isDown('b'),'other display cannot release primary B')
game:touchreleased(9);T.check(not Input:isDown('b'),'primary B still releases normally')
TC.controllerHidden=true;TC:touchpressed(10,L.b.cx,L.b.cy)
T.check(Input:isDown('b') and not TC.controllerHidden,'first touch restores controls and presses B');TC:touchreleased(10)
V.set('emerald');T.check(not TC:layout().x,'Gen3 retains its two-button layout');Input:overlayPressed('x');Input:step();T.check(not Input:wasPressed('start'),'X does not alias START in other generations')
T.finish()
