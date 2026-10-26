-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-landmarks.md.
-- Semantic landmark records project into the native town-map number space.
local Merge=require('src.mods.Merge')
local Native=require('src.world.Gen2Landmarks')
local Schemas=require('src.mods.Schemas')
local M={}
local copy=Merge.deepCopy
local previous=setmetatable({},{__mode='k'})
local mounted=setmetatable({},{__mode='k'})
local function equal(a,b)
 if a==b then return true end
 if type(a)~='table' or type(b)~='table'then return false end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function finite(v,seen)
 if type(v)=='number'then assert(v==v and math.abs(v)<math.huge,'landmarks: non-finite value')end
 if type(v)~='table' or v==Merge.DELETE then return end
 seen=seen or{};assert(not seen[v],'landmarks: cyclic value');seen[v]=true
 for k,x in pairs(v)do finite(k,seen);finite(x,seen)end
 seen[v]=nil
end
local function index(value)
 local n=tonumber(value)
 return n and n%1==0 and n>=0 and n<=255 and n or nil
end
local function record(registry,id,value)
 assert(type(value)=='table' and value~=Merge.DELETE,'landmarks: expected record')
 finite(value)
 for key in pairs(value)do assert(registry.spec.fields[key],'landmarks: unknown field '..tostring(key))end
 local ok,why=Schemas.check(registry.spec,'landmarks',id,value,'register');assert(ok,why)
 assert(index(value.index),'landmarks: native index must be a byte')
 return copy(value)
end
function M.prepare(loader,data)
 local history=data and previous[data]
 if history and data.field==history.field and history.field.townMap==history.town and
     history.town.landmarks==history.after then
  local rows=history.after
  for key,entry in pairs(history.changed)do
   if rows[key]==entry.value and equal(rows[key],entry.snapshot)then rows[key]=entry.before end
  end
  local pristine=true
  for key,value in pairs(rows)do if history.before[key]~=value then pristine=false;break end end
  if pristine then
   for key,value in pairs(history.before)do if rows[key]~=value then pristine=false;break end end
  end
  if pristine then
   if history.createdRows then history.town.landmarks=nil else history.town.landmarks=history.before end
  end
  if history.createdTown and not next(history.town)then history.field.townMap=nil end
  if history.createdField and not next(history.field)then data.field=nil end
 end
 if data then previous[data]=nil end
 local state={base={},order=Native.dataOrder(data)}
 if loader:_generation()==2 then
  local town=Native.town(data);local rows=town and town.landmarks or{}
  local indices={}
  for key in pairs(rows)do local n=index(key);if n then indices[n]=true end end
  local ordered={};for n in pairs(indices)do ordered[#ordered+1]=n end;table.sort(ordered)
  for _,n in ipairs(ordered)do
   local native=rows[n] or rows[tostring(n)]
   if type(native)=='table'then
    local id=native.landmarkId or native.id or state.order[n+1] or 'landmark:'..n
    if type(id)~='string' or id=='' or state.base[id]then id='landmark:'..n end
    state.base[id]={id=native.id,name=native.name,x=native.x,y=native.y,index=n}
   end
  end
 end
 mounted[loader]=state
 loader.content.landmarks.base=function()return state.base end
end
function M.apply(loader,data)
 local registry=loader.content.landmarks
 if loader:_generation()~=2 or not data or not next(registry.ops)then return end
 local state=assert(mounted[loader]);local values,chosen={},{}
 for id,value in registry:each()do
  value=registry.ops[id] and record(registry,id,value) or copy(value)
  values[id]=value
  local n=index(value.index)
  assert(n,'landmarks: native index must be a byte')
  local old=chosen[n]
  -- Match the reference's index arbitration: a native identity keeps its
  -- original slot; newcomers use lexical ID order, independent of pairs().
  if not old or state.order[n+1]==id or state.order[n+1]~=old and id<old then chosen[n]=id end
 end
 for i,id in ipairs(state.order)do
  if not chosen[i-1] and values[id]then chosen[i-1]=id end
 end
 local field=data.field or{}
 local town=field.townMap or{}
 local before=town.landmarks or{}
 local out={};for key,value in pairs(before)do if index(key)==nil then out[key]=value end end
 for n,id in pairs(chosen)do
  local value=copy(values[id]);value.landmarkId=id
  out[n]=value
 end
 local history={field=field,town=town,before=before,after=out,changed={},
  createdField=data.field==nil,createdTown=field.townMap==nil,createdRows=town.landmarks==nil}
 local keys={};for key in pairs(before)do keys[key]=true end;for key in pairs(out)do keys[key]=true end
 for key in pairs(keys)do
  if out[key]~=before[key]then history.changed[key]={before=before[key],value=out[key],snapshot=copy(out[key])}end
 end
 data.field=field;field.townMap=town;town.landmarks=out;previous[data]=history
end
function M.api(loader,mod,native,generation)
 local available=generation==2
 local reason=not available and 'unsupported: landmarks has no native target in this dataset' or nil
 local registry=loader.content.landmarks
 local out={available=available,supports=function()return available,reason end}
 function out:get(id)if not available then return nil,reason end;return copy(native:get(id))end
 function out:has(id)return self:get(id)~=nil end
 function out:each()
  if not available then return function()end end
  local nextRow=native:each()
  return function()local id,value=nextRow();return id,copy(value)end
 end
 for _,verb in ipairs({'register','override','patch','remove'})do
  out[verb]=function(_,id,value)
   if not available then return nil,reason end
   assert(type(id)=='string' and id~='','landmarks: id is required')
   if verb=='remove'then return native:remove(id)end
   finite(value);assert(type(value)=='table' and value~=Merge.DELETE,'landmarks: expected record')
   for key in pairs(value)do assert(registry.spec.fields[key],'landmarks: unknown field '..tostring(key))end
   local payload=copy(value)
   local effective=verb=='patch' and Merge.deepMerge(copy(registry:get(id)or{}),payload,'record')or payload
   record(registry,id,effective)
   native[verb](native,id,effective)
   return out:get(id)
  end
 end
 return out
end
return M
