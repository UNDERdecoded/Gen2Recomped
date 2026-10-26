-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Source=require('src.compat.gen1.SourcePokemon')
local Ids=require('src.compat.gen1.BattleIds')
local M={}
function M.relearnableMoves(value)
 local mon,g=Source.resolve(value);local d=g.data.pokemon[mon.species];local ids=Ids.new(g.data)
 local known,seen,out={},{},{}
 for _,m in ipairs(mon.moves or{})do known[m.id]=true end
 local function add(key)
  local n=ids:read('moves',key)
  if n and not known[key]and not seen[key]then out[#out+1]=n;seen[key]=true end
 end
 for _,key in ipairs(d.level1Moves or{})do add(key)end
 for _,row in ipairs(d.learnset or{})do if row.level<=mon.level then add(row.move)end end
 return out
end
return M
