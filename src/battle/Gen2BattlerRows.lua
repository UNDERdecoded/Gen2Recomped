-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- GSC copies enemy feet / player head from BG picture tiles into OBJ VRAM.
-- Snapshot at the real battlergfx command; drawing never rereads live art.
local Assets=require('src.render.Assets')
local M={}
function M.snapshot(source,entry)
  if not(source and source.path and love.image and love.image.newImageData)then return end
  local shared=Assets.imageDataShared
  local raw=(shared or Assets.imageData)(source.path)
  local w,h=raw:getDimensions()
  local x0=0
  if source.crop then w=source.crop.width;x0=(source.crop.index-1)*w end
  if w<=0 or h<=0 then return end
  local back=entry.battler=='player'
  local size=back and 48 or 56
  -- Native fronts are 5/6/7 tiles. PadFrontpic puts both smaller sizes
  -- one tile from the left and bottom-aligns them in the seven-tile box.
  -- Replacement sheets already contain their full box. Custom larger art
  -- is sampled into the same logical OBJ cells, preserving its own alpha.
  local lw,lh=size,size
  if not back and (w==40 or w==48)then lw=w end
  if not back and (h==40 or h==48)then lh=h end
  local left=lw<size and 8 or 0
  local top=size-lh
  local cols,rows=size/8,entry.rows
  local out=love.image.newImageData(size,rows*8)
  local start=back and 0 or size-rows*8
  for y=0,rows*8-1 do for x=0,size-1 do
    local px,py=x-left,start+y-top
    if px>=0 and py>=0 and px<lw and py<lh then
      local r,g,b,a=raw:getPixel(x0+math.floor(px*w/lw),math.floor(py*h/lh))
      -- OBJ colour zero is transparent before OBP remapping, even if an
      -- indexed input has an opaque BG paper colour. RGB custom art opts out.
      if not source.trueColor and r>0.83 then a=0 end
      out:setPixel(x,y,r,g,b,a)
    end
  end end
  local image=love.graphics.newImage(out)
  if out.release then out:release()end
  if not shared and raw.release then raw:release()end
  image:setFilter('nearest','nearest')
  return {image=image,rows=rows,cols=cols,trueColor=source.trueColor,quads={}}
end
function M.quad(snapshot,index)
  if index<0 or index>=snapshot.rows*snapshot.cols then return end
  if not snapshot.quads[index]then
    snapshot.quads[index]=love.graphics.newQuad(math.floor(index/snapshot.rows)*8,
      (index%snapshot.rows)*8,8,8,snapshot.cols*8,snapshot.rows*8)
  end
  return snapshot.quads[index]
end
return M
