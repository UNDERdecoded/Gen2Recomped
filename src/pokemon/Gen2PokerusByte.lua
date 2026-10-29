-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- One native MON_PKRS byte reader for lifecycle and experience consumers.
local B={}
function B.read(mon)
 local n=tonumber(mon and mon.pokerus)or 0
 if n~=n or math.abs(n)==math.huge then return 0 end
 return math.max(0,math.floor(n))%256
end
function B.doublesStatExp(mon)return B.read(mon)~=0 end
return B
