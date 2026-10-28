-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Shared FR/LG Thumb sites from cartridge-matching pret/pokefirered ELFs
-- (ce6406d8c2eaf46d543c8a2606de0c3cb1951982). The importer authenticates the
-- cartridge; the native operand reader still checks every instruction.
local M={REVISION=1}
local supported={
 ['41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc']=true,
 ['574fa542ffebb14be69902d1d36f1ec0a4afd71e']=true,
}
local sites={AT_HAND_X=0x4aaca,AT_HAND_Y=0x4aacc,
 AT_DEMO_X=0x4aab0,AT_DEMO_Y=0x4aab2,AT_FRAMES=0x4b688,
 AT_TARGET_DY=0x4b6ae,AT_ARC=0x4b6b2,AT_FOE_DY=0x4ab12,
 AT_FOE_WAIT=0x4b876,AT_FADE=0x4b2b6,AT_RISE=0x4b510,
 MOV_R0=0x2000,MOV_R2=0x2200,MOV_HAND_X=0x2500,MOV_HAND_Y=0x2400,
 ADD_R0=0x3000,CMP_R0=0x2800}
function M.forSha1(hash)
 if not supported[hash]then return nil end
 local copy={};for key,value in pairs(sites)do copy[key]=value end
 return copy
end
return M
