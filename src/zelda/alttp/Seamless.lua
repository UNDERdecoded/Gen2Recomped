-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SEAMLESS TRANSITIONS (round 14, user request; OURS). The cartridge stops
-- Link and scrolls the screen when he crosses into the next overworld area or
-- dungeon room, and cuts between the overworld and a room. With seamless
-- transitions on (the default) instead:
--
-- * Overworld area to area: the area switches the moment Link crosses (the
--   same test as the cartridge's, Game:update), Link keeps walking and the
--   camera glides from the old area's bounds to the new one's (followCam).
--   The neighbouring screens are drawn already (View caches them), so
--   nothing goes black.
-- * Dungeon room to room and quadrant to quadrant: the cartridge's walk-in
--   and landing (Doors.lua: +28 / -18 / +21 / -8, kStaircaseTab2's spot)
--   run exactly as before -- every door, layer toggle, trapdoor and kill
--   memory rule fires at the same place -- but the landing starts at once
--   instead of after the pan, and the camera glides there meanwhile; the
--   room being left stays drawn while it is in view.
-- * Doors and stairs that change map (an entrance, an exit, stairs to
--   another room): a 12-frame crossfade from the last picture instead of a
--   cut.
--
-- The system menu's "CARTRIDGE TRANSITIONS" (off by default) brings back
-- the round-13 behaviour: the area scroll with Link stopped, the room pan,
-- the cuts. Saved as the game option "cartTransitions".

local S = {}

S.FADE_FRAMES = 12

-- one axis of the camera glide: at least 2 px, a sixth of the way
local function approach(v, target)
  local d = target - v
  if d == 0 then return v end
  local st = math.max(2, math.ceil(math.abs(d) / 6))
  if st >= math.abs(d) then return target end
  return v + (d > 0 and st or -st)
end
S.approach = approach

function S.install(G)
  local function host(self) return self.opts and self.opts.host end

  function G:seamless()
    if self.cartTrans == nil then
      local h = host(self)
      local v = h and h.gameOption and h:gameOption("cartTransitions")
      if v == nil then v = self.opts and self.opts.cartTransitions end
      self.cartTrans = v == true
    end
    return not self.cartTrans
  end

  function G:setCartTransitions(on)
    self.cartTrans = on and true or false
    local h = host(self)
    if h and h.gameOption then h:gameOption("cartTransitions", self.cartTrans) end
  end

  -- ZeldaRuntime's system menu rows
  function G:menuOptions()
    local lv = self.zoomLevel and self:zoomLevel() or 0
    local zl = lv == 0 and "FIT" or (lv < 0 and ("OUT" .. -lv) or ("IN" .. lv))
    return {
      { id = "trans", label = "CARTRIDGE TRANSITIONS", value = self:seamless() and "OFF" or "ON" },
      { id = "zoom", label = "ZOOM (WHEEL, L3 / R3)", value = zl },
    }
  end

  function G:menuOption(id, dir)
    if id == "trans" then
      self:setCartTransitions(self:seamless())
    elseif id == "zoom" then
      local scale = self.lastScale or 1
      local Z = require("src.zelda.alttp.Zoom")
      self:setZoomLevel(Z.clampLevel(scale, (self:zoomLevel() or 0) + (dir or 1)))
    end
  end

  -- ------------------------------------------------------------ overworld

  -- the area changes under Link without stopping him (the cartridge's
  -- beginScroll minus the scroll)
  function G:seamlessArea(newArea)
    local oldArea = self.area
    self.area = newArea
    self.ow.attrCache = {}
    self.camGlide = { x = self.cam.x, y = self.cam.y }
    self.areaSwitches = (self.areaSwitches or 0) + 1
    if self.music.screenChanged then self.music:screenChanged(oldArea.parent, newArea.parent, self.link.world) end
    self.cam = self:followCam(self.area)
  end

  -- the camera for this frame: the cartridge's (cameraFor), or on the way
  -- there after a seamless area switch
  function G:followCam(area)
    local target = self:cameraFor(area)
    local g = self.camGlide
    if not g then return target end
    g.x, g.y = approach(g.x, target.x), approach(g.y, target.y)
    if g.x == target.x and g.y == target.y then self.camGlide = nil end
    return { x = g.x, y = g.y }
  end

  -- ---------------------------------------------------------------- rooms

  local updateRoomScroll0 = G.updateRoomScroll
  function G:updateRoomScroll()
    local sc = self.roomScroll
    if sc and self:seamless() and not sc.seamless then
      sc.seamless = true
      local p = math.min(1, sc.t / sc.frames)
      self.roomGlide = { x = math.floor(sc.fromX + (sc.toX - sc.fromX) * p + 0.5),
                         y = math.floor(sc.fromY + (sc.toY - sc.fromY) * p + 0.5),
                         old = sc.old, oldX = sc.oldX, oldY = sc.oldY, oldPr = sc.oldPr, oldRoom = sc.oldRoom }
      -- the landing (Doors.landing) starts now; without one Link walks his
      -- 16 px as before
      if sc.land then sc.t = sc.frames - 1 else sc.frames = 16 end
    end
    return updateRoomScroll0(self)
  end

  -- once per room tick: the glide toward the cartridge's camera
  function G:updateRoomGlide()
    local g = self.roomGlide
    if not (g and self.interior) then return end
    local tx, ty = self.interior:camera(self.link.x, self.link.y, 240, 160)
    g.x, g.y = approach(g.x, tx), approach(g.y, ty)
    if g.x == tx and g.y == ty and not self.roomScroll then self.roomGlide = nil end
  end

  local updateRoom0 = G.updateRoom
  function G:updateRoom()
    local r = updateRoom0(self)
    self:updateRoomGlide()
    return r
  end

  -- ------------------------------------------------------------ crossfade

  function G:startCrossfade()
    if not self:seamless() or self.headless then return end
    self.xfade = { t = 0, n = S.FADE_FRAMES, pending = true }
    self.crossfades = (self.crossfades or 0) + 1
  end

  function G:updateCrossfade()
    local x = self.xfade
    if not x or x.pending then return end
    x.t = x.t + 1
    if x.t >= x.n then
      self.xfade = nil
      if x.img then pcall(x.img.release, x.img) end
    end
  end

  -- at the end of the field (before the HUD): keep a copy of the picture
  -- for the next crossfade, and draw the old picture fading out over a new
  -- one
  function G:drawCrossfade()
    if not self:seamless() then return end
    local lg = love.graphics
    local cur = lg.getCanvas()
    if not cur then return end
    local x = self.xfade
    if x and x.pending then
      x.pending = nil
      x.img, self.fieldCanvas = self.fieldCanvas, nil
      if not x.img then self.xfade = nil; x = nil end
    end
    local w, h = cur:getDimensions()
    if not (self.fieldCanvas and self.fieldCanvas:getWidth() == w and self.fieldCanvas:getHeight() == h) then
      if self.fieldCanvas then pcall(self.fieldCanvas.release, self.fieldCanvas) end
      self.fieldCanvas = lg.newCanvas(w, h)
      self.fieldCanvas:setFilter("nearest", "nearest")
    end
    lg.push("all")
    lg.setCanvas(self.fieldCanvas)
    lg.origin()
    lg.setBlendMode("replace", "premultiplied")
    lg.setColor(1, 1, 1, 1)
    lg.draw(cur, 0, 0)
    lg.pop()
    if x and x.img then
      lg.push("all")
      lg.origin()
      lg.setColor(1, 1, 1, 1 - x.t / x.n)
      local iw, ih = x.img:getDimensions()
      lg.draw(x.img, math.floor((w - iw) / 2), math.floor((h - ih) / 2))
      lg.pop()
    end
  end

  -- the map changes: an entrance, an exit, stairs to another room
  local enterRoom0 = G.enterRoom
  function G:enterRoom(e)
    if self.state == "play" then self:startCrossfade() end
    if self.forgetNeighbours then self:forgetNeighbours() end
    self.roomGlide, self.camGlide = nil, nil
    return enterRoom0(self, e)
  end

  local leaveRoom0 = G.leaveRoom
  function G:leaveRoom()
    self:startCrossfade()
    if self.forgetNeighbours then self:forgetNeighbours() end
    self.roomGlide, self.camGlide = nil, nil
    return leaveRoom0(self)
  end

  local startRoomScroll0 = G.startRoomScroll
  function G:startRoomScroll(dir, leaves, stairRoom)
    if stairRoom then
      self:startCrossfade()
      self.roomGlide = nil
    end
    return startRoomScroll0(self, dir, leaves, stairRoom)
  end

  local enterStart0 = G.enterStart
  function G:enterStart(i, e)
    if self.forgetNeighbours then self:forgetNeighbours() end
    self.roomGlide, self.camGlide = nil, nil
    return enterStart0(self, i, e)
  end
end

return S
