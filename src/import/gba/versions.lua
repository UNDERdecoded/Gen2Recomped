-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Shared retail portrait indices already used by the native FR/LG importer.
local V={TRAINER_PIC_RED=135,TRAINER_PIC_LEAF=136}
return setmetatable(V,{__index=function(_,key)
 if key=='BUILD'then return require('src.core.GameVersion').get()end
end})
