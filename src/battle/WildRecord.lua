-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Authored native encounters carry an individual into the ordinary battle
-- constructor. Validation is pure and happens before RNG/dex/stack changes.
local M={}
local fields={species=true,level=true,personality=true,ivs=true,item=true,hp=true,status=true,
  moves=true,roamer=true}
local stats={'hp','attack','defense','speed','spatk','spdef'}
local function uint(n,max)return type(n)=='number'and n==n and n>=0 and n<=max and n%1==0 end
function M.validate(data,record)
  if type(record)~='table'then return nil,'encounter record required'end
  for key in pairs(record)do if not fields[key]then return nil,'unsupported encounter field: '..tostring(key)end end
  if not(data.pokemon and data.pokemon[record.species])then return nil,'unknown native species'end
  if not(uint(record.level,100)and record.level>=1)then return nil,'invalid encounter level'end
  local out={species=record.species,level=record.level}
  if record.personality~=nil then
    if not uint(record.personality,4294967295)then return nil,'invalid encounter personality'end
    out.personality=record.personality
  end
  if record.ivs~=nil then
    if type(record.ivs)~='table'then return nil,'invalid encounter IVs'end
    out.ivs={}
    for _,key in ipairs(stats)do
      if not uint(record.ivs[key],31)then return nil,'invalid encounter IV '..key end
      out.ivs[key]=record.ivs[key]
    end
    for key in pairs(record.ivs)do if out.ivs[key]==nil then return nil,'unknown encounter IV '..tostring(key)end end
  end
  if record.item~=nil then
    if record.item~=false and not(data.items and data.items[record.item])then return nil,'unknown encounter item'end
    out.item=record.item
  end
  if record.hp~=nil then
    if not(uint(record.hp,65535)and record.hp>0)then return nil,'invalid encounter HP'end
    out.hp=record.hp
  end
  if record.status~=nil then
    if not uint(record.status,255)or record.status>7 and not({[8]=true,[16]=true,[32]=true,[64]=true,[128]=true})[record.status]then
      return nil,'invalid encounter status'
    end
    out.status=record.status
  end
  if record.moves~=nil then
    if type(record.moves)~='table'or#record.moves<1 or#record.moves>4 then return nil,'invalid encounter moves'end
    out.moves={}
    for i,row in ipairs(record.moves)do
      local id=type(row)=='table'and row.id or row
      local def=data.moves and data.moves[id]
      if not def then return nil,'unknown encounter move'end
      local pp=type(row)=='table'and row.pp or def.pp
      if not(uint(pp,255)and pp<=(def.pp or 0))then return nil,'invalid encounter PP'end
      out.moves[i]={id=id,pp=pp}
    end
    for i in pairs(record.moves)do
      if not uint(i,4)or i<1 or i>#out.moves then return nil,'invalid encounter move slot'end
    end
  end
  if record.roamer~=nil and type(record.roamer)~='boolean'then return nil,'invalid roaming encounter'end
  out.roamer=record.roamer
  return out
end
function M.apply(data,mon,record)
  if record.personality~=nil or record.ivs then
    require('src.pokemon.Pokemon').applySeed(data,mon,{personality=record.personality,ivs=record.ivs})
  end
  if record.item~=nil then mon.item=record.item or nil end
  if record.moves then mon.moves=record.moves end
  if record.hp then mon.hp=math.min(record.hp,mon.stats.hp)end
  if record.status~=nil then
    local bits=record.status
    mon.status=bits>0 and(bits<=7 and'SLP'or({[8]='PSN',[16]='BRN',[32]='FRZ',[64]='PAR',[128]='PSN'})[bits])or nil
    mon.sleepTurns=bits>0 and bits<=7 and bits or nil;mon.toxic=bits==128 or nil
  end
end
return M
