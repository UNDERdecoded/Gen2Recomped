-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local G={TILE_PIXELS=8}
local floor=math.floor
function G.loRomOffset(bank,high,low)
  if type(bank)~="number" or type(high)~="number" or type(low)~="number" then return nil end
  if bank<0 or bank>255 or high<128 or high>255 or low<0 or low>255
      or bank%1~=0 or high%1~=0 or low%1~=0 then return nil end
  return bank%128*32768+(high*256+low)%32768
end
function G.color(word)
  return word%32*255/31,floor(word/32)%32*255/31,floor(word/1024)%32*255/31
end
function G.readPalette(bytes,offset,count)
  if type(bytes)~="string" or type(offset)~="number" or offset<0 or offset%1~=0
      or type(count)~="number" or count<0 or count%1~=0 or offset+count*2>#bytes then return nil,"palette is outside the cartridge" end
  local colors={}
  for i=0,count-1 do
    local a,b=bytes:byte(offset+i*2+1,offset+i*2+2)
    local r,g,blue=G.color(a+b*256)
    colors[i+1]={floor(r+0.5),floor(g+0.5),floor(blue+0.5)}
  end
  return colors
end
local function tile(bytes,index,bits)
  local stride=bits*8
  if type(bytes)~="string" or type(index)~="number" or index<0 or index%1~=0
      or (index+1)*stride>#bytes then return nil,"tile is outside the graphics block" end
  local pixels={}
  for y=0,7 do
    for x=0,7 do
      local color=0
      for plane=0,bits-1 do
        local position
        if bits==3 and plane==2 then position=16+y
        else position=floor(plane/2)*16+y*2+plane%2 end
        local byte=bytes:byte(index*stride+position+1)
        color=color+floor(byte/2^(7-x))%2*2^plane
      end
      pixels[y*8+x+1]=color
    end
  end
  return pixels
end
function G.decodeTile2bpp(bytes,index)return tile(bytes,index,2)end
function G.decodeTile3bpp(bytes,index)return tile(bytes,index,3)end
function G.decodeTile4bpp(bytes,index)return tile(bytes,index,4)end
function G.decodeTiles(bytes,bits)
  if bits~=2 and bits~=3 and bits~=4 then return nil,"unsupported bit-plane format" end
  if type(bytes)~="string" or #bytes==0 or #bytes%(bits*8)~=0 then return nil,"incomplete graphics tiles" end
  local out={}
  for i=0,#bytes/(bits*8)-1 do out[i+1]=assert(tile(bytes,i,bits)) end
  return out
end
function G.sheetFormat(size)
  if type(size)~="number" or size<=0 or size>65536 then return nil end
  if size%24==0 then return 3,size/24 end
  if size%16==0 then return 2,size/16 end
end
function G.decodeSheet(bytes)
  local bits=type(bytes)=="string" and G.sheetFormat(#bytes)
  if not bits then return nil,"unsupported graphics sheet length" end
  local pixels,err=G.decodeTiles(bytes,bits)
  if not pixels then return nil,err end
  return pixels,bits
end
function G.sheet(tiles,palette,columns)
  columns=columns or 16
  local width,height=columns*8,math.ceil(#tiles/columns)*8
  assert(width>0 and height>0 and width*height<=4*1024*1024,"graphics sheet exceeds image bounds")
  local colors={[0]=string.char(0,0,0,0)}
  for i,rgb in ipairs(palette) do colors[i]=string.char(rgb[1],rgb[2],rgb[3],255) end
  local rows={}
  for y=0,height-1 do
    local pixels={}
    for x=0,width-1 do
      local source=tiles[floor(y/8)*columns+floor(x/8)+1]
      local index=source and source[y%8*8+x%8+1] or 0
      pixels[x+1]=assert(colors[index],"graphics palette is incomplete")
    end
    rows[y+1]=table.concat(pixels)
  end
  return {width=width,height=height,rgba=table.concat(rows)}
end
return G
