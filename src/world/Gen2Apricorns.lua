-- Copyright (c) 2026 Roxas2712. See the PR contribution permission in docs/native-gen2-apricorn-selection.md.
-- Native recipe order for Kurt's selection; ball delivery remains script-owned.
local M={}
local Version=require('src.core.GameVersion')
local function stock(version)return version=='gold' or version=='silver' or version=='crystal'end
local function item(value)
  local id=type(value)=='string' and value:match('^ITEM_(%d%d%d)$')
  id=tonumber(id)
  return id and id>0 and id<255 and id or nil
end
function M.rows(data)
  local pool=data and data.map_scripts
  local source=pool and pool.apricornBalls
  local out={}
  if source~=nil then
    if type(source)~='table' or pool.apricornInfo and pool.apricornInfo.complete==false then return out end
    for _,row in ipairs(source)do
      if type(row)~='table' or not item(row.apricorn) or not item(row.ball) then return {} end
      out[#out+1]={index=#out+1,apricorn=row.apricorn,ball=row.ball}
    end
    return out
  end
  -- Historical caches have no recipe table. Keep selection available until
  -- reimport; do not invent their missing ball mappings.
  local legacy={85,89,92,93,97,99,101}
  for i,id in ipairs(legacy)do out[i]={index=i,apricorn=string.format('ITEM_%03d',id)}end
  return out
end
function M.inBag(data,save)
  local out={}
  local nativeStock=stock(Version.get())
  for _,row in ipairs(M.rows(data))do
    local n=tonumber(save and save.inventory and save.inventory[row.apricorn])
    if n and n==n and n<math.huge and n>=1 then
      local quantity=math.floor(n)
      if nativeStock then quantity=math.min(99,quantity)end
      out[#out+1]={index=row.index,apricorn=row.apricorn,ball=row.ball,
        item=item(row.apricorn),quantity=quantity}
    end
  end
  return out
end
return M
