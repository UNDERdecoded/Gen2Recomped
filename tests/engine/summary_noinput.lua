package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness');local Summary=require('src.ui.Gen3SummaryMenu')
local queried,animated,popped,chosen,selected=0,0,0,0,0
local input={wasPressed=function(_,key)queried=queried+1;return key=='right'end}
local game={data={constants={},pokemon={}},save={player={}},input=input,stack={pop=function()popped=popped+1 end}}
T.check(Summary.supportsNoInput==true,'native summary advertises the optional read-only contract')
for _,mode in ipairs{'pages','learn','move-select'}do
 local screen=Summary.new(game,{noInput=true})
 screen.picAnim={update=function(_,dt)T.check(dt==1/60,'picture keeps native dt');animated=animated+1 end}
 screen.monAnim={update=function(_,dt)T.check(dt==1/60,'pose keeps native dt');animated=animated+1 end}
 if mode=='learn'then screen.choose={onChoose=function()chosen=chosen+1 end};screen.chooseInput=function()chosen=chosen+1 end end
 if mode=='move-select'then screen.moveSelect=true;screen.moveSelectInput=function()selected=selected+1 end end
 for _=1,3 do screen:update(1/60)end
 T.check(screen.page==1,'read-only '..mode..' keeps its page')
end
T.check(animated==18,'both animation owners advance on every preview tick')
T.check(queried==0 and chosen==0 and selected==0 and popped==0,'preview reads no actions or callbacks')
for _,opts in ipairs{{},{noInput=false}}do
 local screen=Summary.new(game,opts);screen:update(1/60)
 T.check(screen.page==2,'ordinary summary still follows native right input')
end
local ordinary=Summary.new(game,{noInput=false});ordinary.choose={};ordinary.chooseInput=function()chosen=chosen+1 end;ordinary:update(1/60)
T.check(chosen==1,'ordinary move learning still delegates to its native choice owner')
ordinary.choose=nil;ordinary.moveSelect=true;ordinary.moveSelectInput=function()selected=selected+1 end;ordinary:update(1/60)
T.check(selected==1,'ordinary move selection still delegates to its native input owner')
T.finish('Native Gen3 summary optional noInput animation contract')
