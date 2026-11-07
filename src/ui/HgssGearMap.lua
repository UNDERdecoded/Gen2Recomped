-- THE POKeGEAR'S MAP (overlay 101: pokegear_map.c, overlay_101_021E7FF4 /
-- 021E9270 / 021EB568), the MAP app of src/ui/HgssPokegear.lua.
--
-- READ FROM CODE:
--   * the map: pgmap NSCR 11 (a linear 64-column map) on MAIN_3, its first
--     47 x 20 tiles; Kanto covered until the map card's unlock level allows
--     it (cols 22-27 from the source's (48, 0) at level 0, 29-31 from (54, 0)
--     at level 1) (ov101_021EAF40)
--   * a map cell is one tile: the cursor starts on the player, whose cell is
--     the field's matrix cell with y + 2 (PokegearMap_InitInternal); the
--     cursor keeps to x 2 .. maxX - 1 (maxX 26 / 29 / 45 by unlock level,
--     sMapXScrollLimits) and y 2 .. 17 (ov101_021EB654), one cell per two
--     frames while a direction is held
--   * the view: unzoomed 24 x 17 cells of 8 px, zoomed 12 x 8 of 16 px, from
--     (8, 8) (centerX / centerY); it scrolls when the cursor would leave
--     screen cells 1 .. 22 / 16 (zoomed 10 / 7) (ov101_021EC304), clamped to
--     cells 1 .. maxX / 17; X or the zoom button (y 88-152, x 216-248)
--     toggles the zoom (SEQ_SE_GS_GEARXBUTTON / SEQ_SE_GS_XBUTTON_SYUKUSHOU)
--   * touch: a tap on the map (x 8-200, y 8-152) moves the cursor to that
--     cell (clamped to screen cells 1..22 / 1..16, zoomed 1..10 / 1..7) with
--     SEQ_SE_GS_GEARMAPTOUCH, and dragging scrolls the map
--   * the frame (MAIN_1): NSCR 32 + skin's first 20 rows; the Y (markings)
--     button's states at (6 state, 21) 6 x 7 to (26, 2) -- 0 up, 1 pressed,
--     2 grey where nothing can be marked -- and the X (zoom) button's at
--     (6 state + 18, 21) 6 x 9 to (26, 11), state = zoomed (ov101_021EB38C)
--   * the cursor (map OBJ set B seq 0) and the player (set B seq 1, frame =
--     gender)
--   * the top screen (SUB): NSCR 56 + skin rows 7-23 (SUB_2); for a cell
--     inside one of the 100 sLocationSpecs, the region's name (bank 273 1
--     Johto / 0 Kanto) at window (1, 8) + (2, 4), the landmark's name at (3,
--     12), its flavour text (bank 273) at (1, 14), its picture frame (the
--     NSCR's block (8, 0), else (0, 0)) at (23, 11) and its picture (NSCR 13,
--     block - 1 in a 4-wide grid of 7 x 7) at (24, 11) (ov101_021EAA0C);
--     Sinjoh / the S.S. Aqua hidden unless the player is there, Kanto's
--     specs hidden before the Kanto map (except Mt. Silver at 25, 10)
--   * the roaming legendaries (ov101_021E9270.c "Roamer icons", sprites
--     from template 4 = set B anim 2, frame = roamer index: Raikou 0, Entei
--     1, Latias 2, Latios 3): each active roamer (GetRoamerIsActiveByIndex)
--     at its met location's spec (PokegearMap_GetLocationSpecByMapID):
--     ((x - left) * grid + 8 + grid / 2 + objXoffset * (zoomed + 1), same
--     for y) (Map:drawRoamers)
--   * the markings mode (Y on a markable place) is src/ui/HgssGearMarkings
--     (icons and Easy Chat words per place, the top screen's strip, the
--     map's has-markings sprites: set B anim 4 at the place's sprite spot)
-- NOT DONE: the
-- rematch / gift icon, greying the towns not yet visited, the zoom's affine
-- slide animation (the view changes at once).

local Font = require("src.render.Font")
local Markings = require("src.ui.HgssGearMarkings")

local Map = {}
Map.__index = Map

local floor = math.floor
local X_LIMIT = { [0] = 26, 29, 45 }
local MIN, MAX_Y = 1, 17
local CENTER = 8
local SINJOH, SS_AQUA = 521, 307

function Map.new(gear)
  local self = setmetatable({ gear = gear, game = gear.game, t = 0, step = 0 }, Map)
  local pg = gear:save()
  self.level = math.max(0, math.min(2, tonumber(pg.mapLevel) or 0))
  self.maxX = X_LIMIT[self.level]
  self.zoomed = pg.mapZoom == true
  local mx, my = gear:matrixCell()
  self.px, self.py = mx, my + 2
  self.cx = math.max(2, math.min(self.maxX - 1, self.px))
  self.cy = math.max(2, math.min(MAX_Y, self.py))
  local _, headerId = gear:header()
  self.hereId = headerId
  self:recenter()
  self:select()
  return self
end

function Map:grid() return self.zoomed and 16 or 8 end
function Map:viewW() return self.zoomed and 12 or 24 end
function Map:viewH() return self.zoomed and 8 or 17 end

-- ov101_021E9530: the view around the cursor, clamped to the scroll limits
function Map:recenter()
  local w, h = self:viewW(), self:viewH()
  local left = self.cx - floor(w / 2) + (self.zoomed and 0 or 1)
  local top = self.cy - floor(h / 2)
  left = math.max(MIN, math.min(self.maxX - w + 1, left))
  top = math.max(MIN, math.min(MAX_Y - h + 1, top))
  self.left, self.top = left, top
end

-- keep the cursor inside screen cells 1 .. limit (ov101_021EC304)
function Map:follow()
  local limX = self.zoomed and 10 or 22
  local limY = self.zoomed and 7 or 16
  local sx, sy = self.cx - self.left, self.cy - self.top
  if sx < 1 then self.left = self.cx - 1 elseif sx > limX then self.left = self.cx - limX end
  if sy < 1 then self.top = self.cy - 1 elseif sy > limY then self.top = self.cy - limY end
  local w, h = self:viewW(), self:viewH()
  self.left = math.max(0, math.min(self.maxX - w + 1, self.left))
  self.top = math.max(0, math.min(MAX_Y - h + 1, self.top))
end

-- ------------------------------------------------------------ locations

function Map:hidden(mapId)
  if mapId == SINJOH then return self.hereId ~= SINJOH end
  if mapId == SS_AQUA then return self.hereId ~= SS_AQUA end
  return false
end

-- PokegearMap_GetLocationSpecByCoord + ov101_021EA794
function Map:specAt(x, y)
  for _, s in ipairs(self.gear:art().locations or {}) do
    if x >= s.x and y >= s.y and x < s.x + s.width and y < s.y + s.height then
      if self:hidden(s.mapId) then return nil end
      if self.level == 0 and not (x == 25 and y == 10) and x >= 22 then return nil end
      return s
    end
  end
  return nil
end

function Map:select()
  self.spec = self:specAt(self.cx, self.cy)
end

-- ov101_021EA6C4: something a marking can be put on
function Map:markable()
  local s = self.spec
  return s ~= nil and s.mapId ~= SINJOH and s.mapId ~= SS_AQUA
end

function Map:landmarkName(mapId)
  local h = (require("src.ui.HgssPokegear").headers(self.game.data) or {})[mapId]
  return h and h.label or ""
end

-- Pokegear_RegionFromCoords on (x, y - 2): 0 Johto, 1 Kanto (the region
-- name's index, ov101_021EAD90)
function Map:regionIndex()
  local x, y = self.cx, self.cy - 2
  if x > 21 then
    if x == 25 and y == 8 then return 0 end
    return 1
  end
  return 0
end

-- ------------------------------------------------------------------ input

function Map:toggleZoom()
  self.zoomed = not self.zoomed
  self.gear:save().mapZoom = self.zoomed
  self.gear:se(self.zoomed and "SEQ_SE_GS_GEARXBUTTON" or "SEQ_SE_GS_XBUTTON_SYUKUSHOU")
  self:recenter()
  self:follow()
end

function Map:markings()
  if not self:markable() then return end
  self.gear:se("SEQ_SE_GS_GEARDECIDE")
  self.yPressed = 8
  self.mark = Markings.new(self)
end

function Map:keys(input)
  if self.mark then return self.mark:keys(input) end
  if input:wasPressed("b") then return self.gear:toBar() end
  if input:wasPressed("x") then return self:toggleZoom() end
  if input:wasPressed("y") then return self:markings() end
  if self.step > 0 then return end
  local moved = false
  if input:isDown("up") then
    if self.cy > MIN + 1 then self.cy = self.cy - 1; moved = true end
  elseif input:isDown("down") then
    if self.cy < MAX_Y then self.cy = self.cy + 1; moved = true end
  end
  if input:isDown("left") then
    if self.cx > MIN + 1 then self.cx = self.cx - 1; moved = true end
  elseif input:isDown("right") then
    if self.cx < self.maxX - 1 then self.cx = self.cx + 1; moved = true end
  end
  if moved then
    self.step = 2
    self:follow()
    self:select()
  end
end

-- ov101_021EC980: the touched cell, clamped to the screen's cells
function Map:cellAt(x, y)
  local g = self:grid()
  local cx, cy = floor((x - CENTER) / g), floor((y - CENTER) / g)
  local lim = self.zoomed and { 1, 7, 1, 10 } or { 1, 16, 1, 22 }
  cy = math.max(lim[1], math.min(lim[2], cy))
  cx = math.max(lim[3], math.min(lim[4], cx))
  return cx + self.left, cy + self.top
end

function Map:touch(x, y)
  if self.mark then
    self.mark:touch(x, y)
    self.busy = self.mark ~= nil and self.mark.busy or false
    return true
  end
  if y >= 16 and y < 64 and x >= 216 and x < 248 then self:markings(); return true end
  if y >= 88 and y < 152 and x >= 216 and x < 248 then self:toggleZoom(); return true end
  if x >= 8 and x < 200 and y >= 8 and y < 152 then
    self.gear:se("SEQ_SE_GS_GEARMAPTOUCH")
    local cx, cy = self:cellAt(x, y)
    self.cx = math.max(MIN + 1, math.min(self.maxX - 1, cx))
    self.cy = math.max(MIN + 1, math.min(MAX_Y, cy))
    self:select()
    self.drag = { x = x, y = y, left = self.left, top = self.top }
    self.busy = true
    return true
  end
  return false
end

-- FlyMap_HandleTouchInput_DraggingMap: the map follows the stylus
function Map:touchMove(x, y)
  if self.mark then return self.mark:touchMove(x, y) end
  local d = self.drag
  if not d then return end
  local g = self:grid()
  local w, h = self:viewW(), self:viewH()
  local left = d.left - floor((x - d.x) / g)
  local top = d.top - floor((y - d.y) / g)
  self.left = math.max(0, math.min(self.maxX - w + 1, left))
  self.top = math.max(0, math.min(MAX_Y - h + 1, top))
end

function Map:touchUp()
  if self.mark then self.mark:touchUp() end
  self.drag, self.busy = nil, false
end

function Map:busyUpdate()
  if self.mark then
    self.mark:busyUpdate()
    self.busy = self.mark ~= nil and self.mark.busy or false
    return
  end
  if not self.gear.touchHeld then self.drag, self.busy = nil, false end
end

function Map:reselect() end

function Map:update()
  self.t = self.t + 1
  if self.mark then self.mark:update() end
  if self.step > 0 then self.step = self.step - 1 end
  if self.yPressed then
    self.yPressed = self.yPressed - 1
    if self.yPressed <= 0 then self.yPressed = nil end
  end
end

-- ------------------------------------------------------------------- draw

function Map:drawTouch()
  if self.mark then return self.mark:drawTouch() end
  local g = love.graphics
  local gear = self.gear
  local full = gear:img("map_full")
  local grid = self:grid()
  local s = grid / 8
  g.setColor(1, 1, 1, 1)
  if full then
    local w, h = self:viewW(), self:viewH()
    -- one cell more each way so a partial edge is not left black
    local q = g.newQuad(self.left * 8, self.top * 8, (w + 1) * 8, (h + 1) * 8, full:getDimensions())
    g.draw(full, q, CENTER, CENTER, 0, s, s)
    -- Kanto covered before the map card reaches it (ov101_021EAF40)
    local function cover(dx, w2, sx)
      local qq = g.newQuad(sx * 8, 0, w2 * 8, 20 * 8, full:getDimensions())
      g.draw(full, qq, CENTER + (dx - self.left) * grid, CENTER - self.top * grid, 0, s, s)
    end
    if self.level == 0 then cover(22, 6, 48) elseif self.level == 1 then cover(29, 3, 54) end
  else
    gear:picture("map_world")
  end
  -- the frame over it
  local ui = gear:img("map_ui")
  if ui then
    gear:tiles(ui, 0, 0, 32, 20, 0, 0)
    local yState = (not self:markable()) and 2 or (self.yPressed and 1 or 0)
    gear:tiles(ui, 6 * yState, 21, 6, 7, 26, 2)
    gear:tiles(ui, 6 * (self.zoomed and 1 or 0) + 18, 21, 6, 9, 26, 11)
  else
    gear:picture("map_top")
  end
  self:drawMarked()
  self:drawRoamers()
  -- the player and the cursor
  local half = grid / 2
  local function at(cx, cy) return CENTER + (cx - self.left) * grid + half, CENTER + (cy - self.top) * grid + half end
  local px, py = at(self.px, self.py)
  if px > 0 and px < 208 and py > 0 and py < 160 then
    local girl = ((self.game.save or {}).player or {}).gender == "girl"
    gear:obj("mapB", 1, girl and 1 or 0, px, py)
  end
  if not gear.zone and not gear.fade then
    local x, y = at(self.cx, self.cy)
    if not gear:obj("mapB", 0, floor(self.t / 16) % 2, x, y) then
      g.setColor(1, 0.2, 0.2, 1)
      g.rectangle("line", x - half + 0.5, y - half + 0.5, grid - 1, grid - 1)
      g.setColor(1, 1, 1, 1)
    end
  end
end

-- The active roamers' map headers by roamer index (save.gen4Roamers, routes
-- through Gen4Roamers' HGSS table): { [slot] = header }.
function Map:roamerHeaders()
  local out = {}
  local okR, R = pcall(require, "src.world.Gen4Roamers")
  if not okR then return out end
  if R.useFamily then pcall(R.useFamily) end
  for slot, roamer in pairs((self.game.save or {}).gen4Roamers or {}) do
    local route = type(roamer) == "table" and roamer.active and R.ROUTES and R.ROUTES[tonumber(roamer.route) or -1]
    if route and route.header then out[tonumber(slot) or slot] = route.header end
  end
  return out
end

-- the places carrying markings (set B anim 4 at the place's sprite spot)
function Map:drawMarked()
  local list = (self.gear:save() or {}).markings
  if not list or #list == 0 then return end
  local grid = self:grid()
  local scale = self.zoomed and 2 or 1
  for _, s in ipairs(self.gear:art().locations or {}) do
    if Markings.get(self.gear:save(), s.mapId) and not self:hidden(s.mapId) then
      local x = (s.x - self.left) * grid + CENTER + grid / 2 + (s.objX or 0) * scale
      local y = (s.y - self.top) * grid + CENTER + grid / 2 + (s.objY or 0) * scale
      if x > 0 and x < 208 and y > 0 and y < 160 then self.gear:obj("mapB", 4, 0, x, y) end
    end
  end
end

function Map:drawRoamers()
  local grid = self:grid()
  local scale = self.zoomed and 2 or 1
  local specs = self.gear:art().locations or {}
  for slot, header in pairs(self:roamerHeaders()) do
    for _, s in ipairs(specs) do
      if s.mapId == header then
        local x = (s.x - self.left) * grid + CENTER + grid / 2 + (s.objX or 0) * scale
        local y = (s.y - self.top) * grid + CENTER + grid / 2 + (s.objY or 0) * scale
        if x > 0 and x < 208 and y > 0 and y < 160 then
          self.gear:obj("mapB", 2, tonumber(slot) or 0, x, y)
        end
        break
      end
    end
  end
end

function Map:drawTop()
  local gear = self.gear
  local info = gear:img("map_info")
  local ink = { text = gear:ink("mapSub", 1, { 1, 1, 1 }), shadow = gear:ink("mapSub", 2, { 0.3, 0.3, 0.3 }) }
  if info then gear:tiles(info, 0, 7, 32, 17, 0, 7) end
  Font.pushStyle(ink)
  Font.draw(gear:text(273, self:regionIndex() == 0 and 1 or 0) or "", 8 + 2, 64 + 4)
  local s = self.spec
  if s then
    Font.draw(self:landmarkName(s.mapId), 24, 96)
    local flavour = gear:text(273, s.flavour) or ""
    local y = 112
    for line in (flavour .. "\n"):gmatch("([^\n]*)\n") do Font.draw(line, 8, y); y = y + 16 end
  end
  Font.popStyle()
  if info then gear:tiles(info, (s and s.block ~= 0) and 8 or 0, 0, 8, 7, 23, 11) end
  if s and s.block ~= 0 then
    local pics = gear:img("map_landmarks", true)
    local b = s.block - 1
    if pics then gear:tiles(pics, (b % 4) * 7, floor(b / 4) * 7, 7, 7, 24, 11) end
  end
  Markings.drawTop(self, s)
end

return Map
