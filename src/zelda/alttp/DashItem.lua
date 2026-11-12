-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SPRITE 0x3B, THE DASH ITEM (round 21): the SNES Sprite_DashItem the GBA
-- keeps (zelda3 sprite_main.c), indoors (SpritePrep_BonkItem):
--
--   room 0x107 (the library): the Book of Mudora on the bookcase (gone once
--   Link has it). It waits until Link, facing up, is within (x - 39 .. + 7,
--   y - 40 .. + 5) of it while the screen shakes (bg1_x / y_offset: the
--   dash's bonk, Effects.tremor); then it falls: z speed 32, y speed -5,
--   z speed - 1 a frame, bouncing with - z speed / 4. Touching Link
--   (Sprite_CheckDamageToLink_same_layer) gives item 0x1D (Link_ReceiveItem;
--   Link_CancelDash).
--   other rooms: a bonk key (the same fall, Link_ReceiveItem is a small key;
--   its room bit 0x4000 / 0x2000 keeps it taken).
--
-- OURS: the fall from the shelf's top to the floor in front (see ai 1); the
-- book is drawn as its item-menu icon (the cartridge decodes its
-- animated sprite tile, DecodeAnimatedSpriteTile_variable(0x0E)); the item
-- receipt's hold-up pose and message are the chest's (G:getItem).

local bit = require("bit")
local band = bit.band

local M = {}
M.TYPE = 0x3B
M.BOOK = 0x1D

local function hasItem(game, id)
  for _, v in ipairs((game.progress and game.progress.items) or {}) do if v == id then return true end end
  return false
end

local function shaking(game)
  local s = game.shake
  return s ~= nil and (s.off or 0) ~= 0
end

-- one frame (Actors:update)
function M.update(actors, a, lk)
  local game = actors.game
  local room = actors.inside and actors.inside.room
  if not a.dashPrep then
    a.dashPrep = true
    a.book = room == 0x107
    a.z, a.vz, a.ai, a.vy, a.fz, a.fy = 0, 0, 0, 0, 0, 0
    if a.book and hasItem(game, M.BOOK) then a.dead = true return end
    if not a.book and actors.inside.mem and actors.inside.mem.bonkKey then a.dead = true return end
  end
  -- Sprite_CheckDamageToLink_same_layer: Link touches it -> give it
  if a.ai >= 2 and (a.z or 0) <= 8 then
    local A = require("src.zelda.alttp.Actors")
    local lx, ly, lw, lh = A.linkBox(lk)
    if A.overlapCart(lx, ly, lw, lh, a.x, a.y - (a.z or 0), 16, 16) then a.ai = 3 end
  end
  -- Sprite_MoveXY (y only), the z fall and bounce
  a.fy = (a.fy or 0) + (a.vy or 0)
  local my = (a.fy >= 0) and math.floor(a.fy / 16) or -math.floor(-a.fy / 16)
  a.fy = a.fy - my * 16
  a.y = a.y + my
  if a.ai >= 2 then
    a.vz = a.vz - 1
    a.fz = (a.fz or 0) + a.vz
    local mz = (a.fz >= 0) and math.floor(a.fz / 16) or -math.floor(-a.fz / 16)
    a.fz = a.fz - mz * 16
    a.z = a.z + mz
    if a.z < 0 then
      a.vy, a.z = 0, 0
      a.vz = math.floor(band(-a.vz, 0xFF) / 4)
      if a.vz >= 64 then a.vz = 0 end
    end
  end
  if a.ai == 0 then
    local dx, dy = a.x - lk.x, a.y - lk.y
    if a.book then
      if lk.facing == 0 and dx + 39 >= 0 and dx + 39 < 47 and dy + 40 >= 0 and dy + 40 < 46 and shaking(game) then a.ai = 1 end
    else
      if dx + 16 >= 0 and dx + 16 < 33 and dy + 24 >= 0 and dy + 24 < 41 and shaking(game) then a.ai = 1 end
    end
  elseif a.ai == 1 then
    -- being falling. OURS: it drops from the shelf's top to the floor in
    -- front of the shelf (y + 64, drawn from z 64); how the cartridge puts
    -- the book on the shelf's top is not traced
    a.vz, a.vy, a.ai = 32, -5, 2
    if a.book then a.y, a.z = a.y + 64, 64 end
    game.dashItemsFallen = (game.dashItemsFallen or 0) + 1
  elseif a.ai == 3 then
    a.dead = true
    require("src.zelda.alttp.Dash").cancel(game)
    if a.book then game:getItem(M.BOOK)
    else
      game:getItem(0x24)
      actors.inside.mem.bonkKey = true
    end
    game.dashItemsTaken = (game.dashItemsTaken or 0) + 1
  end
end

-- the book as its item-menu icon; a bonk key as the key
function M.draw(game, a, x, y)
  local zz = a.z or 0
  if a.book then
    if game.drawItemIcon then game:drawItemIcon(M.BOOK, x, y - zz) end
  else
    local spr = game.spriteGfx and game:spriteGfx()
    if spr then spr:drawKey(a, x, y - zz) end
  end
end

return M
