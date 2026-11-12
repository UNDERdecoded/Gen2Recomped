-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Round 26 (team A): the import of this round's world / item modules, one
-- call from Extract.lua (each module reads its own GBA tables).

local X = {}

function X.extract(t, rom, R, check)
  t.dw = require("src.zelda.alttp.DarkWorld").extract(rom, R, check)
  t.gear = require("src.zelda.alttp.Gear").extract(rom, R, check)
  t.swim = require("src.zelda.alttp.Swim").extract(rom, R, check)
  t.tools = require("src.zelda.alttp.Tools").extract(rom, R, check)
  t.events = require("src.zelda.alttp.OwEvents").extract(rom, R, check)
end

return X
