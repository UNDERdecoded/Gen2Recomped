-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen3 metatile compositing.
--
-- A Gen 1 or Gen 2 block is 4x4 tiles out of one tileset with one palette map
-- and no flipping, so the renderer can bake a single atlas once and blit 8x8
-- quads out of it.  A Gen 3 metatile is none of those things:
--
--   * it is 16x16 -- 2x2 tiles, not 4x4 -- so a metatile is the engine's CELL,
--     not its block;
--   * it has TWO LAYERS of those 2x2 tiles, and the player walks between them,
--     which is what puts a sprite behind a treetop;
--   * every one of the eight tile entries carries its own PALETTE and its own
--     horizontal and vertical flip;
--   * and it draws out of TWO tilesets at once -- the map's primary and its
--     secondary -- with a separate bank boundary for tiles, for metatiles and
--     for palettes.
--
-- Those three boundaries are the trap.  They are plain constants with nothing
-- in the cartridge header to announce them, and the palette one fails
-- silently: palette slot 6 read out of the primary bank is sixteen zero words,
-- so a wrong boundary renders every wall in Littleroot solid black while the
-- roofs directly above them stay perfect.  tools/gen3_discover.py derives all
-- three from the cartridge -- a primary tileset is by definition the one whose
-- metatiles never reach into the other bank, and 14 secondaries independently
-- begin their palettes at exactly slot 6 -- and this module reads them from
-- the manifest rather than restating them.
--
-- Index 0 is transparent on BOTH layers.  What shows through is the backdrop,
-- which is palette 0 colour 0.

local Gen3Tiles = {}
Gen3Tiles.__index = Gen3Tiles

-- Defaults matching Emerald, overridden from the manifest's layout block.
local DEFAULTS = {
  tilesInPrimary = 512,
  metatilesInPrimary = 512,
  palettesInPrimary = 6,
  metatileLayers = 2,
}

local byte = string.byte

-- pair = { primary = <tileset record>, secondary = <tileset record or nil> }
-- layout = the manifest's layout table (optional; defaults above are Emerald's)
function Gen3Tiles.new(pair, layout)
  layout = layout or {}
  local self = setmetatable({
    primary = pair.primary,
    secondary = pair.secondary,
    tilesInPrimary = tonumber(layout.tilesInPrimary) or DEFAULTS.tilesInPrimary,
    metatilesInPrimary = tonumber(layout.metatilesInPrimary)
      or DEFAULTS.metatilesInPrimary,
    palettesInPrimary = tonumber(layout.palettesInPrimary)
      or DEFAULTS.palettesInPrimary,
    layers = tonumber(layout.metatileLayers) or DEFAULTS.metatileLayers,
    tileCache = {},
  }, Gen3Tiles)
  return self
end

-- Which record owns a given tile / metatile / palette index, and its index
-- within that record.  One place, because getting any of the three wrong is
-- the failure this module exists to prevent.
function Gen3Tiles:tileBank(index)
  if index < self.tilesInPrimary then return self.primary, index end
  return self.secondary or self.primary, index - self.tilesInPrimary
end

function Gen3Tiles:metatileBank(index)
  if index < self.metatilesInPrimary then return self.primary, index end
  return self.secondary or self.primary, index - self.metatilesInPrimary
end

function Gen3Tiles:paletteBank(index)
  if index < self.palettesInPrimary then return self.primary, index end
  return self.secondary or self.primary, index
end

-- A tile's 64 palette indices.  4bpp, and the LOW nibble is the LEFT pixel --
-- reading the high nibble first mirrors every tile in the game.
function Gen3Tiles:tilePixels(index)
  local hit = self.tileCache[index]
  if hit then return hit end
  local out = {}
  -- AN ANIMATED TILE IS WHATEVER FRAME IS SHOWING.  The cartridge copies the
  -- frame over the tileset's own graphics in VRAM, so the tileset record is
  -- left alone here and the frame is laid over it -- the dataset is shared by
  -- every pair that uses this tileset and must not be written through.
  local override = self.tileOverride and self.tileOverride[index]
  local data, base
  if override then
    data, base = override, 0
  else
    local record, local_ = self:tileBank(index)
    data = record and record.tiles
    base = local_ * 32
  end
  if data and base + 32 <= #data then
    local n = 0
    for row = 0, 7 do
      for half = 0, 3 do
        local b = byte(data, base + row * 4 + half + 1)
        out[n + 1] = b % 16
        out[n + 2] = math.floor(b / 16)
        n = n + 2
      end
    end
  else
    for i = 1, 64 do out[i] = 0 end
  end
  self.tileCache[index] = out
  return out
end

function Gen3Tiles:palette(index)
  if self.paletteState then
    local name = index < self.palettesInPrimary and "primary" or "secondary"
    return self.paletteState[name][index + 1]
  end
  local record = self:paletteBank(index)
  local pals = record and record.palettes
  return pals and pals[index + 1] or nil
end

-- Independent palette cadence; does not alter the tile animation picture.
-- Missing legacy metadata retains the original base-palette rendering.
function Gen3Tiles:setPaletteTicks(ticks)
  local cycles = require("src.render.Gen3PaletteCycles")
  if cycles.staticUnchanged(self, self, ticks, self.paletteState) then
    self.paletteState.ticks = ticks
    return false
  end
  local state, reason
  if self.paletteSampler then
    state, reason = self.paletteSampler:sample(self, self, ticks)
  else
    state, reason = cycles.sample(self, self, ticks)
    if state and (#state.primaryFrames > 0 or #state.secondaryFrames > 0) then
      self.paletteSampler = require("src.render.Gen3PaletteSamples").new(self, self, state)
    end
  end
  local changed = (state and state.contentKey) ~= (self.paletteState and self.paletteState.contentKey)
  self.paletteState = state
  return changed, reason
end

-- The colour the backdrop shows where nothing is drawn: palette 0, colour 0.
function Gen3Tiles:backdrop()
  local p = self:palette(0)
  return p and p[1] or { 0, 0, 0 }
end

-- One metatile's eight tile entries, as { tile, flipX, flipY, palette }.
function Gen3Tiles:entries(metatile)
  local record, local_ = self:metatileBank(metatile)
  local data = record and record.metatiles
  local out = {}
  local base = local_ * 16
  if not (data and base + 16 <= #data) then return out end
  for k = 0, 7 do
    local lo = byte(data, base + k * 2 + 1)
    local hi = byte(data, base + k * 2 + 2)
    local word = lo + hi * 256
    out[k + 1] = {
      tile = word % 1024,
      flipX = math.floor(word / 1024) % 2 == 1,
      flipY = math.floor(word / 2048) % 2 == 1,
      palette = math.floor(word / 4096) % 16,
    }
  end
  return out
end

-- The metatile's behaviour byte and layer type, out of the attributes word.
function Gen3Tiles:attributes(metatile)
  local record, local_ = self:metatileBank(metatile)
  local data = record and record.attributes
  local base = local_ * 2
  if not (data and base + 2 <= #data) then return 0, 0 end
  local word = byte(data, base + 1) + byte(data, base + 2) * 256
  return word % 256, math.floor(word / 4096) % 16
end

-- Original cartridge behavior, distinct from attributes()' native numbering.
-- Old normalized-only records cannot prove this value and must not guess it.
function Gen3Tiles:sourceBehavior(metatile)
  if type(metatile) ~= "number" or metatile < 0 or metatile % 1 ~= 0 then return nil end
  if metatile >= self.metatilesInPrimary and not self.secondary then return nil end
  local record, index = self:metatileBank(metatile)
  local stride = record and record.sourceAttributeBytes
  local mask = record and record.sourceBehaviorMask
  if (stride ~= 2 and stride ~= 4) or type(mask) ~= "number"
      or (mask ~= 255 and mask ~= 511) then return nil end
  local data = stride == 4 and record.sourceAttributes or record.attributes
  local base = index * stride
  if type(data) ~= "string" or base + stride > #data then return nil end
  return (byte(data, base + 1) + byte(data, base + 2) * 256) % (mask + 1)
end

-- Draw one metatile's layer into `plot(x, y, r, g, b)` at (ox, oy).  Layer 1
-- is what the player walks in front of and layer 2 what they walk behind, so
-- the caller draws them either side of the sprites rather than flattening the
-- two -- flattening is what puts a character on top of a treetop they should
-- disappear behind.
function Gen3Tiles:drawLayer(metatile, layer, ox, oy, plot)
  local first = (layer - 1) * 4
  if first<0 or first+4>8 or first%1~=0 then return end
  local record,local_ = self:metatileBank(metatile)
  local data=record and record.metatiles
  local base=local_*16
  if not (data and base+16<=#data) then return end
  base=base+first*2
  for q = 0, 3 do
    -- Decode the four ROM words directly. Baking every animation frame
    -- previously allocated eight entry tables plus a list for each layer,
    -- even though this path only reads half of them and retains none.
    local word=byte(data,base+q*2+1)+byte(data,base+q*2+2)*256
    local tile=word%1024
    local flipX=math.floor(word/1024)%2==1
    local flipY=math.floor(word/2048)%2==1
    local pixels = self:tilePixels(tile)
    local pal = self:palette(math.floor(word/4096)%16)
    local tx = ox + (q % 2) * 8
    local ty = oy + math.floor(q / 2) * 8
    for y = 0, 7 do
      local sy = flipY and (7 - y) or y
      for x = 0, 7 do
        local sx = flipX and (7 - x) or x
        local v = pixels[sy * 8 + sx + 1]
        -- index 0 is transparent on BOTH layers; the backdrop shows through
        if v ~= 0 and pal then
          local c = pal[v + 1]
          if c then plot(tx + x, ty + y, c[1], c[2], c[3]) end
        end
      end
    end
  end
end

-- Whole metatile, both layers, bottom first.
function Gen3Tiles:draw(metatile, ox, oy, plot)
  for layer = 1, self.layers do
    self:drawLayer(metatile, layer, ox, oy, plot)
  end
end

-- ---------------------------------------------------------------------------
-- WHAT MOVES
--
-- A Gen 3 tileset animates by having a run of its tiles replaced in VRAM
-- every few frames -- water, a waterfall, a shoreline, a flower bed, a
-- fountain.  The extractor reads those runs off the cartridge (see
-- extractTilesetAnimations) and hangs them on the tileset record; both halves
-- of a pair may carry some, and a secondary's tile numbers are relative to
-- its own bank, so they are shifted into the pair's numbering here -- the
-- same place every other bank boundary is resolved.
-- ---------------------------------------------------------------------------

function Gen3Tiles:animations()
  if self._anims then return self._anims end
  local out = {}
  local function add(record, base)
    local list = record and record.animations
    if type(list) ~= "table" then return end
    for _, a in ipairs(list) do
      local frames = a.frames
      if type(frames) == "table" and #frames > 1 and (tonumber(a.count) or 0) > 0 then
        out[#out + 1] = { tile = base + (tonumber(a.tile) or 0),
                          count = tonumber(a.count),
                          step = tonumber(a.step) or 16,
                          frames = frames }
      end
    end
  end
  add(self.primary, 0)
  add(self.secondary, self.tilesInPrimary)
  self._anims = out
  return out
end

local function gcd(a, b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

-- HOW MANY DISTINCT PICTURES THE PAIR HAS.
--
-- Each animation has its own frame count -- Hoenn's water has eight, its
-- waterfall four -- and they all advance on the same tick, so the pair
-- repeats after the least common multiple of them.  Capped, because a sheet
-- is baked once per frame and a pathological cache should cost a missing
-- animation rather than a minute of loading.
Gen3Tiles.MAX_ANIM_FRAMES = 16

function Gen3Tiles:animFrameCount()
  local n = 1
  for _, a in ipairs(self:animations()) do
    local f = #a.frames
    n = n * f / gcd(n, f)
    if n > Gen3Tiles.MAX_ANIM_FRAMES then return Gen3Tiles.MAX_ANIM_FRAMES end
  end
  return math.floor(n)
end

-- How many ticks one frame lasts.  The cartridge gives each animation its own
-- divisor; this port reads one cadence for all of them, so a pair that
-- somehow carried two takes the shorter and says nothing -- there is nothing
-- to say until the divisors are read out of the callbacks.
function Gen3Tiles:animStep()
  local step = nil
  for _, a in ipairs(self:animations()) do
    if not step or a.step < step then step = a.step end
  end
  return step or 16
end

-- Lay frame `f` (0-based) over the tileset's own tiles.
function Gen3Tiles:setAnimFrame(f)
  local anims = self:animations()
  if #anims == 0 then return end
  self.animFrame = f
  self.tileOverride = {}
  for _, a in ipairs(anims) do
    local frame = a.frames[(f % #a.frames) + 1]
    if type(frame) == "string" then
      for k = 0, a.count - 1 do
        local at = k * 32
        if at + 32 <= #frame then
          self.tileOverride[a.tile + k] = frame:sub(at + 1, at + 32)
        end
      end
    end
  end
  self.tileCache = {}
end

-- Observe independent VRAM animation clocks without pre-baking a combined
-- cycle. A projection can keep fixed atlas slots even when animation periods
-- have a large LCM. Only changed tile decodes are invalidated; native shared
-- bank bytes and the renderer's legacy frame-selection API stay untouched.
function Gen3Tiles:setAnimationTicks(ticks)
  assert(type(ticks) == "number" and ticks >= 0 and ticks % 1 == 0
    and ticks <= 9007199254740991, "invalid terrain animation ticks")
  local nextOverrides = {}
  for _, a in ipairs(self:animations()) do
    local frame = a.frames[(math.floor(ticks / math.max(1, a.step)) % #a.frames) + 1]
    if type(frame) == "string" then
      for k = 0, a.count - 1 do
        local at = k * 32
        if at + 32 <= #frame then nextOverrides[a.tile + k] = frame:sub(at + 1, at + 32) end
      end
    end
  end
  local previous, dirty = self.tileOverride or {}, {}
  for tile, bytes in pairs(nextOverrides) do
    if previous[tile] ~= bytes then dirty[tile] = true; self.tileCache[tile] = nil end
  end
  for tile in pairs(previous) do
    if nextOverrides[tile] == nil then dirty[tile] = true; self.tileCache[tile] = nil end
  end
  self.tileOverride, self.animationTicks = nextOverrides, ticks
  return dirty
end

-- Which metatiles change when the frame does -- the only ones a sheet has to
-- hold more than one picture of.
function Gen3Tiles:animatedMetatiles()
  local anims = self:animations()
  if #anims == 0 then return {} end
  local moves = {}
  for _, a in ipairs(anims) do
    for k = 0, a.count - 1 do moves[a.tile + k] = true end
  end
  local out = {}
  for id = 0, self:metatileCount() - 1 do
    for _, e in ipairs(self:entries(id)) do
      if moves[e.tile] then
        out[#out + 1] = id
        break
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Sheet baking
--
-- The renderer wants one quad per cell, not eight tile draws with a palette
-- swap between each, so a pair's metatiles are composited once into two
-- sheets -- bottom layer and top layer -- and the map then blits 16x16 quads
-- out of them.  Two sheets rather than one flattened image is the whole point:
-- the player walks BETWEEN them, which is what puts a character behind a
-- treetop and in front of the grass under it.
--
-- Baking is deferred and cached per pair because it is the expensive part
-- (a 656-metatile pair is about 336,000 pixels across the two sheets) and
-- because 441 layouts share only 76 pairs.
-- ---------------------------------------------------------------------------

Gen3Tiles.SHEET_COLS = 16

-- HOW LONG THE SHEET IS -- which is the size of the metatile ID SPACE, not
-- the number of metatiles anybody defined.
--
-- metatileBank splits at metatilesInPrimary: id 511 is the primary's last
-- slot and id 512 is the SECONDARY's first, whatever the primary actually
-- filled in. A pair's sheet is indexed by the id itself, so it has to be that
-- long or the secondary's metatiles have nowhere to sit.
--
-- Summing the two counts instead looks right and is right exactly when the
-- primary defines all 512 -- which the OUTDOOR primary does, so Littleroot
-- and the moving truck drew perfectly. Emerald's indoor primary defines
-- EIGHT. Every room in the game asks for ids 513 and up, the sheet was 204
-- metatiles long, every lookup past 203 came back nil, and the inside of the
-- house was white while the town outside it was not.
--
-- The blank stretch this leaves (504 undefined ids on an indoor pair) costs
-- loop iterations and no pixels: `entries` returns nothing for an id its bank
-- never defined, so nothing is plotted and the sheet rows stay transparent.
function Gen3Tiles:metatileCount()
  if self.secondary then
    return self.metatilesInPrimary + (self.secondary.metatileCount or 0)
  end
  return (self.primary and self.primary.metatileCount) or 0
end

function Gen3Tiles:sheetLayout()
  local count = self:metatileCount()
  local cols = Gen3Tiles.SHEET_COLS
  local rows = math.ceil(count / cols)
  return cols, rows, cols * 16, rows * 16
end

-- Where a metatile sits on the sheet, in pixels.
function Gen3Tiles:sheetOrigin(metatile)
  local cols = Gen3Tiles.SHEET_COLS
  return (metatile % cols) * 16, math.floor(metatile / cols) * 16
end

-- Composite one layer of every metatile into `plot(x, y, r, g, b)`.  The
-- caller supplies the surface, so this is the same code path the headless
-- tests exercise and the one that fills a love ImageData.
-- WHICH SIDE OF THE PLAYER A METATILE'S TOP HALF IS ON.
--
-- Not every metatile's second layer is scenery to walk behind. The
-- attributes word carries a layer type, and it decides which background the
-- top half is drawn to -- which is to say whether the player passes in front
-- of it or behind it.
--
-- The cartridge answers this with its own map data, on the first map of the
-- game. In Littleroot:
--
--   * the cell directly in front of EVERY door -- metatile 513, the one you
--     stand on the moment you step out of a house -- is layer type 1, and it
--     has 138 of its 256 pixels in the TOP layer. Drawn above the player,
--     that buries him to the chest every time he leaves a building.
--   * every tree and roof cell -- 528, 529, 530, up to 256 pixels of top
--     layer, all of them impassable -- is layer type 0. Those are precisely
--     the things you walk behind.
--
-- So type 1's top half is a second layer of GROUND (a carpet over a floor, a
-- path over grass) and belongs under the sprites; type 0's is cover and
-- belongs over them. Type 2 is rare -- 392 cells in the whole game, 98% of
-- them with a top layer and 85% walkable -- and behaves like type 0: it is
-- the tall grass you stand IN, whose blades draw across your feet.
--
-- Baking everything above the sprites, which is what this did, put a
-- character under the floor he was standing on 29% of the time.
local COVERED = 1
local SPLIT = 2

function Gen3Tiles:topIsAbovePlayer(metatile)
  local _, layerType = self:attributes(metatile)
  return layerType ~= COVERED
end

-- WHICH HALF OF A METATILE COVERS A REFLECTION, which is not the same
-- question as which half covers the PLAYER -- and the difference is the whole
-- of why reflections were painting over bridge planks.
--
-- The hardware has THREE background layers under a Gen 3 map, and a
-- metatile's layer type says which two of them it uses
-- (METATILE_LAYER_TYPE_*, read out of bits 12-15 of the attributes word):
--
--   NORMAL  (0)  middle + top
--   COVERED (1)  bottom + middle
--   SPLIT   (2)  bottom + top
--
-- A character is an object at priority 2, which on this hardware draws above
-- the bottom and middle backgrounds and below the top one -- so the top layer
-- is the half that hides them, which is what topIsAbovePlayer answers and
-- what drawAbove draws.
--
-- A REFLECTION is an object at priority 3 (SetUpReflection, ROM:0153EE8,
-- `mov r3,#152` subpriority and the priority field beside it).  Priority 3
-- draws above the BOTTOM background ONLY: every other layer of the metatile
-- it lands in covers it.  So:
--
--   NORMAL   nothing of the metatile is on the bottom layer, so BOTH halves
--            cover the reflection -- layer 1 here, layer 2 via drawAbove
--   COVERED  layer 1 is the bottom (the water), layer 2 the middle -- so the
--            reflection sits on the water and layer 2 covers it.  THIS IS
--            THE BRIDGE: every one of the eight REFLECTION_UNDER_BRIDGE
--            metatiles in the game is COVERED, its water in layer 1 and its
--            planks in layer 2, and that is how the cartridge puts a
--            reflection in the water UNDER a pier instead of on top of it.
--   SPLIT    layer 1 is the bottom and layer 2 the top, so drawAbove already
--            covers it and there is nothing extra to draw.
--
-- Returns the layer to overdraw, or nil when the top layer alone suffices.
function Gen3Tiles:reflectionCoverLayer(metatile)
  local _, layerType = self:attributes(metatile)
  if layerType == COVERED then return 2 end
  if layerType == SPLIT then return nil end
  return 1
end

-- One metatile into one sheet slot, with the layer rules above.  Separate
-- from bakeLayer because an animation frame redraws only the metatiles that
-- move, into slots of their own past the end of the static sheet.
function Gen3Tiles:bakeMetatileInto(id, layer, slot, plot)
  local ox, oy = self:sheetOrigin(slot)
  if layer == 1 then
    self:drawLayer(id, 1, ox, oy, plot)
    -- a covered metatile's top half is ground too, so it is composited
    -- into the SAME sheet, over its own bottom half and under everything
    if not self:topIsAbovePlayer(id) then
      self:drawLayer(id, 2, ox, oy, plot)
    end
  elseif self:topIsAbovePlayer(id) then
    self:drawLayer(id, layer, ox, oy, plot)
  end
end

function Gen3Tiles:bakeLayer(layer, plot)
  local count = self:metatileCount()
  for id = 0, count - 1 do
    self:bakeMetatileInto(id, layer, id, plot)
  end
  return count
end


return Gen3Tiles
