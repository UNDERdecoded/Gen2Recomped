-- Round 96: a bomb lying over a pit / water / lava / swamp is gone at once, as on the cartridge.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * src/playerItem/playerItemBomb.c PlayerItemBomb_Action1 (a placed bomb, or one landed after a throw):
--     `if (!sub_0800442E(super)) RegisterCarryEntity(super);` every frame.
--   * asm/src/code_080043E8.s sub_0800442E -> GetTileHazardType: the act tile under the entity (UpdateCollisionLayer)
--     looked up in hazard_list {ACT 13 -> 1, 16 -> 2, 17 -> 2, 90 -> 3, 19 -> 4}; a hazard calls
--     CreatePitFallFx / CreateDrownFx / CreateLavaDrownFx / CreateSwampDrownFx (asm/src/code_08003FC4.s: a SPECIAL_FX
--     of FX_FALL_DOWN / FX_WATER_SPLASH / FX_LAVA_SPLASH / FX_GREEN_SPLASH at the bomb, then DeleteEntity).
--   The port's Bombs.updateBomb only checked the throw's landing (carryFrame's FALLS): a bomb set down at the edge of
--   a pit (its spot is Link's front point, Bombs.OFFS) stayed floating over the pit and went off there.
-- The act-tile numbers are the engine's enum values (include/tiles.h ACT_TILE_13 / 16 / 17 / 19 / 90), the FX ids
-- the SPECIAL_FX type enum (include/effects.h); no game data here.
--
-- Wraps Bombs.updateBomb at require time (guard B.bomb96Installed); listed in R27A.MODULES.
local M = {}

M.SPECIAL_FX = 0x0F
-- act tile -> the FX made (hazard_list order: pit, water, deep water, lava, swamp)
M.HAZARD_FX = { [0x0D] = 0x00, [0x10] = 0x0B, [0x11] = 0x0B, [0x5A] = 0x0C, [0x13] = 0x52 }

-- the act tile under (x, y) on a layer (nil for a special tile)
function M.actAt(f, x, y, layer)
  local r = f.room
  if not (r and r.tileType) then return nil end
  local tt = r:tileType(layer or 1, math.floor(x / 16), math.floor(y / 16))
  if not tt or tt >= 0x4000 then return nil end
  return f.assets and f.assets.actTile and f.assets.actTile[tt]
end

-- GetTileHazardType for a bomb: the FX type, or nil
function M.hazard(f, b)
  return M.HAZARD_FX[M.actAt(f, b.x, b.y, b.layer or 1) or -1]
end

-- PlayerItemBomb_Action1's sub_0800442E: true when the bomb was removed
function M.check(f, b)
  if b.deleted or b.action ~= 1 or (b.z or 0) > 0 then return false end
  local fx = M.hazard(f, b)
  if not fx then return false end
  if f.addFx then f:addFx(b.x, b.y, M.SPECIAL_FX, fx) end
  b.deleted = true
  return true
end

function M.install()
  local ok, B = pcall(require, "src.zelda.tmc.Bombs")
  if not ok or type(B) ~= "table" or B.bomb96Installed then return end
  B.bomb96Installed = true
  local upd0 = B.updateBomb
  B.updateBomb = function(f, b)
    if M.check(f, b) then return end
    return upd0(f, b)
  end
end
M.install()

return M
