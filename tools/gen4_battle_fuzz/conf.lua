-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

function love.conf(t)
  -- One identity for every fuzz run so the save directory is predictable.
  -- POKEPORT_IDENTITY overrides it exactly as the main game's conf does.
  t.identity = os.getenv("POKEPORT_IDENTITY") or "pl_battle"
  t.console = true
  t.window.width, t.window.height = 512, 384
  t.window.title = "gen4 battle fuzz"
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
  t.modules.touch = false
end
