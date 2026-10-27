-- Owned sprite resources over native imported sheets or an explicit binary
-- cache provider. The native SpriteRenderer/Assets GPU caches are never lent.
local Session=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Sheets=require('src.import.Gen3ObjectSheets')
local Assets=require('src.render.Assets')
local Cache=require('src.compat.gen1.SpriteCache')
local R={};R.__index=R
local ENGINE={}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function integer(n,lo,hi)return finite(n)and n%1==0 and n>=lo and n<=hi end
local function release(x)if x and x.release then pcall(x.release,x)end end
local function copy(v,seen,depth)
  if type(v)~='table'then
    if type(v)=='number'or type(v)=='string'or type(v)=='boolean'then return v end
    return nil
  end
  seen=seen or{};if seen[v]then return seen[v]end
  assert((depth or 0)<32,'sprite metadata nesting limit')
  local out={};seen[v]=out
  for k,x in pairs(v)do if type(k)=='number'or type(k)=='string'then out[k]=copy(x,seen,(depth or 0)+1)end end
  return out
end
local function owner()
  local native=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return native and native.currentMod or facade and facade._callbackOwner and facade._callbackOwner()or ENGINE
end
local function root()
  local extract=package.loaded['src.import.gba.extract_island1']
  return ((extract and extract.CACHE_ROOT)or'data/generated/gba')..'/ow'
end
local function dropSprite(sprite)
  if not sprite then return end
  release(sprite.image);release(sprite.imageData)
  for _,q in pairs(sprite.quads or{})do release(q)end
  sprite.image,sprite.imageData,sprite.quads=nil,nil,{}
  sprite._retired=true
end
function R.new()
  return setmetatable({loaded={},reflections={},overrides={},errors={},jobs={},providers={},owned={},serial=0,bytes=0,maxBytes=128*1024*1024},R)
end
function R:cancelJob(job)
  if self.jobs[job.id]==job then self.jobs[job.id]=nil end
  job.cancelled=true
  for _,p in ipairs(job.parts)do release(p)end;job.parts={}
end
function R:invalidate()
  local old=self.jobs;self.jobs={};for _,job in pairs(old)do self:cancelJob(job)end
  for sprite in pairs(self.owned)do dropSprite(sprite)end
  self.owned={};self.loaded,self.reflections,self.overrides={},{},{}
  self.errors={};self.context=nil;self.bytes=0
end
function R:release()self:invalidate();self.providers={}end
function R:install(provider)
  if provider~=nil and(type(provider)~='table'or type(provider.read)~='function')then return nil,'invalid sprite cache provider'end
  local who=owner()
  for i=#self.providers,1,-1 do if self.providers[i].owner==who then table.remove(self.providers,i)end end
  self.providers[#self.providers+1]={owner=who,cache=provider,edition=Version.get()}
  self:invalidate();return self:ready()
end
function R:current()
  local game=Session.game();local edition=Version.get();local info=Version.info(edition)
  if not info or info.generation~=3 then self:invalidate();return nil,'no native GBA sprite session'end
  local data=game and game.data;local meta=data and data.gen3_object_sheets
  local lease=self.providers[#self.providers];local provider=lease and lease.edition==edition and lease.cache
  if meta and(meta.schema~=Sheets.SCHEMA or meta.edition~=edition or not Version.acceptsSha1(edition,meta.romSha1))then
    meta=nil
  end
  if not meta and not provider then self:invalidate();return nil,'native original sprite cache unavailable or outdated'end
  local c=self.context;local saved=game and game.save;local mods=game and game.mods;local prefix=root()
  if c and(c.game~=game or c.data~=data or c.meta~=meta or c.save~=saved or c.mods~=mods
      or c.edition~=edition or c.provider~=provider or c.root~=prefix or c.assets~=Assets.loader)then self:invalidate();c=nil end
  if not c then
    c={game=game,data=data,meta=meta,save=saved,mods=mods,edition=edition,provider=provider,root=prefix,assets=Assets.loader}
    self.context=c
  end
  return c
end
function R:manifest()
  local c,why=self:current();if not c then return nil,why end
  if not c.manifest then
    if c.provider then c.manifest=copy(Cache.manifest(c.provider,c.root))end
    if not c.manifest and c.meta then
      local manifest={sprites={},avatars=copy(c.meta.avatars),count=0}
      for id,r in pairs(c.meta.objects)do
        manifest.sprites[id]={width=r.width,height=r.height,frameCount=r.frameCount,paletteTag=r.paletteTag,inanimate=r.inanimate}
        manifest.count=manifest.count+1
      end
      c.manifest=manifest
    end
  end
  return c.manifest
end
function R:ready()local c=self:current();return c~=nil and(self:manifest()~=nil)end
function R:record(id)
  id=tonumber(id);if not integer(id,0,65535)then return nil,'invalid sprite graphics ID'end
  local c,why=self:current();if not c then return nil,why end
  if c.provider then
    c.sourceRecords=c.sourceRecords or{}
    if c.sourceRecords[id]==nil then
      local ok,record,rgba=pcall(Cache.read,c.provider,c.root,id)
      if not ok then c.sourceRecords[id]={error=tostring(record)}
      elseif record then c.sourceRecords[id]={record=record,rgba=rgba}
      elseif rgba then c.sourceRecords[id]={error=rgba}
      else c.sourceRecords[id]=false end
    end
    local found=c.sourceRecords[id]
    if found then
      if found.error then return nil,found.error end
      return found.record,c,found.rgba
    end
  end
  local r=c.meta and c.meta.objects[id]
  if not r then return nil,'original sprite graphics unavailable'end
  if not(r.graphicsId==id and integer(r.width,8,128)and integer(r.height,8,128)and integer(r.frameCount,1,256)
      and r.width*r.height*r.frameCount<=2097152 and type(r.indexed)=='string'
      and#r.indexed==r.width*r.height*r.frameCount)then return nil,'invalid native sprite geometry'end
  return r,c
end
local function selection(c,r)
  local n=r.native;local out={}
  local raw=('assets/generated/overworld/g3_%03d_source.png'):format(r.graphicsId)
  local resolved=Assets.resolve(raw)
  if resolved~=raw then out.raw=resolved;return out end
  for i,pair in ipairs({{n and n.key,n and n.order},{n and n.runKey,n and n.runOrder}})do
    local key,order=pair[1],pair[2];local def=key and c.data and c.data.sprites and c.data.sprites[key]
    if def and type(def.image)=='string'and order then
      local original=i==2 and n.runImage or n.image
      local path=Assets.resolve(def.image)
      if path~=original or def.frameWidth~=(i==2 and n.runWidth or n.defaultWidth) or def.frameHeight~=(i==2 and n.runHeight or n.defaultHeight)
          or math.max(def.frames or 1,def.poseFrames or 1)~=(i==2 and n.runFrames or n.frames) or i==1 and def.walker~=n.walker then
        out[i]={key=key,path=path,def=def,order=order,width=def.frameWidth or n.width,height=def.frameHeight or n.height,
          frames=math.max(def.frames or 1,def.poseFrames or 1),inanimate=(def.frames or 1)<=1,walker=def.walker}
      end
    end
  end
  return out
end
local function same(a,b)
  if a.raw~=b.raw then return false end
  for i=1,2 do
    local x,y=a[i],b[i]
    if (x==nil)~=(y==nil)then return false end
    if x and(x.path~=y.path or x.def~=y.def or x.width~=y.width or x.height~=y.height or x.frames~=y.frames or x.walker~=y.walker)then return false end
  end
  return true
end
function R:yield(job)
  self:current()
  if self.context~=job.context or job.cancelled then error('sprite preparation retired')end
  if not job.flushing then coroutine.yield()end
end
function R:build(job)
  local r,c=job.record,job.context
  local rgba=job.rgba or Sheets.rgba(r,nil,function()self:yield(job)end)
  local data=love.image.newImageData(r.width,r.height*r.frameCount,'rgba8',rgba);job.parts[#job.parts+1]=data
  local width,height,count=r.width,r.height,r.frameCount
  local pick=job.selection
  if pick.raw then
    local source=love.image.newImageData(pick.raw);job.parts[#job.parts+1]=source
    assert(source:getWidth()==width and source:getHeight()==height*count,'original sprite override dimensions differ')
    data:paste(source,0,0,0,0,width,height*count)
  else
    for i=1,2 do
      local s=pick[i]
      if s then
        local source=love.image.newImageData(s.path);job.parts[#job.parts+1]=source
        assert(source:getWidth()==s.width and source:getHeight()>=s.height*s.frames,'native sprite override dimensions differ')
        if s.inanimate and i==1 then
          width,height,count=s.width,s.height,1
          data=love.image.newImageData(width,height,'rgba8');job.parts[#job.parts+1]=data
          data:paste(source,0,0,0,0,width,height)
          job.inanimate=true;break
        end
        assert(s.width>=width and s.height>=height,'native override cannot represent original sprite geometry')
        for frame,original in ipairs(s.order)do
          assert(original<count and frame<=s.frames,'native override frame map unavailable')
          data:paste(source,0,original*height,0,(frame-1)*s.height,width,height)
          if frame%16==0 then self:yield(job)end
        end
      end
    end
  end
  self:yield(job)
  local size=width*height*count*8;assert(self.bytes+size<=self.maxBytes,'owned sprite texture budget exhausted')
  if love.graphics.getSystemLimits then assert(height*count<=love.graphics.getSystemLimits().texturesize,'sprite sheet exceeds GPU limit')end
  local image=love.graphics.newImage(data);job.parts[#job.parts+1]=image;image:setFilter('nearest','nearest')
  self:yield(job)
  local sprite={image=image,imageData=data,width=width,height=height,frameCount=count,quads={},graphicsId=r.graphicsId,
    inanimate=job.inanimate or r.inanimate,drawOffX=r.drawOffX or 0,drawOffY=r.drawOffY or 0,
    paletteTag=r.paletteTag,paletteSlot=r.paletteSlot,palette=copy(r.palette),reflectionPaletteTag=r.reflectionPaletteTag,
    reflectionPaletteMappedTag=r.reflectionPaletteMappedTag,reflectionPalette=copy(r.reflectionPalette),mappedReflectionPalette=copy(r.mappedReflectionPalette)}
  if pick[1]then sprite.nativeWalker=pick[1].walker;sprite.nativeStandOrder={pick[1].order[1],pick[1].order[2],pick[1].order[3]}end
  for frame=0,count-1 do
    local quad=love.graphics.newQuad(0,frame*height,width,height,width,height*count)
    sprite.quads[frame]=quad;job.parts[#job.parts+1]=quad
    if frame%16==15 then self:yield(job)end
  end
  assert(self.context==c and not job.cancelled,'sprite publication retired')
  -- Source images used for projection are temporary; only our final data,
  -- image and quads become a published sprite resource.
  local keep={[data]=true,[image]=true};for _,q in pairs(sprite.quads)do keep[q]=true end
  for _,p in ipairs(job.parts)do if not keep[p]then release(p)end end;job.parts={}
  self.owned[sprite]={size=size,owners=job.owners,record=r,selection=job.selection,context=c}
  self.bytes=self.bytes+size;self.loaded[job.id]=sprite
end
function R:prefetch(id,priority)
  local r,c,rgba=self:record(id);if not r then return false,c end
  id=r.graphicsId;local who=owner();local cached=self.loaded[id]
  if cached then local held=self.owned[cached];if held then held.owners[who]=true end;return false end
  local job=self.jobs[id]
  if job then job.owners[who]=true;job.priority=math.min(job.priority,tonumber(priority)or 5);return false end
  local pick=rgba and{}or selection(c,r)
  self.serial=self.serial+1
  job={id=id,record=r,context=c,rgba=rgba,selection=pick,priority=tonumber(priority)or 5,serial=self.serial,owners={[who]=true},parts={}}
  job.co=coroutine.create(function()self:build(job)end);self.jobs[id]=job
  return true
end
function R:advance(job)
  local ok,why=coroutine.resume(job.co)
  if not ok then
    local retired=job.cancelled or self.context~=job.context
    self:cancelJob(job);if not retired then self.errors[job.id]=tostring(why)end;return false
  end
  if coroutine.status(job.co)=='dead'and self.jobs[job.id]==job then self.jobs[job.id]=nil;self.errors[job.id]=nil end
  return true
end
function R:poll()self:current()end
function R:step(budget)
  if not self:current()then return end
  local clock=love and love.timer and love.timer.getTime or os.clock
  local deadline=clock()+(budget or .002)
  repeat
    local selected
    for _,job in pairs(self.jobs)do if not selected or job.priority<selected.priority or job.priority==selected.priority and job.serial<selected.serial then selected=job end end
    if not selected then break end
    self:advance(selected)
  until clock()>=deadline
end
function R:cancelPending()local jobs=self.jobs;self.jobs={};for _,job in pairs(jobs)do self:cancelJob(job)end end
function R:drop(sprite)
  local held=self.owned[sprite]
  if held then self.bytes=self.bytes-held.size;self.owned[sprite]=nil;dropSprite(sprite)end
end
function R:get(id)
  id=tonumber(id);local c,why=self:current();if not c then return nil,why end
  local sprite=self.loaded[id]
  if sprite and not sprite._retired then
    local held=self.owned[sprite]
    if not held then return sprite end -- explicit source injection remains caller-owned
    local r,context,rgba=self:record(id)
    if r==held.record and context==held.context and(rgba or same(selection(c,r),held.selection))then held.owners[owner()]=true;return sprite end
    self:drop(sprite);self.loaded[id]=nil;self:clearPalette(id);self:drop(self.reflections[id]);self.reflections[id]=nil
  end
  local ok,reason=self:prefetch(id,0);local job=self.jobs[id]
  if not job then return self.loaded[id],reason end
  if job.co==coroutine.running()then return nil,'recursive sprite preparation'end
  job.flushing=true
  while self.jobs[id]==job do if not self:advance(job)then break end end
  return self.loaded[id],self.errors[id]
end
function R:variant(base,from,to)
  if type(from)~='table'or type(to)~='table'or#from~=#to or#from==0 then return nil,'invalid sprite palette substitution'end
  local colors,lut={},{};for i,a in ipairs(from)do
    local b=to[i];assert(type(a)=='table'and type(b)=='table','invalid palette color')
    for c=1,3 do assert(integer(a[c],0,255)and integer(b[c],0,255),'invalid palette channel')end
    colors[i]={a[1],a[2],a[3],b}
    lut[a[1]*65536+a[2]*256+a[3]]=b
  end
  local data=base.imageData:clone();local image,quads;local matches=0
  local ok,why=pcall(function()
    data:mapPixel(function(_,_,r,g,b,a)
      if a<=0 then return r,g,b,a end
      local rr,gg,bb=math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5)
      local best,distance=lut[rr*65536+gg*256+bb]
      if not best then
        for _,c in ipairs(colors)do
          local d=(rr-c[1])^2+(gg-c[2])^2+(bb-c[3])^2
          if d<=48 and(not distance or d<distance)then best,distance=c[4],d end
        end
      end
      if not best then return r,g,b,a end
      matches=matches+1;return best[1]/255,best[2]/255,best[3]/255,a
    end)
    assert(matches>0,'sprite palette substitution matched no pixels')
    assert(self.bytes+base.width*base.height*base.frameCount*8<=self.maxBytes,'owned sprite texture budget exhausted')
    image=love.graphics.newImage(data);image:setFilter('nearest','nearest');quads={}
    for frame=0,base.frameCount-1 do quads[frame]=love.graphics.newQuad(0,frame*base.height,base.width,base.height,base.width,base.height*base.frameCount)end
  end)
  if not ok then release(data);release(image);for _,q in pairs(quads or{})do release(q)end;return nil,tostring(why)end
  local sprite={};for k,v in pairs(base)do sprite[k]=v end
  sprite.image,sprite.imageData,sprite.quads=image,data,quads
  local size=base.width*base.height*base.frameCount*8;self.bytes=self.bytes+size
  self.owned[sprite]={size=size,owners={[owner()]=true},base=base};return sprite
end
function R:clearPalette(id)
  id=tonumber(id);local o=self.overrides[id];if not o then return false end
  self:drop(o.spr);self.overrides[id]=nil;return true
end
function R:setPalette(id,key,to,from)
  id=tonumber(id);if type(key)~='string'or not id then return false end
  local base=self:get(id);if not base then return false end
  local previous=self.overrides[id];if previous and previous.key==key and previous.base==base then return true end
  if not from then local d=package.loaded['src.core.game3.deoxys'];from=d and d.ROCK_PALS and d.ROCK_PALS[1]end
  local ok,sprite=pcall(self.variant,self,base,from,to);if not ok or not sprite then return false end
  self:clearPalette(id);self.overrides[id]={key=key,spr=sprite,base=base,colours=copy(to),sourceColours=copy(from),owner=owner()};return true
end
function R:getDraw(id)
  local base,why=self:get(id);if not base then return nil,why end
  local ov=self.overrides[tonumber(id)];return ov and ov.spr or base
end
local function rgb(p)
  if not p then return nil end
  local rows={};for i=1,15 do local n=p[i];if n==nil then return nil end
    rows[i]={math.floor(n%32*255/31+.5),math.floor(math.floor(n/32)%32*255/31+.5),math.floor(math.floor(n/1024)%32*255/31+.5)}end
  return rows
end
function R:reflection(id)
  id=tonumber(id);local base=self:get(id);if not base or not base.reflectionPaletteMappedTag then return nil end
  local cached=self.reflections[id]
  if cached then
    local held=self.owned[cached];if held then held.owners[owner()]=true end
    return cached
  end
  local from,to=rgb(base.palette),rgb(base.mappedReflectionPalette);if not from or not to then return nil end
  local sprite=self:variant(base,from,to);if sprite then self.reflections[id]=sprite end;return sprite
end
function R:releaseOwner(who)
  if type(who)~='string'then return end
  for i=#self.providers,1,-1 do if self.providers[i].owner==who then table.remove(self.providers,i)end end
  self:current()
  for _,job in pairs(self.jobs)do job.owners[who]=nil;if not next(job.owners)then self:cancelJob(job)end end
  -- The public cache may replace a resource without releasing it. Retire
  -- through our allocation registry so displaced and derived resources are
  -- included, while caller-injected images remain outside our ownership.
  for sprite,held in pairs(self.owned)do
    held.owners[who]=nil
    if not next(held.owners)then self:drop(sprite)end
  end
  for id,sprite in pairs(self.loaded)do
    if sprite._retired then self.loaded[id]=nil;self:clearPalette(id)end
  end
  for id,sprite in pairs(self.reflections)do
    if sprite._retired then self.reflections[id]=nil end
  end
  for id,o in pairs(self.overrides)do if o.owner==who then self:clearPalette(id)end end
end
R.copy=copy
return R
