local M={}
local function expected(r)
  local parts={}
  for i=1,#r.indexed do
    local n=r.indexed:byte(i)
    if n==0 then parts[i]='\0\0\0\0'
    else local v=math.floor(n*255/31+.5);parts[i]=string.char(v,v,v,255)end
  end
  return table.concat(parts)
end
function M.run(T,read,asset)
  local S=require('src.core.game3.ow_sprites');local Stream=require('src.core.game3.asset_stream')
  local Assets=require('src.render.Assets');local F=require('tools.sprite-runtime.fixture')
  local originalGame=package.loaded['src.core.Game'];local sourcePlayer=package.loaded['src.core.game3.player']
  package.loaded['src.core.game3.player']=nil
  local function dead(o)return not pcall(function()return o:getWidth()end)end
  for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
    S.release();local f=F.new(edition)
    T.eq(S.ready(),true);T.eq(S._stream.context,nil,'the stream protocol cannot lend its native context')
    T.eq(S._manifest.sprites[0].frameCount,18)
    local base=assert(S.get(0));local pixels=expected(f.records[0])
    T.eq(base.width,16);T.eq(base.height,16);T.eq(base.frameCount,18);T.eq(base.inanimate,false)
    T.eq(base.imageData:getString(),pixels);T.eq(read(base.image),pixels,'GPU upload preserves original image-table pixels')
    T.eq(S.get(0),base);T.eq(S._loaded[0],base)
    for frame=0,17 do
      local x,y,w,h=base.quads[frame]:getViewport();T.eq(x,0);T.eq(y,frame*16);T.eq(w,16);T.eq(h,16)
    end
    base.palette[1]=999;T.eq(f.records[0].palette[1],1057,'source palette records are detached')
    base.palette[1]=1057
    T.eq(S.get(-1),nil);T.eq(S.get(0/0),nil);T.eq(S.get(65536),nil);T.eq(S.get(999),nil)
    -- Source queue work is cooperative, and cancelled work is never published.
    T.eq(S.prefetch(1,4),true);T.eq(S._stream.pending[1],true)
    S._stream:step(0);T.eq(S._loaded[1],nil)
    S._stream:retain({[0]=true});T.eq(S._stream.pending[1],nil);T.eq(S._loaded[1],nil)
    S.prefetch(1,4);local steps=0
    while S._stream.pending[1]do S._stream:step(0);steps=steps+1;assert(steps<100)end
    T.check(steps>2,'data, texture and quad preparation use separate slices')
    local npc=assert(S.get(1));T.eq(read(npc.image),expected(f.records[1]));T.eq(S.peekDraw(1),npc)
    T.eq(S.peekDraw(2),nil);T.eq(S._stream.pending[2],true)
    local mount=assert(S.get(2));T.eq(mount.frameCount,3)
    -- Exact palette replacement, no silent successful no-op and no mutation
    -- of the base pixels that another source/native consumer already holds.
    local red={{255,0,0}};T.eq(S.setObjectPalette(0,'red',red,{{8,8,8}}),true)
    local alt=assert(S.getDraw(0));T.check(alt~=base);T.eq(S.get(0),base)
    T.eq(S.objectPaletteKey(0),'red');T.eq(alt.imageData:getString():sub(5,8),string.char(255,0,0,255))
    T.eq(base.imageData:getString(),pixels);T.eq(read(alt.image),alt.imageData:getString())
    T.eq(S.setObjectPalette(0,'no match',{{1,2,3}},{{70,11,240}}),false)
    T.eq(S.objectPaletteKey(0),'red','a rejected substitution cannot discard the old valid palette')
    T.eq(S.setObjectPalette(0,'bad',{{0/0,2,3}},{{8,8,8}}),false)
    local altImage=alt.image;T.eq(S.clearObjectPalette(0),true);T.eq(dead(altImage),true);T.eq(S.getDraw(0),base)
    local mirror=assert(S.getReflectionDraw(0));T.eq(S.getReflectionDraw(0),mirror)
    T.eq(read(mirror.image),mirror.imageData:getString());T.eq(base.imageData:getString(),pixels)
    -- Native image overrides are projected through the imported frame map,
    -- while the engine's shared image cache is never used or released.
    local nativeFile='sprite-tests/'..edition..'-native.png';local runFile='sprite-tests/'..edition..'-run.png'
    local frames={};local runs={}
    for frame=0,8 do
      frames[#frames+1]=string.rep(string.char(20+frame,70,90,255),256)
      runs[#runs+1]=string.rep(string.char(120+frame,80,100,255),256)
    end
    asset(nativeFile,16,144,table.concat(frames));asset(runFile,16,144,table.concat(runs))
    f.game.data.sprites.SPRITE_G3_000.image=nativeFile
    f.game.data.sprites.SPRITE_G3_000_RUN.image=runFile
    local oldImage=base.image;local replaced=assert(S.get(0));T.check(replaced~=base);T.eq(dead(oldImage),true)
    for frame,original in ipairs(f.records[0].native.order)do
      T.eq(replaced.imageData:getString():sub(original*1024+1,(original+1)*1024),frames[frame],'native walk-frame projection')
    end
    for frame,original in ipairs(f.records[0].native.runOrder)do
      T.eq(replaced.imageData:getString():sub(original*1024+1,(original+1)*1024),runs[frame],'native run-frame projection')
    end
    T.eq(read(replaced.image),replaced.imageData:getString())
    -- An original-order override keeps every slot, including poses absent
    -- from normalized walk/run sheets. Use the real asset-search bridge.
    local oldLoader=Assets.loader
    local rawFile='sprite-tests/'..edition..'-source.png'
    local rawBytes=string.rep('\19\29\39\255',256*18)
    local replacedImage=replaced.image
    asset(rawFile,16,288,rawBytes)
    Assets.loader={overrideOrder=function()return{}end,derivedPath=function(_,rel)
      if rel=='overworld/g3_000_source.png'then return rawFile end
    end}
    local raw=assert(S.get(0));T.eq(raw.frameCount,18);T.eq(read(raw.image),rawBytes)
    T.eq(dead(replacedImage),true,'a changed asset search retires the previous resource')
    Assets.loader=oldLoader
    -- Changing a native definition to a static sheet retains that behavior.
    local static='sprite-tests/'..edition..'-static.png';asset(static,16,16,string.rep('\12\23\34\255',256))
    f.game.data.sprites.SPRITE_G3_000.image=static;f.game.data.sprites.SPRITE_G3_000.frames=1
    local still=assert(S.get(0));T.eq(still.frameCount,1);T.eq(still.inanimate,true)
    T.eq(S.pose(still,'right',1,false),0);T.eq(read(still.image),string.rep('\12\23\34\255',256))
    -- Base metadata cannot be silently reused after any owning cohort changes.
    for _,replace in ipairs({
      function()f.game.save={player={gender=1}}end,
      function()f.game.mods={}end,
      function()local data={};for k,v in pairs(f.game.data)do data[k]=v end;f.game.data=data end,
      function()local meta={};for k,v in pairs(f.game.data.gen3_object_sheets)do meta[k]=v end;f.game.data.gen3_object_sheets=meta end,
    })do
      local old=assert(S.get(1));local image=old.image;replace();local next=assert(S.get(1));T.check(next~=old);T.eq(dead(image),true)
    end
    local old=assert(S.get(1));local image,data=old.image,old.imageData
    Assets.invalidate();T.eq(dead(image),true);T.eq(dead(data),true);T.check(S.get(1)~=old)
    -- Avatar observations use the native state without touching its timers.
    f.game.save.player.gender=0
    T.eq(S.playerGraphicsId(f.game),0)
    f.player.fishing=true;T.eq(S.playerGraphicsId(f.game),(edition=='firered'or edition=='leafgreen')and 4 or 137)
    f.player.fishing=nil;f.game.save.player.gender=1;T.eq(S.playerGraphicsId(f.game),(edition=='firered'or edition=='leafgreen')and 7 or 89)
    -- Earlier generations keep the native rendering path and cannot inherit
    -- this GBA resource context, even while the same Game table remains live.
    local held=S.get(1);local heldImage=held.image
    require('src.core.GameVersion').set('crystal');T.eq(S.ready(),false);T.eq(dead(heldImage),true);T.eq(S.get(1),nil)
  end
  package.loaded['src.core.game3.player']=sourcePlayer
  package.loaded['src.core.Game']=originalGame;S.release()
end
return M
