-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Font=require('src.render.Font')
local Assets=require('src.render.Assets')
for _,key in ipairs{'useBattleExtra','battleExtraActive','setFrame','frameIndex'}do
  T.eq(type(Font[key]),'function','Gen1 public font control '..key)
end
if type(Font.setFrame)~='function'then T.finish('Gen2 font selection');return end
T.eq(Font.useBattleExtra(true),false,'safe before load')
T.eq(Font.battleExtraActive(),false)
local G=love.graphics
local oldImage,oldDraw,oldQuad=Assets.image,G.draw,G.newQuad
local dims={main={128,64},extra={128,16},battle={128,16},frames={48,64},bad={40,7}}
Assets.image=function(path)
  if path=='missing'then error('missing optional sheet')end
  return{path=path,getDimensions=function()return unpack(assert(dims[path]))end}
end
G.newQuad=function(x,y,w,h,iw,ih)return{x=x,y=y,w=w,h=h,iw=iw,ih=ih}end
local draws={}
G.draw=function(img,quad,x,y)draws[#draws+1]={image=img.path,q=quad,x=x,y=y}end
local function data()
  return{font={image='main',imageExtra='extra',imageBattleExtra='battle',imageFrames='frames',
    charmap={{seq='X',code=0x6e}},pages={battleExtra={image='battle',base=0x60,inactive=true,advance=5}}}}
end
local function sample(code,path,qx,qy)
  draws={};Font.drawCode(code,3,7)
  T.eq(#draws,1,'one glyph blit')
  if #draws>0 then
    T.eq(draws[1].image,path,'correct source sheet at '..code)
    if qx then T.eq(draws[1].q.x,qx)end
    if qy then T.eq(draws[1].q.y,qy)end
  end
end
Font.setFrame(3);Font.load(data())
T.eq(Font.frameIndex(),3,'pre-load selection retained')
T.eq(Font.battleExtraActive(),false)
T.eq(Font.width('X'),8)
sample(0x6e,'extra',112,0)
T.eq(Font.useBattleExtra(true),false)
T.eq(Font.battleExtraActive(),true)
T.eq(Font.width('X'),5,'switch changes real text measurement')
sample(0x6e,'battle',112,0)
T.eq(Font.useBattleExtra(true),true,'nested caller receives actual previous setting')
for frame=1,8 do
  Font.setFrame(frame)
  for tile=0,5 do sample(0x79+tile,'frames',tile*8,(frame-1)*8)end
end
sample(0x78,'battle',64,8)
sample(0x7f,'extra',120,8)
sample(0x80,'main',0,0)
T.eq(Font.useBattleExtra(false),true)
T.eq(Font.width('X'),8,'no stale width after sheet restore')
Font.setFrame(2.9);T.eq(Font.frameIndex(),2)
Font.invalidate();T.eq(Font.frameIndex(),2,'asset reload preserves frame selection')
T.eq(Font.battleExtraActive(),false,'asset reload resets temporary battle sheet')
sample(0x79,'frames',0,8)
Font.setFrame(99);sample(0x79,'extra',72,8)
Font.setFrame('invalid');T.eq(Font.frameIndex(),1)
local d=data();d.font.imageFrames='missing';d.font.imageBattleExtra='missing';d.font.pages=nil
Font.load(d);Font.useBattleExtra(true);sample(0x6e,'extra',112,0);sample(0x79,'extra',72,8)
d.font.imageFrames='bad';Font.load(d);sample(0x79,'extra',72,8)
-- The ordinary GBA named-face path retains priority and its own box-frame
-- option. No GSC sheet is admitted just by sharing its glyph numbers.
d=data();d.font.faces={small={image='main',base=0,advance=4}}
Font.load(d);Font.setFrame(4);Font.useBattleExtra(true)
T.check(Font.pushFace('small'));sample(0x79,'main');T.eq(Font.advanceOf(0x79),4)
Font.popFace();sample(0x79,'frames',0,24)
-- Authored inactive pages must never win the ordinary same-base lookup.
d=data();d.font.imageBattleExtra=nil;d.font.pages.battleExtra.inactive=true
Font.load(d);sample(0x6e,'extra',112,0)
-- The public content registry retains inactive pages through the actual
-- SDK merge. A replacement battle sheet must not leak into field text.
local Schemas=require('src.mods.Schemas')
T.check(Schemas.check(Schemas.REGISTRIES.font,'font','battleExtra',
  {image='battle',base=0x60,inactive=true},'register'))
T.check(not Schemas.check(Schemas.REGISTRIES.font,'font','battleExtra',
  {image='battle',base=0x60,inactive='yes'},'register'))
local target=T.fixtures.fresh();target.font=data().font;target.font.pages=nil
local json=require('src.link.Json')
local run=T.sdk.loadMods({'mods/battle_font_probe'},{data=target,fs=T.sdk.memfs({
  ['mods/battle_font_probe/manifest.json']=json.encode({id='battle_font_probe',name='Font sheet fixture',version='1.0.0',api=2,entry='main.lua'}),
  ['mods/battle_font_probe/main.lua']='local mod=...;mod.content.font:register("battleExtra",{image="battle",base=96,inactive=true,advance=5})',
})})
T.eq(#run.errors,0)
T.eq(target.font.pages.battleExtra.inactive,true)
Font.load(target);sample(0x6e,'extra',112,0)
Font.useBattleExtra(true);sample(0x6e,'battle',112,0)
T.eq(Font.width('X'),5)
run.release()
Font.setFrame(1);Font.useBattleExtra(false)
Assets.image,G.draw,G.newQuad=oldImage,oldDraw,oldQuad
T.finish('Gen1 GSC battle-sheet controls and eight independent textbox frames')
