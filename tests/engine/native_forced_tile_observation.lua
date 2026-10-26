-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local MB=require('src.compat.gen1.MetatileBehavior')
local before=package.loaded['src.core.Game']
local F=require('src.core.game3.forced_movement')
T.eq(package.loaded['src.core.Game'],before,'a pure terrain query cannot bootstrap a game')
local original=V.get()
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 V.set(edition);local rse=edition~='firered'and edition~='leafgreen'
 T.eq(F.isRse(),rse)
 for raw=0,255 do
  -- Independent cartridge-byte oracle. Hoenn uses ICE at $20 and has
  -- secret-base mats, muddy slope and cracked floor; FRLG has spin arrows.
  local expected=raw==0x13 or raw==(rse and 0x20 or 0x23)
   or raw>=0x40 and raw<=0x48 or raw>=0x50 and raw<=0x53
   or not rse and raw>=0x54 and raw<=0x57
   or rse and(raw==0xBB or raw==0xBC or raw==0xD0 or raw==0xD2)
  T.eq(F.isForcedMovementTile(MB.fromRaw(edition,raw)),expected,edition..' raw terrain '..raw)
 end
 for _,value in ipairs{false,true,'64',{},.5,-1,math.huge,0/0}do T.eq(F.isForcedMovementTile(value),false)end
 T.eq(F.isForcedMovementTile(nil),false)
 for _,name in ipairs{'MUDDY_SLOPE','CRACKED_FLOOR','SECRET_BASE_JUMP_MAT','SECRET_BASE_SPIN_MAT'}do
  T.eq(F.isForcedMovementTile(MB.require(name)),rse,'edition-specific semantic IDs are not raw FRLG bytes')
 end
end
for _,edition in ipairs{'red','gold','platinum'}do
 V.set(edition);T.eq(F.isRse(),false)
 for _,name in ipairs{'ICE','WALK_SOUTH','SPIN_LEFT','MUDDY_SLOPE'}do T.eq(F.isForcedMovementTile(MB.require(name)),false)end
end
V.set(original);T.eq(package.loaded['src.core.Game'],before,'queries never construct a native simulation')
T.finish('native semantic forced terrain observation across GBA editions')
