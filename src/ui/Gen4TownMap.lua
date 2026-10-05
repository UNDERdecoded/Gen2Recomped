-- PLATINUM'S TOWN MAP -- the top screen of pokeplatinum
-- src/applications/town_map, for the Town Map key item and for Fly.
--
-- What it draws, in the cartridge's order:
--   * the region (`top_screen_region_bg`) with the routes over it
--     (`top_screen_region_map`), both composed by the graphics stage;
--   * the twenty town blocks (`sFlyLocations`), each in its shape and in
--     sub-palette 5 + palette + unlocked; Pal Park's and Victory Road's are
--     hidden until unlocked; in FLY mode the one under the cursor blinks
--     between that and 8 + palette every 16 ticks;
--   * the player's icon where the player is (or, indoors, where the player
--     last stood outside), and the cursor;
--   * the location's name on the bar at the bottom -- only on a cell with a
--     `tmap_block.dat` block -- centred, or in FLY mode after "Fly to where?".
--
-- The grid: cell (x, z) of the main map matrix is at 7x + 25, 7z - 34
-- (TOWN_MAP_GRID_X/Y). The cursor keeps to x 1..28, z 6..28 and steps once
-- every three ticks while a direction is held (HandleInput / DoZoomedMapMvt).
--
-- NOT DRAWN: the bottom screen's zoomed map and signposts.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")

local Gen4TownMap = {}
Gen4TownMap.__index = Gen4TownMap
Gen4TownMap.isOpaque = true

local W, H = 256, 192
local STEP_FRAMES = 6            -- three 30 Hz ticks
local BLINK_FRAMES = 32          -- sixteen ticks
local EVERYWHERE = 0             -- MAP_HEADER_EVERYWHERE

function Gen4TownMap:uiSize() return W, H end
function Gen4TownMap:wantsFillScale() return true end
function Gen4TownMap:wantsEdgeBleed() return false end

local function record(game) return game and game.data and game.data.gen4_town_map end

-- The main map matrix: header at (x, z), and the cells a header covers.
local function matrix(game)
  local m = game.data.gen4_map_matrices
  return m and m[0]
end

function Gen4TownMap.headerAt(game, x, z)
  local m = matrix(game)
  if not m then return nil end
  if x < 0 or z < 0 or x >= m.width or z >= m.height then return nil end
  return m.headers[z * m.width + x + 1]
end

local function originOf(game, header)
  local m = matrix(game)
  if not m then return nil end
  local bx, bz
  for i, h in ipairs(m.headers) do
    if h == header then
      local x, z = (i - 1) % m.width, math.floor((i - 1) / m.width)
      if not bx or z < bz or (z == bz and x < bx) then bx, bz = x, z end
    end
  end
  return bx, bz
end

-- Where the player is on the map: the matrix cell under them on an outdoor
-- map, else the last outdoor cell recorded (TownMapContext_Init's exitLocation
-- arm -- see Gen4TownMap.remember).
function Gen4TownMap.playerCell(game)
  local ow = game.overworld
  local def = ow and ow.map and ow.map.def
  local p = ow and ow.player
  if def and def.layout == 0 and p and p.cellX then
    local ox, oz = originOf(game, def.header)
    if ox then
      return ox + math.floor(p.cellX / 32), oz + math.floor(p.cellY / 32)
    end
  end
  local last = game.save and game.save.gen4TownMapCell
  if last then return last.x, last.z end
  return 3, 27
end

-- Called on every outdoor step-in so an indoor opening has somewhere to point.
function Gen4TownMap.remember(game)
  local ow = game and game.overworld
  local def = ow and ow.map and ow.map.def
  if not (def and def.layout == 0 and game.save) then return end
  local x, z = Gen4TownMap.playerCell(game)
  game.save.gen4TownMapCell = { x = x, z = z }
end

function Gen4TownMap.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Gen4TownMap)
  self.game = game
  self.mode = opts.mode or "map"           -- "map" or "fly"
  self.onFly = opts.onFly
  self.onCancel = opts.onCancel
  self.rec = record(game)
  self.cache = {}
  self.px, self.pz = Gen4TownMap.playerCell(game)
  self.cx, self.cz = self.px, self.pz
  self.frame, self.moveWait = 0, 0
  return self
end

-- ------------------------------------------------------------- the rules --

local function flagOpen(save, firstArrival)
  local flags = save and save.flags
  return type(flags) == "table"
    and flags[("FLAG_G4_%04X"):format(0x9B1 + firstArrival)] == true
end

function Gen4TownMap:locations()
  local out = {}
  local rec = self.rec
  if not rec then return out end
  for i, loc in ipairs(rec.flyLocations or {}) do
    local fa = rec.firstArrival[i] or 0
    out[i] = { loc = loc, firstArrival = fa, unlocked = flagOpen(self.game.save, fa) }
  end
  return out
end

-- TownMap_GetFlyLocationAtPos
function Gen4TownMap:flyLocationAt(header, x, z)
  for _, row in ipairs(self:locations()) do
    local loc = row.loc
    if loc.header == header then
      if not loc.special then return row end
      if loc.cell and loc.cell[1] == x and loc.cell[2] == z then return row end
    end
  end
  return nil
end

-- TownMap_GetMapBlockAtPosition
function Gen4TownMap:blockAt(x, z)
  for _, b in ipairs((self.rec and self.rec.blocks) or {}) do
    if b.x == x and b.z == z then
      if (b.hidden or 0) == 0 then return b end
      local H = require("src.world.Gen4HiddenPaths")
      for loc = 0, 3 do
        if math.floor(b.hidden / 2 ^ loc) % 2 == 1 and H.unlocked(self.game.save, loc) then
          return b
        end
      end
      return nil
    end
  end
  return nil
end

-- LoadMapName: the header's name, or for MAP_HEADER_EVERYWHERE the few cells
-- the cartridge names anyway (Mt. Coronet's inside, the Fight Area gate).
function Gen4TownMap:labelFor(header)
  if not self.labels then
    self.labels = {}
    for _, def in pairs(self.game.data.maps or {}) do
      if def.header and def.label and self.labels[def.header] == nil then
        self.labels[def.header] = def.label
      end
    end
  end
  return self.labels[header]
end

function Gen4TownMap:nameAt(x, z)
  local header = Gen4TownMap.headerAt(self.game, x, z)
  if header == EVERYWHERE then
    for _, row in ipairs((self.rec and self.rec.offMatrix) or {}) do
      if row[1] == x and row[2] == z then return self:labelFor(row[3]) end
    end
  end
  return header and self:labelFor(header) or nil
end

-- ------------------------------------------------------------- pictures --

function Gen4TownMap:img(key)
  if self.cache[key] == nil then
    local path = "assets/generated/gen4/town_map/" .. key .. ".png"
    local ok, image = pcall(Assets.image, path)
    self.cache[key] = ok and image or false
    if self.cache[key] then self.cache[key]:setFilter("nearest", "nearest") end
  end
  return self.cache[key] or nil
end

function Gen4TownMap:sprite(key, cell, slot)
  local rec = self.rec
  local im = rec and rec.images[key] and rec.images[key][(cell or 0) + 1]
  if not im then return nil end
  slot = slot or im.bank or 0
  local id = key .. "|" .. (cell or 0) .. "|" .. slot
  if self.cache[id] ~= nil then return self.cache[id] or nil, im end
  local pal = rec.spritePalette or {}
  local data = love.image.newImageData(im.w, im.h)
  for y = 0, im.h - 1 do
    for x = 0, im.w - 1 do
      local at = (y * im.w + x) * 2 + 1
      local v = tonumber(im.idx:sub(at, at + 1), 16) or 0
      if v ~= 0 then
        local c = pal[slot * 16 + v + 1] or { 255, 0, 255 }
        data:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, 1)
      end
    end
  end
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  self.cache[id] = img
  return img, im
end

local function gridX(x) return 7 * x + 25 end
local function gridY(z) return 7 * z - 34 end

-- ----------------------------------------------------------------- input --

function Gen4TownMap:close()
  self.game.stack:pop()
  if self.onCancel then self.onCancel() end
end

function Gen4TownMap:update()
  self.frame = self.frame + 1
  local input = self.game.input
  if not input then return end
  if input:wasPressed("b") then return self:close() end
  if self.mode == "fly" and input:wasPressed("a") then
    local header = Gen4TownMap.headerAt(self.game, self.cx, self.cz)
    local row = self:blockAt(self.cx, self.cz) and self:flyLocationAt(header, self.cx, self.cz)
    if row and row.unlocked then
      self.game.stack:pop()
      if self.onFly then self.onFly(row.firstArrival, row.loc.header) end
    end
    return
  end
  if self.moveWait > 0 then self.moveWait = self.moveWait - 1 return end
  local down = function(k) return input.isDown and input:isDown(k) end
  local moved = false
  if down("up") and self.cz >= 7 then self.cz = self.cz - 1 moved = true end
  if down("down") and self.cz <= 27 then self.cz = self.cz + 1 moved = true end
  if down("right") and self.cx <= 27 then self.cx = self.cx + 1 moved = true end
  if down("left") and self.cx >= 2 then self.cx = self.cx - 1 moved = true end
  if moved then self.moveWait = STEP_FRAMES - 1 end
end

-- ------------------------------------------------------------------ draw --

function Gen4TownMap:draw()
  local g = love.graphics
  g.clear(0, 0, 0, 1)
  g.setColor(1, 1, 1, 1)
  local bg, routes = self:img("top_screen_region_bg"), self:img("top_screen_region_map")
  if bg then g.draw(bg, 0, 0) end
  if routes then g.draw(routes, 0, 0) end

  -- the town blocks
  local header = Gen4TownMap.headerAt(self.game, self.cx, self.cz)
  local hovered = self:blockAt(self.cx, self.cz) and self:flyLocationAt(header, self.cx, self.cz)
  local blinkOn = math.floor(self.frame / BLINK_FRAMES) % 2 == 0
  for _, row in ipairs(self:locations()) do
    local loc = row.loc
    local hidden = not row.unlocked and (loc.special == "palPark" or loc.special == "victoryRoad")
    if not hidden then
      local slot = 5 + loc.palette + (row.unlocked and 1 or 0)
      if self.mode == "fly" and hovered == row and row.unlocked and blinkOn then
        slot = 8 + loc.palette
      end
      local img, im = self:sprite("flyBlocks", loc.shape, slot)
      if img then g.draw(img, loc.x + 25 + im.x, loc.y - 34 + im.y) end
    end
  end

  -- the player, then the cursor
  local girl = ((self.game.save or {}).player or {}).gender
  girl = girl == "girl" or girl == "female"
  local pimg, pim = self:sprite("player", girl and 1 or 0)
  if pimg then g.draw(pimg, gridX(self.px) + pim.x, gridY(self.pz) + pim.y) end
  local cimg, cim = self:sprite("cursor", math.floor(self.frame / 16) % 2)
  if cimg then g.draw(cimg, gridX(self.cx) + cim.x, gridY(self.cz) + cim.y) end

  -- the bar: window at tile (3, 21), text at y + 6 (PrintLocationName)
  local faced = Font.pushFace and Font.pushFace("system")
  g.setColor(1, 1, 1, 1)
  local name = self:blockAt(self.cx, self.cz) and self:nameAt(self.cx, self.cz)
  local wx, wy = 24, 21 * 8 + 6 - 4
  if self.mode == "fly" then
    local text = (self.game.data.text or {}).TEXT_B0615_00000 or "Fly to where?"
    Font.draw(text, wx, wy)
    if name then Font.draw(name, wx + 15 * 8 + 2, wy) end
  elseif name then
    local tw = Font.width and Font.width(name) or #name * 6
    Font.draw(name, wx + math.floor((W - 6 * 8 - tw) / 2), wy)
  end
  if faced and Font.popFace then Font.popFace() end
end

return Gen4TownMap
