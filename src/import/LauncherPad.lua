-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CONTROLLER IN THE SIDEBAR LAUNCHER (input round, 2026-11-18).
--
-- RomImporter:gamepadpressed was written for the classic tab bar: START /
-- SELECT played (or imported) whatever `self.tab` was -- in the sidebar that
-- can be a game the player is not looking at -- and B did nothing, so a pad
-- had no way back out of a page. In the sidebar layout now:
--
--   * B (the Nintendo-position cancel, through GamepadMap) is Escape: it
--     closes a dialog, the search box or steps back one page (_sbBack);
--   * START / SELECT on a game's own page play it or import it (as before,
--     and as Enter does: LauncherSidebar only lets Enter play from there);
--   * START / SELECT anywhere else open GAMES, the launcher's game list.
--
-- The classic layout keeps its old behaviour.

local GamepadMap = require("src.core.GamepadMap")

local P = {}

function P.install(RI)
  local orig = RI.gamepadpressed
  RI.gamepadpressed = function(self, joystick, button, ...)
    if not self.sidebarMode then return orig(self, joystick, button, ...) end
    local action = GamepadMap.mapGamepadButton(button)
    if action == "b" then
      if self._activatePadCursor then self:_activatePadCursor() end
      return self:keypressed("escape")
    end
    if button == "start" or button == "back" then
      if self.section == "games" and self.gamesView == "game" then
        return orig(self, joystick, button, ...)
      end
      if self._activatePadCursor then self:_activatePadCursor() end
      if self.workState == "working" then return end
      if self._sbGo then self:_sbGo("games") end
      return
    end
    return orig(self, joystick, button, ...)
  end
end

return P
