-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- One rolling four-move window for source and native GSC arrival paths.
local L={}
function L.ids(def,level,native)
 local known={}
 local function add(id)
  for _,old in ipairs(known)do if old==id then return end end
  known[#known+1]=id
  if #known>4 then table.remove(known,1)end
 end
 if native and def and not def.levelMoves then
  for _,id in ipairs(def.level1Moves or{})do add(id)end
 end
 for _,row in ipairs(def and (def.levelMoves or (native and def.learnset))or{})do
  if row.level<=level then add(row.move)end
 end
 return known
end
function L.slots(def,level,moves)
 local result={}
 for _,id in ipairs(L.ids(def,level,def and def.levelMoves==nil and def.learnset~=nil))do
  local pp=moves and moves[id]and moves[id].pp or 0
  result[#result+1]={id=id,pp=pp,maxPp=pp}
 end
 return result
end
function L.learn(mon,id,data)
 mon.moves=mon.moves or{}
 for _,slot in ipairs(mon.moves)do if slot.id==id then return false,'known'end end
 local def=data and data.moves and data.moves[id]
 local pp=def and def.pp or 0
 local slot={id=id,pp=pp,maxPp=pp}
 if #mon.moves>=4 then return false,'full',slot end
 mon.moves[#mon.moves+1]=slot
 require('src.mods.Runtime').emit('pokemon.move_learned',{mon=mon,moveId=id})
 return true
end
return L
