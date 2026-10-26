-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Virtual native station records; failed entries never mutate a live dial.
local Merge=require("src.mods.Merge")
local Radio=require("src.world.Gen2Radio")
local M={}
local previous=setmetatable({},{__mode="k"})
local pending=setmetatable({},{__mode="k"})
local function equal(a,b,seen)
  if a==b then return true end
  if type(a)~="table" or type(b)~="table" then return false end
  seen=seen or {};if seen[a]==b then return true end;seen[a]=b
  for k,v in pairs(a)do if not equal(v,b[k],seen)then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end
  return true
end
local function finite(value,seen)
  if type(value)=="number" then assert(value==value and math.abs(value)<math.huge,"radio_channels: non-finite value")end
  if type(value)~="table" or value==Merge.DELETE then return end
  seen=seen or {};assert(not seen[value],"radio_channels: cyclic value");seen[value]=true
  for k,v in pairs(value)do finite(k,seen);finite(v,seen)end
  seen[value]=nil
end
local function shallow(t)
  local out={};for k,v in pairs(t or {})do out[k]=v end;return out
end
local function replace(target,rows)
  for k in pairs(target)do target[k]=nil end
  for k,v in pairs(rows)do target[k]=v end
end
function M.prepare(loader,data)
  local old=data and previous[data]
  if old and data.gen2RadioChannels==old.target then
    local external={};local changed=false
    for id in pairs(old.snapshot)do
      if not equal(old.target[id],old.snapshot[id])then external[id]=true;changed=true end
    end
    for id in pairs(old.target)do
      if old.snapshot[id]==nil then external[id]=true;changed=true end
    end
    if changed then
      local base=shallow(old.base)
      for id in pairs(external)do base[id]=old.target[id] end
      replace(old.target,base)
      local flags=Merge.deepCopy(old.beforeFlags or {})
      for id in pairs(external)do flags[id]=type(base[id])=="table" and base[id].name~=nil or nil end
      Radio.setLiteralState(data,flags)
    elseif old.existed then replace(old.target,old.before)
    else data.gen2RadioChannels=nil end
    if not changed then Radio.setLiteralState(data,old.beforeFlags)end
  end
  if data then previous[data]=nil end
  local registry=loader.content.radio_channels
  local base=loader:_generation()==2 and Merge.deepCopy(Radio.records(data)) or {}
  registry.base=function()return base end
  pending[registry]={data=data,base=base,existed=type(data and data.gen2RadioChannels)=="table",
    before=shallow(data and data.gen2RadioChannels),beforeFlags=Merge.deepCopy(Radio.literalState(data))}
end
function M.write(target,registry)
  local state=assert(pending[registry],"radio registry was not prepared")
  local rows={}
  for id,row in registry:each()do rows[id]=Merge.deepCopy(row) end
  replace(target,rows)
  local flags=Merge.deepCopy(state.beforeFlags or {})
  if state.existed and state.beforeFlags==nil then
    for id,row in pairs(state.before)do flags[id]=type(row)=="table" and row.name~=nil or nil end
  end
  for id,ops in pairs(registry.ops)do
    for _,op in ipairs(ops)do
      local value=op.value
      if op.op=="remove" or value==Merge.DELETE then flags[id]=nil
      elseif op.op=="register" or op.op=="override" then flags[id]=type(value)=="table" and value.name~=nil or nil
      elseif type(value)=="table" and value.name~=nil then flags[id]=value.name~=Merge.DELETE or nil end
    end
  end
  Radio.setLiteralState(state.data,flags)
  state.target,state.snapshot=target,Merge.deepCopy(rows)
  if state.data then previous[state.data]=state end
end
function M.api(loader,mod,native,generation)
  local registry=loader.content.radio_channels
  local available=generation==2
  local reason=not available and "unsupported: radio_channels has no native target in this dataset" or nil
  local out={available=available,supports=function()return available,reason end}
  function out:get(id)
    if not available then return nil,reason end
    return Merge.deepCopy(native:get(id))
  end
  function out:has(id)return self:get(id)~=nil end
  function out:each()
    if not available then return function()end end
    local nextRow=native:each()
    return function()local id,row=nextRow();return id,Merge.deepCopy(row)end
  end
  for _,verb in ipairs({"register","override","patch","remove"})do
    out[verb]=function(_,id,value)
      if not available then return nil,reason end
      assert(type(id)=="string" and id~="","radio_channels id is required")
      finite(value)
      local effective=value
      if verb=="patch" and value~=Merge.DELETE then
        effective=Merge.deepMerge(Merge.deepCopy(registry:get(id) or {}),value,"record")
      end
      local channel=type(effective)=="table" and effective.channel
      if verb~="remove" and channel and channel~=0 then
        for other,row in registry:each()do
          assert(other==id or row.channel~=channel,"radio_channels: channel collision "..tostring(channel))
        end
      end
      native[verb](native,id,Merge.deepCopy(value))
      return out:get(id)
    end
  end
  return out
end
return M
