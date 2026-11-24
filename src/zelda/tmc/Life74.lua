-- Round 74: HandlePlayerLife's death check every frame (interrupts.c HandlePlayerLife -> playerUtils.c
-- sub_08079B24 -> sub_08079708).
--
-- The cartridge runs sub_08079B24 at the top of every PlayerUpdate (while the player entity is not disabled):
-- health 0 and not PLAYER_MINISHDIE -> knockback cleared; with field_0x7 == 0:
--   * swim_state != 0 -> RespawnPlayer, then the death;
--   * else, not field_0x14 / not in a minecart: z < 0 (in the air) -> wait for the landing (jump_status $41);
--     not PL_FLAGS2 and sub_08079D48 (no safe floor here) -> wait (field_0xa |= $10);
--   * otherwise the death (sub_08079708: PL_STATE_DIE).
-- The port only died inside Player:hurt and a few hand-made checks (Story56.deathCheck after the water / pit
-- respawn and PlayerFall, the bosses).  A damage path that only called ModHealth -- gibdo.c sub_08037B10 (the
-- Gibdo's bite while it holds Link) -- left Link alive at 0 hp: round 73 saw him held / walking at hp 0 with no
-- game over (the Lantern's burn state on).  On the cartridge sub_08037B10 frees Link at 0 (sub_08037A58) and the
-- next HandlePlayerLife starts the death.
local M = {}

-- states in which the port's Player:update is Link's own frame (not a scene, a fall, a warp or the item get)
local SKIP = { dead = true, portal = true, itemget = true }

-- true = the death was started this frame
function M.frame(p)
  local f = p and p.field
  if not f or type(f.save) ~= "table" or type(f.save.stats) ~= "table" then return false end
  if (f.save.stats.health or 0) > 0 then return false end
  if SKIP[p.state] or p.minishDie or p.falling or p.fall or p.inCart then return false end -- PLAYER_MINISHDIE / PlayerFall / the minecart (field_0x14)
  if f.playerScript or f.transition or f.gameOver then return false end -- EntityDisabled / no PlayerUpdate
  if p.swimming then return false end -- swim_state: the port's water respawn path (Dungeon.lua) runs the death itself
  if (p.z or 0) > 0 or p.jumping or p.ledge or p.hop42 then return false end -- z < 0: wait for the landing
  return require("src.zelda.tmc.Story56").deathCheck(p)
end

return M
