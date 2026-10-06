package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Dialogue docking and Platinum names')
local V=require('src.core.GameVersion')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local paints={}
Assets.image=function() return {getDimensions=function() return 144,160 end} end
love.graphics.newQuad=function(x,y,w,h) return {x=x,y=y,w=w,h=h} end
love.graphics.draw=function(_,_,x,y,_,sx,sy)
 if sy and sy<0 then y=y-8 end
 if sx and sx<0 then x=x-8 end
 paints[#paints+1]={x=x,y=y,w=8,h=8}
end
love.graphics.rectangle=function(_,x,y,w,h) paints[#paints+1]={x=x,y=y,w=w,h=h} end
local TextBox=require('src.render.TextBox')
local Renderer=require('src.render.Renderer')
local layouts={
 {version='red',box={0,12,20,6},width=160,height=144},
 {version='blue',box={0,12,20,6},width=160,height=144},
 {version='yellow',box={0,12,20,6},width=160,height=144},
 {version='gold',box={0,12,20,6},width=160,height=144},
 {version='silver',box={0,12,20,6},width=160,height=144},
 {version='crystal',box={0,12,20,6},width=160,height=144},
 {version='prism',box={0,12,20,6},width=160,height=144},
 {version='polishedcrystal',box={0,12,20,6},width=160,height=144},
 {version='emerald',box={1,14,28,6},width=240,height=160,frames=true},
 {version='firered',box={1,14,28,6},width=240,height=160,dialogue={image='fr-frame',tiles=18,count=1}},
 {version='platinum',box={1,18,29,6},width=256,height=192,dialogue={image='pt-frame',tiles=18,count=20,layout='gen4'}},
}
for _,case in ipairs(layouts) do
 V.set(case.version)
 Font.load({font={pages={normal={image='test-font',base=0,glyphsPerRow=16}},frame=case.frames and 'sheet' or 'drawn',frames=case.frames and {image='emerald-frame',count=20,cell=24,tile=8} or nil,dialogueFrame=case.dialogue}})
 local b=case.box
 local render=setmetatable({uiAnchors={},uiCentered=false}, {__index=Renderer})
 local box=setmetatable({game={renderer=render},boxTx=b[1],boxTy=b[2],boxTw=b[3],boxTh=b[4],drawFrame=true,shown={},letterSpacing=0},{__index=TextBox})
 paints={};box:draw()
 local a=render.uiAnchors[1]
 T.check(a~=nil,case.version..' registers full frame')
 for _,p in ipairs(paints) do
  T.check(p.x>=a.x and p.y>=a.y and p.x+p.w<=a.x+a.w and p.y+p.h<=a.y+a.h,case.version..' painted edge lies inside docking region')
 end
 for _,screen in ipairs({{390,844},{844,390},{1280,800}}) do
  for _,dpi in ipairs({1,1.5,2.755}) do
   local scale=math.floor(math.min(screen[1]*dpi/case.width,screen[2]*dpi/case.height))/dpi
   local safeBottom=screen[2]-(dpi==1 and 0 or 24)
   local gap=(case.height-a.y-a.h)*scale
   local dy=safeBottom-gap-a.h*scale
   for _,p in ipairs(paints) do
    local y=dy+(p.y-a.y)*scale
    T.check(y>=dy-0.001 and y+p.h*scale<=dy+a.h*scale+0.001,case.version..' Android/desktop edges dock with middle')
   end
  end
 end
 if case.version=='platinum' then T.eq(a.x,0,'Platinum left cap');T.eq(a.w,256,'Platinum right cap reaches native edge') end
 if case.version=='firered' then T.eq(a.x,0,'FireRed left cap');T.eq(a.w,240,'FireRed right cap reaches native edge') end
 -- Unframed windows retain precisely their supplied bounds.
 render.uiAnchors={};box.drawFrame=false;box.fillColor={1,1,1};box:draw();a=render.uiAnchors[1]
 T.eq(a.x,b[1]*8,case.version..' plain window position');T.eq(a.w,b[3]*8,case.version..' plain window width')
end
V.set('platinum')
local Screens=require('src.ui.Screens')
local Rowan=require('src.ui.Gen4RowanIntro')
local Naming=require('src.ui.Gen4NamingScreen')
for _,gender in ipairs({'boy','girl'}) do
 local pushed
 local game={data={isGen4Cache=true,constants={playerNameLength=7},field={boot={namePresets={player={'Lucas','Dawn'}}}}},save={player={}},stack={push=function(_,s) pushed=s end,pop=function() end}}
 local intro=setmetatable({game=game,answers={gender=gender},rec={text={name='Your name?',rivalName='Rival name?'},rivalNames={{custom=true,label='New name!'},{label='Barry'}}},fill=function(_,s) return s end,say=function() end},{__index=Rowan})
 intro:askName()
 T.eq(getmetatable(pushed),Naming,gender..' player uses Gen4 keyboard')
 T.eq(pushed.female,gender=='girl',gender..' header gender preserved')
 T.eq(pushed.maxLen,7,'player name length')
 pushed.onDone('CEDRIC');T.eq(game.save.player.name,'CEDRIC','player name callback')
 intro:askRivalName();T.eq(getmetatable(pushed),Naming,'rival uses Gen4 keyboard');pushed.onDone('BARRY');T.eq(game.save.player.rival,'BARRY','rival name callback')
 local id=Screens.resolveId(game,'NamingScreen',{kind='mon',mon={species=387},species=387,title='Nickname?',onDone=function() end})
 T.eq(id,'Gen4NamingScreen','nickname still routes to Gen4')
end
T.finish()

