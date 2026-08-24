-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The voxel art classes an override may name, and what each one means.
--
-- ONE LIST, SHARED, BECAUSE THE PANELS HAD DIFFERENT ONES. The Voxels tab
-- built its chooser from the profile's `heights` keys and the preview did the
-- same, which sounds authoritative and is not: `heights` is 28 entries and the
-- vocabulary TileShape actually resolves against is 40. Every class the
-- profile pins by TILE rather than by height -- post, cylinder, grass, canopy,
-- flower, billboard, signpost, stump, shell, rail_face, figures, can, console,
-- prop_bg, prop_ground, mounted -- was simply not offered. Those are not
-- exotic: `post` is every fence in Johto and `grass` is every tuft.
--
-- RESOLUTION ORDER, most authoritative first:
--
--   1. TileShape.CLASS_INFO, if the voxel mod is on the require path. That is
--      the consumer's own table, so a mod that adds a class gets it here with
--      nothing to update.
--   2. This file's table, which mirrors TileShape's FALLBACK_HEIGHTS and ART
--      as of the version it was written against.
--   3. The profile's per-tileset height overrides are layered on top of
--      whichever of those answered, because a tileset entry's `heights` is
--      how the DOJO's 6px tables stop being 12px tables.
--
-- `art` is the fold: how the drawing is applied to the box. It is shown in the
-- editor because it is the difference between a class that stands its artwork
-- upright and one that lays it on top, and picking between `wall` and `roof`
-- without knowing that is guesswork.

local VoxelClasses = {}

-- class -> { h = height in world pixels, art = fold }
VoxelClasses.FALLBACK = {
  ground       = { h = 0,   art = "flat" },
  water        = { h = -2,  art = "flat" },
  void         = { h = 0,   art = "flat" },
  grass        = { h = 0,   art = "grass" },
  flower       = { h = 0,   art = "flower" },
  relief       = { h = 3,   art = "relief" },
  ledge        = { h = 6,   art = "top" },
  bed          = { h = 7,   art = "top" },
  counter      = { h = 8,   art = "upright" },
  stool        = { h = 8,   art = "billboard" },
  can          = { h = 9,   art = "cylinder" },
  fence        = { h = 10,  art = "upright" },
  sign         = { h = 12,  art = "upright" },
  table        = { h = 12,  art = "upright" },
  backrest     = { h = 12,  art = "top" },
  wall         = { h = 16,  art = "upright" },
  tree         = { h = 16,  art = "upright" },
  terrace      = { h = 16,  art = "top" },
  cylinder     = { h = 16,  art = "cylinder" },
  post         = { h = 16,  art = "post" },
  prop         = { h = 16,  art = "billboard" },
  cutout       = { h = 16,  art = "billboard" },
  bike         = { h = 16,  art = "billboard" },
  billboard    = { h = 16,  art = "billboard" },
  signpost     = { h = 16,  art = "billboard" },
  console      = { h = 16,  art = "billboard" },
  stump        = { h = 16,  art = "cylinder" },
  stair_e      = { h = 16,  art = "stair" },
  stair_w      = { h = 16,  art = "stair" },
  stair_down_e = { h = 16,  art = "stair" },
  stair_down_w = { h = 16,  art = "stair" },
  desk         = { h = 24,  art = "upright" },
  roof         = { h = 28,  art = "top" },
  cliff        = { h = 32,  art = "upright" },
  shell        = { h = 32,  art = "upright" },
  waterfall    = { h = 32,  art = "upright" },
  canopy       = { h = 32,  art = "canopy" },
  planter      = { h = 32,  art = "planter" },
  bookcase     = { h = 32,  art = "bookcase" },
  column       = { h = 32,  art = "post" },
}

-- ---------------------------------------------------------------------------
-- which mod's data to edit against
-- ---------------------------------------------------------------------------
--
-- More than one installed mod can define voxel shapes, and they do not agree:
-- a class list is a mod's own authored content, and two of them will pin the
-- same tile to different things on purpose. So the editor cannot just find
-- "the" voxel data -- it has to be told which mod's world is being edited, or
-- it will show heights from one mod while the player is running another.
--
-- Discovered rather than hardcoded: a mod ships voxel data if it has a
-- TileShape that publishes CLASS_INFO, or a data/voxel_heights.lua profile, or
-- both. Anything that does is offered.
local MOD_ROOT = "mods"

local function modFileExists(path)
  local fs = love and love.filesystem
  if not (fs and fs.getInfo) then return false end
  local ok, info = pcall(fs.getInfo, path)
  return ok and info ~= nil
end

local function loadModule(dotted)
  local ok, m = pcall(require, dotted)
  if ok and type(m) == "table" then return m end
  return nil
end

local sourceCache = nil

-- WHICH MODS THE PLAYER ACTUALLY HAS ON.
--
-- A mod folder on disk is not a mod in the world: the launcher's mod list has
-- a toggle per mod, and an experimental one is off until opted into. The
-- editor was picking the first mod it found in `mods/` -- alphabetical -- so a
-- player with two installed and one enabled could open the editor and be shown
-- the world of the one they had turned OFF, under its name, with no hint that
-- the running game looks nothing like it.
--
-- Read once, with the source list, and guarded: the launcher's mod module does
-- real disk work and is not part of the map editor's own dependencies.
local function enabledMods()
  local ok, LM = pcall(require, "src.mods.LauncherMods")
  if not (ok and type(LM) == "table" and LM.list) then return nil end
  local okList, rows = pcall(LM.list)
  if not (okList and type(rows) == "table") then return nil end
  local set, order = {}, {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and row.id then
      set[row.id] = row.enabled and true or false
      order[#order + 1] = row.id
    end
  end
  return set, order
end

function VoxelClasses.sources()
  if sourceCache then return sourceCache end
  local out = {}
  local enabled = enabledMods()
  local fs = love and love.filesystem
  if fs and fs.getDirectoryItems then
    local ok, names = pcall(fs.getDirectoryItems, MOD_ROOT)
    if ok and type(names) == "table" then
      table.sort(names)
      for _, name in ipairs(names) do
        local root = MOD_ROOT .. "/" .. name
        local hasShape = modFileExists(root .. "/lib/TileShape.lua")
        local hasProfile = modFileExists(root .. "/data/voxel_heights.lua")
        if hasShape or hasProfile then
          out[#out + 1] = {
            id = name,
            -- nil, not false, when the launcher could not be asked: "off" and
            -- "unknown" are different answers and only the first should stop a
            -- mod being the default.
            enabled = enabled and (enabled[name] == true) or nil,
            label = name:gsub("_", " "),
            shape = hasShape and (MOD_ROOT .. "." .. name .. ".lib.TileShape") or nil,
            profile = hasProfile
              and (MOD_ROOT .. "." .. name .. ".data.voxel_heights") or nil,
          }
        end
      end
    end
  end
  -- Always last, always present: the table this file carries. It is what the
  -- editor uses when no mod is installed, and naming it explicitly means the
  -- selector never has an empty list and the reader always knows which of the
  -- two they are looking at.
  out[#out + 1] = { id = "builtin", label = "BUILT-IN", builtin = true }
  sourceCache = out
  return out
end

-- Drop the cache when mods may have changed -- the editor calls this when it
-- opens, so an install between sessions is picked up.
function VoxelClasses.rescan()
  sourceCache = nil
end

function VoxelClasses.sourceFor(id)
  local list = VoxelClasses.sources()
  for _, src in ipairs(list) do
    if src.id == id then return src end
  end
  -- NO SELECTION LANDS ON THE FIRST MOD THE PLAYER HAS ON.
  --
  -- Three passes, in order of how sure we are. An ENABLED mod with voxel data
  -- is the world the running game is actually building, which is the only
  -- default that can be right by accident. Then any mod with voxel data, for
  -- the case where the launcher could not be asked at all. The built-in table
  -- is last and is a fallback, never a preference: it is this file's own copy
  -- of a vocabulary, and showing it while a mod is installed is showing a
  -- world nobody is running.
  for _, src in ipairs(list) do
    if (src.shape or src.profile) and src.enabled then return src end
  end
  for _, src in ipairs(list) do
    if src.shape or src.profile then return src end
  end
  return list[#list]
end

-- THE ID `sourceFor` WOULD PICK, as an id rather than a record.
--
-- WHY THIS EXISTS AT ALL. `nil` meant two different things in two files and
-- nobody noticed, because each was locally right:
--
--   VoxelClasses.sourceFor(nil)  "whichever installed mod the player has on"
--   ModShapes.modules(nil)       "no mod -- use the built-in shapes"
--
-- So the 3D preview resolved its CLASS VOCABULARY from an installed mod and
-- its actual PER-TILE SHAPES from neither, and drew a world with the mod's
-- names on the editor's own geometry. Pressing 3D showed built-in shapes with
-- wrong tiles until the reader picked a mod by hand -- at which point
-- `S.voxelSource` was a real string and both files finally agreed.
--
-- The fix is not a cleverer default in either file. It is to stop passing an
-- absence across a boundary where the two sides define it differently: resolve
-- once, here, and hand a concrete id to everything downstream.
function VoxelClasses.defaultSourceId()
  local src = VoxelClasses.sourceFor(nil)
  return src and src.id or "builtin"
end

-- The id to actually USE, given whatever the editor state holds. `nil` becomes
-- the default source; an explicit "builtin" stays builtin, because that is a
-- choice the reader can make and it must not be quietly overridden.
function VoxelClasses.resolveId(sourceId)
  if sourceId ~= nil and sourceId ~= "" then return sourceId end
  return VoxelClasses.defaultSourceId()
end

-- THE MOD'S OWN CLASS VOCABULARY.
--
-- Loaded through ModShapes first, which gives the mod's modules the namespace
-- they are written against (`local V = ...`) and reads them with
-- love.filesystem -- so a mod installed into the SAVE directory, which is
-- where the launcher puts one, is found at all. A plain `require` reaches only
-- what is on package.path, which is the game directory and nothing else.
--
-- The package.path require is kept as a second attempt because it costs one
-- line and covers the case ModShapes cannot: a module already published into
-- package.loaded by something else.
local function fromMod(src)
  if not src then return nil end
  local ok, MS = pcall(require, "tools.map-editor.ModShapes")
  if ok and type(MS) == "table" then
    local mods = MS.modules(src.id)
    local TS = mods and mods.TileShape
    if TS and type(TS.CLASS_INFO) == "table" then return TS.CLASS_INFO end
  end
  if not src.shape then return nil end
  local TS = loadModule(src.shape)
  if TS and type(TS.CLASS_INFO) == "table" then return TS.CLASS_INFO end
  return nil
end

-- Same two attempts, same reason: the mod's own data loader first (it reads
-- through love.filesystem and so sees a mod in the save directory), then
-- package.path.
local function profileOf(src)
  if not src then return nil end
  local ok, MS = pcall(require, "tools.map-editor.ModShapes")
  if ok and type(MS) == "table" then
    local mods = MS.modules(src.id)
    if mods and mods.V then
      local got, prof = pcall(mods.V.data, "voxel_heights")
      if got and type(prof) == "table" then return prof end
    end
  end
  if not src.profile then return nil end
  return loadModule(src.profile)
end

-- `tilesetId` is optional; pass it to pick up that tileset's height overrides.
-- `sourceId` names which mod's data to read; omitted, the first installed one.
function VoxelClasses.info(tilesetId, sourceId)
  local src = VoxelClasses.sourceFor(sourceId)
  local base = fromMod(src) or VoxelClasses.FALLBACK
  local out = {}
  for class, spec in pairs(base) do
    out[class] = { h = spec.h or 0, art = spec.art or "upright" }
  end

  local profile = profileOf(src)
  if type(profile) == "table" then
    -- A class the profile knows and the table above does not: take it at the
    -- profile's height rather than dropping it, so a mod that adds one is
    -- offered even before this file hears about it.
    for class, h in pairs(profile.heights or {}) do
      if type(h) == "number" then
        out[class] = out[class] or { h = h, art = "upright" }
      end
    end
    for _, class in pairs(profile.collision or {}) do
      if type(class) == "string" then
        out[class] = out[class] or { h = 0, art = "upright" }
      end
    end
    if tilesetId then
      local entry = profile.tilesets and profile.tilesets[tilesetId]
      local over = entry and entry.heights
      if type(over) == "table" then
        for class, h in pairs(over) do
          if type(h) == "number" and out[class] then
            out[class] = { h = h, art = out[class].art, tileset = true }
          end
        end
      end
    end
  end

  -- LAST, so it wins: the editor's own per-tileset heights. It has to be
  -- applied here rather than at the panel, because `info` is what the MESHER
  -- reads -- a height changed anywhere else would show in the class list and
  -- not in the render, which is the same "my change did nothing" the store
  -- exists to avoid.
  local mine = VoxelClasses.overrides(tilesetId, sourceId).heights
  if type(mine) == "table" then
    for class, h in pairs(mine) do
      if type(h) == "number" then
        local prev = out[class]
        out[class] = { h = h, art = prev and prev.art or "upright",
                       tileset = true, edited = true }
      end
    end
  end
  return out
end

-- The same thing as a sorted list, which is what a chooser wants.
function VoxelClasses.list(tilesetId, sourceId)
  local info = VoxelClasses.info(tilesetId, sourceId)
  local names = {}
  for class in pairs(info) do names[#names + 1] = class end
  table.sort(names)
  return names, info
end

-- ---------------------------------------------------------------------------
-- tile pins
-- ---------------------------------------------------------------------------

-- Which CLASS a tileset's profile pins each TILE ID to.
--
-- THIS IS THE STEP THE EDITOR WAS MISSING, and it is the reason heights did
-- not match the running mod. TileShape resolves a tile in this order:
--
--   conditional pins -> hop lip -> THE TILE PIN -> collision class ->
--   water cell -> walkable cell -> wall
--
-- The editor had the collision class and the cell rules and nothing else, so
-- every tile the profile pins by hand -- the tables, the stools, the counters,
-- the televisions, the bookcases, every piece of furniture in an interior --
-- resolved by walkability instead and came out as flat floor or as a 16px
-- wall. The pin is the whole point of the profile: it is where a mod states
-- what its own drawings ARE.
--
-- A tileset entry also carries option keys (`heights`, `when_above`,
-- `can_taper`, `bookcase_backfill`, ...) alongside its class lists. Rather
-- than keeping a list of those to skip -- which would go stale the moment a
-- mod added one -- a key counts as a class only if the class table knows it
-- and its value is a list of numbers.
function VoxelClasses.tilePins(tilesetId, sourceId)
  if not tilesetId then return {} end
  local src = VoxelClasses.sourceFor(sourceId)
  local profile = profileOf(src)
  local entry = profile and profile.tilesets and profile.tilesets[tilesetId]
  if type(entry) ~= "table" then return {} end
  local info = VoxelClasses.info(tilesetId, sourceId)

  local pins = {}
  for key, value in pairs(entry) do
    if info[key] and type(value) == "table" then
      for _, tile in ipairs(value) do
        if type(tile) == "number" then pins[tile] = key end
      end
    end
  end
  return pins
end

-- ---------------------------------------------------------------------------
-- the render options a profile carries per tileset
-- ---------------------------------------------------------------------------

-- A tileset entry is not only class lists. Alongside them sit the knobs that
-- say HOW the classes in that tileset are built -- how far a bin tapers, how
-- deep a potted plant's spray of leaves is, whether a bookcase run carries the
-- pane relief on its front. They are the difference between a drawing that
-- reads as what it depicts and one that reads as a box, and until now the only
-- way to touch one was to edit the mod's data file by hand.
--
-- Each row states the DEFAULT the mod itself uses when the key is absent, read
-- out of the consumer rather than guessed: Structures' own locals for the can
-- and stump numbers, TileShape's `bookcaseRelief`/`bookcaseBackfill` for the
-- two bookcase keys. A row whose value in the profile equals the default is
-- still shown -- the point of the panel is that every knob is visible, not
-- only the ones a tileset happens to have bothered to state.
--
-- `preview` says the editor's own mesher models this key, so changing it shows
-- in the 3D view. The rest are saved and reach the GAME -- they are consumed
-- by parts of Structures the preview does not reproduce (the hollowed bin, the
-- pane relief, the length of a conifer run) -- and the panel says so per row
-- rather than letting a control look inert or, worse, look like it worked.
--
-- Table-valued keys (`figures`, `mounted`, `prop_bg`, `when_above`, ...) are
-- deliberately NOT here. They are hand-drawn pixel masks and conditional pin
-- lists; a stepper cannot edit one, and pretending otherwise would offer a
-- control that silently does nothing. The panel reports their presence and
-- leaves them alone.
VoxelClasses.OPTIONS = {
  { key = "can_height", kind = "number", default = 9, min = 1, max = 16,
    doc = "voxels an open bin's body stands" },
  { key = "can_well", kind = "number", default = 5, min = 0, max = 16,
    doc = "how far its mouth is hollowed out" },
  { key = "can_taper", kind = "number", default = 4, min = 0, max = 16,
    doc = "how much its plan narrows toward the floor" },
  { key = "can_cap", kind = "number", default = 9, min = 0, max = 16,
    doc = "art row the drawn mouth ellipse is read from" },
  { key = "can_base", kind = "number", default = 4, min = 0, max = 16,
    doc = "art row the drawn base ellipse is read from" },
  { key = "stump_cap", kind = "number", default = 6, min = 1, max = 16,
    doc = "voxels a stump's body band repeats up to" },
  { key = "column_max", kind = "number", default = 32, min = 1, max = 96,
    doc = "tallest a detected column may rise, in voxels" },
  { key = "planter_spray", kind = "toggle", default = true, preview = true,
    doc = "cap a planter's crown to a flat spray (off: a full ball)" },
  { key = "bookcase_relief", kind = "toggle", default = true,
    doc = "sink a bookcase's panes behind their own frame" },
  { key = "bookcase_backfill", kind = "choice", default = "ground",
    choices = { "ground", "above" },
    doc = "what is painted behind a collapsed shelf's back rows" },
}

local OPTION_BY_KEY = {}
for _, o in ipairs(VoxelClasses.OPTIONS) do OPTION_BY_KEY[o.key] = o end
function VoxelClasses.option(key) return OPTION_BY_KEY[key] end

-- What the profile itself states for one key, normalised to the schema's kind.
--
-- `planter_spray` is the awkward one and is worth stating: the mod writes it
-- as `false` to switch the cap OFF and as a `{rows=,depth=}` table to shape
-- it, and Structures reads "a table with rows > 0" as on. So a table is `true`
-- here, `false` is `false`, and absent is the default -- which is what the mod
-- does with it, rather than what its two spellings look like.
local function profileOption(entry, spec)
  local v = entry and entry[spec.key]
  if v == nil then return nil end
  if spec.kind == "number" then
    return tonumber(v)
  elseif spec.kind == "toggle" then
    if spec.key == "planter_spray" then
      if v == false then return false end
      if type(v) == "table" then return (tonumber(v.rows) or 0) > 0 end
    end
    if type(v) == "boolean" then return v end
    return v and true or false
  elseif spec.kind == "choice" then
    if spec.key == "bookcase_backfill" then
      return v == "above" and "above" or "ground"
    end
    return tostring(v)
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- editor overrides
-- ---------------------------------------------------------------------------

-- The editor's own changes, on top of the mod's. Injected rather than read
-- from MapEdits here so this file stays a reader of mod data with no idea
-- which store or which game is open -- and so a test can hand it a table.
--
-- The provider is called with (tilesetId, sourceId) and returns
-- `{ heights = { <class> = <px> }, options = { <key> = <value> } }`, either
-- key optional.
local overrideProvider = nil

function VoxelClasses.setOverrides(fn)
  overrideProvider = (type(fn) == "function") and fn or nil
end

-- The usual wiring, done once per (store, game) rather than per frame: every
-- panel that shows voxel data calls this on the way in, and calling it with
-- the pair already bound is free. MapEdits is required lazily and nothing in
-- MapEdits requires this file, so there is no cycle.
local boundStore, boundGame = nil, nil

function VoxelClasses.bind(store, game)
  if store == boundStore and game == boundGame then return end
  boundStore, boundGame = store, game
  if not store then
    VoxelClasses.setOverrides(nil)
    return
  end
  local ok, ME = pcall(require, "tools.map-editor.MapEdits")
  if not (ok and type(ME) == "table" and ME.voxelOverrides) then return end
  VoxelClasses.setOverrides(function(tilesetId, sourceId)
    return ME.voxelOverrides(store, game, tilesetId, sourceId)
  end)
end

-- Forget the binding, so the next `bind` re-installs. The panels rebind on
-- every draw, so this only matters to a test that swaps stores.
function VoxelClasses.unbind()
  boundStore, boundGame = nil, nil
  VoxelClasses.setOverrides(nil)
end

function VoxelClasses.overrides(tilesetId, sourceId)
  if not (overrideProvider and tilesetId) then return {} end
  local ok, out = pcall(overrideProvider, tilesetId, sourceId)
  if ok and type(out) == "table" then return out end
  return {}
end

-- Every option for a tileset, resolved: schema default, then whatever the
-- profile states, then whatever the editor has changed. `from` names which of
-- the three won, because "is this value mine or the mod's" is the question a
-- panel showing both has to answer.
function VoxelClasses.options(tilesetId, sourceId)
  local src = VoxelClasses.sourceFor(sourceId)
  local profile = profileOf(src)
  local entry = profile and profile.tilesets and profile.tilesets[tilesetId]
  local over = VoxelClasses.overrides(tilesetId, sourceId).options or {}

  local out = {}
  for i, spec in ipairs(VoxelClasses.OPTIONS) do
    local value, from = spec.default, "default"
    local fromProfile = profileOption(entry, spec)
    if fromProfile ~= nil then value, from = fromProfile, "mod" end
    if over[spec.key] ~= nil then value, from = over[spec.key], "edit" end
    out[i] = { key = spec.key, kind = spec.kind, doc = spec.doc,
               min = spec.min, max = spec.max, choices = spec.choices,
               default = spec.default, value = value, from = from,
               preview = spec.preview or false, modValue = fromProfile }
  end
  return out
end

-- The hand-authored tables a stepper cannot edit, as a list of
-- `{ key, count }` -- so the panel can say a tileset HAS eleven figure masks
-- without pretending it can change one.
function VoxelClasses.optionTables(tilesetId, sourceId)
  local src = VoxelClasses.sourceFor(sourceId)
  local profile = profileOf(src)
  local entry = profile and profile.tilesets and profile.tilesets[tilesetId]
  if type(entry) ~= "table" then return {} end
  local info = VoxelClasses.info(tilesetId, sourceId)

  local out = {}
  for key, value in pairs(entry) do
    if type(value) == "table" and not info[key] and not OPTION_BY_KEY[key]
       and key ~= "heights" then
      local n = 0
      for _ in pairs(value) do n = n + 1 end
      out[#out + 1] = { key = key, count = n }
    end
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

return VoxelClasses
