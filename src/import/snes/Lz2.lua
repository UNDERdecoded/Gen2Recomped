-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- SNES graphics command stream: literal, byte/word fill, ascending fill and
-- absolute output copies. Graphics copy offsets are little endian.
local Lz={MAX_OUTPUT=65536}
local unpack=table.unpack or unpack
function Lz.decompress(bytes,offset,limit)
  if type(bytes)~="string" or type(offset)~="number" or offset<0 or offset%1~=0 then return nil,"invalid compressed graphics source" end
  limit=limit or Lz.MAX_OUTPUT
  if type(limit)~="number" or limit<0 or limit>Lz.MAX_OUTPUT or limit%1~=0 then return nil,"invalid graphics expansion limit" end
  local p=offset+1
  local output={}
  local function nextByte()
    local value=bytes:byte(p);p=p+1
    if not value then error("truncated compressed graphics",0) end
    return value
  end
  local ok,body=pcall(function()
    while true do
      local head=nextByte()
      if head==255 then break end
      local command,length
      if head>=224 then
        command=math.floor(head/4)%8
        length=(head%4)*256+nextByte()+1
      else command=math.floor(head/32);length=head%32+1 end
      if #output+length>limit then error("graphics expansion exceeds its limit",0) end
      if command==0 then
        for _=1,length do output[#output+1]=nextByte() end
      elseif command==1 then
        local byte=nextByte();for _=1,length do output[#output+1]=byte end
      elseif command==2 then
        local a,b=nextByte(),nextByte()
        for i=1,length do output[#output+1]=i%2==1 and a or b end
      elseif command==3 then
        local first=nextByte();for i=0,length-1 do output[#output+1]=(first+i)%256 end
      else
        local low=nextByte();local start=low+256*nextByte()
        if start>=#output then error("graphics copy points outside prior output",0) end
        for i=1,length do output[#output+1]=assert(output[start+i],"invalid graphics copy") end
      end
    end
    local chunks={}
    for first=1,#output,4096 do
      chunks[#chunks+1]=string.char(unpack(output,first,math.min(first+4095,#output)))
    end
    return table.concat(chunks)
  end)
  if not ok then return nil,tostring(body) end
  return body,p-offset-1
end
return Lz
