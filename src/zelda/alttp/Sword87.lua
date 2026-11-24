-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 87: the sword swing goes on while Link recoils (traced; no ROM
-- reads).
--
-- Escape.lua's indoor frame returned at the recoil before the swing code, so
-- a swing that hit something which throws Link back (the "is_many" sprites:
-- Trinexx's heads, Ganon, the Thieves' Town / PoD bosses: recoil 32, 16
-- frames) froze until he landed and then ran its last steps with Link
-- standing still. Traced on the GBA, LinkState_Default (0x0809D5CC), the
-- zelda3 PlayerHandler_00 order:
--   0x0809D65A Link_HandleToss (0x080A185C), 0x0809D668 Link_HandleAPress
--   (0x080A18F0); then, when +0x1791 | +0x1808 and +0x1809 are 0 and the
--   state (+0x1718) is not 0x11 (the dash's start): 0x0809D68E the item
--   button (0x080A3BEC) and, with +0x165E and 0x0200233D set, 0x0809D6A4
--   Link_HandleSwordCooldown (0x080A3D38: the swing's steps, the held
--   sword) -- all BEFORE 0x0809D70E: link_incapacitated_timer (+0x16F8) not
--   0 -> the recoil handler (0x08099D98) and return.
-- So the swing's steps (and their sword box) keep running during a recoil;
-- Link lands with the swing already done and walks at once.
--
-- OURS: only a plain swing (steps 0-8) runs on (a held sword / the spin
-- stay as before); a new swing cannot start during a recoil (the cartridge's
-- Link_CheckForSwordSwing would take a fresh B there); the overworld's
-- recoil block is unchanged; a hurt still drops the swing at once
-- (G:hurtLink) where the cartridge clears button_b_frames on landing.

local M = {}

-- one swing step while recoiling: Escape.lua's plain-swing branch
function M.frame(game)
  local s = game.swing
  if not s or s.held or s.spin then return false end
  local cb = game.data and game.data.roomIdx and game.data.roomIdx.combat
  local inside = game.interior
  if not cb or not inside then return false end
  local lk = game.link
  s.delay = s.delay - 1
  if s.delay < 0 then
    s.step = s.step + 1
    if s.step >= 9 then
      local inp = game.input
      if inp and inp.isDown and inp.isDown("b") then
        s.held, s.step, s.delay, s.charge, s.facing = true, 9, 0, 0, lk.facing
        game.swordHeld = 9
        game.swordHolds = (game.swordHolds or 0) + 1
      else
        game.swing = nil
      end
      game.recoilSwings87 = (game.recoilSwings87 or 0) + 1
      return true
    end
    s.delay = cb.swordDelays[s.step + 1] or 0
  end
  local Actors = require("src.zelda.alttp.Actors")
  local x, y, w, h = Actors.swordBox(cb, lk, s.step, game.data.t.playerOamOffs)
  s.box = x and { x, y, w, h } or nil
  s.n = (s.n or 0) + 1
  if x then game.actors:swordHit(x, y, w, h, { vel = 0x50, lower = inside.lower or false,
                                               sword = true, bFrames = s.step }) end
  game.recoilSteps87 = (game.recoilSteps87 or 0) + 1
  return true
end

function M.extract(rom, R, check) return {} end

function M.install(G)
  if G.sword87Installed then return end
  G.sword87Installed = true
  function G:recoilSwing87() return M.frame(self) end
end

return M
