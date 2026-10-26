-- Bounded validation and canonical range reads shared by import UIs and mods.
local MD5
local function digest() MD5=MD5 or require("src.mods.StreamMD5");return MD5.new() end
local Files = { CHUNK_BYTES=1024*1024, MAX_READ_BYTES=8*1024*1024 }
local memo = setmetatable({}, {__mode="k"})

local function integer(n)
  return type(n)=="number" and n==n and n>=0 and n<math.huge and n%1==0
end

local function dated(info)
  local n=info and info.modtime
  return type(n)=="number" and n==n and n>=0 and n<math.huge
end

local function open(fs,path)
  if not (fs and fs.newFile) then return nil,"bounded file access is unavailable" end
  local called,file,err=pcall(fs.newFile,path)
  if not called then return nil,tostring(file) end
  if not file then return nil,err or "could not open import" end
  local opened,ok,why=pcall(file.open,file,"r")
  if not opened then pcall(file.close,file);return nil,tostring(ok) end
  if not ok then pcall(file.close,file);return nil,why or "could not open import" end
  return file
end

function Files.range(fs,path,offset,length,size)
  if not integer(offset) or not integer(length) then return nil,"invalid import range" end
  if length>Files.MAX_READ_BYTES then return nil,"single import read exceeds 8 MiB" end
  if size and offset+length>size then return nil,"import read is out of bounds" end
  if length==0 then return "" end
  local data,err
  if fs.readRange then
    local ok,result,detail=pcall(fs.readRange,path,offset,length)
    if not ok then return nil,tostring(result) end
    data,err=result,detail
  elseif fs.newFile then
    local file,why=open(fs,path)
    if not file then return nil,why end
    local ok,result,detail=pcall(function()
      local at,seekErr=file:seek(offset)
      if at==nil or at==false then return nil,seekErr or "could not seek import" end
      return file:read(length)
    end)
    pcall(file.close,file)
    if not ok then return nil,tostring(result) end
    data,err=result,detail
  elseif fs.read and size and size<=Files.MAX_READ_BYTES then
    local body=fs.read(path)
    if type(body)=="string" then data=body:sub(offset+1,offset+length) end
  else
    return nil,"bounded file access is unavailable"
  end
  if type(data)~="string" then return nil,err or "could not read import" end
  if #data~=length then return nil,"short import read" end
  return data
end

local function swap(data,width)
  if width==2 then return (data:gsub("(.)(.)","%2%1")) end
  if width==4 then return (data:gsub("(.)(.)(.)(.)","%4%3%2%1")) end
  return data
end

function Files.layout(entry,fs,path,info)
  local size=info and tonumber(info.size)
  if not integer(size) or size==0 then return nil,"import size is unavailable or empty" end
  local offset,width=0,1
  if entry.format=="n64" then
    local prefix,err=Files.range(fs,path,0,math.min(size,516),size)
    if not prefix then return nil,err end
    local kinds={["\128\55\18\64"]=1,["\55\128\64\18"]=2,["\64\18\55\128"]=4}
    width=kinds[prefix:sub(1,4)]
    if not width then offset=512;width=kinds[prefix:sub(513,516)] end
    if not width then return nil,"unrecognized N64 signature" end
    if (size-offset)%width~=0 then return nil,"unaligned N64 source" end
  end
  local logical=size-offset
  if entry.size and logical~=entry.size then return nil,"import size does not match declaration" end
  if entry.max_size and logical>entry.max_size then return nil,"import exceeds max_size" end
  return {size=logical,physicalSize=size,offset=offset,width=width,modtime=info.modtime}
end

function Files.canonicalRange(fs,path,layout,offset,length)
  if not integer(offset) or not integer(length) then return nil,"offset and length must be non-negative integers" end
  if length>Files.MAX_READ_BYTES then return nil,"single import read exceeds 8 MiB" end
  if offset+length>layout.size then return nil,"import read is out of bounds" end
  if length==0 then return "" end
  local width=layout.width or 1
  local first=math.floor(offset/width)*width
  local last=math.ceil((offset+length)/width)*width
  -- Alignment can add at most six bytes. Split the maximum-size case so no
  -- physical read exceeds the public bound either.
  local data,err=Files.range(fs,path,layout.offset+first,math.min(last-first,Files.MAX_READ_BYTES),layout.physicalSize)
  if not data then return nil,err end
  if last-first>#data then
    local tail,why=Files.range(fs,path,layout.offset+first+#data,last-first-#data,layout.physicalSize)
    if not tail then return nil,why end
    data=data..tail
  end
  return swap(data,width):sub(offset-first+1,offset-first+length)
end

local function accepted(entry,digest)
  if not entry.md5 then return true end
  for _,one in ipairs(entry.md5s or {entry.md5}) do if one==digest then return true end end
  return false
end
Files.accepted = accepted
Files.swap = swap

local function signature(entry,fs,path,layout)
  if not entry.magic then return true end
  local length=0
  for _,hex in ipairs(entry.magic) do length=math.max(length,#hex/2) end
  local at=entry.magicOffset or 0
  local bytes,err=Files.range(fs,path,at,length,layout.physicalSize)
  if not bytes then return nil,err end
  local hex=bytes:gsub(".",function(c)return ("%02x"):format(c:byte())end)
  for _,wanted in ipairs(entry.magic) do if hex:sub(1,#wanted)==wanted then return true end end
  return nil,"import signature does not match declaration"
end

local function receiptPath(path)
  return "imports/validated/"..digest():update(path):final()..".txt"
end

local function storedDigest(entry,fs,path,info)
  if not (dated(info) and fs.read) then return nil end
  local receipt=receiptPath(path)
  local stat=fs.getInfo(receipt,"file")
  if not stat or not stat.size or stat.size>256 then return nil end
  local data=fs.read(receipt)
  if type(data)~="string" then return nil end
  local digest,size,time=data:match("^v1\n(%x+)\n(%d+)\n([^\n]+)\n$")
  if digest and #digest==32 and tonumber(size)==info.size and tonumber(time)==info.modtime and accepted(entry,digest) then return digest end
end

local function hash(entry,fs,path,layout)
  local context=digest()
  for at=0,layout.size-1,Files.CHUNK_BYTES do
    local data,err=Files.canonicalRange(fs,path,layout,at,math.min(Files.CHUNK_BYTES,layout.size-at))
    if not data then return nil,err end
    context:update(data)
  end
  return context:final()
end

function Files.record(entry,fs,path,value)
  local info=fs.getInfo(path,"file")
  local layout,err=Files.layout(entry,fs,path,info)
  if not layout then return nil,err end
  local ok,why=signature(entry,fs,path,layout)
  if not ok then return nil,why end
  if entry.verify=="mod" then layout.verified="mod"
  elseif entry.md5 then
    if not value or not accepted(entry,value) then return nil,"import MD5 mismatch" end
    layout.verified,layout.md5="md5",value
    if dated(info) and fs.write then
      if fs.createDirectory then pcall(fs.createDirectory,"imports/validated") end
      pcall(fs.write,receiptPath(path),("v1\n%s\n%d\n%s\n"):format(value,info.size,tostring(info.modtime)))
    end
  else layout.verified="size" end
  return layout
end

function Files.validate(entry,fs,path,force)
  if not (fs and fs.getInfo and path) then return nil,"filesystem is unavailable" end
  local info=fs.getInfo(path,"file")
  if not info or info.type=="directory" then return nil,"import is missing" end
  local key=table.concat({entry.format or "raw",entry.verify or "",entry.md5 or "",table.concat(entry.md5s or {},","),
    tostring(entry.size),tostring(entry.max_size),table.concat(entry.magic or {},","),tostring(entry.magicOffset)},"|")
  local cache=memo[fs]
  local cached=cache and cache[path]
  if not force and dated(info) and cached and cached.size==info.size and cached.time==info.modtime and cached.key==key then return cached.layout end
  local layout,err=Files.layout(entry,fs,path,info)
  if not layout then return nil,err end
  local valid,why=signature(entry,fs,path,layout)
  if not valid then return nil,why end
  if entry.verify=="mod" then layout.verified="mod"
  elseif entry.md5 then
    local digest=not force and storedDigest(entry,fs,path,info) or nil
    local fromReceipt=digest~=nil
    if not digest then digest,err=hash(entry,fs,path,layout) end
    if not digest then return nil,err end
    if not accepted(entry,digest) then return nil,"import MD5 mismatch" end
    layout.md5,layout.verified=digest,"md5"
    if not fromReceipt and dated(info) and fs.write then
      if fs.createDirectory then pcall(fs.createDirectory,"imports/validated") end
      pcall(fs.write,receiptPath(path),("v1\n%s\n%d\n%s\n"):format(digest,info.size,tostring(info.modtime)))
    end
  else layout.verified="size" end
  local after=fs.getInfo(path,"file")
  if not after or after.size~=info.size or after.modtime~=info.modtime then return nil,"import changed during validation" end
  memo[fs]=cache or {};memo[fs][path]={size=info.size,time=info.modtime,key=key,layout=layout}
  return layout
end

function Files.invalidate(fs,path)
  if memo[fs] then memo[fs][path]=nil end
  if fs.remove then pcall(fs.remove,receiptPath(path)) end
end

return Files
