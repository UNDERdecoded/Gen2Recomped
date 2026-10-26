-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local G=require("src.import.snes.Graphics")
local O={}
local function byte(rom,at)return assert(rom:byte(at+1),"truncated overworld data")end
local function word(rom,at)return byte(rom,at)+byte(rom,at+1)*256 end
function O.sheets(rom,area)
  local group=area<64 and 32 or 33
  local auxiliary=byte(rom,0x7c9c+area)
  local out={}
  for slot=0,7 do
    local index=byte(rom,0x6073+group*8+slot)
    if slot>=3 and slot<=6 then
      local override=byte(rom,0x5d97+auxiliary*4+slot-3)
      if override~=0 then index=override end
    end
    out[slot+1]=index
  end
  return out
end
function O.palettes(rom,area)
  local group=byte(rom,0x7d1c+area)
  local selectors={byte(rom,0x75504+group*4),byte(rom,0x75505+group*4),byte(rom,0x75506+group*4)}
  local result={}
  local function install(row,column,address)
    local colors=assert(G.readPalette(rom,address,7))
    result[row]=result[row] or {}
    for i=1,7 do result[row][column+i-1]=colors[i] end
  end
  local main=area<64 and 0 or 1
  local mainOffset=word(rom,0xdec3b+main*2)
  for row=2,6 do install(row,1,0xde6c8+mainOffset+(row-2)*14) end
  local first=word(rom,0xdec13+selectors[1]*2)
  local second=word(rom,0xdec13+selectors[2]*2)
  for row=2,4 do install(row,9,0xde86c+first+(row-2)*14) end
  for row=5,7 do install(row,9,0xde86c+second+(row-5)*14) end
  install(7,1,0xde604+byte(rom,0xdebc6+selectors[3]))
  return result
end
function O.raster(rom,readSheet,progress)
  local area=0x18
  local sheets={}
  for slot,index in ipairs(O.sheets(rom,area)) do sheets[slot]=assert(readSheet(rom,index)) end
  local palettes=O.palettes(rom,area)
  local rgb={G.color(0x2669)}
  local background=string.char(math.floor(rgb[1]+0.5),math.floor(rgb[2]+0.5),math.floor(rgb[3]+0.5),255)
  local packed={}
  for row,colors in pairs(palettes) do
    packed[row]={}
    for index,c in pairs(colors) do packed[row][index]=string.char(c[1],c[2],c[3],255) end
  end
  local high={[0]=true,[3]=true,[4]=true,[5]=true}
  local pixels={}
  for definition=0,4095 do
    local tx,ty=definition%64*16,math.floor(definition/64)*16
    for quadrant=0,3 do
      local descriptor=word(rom,0x78000+definition*8+quadrant*2)
      local tileIndex=descriptor%1024
      local slot=math.floor(tileIndex/64)
      local tile=sheets[slot+1] and sheets[slot+1][tileIndex%64+1]
      local palette=packed[math.floor(descriptor/1024)%8]
      local flipX,flipY=math.floor(descriptor/16384)%2==1,descriptor>=32768
      for y=0,7 do
        for x=0,7 do
          local sx,sy=flipX and 7-x or x,flipY and 7-y or y
          local index=tile and tile[sy*8+sx+1] or 0
          local color=index~=0 and palette and palette[index+(high[slot] and 8 or 0)] or nil
          local dx,dy=tx+quadrant%2*8+x,ty+math.floor(quadrant/2)*8+y
          pixels[dy*1024+dx+1]=color or background
        end
      end
    end
    if progress and definition%128==127 then progress(definition+1,4096) end
  end
  return {width=1024,height=1024,rgba=table.concat(pixels)}
end
function O.image(rom,readSheet)
  local result=O.raster(rom,readSheet)
  return love.image.newImageData(result.width,result.height,"rgba8",result.rgba)
end
return O
