-- Round 56: the Flippers quest, book 2 (Dr. Left) and fixes met on the way.
--
--   * deathCheck(p): playerUtils.c sub_08079B24 runs every frame: Link's
--     health 0 (not PLAYER_MINISHDIE) -> the death.  The port only died from
--     Player:hurt; the water / pit / lava respawn (RespawnPlayer + ModHealth(-2),
--     Dungeon.lua) and PlayerFall's landing took the last hearts and left Link
--     walking at 0 health.  Hooked after those two ModHealth calls.
local M = {}

local SFX_PLY_DIE = 0x87

function M.deathCheck(p)
  local f = p and p.field
  if not f or not f.save or not f.save.stats then return false end
  if (f.save.stats.health or 0) > 0 or p.state == "dead" then return false end
  p.state = "dead"
  p.timer = 90
  p.extUpdate = nil
  p.falling = nil
  if f.sound then f:sound(SFX_PLY_DIE) end
  return true
end

return M
