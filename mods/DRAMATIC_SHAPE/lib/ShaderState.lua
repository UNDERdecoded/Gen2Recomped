-- Preserve uniform state when drawing an instanced variant of a scene shader.
local V=...
local S={}
local values=setmetatable({}, {__mode="k"})
local unpack=table.unpack or unpack
local lastBudget
-- Snapshot small plain numeric vectors/matrices. Comparing table identity is
-- unsafe: callers mutate camera and model arrays in place between draws.
local function numericSize(value)
 if type(value)~="table" or getmetatable(value)~=nil then return nil end
 local n=#value
 if n<1 or n>16 then return nil end
 for i=1,n do if type(rawget(value,i))~="number" then return nil end end
 return n
end
function S.send(shader,name,...)
 local budget=V and V.renderBudget~=false
 if budget~=lastBudget then values=setmetatable({}, {__mode="k"});lastBudget=budget end
 if not budget and not (V and V.sharedHulls) then return pcall(shader.send,shader,name,...) end
 local record=values[shader]
 if not record then record={};values[shader]=record end
 local args=record[name]
 if not args then args={};record[name]=args end
 if budget and args.failed then return false,args.failed end
 local arrays=args.arrays
 if not arrays then arrays={};args.arrays=arrays end
 local n=select("#",...)
 local unchanged=args.sent and args.n==n
 for i=1,n do
  local value=select(i,...)
  if type(value)=="table" then
   local size=numericSize(value)
   local previous=arrays[i] and args[i]
   if not size or not previous or #previous~=size then unchanged=false
   else
    for j=1,size do if previous[j]~=value[j] then unchanged=false;break end end
   end
  elseif arrays[i] or args[i]~=value then unchanged=false end
 end
 if unchanged then return true end
 for i=1,n do
  local value=select(i,...)
  local size=numericSize(value)
  if size then
   local snapshot=arrays[i] and args[i] or {}
   for j=1,size do snapshot[j]=value[j] end
   for j=size+1,#snapshot do snapshot[j]=nil end
   args[i]=snapshot;arrays[i]=true
  else args[i]=value;arrays[i]=nil end
 end
 for i=n+1,args.n or #args do args[i]=nil;arrays[i]=nil end
 args.n=n
 local ok,err
 if budget and args.sent then shader:send(name,...);ok=true
 else ok,err=pcall(shader.send,shader,name,...) end
 if budget and not ok and (not shader.hasUniform or not shader:hasUniform(name)) then args.failed=err end
 args.sent=ok
 return ok,err
end
function S.copy(source,target)
 for name,args in pairs(values[source] or {})do S.send(target,name,unpack(args,1,args.n))end
end
return S
