-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WIDESCREEN for ALttP (2026-11-18; OURS, the GBA's picture is 240 x 160).
-- The runtime side is src/zelda/ZeldaWide.lua. Here the play field is made
-- wider through the same seams the zoom uses (Zoom.lua): viewSize returns a
-- field `wide` game pixels wide (times the zoom), viewOrigin centres it on
-- the cartridge's camera, the HUD and text go to the centred 240 x 160
-- overlay (drawOverlay = drawHud).
--
-- * The cartridge's camera, scrolling, room / area bounds and every gameplay
--   rule stay on its own 240 x 160 screen (G.W / G.H, Interior:camera,
--   cameraFor; arrows / boomerangs leave at its edges, Items.lua / Tools.lua).
--   Only the drawing widens; sprites are not culled by the screen.
-- * Overworld: the screens beside the area are drawn from the ROM maps
--   (Zoom's viewScreens), so the neighbouring areas show past an area's edge.
--   At the edge of the 8 x 8 world the view is held inside it (no void); in
--   the special areas (world "sp": the grove, Zora's waterfall...) inside the
--   area, as only its own screens exist.
-- * Indoors: the room's other quadrants (the same 512 x 512 map) and the
--   rooms that connect to it (Zoom's roomNeighbours) are drawn; past them the
--   room's backdrop colour (CGRAM colour 0) fills the view, so a small room
--   sits in its own background, never in a black bar.
-- * The item menu, text, the HUD stay 240 wide in the middle over the wide
--   world; the overworld map, the dungeon map, Four Swords, the front end and
--   the ending keep the cartridge's 240 x 160.
local Z = require("src.zelda.alttp.Zoom")

local M = {}

function M.install(G)
  G.wideScreen = true   -- ZeldaWide: this game takes viewSize(scale, wide)

  -- a wide field is drawn: walking around, the item menu and text included
  function G:wideOk()
    if self.state ~= "play" and self.state ~= "room" then return false end
    if self.owmap or self.dmap or self.ending27 or self.headless then return false end
    return true
  end

  local viewSize0 = G.viewSize
  function G:viewSize(scale, wide)
    wide = math.floor(tonumber(wide) or 240)
    if wide <= 240 or not self:wideOk() then
      self.wideW = nil
      return viewSize0(self, scale)
    end
    self.lastScale = scale
    self.wideW = wide
    local level = self:zoomable() and self:zoomLevel() or 0
    local w, h = wide, 160
    if level ~= 0 then
      local s = Z.pixelScale(scale, Z.clampLevel(scale, level))
      w, h = math.ceil(wide * scale / s), math.ceil(160 * scale / s)
    end
    self.viewW, self.viewH, self.zoomOverlay = w, h, true
    return w, h, wide
  end

  -- outdoors, the view stays inside the world (or the special area)
  local viewOrigin0 = G.viewOrigin
  function G:viewOrigin(cx, cy)
    local vx, vy = viewOrigin0(self, cx, cy)
    if not self.wideW then return vx, vy end
    if self.state == "room" and self.interior then return M.roomClamp(self, vx, vy) end
    if self.state ~= "play" or self.interior then return vx, vy end
    local vw = self.viewW or 240
    local x0, x1 = 0, 4096
    if self.link and self.link.world == "sp" then
      local a = self.area
      if not a or self.scroll then return vx, vy end
      x0, x1 = a.x, a.x + a.w
    end
    if x1 - x0 >= vw then vx = math.max(x0, math.min(x1 - vw, vx)) end
    return vx, vy
  end

  -- indoors, a side with no connected room is not shown: the view stays
  -- inside the room's 512 px map there (its other quadrant fills the field)
  function M.roomClamp(g, vx, vy)
    local base = g.interior.room
    if base == nil or not g.connectedRooms then return vx, vy end
    if g.nbBase ~= base or not g.nbList then
      local ok, list = pcall(g.connectedRooms, g, base, Z.ROOM_DEPTH)
      if not ok then return vx, vy end
      g.nbBase, g.nbList = base, list
    end
    local west, east = false, false
    for _, d in pairs(g.nbList) do
      if d[2] == 0 and d[1] == -1 then west = true end
      if d[2] == 0 and d[1] == 1 then east = true end
    end
    local vw = g.viewW or 240
    if vw > 512 then return vx, vy end
    if not east and vx + vw > 512 then vx = 512 - vw end
    if not west and vx < 0 then vx = 0 end
    return vx, vy
  end

  -- indoors, the room's backdrop under the whole view
  local drawRoom0 = G.drawRoom
  function G:drawRoom(...)
    local ri = self.roomImages
    if self.wideW and ri and ri.backdrop and not (self.opening == "telepathy" and self.textBox) then
      local Palette = require("src.zelda.alttp.Palette")
      local r, g, b = Palette.rgb(ri.backdrop)
      local k = self.darkFactor and self:darkFactor()
      k = (type(k) == "number") and k or 1
      love.graphics.clear(r * k, g * k, b * k, 1)
    end
    return drawRoom0(self, ...)
  end
end

return M
