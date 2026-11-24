-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 81: the Light World's Turtle Rock peg puzzle (HandlePegPuzzles).
--
-- GBA 0x0808D3EC (called from the hammer's tile interaction when a peg,
-- map16 0x21B, is driven in), first branch: the screen (+0x9C6) is 7
-- (`cmp r0, #7` at 0x0808D3F6); nothing once the area's event byte
-- (0x02002287, the literal at 0x0808D3FA) has bit 0x20 (`movs r0, #0x20`
-- at 0x0808D3FE). The counter +0xB70 (a byte offset, 0xFFFF = failed)
-- picks the next position from a table of halfwords (`ldr r2` at
-- 0x0808D420); the hammered tile's area position (0x080925A4 on +0x96C:
-- y / 16 * 0x80 + x / 16 * 2 from the area's corner) must match, else the
-- counter becomes 0xFFFF with sound 0x40 (`movs r0` at 0x0808D476) and
-- every later peg fails the same way. A match adds 2 and plays 0x47
-- (0x0808D46C); at 6 (`cmp r4, #6` at 0x0808D432: three pegs) it plays 0x7B
-- (0x0808D436), sets the event bit and starts submodule 0x2F (0x0808D44A),
-- whose first step (0x08073594) flips the world bit of the area
-- (+0x165C ^= 0x40) and loads the other world at Link's spot: he is
-- warped onto Turtle Rock's top. The counter is zeroed when an area is
-- (re)loaded (overworld submodules 6 / 0x14, 0x080744EC) and by that step.
--
-- The positions, the count, the sound ids and the event bit are read from
-- the player's ROM at import (data.t.peg81); the extract refuses other code
-- shapes. OURS: the crossing is the port's warp-tile crossing
-- (DarkWorld.start "tile": the white filter and the wave) where the
-- cartridge runs submodule 0x2F's own fade / mosaic steps (0x0814D678:
-- 0x08073594 ..., not stepped); the second branch (screen 0x62, 22 pegs ->
-- the Village of Outcasts' peg field tile at +0xC04 / +0xC0A) is not ported.

local bit = require("bit")
local band, bor, bnot = bit.band, bit.bor, bit.bnot

local M = { NAME = "peg81" }

M.SITES = {
  screen = 0x0808D3F6,    -- cmp r0, #7
  event = 0x0808D3FE,     -- movs r0, #0x20
  table = 0x0808D420,     -- ldr r2, =positions
  count = 0x0808D432,     -- cmp r4, #6
  solved = 0x0808D436,    -- movs r0, #0x7B
  good = 0x0808D46C,      -- movs r0, #0x47
  bad = 0x0808D476,       -- movs r0, #0x40
  sub = 0x0808D44A,       -- movs r0, #0x2F (submodule)
}

local function off(a) return a - 0x08000000 end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

-- the 8-bit immediate of a `movs rX, #imm` / `cmp rX, #imm` (op = 0x2000 /
-- 0x2800, any register)
local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= op then return nil end
  return band(h, 0xFF)
end

function M.extract(rom, R, check)
  local S = M.SITES
  local t = {}
  t.screen = imm8(rom, S.screen, 0x2800)
  t.bit = imm8(rom, S.event, 0x2000)
  local n2 = imm8(rom, S.count, 0x2800)
  t.solvedSfx = imm8(rom, S.solved, 0x2000)
  t.goodSfx = imm8(rom, S.good, 0x2000)
  t.badSfx = imm8(rom, S.bad, 0x2000)
  local sub = imm8(rom, S.sub, 0x2000)
  local p = lit(rom, S.table)
  check(t.screen and t.bit and n2 and n2 % 2 == 0 and n2 >= 2 and n2 <= 16 and t.solvedSfx and t.goodSfx and t.badSfx
        and sub and p and p >= 0x08000000 and p < 0x0A000000, "peg81 HandlePegPuzzles shape")
  t.pos = {}
  for i = 1, n2 / 2 do t.pos[i] = rom:u16(off(p) + (i - 1) * 2) end
  return t
end

-- ------------------------------------------------------------ run time

local function tab(game) return game and game.data and game.data.t and game.data.t.peg81 end
M.tab = tab

local function events(game)
  game.progress.owEvents = game.progress.owEvents or {}
  return game.progress.owEvents
end

function M.solved(game)
  local t = tab(game)
  return t and band(events(game)[tostring(t.screen)] or 0, t.bit) ~= 0 or false
end

-- the area's (re)load: the counter back to 0
function M.reset(game) game.pegCount81 = 0 end

local function sfx(game, id)
  if id then pcall(require("src.zelda.alttp.Sfx").start, game, id, "peg81") end
end

-- a peg was driven in at world (x, y) (the hammer's tile change)
function M.hammered(game, x, y)
  local t = tab(game)
  local area = game.area
  if not (t and area and game.link) then return end
  if (area.parent or area.id) ~= t.screen or game.link.world ~= "lw" then return end
  if M.solved(game) then return end
  local c = game.pegCount81 or 0
  local tx, ty = math.floor(x / 16) * 16, math.floor(y / 16) * 16
  local pos = math.floor((ty - area.y) / 16) * 128 + math.floor((tx - area.x) / 16) * 2
  if c == 0xFFFF or t.pos[c / 2 + 1] ~= pos then
    game.pegCount81 = 0xFFFF
    game.pegFails81 = (game.pegFails81 or 0) + 1
    sfx(game, t.badSfx)
    return
  end
  c = c + 2
  game.pegCount81 = c
  if c ~= #t.pos * 2 then sfx(game, t.goodSfx) return end
  sfx(game, t.solvedSfx)
  local e = events(game)
  e[tostring(t.screen)] = bor(e[tostring(t.screen)] or 0, t.bit)
  game.pegCount81 = 0
  game.pegSolved81 = (game.pegSolved81 or 0) + 1
  -- submodule 0x2F: the other world at Link's spot
  local DW = require("src.zelda.alttp.DarkWorld")
  game.toolUse = nil
  DW.start(game, "tile")
end

function M.install(G)
  if G.peg81Installed then return end
  G.peg81Installed = true
  local change0 = G.owTileChange
  function G:owTileChange(x, y, fromTo)
    local r = change0(self, x, y, fromTo)
    if r and fromTo == require("src.zelda.alttp.Tools").PEG and tab(self) then M.hammered(self, x, y) end
    return r
  end
end

return M
