-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LEDGE HOP'S TWO SOUNDS (round 69). Sfx.lua (round 32) reads both ids
-- from the `movs` before their calls (Sfx.SITES): jump 0x080946DC (the hop
-- starts, sfx2 0x20) and land 0x0809969A (the hop lands, sfx2 0x21). Round
-- 68's Sfx68 played "jump" on game.ledgeHops, but that counter steps when an
-- indoor hop ENDS (Game.lua: `(wasHop or hopNow) and not lk.hop`), and an
-- outdoor hop (Link.lua's link.hop) counted nothing. Here:
--   * Sfx68's ledgeHops entry is dropped (the hop's start keeps hops50 ->
--     "jump" indoors);
--   * an outdoor hop that starts this frame (link.hop nil -> set, outdoors)
--     plays "jump";
--   * any hop that ends this frame (link.hop set -> nil, indoors or out)
--     plays "land" (game.hopLands69 counts them).
-- OURS: the sound at the end of the frame the hop state changed. No ROM
-- reads (the ids are Sfx.lua's import).

local M = {}

function M.extract(rom, R, check) return {} end

-- the events of one frame: had / has the hop, indoors or out, the indoor
-- hop counter before / after
function M.events(had, has, indoor, hops0, hops1)
  local out = {}
  if not had and has and not indoor then out[#out + 1] = "jump" end
  if had and not has then out[#out + 1] = "land" end
  return out
end

-- Sfx68's ledgeHops entry (an indoor hop's END, not its start) is dropped
function M.patchSfx68()
  local ok, S68 = pcall(require, "src.zelda.alttp.Sfx68")
  if not ok or not S68.COUNTERS then return false end
  for i = #S68.COUNTERS, 1, -1 do
    if S68.COUNTERS[i][1] == "ledgeHops" then table.remove(S68.COUNTERS, i) end
  end
  return true
end

function M.install(G)
  M.patchSfx68()
  local update0 = G.update
  function G:update(dt)
    local lk = self.link
    local had = lk and lk.hop ~= nil
    local hops0 = self.hops50 or 0
    local r = update0(self, dt)
    lk = self.link
    local has = lk and lk.hop ~= nil
    local evs = M.events(had, has, self.state == "room", hops0, self.hops50 or 0)
    if #evs > 0 then
      local S = require("src.zelda.alttp.Sfx")
      for _, ev in ipairs(evs) do
        pcall(S.play, self, ev)
        if ev == "land" then self.hopLands69 = (self.hopLands69 or 0) + 1 end
      end
      self.sfx69 = (self.sfx69 or 0) + #evs
    end
    return r
  end
end

return M
