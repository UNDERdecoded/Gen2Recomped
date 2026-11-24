-- Round 70: PL_SPAWN_9 (gameUtils.c InitializePlayer: sPlayerSpawnStates[PL_SPAWN_9] = PLAYER_MINISH).
--
-- CARTRIDGE BEHAVIOUR (player.c)
--   * sub_08073C80 (PlayerMinish's init): spawn type 9 -> spawn type DEFAULT, Link not drawn, subAction 2;
--     sub_08073F04 clears PL_MINISH (he is growing, no longer Minish), zVelocity 2.5; sub_08073F4C walks him to
--     (gArea.portal_x, portal_y) -- the portal manager he spawned in (MinishPortalManager_Main sets them while he is
--     within its 64 x 64 box) -- then ANIM_GROW for 30 frames, drawn again (SFX_PLY_JUMP), and out of it full size.
--   * Used by the Temple of Droplets' exit (TEMPLE_OF_DROPLETS_MANAGER type 6, DoExitTransition(gUnk_0813AD88[0]):
--     Lake Hylia, spawn type 9): Link comes out of the frozen block's PT_TOD portal full size.
--   * The port made spawn type 9 a Minish spawn (Field:transitionSwitch): Link stayed Minish on the frozen block,
--     where PT_TOD does not let Minish Link grow (PortalReadyForMinish) and deep water all round -- stuck.
-- PORTED: spawn type 9 with a portal manager whose 64 x 64 box holds Link: the port's grow at that portal
--   (Objects:tryPortal's Minish branch: ANIM_GROW, SFX_GROW, then Objects:portalDone -> full size, on the stump).
--   Without a portal there, Link is simply full size (PL_MINISH is cleared either way).
-- SIMPLIFIED: the grow is the port's portal grow (60 frames, drawn), not the hidden walk + 30-frame ANIM_GROW.
local M = {}

M.PL_SPAWN_9 = 9
local ANIM_GROW, SFX_GROW = 0x73C, 0x170

-- the portal manager whose CheckPlayerProximity box (x - $20 .. + $40, y - $20 .. + $40) holds (x, y)
function M.portalAt(f, x, y)
  for _, p in ipairs(f.portals or {}) do
    if x >= p.x - 0x20 and x < p.x + 0x20 and y >= p.y - 0x20 and y < p.y + 0x20 then return p end
  end
  return nil
end

function M.after(f, exit)
  if not exit or exit.kind ~= M.PL_SPAWN_9 or exit.scroll then return false end
  local pl = f.player
  local p = M.portalAt(f, pl.x, pl.y)
  if not p then pl.minish = false return true end
  pl.minish = true
  pl.state = "portal"
  pl.portal = p
  pl.x, pl.y = p.x, p.y
  pl.animationState = 4
  if pl.setAnim then pl:setAnim(ANIM_GROW, true) end
  f:sound(SFX_GROW)
  pl.timer = 60
  return true
end

return M
