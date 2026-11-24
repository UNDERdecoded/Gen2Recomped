-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 91: a pit fall waits while the pegs move.
--
-- GBA (Fall52's trace): the fall is Link's state, run by Link_Main from the
-- dungeon's submodule 0 (0x0806CE1C); Sprite_Main runs every frame but the
-- sprites' pause test reads the submodule (+0x9AD, 0x080C1B8C). A crystal
-- switch hit sets submodule 0x16 (Module07_16_UpdatePegs, Dungeons26
-- pegFrame): neither Link_Main nor the sprites run until the pegs are done,
-- then the fall goes on where it was.
--
-- The port's Fall52 runs the actors and the ancillae during the fall before
-- Dungeons26's peg test, so they also ran during the peg update. In Ganon's
-- Tower 0x9D a Somaria block rides the conveyor into the crystal switch and
-- keeps touching it: with the switch's own counter (sprite_F 15) running
-- through the 16 peg frames, a new toggle came every 15 frames, the peg
-- update never ended, and Link stood on the hole forever (chest 0's holes to
-- 0x7B). Here Fall52's "falling" test is false while the pegs move, so the
-- frame is the peg update alone, as on the cartridge.
--
-- No ROM data: nothing is read (extract returns an empty table).

local M = { NAME = "fall91" }

M.SITES = { pauseTest = 0x080C1B8C, submodule0 = 0x0806CE1C }

function M.extract(rom, R, check) return {} end

function M.install(G)
  if G.fall91Installed then return end
  G.fall91Installed = true
  local F52 = require("src.zelda.alttp.Fall52")
  local run0 = F52.running
  function F52.running(game)
    if game.pegAnim then
      game.fallPegWaits91 = (game.fallPegWaits91 or 0) + 1
      return false
    end
    return run0(game)
  end
end

return M
