package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local F=require('src.render.Font')
local S=require('src.ui.Gen3SummaryMenu')
local draw,width=F.draw,F.width
local rows={}
F.width=function(s)return #tostring(s)*8 end
F.draw=function(s,x,y)rows[tostring(s)]={x=x,y=y,w=F.width(s)} end
local screen=setmetatable({hasArt=false,page=2,game={data={constants={}}},
 mon={hp=999,stats={hp=999,attack=888,defense=777,spatk=666,spdef=555,speed=444},exp=0},
 statColour=function()return{0,0,0}end,expToNext=function()return 1 end}, {__index=S})
local ok,err=pcall(function()screen:drawSkills()end)
F.draw,F.width=draw,width
assert(ok,err)
for _,pair in ipairs{{'HP','999/999'},{'ATTACK','888'},{'DEFENSE','777'},
 {'SP. ATK','666'},{'SP. DEF','555'},{'SPEED','444'}} do
 local label,value=assert(rows[pair[1]]),assert(rows[pair[2]])
 T.check(label.x+label.w<=value.x,pair[1]..' does not overlap its value')
 T.check(value.x+value.w<=224,pair[2]..' stays inside the native fallback panel')
 if label.x<132 then T.check(value.x+value.w<132,'left value ends before right labels') end
end
T.finish('Native summary fallback column bounds')
