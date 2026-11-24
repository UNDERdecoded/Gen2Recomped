-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SWIM STROKES, LEDGE HOPS, PIT FALLS (round 68). Sfx.lua (round 32) reads
-- the ids of these four sounds from the `movs` before their calls (Sfx.SITES:
-- swim 0x0809B62E, the stroke; jump 0x080946DC, the ledge hop; land
-- 0x0809969A, its landing; pit 0x0809AC3E, LinkState_FallingIntoHole) into
-- data.t.sfx.ev, but nothing played them -- indoors (Swim54, Hop50) or out.
-- The port's own counters mark the same moments:
--   game.swimStrokes   Swim.lua's stroke start (s.hard 0 -> 1), indoors
--                      and outdoors (Swim54 runs Swim.swimFrame);
--   game.ledgeHops / game.hops50   the outdoor / indoor ledge hop's start;
--   game.pitFalls      Dungeons26's LinkState_FallingIntoHole start.
-- Not wired: `land` (no landing counter yet), the splash entering water.
-- OURS: one sound per counter step, at the end of the frame that stepped it.
-- No ROM reads (the ids are Sfx.lua's import).

local M = {}

M.COUNTERS = {
  { "swimStrokes", "swim" },
  { "ledgeHops", "jump" },
  { "hops50", "jump" },
  { "pitFalls", "pit" },
}

function M.extract(rom, R, check) return {} end

-- the events of one frame from the counters before / after it
function M.events(before, game)
  local out = {}
  for _, c in ipairs(M.COUNTERS) do
    if (game[c[1]] or 0) > (before[c[1]] or 0) then out[#out + 1] = c[2] end
  end
  return out
end

function M.install(G)
  local update0 = G.update
  function G:update(dt)
    local before = {}
    for _, c in ipairs(M.COUNTERS) do before[c[1]] = self[c[1]] or 0 end
    local r = update0(self, dt)
    local evs = M.events(before, self)
    if #evs > 0 then
      local S = require("src.zelda.alttp.Sfx")
      for _, ev in ipairs(evs) do pcall(S.play, self, ev) end
      self.sfx68 = (self.sfx68 or 0) + #evs
    end
    return r
  end
end

return M
