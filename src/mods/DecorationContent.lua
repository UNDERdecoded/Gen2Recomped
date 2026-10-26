-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- A DECO byte is identity, not the sorted position of a mod record.
local Merge=require('src.mods.Merge')
local Native=require('src.world.Gen2Decorations')
local Schemas=require('src.mods.Schemas')
local M={}
local copy=Merge.deepCopy
local mounted=setmetatable({},{__mode='k'})
local previous=setmetatable({},{__mode='k'})
local function equal(a,b)
 if a==b then return true end
 if type(a)~='table'or type(b)~='table'then return false end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local function byte(id)
 local digits=type(id)=='string'and id:match('^deco:(%d+)$')
 local n=digits and tonumber(digits)
 assert(n and n>=0 and n<=255 and 'deco:'..n==id,'decorations: expected canonical deco:<byte> ID')
 return n
end
local function finite(value,seen)
 if type(value)=='number'then assert(value==value and math.abs(value)<math.huge,'decorations: non-finite number')end
 if type(value)~='table'or value==Merge.DELETE then return end
 seen=seen or{};assert(not seen[value],'decorations: cyclic value');seen[value]=true
 for k,v in pairs(value)do finite(k,seen);finite(v,seen)end
 seen[value]=nil
end
local function record(registry,id,value)
 byte(id);finite(value)
 assert(type(value)=='table'and value~=Merge.DELETE,'decorations: expected record')
 for key in pairs(value)do assert(registry.spec.fields[key],'decorations: unknown field '..tostring(key))end
 local ok,why=Schemas.check(registry.spec,'decorations',id,value,'register');assert(ok,why)
 assert(value.flag<=65534,'decorations: native ownership event must be 0..65534')
 assert(value.action==nil or Native.action(value.action),'decorations: unknown native action')
 return copy(value)
end
function M.prepare(loader,data)
 local history=data and previous[data]
 if history and data.map_scripts==history.pool and history.pool.decorations==history.after then
  for key,entry in pairs(history.changed)do
   if history.after[key]==entry.value and equal(entry.value,entry.snapshot)then history.after[key]=entry.before end
  end
  local pristine=equal(history.after,history.before)
  if pristine then history.pool.decorations=history.before end
 end
 if data then previous[data]=nil end
 local state={base={},available=loader:_generation()==2 and Native.ready(data)}
 if state.available then
  for key,row in pairs(data.map_scripts.decorations)do
   local n=tonumber(key)
   if n and n%1==0 and n>=0 and n<=255 and type(row)=='table'then
    state.base['deco:'..n]=copy(data.map_scripts.decorations[n]or row)
   end
  end
 end
 mounted[loader]=state
 loader.content.decorations.base=function()return state.base end
end
function M.apply(loader,data)
 local registry=loader.content.decorations;local state=mounted[loader]
 if not(state and state.available)or not next(registry.ops)then return end
 local pool=data.map_scripts;local before=pool.decorations;local out={}
 for key,row in pairs(before)do if tonumber(key)==nil then out[key]=row end end
 for id,value in registry:each()do out[byte(id)]=registry.ops[id]and record(registry,id,value)or copy(value)end
 local changed={};local keys={}
 for key in pairs(before)do keys[key]=true end;for key in pairs(out)do keys[key]=true end
 for key in pairs(keys)do
  if before[key]~=out[key]then changed[key]={before=before[key],value=out[key],snapshot=copy(out[key])}end
 end
 pool.decorations=out;previous[data]={pool=pool,before=before,after=out,changed=changed}
end
function M.api(loader,mod,native,generation)
 local state=mounted[loader]
 local available=generation==2 and state and state.available or false
 local reason=not available and 'unsupported: decorations requires an imported native GSC attribute table'or nil
 local registry=loader.content.decorations
 local out={available=available,supports=function()return available,reason end}
 function out:get(id)if not available then return nil,reason end;byte(id);return copy(native:get(id))end
 function out:has(id)return self:get(id)~=nil end
 function out:each()
  if not available then return function()end end
  local nextRow=native:each();return function()local id,value=nextRow();return id,copy(value)end
 end
 for _,verb in ipairs({'register','override','patch','remove'})do
  out[verb]=function(_,id,value)
   if not available then return nil,reason end
   byte(id)
   if verb=='remove'then return native:remove(id)end
   finite(value);assert(type(value)=='table'and value~=Merge.DELETE,'decorations: expected record')
   for key in pairs(value)do assert(registry.spec.fields[key],'decorations: unknown field '..tostring(key))end
   local effective=verb=='patch'and Merge.deepMerge(copy(registry:get(id)or{}),copy(value),'record')or value
   effective=record(registry,id,effective);native[verb](native,id,effective)
   return out:get(id)
  end
 end
 return out
end
return M
