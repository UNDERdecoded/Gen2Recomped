-- Berry parameters and watch-map positions, read from Platinum's ROM.
local B = {}
B.PATH = '/itemtool/itemdata/nuts_data.narc'
B.PATCH_COUNT = 118
function B.mapCells(archive)
  local A=require('src.import.Gen4Archives')
  local G=require('src.import.Gen4Graphics')
  local id=A.find('/graphic/poketch.narc','map_anim.NANR.lz')
  local bytes=id and archive:get(id)
  if bytes and G.isCompressed(bytes) then bytes=G.decompress(bytes) end
  local container=G.container(bytes or '')
  local section=container and container.sections.KNBA
  if not section then return nil end
  local d,base=container.data,section.body
  local function u16(at)
    local a,b=d:byte(at,at+1)
    return b and a+b*256
  end
  local function u32(at)
    local a,b=u16(at),u16(at+2)
    return a and b and a+b*65536
  end
  local sequences,frames,results=u32(base+4),u32(base+8),u32(base+12)
  if not results or u16(base)<8 then return nil end
  -- Index, SRT and translation results all start with a u16 cell index.
  -- Only the static first cell is used here; the transform is not animated.
  local function cell(sequence)
    local offset=u32(base+sequences+sequence*16+12)
    local result=offset and u32(base+frames+offset)
    return result and u16(base+results+result)
  end
  local berry,cursor=cell(7),cell(0)
  if not (berry and cursor) then return nil end
  local out={berry=berry,cursor=cursor,markers={},markerBig={}}
  if u16(base)>=19 then
    out.roamer=cell(18)
    for i=1,6 do out.markers[i]=cell(i); out.markerBig[i]=cell(i+7) end
  end
  return out
end
function B.growth(archive)
  local out = {}
  if not archive or archive.count ~= 64 then return nil end
  for i=0,63 do
    local bytes=archive:get(i)
    if not bytes or #bytes<12 then return nil end
    local yield,hours,drain=bytes:byte(4,6)
    if yield<1 or hours<1 or hours>96 or drain>100 then return nil end
    out[149+i]={baseYield=yield,stageHours=hours,drain=drain}
  end
  return out
end
-- THE POFFIN HALF of the same records (BerryData: u16 size, firmness, yield,
-- stage hours, drain, then spicy/dry/sweet/bitter/sour and smoothness --
-- bytes 7..12), which the cooking result reads (ov83_0223F7F4).
function B.flavors(archive)
  if not archive or archive.count ~= 64 then return nil end
  local out = {}
  for i = 0, 63 do
    local bytes = archive:get(i)
    if not bytes or #bytes < 12 then return nil end
    local a, b, c, d, e, smooth = bytes:byte(7, 12)
    out[149 + i] = { flavors = { a, b, c, d, e }, smoothness = smooth }
  end
  return out
end
function B.positions(rom)
  local anchor='\5\20\5\20\6\20\6\20\6\19\6\19\7\17\7\17'
  local found,hits=nil,0
  for id=0,rom:header().overlays9-1 do
    local bytes=rom:overlay(id)
    local at=bytes and bytes:find(anchor,1,true)
    if at then
      local out,valid={},true
      for i=0,B.PATCH_COUNT-1 do
        local x,y=bytes:byte(at+i*2,at+i*2+1)
        if not y or x>30 or y>30 then valid=false; break end
        out[i]={x=x,y=y}
      end
      if valid then found,hits=out,hits+1 end
    end
  end
  return hits==1 and found or nil
end
function B.initial(rom)
  local anchor='\155\0\1\0\149\0\1\0\150\0\1\0\151\0\1\0'
  local found,hits=nil,0
  local function scan(bytes)
    local at=bytes and bytes:find(anchor,1,true)
    if not at then return end
    local out={}
    for i=0,B.PATCH_COUNT-1 do
      local item,pad,quantity,high=bytes:byte(at+i*4,at+i*4+3)
      if not high or pad~=0 or high~=0 or item<149 or item>212
        or quantity<1 or quantity>5 then return end
      out[i]={item=item,yield=quantity}
    end
    found,hits=out,hits+1
  end
  scan(rom:arm9())
  for id=0,rom:header().overlays9-1 do scan(rom:overlay(id)) end
  return hits==1 and found or nil
end
return B
