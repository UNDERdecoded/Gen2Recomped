-- Copyright (c) 2026 Roxas2712. See the offered PR contribution permission in docs/native-gen2-phone-book.md.
-- Native ten-byte order beside the existing numeric registration set. Reads
-- retain legacy overflow entries; no save or contact ID is renumbered.
local M = { SIZE=10 }
local function valid(id)
  return type(id)=='number' and id%1==0 and id>=1 and id<=255
end
local function registered(save)
  if type(save.g2Phone)~='table' then save.g2Phone={} end
  return save.g2Phone
end
function M.slots(save)
  local set=registered(save)
  local slots=type(save.g2PhoneSlots)=='table' and save.g2PhoneSlots or {}
  save.g2PhoneSlots=slots
  local seen={}
  for i=1,M.SIZE do
    local id=slots[i]
    if valid(id) and set[id] and not seen[id] then seen[id]=true
    else slots[i]=0 end
  end
  local pending={}
  for id,on in pairs(set) do
    if on and valid(id) and not seen[id] then pending[#pending+1]=id end
  end
  table.sort(pending)
  local cursor=1
  for i=1,M.SIZE do
    if slots[i]==0 and pending[cursor] then slots[i]=pending[cursor];cursor=cursor+1 end
  end
  return slots
end
function M.contacts(save)
  local slots,out=M.slots(save),{}
  for i=1,M.SIZE do out[i]=slots[i] end
  return out
end
function M.has(save,id)
  if id==0 then
    for _,value in ipairs(M.slots(save)) do if value==0 then return true end end
    return false
  end
  return valid(id) and registered(save)[id] and true or false
end
function M.permanent(data)
  local out={}
  local pool=data and data.map_scripts and data.map_scripts.phone
  local constants=data and data.constants or {}
  local order=constants.phoneContactOrder or {}
  local version=require('src.core.GameVersion').get()
  local retail=version=='gold' or version=='silver' or version=='crystal'
  for id,row in pairs(pool or {}) do
    if valid(id) and type(row)=='table' and not (row.class and row.class~=0) then
      local number=row.contactNumber
      if number==1 or number==4 or number==nil and
          (order[id+1]=='PHONE_MOM' or order[id+1]=='PHONE_ELM'
            or retail and constants.phoneContactOrder==nil and (id==1 or id==4)) then out[id]=true end
    end
  end
  -- Before import, the retail constants still reserve their two slots. A
  -- custom cartridge receives no guessed retail identities.
  if pool==nil and retail and constants.phoneContactOrder==nil then out[1],out[4]=true,true end
  return out
end
function M.remainingSlots(data,save,id)
  local missing=0
  for permanent in pairs(M.permanent(data)) do
    if permanent~=id and not M.has(save,permanent) then missing=missing+1 end
  end
  return math.max(0,M.SIZE-missing)
end
function M.openSlot(data,save,id)
  local slots=M.slots(save)
  for i=1,M.remainingSlots(data,save,id) do if slots[i]==0 then return i end end
end
function M.add(data,save,id)
  if not valid(id) then return false,'unknown' end
  local pool=data and data.map_scripts and data.map_scripts.phone
  if pool and type(pool[id])~='table' then return false,'unknown' end
  if M.has(save,id) then return false,'already' end
  local slot=M.openSlot(data,save,id)
  if not slot then return false,'full' end
  registered(save)[id]=true;save.g2PhoneSlots[slot]=id
  return true
end
function M.remove(save,id)
  local slots=M.slots(save)
  for i=1,M.SIZE do
    if slots[i]==id then
      slots[i]=0
      if id~=0 then registered(save)[id]=nil end
      return true
    end
  end
  -- An old oversized flat set remains recoverable, including deletion of an
  -- entry that could not fit into the ten hardware slots yet.
  if valid(id) and registered(save)[id] then registered(save)[id]=nil;return true end
  return false
end
function M.deleteAt(save,slot)
  if type(slot)~='number' or slot%1~=0 or slot<1 or slot>M.SIZE then return false end
  local slots=M.slots(save);local id=slots[slot]
  if id==0 then return false end
  registered(save)[id]=nil;slots[slot]=0
  local write=1
  for read=1,M.SIZE do
    if slots[read]~=0 then slots[write]=slots[read];write=write+1 end
  end
  for i=write,M.SIZE do slots[i]=0 end
  return true
end
function M.canDelete(data,id)
  local pool=data and data.map_scripts and data.map_scripts.phone
  return valid(id) and pool and type(pool[id])=='table' and not M.permanent(data)[id] or false
end
return M
