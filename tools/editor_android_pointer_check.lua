package.path='tools/save-editor/?.lua;tools/save-editor/panels/?.lua;./?.lua;'..package.path
love=require('tests.love_stub')
love.system={getOS=function()return 'Android'end}
love.mouse={getPosition=function()return 0,0 end}
local T=require('tests.harness').suite('Android editor pointer')
local App=require('App')
local Kit=require('Kit')
local captured
Kit.layout=function()Kit.scale=1 end
Kit.beginFrame=function(x,y,click)captured={x,y,click};error('POINTER_CAPTURE')end
for i=1,40 do local n=debug.getupvalue(App.draw,i);if n=='S'then debug.setupvalue(App.draw,i,{tab=1});break end end
for _,point in ipairs({{320,200},{70,580},{480,130}})do
 App.touchpressed(1,point[1],point[2]);App.touchreleased(1,point[1],point[2])
 local ok,why=pcall(App.draw)
 T.check(not ok and tostring(why):find('POINTER_CAPTURE'),'editor draw reached pointer dispatch')
 T.eq(captured[1],point[1],'tap x comes from touch, not stale mouse')
 T.eq(captured[2],point[2],'tap y comes from touch, not stale mouse')
 T.check(captured[3],'tap selects in Kit');T.check(Kit.virtualPointer,'map viewport uses click fallback')
end
App.resetTouch()
pcall(App.draw);T.eq(captured[1],0,'reset discards old touch position')
T.finish()
