-- Files/iTunes sharing, Android storage and console MTP all reach this same
-- relative inbox. Never move or delete the user's source pack directories.
local Importers=require("src.import.Importers")
local Inbox={ROOT="imports/asset_packs",SOURCES="imports/asset_sources"}
function Inbox.start(fs)
  fs=Importers.fs(fs)
  local queue={}
  -- Source cartridges run first. Explicit extracted packs in the inbox may
  -- then override individual packs, preserving their established precedence.
  for _,desc in ipairs(Importers.all()) do
    if desc.module then
      for _,extension in ipairs(desc.source.formats or {}) do
        local path=Inbox.SOURCES.."/"..desc.id.."."..extension
        if fs.getInfo(path,"file") then
          queue[#queue+1]={importer=desc.id,pack="graphics",source=path,module=desc.module}
          break
        end
      end
    end
  end
  for _,desc in ipairs(Importers.all()) do
    for _,pack in ipairs(desc.packs) do
      local root=Inbox.ROOT.."/"..desc.id.."/"..pack.id
      if fs.getInfo(root.."/"..Importers.PACK_FILE,"file") then
        queue[#queue+1]={importer=desc.id,pack=pack.id,root=root}
      end
    end
  end
  return coroutine.create(function()
    local installed,failed,positions={},{},{}
    local function record(result)
      local key=result.importer.."/"..result.pack
      local at=positions[key] or #installed+1
      positions[key],installed[at]=at,result
    end
    for _,item in ipairs(queue) do
      local co
      local prepared,prepareError=pcall(function()
        if item.source then
          local data,err=require("src.import.PackData").read(fs,item.source)
          assert(data,err)
          co=require(item.module).job(data,fs)
        else co=Importers.install(item.importer,item.pack,fs,item.root,fs) end
      end)
      if not prepared then
        failed[#failed+1]={importer=item.importer,pack=item.pack,error=tostring(prepareError)}
      end
      while co do
        local ok,value=coroutine.resume(co)
        if not ok then
          failed[#failed+1]={importer=item.importer,pack=item.pack,error=tostring(value)}; break
        end
        if coroutine.status(co)=="dead" then
          if item.source then
            for _,desc in ipairs(Importers.get(item.importer).packs) do
              local count=value.packs and value.packs[desc.id]
              if count then record({importer=item.importer,pack=desc.id,entries=count,reused=value.reused}) end
            end
          else record(value) end
          break
        end
        value.importer,value.pack=item.importer,item.pack
        coroutine.yield(value)
      end
    end
    return {installed=installed,failed=failed,found=#queue}
  end)
end
return Inbox
