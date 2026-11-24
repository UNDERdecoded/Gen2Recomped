-- Round 78: the HUD hidden in cutscenes (gHUD.hideFlags), hooked from Field:drawHud / Field:updateHudUi.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * script.c DisablePauseMenu (also reached through DisablePauseMenuAndPutAwayItems, the natives every cutscene
--     script calls first): gHUD.hideFlags = HUD_HIDE_ALL ($FF), gPauseMenuOptions.disabled = $FF.
--     EnablePauseMenu: disabled = 0, hideFlags = HUD_HIDE_NONE, RecoverUI.
--   * ui.c DrawUI: gHUD.unk_0 &= ~hideFlags; DrawHearts (HUD_HIDE_HEARTS $10: EraseChargeBar + EraseHearts),
--     DrawRupees (HUD_HIDE_RUPEES $40: the three digits and the wallet erased), DrawKeys (HUD_HIDE_KEYS $80); the
--     A / B / R button elements (type2 0) slide up off the screen while their bit (1 << type) is set
--     (UIElement y - $28, Ui.lua already moves them on ui.hideFlags).
--   * hideFlags is not touched by a room change (only gPauseMenuOptions.disabled is cleared there), so it is a
--     field of its own here (f.hudHideFlags), not the port's f.menuDisabled.
--   The port drew the hearts, rupees, keys and buttons through every cutscene.
-- SIMPLIFIED: the charge bar has no separate drawing in the port (it goes with the hearts).
local bit = require("bit")
local band = bit.band

local M = {}

M.HIDE_NONE, M.HIDE_ALL = 0x00, 0xFF
M.HIDE_HEARTS, M.HIDE_RUPEES, M.HIDE_KEYS = 0x10, 0x40, 0x80
M.DISABLE_PUT_AWAY, M.DISABLE, M.ENABLE = 0x0807DF28, 0x0807DF38, 0x0807DF50

function M.flags(f)
  return (f and f.hudHideFlags) or 0
end

function M.hides(f, bitv) return band(M.flags(f), bitv) ~= 0 end

-- wrap the three natives (once): they keep doing what they did, and set / clear gHUD.hideFlags
function M.install()
  if M._installed then return end
  local okN, Native = pcall(require, "src.zelda.tmc.Native")
  if not okN or not Native or not Native.N then return end
  local N = Native.N
  M._installed = true
  local function wrap(addr, v)
    local f0 = N[addr]
    N[addr] = function(f, ...)
      if f then f.hudHideFlags = v end
      if f0 then return f0(f, ...) end
      if f and v == M.HIDE_ALL then f.menuDisabled = true end -- DisablePauseMenu's own half (VaatiScripts keeps this one)
    end
  end
  wrap(M.DISABLE_PUT_AWAY, M.HIDE_ALL)
  wrap(M.DISABLE, M.HIDE_ALL)
  wrap(M.ENABLE, M.HIDE_NONE)
end

M.install()

return M
