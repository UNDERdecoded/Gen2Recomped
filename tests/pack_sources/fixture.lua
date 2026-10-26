-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Generated format vectors; no cartridge bytes or extracted graphics.
local F={}
function F.memory(initial)
  local data,times={},{};local clock=0
  for p,b in pairs(initial or {}) do data[p]=b;times[p]=0 end
  local fs={maxRead=0,writes=0}
  function fs.getInfo(p,kind)
    if data[p] then return {type='file',size=#data[p],modtime=times[p]} end
    if kind~='file' then for key in pairs(data) do if key:sub(1,#p+1)==p..'/' then return {type='directory'} end end end
  end
  function fs.read(p,n)return data[p] and data[p]:sub(1,n or -1)end
  function fs.readRange(p,at,n)fs.maxRead=math.max(fs.maxRead,n);return data[p] and data[p]:sub(at+1,at+n)end
  function fs.write(p,b)
    fs.writes=fs.writes+1
    if fs.failWrite then return nil,'injected write failure' end
    clock=clock+1;data[p]=fs.shortWrite and b:sub(1,1) or b;times[p]=clock;return true
  end
  function fs.rename(a,b)
    if fs.throwRename then error('injected replacement exception') end
    if fs.failRename then return nil,'injected replacement failure' end
    if not data[a] then return nil,'missing staging data' end
    clock=clock+1;data[b],times[b]=data[a],clock;data[a],times[a]=nil,nil;return true
  end
  function fs.createDirectory()return not fs.failDirectory end
  function fs.remove(p)data[p],times[p]=nil,nil;return true end
  return fs,data
end
function F.cartridge()
  local patches={}
  local function add(at,bytes)patches[#patches+1]={at=at,bytes=bytes}end
  local function word(n)return string.char(n%256,math.floor(n/256))end
  local banks,highs,lows={},{},{}
  for i=0,222 do
    local at=i>=115 and i<=126 and 0x93000 or 0x92000
    banks[#banks+1]=string.char(math.floor(at/32768))
    highs[#highs+1]=string.char(128+math.floor(at%32768/256))
    lows[#lows+1]=string.char(at%256)
  end
  add(0x4f80,table.concat(banks));add(0x505f,table.concat(highs));add(0x513e,table.concat(lows))
  local raw=string.char(128)..string.rep('\0',1535)
  add(0x92000,string.char(0xe3,255)..raw:sub(1,1024)..string.char(0xe1,255)..raw:sub(1025)..string.char(255))
  add(0x93000,raw)
  add(0x80000,string.rep('\0',17)..string.char(128)..string.rep('\0',0x7000-18))
  for _,spec in ipairs({{0xdd218,60,31},{0xdd290,60,31},{0xdd308,75,31},
      {0xdd39e,84,31},{0xdd734,240,992},{0xde604,84,31}}) do
    local colors={}
    for i=1,spec[2] do colors[i]=word(spec[1]==0xdd308 and i==8 and 31744 or spec[3]) end
    add(spec[1],table.concat(colors))
  end
  add(0xde86c,word(31)..string.rep('\0',40))
  add(0x78000,word(0x0800)..word(0x4800)..word(0x8800)..word(0xc800))
  table.sort(patches,function(a,b)return a.at<b.at end)
  local chunks,at={},0
  for _,p in ipairs(patches) do
    assert(p.at>=at,'overlapping generated test vectors')
    chunks[#chunks+1]=string.rep('\0',p.at-at);chunks[#chunks+1]=p.bytes;at=p.at+#p.bytes
  end
  chunks[#chunks+1]=string.rep('\0',1048576-at)
  return table.concat(chunks)
end
return F
