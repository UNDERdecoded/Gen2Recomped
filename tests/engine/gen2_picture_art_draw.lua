package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local F=dofile('tests/gen2_picture_art/fixture.lua')
local Import=require('src.import.Gen2BattlePictureArt')
local Battle=require('src.battle.BattleState')
local V=require('src.core.GameVersion')
local P=require('src.render.PaletteFX')
local G=require('src.render.Gen2PaletteDraw')
local Assets=require('src.render.Assets')
local previous=V.get()
local oldImage,oldData,oldNew,oldDraw=love.image,Assets.imageData,love.graphics.newImage,love.graphics.draw
local graphics=love.graphics
local push,pop,setScissor,getScissor,intersect=graphics.push,graphics.pop,graphics.setScissor,
  graphics.getScissor,graphics.intersectScissor
local clip,clipStack=nil,{}
graphics.push=function(...)
  clipStack[#clipStack+1]=clip or false
  return push(...)
end
graphics.pop=function(...)
  clip=table.remove(clipStack)or nil
  return pop(...)
end
graphics.getScissor=function()if clip then return unpack(clip)end end
graphics.setScissor=function(x,y,w,h)
  clip=x and{x,y,w,h}or nil
  return setScissor(x,y,w,h)
end
graphics.intersectScissor=function(x,y,w,h)
  if clip then
    local right,bottom=math.min(x+w,clip[1]+clip[3]),math.min(y+h,clip[2]+clip[4])
    x,y=math.max(x,clip[1]),math.max(y,clip[2]);w,h=math.max(0,right-x),math.max(0,bottom-y)
  end
  graphics.setScissor(x,y,w,h)
end
love.image={newImageData=F.image}
local images,calls={},{}
Assets.imageData=function(path)
  if images[path]then return images[path]:clone()end
  local w=path:find('_back',1,true)and 48 or 56
  local out=F.image(w,w)
  out:mapPixel(function(x)return (3-x%4)/3,(3-x%4)/3,(3-x%4)/3,1 end)
  return out
end
love.graphics.newImage=function(data)
  if type(data)=='table'and data.clone then return data:clone()end
  if data=='assets/generated/sprites/monster.png'and images[data]then return images[data]:clone()end
  return oldNew(data)
end
love.graphics.draw=function(image,x,y,rotation,sx,sy,extra,...)
  if type(x)=='table'and x.getViewport then
    x,y,rotation,sx,sy=y,rotation,sx,sy,extra
  end
  calls[#calls+1]={image=image,x=x,y=y,rotation=rotation,sx=sx or 1,sy=sy or 1,
    clip={love.graphics.getScissor()},byte=G.bgp}
end
local A={{255,255,255},{211,41,67},{29,173,101},{3,7,13}}
local function make(edition,side,kind)
  V.set(edition);P.setDisplay('gbc',nil);G.setBgp(0xe4)
  local e;e,images=F.extractor(edition)
  local art=assert(Import.extract(e))
  images['assets/generated/sprites/monster.png']=images[art.substitute.sheet]
  local data=T.fixtures.fresh();data.constants.gen=2
  for _,def in pairs(data.pokemon)do def.palette='PIC_ART'end
  data.palettes={palettes={PIC_ART=A,GRAYMON=A,MEWMON=A},
    pokemon={FIXMON_A='PIC_ART',FIXMON_B='PIC_ART',FIXMON_C='PIC_ART'}}
  require('src.core.Data').publishGen2Palettes(data)
  data.moves.PROBE={id='PROBE',name='PROBE',power=0,type='NORMAL',pp=10}
  data.battle_anims={gen2=true,pictureArt=art,moveAnims={PROBE=1},scripts={
    [1]={entry=1,code={{op=kind=='substitute'and'raisesub'or'minimizeopp'},
      {op='delay',frames=100},{op='ret'}}},
  }}
  Battle.invalidate()
  require('src.render.Font').load(data)
  local save=require('src.core.SaveData').newGame()
  save.party={require('src.pokemon.Pokemon').new(data,'FIXMON_A',30)}
  local s=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
  s.queue,s.current,s.waitFrames={},nil,nil
  s.introSlide,s.sendingOut,s.enemySendingOut=0,false,false
  s.showPlayerBack,s.showEnemyTrainer=false,false
  s:animForMove('PROBE',side);s.animPlayer:update()
  return s,s[side],art
end
local function draw(s,b,back)
  calls={}
  if back==nil or not s.drawPic then s:drawPicsLayer(0,0,0,b.isPlayer and'player'or'enemy',true)
  else s:drawPic(b.mon,back)end
  return calls
end
local function pixel(image,x,y,color,label)
  T.same({image:getPixel(x,y)},{color[1]/255,color[2]/255,color[3]/255,1},label)
end
for _,edition in ipairs({'gold','silver','crystal'})do for _,side in ipairs({'player','enemy'})do
 for _,kind in ipairs({'substitute','minimize'})do
  local s,b,a=make(edition,side,kind)
  local original=b.sprite;local frame=s.anim.frames
  local rows=draw(s,b)
  T.eq(#rows,1,'native picture layer emits one full ROM box')
  local row=rows[1];local n=b.isPlayer and 48 or 56
  T.same({row.image:getDimensions()},{n,n},'real image keeps the six/seven-tile slot')
  T.eq(row.x,b.isPlayer and 16 or 96,'actual Gen2 picture box origin')
  T.eq(row.y,b.isPlayer and 48 or 0,'actual Gen2 picture box baseline')
  local px=kind=='substitute'and 17 or 26
  local py=b.isPlayer and 32 or 40
  pixel(row.image,px,py,A[2],'replacement uses saved Pokemon CGB palette')
  local _,_,_,alpha=row.image:getPixel(kind=='substitute'and 16 or 25,py)
  T.eq(alpha,0,'background shade remains transparent')
  T.eq(b.sprite,original,'replacement does not write native Pokemon image')
  T.eq(s.anim.frames,frame,'native drawing does not advance command VM')
  if s.pic then
   local direct=s:pic(b.mon,b.isPlayer)
   T.neq(direct,row.image,'public indexed Pokemon getter retains its original art')
  end
  if s.drawPic then for _,back in ipairs({false,true})do
    rows=draw(s,b,back);T.eq(#rows,1,'public capture emits actual ROM replacement')
    row=rows[1];local size=back and 48 or 56
    T.same({row.image:getDimensions()},{size,size},'capture selects requested front/back art')
    T.eq(row.x,back and 16 or 96,'public capture correct requested box x')
    T.eq(row.y,back and 48 or 0,'public capture correct requested box y')
    pixel(row.image,px,back and 32 or 40,A[2],'opposite-side capture retains actual owner palette')
  end end
  s.anim.bg.slide[side]=5;s.anim.bg.picSize[side]=b.isPlayer and 1 or 4
  rows=draw(s,b);row=rows[1]
  local ratio=b.isPlayer and 4/6 or 5/7
  T.eq(row.sx,ratio,'actual resize register scales whole native box')
  T.eq(row.x,(b.isPlayer and 16 or 96)+5+math.floor(n*(1-ratio)/2),'slide and resize share selected footprint')
  T.eq(row.y,(b.isPlayer and 48 or 0)+math.floor(n*(1-ratio)),'resize retains full picture baseline')
  if s.drawPic then
  s.anim.bg.picSize[side]=0
  rows=draw(s,b,false);row=rows[1]
  T.eq(row.sx,6/7,'front capture uses seven-tile resize denominator even for native player')
  T.eq(row.y,math.floor(56*(1-6/7)),'opposite front capture resize pins front baseline')
  end
  s.anim.bg.picSize[side]=nil;s.anim.bg.slide[side]=0
  s.anim.bg.monShade[side]=0xfc
  rows=draw(s,b)
  pixel(rows[1].image,px,py,A[4],'per-mon shade register reaches real replacement bake')
  T.eq(G.bgp,nil,'native draw restores caller identity-register representation')
  s.anim.bg.monShade[side]=nil;G.setBgp(0x1b)
  rows=draw(s,b)
  pixel(rows[1].image,px,py,A[3],'whole-background BGP reaches real replacement bake')
  T.eq(G.bgp,0x1b,'replacement restores caller BGP even when nonidentity')
  G.setBgp(0xe4)
  do
    local base
    if s.pic then local _,_,path=s:pic(b.mon,b.isPlayer);base=path
    else base=require('src.pokemon.Sprites').path(s.data,b.mon.species,b.isPlayer and 'back'or'front',{mon=b.mon,kind='battle'})end
    s.data.battle_sprite_scales={OWNED={path=base,scale=2}}
    row=draw(s,b)[1]
    T.eq(row.sx,2,'generated picture retains underlying per-image scale override')
    s.data.battle_sprite_scales=nil
  end
  if s.substituteDoll then
    local first,quad=s:substituteDoll(true)
    T.same({first:getDimensions()},{16,32},'public doll getter exposes genuine indexed ROM sheet')
    T.same({quad:getViewport()},{0,16,16,16},'back doll quad selects facing-up frame')
    local nextImage,nextQuad=s:substituteDoll(true)
    T.eq(nextImage,first,'public doll getter shares native cached image')
    T.eq(nextQuad,quad,'public doll getter reuses owned quad')
  end
  if s.drawPic then
  s.anim.bg.liftedRows[side]={4,1}
  rows=draw(s,b,false)
  T.eq(#rows,2,'normal front capture splits around actual lifted band')
  T.eq(rows[1].clip[2],0,'opposite capture lifted band is in front coordinates')
  T.eq(rows[1].clip[4],32,'front rows above lifted band remain visible')
  T.eq(rows[2].clip[2],40,'front rows below lifted band resume correctly')
  s.anim.bg.liftedRows[side]=nil
  end
  local realDraw=love.graphics.draw
  love.graphics.draw=function()error('picture device failure',0)end
  T.raises(function()draw(s,b,false)end,'picture device failure','device draw failure remains visible')
  T.eq(G.bgp,nil,'failed replacement paint restores caller identity register')
  T.eq(s._gen2PicPaletteSide,nil,'failed replacement paint releases palette owner')
  love.graphics.draw=realDraw
 end
end end
V.set(previous);love.image=oldImage;Assets.imageData=oldData
love.graphics.newImage,love.graphics.draw=oldNew,oldDraw
graphics.push,graphics.pop,graphics.setScissor,graphics.getScissor,graphics.intersectScissor=
  push,pop,setScissor,getScissor,intersect
T.finish('native GSC replacement pixels, actual drawing, capture geometry and palette lifetime')
