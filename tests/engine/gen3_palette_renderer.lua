package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local F = require("tools.native-palettes.fixture")
local Copy = require("src.mods.Merge").deepCopy
local TR = require("src.render.TileRenderer")
local Tiles = require("src.render.Gen3Tiles")
-- Pixel-bearing texture/Canvas stand-ins: run the real sheet bake, refresh,
-- cached batch and border paths without a window, GPU, cartridge or save.
local original={image=love.image,newImage=love.graphics.newImage,newCanvas=love.graphics.newCanvas,
  draw=love.graphics.draw,clear=love.graphics.clear}
local allocations,updates,canvases,surfaceReleases=0,0,0,0
local function surface(w,h,format,bytes)
  local data={w=w,h=h,bytes=bytes or string.rep("\0",w*h*4)}
  function data:release()
    T.check(not self.released,"CPU atlas released once")
    self.released=true;self.bytes=nil;surfaceReleases=surfaceReleases+1
  end
  return data
end
local function image(data)
  T.check(not data.released,"image upload receives live CPU pixels")
  allocations=allocations+1
  local out={w=data.w,h=data.h,bytes=data.bytes,updates=0}
  function out:replacePixels(next)
    T.check(not next.released,"palette upload never uses evicted CPU pixels")
    T.eq(next.w,self.w,"palette refresh preserves image width")
    T.eq(next.h,self.h,"palette refresh preserves image height")
    self.bytes=next.bytes;self.updates=self.updates+1;updates=updates+1
  end
  function out:setWrap() end
  function out:setFilter() end
  return out
end
love.image={newImageData=surface}
love.graphics.newImage=image
love.graphics.newCanvas=function(w,h)
  canvases=canvases+1
  local c={w=w,h=h,pixels={}}
  function c:newImageData() return surface(w,h,"rgba8",table.concat(self.pixels)) end
  return c
end
love.graphics.clear=function(r,g,b,a)
  local canvas=love.graphics.getCanvas()
  if not canvas then return end
  local p=string.char(r*255,g*255,b*255,(a or 1)*255)
  for i=1,canvas.w*canvas.h do canvas.pixels[i]=p end
end
love.graphics.draw=function(img,quad,ox,oy)
  local canvas=love.graphics.getCanvas()
  if not canvas then return end
  for y=0,quad.h-1 do for x=0,quad.w-1 do
    local at=((quad.y+y)*img.w+quad.x+x)*4+1
    local px=img.bytes:sub(at,at+3)
    if px:byte(4)==255 then canvas.pixels[(y+oy)*canvas.w+x+ox+1]=px end
  end end
end
local function expectedSheet(decoder,record,layer)
  local pixels={}
  for i=1,record.width*record.height do pixels[i]="\0\0\0\0" end
  local function plot(x,y,r,g,b) pixels[y*record.width+x+1]=string.char(r,g,b,255) end
  decoder:setAnimFrame(0);decoder:bakeLayer(layer,plot)
  for mid,slots in pairs(record.animSlots or {}) do
    for frame=2,record.animFrames do
      decoder:setAnimFrame(frame-1);decoder:bakeMetatileInto(mid,layer,slots[frame],plot)
    end
  end
  return table.concat(pixels)
end
for _,version in ipairs({"emerald","firered"}) do
  TR.releaseGen3Sheets()
  local f=F.new(version,2,true)
  local s=f.state
  local layout=s.game.data.constants.gen3Layout
  local split=layout.palettesInPrimary
  f.records.P.paletteCycles={ {kind="rotate",first=17,count=4,step=3,direction=1} }
  f.records.S.paletteCycles={ {kind="rotate",first=split*16+1,count=4,step=5,direction=-1} }
  local originalP,originalS=Copy(f.records.P.palettes),Copy(f.records.S.palettes)
  local record=assert(TR.gen3SheetsFor(s.map.tileset,s.game.data,layout))
  local renderer=setmetatable({gen3=record,map=s.map,gen3Key=s.map.tileset.id,
    gen3Quads={},bodyTilesW=6,bodyTilesH=4,blockTiles=2}, {__index=TR})
  -- The real sheet column count, not a guessed source-layout dimension.
  for id=0,record.slots-1 do
    renderer.gen3Quads[id]=love.graphics.newQuad(id%Tiles.SHEET_COLS*16,math.floor(id/Tiles.SHEET_COLS)*16,16,16)
  end
  s.map.def.border=string.rep("\0",8)
  renderer:ensureWindow(0,0,48,32)
  renderer:ensureBorderFill()
  local bottom,top,cover,border=record.bottom,record.top,record.cover,renderer.borderFill
  T.check(cover~=nil,"fixture exercises reflection-cover refresh")
  T.check(border~=nil,"fixture exercises border refresh")
  local batch=renderer.winBatch
  local baseAllocations=allocations
  local baseCanvases=canvases
  for step=0,12 do
    local priorKey=record.tiles.paletteState.contentKey
    local priorUpdates=bottom.updates+top.updates+(cover and cover.updates or 0)
    renderer:ensureWindow(0,0,48,32)
    renderer:ensureBorderFill()
    local ticks=TR.animFrame()
    local p,q=Copy(f.records.P),Copy(f.records.S)
    for c=0,3 do
      p.palettes[2][c+2]=Copy(originalP[2][(c-math.floor(ticks/3))%4+2])
      q.palettes[split+1][c+2]=Copy(originalS[split+1][(c+math.floor(ticks/5))%4+2])
    end
    local expected=Tiles.new({primary=p,secondary=q},layout)
    T.eq(record.bottom.bytes,expectedSheet(expected,record,1),"native bottom atlas uses independently expected palette")
    T.eq(record.top.bytes,expectedSheet(expected,record,2),"native top atlas and every tile frame recolored")
    if cover then
      for mid,quads in pairs(record.coverQuads) do
        for frame,quad in ipairs(quads) do
          expected:setAnimFrame(frame-1)
          local pixels={}
          for i=1,256 do pixels[i]="\0\0\0\0" end
          expected:drawLayer(mid,2,0,0,function(x,y,r,g,b) pixels[y*16+x+1]=string.char(r,g,b,255) end)
          local got={}
          for y=0,15 do
            local start=((quad.y+y)*cover.w+quad.x)*4+1
            got[#got+1]=cover.bytes:sub(start,start+63)
          end
          T.eq(table.concat(got),table.concat(pixels),"reflection cover uses current palette in every tile frame")
        end
      end
    end
    local borderPixels={}
    for y=0,31 do for x=0,31 do
      local at=((y%16)*bottom.w+x%16)*4+1
      local a,b=bottom.bytes:sub(at,at+3),top.bytes:sub(at,at+3)
      borderPixels[#borderPixels+1]=b:byte(4)==255 and b or (a:byte(4)==255 and a or "\0\0\0\255")
    end end
    T.eq(border.bytes,table.concat(borderPixels),"map border actually receives current atlas colours")
    T.eq(record.bottom,bottom,"native bottom texture retained")
    T.eq(record.top,top,"native top texture retained")
    T.eq(record.cover,cover,"reflection texture retained")
    T.eq(renderer.borderFill,border,"border texture retained")
    T.eq(renderer.winBatch,batch,"cached batch survives palette updates")
    T.eq(allocations,baseAllocations,"no GPU-image churn during palette cycle")
    T.eq(canvases,baseCanvases,"no border canvas churn during palette cycle")
    local count=updates
    renderer:drawReflectionCover(0,0,0,0)
    renderer:syncGen3Palettes()
    T.eq(updates,count,"multiple passes in one tick never repaint twice")
    if priorKey==record.tiles.paletteState.contentKey then
      T.eq(priorUpdates,bottom.updates+top.updates+(cover and cover.updates or 0),"stable picture avoids sheet upload")
    end
    if step==0 then
      local second=setmetatable({gen3=record,map=s.map,gen3Quads=renderer.gen3Quads},{__index=TR})
      second:ensureBorderFill()
      local old=second.borderFill
      for _=1,5 do TR.tick(1/60) end
      renderer:syncGen3Palettes()
      local prior=updates
      second:ensureBorderFill()
      T.eq(second.borderFill,old,"shared pair refresh retains each renderer's border image")
      T.check(updates>prior,"second renderer refreshes border even after pair was already sampled")
      baseAllocations=allocations
      baseCanvases=canvases
    else TR.tick(1/60) end
  end
  T.check(bottom.updates>0 and top.updates>0 and cover.updates>0,"both layers and covers receive changed colours")
  T.check(border.updates>0,"palette changes reach map border")
  T.same(f.records.P.palettes,originalP,"native cycle never modifies source primary")
  T.same(f.records.S.palettes,originalS,"native cycle never modifies source secondary")
  -- Invalid/removed metadata returns to base colors instead of leaving a
  -- formerly animated palette frozen in the texture.
  f.records.P.paletteCycles=nil
  TR.tick(1/60);renderer:syncGen3Palettes()
  T.eq(record.tiles.paletteState,nil,"incomplete source metadata leaves native base fallback")
  local base=Tiles.new({primary=f.records.P,secondary=f.records.S},layout)
  T.eq(record.bottom.bytes,expectedSheet(base,record,1),"base fallback actually reaches existing atlas")
  local before=updates
  TR.tick(1/60);renderer:syncGen3Palettes()
  T.eq(updates,before,"invalid metadata does not repeatedly upload unchanged base")
  f.run.release()
end
-- Legacy/no-mod source remains pixel-identical and performs no new upload.
TR.releaseGen3Sheets()
local f=F.new("emerald",2)
local rec=assert(TR.gen3SheetsFor(f.state.map.tileset,f.state.game.data,f.state.game.data.constants.gen3Layout))
local r=setmetatable({gen3=rec},{__index=TR})
local before=updates
for _=1,20 do TR.tick(1/60);r:syncGen3Palettes() end
T.eq(updates,before,"legacy metadata-free native rendering has no palette uploads")
T.eq(rec.tiles.paletteState,nil,"legacy decoder retains original palettes")
f.run.release()

-- The repeating four-picture program must stop baking after warmup, while
-- every restored atlas/animation/cover remains pixel-identical to decoding.
TR.releaseGen3Sheets()
f=F.new("emerald",2)
local frames={}
for i=1,4 do frames[i]=string.rep(string.char(i*29,i*43,i*53),4) end
f.records.P.paletteCycles={{kind="frames",first=17,count=4,step=1,frames=frames}}
f.records.S.paletteCycles={}
rec=assert(TR.gen3SheetsFor(f.state.map.tileset,f.state.game.data,f.state.game.data.constants.gen3Layout))
r=setmetatable({gen3=rec},{__index=TR})
local bakes=0
local bake=rec.tiles.bakeLayer
rec.tiles.bakeLayer=function(self,... )bakes=bakes+1;return bake(self,...)end
local originalBottom,originalTop,originalCover=rec.bottom,rec.top,rec.cover
for n=1,40 do
  TR.tick(1/60);r:syncGen3Palettes()
  local expected=Tiles.new({primary=f.records.P,secondary=f.records.S},f.state.game.data.constants.gen3Layout)
  expected:setPaletteTicks(TR.animFrame())
  T.eq(rec.bottom.bytes,expectedSheet(expected,rec,1),"cached bottom equals independent current decode")
  T.eq(rec.top.bytes,expectedSheet(expected,rec,2),"cached top/animation slots equal current decode")
  if rec.cover then
    for mid,quads in pairs(rec.coverQuads) do
      for frame,quad in ipairs(quads) do
        expected:setAnimFrame(frame-1)
        local pixels={};for i=1,256 do pixels[i]="\0\0\0\0" end
        expected:drawLayer(mid,2,0,0,function(x,y,rr,gg,bb)pixels[y*16+x+1]=string.char(rr,gg,bb,255)end)
        local got={}
        for y=0,15 do local at=((quad.y+y)*rec.cover.w+quad.x)*4+1;got[#got+1]=rec.cover.bytes:sub(at,at+63)end
        T.eq(table.concat(got),table.concat(pixels),"cached reflection cover equals independent decode")
      end
    end
  end
  T.eq(rec.bottom,originalBottom,"cache hit preserves bottom GPU identity")
  T.eq(rec.top,originalTop,"cache hit preserves top GPU identity")
  T.eq(rec.cover,originalCover,"cache hit preserves reflection GPU identity")
end
T.eq(bakes,6,"four-picture cycle bakes only three missing two-layer pictures")
T.eq(TR.gen3PaletteCacheStats().entries,4,"four-picture cycle retains four pictures")
local warmed=bakes
for _=1,100 do TR.tick(1/60);r:syncGen3Palettes() end
T.eq(bakes,warmed,"many repeated palette cycles perform no full atlas bake")
-- A new colour picture fails its upload: no partial picture enters the cache,
-- temporary CPU pixels are released and the tile-animation selection survives.
local savedUpload=rec.bottom.replacePixels
rec.bottom.replacePixels=function()error("intentional atlas upload failure")end
for i=1,4 do frames[i]=string.rep(string.char(250-i,240-i,230-i),4) end
local releasedBefore=surfaceReleases
local frameBefore=rec.tiles.animFrame
TR.tick(1/60)
T.check(not pcall(r.syncGen3Palettes,r),"upload failure propagates")
T.eq(surfaceReleases,releasedBefore+1,"failed upload releases its temporary surface")
T.eq(rec.tiles.animFrame,frameBefore,"failed bake restores animation selection")
T.eq(TR.gen3PaletteCacheStats().entries,4,"failed picture is never cached")
rec.bottom.replacePixels=savedUpload
releasedBefore=surfaceReleases
TR.releaseGen3Sheets()
T.eq(TR.gen3PaletteCacheStats().bytes,0,"source/cache reset releases all CPU atlas bytes")
T.eq(TR.gen3PaletteCacheStats().entries,0,"source/cache reset drops prior colour pictures")
T.eq(surfaceReleases-releasedBefore,4*(rec.cover and 3 or 2),"reset releases every cached layer once")
local fresh=assert(TR.gen3SheetsFor(f.state.map.tileset,f.state.game.data,f.state.game.data.constants.gen3Layout))
T.check(fresh~=rec,"source reset creates a new owner even with the same tileset id")
T.eq(TR.gen3PaletteCacheStats().entries,1,"source rebuild primes only its own current picture")
TR.invalidate()
T.eq(TR.gen3PaletteCacheStats().bytes,0,"asset invalidation also releases CPU picture storage")
T.eq(TR.gen3PaletteCacheStats().entries,0,"asset invalidation cannot retain source pictures")
T.check(fresh.bottom.bytes~=nil,"asset invalidation preserves live GPU resources")
f.run.release()
love.image=original.image
for _,name in ipairs({"newImage","newCanvas","draw","clear"}) do love.graphics[name]=original[name] end
T.finish("Native palette sheet, batch, border and reflection refresh")
