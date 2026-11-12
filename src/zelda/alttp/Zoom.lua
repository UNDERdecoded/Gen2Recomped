-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ZOOM AND THE WHOLE MAP (round 14, user request; OURS -- the cartridge has
-- no zoom). The Pokemon games' survey zoom, for ALttP:
--
-- * Input: the mouse wheel (ZeldaRuntime forwards it), the pad's R3 in / L3
--   out and both together back to the default -- the SAME Input actions
--   ("zoomin" / "zoomout", src/core/HotActions.lua defaults, rebindable in
--   CONTROLS) the Pokemon games use, read through ZeldaRuntime.input.
-- * Steps: integer screen pixels per game pixel, like src/render/Zoom.lua:
--   level 0 is the window's own scale S (the cartridge picture, drawn
--   exactly as before: 240 x 160 through the same code path); each step
--   out is one screen pixel less per game pixel (down to 1), each step in
--   one more (up to 2 S). Saved as the game option "zoom" (options.zelda).
-- * Only while walking around (state play / room). Menus, the front end,
--   Four Swords and the overworld map stay the cartridge's 240 x 160.
-- * The view is centred where the cartridge's camera is centred; the HUD
--   and text stay at the normal scale (ZeldaRuntime drawOverlay).
-- * Overworld: every 512 x 512 screen the view touches is drawn from the
--   ROM maps (View:screen), so zooming out shows the connected map around
--   Link, not just his area. Screens beyond the cartridge's own 240 x 160
--   are decoded at most two a frame (no hitch); until then they are black.
-- * Indoors: the rooms of the floor that connect to Link's room (doors
--   that meet on a shared wall, breadth first, at most 3 steps) are drawn at their
--   place in the dungeon's 16 x 16 room grid, one decoded a frame.

local bit = require("bit")
local band = bit.band

local Z = {}

Z.STEP_BUDGET = 2       -- extra overworld screens decoded per frame
Z.ROOM_BUDGET = 1       -- neighbour rooms decoded per frame
Z.ROOM_DEPTH = 3        -- breadth-first steps from Link's room

local DIRS = { { 0, -1, -16, "up" }, { 0, 1, 16, "down" }, { -1, 0, -1, "left" }, { 1, 0, 1, "right" } }

-- the screen pixels per game pixel at a zoom level, for the window scale
function Z.pixelScale(scale, level)
  local S = math.max(1, math.floor((tonumber(scale) or 1) + 1e-6))
  local s = S + (level or 0)
  return math.max(1, math.min(2 * S, s)), S
end

function Z.clampLevel(scale, level)
  local S = math.max(1, math.floor((tonumber(scale) or 1) + 1e-6))
  return math.max(1 - S, math.min(S, math.floor(level or 0)))
end

-- A room's doors on its outer walls (Interior:doorSlots: the cartridge's
-- door list; exits to the overworld are not slots): { [dir] = { positions
-- along the wall } } for dir 1 up (row <= 8), 2 down (row >= 55), 3 left
-- (column <= 6), 4 right (column >= 55). Two rooms of the grid connect when
-- both have a door on the shared wall at the same place (+-2 cells). The
-- castle's maps are floor even in the void outside the walls, so the walls'
-- cells cannot tell; warp doors (0x46) lead elsewhere and do not count.
-- OURS: open edges with no door are not followed.
function Z.edgeDoors(inside)
  local out = { {}, {}, {}, {} }
  local ok, slots = pcall(inside.doorSlots, inside)
  if not ok then return out end
  for _, sl in pairs(slots) do
    local a = sl.addr % 4096
    local col, row = a % 64, math.floor(a / 64)
    if sl.type ~= 0x46 then
      if sl.dir == 0 and row <= 8 then out[1][#out[1] + 1] = col
      elseif sl.dir == 1 and row >= 55 then out[2][#out[2] + 1] = col
      elseif sl.dir == 2 and col <= 6 then out[3][#out[3] + 1] = row
      elseif sl.dir == 3 and col >= 55 then out[4][#out[4] + 1] = row end
    end
  end
  return out
end

local OPP = { 2, 1, 4, 3 }
function Z.doorsMeet(a, b)
  for _, p in ipairs(a) do for _, q in ipairs(b) do if math.abs(p - q) <= 2 then return true end end end
  return false
end

function Z.install(G)
  local function host(self) return self.opts and self.opts.host end

  function G:zoomLevel()
    if self.zoomLv == nil then
      local h = host(self)
      local v = h and h.gameOption and h:gameOption("zoom")
      if v == nil and self.opts then v = self.opts.zoom end
      self.zoomLv = math.floor(tonumber(v) or 0)
    end
    return self.zoomLv
  end

  function G:setZoomLevel(v)
    self.zoomLv = math.floor(v or 0)
    local h = host(self)
    if h and h.gameOption then h:gameOption("zoom", self.zoomLv) end
  end

  -- walking around (not a menu, the front end, Four Swords or a map)
  function G:zoomable()
    if self.state ~= "play" and self.state ~= "room" then return false end
    if self.menu or self.owmap then return false end
    return true
  end

  -- ZeldaRuntime: the play field's size in game pixels for window scale
  -- `scale` (240 x 160 = the cartridge picture)
  function G:viewSize(scale)
    self.lastScale = scale
    local level = self:zoomLevel()
    if level == 0 or not self:zoomable() then
      self.viewW, self.viewH, self.zoomOverlay = 240, 160, nil
      return 240, 160
    end
    level = Z.clampLevel(scale, level)
    local s = Z.pixelScale(scale, level)
    local w = math.ceil(240 * scale / s)
    local h = math.ceil(160 * scale / s)
    self.viewW, self.viewH = w, h
    self.zoomOverlay = (w ~= 240 or h ~= 160) or nil
    return w, h
  end

  -- ZeldaRuntime: the HUD and text at the normal scale over a zoomed field
  function G:drawOverlay()
    self:drawHud()
  end

  -- the view's top-left for the cartridge camera's top-left (cx, cy)
  function G:viewOrigin(cx, cy)
    local vw, vh = self.viewW or 240, self.viewH or 160
    return cx + math.floor((240 - vw) / 2), cy + math.floor((160 - vh) / 2)
  end

  -- one step in (+1) or out (-1); 0 resets
  function G:zoomStep(d)
    if not self:zoomable() then return false end
    local scale = self.lastScale or 1
    local lv = self:zoomLevel()
    local nl = (d == 0) and 0 or Z.clampLevel(scale, lv + d)
    if nl ~= lv then self:setZoomLevel(nl) end
    return true
  end

  function G:wheelmoved(_, dy)
    if (dy or 0) > 0 then self:zoomStep(1) elseif (dy or 0) < 0 then self:zoomStep(-1) end
  end

  -- once per tick: the pad / rebound zoom actions (HotActions' actions)
  function G:zoomInput()
    local inp = self.input
    if not (inp and inp.wasPressed) then return end
    local zin, zout = inp.wasPressed("zoomin"), inp.wasPressed("zoomout")
    if not (zin or zout) then return end
    if inp.isDown and inp.isDown("zoomin") and inp.isDown("zoomout") then
      self:zoomStep(0)
    elseif zin then self:zoomStep(1)
    else self:zoomStep(-1) end
  end

  -- the overworld screens to draw: { s, x, y } for the view, decoding the
  -- ones outside the cartridge's own picture at most STEP_BUDGET a frame
  function G:viewScreens()
    local list = {}
    local x0, y0 = self.cam.x, self.cam.y
    local vw, vh = self.viewW or 240, self.viewH or 160
    local view = self.view
    local budget = Z.STEP_BUDGET
    local core = self.coreCam
    for sy = math.floor(y0 / 512), math.floor((y0 + vh - 1) / 512) do
      for sx = math.floor(x0 / 512), math.floor((x0 + vw - 1) / 512) do
        if sx >= 0 and sy >= 0 and sx < 8 and sy < 8 then
          local s = sy * 8 + sx + (self.link.world == "dw" and 0x40 or 0)
          local need = true
          if view and not view.screens[s] and core then
            -- inside the cartridge's 240 x 160: always; else on budget
            local inCore = sx * 512 < core.x + 240 and sx * 512 + 512 > core.x
                           and sy * 512 < core.y + 160 and sy * 512 + 512 > core.y
            if not inCore then
              if budget > 0 then budget = budget - 1 else need = false end
            end
          end
          if need then list[#list + 1] = { s = s, x = sx * 512 - x0, y = sy * 512 - y0 } end
        end
      end
    end
    if view then view.keep = math.max(12, #list + 8) end
    return list
  end

  -- ------------------------------------------------------- indoor neighbours

  -- rooms connected to `base` (breadth first): { [room] = { dx, dy } } in
  -- room-grid steps
  function G:connectedRooms(base, depth)
    self.roomOpenCache = self.roomOpenCache or {}
    local I = require("src.zelda.alttp.Interior")
    local function doors(r)
      local hit = self.roomOpenCache[r]
      if hit then return hit end
      local ok, x = pcall(function()
        local n = setmetatable({ data = self.data, memory = {} }, I)
        n:loadRoom(r, self.interior.main)
        return n
      end)
      hit = ok and Z.edgeDoors(x) or { {}, {}, {}, {} }
      self.roomOpenCache[r] = hit
      return hit
    end
    local out = { [base] = { 0, 0 } }
    local frontier = { base }
    local count = #(self.data.roomIdx.headers or {})
    for _ = 1, depth do
      local nextF = {}
      for _, r in ipairs(frontier) do
        local o = doors(r)
        for i, d in ipairs(DIRS) do
          local to = r + d[3]
          local sameRow = d[1] == 0 or math.floor(to / 16) == math.floor(r / 16)
          if #o[i] > 0 and sameRow and to >= 0 and to < count and band(to, 0x100) == band(r, 0x100)
             and not out[to] and Z.doorsMeet(o[i], doors(to)[OPP[i]]) then
            out[to] = { out[r][1] + d[1], out[r][2] + d[2] }
            nextF[#nextF + 1] = to
          end
        end
      end
      frontier = nextF
    end
    return out
  end

  -- a neighbour room's three map images (cached; one built a frame)
  function G:neighbourImages(r)
    self.nbCache = self.nbCache or {}
    local key = r .. ":" .. tostring(self.interior.main)
    local hit = self.nbCache[key]
    if hit then return hit end
    if (self.nbBudget or 0) <= 0 then return nil end
    self.nbBudget = self.nbBudget - 1
    local I = require("src.zelda.alttp.Interior")
    local View = require("src.zelda.alttp.View")
    -- the room memory read through a proxy: drawing a room never creates
    -- its memory entry
    local mem = setmetatable({}, { __index = self.roomMemory or {} })
    local n = setmetatable({ data = self.data, memory = mem }, I)
    if not pcall(n.loadRoom, n, r, self.interior.main) then
      self.nbCache[key] = { im = {}, pr = {} }
      return self.nbCache[key]
    end
    local pal = n:palette()
    local im = { backdrop = pal[0] }
    for _, layer in ipairs({ "bg3", "bg2", "bg1" }) do
      if layer ~= "bg3" or n.bg3 then
        local img = love.image.newImageData(512, 512)
        local cells = {}
        View.fill(img, 512, 512, n:decodeLayer(layer, cells), pal, nil)
        local g = love.graphics.newImage(img)
        g:setFilter("nearest", "nearest")
        im[layer] = g
        local AT = require("src.zelda.alttp.AnimTiles")   -- r15
        AT.register(g, img, cells, AT.dungFrames(self.data, n.main), AT.DUNG_BASE, pal, nil)
      end
    end
    hit = { im = im, pr = require("src.zelda.alttp.Layers").roomBg(n.hdr) }
    self.nbCache[key] = hit
    self.nbKeys = self.nbKeys or {}
    self.nbKeys[#self.nbKeys + 1] = key
    while #self.nbKeys > 16 do
      local old = table.remove(self.nbKeys, 1)
      local o = self.nbCache[old]
      if o then for _, g in pairs(o.im) do if type(g) == "userdata" then pcall(g.release, g) end end end
      self.nbCache[old] = nil
    end
    return hit
  end

  -- drawRoom: the neighbour rooms in view, behind the current room
  function G:roomNeighbours(rooms, vx, vy)
    local vw, vh = self.viewW or 240, self.viewH or 160
    local sc = self.roomScroll or self.roomGlide
    local wide = vw > 240 or vh > 160
    if not wide then return end
    self.nbBudget = Z.ROOM_BUDGET
    local base = self.interior.room
    if self.nbBase ~= base then
      self.nbBase, self.nbList = base, self:connectedRooms(base, Z.ROOM_DEPTH)
    end
    local skip = sc and sc.oldRoom
    for r, d in pairs(self.nbList) do
      if r ~= base and r ~= skip then
        local x, y = d[1] * 512 - vx, d[2] * 512 - vy
        if x < vw and y < vh and x + 512 > 0 and y + 512 > 0 then
          local nb = self:neighbourImages(r)
          if nb then rooms[#rooms + 1] = { im = nb.im, x = x, y = y, pr = nb.pr } end
        end
      end
    end
  end

  -- a room's memory changed (doors, chests) or a new entrance: rebuild
  function G:forgetNeighbours()
    for _, o in pairs(self.nbCache or {}) do
      for _, g in pairs(o.im) do if type(g) == "userdata" then pcall(g.release, g) end end
    end
    self.nbCache, self.nbKeys, self.nbBase, self.nbList = {}, {}, nil, nil
  end
end

return Z
