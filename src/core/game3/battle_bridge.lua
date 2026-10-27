-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source requests enter the same native encounter transaction and completion.
local B={}
function B.startWild(mod,game,encounter,opts)
  return require('src.compat.gen1.BattleRequests').startWild(game,encounter,opts)
end
return B
