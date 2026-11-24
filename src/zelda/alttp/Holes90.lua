-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 90: the chest-hole room tags 0x22 and 0x3B (zelda3: the "chest
-- holes" tags). The port had no case for them: Ganon's Tower's compass room
-- (0x9D, tag 0x3B) kept its floor after the first chest was opened.
--
-- GBA (kDungTagroutines 0x08152AC4, Link's block 0x03002230), both routines
-- have the same shape (0x0807B2D0 for 0x22, 0x0807B33C for 0x3B):
--   * the room's save bits (+0xAA8) & mask (`movs r0, #n` / `lsls r0, r0,
--     #1` at +0x0C: 0x100) -- the bit OpenChestForItem sets for the room's
--     first chest (kChestOpenMasks 0x081676F2[0]); nothing until then;
--   * then the overlay index +0xB62 = n (0x22: `movs r2, #n` at +0x02 is the
--     stored register; 0x3B: `movs r0, #n` at +0x1C), +0x9F4 / +0x9E8 = 0,
--     a sound (the call at +0x30), submodule +0x9AD = 3 (Module07_03: the
--     overlay drawn, Dungeon_DrawRoomOverlay) and the tag slot cleared.
-- The bit stays in the room's save bits, so the tag fires again on every
-- load of the room: the holes are there on a later visit too.
--
-- All numbers are read at import (data.t.holes90), refused on other shapes.
-- OURS: the sound is not played; the overlay is drawn in one frame (the
-- cartridge's submodule 3 draws it over a few frames with Link held).

local bit = require("bit")
local band = bit.band

local M = { NAME = "holes90" }

M.TAG_TABLE = 0x08152AC4      -- kDungTagroutines
M.CHEST_MASKS = 0x081676F2    -- kChestOpenMasks (u16)
-- per tag: the routine, the mask's `movs` site and the overlay immediate's site
M.TAGS = {
  [0x22] = { fn = 0x0807B2D0, mask = 0x0807B2DC, ov = 0x0807B2D2, store = 0x0807B2EC },
  [0x3B] = { fn = 0x0807B33C, mask = 0x0807B346, ov = 0x0807B358, store = 0x0807B35A },
}

function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local t = {}
  local ok = true
  for tag, s in pairs(M.TAGS) do
    local entry = rom:u32(M.TAG_TABLE - 0x08000000 + tag * 4)
    local mask, mf = RT.codeImm(rom, s.mask)
    local ov, of = RT.codeImm(rom, s.ov)
    -- the overlay index is stored as a halfword (strh) right after
    local st = rom:u16(s.store - 0x08000000)
    local good = entry == s.fn + 1 and mf == "movs" and of == "movs" and band(st, 0xF800) == 0x8000
    local chest
    if good then
      for n = 0, 5 do
        if rom:u16(M.CHEST_MASKS - 0x08000000 + n * 2) == mask then chest = n break end
      end
    end
    if good and chest then
      t[tag] = { chest = chest, overlay = ov }
    else
      ok = false
    end
  end
  check(ok and t[0x22] and t[0x3B], "the chest-hole room tags 0x22 / 0x3B (mask, overlay index)")
  return ok and t or {}
end

local function tab(game) return game.data and game.data.t and game.data.t.holes90 end
M.tab = tab

-- one frame of the tags (after Dungeons26's overlay tags)
function M.frame(game)
  local T = tab(game)
  local inside = game.interior
  if not (T and inside and inside.hdr) then return false end
  local fired = false
  for slot, tag in ipairs({ inside.hdr[6] or 0, inside.hdr[7] or 0 }) do
    local e = T[tag]
    inside.holes90 = inside.holes90 or {}
    if e and not inside.holes90[slot] and inside.mem and inside.mem.chests and inside.mem.chests[e.chest + 1] then
      inside.holes90[slot] = true   -- the tag slot cleared (until the room is loaded again)
      require("src.zelda.alttp.Dungeons26").drawOverlay(game, e.overlay)
      game.holes90 = (game.holes90 or 0) + 1
      fired = true
    end
  end
  return fired
end

function M.install(G)
  if G.holes90Installed then return end
  G.holes90Installed = true
  local D = require("src.zelda.alttp.Dungeons26")
  -- a load starts with the tags (Dungeon_LoadHeader): the slots fire again
  local I = require("src.zelda.alttp.Interior")
  local load0 = I.loadRoom
  function I:loadRoom(room, main)
    local r = load0(self, room, main)
    self.holes90 = nil
    return r
  end
  local tags0 = D.overlayTags
  D.overlayTags = function(game)
    local r = tags0(game)
    M.frame(game)
    return r
  end
end

return M
