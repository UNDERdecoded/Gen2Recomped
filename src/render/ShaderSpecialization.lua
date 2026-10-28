-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional, bounded Metal compiler adapter. The caller keeps the real original
-- Shader interface. Its C program always receives every successful write and
-- remains the fallback for unsupported source, values or resource lifetimes.
local Branches=require('src.render.ShaderBranches')
local Guard=require('src.render.ShaderSamplerGuard')
local S={}
local installed=false
local stats={sources=0,variants=0,compiled=0,uses=0,depthUses=0,depthCompiled=0,fallbacks=0,failures=0,unsupported=0,compileSeconds=0}
local limits={sources=16,sourceBytes=2*1024*1024,minBytes=65536,maxBytes=262144,variants=64,perSource=16,uniforms=256,arguments=256,leaves=32768}
local originals=setmetatable({},{__mode='k'})
local variants={}
local records={}
local hooks={}
local sourceBytes=0
local raw,compiling
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function original(record)
 local shader=record.lease:peek()
 originals[shader]=record;record.aliases[shader]=true
 return shader
end
local function disable(record)
 record.disabled=true
 local current=raw.getShader()
 if variants[current]==record then raw.setShader(original(record))end
end
local function liveAlias(record)
 for alias in pairs(record.aliases)do
  if pcall(record.hook.hasUniform,alias,Guard.uniform)then return true end
 end
 return false
end
local function retire(record)
 if variants[raw.getShader()]==record then raw.setShader(original(record))end
 for alias in pairs(record.aliases)do originals[alias]=nil end
 for _,variant in pairs(record.variants)do
  if variant then variants[variant.shader]=nil;record.hook.release(variant.shader);stats.variants=stats.variants-1 end
 end
 record.lease:clear();record.lease:release()
 record.retired=true;sourceBytes=sourceBytes-#record.plan.source;stats.sources=stats.sources-1
end
local function sweep()
 -- This queries the actual native stack, including raw C push/pop callers.
 -- Never retire mappings or C leases while a hidden native frame may own a
 -- variant. There is no public Shader reference-count API to rely upon.
 if raw.getStackDepth()~=0 then return end
 for i=#records,1,-1 do
  local record=records[i]
  if record.disabled or not liveAlias(record)then retire(record);table.remove(records,i)end
 end
end
local function snapshot(value,budget,depth)
 budget.n=budget.n+1
 if budget.n>limits.leaves then error('uniform snapshot cap')end
 local kind=type(value)
 if kind=='number'or kind=='boolean'then return value end
 if kind=='string'and(value=='row'or value=='column')then return value end
 if kind=='userdata'and value.typeOf and value:typeOf('Texture')then
  return{resource=setmetatable({value},{__mode='v'})}
 end
 if kind~='table'or depth>=4 or getmetatable(value)~=nil then error('unsupported uniform value')end
 local out={};local size=0
 for key,item in next,value do
  if type(key)~='number'or key<1 or key%1~=0 or key>256 then error('unsupported uniform table')end
  size=math.max(size,key);out[key]=snapshot(item,budget,depth+1)
 end
 for i=1,size do if out[i]==nil then error('sparse uniform table')end end
 return out
end
local function restore(value)
 if type(value)~='table'then return value end
 if value.resource then
  local resource=value.resource[1]
  if not resource or not pcall(resource.getDimensions,resource)then error('uniform resource no longer replayable')end
  return resource
 end
 local out={};for i=1,#value do out[i]=restore(value[i])end;return out
end
local function remember(record,method,args)
 if record.disabled then return end
 local name=args[1]
 if type(name)~='string'or not name:match('^[%a_][%w_]*$')or args.n<2 or args.n>limits.arguments+2 then disable(record);return end
 local budget={n=0};local row={method=method,n=args.n-1}
 for i=2,args.n do row[i-1]=snapshot(args[i],budget,0)end
 if budget.n>limits.leaves then error('uniform snapshot cap')end
 local first=type(args[2])=='string'and 3 or 2
 row.coverage=args.n-first+1;row.leaves=budget.n
 local bank=record.bank[name]
 if not bank then
  if record.uniformCount>=limits.uniforms then error('uniform count cap')end
  record.uniformCount=record.uniformCount+1;bank={};record.bank[name]=bank
 end
 -- A later successful native send overwrites an array prefix. Keep exactly
 -- the older longer prefixes needed to reconstruct the untouched tail. This
 -- also preserves per-send row/column matrix layout without reinterpretation.
 for i=#bank,1,-1 do
  if bank[i].coverage<=row.coverage then record.leaves=record.leaves-bank[i].leaves;table.remove(bank,i)end
 end
 record.leaves=record.leaves+row.leaves
 if record.leaves>limits.leaves then error('uniform bank cap')end
 bank[#bank+1]=row
 if record.plan.kinds[name]then
  local literal=row.n==1 and Branches.literal(record.plan.kinds[name],args[2])or nil
  if record.scalars[name]~=literal then record.scalars[name]=literal;record.scalarRevision=record.scalarRevision+1 end
 end
 -- Eager writes keep existing variant textures current, release their old C
 -- texture references, and flush pending batches at the native uniform seam.
 for _,variant in pairs(record.variants)do
  if variant and record.hook.hasUniform(variant.shader,name)then
   record.hook[method](variant.shader,name,unpack(args,2,args.n))
  end
 end
 record.bankRevision=record.bankRevision+1
end
local function afterSend(record,method,args,...)
 if not record.disabled then
  local ok,why=pcall(remember,record,method,args)
  if not ok then stats.unsupported=stats.unsupported+1;stats.lastFallback=tostring(why):sub(1,160);disable(record)end
 end
 return ...
end
local function hook(shader)
 local methods=debug.getmetatable(shader).__index
 local prior=hooks[methods]
 if prior then
  local alpha=package.loaded['src.render.AlphaDepthCompat']
  -- The depth adapter hooks this native class lazily, on its first cutout.
  -- Rebase only that exact engine-owned interposition. Foreign owners keep
  -- the existing conservative fallback; old closures must forward once.
  if not(alpha and alpha.followsShaderMethods and alpha.followsShaderMethods(methods,prior.wrapped,prior.hasUniform))then return prior end
 end
 local h={send=methods.send,sendColor=methods.sendColor,release=methods.release,hasUniform=methods.hasUniform,methods=methods,wrapped={}}
 hooks[methods]=h
 for _,method in ipairs{'send','sendColor'}do
  if h[method]then h.wrapped[method]=function(self,...)
   local record=not compiling and originals[self]
   if not record or record.disabled or record.hook~=h then return h[method](self,...)end
   return afterSend(record,method,pack(...),h[method](self,...))
  end;methods[method]=h.wrapped[method]end
 end
 methods.release=function(self,...)
  local record=originals[self]
  if record and record.hook==h then disable(record)end
  return h.release(self,...)
 end
 h.wrapped.release=methods.release
 if prior then for _,record in ipairs(records)do if record.hook==prior then record.hook=h end end end
 return h
end
local function construct(record,key,constants,depth)
 if record.count>=limits.perSource or stats.variants>=limits.variants then return end
 -- Reconstruct resources before compiling. A missing/released Lua Texture is
 -- still correctly owned by the original C shader, so retain that path.
 local replay={}
 for name,bank in pairs(record.bank)do
  local rows={};replay[name]=rows
  for _,row in ipairs(bank)do
   local values={n=row.n,method=row.method}
   for i=1,row.n do values[i]=restore(row[i])end
   rows[#rows+1]=values
  end
 end
 local shader
 local started=love.timer.getTime();compiling=true
 local ok,why=pcall(function()
  local source=Branches.rewrite(record.plan,constants)
  source=Guard.rewrite(source,record.plan.clean,function(name)return record.hook.hasUniform(original(record),name)end)
  local compiler=raw.compile
  if record.depthAdapter then
   compiler=record.depthAdapter.compileNative
   if depth then
    local changed;source,changed=record.depthAdapter.source(source)
    assert(changed,'native depth variant no longer admissible')
   end
  end
  shader=compiler(source)
  if record.hook.hasUniform(shader,Guard.uniform)then record.hook.send(shader,Guard.uniform,0)end
  for name,rows in pairs(replay)do
   if record.hook.hasUniform(shader,name)then
    for _,row in ipairs(rows)do record.hook[row.method](shader,name,unpack(row,1,row.n))end
   end
  end
 end)
 compiling=false;stats.compileSeconds=stats.compileSeconds+love.timer.getTime()-started
 record.count=record.count+1
 if not ok then
  if shader then record.hook.release(shader)end
  record.variants[key]=false;stats.failures=stats.failures+1;stats.lastFailure=tostring(why):sub(1,1000)
  return nil,why
 end
 local variant={shader=shader,depth=depth}
 record.variants[key]=variant;variants[shader]=record
 stats.variants=stats.variants+1;stats.compiled=stats.compiled+1
 if depth then stats.depthCompiled=stats.depthCompiled+1 end
 return variant
end
local function choose(record)
 if record.disabled then return end
 local h=record.hook
 if h.methods.send~=h.wrapped.send or h.methods.sendColor~=h.wrapped.sendColor or h.methods.release~=h.wrapped.release or h.methods.hasUniform~=h.hasUniform then
  stats.unsupported=stats.unsupported+1;stats.lastFallback='Shader methods changed after admission';disable(record);return
 end
 if love.graphics.isGammaCorrect and love.graphics.isGammaCorrect()~=record.gamma then disable(record);return end
 if record.keyRevision~=record.scalarRevision then
  local constants,key={},{}
  for _,name in ipairs(record.plan.order)do
   local value=record.scalars[name]
   if value then constants[name]=value;key[#key+1]=name..'='..value end
  end
  record.constants,record.key=constants,table.concat(key,';');record.keyRevision=record.scalarRevision
 end
 if record.key==''then return end
 local depth=record.depthAdapter and record.depthAdapter.fragmentDepthTarget()or false
 local key=record.key..(record.depthAdapter and(depth and';@native-depth'or';@native-color')or'')
 local variant=record.variants[key]
 if variant==nil then
  if record.retryKey==key and record.retryRevision==record.bankRevision then return end
  local ok,value=pcall(construct,record,key,record.constants,depth)
  if ok then variant=value else stats.unsupported=stats.unsupported+1;stats.lastFallback=tostring(value):sub(1,160)end
  if not variant then record.retryKey,record.retryRevision=key,record.bankRevision end
 end
 return variant
end
local function beforeDraw()
 if stats.sources==0 then return end
 local actual=raw.getShader();local record=variants[actual]or originals[actual]
 if not record then return end
 local variant=choose(record)
 if variant then
  if actual~=variant.shader then raw.setShader(variant.shader)end
  stats.uses=stats.uses+1;if variant.depth then stats.depthUses=stats.depthUses+1 end
 else raw.setShader(original(record));stats.fallbacks=stats.fallbacks+1 end
end
local function admit(shader,source,second,third,n)
 if compiling or n>3 or second~=nil or third~=nil or type(source)~='string'or #source<limits.minBytes or #source>limits.maxBytes then return end
 sweep()
 if stats.sources>=limits.sources or sourceBytes+#source>limits.sourceBytes then return end
 -- Legacy canvas-Y programs retain their existing synchronization owner.
 if shader:hasUniform('pokeportLegacyCanvasY')then return end
 local plan=Branches.plan(source)
 if not plan or #plan.order==0 or plan.clean:find('void%s+[vp]ertexmain%s*%(')or plan.clean:find('void%s+pixelmain%s*%(')then return end
 local h=hook(shader);local lease=love.thread.newChannel();lease:push(shader)
 local record={plan=plan,lease=lease,hook=h,aliases=setmetatable({},{__mode='k'}),variants={},bank={},scalars={},uniformCount=0,leaves=0,count=0,scalarRevision=0,bankRevision=0,gamma=love.graphics.isGammaCorrect and love.graphics.isGammaCorrect()}
 local alpha=package.loaded['src.render.AlphaDepthCompat']
 if alpha and type(alpha.compileNative)=='function'and type(alpha.fragmentDepthTarget)=='function'then
  local _,eligible=alpha.source(source)
  if eligible then record.depthAdapter=alpha end
 end
 record.aliases[shader]=true;originals[shader]=record;records[#records+1]=record
 sourceBytes=sourceBytes+#source;stats.sources=stats.sources+1
end
function S.install()
 if installed then return false end
 local env=os.getenv('POKEPORT_SHADER_BRANCHES')
 local performance=require('src.core.Performance')
 if env=='0'or(env~='1'and not performance.shaderBranchSpecialization)then return false end
 local g=love and love.graphics
 if not(g and love.getVersion and love.getVersion()>=12 and love.system and love.system.getOS and love.system.getOS()=='OS X'and jit and jit.arch=='arm64'
  and love.thread and love.thread.newChannel and love.timer and love.timer.getTime and g.getStackDepth and g.getRendererInfo
  and g.newShader and g.getShader and g.setShader and debug and debug.getmetatable)then return false end
 local renderer=g.getRendererInfo()
 if type(renderer)~='string'or not renderer:lower():find('metal',1,true)then return false end
 local legacy=package.loaded['src.render.LegacyShaderCompat']
 if legacy and type(legacy.compileNative)~='function'then return false end
 installed=true;raw={newShader=g.newShader,setShader=g.setShader,getShader=g.getShader,getStackDepth=g.getStackDepth,present=g.present}
 raw.compile=legacy and legacy.compileNative or raw.newShader
 g.newShader=function(...)
  local shader=raw.newShader(...)
  local a,b,c=...
  local ok=pcall(admit,shader,a,b,c,select('#',...))
  if not ok then stats.failures=stats.failures+1 end
  return shader
 end
 g.getShader=function()
  local shader=raw.getShader();local record=variants[shader]
  return record and original(record)or shader
 end
 for _,name in ipairs{'draw','drawInstanced','drawFromShader','drawLayer','drawIndirect','drawFromShaderIndirect','rectangle','polygon','circle','ellipse','arc','line','points','print','printf'}do
  local native=g[name]
  if native then g[name]=function(...)beforeDraw();return native(...)end end
 end
 if raw.present then g.present=function(...)sweep();return raw.present(...)end end
 return true
end
function S.status()
 local out={installed=installed,sourceBytes=sourceBytes}
 for k,v in pairs(stats)do out[k]=v end
 return out
end
return S
