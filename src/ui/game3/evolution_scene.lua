-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Flow=require('src.compat.gen1.UiFlow')
local Source=require('src.compat.gen1.SourcePokemon')
local Ids=require('src.compat.gen1.BattleIds')
local E={}
local active
function E.isOpen()return active~=nil and active:valid()end
function E.start(value,target,opts)
 opts=opts or{};if E.isOpen()then return false end
 local mon,known,g=Source.resident(value);if not mon then return false,'evolution requires a live party member'end
 local member=false;for _,m in ipairs(g.save.party or{})do if m==mon then member=true end end
 if not member then return false,'evolution requires the current party'end
 local key=Ids.new(g.data):native('pokemon',target);if not key then return false,'unknown evolution species'end
 local expected,evo=require('src.pokemon.Evolution').pendingFor(g,mon,{kind='levelup'})
 if key~=expected then return false,'evolution target changed'end
 local flow,why=Flow.new(function(...)active=nil;if opts.onDone then opts.onDone(...)end end)
 if not flow then return false,why end
 active=flow
 local ok,err=pcall(function()
  flow:push(require('src.ui.Gen3EvolutionState').new(g,mon,key,function(...)flow:finish(...)end,opts.canStop==false and'ITEM'or'LEVEL',evo))
 end)
 if not ok then flow:retire();active=nil;error(err,0)end
 return true
end
return E
