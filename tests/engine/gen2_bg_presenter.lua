-- Actual native VM -> scene -> BG presenter. Older upstream uses its
-- native battler draw where the separate public portrait API is absent. Only graphics device calls
-- are recorded. These checks do not claim rendered GPU pixel acceptance.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local View=require('src.battle.Gen2AnimView')
local Bg=require('src.battle.gen2.BgEffects')
local Palette=require('src.render.Gen2PaletteDraw')
local Pictures=require('src.battle.Gen2BgPictures')
local Battle=require('src.battle.BattleState')
local Wide=require('src.battle.WideBattle')
local Pokemon=require('src.pokemon.Pokemon')
local g=love.graphics
local draw,newCanvas,rectangle=g.draw,g.newCanvas,g.rectangle
local calls,rects,allocations,released={},{},0,0
local previous=Version.get()
g.draw=function(image,quad,x,y,...)
  calls[#calls+1]={image=image,quad=quad,x=x,y=y,shader=g.getShader(),byte=Palette.bgp,
    viewport=type(quad)=='table'and quad.getViewport and {quad:getViewport()}or nil}
end
g.rectangle=function(...)rects[#rects+1]={...};return rectangle(...)end
g.newCanvas=function(...)
  allocations=allocations+1
  local canvas=newCanvas(...)
  canvas.release=function()released=released+1 end
  return canvas
end
local function native(edition,effect)
  Version.set(edition)
  local data=T.fixtures.fresh();data.constants.gen=2
  data.battle_anims={gen2=true,moveAnims={PROBE=1},scripts={
    [1]={entry=1,code={{op='bgeffect',args={effect or 'BATTLE_BG_EFFECT_BODY_SLAM',0,1,0}},
      {op='delay',frames=16},{op='ret'}}}},objects={},framesets={},oam={},gfx={}}
  require('src.render.Font').load(data)
  local save=require('src.core.SaveData').newGame()
  save.party={Pokemon.new(data,'FIXMON_A',30)}
  local s=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
  s.introSlide=0;s.showPlayerBack=false;s.showEnemyTrainer=false
  s.sendingOut=false;s.enemySendingOut=false;s.enemyHidden=false
  T.check(s:animForId('PROBE','player'),'actual native screen starts its existing animation player')
  for _=1,3 do s.animPlayer:update()end
  return s
end
for _,edition in ipairs({'gold','silver','crystal'})do
  local s=native(edition)
  for _,width in ipairs({160,304,160})do
    calls,rects={},{}
    local external={};g.setShader(external);g.setColor(.2,.3,.4,.5)
    local frame=s.anim.frames
    if width==304 then Wide.draw(s)else s:drawSceneBody()end
    local blits={}
    for _,row in ipairs(calls)do
      if row.image==s.animView.canvas then blits[#blits+1]=row end
    end
    T.eq(#blits,144,'native composition blits one actual background row per LCD row')
    T.eq(s.animView.canvas:getWidth(),width,'presenter uses the actual classic or wide surface')
    T.eq(blits[49].x,2,'native BODY_SLAM shifts the selected LCD band by signed two pixels')
    T.eq(blits[49].viewport[3],width-2,'shifted row clips to its own surface width')
    T.eq(blits[1].x,0,'row above the LCD window remains fixed')
    T.eq(blits[144].x,0,'text rows remain outside the BODY_SLAM window')
    for _,row in ipairs(blits)do T.eq(row.shader,nil,'already-coloured canvas rows bypass a caller shader')end
    T.eq(s.anim.frames,frame,'scene rendering never advances the native VM')
    T.eq(g.getShader(),external,'native composition restores caller shader')
    if width==304 then
      T.same({g.getColor()},{1,1,1,1},'outer native scene sets neutral tint for final overlays')
    else
      T.same({g.getColor()},{.2,.3,.4,.5},'native scene body restores caller tint')
    end
  end
  s.animView:release();s.animPlayer:release()
end
-- Paint the actual native battler under picture-size, hide, shade and lifted
-- states. These are graphics-device records, not fabricated gameplay saves.
for _,edition in ipairs({'gold','silver','crystal'})do
  local s=native(edition,'BATTLE_BG_EFFECT_ENTER_MON')
  local b=s.player
  local image=s:battlerPic(b);local w,h=image:getDimensions()
  calls={}
  s:drawBattlerPic(b,10,20,1)
  local row=calls[#calls]
  T.check(row~=nil,'native entry still paints its actual battler')
  T.eq(row.quad,10+math.floor(w*(1-1/3)/2),'entry picture compensation stays on integer native pixels')
  T.eq(row.x,20+math.floor(h*(1-1/3)),'entry keeps its bottom edge pinned to the native box')
  local bg=s.anim.bg;bg.picSize.player=nil
  local read=s.animPicState
  s.animPicState=function(self,side)
    local state=read(self,side);state.slide=3;return state
  end
  calls={};s:drawBattlerPic(b,10,20,1)
  T.eq(calls[#calls].quad,13,'public picture-state slide override reaches the actual native draw')
  s.animPicState=read
  bg.monShade.player=0xf8;bg.monShade.enemy=0xfc
  Palette.setBgp(0x1b);calls={}
  if s.drawPic then s:drawPic(b.mon,false)else s:drawBattlerPic(b,10,20,1)end
  T.check(#calls>0,'front capture of the actual player remains drawable')
  for _,paint in ipairs(calls)do
    T.eq(paint.byte,Pictures.paletteByte(0xf8,0x1b),'player front capture uses player shade and composes it once')
  end
  T.eq(Palette.bgp,0x1b,'picture capture restores the surrounding BG register')
  Palette.setBgp(nil)
  bg.hidden.player=true;calls={}
  s:drawBattlerPic(b,10,20,1)
  T.eq(#calls,0,'actual BG hide state suppresses the native battler draw')
  bg.hidden.player=false;bg.liftedRows.player={0,1}
  local scissor=g.setScissor;local clips={}
  g.setScissor=function(...)clips[#clips+1]={...};return scissor(...)end
  calls={};s:drawBattlerPic(b,10,20,1)
  T.same(clips[1],{0,0,160,48},'native BG paints only above the lifted player row')
  T.same(clips[2],{0,56,160,88},'native BG paints only below the lifted player row')
  T.eq(#calls,2,'lifted row is excluded from the actual BG picture pass')
  clips={};calls={};s.liftedPass=true;s:drawBattlerPic(b,10,20,1);s.liftedPass=nil
  T.same(clips[1],{0,48,160,8},'lifted OBJ pass selects the original player tile row')
  T.eq(#calls,1,'lifted row is restored exactly once outside BG distortion')
  g.setScissor=scissor
  local external={};g.setShader(external);Palette.setBgp(0x1b)
  local record=g.draw;g.draw=function()error('native portrait failure',0)end
  T.raises(function()
    if s.drawPic then s:drawPic(b.mon,false)else s:drawBattlerPic(b,10,20,1)end
  end,'native portrait failure','picture error remains visible')
  T.eq(Palette.bgp,0x1b,'failed portrait restores its BG palette owner')
  T.eq(s._gen2PicPaletteSide,nil,'failed portrait retires its per-side palette context')
  T.eq(g.getShader(),external,'failed portrait restores caller shader')
  g.draw=record;g.setShader();Palette.setBgp(nil);s.animPlayer:release()
end
T.check(released>=9,'changing surface and releasing native views retires owned canvases')
Version.set('crystal')
do
  local v=View.new()
  local pool=Bg.new({},{});pool.scx=2
  local screen={worldBackdrop=function()return true end}
  calls,rects={},{}
  local seen=0
  v:present({bg=pool},function()seen=seen+1 end,screen)
  T.eq(seen,1,'transparent scene still draws its actual supplied panel')
  T.eq(#rects,0,'exposed scanlines do not paint paper over a live world')
  local external={};local target={};g.setShader(external);g.setCanvas(target)
  g.setColor(.2,.4,.6,.8);Palette.setBgp(0x1b)
  T.raises(function()v:present({bg=pool},function()
    g.setShader();g.setColor(1,0,0,1);error('native panel failure',0)
  end)end,'native panel failure','actual panel failure remains visible')
  T.eq(g.getShader(),external,'failed BG bake restores caller shader')
  T.eq(g.getCanvas(),target,'failed BG bake restores caller canvas')
  T.same({g.getColor()},{.2,.4,.6,.8},'failed BG bake restores caller tint')
  T.eq(Palette.bgp,0x1b,'failed BG bake restores native palette register')
  g.setCanvas();g.setShader();Palette.setBgp(nil)
  local bg=Bg.new({},{});bg.lcdc='BGP';bg.lyStart=0;bg.lyEnd=4
  for i=0,3 do bg.lyBackup[i]=0xff end
  local bands=View.bgpBands(bg)
  T.eq(#bands,2,'LCD palette bands are grouped by their actual byte')
  T.eq(bands[1].byte,0xe4,'identity palette band is baked first')
  T.eq(bands[2].rows[1],1,'LCD applies the prior backup byte starting one row after LY start')
  T.eq(bands[2].rows[4],4,'LCD window includes its final scanline')
  v:release()
end
for _,monByte in ipairs({0xe4,0x00,0xff,0xf8,0xfc,0x1b})do
  for _,bgByte in ipairs({0xe4,0x00,0xff,0x1b})do
    local colors={{0},{1},{2},{3}}
    local expected=Palette.remap(Palette.remap(colors,monByte),bgByte)
    local actual=Palette.bgpShades(Pictures.paletteByte(monByte,bgByte))
    for i=1,4 do T.eq(actual[i],expected[i][1],'native mon and BG palette composition retains index ordering')end
  end
end
g.draw,g.newCanvas,g.rectangle=draw,newCanvas,rectangle
g.setShader();g.setCanvas();g.setColor(1,1,1,1);Palette.setBgp(nil);Version.set(previous)
T.finish('native GSC BG row presentation, wide composition, transparency and state restoration')
