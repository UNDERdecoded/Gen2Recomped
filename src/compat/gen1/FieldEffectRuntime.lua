-- Owned field-effect artwork over the native dataset or an explicit cache.
-- This service has no actor, animation, task, RNG or gameplay clock.
local Session=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Catalog=require('src.render.Gen3FieldEffectCatalog')
local Cache=require('src.compat.gen1.FieldEffectCache')
local Assets=require('src.render.Assets')
local R={};R.__index=R
local ENGINE={}
local function owner()
  local runtime=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return runtime and runtime.currentMod or facade and facade._callbackOwner and facade._callbackOwner()or ENGINE
end
local function release(value)if value and value.release then pcall(value.release,value)end end
local function root()
  local extract=package.loaded['src.import.gba.extract_island1']
  return ((extract and extract.CACHE_ROOT)or'data/generated/gba')..'/field_effects'
end
local function signature(r)return table.concat({r.path or r.rgba,r.fw,r.fh,r.frames},'\0')end
function R.new()
  return setmetatable({loaded={},owned={},providers={},bytes=0,maxBytes=64*1024*1024},R)
end
function R:drop(sheet)
  local held=self.owned[sheet];if not held then return end
  self.owned[sheet]=nil;self.bytes=self.bytes-held.bytes
  -- Public sheet tables are mutable. Retire only allocations recorded at
  -- construction, never an image/quad a mod later assigned to that table.
  for _,part in ipairs(held.parts)do release(part)end
  sheet.image,sheet.imageData,sheet.quads,sheet.quadsFront=nil,nil,{},{};sheet._retired=true
end
function R:invalidate()
  for sheet in pairs(self.owned)do self:drop(sheet)end
  self.loaded={};self.context=nil
end
function R:release()self:invalidate();self.providers={}end
function R:current()
  local game,why=Session.game();local edition=Version.get()
  if not(game and type(game.data)=='table'and type(game.data.constants)=='table')then
    self:release();return nil,why or'no native field-effect dataset'
  end
  local provider
  for i=#self.providers,1,-1 do
    local p=self.providers[i]
    if p.game==game and p.data==game.data and p.save==game.save and p.mods==game.mods and p.edition==edition then
      provider=provider or p
    else table.remove(self.providers,i)end
  end
  local c=self.context;local prefix=root()
  if c and(c.game~=game or c.data~=game.data or c.constants~=game.data.constants or c.sprites~=game.data.sprites
      or c.save~=game.save or c.mods~=game.mods or c.edition~=edition or c.provider~=provider
      or c.root~=prefix or c.assets~=Assets.loader)then self:invalidate();c=nil end
  if not c then
    c={game=game,data=game.data,constants=game.data.constants,sprites=game.data.sprites,
      save=game.save,mods=game.mods,edition=edition,provider=provider,root=prefix,assets=Assets.loader}
    self.context=c
  end
  return c
end
function R:install(cache)
  if cache~=nil and(type(cache)~='table'or type(cache.read)~='function')then return nil,'invalid field cache provider'end
  local c,why=self:current();if not c then return nil,why end
  local who=owner()
  for i=#self.providers,1,-1 do if self.providers[i].owner==who then table.remove(self.providers,i)end end
  if cache then self.providers[#self.providers+1]={owner=who,cache=cache,game=c.game,data=c.data,save=c.save,mods=c.mods,edition=c.edition}end
  self:invalidate();return self:manifest()
end
function R:catalog()
  local c,why=self:current();if not c then return nil,why end
  if c.provider and not c.providerRead then
    c.providerRead=true
    local ok,manifest,err=pcall(Cache.manifest,c.provider.cache,c.root,Version.isFRLG(c.edition)and'frlg'or'rse')
    if not ok then c.manifestError=tostring(manifest)else c.manifest,c.manifestError=manifest,err end
    if self:current()~=c then return nil,'field cache cohort retired during manifest read'end
  end
  if c.manifestError then return nil,c.manifestError end
  return c
end
function R:manifest()
  local c,why=self:catalog();if not c then return nil,why end
  if c.manifest then return Cache.copy(c.manifest)end
  local manifest={family=Version.isFRLG(c.edition)and'frlg'or'rse',objects={},extras={},_byName={}}
  for name,row in pairs(Catalog.records(c.data))do
    local item={name=name,fw=row.fw,fh=row.fh,frames=row.frames,nativePath=row.path}
    manifest.objects[#manifest.objects+1]=item;manifest._byName[name]=item
  end
  table.sort(manifest.objects,function(a,b)return a.name<b.name end)
  return manifest
end
function R:record(name)
  if type(name)~='string'or#name>80 or not name:match('^[%w_%-]+$')then return nil,'invalid field sheet name'end
  local c,why=self:catalog();if not c then return nil,why end
  if c.manifest then
    local row=c.manifest._byName[name]
    if not row then return nil,'field sheet absent from installed manifest'end
    return row,c,true
  end
  local row=Catalog.records(c.data)[name]
  if not row then return nil,'native field sheet unavailable'end
  return row,c,false
end
function R:get(name)
  local row,c,explicit=self:record(name);if not row then return nil,c end
  local sig=signature(row)
  if not explicit then sig=sig..'\0'..Assets.resolve(row.path)end
  local cached=self.loaded[name];local held=cached and self.owned[cached]
  if held and held.signature==sig then held.owners[owner()]=true;return cached end
  if cached then self:drop(cached);self.loaded[name]=nil end
  if not(love and love.image and love.graphics)then return nil,'field sheet graphics unavailable'end
  local size=row.fw*row.fh*row.frames*8
  if self.bytes+size>self.maxBytes then return nil,'owned field sheet budget exhausted'end
  local parts={};local function keep(x)parts[#parts+1]=x;return x end
  local ok,sheet=pcall(function()
    local data
    if explicit then
      local bytes,why=Cache.rgba(c.provider.cache,c.root,row);assert(bytes,why)
      data=keep(love.image.newImageData(row.fw,row.fh*row.frames,'rgba8',bytes))
    else data=keep(love.image.newImageData(Assets.resolve(row.path)))end
    assert(data:getWidth()==row.fw and data:getHeight()==row.fh*row.frames,'field sheet image dimensions differ')
    local limits=love.graphics.getSystemLimits and love.graphics.getSystemLimits()
    assert(not limits or row.fh*row.frames<=limits.texturesize,'field sheet exceeds GPU limit')
    local image=keep(love.graphics.newImage(data));image:setFilter('nearest','nearest')
    local made={image=image,imageData=data,fw=row.fw,fh=row.fh,frames=row.frames,quads={},quadsFront={}}
    for i=0,row.frames-1 do
      made.quads[i]=keep(love.graphics.newQuad(0,i*row.fh,row.fw,row.fh,row.fw,row.fh*row.frames))
      made.quadsFront[i]=keep(love.graphics.newQuad(0,i*row.fh+row.fh-8,row.fw,8,row.fw,row.fh*row.frames))
    end
    assert(self:current()==c,'field sheet cohort retired during preparation')
    local latest,context,provider=self:record(name)
    assert(context==c and provider==explicit and signature(latest)==signature(row)
      and(explicit or sig==signature(latest)..'\0'..Assets.resolve(latest.path)),'field sheet record changed during preparation')
    assert(self.bytes+size<=self.maxBytes,'owned field sheet budget exhausted during preparation')
    return made
  end)
  if not ok then for _,part in ipairs(parts)do release(part)end;return nil,tostring(sheet)end
  self.owned[sheet]={signature=sig,bytes=size,parts=parts,owners={[owner()]=true}};self.bytes=self.bytes+size
  self.loaded[name]=sheet;return sheet
end
function R:releaseOwner(who)
  for i=#self.providers,1,-1 do if self.providers[i].owner==who then table.remove(self.providers,i)end end
  for name,sheet in pairs(self.loaded)do
    local held=self.owned[sheet]
    if held then held.owners[who]=nil;if next(held.owners)==nil then self:drop(sheet);self.loaded[name]=nil end end
  end
  self:current()
end
function R:poll()self:current()end
return R
