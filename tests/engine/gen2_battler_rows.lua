-- Actual native command -> copied picture cells -> emitted OBJ draw calls.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local F=dofile('tests/gen2_picture_art/fixture.lua')
local V=require('src.core.GameVersion')
local Battle=require('src.battle.BattleState')
local Assets=require('src.render.Assets')
local P=require('src.render.Gen2PaletteDraw')
local Rows=require('src.battle.Gen2BattlerRows')
local oldVersion=V.get()
local g=love.graphics
local oldData,oldImage,oldNew,oldDraw,oldShader=Assets.imageData,love.image,g.newImage,g.draw,g.newShader
local sources,draws,decodes,uploads={},{},0,0
love.image={newImageData=F.image}
local function picture(w,h,seed)
  local image=F.image(w,h)
  image:mapPixel(function(x,y)
    local shade=(math.floor(x/8)*3+math.floor(y/8)*2+x+2*y+seed)%4
    return (3-shade)/3,(3-shade)/3,(3-shade)/3,1
  end)
  return image
end
Assets.imageData=function(path)
  decodes=decodes+1
  if not sources[path]then sources[path]=picture(path:find('/back/',1,true)and 48 or 40,
    path:find('/back/',1,true)and 48 or 40,0)end
  return sources[path]:clone()
end
g.newImage=function(data)
  if type(data)=='table'and data.clone then
    uploads=uploads+1
    local image=data:clone()
    function image:release()self.released=true end
    return image
  end
  return oldNew(data)
end
g.newShader=function()return {values={},send=function(self,k,v)self.values[k]=v end}end
g.draw=function(image,quad,x,y,angle,sx,sy)
  local shader=g.getShader();local colors={}
  if shader and shader.values then for k,v in pairs(shader.values)do colors[k]=v end end
  draws[#draws+1]={image=image,quad=quad,x=x,y=y,sx=sx,sy=sy,colors=colors}
end
local function make(edition,rows,attacker)
  V.set(edition);Assets.invalidate();Battle.invalidate();sources={}
  local data=T.fixtures.fresh();data.constants.gen=2
  for name,def in pairs(data.pokemon)do
    def.spriteFront='qa/front/'..name..'.png'
    def.spriteBack='qa/back/'..name..'.png'
  end
  data.constants.battleAnimGfxOrder={'BATTLE_ANIM_GFX_PLAYERHEAD','BATTLE_ANIM_GFX_ENEMYFEET'}
  data.battle_anims={gen2=true,moveAnims={PROBE=1},scripts={[1]={entry=1,code={
    {op=rows==2 and 'battlergfx_1row'or'battlergfx_2row'},
    {op='obj',args={0,64,80,0}},{op='obj',args={1,88,88,0}},
    {op='delay',frames=100},{op='ret'}}}},
    functions={[0]='MoveFromUserToTarget'},objects={},framesets={},oam={}}
  for id=0,1 do
    data.battle_anims.objects[id]={oamFlags=1,fixY=255,fn=0,frameset=id,palette=id,gfx=id}
    data.battle_anims.framesets[id]={frames={{oam=id,duration=1}},loop='restart'}
    local sprites={}
    for tile=0,(id==0 and 7 or 6)*rows-1 do
      sprites[#sprites+1]={x=0,y=0,tile=tile,attr=(tile%4)*32}
    end
    data.battle_anims.oam[id]={tile=0,sprites=sprites}
  end
  require('src.render.Font').load(data)
  local save=require('src.core.SaveData').newGame()
  save.party={require('src.pokemon.Pokemon').new(data,'FIXMON_A',30)}
  local s=Battle.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',23)
  s.queue,s.current,s.waitFrames={},nil,nil
  s:animForMove('PROBE',attacker)
  local p=s.animPlayer
  T.eq(p.screen,s,'existing native player owns the real picture source')
  p:update()
  return s,p
end
for _,edition in ipairs{'gold','silver','crystal'}do
 for _,rows in ipairs{1,2}do for _,attacker in ipairs{'player','enemy'}do
  local s,p=make(edition,rows,attacker)
  local runner=p.runtime
  T.eq(#runner.loaded,2)
  for _,entry in ipairs(runner.loaded)do
    local snapshot=p.view.battlerRows[entry]
    T.check(snapshot~=nil,'real battlergfx command uploads its native battler rows')
    local back=entry.battler=='player'
    local n=back and 48 or 56
    T.same({snapshot.image:getDimensions()},{n,rows*8})
    local raw=sources[s:gen2ObjectPictureSource(entry.battler).path]
    for y=0,rows*8-1 do for x=0,n-1 do
      local px,py=x,back and y or 56-rows*8+y
      if not back then px=px-8;py=py-(56-raw.h)end
      local expected={0,0,0,0}
      if px>=0 and py>=0 and px<raw.w and py<raw.h then
        expected={raw:getPixel(px,py)}
        if expected[1]>.83 then expected[4]=0 end
      end
      T.same({snapshot.image:getPixel(x,y)},expected,'OBJ pixels follow native BG-to-OBJ copy and colour-zero key')
    end end
  end
  local before,frame,random=decodes,p.frames,s.rng
  local images=uploads
  draws={}
  local outerColors={{251,239,227},{193,151,109},{83,61,47},{17,11,5}}
  P.useRaw(outerColors);local outside=g.getShader();P.setBgp(0)
  p:draw();local once=draws
  T.eq(#once,13*rows,'both real picture strips reach the native OAM renderer')
  T.eq(g.getShader(),outside,'caller shader restored')
  for i=1,4 do
    T.same(outside.values['pal'..(i-1)],{outerColors[i][1]/255,outerColors[i][2]/255,outerColors[i][3]/255},
      'caller palette uniforms survive reuse of the same indexed shader')
  end
  local oam=runner:oam()
  for index,draw in ipairs(once)do
    local obj=oam[index]
    local entry=runner.loaded[index<=7*rows and 1 or 2]
    local localTile=obj.tile-entry.tile
    T.same({draw.quad:getViewport()},{math.floor(localTile/rows)*8,(localTile%rows)*8,8,8},
      'copied strip is addressed column-major, not as a regular OBJ atlas')
    local sx=math.floor(obj.attr/32)%2==1 and -1 or 1
    local sy=math.floor(obj.attr/64)%2==1 and -1 or 1
    T.same({draw.x,draw.y,draw.sx,draw.sy},{obj.x-8+(sx<0 and 8 or 0),obj.y-16+(sy<0 and 8 or 0),sx,sy},
      'actual native OAM retains both flips and attacker mirroring')
    local colors=p.view:objPalette(obj.palette,p.battle)
    local expected=P.resolve(colors)
    for i=1,4 do T.same(draw.colors['pal'..(i-1)],{expected[i][1]/255,expected[i][2]/255,expected[i][3]/255},
      'OBJ colours retain the real battler palette and ignore BGP')end
  end
  -- Mutating the picture provider cannot repaint already copied OBJ VRAM.
  local source=s:gen2ObjectPictureSource('enemy')
  sources[source.path]=picture(40,40,1)
  for _=1,4 do p:draw()end
  T.eq(decodes,before,'drawing does no image decode or GPU readback')
  T.eq(uploads,images,'drawing does not upload images again')
  T.eq(p.frames,frame,'drawing never runs the VM')
  T.eq(s.rng,random)
  local first=runner.loaded[1];local snapshot=p.view.battlerRows[first]
  p:start('PROBE',attacker=='player');p:update()
  T.check(p.runtime~=runner,'restart still creates the existing distinct runner')
  T.eq(p.view.battlerRows[first],snapshot,'retained old runner keeps its own copied art')
  local retained=runner:oam();retained.runner=runner;draws={};p:drawSprites(retained)
  T.eq(#draws,13*rows,'retained real OAM draws without rebinding to the current runner')
  T.eq(draws[1].image,snapshot.image)
  local draw=g.draw;g.draw=function()g.setShader({});error('row draw failure')end
  T.raises(function()p:drawSprites(retained)end,'row draw failure')
  T.eq(g.getShader(),outside,'failed drawing also restores caller graphics state')
  for i=1,4 do
    T.same(outside.values['pal'..(i-1)],{outerColors[i][1]/255,outerColors[i][2]/255,outerColors[i][3]/255},
      'failed drawing restores caller palette uniforms as well as shader identity')
  end
  g.draw=draw
  p:release();T.eq(snapshot.image.released,true,'view retirement releases retained snapshot images')
  P.setBgp(nil);g.setShader()
 end end
end
-- Smaller 6x6 fronts still start one TILE from the left, as PadFrontpic does.
for _,n in ipairs{40,48,56}do
  sources['sized-'..n]=picture(n,n,0);Assets.invalidate()
  local row=Rows.snapshot({path='sized-'..n},{battler='enemy',rows=1})
  local left=n<56 and 8 or 0
  for x=0,55 do
    local expected={0,0,0,0}
    if x>=left and x<left+n then
      expected={sources['sized-'..n]:getPixel(x-left,n-1)}
      if expected[1]>.83 then expected[4]=0 end
    end
    T.same({row.image:getPixel(x,7)},expected,'declared native 5/6/7-tile front padding')
  end
end
-- Custom RGB art opts out of indexed colour-zero removal; crop keeps the
-- selected Crystal frame instead of sampling an entire animation strip.
Assets.invalidate();sources.rgb=F.image(96,48)
sources.rgb:mapPixel(function(x)return x<48 and 0 or 1,.4,.2,.75 end)
local rgb=Rows.snapshot({path='rgb',trueColor=true,crop={index=2,width=48}},{battler='player',rows=2})
T.same({rgb.image:getPixel(0,0)},{1,.4,.2,.75});T.eq(rgb.trueColor,true)
T.eq(Rows.quad(rgb,12),nil,'out-of-range OAM cells are not invented')
do
  local s,p=make('crystal',2,'player')
  local original=s:gen2ObjectPictureSource('player').path
  local row={anim='PROBE'};s.moveAnimRow=row;s.queue={row}
  require('src.battle.Gen2PicturePresentation').transform(s,s.player,s.enemy)
  T.eq(s:gen2ObjectPictureSource('player').path,original,
    'queued Transform reads the pinned old picture, not its future resolved sprite')
  s:animForMove('PROBE','player');p:update()
  local entry=p.runtime.loaded[2]
  T.check(p.view.battlerRows[entry]~=nil,'pending picture snapshot still uses actual command')
  local originalProvider=s.gen2ObjectPictureSource
  sources['rgb-live']=F.image(96,48)
  sources['rgb-live']:mapPixel(function(x)return x<48 and 0 or 1,.4,.2,.75 end)
  function s:gen2ObjectPictureSource(side)
    if side=='player'then return {path='rgb-live',trueColor=true,crop={index=2,width=48}}end
    return originalProvider(self,side)
  end
  s:animForMove('PROBE','player');p:update();draws={};p:draw()
  T.eq(#draws,26)
  for i=15,26 do
    T.same(draws[i].colors,{},'actual custom RGB OAM clears preceding indexed shader')
    T.same({draws[i].image:getPixel(0,0)},{1,.4,.2,.75},'actual OBJ copy retains selected RGB frame')
  end
  s.gen2ObjectPictureSource=originalProvider
  -- A real raisesub command precedes the copy, and therefore the doll is
  -- the current BG source. A later dropsub cannot alter these copied cells.
  local code=p.anims.scripts[1].code
  table.insert(code,1,{op='raisesub'})
  p.anims.pictureArt={version=1,substitute={player='qa-doll-back',enemy='qa-doll-front'}}
  sources['qa-doll-back']=picture(48,48,2);sources['qa-doll-front']=picture(56,56,1)
  s:animForMove('PROBE','player');p:update()
  T.eq(s:gen2ObjectPictureSource('player').path,'qa-doll-back','source follows real VM replacement state')
  local copied=p.view.battlerRows[p.runtime.loaded[2]].image
  local expected={sources['qa-doll-back']:getPixel(0,0)}
  if expected[1]>.83 then expected[4]=0 end
  T.same({copied:getPixel(0,0)},expected,'real native copy uses replacement pixels')
  p.runtime.picOverride.player=false
  T.eq(s:gen2ObjectPictureSource('player').path,original,'drop reveals native pinned Pokemon source')
  T.same({copied:getPixel(0,0)},expected,'later visible picture change cannot mutate earlier OBJ copy')
  p:release()
end
Assets.imageData,love.image,g.newImage,g.draw,g.newShader=oldData,oldImage,oldNew,oldDraw,oldShader
Assets.invalidate();V.set(oldVersion)
T.finish('native GSC battler-row copy pixels, actual OAM, palettes, snapshots and lifetime')
