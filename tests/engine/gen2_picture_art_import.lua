package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local F=dofile('tests/gen2_picture_art/fixture.lua')
local Art=require('src.import.Gen2BattlePictureArt')
local Data=require('src.battle.Gen2AnimData')
local Player=require('src.battle.Gen2AnimPlayer')
local image=love.image;love.image={newImageData=F.image}
local shades={1,2/3,1/3,0}
for _,edition in ipairs({'gold','silver','crystal','prism'})do
  local e,images=F.extractor(edition)
  local a=assert(Art.extract(e))
  T.eq(a.version,1,'import advertises actual decoded picture format')
  T.eq(a.stagedActorPic,edition=='crystal'or edition=='prism','only positive staged-copy handler is advertised')
  local count=0;for _ in pairs(images)do count=count+1 end
  T.eq(count,5,'actual importer emits four full boxes and public doll sheet')
  for _,back in ipairs({false,true})do
    local side=back and 'player'or'enemy'
    local n=back and 6 or 7
    local doll=images[a.substitute[side]]
    T.same({doll:getDimensions()},{n*8,n*8},'doll uses native full tile box')
    for y=0,n*8-1 do for x=0,n*8-1 do
      local inside=x>=16 and x<32 and y>=(back and 32 or 40)and y<(back and 48 or 56)
      local expected=0
      if inside then
        local tile=(back and 4 or 0)+math.floor((y-(back and 32 or 40))/8)*2+math.floor((x-16)/8)
        expected=(tile+x%8+2*(y%8))%4
      end
      local r,g,b,alpha=doll:getPixel(x,y)
      T.same({r,g,b,alpha},{shades[expected+1],shades[expected+1],shades[expected+1],expected==0 and 0 or 1},
        'ROM doll tile identity, row/column order, shade and transparency')
    end end
    local mini=images[a.minimize[side]]
    for y=0,n*8-1 do for x=0,n*8-1 do
      local inside=x>=24 and x<32 and y>=(back and 32 or 40)and y<(back and 40 or 48)
      local expected=inside and (3+x%8+2*(y%8))%4 or 0
      local r,g,b,alpha=mini:getPixel(x,y)
      T.same({r,g,b,alpha},{shades[expected+1],shades[expected+1],shades[expected+1],expected==0 and 0 or 1},
        'ROM Minimize tile is copied once into its own native column/row')
    end end
  end
  local tables=Data.tables({pictureArt=a})
  T.eq(tables.pictureArt,a,'native adapter retains actual imported capability and paths')
  for _,back in ipairs({false,true})do
    for _,kind in ipairs({'minimize','transform'})do
      local native={gen2=true,pictureArt=a,moveAnims={PROBE=1},scripts={
        [1]={entry=1,code={{op=kind},{op='delay',frames=3},{op='updateactorpic'},
          {op='delay',frames=3},{op='ret'}}},
      }}
      local p=Player.new({battle_anims=native})
      p:start('PROBE',back);local r=p.runtime;local side=back and 'player'or'enemy'
      p:update()
      local initial
      if not a.stagedActorPic and kind=='transform'then initial='transform'end
      T.eq(r.picOverride[side],initial,
        'staging cannot repaint actor before update command')
      if a.stagedActorPic then T.eq(r.actorPic[side],kind,'real VM owns staged tile identity')end
      local steps=0
      while r.frames<5 and steps<100 do p:update();steps=steps+1 end
      T.eq(r.picOverride[side],a.stagedActorPic and kind or (kind=='transform'and'transform'or nil),
        'real copy command publishes the staged identity only on capable ROMs')
      p:start('PROBE',not back)
      T.eq(next(p.runtime.actorPic),nil,'new VM starts with empty staged tiles')
      p:release()
    end
  end
end
for _,change in ipairs({
  function(s)s.MonsterSpriteGFX=nil;s.MinimizePic=nil end,
  function(s,r)r[0x5000]=300;r[0x6000]=-1 end,
  function(s,r)r[0x5000]=nil;r[0x6000]=nil end,
})do
  local e,images=F.extractor('gold',change)
  T.eq(Art.extract(e),nil,'missing/malformed ROM bytes do not invent picture art')
  T.eq(next(images),nil,'unavailable art cannot leave advertised partial images')
end
local e,images=F.extractor('crystal',function(s)s.MonsterSpriteGFX=nil;s.MinimizePic=nil end)
local a=Art.extract(e)
T.eq(a.stagedActorPic,true,'independent actor-copy capability survives unavailable optional graphics')
T.eq(a.minimize,nil,'missing Minimize symbol does not fabricate a replacement')
T.eq(next(images),nil,'metadata alone emits no invented art')
love.image=image
T.finish('native GSC picture import pixels, staged copy and missing-ROM-data boundaries')
