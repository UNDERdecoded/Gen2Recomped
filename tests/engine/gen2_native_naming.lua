-- Original contributions (c) 2026 Roxas2712; offered to UNDERdecoded under
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local edition=Version.get()
local UI=require('src.ui.Gen2NamingScreen');local Font=require('src.render.Font')
local Screens=require('src.ui.Screens');local Json=require('src.link.Json')
local data=T.fixtures.fresh()
-- Synthetic, relocated glyphs. Bracket aliases follow the font, never a
-- fixed retail tile ordinal, and a font's explicit alias has precedence.
data.font.charmap[#data.font.charmap+1]={seq='PK',code=0xd1}
data.font.charmap[#data.font.charmap+1]={seq='MN',code=0xd2}
Font.load(data)
T.eq(#Font.split('<PK><MN>'),2,'legacy ligatures are two native glyphs')
T.eq(Font.split('<PK>')[1].code,0xd1,'PK follows its actual active font')
T.eq(Font.split('<MN>')[1].code,0xd2,'MN follows its actual active font')
T.eq(Font.width('<PK>'),Font.width('PK'),'measurement uses the same ligature as drawing')
data.font.charmap[#data.font.charmap+1]={seq='<PK>',code=0xd3}
Font.load(data);T.eq(Font.split('<PK>')[1].code,0xd3,'authored bracket glyph retains precedence')
local preview=UI.new(nil,{initial='AB'})
T.eq(preview.text,'AB','constructing a public preview does not require a live game')
T.eq(preview:characterAt(0,0),'A');preview:update();T.eq(preview.clock,1)
-- Mail entry must keep both sixteen-glyph rows above its keyboard.
local entry=UI.new({data=data},{type='box',maxLength=32})
entry.mailMode=true;entry.text=string.rep('X',32)
local drawn={};local draw=Font.draw
Font.draw=function(text,x,y)drawn[#drawn+1]={text,x,y}end
entry:drawEntry(5,4);Font.draw=draw
T.eq(#drawn,32);T.eq(drawn[1][2],8);T.eq(drawn[16][2],128)
T.eq(drawn[17][2],8);T.eq(drawn[17][3],36)
for _,p in ipairs(drawn)do T.check(p[2]>=8 and p[2]+8<=152 and p[3]+8<=entry:keyboardTop()*8,'native mail glyph fits above keyboard')end
local function game()
 local g={data=data,save={player={gender='girl'}}}
 g.stack=setmetatable({},{__index=require('src.core.StateStack')});g.stack:init()
 return g
end
local function tap(g,s,key)
 g.input={wasPressed=function(_,k)return key==k end};s:update()
end
for _,v in ipairs({'gold','silver','crystal'})do
 Version.set(v)
 for _,name in ipairs({'player','rival','mom','box','nickname'})do
  local g=game();local parent={};g.stack:push(parent);local called=0
  local s;s=UI.new(g,{type=name,initial='A<PK>é',onDone=function(text)
   called=called+1;T.eq(g.stack:top(),s,'public completion leaves the native owner to its caller');g.stack:pop()
   T.eq(text,'A<PK>',v..' glyph deletion retains complete ligature')
  end});g.stack:push(s)
  T.eq(s.row,0,'Gen2 cursor starts at zero-based first row');T.eq(s.col,0)
  T.eq(s.maxLength,UI.TYPES[name].maxLength,name..' native field limit')
  T.eq(#s.glyphs,3,'entry counts font glyphs, not encoded bytes')
  tap(g,s,'b');T.eq(s.text,'A<PK>')
  tap(g,s,'start');T.eq(s:cursorCharacter(),'END');T.eq(called,0,'START selects END without completing')
  tap(g,s,'a');T.eq(called,1);T.eq(g.stack:top(),parent)
 end
 local g=game();local s=UI.new(g,{})
 T.eq(#s:rows(),4,'ordinary Gen2 board has four letter rows')
 T.eq(s:characterAt(8,2),' ','a real trailing blank remains an input cell')
 s.col=8;s.row=2;tap(g,s,'a');T.eq(s.text,' ')
 tap(g,s,'select');T.eq(s.lower,true);T.eq(s:characterAt(7,3),'<PK>')
 s.row=3;s.col=7;tap(g,s,'a');T.eq(s.text,' <PK>')
 tap(g,s,'start');tap(g,s,'left');T.eq(s:cursorCharacter(),'DEL');tap(g,s,'a');T.eq(s.text,' ')
 tap(g,s,'left');T.eq(s:cursorCharacter(),'CASE');tap(g,s,'a');T.eq(s.lower,false)
 tap(g,s,'left');T.eq(s:cursorCharacter(),'END','bottom targets wrap as three fat cells')
 s.row=0;s.col=8;tap(g,s,'up');T.eq(s:cursorCharacter(),'END');tap(g,s,'down');T.eq(s.row,0)
 s=UI.new(g,{type='box'});T.eq(#s:rows(),5,'box names have an extra character row')
 s.text='12345678';tap(g,s,'b');T.eq(s.text,'1234567');tap(g,s,'select');T.eq(s:characterAt(8,4),'9')
 s=UI.new(g,{maxLength=2});s:addCharacter('é<PK>');T.eq(s.text,'é<PK>');T.eq(s:addCharacter('X'),false)
 s.row=0;s.col=0;tap(g,s,'a');T.eq(s:cursorCharacter(),'END','filling the name selects END but does not accept')
 -- Actual ordinary constructor uses this same native screen while retaining
 -- its distinct pop-before-callback contract, including empty nickname entry.
 local popped=0;local parent={};g.stack:push(parent)
 s=require('src.ui.NamingScreen').new(g,{kind='mon',maxLen=10,onDone=function(text)
  popped=popped+1;T.eq(text,'');T.eq(g.stack:top(),parent)
 end});g.stack:push(s)
 T.eq(getmetatable(s),UI,'native admission is not a secondary keyboard simulation')
 tap(g,s,'start');T.eq(popped,0);tap(g,s,'a');T.eq(popped,1)
 tap(g,s,'a');T.eq(popped,1,'completed native admission cannot run again')
 -- Presets draw the original parent, without a ghost keyboard behind them.
 local keyboard=0;local old=UI.drawPanel;UI.drawPanel=function()keyboard=keyboard+1 end
 local parent={};g.stack:init();g.stack:push(parent)
 s=require('src.ui.NamingScreen').new(g,{presets={'FIXNAME'},onDone=function(n)T.eq(n,'A')end})
 g.stack:push(s);s:draw();s:drawWidescreen(800,720)
 T.eq(s.choosing,true);T.eq(s.isOpaque,false);T.eq(keyboard,0,'no keyboard is drawn under name presets')
 local menu=g.stack:top();tap(g,menu,'a');T.eq(g.stack:top(),s);T.eq(s.choosing,nil);T.eq(s.isOpaque,true)
 s:draw();T.eq(keyboard,1,'NEW NAME activates the native keyboard')
 tap(g,s,'a');tap(g,s,'start');tap(g,s,'a');T.eq(g.stack:top(),parent)
 UI.drawPanel=old
 -- Actual Oak name-step dispatch retains its semantic role even when a
 -- mod changes the player field length to the usual box-name length.
 for _,who in ipairs({'player','rival'})do
  local g=game();local parent={};g.stack:push(parent);local advanced=0
  local speech={game=g,nameLen=8,recordAnswer=function()end,advance=function()advanced=advanced+1 end}
  require('src.ui.OakSpeech').runStep(speech,{kind='name',who=who,presets={}})
  local own=g.stack:top();T.eq(getmetatable(own),UI)
  T.eq(own.kind,UI.TYPES[who],'native Oak passes the actual naming role')
  T.eq(own.isBox,false,'eight-letter player/rival fields do not become box keyboards')
  tap(g,own,'a');tap(g,own,'start');tap(g,own,'a')
  T.eq(g.save.player[who=='rival'and'rival'or'name'],'A')
  T.eq(advanced,1);T.eq(g.stack:top(),parent)
 end
 for _,api in ipairs({{1,'native'},{2,'native'}})do
  local files={['mods/naming/manifest.json']=Json.encode({id='naming',name='Native name client',version='1.0.0',api=api[1],content_format=api[2],entry='main.lua',affects_link=false}),
   ['mods/naming/main.lua']=[[
    local mod=...;local Screen=require('src.ui.gen2.NamingScreen')
    mod.exports.make=function(game)return Screen.new(game,{type='box',initial='AB'})end
   ]]}
  local loaded=T.sdk.loadMods({'mods/naming'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
  T.eq(#loaded.errors,0,'actual loader admits native naming client')
  local s=loaded.loader.exports.naming.make(game())
  T.eq(getmetatable(s),UI,'legacy class spelling targets the native Gen2 owner')
  T.eq(s.text,'AB');T.eq(s:bottomRow(),5)
  require('src.mods.Loader').teardown();loaded.release()
 end
end
-- Imported cursor sheets are actually used and their quads are retained.
local cursor=UI.new(nil,{})
cursor.tiles.cursor={getDimensions=function()return 8,16 end}
local newQuad,draw=love.graphics.newQuad,love.graphics.draw
local quads,draws=0,0
love.graphics.newQuad=function(...)quads=quads+1;return newQuad(...)end
love.graphics.draw=function(image,...)T.eq(image,cursor.tiles.cursor);draws=draws+1 end
cursor:drawCursorBox(2,8,1);cursor:drawCursorBox(2,8,1);cursor:drawCursorBox(8,16,5)
T.eq(quads,2,'cursor quads are retained across frames and target sizes')
T.eq(draws,18,'letter corners and wide-target edges use the imported sheet')
love.graphics.newQuad,love.graphics.draw=newQuad,draw
-- A real external presenter can replace both class draw methods. Preset
-- ownership must suppress those too, without discarding the presenter once
-- NEW NAME makes the native keyboard active.
local oldDraw,oldWide=UI.draw,UI.drawWidescreen
local presented=0
UI.draw=function()presented=presented+1 end
UI.drawWidescreen=function()presented=presented+1 end
local g=game();local parent={};g.stack:push(parent)
local s=require('src.ui.NamingScreen').new(g,{presets={'ONE'}});g.stack:push(s)
s:draw();s:drawWidescreen(800,720);T.eq(presented,0,'external keyboard presenter is suppressed below presets')
tap(g,g.stack:top(),'a');s:draw();s:drawWidescreen(800,720)
T.eq(presented,2,'the original external presenter resumes for actual name entry')
T.eq(rawget(s,'draw'),nil);T.eq(rawget(s,'drawWidescreen'),nil)
UI.draw,UI.drawWidescreen=oldDraw,oldWide
Version.set('red')
T.eq(getmetatable(require('src.ui.NamingScreen').new(game(),{})),require('src.ui.NamingScreen'),'Gen1 retains its own keyboard')
Version.set(edition);Screens.invalidate()
T.finish('native Gen2 keyboard input, glyphs, original admission and loaded class owner')
