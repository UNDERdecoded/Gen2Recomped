-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Field item requests share the native effect and inventory transaction.
local U={}
function U.useField(session,bag,id,target)
 local g,save=require('src.compat.gen1.SessionView').store(bag,'bag')
 local record=require('src.compat.gen1.SessionView').record(session)
 if not(g and record and record:valid()and record.owner==g)then return false,false end
 local key=require('src.compat.gen1.BattleIds').new(g.data):native('items',id)
 if not key or(save.inventory[key]or 0)<1 then return false,false end
 local mon
 if target then mon=require('src.compat.gen1.SourcePokemon').resident(target);if not mon then return false,false end end
 local kind,messages=require('src.inventory.ItemEffects').use(g.data,save,key,mon,nil,nil,require('src.compat.gen1.NativeSession').world(g))
 if kind=='consumed'then
  require('src.inventory.Bag').remove(save,key,1)
  if key=='REPEL'or key=='SUPER_REPEL'or key=='MAX_REPEL'then require('src.ui.RepelPrompt').remember(save,key)end
  return true,true,table.concat(messages or{},'\f')
 end
 return kind=='used',false,type(messages)=='table'and table.concat(messages,'\f')or nil
end
return U
