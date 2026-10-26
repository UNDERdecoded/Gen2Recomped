-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-apricorn-selection.md.
local Merge=require('src.mods.Merge')
local Ids=require('src.mods.UnifiedIds')
local Programs=require('src.world.Gen2ApricornPrograms')
local M={}
local mounted=setmetatable({},{__mode='k'})
local previous=setmetatable({},{__mode='k'})
local copy=Merge.deepCopy
local function equal(a,b)
  if a==b then return true end
  if type(a)~='table' or type(b)~='table'then return false end
  for k,v in pairs(a)do if not equal(v,b[k])then return false end end
  for k in pairs(b)do if a[k]==nil then return false end end
  return true
end
local function finite(v,seen)
  if type(v)=='number'then assert(v==v and math.abs(v)<math.huge,'apricorns: non-finite value')end
  if type(v)~='table' or v==Merge.DELETE then return end
  seen=seen or{};assert(not seen[v],'apricorns: cyclic value');seen[v]=true
  for k,x in pairs(v)do finite(k,seen);finite(x,seen)end
  seen[v]=nil
end
local function nativeItem(loader,id)
  assert(type(id)=='string' and id~='','apricorns: item ID is required')
  if Programs.item(id) and loader.content.items:get(id)then return id end
  local group,why=Ids.new(loader):resolve('items',id)
  assert(group,why)
  local found
  for _,key in ipairs(group.keys)do
    if Programs.item(key)then
      assert(not found or found==key,'apricorns: ambiguous native item byte')
      found=key
    end
  end
  return assert(found,'apricorns: item requires a native GSC item byte')
end
local function row(loader,id,value,defer)
  local registry=loader.content.apricorns
  assert(type(value)=='table' and value~=Merge.DELETE,'apricorns: expected recipe record')
  finite(value)
  for k in pairs(value)do assert(registry.spec.fields[k],'apricorns: unknown field '..tostring(k))end
  local ok,why=require('src.mods.Schemas').check(registry.spec,'apricorns',id,value,'register')
  assert(ok,why)
  -- The public schema describes records; native script operands have a
  -- narrower space (0xffff selects the halfword variable in setevent).
  assert(value.event<=65534,'apricorns: native event must be 0..65534')
  assert(value.index<=65535,'apricorns: native recipe index must be 1..65535')
  local function resolve(id)
    if not defer then return nativeItem(loader,id) end
    local found,key=pcall(nativeItem,loader,id)
    return found and key or id
  end
  return {apricorn=resolve(value.apricorn),ball=resolve(value.ball),
    event=value.event,index=value.index}
end
local function ordered(loader,overrideId,overrideRow,defer)
  local values={}
  for id,value in loader.content.apricorns:each()do values[id]=value end
  if overrideId then values[overrideId]=overrideRow end
  local out,items,events,normalized={},{},{},{}
  for id,value in pairs(values)do
    local r=row(loader,id,value,defer)
    assert(not items[r.apricorn],'apricorns: duplicate native apricorn item')
    assert(not events[r.event],'apricorns: duplicate recipe event')
    items[r.apricorn]=true;events[r.event]=true
    normalized[id]=r
    out[#out+1]={id=id,value=r}
  end
  table.sort(out,function(a,b)
    if a.value.index~=b.value.index then return a.value.index<b.value.index end
    return a.id<b.id
  end)
  local records,ids={},{};for i,entry in ipairs(out)do records[i]=entry.value;ids[i]=entry.id end
  return records,normalized,ids
end
function M.validate(loader)
  if loader:_generation()~=2 then return{}end
  local registry=loader.content.apricorns
  if not next(registry.ops)then return{}end
  local problems,items,events,ranks={},{},{},{}
  for i,id in ipairs(loader.order or{})do ranks[id]=i end
  local function conflict(id,old,label)
    local owner,other=registry.owners[id],registry.owners[old]
    if not owner or other and (ranks[other] or 0)>(ranks[owner] or 0)then owner=other end
    problems[#problems+1]={owner=owner,message='apricorns: duplicate '..label..' in '..old..' and '..id}
  end
  for id,value in registry:each()do
    local ok,r=pcall(row,loader,id,value,false)
    if not ok then problems[#problems+1]={owner=registry.owners[id],message=tostring(r)}
    else
      if items[r.apricorn]then conflict(id,items[r.apricorn],'native apricorn item')else items[r.apricorn]=id end
      if events[r.event]then conflict(id,events[r.event],'recipe event')else events[r.event]=id end
    end
  end
  return problems
end
function M.prepare(loader,data)
  local history=data and previous[data]
  if history and data.map_scripts==history.pool then
    local pool=history.pool
    if pool.apricornBalls==history.rows then
      -- Undo per record, not per whole array: one external edit must not
      -- keep every other unchanged recipe owned by the disabled mod alive.
      local present,replacements,removed,extras={},{},{},{}
      for _,value in ipairs(history.rows)do present[value]=true end
      for owned,entry in pairs(history.rowOwners)do
        if present[owned]then
          if not equal(owned,entry.snapshot)then
            if entry.before then replacements[entry.before]=owned
            else extras[owned]=true end
          end
        elseif entry.before then removed[entry.before]=true end
      end
      for _,value in ipairs(history.rows)do
        if not history.rowOwners[value]then
          local before=type(value)=='table' and history.beforeByItem[value.apricorn]
          if before and not replacements[before]then
            replacements[before]=value;removed[before]=nil
          else extras[value]=true end
        end
      end
      local restored={}
      for _,value in ipairs(history.beforeRows)do
        if not removed[value]then restored[#restored+1]=replacements[value] or value end
      end
      for _,value in ipairs(history.rows)do
        if extras[value]then restored[#restored+1]=value end
      end
      local pristine=#restored==#history.beforeRows
      for i,value in ipairs(restored)do if value~=history.beforeRows[i]then pristine=false;break end end
      pool.apricornBalls=pristine and history.beforeRows or restored
    end
    if pool.scripts==history.scripts then
      for key,value in pairs(history.changed)do
        if pool.scripts[key]==value and equal(value,history.snapshots[key])then
          pool.scripts[key]=history.beforeScripts[key]
        end
      end
      local same=true
      for key,value in pairs(pool.scripts)do if history.beforeScripts[key]~=value then same=false;break end end
      if same then
        for key,value in pairs(history.beforeScripts)do if pool.scripts[key]~=value then same=false;break end end
      end
      if same then pool.scripts=history.beforeScripts end
    end
  end
  if data then previous[data]=nil end
  local desc,why
  if loader:_generation()==2 then desc,why=Programs.describe(data)end
  local state={data=data,description=desc,why=why,base={}}
  if desc then
    local ids=Ids.new(loader)
    for _,r in ipairs(desc.base)do
      local id=ids:read('items',r.apricorn) or r.apricorn
      if state.base[id]then id=r.apricorn end
      state.base[id]=copy(r)
    end
  end
  mounted[loader]=state
  loader.content.apricorns.base=function()return state.base end
end
function M.apply(loader,data)
  if loader:_generation()~=2 or not data then return end
  local registry=loader.content.apricorns
  if not next(registry.ops) and not require('src.mods.Runtime').wants('apricorn.converted')then return end
  local state=assert(mounted[loader]);local desc=state.description
  if not desc and not next(registry.ops)then return end
  assert(desc,state.why)
  local pool=data.map_scripts
  assert(pool and pool.scripts==desc.scripts,'apricorns: native Kurt programs changed during mod load')
  local recipes,normalized,ids=ordered(loader)
  -- A removed/rekeyed native recipe stops accepting new work, but an old
  -- event can still deliver its original job unless an active rule claims it.
  local scripts,touched=Programs.project(desc,recipes,desc.base)
  local history={pool=pool,beforeRows=pool.apricornBalls,rows=copy(recipes),
    beforeByItem={},rowOwners={},beforeScripts=pool.scripts,scripts=scripts,changed={},snapshots={}}
  for _,value in ipairs(history.beforeRows)do history.beforeByItem[value.apricorn]=value end
  for i,value in ipairs(history.rows)do
    local base=state.base[ids[i]]
    history.rowOwners[value]={snapshot=copy(value),before=base and history.beforeByItem[base.apricorn]}
  end
  for key in pairs(touched)do history.changed[key]=scripts[key];history.snapshots[key]=copy(scripts[key])end
  -- Keep the folded view in actual native keys after deferred references
  -- resolve. The generic post-merge reference audit reads the same view as
  -- the native projection; the owner journals remain intact for rollback.
  for id,value in pairs(normalized)do registry.cache[id]={value=value}end
  -- All validation and IR construction precedes the first native mutation.
  pool.apricornBalls=history.rows;pool.scripts=scripts
  previous[data]=history
end
function M.api(loader,mod,native,generation)
  local available=generation==2
  local reason=not available and 'unsupported: apricorns has no native target in this dataset' or nil
  local registry=loader.content.apricorns
  local function key(id)
    if registry:get(id)~=nil or registry.ops[id]then return id end
    local ok,item=pcall(nativeItem,loader,id)
    if ok then
      for other,value in registry:each()do if value.apricorn==item then return other end end
    end
    return id
  end
  local function view(value)
    if not value then return nil end
    local ids=Ids.new(loader);value=copy(value)
    value.apricorn=ids:read('items',value.apricorn)
    value.ball=ids:read('items',value.ball)
    return value
  end
  local out={available=available,supports=function()return available,reason end}
  function out:get(id)if not available then return nil,reason end;return view(native:get(key(id)))end
  function out:has(id)return self:get(id)~=nil end
  function out:each()
    if not available then return function()end end
    local nextRow=native:each()
    return function()local id,value=nextRow();return id,view(value)end
  end
  for _,verb in ipairs({'register','override','patch','remove'})do
    out[verb]=function(_,id,value)
      if not available then return nil,reason end
      assert(type(id)=='string' and id~='','apricorns: id is required');id=key(id)
      local state=assert(mounted[loader]);assert(state.description,state.why)
      if verb=='remove'then native:remove(id);return end
      finite(value);assert(type(value)=='table' and value~=Merge.DELETE,'apricorns: expected recipe record')
      for k in pairs(value)do assert(registry.spec.fields[k],'apricorns: unknown field '..tostring(k))end
      local payload=copy(value)
      local effective=verb=='patch' and Merge.deepMerge(copy(registry:get(id) or{}),payload,'record') or payload
      effective=row(loader,id,effective,true)
      ordered(loader,id,effective,true)
      native[verb](native,id,effective)
      return out:get(id)
    end
  end
  return out
end
return M
