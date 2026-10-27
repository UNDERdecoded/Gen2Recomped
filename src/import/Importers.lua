-- Shared, cartridge-derived asset packs. Providers publish data; consumers
-- only see packs explicitly declared by their mod. No game assets ship here.
local Data = require("src.import.PackData")
local Semver = require("src.mods.Semver")
local Writer = require("src.import.LuaWriter")
local MD5 = require("src.mods.StreamMD5")
local Importers = { ROOT="asset_packs", PACK_FILE="pack.lua", PACK_FORMAT=1,
  MAX_ENTRY_BYTES=Data.MAX_BYTES }
Importers.KINDS = {
  sprite={ext={png=true}}, tileset={ext={png=true}}, palette={ext={png=true,lua=true}},
  font={ext={png=true}}, sfx={ext={wav=true,ogg=true}}, music={ext={wav=true,ogg=true}},
  sample={ext={wav=true,ogg=true}},
}
Importers.STATUS = { planned=true, beta=true, ready=true }
-- This catalogue describes the portable pack identities. ROM extraction
-- services are tracked separately; installing an existing pack is available.
local catalog = {
  {id="gen5_bw",name="Black / White",status="beta",
    source={name="Black / White cartridge dump",formats={"nds"},sizes={268435456}},
    packs={{id="battle_sprites",name="Battle sprites",kind="sprite"}}},
  {id="pmd_red",name="Red Rescue Team",status="beta",
    source={name="Red Rescue Team cartridge dump",formats={"gba"},sizes={33554432}},
    packs={{id="sprites",name="Sprite sheets",kind="sprite"}}},
  {id="lttp",name="A Link to the Past",status="beta",module="src.import.lttp.LttpImport",
    source={name="A Link to the Past cartridge dump",formats={"sfc","smc"},sizes={1048576,2097152}},
    packs={{id="sprites",name="Sprites",kind="sprite"},{id="tiles",name="Tiles",kind="tileset"},
      {id="palettes",name="Palettes",kind="palette"},
      {id="sfx",name="Sound effects",kind="sfx",planned=true},
      {id="music",name="Music",kind="music",planned=true}}},
}
local byId = {}; for _, desc in ipairs(catalog) do byId[desc.id] = desc end
local cache = setmetatable({}, {__mode="k"})
local function validId(id) return type(id)=="string" and #id<=128 and id:match("^[a-z0-9_%-]+$")~=nil end
Importers.validId = validId
local function pathInside(file)
  if type(file)~="string" or file=="" or #file>1024 or file:find("[%z\1-\31\\:]")
      or file:sub(1,1)=="/" then return nil end
  local parts={}
  for p in file:gmatch("[^/]+") do
    if p==".." then return nil end
    if p~="." then parts[#parts+1]=p end
  end
  return #parts>0 and table.concat(parts,"/") or nil
end
local function integer(n) return type(n)=="number" and n>=0 and n<math.huge and n%1==0 end
local function ext(path) return (path:match("%.([a-zA-Z0-9]+)$") or ""):lower() end
function Importers.all() return Data.copy(catalog) end
function Importers.get(id) return Data.copy(byId[id]) end
function Importers.pack(id, pack)
  for _, p in ipairs(byId[id] and byId[id].packs or {}) do if p.id==pack then return Data.copy(p) end end
end
function Importers.validateDescriptor(desc)
  if type(desc)~="table" or not validId(desc.id) or type(desc.name)~="string" or desc.name==""
      or not Importers.STATUS[desc.status] or type(desc.source)~="table"
      or type(desc.source.name)~="string" or type(desc.packs)~="table" or #desc.packs==0 then
    return false,"invalid importer descriptor"
  end
  local seen={}
  for _,p in ipairs(desc.packs) do
    if not validId(p.id) or seen[p.id] or not Importers.KINDS[p.kind] or type(p.name)~="string" then
      return false,"invalid pack descriptor"
    end
    seen[p.id]=true
  end
  return true
end
function Importers.packRoot(id,pack)
  if not validId(id) or not validId(pack) then return nil,"invalid pack identity" end
  return Importers.ROOT.."/"..id.."/"..pack
end
function Importers.manifestPath(id,pack)
  local root,err=Importers.packRoot(id,pack); if not root then return nil,err end
  return root.."/"..Importers.PACK_FILE
end
function Importers.assetPath(id,pack,file)
  local root,err=Importers.packRoot(id,pack); if not root then return nil,err end
  local rel=pathInside(file); if not rel then return nil,"asset path must stay inside its pack" end
  return root.."/"..rel
end
function Importers.fs(fs)
  if fs and (not love or fs~=love.filesystem) then return fs end
  return require("src.import.CacheFs").dataFs()
end
-- Long-running pack operations yield to the launcher. A folder switch must
-- stop that operation instead of splitting its objects between two roots.
function Importers.pinScope(fs)
  local getter=fs and fs.getWriteRoot
  local captured=getter and getter()
  return function()
    if getter and getter()~=captured then return nil,"game-data folder changed during the pack operation" end
    return true
  end
end
function Importers.validatePack(m,id,pack)
  if type(m)~="table" or m.format~=Importers.PACK_FORMAT or not validId(m.importer) or not validId(m.pack) then
    return false,"invalid pack manifest identity or format"
  end
  if (id and m.importer~=id) or (pack and m.pack~=pack) then return false,"pack manifest names another pack" end
  local kind=Importers.KINDS[m.kind]
  if not kind or not Semver.parse(m.version or "") then return false,"invalid pack kind or version" end
  if type(m.source)~="table" or type(m.source.md5)~="string" or #m.source.md5~=32
      or m.source.md5:find("[^a-fA-F0-9]") then return false,"pack source needs its cartridge MD5" end
  if type(m.entries)~="table" then return false,"pack entries must be a table" end
  local count, files=0,{}
  local function fileRecord(file,size)
    local rel=pathInside(file)
    if not rel or not integer(size) or size>Importers.MAX_ENTRY_BYTES then return false end
    if files[rel] and files[rel]~=size then return false end
    files[rel]=size; return true
  end
  for key,entry in pairs(m.entries) do
    if type(key)~="string" or not key:match("^[a-z0-9_%-]+[a-z0-9_/%-]*$") or #key>512
        or type(entry)~="table" or not fileRecord(entry.file,entry.size)
        or not kind.ext[ext(entry.file)] then return false,"invalid pack entry: "..tostring(key) end
    if entry.metadata~=nil then
      local meta=entry.metadata
      if type(meta)~="table" or not fileRecord(meta.file,meta.size) or ext(meta.file)~="lua" then
        return false,"invalid entry metadata: "..key
      end
    end
    count=count+1; if count>20000 then return false,"pack entry count limit" end
  end
  return true,nil,count
end
function Importers.invalidate(fs,id,pack)
  -- Providers may use a scoped wrapper over the same writable filesystem.
  -- Invalidate readers of that relative identity as well as the writer.
  local path=Importers.manifestPath(id,pack)
  if path then for _,c in pairs(cache) do c[path]=nil end end
end
function Importers.readPack(id,pack,fs)
  fs=Importers.fs(fs)
  local path,err=Importers.manifestPath(id,pack); if not path then return nil,err end
  local info=fs and fs.getInfo and fs.getInfo(path,"file")
  if not info then return nil,"pack is not installed" end
  local c=cache[fs]; local old=c and c[path]
  local origin=fs.getRealDirectory and fs.getRealDirectory(path)
  -- Timeless injected filesystems are deliberately never memoized.
  if old and type(info.modtime)=="number" and info.modtime>=0 and info.modtime<math.huge and old.size==info.size
      and old.time==info.modtime and old.origin==origin then return old.manifest end
  local bytes,why=Data.read(fs,path); if not bytes then return nil,why end
  local m; m,why=Data.decode(bytes); if not m then return nil,why end
  local ok; ok,why=Importers.validatePack(m,id,pack); if not ok then return nil,why end
  c=c or {}; cache[fs]=c; c[path]={size=info.size,time=info.modtime,origin=origin,manifest=m}
  return m
end
function Importers.resolve(spec,fs)
  if type(spec)~="table" then return nil,"asset requirement must be an object" end
  local desc=Importers.pack(spec.importer,spec.pack)
  if not desc then return nil,"unknown asset pack: "..tostring(spec.importer).."/"..tostring(spec.pack) end
  local m,err=Importers.readPack(spec.importer,spec.pack,fs); if not m then return nil,err end
  if m.kind~=desc.kind then return nil,"pack kind does not match its descriptor" end
  if spec.version and not Semver.satisfies(m.version,spec.version) then return nil,"asset pack version does not satisfy "..spec.version end
  return m
end
-- The loader and install UI check completeness; individual reads check their
-- own files again, without walking thousands of entries for every sprite.
function Importers.check(spec,fs)
  fs=Importers.fs(fs)
  local m,err=Importers.resolve(spec,fs); if not m then return nil,err end
  local seen={}
  for _,entry in pairs(m.entries) do
    for _,rec in ipairs({entry,entry.metadata or false}) do
      if rec and not seen[rec.file] then
        local path=Importers.assetPath(m.importer,m.pack,rec.file)
        local info=fs and fs.getInfo and fs.getInfo(path,"file")
        if not info or info.type~="file" or info.size~=rec.size then return nil,"pack asset is missing or changed: "..rec.file end
        seen[rec.file]=true
      end
    end
  end
  return m
end
function Importers.installed(id,fs)
  local out={}
  for _,p in ipairs(byId[id] and byId[id].packs or {}) do
    local m=Importers.check({importer=id,pack=p.id},fs)
    if m then local count=0; for _ in pairs(m.entries) do count=count+1 end
      out[p.id]={version=m.version,kind=m.kind,entries=count,source=Data.copy(m.source)} end
  end
  return out
end
function Importers.state(id,fs)
  local desc=byId[id]; if not desc then return "unknown" end
  if desc.status=="planned" then return "planned" end
  local have,total,installed=0,0,Importers.installed(id,fs)
  for _,p in ipairs(desc.packs) do if not p.planned then total=total+1; if installed[p.id] then have=have+1 end end end
  return have==0 and "missing" or have<total and "partial" or "ready"
end
function Importers.readMetadata(id,pack,entry,fs)
  local meta=entry and entry.metadata; if not meta then return nil,"entry has no metadata" end
  local path,err=Importers.assetPath(id,pack,meta.file); if not path then return nil,err end
  local bytes; bytes,err=Data.read(Importers.fs(fs),path,meta.size); if not bytes then return nil,err end
  return Data.decode(bytes)
end
local publish=require("src.import.PackPublish")
-- Install from an existing extracted pack, one bounded file per resume. The
-- source remains untouched. Immutable objects are written before the atomic
-- descriptor switch, so cancellation never changes the previous pack.
function Importers.install(id,pack,sourceFs,sourceRoot,destinationFs)
  destinationFs=Importers.fs(destinationFs)
  local sourceScope,destinationScope=Importers.pinScope(sourceFs),Importers.pinScope(destinationFs)
  return coroutine.create(function()
    assert(sourceScope());assert(destinationScope())
    assert(Importers.pack(id,pack),"unknown asset pack")
    assert(pathInside(sourceRoot)==sourceRoot,"source root must be a relative directory")
    local text,err=Data.read(sourceFs,sourceRoot.."/"..Importers.PACK_FILE); assert(text,err)
    local m; m,err=Data.decode(text); assert(m,err)
    local ok; ok,err=Importers.validatePack(m,id,pack); assert(ok,err)
    assert(m.kind==Importers.pack(id,pack).kind,"pack kind does not match its descriptor")
    local keys={}; for key in pairs(m.entries) do keys[#keys+1]=key end; table.sort(keys)
    local copied={}
    local function copy(rec,metadata)
      assert(sourceScope());assert(destinationScope())
      local rel=pathInside(rec.file)
      local old=copied[rel]
      if old and (not metadata or old.metadata) then rec.file=old.file; return end
      local bytes,why=Data.read(sourceFs,sourceRoot.."/"..rel,rec.size); assert(bytes,why)
      if metadata then local parsed; parsed,why=Data.decode(bytes); assert(parsed,why) end
      if old then old.metadata=true; rec.file=old.file; return end
      local hash=MD5.new():update(bytes):final()
      local file="objects/"..hash.."."..ext(rel)
      local path=assert(Importers.assetPath(id,pack,file))
      local existing=Data.read(destinationFs,path,#bytes)
      if existing~=bytes then local saved; saved,why=publish(destinationFs,path,bytes); assert(saved,why) end
      copied[rel],rec.file={file=file,metadata=metadata},file
    end
    for i,key in ipairs(keys) do
      local entry=m.entries[key]; copy(entry,false)
      if entry.metadata then copy(entry.metadata,true) end
      coroutine.yield({done=i,total=#keys,status="Installing "..key})
    end
    local encoded=Writer.encode(m); assert(#encoded<=Data.MAX_BYTES,"pack manifest exceeds the read limit")
    assert(sourceScope());assert(destinationScope())
    ok,err=publish(destinationFs,assert(Importers.manifestPath(id,pack)),encoded); assert(ok,err)
    Importers.invalidate(destinationFs,id,pack)
    return {importer=id,pack=pack,version=m.version,entries=#keys}
  end)
end
return Importers
