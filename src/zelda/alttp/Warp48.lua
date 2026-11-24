-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DUNGEON WARP TILE (round 48). Tile attribute 0x4B indoors (the Palace
-- of Darkness's basement 0x0A holds one between pots) was walkable floor in
-- the port and did nothing.
--
-- Traced on the GBA:
--   * TileDetect's jump table 0x0816832C (256 attributes x 2 variants):
--     0x4B -> 0x080A0C90: +0x17E8 = probe bit << 4.
--   * The nearby probe 0x0809EEB4(0) (called after Link's move): one point,
--     Link + (kNearbyX[0], kNearbyY[0]) (s16 tables 0x081681D4 / 0x0816817C,
--     read at import), through 0x080A0454 -> the jump table, probe bit 1.
--   * 0x0809EFCA: +0x17E8 & 0x10 -> unless ((link_y + 8) & 15) is 4..11 or
--     (link_x & 15) is 4..11 (Link not on the tile's grid), the blink timer
--     (+0x17AA) runs or link_auxiliary_state (+0x1702) is set: indoors
--     (+0x9B2) -> 0x08070064, sound 0x4C (the `movs` at 0x0809F028, read at
--     import), +0x1719 = 0, module 7 submodule 0x16, the old room saved,
--     dungeon_room_index = (room & 0xFF00) | +0xCF0 (the header's byte 9,
--     the room the holes fall to: 0x08080F18 stores it), 0x0809E4FC.
--     (Outdoors the same bit is the Dark World warp, DarkWorld.lua.)
--   * Module 7 submodule 0x16 (0x080713A0, steps table 0x0814CD50): step 2
--     (0x080709DC) loads the room (0x0807FF10 ...), the later steps fade the
--     palettes back (0x08089E94 for steps > 2). Link keeps his spot in the
--     room.
-- OURS: the fade's length and look (a black filter, 16 frames out and 16
-- in); the steps' palette work is not traced.

local bit = require("bit")
local band = bit.band

local M = {}

M.OFF = {
  nearX = 0x1681D4,      -- s16 kNearbyX (probe 0 used)
  nearY = 0x16817C,      -- s16 kNearbyY
  sfxSite = 0x0809F028,  -- movs r0, #id before the sound call
  table = 0x16832C,      -- TileDetect's jump table (0x4B's handler checked)
}
M.ATTR = 0x4B
M.FADE = 16             -- OURS

local function s16(v) if v >= 0x8000 then return v - 0x10000 end return v end

function M.extract(rom, R, check)
  local O = M.OFF
  local t = { px = s16(rom:u16(O.nearX)), py = s16(rom:u16(O.nearY)) }
  local h = rom:u16(O.sfxSite - 0x08000000)
  t.sfx = (bit.rshift(h, 11) == 4) and band(h, 0xFF) or nil
  -- the handler of 0x4B is the same in both halves of the table
  local a = rom:u32(O.table + M.ATTR * 4)
  local b = rom:u32(O.table + (256 + M.ATTR) * 4)
  check(t.sfx ~= nil and a == b and t.px >= 0 and t.px < 16 and t.py >= 8 and t.py < 24,
        "warp tile tables (probe %d,%d, sound %s)", t.px, t.py, tostring(t.sfx))
  return t
end

local function tab(game) return game.data and game.data.t and game.data.t.warp48 end
M.tab = tab

-- is Link standing on the warp tile the cartridge's way (0x0809EFCA)?
function M.onTile(game)
  local t = tab(game)
  local inside, lk = game.interior, game.link
  if not (t and inside and lk) then return false end
  if inside:attrAt(lk.x + t.px, lk.y + t.py) ~= M.ATTR then return false end
  local fy = band(lk.y + 8, 15)
  local fx = band(lk.x, 15)
  if fy >= 4 and fy <= 11 then return false end
  if fx >= 4 and fx <= 11 then return false end
  return true
end

function M.start(game)
  local inside = game.interior
  local hdr = inside.hdr or {}
  local t = tab(game)
  game.warp48 = { t = 0, from = inside.room, dest = hdr[10] or 0 }
  game.warps48 = (game.warps48 or 0) + 1
  if t and t.sfx then pcall(function() require("src.zelda.alttp.Sfx").start(game, t.sfx, "warp") end) end
  game.swing = nil
  if game.dash then pcall(function() require("src.zelda.alttp.Dash").cancel(game) end) end
end

-- one frame of the warp; true while it runs (everything else waits)
function M.frame(game)
  local w = game.warp48
  w.t = w.t + 1
  if w.t == M.FADE then
    local inside, lk = game.interior, game.link
    if game.dropCarry then game:dropCarry() end
    inside:loadRoom(w.dest, inside.main)
    inside.lower = false   -- +0x1719 = 0
    game.roomImages = nil
    inside.qx, inside.qy = math.floor((lk.x + 8) / 256), math.floor((lk.y + 12) / 256)
    game.roomChanges = (game.roomChanges or 0) + 1
    game.roomScroll = nil
    if game.actors and game.actors.enterRoom then game.actors:enterRoom(inside) end
    w.landed = w.dest
  end
  if w.t >= M.FADE * 2 then game.warp48 = nil end
  return true
end

function M.install(G)
  if G.warp48Installed then return end
  G.warp48Installed = true
  local esc0 = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.warp48 then return M.frame(self) end
    return esc0(self, inp)
  end
  local Doors = require("src.zelda.alttp.Doors")
  local move0 = Doors.move
  function Doors.move(g, inp)
    move0(g, inp)
    if g.interior and g.state == "room" and not g.warp48 and not g.pitFall and not g.roomScroll
       and (g.blink or 0) == 0 and not g.recoil and not (g.link and g.link.hop) and M.onTile(g) then
      M.start(g)
    end
  end
  local xf0 = G.drawCrossfade
  function G:drawCrossfade()
    if xf0 then xf0(self) end
    local w = self.warp48
    if not w then return end
    local k = (w.t < M.FADE) and (w.t / M.FADE) or math.max(0, (2 * M.FADE - w.t) / M.FADE)
    if k <= 0 then return end
    local lg = love.graphics
    lg.push("all")
    lg.origin()
    lg.setColor(0, 0, 0, math.min(1, k))
    lg.rectangle("fill", 0, 0, 4096, 4096)
    lg.pop()
  end
  -- a new room or the overworld ends a warp that is still running
  local enter0 = G.enterRoom
  function G:enterRoom(...)
    self.warp48 = nil
    return enter0(self, ...)
  end
end

return M
