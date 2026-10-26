-- Copyright (c) 2026 Roxas2712. See the offered PR contribution permission in docs/native-gen2-phone-content.md.
-- Semantic contacts project onto the native numeric book, never onto saves.
local Merge = require('src.mods.Merge')
local M = {}
local previous = setmetatable({}, {__mode='k'})
local mounted = setmetatable({}, {__mode='k'})
local copy = Merge.deepCopy
local function equal(a,b)
  if a==b then return true end
  if type(a)~='table' or type(b)~='table' then return false end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function finite(v,seen)
  if type(v)=='number' then assert(v==v and math.abs(v)<math.huge,'phone_contacts: non-finite value') end
  if type(v)~='table' or v==Merge.DELETE then return end
  seen=seen or {};assert(not seen[v],'phone_contacts: cyclic value');seen[v]=true
  for k,x in pairs(v) do finite(k,seen);finite(x,seen) end
  seen[v]=nil
end
local function position(list,value)
  local found
  for i,v in ipairs(list or {}) do
    if v==value then assert(not found,'phone_contacts: ambiguous identity '..tostring(value));found=i end
  end
  return found
end
local function mapName(data,row)
  local found
  for id,def in pairs(data.maps or {}) do
    if type(def)=='table' and def.group==row.group and def.number==row.number then
      -- Only shared physical records prove an alias; spelling and provenance
      -- alone must not collapse two independently authored maps.
      local name=id
      if type(def.id)=='string' and type(def.sourceId)=='string'
          and data.maps[def.id]==def and data.maps[def.sourceId]==def then name=def.id end
      if found and found~=name then return nil end
      found=name
    end
  end
  return found
end
local function semantic(data,index,row)
  local c=data.constants or {}
  local class=(c.trainerClassOrder or {})[row.class]
  local member=class and (c.trainerClassMembers or {})[class]
  member=member and member[row.trainer]
  return {index=index,name=row.name,number=row.contactNumber,
    class=member and class or nil,member=member,map=mapName(data,row),
    calleeTime=row.callTime,callerTime=row.receiveTime,
    calleeKey=row.call,callerKey=row.receive,rematchEvent=row.rematchEvent}
end
function M.prepare(loader,data)
  local history=data and previous[data]
  for _,undo in ipairs(history or {}) do
    if undo.target[undo.index]==undo.value and equal(undo.value,undo.snapshot) then
      undo.target[undo.index]=undo.before
    end
  end
  if history and history.createdPhone and data.map_scripts==history.pool
      and data.map_scripts.phone==history.target and not next(history.target) then
    data.map_scripts.phone=nil
    if history.createdPool and not next(history.pool) then data.map_scripts=nil end
  end
  if data then previous[data]=nil end
  local state={data=data,base={},native={},floor=0}
  local pool=data and data.map_scripts
  local constants=data and data.constants or {}
  local order=constants.phoneContactOrder or {}
  state.floor=math.max(0,#order-1,(pool and pool.phoneInfo and pool.phoneInfo.size or 1)-1)
  if data and loader:_generation()==2 then
    for index,row in pairs(pool and pool.phone or {}) do
      if type(index)=='number' and type(row)=='table' then
        state.floor=math.max(state.floor,index)
        local id=order[index+1]
        if not id or id=='PHONE_UNUSED' or state.base[id] then id='phone:'..index end
        state.base[id]=semantic(data,index,row);state.native[id]=copy(row)
      end
    end
  end
  mounted[loader]=state
  loader.content.phone_contacts.base=function() return state.base end
end
local function indexFor(registry,state,id,value)
  local old,used=nil,{}
  local function reserve(other,row)
    if type(row)~='table' or row==Merge.DELETE or row.index==nil then return end
    if other==id then old=old or row.index end
    if used[row.index] and used[row.index]~=other then used[row.index]=true
    else used[row.index]=other end
  end
  for other,row in pairs(state.base) do reserve(other,row) end
  for other,ops in pairs(registry.ops) do for _,op in ipairs(ops) do reserve(other,op.value) end end
  local index=value.index or old
  if old and value.index then assert(value.index==old,'phone_contacts: changing an index is unsupported') end
  if not index then
    for candidate=state.floor+1,255 do if not used[candidate] then index=candidate;break end end
  end
  assert(type(index)=='number' and index%1==0 and index>=1 and index<=255,'phone_contacts: invalid or exhausted index')
  assert(not used[index] or used[index]==id,'phone_contacts: index collision')
  assert(old or index>state.floor,'phone_contacts: native rows and holes are reserved')
  return index
end
local function nativeRow(loader,id,row)
  local state=assert(mounted[loader]);local data=state.data
  local old=state.native[id] or {}
  local out=copy(old)
  out.name=row.name;out.contactNumber=row.number;out.rematchEvent=row.rematchEvent
  if row.class or row.member then
    assert(row.class and row.member,'phone_contacts: class and member are required together')
    assert(row.number==nil,'phone_contacts: trainer and non-trainer identities are exclusive')
    local c=data.constants or {}
    out.class=assert(position(c.trainerClassOrder,row.class),'phone_contacts: unknown trainer class')
    out.trainer=assert(position((c.trainerClassMembers or {})[row.class],row.member),'phone_contacts: unknown trainer member')
    out.contactNumber=nil
  elseif not (old.class and state.base[id] and not state.base[id].class) then
    out.class=nil;out.trainer=nil
  end
  if row.map then
    local def=loader.content.maps:get(row.map)
    assert(type(def)=='table' and type(def.group)=='number' and type(def.number)=='number',
      'phone_contacts: map requires native group/number metadata')
    out.group,out.number=def.group,def.number
  elseif state.base[id] and state.base[id].map then
    out.group,out.number=nil,nil
  end
  out.call=row.calleeKey or row.callee
  out.receive=row.callerKey or row.caller
  out.callTime,out.receiveTime=row.calleeTime or 0,row.callerTime or 0
  for _,field in ipairs({'call','receive'}) do
    local key=out[field];local mask=out[field..'Time']
    assert(mask==0 or type(key)=='string' and key~='','phone_contacts: enabled direction needs a script key')
    -- This version delegates existing imported scripts to the real native VM.
    -- It does not interpret Gen1 bytecode or fabricate missing script labels.
    if key then assert(data.map_scripts and data.map_scripts.scripts and data.map_scripts.scripts[key],
      'phone_contacts: script key is not in the native script pool: '..tostring(key)) end
  end
  assert(type(row.name)=='string' and row.name~='' or out.class,
    'phone_contacts: contact needs a name or trainer identity')
  return out
end
function M.apply(loader,data)
  local registry=loader.content.phone_contacts
  if loader:_generation()~=2 or not data or not next(registry.ops) then return end
  local state=assert(mounted[loader]);local plan={}
  for _,id in ipairs(registry.order) do
    if registry.ops[id] then
      local row=registry:get(id);local old=state.base[id]
      local index=row and row.index or old and old.index
      if index then plan[#plan+1]={index=index,value=row and nativeRow(loader,id,row)} end
    end
  end
  -- Validate every conversion before the first native write.
  local createdPool=data.map_scripts==nil
  data.map_scripts=data.map_scripts or {}
  local createdPhone=data.map_scripts.phone==nil
  data.map_scripts.phone=data.map_scripts.phone or {}
  local target=data.map_scripts.phone;local undo={createdPool=createdPool,createdPhone=createdPhone,pool=data.map_scripts,target=target}
  for _,entry in ipairs(plan) do
    undo[#undo+1]={target=target,index=entry.index,before=target[entry.index],
      value=entry.value,snapshot=copy(entry.value)}
    target[entry.index]=entry.value
  end
  previous[data]=undo
end
function M.api(loader,mod,native,generation)
  local registry=loader.content.phone_contacts;local available=generation==2
  local reason=not available and 'unsupported: phone_contacts has no native target in this dataset' or nil
  local out={available=available,supports=function() return available,reason end}
  local function view(row)
    row=copy(row)
    if row then row.callee=row.calleeKey or row.callee;row.caller=row.callerKey or row.caller end
    return row
  end
  function out:get(id) if not available then return nil,reason end;return view(native:get(id)) end
  function out:has(id) return self:get(id)~=nil end
  function out:each()
    if not available then return function() end end
    local nextRow=native:each()
    return function() local id,row=nextRow();return id,view(row) end
  end
  for _,verb in ipairs({'register','override','patch','remove'}) do
    out[verb]=function(_,id,value)
      if not available then return nil,reason end
      assert(type(id)=='string' and id~='','phone_contacts: id is required')
      if verb=='remove' then native:remove(id);return nil end
      finite(value);assert(type(value)=='table' and value~=Merge.DELETE,'phone_contacts: expected record')
      for key in pairs(value) do assert(registry.spec.fields[key],'phone_contacts: unknown field '..tostring(key)) end
      local ok,err=require('src.mods.Schemas').check(registry.spec,'phone_contacts',id,value,verb)
      assert(ok,err)
      local payload=copy(value)
      for _,direction in ipairs({'callee','caller'}) do
        if payload[direction]~=nil then
          local key=direction..'Key'
          if payload[key]==nil then payload[key]=payload[direction] end
          payload[direction]=nil
        end
      end
      payload.index=indexFor(registry,assert(mounted[loader]),id,value)
      local effective=Merge.deepMerge(verb=='patch' and copy(registry:get(id) or {}) or {},payload,'record')
      nativeRow(loader,id,effective)
      if verb~='patch' then payload=effective end
      native[verb](native,id,payload)
      return out:get(id)
    end
  end
  return out
end
return M
