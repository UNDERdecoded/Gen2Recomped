-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Engine bootstrap only. Mod text runs in a separate, JIT-disabled Lua state
-- with guarded protected calls and coroutines. No engine modules or raw I/O
-- are reachable from its environment.
require('love.timer')
local Wire=require('src.mods.JobData')
local prefix,source,argument,seconds,assetIO=...
local control=love.thread.getChannel(prefix..'.control')
local requests=love.thread.getChannel(prefix..'.requests')
local replies=love.thread.getChannel(prefix..'.replies')
local result=love.thread.getChannel(prefix..'.result')
local progress=love.thread.getChannel(prefix..'.progress')
local rawPcall,rawXpcall,unpack=pcall,xpcall,unpack or table.unpack
local function pack(...)return {n=select('#',...),...}end
local deadline=love.timer.getTime()+seconds
local abort
local function guard()
  if control:peek() then abort='cancelled' end
  if not abort and love.timer.getTime()>=deadline then abort='job time budget exceeded' end
  if abort then error(abort,0) end
end
if jit then jit.off();jit.flush() end
local env={assert=assert,error=error,pairs=pairs,ipairs=ipairs,next=next,select=select,
  tonumber=tonumber,tostring=tostring,type=type,unpack=unpack,rawget=rawget,rawset=rawset,
  rawequal=rawequal,setmetatable=setmetatable,_VERSION=_VERSION}
function env.getmetatable(value)
  -- A string's VM-wide metatable exposes the bootstrap's original string
  -- library. Only a mod's own table metatables belong in this environment.
  if type(value)=='table' then return getmetatable(value) end
end
for _,name in ipairs({'math','string','table'}) do
  env[name]={};for key,value in pairs(_G[name]) do env[name][key]=value end
end
env.string.dump=nil
function env.pcall(fn,...)
  guard();local values=pack(rawPcall(fn,...));guard();return unpack(values,1,values.n)
end
function env.xpcall(fn,handler)
  guard()
  local values=pack(rawXpcall(fn,function(err)guard();local v=handler(err);guard();return v end))
  guard();return unpack(values,1,values.n)
end
env.coroutine={running=coroutine.running,status=coroutine.status,yield=coroutine.yield}
function env.coroutine.create(fn)
  local co=coroutine.create(fn);debug.sethook(co,guard,'',2000);return co
end
function env.coroutine.resume(co,...)
  guard();local values=pack(coroutine.resume(co,...));guard();return unpack(values,1,values.n)
end
function env.coroutine.wrap(fn)
  local co=env.coroutine.create(fn)
  return function(...)
    local values=pack(env.coroutine.resume(co,...))
    if not values[1] then error(values[2],0) end
    return unpack(values,2,values.n)
  end
end
function env.require()error('worker require is unavailable',0)end
function env.print(...)
  local values={}
  for index=1,math.min(select('#',...),16) do values[index]=tostring(select(index,...)):sub(1,1024) end
  print('[native mod job] '..table.concat(values,' '))
end
env._G=env
local function rpc(op,key,a,b)
  guard();replies:clear();requests:push({op=op,key=key,a=a,b=b})
  local reply=replies:demand();guard()
  if not reply or reply.abort then error(reply and reply.abort or 'job I/O unavailable',0) end
  return unpack(reply.values,1,reply.values.n)
end
env.job={}
function env.job.progress(value)
  guard();local bytes,why=Wire.encode(value,65536);assert(bytes,why)
  progress:clear();progress:push(bytes)
end
if assetIO then
  env.job.imports={info=function(_,id)return rpc('import.info',id)end,
    read=function(_,id,offset,length)return rpc('import.read',id,offset,length)end}
  env.job.cache={info=function(_,key)return rpc('cache.info',key)end,
    read=function(_,key)return rpc('cache.read',key)end,
    write=function(_,key,bytes)return rpc('cache.write',key,bytes)end,
    exists=function(_,key)return rpc('cache.exists',key)end}
end
local ok,value=rawPcall(function()
  local arg,why=Wire.decode(argument);assert(not why,why)
  assert(source:byte(1)~=27,'binary worker chunks are forbidden')
  local chunk,err=loadstring(source,'@native-mod-worker.lua');assert(chunk,err)
  setfenv(chunk,env)
  debug.sethook(guard,'',2000)
  return chunk(arg)
end)
debug.sethook()
local report
if abort then report={status=abort=='cancelled' and 'cancelled' or 'error',err=abort}
elseif ok then report={status='ok',result=value}
else
  -- An arbitrary error object can have a looping __tostring metamethod.
  -- Never execute mod code after removing the cancellation hook.
  local message=type(value)=='string' and value or 'worker raised a '..type(value)..' value'
  report={status='error',err=message:sub(1,4096)}
end
local bytes,why=Wire.encode(report)
if not bytes then bytes=assert(Wire.encode({status='error',err=why})) end
result:push(bytes)
