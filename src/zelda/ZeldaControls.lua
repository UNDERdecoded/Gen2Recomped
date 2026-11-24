-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- START AND THE SYSTEM MENU in the Zelda runtime (input round, 2026-11-18).
--
-- Reported: "there's no way to open the launcher menu by pressing start on
-- controller". The runtime's system menu (RESUME / SAVE / LINK PLAY /
-- OPTIONS / QUIT TO LAUNCHER) opened only from Escape, the pad's guide button
-- (which Windows, Steam and most phones keep for themselves) or SELECT+START
-- held -- and Escape, which is START in the Pokemon games, never reached the
-- game, so a keyboard without a numeric keypad had no START at all (The
-- Minish Cap's pause menu was out of reach).
--
-- Now, the same on keyboard, controller and touch:
--   * START (pad Start, Escape / numpad Enter, touch START) is the game's
--     START, as Escape is START in the Pokemon games. In A Link to the Past
--     START in play IS the system menu (the cartridge's START is its save /
--     quit dialogue: alttp/Controls.lua); in The Minish Cap it is the
--     cartridge's pause menu.
--   * Holding START for half a second opens the system menu in either game,
--     from anywhere (title, pause menu, play).
--   * The guide button, SELECT+START held and the touch MENU button still
--     open it.

local Z = {}

Z.HOLD_TICKS = 30   -- ~0.5 s at the GBA's 59.73 Hz

-- Called at the top of Host:_tick after Input:step(); true when it opened the
-- system menu (the tick ends there).
function Z.tick(host, Input)
  if Input:wasPressed("start") then
    host.startHold = (not host.menu and not host.link) and 0 or nil
  end
  if host.startHold and Input:isDown("start") then
    host.startHold = host.startHold + 1
    if host.startHold >= Z.HOLD_TICKS then
      host.startHold = nil
      if not host.menu and not host.link and not host.error then
        host:openMenu()
        return true
      end
    end
  elseif not Input:isDown("start") then
    host.startHold = nil
  end
  return false
end

-- Escape is START (src/core/Input.lua binds it so, as for the Pokemon games);
-- it still backs out of the LINK PLAY screens first. True when handled here.
function Z.escape(host)
  if host.link then host.link.done = true; host.link = nil; return true end
  return false
end

return Z
