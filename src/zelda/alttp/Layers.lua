-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BG AND OBJ PRIORITY, the GBA way (round 14). Before this round every room
-- drew all its maps first and the sprites on top, so Link walked OVER the
-- door frames he should pass under (user report).
--
-- How the cartridge does it (alttp.md "Layers and priority (round 14)"):
--
-- * A room's three maps sit on three GBA BGs (0x08079220 copies them to
--   VRAM): our "bg3" (map 0x0201A000, the lower level) on BG1, our "bg2"
--   (0x02018000, the upper level) on BG2, our "bg1" (0x0201C000, the
--   high-priority copy: door frames, wall tops -- the GBA has no per-tile
--   priority bit, the SNES high-priority tiles go to this extra map; the door
--   drawers 0x08084CB0.. write a door's outer row there too) on BG3.
-- * BG priorities: the dungeon entrance (0x08078864) sets BG1 3 and BG3 1,
--   BG2 keeps 2; the room's layer setup 0x0806D598 (run after a room
--   loads, from the SNES TM/TS/CGADSUB the room's BG2 property gives) keeps
--   that, except: TM 0x17 (property 3, "on top") -> BG1 priority 1;
--   CGADSUB 0x62 (property 4) -> BG2 3, BG1 2, BG1 blended 8/16 over the
--   rest; another blend (properties 2 and 7) -> BG1 1, blended 14/16 + 16/16.
-- * The overworld (0x08075C0C): the ground (BG2 table) on GBA BG2, priority
--   2; the overlay (BG1 table: canopies, roofs, door tops) on GBA BG1,
--   priority 1 (defaults set at 0x0806A220).
-- * OBJs keep SNES OAM flags; 0x080A452C converts the SNES priority with the
--   table RomMap.layers.oamPrioMap. Link's SNES priority is
--   linkFloorPrio[link_is_on_lower_level] (0 upper, 1 lower, 2 while an
--   outdoor ledge hop is in the air), a sprite's spritePrios[floor].
-- * The GBA draws priority 3 first, each priority's BGs (BG3 behind BG2
--   behind BG1) and then its OBJs (an OBJ is in front of a BG of the same
--   priority).
--
-- So on the upper level Link (OBJ priority 2) is over both room maps and
-- under the high-priority map; on the lower level (3) he is under the upper
-- map too (a bridge over him). OURS: dark rooms keep our darkness overlay
-- (their 0xB3 colour math is not ported) and the lower map stays at the
-- bottom there; rooms 0x0D / 0x90 / 0xA4 / 0xAC's own cases are not ported.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local L = {}

-- the GBA OBJ priority of a SNES priority (0-3); nil without the tables
function L.objPrio(data, snes)
  local t = data and data.t and data.t.layers
  if not t then return nil end
  return band(t.oamPrioMap[band(snes, 3) + 1] or 2, 3)
end

-- Link: level 0 upper / outdoors, 1 lower, 2 outdoor hop in the air
function L.linkPrio(data, level)
  local t = data and data.t and data.t.layers
  if not t then return nil end
  return L.objPrio(data, rshift(t.linkFloorPrio[(level or 0) + 1] or 0x2000, 12))
end

-- a sprite on floor 0 (upper) or 1 (lower)
function L.spritePrio(data, lower)
  local t = data and data.t and data.t.layers
  if not t then return nil end
  return L.objPrio(data, rshift(t.spritePrios[(lower and 1 or 0) + 1] or 0x20, 4))
end

-- the GBA BG priority of each room map and the blend, from the room header
-- (byte 0: BG2 property << 5 | lights out), as 0x0806D598 sets them
function L.roomBg(hdr)
  local b0 = (hdr and hdr[1]) or 0
  local prop, dark = rshift(b0, 5), band(b0, 1) == 1
  local p = { bg3 = 3, bg2 = 2, bg1 = 1 }
  if dark then return p end
  if prop == 3 then
    p.bg3 = 1
  elseif prop == 4 then
    p.bg2, p.bg3 = 3, 2
    p.blend = { layer = "bg3", a = 8 / 16, b = 8 / 16 }
  elseif prop == 7 or prop == 2 then
    p.bg3 = 1
    p.blend = { layer = "bg3", a = 14 / 16, b = 1 }
  end
  return p
end

-- back to front at one priority: GBA BG3, BG2, BG1
L.BG_ORDER = { "bg1", "bg2", "bg3" }

-- ------------------------------------------------------------------ drawing

function L.install(G)
  -- Link's GBA OBJ priority now (nil: an old cache, draw on top as before)
  function G:linkObjPrio()
    local level = 0
    if self.state == "room" and self.interior then
      level = self.interior.lower and 1 or 0
    elseif self.link and self.link.hop then
      level = 2
    end
    return L.linkPrio(self.data, level)
  end

  -- dark rooms (header byte 0 bit 0): OURS, the round-7 darkness applied to
  -- each BG layer instead of over the whole picture, so sprites stay lit
  -- between the layers
  function G:darkFactor()
    local inside = self.interior
    if not (self.state == "room" and inside and inside.hdr and band(inside.hdr[1] or 0, 1) == 1) then return nil end
    return self.hasLamp and self:hasLamp() and "lamp" or 0.25
  end

  local function lampMask(self, w, h)
    if self.lampMask and self.lampMaskW == w and self.lampMaskH == h then return self.lampMask end
    if self.lampMask then pcall(self.lampMask.release, self.lampMask) end
    local W, H = w * 2, h * 2
    local img = love.image.newImageData(W, H)
    local lamp = 40
    img:mapPixel(function(x, y)
      local d = math.sqrt((x - W / 2) ^ 2 + (y - H / 2) ^ 2)
      local a = d < lamp and 0 or math.min(0.94, (d - lamp) / 16 * 0.94)
      return 1 - a, 1 - a, 1 - a, 1
    end)
    self.lampMask = love.graphics.newImage(img)
    self.lampMaskW, self.lampMaskH = w, h
    return self.lampMask
  end

  -- one BG layer image at (x, y) on screen, with the room's blend and the
  -- darkness
  function G:drawBgLayer(im, x, y, blend)
    local lg = love.graphics
    local dark = self:darkFactor()
    local vw, vh = self.viewW or 240, self.viewH or 160
    if dark == "lamp" then
      local prev = lg.getCanvas()
      if not (self.layerCanvas and self.layerCanvas:getWidth() == vw and self.layerCanvas:getHeight() == vh) then
        if self.layerCanvas then pcall(self.layerCanvas.release, self.layerCanvas) end
        self.layerCanvas = lg.newCanvas(vw, vh)
        self.layerCanvas:setFilter("nearest", "nearest")
      end
      lg.push("all")
      lg.setCanvas(self.layerCanvas)
      lg.origin()
      lg.clear(0, 0, 0, 0)
      lg.setColor(1, 1, 1, 1)
      lg.draw(im, x, y)
      lg.setBlendMode("multiply", "premultiplied")
      lg.draw(lampMask(self, vw, vh), self.link.x + 8 - (self.cam and self.cam.x or 0) - vw,
              self.link.y + 14 - (self.cam and self.cam.y or 0) - vh)
      lg.pop()
      lg.setCanvas(prev)
      lg.setColor(1, 1, 1, 1)
      lg.draw(self.layerCanvas, 0, 0)
      return
    end
    local k = (type(dark) == "number") and dark or 1
    if blend then
      if blend.b >= 1 then
        lg.setBlendMode("add")
        lg.setColor(k, k, k, blend.a)
      else
        lg.setColor(k, k, k, blend.a)
      end
    else
      lg.setColor(k, k, k, 1)
    end
    lg.draw(im, x, y)
    lg.setBlendMode("alpha")
    lg.setColor(1, 1, 1, 1)
  end

  -- THE ROOM FIELD by priority. `rooms` = { { im = { bg1, bg2, bg3 }, x, y
  -- (screen position of the room's top-left), pr = L.roomBg(hdr) } ... }:
  -- the current room, the room being left mid-transition, neighbours.
  -- `sprites(p)` draws the OBJs of GBA priority p.
  function G:drawRoomField(rooms, sprites, bgOff)
    -- the backdrop (colour 0) under each room
    if not bgOff then
      local Palette = require("src.zelda.alttp.Palette")
      for _, r in ipairs(rooms) do
        local c = r.im.backdrop
        if c then
          local cr, cg, cb = Palette.rgb(c)
          local k = self:darkFactor()
          k = (type(k) == "number") and k or 1
          love.graphics.setColor(cr * k, cg * k, cb * k, 1)
          love.graphics.rectangle("fill", r.x, r.y, 512, 512)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    for p = 3, 0, -1 do
      if not bgOff then
        for _, layer in ipairs(L.BG_ORDER) do
          for _, r in ipairs(rooms) do
            local im = r.im[layer]
            if im and r.pr[layer] == p then
              local bl = r.pr.blend and r.pr.blend.layer == layer and r.pr.blend or nil
              -- r24: the moving wall's BG1 offset (DesertPalace.lua)
              local dx, dy, show = 0, 0, true
              if layer == "bg3" and r.im == self.roomImages and self.interior and self.interior.wall then
                dx, dy, show = require("src.zelda.alttp.DesertPalace").bg3Offset(self)
              end
              if show then self:drawBgLayer(im, r.x + dx, r.y + dy, bl) end
            end
          end
        end
      end
      sprites(p)
    end
  end

  -- the OBJs of one GBA priority in a room (actors, the follower, drops,
  -- Link with his sword and what he carries); nil prio = everything (old
  -- cache)
  function G:drawRoomSprites(p, cx, cy)
    local lp = self:linkObjPrio()
    self.prioPass = p
    self:drawActors(cx, cy)
    self:drawDrops(cx, cy, self:spriteGfx())
    if lp == p or (lp == nil and p == 0) then
      -- round 16: a block being pushed (RoomObjects.lua)
      if self.interior then require("src.zelda.alttp.RoomObjects").drawMoving(self, cx, cy) end
      -- r21: the dash dust (Effects.lua); Link is drawn without the shake's
      -- camera offset (LinkOam_Main runs after the camera is put back)
      local Effects = require("src.zelda.alttp.Effects")
      Effects.drawDust(self, self:spriteGfx(), cx, cy)
      local sx, sy = Effects.shakeOffset(self)
      love.graphics.push(); love.graphics.translate(sx, sy)
      if not ((self.blink or 0) > 0 and self.blink % 4 < 2) then self:drawLink(self.link) end
      self:drawSword(cx, cy)
      love.graphics.pop()
    end
    -- the item rising out of a chest: over the room (OURS: its OAM
    -- priority is not traced)
    if p == (lp and 1 or 0) and self.drawReceipt then self:drawReceipt(cx, cy) end
    self.prioPass = nil
  end

  -- does an OBJ at GBA priority `prio` draw in the current pass?
  function G:inPrioPass(prio)
    local p = self.prioPass
    if p == nil then return true end
    if prio == nil then return p == 0 end
    return prio == p
  end
end

return L
