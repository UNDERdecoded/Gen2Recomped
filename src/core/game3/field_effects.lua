-- Field artwork resources. Native effect tasks and phase observations are
-- separate contracts; no empty animation lists or substitute clocks here.
local Runtime=require('src.compat.gen1.FieldEffectRuntime')
local Assets=require('src.render.Assets')
local Stream=require('src.core.game3.asset_stream')
local service=Runtime.new()
local F={}
Stream.register(service)
Assets.register(function()service:invalidate()end)
function F.install(cache)return service:install(cache)end
function F.invalidate()service:invalidate()end
function F.release()service:release()end
function F.cancelOwner(who)service:releaseOwner(who)end
function F.manifest()return service:manifest()end
function F.manifestObject(name)
  local manifest,why=F.manifest();if not manifest then return nil,why end
  return manifest._byName[name]
end
function F.loadSheet(name)return service:get(name)end
F.getSpriteSheet=F.loadSheet
setmetatable(F,{__index=function(_,key)
  if key=='_cache'then local c=service:current();return c and c.provider and c.provider.cache end
  if key=='_sheets'then service:current();return service.loaded end
  if key=='_manifest'then return F.manifest()end
end,__newindex=function(t,key,value)
  if key=='_cache'then return F.install(value)end
  if key=='_sheets'then
    assert(type(value)=='table'and next(value)==nil,'field sheet cache replacement must be empty')
    return F.invalidate()
  end
  rawset(t,key,value)
end})
return F
