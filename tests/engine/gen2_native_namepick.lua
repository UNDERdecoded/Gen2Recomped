-- Original integration contributions (c) 2026 Roxas2712; offered to UNDERdecoded under
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local edition=Version.get()
local Pick=require('src.ui.Gen2NamePick');local Naming=require('src.ui.Gen2NamingScreen')
local Stack=require('src.core.StateStack');local Screens=require('src.ui.Screens')
local data=T.fixtures.fresh()
local function game()
 local g={data=data,save={player={gender='girl'}},stack=setmetatable({},{__index=Stack})}
 g.stack:init();return g
end
local function tap(g,s,key)g.input={wasPressed=function(_,k)return key==k end};s:update()end
local function settle(g,s)
 for _=1,8 do tap(g,s,'a')end
 T.eq(s.picX,13);T.eq(s.slide,nil);T.eq(g.stack:top(),s,'slide blocks keyboard/menu input')
end
for _,edition in ipairs({'gold','silver','crystal'})do
 Version.set(edition)
 local g=game();local parent={};g.stack:push(parent);local done=0
 local s;s=Pick.new(g,{presets={'ONE','TWO'},onDone=function(name)
  done=done+1;T.eq(name,'TWO');T.eq(g.stack:top(),s,'public picker leaves dismissal to its caller')
 end});g.stack:push(s)
 T.eq(s.picX,6);T.eq(s.cursor,1);settle(g,s)
 tap(g,s,'b');T.eq(g.stack:top(),s);T.eq(done,0,'B cannot cancel the native name choice')
 tap(g,s,'up');T.eq(s.cursor,3);tap(g,s,'a');T.eq(s.slide,'out');T.eq(done,0)
 for x=12,6,-1 do tap(g,s,'a');T.eq(s.picX,x);T.eq(done,0,'preset waits for the return walk')end
 tap(g,s,'a');T.eq(done,1);tap(g,s,'a');T.eq(done,1,'selection is once-only')
 g=game();g.stack:push(parent);local received
 s=Pick.new(g,{presets={'FALLBACK'},maxLength=8,onDone=function(name)received=name end});g.stack:push(s);settle(g,s)
 tap(g,s,'start');local keyboard=g.stack:top()
 T.eq(getmetatable(keyboard),Naming,'NEW NAME opens the real native Gen2 keyboard')
 T.eq(keyboard.kind,Naming.TYPES.player);T.eq(keyboard.maxLength,8);T.eq(keyboard.isBox,false)
 tap(g,keyboard,'a');tap(g,keyboard,'start');T.eq(received,nil);tap(g,keyboard,'a')
 T.eq(received,'A');T.eq(g.stack:top(),s)
 -- Empty input chooses the import-provided default, never an unrelated name.
 g=game();s=Pick.new(g,{presets={'LOCAL DEFAULT'},onDone=function(name)received=name end})
 g.stack:push(s);settle(g,s);tap(g,s,'a');keyboard=g.stack:top();received=nil
 tap(g,keyboard,'start');tap(g,keyboard,'a');T.eq(received,'LOCAL DEFAULT')
 -- Real Oak dispatch owns the picker and its continuation, including a
 -- changed field length, with no second naming/preset simulation.
 g=game();g.stack:push(parent);local advanced=0
 local speech=setmetatable({game=g,nameLen=8,recordAnswer=function()end,advance=function()advanced=advanced+1 end},{__index=require('src.ui.OakSpeech')})
 speech:runStep({kind='name',who='player',presets={'LOCAL DEFAULT'}})
 s=g.stack:top();T.eq(getmetatable(s),Pick);settle(g,s)
 tap(g,s,'a');keyboard=g.stack:top();tap(g,keyboard,'a');tap(g,keyboard,'start');tap(g,keyboard,'a')
 T.eq(g.stack:top(),parent);T.eq(g.save.player.name,'A');T.eq(advanced,1)
 T.eq(require('src.core.ModCompat').ALIASES['src.ui.gen2.NamePick'],'src.ui.Gen2NamePick')
end
Version.set('crystal')
T.eq(Pick.presetsFor('girl')[1],'KRIS');T.eq(Pick.presetsFor('female')[1],'KRIS')
T.eq(Pick.presetsFor('boy',{field={playerForms={boy={names={'CUSTOM'}}}}})[1],'CUSTOM')
T.eq(Pick.presetsFor('boy',{field={boot={namePresets={player={'BOOT'}}}}})[1],'BOOT')
local g=game();local completed=0
local stale=Pick.new(g,{presets={'X'},onDone=function()completed=completed+1 end})
g.stack:push(stale);settle(g,stale);tap(g,stale,'a')
local child=g.stack:pop();g.stack:pop();g.stack:push({});g.stack:push(child)
tap(g,child,'start');tap(g,child,'a')
T.eq(completed,0,'a keyboard whose original caller was removed cannot commit to it')
-- Rendering uses the actual supplied portrait at native tile positions and
-- retains true-colour ownership. No private picture data is needed.
local s=Pick.new(nil,{presets={'X'}});local draws={};local draw=love.graphics.draw
s.pic={getDimensions=function()return 56,40 end}
love.graphics.draw=function(image,x,y)draws[#draws+1]={image,x,y}end
s:drawPic();T.eq(draws[1][1],s.pic);T.eq(draws[1][2],48);T.eq(draws[1][3],48)
s.picX=13;s:drawPic();T.eq(draws[2][2],104)
love.graphics.draw=draw
Version.set(edition);Screens.invalidate()
T.finish('native Gen2 name choice, blocking portrait walk and original Oak continuation')
