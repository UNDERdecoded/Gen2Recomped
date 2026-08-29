-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Draws a map's tile layer: one texture atlas per tileset, 8x8 quads,
-- a single static SpriteBatch covering the map plus a border-block ring
-- (the ring plays the role of the GB border blocks around small maps).

local Assets = require("src.render.Assets")
local PaletteFX = require("src.render.PaletteFX")

local TileRenderer = {}
TileRenderer.__index = TileRenderer

local BORDER_BLOCKS = 3 -- ring width; > half a screen (2.5 blocks)

-- OVERWORLD maps fill beyond-edge space from save.options.voidFill:
--   trees (default) -- solid tree wall $0F (Viridian/Cerulean/Celadon)
--   water           -- solid water $43 (Cinnabar/Route 19 border block)
--   black           -- solid black (no tiled metatile)
-- Other tilesets keep their designated border (interiors stay black/void).
local TREE_WALL_BLOCK = 0x0F
local WATER_BORDER_BLOCK = 0x43
TileRenderer.VOID_FILLS = { "trees", "water", "black" }
TileRenderer.voidFill = "trees"

local function borderBlockFor(map)
  if map.def.tileset == "OVERWORLD" then
    local mode = TileRenderer.voidFill or "trees"
    if mode == "water" then return WATER_BORDER_BLOCK end
    if mode == "black" then return false end
    return TREE_WALL_BLOCK
  end
  return map.def.borderBlock
end
TileRenderer.borderBlockFor = borderBlockFor

function TileRenderer.setVoidFill(mode)
  local ok = false
  for _, m in ipairs(TileRenderer.VOID_FILLS) do
    if m == mode then ok = true; break end
  end
  TileRenderer.voidFill = ok and mode or "trees"
end

function TileRenderer.cycleVoidFill()
  local cur = TileRenderer.voidFill or "trees"
  local idx = 1
  for i, m in ipairs(TileRenderer.VOID_FILLS) do
    if m == cur then idx = i; break end
  end
  TileRenderer.setVoidFill(
    TileRenderer.VOID_FILLS[idx % #TileRenderer.VOID_FILLS + 1])
  return TileRenderer.voidFill
end

-- field.gen2TileAnim, handed over when a map's renderer is built (MapLoader
-- has the dataset; this module does not).  Nil on Gen 1 and on any cache
-- older than the one that started extracting TilesetTowerAnim.
function TileRenderer.setTileAnim(spec)
  if type(spec) == "table" and spec.tiles and spec.image then
    TileRenderer.TILE_ANIM = spec
  end
end

function TileRenderer.applyOptions(opts)
  TileRenderer.setVoidFill(opts and opts.voidFill or "trees")
end

function TileRenderer.voidFillLabel(mode)
  mode = mode or TileRenderer.voidFill or "trees"
  if mode == "water" then return "WATER" end
  if mode == "black" then return "BLACK" end
  return "TREES"
end

local imageCache = {}

local function getImage(path)
  if not imageCache[path] then
    imageCache[path] = Assets.image(path)
  end
  return imageCache[path]
end

-- ------------------------------------------------------------------
-- Tile animation (home/vcopy.asm): tilesets with TILEANIM_WATER[_FLOWER]
-- rotate water tile $14 one pixel every 20 frames (4 steps right, 4
-- left) and cycle flower tile $03 through 3 frames.
-- Those two cycles are the *defaults* a vanilla tileset record derives
-- from its `animation` string; a tileset that carries `animatedTiles`
-- declares its own set instead and animates with no engine change.
-- ------------------------------------------------------------------

local WATER_TILE, FLOWER_TILE = 0x14, 0x03
-- cumulative pixel offset per animation step (the rrca/rlca sequence)
local WATER_OFFSETS = { 1, 2, 3, 2, 1, 0, 7, 0 }
-- flower frame per step (wMovingBGTilesCounter2 & 3: <2 -> 1, 2, 3)
local FLOWER_FRAMES = { 1, 2, 3, 1, 1, 2, 3, 1 }
local ANIM_PERIOD = 20
local FLOWER_IMAGES = {
  "assets/generated/tilesets/flower1.png",
  "assets/generated/tilesets/flower2.png",
  "assets/generated/tilesets/flower3.png",
}
local SPINNER_STRIP = "assets/generated/tilesets/spinners.png"

local animFrame = 0
local animAccum = 0
local ANIM_STEP = 1 / 60 -- Game Boy logic rate (matches FixedStep.STEP)

-- Advance water/flower/spinner tile animation.  Called from the overworld
-- draw path so it keeps running under dialogs (overworld update does not),
-- but consumes wall-clock dt into 60Hz steps so high/low display refresh
-- no longer speeds up or slows the cycle (issue #4).
-- tick() / tick(nil) with no love.timer.getDelta (headless tests) still
-- advances exactly one frame per call.
function TileRenderer.tick(dt)
  if dt == nil and love and love.timer and love.timer.getDelta then
    dt = love.timer.getDelta()
  end
  if dt == nil then
    animFrame = animFrame + 1
    return
  end
  -- Cap catch-up so a long stall cannot jump many water/flower periods
  animAccum = math.min(animAccum + dt, 0.25)
  while animAccum >= ANIM_STEP do
    animAccum = animAccum - ANIM_STEP
    animFrame = animFrame + 1
  end
end

-- ------------------------------------------------------------------
-- Spinner arrow tiles (engine/overworld/spinners.asm LoadSpinnerArrowTiles):
-- a wholly separate, contextually-triggered VRAM patch layered on top of
-- the ambient water/flower cycle above -- while wMovementFlags.BIT_SPINNING
-- is set (Gym/Rocket Hideout spinner puzzles), each forced-movement step
-- farcalls LoadSpinnerArrowTiles, which flips 4 fixed destination tile IDs
-- per tileset between the shared 'blur' graphic (gfx/overworld/spinners.2bpp,
-- SpinnerArrowAnimTiles) and the tileset's own static graphic (restore).
-- Only 2 distinct frames exist -- no continuous multi-frame cycle.
-- ------------------------------------------------------------------

-- data/tilesets/spinner_tiles.asm: dest tile IDs patched per tileset
TileRenderer.SPINNER_ARROW_TILES = {
  GYM = { 0x3c, 0x3d, 0x4c, 0x4d },
  FACILITY = { 0x20, 0x21, 0x30, 0x31 },
}

-- dest tile id -> offset (in 8x8 tiles) into the SpinnerArrowAnimTiles strip,
-- taken verbatim from the `spinner SpinnerArrowAnimTiles, <offset>, <dest>`
-- rows of data/tilesets/spinner_tiles.asm
local SPINNER_STRIP_OFFSET = {
  GYM = { [0x3c] = 1, [0x3d] = 3, [0x4c] = 0, [0x4d] = 2 },
  FACILITY = { [0x20] = 0, [0x21] = 1, [0x30] = 2, [0x31] = 3 },
}

local spinning = false
function TileRenderer.setSpinning(active)
  spinning = active
end

-- true while the spinner arrow tiles should show the 'blur' graphic; false
-- means draw nothing extra (the static window tile shows through,
-- matching the asm's restore-to-original behavior). The 8-tick
-- half-period approximates one GB movement step (2px/frame); this is a
-- deliberate approximation of wSimulatedJoypadStatesIndex bit-0 parity, not
-- a cycle-accurate replication -- the port's tweened scriptMove has no
-- direct equivalent discrete step counter.
function TileRenderer.spinBlurActive()
  return spinning and (math.floor(animFrame / 8) % 2 == 0)
end

-- ------------------------------------------------------------------
-- animatedTiles: the per-kind resource builders.  Each returns the
-- texture list a step indexes into, or false when the pixels are
-- unreachable (headless, or a missing frame file) -- false disables that
-- one entry and leaves the static batch showing through, which is what
-- the water/flower branches did before they were data.
-- ------------------------------------------------------------------

-- shade 0-3 -> one of `colors`' 4 entries (same cutoffs PaletteFX's shader
-- uses), alpha passed through unchanged; nil colors leaves r,g,b as-is.
-- Shared by the whole-atlas bake (getGbcAtlas) and the animated-tile
-- variants below, so water/flowers/spinners match the static tiles around
-- them under RED++ instead of showing their un-recolored grayscale.
local function recolorSample(r, g, b, a, colors)
  if not (colors and a > 0) then return r, g, b, a end
  local col = r > 0.83 and colors[1] or r > 0.5 and colors[2]
              or r > 0.17 and colors[3] or colors[4]
  return col[1] / 255, col[2] / 255, col[3] / 255, a
end

-- exported: a render pipeline bakes a map's palette into its own texture
-- atlas the same way, and has to land on the identical colors as the 2D
-- tiles it is standing in for
TileRenderer.recolorSample = recolorSample

-- the 8 shifted variants of one tile (built once per sheet + tile id [+
-- gbcKey, when `colors` recolors it for RED++ -- see buildAnim])
local shiftVariants = {}
local function getShiftVariants(tilesetImagePath, perRow, tile, colors, gbcKey)
  local key = tilesetImagePath .. "#" .. tile .. (gbcKey or "")
  if shiftVariants[key] ~= nil then return shiftVariants[key] end
  if not (love.image and love.image.newImageData) then
    shiftVariants[key] = false
    return false
  end
  local id = Assets.imageData(tilesetImagePath)
  local sx = (tile % perRow) * 8
  local sy = math.floor(tile / perRow) * 8
  local out = {}
  for o = 0, 7 do
    local v = love.image.newImageData(8, 8)
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = id:getPixel(sx + x, sy + y)
        r, g, b, a = recolorSample(r, g, b, a, colors)
        v:setPixel((x + o) % 8, y, r, g, b, a)
      end
    end
    out[o + 1] = love.graphics.newImage(v)
  end
  shiftVariants[key] = out
  return out
end

local frameImages = {}
local function getFrameImages(paths, colors, gbcKey)
  local key = table.concat(paths, "|") .. (gbcKey or "")
  if frameImages[key] ~= nil then return frameImages[key] end
  local out = {}
  for i, path in ipairs(paths) do
    local ok, img = pcall(function()
      if not (colors and love.image and love.image.newImageData) then
        return getImage(path)
      end
      local id = Assets.imageData(path)
      local w, h = id:getDimensions()
      local out2 = love.image.newImageData(w, h)
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          local r, g, b, a = id:getPixel(x, y)
          r, g, b, a = recolorSample(r, g, b, a, colors)
          out2:setPixel(x, y, r, g, b, a)
        end
      end
      return love.graphics.newImage(out2)
    end)
    if not ok then
      frameImages[key] = false
      return false
    end
    out[i] = img
  end
  frameImages[key] = out
  return out
end

-- the tileset's own atlas ImageData with the patched tile slots blitted
-- over with a shared strip (vanilla: assets/generated/tilesets/spinners.png,
-- extracted from gfx/overworld/spinners.png); cached per tileset + strip
local toggleImages = {}
local stripData = {}
local function getToggleImage(spec, tilesetImagePath, perRow)
  local key = tilesetImagePath .. "#" .. tostring(spec.image)
  if toggleImages[key] ~= nil then return toggleImages[key] end
  local offsets = spec.stripOffsets
  if not (love.image and love.image.newImageData) or not offsets then
    toggleImages[key] = false
    return false
  end
  if stripData[spec.image] == nil then
    local ok, id = pcall(Assets.imageData, spec.image)
    stripData[spec.image] = ok and id or false
  end
  local strip = stripData[spec.image]
  if not strip then
    toggleImages[key] = false
    return false
  end
  local atlas = Assets.imageData(tilesetImagePath)
  local clone = love.image.newImageData(atlas:getWidth(), atlas:getHeight())
  clone:paste(atlas, 0, 0, 0, 0, atlas:getWidth(), atlas:getHeight())
  for id, offset in pairs(offsets) do
    local sx = offset * 8
    local dx = (id % perRow) * 8
    local dy = math.floor(id / perRow) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = strip:getPixel(sx + x, y)
        clone:setPixel(dx + x, dy + y, r, g, b, a)
      end
    end
  end
  local img = love.graphics.newImage(clone)
  toggleImages[key] = img
  return img
end

-- One atlas-SIZED texture per animation FRAME, transparent everywhere except
-- the animated tiles, which are pasted in from a strip at their atlas cells.
-- This is the toggle builder's trick applied to a sequence instead of a gate:
-- because every frame keeps the atlas layout, the batch's existing per-tile
-- quads stay valid and the draw path only has to swap the texture -- which is
-- exactly what it already does for water.  Leaving the rest transparent (as
-- opposed to cloning the atlas) means the overdraw can never repaint a
-- neighboring tile, and it stays correct under the GBC atlas bake, where the
-- static window is drawn from a recolored atlas this builder cannot see.
--
-- SPROUT TOWER's pillar needs this and the single-tile `frames` kind cannot
-- give it: AnimateTowerPillarTile rewrites TEN different tiles in step, so a
-- frame is ten tiles, not one.
local atlasFrames = {}

local function getAtlasFrames(spec, tilesetImagePath, perRow, colors, gbcKey,
                              colorsFor)
  local key = tilesetImagePath .. "#af#" .. tostring(spec.image) .. (gbcKey or "")
  if atlasFrames[key] ~= nil then return atlasFrames[key] or nil end
  local tiles, count = spec.tiles, spec.frames or 0
  if not (love.image and love.image.newImageData) or not tiles or count < 1 then
    atlasFrames[key] = false
    return nil
  end
  local okStrip, strip = pcall(Assets.imageData, spec.image)
  local okAtlas, atlas = pcall(Assets.imageData, tilesetImagePath)
  if not (okStrip and strip and okAtlas and atlas) then
    atlasFrames[key] = false
    return nil
  end
  local aw, ah = atlas:getWidth(), atlas:getHeight()
  local out = {}
  for frame = 0, count - 1 do
    local page = love.image.newImageData(aw, ah)
    for column, id in ipairs(tiles) do
      local sx, sy = (column - 1) * 8, frame * 8
      local dx, dy = (id % perRow) * 8, math.floor(id / perRow) * 8
      -- Gen2's palette byte is per TILE, and the pillar's ten tiles need not
      -- share one, so ask per tile and only fall back to the entry's palette
      local tint = colors
      if colorsFor then tint = colorsFor(id) or colors end
      if sx + 8 <= strip:getWidth() and sy + 8 <= strip:getHeight()
         and dx + 8 <= aw and dy + 8 <= ah then
        for y = 0, 7 do
          for x = 0, 7 do
            local r, g, b, a = strip:getPixel(sx + x, sy + y)
            r, g, b, a = recolorSample(r, g, b, a, tint)
            page:setPixel(dx + x, dy + y, r, g, b, a)
          end
        end
      end
    end
    out[frame + 1] = love.graphics.newImage(page)
  end
  atlasFrames[key] = out
  return out
end

-- a toggle entry names the predicate that decides whether its patch shows
-- this frame; an unknown name (or none) is always on
TileRenderer.GATES = {
  spinning = function() return TileRenderer.spinBlurActive() end,
}

function TileRenderer.registerGate(name, predicate)
  TileRenderer.GATES[name] = predicate
end

local function gateOpen(name)
  local predicate = TileRenderer.GATES[name]
  if not predicate then return true end
  return predicate() and true or false
end

-- The vanilla animation set as data: what the importer would write onto a
-- tileset record derived from its `animation` string and its spinner-tile
-- row.  Consulted only when the record declares no animatedTiles of its
-- own, so the vanilla frame is byte-for-byte what it always was.
function TileRenderer.defaultAnimatedTiles(tileset)
  local out = {}
  local anim = tileset.animation
  if anim == "TILEANIM_WATER" or anim == "TILEANIM_WATER_FLOWER" then
    out[#out + 1] = { tile = WATER_TILE, kind = "hshift",
                      period = ANIM_PERIOD, offsets = WATER_OFFSETS }
  end
  if anim == "TILEANIM_WATER_FLOWER" then
    out[#out + 1] = { tile = FLOWER_TILE, kind = "frames",
                      period = ANIM_PERIOD, images = FLOWER_IMAGES,
                      sequence = FLOWER_FRAMES }
  end
  -- field.gen2TileAnim: the Sprout / Tin Tower pillar, read off
  -- TilesetTowerAnim.  Named by tileset so it only claims the tower set.
  local pillar = TileRenderer.TILE_ANIM
  if pillar and pillar.tileset and pillar.tiles
     and (tileset.id == pillar.tileset or tileset.name == pillar.tileset) then
    out[#out + 1] = { tiles = pillar.tiles, kind = "atlasframes",
                      period = pillar.period or ANIM_PERIOD,
                      image = pillar.image, frames = pillar.frames,
                      sequence = pillar.sequence }
  end
  local spinners = TileRenderer.SPINNER_ARROW_TILES[tileset.id]
  if spinners then
    out[#out + 1] = { tiles = spinners, kind = "toggle", image = SPINNER_STRIP,
                      stripOffsets = SPINNER_STRIP_OFFSET[tileset.id],
                      gate = "spinning" }
  end
  return out
end

-- one entry's runtime form: the tile ids it claims, the textures a step
-- picks from, and either a step sequence (hshift/frames) or a gate
-- (toggle).  nil when the entry's pixels could not be built.
--
-- gbc, when present (RED++ with a baked atlas -- see getGbcAtlas), recolors
-- hshift/frames entries (water/flowers) the same way the atlas bakes their
-- static tile, so they match their surroundings instead of showing raw
-- grayscale over an otherwise fully-colored map. The "toggle" kind
-- (spinner puzzle blur, gfx/overworld/spinners.png) is a whole-atlas clone
-- built from the ORIGINAL grayscale atlas, not worth recoloring for a rare,
-- gameplay-gated blur -- it is skipped under gbc, same as the buildAnim
-- caller already does for a texture-build failure (the static, correctly-
-- colored tile shows through unanimated).
local function buildAnim(spec, tilesetImagePath, perRow, quads, gbc)
  local tiles = spec.tiles
  if not tiles then
    if spec.tile == nil then return nil end
    tiles = { spec.tile }
  end
  local period = spec.period or ANIM_PERIOD
  local colors
  if gbc then
    if gbc.colorsFor then
      -- Gen2: the palette comes from the tileset's own palMap/palColors
      -- (LoadTilesetPalette's tile->palette byte), not from RED++'s eight
      -- world groups.  Without this the surf shimmer overdrew the baked
      -- atlas with raw grayscale every frame -- i.e. grey water.
      colors = gbc.colorsFor(tiles[1])
    else
      local group = PaletteFX.worldGroupAt(gbc.tilesetId, gbc.mapId, tiles[1])
      colors = group and gbc.groupColors[group + 1]
    end
  end
  if spec.kind == "hshift" then
    local offsets = spec.offsets
    if not offsets or #offsets == 0 then return nil end
    local textures = getShiftVariants(tilesetImagePath, perRow, tiles[1],
                                      colors, gbc and gbc.key)
    if not textures then return nil end
    local sequence = {}
    for i, offset in ipairs(offsets) do sequence[i] = offset + 1 end
    return { tiles = tiles, textures = textures, sequence = sequence,
             period = period }
  elseif spec.kind == "frames" then
    local sequence = spec.sequence
    if not (spec.images and sequence and #sequence > 0) then return nil end
    local textures = getFrameImages(spec.images, colors, gbc and gbc.key)
    if not textures then return nil end
    return { tiles = tiles, textures = textures, sequence = sequence,
             period = period }
  elseif spec.kind == "atlasframes" then
    local sequence = spec.sequence
    if not (sequence and #sequence > 0) then return nil end
    local textures = getAtlasFrames(spec, tilesetImagePath, perRow, colors,
                                    gbc and gbc.key, gbc and gbc.colorsFor)
    if not textures then return nil end
    -- each frame texture is atlas-sized, so a cell needs the quad of the tile
    -- it stands in rather than a single-tile image (same as `toggle`); unlike
    -- `toggle` it steps through a sequence rather than being gated
    return { tiles = tiles, textures = textures, sequence = sequence,
             period = period,
             quadFor = function(tile) return quads[tile] end }
  elseif spec.kind == "toggle" then
    if gbc and gbc.groupColors then return nil end
    local image = getToggleImage(spec, tilesetImagePath, perRow)
    if not image then return nil end
    -- the patch texture is a whole-atlas clone, so each cell needs the
    -- quad of the tile it stands in rather than a single-tile image
    return { tiles = tiles, textures = { image }, gate = spec.gate,
             quadFor = function(tile) return quads[tile] end }
  end
  return nil
end

-- True GBC overworld coloring (COLORS=RED++): recolor the WHOLE tileset
-- atlas once, per (tileset image, map), rather than trying to retrofit the
-- SGB zone/shade-remap-shader post-process (built for a handful of coarse
-- screen regions) into per-tile precision -- pokered-gbc's real model is
-- "one of 8 four-color BG palettes baked per tile GRAPHIC"
-- (color/loadpalettes.asm LoadTilesetPalette), which is exactly a
-- recolored atlas, not a shader pass. Every existing draw path (batches,
-- quads, border fill) then just works unmodified, with no shader at
-- draw time; OverworldState.sgbWorldZones skips the shade-remap zone pass
-- entirely when this is active (re-running it over already-true-color
-- pixels would corrupt them), and SpriteRenderer's own OBP bake composites
-- on top with ordinary alpha blending -- no trueColor exemption needed,
-- because there is no shader left for it to be exempted from.
--
-- Only the ROOF group (index 6, OVERWORLD/PLATEAU only) varies by town
-- (LoadTownPalette); Route 6's mid-map Saffron-roof y<2 split is not
-- reproduced (it would need a rebuild on crossing the boundary for two
-- tile-rows of one route -- not worth the complexity), so it bakes with
-- the route's own default roof (Vermilion's) throughout.
local gbcAtlasCache = {}

-- Gen2 GBC palette atlas: bakes pre-colored tiles using the palMap (tile→palette)
-- and palColors (7 palettes × 4 RGB colors) stored in the tileset def.
--
-- exported because the ANIMATED tiles have to land on the same palette: the
-- surf shimmer overdraws the baked atlas every frame, so a shimmer built from
-- the raw grayscale sheet turns the whole sea grey (only the un-animated wave
-- crests kept their blue).
function TileRenderer.gen2TileColors(palMap, palColors, tile)
  if not (palMap and palColors and #palColors > 0) then return nil end
  local raw = palMap[tile + 1] or 0
  return palColors[math.min(raw, #palColors - 1) + 1]
end

-- Which of the tileset's four time-of-day palette rows is live.  The ROM picks
-- these per map (LoadMapPals: EnvironmentColorsPointers[environment] then the
-- GetTimeOfDay row), and a PALETTE_DARK map takes the DARKNESS row outright --
-- which is the same flag the RED++ bake already keys on.
--
-- palColorsByTod is what the Gen2 importer now writes; palColors alone is the
-- older single-row shape, kept working so a dataset extracted before this
-- change still renders instead of falling back to grey.
local function gen2PalColors(tileset)
  local byTod = tileset.palColorsByTod
  if type(byTod) ~= "table" then return tileset.palColors end
  if PaletteFX.darkWorld() then return byTod.DARK or tileset.palColors end
  return byTod[PaletteFX.gen2Tod()] or byTod.DAY or tileset.palColors
end

-- One atlas per (tileset image, COLORS mode, time of day).  Leaving the mode
-- out of this key is why switching COLORS did nothing out in the Gen2
-- overworld: the first bake won and every later mode kept being handed it.
local function gen2AtlasKey(imagePath)
  return imagePath .. "#gen2pal:" .. tostring(PaletteFX.mode) .. ":"
    .. (PaletteFX.darkWorld() and "DARK" or tostring(PaletteFX.gen2Tod()))
end

local gen2AtlasCache = {}
-- The tile index where a tileset's COPIED art begins, or nil when it has none.
--
-- `_borrowSrcH` is the atlas height before any borrowing, stamped by
-- MapEdits.extendAtlas. Every palette bake needs the same boundary, and each
-- one deriving it separately is three chances to derive it differently.
function TileRenderer.borrowStart(tileset)
  if type(tileset) ~= "table" then return nil end
  if not (tileset._borrowSrcH and tileset.imageWidth) then return nil end
  return math.floor(tileset.imageWidth / 8) * math.floor(tileset._borrowSrcH / 8)
end

local function getGen2Atlas(key, imagePath, perRow, palMap, palColors,
                            borrowStartOf)
  if not (love.image and love.image.newImageData) then return nil end
  if gen2AtlasCache[key] ~= nil then return gen2AtlasCache[key] or nil end
  local img = false
  local ok, src = pcall(Assets.imageData, imagePath)
  if ok and src then
    local iw, ih = src:getDimensions()
    local total = (iw / 8) * (ih / 8)
    local borrowFrom = borrowStartOf
    -- SAY IT WHEN THE PALETTE MAP IS SHORTER THAN THE ATLAS.
    --
    -- `gen2TileColors` reads `palMap[tile + 1] or 0`, so a tile past the end
    -- of the map does not fail -- it takes row zero, or, when the row list is
    -- shorter still, nothing at all, and the tile is drawn in the raw 2bpp
    -- greys it was extracted as. That is a tile in black and white inside a
    -- coloured map, and every symptom of it points at the ART rather than at
    -- the palette, which is where several rounds of looking went.
    --
    -- The editor extends both when it copies art between tilesets. If they
    -- ever disagree, this is the line that says so, with both numbers.
    if type(palMap) == "table" and #palMap > 0 and #palMap < total then
      require("src.core.Logger").warn(
        "gen2 atlas %s: %d tiles but palMap has %d - tiles %d..%d will draw "
        .. "in raw greys", tostring(imagePath), total, #palMap, #palMap,
        total - 1)
    end
    local out = love.image.newImageData(iw, ih)
    for t = 0, total - 1 do
      local colors = TileRenderer.gen2TileColors(palMap, palColors, t)
      -- THE SAME LAST RESORT THE RED++ BAKE HAS. If a copied tile somehow has
      -- no row of its own here -- a palMap that did not grow with the atlas,
      -- a colour list that did not -- it must not fall through to row 0, which
      -- is this tileset's text grey and is what "a black-and-white object in a
      -- coloured town" looks like. Row 0 is a real answer for a real tile and
      -- a wrong one for a borrowed one.
      if colors == nil and borrowFrom and t >= borrowFrom
         and type(palColors) == "table" and #palColors > 0 then
        colors = palColors[#palColors]
      end
      local ox, oy = (t % perRow) * 8, math.floor(t / perRow) * 8
      for py = 0, 7 do
        for px = 0, 7 do
          local r, g, b, a = src:getPixel(ox + px, oy + py)
          r, g, b, a = recolorSample(r, g, b, a, colors)
          out:setPixel(ox + px, oy + py, r, g, b, a)
        end
      end
    end
    img = love.graphics.newImage(out)
  end
  gen2AtlasCache[key] = img
  return img or nil
end

-- THE SAME BAKE, FOR A TILESET WITHOUT A MAP.
--
-- The map editor's tile palette drew straight from `Assets.image(ts.image)`,
-- which is the raw 2bpp sheet -- so every swatch in it was grey while the
-- viewport beside it was in colour, and picking a block meant matching a grey
-- drawing against a coloured world.  The colour is not the map's: Gen 2's
-- palette byte is per TILE GRAPHIC and lives on the TILESET (palMap into
-- palColors), so a tileset is all the bake needs and every map drawn with it
-- lands on the same picture.
--
-- Gated exactly as the renderer's own bake is, and returning nil when the gate
-- is shut or the extraction carries no palette -- the caller falls back to the
-- raw sheet, which is what it was already showing.
function TileRenderer.gen2AtlasFor(tileset)
  if type(tileset) ~= "table" or not tileset.image then return nil end
  if not (tileset.palMap and #tileset.palMap > 0) then return nil end
  if not PaletteFX.usesGen2BgPal() then return nil end
  local colors = gen2PalColors(tileset)
  if not (colors and #colors > 0) then return nil end
  local perRow = tileset.tilesPerRow
  if not perRow or perRow < 1 then return nil end
  local key = gen2AtlasKey(tileset.image)
  return getGen2Atlas(key, tileset.image, perRow, tileset.palMap, colors,
                      TileRenderer.borrowStart(tileset))
end

-- Cache suffix for a map's RED++ bake.  A dark cave folds FadePal2 into the
-- palette worldGroupColors hands the bake (#383), so the lit and dark bakes of
-- one map are different images and must not share a key.
local function gbcKeyFor(mapId)
  return "#gbc:" .. mapId .. PaletteFX.darkKey()
end

local function getGbcAtlas(imagePath, tilesetId, mapId, perRow, data)
  local key = imagePath .. gbcKeyFor(mapId)
  if gbcAtlasCache[key] ~= nil then return gbcAtlasCache[key] or nil end
  local img = false
  if love.image and love.image.newImageData then
    local groupColors = PaletteFX.worldGroupColors(data, tilesetId, mapId, nil)
    if groupColors then
      local src = Assets.imageData(imagePath)
      local iw, ih = src:getDimensions()
      local total = (iw / 8) * (ih / 8)
      local out = love.image.newImageData(iw, ih)
      -- A TILE THE CARTRIDGE NEVER HAD HAS NO PALETTE GROUP, and `false` is
      -- not a colour -- it is "leave the pixels as they are", which for a 2bpp
      -- sheet is raw grey.
      --
      -- The RED++ bake colours by PALETTE GROUP: `worldGroupAt` maps a tile id
      -- to one of the map's groups, and that table was built from the ROM, so
      -- it stops at the last tile the cartridge shipped. The editor can now
      -- copy art between tilesets, and a borrowed tile lands past that end --
      -- so it fell through to `false` and drew in greys inside a fully
      -- coloured town. Nothing about it looked like a palette problem, because
      -- every other tile on screen was correct.
      --
      -- The borrowed tile brings its own palette with it (see
      -- MapEdits.extendAtlas: the source tileset's row is appended to this
      -- tileset's `palColors` and pointed at by `palMap`). So that is the
      -- fallback -- not a guess, the colours the art was drawn in.
      local borrowedTs = data and data.tilesets and data.tilesets[tilesetId]
      local borrowedMap = borrowedTs and borrowedTs.palMap
      local borrowedRows = borrowedTs and gen2PalColors(borrowedTs)
      -- WHERE THE CARTRIDGE'S OWN ART STOPS AND THE COPIED ART BEGINS.
      --
      -- `worldGroupAt` does NOT return nil for a tile it has never heard of --
      -- it returns group 7, the TEXT palette, which is the menu grey:
      --
      --     return groups[tileId] or 7  -- tile ids past the tileset's 96
      --
      -- That is right for the menu tiles it was written for and wrong for
      -- borrowed art, and it is why the "no group" fallback below could never
      -- fire: `colors` was always a valid row, and the row was grey. A tree
      -- copied out of TilesetForest was not falling through a gap, it was
      -- being deliberately assigned the text palette.
      --
      -- `_borrowSrcH` is the atlas height before any borrowing (stamped by
      -- MapEdits.extendAtlas), so this is the exact tile index where the
      -- copied art starts. Below it nothing changes; at or above it the tile
      -- carries its own palette and that is the one to use.
      local borrowFrom = TileRenderer.borrowStart(borrowedTs)
      local tileColors = {}
      for t = 0, total - 1 do
        local colors = tileColors[t]
        if colors == nil then
          -- BORROWED ART ANSWERS FOR ITSELF, and is asked FIRST: the group
          -- table has an answer for this tile and the answer is wrong.
          if borrowFrom and t >= borrowFrom and borrowedMap and borrowedRows then
            colors = TileRenderer.gen2TileColors(borrowedMap, borrowedRows, t)
              or false
          end
          if not colors then
            local group = PaletteFX.worldGroupAt(tilesetId, mapId, t)
            colors = (group and groupColors[group + 1]) or false
          end
          tileColors[t] = colors
        end
        local ox, oy = (t % perRow) * 8, math.floor(t / perRow) * 8
        for py = 0, 7 do
          for px = 0, 7 do
            local sx, sy = ox + px, oy + py
            local r, g, b, a = src:getPixel(sx, sy)
            r, g, b, a = recolorSample(r, g, b, a, colors)
            out:setPixel(sx, sy, r, g, b, a)
          end
        end
      end
      -- duplicate-tile aliases: bake a copy of a shared tile graphic into
      -- a spare slot under a different palette group, so block cells that
      -- draw the alias can color apart from cells sharing the raw tile
      for _, al in ipairs(PaletteFX.TILE_ALIASES and PaletteFX.TILE_ALIASES[mapId] or {}) do
        if al.alias < total then
          local colors = groupColors[al.group + 1]
          local sxo = (al.tile % perRow) * 8
          local syo = math.floor(al.tile / perRow) * 8
          local dxo = (al.alias % perRow) * 8
          local dyo = math.floor(al.alias / perRow) * 8
          for py = 0, 7 do
            for px = 0, 7 do
              local r, g, b, a = src:getPixel(sxo + px, syo + py)
              r, g, b, a = recolorSample(r, g, b, a, colors)
              out:setPixel(dxo + px, dyo + py, r, g, b, a)
            end
          end
        end
      end
      img = love.graphics.newImage(out)
    end
  end
  gbcAtlasCache[key] = img
  return img or nil
end

-- THE GEN 1 BAKE, FOR AN EDITOR THAT HAS A MAP BUT NO RENDERER.
--
-- Gen 1 colour is not per tile GRAPHIC the way Gen 2's is -- there is no
-- palette byte on the tileset. It is per palette GROUP, resolved per MAP
-- (`PaletteFX.worldGroupAt`), which is why this one needs a map id where
-- `gen2AtlasFor` needs only a tileset: the same tile is grass on one route and
-- a roof on another.
--
-- The map editor's tile palette drew the raw 2bpp sheet for these, so every
-- Gen 1 tileset came out grey beside a coloured viewport. Exported rather than
-- reimplemented for the reason everything else in this project is: a second
-- copy of a colour rule drifts, and a palette that drifts is a palette that is
-- wrong in a way nobody can see.
--
-- Returns nil when the mode is not one that colours this way, which is the
-- caller's cue to fall back -- the DMG-flavoured modes are meant to be grey.
function TileRenderer.gbcAtlasFor(tileset, mapId, data)
  if type(tileset) ~= "table" or not tileset.image then return nil end
  if not PaletteFX.usesGbcPack() then return nil end
  local perRow = tileset.tilesPerRow
  if not perRow or perRow < 1 then return nil end
  if not mapId then return nil end
  return getGbcAtlas(tileset.image, tileset.id, mapId, perRow, data)
end

-- data: Game.data (threaded through explicitly, not required lazily, so
-- headless tests that build a map from a plain local table still work)
-- ---------------------------------------------------------------------------
-- Gen 3 metatile sheets
--
-- A Gen 1/Gen 2 tileset bakes to ONE atlas of 8x8 tiles and every block is
-- four rows of four indices into it.  A Gen 3 metatile cannot be expressed
-- that way: its eight tile entries each carry their own palette and their own
-- flips, and they come out of two tilesets at once.  So the pair is composited
-- once into two 16x16-per-metatile sheets -- bottom layer and top -- and the
-- window batches blit one quad per cell out of each.
--
-- TWO sheets, not one flattened image, because the player walks between them.
-- Flattening would put a character on top of the treetop they should vanish
-- behind, which is the single most visible thing this file can get wrong.
--
-- Cached by pair id: 441 layouts share 76 pairs, and baking is the expensive
-- part (about 336,000 pixels for a 656-metatile pair).
local gen3Sheets = {}

function TileRenderer.gen3SheetsFor(tilesetDef, data, layout)
  if not (tilesetDef and tilesetDef.blockTiles == 2) then return nil end
  local key = tilesetDef.id
  local hit = gen3Sheets[key]
  if hit ~= nil then return hit or nil end
  gen3Sheets[key] = false            -- do not retry a failed bake every frame

  local store = data and data.map_tilesets
  local primary = store and store[tilesetDef.primaryKey]
  if not primary then
    Logger.warn("gen3 tiles: %s names primary %s, which is not in "
                .. "map_tilesets", tostring(key), tostring(tilesetDef.primaryKey))
    return nil
  end
  if not (love.image and love.image.newImageData) then return nil end

  local Gen3Tiles = require("src.render.Gen3Tiles")
  local tiles = Gen3Tiles.new({
    primary = primary,
    secondary = tilesetDef.secondaryKey and store[tilesetDef.secondaryKey] or nil,
  }, layout)

  local _, _, w, h = tiles:sheetLayout()
  if w <= 0 or h <= 0 then return nil end

  local built = {}
  for layer = 1, 2 do
    local surface = love.image.newImageData(w, h)
    tiles:bakeLayer(layer, function(x, y, r, g, b)
      if x >= 0 and y >= 0 and x < w and y < h then
        surface:setPixel(x, y, r / 255, g / 255, b / 255, 1)
      end
    end)
    built[layer] = love.graphics.newImage(surface)
  end

  local record = { bottom = built[1], top = built[2], width = w, height = h,
                   tiles = tiles, metatiles = tiles:metatileCount() }
  gen3Sheets[key] = record
  Logger.info("gen3 tiles: baked %s -- %d metatiles into two %dx%d sheets",
              tostring(key), record.metatiles, w, h)
  return record
end

-- a re-import replaces the data the sheets were baked from
function TileRenderer.releaseGen3Sheets()
  gen3Sheets = {}
end

function TileRenderer.new(map, data)
  local self = setmetatable({}, TileRenderer)
  self.map = map
  self.data = data
  self.image = getImage(map.tileset.image)
  local gbcCtx
  if data and PaletteFX.usesGbcPack() and PaletteFX.hasWorldTileset(map.tileset.id) then
    local gbc = getGbcAtlas(map.tileset.image, map.tileset.id, map.id,
                            map.tileset.tilesPerRow, data)
    if gbc then
      self.image = gbc
      self.gbcAtlas = true
      -- also recolors the animated water/flower entries below, so they
      -- match the atlas's static tiles instead of showing raw grayscale
      gbcCtx = { tilesetId = map.tileset.id, mapId = map.id, key = gbcKeyFor(map.id),
                groupColors = PaletteFX.worldGroupColors(data, map.tileset.id, map.id, nil) }
      -- ...and feeds the color-0-keyed single tiles the feet overdraw needs
      -- (see getKeyedTile): same source image and palette groups, so keep the
      -- context rather than re-deriving it per draw.
      gbcCtx.imagePath = map.tileset.image
      gbcCtx.perRow = map.tileset.tilesPerRow
      self.gbcCtx = gbcCtx
      self.gbcAtlasKey = map.tileset.image .. gbcCtx.key
      self.gbcKeyed = {}
    end
  end
  -- a full-color atlas colors everything it paints, ring and border fill
  -- included, so every draw entry point claims its rect out of the pass
  self.trueColor = map.tileset.trueColor or nil

  -- Gen2: if the tileset has palMap/palColors from ROM extraction, bake a
  -- pre-colored atlas so tiles render with correct GBC palette colors.
  --
  -- Gated on the COLORS setting for the same reason SpriteRenderer's OBJ bake
  -- is: this IS the hardware colour, so it belongs to the modes that mean
  -- "show me the hardware", and the DMG/SGB-flavoured modes have to fall
  -- through to the raw sheet and their own shade treatment.  Unconditional, it
  -- made COLORS a no-op for every Gen2 tile on screen.
  local gen2Colors = PaletteFX.usesGen2BgPal() and gen2PalColors(map.tileset)
  if not self.gbcAtlas and map.tileset.palMap and #map.tileset.palMap > 0
      and gen2Colors and #gen2Colors > 0 then
    local key = gen2AtlasKey(map.tileset.image)
    local gen2img = getGen2Atlas(key, map.tileset.image, map.tileset.tilesPerRow,
                                 map.tileset.palMap, gen2Colors,
                                 TileRenderer.borrowStart(map.tileset))
    if gen2img then
      self.image = gen2img
      self.trueColor = true
      -- ...and hand the same tile->palette lookup to buildAnim, so the
      -- animated water/flower tiles that overdraw this atlas are baked with
      -- the palette their static neighbours got (see buildAnim's colorsFor)
      local palMap, palColors = map.tileset.palMap, gen2Colors
      gbcCtx = {
        -- the variant key, not just the tileset id: the derived shimmer
        -- textures cache alongside the atlas and must not survive a mode or
        -- time-of-day change either
        key = key,
        colorsFor = function(tile)
          return TileRenderer.gen2TileColors(palMap, palColors, tile)
        end,
      }
    end
  end

  local iw, ih = self.image:getDimensions()
  self.quads = {}
  local perRow = map.tileset.tilesPerRow
  for t = 0, (iw / 8) * (ih / 8) - 1 do
    self.quads[t] = love.graphics.newQuad((t % perRow) * 8,
                                          math.floor(t / perRow) * 8, 8, 8, iw, ih)
  end

  local def = map.def
  -- The map body measured in 8px tiles (each block is 4x4 tiles).  The tile
  -- layer is drawn windowed to the camera (see :ensureWindow) instead of
  -- baked into a whole-map SpriteBatch, so a map becoming visible -- a warp,
  -- a connection seam -- costs nothing to "build": there is no per-map batch
  -- construction that scales with map size, which is what stuttered.
  -- Tiles per block edge: 4 for a Gen 1/Gen 2 block (32px), 2 for a Gen 3
  -- metatile (16px).  Taken from the map object, which took it from the
  -- tileset -- the same number Map:tileAt divides by, so the renderer's window
  -- and the collision lookup cannot drift apart.
  self.blockTiles = map.blockTiles or 4
  self.bodyTilesW = def.width * self.blockTiles
  self.bodyTilesH = def.height * self.blockTiles

  -- Gen 3: one quad per 16x16 metatile out of two composited sheets, instead
  -- of one quad per 8x8 tile out of a single atlas.  When the bake is not
  -- available the renderer falls through to the tile path and the map draws
  -- as whatever its `blocks` table holds, which is blank rather than wrong.
  self.gen3 = TileRenderer.gen3SheetsFor(map.tileset, data,
                                         data and data.constants
                                         and data.constants.gen3Layout)
  if self.gen3 then
    local cols = require("src.render.Gen3Tiles").SHEET_COLS
    self.gen3Quads = {}
    for id = 0, self.gen3.metatiles - 1 do
      self.gen3Quads[id] = love.graphics.newQuad(
        (id % cols) * 16, math.floor(id / cols) * 16, 16, 16,
        self.gen3.width, self.gen3.height)
    end
  end
  -- Animated tiles overdraw the static window each frame.  Only the per-entry
  -- render spec (textures/sequence/gate) is kept here; the animated cells are
  -- gathered per camera window in :ensureWindow, so nothing here scales with
  -- map size either.  Entry order decides which entry claims a tile listed
  -- twice (the vanilla water-then-flower-then-spinner precedence).
  local anims, claimedBy = {}, {}
  local declared = map.tileset.animatedTiles
                   or TileRenderer.defaultAnimatedTiles(map.tileset)
  for _, spec in ipairs(declared) do
    local anim = buildAnim(spec, map.tileset.image, perRow, self.quads, gbcCtx)
    if anim then
      anims[#anims + 1] = anim
      for _, tile in ipairs(anim.tiles) do
        if claimedBy[tile] == nil then claimedBy[tile] = anim end
      end
    end
  end

  -- duplicate-tile alias remap (RED++ atlas only): [blockId][0-based cell]
  -- -> alias tile id (see PaletteFX.TILE_ALIASES / getGbcAtlas's bake)
  local aliasMap
  if gbcCtx then
    for _, al in ipairs(PaletteFX.TILE_ALIASES and PaletteFX.TILE_ALIASES[map.id] or {}) do
      aliasMap = aliasMap or {}
      local cells = aliasMap[al.block] or {}
      for ci in pairs(al.cells) do cells[ci] = al.alias end
      aliasMap[al.block] = cells
    end
  end
  self.aliasMap = aliasMap
  self.anims = anims
  self.claimedBy = claimedBy

  -- border-fill image is built lazily in :ensureBorderFill so a VOID FILL
  -- option change can swap trees/water/black without reloading the map
  self.borderFillMode = nil
  self.borderFill = nil

  return self
end

-- Bake a static repeating 32x32 of `block` into self.borderFill.
local function bakeBorderFill(self, block)
  local border = self.map.tileset.blocks[block + 1]
  if not border then return end
  -- 32x32 real pixels: a DPI-scaled canvas would bake the border block at a
  -- fractional texel size and the repeat-wrapped image would then tile at
  -- non-square pixels (#208, see src/render/PixelCanvas.lua)
  local canvas = require("src.render.PixelCanvas").new(32, 32)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(1, 1, 1, 1)
  for ty = 0, 3 do
    for tx = 0, 3 do
      local quad = self.quads[border[ty * 4 + tx + 1]]
      if quad then love.graphics.draw(self.image, quad, tx * 8, ty * 8) end
    end
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  local img = love.graphics.newImage(canvas:newImageData())
  img:setWrap("repeat", "repeat")
  img:setFilter("nearest", "nearest")
  self.borderFill = img
end

-- WATER void fill: the eight hshift frames of tile $14 (same cycle as map
-- water), wrap-tiled so the void scrolls in lockstep with on-map water.
local function ensureWaterBorderFill(self)
  if self.borderWaterTextures then return true end
  local map = self.map
  local perRow = map.tileset.tilesPerRow
  local colors, gbcKey
  if self.gbcAtlas and self.data then
    local group = PaletteFX.worldGroupAt(map.tileset.id, map.id, WATER_TILE)
    local groupColors = PaletteFX.worldGroupColors(
      self.data, map.tileset.id, map.id, nil)
    colors = group and groupColors and groupColors[group + 1] or nil
    gbcKey = gbcKeyFor(map.id)
  end
  local textures = getShiftVariants(map.tileset.image, perRow, WATER_TILE,
                                    colors, gbcKey)
  if not textures then return false end
  for _, img in ipairs(textures) do
    img:setWrap("repeat", "repeat")
    img:setFilter("nearest", "nearest")
  end
  self.borderWaterTextures = textures
  return true
end

-- (re)build the repeating border image when the VOID FILL mode or tileset
-- choice changes.  OVERWORLD "black" leaves borderFill nil and draws a
-- solid clear; "water" keeps the live hshift textures instead of a bake.
function TileRenderer:ensureBorderFill()
  local block = borderBlockFor(self.map)
  local mode = block == false and "black"
              or ((self.map.def.tileset == "OVERWORLD")
                  and (TileRenderer.voidFill or "trees")
                  or "map")
  local ready = (mode == "black")
                or (mode == "water" and self.borderWaterTextures)
                or (mode ~= "water" and mode ~= "black" and self.borderFill)
  if self.borderFillMode == mode and ready then return end
  if self.borderFill and self.borderFill.release then
    pcall(self.borderFill.release, self.borderFill)
  end
  self.borderFill = nil
  -- shared shift-variant cache: drop the reference only, never release
  self.borderWaterTextures = nil
  self.borderFillMode = mode
  if mode == "black" or block == false or block == nil then return end
  if mode == "water" then
    if ensureWaterBorderFill(self) then return end
    -- headless / missing pixels: fall back to the static water block bake
  end
  pcall(bakeBorderFill, self, block)
end

-- tile the border block across the whole view (world-aligned so it
-- meshes seamlessly with the ring batch)
function TileRenderer:drawBorderFill(camX, camY, vw, vh)
  self:ensureBorderFill()
  if self.borderFillMode == "black" then
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, vw, vh)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  if self.trueColor then PaletteFX.markTrueColor(0, 0, vw, vh) end
  local x, y = math.floor(camX), math.floor(camY)
  -- one reused Quad per renderer, mutated in place: this runs every
  -- overworld frame, so allocating a fresh Quad here churned the GC
  local q = self.borderQuad
  if self.borderFillMode == "water" and self.borderWaterTextures then
    local step = math.floor(animFrame / ANIM_PERIOD) % #WATER_OFFSETS + 1
    local tex = self.borderWaterTextures[WATER_OFFSETS[step] + 1]
    if not tex then return end
    if q then
      q:setViewport(x, y, vw, vh, 8, 8)
    else
      q = love.graphics.newQuad(x, y, vw, vh, 8, 8)
      self.borderQuad = q
    end
    love.graphics.draw(tex, q, 0, 0)
    return
  end
  if not self.borderFill then return end
  if q then
    q:setViewport(x, y, vw, vh, 32, 32)
  else
    q = love.graphics.newQuad(x, y, vw, vh, 32, 32)
    self.borderQuad = q
  end
  love.graphics.draw(self.borderFill, q, 0, 0)
end

-- GB OBJ-to-BG priority: sprites show through BG color 0 and hide under
-- colors 1-3.  Tall-grass overdraw needs the same rule, otherwise the
-- tile's white gaps paint opaque boxes over the sprite's feet.
local color0KeyShader -- false = unavailable
local function getColor0KeyShader()
  if color0KeyShader ~= nil then return color0KeyShader or nil end
  local ok, sh = pcall(love.graphics.newShader, [[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc) * color;
      // same shade-0 cutoff PaletteFX uses (DMG white / lightest gray)
      if (p.r > 0.83 && p.g > 0.83 && p.b > 0.83) p.a = 0.0;
      return p;
    }
  ]])
  color0KeyShader = ok and sh or false
  return color0KeyShader or nil
end

-- RED++ (COLORS=ADVANCED): the color-0 key, BAKED instead of tested for.
local function getKeyedTile(self, tile)
  local ctx = self.gbcCtx
  local cached = self.gbcKeyed[tile]
  if cached ~= nil then return cached or nil end
  local img = false
  if ctx.groupColors and love.image and love.image.newImageData then
    local group = PaletteFX.worldGroupAt(ctx.tilesetId, ctx.mapId, tile)
    local colors = group and ctx.groupColors[group + 1]
    local src = Assets.imageData(ctx.imagePath)
    local ox = (tile % ctx.perRow) * 8
    local oy = math.floor(tile / ctx.perRow) * 8
    local out = love.image.newImageData(8, 8)
    for py = 0, 7 do
      for px = 0, 7 do
        local r, g, b, a = src:getPixel(ox + px, oy + py)
        -- read shade 0 off the RAW sheet, on recolorSample's own cutoff, so
        -- the keyed pixels are exactly the ones the shader path keys
        local shade0 = r > 0.83
        r, g, b, a = recolorSample(r, g, b, a, colors)
        out:setPixel(px, py, r, g, b, shade0 and 0 or a)
      end
    end
    img = love.graphics.newImage(out)
  end
  self.gbcKeyed[tile] = img
  return img or nil
end

function TileRenderer:drawCellBottomRaw(cx, cy, camX, camY)
  local ty = cy * 2 + 1
  for i = 0, 1 do
    local tx = cx * 2 + i
    local tile = self.map:tileAt(tx, ty)
    local keyed = tile and self.gbcCtx and getKeyedTile(self, tile)
    if keyed then
      love.graphics.draw(keyed, tx * 8 - camX, ty * 8 - camY)
    else
      local quad = self.quads[tile]
      if quad then
        love.graphics.draw(self.image, quad, tx * 8 - camX, ty * 8 - camY)
      end
    end
  end
end

-- redraw a cell's bottom tile row (tall grass hides the lower half of
-- sprites standing in it, like the GB sprite-priority trick)
function TileRenderer:drawCellBottom(cx, cy, camX, camY)
  -- the RED++ path is pre-keyed; the white test would be a no-op there at
  -- best, and a false hit on some other group's near-white color 0 at worst
  local shader = not self.gbcCtx and getColor0KeyShader() or nil
  if shader then love.graphics.setShader(shader) end
  self:drawCellBottomRaw(cx, cy, camX, camY)
  if shader then love.graphics.setShader() end
end

-- queue the same bottom tile row for the post-zone sprite-redraw pass
-- (GBC mode: OBP-baked sprites replay after the zone shader, so the
-- grass patch that hides their feet must replay over them, colorized
-- with the map's palette and color-0 keyed)
function TileRenderer:markCellBottomRedraw(cx, cy, camX, camY, colors)
  local ty = cy * 2 + 1
  for i = 0, 1 do
    local tx = cx * 2 + i
    local quad = self.quads[self.map:tileAt(tx, ty)]
    if quad then
      PaletteFX.markSpriteRedraw(self.image, quad, tx * 8 - math.floor(camX),
                                 ty * 8 - math.floor(camY), 1, colors, true)
    end
  end
end

local WINDOW_MARGIN = 8 -- tiles of slack kept around the view between refills

function TileRenderer:ensureWindow(camX, camY, vw, vh)
  local W, H = self.bodyTilesW, self.bodyTilesH
  vw = vw or W * 8 -- a nil view (headless draw) means the whole body
  vh = vh or H * 8
  -- visible body-tile range (8px tiles), clamped to the map body
  local tx0 = math.min(W, math.max(0, math.floor(camX / 8)))
  local ty0 = math.min(H, math.max(0, math.floor(camY / 8)))
  local tx1 = math.max(0, math.min(W, math.floor((camX + vw) / 8) + 1))
  local ty1 = math.max(0, math.min(H, math.floor((camY + vh) / 8) + 1))
  local win = self.win
  if win and tx0 >= win.tx0 and ty0 >= win.ty0
     and tx1 <= win.tx1 and ty1 <= win.ty1 then
    return -- still inside the last fill
  end
  -- refill with margin so the next few scrolled pixels stay covered
  tx0 = math.max(0, tx0 - WINDOW_MARGIN)
  ty0 = math.max(0, ty0 - WINDOW_MARGIN)
  tx1 = math.min(W, tx1 + WINDOW_MARGIN)
  ty1 = math.min(H, ty1 + WINDOW_MARGIN)
  if self.gen3 then
    -- one quad per CELL into each of the two layer batches.  The tile-grid
    -- bounds above are still the right window -- a Gen 3 cell is two tiles
    -- wide, so dividing by blockTiles gives the cell range directly.
    if not self.winBatch then
      self.winBatch = love.graphics.newSpriteBatch(self.gen3.bottom, 1024, "dynamic")
      self.winBatchTop = love.graphics.newSpriteBatch(self.gen3.top, 1024, "dynamic")
    end
    self.winBatch:clear()
    self.winBatchTop:clear()
    local map = self.map
    local n = self.blockTiles
    local cx0, cy0 = math.floor(tx0 / n), math.floor(ty0 / n)
    local cx1, cy1 = math.ceil(tx1 / n), math.ceil(ty1 / n)
    for cy = cy0, cy1 - 1 do
      for cx = cx0, cx1 - 1 do
        local id = map:blockAt(cx, cy)
        local quad = id and self.gen3Quads[id]
        if quad then
          local wx, wy = cx * 16, cy * 16
          self.winBatch:add(quad, wx, wy)
          self.winBatchTop:add(quad, wx, wy)
        end
      end
    end
    self.win = { tx0 = tx0, ty0 = ty0, tx1 = tx1, ty1 = ty1 }
    return
  end

  if not self.winBatch then
    self.winBatch = love.graphics.newSpriteBatch(self.image, 1024, "dynamic")
  end
  self.winBatch:clear()
  local anims = self.anims
  for _, anim in ipairs(anims) do
    if not anim.batch then
      anim.batch = love.graphics.newSpriteBatch(anim.textures[1], 256, "dynamic")
    end
    anim.batch:clear()
  end
  local map, quads = self.map, self.quads
  local claimedBy, aliasMap = self.claimedBy, self.aliasMap
  local n = self.blockTiles
  for ty = ty0, ty1 - 1 do
    local by = math.floor(ty / n)
    local tyn = ty % n
    for tx = tx0, tx1 - 1 do
      local blockId = map:blockAt(math.floor(tx / n), by)
      local block = map.tileset.blocks[blockId + 1]
      if block then
        local ci = tyn * n + (tx % n)
        local tile = block[ci + 1]
        local remap = aliasMap and aliasMap[blockId]
        if remap and remap[ci] then tile = remap[ci] end
        local wx, wy = tx * 8, ty * 8
        local quad = quads[tile]
        if quad then self.winBatch:add(quad, wx, wy) end
        local anim = claimedBy[tile]
        if anim then
          if anim.quadFor then
            anim.batch:add(anim.quadFor(tile), wx, wy)
          else
            anim.batch:add(wx, wy)
          end
        end
      end
    end
  end
  self.win = { tx0 = tx0, ty0 = ty0, tx1 = tx1, ty1 = ty1 }
end

-- draw the static tile window, then its animated overdraw, at the camera offset
function TileRenderer:drawWindow(camX, camY, vw, vh)
  self:ensureWindow(camX, camY, vw, vh)
  if self.winBatch then
    love.graphics.draw(self.winBatch, -math.floor(camX), -math.floor(camY))
  end
  self:drawAnimated(camX, camY)
end

-- animated overdraw at the current step, over the static window batch.  The
-- cells were gathered for the current camera window by :ensureWindow, so this
-- only ever touches on-screen animated tiles.
function TileRenderer:drawAnimated(camX, camY)
  local anims = self.anims
  if not anims then return end
  local x, y = -math.floor(camX), -math.floor(camY)
  for _, anim in ipairs(anims) do
    local batch = anim.batch
    if batch then
      if anim.gate then
        -- a gated entry has only the two frames the asm has (patch /
        -- restore-to-static); when the gate is shut draw nothing so the
        -- already-static window tile shows through unchanged
        if gateOpen(anim.gate) then love.graphics.draw(batch, x, y) end
      else
        local step = math.floor(animFrame / anim.period) % #anim.sequence + 1
        batch:setTexture(anim.textures[anim.sequence[step]])
        love.graphics.draw(batch, x, y)
      end
    end
  end
end

-- the drawn extent of one batch in world-canvas pixels; `blocks` is the
-- ring width the batch reaches past the map body on every side
function TileRenderer:markTrueColor(camX, camY, blocks)
  local def = self.map.def
  PaletteFX.markTrueColor(-math.floor(camX) - blocks * 32,
                          -math.floor(camY) - blocks * 32,
                          (def.width + 2 * blocks) * 32,
                          (def.height + 2 * blocks) * 32)
end

function TileRenderer:draw(camX, camY, vw, vh)
  if self.trueColor then self:markTrueColor(camX, camY, BORDER_BLOCKS) end
  self:drawWindow(camX, camY, vw, vh)
end

-- The Gen 3 TOP layer, drawn AFTER the sprites.
--
-- This is the half of the metatile the player walks behind: treetops, the
-- upper storey of a building, the far rail of a bridge.  The overworld calls
-- it once the entity pass is done; on a Gen 1/Gen 2 map it returns false and
-- does nothing, so the call site needs no generation test.
--
-- Nothing already here can stand in for it.  drawCellBottom redraws ONE
-- cell's lower tile row to hide a sprite's feet in tall grass -- a per-cell
-- exception -- where a Gen 3 top layer applies to every cell on the map.
function TileRenderer:drawAbove(camX, camY, vw, vh)
  if not self.gen3 then return false end
  self:ensureWindow(camX, camY, vw, vh)
  if self.winBatchTop then
    love.graphics.draw(self.winBatchTop, -math.floor(camX), -math.floor(camY))
  end
  return true
end

-- Does this map draw anything above the sprites?  Lets a caller skip the
-- state changes around the call on the generations that do not.
function TileRenderer:hasAboveLayer()
  return self.gen3 ~= nil
end

-- body only, for connected-map strips.  Identical to :draw now that the
-- border ring is served by :drawBorderFill for the current map too -- the
-- only remaining difference is the trueColor mark extent.
function TileRenderer:drawMapOnly(camX, camY, vw, vh)
  if self.trueColor then self:markTrueColor(camX, camY, 0) end
  self:drawWindow(camX, camY, vw, vh)
end

local function safeRelease(o)
  if o and o.release then pcall(o.release, o) end
end

-- Release only the GPU objects this instance built and uniquely owns: the
-- two SpriteBatches, the border-fill image and its quad, the per-tile
-- quads, and the animated-overdraw batches.  Deliberately leaves the
-- tileset atlas (self.image, shared through Assets/imageCache) and the
-- animation textures (shared module caches) alone -- other maps still use
-- them.  Used by :rebuild before it swaps in fresh batches, and by
-- :release on eviction.
function TileRenderer:releaseBatches()
  safeRelease(self.winBatch); self.winBatch = nil
  -- the Gen 3 top-layer batch lives and dies with the bottom one; the two
  -- SHEETS behind them are module-cached per tileset pair and are not
  -- released here, exactly as the animated tile textures are not
  safeRelease(self.winBatchTop); self.winBatchTop = nil
  safeRelease(self.borderFill); self.borderFill = nil
  safeRelease(self.borderQuad); self.borderQuad = nil
  -- shared shift-variant cache; only drop the reference
  self.borderWaterTextures = nil
  self.borderFillMode = nil
  self.win = nil
  if self.quads then
    for _, q in pairs(self.quads) do safeRelease(q) end
    self.quads = nil
  end
  if self.anims then
    for _, a in ipairs(self.anims) do
      safeRelease(a.batch); a.batch = nil
      -- a.textures are shared, module-cached: never released here
    end
  end
end

-- Full teardown for eviction (MapLoader.evict): the owned batches, plus
-- the RED++ per-map recolored atlas, which -- unlike the plain tileset
-- atlas -- is unique to this map (gbcAtlasCache is keyed by map id).
function TileRenderer:release()
  self:releaseBatches()
  if self.gbcKeyed then
    -- baked per instance, shared with nobody (see getKeyedTile)
    for _, img in pairs(self.gbcKeyed) do safeRelease(img) end
    self.gbcKeyed = nil
    self.gbcCtx = nil
  end
  if self.gbcAtlas and self.image then
    local key = self.gbcAtlasKey or (self.map.tileset.image .. gbcKeyFor(self.map.id))
    if gbcAtlasCache[key] == self.image then gbcAtlasCache[key] = nil end
    self.gbcAtlasKey = nil
    safeRelease(self.image)
    self.image = nil
    self.gbcAtlas = nil
  end
  self.anims = nil
end

-- rebuild after a block change (Cut trees, card-key doors).  The tile layer
-- is read live from the map on every window fill, so a block swap only needs
-- the cached window dropped -- the next draw re-reads the changed blocks.  No
-- SpriteBatch is reconstructed; that is the whole point of the windowed draw.
function TileRenderer:rebuild()
  self.win = nil
end

-- drop every atlas and every derived animation texture so the next
-- TileRenderer.new re-resolves through the asset search path.  Live
-- instances keep the batches they already built; MapLoader.invalidateAll
-- is what drops those (14 §cache-invalidation contract).
function TileRenderer.invalidate()
  imageCache = {}
  shiftVariants = {}
  frameImages = {}
  toggleImages = {}
  stripData = {}
  gen2AtlasCache = {}
  -- THE GEN 1 BAKE AND THE ANIMATED PAGES TOO, which this did not drop.
  --
  -- `gbcAtlasCache` is keyed on the image and the MAP -- not on the colour
  -- mode -- so a mode change neither missed the cache nor cleared it, and a
  -- Gen 1 world went on drawing in the palette it was first baked with. It
  -- survived because nothing changed the mode mid-session until the map
  -- editor grew a COLOURS control; the launcher sets it before the game
  -- builds anything.
  gbcAtlasCache = {}
  atlasFrames = {}
end

Assets.register(TileRenderer.invalidate)

return TileRenderer
