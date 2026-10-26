-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Views=require('src.compat.gen1.SessionView')
local Ids=require('src.compat.gen1.BattleIds')
local Native=require('src.inventory.Bag')
local B={}
local function context(bag,id)
  local game,save=Views.store(bag,'bag');if not game then return end
  local key=Ids.new(game.data):native('items',id)
  if key then return game,save,key end
end
function B.canAdd(bag,id,qty)
  local g,s,key=context(bag,id)
  return g~=nil and Native.canAdd(s,key,qty,g.data)or false
end
function B.add(bag,id,qty)
  local g,s,key=context(bag,id);qty=qty or 1
  if not(g and Native.canAdd(s,key,qty,g.data))then return false,0 end
  local ok=Native.add(s,key,qty,g.data);return ok,ok and qty or 0
end
function B.has(bag,id,qty)
  local g,s,key=context(bag,id)
  return g~=nil and(s.inventory[key]or 0)>=(qty or 1)or false
end
function B.count(bag,id)local g,s,key=context(bag,id);return g and(s.inventory[key]or 0)or 0 end
function B.remove(bag,id,qty)
  local g,s,key=context(bag,id)
  qty=qty or 1
  if type(qty)~='number'or qty~=qty or qty%1~=0 or qty<1 or qty>999 or not g or not B.has(bag,id,qty)then return false end
  Native.remove(s,key,qty or 1);return true
end
return B
