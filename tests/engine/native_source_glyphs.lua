-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Font=require('src.render.Font')
local Source=require('src.ui.game3.frlg_font')
local V=require('src.core.GameVersion')
local Assets=require('src.render.Assets');local savedImage=Assets.image
local image={getDimensions=function()return 128,128 end}
Assets.image=function()return image end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 V.set(edition)
 local data={font={pages={main={image='OWNED_FONT',base=0,glyphWidth=8,glyphHeight=8,advance=9}},
  faces={small={image='OWNED_SMALL',base=0,glyphWidth=8,glyphHeight=8,advance=5}},
  charmap={{seq='A',code=13},{seq='é',code=42},{seq=' ',code=0},{seq='<PK>',code=57}}}}
 Font.load(data)
 T.eq(Source.glyphId('A'),13);T.eq(Source.glyphId('é'),42);T.eq(Source.glyphId('<PK>'),57)
 T.eq(Source.glyphId(''),0);T.eq(Source.glyphId(nil),0)
 T.eq(Source.advance(13),9);T.eq(Source.advance(13,{small=true}),5)
 T.eq(Font.advanceOf(13),9,'source measurement restores the current native face')
 local painted;local draw=Font.drawCode
 Font.drawCode=function(code,x,y)painted={code,x,y,Font.advanceOf(code)}end
 local shader={name='native previous'};love.graphics.setShader(shader);love.graphics.setColor(.2,.3,.4,.5)
 T.eq(Source.drawGlyph(42,17,23,{small=true}),5)
 T.eq(painted[1],42);T.eq(painted[2],17);T.eq(painted[3],23);T.eq(painted[4],5)
 T.eq(Font.advanceOf(42),9);T.eq(love.graphics.getShader(),shader)
 local r,g,b,a=love.graphics.getColor();T.eq(r,.2);T.eq(g,.3);T.eq(b,.4);T.eq(a,.5)
 Font.drawCode=function()error('glyph painter failure')end
 T.raises(function()Source.drawGlyph(13,0,0,{small=true})end,'glyph painter failure')
 T.eq(Font.advanceOf(13),9);T.eq(love.graphics.getShader(),shader,'errors restore native shader')
 Font.drawCode=draw
 data.font.charmap[1].code=71;Font.load(data);T.eq(Source.glyphId('A'),71,'no stale glyph cache after native reload')
end
Assets.image=savedImage
T.finish('native source glyph IDs, proportional faces and draw ownership')
