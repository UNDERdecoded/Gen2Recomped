-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
local G=love.graphics
local oldImage,oldNewFont,oldDraw,oldPrint=Assets.image,G.newFont,G.draw,G.print
local loads,prints,draws={},{},{}
local widths={i=2,W=9,['é']=6,['漢']=11,['🙂']=12,['.']=3}
Assets.image=function(path)return{path=path,getDimensions=function()return 128,path=='extra'and 16 or 64 end}end
G.newFont=function(file,size,hint,dpi)
  if type(file)~='string'then return oldNewFont(file)end
  if file=='missing.ttf'then error('missing font')end
  local face={file=file,reads=0}
  function face:getWidth(ch)self.reads=self.reads+1;return widths[ch]or 5 end
  function face:getHeight()return size end
  function face:getBaseline()return 11 end
  function face:setFilter(a,b)self.filter={a,b}end
  loads[#loads+1]={file=file,size=size,hint=hint,dpi=dpi,face=face}
  return face
end
G.print=function(text,x,y)prints[#prints+1]={text=text,x=x,y=y,font=G.getFont(),color={G.getColor()}}end
G.draw=function(image,quad,x,y)draws[#draws+1]={image=image.path,x=x,y=y}end
local function data(spec)
  return{font={image='main',imageExtra='extra',ttf=spec,
    charmap={{seq='A',code=128},{seq='W',code=129},{seq='i',code=130},
      {seq='é',code=234},{seq='0',code=200},{seq=' ',code=127},
      {seq='<PK>',code=240},{seq="'d",code=241}}}}
end
local BASE=0x400000
local asset=io.open('assets/fonts/plainpixel/PlainPixel-Regular.ttf','rb')
T.check(asset~=nil,'default font is included in the engine source/package input')
if asset then T.eq(asset:read(4),'\0\1\0\0','bundled asset is a TrueType font');asset:close()end
T.eq(type(Font.ttfActive),'function','Gen1 TTF status API')
if type(Font.ttfActive)~='function'then T.finish('font TTF contract');return end
T.check(not Font.ttfActive(),'safe before load')
local d=data({});Font.load(d)
T.check(Font.ttfActive(),'default TTF opt-in')
local load=loads[#loads]
T.eq(load.file,'assets/fonts/plainpixel/PlainPixel-Regular.ttf')
T.eq(load.size,15,'Gen1 design size')
T.eq(load.hint,'mono');T.eq(load.dpi,1,'rasterization independent of window DPI')
T.same(load.face.filter,{'nearest','nearest'})
local text="Aié漢🙂<PK>'d"
T.same(Font.encode(text),{BASE+65,BASE+105,BASE+233,BASE+28450,BASE+128578,240,241},'Unicode text and authored ligatures share the real native pipeline')
local spans=Font.split(text)
T.same(spans[3],{from=3,to=4,code=BASE+233})
T.same(spans[4],{from=5,to=7,code=BASE+28450})
T.same(spans[5],{from=8,to=11,code=BASE+128578})
T.eq(Font.glyphCount(text),7)
T.eq(Font.width(text),52,'proportional TTF and tile advances')
T.eq(Font.fit('WiW',11),'.','narrow retained glyph cannot pay for a wider ellipsis')
T.eq(Font.fit('WiW',12),'W.','actual ellipsis advance is reserved')
for _,label in ipairs{'WiW','漢🙂W','#MON#MON'}do
  for budget=0,60 do
    T.check(Font.width(Font.fit(label,budget))<=budget,'truncation fits proportional budget')
  end
end
local before=load.face.reads
T.eq(Font.width(text),52);T.eq(load.face.reads,before,'glyph metric reuse')
local previous=oldNewFont(8);G.setFont(previous)
prints,draws={},{}
T.eq(Font.draw(text,10,20),52,'native text draw shares measurements')
T.eq(#prints,5);T.eq(#draws,2,'ligatures remain atlas glyphs')
T.eq(prints[3].text,'é');T.eq(prints[4].text,'漢');T.eq(prints[5].text,'🙂')
T.eq(prints[1].y,16,'baseline anchored to row seven')
T.eq(prints[2].x,15);T.eq(prints[3].x,17);T.eq(prints[4].x,23)
T.eq(prints[5].x,34);T.eq(draws[1].x,46)
T.eq(G.getFont(),previous,'TTF draw restores caller font')
prints,draws={},{};Font.drawCode(Font.BORDER.tl,0,0)
T.eq(#prints,0);T.eq(#draws,1,'direct border codes remain tiles')
Font.pushStyle({text={0.2,0.3,0.4,0.5},shadow={0,0,0,1}})
G.setColor(1,1,1,0.8);prints={};Font.draw('A',0,0);Font.popStyle()
T.eq(#prints,1,'styled TTF is not swallowed by atlas two-tone handling')
T.same(prints[1].color,{0.2,0.3,0.4,0.4},'native ink and alpha apply')
T.eq(G.getFont(),previous)
G.setColor(1,1,1,1)
-- Retaining individual tile characters accepts either UTF-8 text or rows.
d.font.ttf.tiles='0é';Font.invalidate()
T.same(Font.encode('A0é漢'),{BASE+65,200,234,BASE+28450})
d.font.ttf.tiles={'A','<PK>'};Font.invalidate()
T.same(Font.encode('A0é<PK>'),{128,BASE+48,BASE+233,240})
d.font.ttf={file='owned.ttf',size=30,spacing=-1,bold=true,yOffset=2};Font.invalidate()
T.eq(loads[#loads].file,'owned.ttf');T.eq(loads[#loads].size,30)
T.eq(Font.width('Ai'),7,'bold advance includes the duplicate pixel and signed spacing')
prints={};Font.draw('Ai',4,9)
T.eq(#prints,4);T.eq(prints[1].x,4);T.eq(prints[2].x,5)
T.eq(prints[3].x,9);T.eq(prints[4].x,10);T.eq(prints[1].y,11)
-- No stale selection or metrics when the same font record is disabled or
-- replaced. Native pages, translation fallback and public hooks still own
-- their normal paths when TTF is absent.
local revision=Font.revision;d.font.ttf=nil;Font.invalidate()
T.check(not Font.ttfActive());T.check(Font.revision>revision)
T.same(Font.encode('Aié'),{128,130,234});T.eq(Font.width('Aié'),24)
d.font.ttf={file='missing.ttf'};Font.invalidate()
T.check(not Font.ttfActive(),'failed TTF falls back to atlas')
T.same(Font.encode('Aié'),{128,130,234})
Font.load({font={ttf={}}});T.check(Font.ttfActive(),'TTF does not require atlas extraction')
T.eq(Font.width('A'),5)
Font.load({font={source='Gen2 scaffold',ttf={}}});T.check(Font.ttfActive(),'explicit font also works before scaffold atlas exists')
T.eq(Font.width('A'),5)
Font.load(data({}));T.eq(Font.glyphCount('#MON'),7,'source commands also use TTF')
local TextBox=require('src.render.TextBox')
local game={data={},save={options={textSpeed=1}},input={isDown=function()return false end,wasPressed=function()return false end}}
local box=TextBox.new(game,'Aié漢🙂')
for tick,code in ipairs{BASE+65,BASE+105,BASE+233,BASE+28450,BASE+128578}do
  box:update(1/60);T.eq(box.charIndex,tick);T.eq(box.shown[1][tick],code,'real native typewriter preserves Unicode code')
end
-- Exercise the public SDK registration and live merge, not a fabricated
-- target.font assignment alone. No external mod source is edited.
local Schemas=require('src.mods.Schemas')
local spec=Schemas.REGISTRIES.font
for _,bad in ipairs{{image='main'},{base=128},{foo=true},{file=12},{size=0},{bold='yes'},{tiles={3}}}do
  T.check(not Schemas.check(spec,'font','ttf',bad,'register'),'invalid TTF/page shape stays invalid')
end
T.check(not Schemas.check(spec,'font','page',{},'register'),'optional TTF branch cannot admit an empty page')
T.check(not Schemas.check(spec,'font','ttf',{seq='A',code=128},'register'),'charmap row cannot masquerade as TTF')
for _,edition in ipairs{'red','crystal','emerald'}do
  require('src.core.GameVersion').set(edition)
  local target=T.fixtures.fresh()
  local json=require('src.link.Json')
  local run=T.sdk.loadMods({'mods/font_probe'},{data=target,fs=T.sdk.memfs({
    ['mods/font_probe/manifest.json']=json.encode({id='font_probe',name='Font contract fixture',version='1.0.0',api=2,entry='main.lua'}),
    ['mods/font_probe/main.lua']='local mod=...;mod.content.font:register("ttf",{spacing=1,tiles="0"})',
  })})
  T.eq(#run.errors,0,edition..': actual SDK accepts Gen1 registration')
  T.same(target.font.ttf,{spacing=1,tiles='0'})
  T.eq(target.font.pages.ttf,nil,'TTF is not an atlas page')
  Font.load(target);T.check(Font.ttfActive(),'merged entry reaches actual renderer')
  run.release()
end
local Registry=require('src.mods.Registry')
local target=data({}).font
spec.write(target,Registry.new('font',spec))
T.eq(target.ttf,nil,'empty registry removes previous mod-owned TTF')
Font.load({font=target});T.check(not Font.ttfActive())
Assets.image,G.newFont,G.draw,G.print=oldImage,oldNewFont,oldDraw,oldPrint
T.finish('Gen1 opt-in TTF, native text pipeline, SDK registration and lifecycle')
