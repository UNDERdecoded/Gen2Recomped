-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE OVERWORLD MAP SCREEN (round 8), ported from the GBA (RomMap.owmap):
-- the cartridge's 512x512 map picture (8bpp tiles, one-byte map, 128
-- colours per world), drawn line by line the way its HBlank handler sets the
-- affine registers from the per-line zoom table (the SNES mode-7 tilt), the
-- zoom and scroll rules of 0x080B1EFC and the Link-centred start of
-- 0x080B198C. Ours: the marker is Link's head cell placed by inverting the
-- line formula (the GBA's own marker routine 0x080B23F8 is not ported), and
-- the fade in/out is not drawn.

local bit = require("bit")
local band = bit.band
local R = require("src.zelda.alttp.RomMap")

local O = {}
O.__index = O

function O.available(data)
  return data and data.menus and data.menus.info.blobs.owTiles and true or false
end

function O.new(game)
  local self = setmetatable({ game = game, data = game.data, t = game.data.menus }, O)
  return self
end

local function s16(v) return v >= 0x8000 and v - 0x10000 or v end

-- 0x080B198C: centre on Link (zoomed in)
function O:centre()
  local lk = self.game.link
  local y0 = band(math.floor(lk.y / 16) + 0x30, 0xFFFE)
  local x0 = band(math.floor(lk.x / 16) + 0x80, 0xFFFE)
  local L = R.owmap.limit
  local t = self.t
  local yHi, yLo = s16(t:u16(L + 4)), s16(t:u16(L + 8))
  local xHi, xLo = s16(t:u16(L + 6)), s16(t:u16(L + 10))
  if y0 >= yHi then y0 = yHi elseif y0 <= yLo then y0 = yLo end
  if x0 >= xHi then x0 = xHi elseif x0 <= xLo then x0 = xLo end
  self.x0, self.y0 = x0, y0
end

function O:setZoom(flags)
  self.flags = flags
  local z = {}
  for i = 0, 229 do z[i] = self.t:u16(R.owmap.zoom[flags] + i * 2) end
  self.scale = z
  if flags == 1 then self:centre() else self.x0, self.y0 = R.owmap.outX0, R.owmap.outY0 end
end

function O:open()
  self.world = self.game.link.world == "dw" and "dw" or "lw"
  self.wait, self.frame, self.done = 0, 0, false
  self:setZoom(1)
end

-- one GBA frame
function O:update(input)
  local function pressed(b) return input and input.wasPressed(b) end
  local function held(b) return input and input.isDown(b) end
  self.frame = self.frame + 1
  if pressed("b") then self.done = true; return end
  if self.wait > 0 then
    self.wait = self.wait - 1
  elseif pressed("l") or pressed("r") or pressed("a") then
    self.wait = 8
    self:setZoom(1 - self.flags)
  end
  if self.flags == 1 then
    local t, S, L = self.t, R.owmap.step, R.owmap.limit
    -- the SNES-style held byte: up 8, down 4, left 2, right 1
    local h = (held("up") and 8 or 0) + (held("down") and 4 or 0)
    local k = band(h, 0x0C)
    if self.y0 ~= s16(t:u16(L + k)) then self.y0 = self.y0 + s16(t:u16(S + k)) end
    local hx = (held("left") and 2 or 0) + (held("right") and 1 or 0)
    k = (hx * 2 + 1) * 2
    if self.x0 ~= s16(t:u16(L + k)) then self.x0 = self.x0 + s16(t:u16(S + k)) end
  end
end

-- the 512x512 picture of a world, built once
function O:image()
  self.images = self.images or {}
  local hit = self.images[self.world]
  if hit then return hit end
  local t = self.t
  local tiles = t:get("owTiles")
  local map = t:get(self.world == "dw" and "owMapDw" or "owMapLw")
  local pal = t:get(self.world == "dw" and "owPalDw" or "owPalLw")
  local cols = {}
  for i = 0, 127 do
    local c = pal:byte(i * 2 + 1) + pal:byte(i * 2 + 2) * 256
    cols[i] = { band(c, 31) / 31, band(bit.rshift(c, 5), 31) / 31, band(bit.rshift(c, 10), 31) / 31 }
  end
  self.backdrop = cols[0]
  local img = love.image.newImageData(512, 512)
  for ty = 0, 63 do
    for tx = 0, 63 do
      local tn = map:byte(ty * 64 + tx + 1)
      local base = tn * 64
      for y = 0, 7 do
        for x = 0, 7 do
          local c = cols[tiles:byte(base + y * 8 + x + 1) % 128]
          img:setPixel(tx * 8 + x, ty * 8 + y, c[1], c[2], c[3], 1)
        end
      end
    end
  end
  local im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  im:setWrap("repeat", "repeat")
  self.images[self.world] = im
  return im
end

-- where a map pixel (tx, ty) lands on the screen (inverts the line formula)
function O:toScreen(tx, ty)
  for line = 0, 159 do
    local s = self.scale[line]
    local y = math.floor((self.y0 * 256 + (s + math.floor(s / 2)) * line) / 256)
    if y >= ty then
      return 120 + (tx - self.x0) * 256 / s, line
    end
  end
  return nil
end

function O:draw()
  local im = self:image()
  local W = 512
  self.quad = self.quad or love.graphics.newQuad(0, 0, 1, 1, W, W)
  local q = self.quad
  local c = self.backdrop
  love.graphics.clear(0, 0, 0, 1)
  for line = R.owmap.winTop, R.owmap.winBottom - 1 do
    local s = self.scale[line]
    local bx = self.x0 * 256 - 120 * s
    local by = self.y0 * 256 + (s + math.floor(s / 2)) * line
    local ty = math.floor(by / 256)
    local tx = bx / 256
    q:setViewport(tx, ty, 240 * s / 256, 1, W, W)
    love.graphics.draw(im, q, 0, line, 0, 256 / s, 1)
  end
  -- Link's marker: his head cell, blinking every 16 frames (SNES frame & 0x10)
  if band(self.frame, 0x10) ~= 0 then
    local g = self.game
    local lk = g.link
    local sx, sy = self:toScreen(lk.x / 16 + 128, lk.y / 16 + 128)
    if sx and g.view then
      local Link = require("src.zelda.alttp.Link")
      local parts = Link.pose(g.data, Link.DOWN, 0)
      local p = parts[1]
      local cell = g.view:linkCell(p.cell, g.linkPal, "green")
      love.graphics.draw(cell, math.floor(sx) - 8, sy - 8)
    end
  end
  return c
end

return O
