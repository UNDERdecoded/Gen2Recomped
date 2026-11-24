-- Round 82: a pushed block that stops over a pit / the sky / water / lava falls in (sub_0800442E).
--
-- CARTRIDGE BEHAVIOUR (src/object/blockPushed.c sub_080830B8 type 0, asm/src/code_080043E8.s GetTileHazardType /
-- sub_0800442E, asm/src/code_08003FC4.s CreatePitFallFx .. CreateSwampDrownFx):
--   * When the 1 x 1 block's 32 frames are over, sub_0800442E(block): GetTileHazardType looks the act tile under
--     it (UpdateCollisionLayer) up in hazard_list ({act, kind} pairs, 0-terminated, read from the ROM:
--     PushBlock82.HAZARDS); kind 1 -> CreatePitFallFx (FX_FALL_DOWN 0), 2 -> CreateDrownFx (FX_WATER_SPLASH $B),
--     3 -> CreateLavaDrownFx (FX_LAVA_SPLASH $C), 4 -> CreateSwampDrownFx (FX_GREEN_SPLASH $52): a SPECIAL_FX
--     object at the block, the block deleted, and NO tile laid (the hole stays; the tile it left stays the
--     TILE_TYPE_32 / 33 set when the push started).
--   * Else the block is laid as tile $365 (PushBlock.lua, as before).
-- Port gap fixed: PushBlock laid $365 on any tile, so a block pushed off a ledge into the sky ($70:18's three blocks
--   at the top) stood in the air and walled the gap it opened.
local M = {}

local HZ = require("src.zelda.tmc.RomTables").t("PushBlock82.HAZARDS") -- hazard_list {act, kind}
local SPECIAL_FX = 0x0F
M.FX = { [1] = 0x00, [2] = 0x0B, [3] = 0x0C, [4] = 0x52 } -- CreatePitFallFx / Drown / LavaDrown / SwampDrown

-- stand-in list for tests: M.use({ {act, kind}, ... })
local override
function M.use(list) override = list end

-- GetTileHazardType for an act tile: the kind (1..4) or 0
function M.kindOf(act)
  if not act or act == 0 then return 0 end
  if override then
    for _, h in ipairs(override) do if h[1] == act then return h[2] end end
    return 0
  end
  local RT = require("src.zelda.tmc.RomTables")
  if not RT.attached() then return 0 end
  for i = 0, 7 do
    local ok, h = pcall(function() return HZ[i] end)
    if not ok or not h then break end
    local a, k = h.act or h[1], h.kind or h[2]
    if not a or a == 0 then break end
    if a == act then return k or 0 end
  end
  return 0
end

-- sub_0800442E on a pushed block entity: true when it fell / sank (fx made, the caller deletes it)
function M.hazard(f, e)
  local d = f and f._dungeon
  if not (d and d.actAt) then return false end
  local act = d:actAt(math.floor(e.x), math.floor(e.y), e.layer or 1) or 0
  local k = M.kindOf(act)
  if k == 0 then return false end
  if f.addFx then f:addFx(e.x, e.y, SPECIAL_FX, M.FX[k] or 0) end
  return true
end

return M
