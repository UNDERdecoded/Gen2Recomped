-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The LÖVE side of ALttP: turns decoded screens and Link's cells into Images
-- (nearest-filtered) and keeps a small cache of them.

local Palette = require("src.zelda.alttp.Palette")

local V = {}
V.__index = V

local okFfi, ffi = pcall(require, "ffi")

local function rgba8(c)
  local r, g, b = Palette.rgb(c)
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

-- fill an ImageData from 0-based indices through a palette (0 = transparent
-- unless opaque0 is given as a colour)
local function fill(img, w, h, idx, pal, opaque0)
  local lut = {}
  for i = 0, 255 do
    local c = pal[i]
    if c then lut[i] = { rgba8(c) } end
  end
  local bg = opaque0 and { rgba8(opaque0) } or nil
  if okFfi and img.getPointer then
    local p = ffi.cast("uint8_t*", img:getPointer())
    for i = 0, w * h - 1 do
      local v = idx[i] or 0
      local o = i * 4
      local c = (v ~= 0) and lut[v] or bg
      if c then
        p[o], p[o + 1], p[o + 2], p[o + 3] = c[1], c[2], c[3], 255
      else
        p[o], p[o + 1], p[o + 2], p[o + 3] = 0, 0, 0, 0
      end
    end
  else
    for i = 0, w * h - 1 do
      local v = idx[i] or 0
      local c = (v ~= 0) and lut[v] or bg
      if c then img:setPixel(i % w, math.floor(i / w), c[1] / 255, c[2] / 255, c[3] / 255, 1) end
    end
  end
end
V.fill = fill

function V.new(ow, data, opts)
  opts = opts or {}
  return setmetatable({ ow = ow, data = data, screens = {}, order = {},
                        keep = opts.keep or 12, linkCells = {}, phase = opts.phase or 0 }, V)
end

-- { bg2 = Image, bg1 = Image } for a screen
function V:screen(s)
  local hit = self.screens[s]
  -- bug round: least recently USED goes first (a screen on view stays), and
  -- a screen dropped from outside (a cut bush: screens[s] = nil) leaves no
  -- stale entry in `order` that would later evict its reloaded pictures
  local order = self.order
  for i = #order, 1, -1 do
    if order[i] == s then
      if hit and i == #order then return hit end
      table.remove(order, i)
      break
    end
  end
  if hit then order[#order + 1] = s return hit end
  local pal = self.ow:palette(s, self.phase)
  local out = {}
  local AT = require("src.zelda.alttp.AnimTiles")
  for _, layer in ipairs({ "bg2", "bg1" }) do
    local cells = {}
    local idx = self.ow:decodeLayer(s, layer, cells)
    local img = love.image.newImageData(512, 512)
    fill(img, 512, 512, idx, pal, layer == "bg2" and pal[0] or nil)
    local im = love.graphics.newImage(img)
    im:setFilter("nearest", "nearest")
    out[layer] = im
    -- r15: the animated tiles (water...) step with AnimTiles.tick
    AT.register(im, img, cells, AT.owFrames(self.data, self.ow:parent(s)), AT.OW_BASE, pal,
                layer == "bg2" and pal[0] or nil)
  end
  self.screens[s] = out
  self.order[#self.order + 1] = s
  while #self.order > self.keep do
    local old = table.remove(self.order, 1)
    local o = self.screens[old]
    if o then
      for _, im in pairs(o) do pcall(im.release, im) end
    end
    self.screens[old] = nil
  end
  return out
end

-- an Image of HUD-charblock map words (cols x rows), cached by content
function V:hudImage(words, cols, rows, pal, chrHi)
  local Hud = require("src.zelda.alttp.Hud")
  local key = table.concat(words, ",")
  self.hudCache = self.hudCache or {}
  local hit = self.hudCache[key]
  if hit then return hit end
  self.hudTiles = self.hudTiles or {}
  local idx, w, h = Hud.decode(self.data.uiChr, words, cols, rows, self.hudTiles, chrHi)
  local img = love.image.newImageData(w, h)
  fill(img, w, h, idx, pal)
  local im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  self.hudKeys = self.hudKeys or {}
  self.hudKeys[#self.hudKeys + 1] = key
  self.hudCache[key] = im
  while #self.hudKeys > 8 do
    local old = table.remove(self.hudKeys, 1)
    local o = self.hudCache[old]
    if o then pcall(o.release, o) end
    self.hudCache[old] = nil
  end
  return im
end

-- a message box's text as an Image (168 x 48), rebuilt when it changes
function V:textImage(box, pal)
  if self.textBoxRef == box and self.textVersion == box.version and self.textIm then
    return self.textIm
  end
  local Text = require("src.zelda.alttp.Text")
  local idx, w, h = Text.pixels(self.data, box.glyphs)
  local img = love.image.newImageData(w, h)
  fill(img, w, h, idx, pal)
  if self.textIm then pcall(self.textIm.release, self.textIm) end
  self.textIm = love.graphics.newImage(img)
  self.textIm:setFilter("nearest", "nearest")
  self.textBoxRef, self.textVersion = box, box.version
  return self.textIm
end

-- the cartridge title screen: { bg1 = Image, bg2 = Image, backdrop = {r,g,b} }
function V:titleImages(pal)
  if self.titleIm then return self.titleIm end
  local Hud = require("src.zelda.alttp.Hud")
  local blob = self.data.title
  local chr = blob:sub(1, 0x4000)
  local out = {}
  for name, at in pairs({ bg1 = 0x4000, bg2 = 0x4800 }) do
    local words = {}
    for i = 0, 1023 do
      local a, b = blob:byte(at + i * 2 + 1, at + i * 2 + 2)
      words[i + 1] = a + b * 256
    end
    local idx = {}
    local tiles = {}
    -- charblock 0 holds 512 tiles; decode like the HUD but with this block
    for ty = 0, 31 do
      for tx = 0, 31 do
        local wd = words[ty * 32 + tx + 1]
        local t = wd % 0x200
        local px = Hud.tilePixels(chr, t, tiles)
        local hf, vf = math.floor(wd / 0x400) % 2 == 1, math.floor(wd / 0x800) % 2 == 1
        local p = math.floor(wd / 0x1000) * 16
        for y = 0, 7 do
          local sy = vf and (7 - y) or y
          for x = 0, 7 do
            local c = px[sy * 8 + (hf and (7 - x) or x) + 1]
            idx[(ty * 8 + y) * 256 + tx * 8 + x] = (c ~= 0) and (p + c) or 0
          end
        end
      end
    end
    local img = love.image.newImageData(256, 256)
    fill(img, 256, 256, idx, pal)
    local im = love.graphics.newImage(img)
    im:setFilter("nearest", "nearest")
    out[name] = im
  end
  local r, g, b = rgba8(pal[0])
  out.backdrop = { r / 255, g / 255, b / 255 }
  self.titleIm = out
  return out
end

-- a 16x16 Image of one Link cell (SNES layout: 2 tiles, then 2 tiles 0x200 on)
function V:linkCell(off, pal, key)
  key = (key or "") .. ":" .. off
  local hit = self.linkCells[key]
  if hit then return hit end
  local idx = {}
  local sheet = self.data.link
  for half = 0, 1 do
    for tcol = 0, 1 do
      local base = off + half * 0x200 + tcol * 32
      for y = 0, 7 do
        for xb = 0, 3 do
          local b = sheet:byte(base + y * 4 + xb + 1) or 0
          local px = (half * 8 + y) * 16 + tcol * 8 + xb * 2
          idx[px] = b % 16
          idx[px + 1] = math.floor(b / 16)
        end
      end
    end
  end
  local img = love.image.newImageData(16, 16)
  fill(img, 16, 16, idx, pal)
  local im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  self.linkCells[key] = im
  return im
end

return V
