-- Round 70: script LoadMenu (script.c: MenuFadeIn(intVariable & $FF, intVariable >> 8)) for SUBTASK_MAPHINT (3)
-- (src/subtask/subtaskMapHint.c).
--
-- CARTRIDGE BEHAVIOUR
--   * Subtask_MapHint_0: gSave.map_hints |= gUnk_08128F4C[hint] (a u16 table in the pause menu's data), the world
--     map shown (sub_080A4D34 / sub_080A4DB8(4)), 60 frames, at 30 SFX_103 and the new hint's marker blinking
--     (gGenericMenu.unk2c & $20: sub_080A6438 draws gUnk_08128F58's hint sprites); then A / B / START closes it.
--   * script_KingGustafHologram (Lake Hylia after the Temple of Droplets) ends with SetIntVariable $203, LoadMenu:
--     map hint 2.  The port's LoadMenu did nothing: the hint bit was never set (MapMenu draws save.mapHints).
-- PORTED: the hint bit from the ROM's table (read through the pause menu data the cache already holds, Layout
--   "pauseData2" $08128F38..), then the pause menu opened on the world map (screen 4), SFX_103.
-- SIMPLIFIED: the map is the pause menu's world map page (closed with START like the pause menu, not A / B), and
--   the hint marker blinks with that page's own timer.
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = {}
M.SUBTASK_MAPHINT = 3
M.HINT_BITS = 0x08128F4C -- gUnk_08128F4C (u16 per hint), inside Layout's pauseData2 range
local SFX_103 = 0x103

-- the hint's bits from the cache's pause-menu data (nil without a cache)
function M.bits(f, hint)
  local ok, t = pcall(function() return require("src.zelda.tmc.Ppu").table({ A = f.assets }, "pauseData2") end)
  if not ok or not t then return nil end
  return t.u16(M.HINT_BITS + 2 * hint)
end

-- LoadMenu: true when handled
function M.load(f, iv)
  iv = iv or 0
  local menuType, sub = band(iv, 0xFF), band(rshift(iv, 8), 0xFF)
  if menuType ~= M.SUBTASK_MAPHINT then return false end
  local v = M.bits(f, sub)
  if v then f.save.mapHints = bor(f.save.mapHints or 0, v) end
  if f.menu and not f.menu.open and f.menu.openMenu then
    f.menu.screen = 4
    local ok = pcall(function() f.menu:openMenu() end)
    if ok then f:sound(SFX_103); f.menu.mapHint = require("src.zelda.tmc.Bell75").HINT_FRAMES end -- round 75: A / B / START after 60 frames
  end
  return true
end

return M
