-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SINNOH, DRAWN.
--
-- Platinum has no tileset: its world is 666 land chunks, each a 32 x 32 tile
-- square carrying an NSBMD mesh and a texture set named by the map's own area
-- record. The import stage puts all of that in the cache (see Gen4Terrain);
-- this is what turns it into pixels, and it replaces `TILESET_GEN4_STANDIN` --
-- one flat colour per terrain class, which is a legible plan of a map and is
-- not Sinnoh.
--
-- A CHUNK IS BAKED ONCE, TOP-DOWN, INTO A CANVAS, and the canvas is what the
-- map draws. That is not a shortcut around a 3D view; it is the same thing
-- `Gen3Tiles` already does with its metatile sheets, for the same reason: the
-- geometry does not change, so rasterising it every frame is work done over
-- and over to arrive at the same 512 x 512 picture. When a real camera exists
-- the meshes are already here and this becomes the flat case of it.
--
-- ONE PIXEL PER WORLD UNIT, which is what makes everything else line up: a
-- tile is 16 units and the engine draws tiles at 16 pixels, so the collision
-- grid, the warps and the sprites land on the ground without a second scale to
-- keep in step.
--
-- THE PROJECTION IS ORTHOGRAPHIC AND THE CHUNK'S ORIGIN IS ITS CENTRE.
-- `posScale` is 32 and a chunk's vertices run about -8..+8, so it spans
-- -256..+256 of its 512-unit square -- read as 0..512 seven eighths of the
-- mesh falls off the edge, which looks like a broken decoder and is
-- arithmetic. World +z is south, and a chunk bakes into a CANVAS, where clip
-- y counts the other way round -- see `topDown` for the whole of it.

local Assets = require("src.render.Assets")
local Gen4Model = require("src.render.Gen4Model")
local Logger = require("src.core.Logger")
local Gen4TexAnim = require("src.render.Gen4TexAnim")
local Gen4Camera = require("src.render.Gen4Camera")
local Gen4Shade = require("src.render.Gen4Shade")
local Gen4View = require("src.render.Gen4View")

local Gen4Ground = {}
Gen4Ground.__index = Gen4Ground

-- How many baked chunks to keep. Each is a 512 x 512 canvas -- a megabyte of
-- colour and its depth buffer -- and a screen shows at most four, so this is
-- room to walk about in without rebaking and a bounded cost.
Gen4Ground.CACHE = 16

-- How many chunks may bake in one frame.
--
-- One was too few: a screen shows up to four, a map entry needs all of them,
-- and at one a frame the other three showed the stand-in for three frames --
-- which with the old early-return showed nothing at all. Four is the whole
-- visible set, so a map entry pays one hitch and then nothing; walking into a
-- new chunk pays for that one.
Gen4Ground.BAKES_PER_FRAME = 4

-- The depth range the height is mapped into, and it is a PRECISION choice
-- rather than a safety margin.
--
-- Four thousand was the first guess and it spent almost all of the depth
-- buffer on heights that do not occur: a chunk's own geometry spans tens of
-- units, so two nearly coplanar surfaces -- a floor and the mat on it -- came
-- out a couple of millionths apart in clip space and fought, which reads on
-- screen as alternating rows of one surface and the other. A thousand and
-- twenty-four still clears anything in the cartridge (Mount Coronet is
-- hundreds) and gives four times the resolution to tell them apart.
local DEPTH_RANGE = 1024

-- An orthographic top-down matrix, in the same row-major layout
-- `Gen4Model.perspective` returns.
--
-- CLIP Y COUNTS THE OTHER WAY INTO A CANVAS, and this row used to be -1/half,
-- which baked EVERY CHUNK IN SINNOH UPSIDE DOWN.  Reported from play as "the
-- map ... seems like its upside down and maps arent properly aligned nor
-- walkable areas", and the second half of that sentence is the first half's
-- consequence: the collision grid was never flipped, so a house you could see
-- at the bottom of the screen had its walls at the top and its door on the
-- wrong side of it.
--
-- `Gen4Title` already carries this trap written up -- "Giratina is showing ...
-- upside down" -- and its `FLIP_Y`; a custom `position()` returns clip
-- coordinates directly and so bypasses the projection LOVE would set up for
-- the target, and a canvas's framebuffer counts its rows the opposite way from
-- the screen.  This file was written without that compensation.
--
-- MEASURED RATHER THAN EYEBALLED, on Twinleaf Town (T01, matrix 0, chunk cell
-- 3,27):
--
--   * the four houses' collision footprints are 5x5 at the top-left and
--     bottom-right and 4x4 at the top-right and bottom-left; the baked picture
--     had the 5x5 pair at bottom-left and top-right -- mirrored
--   * all four of the map's warps sit on the BOTTOM row of their own house's
--     footprint, which is where a door is; the door model (build_model 67,
--     placed four times) sits at z = house z + 13, so +z is south in the
--     grid's terms as well as the cartridge's
--   * `Gen4Ground:heightsAt` already reads tile y as +z, so the height lookup
--     and the picture disagreed about which way south was
--   * the asymmetric gaps in the town's border (rows 1-2 only, never rows
--     29-30) rendered at the bottom of the screen
--
-- A vertical flip also reverses triangle winding.  That costs nothing here
-- because `Gen4Model:draw` sets cull mode "none"; if culling is ever turned on
-- for the ground, the winding has to be reversed with it.
--
-- AND IT IS NO LONGER STRAIGHT DOWN.  `Gen4Camera` carries Platinum's own
-- seventeen field cameras; every one of them is TILTED, between 40.6 and 78.4
-- degrees, and the map header says which.  This projects at that pitch as an
-- OBLIQUE camera:
--
--   screenX = x                       screenY = z - y * cot(pitch)
--
-- so the ground plane still maps one to one -- the tile grid, the collision
-- and every sprite stay exactly where they were, and nothing above this file
-- has to change -- while HEIGHT leans up the screen, which is what puts a
-- house's front and a cliff's face back on it.  `Gen4Camera` has the whole
-- argument, including how far that is from the cartridge's perspective one
-- (0.5% on the depth the screen covers; a tenth at its two edges).
--
-- THE CANVAS GROWS UPWARDS BY `leanPx`, because that is where the leaning
-- geometry goes: a chunk's ground still occupies rows leanPx..leanPx+512 and
-- anything standing on it reaches above that.  The blit takes the same leanPx
-- back off, so the ground lands where it always did.  Chunks are drawn north
-- to south, which is already the loop's order and is the order that has to
-- hold once one chunk's towers can overlap the next one's ground.
--
-- `MAX_RISE` is how much height the extra rows allow for.  Measured against
-- the build models this is generous -- the tallest houses are about 160 units
-- -- and terrain that climbs more than this inside one chunk loses its top few
-- rows rather than drawing over its neighbour.
local MAX_RISE = 384

-- HOW HIGH A CHARACTER REACHES, in the units the models are built in.
--
-- A tile is 16 units and an overworld sprite stands about two of them, so
-- geometry above 32 is over everybody's head.  That is the whole rule behind
-- the canopy: the part of a building higher than this can be painted AFTER the
-- sprites without ever covering one that is standing in front of it, and
-- painting it there is what lets somebody walk behind the house.
--
-- Approximate on purpose.  The exact answer depends on how far north of the
-- building the character is standing, which is a per-sprite comparison this
-- does not make; what it buys instead is occlusion at all, for one extra bake
-- and one extra blit, with no per-frame model draws.
local CANOPY_Y = 32
-- The band the canopy pass leaves to the sprite, in world units: from the
-- player's tile edge (KEEP_FEET south of the feet) to KEEP_BEHIND north of
-- them. See the cut draw in `livePass`.
local KEEP_BEHIND, KEEP_FEET = 40, 8

-- HOW TALL A THING HAS TO BE FOR THE HEIGHT CUT TO MEAN ANYTHING.
--
-- The cut paints the part of an object ABOVE head height over the sprites, so
-- it can only ever describe something taller than a character.  Measured over
-- all 590 building models, 338 of them -- 57.3% -- top out below `CANOPY_Y`,
-- and for every one of those the cut has nothing to say: `shelf01` ends at
-- exactly 32.00 and fails on the shader's `<=`, `table_l01` at 30,
-- `machine_pc01` at 24.16.
--
-- Reported from play: *"many indoor objects when walked behind dont mask the
-- player but houses do perfectly"*.  Houses are 71 to 91 and the cut serves
-- them well; furniture is 17 to 32 and the cut cannot serve it at all.
--
-- So a SHORT prop is sorted instead of cut: if the player is behind it, the
-- whole thing is painted over them; if they are in front, it is not painted at
-- all.  That is the y-sort Gen 1-3 has always used (`gen3AboveTopLayer`), and
-- it is right for exactly the objects the cut is wrong for.
--
-- The proper answer is neither -- it is the depth buffer, which the cartridge
-- uses and which pass 30's `beginWorld`/`drawSprite`/`endWorld` makes possible.
-- That needs the entity pass drawing into the world's target, which is a
-- change to the overworld's draw ORDER with a black-frame failure mode, in a
-- 730 KB function with two draw sites and one close point.  This is the part
-- that can be made correct without it.
local SORTED_BELOW = CANOPY_Y

-- ...AND IT IS THE CARTRIDGE'S CAMERA NOW, not an oblique approximation of it.
--
-- The oblique kept the ground plane one to one and leaned height up the screen
-- by cot(pitch).  That was chosen so no sprite had to move, and it is what made
-- the world read as flat: the cartridge COMPRESSES the ground.
--
-- `Camera_AdjustPositionAroundTarget` puts the eye due south of its target and
-- above it, which gives screen axes `right = (1,0,0)` and
-- `up = (0, cos p, -sin p)`, and therefore
--
--     screenX = x                screenY = z * sin(pitch) - y * cos(pitch)
--
-- Ground depth scales by sin, height by cos.  The oblique's 1 and cot are that
-- same picture stretched vertically by 1/sin -- 16.6% at DEFAULT's 59 degrees,
-- 30.4% at an interior's 50 -- and a world stretched a third taller than it
-- should be is a world that does not read as tilted at all.
--
-- ONLY TWO COEFFICIENTS CHANGE.  Row 2 is the screen-Y row: the height term
-- goes from `-2*lean/height` to `-2*cos/height` and the ground term from
-- `2/height` to `2*sin/height`.  At pitch 90 that is sin = 1, cos = 0, which
-- collapses to exactly the straight-down matrix above it -- so the OPTIONS
-- row's 90 is still the flat bake, with no second code path.
--
-- ROW 3, THE DEPTH ROW, IS LEFT ALONE and that is deliberate rather than
-- lazy: it reads `-(y + lean*z)/DEPTH_RANGE`, and multiplying through by
-- sin(pitch) gives `-(y*sin + z*cos)/(DEPTH_RANGE*sin)` -- the true view-axis
-- depth, scaled by a positive constant.  A depth test only cares about order,
-- so the row was already right for every pitch.
local function projection(half, sinP, cosP, height)
  if cosP <= 1e-6 then
    return {
      1 / half, 0, 0, 0,
      0, 0, 1 / half, 0,
      0, -1 / DEPTH_RANGE, 0, 0,
      0, 0, 0, 1,
    }, 0
  end
  local lean = cosP / sinP
  -- The rows the chunk's own ground occupies are `2*half*sin`; everything
  -- above them is room for whatever stands on it.
  local leanPx = height - 2 * half * sinP
  return {
    1 / half, 0, 0, 0,
    0, -2 * cosP / height, 2 * sinP / height, leanPx / height,
    0, -1 / DEPTH_RANGE, -lean / DEPTH_RANGE, 0,
    0, 0, 0, 1,
  }, leanPx
end

-- ---------------------------------------------------------------------------

-- forMap(map, data) -> a ground, or nil when this is not a Gen 4 map with
-- terrain in the cache. Nil is the ordinary answer for every other
-- generation and for a Platinum cache imported before the terrain stage, and
-- the caller falls back to the tile path it always used.
function Gen4Ground.forMap(map, data)
  local terrain = data and data.gen4_terrain
  local def = map and map.def
  if not (terrain and terrain.chunks and terrain.matrices and def) then return nil end

  local grid = terrain.matrices[def.layout]
  if not (grid and grid.land) then return nil end

  -- BY THE CARTRIDGE'S OWN NAME FIRST.  `gen4_terrain.maps` is keyed by the
  -- internal names in `mapname.bin` -- `T01R0201` -- while a map reached
  -- through `Data`'s alias table carries the Game Boy-style respelling
  -- `T_01R_0201` in `id` and the original in `sourceId`.  Asking for `id`
  -- alone missed every aliased map and kept the stand-in; see the comment on
  -- `aliasMap` in `src/core/Data.lua`.
  local record = terrain.maps
    and (terrain.maps[def.sourceId or def.id] or terrain.maps[def.id])
  local set = record and terrain.sets and terrain.sets[record.texture]
  if not set then
    -- The mesh without its textures is a grey solid, which is worse than the
    -- stand-in it would be replacing.
    Logger.warn("gen4 ground: %s names no texture set; keeping the stand-in",
                tostring(def.id))
    return nil
  end

  local self = setmetatable({}, Gen4Ground)
  self.terrain = terrain
  -- THE PERMISSION GRIDS, TAKEN FROM `data` RATHER THAN A GLOBAL.
  --
  -- `_G.Game` is nil in a real session -- that is a trap this port has already
  -- paid for once in the Gen 3 world -- and this constructor is handed `data`
  -- outright, so there is nothing to reach around for.
  self.perms = data.gen4_map_permissions
  self.def = def
  self.grid = grid
  -- EACH CHUNK'S ALTITUDE, which is how far up the cartridge draws it.
  --
  -- Reported from play at Oreburgh: *"map boundaries arent at the proper
  -- height"* -- the chunks around the city stood at the wrong level with the
  -- void showing through the seams.
  --
  -- `LandDataManager_CalculateRenderingPosition` (pokeplatinum
  -- src/overlay005/land_data.c) puts every loaded chunk's model and props at
  -- `y = altitude * MAP_OBJECT_TILE_SIZE / 2` -- eight units a step -- read
  -- from the matrix's altitude section. `Gen4Maps.matrix` has parsed that
  -- section from the start and nothing drew with it, so every chunk sat at 0.
  --
  -- It matters most for the FILLER chunks the overworld reuses -- the sea,
  -- the mountain mass -- which are modelled flat at 0 and lifted into place
  -- by this number alone: chunk 177 at altitude 4 meets its neighbour's
  -- ground at 32 exactly. MEASURED over matrix 0: with the lift, 385 seams
  -- between chunks of different altitude go from 13.4% matching to 55.7%, and
  -- every other scale makes them worse.
  --
  -- RENDERING ONLY, as on the cartridge: `TerrainCollisionManager` reads the
  -- BDHC with no altitude added, so the walkable height is untouched.
  --
  -- Taken from the terrain grid when a newer import carried it there, and
  -- otherwise from `gen4_map_matrices`, which has held it in every cache.
  local matrix = data.gen4_map_matrices and data.gen4_map_matrices[def.layout]
  self.altitudes = grid.altitudes
    or (matrix and matrix.width == grid.width and matrix.height == grid.height
        and matrix.altitudes) or nil
  -- ...AND THE HIDDEN PATHS, which change both: Spring Path's chunks are drawn
  -- as filler at altitude 2 until it is unlocked, and Seabreak Path's appear
  -- once Oak's Letter has been used. See Gen4HiddenPaths.
  do
    local okG, Game = pcall(require, "src.core.Game")
    local save = okG and type(Game) == "table" and Game.save or nil
    local Gen4HiddenPaths = require("src.world.Gen4HiddenPaths")
    self.grid, self.altitudes =
      Gen4HiddenPaths.grid(def.layout, self.grid, self.altitudes, save)
    grid = self.grid
  end
  self.set = set
  self.chunkPx = (terrain.chunkUnits or 512) * (terrain.pixelsPerUnit or 1)
  self.half = (terrain.chunkUnits or 512) / 2
  -- THE MAP'S OWN CAMERA, by the `cameraType` byte in its header.  A cache
  -- imported before that byte was carried through has no `cameraType`, and
  -- `Gen4Camera.forType` answers DEFAULT for it -- which is the right answer
  -- for the 189 headers that use it and a tilted one for the rest, rather than
  -- the straight-down view that was never any map's.
  self:applyCamera()
  -- Where this map's corner sits in its matrix, in pixels. A map cropped out
  -- of a shared matrix draws the same chunks; it just starts part way in.
  self.offsetX = (def.originX or 0) * 16
  self.offsetY = (def.originY or 0) * 16
  -- WHICH CHUNK THIS MAP THINKS IT IS STANDING ON, said once per map load.
  --
  -- Twinleaf bakes land chunk 4. The ROM's own header layer says header 411
  -- owns exactly one cell, (3,27), which is land chunk 0 -- and chunk 4 belongs
  -- to header 334, a different map. Chunk 0 carries eight props; chunk 4 carries
  -- none, which is why the town has no houses and reads as flat.
  --
  -- Every value this depends on has been checked in the CACHE and is right:
  -- `T01` records header 411, layout 0, originX 96, originY 864, and
  -- 96 * 16 / 512 is 3. So the wrong answer is being produced at RUNTIME from
  -- correct data, and this prints the four numbers that decide it rather than
  -- inferring them from the outside a fourth time.
  Logger.info("gen4 ground: %s layout=%s origin=(%s,%s) tiles -> offset=(%d,%d)px "
              .. "chunkPx=%d grid=%dx%d",
              tostring(def.id), tostring(def.layout),
              tostring(def.originX), tostring(def.originY),
              self.offsetX, self.offsetY, self.chunkPx,
              grid.width or -1, grid.height or -1)
  self.baked = {}
  self.canopies = {}
  self.order = {}
  -- The building models, by index into `build_model.narc`, built on first use.
  -- An absent set is not a failure: a cache imported before the buildings were
  -- extracted draws the floors and nothing on them, which is what it did
  -- before and is better than refusing to draw the ground.
  self.buildingSet = ((data.gen4_models or {}).sets or {}).buildings
  self.buildings = {}
  -- THE OBJECTS THAT ARE MODELS RATHER THAN BILLBOARDS -- every sign and every
  -- mailbox in Sinnoh.  Absent on a cache imported before `fldeff.narc` was
  -- read, which draws the map without its signs exactly as it did before rather
  -- than refusing to draw at all.  See `src/import/Gen4ObjectGfx.lua` for the
  -- nine-row table that names them, and for why "no sprite" never meant "no
  -- picture".
  self.fldeffSet = ((data.gen4_models or {}).sets or {}).fldeff
  self.fieldModels = {}
  -- Built on first use rather than here: it needs `heightAt`, which needs the
  -- chunk store, and a map that is never drawn should not open it.
  self.signposts = nil
  -- THE AREA LIGHT THIS MAP IS LIT BY.
  --
  -- `record.areaLight` is the member of `/data/arealight.narc` the map's own
  -- area record names, 0..2 across the 593 maps.  It is held rather than
  -- resolved here because the member holds FIFTEEN templates and which one is
  -- live depends on the clock; `applyLight` picks the band.
  self.arealight = data and data.gen4_arealight
  self.lightMember = record.areaLight
  -- WHETHER THIS MAP CAN SEE THE SKY, by the cartridge's own rule.
  --
  -- Reported from play: *"indoors no skybox should show"*.  The answer is not
  -- a new judgement -- `AreaDataManager_IsOutdoorsLighting` (area_data.c) is
  -- `areaLightArchiveID == 0 || == 3`, and the extractor already stores it per
  -- map as `outdoors`.  110 of the 593 maps are outdoors and 483 are not,
  -- which is the same 110 that sit on light member 0.
  --
  -- DERIVED from the member when the field is absent, so a cache imported
  -- before `outdoors` was carried still hides the sky indoors instead of
  -- needing a re-import.  Only a cache with neither leaves it nil, and nil
  -- draws the sky -- which is what it did before.
  self.outdoors = record.outdoors
  if self.outdoors == nil and self.lightMember then
    self.outdoors = (self.lightMember == 0 or self.lightMember == 3)
  end
  self:applyLight()
  -- The texture animations, by the name of the model they drive.  `bm_anime`
  -- and `build_model` are separate archives, so this is the one place the two
  -- meet at run time -- and it is built once per map rather than searched.
  self.animsByName = {}
  -- ...AND BY MEMBER, which is what a one-shot names.  `animsByName` keys on
  -- the model name a texture animation drives; a joint one-shot is identified
  -- by its `bm_anime` member, because that is what `bm_anime_list` points at.
  self.animsByMember = {}
  -- ...AND BY THE PROP MODEL THAT CLAIMS IT.  See the loop below.
  self.animsByProp = {}
  local field = ((data.gen4_models or {}).sets or {}).field
  for _, record in ipairs((field or {}).animations or {}) do
    if record.name then
      local list = self.animsByName[record.name]
      if not list then list = {} ; self.animsByName[record.name] = list end
      list[#list + 1] = record
    end
    -- A one-shot asks for a MEMBER, and an animation record carries the member
    -- it came from whether or not it also carries a name.  First wins: an
    -- NSBCA member holds one animation in this archive, and taking the last
    -- would make the result depend on the order the file happens to list them.
    if record.member and self.animsByMember[record.member] == nil then
      self.animsByMember[record.member] = record
    end
    -- ...AND BY PROP, WHICH IS THE JOIN THE CARTRIDGE ACTUALLY MAKES.
    --
    -- `animsByName` is this port's own join, and it is not the hardware's.
    -- The cartridge pairs an animation with a prop through `bm_anime_list`
    -- (`area_build -> bm_anime_list : mapPropModelIDs`, then
    -- `bm_anime_list -> bm_anime : animeArchiveIDs`), which
    -- `RomExtractorGen4:propAnimationClaims` reads and the extractor records
    -- on each animation as `props`.  The two joins do not agree, and the gap
    -- is not small -- measured on this cartridge:
    --
    --    112 prop models are claimed by a `bm_anime` animation
    --     68 of them share a NAME with one, which is all this table saw
    --     44 do not, and were handed to the static bake and never moved
    --
    -- The 44 split 22 joint -- already reached, because `oneShotProps` keys on
    -- the claim -- and 22 TEXTURE: twelve BTA0 and ten BTP0 over 124
    -- placements.  Among them all six `wfall*` models, every one claimed by
    -- animation 18 (`wfall`, 61 frames, three SRT targets) and none of them
    -- named `wfall`, so PLATINUM'S WATERFALLS WERE STATIC.  Also
    -- `cy_slope`/`cy_slope_dun` (animations 20/21), `ev_o01` (35/36),
    -- `l_lake_l4` (19), the four `stair_pc_*` escalators (15/16), the three
    -- `table_l*` and `pc01` monitors (41/42) and `ele_door1` (51/52).
    for _, index in ipairs(record.props or {}) do
      local owned = self.animsByProp[index]
      if not owned then owned = {} ; self.animsByProp[index] = owned end
      owned[#owned + 1] = record
    end
  end
  self.animated = {}     -- land -> { canvas, frame } | false
  -- The terrain mesh of a chunk that has moving props on it, held because that
  -- chunk's depth pass runs every frame.  Only those chunks, so a map with no
  -- fountains holds nothing.
  self.depthModels = {}
  self.clock = 0
  return self
end

-- The camera this map is drawn with, and everything derived from it.
--
-- Re-run whenever the OPTIONS tilt changes: the pitch is baked INTO the chunk
-- canvases, so a new pitch means the bakes are stale.  `Gen4Camera.generation`
-- ticks on every change and `draw` compares it, which is cheaper than a hook
-- and cannot be missed by a screen that forgot to call one.
function Gen4Ground:applyCamera()
  self.camera = Gen4Camera.forMap(self.def)
  self.tiltGeneration = Gen4Camera.generation
  -- THE VIEW PITCH, WHEN A CALLER HAS ASKED FOR ONE.
  --
  -- `self.viewPitch` is degrees below horizontal, or nil for the cartridge's
  -- own camera row -- which is the DEFAULT, because the pitch is the picture
  -- the DS draws and the overworld must keep it.  The map editor sets it so
  -- a map can be looked at straight down (90) or at any angle between; a
  -- synthetic one-field config is enough, because `scales` and `lean` read
  -- nothing else, and everything downstream here is derived from sinP/cosP.
  --
  -- READ HERE RATHER THAN SET FROM OUTSIDE, which is the whole point.  The
  -- pitch is baked into the chunk canvases, so `draw` re-applies the camera
  -- whenever `Gen4Camera.generation` ticks -- a scale assigned onto the
  -- instance from a caller would be silently overwritten the first time the
  -- OPTIONS tilt moved, with no edit to blame.
  local shot = self.camera
  if type(self.viewPitch) == "number" then
    shot = { pitch = self.viewPitch, heightPitch = self.viewPitch }
  end
  local sinP, cosP = Gen4Camera.scales(shot)
  self.groundScale, self.heightScale = sinP, cosP
  self.lean = Gen4Camera.lean(shot)
  -- The canvas is the compressed ground plus room for what stands on it.
  self.canvasPx = math.ceil(self.chunkPx * sinP + cosP * MAX_RISE)
  self.view, self.leanPx = projection(self.half, sinP, cosP, self.canvasPx)

  -- WHICH VIEW THE TILT LADDER IS ASKING FOR.
  --
  -- The last two rungs are "third" and "first" rather than angles, and they
  -- hand the frame to `Gen4View` instead of to the matrix above.  Kept across
  -- a re-apply when the mode has not changed, so stepping the ladder does not
  -- throw away a yaw a look control has set.
  -- ...AND AN EXPLICIT PITCH TAKES NO RUNG OFF THE TILT LADDER.  The last two
  -- are `third` and `first`, which hand the frame to `Gen4View` and pick
  -- their own chunks around a free camera; a tool asking for a fixed angle
  -- would get a player's-eye view instead of the angle it asked for.
  local mode = (self.viewPitch == nil) and Gen4Camera.mode() or nil
  if mode then
    if not (self.view3d and self.view3d.mode == mode) then
      self.view3d = Gen4View.new(mode)
    end
    -- THE MAP'S OWN CAMERA ROW, and the angle the ladder asked for.
    --
    -- Re-sent on every apply rather than once at construction, because the
    -- ladder can be stepped without the mode changing -- rung 60 to rung 30 is
    -- the same `field3d` view at a different pitch -- and a camera that only
    -- read this when it was built would ignore every step after the first.
    if self.view3d.useConfig then
      -- `rungPitch` FIRST, which is the ladder's own angle.
      --
      -- It used to read `heightPitch`, and that field was carrying two
      -- different decisions at once: how tall to draw what stands on the
      -- ground (the oblique pass's business) and which angle this camera
      -- should sit at. Reading it here is what made the stretch load-bearing
      -- -- remove the exaggeration and every rung drew the same picture -- so
      -- the angle now has a field of its own and `heightPitch` keeps the map
      -- header's answer. See `Gen4Camera.forMap`.
      self.view3d:useConfig(self.camera,
                            self.camera and (self.camera.rungPitch
                                             or self.camera.heightPitch
                                             or self.camera.pitch))
    end
  else
    self.view3d = nil
  end
  -- HOW FAR A UNIT OF HEIGHT IS NEARER THE EYE THAN THE GROUND, as a fraction
  -- of the camera's distance.  This is the whole of the perspective term the
  -- live pass applies; see the shader in `Gen4Model` for what it does with it.
  --
  -- The MAP'S OWN pitch, not the OPTIONS row's height pitch: the spread is a
  -- fact about where the physical camera sits, and the row only exaggerates
  -- how tall things are drawn.  Zero for the 300 headers the cartridge itself
  -- draws orthographically -- there is no spread to reproduce there, and
  -- inventing one would be worse than the flat picture it replaced.
  local cam = self.camera or {}
  -- A CHOSEN TILT RUNG NAMES ITS OWN DISTANCE, and that is what makes stepping
  -- the ladder add depth instead of only height.  `Gen4Camera.forMap` sets
  -- `spreadDistance`/`spreadPitch` on a numeric rung and leaves them nil at the
  -- cartridge rung, so the faithful path is byte-identical and there is no
  -- branch here that can drift from it.  See that function for why an
  -- orthographic header gets a spread once the player has asked for one.
  local distance = tonumber(cam.spreadDistance) or tonumber(cam.distance) or 0
  local pitch = tonumber(cam.spreadPitch or cam.pitch) or 90
  local wanted = cam.spreadDistance ~= nil or cam.projection == "perspective"
  if wanted and distance > 1 then
    self.spread = { math.cos(math.rad(pitch)) / distance, 0 }
  else
    self.spread = { 0, 0 }
  end
  -- SAY WHICH CAMERA IS IN USE, once per change.  There are two ways to end up
  -- with a flat world that look identical on screen -- the map's header naming
  -- a straight-down type, or the OPTIONS `CAM TILT` row pinned to 90 -- and
  -- without this the only way to tell them apart is to read the save.
  local camera = self.camera or {}
  -- THE HEIGHT PITCH IS NAMED SEPARATELY, because it is now the one the
  -- OPTIONS row moves and `pitch` always stays the map header's own.  A line
  -- that printed only `pitch` would read 59.05 on every rung of the ladder and
  -- make a working control look like a dead one.
  local heightPitch = camera.heightPitch or camera.pitch
  local key = ("%s/%s/%s"):format(tostring(camera.id), tostring(camera.pitch),
                                  tostring(heightPitch))
  if self.reportedCamera ~= key then
    self.reportedCamera = key
    Logger.info("gen4 camera: %s at %.2f deg, height at %.2f deg (%s) -- "
                .. "ground x%.3f, height x%.3f",
                tostring(camera.id), tonumber(camera.pitch) or 0,
                tonumber(heightPitch) or 0,
                camera.chosen and "chosen in OPTIONS" or "the map header's own",
                sinP, cosP)
  end
end

-- THE LIGHT THIS MAP IS DRAWN UNDER, and the band of the day it is in.
--
-- Split from `applyCamera` because the two go stale for different reasons and
-- cost different amounts to put right.  A new PITCH invalidates the baked
-- canvases and nothing else -- the meshes are reusable, only the matrix
-- changed.  A new LIGHT BAND invalidates the MESHES, because the tint is
-- multiplied into the vertex colours when the mesh is built; re-baking a mesh
-- that still carries dawn's colours at noon would change nothing.
function Gen4Ground:applyLight()
  local now = os.date("*t")
  local shade, template, index =
    Gen4Shade.forMap(self.arealight, self.lightMember, now.hour, now.min)
  self.shade = shade
  self.lightBand = index or 0

  -- THE SKY'S OWN SIGNAL, and deliberately NOT derived from the band.
  --
  -- Nightness moves CONTINUOUSLY inside a keyframe span -- the whole dusk fade
  -- happens within band 14 -- so reading it off `lightBand` would turn an hour
  -- long fade into a single step.  Keeping it separate costs nothing and is
  -- also what makes it safe: it feeds an ALPHA, not a baked vertex colour, so
  -- unlike the tint it never invalidates a mesh and `dropLitModels` must not
  -- fire when it changes.
  self.nightness = Gen4Shade.nightness(self.arealight, self.lightMember,
                                       now.hour, now.min)

  -- SAID OUT LOUD, ONCE PER CHANGE.
  --
  -- An absent light is the one failure that looks exactly like success: the
  -- world still draws, at full brightness, with no directional term -- which
  -- is precisely the "correct tilt, flat rendering" this whole stage exists to
  -- fix, and it reported nothing at all for five rounds of play-testing.
  local key = ("%s/%s"):format(tostring(self.lightMember), tostring(self.lightBand))
  if self.reportedLight ~= key then
    self.reportedLight = key
    if shade then
      -- What a wall actually loses against the ground, so the line carries a
      -- number that would change if the equation broke rather than a name.
      local wr = select(1, shade(1, 0, 0))
      Logger.info("gen4 light: %s on member %s band %s -- a vertical face is "
                  .. "x%.3f of the ground, sky nightness %s",
                  tostring(self.def and self.def.id),
                  tostring(self.lightMember), tostring(self.lightBand), wr or 1,
                  self.nightness and ("%.2f"):format(self.nightness) or "n/a")
    else
      Logger.warn("gen4 light: %s has no area light (member %s) -- the ground "
                  .. "draws unlit, which looks flat however correct the camera is",
                  tostring(self.def and self.def.id), tostring(self.lightMember))
    end
  end
end

-- Drop everything that carries the light baked into it.  The bakes go with
-- them: a canvas is a picture of the meshes that are about to be thrown away.
function Gen4Ground:dropLitModels()
  self:dropBakes()
  self.buildings = {}
  self.depthModels = {}
  -- ...and the live meshes, which carry the tint in their vertex colours
  -- exactly as the baked ones do.
  for _, held in pairs(self.liveModels or {}) do
    if type(held) == "table" and held.release then pcall(held.release, held) end
  end
  self.liveModels, self.liveOrder = {}, {}
end

-- How much of a map pixel a screen row is worth, so the overworld can place
-- its camera and its sprites in the same picture the ground is drawn in.  One
-- at pitch 90, which is the flat bake and every other generation.
function Gen4Ground:scale()
  return self.groundScale or 1, self.heightScale or 0
end

-- LOOK AT THIS MAP FROM A CHOSEN ANGLE, for a caller that is not the
-- overworld.
--
-- `degrees` is pitch below horizontal: 90 is straight down, the cartridge's
-- own rows run 40.6 to 78.4, and nil hands the map back to its own camera.
--
-- The map editor is the caller.  It lays out its viewport, clamps its camera
-- and turns a mouse position into a cell in FLAT map pixels, while this
-- renderer draws with the cartridge's pitch -- at the DEFAULT row's 59.05
-- degrees the ground is compressed to sin(59.05) = 0.858 of its depth, so
-- 14.2% of a viewport's height has no map in it and shows `GEN4_BACKDROP`.
-- That is a real effect and it is why the angle is adjustable rather than
-- fixed; it is NOT, on its own, the whole of the black band that was
-- reported, which survived pinning the pitch to 90.
--
-- NOT THE DEFAULT, and the editor now opens on the cartridge angle: *"add
-- the tilt back and add an option for changing the camera angle above the
-- map view"*.  A tool that silently flattened Sinnoh would be answering a
-- question nobody asked.
function Gen4Ground:setViewPitch(degrees)
  local want = tonumber(degrees)
  if want then want = math.max(5, math.min(90, want)) end
  if self.viewPitch == want then return self end
  self.viewPitch = want
  -- The bakes ARE the old pitch -- a chunk canvas is drawn compressed and
  -- cached -- so they go with it, or the first frame after the change is the
  -- old projection laid out on the new one's grid.
  self:dropBakes()
  self:applyCamera()
  return self
end

-- The straight-down case by name, kept because it reads better at the call
-- site than the number does and because the checks name it.
function Gen4Ground:setFlatView(on)
  return self:setViewPitch(on and 90 or nil)
end

-- Drop every baked chunk, keeping the store and the height data open.  The
-- tilt changed; the geometry did not.
function Gen4Ground:dropBakes()
  -- THE PAINTED GROUND GOES WITH THEM, and this is not housekeeping: a decal
  -- is baked INTO the chunk canvas, so a cached decal model outliving the
  -- canvas it was baked into means a cell painted in the editor does not
  -- appear until the game is restarted. Every path that invalidates a bake --
  -- a tilt change, a re-apply, an edit -- has to invalidate these too, and
  -- doing it here is what makes that true by construction.
  self.decalModels, self.decalCells, self.decalWhy = nil, nil, nil
  for _, canvas in pairs(self.baked) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.baked, self.order = {}, {}
  -- ...and the canopies, which are baked at the same pitch, go stale with it,
  -- and are a canvas per chunk exactly like the bakes above.
  for _, canvas in pairs(self.canopies or {}) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.canopies = {}
  for _, entry in pairs(self.animated or {}) do
    if type(entry) == "table" and entry.canvas and entry.canvas.release then
      pcall(entry.canvas.release, entry.canvas)
    end
  end
  for _, held in pairs(self.depthModels or {}) do
    if type(held) == "table" and held.release then pcall(held.release, held) end
  end
  self.animated, self.depthModels = {}, {}
end

-- The animation records driving one building, or nil.  `false` is cached so a
-- chunk with forty copies of a static house asks once.
-- Returns the animation records AND the model's own flipbook frames, because
-- a BTP0 is only playable when both are present and every caller needs the
-- pair.
-- ...AND IT MUST BE TOLD WHICH ARCHIVE TOO.  `bm_anime` is paired to
-- `build_model` BY MODEL NAME, and the pairing is done by looking the index up
-- in the building set.  Handed an fldeff member that lookup does not fail --
-- it returns whatever building sits at that position and hands a signpost
-- another model's animations.  A wrong answer, not a missing one.
-- A RUNNING ONE-SHOT'S POSE, for the prop this object is.
--
-- `Gen4Model:draw(viewProjection, pose, materials, ...)` has taken a pose as
-- its second argument all along and every prop draw passed `nil`, which is
-- what made a door's NSBCA look unreachable from here.  It is not: the join
-- (`Gen4PropAnim`, which `bm_anime` member a prop owns) and the matrices
-- (`Gen4Anim.jointMatrices`, packed into the cache) both exist, and this is
-- the one place that was missing.
--
-- BY OBJECT IDENTITY. `Gen4Doors.propAt` found the door in this same
-- `terrain.chunks[land].objects` table, so the object a script opened IS the
-- object drawn here and no coordinate is compared twice.
--
-- `self.oneShots` IS HANDED OVER by the overworld each frame, not reached
-- through it. This renderer is built by `MapLoader` and holds no controller
-- reference, which is right -- and a `self.overworld` here would have been
-- cold by construction, returning nil for ever with nothing to say so.
--
-- Returns nil when there is no one-shot, no track in the cache for its
-- animation, or no overworld -- and nil is the rest pose, so a door with no
-- tracks yet draws exactly as it does today rather than collapsing to the
-- origin.
function Gen4Ground:oneShotPose(object, building)
  if not (object and building) then return nil end
  local slots = self.oneShots
  if not slots then return nil end
  local okO, OneShot = pcall(require, "src.world.Gen4PropOneShot")
  if not okO or not OneShot then return nil end
  local slot = OneShot.poseIn(slots, object)
  if not slot then return nil end
  local byJoint = self:jointMatricesAt(slot)
  if not byJoint then return nil end
  return building:posed(function(node) return byJoint[node] end)
end

-- jointMatricesAt(slot) -> { [joint index] = 4x4 } | nil
--
-- The ARITHMETIC, split out from the draw so it can be graded. `oneShotPose`
-- needs a built model and therefore LOVE; this needs neither, and planted
-- faults in it -- writing every track to joint 0, dropping the frame clamp --
-- were invisible while it lived inside the draw and only its source was read.
--
-- The clamp matters beyond tidiness: `advance` holds a finished one-shot on
-- its last frame, `frame` equals `frames`, and a track has `frames` entries
-- indexed from zero -- so the last readable index is `frames - 1` and reading
-- `frame` itself would run one past the end of every held-open door.
function Gen4Ground:jointMatricesAt(slot)
  if not slot then return nil end
  local record = self.animsByMember and self.animsByMember[slot.animation]
  local tracks = record and record.tracks
  if not tracks then return nil end
  local okA, Anim = pcall(require, "src.import.Gen4Anim")
  if not okA or not Anim or not Anim.unpackFrame then return nil end
  local frame = math.floor(tonumber(slot.frame) or 0)
  local byJoint = {}
  for _, track in ipairs(tracks) do
    local at = frame
    if track.frames and at >= track.frames then at = track.frames - 1 end
    if at < 0 then at = 0 end
    byJoint[track.index] = Anim.unpackFrame(track.matrices, at)
  end
  return byJoint
end

-- PROP MODELS THAT CAN RUN A JOINT ONE-SHOT, by `build_model` index.
--
-- Derived from the cache, not from a list of names: an animation record
-- carries `props`, the prop models that claim it (`bm_anime_list`), and
-- `tracks`, the packed joint matrices. A model is one-shot capable when some
-- animation names it AND that animation has tracks to pose it with.
--
-- BY INDEX, because the two namespaces disagree. `doorModelIDs[]` names the
-- file (`brown_wooden_door`) and the cache names the model inside it
-- (`t1_door1`) -- different for nineteen of the twenty doors, with `door01`
-- the one coincidence that makes a spot-check pass. See
-- claude/gen4_prop_animations.md; keying this on a name would have been wrong
-- for nineteen doors while looking right for the one anybody checked.
--
-- Measured on the regenerated cache: 39 prop models over 218 placements --
-- the twenty doors plus nineteen other animated props.  211 of those
-- placements move for a joint reason ALONE; the other 7 are texture-animated
-- as well, because three of the 39 models are in both sets.
function Gen4Ground:oneShotProps()
  if self.oneShotPropSet then return self.oneShotPropSet end
  local set = {}
  local models = (self.buildingSet or {}).models or {}
  local oneShot = Gen4Ground.oneShotAnimations()
  for _, record in pairs(self.animsByMember or {}) do
    if record.tracks and record.props then
      for _, index in ipairs(record.props) do set[index] = true end
    end
    -- A TEXTURE-PATTERN ONE-SHOT IS STILL A ONE-SHOT, and `tracks` alone
    -- cannot see it.  `elevator_door` animates with BTP0 (members 51 and 52,
    -- 8 frames, textures `ele_door.1`..`.4`) and the other nineteen doors
    -- with BCA0, so the test above answered no for exactly one of the twenty
    -- -- which left `ele_door1` in the static bake, where the draw never asks
    -- for a pose and the runner's 8 frames went nowhere.
    --
    -- Restricted to the script-owned members so the two arms stay disjoint: a
    -- CLOCK-driven flipbook (`pc_moni_on`, `moniter_mb`) is already answered
    -- by `animationsFor`, and counting it here as well would say nothing.
    --
    -- The pictures are required, not assumed: measured against the cartridge,
    -- all ten claim-only BTP0 models carry every one of their animation's
    -- texture names in their OWN TEX0 (15 model/animation pairs, 0 misses),
    -- but a cache imported before those frames were written has the animation
    -- and not the pictures -- and `animates` is the same test the clock route
    -- applies, so a prop cannot be animated by one and baked by the other.
    if record.pattern and record.props and oneShot[record.member or -1] then
      for _, index in ipairs(record.props) do
        local packed = models[index + 1]
        if packed and Gen4TexAnim.animates({ record }, packed.patternImages) then
          set[index] = true
        end
      end
    end
  end
  self.oneShotPropSet = set
  return set
end

-- texturePatternAt(slot, index) -> material states | nil
--
-- The FLIPBOOK HALF of `oneShotPose`, and the reason the elevator door needed
-- one.  `jointMatricesAt` answers nil for a BTP0 record because there are no
-- tracks, nil is the rest pose, and the runner's frame counter was therefore
-- advancing against a door that drew frame zero throughout.
--
-- Split out of the draw for the same reason `jointMatricesAt` was: this needs
-- no LOVE, so it can be executed by a check rather than read.
--
-- THE FRAME IS CLAMPED, and here the clamp is not tidiness either.
-- `Gen4PropOneShot.advance` holds a finished one-shot at `frame == frames`,
-- and `Gen4TexAnim.materials` takes `frame % period` -- so an unclamped read
-- wraps a held-open door back to key zero and SNAPS IT SHUT the instant it
-- finishes opening.  Clamped to `frames - 1` it holds its last key, which is
-- what `looping == FALSE` does on the cartridge.
function Gen4Ground:texturePatternAt(slot, index)
  if not slot then return nil end
  local record = self.animsByMember and self.animsByMember[slot.animation]
  if not (record and record.kind == "BTP0" and record.pattern) then return nil end
  local models = (self.buildingSet or {}).models or {}
  local packed = models[(tonumber(index) or -1) + 1]
  local images = packed and packed.patternImages
  if not images then return nil end
  local frames = tonumber(record.frames) or 0
  local frame = math.floor(tonumber(slot.frame) or 0)
  if frames > 0 and frame >= frames then frame = frames - 1 end
  if frame < 0 then frame = 0 end
  return Gen4TexAnim.materials({ record }, frame, images)
end

-- THE MATERIALS A PROP WEARS AT A FRAME -- one function, three draw sites.
--
-- The static pass, the flat pass and the animated bake each used to spell this
-- as `animationsFor` plus `Gen4TexAnim.materials`, and pass 186 found two of
-- the three asking `animationsFor` with different arguments.  Three spellings
-- of one question is this project's recurring bug; the one-shot flipbook would
-- have made it three again.
function Gen4Ground:propMaterials(object, frame)
  if not object then return nil end
  local records, images = self:animationsFor(object.model, object.archive)
  local mats = records and Gen4TexAnim.materials(records, frame, images) or nil
  if object.archive == "fldeff" then return mats end
  local slots = self.oneShots
  if not slots then return mats end
  local okO, OneShot = pcall(require, "src.world.Gen4PropOneShot")
  if not (okO and OneShot) then return mats end
  local slot = OneShot.poseIn(slots, object)
  local one = slot and self:texturePatternAt(slot, object.model)
  if not one then return mats end
  if not mats then return one end
  -- MERGED rather than assigned, the same reasoning `Gen4TexAnim.materials`
  -- uses between a scroll and a flipbook: a prop can carry a clock-driven
  -- scroll and a script-driven flipbook on two different materials, and
  -- replacing the table would drop whichever was built first.
  for name, state in pairs(one) do
    local into = mats[name] or {}
    for key, value in pairs(state) do into[key] = value end
    mats[name] = into
  end
  return mats
end

-- movesAtRuntime(index, archive) -- the ONE test both prop selections use.
--
-- The static bake draws every prop this says no to; the animated bake draws
-- every prop it says yes to. They are complements, and that only holds while
-- they ask the same question -- which is why this is a function and not two
-- conditions. Pass 186 found them asking different ones (one passed `archive`
-- and the other did not) and nothing had noticed, because the only props the
-- difference could reach are never placed.
function Gen4Ground:movesAtRuntime(index, archive)
  if self:animationsFor(index, archive) then return true end
  -- fldeff props are a different archive and carry no `bm_anime` claim
  if archive == "fldeff" then return false end
  return self:oneShotProps()[index] == true
end

-- THE TWO DECISIONS, NAMED.
--
-- `shouldBake` and `shouldAnimate` are what the static bake's guard and the
-- animated bake's selection actually call. They exist as methods rather than
-- as two inline conditions for one reason: a check can then GRADE them.
--
-- The first draft of pass 187's complement assertion recomputed
-- `not movesAtRuntime(...)` for itself, so a plant that reverted the static
-- guard to the old predicate -- putting every door in BOTH passes, drawn
-- twice -- changed nothing and 427 checks stayed green. That is shape 6a of
-- claude/check_design_lessons.md: setup that mirrors the subject grades the
-- mirror.
--
-- They must be exact complements. Written as one `not` of the other rather
-- than as two tests, because two tests is how they drift.
function Gen4Ground:shouldBake(object)
  return not self:shouldAnimate(object)
end

function Gen4Ground:shouldAnimate(object)
  if not object then return false end
  return self:movesAtRuntime(object.model, object.archive) == true
end

-- THE ANIMATIONS A SCRIPT OWNS, which must never be put on the frame clock.
--
-- `loaddooranimation` hands a tag, `playdooropenanimation` plays on it and
-- `Gen4PropOneShot` holds the last frame until `unloadanimation`.  The clock
-- is a free-running loop over the animation's own period, so a flipbook door
-- driven by it would open and shut for ever on its own -- which is worse than
-- the static door it replaced, and is what widening the join below would have
-- done to `elevator_door` without this.
--
-- DERIVED from `Gen4PropAnim.DOORS` rather than listed here, because that
-- table is the one derived from pokeplatinum's `doorModelIDs[]`; a door added
-- there is excluded from the clock the day it is added.  The require is not
-- wrapped: an empty set here would silently put every door on the clock, and
-- a raise names the cause.
function Gen4Ground.oneShotAnimations()
  if Gen4Ground._oneShotAnimations then return Gen4Ground._oneShotAnimations end
  local PropAnim = require("src.import.Gen4PropAnim")
  local set = {}
  for _, row in ipairs(PropAnim.DOORS or {}) do
    for _, id in ipairs(row.ids or {}) do set[id] = true end
  end
  for _,id in ipairs(PropAnim.INTERACTION_ANIMATIONS) do set[id]=true end
  Gen4Ground._oneShotAnimations = set
  return set
end

-- THE CLOCK-DRIVEN ANIMATIONS FOR ONE PROP -- both joins, minus the one-shots.
--
-- The name route and the claim route are a UNION rather than a fallback,
-- because three of the 112 claimed models are in both sets and taking only one
-- route would drop a scroll or a flipbook from them.  Deduplicated by record
-- identity, since a model reachable both ways would otherwise have the same
-- animation evaluated twice into the same material.
function Gen4Ground:animationsFor(index, archive)
  if archive == "fldeff" then return nil end
  local set = self.buildingSet
  local packed = set and set.models and set.models[index + 1]
  if not packed then return nil end
  local images = packed.patternImages
  local oneShot = Gen4Ground.oneShotAnimations()
  local list, seen = nil, {}
  local function add(records)
    for _, record in ipairs(records or {}) do
      local scripted=record.member and oneShot[record.member]
      if record.member==32 and self.healScreenActive then scripted=false end
      if not seen[record] and not scripted then
        seen[record] = true
        list = list or {}
        list[#list + 1] = record
      end
    end
  end
  add(packed.name and self.animsByName[packed.name])
  add(self.animsByProp and self.animsByProp[index])
  if not (list and Gen4TexAnim.animates(list, images)) then return nil end
  return list, images
end

-- ONE BUILDING, by its member index.  `false` is cached for a model that does
-- not resolve, so a chunk with fifty copies of a broken model asks once.
-- `archive` names WHICH archive `index` belongs to.  Absent means the buildings,
-- which is every caller that existed before signposts; "fldeff" is the object
-- models -- signs, mailboxes -- and it is a DIFFERENT FILE, so the same number
-- means a different model in each and the caches must not be shared either.
function Gen4Ground:building(index, archive)
  local field = archive == "fldeff"
  local cache = self.buildings
  if field then
    self.fieldModels = self.fieldModels or {}
    cache = self.fieldModels
  end
  if cache[index] ~= nil then return cache[index] or nil end
  local packed
  if field then
    -- BY MEMBER, NOT BY POSITION.  `models[index + 1]` below is right for the
    -- buildings only because that archive happens to be one model per member
    -- with every member decoding; measured, it holds for 590 of 590 buildings
    -- and for NONE of the starter, opening or title sets.  fldeff.narc is 201
    -- members of which 145 are models, so position would resolve the wrong one
    -- and still draw something.
    local set = self.fldeffSet
    local at = set and set.byMember and set.byMember[index]
    packed = at and set.models and set.models[at]
  else
    local set = self.buildingSet
    packed = set and set.models and set.models[index + 1]
  end
  if not packed then
    cache[index] = false
    return nil
  end
  local shapes = {}
  for i, s in ipairs(packed.shapes or {}) do
    shapes[#shapes + 1] = {
      name = s.name, index = i - 1,
      vertices = s.vertices, indices = s.indices,
      vertexCount = s.vertexCount, triangleCount = s.triangleCount,
      -- THE MATERIAL TRAVELS WITH THE SHAPE, and it has to.
      --
      -- This list is rebuilt rather than passed through, and it dropped
      -- `material`, `texture` and `alpha` -- so the renderer, which decides a
      -- shape's translucency from exactly those three, saw nothing to decide
      -- with and drew every one opaque.  That is why the building shadows
      -- stayed solid black after the polygon alpha was extracted and applied:
      -- the value was read off the cartridge correctly and then thrown away
      -- one function before it was used.
      material = s.material, texture = s.texture, alpha = s.alpha,
      -- 22 of the 590 carry no texture of their own.  They are drawn
      -- untextured rather than wearing a borrowed picture: a wrong picture on
      -- a building looks deliberate, and a flat one does not.
      image = s.image,
    }
  end
  if #shapes == 0 then
    cache[index] = false
    return nil
  end
  local model = Gen4Model.new({ name = (field and "fldeff%d" or "build%d"):format(index),
                                posScale = packed.posScale, shapes = shapes,
                                -- The building set is SHARED between maps and
                                -- this cache is not: `self.buildings` belongs
                                -- to one ground, so a house in Twinleaf and
                                -- the same house in Sandgem are two meshes
                                -- under two lights, which is the point.
                                shade = self.shade,
                                -- INDOORS ONLY, and only where the cartridge
                                -- left a gap.  Requested as *"implement
                                -- shadows for indoor objects"*: Platinum's
                                -- interior furniture ships none -- `sofa01`,
                                -- `table02`, `chair03`, `bed_h01` and
                                -- `plant01` carry zero shadow shapes between
                                -- them -- while its OUTDOOR props do, so
                                -- adding one outdoors would double up on
                                -- geometry the ROM already has.  A model that
                                -- already owns a `kage` shape keeps it either
                                -- way; `addGroundShadow` checks.
                                groundShadow = (self.outdoors == false)
                                               and self:shadowTexture() or nil,
                                -- CLOSE THE MISSING BACK.  The cartridge never
                                -- modelled it because its camera never looks
                                -- that way; a camera that can be orbited does.
                                --
                                -- OUTDOORS ONLY, and for the same reason the
                                -- ground shadows above are indoors only: the
                                -- two jobs are opposites and the map already
                                -- knows which it is.
                                --
                                -- This is the line that keeps a back wall on
                                -- buildings and off furniture, and nothing
                                -- else can.  Measured over all 590 models, a
                                -- fridge, a crate and a shelf have EXACTLY as
                                -- much north-facing wall as a Twinleaf house
                                -- -- none at all -- so no test on the geometry
                                -- tells them apart.  What does is that one of
                                -- them stands in a room.
                                -- ...and NOT on a signpost.  The back wall is
                                -- generated by copying a face, which is right
                                -- for a house with an unmodelled north side and
                                -- wrong for a board that is MEANT to be thin.
                                capBack = (not field)
                                          and (self.outdoors ~= false) or false })
  cache[index] = model or false
  return model
end

-- THE SIGNPOSTS, AS PROPS THIS MAP OWNS.
--
-- Reported from play: *"signs also still dont appear ... i cant walk through it
-- but theres nothing rendered"*, with the sign's text reading correctly.  They
-- are OBJECT EVENTS carrying `fldeffModel`, not chunk props, so they are not in
-- `record.objects` and nothing here ever drew them.  212 placements across 65
-- maps.
--
-- KEYED BY CHUNK AND BUILT ONCE, in the same shape a chunk prop has, so every
-- draw below treats the two alike and there is no second draw path to keep in
-- step with the first.
--
-- NOT WRITTEN INTO `record.objects`.  `self.terrain.chunks` is SHARED BETWEEN
-- MAPS -- one table for the whole cartridge -- so appending to it would leak
-- Twinleaf's mailboxes into every other map that draws the same chunk, and
-- would do it more than once.
function Gen4Ground:signpostsFor(land)
  if not self.signposts then
    local byLand = {}
    local tiles = self.terrain.chunkTiles or 32
    local unit = self.terrain.tileUnits or 16
    local half = (self.terrain.chunkUnits or 512) / 2
    local grid = self.grid
    local originX = math.floor(self.offsetX / 16)
    local originY = math.floor(self.offsetY / 16)
    for _, object in ipairs((self.def and self.def.objects) or {}) do
      local member = object.fldeffModel
      -- `x`/`y` on a map object are MAP-LOCAL TILES; a chunk prop's are units
      -- from its own centre.  The two spaces are why this conversion exists.
      local tx, ty = object.x, object.y
      if member and tx and ty then
        local mx, my = tx + originX, ty + originY
        local cx, cy = math.floor(mx / tiles), math.floor(my / tiles)
        if mx >= 0 and my >= 0 and cx < grid.width and cy < grid.height then
          local at = grid.land[cy * grid.width + cx + 1]
          if at then
            local list = byLand[at]
            if not list then list = {} byLand[at] = list end
            list[#list + 1] = {
              model = member,
              archive = "fldeff",
              -- The tile's CENTRE, in the chunk's own space, which is centred
              -- on the origin -- the same arithmetic `heightsAt` does.
              x = ((mx % tiles) + 0.5) * unit - half,
              z = ((my % tiles) + 0.5) * unit - half,
              -- A CHUNK PROP STATES ITS OWN `y` AND A MAP OBJECT DOES NOT, so
              -- the ground has to say.  Sinnoh is not flat and a sign on a
              -- fixed height would sink into every slope in the game.
              y = self:heightAt(tx, ty) or 0,
              scaleX = 1, scaleY = 1, scaleZ = 1,
            }
          end
        end
      end
    end
    self.signposts = byLand
  end
  return self.signposts[land]
end

-- The chunk's own props PLUS this map's signposts standing on it.  One function
-- so the three draws below cannot disagree about what is on a chunk.
function Gen4Ground:objectsFor(land, record)
  local own = (record and record.objects) or {}
  local edits=self.def.gen4ModelEdits
  if edits and edits[tostring(land)] then own=edits[tostring(land)] end
  local mine = self:signpostsFor(land)
  local heal = self.healingProps and self.healingProps[land]
  if (not mine or #mine == 0) and not heal then return own end
  local all = {}
  for _, o in ipairs(own) do all[#all + 1] = o end
  for _, o in ipairs(mine or {}) do all[#all + 1] = o end
  for _, o in ipairs(heal or {}) do all[#all + 1] = o end
  return all
end

-- The healing balls are map props in Platinum, placed relative to the
-- console, so they participate in the same depth/camera pass as its ROM art.
function Gen4Ground:setHealingBalls(count, visible)
  self.healScreenActive=(count or 0)>0
  local key = tostring(count or 0) .. ':' .. tostring(visible)
  if self.healingPropsKey == key then return end
  self.healingPropsKey, self.healingProps = key, nil
  if count and count > 0 and visible ~= false then
    local A = require('src.import.Gen4Archives')
    local path = '/fielddata/build_model/build_model.narc'
    local machine = A.find(path, 'pokecenter_healing_machine.nsbmd')
    local ball = A.find(path, 'pokecenter_healing_machine_mini_pokeball.nsbmd')
    if machine and ball then
      for _, land in ipairs(self.grid.land or {}) do
        local record = self.terrain.chunks[land]
        for _, object in ipairs(record and record.objects or {}) do
          if object.model == machine then
            local props = {}
            for i = 1, math.min(6, count) do
              props[i] = { model = ball, x = (object.x or 0) + ((i-1)%2 == 0 and -4.5 or 4.5),
                y = (object.y or 0) + 12, z = (object.z or 0) + (math.floor((i-1)/2)-1)*4.5,
                scaleX = 1, scaleY = 1, scaleZ = 1 }
            end
            self.healingProps = { [land] = props }
            break
          end
        end
        if self.healingProps then break end
      end
    end
  end
  self:dropBakes()
end

-- WHERE A BUILDING STANDS, as a row-major matrix in the chunk's own units.
--
-- The object record's x/y/z are already divided out of 20.12 fixed point by
-- `Gen4Maps.objects`, and `Gen4Model` has already multiplied the model's own
-- `posScale` into its vertices -- so both sides are in world units and this is
-- an ordinary scale-then-translate with nothing left to reconcile.
--
-- A SCALE OF ZERO IS NOT A SCALE.  Some records leave the three scale fields
-- empty, and reading those as zero collapses the model to a point -- which
-- draws nothing and looks exactly like a missing building.  Absent means one.
local function placement(object)
  local sx = (object.scaleX and object.scaleX ~= 0) and object.scaleX or 1
  local sy = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
  local sz = (object.scaleZ and object.scaleZ ~= 0) and object.scaleZ or 1
  return {
    sx, 0,  0,  object.x or 0,
    0,  sy, 0,  object.y or 0,
    0,  0,  sz, object.z or 0,
    0,  0,  0,  1,
  }
end

-- The chunk store, opened once and read in ranges.
--
-- Not read whole: the packed geometry is 17.7 MB and a map needs a few chunks
-- of it. `File:seek` plus `File:read` is the difference between seventeen
-- megabytes resident for every Platinum session and a few hundred kilobytes.
function Gen4Ground:store()
  if self.file ~= nil then return self.file or nil end
  local path = self.terrain.chunkFile
  local fs = love and love.filesystem
  if not (path and fs and fs.newFile) then self.file = false return nil end
  local file, why = fs.newFile(Assets.resolve(path), "r")
  if not file then
    Logger.warn("gen4 ground: %s would not open (%s)", tostring(path), tostring(why))
    self.file = false
    return nil
  end
  self.file = file
  return file
end

function Gen4Ground:slice(at, bytes)
  local file = self:store()
  if not (file and bytes and bytes > 0) then return nil end
  if not file:seek(at) then return nil end
  return file:read(bytes)
end

-- The model for one chunk, rebuilt from the store in the shape `Gen4Model`
-- already takes -- which is why there is no second loader here: a terrain
-- chunk and a Poke Ball are the same kind of thing to the renderer, and the
-- only difference is where their bytes came from.
--
-- NO NODES AND NO POSE, and that is measured rather than assumed. A model's
-- shapes are placed by the matrix slot each is bound to, and across all 666
-- chunks -- 7,547 shapes -- EVERY shape is bound to slot 0. Thirty-three
-- chunks do carry more than one node and 207 node matrices are not the
-- identity, so the nodes are not absent; nothing places a shape with them.
-- The vertices are already in the chunk's own space, which is what the first
-- render of one off the cartridge showed and this counts.
function Gen4Ground:modelFor(land)
  local record = self.terrain.chunks[land]
  if not record then return nil end
  local shapes = {}
  for _, s in ipairs(record.shapes or {}) do
    local vertices = self:slice(s.vertexAt, s.vertexBytes)
    local indices = self:slice(s.indexAt, s.indexBytes)
    if vertices and indices then
      -- THE TEXTURE, AND THE PALETTE IT IS WORN WITH.  A shape names both,
      -- because the material does; 29 textures in this cartridge are worn with
      -- two different palettes and are filed under "<texture>#<palette>" as
      -- well as under their own name.  Everything else is filed once, so the
      -- second lookup misses and the first answers.
      local textures = self.set.textures
      local texture = s.texture and
        ((s.palette and textures[s.texture .. "#" .. s.palette])
         or textures[s.texture])
      shapes[#shapes + 1] = {
        name = s.name,
        index = #shapes,
        vertices = vertices, indices = indices,
        vertexCount = s.vertexCount, triangleCount = s.triangleCount,
        image = texture and texture.path or nil,
        -- THE MATERIAL'S TEXTURE NAME, because it is how the cartridge itself
        -- separates the lawn from the grass a wild Pokemon lives in: they are
        -- different materials on different polygons of the same chunk.
        texture = s.texture,
        -- THE MATERIAL'S OWN NAME AND THE ALPHA IT STATES.  `Gen4Ground:building`
        -- has carried all three for PROPS since dropping them cost the building
        -- shadows; terrain carried only the texture, so Sinnoh's `sea` drew as
        -- opaque as its cliffs and every `shadowchip` decal was a solid patch.
        --
        -- The cache has had `material` since the palette work and nothing read
        -- it.  `alpha` is new as of the same pass as this line, so it is nil on
        -- any cache written earlier and `Gen4Model.shapeAlpha` falls back to
        -- the name -- which is why that fallback now tests BOTH names: eleven
        -- terrain materials wear a `kage` TEXTURE under a name that says
        -- nothing (`chair4`, `counter2`, `shelf2`, `lambert7`), and supplying
        -- `material` while checking it alone would have turned those eleven
        -- correct shadows opaque on every existing cache.
        material = s.material,
        alpha = s.alpha,
      }
    end
  end
  if #shapes == 0 then return nil end
  return Gen4Model.new({ name = ("chunk%d"):format(land),
                         posScale = record.posScale, shapes = shapes,
                         -- WHERE THE CHUNK'S SHAPES STAND.
                         --
                         -- A chunk model's shapes are drawn through a node,
                         -- like every other model here, and `Gen4Model` has
                         -- posed them all along -- `restPose` walks `ops` with
                         -- `nodes` and `draw` places each shape by the result.
                         -- Terrain simply never handed either over, so every
                         -- chunk was drawn as if its node were the identity.
                         --
                         -- Nil on the 649 chunks whose node IS the identity,
                         -- and on every cache written before the importer
                         -- started carrying them -- `Gen4Model` defaults both
                         -- to empty and poses to the origin, which is exactly
                         -- what it did before. So this costs nothing and
                         -- changes nothing until the ROM is imported again.
                         nodes = record.nodes, ops = record.ops,
                         -- ...AND THE LIGHT.  Without this the mesh is built
                         -- from white vertices and no camera can make it read
                         -- as anything but flat.
                         shade = self.shade,
                         -- HOW BIG A TILE IS, for the standing grass.  Read
                         -- off the cache rather than assumed: `tileUnits` is
                         -- what the importer measured.
                         tileUnits = self.terrain.tileUnits,
                         -- TERRAIN ONLY, and deliberately not the buildings.
                         -- Sinnoh's trees are terrain shapes; the same
                         -- classifier run over `build_model.narc` catches a
                         -- school roof and a fountain that happen to sit at
                         -- the tree's lean, and they must not spin.
                         billboard = true })
end

-- ---------------------------------------------------------------------------
-- THE LIVE PASS
-- ---------------------------------------------------------------------------
--
-- Reported from play, after the lighting and the tilt both landed: *"still
-- looks completely flat from my view ... current camera when walking makes it
-- look flat"*.
--
-- That is the correct diagnosis of something no amount of height fixes.  The
-- ground was drawn by BAKING each chunk once into a canvas and blitting the
-- canvas, and a blit is rigid: walking slides a finished 2D picture. Worse,
-- the matrix it was baked with is ORTHOGRAPHIC, and an orthographic projection
-- has NO MOTION PARALLAX BY CONSTRUCTION -- screen position is a linear
-- function of (x, y, z) with no divide by depth, so the offset between a
-- tree's top and its base cannot depend on where the camera is.
--
-- The cartridge's DEFAULT camera record says `projection = "perspective"`,
-- distance 666.92, half-fov 8.09.  That frustum gives 1.0125 px per unit at
-- the target, and geometry standing on the ground is nearer the eye:
--
--   a 42-unit tree      x1.0337  -> 4.3 px further out at the screen edge
--   t1_h01, 71 units    x1.0579  -> 7.4 px
--   t1_s01, 90.8 units  x1.0753  -> 9.6 px
--
-- Zero at the screen centre, largest at the edges -- so walking past a tree
-- sweeps its top about eight pixels across its own trunk.  THAT is the cue,
-- and it is worth more than any static amount of lean.
--
-- So the chunks are drawn EVERY FRAME into one screen-sized target instead of
-- once each into their own.  That is cheaper than it sounds and was probably
-- always the better shape: chunk 5 is 13 shapes and 1,464 vertices, chunk 0 is
-- 19 and 3,226, and a screen shows a handful -- tens of thousands of triangles
-- a frame, which is nothing, against a cache of 512x1010 canvases with a depth
-- buffer apiece.
--
-- WHAT DOES NOT MOVE IS THE GROUND, and that is the containment argument.  The
-- spread is `1 / (1 - h * cos(pitch) / D)`, which at h = 0 is exactly 1.  The
-- ground plane therefore projects EXACTLY where it did, so every sprite the
-- overworld places, every collision pick and every screen-row-to-tile-row
-- answer is untouched.  Only things that stand up move, and they move relative
-- to their own base, which is the definition of the cue that was missing.

-- The depth row's divisor.  The live pass shares ONE buffer across every
-- visible chunk, so a chunk's own north-south offset has to be in its depth or
-- two chunks a row apart would sort against each other rather than with each
-- other.  Values land near zero and ordering is all a depth test reads.
local LIVE_DEPTH = 32768

-- Chunk-local coordinates straight to the target's NDC, for a chunk whose
-- top-left corner sits at (offX, offY) in screen pixels.
--
-- The `leanPx` that the bake added and the blit took back off cancels here and
-- is simply absent: a screen row is a screen row.
-- How far up the chunk at matrix cell (cx, cy) is drawn, in world units --
-- `altitude * MAP_OBJECT_TILE_SIZE / 2`. Zero where the matrix has no
-- altitude section, which is most interiors.
function Gen4Ground:chunkLift(cx, cy)
  local alt = self.altitudes
  local grid = self.grid
  if not (alt and grid) then return 0 end
  local a = alt[cy * grid.width + cx + 1]
  if not a or a == 0 then return 0 end
  return a * 8 * ((self.terrain and self.terrain.pixelsPerUnit) or 1)
end

-- A raised chunk's spread, in ITS OWN model space.
--
-- The spread and the walk-behind cut are both compared against the vertex's
-- MODEL-LOCAL y in the shader, and the lift is applied by the matrix after
-- that -- so a chunk drawn `lift` higher has to be asked about a height `lift`
-- lower, or its perspective spreads about the wrong height and the player's
-- cut lands in the wrong place.
local function liftedSpread(spread, lift)
  if not spread or lift == 0 then return spread end
  local out = {}
  for i, v in ipairs(spread) do out[i] = v end
  out[2] = (out[2] or 0) - lift
  return out
end

-- m * translation(0, lift, 0), for a row-major 4x4: only column four moves.
local function liftMatrix(m, lift)
  if lift == 0 then return m end
  local out = {}
  for i = 1, 16 do out[i] = m[i] end
  out[4] = m[4] + m[2] * lift
  out[8] = m[8] + m[6] * lift
  out[12] = m[12] + m[10] * lift
  out[16] = m[16] + m[14] * lift
  return out
end
Gen4Ground.liftMatrix = liftMatrix

function Gen4Ground:screenMatrix(offX, offY, vw, vh)
  local sinP = self.groundScale or 1
  local cosP = self.heightScale or 0
  local half = self.half
  return {
    2 / vw, 0, 0, 2 * (offX + half) / vw - 1,
    -- Y IS NEGATIVE AND Z POSITIVE, which is the same pair of signs the baked
    -- `projection` uses one screen up.  Writing them the other way round is
    -- not a subtle error -- it renders the whole map upside down -- and it is
    -- what the first run of this did.
    0, -2 * cosP / vh, 2 * sinP / vh, 2 * (offY + half) * sinP / vh - 1,
    0, -sinP / LIVE_DEPTH, -cosP / LIVE_DEPTH, -(offY * cosP) / LIVE_DEPTH,
    0, 0, 0, 1,
  }
end

-- How many chunk meshes to hold.  A screen shows a handful and a walk crosses
-- them steadily, so this is room to move about in without re-meshing and a
-- BOUNDED cost -- which the first version of this was not: it kept every chunk
-- it had ever drawn, and a session that walked the length of Sinnoh would have
-- held all 666.
-- How far above the terrain the free camera's eye is held, in world units.
-- A third of a tile: enough that the near clip plane does not slice into a
-- slope, small enough that the camera still skims the ground when asked to.
Gen4Ground.EYE_CLEARANCE = 6

Gen4Ground.LIVE_CACHE = 32

-- The chunk meshes, HELD now rather than built and thrown away.
--
-- `bake` called `modelFor` once and dropped the result, which was right when a
-- chunk was meshed once in its life.  The live pass needs it every frame.
function Gen4Ground:liveModel(land)
  self.liveModels = self.liveModels or {}
  self.liveOrder = self.liveOrder or {}
  local hit = self.liveModels[land]
  if hit ~= nil then return hit or nil end

  local model = self:modelFor(land)
  self.liveModels[land] = model or false
  self.liveOrder[#self.liveOrder + 1] = land
  -- Oldest first, and only the ones that cost something to hold: a `false`
  -- entry is a chunk with no geometry and remembering that is the point of it.
  while #self.liveOrder > Gen4Ground.LIVE_CACHE do
    local oldest = table.remove(self.liveOrder, 1)
    local held = self.liveModels[oldest]
    if type(held) == "table" and held.release then pcall(held.release, held) end
    if held then self.liveModels[oldest] = nil end
  end
  return model
end

-- ---------------------------------------------------------------------------
-- HOW MANY REAL PIXELS THE 3D VIEW GETS
-- ---------------------------------------------------------------------------
--
-- Reported from play: *"the first and third person are also really low
-- resolution and highly pixelated"*.
--
-- MEASURED, NOT GUESSED. `Renderer:fitScale` is
-- `floor(min(pw / uiW, ph / uiH))` and a Gen 4 UI is the DS's own 256x192, so
-- on a 1536-wide window the scale lands near 5 and `Renderer:worldViewSize`
-- hands this pass about 307x230. `drawFree` then allocated a target of exactly
-- that and the result was blitted up five times with NEAREST filtering.
--
-- That is RIGHT FOR PIXEL ART and wrong here. An integer scale with nearest is
-- what keeps a 16x16 tile crisp; perspective geometry has no pixel grid to
-- preserve, so the same treatment just makes it chunky. This is why the flat
-- and tilted views look fine and only the free camera reads as low resolution.
--
-- SUPERSAMPLING, not a bigger viewport. The target grows by `k` in each axis
-- and is blitted back at 1/k with linear filtering, so the DOWNSAMPLE is the
-- anti-aliasing. The projection is unaffected because a matrix depends on the
-- ASPECT, which k does not change, and 3D geometry lands in NDC and fills
-- whatever target is bound -- so the view shows exactly the same amount of
-- world. That containment is the whole point: growing `vw`/`vh` instead would
-- show MORE of Sinnoh than the game ever does, which is the 512x384 harness
-- trap this port has now walked into twice.
--
-- AND THE SPRITES COME ALONG FOR FREE, which is what makes this safe. The one
-- reader of `freeW`/`freeH` is `Gen4Ground:freeEntity`, which projects a
-- character through `view3d:project(..., vw, vh)` and applies the scale that
-- comes back. Setting them to the TARGET's size therefore moves every
-- character into target pixels with no graphics transform spanning the open
-- pass -- and a transform with that lifetime is exactly what has already
-- produced two `setCanvas` crashes in this file.
Gen4Ground.RENDER_SCALES = { 1, 2, 3, 4 }

-- Held on the MODULE rather than read from the save, for the reason
-- `Gen4Camera` records: the thing that needs it is built by `MapLoader.load`
-- and is never handed a game. `OverworldState:enter` closes the same gap for
-- this that it closes for the camera tilt.
Gen4Ground.renderScaleIndex = 1

function Gen4Ground.setRenderScale(index)
  index = tonumber(index) or 1
  if not Gen4Ground.RENDER_SCALES[index] then index = 1 end
  Gen4Ground.renderScaleIndex = index
  return Gen4Ground.RENDER_SCALES[index]
end

function Gen4Ground.renderScale()
  return Gen4Ground.RENDER_SCALES[Gen4Ground.renderScaleIndex] or 1
end

-- syncRenderScale(game) -> scale, index.  A no-op on every other generation:
-- the option is only ever written by the Gen 4 OPTIONS row, and an absent
-- value leaves the default of 1 alone -- which renders exactly as this pass
-- did before the setting existed.
function Gen4Ground.syncRenderScale(game)
  local o = game and game.save and game.save.options
  local index = o and tonumber(o.gen4RenderScale) or nil
  if index and Gen4Ground.RENDER_SCALES[index] then
    Gen4Ground.renderScaleIndex = index
  end
  return Gen4Ground.renderScale(), Gen4Ground.renderScaleIndex
end

function Gen4Ground:liveTargetFor(vw, vh)
  if self.liveW == vw and self.liveH == vh and self.liveColour then
    return self.liveColour, self.liveDepthBuf
  end
  -- RETRACTED BEFORE IT IS FREED, because it may still be published.
  --
  -- `endFree` hands this canvas to `Renderer:setWorldOverride` above 1x, and
  -- the renderer holds it until it composites the frame. Freeing it here left
  -- the renderer measuring a released object:
  --     Renderer.lua:997: Cannot use object after it has been released
  -- reported from Android when CAM TILT was stepped between CARTRIDGE and 90,
  -- which switches between the free and oblique passes and so asks for a
  -- different target size -- the one thing that reaches this branch.
  --
  -- Whoever publishes a canvas owns the retraction: the renderer cannot know
  -- when we free it, and there is no way to ask a LOVE object whether it is
  -- still alive. Only OUR canvas is withdrawn -- a mod pipeline's override is
  -- left alone.
  if self.liveColour then
    local got, Game = pcall(require, "src.core.Game")
    local renderer = got and Game and Game.renderer
    if renderer and renderer.worldOverride == self.liveColour
       and renderer.setWorldOverride then
      renderer:setWorldOverride(nil)
    end
    -- ...and the module-global the free pass blits from, for the same reason:
    -- it outlives the ground that opened the pass (see `freeOpen`).
    if Gen4Ground.freeColour == self.liveColour then
      Gen4Ground.freeColour = nil
    end
  end
  if self.liveColour and self.liveColour.release then pcall(self.liveColour.release, self.liveColour) end
  if self.liveDepthBuf and self.liveDepthBuf.release then pcall(self.liveDepthBuf.release, self.liveDepthBuf) end
  self.liveColour, self.liveDepthBuf = Gen4Model.newTarget(vw, vh)
  if not self.liveColour then
    -- Same latch as the bake path's, and said for the same reason: a ground
    -- that silently stops drawing looks exactly like a ground that has nothing
    -- to draw.
    Logger.warn("gen4 ground: %s could not allocate a %dx%d live target -- "
                .. "falling back to the baked path for the rest of the session",
                tostring(self.def and self.def.id), vw, vh)
    self.liveOff = true
    self.liveW, self.liveH = nil, nil
    return nil
  end
  self.liveW, self.liveH = vw, vh
  return self.liveColour, self.liveDepthBuf
end

-- One pass over the visible chunks, into one target, with the spread on.
-- `yCut` nil draws the whole world; the canopy pass passes a cut and a colour
-- mask instead of owning a second loop.
-- The lean, for the coverage report below -- read through one accessor so the
-- report and the pass cannot disagree about which number they mean.
local function sinPOf(self) return self.groundScale or 1 end

-- WHERE THE PLAYER IS, IN MAP PIXELS, AND THE ONE PLACE IT IS DERIVED.
--
-- The overworld keeps the player at the centre of the view, so the centre IS
-- the player to within the follow distance -- the identity the free camera
-- already places itself with, and the reason none of this needs a new
-- argument threaded through four files.
--
-- It was spelled out FOUR separate times before this existed: the short-prop
-- sort's `playerZ`, the height spread's datum, the free camera's eye, and the
-- canopy cut.  Four copies of one derivation is the shape every bug in this
-- file has had -- the same thing spelled differently in two places that never
-- meet -- so there is one now.
function Gen4Ground:viewCentre(camX, camY, vw, vh)
  local sinP = self.groundScale or 1
  if not (sinP > 1e-6) then sinP = 1 end
  return (camX or 0) + (vw or 0) / 2, (camY or 0) + (vh or 0) / (2 * sinP)
end

-- THE CANOPY CUT, RELATIVE TO THE GROUND THE PLAYER IS STANDING ON.
--
-- Reported from play: *"using the cartridges camera view makes sprites
-- dissapear when walking on an area that has a higher terrain"*.
--
-- `CANOPY_Y` is 32 because that is how high a character reaches, and the pass
-- paints everything ABOVE the cut over the sprites.  Stated as an ABSOLUTE
-- world height that is only ever right at sea level: climb a hill and the
-- floor underfoot is itself above 32, so the canopy paints the ground out
-- from under the player and takes the player with it.
--
-- MEASURED over 60,606 plated tiles across 80 chunks: 12,831 of them --
-- 21.2% -- stand above 32, spread over 30 of the 80.  A fifth of Sinnoh
-- paints over the player, which is exactly what was reported.
--
-- So the cut is the ground under the player PLUS head height, which is what
-- the number always meant.  At sea level it is still 32 and nothing moves.
-- WHERE THE PLAYER ACTUALLY IS, for the canopy pass: handed over by the
-- overworld right before it (`focusX`/`focusZ`, map pixels, the feet), and the
-- view centre only when nobody did. The view centre is NOT the player whenever
-- the background offset the canopy is drawn with differs from the camera's --
-- and both the height cut and the band behind the player were being measured
-- from wherever the screen's middle happened to be.
function Gen4Ground:focus(camX, camY, vw, vh)
  if self.focusX and self.focusZ then return self.focusX, self.focusZ end
  return self:viewCentre(camX, camY, vw, vh)
end

function Gen4Ground:canopyCut(camX, camY, vw, vh)
  local ex, ey = self:focus(camX, camY, vw, vh)
  return (self:groundY(ex, ey) or 0) + CANOPY_Y
end

function Gen4Ground:livePass(camX, camY, vw, vh, yCut)
  local grid = self.grid
  if not grid then return 0 end
  local px = self.chunkPx
  local sinP = self.groundScale or 1
  local left = camX + self.offsetX
  local top = camY + self.offsetY
  local x0, y0 = math.floor(left / px), math.floor(top / px)
  local x1 = math.floor((left + vw) / px)
  local y1 = math.floor((top + vh / sinP) / px)
  -- HOW FAR DOWN THE CANVAS THE GROUND ACTUALLY REACHES, in view rows.
  --
  -- The black band under a Gen 4 map has survived five fixes that were each
  -- real, and the reason it keeps surviving is that nobody has measured the
  -- one number that decides it: whether the ground COVERS the canvas it is
  -- painting into. Every reading of this file says it does -- `y1` is derived
  -- from `vh / sinP` precisely so that it should -- and a reading has now been
  -- wrong five times.
  --
  -- `(y1 + 1) * px` is the bottom edge of the last chunk row this pass will
  -- touch, in matrix pixels; minus `top` puts it in world rows below the
  -- camera, and the lean puts it in view rows. If that is less than `vh`, the
  -- bottom of the canvas was never painted and the difference IS the band, in
  -- the same units the screenshot shows it in.
  self.liveReach = ((y1 + 1) * px - top) * sinP
  self.liveWant = vh
  local spread = self.spread
  local g = love.graphics
  local drawn = 0
  -- WHERE THE PLAYER IS, for the short-prop sort -- from `viewCentre`, which
  -- is the only place that identity is written down now.
  local _, pz = self:focus(camX, camY, vw, vh)
  local playerZ = pz + (self.offsetY or 0)

  for cy = y0, y1 do
    for cx = x0, x1 do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local model = self:liveModel(land)
        if model then
          -- THE CHUNK'S ALTITUDE, on the model and on everything standing on
          -- it -- shadowed here so the props below inherit the same lift.
          local lift = self:chunkLift(cx, cy)
          local mvp = liftMatrix(
            self:screenMatrix(cx * px - left, cy * px - top, vw, vh), lift)
          local spread = liftedSpread(spread, lift)
          local yCut = yCut and (yCut - lift)
          if yCut then
            -- The floor goes in with the COLOUR MASK OFF so the depth buffer
            -- still hides what a hill should hide, and then AGAIN with the cut
            -- so a treetop the player walks under is painted over them.  Both
            -- passes are `bakeCanopy`'s, moved here unchanged.
            local r, gg, b, a = g.getColorMask()
            g.setColorMask(false, false, false, false)
            model:draw(mvp, nil, nil, nil, spread)
            g.setColorMask(r, gg, b, a)
            -- LEQUAL, NOT LESS, AND THIS IS THE WHOLE OF "TREES DO NOT MASK
            -- THE PLAYER".
            --
            -- The pass above just wrote depth for this exact geometry, so
            -- every fragment of this second draw sits at EXACTLY that depth.
            -- Under the default "less" every one is rejected and the terrain
            -- canopy paints NOTHING -- measured at 0 samples against 13,507
            -- with "lequal", on Twinleaf's chunk 0.
            --
            -- The buildings below were never affected because they are drawn
            -- ONCE in this pass, against depth nothing else has written. That
            -- asymmetry is exactly what play-testing reported: *"trees should
            -- mask the players character ... but houses do perfectly"*.
            -- ...EXCEPT THE GROUND JUST BEHIND THE PLAYER.
            --
            -- Reported from play on Route 207: *"The mud slides are over my
            -- character when i walk up to them when they shouldnt be"*. The
            -- cut is a HEIGHT rule -- anything 32 units above the player's
            -- ground is painted after the sprites -- and a ramp rising north
            -- of the player passes it while being BEHIND them. The cartridge
            -- draws in real 3D and a billboard in front of a slope is never
            -- covered by it.
            --
            -- Only a narrow band can do that: terrain behind the feet lands on
            -- the sprite's 32 rows only within about two tiles, since every
            -- unit further back and every unit higher moves it further up the
            -- screen. So that band -- the player's own tile and 40 units north
            -- -- is left out of the cut pass, and everything else keeps the
            -- old rule: a cliff or treetop SOUTH of the player still covers
            -- them, and terrain further north still covers an NPC behind it.
            local chunkZ = cy * px + self.half
            Gen4Model.zKeep = { playerZ - KEEP_BEHIND - chunkZ,
                                playerZ + KEEP_FEET - chunkZ }
            model:draw(mvp, nil, nil, yCut, spread, "lequal")
            Gen4Model.zKeep = nil
          else
            model:draw(mvp, nil, nil, nil, spread)
          end
          drawn = drawn + 1
          local record = self.terrain.chunks[land]
          for _, object in ipairs(self:objectsFor(land, record)) do
            local building = self:building(object.model, object.archive)
            if building then
              -- A MOVING PROP RUNS HERE NOW, on the frame clock, instead of
              -- needing a canvas of its own re-baked whenever it ticked.
              local mats = self:propMaterials(object, self.clock)
              -- The cut is stated in WORLD units and the shader tests MODEL
              -- ones, so the object's own lift and scale come back off before
              -- it is sent -- the same arithmetic `bakeCanopy` does.
              local cut, skip = nil, false
              if yCut then
                local sy = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
                -- THE PROP'S OWN HEIGHT, NOT ITS HEIGHT ABOVE SEA LEVEL.
                --
                -- `SORTED_BELOW` asks "is this shorter than a character", and
                -- its own comment measures it that way -- *"338 of them top
                -- out below CANOPY_Y"* is a statement about MODELS.  Adding
                -- `object.y` turned it into a question about the prop's
                -- ALTITUDE, and measured over all 3,476 placed props, 889 --
                -- 25.6% -- carry a lift of 32 or more before any model height
                -- at all.  Every one was forced down the TALL branch however
                -- short it really is, where the cut came out at `(32 - y)/sy`
                -- <= 0 and painted the ENTIRE prop over the sprites: a chair
                -- on a plateau hiding the player standing beside it.
                local ownTop = building:topY() * sy
                if ownTop <= SORTED_BELOW then
                  -- SHORT: sorted, not cut.  `playerZ` is the view's own
                  -- centre, which the overworld keeps the player at, so this
                  -- needs nothing passed in that the pass does not already
                  -- have.
                  local worldZ = cy * px + self.half + (object.z or 0)
                  if worldZ > (playerZ or 0) then
                    cut = nil          -- the whole prop goes over the sprite
                  else
                    skip = true        -- the player is in front of it
                  end
                else
                  cut = (yCut - (object.y or 0)) / sy
                end
              end
              if not skip then
                building:draw(Gen4Model.multiply(mvp, placement(object)),
                              self:oneShotPose(object, building),
                              mats, cut, spread)
              end
            end
          end
        end
      end
    end
  end
  return drawn
end

-- ---------------------------------------------------------------------------
-- FIRST AND THIRD PERSON
-- ---------------------------------------------------------------------------
--
-- A free camera cannot use `screenMatrix`: that one is OBLIQUE, has no yaw,
-- and scales its two axes by different amounts on purpose.  `Gen4View` builds
-- a real perspective matrix instead, which is also what answers the stated
-- requirement -- *"without stretching the textures or models of the house"*.
-- `Gen4Model.perspective` divides x by the aspect ratio and leaves y alone, so
-- a square in the world is a square on screen at any window size and a wall's
-- texture keeps its proportions however the wall is turned.
--
-- THE HEIGHT SPREAD IS SWITCHED OFF HERE, and that is not an omission.  It is
-- a first-order stand-in for a perspective divide that the field view does not
-- have; a real perspective camera performs the whole divide, and applying both
-- would count the same effect twice.

-- How far out to draw, in chunks, around the one the camera stands on.
--
-- Two is the smallest radius that reaches the far side of a neighbouring chunk
-- at eye level: the camera can stand at a chunk's edge, so a radius of one
-- leaves geometry missing 512 units ahead, which at this field of view is well
-- inside the visible distance.  The frustum and the depth buffer discard what
-- does not land; this only bounds how much is offered to them.
local FREE_RADIUS = 2

local function translation(x, y, z)
  return { 1, 0, 0, x,
           0, 1, 0, y,
           0, 0, 1, z,
           0, 0, 0, 1 }
end

-- Put the camera where the mode says, in ABSOLUTE matrix coordinates.
--
-- `px`/`py` are the player's position in this map's own pixels, which is what
-- the overworld holds; the map's origin goes on here so the camera speaks the
-- same absolute space the chunks are laid out in and does not have to care
-- which of the six maps on screen it is standing on.
function Gen4Ground:placeCamera(px, py, facing)
  if not (self.view3d and self.view3d:isFree()) then return end
  -- ...standing on whatever the height map says is under them, so every
  -- height in `Gen4View` means "above the player's feet" rather than "above
  -- absolute zero".  `groundY` takes MAP coordinates, which is what `px`/`py`
  -- already are -- the offsets go on afterwards, for the camera only.
  -- AIMED AT WHERE THE PLAYER STANDS, which is the middle of their tile and
  -- not its corner.
  --
  -- Reported from play: *"in third person when zoomed in the player isnt
  -- centered, zoomed out it is though"*, with a screenshot showing them well
  -- right of centre.  `freeEntity` anchors a character's feet at
  -- `(mapX + FEET_X, mapY + FEET_X)` -- the tile's CENTRE -- and this aimed at
  -- `(px, py)`, its CORNER.  Eight units apart, in both axes.
  --
  -- Eight units is a handful of pixels with the camera far back and grows with
  -- the zoom, because the scale is pixels-per-unit at the eye's distance.
  -- Measured on a 512-wide frame: 13 px off at the far stop, 34.6 at rest,
  -- 76.5 at the near one -- which on a full-width window is most of the way
  -- to the edge of the player. That is exactly "wrong zoomed in, fine zoomed
  -- out", and it is why the pass-47 centring check did not catch it: that
  -- check projected the PIVOT, which is the point the camera aims at by
  -- definition and therefore cannot disagree with itself.
  local fx = (px or 0) + Gen4Ground.FEET_X
  local fz = (py or 0) + Gen4Ground.FEET_X
  self.view3d:follow(fx + (self.offsetX or 0), fz + (self.offsetY or 0),
                     facing, self:groundY(fx, fz))
  -- ...and say so, so `draw` does not overwrite it with its own estimate.
  self.cameraPlaced = true
end

-- THE SKY BEHIND A FREE CAMERA.
--
-- Requested, with the artwork supplied.  The field view never needed one -- it
-- looks down at the ground and the DS fills the rest with a backdrop colour --
-- but a camera you can raise to the horizon shows whatever lies past the last
-- chunk, which until now was the clear colour.
--
-- MIRRORED INTO A SEAMLESS TILE at import: the image is laid beside its own
-- mirror image, so the first and last column are the same pixels and a full turn
-- of the camera crosses no seam.  Verified on the file -- the worst difference
-- between those two columns is 0.
-- TWO SHEETS AND A FADE BETWEEN THEM, requested with both pieces of artwork
-- supplied: *"apply this updated skybox and a nighttime variant as well based on
-- the time it should fade between the two"*.  Which way the fade sits is
-- `Gen4Shade.nightness`, off the cartridge's own light keyframes -- see there.
Gen4Ground.SKY_DAY = "assets/sky/gen4_sky_day.png"
Gen4Ground.SKY_NIGHT = "assets/sky/gen4_sky_night.png"
-- The single name this started as, still read when the pair is absent, so a tree
-- that has not taken the new art keeps a sky rather than losing one.
Gen4Ground.SKY_IMAGE = "assets/sky/gen4_sky.png"
-- The panorama spans 360 degrees across its width, by definition rather than
-- by choice -- see `drawSky`.

local function loadSkySheet(path)
  local ok, img = pcall(Assets.image, path)
  if not (ok and img) then return nil end
  img:setWrap("repeat", "clamp")
  -- Nearest, like every other texture here: the artwork is pixel art and a
  -- linear filter turns its edges to mush against the rest of the scene.
  img:setFilter("nearest", "nearest")
  return img
end

-- skySheets() -> day, night.  Night is nil when there is no night sheet, and the
-- caller then draws the day one alone rather than nothing.
function Gen4Ground:skySheets()
  if self.sky == nil then
    local day = loadSkySheet(Gen4Ground.SKY_DAY)
                or loadSkySheet(Gen4Ground.SKY_IMAGE)
    local night = loadSkySheet(Gen4Ground.SKY_NIGHT)
    -- BOTH SHEETS ARE DRAWN WITH ONE SET OF NUMBERS -- one quad, one scale, one
    -- horizon -- because that is what makes the fade a cross-fade and not a
    -- slide.  A night sheet of a different size would not register with the day
    -- one: the same yaw would land on different clouds and the sky would appear
    -- to drift sideways as it darkened.  So it is DROPPED rather than stretched,
    -- which keeps the day sky exactly right and loses only the night.
    if day and night then
      local dw, dh = day:getDimensions()
      local nw, nh = night:getDimensions()
      if dw ~= nw or dh ~= nh then
        Logger.warn("gen4 sky: the night sheet is %dx%d but the day sheet is "
                    .. "%dx%d -- the two cannot register, so night is dropped",
                    nw, nh, dw, dh)
        night = nil
      end
    end
    self.sky = day or false
    self.skyNight = night or false
  end
  return self.sky or nil, self.skyNight or nil
end

-- Drawn FIRST and with no depth at all, so every chunk and prop lands on top of
-- it and it can never occlude anything.  The world writes depth; the sky does
-- not take part.
-- A SPRITE THAT TAKES PART IN THE DEPTH BUFFER.
--
-- Reported from play, more than once: *"3d objects dont seem to mask the player
-- or 3d sprites still ... especially in 3rd person or first person"*.
--
-- The free pass drew the whole world into a target WITH a depth buffer and then
-- blitted it to the screen, and only afterwards did the overworld draw its
-- characters -- on top of a finished picture, with nothing left to test against.
-- No amount of sorting fixes that; the sprite has to be in the target while the
-- depth is still there.
--
-- It cannot go through `SPRITE_SHADER`: that one places a quad itself, and an
-- entity's own `draw` is what knows its sheet, frame, palette and followers.
-- So this shader leaves the 2D transform exactly as LOVE built it and overrides
-- ONLY the depth -- `p.z = spriteZ * p.w` survives the perspective divide as
-- `spriteZ` -- which lets any ordinary draw call land at a chosen depth.
--
-- ONE DEPTH FOR THE WHOLE SPRITE, taken at its feet.  A character is a flat
-- card in a 3D world, and the question being asked is "is this card in front of
-- that house" -- which has one answer.  Per-pixel depth would need the sprite to
-- carry geometry it does not have.
local DEPTH_SPRITE_SHADER = [[
#ifdef VERTEX
uniform float spriteZ;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 p = transform_projection * vertex_position;
    p.z = spriteZ * p.w;
    return p;
}
#endif
#ifdef PIXEL
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen)
{
    vec4 texel = Texel(tex, uv);
    // A transparent texel must not write depth, or the square around a
    // character would occlude whatever is behind it -- the same rule the model
    // shader states for a leaf and the sprite shader states for a character.
    if (texel.a < 0.02) { discard; }
    return texel * colour;
}
#endif
]]

local depthSprite
local function ensureDepthSprite()
  if depthSprite == nil then
    local ok, made = pcall(love.graphics.newShader, DEPTH_SPRITE_SHADER)
    depthSprite = (ok and made) or false
    if not depthSprite then
      Logger.error("gen4 ground: the depth-sprite shader would not compile (%s)"
                   .. " -- characters cannot be masked by the world",
                   tostring(made))
    end
  end
  return depthSprite or nil
end

function Gen4Ground:drawSky(view, vw, vh)
  -- Indoors there is a ceiling, and a panorama behind it is just wrong.
  if self.outdoors == false then return false end
  local img, night = self:skySheets()
  if not (img and view and vw and vh and vw > 0 and vh > 0) then return false end
  local g = love.graphics
  local iw, ih = img:getDimensions()
  -- THE FOV THE WORLD IS ACTUALLY DRAWN WITH, which on a tilt rung is not
  -- `view.fovY`: a field camera derives its fov from the target height so a
  -- unit stays a pixel.  The sky is locked to the world by matching its
  -- pixels-per-degree, so reading a different fov here would unlock it.
  local fov = view.effectiveFovY and view:effectiveFovY(vh)
              or ((view.fovY and view.fovY > 0) and view.fovY or 50)
  if not (fov and fov > 0) then fov = 50 end

  -- THE SKY IS AT INFINITY, AND THAT FIXES EVERY NUMBER HERE.
  --
  -- Reported from play: *"the skybox seems to move when i look around as well
  -- rather than seeming like a static sky"* -- and it did, because the first
  -- version scrolled it `SKY_TURNS` copies per revolution with a scale picked
  -- to look right.  Two copies per turn is a sky moving at twice the world's
  -- rate, which the eye reads as the SKY turning rather than the camera.
  --
  -- There is nothing to tune.  A cloud infinitely far away sits at a fixed
  -- WORLD DIRECTION, so the panorama must span 360 degrees across its width
  -- exactly once, and one degree of yaw must move it by exactly the screen
  -- distance one degree of the world moves.
  local aspect = vw / vh
  local hfov = 2 * math.deg(math.atan(math.tan(math.rad(fov / 2)) * aspect))
  -- Screen pixels per degree, from the camera's own field of view -- the same
  -- number the world is drawn with, which is what keeps the two locked.
  local pxPerDeg = vw / hfov
  local scale = pxPerDeg * 360 / iw

  local yawDeg = math.deg(view.yaw or 0) % 360
  local u = (yawDeg / 360) * iw

  -- WHERE THE HORIZON IS, in screen pixels -- LOCKED TO THE WORLD, exactly
  -- like the yaw.
  --
  -- THE SIGN HERE HAS BEEN WRONG TWICE, in opposite directions, and the second
  -- time was mine.
  --
  -- It began as `vh * 0.5 + pitch * pxPerDeg`.  Positive pitch in this engine
  -- is looking DOWN -- `forward()` returns `-sin(pitch)` for y -- and a camera
  -- looking down puts the horizon ABOVE the centre of the view, at
  -- `vh/2 - pitch * pxPerDeg`.  So the original moved the sky the WRONG WAY:
  -- it slid down as the world slid up, which reads as a sky travelling at
  -- double rate against the ground.  That is the original report.
  --
  -- Pass 46 then read *"the skybox shouldnt move when moving camera up or
  -- down"* as "pin it to the screen" and set this to `vh * 0.5` flat.  That
  -- removed the double rate by removing the response altogether, which is
  -- worse in a way that is easy to miss: a sky that holds still on the screen
  -- is a sky glued to the camera.  Reported straight back --
  --     *"the sky keep its look moving it with the camera rather than the
  --     clouds staying in the same place and me looking up beyond the cloud
  --     im looking at"*
  -- -- and that sentence is the specification.  A cloud is a fixed direction
  -- in the world; looking up must carry the view PAST it.
  --
  -- The correct term is the negative one, and it is not a taste: it is where a
  -- point at infinity on the eye plane actually projects.  Checked against the
  -- world rather than by eye -- `drawSky`'s horizon row is compared with the
  -- projection of a far-off point at the camera's own height, and the two have
  -- to land on the same pixel at every pitch.  Nothing here is tuned.
  --
  -- AND IT IS NOT LINEAR IN THE PITCH.  `vh/2 - pitch * pxPerDeg` is the
  -- small-angle form and it was measured against the world rather than
  -- trusted: it tracks to about two pixels at the resting pitch and then
  -- comes apart, 89 px out at 50 degrees and 845 px out at the top of the
  -- orbit.  A direction `a` off the view axis lands at
  -- `tan(a) / tan(fovY/2)` in normalised device units, not at `a` times a
  -- constant, so the horizon -- which sits `pitch` above the axis -- is:
  local tanHalf = math.tan(math.rad(fov / 2))
  local horizon = vh * 0.5 * (1 - math.tan(math.rad(view.pitch or 0)) / tanHalf)
  local top = horizon - ih * scale

  local quad = g.newQuad(u, 0, vw / scale, ih, iw, ih)
  -- Below the horizon the panorama has nothing to say and the world has not
  -- drawn yet, so the strip under it takes the artwork's own bottom row rather
  -- than the clear colour showing through as a hard band.
  local hemY = top + ih * scale
  local hem = (hemY < vh) and g.newQuad(u, ih - 1, vw / scale, 1, iw, ih) or nil
  local hemH = vh - hemY

  local mode, write = g.getDepthMode()
  local shader = g.getShader()
  g.setShader()
  g.setDepthMode("always", false)

  -- ONE SET OF NUMBERS, BOTH SHEETS.  Everything above was derived for a sky at
  -- infinity, and the night sheet is the same sky -- so it takes the same quad,
  -- scale and horizon, and the fade happens purely in the alpha.  Drawing it
  -- with its own transform is how a cross-fade turns into two skies sliding
  -- past each other.
  local function sheet(image, alpha)
    g.setColor(1, 1, 1, alpha)
    g.draw(image, quad, 0, top, 0, scale, scale)
    if hem then g.draw(image, hem, 0, hemY, 0, scale, hemH) end
  end

  -- HOW DARK IT IS, from the cartridge's light keyframes by way of
  -- `applyLight`.  Nil is not night and not day -- it is a member with no day
  -- cycle at all (the indoor ones), and those never reach here anyway because
  -- of the `outdoors` gate above.
  local n = self.nightness or 0
  if n < 1 or not night then sheet(img, 1) end
  -- DAY FIRST AND OPAQUE, night over it at the fade's own alpha.  That ordering
  -- is what makes a partial fade read as dusk rather than as a hole: the night
  -- sheet's own pixels are opaque, so at alpha 0.5 the two are genuinely mixed
  -- instead of the clear colour showing through both.
  if night and n > 0 then sheet(night, n) end

  g.setColor(1, 1, 1, 1)
  g.setDepthMode(mode, write)
  g.setShader(shader)
  return true
end

function Gen4Ground:drawFree(vw, vh)
  local view = self.view3d
  local grid = self.grid
  if not (view and grid) then return false end
  local px = self.chunkPx
  local lw, lh = math.floor(vw or 0), math.floor(vh or 0)
  if lw < 1 or lh < 1 then return false end
  -- THE TARGET IS THE LOGICAL VIEW TIMES THE SUPERSAMPLE; see RENDER_SCALES.
  -- At the default of 1 every line below is the arithmetic it always was.
  local scale = Gen4Ground.renderScale()
  local tw, th = lw * scale, lh * scale
  local colour, depth = self:liveTargetFor(tw, th)
  if not colour then return false end
  -- LINEAR ONLY WHEN IT IS BEING SHRUNK. `Gen4Model.newTarget` files every
  -- target as nearest, which is right at 1:1 and is what makes a downsampled
  -- one look no better than the small one it came from.
  if colour.setFilter then
    pcall(colour.setFilter, colour,
          scale > 1 and "linear" or "nearest",
          scale > 1 and "linear" or "nearest")
  end

  -- KEPT FOR THE ENTITY PASS, which is handed a camera and not a viewport.
  -- Same reasoning as `worldTop` in `beginWorld`: the projection a sprite is
  -- placed by has to be the one the world was drawn with, and the only way
  -- to be sure is for the drawing pass to record it rather than the caller
  -- to reconstruct it.
  -- IN TARGET PIXELS, deliberately: `freeEntity` projects every character
  -- through these, so this is what carries the sprites into the supersampled
  -- frame without a transform spanning the open pass.
  self.freeW, self.freeH = tw, th
  local camCx = math.floor(view.x / px)
  local camCy = math.floor(view.z / px)
  local vp = view:matrix(tw, th)

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ colour, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  self:drawSky(view, tw, th)
  -- TURN THE CARDS TO FACE THIS CAMERA, for the length of this pass only.
  --
  -- Requested: *"fix the trees so they always face the camera rotating"*.
  -- Set here rather than in `bake`, because a chunk's mesh is built once and
  -- the camera turns every frame -- the rotation has to be in the shader, and
  -- this is the one number it needs.  Put back to zero at the end of the pass
  -- so no other caller inherits it.
  Gen4Model.billboardYaw = view.yaw or 0
  local drawn = 0
  for cy = camCy - FREE_RADIUS, camCy + FREE_RADIUS do
    for cx = camCx - FREE_RADIUS, camCx + FREE_RADIUS do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local model = self:liveModel(land)
        if model then
          -- A chunk's own vertices are centred on it, so its centre -- not its
          -- corner -- is where it goes in the absolute grid.
          local mvp = Gen4Model.multiply(vp,
            translation(cx * px + self.half, self:chunkLift(cx, cy),
                        cy * px + self.half))
          model:draw(mvp, nil, nil, nil, nil)
          drawn = drawn + 1
          local record = self.terrain.chunks[land]
          for _, object in ipairs(self:objectsFor(land, record)) do
            local building = self:building(object.model, object.archive)
            if building then
              local mats = self:propMaterials(object, self.clock)
              building:draw(Gen4Model.multiply(mvp, placement(object)),
                            self:oneShotPose(object, building),
                            mats, nil, nil)
            end
          end
        end
      end
    end
  end
  -- THE TARGET STAYS BOUND, and that is the whole of the masking fix.
  --
  -- Blitting here ends the frame's 3D: the depth buffer is still full of
  -- the world, but the characters are drawn afterwards onto a flat picture
  -- and have nothing to test against.  So the pass is left OPEN, the
  -- entity pass draws into it through `freeEntity`, and `drawCanopy` --
  -- which the overworld already calls after the sprites -- closes it.
  -- ON THE MODULE, NOT ON THIS GROUND, and that is a CRASH FIX.
  --
  -- Reported from play, on leaving a building in third person:
  --     Gen4Ground.lua: bad argument #4 to 'setCanvas' (Canvas expected,
  --     got table)
  -- A map change builds a NEW Gen4Ground, and the old one's pass was still
  -- open with its canvas still bound.  The new ground's `freeOpen` is nil, so
  -- its own net saw nothing to close, and the first thing downstream to run
  -- `{ g.getCanvas() }` captured a set that was bound as
  -- `{ colour, depthstencil = depth }` -- which is not a plain canvas list,
  -- and handing it back to `setCanvas` is the raise above.
  --
  -- A canvas binding is global state, so the record of it has to be global
  -- too: whichever ground draws next can then close a pass any ground opened.
  -- Same reasoning as `Gen4View.look`, and for the same kind of bug -- state
  -- that outlives the object the map loader throws away.
  Gen4Ground.freeOpen = true
  Gen4Ground.freePrevious = previous
  Gen4Ground.freeColour = colour
  -- ON THE MODULE beside the rest of the pass's state, and for the same
  -- reason: `endFree` may be called by a DIFFERENT ground than the one that
  -- opened the pass, so the factor it has to undo cannot live on `self`.
  Gen4Ground.freeScale = scale

  local key = ("free/%s/%d/%d"):format(tostring(view.mode), drawn, scale)
  if self.reportedPath ~= key then
    self.reportedPath = key
    Logger.info("gen4 ground: %s drew %s PERSON -- %d chunk(s), %dx%d target, "
                .. "eye (%d,%d,%d) yaw %.1f deg pitch %.1f deg, fov %.1f",
                tostring(self.def and self.def.id), view.mode:upper(), drawn,
                tw, th, view.x, view.y, view.z,
                math.deg(view.yaw or 0), view.pitch or 0, view.fovY)
  end
  Gen4Model.billboardYaw = 0
  if drawn > 0 then return true end

  -- NOTHING REACHED THE TARGET THIS FRAME, and this is the SECOND face of the
  -- setCanvas crash.
  --
  -- Reported from play, on switching third person to first:
  --     Gen4Ground.lua: bad argument #4 to 'setCanvas' (Canvas expected,
  --     got table)
  -- This function binds the target and marks the pass open well above, and
  -- then ended on `return drawn > 0`.  A false there is not "I did nothing" --
  -- THE CANVAS IS BOUND -- but `draw` reads it as "the free pass declined, use
  -- the live one", falls through, and the live pass opens with
  -- `{ g.getCanvas() }`, capturing a binding made as
  -- `{ colour, depthstencil = depth }`.  Handing that back to `setCanvas` is
  -- the raise.
  --
  -- `drawn` is zero whenever no chunk is READY rather than whenever none
  -- exists: `bake` is budgeted at `BAKES_PER_FRAME`, so the first frames after
  -- a map load or a mode switch legitimately have nothing built yet.  That is
  -- exactly when it was reported, both times.
  --
  -- The fallback to the live pass is worth keeping -- it is what draws the
  -- world while the bakes catch up -- so the pass is CLOSED here rather than
  -- the fallback removed.  `endFree` restores the canvas and blits what the
  -- target does hold (the sky); the live pass then paints the world over it.
  self:endFree()
  return false
end

-- ---------------------------------------------------------------------------
-- SPRITES IN THE WORLD'S OWN DEPTH BUFFER
-- ---------------------------------------------------------------------------
--
-- Play report: *"many indoor objects when walked behind dont mask the player
-- but houses do perfectly"*.
--
-- `CANOPY_Y` is a fixed world height of 32 and it is the WRONG MECHANISM, not
-- the wrong number.  Measured over all 590 building models, **338 of them --
-- 57.3% -- are entirely below it** and can therefore never mask anything, in
-- any room.  `shelf01` and `shelf05` top out at exactly 32.00 and fail on the
-- shader's `<=`; `table_l01` is 30, `machine_pc01` 24.16, `shelf_fs01` 21.
--
-- And RAISING the cut cannot fix it.  The cut paints the part of an object
-- ABOVE head height over the sprites, so for anything SHORTER than a character
-- there is nothing it can express: a shelf should hide a player's legs and
-- leave their head showing, which is not "above 32" of anything.
--
-- The cartridge has no cut.  It draws the world and the characters into one
-- depth-buffered 3D scene and occlusion falls out.  The live pass finally makes
-- that possible here, because the world is already rendered into a target with
-- a depth buffer -- so a character drawn into the SAME target at the SAME
-- depth the ground was drawn with is occluded correctly by everything, with no
-- height rule anywhere.
--
-- Three calls instead of one, because the entity pass runs between them:
--
--     ground:beginWorld(camX, camY, vw, vh)   -- target bound, ground drawn
--     ground:drawSprite(...)                  -- once per character
--     ground:endWorld()                       -- unbound and blitted
--
-- `draw` is untouched and still works for callers that have not been moved
-- over, so this can land before the overworld uses it.

local SPRITE_SHADER = [[
#ifdef VERTEX
// The quad arrives as 0..1 and is placed in TARGET PIXELS here, so the caller
// does not have to know this canvas's NDC convention -- which is the one that
// rendered the whole map upside down the first time it was written out.
uniform vec4 spriteRect;     // x, y, w, h, in target pixels
uniform vec2 targetSize;
uniform float spriteDepth;   // already in the same units the chunk matrix uses
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    float px = spriteRect.x + vertex_position.x * spriteRect.z;
    float py = spriteRect.y + vertex_position.y * spriteRect.w;
    return vec4(2.0 * px / targetSize.x - 1.0,
                2.0 * py / targetSize.y - 1.0,
                spriteDepth, 1.0);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen)
{
    vec4 texel = Texel(tex, uv);
    // A transparent texel must not write depth, or the square around a
    // character would occlude whatever is behind it -- the same rule the model
    // shader states for a leaf.
    if (texel.a < 0.5) { discard; }
    return texel * colour;
}
#endif
]]

local spriteShader, spriteMesh

local function ensureSprite()
  if spriteShader == nil then
    local ok, made = pcall(love.graphics.newShader, SPRITE_SHADER)
    spriteShader = (ok and made) or false
    if not spriteShader then
      Logger.error("gen4 ground: the sprite shader would not compile (%s) -- "
                   .. "characters cannot be depth-sorted against the world",
                   tostring(made))
    end
  end
  if spriteMesh == nil and spriteShader then
    local format = { { "VertexPosition", "float", 2 },
                     { "VertexTexCoord", "float", 2 } }
    local ok, made = pcall(love.graphics.newMesh, format,
      { { 0, 0, 0, 0 }, { 1, 0, 1, 0 }, { 1, 1, 1, 1 }, { 0, 1, 0, 1 } },
      "fan", "static")
    spriteMesh = (ok and made) or false
  end
  return spriteShader or nil, spriteMesh or nil
end

-- Open the world pass and leave its target bound.
-- Which free mode is up, or nil for the field view.  A one-call question so a
-- caller does not have to know that `view3d` exists or what nil means.
-- THE CARTRIDGE'S OWN PROP-SHADOW TEXTURE, borrowed from a model that has one.
--
-- 153 of the 590 prop models ship a shadow shape whose material is `h_kage`,
-- and that texture -- 16x16, every texel opaque -- is the shadow Platinum
-- draws under its own props.  A generated one should wear it rather than
-- anything invented, so the shadow under a sofa is the same art as the shadow
-- under a gate.
--
-- Searched rather than named: the file lives beside whichever model owns it
-- (`models/buildings/t1_h01/h_kage.png` and so on), so there is no single path
-- to hard-code, and a cache built from a different ROM would put it elsewhere.
-- Found once and held; `false` means this cache has none and nothing is drawn
-- rather than a placeholder being invented.
--
-- IT MUST BE A REAL FILE.  `Assets.image` degrades to a placeholder when a
-- path is missing instead of raising, so a wrong path here does not fail --
-- it silently substitutes art that the model shader's `texel.a < 0.5` discard
-- then throws away, and the shadow is simply absent with nothing said.  That
-- cost a whole investigation: a generated shadow was measured as "does not
-- render" when what was really missing was the texture it was pointed at.
function Gen4Ground:shadowTexture()
  if self.shadowTex ~= nil then return self.shadowTex or nil end
  self.shadowTex = false
  local models = (self.buildingSet and self.buildingSet.models) or {}
  for _, packed in pairs(models) do
    if type(packed) == "table" then
      for _, shape in ipairs(packed.shapes or {}) do
        if shape.image
           and tostring(shape.material or ""):lower():find("kage", 1, true) then
          self.shadowTex = shape.image
          return self.shadowTex
        end
      end
    end
  end
  return nil
end

function Gen4Ground:freeMode()
  local view = self.view3d
  return (view and view:isFree()) and view.mode or nil
end

-- WHERE A CHARACTER'S FEET ARE, relative to their tile, in the flat view.
--
-- DERIVED, not guessed, and independent of the sprite's size, which is what
-- makes it safe to use for every entity. `SpriteRenderer:draw` puts the sheet's
-- top-left at `py - camY + cellYBias - (tileH - 16)`, so the BOTTOM edge is at
-- `py - camY + cellYBias + 16` -- the `tileH` cancels. With the default bias of
-- -4 that is `py - camY + 12`, for a 16x16 sprite and a 64x64 one alike. The
-- horizontal centre cancels the same way, at `px + 8`.
-- ON THE MODULE as well, because `placeCamera` is defined hundreds of lines
-- ABOVE this and a local declared here is not in scope up there.  The camera
-- and the sprite have to agree about where the player is standing, so they
-- must read the same number rather than each carry one.
Gen4Ground.FEET_Y = 12
Gen4Ground.FEET_X = 8
local FEET_Y, FEET_X = Gen4Ground.FEET_Y, Gen4Ground.FEET_X

-- freeEntity(mapX, mapY, camX, camY, rise, draw) -> handled
--
-- Draw a character through the FREE camera instead of flat on the screen.
--
-- Reported from play: *"isnt keeping the player the right size"*, and then
-- *"the player and npc sprite seems to be drawing below the ground"*. Under a
-- free camera the world is a real perspective and the sprites were still drawn
-- by `e:draw(cam.x, cam.y + riseOf(e))` -- their ordinary screen position at
-- their ordinary size.
--
-- THE SPRITE IS NOT REDRAWN, IT IS RE-PLACED. `draw` is the entity's own
-- unchanged draw call, run inside a transform that maps the point it would have
-- put the feet on to the point the projection says. That keeps this out of
-- sprite selection, animation frames, palettes and followers.
--
-- THE MAP POSITION COMES IN, NOT A PAIR OF SCREEN POINTS. The first version
-- took both and the caller got the anchor wrong by half a tile in each axis --
-- which lands a character low and south of where they stand, exactly the
-- "below the ground" report. The two spaces have to be derived from ONE
-- position or they can disagree, so they are derived here.
--
-- The height is the TERRAIN's, not zero: Twinleaf's ground is 16 units up, and
-- projecting a character at y = 0 puts them under it.
--
-- `depthLift`, when given, depth-tests the drawing at a point that many units
-- ABOVE the feet instead of at them, while it is still placed exactly as the
-- owner's sprite is. Sinnoh's "!" hangs 32 units up (Gen4Emotes): tested at
-- the feet it lost to every treetop behind its trainer and never showed.
function Gen4Ground:freeEntity(mapX, mapY, camX, camY, rise, draw, depthLift)
  if not self:freeMode() then return false end
  local vw, vh = self.freeW, self.freeH
  if not (vw and vh and draw) then return true end
  local gx = (mapX or 0) + FEET_X
  local gz = (mapY or 0) + FEET_X
  local sx, sy, scale, depth = self.view3d:project(gx + (self.offsetX or 0),
                                                   self:groundY(gx, gz),
                                                   gz + (self.offsetY or 0), vw, vh)
  -- Behind the eye. `project` returns nil rather than a mirrored point, and
  -- drawing nothing is right: a character behind the camera painted in front of
  -- it is worse than one absent.
  if not sx then return true end
  if depthLift and depthLift ~= 0 then
    local _, _, _, lifted = self.view3d:project(gx + (self.offsetX or 0),
                                                self:groundY(gx, gz) + depthLift,
                                                gz + (self.offsetY or 0), vw, vh)
    depth = lifted or depth
  end
  local g = love.graphics
  -- INTO THE WORLD'S DEPTH BUFFER, while the free pass is still open.
  --
  -- This is what makes a house hide a character who walks behind it. The
  -- shader leaves LOVE's own 2D transform alone -- the entity still draws
  -- itself, with its own sheet and frame -- and overrides only the depth,
  -- to the one `project` gave for the character's feet.
  --
  -- `lequal` rather than `less` for the reason the canopy needs it: a
  -- character standing exactly on a surface shares its depth, and `less`
  -- rejects equal.
  local shader, mode, write
  if Gen4Ground.freeOpen and depth then
    local sp = ensureDepthSprite()
    if sp then
      shader = g.getShader()
      mode, write = g.getDepthMode()
      g.setShader(sp)
      sp:send("spriteZ", depth)
      g.setDepthMode("lequal", true)
    end
  end
  g.push()
  g.translate(sx, sy)
  g.scale(scale, scale)
  g.translate(-(gx - (camX or 0)),
              -((mapY or 0) + FEET_Y - (camY or 0) - (rise or 0)))
  draw()
  g.pop()
  if mode then
    g.setDepthMode(mode, write)
    g.setShader(shader)
  end
  return true
end

-- Battle billboards share the native terrain depth buffer while their UI
-- layout and move-animation offsets remain in screen coordinates.
function Gen4Ground:withFreeDepth(depth, draw)
  if not Gen4Ground.freeOpen then return draw() end
  local g=love.graphics
  local shader=ensureDepthSprite()
  if not shader then return draw() end
  g.push('all')
  g.setShader(shader);shader:send('spriteZ',depth)
  g.setDepthMode('lequal',true)
  local ok,err=pcall(draw)
  g.pop()
  if not ok then error(err,0) end
end

function Gen4Ground:beginWorld(camX, camY, vw, vh)
  if self.liveOff then return false end
  local lw, lh = math.floor(vw or 0), math.floor(vh or 0)
  if lw < 1 or lh < 1 then return false end
  local colour, depth = self:liveTargetFor(lw, lh)
  if not colour then return false end
  local g = love.graphics
  self.worldPrevious = { g.getCanvas() }
  g.setCanvas({ colour, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  -- kept for `drawSprite`, which needs the same origin the chunks were placed
  -- against or its depths would be in a different space from theirs
  self.worldTop = camY + (self.offsetY or 0)
  self.worldW, self.worldH = lw, lh
  self.worldOpen = true
  local painted = self:livePass(camX, camY, lw, lh, nil)
  return painted > 0
end

-- Where a sprite's base sits in the SAME depth units the chunk matrix writes.
--
-- Derived from that matrix rather than invented: it writes
-- `-(sin*y + cos*(z + offY)) / LIVE_DEPTH` with `offY = cy*chunkPx - top`, and
-- a chunk-local z relates to the world by `worldZ = cy*chunkPx + half + z`, so
-- the pair collapses to `worldZ - half - top`.  Getting this wrong does not
-- look wrong -- it looks like sprites that sort against nothing.
function Gen4Ground:spriteDepth(worldZ, baseY)
  local sinP = self.groundScale or 1
  local cosP = self.heightScale or 0
  local top = self.worldTop or 0
  return -(sinP * (baseY or 0) + cosP * (worldZ - self.half - top)) / LIVE_DEPTH
end

-- drawSprite(image, quad, screenX, screenY, w, h, worldZ, baseY)
--
-- `screenX/screenY` are the top-left the 2D path would have drawn at, so a
-- caller that already knows where a character goes does not compute it twice;
-- the world position is needed only for the DEPTH.
function Gen4Ground:drawSprite(image, quad, screenX, screenY, w, h, worldZ, baseY)
  if not (self.worldOpen and image) then return false end
  local shader, mesh = ensureSprite()
  if not (shader and mesh) then return false end
  local g = love.graphics
  local previous = g.getShader()
  local mode, write = g.getDepthMode()
  g.setShader(shader)
  g.setDepthMode("lequal", true)
  shader:send("spriteRect", { screenX, screenY, w, h })
  shader:send("targetSize", { self.worldW, self.worldH })
  shader:send("spriteDepth", self:spriteDepth(worldZ or 0, baseY or 0))
  mesh:setTexture(image)
  if quad then
    local qx, qy, qw, qh = quad:getViewport()
    local iw, ih = image:getDimensions()
    mesh:setVertices({ { 0, 0, qx / iw, qy / ih },
                       { 1, 0, (qx + qw) / iw, qy / ih },
                       { 1, 1, (qx + qw) / iw, (qy + qh) / ih },
                       { 0, 1, qx / iw, (qy + qh) / ih } })
  else
    mesh:setVertices({ { 0, 0, 0, 0 }, { 1, 0, 1, 0 }, { 1, 1, 1, 1 }, { 0, 1, 0, 1 } })
  end
  g.draw(mesh)
  mesh:setTexture()
  g.setDepthMode(mode, write)
  g.setShader(previous)
  return true
end

function Gen4Ground:endWorld()
  if not self.worldOpen then return false end
  local g = love.graphics
  local previous = self.worldPrevious
  g.setCanvas(previous and previous[1] and previous or nil)
  g.setColor(1, 1, 1, 1)
  g.draw(self.liveColour, 0, 0)
  self.worldOpen, self.worldPrevious = false, nil
  return true
end

-- bake(land) -> a canvas, or nil.
-- THE PAINTED CELLS OF ONE CHUNK, as a drawable model.
--
-- `def.gen4TextureEdits` is sparse "x,y" -> texture name in MAP cells; this
-- turns the ones that fall in `land` into a `Gen4Decals` record and builds it
-- once. Cached per chunk and dropped with the bakes, because a decal is baked
-- into the chunk canvas exactly like the ground it sits on.
--
-- NAMES, NOT PATHS, in the store: a path moves when the cache is re-extracted
-- and a name does not. The lookup from one to the other happens here, against
-- whatever the current extraction holds.
function Gen4Ground:decalModelFor(land)
  self.decalModels = self.decalModels or {}
  local hit = self.decalModels[land]
  if hit ~= nil then return hit or nil end

  local edits = self.def and self.def.gen4TextureEdits
  if type(edits) ~= "table" or next(edits) == nil then
    self.decalModels[land] = false
    return nil
  end
  local grid = self.grid
  local terrain = self.terrain or {}
  local tiles = terrain.chunkTiles or 32
  local unit = terrain.tileUnits or 16
  local half = (terrain.chunkUnits or 512) / 2
  -- Which chunk cell (cx, cy) this land id sits at, so a map cell can be
  -- tested against it. Searched rather than stored because a chunk can appear
  -- at more than one place in the matrix and only its own position matters
  -- for the cells of THIS map.
  local cells = {}
  for key, name in pairs(edits) do
    local sx, sy = tostring(key):match("^(-?%d+),(-?%d+)$")
    local mx, my = tonumber(sx), tonumber(sy)
    if mx and my and type(name) == "string" then
      -- Map cell -> matrix tile -> which chunk, and where inside it.
      local tx = math.floor((self.offsetX or 0) / unit) + mx
      local ty = math.floor((self.offsetY or 0) / unit) + my
      local cx, cy = math.floor(tx / tiles), math.floor(ty / tiles)
      local at = grid and grid.land
                 and (cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height)
                 and grid.land[cy * grid.width + cx + 1] or nil
      if at == land then
        local rec = self:textureNamed(name)
        if rec then
          local lx, ly = tx % tiles, ty % tiles
          -- The cell's own corner in the chunk's space, which is centred on
          -- the origin -- so the half-square comes off, exactly as
          -- `heightsAt` does it.
          local x0 = lx * unit - half
          local z0 = ly * unit - half
          local y = self:heightAt(mx, my) or 0
          cells[#cells + 1] = { x = x0, z = z0, y = y, texture = name,
                                image = rec.path, w = rec.width or 16,
                                h = rec.height or 16 }
        end
      end
    end
  end
  -- HOW MANY CELLS ROUTED HERE, recorded separately from the model.
  --
  -- `decalModels[land] = false` means "nothing to draw", and that is true
  -- both when no painted cell belongs to this chunk and when the cells were
  -- found but the model would not build. Those are different facts and a
  -- check that cannot tell them apart cannot see a routing bug at all -- the
  -- map cell to matrix tile to chunk arithmetic is the one piece here that
  -- can be wrong without anything raising, because a cell routed to the wrong
  -- chunk simply paints somewhere else.
  self.decalCells = self.decalCells or {}
  self.decalCells[land] = #cells
  if #cells == 0 then self.decalModels[land] = false ; return nil end

  local okD, Gen4Decals = pcall(require, "src.render.Gen4Decals")
  local record = okD and Gen4Decals.build(cells,
                   { unit = unit, name = "decals:" .. tostring(land) }) or nil
  -- `pcall`: `Gen4Model.new` compiles a shader on first use and raises when
  -- it cannot. A decal that will not build must leave the chunk drawing its
  -- ordinary ground, not take the bake -- and with it the whole map -- down.
  -- Latched as `false` below, so a failure costs one attempt per chunk rather
  -- than one per frame.
  local okM, model = pcall(function()
    return record and Gen4Model.new(record) or nil
  end)
  if not okM then model = nil end

  -- WHY IT DID NOT BUILD, KEPT RATHER THAN DISCARDED.
  --
  -- Reported from play: *"it doesnt seem to paint them onto the world when i
  -- click with one selected"*. Every stage before this one can be checked
  -- without a graphics driver, and all of them now are: the store takes the
  -- edit, the name resolves against the cartridge's own sets, and the cell
  -- routes to the right chunk on all 593 real map defs. This stage cannot be
  -- checked that way -- `Gen4Model.new` compiles a shader and loads an image --
  -- and it was also the one stage that threw its reason away: `if not okM then
  -- model = nil end` discards the error, and `model or false` then makes
  -- "raised", "returned nil" and "nothing is painted here" into the same
  -- answer. A painter whose only failure mode is silence cannot be diagnosed
  -- from a screenshot, which is all I get.
  local why
  if not okD then
    why = "require failed: " .. tostring(Gen4Decals)
  elseif not record then
    why = ("build made no record from %d cells"):format(#cells)
  elseif not okM then
    why = "Gen4Model.new raised: " .. tostring(model)
  elseif not model then
    why = "Gen4Model.new returned nil -- no shader on this driver, or the "
          .. "texture would not load"
  end
  self.decalWhy = self.decalWhy or {}
  self.decalWhy[land] = why
  -- ONCE PER CHUNK rather than once per frame, because the answer is latched
  -- below and cannot change until the bakes are dropped.
  if why then
    Logger.warn("gen4 decals: %s chunk %s -- %d cells painted, %d shapes, "
                .. "NOT DRAWN (%s)", tostring(self.def and self.def.id),
                tostring(land), #cells,
                record and #(record.shapes or {}) or 0, why)
  else
    Logger.info("gen4 decals: %s chunk %s -- %d cells painted in %d shapes, "
                .. "baked", tostring(self.def and self.def.id), tostring(land),
                #cells, #(record.shapes or {}))
  end
  self.decalModels[land] = model or false
  return model
end

-- THE PAINTED LAYER'S OWN ONE-LINER, for the editor's footer.
--
-- `painted` is how many cells the store holds for this map, `routed` how many
-- of them landed in a chunk that has actually been asked for, and `drawn` how
-- many of those chunks ended up with a model. Those three separate "nothing
-- is painted" from "the paint arrived and would not draw" -- which is the
-- distinction a screenshot cannot make and the one I kept having to guess.
function Gen4Ground:decalReport()
  local edits = self.def and self.def.gen4TextureEdits
  local painted = 0
  for _ in pairs(type(edits) == "table" and edits or {}) do
    painted = painted + 1
  end
  local routed, drawn, chunks, why = 0, 0, 0, nil
  for land, n in pairs(self.decalCells or {}) do
    chunks = chunks + 1
    routed = routed + (n or 0)
    if self.decalModels and self.decalModels[land] then drawn = drawn + 1 end
    why = why or (self.decalWhy or {})[land]
  end
  return ("painted %d, routed %d over %d chunks, drawn %d%s"):format(
    painted, routed, chunks, drawn, why and (" -- " .. tostring(why)) or "")
end

-- One texture record by name, across this cartridge's sets.
function Gen4Ground:textureNamed(name)
  local sets = self.terrain and self.terrain.sets
  if not sets then return nil end
  -- The map's OWN set first: a name can appear in several, and the copy in
  -- the set this map draws with is the one whose palette matches the ground
  -- around it.
  local own = self.set and self.set.textures and self.set.textures[name]
  if own then return own end
  -- ...then the others BY ID, which is the order the editor's palette offers
  -- them in (`tools/map-editor/Gen4Terrain.setOrder`). `pairs` here picked a
  -- different copy from run to run, so a decal painted from another set could
  -- draw in different colours from the one the editor showed.
  if not self.setIds then
    local ids = {}
    for id in pairs(sets) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    self.setIds = ids
  end
  for _, id in ipairs(self.setIds) do
    local set = sets[id]
    local rec = set and set.textures and set.textures[name]
    if rec then return rec end
  end
  return nil
end

function Gen4Ground:bake(land)
  local model = self:modelFor(land)
  if not model then
    -- The other silent nil. A chunk with no shapes, or whose geometry could not
    -- be sliced out of the side-car file, simply did not appear -- and an absent
    -- chunk and a chunk that was never asked for looked identical in the log.
    if not self.saidNoModel then self.saidNoModel = {} end
    if not self.saidNoModel[land] then
      self.saidNoModel[land] = true
      Logger.warn("gen4 ground: %s has no drawable geometry for chunk %s "
                  .. "(record %s, shapes %d)",
                  tostring(self.def and self.def.id), tostring(land),
                  self.terrain.chunks[land] and "present" or "MISSING",
                  #((self.terrain.chunks[land] or {}).shapes or {}))
    end
    return nil
  end
  local px = self.chunkPx
  local colour, depth = Gen4Model.newTarget(px, self.canvasPx)
  if not colour then
    -- NO DEPTH TARGET. Everything else still works; the ground keeps the
    -- stand-in rather than being drawn back to front.
    --
    -- SAID OUT LOUD, because this was the one way the whole 3D ground could
    -- switch itself off without a word. A Sinnoh session builds one of these
    -- per map AND per visible neighbour -- seven at once on Route 201 -- and
    -- each keeps a cache of 512x637 colour canvases with a depth buffer apiece.
    -- If an allocation fails partway through, `noDepth` latches, every later
    -- `canvasFor` returns nil at its first line, and the map quietly falls back
    -- to the flat stand-in for the rest of the session. From the outside that
    -- looks exactly like "the 3D does not work", which is what it was reported
    -- as -- and the log said nothing at all.
    Logger.warn("gen4 ground: %s could not allocate a %dx%d draw target for "
                .. "chunk %s -- this ground is switching to the flat stand-in "
                .. "for the rest of the session",
                tostring(self.def and self.def.id), px, self.canvasPx or -1,
                tostring(land))
    self.noDepth = true
    return nil
  end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ colour, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  local view = self.view
  model:draw(view)

  -- ...AND THE PAINTED GROUND, if this map has any.
  --
  -- Per-cell ground textures are a decal layer: Sinnoh's terrain is an
  -- irregular triangulation and 87.5% of its triangles straddle a cell
  -- boundary, so a cell cannot be re-textured by touching the mesh. A painted
  -- cell gets one quad laid just above the ground instead -- see
  -- `src/render/Gen4Decals.lua` for the measurement and the vertex format.
  --
  -- BAKED WITH THE FLOOR, not drawn per frame, for the reason the buildings
  -- are: the geometry does not change between frames, and the same depth
  -- buffer that keeps a basement under its ground keeps a decal under a
  -- bridge. A map with nothing painted builds no record and costs one table
  -- lookup.
  local decals = self:decalModelFor(land)
  if decals then decals:draw(view) end

  -- ...AND THE BUILDINGS STANDING ON IT, into the same canvas and the same
  -- depth buffer.  They are baked with the floor rather than drawn every frame
  -- for the reason the floor is: the geometry does not change, and a town with
  -- forty houses would otherwise be forty model draws a frame to arrive at the
  -- picture that was already there.
  --
  -- The depth buffer is what makes this correct rather than an overlay: a
  -- house drawn after the ground but BELOW it -- a basement, a bridge's
  -- underside -- stays hidden, which painting in order would not manage.
  local record = self.terrain.chunks[land]
  local placed, missing = 0, 0
  for _, object in ipairs(self:objectsFor(land, record)) do
    -- ...EXCEPT the ones that move.  A fountain baked into the floor is a
    -- fountain that never runs, and re-baking the whole chunk on the animation
    -- clock to move one of them is the cost this split exists to avoid.
    --
    -- A JOINT ONE-SHOT COUNTS AS MOVING TOO, since the cache carries the
    -- tracks.  `movesAtRuntime` is the single test this guard and the animated
    -- bake's selection both use, so the two stay complements by construction
    -- rather than by two conditions agreeing.
    --
    -- The cost is measured and permanent: 72 more chunks of 666 (10.8%) now
    -- re-bake their moving canvas each frame, on top of the 119 (17.9%) that
    -- already did.  A door is only in motion for eight frames, so a
    -- conditional membership -- in the moving set only while a one-shot runs --
    -- would cost nothing at rest; it needs the static canvas invalidated on
    -- start AND on unload, and a door holds its open pose until the unload, so
    -- the saving is smaller than it looks.  Taken the simple way, with the
    -- number written down, because a prop drawn twice or not at all is a worse
    -- failure than a chunk re-baking.
    if self:shouldBake(object) then
      local building = self:building(object.model, object.archive)
      if building then
        building:draw(Gen4Model.multiply(view, placement(object)))
        placed = placed + 1
      else
        missing = missing + 1
      end
    end
  end

  -- SAY WHETHER ANYTHING STOOD ON THE FLOOR.
  --
  -- Reported from play: *"buildings outside are still not showing any height
  -- or 3d"*.  A chunk whose houses never baked is a flat floor, and a flat
  -- floor drawn through a correct oblique matrix looks EXACTLY like a correct
  -- floor drawn through a flat one -- so the picture cannot tell the two
  -- apart, and neither could I.  This can: 387 of the cartridge's 666 chunks
  -- carry objects, 3,476 placements between them, and if `placed` comes back 0
  -- on a chunk with objects the fault is the model lookup, not the camera.
  -- ONCE PER CHUNK, NOT ONCE PER GROUND.
  --
  -- This used to be `if not self.reportedBake then self.reportedBake = true`,
  -- so a ground instance reported its FIRST bake and then went silent forever.
  -- That is how three separate investigations concluded that Twinleaf's chunk
  -- "never bakes": the log showed `chunk 5 baked` from a neighbour draw and
  -- nothing afterwards, while chunk 0 was in fact baking with its eight
  -- buildings every time. A once-ever line read as a per-event line is worse
  -- than no line, because it looks like evidence of absence.
  --
  -- Keyed by chunk and capped, so a session says each chunk once and a cache
  -- thrashing between chunks still cannot flood the log.
  self.reportedBake = self.reportedBake or {}
  self.reportedBakes = (self.reportedBakes or 0)
  if not self.reportedBake[land] and self.reportedBakes < 40 then
    self.reportedBake[land] = true
    self.reportedBakes = self.reportedBakes + 1
    Logger.info("gen4 ground: chunk %s baked %d building(s), %d unresolved "
                .. "(canvas %dx%d, lean %d)", tostring(land), placed, missing,
                px, self.canvasPx, math.floor(self.leanPx or 0))
  end

  g.setCanvas(previous[1] or nil)
  return colour
end

-- THE PART OF A CHUNK THAT GOES OVER THE SPRITES.
--
-- Reported from play, repeatedly: *"buildings outside are still not showing
-- any height or 3d"*.  The buildings were there the whole time -- measured
-- against the cartridge's own models, Twinleaf's houses rise 45 to 58 screen
-- pixels at this camera -- but NOTHING IN THE WORLD EVER PASSED IN FRONT OF
-- THE PLAYER.  Every sprite drew over every building, so walking "behind" a
-- house put you on top of its roof, and a world nothing can occlude you in
-- reads as flat however much height its geometry has.
--
-- This is the same picture as `bake`, minus the ground floor: the terrain goes
-- in FIRST WITH THE COLOUR MASK OFF so the depth buffer still hides whatever a
-- hill should hide, and each building is then drawn with everything below
-- CANOPY_Y cut away.  Blitted after the entity pass.
function Gen4Ground:bakeCanopy(land, cut)
  -- WITHOUT THE HEIGHT CUT THIS PASS IS WORSE THAN NOTHING: it would paint
  -- whole buildings over the sprites, so a character standing at a front door
  -- would vanish into it.  No cut, no canopy.
  if not Gen4Model.cutsHeight() then return false end
  -- A CHUNK WITH NO PROPS STILL HAS WALLS.  This used to require `objects`,
  -- which meant every interior -- where the geometry that should mask the
  -- player is the room itself -- got no canopy at all.
  local record = self.terrain.chunks[land]
  if not record then return false end
  local objects = record.objects or {}
  -- Sea level only when nobody said otherwise, which is what it always was.
  local yCut = cut or CANOPY_Y

  local px = self.chunkPx
  local canvas, depth = Gen4Model.newTarget(px, self.canvasPx)
  if not canvas then return false end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ canvas, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  local view = self.view

  local terrain = self.depthModels[land]
  if terrain == nil then
    terrain = self:modelFor(land) or false
    self.depthModels[land] = terrain
  end
  if terrain then
    local r, gr, b, a = g.getColorMask()
    g.setColorMask(false, false, false, false)
    terrain:draw(view)
    g.setColorMask(r, gr, b, a)
    -- ...AND THEN THE TERRAIN'S OWN TALL GEOMETRY, IN COLOUR.
    --
    -- A Gen 4 chunk mesh is not just a floor.  Interior walls, cliff faces and
    -- the trees that are part of the land rather than props all live in it --
    -- so a canopy made only of `objects` left exactly the things the player
    -- most obviously walks in front of.  Reported from play: *"indoor tiles
    -- don't have my character walk behind them and mask the character neither
    -- do trees, it shows me as walking on top of their tiles"*.
    --
    -- Drawn a second time with the same cut the buildings get, over the depth
    -- the pass above just laid down, so a wall still hides what is behind it.
    -- "lequal" for the reason the live pass uses it: this is the same
    -- geometry the masked pass above just wrote depth for, and "less" rejects
    -- every fragment of it.
    terrain:draw(view, nil, nil, yCut, nil, "lequal")
  end

  local drawn = 0
  for _, object in ipairs(objects) do
    local building = self:building(object.model)
    if building then
      -- The cut is stated in WORLD units and the shader tests MODEL ones, so
      -- the object's own lift and scale come back off before it is sent.
      local scale = (object.scaleY and object.scaleY ~= 0) and object.scaleY or 1
      building:draw(Gen4Model.multiply(view, placement(object)), nil, nil,
                    (yCut - (object.y or 0)) / scale)
      drawn = drawn + 1
    end
  end

  g.setCanvas(previous[1] or nil)
  -- The terrain pass alone is reason enough to keep the canvas: an interior
  -- has no props and all of its masking geometry.
  if drawn == 0 and not terrain then return false end
  return canvas
end

function Gen4Ground:canopyFor(land, cut)
  if self.noDepth or land == nil then return nil end
  -- A BAKED CANOPY HOLDS THE CUT IT WAS BAKED WITH, so a cut that now tracks
  -- the player's ground has to be allowed to invalidate it.  Without this the
  -- fallback path keeps a sea-level canopy for the life of the map and the fix
  -- only lands on machines that can run the live pass.
  --
  -- Quantised to one tile unit so walking a slope does not re-bake every
  -- frame: the cut then only moves when the player's elevation does, which on
  -- a real map is a handful of times.
  local want = math.floor(((cut or CANOPY_Y) / 16) + 0.5) * 16
  if self.canopyCutUsed ~= want then
    for _, canvas in pairs(self.canopies or {}) do
      if canvas and canvas.release then pcall(canvas.release, canvas) end
    end
    self.canopies = {}
    self.canopyCutUsed = want
  end
  local held = self.canopies[land]
  if held ~= nil then return held or nil end
  -- ON THE SAME BUDGET AS THE GROUND, and for the same reason: walking into a
  -- town wants several chunks at once, and baking them all in the frame the
  -- map opens is a visible hitch.  A chunk with no canopy yet simply has none
  -- drawn this frame, which costs one frame of missing roofs rather than a
  -- stutter -- and the chunk's ground is already on screen, so nothing is
  -- blank while it waits.
  if (self.canopyBudget or 0) <= 0 then return nil end
  self.canopyBudget = self.canopyBudget - 1
  local made = self:bakeCanopy(land, cut)
  self.canopies[land] = made or false
  return made or nil
end

-- The canopy pass: the same chunks `draw` just painted, in the same places,
-- carrying only what stands above head height.  Called after the sprites.
-- Close the free pass and put it on the screen.
--
-- Idempotent, and called from two places on purpose: `drawCanopy`, which the
-- overworld runs after the sprites, and the top of `draw` as a NET.  A canvas
-- left bound is a black frame, and the one failure mode this design must not
-- have is a path that never reaches the close -- so a missed close costs one
-- frame rather than the session.
function Gen4Ground:endFree()
  if not Gen4Ground.freeOpen then return false end
  local g = love.graphics
  local previous = Gen4Ground.freePrevious
  local colour = Gen4Ground.freeColour
  -- CLEARED FIRST, so a raise below cannot leave the pass marked open and
  -- have every later frame try to close it again.
  local scale = Gen4Ground.freeScale or 1
  Gen4Ground.freeOpen, Gen4Ground.freePrevious, Gen4Ground.freeColour =
    false, nil, nil
  Gen4Ground.freeScale = 1
  -- ONE canvas or none.  `previous` came from `{ g.getCanvas() }`, and that
  -- can hold more than a plain list -- a depthstencil binding puts a table in
  -- it, which is what the `setCanvas` raise above was.  The free pass only
  -- ever displaces a single target, so restoring the first entry is the whole
  -- of the correct answer and cannot reproduce that shape.
  g.setCanvas(previous and previous[1] or nil)
  g.setColor(1, 1, 1, 1)
  -- BLITTED BACK DOWN into whatever was bound before: at `scale` 1 this is
  -- exactly the `g.draw(colour, 0, 0)` it has always been, with the arguments
  -- written out.  Kept even when the override below is published, because it
  -- costs one blit and leaves the world canvas holding a correct picture if
  -- anything downstream declines the override.
  if colour then g.draw(colour, 0, 0, 0, 1 / scale, 1 / scale) end

  -- ...AND HANDED TO THE RENDERER WHOLE, WHICH IS THE POINT OF THE SETTING.
  --
  -- Reported after the first attempt shipped: *"doesnt seem to change anything
  -- though"*.  Correct, and the reason is the blit above rather than anything
  -- in the pass: `OverworldState:draw` binds `Renderer.worldCanvas` at the
  -- LOGICAL size (~307x230 on that window), so a supersampled frame was
  -- downsampled into it one step after being drawn and THAT canvas was what
  -- got upscaled ~5x to the screen.  Every extra pixel was thrown away
  -- immediately.  The resolution ceiling was never this target -- it was the
  -- world canvas downstream of it, which the first attempt never looked at.
  --
  -- `setWorldOverride` is the seam for exactly this and already exists for the
  -- mod render pipelines: endFrame composites the handed canvas instead of the
  -- world canvas, and its own comment says it MEASURES the canvas rather than
  -- assuming its resolution -- "a supersampled or deliberately low-res canvas
  -- is simply fitted".  A free-camera frame meets its contract as written:
  -- terrain, props and characters are all drawn into this one target, because
  -- `freeEntity` draws the characters into it while the pass is open.
  --
  -- ONLY ABOVE 1X, and that is the whole safety argument.  At the default the
  -- renderer is never told anything and this function is byte-for-byte what it
  -- was, so no player who has not chosen a higher setting can be affected --
  -- by this, by the override's "nothing else drew into the world canvas"
  -- assumption, or by anything else here.
  --
  -- `require`d rather than read off a global: a bare `_G.Game` is nil in a
  -- real session, which is a fault this port has already paid for once.
  if scale > 1 and colour and not self.suppressWorldOverride then
    local got, Game = pcall(require, "src.core.Game")
    local renderer = got and Game and Game.renderer
    if renderer and renderer.setWorldOverride then
      renderer:setWorldOverride(colour)
    end
  end
  return true
end

function Gen4Ground:drawCanopy(camX, camY, vw, vh)
  -- AN OPEN FREE PASS IS CLOSED BEFORE ANY GUARD CAN RETURN.
  --
  -- This used to sit below the `noDepth` guard and after the free-mode
  -- branch, which left one frame able to return with the canvas still
  -- bound: a map change between `draw` and here flips `grid`, the guard
  -- takes the early return, and the blit waits for the net at the top of
  -- the next `draw` -- one frame late, into a canvas reference that the
  -- map change may already have replaced.  `endFree` is idempotent and
  -- costs nothing on the frames that go on to draw a canopy, so closing
  -- first is free and removes the case rather than surviving it.
  if Gen4Ground.freeOpen then return self:endFree() end
  if self.noDepth or not self.grid then return false end

  -- A FREE CAMERA HAS ALREADY DRAWN ALL OF THIS, WITH A REAL DEPTH BUFFER.
  --
  -- Everything below projects through `livePass`, which is the OBLIQUE field
  -- matrix.  Run under first or third person it paints a flat-projected
  -- canopy straight over the perspective frame -- reported from play as
  -- *"the first and third person are showing the flat world overlaying"*,
  -- and visible in that screenshot as a band of treetops across the bottom
  -- edge and a column of trees up the left that belong to no building in
  -- the scene.
  --
  -- `drawFree` draws every chunk and prop whole, with no height cut, into a
  -- depth buffer -- so there is nothing left for a canopy pass to add and
  -- nothing it could add that would be in the right projection anyway.
  -- Closing it is NOT this branch's job -- the guard at the top of the
  -- function has already done that, on every frame and in every mode, which
  -- is why this can be a plain `false`.
  if self.view3d and self.view3d:isFree() then return false end

  -- THE LIVE CANOPY, into the same target the ground pass used.
  --
  -- Reusing it is safe and deliberate: this runs after the entity pass, by
  -- which time the ground has long since been blitted to the screen, so the
  -- target holds nothing anyone still wants.  A second one would double the
  -- only allocation this path makes.
  local lw, lh = math.floor(vw or 0), math.floor(vh or 0)
  if not self.liveOff and lw > 0 and lh > 0 then
    local colour, depth = self:liveTargetFor(lw, lh)
    if colour then
      local g = love.graphics
      local previous = { g.getCanvas() }
      g.setCanvas({ colour, depthstencil = depth })
      g.clear(0, 0, 0, 0, true, true)
      local painted = self:livePass(camX, camY, lw, lh,
                                    self:canopyCut(camX, camY, lw, lh))
      g.setCanvas(previous[1] or nil)
      g.setColor(1, 1, 1, 1)
      g.draw(colour, 0, 0)
      if painted > 0 then return true end
    end
  end

  self.canopyBudget = Gen4Ground.BAKES_PER_FRAME
  local px = self.chunkPx
  local grid = self.grid
  local sinP = self.groundScale or 1
  local cut = self:canopyCut(camX, camY, vw, vh)
  local left = camX + self.offsetX
  local top = camY + self.offsetY
  local x0 = math.floor(left / px)
  local y0 = math.floor(top / px)
  local x1 = math.floor((left + (vw or 0)) / px)
  local y1 = math.floor((top + (vh or 0) / sinP) / px)

  local g = love.graphics
  local r, gr, b, a = g.getColor()
  g.setColor(1, 1, 1, 1)
  local drawn = 0
  for cy = y0, y1 do
    for cx = x0, x1 do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local canopy = self:canopyFor(land, cut)
        if canopy then
          g.draw(canopy, cx * px - left, (cy * px - top) * sinP - self.leanPx
                                         - self:chunkLift(cx, cy) * (self.heightScale or 0))
          drawn = drawn + 1
        end
      end
    end
  end
  g.setColor(r, gr, b, a)
  return drawn > 0
end

-- THE MOVING PROPS, on their own canvas, re-drawn when the clock moves.
--
-- The terrain is drawn into it FIRST WITH THE COLOUR MASK OFF, which fills the
-- depth buffer without painting anything.  That is what keeps a prop behind a
-- hill behind it: the canvas comes out transparent everywhere the props are
-- not, and correctly occluded everywhere they are.  Drawing the props alone
-- would have put a lake in front of the cliff above it.
function Gen4Ground:bakeAnimated(land, frame)
  local record = self.terrain.chunks[land]
  local objects = record and record.objects
  if not objects then return nil end

  local moving = {}
  for _, object in ipairs(objects) do
    -- `object.archive` WAS MISSING HERE and is passed now.  The static bake's
    -- guard asks `animationsFor(object.model, object.archive)` and this asked
    -- `animationsFor(object.model)` -- so for a `fldeff` prop the two
    -- selections consulted DIFFERENT models: the guard returns nil for fldeff
    -- and bakes it, while this looked the index up among the buildings and
    -- could have found a texture animation belonging to an unrelated model,
    -- putting the prop in both passes and drawing it twice.
    --
    -- Harmless today, measured: zero fldeff props are placed in any terrain
    -- chunk (the signposts come through the map-object path, not this one), so
    -- there is nothing for the mismatch to catch.  Fixed anyway, because these
    -- two selections have to be complements and one of them reading a
    -- different table than the other is how that stops being true quietly.
    -- THE SELECTION NO LONGER CARRIES THE RECORDS, and that is the point:
    -- `propMaterials` is asked in the draw loop below, so this and the two
    -- live passes cannot spell the question differently again.  A prop with no
    -- records still moves -- nineteen of the twenty doors are NSBCA and their
    -- pose comes from `oneShotPose` -- and `shouldAnimate` is the one test
    -- that decides, for all three sites.
    if self:shouldAnimate(object) then
      moving[#moving + 1] = { object = object }
    end
  end
  if #moving == 0 then return false end

  local px = self.chunkPx
  local canvas, depth = Gen4Model.newTarget(px, self.canvasPx)
  if not canvas then return false end

  local g = love.graphics
  local previous = { g.getCanvas() }
  g.setCanvas({ canvas, depthstencil = depth })
  g.clear(0, 0, 0, 0, true, true)
  local view = self.view

  -- KEPT, not rebuilt.  `modelFor` reads the geometry out of the side-car file
  -- and builds a LOVE mesh per shape; calling it once a frame for every chunk
  -- with a fountain on it would cost more than the animation it is paying for.
  -- The static bake calls it once and throws it away on purpose -- it is used
  -- once -- and this one is used every frame, so this one is held.
  local terrain = self.depthModels[land]
  if terrain == nil then
    terrain = self:modelFor(land) or false
    self.depthModels[land] = terrain
  end
  if terrain then
    local r, gr, b, a = g.getColorMask()
    g.setColorMask(false, false, false, false)
    terrain:draw(view)
    g.setColorMask(r, gr, b, a)
  end

  for _, item in ipairs(moving) do
    -- `item.object.archive` was missing here too, for the same reason as the
    -- selection above: `building(index)` with no archive resolves a BUILDING
    -- for a fldeff index.  Zero fldeff props are placed in chunks today, so
    -- this has never mattered; passing it keeps the three sites consistent.
    local building = self:building(item.object.model, item.object.archive)
    if building then
      building:draw(Gen4Model.multiply(view, placement(item.object)),
                    self:oneShotPose(item.object, building),
                    self:propMaterials(item.object, frame))
    end
  end

  g.setCanvas(previous[1] or nil)
  return canvas
end

-- The moving-prop canvas for a chunk at the current clock, rebuilt only when
-- the clock has moved on.  `false` means this chunk has nothing that moves,
-- which is most of them, and is remembered so it is asked once.
function Gen4Ground:animatedFor(land)
  if self.noDepth or land == nil then return nil end
  local entry = self.animated[land]
  if entry == false then return nil end
  if entry and entry.frame == self.clock then return entry.canvas end

  local canvas = self:bakeAnimated(land, self.clock)
  if canvas == false or canvas == nil then
    self.animated[land] = false
    return nil
  end
  if entry and entry.canvas and entry.canvas.release then
    pcall(entry.canvas.release, entry.canvas)
  end
  self.animated[land] = { canvas = canvas, frame = self.clock }
  return canvas
end

function Gen4Ground:canvasFor(land)
  if self.noDepth or land == nil then return nil end
  local hit = self.baked[land]
  if hit ~= nil then
    -- THE LAST SILENT PATH, and the only one left unaccounted for.
    --
    -- `self.baked[land] = canvas or false` caches a FAILED bake as `false`, and
    -- this line then answers every later call for that chunk without a word. A
    -- chunk that failed once is therefore indistinguishable, from outside, from
    -- a chunk that was never asked for -- which is exactly the shape of the
    -- Twinleaf report: land 0 resolves every frame, nothing bakes, and none of
    -- the three exits below ever fire.
    --
    -- Only the FALSE case is worth a line; a real cache hit is the normal path
    -- and happens every frame.
    if hit == false then
      self.saidDead = self.saidDead or {}
      if not self.saidDead[land] then
        self.saidDead[land] = true
        Logger.warn("gen4 ground: %s is answering chunk %s from a CACHED "
                    .. "FAILURE -- it was baked once, produced nothing, and "
                    .. "will not be retried this session",
                    tostring(self.def and self.def.id), tostring(land))
      end
    end
    return hit or nil
  end
  if self.budget <= 0 then
    -- THE THIRD SILENT EXIT. `BAKES_PER_FRAME` is 4 and a 1024-pixel viewport
    -- covers nine chunks, so the cells past the budget wait for the next frame
    -- -- which is fine, because the ones already baked are answered from
    -- `self.baked` BEFORE this check and cost nothing. It stops being fine if
    -- the cache is being dropped underneath it, because then the same four
    -- chunks are rebuilt every frame and the fifth is never reached at all.
    -- Said once per chunk so the difference is visible in a log.
    self.saidStarved = self.saidStarved or {}
    if not self.saidStarved[land] then
      self.saidStarved[land] = true
      Logger.info("gen4 ground: %s ran out of bake budget before chunk %s "
                  .. "(%d cached, %d per frame)",
                  tostring(self.def and self.def.id), tostring(land),
                  #self.order, Gen4Ground.BAKES_PER_FRAME)
    end
    return nil
  end
  self.budget = self.budget - 1

  local canvas = self:bake(land)
  self.baked[land] = canvas or false
  self.order[#self.order + 1] = land
  -- Oldest out first. A player walks in one direction, so the chunk longest
  -- unused is behind them.
  while #self.order > Gen4Ground.CACHE do
    local old = table.remove(self.order, 1)
    local dropped = self.baked[old]
    if dropped and dropped.release then pcall(dropped.release, dropped) end
    self.baked[old] = nil
    -- ...and its canopy, a third canvas of the same size, allocated per chunk
    -- exactly like the other two and just as much of a leak if forgotten.
    local canopy = self.canopies[old]
    if canopy and canopy.release then pcall(canopy.release, canopy) end
    self.canopies[old] = nil
    -- ...and its moving props, which are a second canvas of the same size and
    -- would otherwise be the leak this eviction exists to prevent.
    local moving = self.animated[old]
    if type(moving) == "table" and moving.canvas and moving.canvas.release then
      pcall(moving.canvas.release, moving.canvas)
    end
    self.animated[old] = nil
    local held = self.depthModels[old]
    if type(held) == "table" and held.release then pcall(held.release, held) end
    self.depthModels[old] = nil
  end
  return canvas
end

-- draw(camX, camY, vw, vh) -- the chunks the camera can see, in map pixels.
function Gen4Ground:draw(camX, camY, vw, vh)
  -- A FREE PASS LEFT OPEN BY THE PREVIOUS FRAME IS CLOSED HERE.
  --
  -- `drawCanopy` closes it in the ordinary run, but a frame that returned
  -- early -- a transition, a menu, a script that skipped the canopy --
  -- would leave the canvas bound and every later draw would go into it
  -- instead of the screen.  That is a black frame that never recovers, so
  -- it gets a net rather than an argument that it cannot happen.
  if Gen4Ground.freeOpen then self:endFree() end
  if self.noDepth then return false end
  if self.tiltGeneration ~= Gen4Camera.generation then
    self:dropBakes()
    self:applyCamera()
  end
  -- THE CLOCK, checked once a second rather than once a frame.
  --
  -- `os.date` is cheap but not free and the answer can only change on a band
  -- boundary; member 0's fifteen bands are minutes apart at dawn and hours
  -- apart at noon, so a second of lag is invisible and sixty calls a second
  -- are waste.  Members 1 and 2 -- 483 of the 593 maps -- are constant across
  -- all fifteen bands and will never take this branch at all.
  self.lightCheck = (self.lightCheck or 0) + 1
  if self.lightCheck >= 60 then
    self.lightCheck = 0
    local band = self.lightBand
    self:applyLight()
    if self.lightBand ~= band then self:dropLitModels() end
  end
  self.budget = Gen4Ground.BAKES_PER_FRAME
  -- One tick a frame, which is the clock every animation in this cartridge is
  -- authored against: its frame counts ARE frames.
  --
  -- DELIBERATELY NOT WRAPPED.  The obvious wrap is a round number, and every
  -- round number this archive's periods do NOT all divide into -- 16, 20, 21,
  -- 25, 60, 61, 91 and 121 are among them -- so a wrap would make every
  -- animation whose period is coprime to it jump phase once a wrap.  A Lua
  -- number counts frames exactly past any session anyone will play, so the
  -- honest clock is the one that does not pretend to a period it has not got.
  self.clock = self.clock + 1

  local px = self.chunkPx
  local grid = self.grid
  local sinP = self.groundScale or 1
  -- Camera is in MAP pixels; the matrix is what the chunks are laid out in, so
  -- the map's own corner goes back on before anything is divided.
  local left = camX + self.offsetX
  local top = camY + self.offsetY
  local x0 = math.floor(left / px)
  local y0 = math.floor(top / px)
  -- THE CELL THIS FRAME RESOLVED TO, once per map rather than per frame.
  --
  -- Twinleaf resolves to a chunk belonging to another map, and every input to
  -- that arithmetic has been checked in the cache and is correct. This reports
  -- what the RUNTIME actually had, which is the one thing that could not be
  -- read from the outside.
  if self.saidCell ~= (x0 * 4096 + y0) then
    self.saidCell = x0 * 4096 + y0
    Logger.info("gen4 ground: cam=(%d,%d) + offset=(%d,%d) -> left/top=(%d,%d) "
                .. "/ chunkPx %d -> cell (%d,%d) -> land %s",
                math.floor(camX or 0), math.floor(camY or 0),
                self.offsetX, self.offsetY, math.floor(left), math.floor(top),
                px, x0, y0,
                tostring(grid.land and grid.land[y0 * grid.width + x0 + 1]))
  end
  local x1 = math.floor((left + (vw or 0)) / px)
  -- ...AND MORE ROWS FIT ON SCREEN ONCE THE GROUND IS COMPRESSED.  A screen
  -- `vh` pixels tall shows `vh / sin(pitch)` map pixels of depth -- at the
  -- default camera that is one and a sixth again, and asking for the old range
  -- leaves a band of unpainted map along the bottom edge.
  local y1 = math.floor((top + (vh or 0) / sinP) / px)


  -- WHERE THE SPREAD PIVOTS: the ground under the player, in world units.
  --
  -- The shader's factor is `1 - (y - datum) * spread`, exactly 1 at the datum.
  -- That plane has to be THE ONE THE SPRITES STAND ON, because they are placed
  -- by the flat projection and are given no spread at all.  Anchoring at 0
  -- instead scaled the whole ground plane about the screen centre while the
  -- characters on it stayed put -- Twinleaf's ground is at y = 16, not 0, and
  -- 50.6% of ground pixels moved at the CARTRIDGE rung, 65.5% at rung 30.
  --
  -- Read at the view's centre, which is where the overworld keeps the player.
  if self.spread then
    self.spread[2] = self:groundY(self:viewCentre(camX, camY, vw, vh))
  end

  local g = love.graphics
  g.setColor(1, 1, 1, 1)

  -- THE LIVE PASS, and the baked one below it as the fallback.
  --
  -- Kept rather than deleted because the live pass needs ONE screen-sized
  -- depth target and a machine that cannot give it one should still get a
  -- world.  `liveOff` latches on the first failure, so a refusal costs one
  -- allocation attempt and not one per frame.
  -- A FREE CAMERA OWNS THE FRAME OUTRIGHT.  It is not a variant of the field
  -- pass: it picks its own chunks (around the camera, not around a viewport
  -- rectangle) and it is the one caller that does not want the height spread.
  if self.view3d and self.view3d:isFree() and not self.liveOff then
    -- PLACE IT FROM THE CAMERA WE ALREADY HAVE, when nothing else has.
    --
    -- `camX/camY` is the viewport's corner and the overworld keeps the player
    -- at its centre, so the centre IS the player to within the follow
    -- distance -- which means the free modes work with NO change to the
    -- overworld at all.  A caller that knows better calls `placeCamera` first
    -- and this leaves it alone.
    if not self.cameraPlaced then
      local ex, ey = self:viewCentre(camX, camY, vw, vh)
      -- NO FACING.  This used to pass `self.view3d.yaw`, which is read BEFORE
      -- `follow` syncs itself to the kept look and would therefore pin the
      -- camera to this view's own stale angle -- the very divergence the sync
      -- exists to remove.  `follow` falls back to the kept heading on its own.
      self.view3d:follow(ex + (self.offsetX or 0), ey + (self.offsetY or 0),
                         nil, self:groundY(ex, ey))
    end
    self.cameraPlaced = nil
    -- HOLD THE EYE ABOVE THE GROUND IT IS LOOKING OVER.
    --
    -- Reported from play: *"the camera doesnt collide with the ground so im
    -- able to see under the map"*.  `Gen4View` clamps its own elevation so
    -- the orbit cannot dig into FLAT ground, but it has no heights to read --
    -- a hill, a ledge or a building's floor between the eye and the player
    -- rises past a perfectly legal elevation.  The heights live here, so the
    -- clamp does too.
    --
    -- Lifting the eye rather than pulling it in: pulling in pushes the camera
    -- through the player instead, which is the same hole from the other side.
    local v = self.view3d
    if v and v.mode ~= "first" then
      local floorY = self:groundY(v.x - (self.offsetX or 0),
                                  v.z - (self.offsetY or 0))
      local lowest = floorY + Gen4Ground.EYE_CLEARANCE
      if v.y < lowest then v.y = lowest end
    end
    if self:drawFree(vw, vh) then return true end
  end

  -- The live pass captures whatever canvas is bound, so it must not start with
  -- a free pass open.  The net at the top of `draw` catches one left by a
  -- PREVIOUS frame; this catches one left by THIS frame.
  if Gen4Ground.freeOpen then self:endFree() end

  local lw, lh = math.floor(vw or 0), math.floor(vh or 0)
  if not self.liveOff and lw > 0 and lh > 0 then
    local colour, depth = self:liveTargetFor(lw, lh)
    if colour then
      local previous = { g.getCanvas() }
      g.setCanvas({ colour, depthstencil = depth })
      g.clear(0, 0, 0, 0, true, true)
      local painted = self:livePass(camX, camY, lw, lh, nil)
      g.setCanvas(previous[1] or nil)
      g.setColor(1, 1, 1, 1)
      g.draw(colour, 0, 0)
      -- WHICH PATH DREW THIS FRAME, once per change.
      --
      -- The live pass and the baked one produce the same picture on flat
      -- ground and differ only in how standing geometry behaves as the camera
      -- moves -- which means a session that quietly fell back to the bake
      -- looks EXACTLY like a session where the live pass is not working.  From
      -- the outside those two are indistinguishable, and that is precisely the
      -- shape of report this port has lost whole passes to before.
      -- The reach is part of the key, so a frame where the coverage CHANGES
      -- reports itself rather than being hidden by a latch keyed on the chunk
      -- count alone.
      local key = ("live/%d/%.6f/%d/%d"):format(
        painted, self.spread and self.spread[1] or 0,
        math.floor(self.liveReach or -1), math.floor(self.liveWant or -1))
      if self.reportedPath ~= key then
        self.reportedPath = key
        Logger.info("gen4 ground: %s drew LIVE -- %d chunk(s), %dx%d target, "
                    .. "height spread %.6f per unit%s",
                    tostring(self.def and self.def.id), painted, lw, lh,
                    self.spread and self.spread[1] or 0,
                    (self.spread and self.spread[1] or 0) == 0
                      and " (this camera is orthographic on the cartridge too)" or "")
        -- ...AND WHETHER IT REACHED THE BOTTOM. Said separately and in plain
        -- words, because this is the question five fixes have been aimed at.
        local reach = self.liveReach or -1
        local want = self.liveWant or -1
        Logger.info("gen4 ground: %s live coverage -- ground reaches %.1f of "
                    .. "%.0f view rows, lean %.4f%s", 
                    tostring(self.def and self.def.id), reach, want, sinPOf(self),
                    (reach + 0.5 < want)
                      and (" -- UNPAINTED BAND OF %.1f ROWS AT THE BOTTOM")
                          :format(want - reach)
                      or " -- covered")
      end
      if painted > 0 then return true end
    end
  end

  if self.reportedPath ~= "baked" then
    self.reportedPath = "baked"
    Logger.info("gen4 ground: %s drew from the BAKED path -- the live pass is "
                .. "not running, so standing geometry will not move as the "
                .. "camera does", tostring(self.def and self.def.id))
  end

  -- WHAT THIS PASS ACTUALLY PAINTED, recorded for the map editor's footer.
  --
  -- The black band under a Gen 4 map in the editor has survived five fixes.
  -- The footer now shows that the camera is mid-map, the matrix has terrain
  -- well past it and the clamp is right -- so the renderer is being asked for
  -- the full height and is painting less, and the only thing that can say why
  -- is the loop that does the painting.
  --
  -- Three numbers, because they separate three different causes: `drawn` is
  -- chunks painted, `missing` is chunks the grid HAS but whose canvas was not
  -- ready (a bake budget not yet spent, or a bake that fails every time), and
  -- `empty` is grid cells with no land at all -- the edge of the matrix. A
  -- band with `missing > 0` is a baking problem; with `empty > 0` it is the
  -- world running out; with both zero the geometry is elsewhere.
  local drawn, missing, empty = 0, 0, 0
  local paintTop, paintBottom = math.huge, -math.huge
  for cy = y0, y1 do
    for cx = x0, x1 do
      if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height then
        local land = grid.land[cy * grid.width + cx + 1]
        local canvas = land and self:canvasFor(land) or nil
        if land == nil then empty = empty + 1 end
        if land ~= nil and not canvas then missing = missing + 1 end
        if canvas then
          -- `leanPx` comes back off: the canvas grew upwards, so its ground
          -- still starts at the chunk's own corner.
          -- The chunk's ground starts at its own corner, COMPRESSED -- the
          -- canvas was baked at the camera's pitch, so the only thing left to
          -- do here is put its top-left where that pitch says it goes.
          local sx = cx * px - left
          -- ...and lifted by the chunk's altitude, which on a flat canvas is a
          -- move up the screen of `lift * cos(pitch)` -- the same factor the
          -- live projection gives a unit of height.
          local sy = (cy * px - top) * sinP - self.leanPx
                     - self:chunkLift(cx, cy) * (self.heightScale or 0)
          g.draw(canvas, sx, sy)
          drawn = drawn + 1
          if sy < paintTop then paintTop = sy end
          local reach = sy + (canvas.getHeight and canvas:getHeight()
                              or self.canvasPx or 0)
          if reach > paintBottom then paintBottom = reach end
          local moving = self:animatedFor(land)
          if moving then
            g.draw(moving, sx, sy)
          end
        end
      end
    end
  end
  self.lastPaint = { top = paintTop, bottom = paintBottom, drawn = drawn,
                     missing = missing, empty = empty,
                     want = vh or 0, chunks = (y1 - y0 + 1) }
  -- ...AND SAID OUT LOUD, once per distinct answer.
  --
  -- The footer carries this too, but a footer only helps if the reader
  -- happens to screenshot the bottom of the window -- and the screenshots
  -- that come back are usually cropped above it. A log line survives a copy
  -- and paste of the log, which is how every other answer in this
  -- investigation has actually arrived.
  --
  -- Keyed on the numbers rather than printed per frame: a flood is not a
  -- diagnostic.
  local key = string.format("%d|%d|%d|%.0f|%.0f", drawn, missing, empty,
                            paintBottom == -math.huge and -1 or paintBottom,
                            vh or 0)
  if self.saidPaint ~= key then
    self.saidPaint = key
    Logger.info("gen4 ground: %s painted %.0f..%.0f of a %0.f-tall canvas "
                .. "-- %d chunk(s) in range, %d drawn, %d with no baked "
                .. "canvas, %d with no land",
                tostring(self.def and self.def.id),
                paintTop == math.huge and 0 or paintTop,
                paintBottom == -math.huge and 0 or paintBottom,
                vh or 0, (y1 - y0 + 1) * (x1 - x0 + 1), drawn, missing, empty)
  end
  return drawn > 0
end

-- ---------------------------------------------------------------------------
-- HOW HIGH THE GROUND IS
-- ---------------------------------------------------------------------------
--
-- A Gen 3 map is flat and its one elevation byte per tile is the whole story.
-- A Gen 4 map is a mesh: a bridge crosses over a path, a slope rises between
-- two tiles, a ledge has a top and a bottom at the same point. The BDHC in
-- each chunk is the cartridge's own answer -- sloped plates with a plane each
-- -- and all 666 of them parse, 8,974 plates between them.
--
-- MEASURED, over all 681,984 tile centres in the cartridge:
--
--   * 76.4% have a plate under them
--   * 0.48% have MORE THAN ONE, up to four deep -- which is the bridge case,
--     and the reason this returns a list rather than a number
--   * about 14% of WALKABLE tiles have none, and that is not a gap: a tile
--     with no plate is flat ground at the chunk's own base, which is what
--     DEFAULT is
--
-- AND IT USES THE BRUTE-FORCE LOOKUP, NOT THE STRIP INDEX. The BDHC carries a
-- scanline index for finding plates quickly, and checked against walking every
-- plate it agrees on 99.59% of tiles and DROPS a plate on 404 of 98,304 --
-- never the other way round. Thirteen plates per chunk is nothing to walk, and
-- a height that is silently absent four times in a thousand is a player
-- falling through a bridge.
Gen4Ground.DEFAULT_HEIGHT = 0

function Gen4Ground:bdhcFor(land)
  self.bdhc = self.bdhc or {}
  local hit = self.bdhc[land]
  if hit ~= nil then return hit or nil end

  local record = self.terrain.chunks[land]
  local path = self.terrain.heightFile
  local fs = love and love.filesystem
  if not (record and record.heightBytes and path and fs and fs.newFile) then
    self.bdhc[land] = false
    return nil
  end
  if self.heights == nil then
    local file = fs.newFile(Assets.resolve(path), "r")
    self.heights = file or false
  end
  local file = self.heights or nil
  if not (file and file:seek(record.heightAt)) then
    self.bdhc[land] = false
    return nil
  end
  local bytes = file:read(record.heightBytes)
  local parsed = bytes and require("src.import.Gen4Bdhc").parse(bytes)
  self.bdhc[land] = parsed or false
  return parsed
end

-- heightsAt(tileX, tileY) -> a list of world heights, highest first.
--
-- Map tile coordinates, the same ones collision and the events are in. Empty
-- means no plate, which is the chunk's base rather than a hole.
-- THE EDITOR'S HEIGHT OVERRIDE, in world units, or nil.
--
-- `def.gen4HeightEdits` is a sparse "x,y" -> height table, the same shape and
-- the same allow-listed home as `gen4ModelEdits`. Read here rather than baked
-- into the BDHC blob for the reason every other edit in this tool is a patch:
-- the blob is cartridge data, a re-import replaces it, and an editor that
-- rewrote it would make the import destructive.
--
-- ONE SURFACE, deliberately. A BDHC tile can carry two -- 652 of 42,624 tiles
-- do, which is every bridge in Sinnoh -- and an override replaces them with
-- the single height it names. That is the honest meaning of "this cell is at
-- this height"; a map maker who needs a bridge keeps the cartridge's tile.
function Gen4Ground:heightOverride(tileX, tileY)
  local edits = self.def and self.def.gen4HeightEdits
  if type(edits) ~= "table" then return nil end
  local v = edits[tostring(math.floor(tileX)) .. "," .. tostring(math.floor(tileY))]
  return type(v) == "number" and v or nil
end

-- KEPT, AND NOW A NO-OP, which is deliberate rather than an oversight.
--
-- There was a per-tile height cache here and the editor called this after every
-- height write to drop it. The cache is gone -- it quantised a value that
-- varies across a tile, which is the slope bug this file was reported for --
-- and an override is now read live on every sample, so there is nothing left to
-- invalidate.
--
-- The entry point stays because the editor calls it through `pcall` and because
-- "tell the ground its heights changed" is a real thing for a caller to want to
-- say; a future cache would hang itself here. Removing it would be a silent
-- behaviour change in the editor for no gain.
function Gen4Ground:dropHeightCache()
  self.riseCache = nil
  return self
end

function Gen4Ground:heightsAt(tileX, tileY)
  -- BEFORE THE BDHC, so the list and the single answer cannot disagree.
  -- `heightAt` takes `list[1]`, so an override applied only there would leave
  -- a caller that asked for the LIST -- the walker picking the surface nearest
  -- its own height -- reading the cartridge's heights on an edited cell.
  local over = self:heightOverride(tileX, tileY)
  if over then return { over } end
  local grid = self.grid
  local tiles = self.terrain.chunkTiles or 32
  local mx = tileX + math.floor(self.offsetX / 16)
  local my = tileY + math.floor(self.offsetY / 16)
  if mx < 0 or my < 0 then return {} end
  local cx, cy = math.floor(mx / tiles), math.floor(my / tiles)
  if cx >= grid.width or cy >= grid.height then return {} end
  local land = grid.land[cy * grid.width + cx + 1]
  local bdhc = land and self:bdhcFor(land)
  if not bdhc then return {} end

  local unit = self.terrain.tileUnits or 16
  local half = (self.terrain.chunkUnits or 512) / 2
  -- The centre of the tile, in the chunk's own space -- which is centred on
  -- the origin, so the half-square comes off.
  local x = ((mx % tiles) + 0.5) * unit - half
  local z = ((my % tiles) + 0.5) * unit - half
  -- PLAIN NUMBERS, HIGHEST FIRST -- and this used to sort the records.
  --
  -- `Gen4Bdhc.heightsAt` answers { index = n, height = y } records, not
  -- heights, so `table.sort(list, a > b)` was asking Lua to order two TABLES,
  -- which raises; and `heightAt` below was handing its caller a record where
  -- it promised a number.  Neither had ever fired because nothing called
  -- either function -- the movement grid still reads elevation 0 -- and the
  -- moment something did it would have gone off on the first tile with two
  -- surfaces under it.  Sampled over 42,624 tiles spread across all 666
  -- chunks, 652 of them (1.5%) have more than one plate: every bridge in
  -- Sinnoh, which is exactly where a player walks.
  local records = require("src.import.Gen4Bdhc").heightsAt(bdhc, x, z) or {}
  local list = {}
  for i = 1, #records do list[i] = records[i].height end
  table.sort(list, function(a, b) return a > b end)
  return list
end

-- HOW FAR UP THE SCREEN A THING STANDING HERE IS LIFTED, in pixels.
--
-- The ground leans; whatever is standing on it has to lean with it, or a
-- character walks through the hill they are supposed to be on top of.  This is
-- the same `z - y * cot(pitch)` the chunk bake uses, applied to one point: the
-- height under a tile, times the lean.
--
-- `px`/`py` are MAP PIXELS rather than tiles, so a caller can pass a sprite's
-- own position and get an answer that changes as it walks rather than one that
-- jumps a whole tile early.  It is still a step per tile -- the BDHC's plates
-- are per region, so the ground itself steps there too -- rather than a ramp;
-- a ramp wants the plate's own plane evaluated at the exact point, which
-- `Gen4Bdhc` can do and this does not ask for yet.
--
-- The heights are cached per tile and the RAW height is what is cached, not
-- the lifted pixels: the tilt can change under this and the terrain cannot.
-- HOW FAR UP THE SCREEN THE GROUND UNDER A POINT LIFTS WHATEVER STANDS ON IT.
--
-- `height * cos(pitch)`, because that is what the camera does with a vertical
-- offset.  It was `height * cot(pitch)` to match the oblique, which lifted
-- everything by a sixth too much at the default pitch.
-- THE GROUND UNDER AN EXACT POINT, not under the middle of its tile.
--
-- Reported from play, twice: *"the player seems to fall beneath raised terrain
-- not walking up with it"* -- first at a tilt rung, then at the cartridge rung
-- too, which is what ruled the camera out.
--
-- `heightsAt` takes a TILE and asks the BDHC at that tile's CENTRE, so it
-- answers one height for the whole tile. On flat ground that is exact. On a
-- SLOPE it is not: the plate is a plane, the mesh drawn from it rises
-- continuously across the tile, and a character placed by the tile's centre
-- height therefore steps up in whole-tile jumps while the ground they are
-- standing on ramps underneath them. For most of every step they are below it.
--
-- MEASURED: 8,974 plates across the 666 chunks, 88.8% flat and 11.2% sloped --
-- and the sloped ones are every ramp, every hill path and every cliff approach
-- in Sinnoh, which is exactly the "raised terrain" in the report.
--
-- The plate already knows: `Gen4Bdhc.heightOn` evaluates
-- `y = -(nx*x + nz*z + c) / ny` at whatever point it is given. The file said so
-- and said this did not ask for it yet -- *"a ramp wants the plate's own plane
-- evaluated at the exact point, which `Gen4Bdhc` can do and this does not ask
-- for yet"*. This asks for it.
--
-- `px`/`py` are MAP PIXELS. One pixel is one world unit here, so the position
-- inside the chunk is the map position plus the map's offset, modulo the chunk,
-- less the half-square -- the same arithmetic `heightsAt` does, without the
-- quantising step in the middle.
-- THE CARTRIDGE'S PER-TILE BEHAVIOUR, FOR THE OUTDOOR WORLD.
--
-- Reported from play: *"i cant walk directly into the cave it wont warp me"*.
-- A Gen 4 door or cave mouth is opened by pressing the direction the tile
-- under the player names, and that name is a behaviour byte. Only 302 of
-- Platinum's 593 map defs carry a behaviour grid of their own; every outdoor
-- map -- and so every cave mouth in Sinnoh -- keeps its own in the land
-- chunk's PERMISSION block instead, one u16 per tile, low byte the behaviour.
--
-- Read the same way the BDHC is, through one open file handle and a seek, for
-- the same reason: 666 chunks of 32x32 u16 is 1.3 MB and belongs beside
-- `heights.bin` rather than inside a Lua table.
--
-- `tileX`/`tileY` are MAP-LOCAL tiles, the same space `heightsAt` takes, so a
-- caller that has a cell has no second coordinate system to learn.
-- ONE CHUNK'S PERMISSION BLOCK, FROM WHICHEVER OF THE TWO PLACES HAS IT.
--
-- The binary side-car beside `heights.bin` is the lean one -- a seek and one
-- read -- but it is written by an IMPORT, and an install that has not re-run
-- one since it was added has no side-car at all. Reported from play after the
-- directional entrances were supposedly fixed: *"walking directly into the
-- cave entrance still doesnt work"*. The code was right and had no data.
--
-- `gen4_map_permissions` has been in every Gen 4 cache since the first one.
-- MEASURED over it: 666 chunks, 1,363,968 bytes -- exactly 2048 each, which is
-- 32x32 tiles of u16 -- with the FIRST byte the behaviour (94 distinct values,
-- carrying all eight warp-entrance constants) and the second only ever 0x00 or
-- 0x80, the blocked flag.
--
-- ONE DECODE, TWO SOURCES. The bytes are identical either way, so the only
-- thing that differs is where the block is fetched -- which keeps this out of
-- the shape every bug in this file has had: the same thing spelled differently
-- in two places that never meet.
--
-- Cached per chunk, so a map pays one read for its whole permission grid
-- rather than one per step.
function Gen4Ground:permBlockFor(land)
  if land == nil then return nil end
  self.permBlocks = self.permBlocks or {}
  local held = self.permBlocks[land]
  if held ~= nil then return held or nil end

  local block
  local terrain = self.terrain
  local record = terrain and terrain.chunks and terrain.chunks[land]
  local fs = love and love.filesystem
  if record and record.permAt and record.permBytes
     and terrain.permissionFile and fs and fs.newFile then
    if self.permFile == nil then
      local file = fs.newFile(Assets.resolve(terrain.permissionFile), "r")
      self.permFile = file or false
    end
    local file = self.permFile or nil
    if file and file:seek(record.permAt) then
      local bytes = file:read(record.permBytes)
      if bytes and #bytes == record.permBytes then block = bytes end
    end
  end

  -- THE CACHE'S OWN TABLE, which needs no import to have been re-run.
  if not block then
    local got = self.perms and self.perms[land]
    if type(got) == "string" then block = got end
  end

  self.permBlocks[land] = block or false
  return block
end

-- `tileX`/`tileY` are MAP-LOCAL tiles, the same space `heightsAt` takes, so a
-- caller that has a cell has no second coordinate system to learn.
function Gen4Ground:permissionWordAt(tileX, tileY)
  local grid = self.grid
  local terrain = self.terrain
  if not (grid and grid.land and terrain) then return nil end
  local tiles = terrain.chunkTiles or 32
  local mx = math.floor(tileX) + math.floor((self.offsetX or 0) / 16)
  local my = math.floor(tileY) + math.floor((self.offsetY or 0) / 16)
  if mx < 0 or my < 0 then return nil end
  local cx, cy = math.floor(mx / tiles), math.floor(my / tiles)
  if cx >= grid.width or cy >= grid.height then return nil end
  local block = self:permBlockFor(grid.land[cy * grid.width + cx + 1])
  if not block then return nil end

  local at = ((my % tiles) * tiles + (mx % tiles)) * 2
  -- INSIDE THIS CHUNK'S OWN BLOCK, which a short or half-written one would
  -- otherwise read straight past -- answering another tile with complete
  -- confidence.
  if at + 2 > #block then return nil end
  local lo, hi = block:byte(at + 1, at + 2)
  return lo + hi * 256
end

-- The low byte is the behaviour; bit 15 of the word is the blocked flag and is
-- not part of it.
function Gen4Ground:behaviourAt(tileX, tileY)
  local word = self:permissionWordAt(tileX, tileY)
  if not word then return nil end
  return word % 256
end

function Gen4Ground:heightsAtPixel(px, py)
  -- THE EDITOR'S OVERRIDE STILL WINS, and it is per TILE because that is what
  -- the editor paints. A cell set to one height is flat by construction.
  local over = self:heightOverride(math.floor((tonumber(px) or 0) / 16),
                                   math.floor((tonumber(py) or 0) / 16))
  if over then return { over } end

  local grid = self.grid
  local terrain = self.terrain
  if not (grid and grid.land and terrain) then return {} end
  local chunkPx = self.chunkPx or ((terrain.chunkUnits or 512)
                                   * (terrain.pixelsPerUnit or 1))
  local half = (terrain.chunkUnits or 512) / 2
  local mx = (tonumber(px) or 0) + (self.offsetX or 0)
  local my = (tonumber(py) or 0) + (self.offsetY or 0)
  if mx < 0 or my < 0 then return {} end
  local cx, cy = math.floor(mx / chunkPx), math.floor(my / chunkPx)
  if cx >= grid.width or cy >= grid.height then return {} end
  local land = grid.land[cy * grid.width + cx + 1]
  local bdhc = land and self:bdhcFor(land)
  if not bdhc then return {} end

  local x = (mx % chunkPx) - half
  local z = (my % chunkPx) - half
  local records = require("src.import.Gen4Bdhc").heightsAt(bdhc, x, z) or {}
  local list = {}
  for i = 1, #records do list[i] = records[i].height end
  table.sort(list, function(a, b) return a > b end)
  return list
end

-- The one height to stand on at an exact point. Falls back to the TILE's
-- answer when no plate covers the point -- which keeps the unplated-tile
-- neighbour rule in `heightAt` rather than growing a second copy of it here.
function Gen4Ground:heightAtPixel(px, py)
  local list = self:heightsAtPixel(px, py)
  if list[1] then return list[1] end
  return (self:heightAt(math.floor((tonumber(px) or 0) / 16),
                        math.floor((tonumber(py) or 0) / 16)))
end

function Gen4Ground:rise(px, py)
  local cosP = self.heightScale or 0
  if cosP <= 1e-6 then return 0 end
  -- THE EXACT POINT, AND SO NO PER-TILE CACHE.
  --
  -- The cache held one height per tile, which is the quantising this call was
  -- reported for: a character crossing a sloped tile was drawn at its centre
  -- height the whole way across, so they sank into the ramp and then stepped
  -- up at the boundary instead of walking up it.
  --
  -- Caching an answer that legitimately varies within a tile is not a cache,
  -- it is the bug. The work it saved is one box test per plate of ONE chunk --
  -- 8,974 plates across all 666, so a dozen or so here -- against a per-frame
  -- call for a handful of entities.
  return (self:heightAtPixel(px, py) or 0) * cosP
end

-- The one height to stand on, when the caller has no opinion: the highest.
-- A caller that DOES have one -- a player already under a bridge -- should ask
-- for the list and pick the surface nearest the height they are on.
-- The terrain height in WORLD UNITS at a map position -- what `rise` returns
-- before it is multiplied into screen pixels by `cos(pitch)`.
--
-- Shares `rise`'s SAMPLER rather than a cache, which is the same guarantee for
-- a better reason: the two cannot disagree because there is only one place the
-- ground is read from.
function Gen4Ground:groundY(px, py)
  -- The same exact sample `rise` takes, so the free camera's sprite placement
  -- and the oblique pass's lift cannot disagree about where the ground is --
  -- which is why this shared the cache with `rise` before and shares the
  -- sampler now.
  return self:heightAtPixel(px, py) or 0
end

-- AN UNPLATED TILE TAKES THE GROUND AROUND IT, NOT ZERO.
--
-- Reported from play: *"the player seems to fall beneath raised terrain not
-- walking up with it"*, and *"i cant walk through some cave entrances on
-- raised terrain ... to go through i have to walk into the warp at a weird
-- angle"*. Those are one fault seen twice -- once as a picture and once as
-- collision.
--
-- `heightsAt` says so itself: *"Empty means no plate, which is the chunk's
-- base rather than a hole"*. This function then turned that empty list into
-- `DEFAULT_HEIGHT`, which is 0 -- the bottom of the world. The comment and the
-- code disagreed, and the code won.
--
-- MEASURED over all 666 chunks and 681,984 tiles: 161,182 (23.6%) carry no
-- plate at all. Nearly all of those are void -- 148,799 have no plated
-- neighbour either, and answering 0 for them costs nothing because nobody can
-- stand there. The ones that bite are the other 12,383: tiles with no plate of
-- their own sitting NEXT TO plated ground, and 7,778 of those neighbours are
-- at a non-zero height. Stand on one and you drop to zero while the ground you
-- can see stays up -- and a step onto it from raised ground is a step down a
-- cliff, which is what refuses the walk into a cave mouth and leaves the one
-- diagonal approach that happens to come from another unplated tile.
--
-- The fallback is the HIGHEST plated 4-neighbour, which is the chunk's base in
-- the only sense that is observable from the tile: a doorway's threshold takes
-- the floor it opens onto rather than the void under the wall. One ring only,
-- and no recursion -- a neighbour is asked with `heightsAt`, never with this
-- function, so an unplated region cannot walk the whole chunk looking for
-- ground.
function Gen4Ground:heightAt(tileX, tileY)
  local list = self:heightsAt(tileX, tileY)
  if list[1] then return list[1], list end

  local best
  local x, y = math.floor(tileX), math.floor(tileY)
  local around = { { x - 1, y }, { x + 1, y }, { x, y - 1 }, { x, y + 1 } }
  for _, at in ipairs(around) do
    local near = self:heightsAt(at[1], at[2])
    local h = near[1]
    if h and (best == nil or h > best) then best = h end
  end
  return best or Gen4Ground.DEFAULT_HEIGHT, list
end

function Gen4Ground:release()
  for _, canvas in pairs(self.baked) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.baked, self.order = {}, {}
  -- ...and the canopies, which are baked at the same pitch, go stale with it,
  -- and are a canvas per chunk exactly like the bakes above.
  for _, canvas in pairs(self.canopies or {}) do
    if canvas and canvas.release then pcall(canvas.release, canvas) end
  end
  self.canopies = {}
  -- ...and the moving props' canvases and the terrain meshes held for their
  -- depth pass, which are the two things this map allocated that the loop above
  -- does not walk.
  for _, entry in pairs(self.animated or {}) do
    if type(entry) == "table" and entry.canvas and entry.canvas.release then
      pcall(entry.canvas.release, entry.canvas)
    end
  end
  for _, held in pairs(self.depthModels or {}) do
    if type(held) == "table" and held.release then pcall(held.release, held) end
  end
  self.animated, self.depthModels = {}, {}
  if self.file and self.file.close then pcall(self.file.close, self.file) end
  if self.heights and self.heights.close then pcall(self.heights.close, self.heights) end
  -- ...AND THE PERMISSION SIDE-CAR, which is the third handle this map opens.
  self.permBlocks = nil
  if self.permFile and self.permFile.close then
    pcall(self.permFile.close, self.permFile)
  end
  self.file, self.heights, self.bdhc = nil, nil, nil
  self.permFile = nil
end

return Gen4Ground
