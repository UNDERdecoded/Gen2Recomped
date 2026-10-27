-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Reuse asks through native dialogue and consumes through native item effects.
local P={}
local remembered=setmetatable({},{__mode='k'})
function P.remember(save,id)if type(save)=='table'then remembered[save]=id end end
function P.item(game)
 local inventory=game.save.inventory or{}
 local last=remembered[game.save]
 if last and(inventory[last]or 0)>0 then return last end
 for _,id in ipairs{'MAX_REPEL','SUPER_REPEL','REPEL'}do if(inventory[id]or 0)>0 then return id end end
end
function P.show(game)
 local features=package.loaded['src.mods.FeatureOptions'];local provider=features and features.provider('repelPrompt')
 local id=provider and P.item(game);if not id then return false end
 local flow= require('src.core.Game3')._withCallbackOwner(provider.who,function()return require('src.compat.gen1.UiFlow').new()end)
 if not flow then return false end
 local name=game.data.items[id]and game.data.items[id].name or id
 local text=features.call(provider,'language')=='de'and('Noch einmal '..name..' verwenden?')or('Use another '..name..'?')
 local TextBox=require('src.render.TextBox')
 flow:push(TextBox.new(game,text,nil,{choice=function(yes)
  if not flow:valid()then flow:retire();return end
  if not yes or(game.save.inventory[id]or 0)<1 then flow:finish();return end
  local result,messages=require('src.inventory.ItemEffects').use(game.data,game.save,id)
  if result~='consumed'then flow:finish();return end
  require('src.inventory.Bag').remove(game.save,id,1);P.remember(game.save,id)
  flow:push(TextBox.new(game,table.concat(messages or{},'\f'),function()flow:finish()end))
 end}))
 return true
end
return P
