-- Round 62: the Temple of Droplets' Minish portal (PT_TOD, portal type 6) on the frozen block in Lake Hylia.
--
-- CARTRIDGE BEHAVIOUR (decomp):
--   * minishPortalManager.c MinishPortalManager_Main: gArea.portal_type = the manager's type (6 = PT_TOD for the
--     lake's centre portal); PortalReadyForMinish is FALSE for PT_TOD, so Minish Link never grows there
--     (portal_mode 3 is not set) -- only full-size Link standing on the portal (PL_USE_PORTAL, portal_mode 2)
--     uses it.
--   * player.c PlayerUsePortal: PortalActivateInit / Update, PortalShrinkInit / Update (the shrink spin), then
--     PortalEnterUpdate: when the timer and GravityUpdate are done Link is hidden and, for PT_TOD,
--     DoExitTransition(&gUnk_0813AB58) -- the temple's entrance room (read from the ROM: RomTables
--     "PortalToD62.WARP_TOD", area / room / end x, y / layer / transition type / facing).  Any other portal type
--     sets gArea.portal_in_use (the portal cutscene, then RespawnAsMinish at the portal's exit).
--   * enterPortalSubtask.c sub_0804AD18: PT_TOD -> FALSE (no respawn as Minish), so B / R during the spin does
--     nothing there either.
-- SIMPLIFIED: the shrink spin is the port's existing portal animation and timer (Objects:tryPortal); the
--   transition starts when it ends, as RespawnAsMinish's place does for the other portal types.
local M = {}

M.PT_TOD = 6
M.WARP = require("src.zelda.tmc.RomTables").t("PortalToD62.WARP_TOD") -- gUnk_0813AB58

-- PortalReadyForMinish: FALSE for PT_TOD (Minish Link can not use / grow at it)
function M.usable(pl, p)
  return not (pl.minish and p.type == M.PT_TOD)
end

-- PortalEnterUpdate for PT_TOD: hidden, DoExitTransition(gUnk_0813AB58).  Returns true when it handled the end
-- of the shrink (Objects:portalDone then does nothing else).
function M.done(f, pl, p)
  if not p or p.type ~= M.PT_TOD or pl.minish then return false end
  require("src.zelda.tmc.PortalJump").clear(pl)
  pl.portal = nil
  pl.state = "normal"
  pl.animId = -1
  pl.hidden, pl.hiddenTod62 = true, true -- PortalEnterUpdate: spriteSettings.draw = FALSE until the new room
  pl.invuln = 0
  local w = M.WARP
  f:startTransition({ warpType = w.warpType, area = w.area, room = w.room, endX = w.endX, endY = w.endY,
                      shape = w.shape, layer = w.layer, kind = w.kind, facing = w.facing })
  return true
end

-- the new room (InitializePlayer draws Link again)
function M.roomInit(f)
  local pl = f.player
  if pl and pl.hiddenTod62 then pl.hidden, pl.hiddenTod62 = nil, nil end
end

return M
