-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional ball shortcuts enter the ordinary native bag/catch transaction.
local Ready=require('src.battle.MenuAuxiliary')
local Effects=require('src.inventory.ItemEffects')
local Q={}
local function available(battle)
 local features=package.loaded['src.mods.FeatureOptions']
 return features and features.enabled('quickBall')and require('src.core.GameVersion').isGen3()
  and battle.kind=='wild'and not battle:isDouble()and Ready.ready(battle)
end
local function balls(battle)
 local out={}
 for key,n in pairs(battle.game.save.inventory or{})do
  local def=battle.data.items[key]
  if n>0 and Effects.isBall(key,def)then out[#out+1]=key end
 end
 table.sort(out,function(a,b)
  local x,y=battle.data.items[a],battle.data.items[b]
  local i,j=x and x.index or 65535,y and y.index or 65535
  if i~=j then return i<j end;return tostring(a)<tostring(b)
 end)
 return out
end
function Q.request(battle)
 if not available(battle)then return end
 local input=battle.game.input
 if not(input:wasPressed('l')or input:wasPressed('r'))then return end
 return{game=battle.game,save=battle.game.save,data=battle.data,stack=battle.game.stack,throw=input:wasPressed('r')}
end
function Q.selected(battle)
 local list=balls(battle);local selected=battle.quickItem
 for i,id in ipairs(list)do if id==selected then return id,i,list end end
 return list[1],1,list
end
function Q.dispatch(battle,token)
 if battle.game~=token.game or battle.game.save~=token.save or battle.data~=token.data or battle.game.stack~=token.stack
  or not available(battle)then return true end
 local id,index,list=Q.selected(battle)
 if not id then return true end
 if token.throw then return require('src.ui.BagMenu').throwBall(battle.game,battle,id)end
 battle.quickItem=list[index%#list+1]
 require('src.core.Sound').play(battle.data,'Press_AB');return true
end
function Q.label(battle)
 if not available(battle)then return nil end
 local id=Q.selected(battle);local row=id and battle.data.items[id]
 return row and row.name
end
return Q
