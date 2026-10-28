-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Metal can commit a projected cutout's depth before its alpha discard.
-- Explicitly returning the unchanged fragment depth forces late depth writes:
-- transparent texels leave later foliage intact, opaque pixels still occlude.
local A={}
local installed=false
local marker='POKEPORT_ALPHA_DEPTH_ADAPTED'
local function clean(source)
 return (source:gsub('/%*.-%*/',function(s)return s:gsub('[^\n]',' ')end)
  :gsub('//[^\n]*',''))
end
local function projected(source)
 return type(source)=='string' and clean(source):find('vec4%s+position%s*%(')~=nil
end
local prefix=[[#ifdef PIXEL
#define POKEPORT_ALPHA_DEPTH_ADAPTED 1
#define effect pokeportAlphaDepthEffect
#endif
#line 1
]]
local suffix=[[
#ifdef PIXEL
#undef effect
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec4 pixel = pokeportAlphaDepthEffect(color, tex, uv, screen);
  gl_FragDepth = gl_FragCoord.z;
  return pixel;
}
#endif
]]
function A.source(source,hasPosition)
 if type(source)~='string' then return source,false end
 local code=clean(source)
 if not(hasPosition or projected(code))
  or not code:find('vec4%s+effect%s*%(')
  or not code:find('%f[%w_]discard%f[^%w_]')
  or code:find('%f[%w_]gl_FragDepth%f[^%w_]')
  or code:find('%f[%w_]gl_FragDepthEXT%f[^%w_]')
  or code:find(marker,1,true)
  or code:find('POKEPORT_NATIVE_ALPHA_DEPTH',1,true)
  or code:find('#%s*define%s+effect%f[^%w_]')
  or code:find('void%s+pixelmain%s*%(')then return source,false end
 return prefix..source..'\n'..suffix,true
end
local unpack=table.unpack or unpack
local originals=setmetatable({},{__mode='k'})
local ignored=setmetatable({},{__mode='k'})
local records,hooks={},{}
local sourceBytes=0
local stats={compiled=0,lateDraws=0,retired=0,failures=0}
local raw
local function find(shader)
 if not shader then return end
 local record=originals[shader]
 if record then return record end
 if ignored[shader]then return end
 for _,candidate in ipairs(records)do
  if candidate.lease:peek()==shader then
   originals[shader]=candidate;candidate.aliases[shader]=true;return candidate
  end
 end
 ignored[shader]=true
end
local function sweep()
 if raw.getStackDepth()~=0 then return end
 find(raw.getShader()) -- preserve a shader still held by the native target
 for i=#records,1,-1 do
  local record=records[i];local live=false
  for alias in pairs(record.aliases)do
   if pcall(record.hook.hasUniform,alias,'pokeportAlphaDepthLifetimeProbe')then live=true;break end
  end
  if record.disabled or not live then
   for alias in pairs(record.aliases)do originals[alias]=nil end
   record.hook.release(record.late);record.lease:clear();record.lease:release()
   sourceBytes=sourceBytes-record.bytes;table.remove(records,i);stats.retired=stats.retired+1
  end
 end
end
local function mirrored(record,method,args,...)
 if not record.disabled then
  local name=args[1]
  if record.hook.hasUniform(record.late,name)then
   local ok=pcall(method,record.late,unpack(args,1,args.n))
   if not ok then record.disabled=true end
  end
 end
 return ...
end
local function released(record,...)
 record.disabled=true
 return ...
end
local function hook(shader)
 local methods=debug.getmetatable(shader).__index
 if hooks[methods]then return hooks[methods]end
 local h={hasUniform=methods.hasUniform,release=methods.release,send=methods.send,sendColor=methods.sendColor,wrapped={}}
 hooks[methods]=h
 for _,name in ipairs{'send','sendColor'}do
  local method=methods[name]
  if method then h.wrapped[name]=function(self,...)
   local record=find(self)
   if not record or record.disabled then return method(self,...)end
   local args={n=select('#',...),...}
   -- The original must accept the write first. A rejected native write must
   -- neither alter the companion nor change the public error/return contract.
   return mirrored(record,method,args,method(self,...))
  end;methods[name]=h.wrapped[name]end
 end
 methods.release=function(self,...)
  local record=find(self)
  if record then return released(record,h.release(self,...))end
  return h.release(self,...)
 end
 h.wrapped.release=methods.release
 return h
end
function A.ownsShaderMethods(methods)
 local h=hooks[methods]
 return h and methods.send==h.wrapped.send and methods.sendColor==h.wrapped.sendColor
  and methods.release==h.wrapped.release and methods.hasUniform==h.hasUniform or false
end
function A.followsShaderMethods(methods,prior,hasUniform)
 local h=hooks[methods]
 return A.ownsShaderMethods(methods)and h.send==prior.send and h.sendColor==prior.sendColor
  and h.release==prior.release and h.hasUniform==hasUniform or false
end
local function depthTarget()
 local target=raw.getCanvas()
 if type(target)~='table'then return false end
 local depth=rawget(target,'depthstencil')
 if type(depth)=='table'then depth=depth[1]end
 return depth and depth.getFormat and depth:getFormat():match('^depth')~=nil or false
end
-- Derivative programs owned by another native compiler adapter can select
-- this exact path once, without creating a second companion or changing
-- programs around every draw. Colour-only targets retain their own program.
function A.fragmentDepthTarget()
 if not installed then return false end
 local _,writes=raw.getDepthMode()
 return writes and depthTarget()or false
end
local function restored(shader,ok,...)
 raw.setShader(shader)
 if not ok then error((...),0)end
 return ...
end
local function draw(native,...)
 local shader=raw.getShader();local record=find(shader)
 if not record or record.disabled then return native(...)end
 local _,writes=raw.getDepthMode()
 -- Metal rejects a fragment-depth output on a colour-only render target,
 -- even if depth testing is off. Query the actual native attachment, so raw
 -- push/pop and nested previews cannot leave stale target bookkeeping here.
 -- Unobservable temporary/backbuffer depth targets keep the original program.
 if not writes or not depthTarget()then return native(...)end
 stats.lateDraws=stats.lateDraws+1
 raw.setShader(record.late)
 return restored(shader,pcall(native,...))
end
function A.install()
 local g=love and love.graphics
 if installed or not(love and love.getVersion and love.getVersion()>=12 and g
  and g.getRendererInfo and g.newShader and g.getShader and g.setShader
  and g.getCanvas and g.getDepthMode and g.getStackDepth
  and love.thread and love.thread.newChannel and debug and debug.getmetatable)then return false end
 local renderer=g.getRendererInfo()
 if type(renderer)~='string' or not renderer:lower():find('metal',1,true)then return false end
 installed=true
 raw={newShader=g.newShader,getShader=g.getShader,setShader=g.setShader,
  getCanvas=g.getCanvas,getDepthMode=g.getDepthMode,getStackDepth=g.getStackDepth,present=g.present}
 A.compileNative=raw.newShader
 local function read(arg)
  if type(arg)=='string' and not arg:find('\n',1,true) then
   local fs=love.filesystem
   if fs and fs.getInfo and fs.getInfo(arg,'file')then return fs.read(arg)or arg end
  elseif type(arg)=='userdata' and arg.typeOf and arg:typeOf('FileData')then return arg:getString()end
  return arg
 end
 g.newShader=function(a,b,c)
  local shader=raw.newShader(a,b,c)
  local first,second=read(a),read(b)
  local size=(type(first)=='string'and #first or 0)+(type(second)=='string'and #second or 0)
  if size>262144 then ignored[shader]=true;return shader end
  local hasPosition=projected(first)or projected(second)
  local adapted,changed=A.source(first,hasPosition)
  local adapted2,changed2=A.source(second,hasPosition)
  if not(changed or changed2)then ignored[shader]=true;return shader end
  sweep()
  if #records>=32 or sourceBytes+size>2*1024*1024 then ignored[shader]=true;return shader end
  local ok,late=pcall(raw.newShader,changed and adapted or a,changed2 and adapted2 or b,c)
  if not ok then stats.failures=stats.failures+1;ignored[shader]=true;return shader end
  local h=hook(shader);local lease=love.thread.newChannel();lease:push(shader)
  local record={late=late,hook=h,lease=lease,bytes=size,aliases=setmetatable({},{__mode='k'})}
  originals[shader]=record;record.aliases[shader]=true;records[#records+1]=record;sourceBytes=sourceBytes+size;stats.compiled=stats.compiled+1
  return shader
 end
 for _,name in ipairs{'draw','drawInstanced','drawFromShader','drawLayer','drawIndirect','drawFromShaderIndirect','rectangle','polygon','circle','ellipse','arc','line','points','print','printf'}do
  local native=g[name]
  if native then g[name]=function(...)return draw(native,...)end end
 end
 if raw.present then g.present=function(...)sweep();return raw.present(...)end end
 return true
end
function A.status()
 local out={installed=installed,sources=#records,sourceBytes=sourceBytes}
 for key,value in pairs(stats)do out[key]=value end
 return out
end
return A
