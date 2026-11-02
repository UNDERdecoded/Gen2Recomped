-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE COMMANDS THAT READ SAVE DATA THIS PORT NEVER FILLS: the
-- roaming legendary's state and the Pokémon Global Link's Dream World
-- uploads. Each answers what the cartridge's own handler reads out of a
-- save that holds nothing there.
--
-- READ FROM CODE (Black):
--   0x1BD <index, dest> (ov10 0x0216BF38): dest = save block 0x38's byte
--         +0x2E + index (0x0200D418 / 0x0200D468) -- the roamer's state;
--         Route 7's soup cook (member 688) asks index 0 (White) / 1 (Black)
--         and says "someone taught that stormy Pokemon a lesson" only at 3
--   0x1EE <mode, dest> (ov21 0x021B6BDC): the Dream World Pokemon a Global
--         Link sync left at the Dreamyard (member 886); mode 0 is 1 when
--         its status word is non-zero (0x021B7864), so 0 here, and the
--         map's load script then hides the Pokemon (flag 0x291)
--   0x1EF <mode, dest> (ov10 0x0215E1C0): the Dream Remnants (member 885);
--         mode 0 is 1 when the PGL block holds items (0x02009370 > 0), so 0
--         here and the girl who hands them over stays hidden (flag 0x2D7)
-- The roamer's state is src/world/Gen5Roamers.lua's (0 never released, 1
-- roaming, 2 knocked out, 3 caught).
-- INFERRED: with no Global Link, the Dream World reads are the empty save's 0; the other
-- modes (item lists, the give-out tasks) are never reached from a 0.

local M = {}

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local function G4() return require("src.script.Gen4Commands") end

function Commands.g5_roamer_state(ctx, index, dest)
  local i = math.floor(tonumber(G4().valueOf(ctx, index)) or 0) % 256
  G4().setVar(ctx.save, dest, require("src.world.Gen5Roamers").state(ctx.save, i))
end

function Commands.g5_dream_world(ctx, _mode, dest)
  G4().setVar(ctx.save, dest, 0)
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwroamerstate = L.bwroamerstate or function(ins, s) emit(s, { "g5_roamer_state", ins.args[1], ins.args[2] }) end
  L.bwdreamworld = L.bwdreamworld or function(ins, s) emit(s, { "g5_dream_world", ins.args[1], ins.args[2] }) end
end

return M
