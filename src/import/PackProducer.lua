-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native extractors publish immutable objects and switch the descriptor only
-- once their complete result is ready. Cancellation never replaces a pack.
local Importers=require("src.import.Importers")
local Data=require("src.import.PackData")
local Writer=require("src.import.LuaWriter")
local MD5=require("src.mods.StreamMD5")
local Producer={}
local publish=require("src.import.PackPublish")

local function literal(value)
  local ok,bytes=pcall(Writer.encode,value)
  if not ok then return nil,tostring(bytes) end
  if #bytes>Data.MAX_BYTES then return nil,"pack data exceeds the read limit" end
  local decoded,err=Data.decode(bytes)
  if not decoded then return nil,err end
  return decoded,bytes
end

function Producer.new(id,pack,version,source,fs)
  local descriptor=Importers.pack(id,pack)
  if not descriptor then return nil,"unknown asset pack" end
  local normalized,err=literal(source)
  if not normalized then return nil,err end
  local manifest={format=Importers.PACK_FORMAT,importer=id,pack=pack,
    kind=descriptor.kind,version=version,source=normalized,entries={}}
  local valid; valid,err=Importers.validatePack(manifest,id,pack)
  if not valid then return nil,err end
  fs=Importers.fs(fs)
  if not (fs and fs.write and fs.rename and fs.remove) then return nil,"atomic pack publication is unavailable" end
  local state,count="open",0
  local scope=Importers.pinScope(fs)
  local root=assert(Importers.packRoot(id,pack))
  local api={}
  local function object(bytes,extension)
    if type(bytes)~="string" or #bytes>Importers.MAX_ENTRY_BYTES then return nil,"asset exceeds the pack read limit" end
    local file="objects/"..MD5.new():update(bytes):final().."."..extension
    local path=root.."/"..file
    if Data.read(fs,path,#bytes)~=bytes then
      local ok,why=publish(fs,path,bytes);if not ok then return nil,why end
    end
    return {file=file,size=#bytes}
  end
  local function refuse(reason)
    state="failed";return nil,reason
  end
  function api:put(key,bytes,attributes,metadata,extension)
    if state~="open" then return nil,"pack producer is "..state end
    local inScope,scopeError=scope();if not inScope then return refuse(scopeError) end
    if count>=20000 then return refuse("pack entry count limit") end
    if type(key)~="string" or not key:match("^[a-z0-9_%-]+[a-z0-9_/%-]*$") or #key>512 then
      return refuse("invalid native pack entry identity")
    end
    if manifest.entries[key] then return refuse("duplicate native pack entry") end
    local attrs,why=literal(attributes or {})
    if not attrs then return refuse(why) end
    extension=extension or (manifest.kind=="palette" and "lua" or "png")
    if not (Importers.KINDS[manifest.kind].ext[extension]) then return refuse("asset extension does not match pack kind") end
    attrs.file,attrs.size="entry."..extension,type(bytes)=="string" and #bytes or -1
    local metadataBytes
    if metadata~=nil then
      local decoded;decoded,metadataBytes=literal(metadata)
      if not decoded then return refuse(metadataBytes) end
      attrs.metadata={file="metadata.lua",size=#metadataBytes}
    else attrs.metadata=nil end
    local probe={format=manifest.format,importer=id,pack=pack,kind=manifest.kind,
      version=version,source=manifest.source,entries={[key]=attrs}}
    local checked;checked,why=Importers.validatePack(probe,id,pack)
    if not checked then return refuse(why) end
    local stored;stored,why=object(bytes,extension)
    if not stored then return refuse(why) end
    attrs.file,attrs.size=stored.file,stored.size
    if metadataBytes then
      attrs.metadata,why=object(metadataBytes,"lua")
      if not attrs.metadata then return refuse(why) end
    end
    manifest.entries[key]=attrs;count=count+1
    return Data.copy(attrs)
  end
  function api:alias(key,existing)
    if state~="open" then return nil,"pack producer is "..state end
    local inScope,scopeError=scope();if not inScope then return refuse(scopeError) end
    if count>=20000 then return refuse("pack entry count limit") end
    if manifest.entries[key] or not manifest.entries[existing] then return refuse("invalid native pack alias") end
    if type(key)~="string" or not key:match("^[a-z0-9_%-]+[a-z0-9_/%-]*$") or #key>512 then
      return refuse("invalid native pack entry identity")
    end
    manifest.entries[key]=Data.copy(manifest.entries[existing]);count=count+1
    return Data.copy(manifest.entries[key])
  end
  function api:finish()
    if state~="open" then return nil,"pack producer is "..state end
    local inScope,scopeError=scope();if not inScope then return refuse(scopeError) end
    if count==0 then return refuse("native extraction produced no entries") end
    local valid,why=Importers.validatePack(manifest,id,pack)
    if not valid then return refuse(why) end
    -- Recheck files at the publication boundary; an interrupted or externally
    -- removed object must not turn a required pack into a ready one.
    for _,entry in pairs(manifest.entries) do
      for _,rec in ipairs({entry,entry.metadata or false}) do
        if rec then
          local info=fs.getInfo and fs.getInfo(root.."/"..rec.file,"file")
          if not info or info.type~="file" or info.size~=rec.size then return refuse("native pack object is missing or changed") end
        end
      end
    end
    local normalized,encoded=literal(manifest)
    if not normalized then return refuse(encoded) end
    local ok;ok,why=publish(fs,assert(Importers.manifestPath(id,pack)),encoded)
    if not ok then return refuse(why) end
    state="published";Importers.invalidate(fs,id,pack)
    return {importer=id,pack=pack,version=version,entries=count}
  end
  function api:cancel() if state=="open" then state="cancelled" end end
  function api:state() return state end
  return api
end
return Producer
