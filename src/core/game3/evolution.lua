-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local E={}
function E.levelTarget(value,session)
 local mon,g=require('src.compat.gen1.SourcePokemon').resolve(value)
 if session then
  local r=require('src.compat.gen1.SessionView').record(session)
  assert(r and r:valid()and r.owner==g,'foreign evolution session')
 end
 local key=require('src.pokemon.Evolution').pendingFor(g,mon,{kind='levelup'})
 return key and require('src.compat.gen1.BattleIds').new(g.data):read('pokemon',key)
end
return E
