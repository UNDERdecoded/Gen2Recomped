-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Flow=require('src.compat.gen1.UiFlow')
local Source=require('src.compat.gen1.SourcePokemon')
local Ids=require('src.compat.gen1.BattleIds')
local R={}
local active
function R.isOpen()return active~=nil and active:valid()end
function R.show(value,opts)
 opts=opts or{};if R.isOpen()then return false end
 local mon,known,g=Source.resident(value);if not mon then return false,'move learning requires a live party member'end
 local member=false;for _,m in ipairs(g.save.party or{})do if m==mon then member=true end end
 if not member then return false end
 local flow,why=Flow.new(function(...)active=nil;if opts.onDone then opts.onDone(...)end end)
 if not flow then return false,why end
 active=flow;local ids=Ids.new(g.data)
 local function choose()
  if not flow:valid()then flow:retire();return end
  local entries={}
  for _,number in ipairs(require('src.core.game3.move_learn').relearnableMoves(value))do
   local key=ids:native('moves',number)
   if key then entries[#entries+1]={label=g.data.moves[key].name,value=key}end
  end
  if #entries==0 then flow:finish(false);return end
  local list
  list=require('src.ui.ListMenu').new(g,'Remember a move',entries,{onCancel=function()flow:finish(false)end,
   onChoose=function(row)
    if not flow:valid()then flow:retire();return end
    g.stack:removeAll({list})
    flow:admit(function()
     require('src.pokemon.Evolution').learnMoves(g,mon,{row.value},function()
      local learned=false;for _,move in ipairs(mon.moves or{})do if move.id==row.value then learned=true end end
      if learned then flow:finish(true)else choose()end
     end)
    end)
   end})
  flow:push(list)
 end
 local ok,err=pcall(choose)
 if not ok then flow:retire();active=nil;error(err,0)end
 return R.isOpen()
end
return R
