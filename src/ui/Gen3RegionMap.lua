-- ---------------------------------------------------------------------------
-- HOENN'S REGION MAP.
--
-- The map on the Pokemon Centre wall printed one line and stopped, and FLY
-- opened a LIST OF WORDS -- Kanto's fly picker, wearing Hoenn's names.  Both
-- are the same missing screen.
--
-- WHERE THE MAP COMES FROM.  sRegionMapEntries is one record per section: a
-- name pointer and then four bytes -- x, y, width, height on the region map's
-- own grid.  The import had been reading those four bytes to PROVE it had
-- found the right table and then throwing them away, so the region had names
-- and no geography.  Keeping them is the whole of the map: 98 sections that
-- a map header points at, laid out on a grid that comes out as 28 by 15
-- without anyone saying so.
--
-- THE PICTURE.  The cartridge's painted background -- the coastline, the
-- mountains, the red ovals on the cities and the tan roads between them -- is
-- an 8bpp tile sheet with a one-byte-per-cell tilemap, and it is now found
-- (RomExtractorGen3:regionMapArt) and drawn behind everything else.  The
-- rectangles stay as what the CURSOR walks; they are no longer what the map
-- looks like.  A dataset whose import could not find the picture falls back
-- to drawing them, which is what this screen used to be.
--
-- WHERE THE GRID SITS ON THE PICTURE.  The section rectangles are in the
-- cartridge's own cursor coordinates, and the cartridge draws cell (0, 0) one
-- tile in and two tiles down from the corner of the background.  Nothing here
-- says so: centring a 28-wide grid on a 240-wide screen puts it at x = 8, and
-- the two-row banner puts it at y = 16, which is that same tile and those
-- same two rows.  The layout the boxes force is the layout the cartridge has.
--
-- FLY MODE (opts.fly + opts.onFly) restricts the cursor to the destinations
-- the player has actually visited, exactly as LoadTownMap_Fly does, and A
-- departs.  Otherwise the cursor walks every place on the map and A does
-- nothing, which is what the wall map is for.
-- ---------------------------------------------------------------------------

local Font = require("src.render.Font")
local Gen3RegionMapArt = require("src.render.Gen3RegionMapArt")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local Gen3RegionMap = {}
Gen3RegionMap.__index = Gen3RegionMap
Gen3RegionMap.isOpaque = true

-- one grid cell, in pixels
local CELL = 8

-- ---------------------------------------------------------------------------
-- THE ZOOM, which is the half of this screen the cartridge has and the port
-- did not.
--
-- UpdateRegionMapZoom (0x08123514) runs for exactly SIXTEEN frames and ramps
-- the affine scale between 0x10000 and 0x8000 in equal steps -- half a texel
-- per pixel, which is two times magnification -- while the background scrolls
-- linearly to its target.  It is not a toggle with an animation bolted on:
-- the fifteen intermediate frames each move both, and the sixteenth assigns
-- the endpoints outright so the ramp cannot drift.
--
-- WHAT STAYS STILL IS THE CURSOR.  Zoomed, the cartridge stops moving it
-- altogether -- it swaps it for the 32x32 sprite, pins it to the middle of
-- the screen and SCROLLS THE MAP UNDER IT, restoring the cell it was on when
-- you zoom back out.  The scroll target for cell x is `x*8 - 52`, and the
-- scroll bounds it enforces while zoomed -- (-44, 171] by (-52, 59] -- are
-- exactly that expression at the four extreme cells, which is the check that
-- says the two halves are the same arithmetic.
--
-- So this drives the zoom off the CURSOR CELL rather than off a scroll
-- register: the cell's own place on the unzoomed map is the pivot, the map is
-- scaled about it, and it slides to the middle of the screen over the
-- sixteen frames.  Moving the cursor while zoomed moves the pivot, which
-- scrolls the map -- the same behaviour, expressed in the units this screen
-- already has.
Gen3RegionMap.ZOOM_FRAMES = 16
Gen3RegionMap.ZOOM_SCALE = 2
-- where the cartridge pins the cursor: SetBgAffine's reference point plus the
-- eight pixels the sprite grows by when it doubles
Gen3RegionMap.ZOOM_FOCUS = { x = 64, y = 80 }
-- WHAT FITS ON A 240x160 SCREEN.  The grid is 28 by 15, so the map is 224 by
-- 120 -- which leaves exactly forty pixels for the two boxes.  Two rows for
-- the banner at the top and three for the name at the bottom is that forty,
-- and getting it wrong by one row is what put the name box over Littleroot.
local BANNER_ROWS = 2
local NAME_ROWS = 3
local TOP = BANNER_ROWS * 8

local function constants(game)
  return (game and game.data and game.data.constants) or {}
end

-- Every place on the map: the sections a map header points at whose record is
-- a real rectangle.  Sorted so the cursor's order is stable.
local function places(game)
  local c = constants(game)
  local rects = c.gen3MapSectionRects
  local names = c.gen3MapSections
  local on = c.gen3RegionMapPlaces
  if not (rects and names and on) then return {} end
  local out = {}
  for sec in pairs(on) do
    local r = rects[sec]
    if r and names[sec] then
      out[#out + 1] = { section = sec, name = names[sec],
                        x = r.x, y = r.y, w = r.w, h = r.h }
    end
  end
  table.sort(out, function(a, b)
    if a.y ~= b.y then return a.y < b.y end
    if a.x ~= b.x then return a.x < b.x end
    return a.section < b.section
  end)
  return out
end

-- WHICH PLACES YOU MAY FLY TO.  The fly order and the fly warps are the
-- heal-location stage's, and a destination is offered only once it has been
-- visited -- which is the same gate every other generation's fly uses.
local function flyTargets(game)
  local field = (game.data or {}).field or {}
  local warps = field.flyWarps or {}
  local visited = (game.save or {}).visited or {}
  local maps = (game.data or {}).maps or {}
  local bySection = {}
  for _, mapId in ipairs(field.flyOrder or {}) do
    local def = maps[mapId]
    local sec = def and tonumber(def.regionMapSection)
    if sec and visited[mapId] and warps[mapId] and not bySection[sec] then
      bySection[sec] = mapId
    end
  end
  return bySection
end

-- ---------------------------------------------------------------------------
-- WHERE A POKEMON LIVES, which is the whole content of the dex's AREA page.
--
-- Reported from play: "im not seeing any pokemons area in the area pokedex
-- menu".  The button opened this map and nothing on it said anything about
-- the Pokemon, because nothing had worked out where it lives.
--
-- FindMapsWithMon walks gWildMonHeaders, looks through each header's four
-- tables -- grass, water, rock smash, fishing -- for the species, and turns
-- the header's map into a REGION MAP SECTION.  The port's encounter tables
-- are that same data keyed by map id, and every map header already carries
-- its `regionMapSection`, so this is the same walk over the same rows.
--
-- ALTERNATE TABLES COUNT.  Altering Cave has nine headers for one map and
-- the import keeps eight of them under `alternates`; a Pokemon that only
-- appears in the eighth still lives there.
local ENCOUNTER_TABLES = { "grass", "water", "rock", "fish" }

function Gen3RegionMap.habitat(game, species)
  local sections = {}
  if not species then return sections end
  local data = (game and game.data) or {}
  local maps = data.maps or {}
  local function holds(entry)
    if type(entry) ~= "table" then return false end
    for _, key in ipairs(ENCOUNTER_TABLES) do
      local rows = entry[key]
      for _, slot in ipairs((type(rows) == "table" and rows.slots) or {}) do
        if slot.species == species then return true end
      end
    end
    return false
  end
  for mapId, entry in pairs(data.encounters or {}) do
    local found = holds(entry)
    if not found and type(entry) == "table" then
      for _, alt in ipairs(entry.alternates or {}) do
        if holds(alt) then found = true break end
      end
    end
    if found then
      local def = maps[mapId]
      local sec = def and tonumber(def.regionMapSection)
      if sec then sections[sec] = true end
    end
  end
  return sections
end

function Gen3RegionMap.new(game, opts)
  opts = opts or {}
  local self = setmetatable({
    game = game,
    fly = opts.fly and true or false,
    onFly = opts.onFly,
    onCancel = opts.onCancel,
    places = places(game),
    blink = 0,
  }, Gen3RegionMap)

  self.targets = self.fly and flyTargets(game) or nil

  -- THE AREA PAGE.  Not a picker: the cartridge's area screen has no cursor
  -- at all -- it lights the places the Pokemon lives and waits for a press.
  self.area = opts.area
  if type(self.area) == "table" and self.area.species then
    self.areaSections = Gen3RegionMap.habitat(game, self.area.species)
    self.areaPlaces = {}
    for _, place in ipairs(self.places) do
      if self.areaSections[place.section] then
        self.areaPlaces[#self.areaPlaces + 1] = place
      end
    end
  else
    self.area = nil
  end

  -- only the places you may pick are pickable
  self.pickable = {}
  for i, place in ipairs(self.places) do
    if not self.fly or self.targets[place.section] then
      self.pickable[#self.pickable + 1] = i
    end
  end

  local grid = constants(game).gen3RegionMapGrid or { width = 28, height = 15 }
  self.grid = grid

  -- ZOOM.  `zoomed` is where it is heading, `zoomFrame` how far along.
  -- opts.zoom = false refuses it outright, which is what the FLY picker
  -- wants: A has to depart, and there is no zoom on the fly map.
  self.canZoom = opts.zoom ~= false and not self.fly and not self.area
  self.zoomed = false
  self.zoomFrame = Gen3RegionMap.ZOOM_FRAMES

  -- start on where the player is standing, when that is a place at all
  local ow = game.overworld
  local here = ow and ow.map and ow.map.def
             and tonumber(ow.map.def.regionMapSection)
  self.here = here
  self.cx, self.cy = 0, 0
  for _, place in ipairs(self.places) do
    if place.section == here then
      self.cx = place.x + math.floor((place.w - 1) / 2)
      self.cy = place.y + math.floor((place.h - 1) / 2)
      break
    end
  end
  return self
end

-- WHAT THE CURSOR IS STANDING ON.
--
-- Reported from play: "you should be able to move the cursor up down left or
-- right ... if the map hover over routes citys etc to see what theyre named".
-- This screen used to walk the PLACES -- press right and it jumped to the
-- nearest town in that direction -- so most of Hoenn could not be pointed at
-- at all, and the sea between two towns was never under the cursor.  The
-- cartridge's cursor walks the GRID, one cell at a time, and whatever section
-- owns that cell is what the box at the bottom names.
-- AND THE RECTANGLES ARE NOT WHAT THE CARTRIDGE ASKS.
--
-- GetMapSecIdAt (0812386C) does not hit-test rectangles; it indexes a flat
-- 28x15 table, one byte per cell.  The rectangles are each section's ANCHOR
-- -- where its name and its player icon go -- and for four cells the two
-- disagree: MT. CHIMNEY owns four cells in the table and its rectangle
-- claims one, so the cursor over Chimney named nothing, and over SOOTOPOLIS
-- it named the sea.
--
-- The rectangle scan stays as the fallback for a cache imported before the
-- table was read: it is right for 413 of the 420 cells, which is why the
-- error was hard to see.
function Gen3RegionMap:sectionAt(cx, cy)
  local layout = (self.game.data.constants or {}).gen3RegionMapLayout
  if layout and layout.cells then
    if cx >= 0 and cy >= 0 and cx < layout.width and cy < layout.height then
      local id = layout.cells[cy * layout.width + cx + 1]
      if id and id ~= layout.none then
        for _, place in ipairs(self.places) do
          if place.section == id then return place end
        end
      end
    end
    return nil
  end
  for _, place in ipairs(self.places) do
    if cx >= place.x and cx < place.x + place.w
       and cy >= place.y and cy < place.y + place.h then
      return place
    end
  end
  return nil
end

function Gen3RegionMap:current()
  return self:sectionAt(self.cx, self.cy)
end

function Gen3RegionMap:close()
  if self.game.stack then self.game.stack:pop() end
  if self.onCancel then self.onCancel() end
end

-- ---------------------------------------------------------------------------
-- MOVING THE CURSOR.
--
-- The cartridge's cursor walks the map itself, cell by cell, and lands on
-- whatever section the cell belongs to.  This walks the PLACES instead --
-- nearest in the direction pressed -- which lands on the same sequence for
-- every straight run and never strands the cursor on empty sea.
-- ---------------------------------------------------------------------------
local DELTA = { up = { 0, -1 }, down = { 0, 1 },
                left = { -1, 0 }, right = { 1, 0 } }
-- polled in a fixed order, so a diagonal on the pad resolves the same way
-- every time rather than by table order
local DIRECTIONS = { "up", "down", "left", "right" }

function Gen3RegionMap:step(dir)
  local d = DELTA[dir]
  if not d then return false end
  local grid = self.grid or { width = 28, height = 15 }
  local nx = self.cx + d[1]
  local ny = self.cy + d[2]
  -- the cartridge's cursor stops at the edge rather than wrapping
  if nx < 0 or ny < 0 or nx >= grid.width or ny >= grid.height then
    return false
  end
  self.cx, self.cy = nx, ny
  return true
end

-- INPUT IS POLLED, NOT DELIVERED.
--
-- This screen read its keys from a `keypressed` callback while every other
-- screen in the port -- the start menu, the bag, the party, the summary --
-- asks `game.input:wasPressed` on its own update.  Nothing calls keypressed
-- with these logical names, so the region map answered nothing at all: the
-- cursor would not move, no town could be chosen, and B did not back out of
-- it, which left the player looking at a map they could not leave.
--
-- The handling is unchanged; only where it is asked from.
-- How far through the zoom, 0 at full map and 1 at two times.
-- `zoomFrame` is absent on a screen built without `new` -- several of this
-- port's tests drive these methods against a bare table -- and absent means
-- "the ramp has finished", which is the resting state either way.
function Gen3RegionMap:zoomT()
  local frames = Gen3RegionMap.ZOOM_FRAMES
  local t = math.min(1, math.max(0, (self.zoomFrame or frames) / frames))
  return self.zoomed and t or (1 - t)
end

function Gen3RegionMap:zooming()
  return (self.zoomFrame or Gen3RegionMap.ZOOM_FRAMES)
           < Gen3RegionMap.ZOOM_FRAMES
end

-- WHICH BUTTON.  The cartridge's help bar says "{L/R} ZOOM {B} CANCEL", and
-- L and R do it here for that reason.  A does it too, on the two maps where A
-- has nothing else to do -- the wall map and the POKéNAV's -- because that is
-- the button a player reaches for, and on the FLY map A still departs.
function Gen3RegionMap:toggleZoom()
  if not self.canZoom then return false end
  if self:zooming() then return false end
  self.zoomed = not self.zoomed
  self.zoomFrame = 0
  Sound.play(self.game.data, "Press_AB")
  return true
end

function Gen3RegionMap:update()
  self.blink = (self.blink + 1) % 60
  self.areaClock = ((self.areaClock or 0) + 1)
                   % (Gen3RegionMap.AREA_CYCLE * math.max(1, #(self.areaPlaces or {})))
  if self:zooming() then
    self.zoomFrame = self.zoomFrame + 1
    -- the sixteenth frame is the one that assigns the endpoints, and nothing
    -- else happens on it
    return
  end
  local game = self.game
  local input = game.input
  if not input then return end

  if input:wasPressed("b") then
    -- zoomed, B backs out to the full map before it leaves the screen, which
    -- is what the help bar's two halves mean read together
    if self.zoomed then return self:toggleZoom() end
    Sound.play(game.data, "Press_AB")
    return self:close()
  end
  -- the AREA page takes one press and leaves; there is nothing on it to move
  -- a cursor over
  if self.area then
    if input:wasPressed("a") then
      Sound.play(game.data, "Press_AB")
      return self:close()
    end
    return
  end
  if input:wasPressed("l") or input:wasPressed("r") then
    return self:toggleZoom()
  end
  if input:wasPressed("a") then
    if self.canZoom and not self.fly then return self:toggleZoom() end
    return self:pick()
  end
  for _, dir in ipairs(DIRECTIONS) do
    if input:wasPressed(dir) then
      if self:step(dir) then Sound.play(game.data, "Press_AB") end
      return
    end
  end
end

function Gen3RegionMap:pick()
  local game = self.game
  local place = self:current()
  local mapId = place and self.targets and self.targets[place.section]
  if self.fly and mapId then
    Sound.play(game.data, "Press_AB")
    if game.stack then game.stack:pop() end
    if self.onFly then self.onFly(mapId) end
  else
    -- not a FLY destination, or not flying: the cartridge refuses out loud
    Sound.play(game.data, "Wrong")
  end
end

-- ...and the callback stays, forwarding to the same places, so a host that
-- does deliver key events still works.
function Gen3RegionMap:keypressed(key)
  if key == "b" then
    Sound.play(self.game.data, "Press_AB")
    return self:close()
  end
  if key == "a" then return self:pick() end
  if DELTA[key] then
    if self:step(key) then Sound.play(self.game.data, "Press_AB") end
  end
end

function Gen3RegionMap:uiSize() return Theme.uiSize() end

-- The head the cartridge puts on the map: the boy's unless the save says the
-- player is the girl, and nothing at all for a dataset without the sprites.
function Gen3RegionMap:playerIcon()
  local player = (self.game.save or {}).player
  local which = (player and player.gender == "girl") and 2 or 1
  return Gen3RegionMapArt.playerIcon(self.game.data, which)
end

-- WHAT THE AREA PAGE SAYS.
--
-- The banner carries the Pokemon's name, which is what the cartridge's own
-- area screen puts on it, and the box at the bottom names the places it
-- lives -- one at a time, a second and a half each, because Hoenn has
-- Pokemon that live in eleven sections and the box is one line.  A Pokemon
-- that lives nowhere wild says so rather than leaving the box empty: a
-- LEGENDARY has no encounter row at all, and an empty box is
-- indistinguishable from a page that failed to load.
Gen3RegionMap.AREA_CYCLE = 90

function Gen3RegionMap:areaTitle()
  local species = self.area and self.area.species
  local def = species and (self.game.data.pokemon or {})[species]
  return (def and def.name) or tostring(species or "")
end

function Gen3RegionMap:areaName()
  local places = self.areaPlaces or {}
  if #places == 0 then return Strings("AREA UNKNOWN") end
  local step = math.floor((self.areaClock or 0) / Gen3RegionMap.AREA_CYCLE)
  return places[step % #places + 1].name
end

-- ---------------------------------------------------------------------------
-- DRAWING IT
-- ---------------------------------------------------------------------------
function Gen3RegionMap:draw()
  local w, h = self:uiSize()
  local grid = constants(self.game).gen3RegionMapGrid
              or { width = 28, height = 15 }
  local ox = math.floor((w - grid.width * CELL) / 2)
  local oy = TOP

  local cur = self:current()

  -- THE ZOOM'S TRANSFORM, applied to everything that lives on the map.
  --
  -- The pivot is the cursor cell's own centre on the unzoomed map; the
  -- destination slides from there to the middle of the screen over the
  -- sixteen frames, and the scale ramps 1 -> 2 with it.  At rest with the
  -- zoom off both are identities and this costs nothing.
  local t = self:zoomT()
  local scale = 1 + (Gen3RegionMap.ZOOM_SCALE - 1) * t
  local pivotX = ox + self.cx * CELL + CELL / 2
  local pivotY = oy + self.cy * CELL + CELL / 2
  local focus = Gen3RegionMap.ZOOM_FOCUS
  local dstX = pivotX + (focus.x - pivotX) * t
  local dstY = pivotY + (focus.y - pivotY) * t
  -- an unzoomed point's place on the screen
  local function at(x, y)
    return dstX + (x - pivotX) * scale, dstY + (y - pivotY) * scale
  end
  local zoomed = t > 0
  if zoomed then
    -- the map is the only thing that scales; the two text boxes do not, so
    -- the scissor keeps the enlarged map out of them
    love.graphics.setScissor(0, 0, w, h)
  end

  local painted = Gen3RegionMapArt.background(self.game.data, math.ceil(h / CELL))
  if painted then
    love.graphics.setColor(1, 1, 1, 1)
    if zoomed then
      love.graphics.draw(painted, dstX, dstY, 0, scale, scale, pivotX, pivotY)
    else
      love.graphics.draw(painted, 0, 0)
    end
  else
    -- NO PICTURE: the map this screen used to be.  Sea everywhere, and one
    -- rectangle of land per place.
    love.graphics.setColor(0.30, 0.55, 0.78, 1)
    love.graphics.rectangle("fill", 0, 0, w, h)
    for _, place in ipairs(self.places) do
      local pickable = not self.fly
                       or (self.targets and self.targets[place.section])
      if pickable then
        love.graphics.setColor(0.55, 0.76, 0.44, 1)
      else
        love.graphics.setColor(0.62, 0.66, 0.55, 1)
      end
      local rx, ry = at(ox + place.x * CELL, oy + place.y * CELL)
      love.graphics.rectangle("fill", rx, ry,
                              place.w * CELL * scale, place.h * CELL * scale)
    end
  end

  -- ---- THE HABITAT GLOW ---------------------------------------------------
  --
  -- RECONSTRUCTED, because the cartridge's is a palette animation on a
  -- tilemap of glow tiles and this port draws the map as one picture: a
  -- rectangle over each section the Pokemon lives in, pulsing on the same
  -- clock the cursor blinks on.  WHICH rectangles is not reconstructed --
  -- that is the encounter walk, and it is the answer the page exists to give.
  if self.area then
    local pulse = 0.35 + 0.3 * math.abs(30 - self.blink) / 30
    for _, place in ipairs(self.areaPlaces or {}) do
      local rx, ry = at(ox + place.x * CELL, oy + place.y * CELL)
      love.graphics.setColor(1, 0.35, 0.2, pulse)
      love.graphics.rectangle("fill", rx, ry,
                              place.w * CELL * scale, place.h * CELL * scale)
      love.graphics.setColor(1, 0.85, 0.4, math.min(1, pulse + 0.3))
      love.graphics.rectangle("line", rx + 0.5, ry + 0.5,
                              place.w * CELL * scale - 1,
                              place.h * CELL * scale - 1)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- WHERE YOU ARE STANDING.  The cartridge marks it with the player's head,
  -- so this does too; without the sprite it falls back to the old block of
  -- yellow, which is at least visible.
  local icon = self.area and nil or self:playerIcon()
  for _, place in ipairs(self.area and {} or self.places) do
    if place.section == self.here then
      local pw, ph = place.w * CELL, place.h * CELL
      local x, y = at(ox + place.x * CELL + pw / 2, oy + place.y * CELL + ph / 2)
      if icon then
        love.graphics.setColor(1, 1, 1, 1)
        local iw, ih = icon:getDimensions()
        love.graphics.draw(icon, x, y, 0, scale, scale, iw / 2, ih / 2)
      else
        love.graphics.setColor(1, 0.85, 0.25, 1)
        love.graphics.rectangle("fill", x - (pw / 2 - 2) * scale,
                                y - (ph / 2 - 2) * scale,
                                (pw - 4) * scale, (ph - 4) * scale)
      end
    end
  end

  -- THE CURSOR.  Four corner brackets around whatever section it is on --
  -- which is the cartridge's own sprite, quartered, because its art is four
  -- corners with nothing between them and that is what lets one 16x16 sprite
  -- fit a section of any size.
  if not self.area then
    -- ON THE CELL, CENTRED.  The cursor is one sixteen-by-sixteen sprite and
    -- the cell under it is eight by eight, so it sits four pixels out on
    -- every side and the cell is in the middle of it.
    --
    -- Reported from play: "the cursor hovering over the locations is not
    -- correct it should be centered on the city location not offset".  It
    -- was quartered and stretched to the corners of a section RECTANGLE --
    -- which put its top-left bracket a whole tile up and left of a one-cell
    -- town, and which the cartridge never does: its cursor is one sprite that
    -- moves, not a frame that resizes.
    -- ZOOMED, THE CURSOR DOES NOT MOVE.  `at` of the pivot IS the
    -- destination, so this lands on the middle of the screen the whole time
    -- the map is sliding under it -- which is the cartridge's own behaviour
    -- read the other way round.
    local cxp, cyp = at(ox + self.cx * CELL + CELL / 2,
                        oy + self.cy * CELL + CELL / 2)
    local x = cxp - CELL / 2
    local y = cyp - CELL / 2
    local frames = Gen3RegionMapArt.cursorFrames(self.game.data)
    local corners = frames > 0
                    and Gen3RegionMapArt.cursor(self.game.data,
                          math.floor(self.blink / 30) % frames + 1)
                    or nil
    if corners then
      love.graphics.setColor(1, 1, 1, 1)
      local iw, ih = corners:getDimensions()
      -- the cartridge swaps the 16x16 sprite for a 32x32 one when it zooms,
      -- which is the same picture at twice the size
      love.graphics.draw(corners, cxp, cyp, 0, scale, scale, iw / 2, ih / 2)
    elseif self.blink < 40 then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", x - 2, y - 2, CELL + 4, 1)
      love.graphics.rectangle("fill", x - 2, y + CELL + 1, CELL + 4, 1)
      love.graphics.rectangle("fill", x - 2, y - 2, 1, CELL + 4)
      love.graphics.rectangle("fill", x + CELL + 1, y - 2, 1, CELL + 4)
    end
  end

  if zoomed then love.graphics.setScissor() end

  -- the banner, and the name of whatever the cursor is on
  local cols, rows = math.floor(w / 8), math.floor(h / 8)
  love.graphics.setColor(1, 1, 1, 1)
  -- THE SMALL FACE, because these are two-tile boxes.
  --
  -- Reported from play: "the top box there the fly to where text is escaping
  -- the box".  It was: the banner is two tiles -- sixteen pixels -- and the
  -- dialogue face is FIFTEEN tall drawn from four pixels down, so it ran
  -- three pixels out of the bottom of its own box.  Emerald prints both of
  -- these in FONT_NARROW for exactly that reason, and the cache has that
  -- face; the row is then centred in the box rather than nudged, so a
  -- dataset whose face is a different height stays inside it too.
  local faced = Font.pushFace("small")
  local lineH = Font.glyphHeight()
  Font.drawBox(0, 0, cols, BANNER_ROWS)
  local title = self.fly and Strings("FLY TO WHERE?") or Strings("HOENN")
  if self.area then title = self:areaTitle() end
  if self.zoomed then title = title .. "  x2" end
  Font.draw(title, 6, math.floor((BANNER_ROWS * 8 - lineH) / 2))

  local name = cur and cur.name or ""
  if self.area then name = self:areaName() end
  Font.drawBox(0, rows - NAME_ROWS, cols, NAME_ROWS)
  Font.draw(name, 6, (rows - NAME_ROWS) * 8
                     + math.floor((NAME_ROWS * 8 - lineH) / 2))
  -- flying: say which of the places under the cursor you may actually go to,
  -- so a town you have not been to yet reads as a place and not as a target
  if self.fly and cur and self.targets and self.targets[cur.section] then
    local mark = Strings("FLY")
    Font.draw(mark, cols * 8 - 6 - Font.width(mark),
              (rows - NAME_ROWS) * 8
                + math.floor((NAME_ROWS * 8 - lineH) / 2))
  end
  if faced then Font.popFace() end
  love.graphics.setColor(1, 1, 1, 1)
end

return Gen3RegionMap
