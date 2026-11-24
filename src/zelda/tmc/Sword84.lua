-- Round 84: the sword swing's hurtType by sword.
--
-- CARTRIDGE BEHAVIOUR (src/playerItem.c ItemInit, src/playerItemDefinitions.c):
--   * PLAYER_ITEM_SWORD is a MULTI_FORM entry of gPlayerItemDefinitions:
--     the definition is gPlayerItemDefinition_0[field_0x68 - 1], field_0x68
--     being the sword item (1 Smith's .. 6 Four Sword); ItemInit copies its
--     hurtType to the swing (the collision matrix row the swing uses against
--     an enemy's hitType: the damage, knockback, iframes).
--   * The spin (hurtType 8 / 9 / $A), the thrust ($B / $C) and the down thrust
--     ($18 - $1A) are set by playerItemSword.c itself (SwordSkills.lua).
-- Port gap fixed: every sword swung with hurtType 4 (the Smith's Sword's row);
-- the White / Red / Blue swords' row is 5 and the Four Sword's 6 (a Ball and
-- Chain Soldier takes 3 from the Blue Sword, not 2).  The rows are read from
-- the player's ROM (RomTablesCat "Sword84.DEFS").
local M = {}

M.DEFS = require("src.zelda.tmc.RomTables").t("Sword84.DEFS")
M.FALLBACK = 4 -- the swing's hurtType before round 84 (a cache without the table)

-- the hurtType of a swing with sword item `item` (1 .. 6)
function M.hurt(item)
  if type(item) ~= "number" or item < 1 or item > 6 then return M.FALLBACK end
  local ok, row = pcall(function() return M.DEFS[item] end)
  if ok and type(row) == "table" and type(row.hurt) == "number" and row.hurt > 0 then return row.hurt end
  return M.FALLBACK
end

-- the hurtType of Link's current swing (the sword on his sword button, as Player:swordPart draws it)
function M.hurtOf(f, p)
  local item = f and f.equipped and f:equipped((p and p.swordButton) or "b")
  if type(item) ~= "number" or item < 1 or item > 6 then item = f and f.equipped and f:equipped("a") end
  return M.hurt(item)
end

return M
