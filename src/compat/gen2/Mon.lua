-- Copyright (c) 2026 Roxas2712. See the offered contribution licence:
-- https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Source stat/signature methods over the actual native Pokemon owner.
-- The inherited older RNG constructor keeps its existing signature;
-- source options-record construction remains a separate capability.
local Native=require('src.pokemon.Pokemon')
local Mon={}
function Mon.hpDV(dvs)return require('src.pokemon.Stats').hpDV(dvs)end
function Mon.stats(base,dvs,level,statExp)
  return require('src.pokemon.Stats').calcGen2(base,dvs,level,statExp)
end
function Mon.syncIdentity(mon,data)return Native.syncIdentity(data,mon)end
function Mon.refreshStats(mon,data)return Native.refreshStats(data,mon)end
return setmetatable(Mon,{__index=Native})
