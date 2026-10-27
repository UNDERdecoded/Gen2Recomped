-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Party/storage operations over the native save. The legacy Gen2 count()
-- counts residents, unlike the shared storage module's box-count query.
local Storage=require("src.pokemon.Boxes")
local Mail=require("src.pokemon.Gen2Mail")
local Party=require("src.pokemon.Party")
local Strings=require("src.core.Strings")
local B={PARTY_SIZE=6}
local function valid(index,max) return type(index)=="number" and index>=1 and index<=max and index%1==0 end
function B.defaultName(n) return "BOX"..tostring(n) end
function B.name(save,n) return save and save.boxNames and save.boxNames[n] or B.defaultName(n) end
function B.rename(save,n,name)
  if not save or not valid(n,Storage.count()) or type(name)~="string" then return false end
  save.boxNames=save.boxNames or {};save.boxNames[n]=name;return true
end
function B.box(save,n)
  if not save then return {} end
  n=n or save.currentBox or 1
  if not valid(n,Storage.count()) then return {} end
  return Storage.ensure(save)[n]
end
function B.count(save,n) return Storage.used(B.box(save,n)) end
function B.isFull(save,n) return B.count(save,n)>=Storage.capacity() end
function B.setCurrent(save,n)
  if not save or not valid(n,Storage.count()) then return false end
  Storage.ensure(save);save.currentBox=n;return true
end
function B.healthyCount(party)
  local n=0;for _,mon in ipairs(party or {}) do if (mon.hp or 0)>0 and not Party.isEgg(mon) then n=n+1 end end
  return n
end
function B.canUsePc(save)
  if not save or #(save.party or {})==0 then return false,Strings("You'll need a\nPOKéMON to call\fwith.") end
  return true
end
function B.canDeposit(save,n,box)
  local mon=save and save.party and save.party[n]
  if not mon then return false,"There is no POKéMON there." end
  box=box or save.currentBox or 1
  if not valid(box,Storage.count()) then return false,"Invalid BOX." end
  if B.isFull(save,box) then return false,"The BOX is full." end
  if (mon.hp or 0)>0 and not Party.isEgg(mon) and B.healthyCount(save.party)<=1 then return false,Strings("You can't deposit\nthe last POKéMON!") end
  if Mail.monHoldsMail(mon) then return false,"Remove MAIL." end
  return true
end
function B.restorePP(mon,data)
  require("src.pokemon.Pokemon").restorePP(mon,data and data.moves)
end
local function recover(mon,data)
  if not mon.stats and data and data.pokemon then require("src.pokemon.Stats").ensure(data.pokemon[mon.species],mon) end
  mon.status,mon.statusTurns=nil,nil
  mon.hp=Party.isEgg(mon) and 0 or (mon.stats and mon.stats.hp or mon.maxHp or mon.hp)
end
function B.enterBox(mon,data)
  if mon then B.restorePP(mon,data);recover(mon,data) end
  return mon
end
local function remove(box,n)
  local mon=box[n];box[n]=nil
  -- Shift the occupied suffix without trusting Lua's length on sparse imports.
  local nextSlot=n+1
  while nextSlot<=Storage.capacity() do
    if box[nextSlot]~=nil then box[n]=box[nextSlot];box[nextSlot]=nil;n=n+1 end
    nextSlot=nextSlot+1
  end
  return mon
end
function B.deposit(save,n,box,data)
  local ok,why=B.canDeposit(save,n,box);if not ok then return false,why end
  local target=B.box(save,box);local to=Storage.firstFree(target)
  local mon=table.remove(save.party,n);Mail.removeSlot(save,n)
  target[to]=mon;B.enterBox(mon,data);return true,mon
end
function B.canWithdraw(save,box,n)
  if not save or not valid(n,Storage.capacity()) or not B.box(save,box)[n] then return false,"There is no POKéMON there." end
  if #(save.party or {})>=6 then return false,Strings("You can't take\nany more POKéMON.") end
  return true
end
function B.withdraw(save,box,n,data)
  local ok,why=B.canWithdraw(save,box,n);if not ok then return false,why end
  local mon=remove(B.box(save,box),n);recover(mon,data)
  save.party=save.party or {};save.party[#save.party+1]=mon;return true,mon
end
function B.release(save,box,n)
  local target=B.box(save,box);if not valid(n,Storage.capacity()) or not target[n] then return false,"There is no POKéMON there." end
  if Party.isEgg(target[n]) then return false,"You can't release an EGG!" end
  return true,remove(target,n)
end
function B.releaseFromParty(save,n)
  local mon=save and save.party and save.party[n]
  if not mon then return false,"There is no POKéMON there." end
  if Party.isEgg(mon) then return false,"You can't release an EGG!" end
  local removed=table.remove(save.party,n);Mail.removeSlot(save,n);return true,removed
end
function B.move(save,from,n,to)
  if from==to then return false,"It's already there." end
  if not valid(to,Storage.count()) then return false,"Invalid BOX." end
  local source=B.box(save,from);if not source[n] then return false,"There is no POKéMON there." end
  if B.isFull(save,to) then return false,"The BOX is full." end
  local target=B.box(save,to);local mon=remove(source,n)
  target[Storage.firstFree(target)]=mon;return true,mon
end
return setmetatable(B,{__index=function(_,key)
  if key=="NUM_BOXES" then return Storage.count() end
  if key=="MONS_PER_BOX" then return Storage.capacity() end
end})
