-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local G=love.graphics
local oldImage,oldDraw=Assets.image,G.draw
-- Atlas I/O alone is synthetic. Exercise actual splitting, encoding,
-- drawing, truncation, invalidation and native public overrides.
Assets.image=function(path)return{path=path,getDimensions=function()
  return 128,path=='extra'and 16 or 64
end}end
local calls={}
G.draw=function(image,quad,x,y)
  calls[#calls+1]={code=(image.path=='extra'and 96 or 128)+quad.y*2+quad.x/8,x=x,y=y}
end
local function data()
  local map={{seq=' ',code=127},{seq='é',code=234},{seq='.',code=232}}
  for i=0,25 do map[#map+1]={seq=string.char(65+i),code=128+i}end
  return{font={image='main',imageExtra='extra',charmap=map}}
end
T.eq(#Font.split('#MON'),7,'Gen1 text macro also segments safely before a font loads')
local d=data();Font.load(d)
local spans=Font.split('#MON')
T.eq(#spans,7,'POKé plus MON is seven glyphs')
for i,code in ipairs{143,142,138,234}do
  T.same(spans[i],{from=1,to=1,code=code},'expanded glyph retains the source command byte')
end
T.same(Font.encode('#MON'),{143,142,138,234,140,142,141})
T.eq(Font.glyphCount('#MON'),7)
T.eq(Font.width('#MON'),56)
calls={};T.eq(Font.draw('#MON',10,20),56)
T.eq(#calls,7,'actual renderer dispatches every expanded glyph')
T.eq(calls[4].code,234,'accent uses its owned font tile')
T.eq(calls[5]and calls[5].x,42,'following text starts after all expanded glyphs')
T.eq(Font.glyphCount('é#MON'),8,'UTF8 prefix and text command retain independent glyphs')
T.same(Font.split('é#MON')[2],{from=3,to=3,code=143})
T.eq(Font.glyphCount('#MON#MON'),14,'commands can repeat')
-- Complete commands stay intact. Partial commands are materialized only
-- up to the actual glyph budget; repeating # for every span overflows.
for _,case in ipairs{{8,'.'},{16,'P.'},{24,'PO.'},{32,'POK.'},{40,'#.'},{48,'#M.'},{56,'#MON'}}do
  local fit=Font.fit('#MON',case[1])
  T.eq(fit,case[2],'source command truncation at '..case[1]..' pixels')
  T.check(Font.width(fit)<=case[1],'truncated command stays within its actual budget')
end
T.eq(Font.fit('A#MON',48),'A#.','complete command is emitted once after a prefix')
T.eq(Font.fit('#MON#MON',80),'#MONPO.','later partial command does not duplicate earlier commands')
local TextBox=require('src.render.TextBox')
local prefix=string.rep('A',16)
local pages=TextBox.paginate(prefix..'#MON',18)
T.same(pages[1],{prefix,'#MON'},'native wrapping moves a source command intact')
for _,line in ipairs(pages[1])do T.check(Font.width(line)<=144,'wrapped native line fits')end
local narrow=TextBox.paginate('#MON',3)
T.same(narrow[1],{'#','MON'},'oversized source command still advances without losing text')
local game={data={},save={options={textSpeed=1}},input={isDown=function()return false end,wasPressed=function()return false end}}
local box=TextBox.new(game,'#MON')
T.eq(#box.codes,7,'native typewriter consumes expanded glyphs')
for frame,code in ipairs{143,142,138,234,140,142,141}do
  box:update(1/60)
  T.eq(box.charIndex,frame,'one native glyph per normal text tick')
  T.eq(box.shown[1][frame],code,'actual native typewriter receives the font glyph')
end
-- A mod's own # page wins, including when it shares the prefix with an
-- unrelated longer sequence. Never reinterpret an authored control prefix.
d.font.charmap[#d.font.charmap+1]={seq='#',code=239};Font.invalidate()
T.same(Font.encode('#MON'),{239,140,142,141},'reload retires cached macro expansion')
T.eq(Font.glyphCount('#MON'),4)
T.eq(Font.fit('#MON',24),'#M.')
d=data();d.font.charmap[#d.font.charmap+1]={seq='#TAG',code=240};Font.load(d)
T.same(Font.encode('#TAG'),{240})
T.same(Font.encode('#MON'),{127,140,142,141},'an authored hash prefix disables the fallback command')
-- Replacement text itself follows the current charmap, including ligatures
-- and relocated accents; no hard-coded ROM glyph ids belong to the macro.
d=data();d.font.charmap[2].code=235
d.font.charmap[#d.font.charmap+1]={seq='PO',code=240};Font.load(d)
T.same(Font.encode('#MON'),{240,138,235,140,142,141})
T.eq(Font.fit('#MON',16),'PO.','partial expansion retains authored ligature boundaries')
T.eq(Font.fit('#MON',32),'#.','complete replacement uses its actual glyph count')
-- The existing public override and missing-atlas paths keep their ownership.
local split=Font.split
Font.split=function(text)return{{from=1,to=#text,code=129}}end
T.same(Font.encode('#MON'),{129},'public splitter controls selection')
T.eq(Font.width('#MON'),8)
Font.split=split;Font.load({font={source='Gen2 scaffold'}})
T.same(Font.encode('#MON'),{35,77,79,78},'raster fallback retains its existing literal-string policy')
Assets.image,G.draw=oldImage,oldDraw
T.finish('Gen1 text macros, source spans, native truncation and authored charmap authority')
