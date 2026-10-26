local Importers=require("src.import.Importers")
local Data=require("src.import.PackData")
local Semver=require("src.mods.Semver")
local Packs={MAX_READ_BYTES=Importers.MAX_ENTRY_BYTES}

function Packs.parse(required,optional)
  local seen={}
  local function list(value,field,isRequired)
    if value==nil then return {} end
    assert(type(value)=="table",field.." must be an array")
    local count=0
    for key in pairs(value) do
      count=count+1
      assert(type(key)=="number" and key%1==0 and key>=1 and key<=#value,field.." must be a dense array")
    end
    assert(count==#value,field.." must be a dense array")
    local out={}
    for _,entry in ipairs(value) do
      assert(type(entry)=="table" and Importers.validId(entry.importer) and Importers.validId(entry.pack),field.." has an invalid pack identity")
      local key=entry.importer.."/"..entry.pack
      assert(not seen[key],"duplicate asset requirement: "..key); seen[key]=true
      if entry.version~=nil then
        assert(type(entry.version)=="string" and entry.version~="" and Semver.validRange(entry.version),field.." has an invalid version range")
      end
      out[#out+1]={importer=entry.importer,pack=entry.pack,version=entry.version,required=isRequired}
    end
    return out
  end
  local a=list(required,"required_assets",true)
  return a,list(optional,"optional_assets",false)
end
function Packs.specs(manifest)
  local out={}
  for _,list in ipairs({manifest.required_assets or {},manifest.optional_assets or {}}) do
    for _,spec in ipairs(list) do out[#out+1]=Data.copy(spec) end
  end
  return out
end
function Packs.missing(manifest,fs)
  local out={}
  for _,spec in ipairs(manifest.required_assets or {}) do
    local pack,err=Importers.check(spec,fs)
    if not pack then out[#out+1]={importer=spec.importer,pack=spec.pack,version=spec.version,reason=err} end
  end
  return #out>0 and out or nil
end
function Packs.new(manifest,fs)
  fs=Importers.fs(fs)
  local declared={}
  for _,spec in ipairs(Packs.specs(manifest)) do declared[spec.importer.."/"..spec.pack]=spec end
  local function resolve(id,pack)
    local spec=declared[tostring(id).."/"..tostring(pack)]
    if not spec then return nil,"undeclared asset pack" end
    return Importers.resolve(spec,fs)
  end
  local function entry(id,pack,key)
    local m,err=resolve(id,pack); if not m then return nil,err end
    local e=m.entries[key]; if not e then return nil,"no such pack entry: "..tostring(key) end
    return e
  end
  local function view(key,e)
    local out=Data.copy(e); out.id=key; return out
  end
  local api={}
  function api:list()
    local out={}
    for _,spec in ipairs(Packs.specs(manifest)) do
      local m=Importers.check(spec,fs)
      out[#out+1]={importer=spec.importer,pack=spec.pack,required=spec.required~=false,
        installed=m~=nil,version=m and m.version,kind=m and m.kind}
    end
    return out
  end
  function api:info(id,pack)
    local m,err=resolve(id,pack); if not m then return nil,err end
    local n=0; for _ in pairs(m.entries) do n=n+1 end
    return {importer=id,pack=pack,kind=m.kind,version=m.version,entries=n,source=m.source.name}
  end
  function api:entries(id,pack)
    local m,err=resolve(id,pack); if not m then return nil,err end
    local out={}; for key,e in pairs(m.entries) do out[#out+1]=view(key,e) end
    table.sort(out,function(a,b)return a.id<b.id end); return out
  end
  function api:entry(id,pack,key)
    local e,err=entry(id,pack,key); if not e then return nil,err end; return view(key,e)
  end
  function api:read(id,pack,key)
    local e,err=entry(id,pack,key); if not e then return nil,err end
    local path; path,err=Importers.assetPath(id,pack,e.file); if not path then return nil,err end
    return Data.read(fs,path,e.size)
  end
  function api:metadata(id,pack,key)
    local e,err=entry(id,pack,key); if not e then return nil,err end
    return Importers.readMetadata(id,pack,e,fs)
  end
  return api
end
return Packs
