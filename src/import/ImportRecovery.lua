-- Durable import breadcrumbs live with settings, independent of the cache root.
local Serializer=require('src.core.SaveSerializer')
local Recovery={PATH='rom-import.pending'}
local current
local function persist()
  if current and love and love.filesystem then
    local ok,err=love.filesystem.write(Recovery.PATH,Serializer.encode(current))
    if not ok then require('src.core.Logger').warn('import recovery: %s',tostring(err)) end
  end
end
function Recovery.load()
  local raw=love.filesystem.read(Recovery.PATH)
  if type(raw)~='string' then return nil end
  local rec=Serializer.decode(raw)
  return type(rec)=='table' and type(rec.source)=='string' and rec or nil
end
function Recovery.begin(source,version,root)
  current={source=source or '',version=version,root=root or love.filesystem.getSaveDirectory(),stage='Verifying cartridge'}
  persist();return current
end
function Recovery.resume(rec) current=rec end
function Recovery.stage(stage,operation)
  if not current then return end
  current.stage=stage or current.stage;current.operation=operation
  current.luaMB=math.floor(collectgarbage('count')/1024)
  persist()
end
function Recovery.fail(message)
  current=Recovery.load() or current
  if not current then return end
  current.error=tostring(message);persist()
  return current
end
function Recovery.finish()
  current=nil;love.filesystem.remove(Recovery.PATH)
end
return Recovery
