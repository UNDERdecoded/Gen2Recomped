-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 91: a burning sprite is not met by Link's ancillae.
--
-- GBA, Ancilla_CheckSpriteCollision (the loop 0x080C09FC): a sprite is
-- only tested while its state ([+0xFA2]) is above 8 (`cmp r0, #8` / `bls`
-- at 0x080C0A58 / 0x080C0A5A). The burn (Burn63: the damage code 0xFD sets
-- sprite_state = 7, SpriteModule_Burn) is below that, so a Gibdo set on fire
-- by the Fire Rod no longer stops the next shot or an arrow while it burns.
-- The port's tool / arrow hit loops (Tools.spriteHit, Game:arrowFrame) only
-- skipped dead sprites: in Ganon's Tower 0x9D a second Fire Rod shot at the
-- next Gibdo burst on the first one's flames (16 magic gone).
--
-- OURS: the burning sprites are hidden (flagged dead) for the length of the
-- call and put back after; nothing else changes.
--
-- No ROM data: nothing is read (extract returns an empty table).

local M = { NAME = "burn91" }

M.SITES = { loop = 0x080C09FC, stateCmp = 0x080C0A58 }

function M.extract(rom, R, check) return {} end

local function actorsHere(game)
  if game.interior then return game.actors end
  return game.owActors
end

-- run f(...) with the burning sprites of the current list out of reach
function M.withoutBurning(game, f, ...)
  local acts = actorsHere(game)
  local hidden
  for _, s in ipairs(acts and acts.list or {}) do
    if s.burn and not s.dead then
      hidden = hidden or {}
      hidden[#hidden + 1] = s
      s.dead = true
    end
  end
  if not hidden then return f(...) end
  local ok, a, b, c = pcall(f, ...)
  for _, s in ipairs(hidden) do
    if s.dead == true then s.dead = nil end
  end
  M.skips = (M.skips or 0) + 1
  if not ok then error(a, 0) end
  return a, b, c
end

function M.install(G)
  if G.burn91Installed then return end
  G.burn91Installed = true
  local af0 = G.arrowFrame
  if af0 then
    function G:arrowFrame(a) return M.withoutBurning(self, af0, self, a) end
  end
  local TL = require("src.zelda.alttp.Tools")
  local sh0 = TL.spriteHit
  if sh0 then
    function TL.spriteHit(game, a, cls, box) return M.withoutBurning(game, sh0, game, a, cls, box) end
  end
end

return M
