-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local Unicode=require('src.translation.UnicodeFont')
local G=love.graphics
local oldImage,oldDraw,oldPrint,oldInfo,oldNewFont=Assets.image,G.draw,G.print,love.filesystem.getInfo,G.newFont
local draws,prints={},{}
-- Only atlas I/O is synthetic. Selection, layout, styles and dispatch use
-- the real Font, including its normal load/invalidate and face lifecycle.
Assets.image=function(path)
  local img={path=path}
  function img:getDimensions()return 128,path=='extra'and 16 or 64 end
  return img
end
G.draw=function(image,quad,x,y)
  draws[#draws+1]={image=image.path,x=x,y=y}
end
G.print=function(text,x,y)prints[#prints+1]={text=text,x=x,y=y}end
G.newFont=function(file,size)return oldNewFont(type(file)=='string'and size or file)end
local function data()
  return {font={image='main',imageExtra='extra',
    pages={main={image='main',base=128,widths={4,9,6,11}}},
    faces={small={image='small',base=128,advance=3}},
    charmap={{seq='A',code=128},{seq='B',code=129},{seq='é',code=130},
      {seq="'d",code=131},{seq=' ',code=127}}}}
end
local d=data();Font.load(d)
T.eq(type(Font.glyphCount),'function','Gen1 glyph-count API exists')
if type(Font.glyphCount)~='function'then T.finish('font text contract');return end
local label="ABé'd"
T.eq(Font.glyphCount(label),4,'UTF8 and authored ligatures each occupy one glyph')
T.same(Font.encode(label),{128,129,130,131})
local first=Font.encode(label);first[1]=999;first[5]=999
T.same(Font.encode(label),{128,129,130,131},'caller mutation cannot poison future typewriter glyphs')
local second=Font.encode(label)
T.check(first~=second,'encode callers own their arrays')
for _=1,3 do
  T.eq(Font.width(label),30,'current proportional metrics')
  draws={};T.eq(Font.draw(label,10,20),30,'draw and measure agree')
  T.eq(#draws,4);T.eq(draws[2].x,14);T.eq(draws[4].x,29)
end
Font.pushFace('small')
T.eq(Font.width(label),12,'warm text immediately uses native alternate-face metrics')
draws={};Font.draw(label,0,0)
T.eq(draws[1].image,'small','warm text paints the active face')
Font.popFace();T.eq(Font.width(label),30,'popping face restores original metrics')
-- Public methods are replaceable by mods. Never memoize a replaced
-- splitter's side effects or bypass a replaced encoder while drawing.
local split,encode=Font.split,Font.encode
local calls=0
Font.split=function(text)calls=calls+1;return{{from=1,to=#text,code=129}}end
T.eq(Font.width(label),9);T.eq(Font.width(label),9)
T.eq(calls,2,'replacement splitter runs for each request')
Font.split=split;T.eq(Font.width(label),30,'restored splitter uses original mapping')
Font.encode=function()return{129}end
T.eq(Font.width(label),9,'width honors public encode replacement')
draws={};T.eq(Font.draw(label,0,0),9,'draw honors public encode replacement')
T.eq(#draws,1);Font.encode=encode
-- A mod reloads the SAME data object after merging a new charmap/page.
local revision=Font.revision
d.font.charmap[3].code=129
Font.invalidate()
T.check(Font.revision>revision,'font invalidation publishes a new public revision')
T.same(Font.encode(label),{128,129,129,131},'reload retires old glyph selection')
T.eq(Font.width(label),33)
Font.load(data());T.eq(Font.width(label),30,'a new game/font cannot inherit old codes')
-- Activation/removal can happen independently of Font.load. A string that
-- used the space fallback must acquire (and then lose) its Unicode glyph.
love.filesystem.getInfo=function(path,...)
  if path:find('translations/fonts/',1,true)then return{type='file'}end
  return oldInfo(path,...)
end
Unicode.configure('original')
T.same(Font.encode('Ω'),{127})
T.check(Unicode.configure('de'),'actual Unicode font config')
local greek=Font.encode('Ω')
T.check(greek[1]<0,'warm text changes to translated Unicode glyph')
draws={};prints={};Font.draw('Ω',0,0)
T.eq(#draws,0);T.eq(prints[1]and prints[1].text,'Ω')
Unicode.configure('original')
T.same(Font.encode('Ω'),{127},'translation removal retires Unicode selection')
-- High-cardinality text (e.g. diagnostics) must leave the font usable and
-- must not prevent a later dataset from taking ownership of the same label.
for i=1,5000 do Font.width(tostring(i))end
Font.load(data());T.same(Font.encode(label),{128,129,130,131})
Font.load({})
T.same(Font.encode('Aé'),{65,63},'missing-font fallback keeps UTF8 whole')
prints={};T.eq(Font.draw('Aé',0,0),16,'fallback draw width counts glyphs, not bytes')
T.eq(prints[1]and prints[1].text,'Aé')
Assets.image,G.draw,G.print,love.filesystem.getInfo=oldImage,oldDraw,oldPrint,oldInfo
G.newFont=oldNewFont
T.finish('font glyph ownership, reloads, native faces, Unicode and public hooks')
