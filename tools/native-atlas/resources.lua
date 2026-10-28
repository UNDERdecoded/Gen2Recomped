local C={}
function C.run(T,readImage)
  local Native=require('src.core.game3.tileset_native')
  local Stream=require('src.core.game3.asset_stream')
  local Upload=require('src.compat.gen1.AtlasUpload')
  local Pixels=require('src.compat.gen1.AtlasPixels')
  local F=require('tools.native-atlas.session-fixture')
  local renderer=require('src.render.TileRenderer')
  local previousGame=package.loaded['src.core.Game']
  local previousView=package.loaded['src.core.game3.field_view']
  local function equalImage(ts,over,message)
    T.eq(readImage(ts[over and'overImage'or'image']),ts[over and'overImageData'or'imageData']:getString(),message)
  end
  local function dead(object)
    return not pcall(function()return object:getWidth()end)
  end
  for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
    Native.release()
    local f=F.new(edition)
    T.eq(Native.ready(f.pair),true,'native atlas can warm before an avatar is spawned')
    T.eq(f.world.player,nil)
    T.eq(Native.prefetch(f.pair,4),true);T.eq(Native.resident(),0)
    local steps=0
    while Native._stream.pending[f.pair]do Stream.update();steps=steps+1;assert(steps<100,'atlas warming did not finish')end
    T.check(steps>1,'CPU and GPU preparation yield between resource stages')
    local ts=assert(Native.get(f.pair));T.eq(Native.get(f.pair),ts)
    local animation=require('src.core.game3.tileset_anim')
    local clock=renderer.animFrame()
    T.eq(animation._pairs[f.pair].native,true,'animation census observes the actual resident native atlas')
    T.eq(animation._pairs[f.pair].rse,edition~='firered'and edition~='leafgreen')
    T.eq(renderer.animFrame(),clock,'reading animation ownership never advances the native clock')
    local observed=animation._pairs;observed[f.pair].rse='mutated'
    T.eq(animation._pairs[f.pair].rse,edition~='firered'and edition~='leafgreen','source observation is detached')
    T.eq(ts.imageData:getWidth(),256);T.eq(ts.imageData:getHeight(),32)
    local expected=Pixels.new(f.picture.pair,f.picture.layout);expected:update(renderer.animFrame())
    T.eq(ts.imageData:getString(),expected:rgba(false));T.eq(ts.overImageData:getString(),expected:rgba(true))
    equalImage(ts,false,'initial native under texture matches CPU bytes')
    equalImage(ts,true,'initial native over texture matches CPU bytes')
    T.eq(Native.hasMid(ts,19),false);T.eq(Native.slotFor(ts,19),0)
    T.eq(Native.slotFor(ts,f.picture.layout.metatilesInPrimary),19)
    T.check(Native.quad(ts,19)~=nil);T.check(Native.overQuad(ts,19)~=nil)
    T.eq(Native.quad(ts,-1),nil)
    local lease=assert(Native.acquire(f.pair))
    T.eq(#Native.trim({},0),0,'explicit leases prevent LRU retirement')
    lease.release();lease.release();T.eq(ts._leases,0,'lease release is idempotent')
    -- Cancel after CPU allocation but before publication. Its partial data
    -- must be released, with the already resident pair left untouched.
    Native.prefetch(f.neighborPair,1)
    local job=Native._stream.pending[f.neighborPair]
    while job and not(job.ts and job.ts.imageData)do Stream.update();job=Native._stream.pending[f.neighborPair]end
    local partial=assert(job and job.ts and job.ts.imageData)
    Native._stream:retain({[f.pair]=true})
    T.eq(Native._stream.pending[f.neighborPair],nil);T.eq(dead(partial),true)
    T.eq(Native.resident(),1)
    Native.ensureAlt(ts)
    -- The actual public flush is replaceable: animation/palette updates
    -- must pass through a source wrapper, so its dirty revisions survive.
    local original=Native.flush;local observed=0
    local ok=require('src.mods.ModSeams').run('atlas_flush_probe',function()
      Native.flush=function(value,under,over)
        observed=observed+1
        return original(value,under,over,3,true)
      end
    end)
    T.eq(ok,true)
    local batch={texture=ts.image}
    function batch:getTexture()return self.texture end
    function batch:setTexture(texture)self.texture=texture end
    package.loaded['src.core.game3.field_view']={_nativeBatch=batch}
    for palette=0,3 do
      local words={};for i=1,16 do words[i]=palette<=1 and 31 or(palette==2 and 31*32 or 31*1024)end
      T.eq(Native.setSlotPalette(ts,palette,words),true)
      T.eq(batch.texture,ts.image,'retained source batches follow buffer switches')
      equalImage(ts,false,'three-buffer partial palette history is complete')
      equalImage(ts,true,'overhead palette history is complete')
    end
    T.check(observed>=3,'native updates invoke the currently installed source flush wrapper')
    -- Dirty cells in different rows must accumulate separately for every
    -- backing image, including after switching between two and three buffers.
    for pass=1,9 do
      local slot=({0,17,30})[(pass-1)%3+1]
      local pixel=string.char(pass*17,255-pass*19,pass*11,255)
      Upload.patch(ts.imageData,ts.cols,slot,string.rep(pixel,256),pass%2==0)
      Native.markDirty(ts,false,slot)
      original(ts,true,false,pass%2==0 and 2 or 3,pass%3~=0)
      equalImage(ts,false,'mixed full/row/cell buffer history preserves every changed cell')
    end
    local third=ts._uploadBuffers.image.entries[3].image
    local other=assert(Native.get(f.neighborPair));local otherImage=other.image
    Native.trim({},0,{[third]=true})
    T.eq(ts.image~=nil,true,'busy protection includes the third backing image')
    T.eq(dead(otherImage),true);T.eq(Native.resident(),1)
    -- Structural replacement publishes a fresh atlas while a leased prior
    -- resource remains usable until its owner explicitly releases it.
    local held=assert(Native.acquire(f.pair));local oldImage=held.atlas.image
    f.game.data.map_tilesets.P.tiles=string.rep('\17',#f.game.data.map_tilesets.P.tiles)
    local replacement=assert(Native.get(f.pair))
    T.check(replacement~=ts);T.eq(dead(oldImage),false)
    held.release();T.eq(dead(oldImage),true)
    package.loaded['src.core.game3.field_view']=previousView
    -- Restore pristine pixels for independent native-clock animation tests.
    Native.release();f.views:release();f=F.new(edition)
    local base=f.game.data.map_tilesets.P
    base.animations={{tile=0,count=1,step=3,frames={string.rep('\17',32),string.rep('\34',32),string.rep('\51',32)}}}
    ts=assert(Native.get(f.pair))
    local expected=Pixels.new({primary=base,secondary=f.game.data.map_tilesets.S},f.picture.layout)
    for tick=1,12 do
      renderer.tick(1/60);Native.update();expected:update(renderer.animFrame())
      T.eq(ts.imageData:getString(),expected:rgba(false),'atlas follows the existing native animation clock')
      equalImage(ts,false,'native-clock pixel updates reach the GPU')
      equalImage(ts,true,'native-clock overhead updates reach the GPU')
    end
    local image=ts.image;local data=ts.imageData
    local generation=Native._gen
    require('src.mods.Loader').teardown()
    T.eq(animation._pairs[f.pair],nil,'retired native resources disappear from animation observations')
    T.eq(Native.resident(),0);T.eq(dead(image),true);T.eq(dead(data),true)
    T.eq(Native.flush,original,'real loader unwind restores source resource wrappers')
    T.eq(Native._cache,nil);T.check(Native._gen>generation)
    f.views:release()
  end
  -- A source mod can replace a public cache entry with its own atlas. The
  -- provider retires the displaced owned resource, while a borrowed-image
  -- alias keeps the original backing image alive for as long as it is live.
  do
    local f=F.new('firered');local ts=assert(Native.get(f.pair));local image=ts.image
    local alias={image=ts.image,overImage=ts.overImage,imageData=ts.imageData,overImageData=ts.overImageData,
      midToSlot=ts.midToSlot,cols=ts.cols,rows=ts.rows,quads={},overQuads={}}
    Native._pairs[f.pair]=alias
    T.eq(Native.get(f.pair),alias);T.eq(dead(image),false,'cache aliases cannot free borrowed backing textures')
    Native._pairs[f.pair]=nil
    Native.ready(f.pair);T.eq(dead(image),true,'displaced unreferenced atlases are retired without waiting for exit')
    Native.release();f.views:release()
  end
  -- Native model validation and GPU creation failure both release the job's
  -- partial payload and retain the diagnostic for the explicit get caller.
  do
    local f=F.new('firered')
    f.game.data.map_tilesets.S.palettes=nil
    local ts,why=Native.get(f.pair)
    T.eq(ts,nil);T.check(why:find('palette data unavailable',1,true)~=nil);T.eq(Native.resident(),0)
    Native.release();f.views:release();f=F.new('firered')
    local constructor=love.graphics.newImage
    love.graphics.newImage=function()error('atlas GPU probe failure')end
    ts,why=Native.get(f.pair)
    love.graphics.newImage=constructor
    T.eq(ts,nil);T.check(why:find('atlas GPU probe failure',1,true)~=nil);T.eq(Native.resident(),0)
    T.eq(Native._stream.pending[f.pair],nil)
    T.check(Native.get(f.pair)~=nil,'a failed upload can retry after the graphics device recovers')
    Native.release();f.views:release()
  end
  Native.release();package.loaded['src.core.Game']=previousGame;package.loaded['src.core.game3.field_view']=previousView
end
return C
