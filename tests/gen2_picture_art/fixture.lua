-- CPU image storage for genuine import/bake pixels, not a drawing substitute.
local F={}
function F.image(w,h)
  local out={w=w,h=h,pixels={}}
  function out:getWidth()return self.w end
  function out:getHeight()return self.h end
  function out:getDimensions()return self.w,self.h end
  function out:setPixel(x,y,...)
    assert(x>=0 and x<self.w and y>=0 and y<self.h,'pixel outside image')
    self.pixels[y*self.w+x]={...}
  end
  function out:getPixel(x,y)return unpack(self.pixels[y*self.w+x]or{0,0,0,0})end
  function out:mapPixel(fn)
    for y=0,self.h-1 do for x=0,self.w-1 do self:setPixel(x,y,fn(x,y,self:getPixel(x,y)))end end
  end
  function out:clone()
    local copy=F.image(self.w,self.h)
    for y=0,self.h-1 do for x=0,self.w-1 do copy:setPixel(x,y,self:getPixel(x,y))end end
    return copy
  end
  function out:rgba8()
    local bytes={}
    for y=0,self.h-1 do for x=0,self.w-1 do
      for _,c in ipairs({self:getPixel(x,y)})do bytes[#bytes+1]=string.char(math.floor(c*255+.5))end
    end end
    return table.concat(bytes)
  end
  function out:setFilter()end
  function out:release()end
  return out
end
-- Distinct artificial tiles, deliberately asymmetric in both directions.
function F.tile(seed)
  local raw={}
  for y=0,7 do
    local lo,hi=0,0
    for x=0,7 do
      local shade=(seed+x+2*y)%4
      lo=lo+(shade%2)*2^(7-x);hi=hi+math.floor(shade/2)*2^(7-x)
    end
    raw[#raw+1]=lo;raw[#raw+1]=hi
  end
  return raw
end
function F.extractor(version,change)
  local E=require('src.import.RomExtractorGen2')
  local symbols={MonsterSpriteGFX={1,0x5000},MinimizePic={1,0x6000}}
  if version=='crystal'or version=='prism'then
    symbols.BattleAnimCmd_UpdateActorPic={1,0x6200}
    symbols.BattleAnimCmd_Minimize={1,0x6300}
  end
  local raw={}
  for i=0,7 do for j,value in ipairs(F.tile(i))do raw[0x5000+i*16+j-1]=value end end
  for i,value in ipairs(F.tile(3))do raw[0x6000+i-1]=value end
  if change then change(symbols,raw)end
  local e=E.new(nil,version,{symbols=symbols});local images={}
  e.rom={bytes=function(_,bank,address,count)
    assert(bank==1)
    local out={};for i=0,count-1 do out[#out+1]=assert(raw[address+i],'outside fixture ROM')end
    return out
  end}
  e.saveImage=function(_,image,path)images['assets/generated/'..path]=image end
  return e,images
end
return F
