-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 34: THE BIRD'S RIDE, DRAWN (Ancilla27_Duck, zelda3 names).
--
-- Its picture: the GBA's LoadItemGFXIntoWRAM4BPPBuffer tail (0x0812FDEC)
-- decompresses sprite sheet 0x58 (the table 0x0822B324, entry 0x160 / 4) and
-- copies its first 0x100 words to RAM 0x0200A8C0 -- the SNES's 0x7EB540
-- buffer that flag_travel_bird DMAs from: a frame's top two tiles at
-- buffer + DmaStuffs[j] * 2, the bottom two 0x200 bytes on (SNES
-- dma_source_addr_20 / 21). So the bird is sheet 0x58's tiles t, t + 1,
-- t + 16, t + 17 with t = DmaStuffs[j] / 16. Its tables, read at import
-- (0x1803D0..): Draw_Char {0x0C, 0, 2}, Draw_Flags {0x22, 0x2E, 0x2E} (the
-- bird on palette row 1, Link's two OAM entries on his own), Draw_Y {0, 12,
-- 20}, Draw_X {0, -9, -9}, DmaStuffs {0, 0x20, 0x40, 0xE0}.
--
-- The take-off (AncillaAdd_Duck_take_off + AddBirdCommon): 0x78 frames held
-- at the screen's left edge - 16, Link's y - 8; then x speed 56 (1/16 px),
-- a wing frame every 4th frame (ancilla_arr3 3, K cycling 0..2), a flap
-- sound every 0x29 frames (OURS: not played); touching Link -> step 2:
-- Link is hidden and drawn by the bird (his head / body chars at (-9, 12) /
-- (-9, 20), pose_for_item 1), z speed -1 a frame (the bird climbs); off the
-- screen's right (x >= 0x130) the flute menu opens (Module0E_0A).
-- The landing (BirdTravel_Finish_Doit -> AddBirdTravelSomething): step 2,
-- L 1, z -51 (0xCD), z speed 40 falling by 1 a frame, from the left edge;
-- 48 px before Link's x the wings are held (frame 3); at Link's x he is
-- let go (visible, 144 frames of blink) and the bird flies on off-screen.
-- Shadows at y + 28 (and x - 7 while carrying).
--
-- OURS: Link carried is drawn with the port's LinkOam pieces at pose row
-- 0x23 (the SNES's pose_for_item 1 = row 0x1D, + the GBA's 6 extra rows as
-- the tablet's 0x1E -> 0x24), not the two DMA'd chars; Ancilla_CheckLink
-- Collision is the bird's x reaching Link's - 8 on his row; the shadow is
-- not drawn; the blink after the drop is not drawn.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = { NAME = "bird34" }

M.OFF = { draw = 0x1803D0, dma = 0x1803DC }
M.SHEET = 0x58

function M.extract(rom, R, check)
  local o = M.OFF.draw
  local function s8(v) return v >= 128 and v - 256 or v end
  local t = {
    char = rom:bytesU8(o, 3), flags = rom:bytesU8(o + 3, 3),
    y = rom:bytesU8(o + 6, 3), x = rom:bytesU8(o + 9, 3), dma = rom:bytesU8(M.OFF.dma, 4),
  }
  for i = 1, 3 do t.y[i], t.x[i] = s8(t.y[i]), s8(t.x[i]) end
  check(t.char[1] == 0x0C and t.flags[1] == 0x22 and t.flags[2] == 0x2E and t.y[2] == 12 and t.x[2] == -9
        and t.dma[2] == 0x20 and t.dma[4] == 0xE0, "travel bird tables")
  return t
end

local function T(game) return game.data and game.data.t and game.data.t.bird34 end
M.T = T

-- one bird on the screen; land = the arrival carrying Link
function M.spawn(game, land)
  local lk = game.link
  local b = { x = (game.cam and game.cam.x or 0) - 16, y = lk.y - 8, sx = 0, z = 0, sz = 0,
              vz = 0, vx = 56, arr3 = 3, K = 0, G = 0, j = 0,
              timer = land and 0 or 0x78, step = land and 2 or 0, land = land }
  if land then b.z, b.vz = -51, 40 end
  game.bird34 = b
  game.birdsSpawned = (game.birdsSpawned or 0) + 1
  return b
end

-- Ancilla_MoveX / MoveZ: 1/16 px
local function move(b, k, vk, sk)
  local v = b[vk] * 1 + b[sk]
  local whole = (v >= 0) and math.floor(v / 16) or -math.floor(-v / 16)
  b[sk] = v - whole * 16
  b[k] = b[k] + whole
end

-- one frame; returns "menu" when the take-off leaves the screen, "gone" at the end
function M.frame(game)
  local b = game.bird34
  if not b then return nil end
  local lk = game.link
  local cx = game.cam and game.cam.x or 0
  if b.timer > 0 then
    b.timer = b.timer - 1
    b.x, b.y = cx - 16, lk.y - 8
    return nil
  end
  if b.land or b.step ~= 0 then
    b.vz = b.vz - 1
    move(b, "z", "vz", "sz")
  end
  move(b, "x", "vx", "sx")
  local forced
  if b.land then
    if b.x >= lk.x then
      if b.step ~= 0 then
        b.step = 0
        game.birdDrops = (game.birdDrops or 0) + 1
      end
    elseif lk.x - b.x < 48 then
      forced = 3
    end
  elseif b.step == 0 and b.x + 8 >= lk.x and math.abs(b.y + 8 - lk.y) < 16 then
    b.step = 2
    game.birdPickups = (game.birdPickups or 0) + 1
  end
  if forced then b.j = forced
  else
    b.arr3 = b.arr3 - 1
    if b.arr3 < 0 then
      b.arr3 = 3
      b.K = b.K + 1
      if b.K == 3 then b.K = 0 end
    end
    b.j = b.K
  end
  if b.x - cx >= 0x130 then
    game.bird34 = nil
    if not b.land and b.step ~= 0 then return "menu" end
    return "gone"
  end
  return nil
end

-- Link is the bird's while it carries him
function M.carrying(game)
  local b = game.bird34
  return b ~= nil and b.step ~= 0
end

local function rgba(c) return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31 end

-- the 16x16 of frame j: sheet 0x58 tiles t, t + 1 / t + 16, t + 17
function M.image(spr, t, j, palRow)
  local key = "b34:" .. j .. ":" .. palRow
  local im = spr.cache[key]
  if im ~= nil then return im or nil end
  local base = M.SHEET * 4096 + (t.dma[j + 1] or 0) * 2
  local img = love.image.newImageData(16, 16)
  local src, pal = spr.data.spr, spr.pal[palRow]
  if not (src and pal) then spr.cache[key] = false return nil end
  for ty = 0, 1 do
    for tx = 0, 1 do
      local off = base + ty * 0x200 + tx * 32
      for y = 0, 7 do
        for xb = 0, 3 do
          local v = src:byte(off + y * 4 + xb + 1) or 0
          local lo, hi = v % 16, math.floor(v / 16)
          if lo ~= 0 and pal[lo] then local r, g, bb = rgba(pal[lo]) img:setPixel(tx * 8 + xb * 2, ty * 8 + y, r, g, bb, 1) end
          if hi ~= 0 and pal[hi] then local r, g, bb = rgba(pal[hi]) img:setPixel(tx * 8 + xb * 2 + 1, ty * 8 + y, r, g, bb, 1) end
        end
      end
    end
  end
  im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  spr.cache[key] = im
  return im
end

function M.draw(game, spr, cx, cy)
  local b = game.bird34
  local t = T(game)
  if not (b and t and spr and spr.pal) then return end
  local x, y = b.x - cx, b.y - cy + b.z
  -- Link first (the bird's OAM entries 1 / 2 come after its own in OAM
  -- order, so the bird is in front)
  if b.step ~= 0 then
    local lk = game.link
    local ox, oy, oz = lk.x, lk.y, lk.z
    lk.x, lk.y, lk.z = b.x + t.x[2], b.y + t.y[2] + b.z, 0
    game.bird34Pose = true
    local ok = pcall(game.drawLink, game, lk)
    game.bird34Pose = nil
    lk.x, lk.y, lk.z = ox, oy, oz
    if not ok then return end
  end
  local im = M.image(spr, t, b.j, band(rshift(t.flags[1], 1), 7))
  if im then love.graphics.draw(im, x, y) end
  game.bird34Draws = (game.bird34Draws or 0) + 1
end

function M.install(G)
  if G.bird34Installed then return end   -- (not G.bird34: that is the game's bird)
  G.bird34Installed = true
  local Flute = require("src.zelda.alttp.Flute")
  -- the take-off replaces Flute.lua's 48-frame ride
  local upd0 = G.update
  function G:update(dt)
    if T(self) and self.birdRide and not self.bird34 and self.state == "play" and not self.textBox and not self.owmap then
      self.birdRide = nil
      M.spawn(self, false)
      self.birdTakeoff = true
    end
    if self.bird34 and self.state == "play" and not self.textBox and not self.owmap then
      local r = M.frame(self)
      if r == "menu" then self.birdTakeoff = nil; Flute.openMenu(self) end
      if r == "gone" then self.birdTakeoff = nil end
    end
    return upd0(self, dt)
  end
  -- the landing: the bird brings Link
  local land0 = Flute.land
  function Flute.land(game, i)
    local r = land0(game, i)
    if T(game) and game.cam then M.spawn(game, true) end
    return r
  end
  -- Link held while the bird has him (and while it waits to take off)
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    if (self.bird34 and (self.bird34.step ~= 0 or self.birdTakeoff)) and inp then
      for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "y", "r" }) do inp[k] = false end
    end
    return owFrame(self, inp)
  end
  -- Link hidden while carried; drawn by the bird with his pose_for_item row
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    if lk == self.link and M.carrying(self) and not self.bird34Pose then return end
    return dl0(self, lk, tint)
  end
  local pose0 = G.linkPose
  function G:linkPose()
    if self.bird34Pose then return 0x23, 0 end
    return pose0(self)
  end
  -- OAM priority 3 (flags | 0x30): over the BG1 overlay, so after it
  local xf0 = G.drawCrossfade
  function G:drawCrossfade()
    if xf0 then xf0(self) end
    if self.state == "play" and self.bird34 and self.cam then
      M.draw(self, self:shadowSprites(), self.cam.x, self.cam.y)
    end
  end
end

return M
