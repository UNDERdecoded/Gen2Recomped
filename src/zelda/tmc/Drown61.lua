-- Round 61: Minish Link drowns without the Flippers (player.c SurfaceAction_ShallowWater / SurfaceAction_Water,
-- playerUtils.c sub_08079C30).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * The surface under Link is gMapActTileToSurfaceType[act tile] (Hole42.surfaceOf, read from the ROM).
--   * SurfaceAction_ShallowWater: for PL_MINISH it is SurfaceAction_Water (full-size Link only splashes).
--   * SurfaceAction_Water: sub_08079C30 TRUE -> sub_08074808: without ITEM_FLIPPERS -> PLAYER_DROWN.
--   * sub_08079C30: FALSE while gPlayerState.field_0x14 (a lily pad, a board, a platform held him up this frame)
--     or PL_FLAGS2 (the large lily pad); else TRUE at once for PL_MINISH (full-size Link needs the same surface at
--     (0, -1), (2, 0) and (-2, 0) -- Dungeon:checkFall's own test).
-- The supports (field_0x14 / PL_FLAGS2) are Dungeon:checkFall's early returns (onLily, Objects37.supports,
-- Board61.supports, bossSupport), so this module only decides "Minish, water surface, no Flippers".
-- SIMPLIFIED: PlayerDrown's Minish branch (ANIM_DROWN_MINISH for 60 frames, SFX_WATER_SPLASH) is the port's
--   existing drown (sound, -2 health, RespawnPlayer at the last safe tile); Minish Link with the Flippers on
--   shallow water does not start swimming (the port's swim is for deep water only).
local M = {}
M.ITEM_FLIPPERS = 0x46
M.SURFACE_SHALLOW_WATER, M.SURFACE_WATER, M.SURFACE_20 = 0x18, 0x19, 0x20

local function surface(a) return a and require("src.zelda.tmc.Hole42").surfaceOf(a) end

-- the act tile `a` (at Link's (0, -1)) is a water surface for Minish Link
function M.waterFor(a)
  local s = surface(a)
  return s == M.SURFACE_SHALLOW_WATER or s == M.SURFACE_WATER or s == M.SURFACE_20
end

-- Minish Link on water without the Flippers: PLAYER_DROWN
function M.drowns(d, p, a)
  if not p.minish then return false end
  if (d.field:inventory(M.ITEM_FLIPPERS) or 0) ~= 0 then return false end
  return M.waterFor(a)
end

-- a tile centre Minish Link may not respawn on (shallow water is not safe ground for him)
function M.unsafe(d, p, x, y)
  if not p.minish then return false end
  return M.waterFor(d:actAt(x, y - 1, p.layer)) and (d.field:inventory(M.ITEM_FLIPPERS) or 0) == 0
end

return M
