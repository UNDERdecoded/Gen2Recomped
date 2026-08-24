-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Lift one map out of another game you have already imported.
--
-- WHY THIS NO LONGER READS A CARTRIDGE.
--
-- The first cut opened a .gbc through a file picker and parsed it: SHA-1, the
-- manifest, `RomExtractorGen2.new`, `gen2MapIndex` walking every map header,
-- `readSourceTable` loading the scaffold, then an LZ decompression per map.
-- All of that ran inside a draw call, on the frame the button was pressed,
-- behind a native dialog that blocks the loop while it is open. The editor
-- stopped responding, which from outside is a hang -- because it was one.
--
-- And it was work already done. AN IMPORTED GAME HAS ITS MAPS DECODED ON DISK:
-- the importer wrote `<prefix>data/generated/maps.lua` with the block array,
-- the size, the tileset name, the warps and the objects all resolved. Reading
-- that is one `love.filesystem.load` and a `pcall`. No ROM file, no picker, no
-- parsing, no hang.
--
-- So the source is a DROPDOWN OF GAMES ALREADY IMPORTED. A cartridge that has
-- not been imported does not appear -- import it in the launcher and it does,
-- which is the better flow anyway: the import is the step that verifies the
-- dump, and doing it there means it is verified once rather than per use.
--
-- `require` is no use for reading it: `package.loaded` holds the table for THIS
-- version, already mutated by the editor's own overlay.
-- `love.filesystem.load` goes to the file -- the same escape hatch
-- `Data.seedMissingGen2Tilesets` uses to read a sibling version's tilesets
-- without disturbing the loaded one.
--
-- WHAT COMES ACROSS, and what does not.
--
-- EVERY IMPORTED GAME IS OFFERED, Gen 1 and the romhacks included. The gate
-- is the TILESET, not the generation: a Gen 1 map names Gen 1 tilesets, which
-- a Gen 2 build does not have, so it is refused by name -- which tells the
-- reader what is actually wrong, where hiding the game told them nothing.
--
--   blocks     yes -- the decoded block array, as the extractor wrote it
--   size       yes -- width and height, in 32px blocks
--   tileset    by NAME, when this build has a tileset of that name
--   warps      yes, with destinations dropped (see below)
--   objects    yes -- sprite, position, movement, facing
--   encounters no -- a separate dataset, keyed by map id, not on the record
--   scripts    no -- a script is bytecode against THAT game's addresses
--   text       no -- same reason: a pointer into another game's text bank
--
-- The last three are absent rather than approximated. An NPC arriving with
-- somebody else's dialogue pointer says whatever happens to live at that
-- address in YOUR game, which is worse than saying nothing.
--
-- THE TILESET IS THE HONEST DIFFICULTY. A block id means "row N of this
-- tileset's block table", so a map's blocks are only meaningful next to the
-- tileset they were drawn against. Gold, Silver and Crystal share their tileset
-- names and their block tables are near-identical, so a Johto route crosses
-- cleanly. A game that renamed or renumbered its tilesets does not, and this
-- says so at the point of import rather than drawing rubble.

local MapEdits = require("tools.map-editor.MapEdits")

local RomMapImport = {}

-- ---------------------------------------------------------------------------
-- which games can be read
-- ---------------------------------------------------------------------------

function RomMapImport.gameOf(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring((S and S.version) or v or "unknown")
end

-- EVERY imported game, this one excluded.
--
-- Gen 1 and the romhacks are listed too. An earlier cut showed only Gen 2, on
-- the reasoning that a Gen 1 record has a different block model -- but that
-- reasoning belongs at the IMPORT, not at the list: hiding a game the reader
-- has imported tells them nothing, while showing it and refusing the map with
-- "this build has no tileset called X" tells them exactly what is wrong.
--
-- The tileset check is the real gate and it is honest for both. A Gen 1 map
-- names Gen 1 tilesets, which a Gen 2 build does not have, so it is refused by
-- name rather than by generation -- and if somebody DOES have both datasets
-- and a matching tileset, there is no reason to stand in their way.
--
-- The generation is carried on the row so the panel can mark the ones whose
-- block ids are unlikely to mean the same thing.
--
-- THE CURRENT GAME IS EXCLUDED because copying a map from the game you are
-- editing into itself is what the ASSET library is for, and it does it better:
-- an asset takes the piece you selected rather than a whole map, and it can be
-- stamped anywhere.
function RomMapImport.sources(S)
  local out = {}
  local okGV, GameVersion = pcall(require, "src.core.GameVersion")
  if not okGV then return out end
  local mine = RomMapImport.gameOf(S)
  local mineGen = ((GameVersion.info(mine) or {}).generation) or 2
  for _, id in ipairs(GameVersion.ORDER or {}) do
    local info = GameVersion.info(id) or {}
    if id ~= mine then
      -- "has maps I can read", not "is ready to play". See hasDataset.
      local okD, ready = pcall(RomMapImport.hasDataset, id)
      ready = (okD and ready) or false
      -- EVERY VERSION IS RETURNED, ready or not, with `ready` on the row.
      --
      -- Filtering the unready ones out here is what made "why is Red not in
      -- the list" unanswerable from the panel: an absent row is
      -- indistinguishable from a version the build has never heard of, from
      -- one whose import is half finished, and from a bug in this function.
      -- A greyed row that says "not imported" answers it.
      local gen = info.generation or 1
      out[#out + 1] = { version = id, label = info.name or id:upper(),
                        generation = gen, foreign = gen ~= mineGen,
                        ready = ready }
    end
  end
  return out
end

-- Just the ones that can actually be opened.
function RomMapImport.readySources(S)
  local out = {}
  for _, row in ipairs(RomMapImport.sources(S)) do
    if row.ready then out[#out + 1] = row end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- opening one
-- ---------------------------------------------------------------------------

-- READ THROUGH CacheFs, WHICH IS PREFIX-AWARE AND MOUNT-BLIND.
--
-- `love.filesystem` is the wrong door for a sibling version's data. The
-- running game's cache is MOUNTED onto the read path, so an unprefixed
-- `data/generated/maps.lua` is whichever version is mounted -- and Red's cache
-- prefix is the empty string, so asking love.filesystem for Red's maps while
-- Crystal is mounted returns CRYSTAL'S MAPS UNDER RED'S NAME. Not an error;
-- just quietly the wrong game.
--
-- `CacheFs` reads the save directory with the version's prefix applied and no
-- mount in the way, which is precisely the question. It falls back to
-- love.filesystem only for a NON-EMPTY prefix, where the path is unambiguous.
-- DELEGATED to src/import/AdoptedTileset, which is the copy a player build
-- has. `tools/` is development material and is pruned from game.love (see
-- scripts/pack_love.sh, which keeps only tools/save-editor and the ROM
-- manifests), so a mod EXPORTED from these edits cannot call anything in this
-- file -- and resolving an adopted tileset is exactly what such a mod has to
-- do on someone else's machine. Two copies of this reasoning would drift; the
-- editor uses the shipped one.
local AdoptedTileset = require("src.import.AdoptedTileset")

local function cacheRead(version, rel)
  return AdoptedTileset.cacheRead(version, rel)
end

RomMapImport.cacheRead = cacheRead

-- Does this version have maps we could copy from?
--
-- NOT `RomImporter.isReady`. That answers "is this version ready to PLAY with
-- the current extractor format" -- it checks a format-stamped marker and the
-- full required-file list -- and a dataset written by an older importer fails
-- it while still holding perfectly readable maps. Asking it is why Red, Blue
-- and Yellow were reported as not imported on a machine where they were.
function RomMapImport.hasDataset(version)
  return AdoptedTileset.hasDataset(version)
end

local function loadDataset(version, name)
  return AdoptedTileset.loadDataset(version, name)
end

RomMapImport.loadDataset = loadDataset

-- Open an imported game for reading. Returns a session, or nil plus a reason.
function RomMapImport.open(S, version)
  if not version then return nil, "no game chosen" end
  local maps, path = loadDataset(version, "maps")
  -- `path` is reported on the session so a reader who gets the wrong maps can
  -- see WHICH FILE they came out of, which is the one fact that makes a
  -- shadowing bug diagnosable instead of baffling.
  if not maps then
    return nil, string.format("%s has no readable map data (%s)",
      tostring(version):upper(), tostring(path or "not found"))
  end
  local okGV, GameVersion = pcall(require, "src.core.GameVersion")
  local info = (okGV and GameVersion.info(version)) or {}

  -- SANITY-CHECK THE DATASET AGAINST THE GAME IT CLAIMS TO BE.
  --
  -- Reading the wrong version's file is silent by nature -- it opens, it
  -- parses, it is full of maps -- so the only way to catch it is to ask
  -- whether these maps could belong to that game. A Gen 1 dataset has no
  -- Johto; a Gen 2 one has no Gen 1 Kanto ids that Gen 2 dropped. One
  -- landmark either way is enough to tell them apart, and being wrong here is
  -- worse than being unavailable.
  local gen = info.generation or 1
  local looksGen2 = maps.NEW_BARK_TOWN ~= nil or maps.GOLDENROD_CITY ~= nil
    or maps.AZALEA_TOWN ~= nil
  if gen == 1 and looksGen2 then
    return nil, string.format(
      "%s's data could not be told apart from the running game's - its cache "
      .. "may be shadowed by the mounted one", tostring(info.name or version))
  end

  return {
    version = version,
    name = info.name or tostring(version):upper(),
    generation = gen,
    maps = maps,
    tilesets = (loadDataset(version, "tilesets")),
    path = path,
  }
end

-- Every map in it, sorted by id.
function RomMapImport.list(session)
  if not (session and type(session.maps) == "table") then return {} end
  local out = {}
  for id, def in pairs(session.maps) do
    -- `_romInfo` is the extractor's provenance stamp, not a map; and a record
    -- with no block array is a scaffold row the import never reached.
    if type(id) == "string" and id:sub(1, 1) ~= "_" and type(def) == "table"
       and type(def.blocks) == "table" and #def.blocks > 0 then
      out[#out + 1] = { id = id, tileset = def.tileset,
                        w = def.width, h = def.height, def = def }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function RomMapImport.matches(row, query)
  if not query or query == "" then return true end
  return (row.id or ""):lower():find(query:lower(), 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- bringing its tileset with it
-- ---------------------------------------------------------------------------

-- The namespaced id an adopted tileset takes here.
--
-- `TilesetJohto@gold`, not `TilesetJohto`: a name that cannot collide with a
-- local tileset, so adopting one can never change how an existing map draws.
function RomMapImport.adoptedId(name, version)
  return AdoptedTileset.id(name, version)
end

-- Copy a tileset out of the source game and register it here.
--
-- Returns the new id, or nil plus a reason.
--
-- THE ART IS NOT COPIED, its PATH is rewritten. Every version's cache is a
-- folder beside this one's, so `gold/assets/generated/tilesets/x.png` is
-- already visible to `love.filesystem` -- and a second copy of the PNG would be
-- one more thing to keep in step with a re-import. The path is checked before
-- the record is kept: a tileset registered against art that is not there draws
-- nothing, which is a worse failure than refusing.
function RomMapImport.adoptTileset(S, session, name)
  if not (session and session.version and type(session.tilesets) == "table") then
    return nil, "that game's tileset data could not be read"
  end

  -- THE SHIPPED BUILDER, not a second copy of it -- but fed from the session
  -- the caller already opened rather than re-reading the cache.
  --
  -- `AdoptedTileset.fromRecord` is the same code the EXPORTED mod reaches
  -- through `resolve` on the recipient's machine, so a tileset adopted here
  -- and one resolved there are the same record built the same way; a failure
  -- the author never sees cannot be a difference between them. What differs is
  -- only where the source table came from, which is the one thing that
  -- genuinely differs between the two callers: the editor has the game open,
  -- an installed mod has a name and a cache.
  local copy, why = AdoptedTileset.fromRecord(session.version, name,
                                              session.tilesets[name])
  if not copy then return nil, why end

  local id = AdoptedTileset.id(name, session.version)
  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  local game = RomMapImport.gameOf(S)
  local ok, setWhy = MapEdits.setAdoptedTileset(store, game, id, copy)
  if not ok then return nil, tostring(setWhy or "it could not be recorded") end

  -- live, now: the map about to be created names this id and MapLoader asserts
  -- on a tileset it cannot resolve
  MapEdits.applyAdoptedTilesets(store, game, S.data.tilesets)
  S._tilesetNames, S.warpTilesets = nil, nil
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return id
end

-- ---------------------------------------------------------------------------
-- reconnecting the doors
-- ---------------------------------------------------------------------------
--
-- WHY A WARP ARRIVED WITH NO DESTINATION, and why that was only half right.
--
-- A warp names its destination by MAP ID and by an INDEX into that map's warp
-- list. Both are the source cartridge's, and at the moment a single map is
-- copied neither is meaningful here: the map on the other end has not been
-- imported, and if a local map happens to share the id it is a different place
-- with the same name. So the import dropped the destination and said so.
--
-- The half that was wrong is that it dropped it FOREVER. Import Cerulean Cave
-- 1F and the stairs down point at CERULEAN_CAVE_2F, which is not here yet;
-- import 2F a minute later and it is -- but the first map's door had already
-- been reduced to a pair of coordinates, with nothing left to say where it had
-- once gone. The reader is then asked to reconnect by hand a link the data
-- knew perfectly well.
--
-- So the destination is REMEMBERED rather than dropped (`destSourceMap` and
-- `destSourceWarp` on the warp) and this runs after every import, over every
-- imported map, in both directions. A door resolves the moment both ends are
-- present, whichever order they arrived in.
--
-- WHAT IT WILL NOT DO. It will not link a Gen 1 map's door to a Gen 2 map that
-- happens to share the id. `ROUTE_1` exists in both and they are different
-- places, and a door that silently lands the player in the wrong game's Route
-- 1 is worse than a door that says it needs a destination. Across generations
-- the only links made are to maps imported from the SAME cartridge, where the
-- id genuinely means the same place. Within a generation -- Gold's maps into
-- Crystal -- a local map of that id is the map, and it is used.

-- The engine's own sentinels, which are not map ids and need no translation.
-- `LAST_MAP` means "back where I came from" and `LAST_WARP` means "back onto
-- the tile I stepped through"; both are resolved at run time by Warp.lua
-- against the player's history, so they work unchanged in any build.
RomMapImport.WARP_SENTINELS = { LAST_MAP = true, LAST_WARP = true }

local function generationOf(version)
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if not ok then return nil end
  return ((GameVersion.info(version) or {}).generation)
end

-- Where a door wants to go, expressed locally. Returns the map id and the warp
-- index, or nil plus why it could not be resolved yet.
local function resolveDestination(S, store, game, warp, originGame)
  local want = warp.destSourceMap
  if type(want) ~= "string" or want == "" then
    return nil, "no destination was recorded"
  end
  if RomMapImport.WARP_SENTINELS[want] then
    return want, warp.destSourceWarp or 1
  end

  -- FIRST, A MAP IMPORTED FROM THE SAME CARTRIDGE. This is the case the
  -- feature exists for and it is unambiguous: same game, same id, same place.
  local localId = MapEdits.mapByOrigin(store, game, originGame, want)
  if localId then
    -- AND THE WARP INDEX THROUGH THE OTHER MAP'S OWN TRANSLATION TABLE. The
    -- imported list is not the cartridge's list -- a warp with no coordinates
    -- is skipped -- so index 3 there may be index 2 here. Every imported warp
    -- carries the index it had; this is a search through them for a match.
    local m = MapEdits.bucket(store, game, localId, false)
    local wanted = warp.destSourceWarp
    if wanted then
      for i, w in ipairs((m and m.addedWarps) or {}) do
        if w.sourceWarp == wanted then return localId, i end
      end
    end
    -- The other end is here but that particular warp is not (it had no
    -- coordinates and was skipped). Landing on its first door beats not
    -- landing at all, and beats a nil index, which is a fall through the
    -- floor at run time.
    return localId, 1, "warp " .. tostring(wanted) .. " of " .. want
      .. " was not imported; using its first door"
  end

  -- THEN A LOCAL MAP OF THAT ID, but only within a generation. See the header.
  local mine = generationOf(RomMapImport.gameOf(S))
  local theirs = generationOf(originGame)
  if mine ~= nil and theirs ~= nil and mine == theirs then
    local def = S.data and S.data.maps and S.data.maps[want]
    if def then return want, warp.destSourceWarp or 1 end
  end
  return nil, want .. " is not here yet"
end

-- Reconnect every imported door whose other end can now be found.
--
-- Returns how many were linked, and a list of notes. Cheap enough to run after
-- every import: it walks only the maps the editor created, and only their
-- warps.
function RomMapImport.relinkWarps(S)
  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  local game = RomMapImport.gameOf(S)
  local linked, notes = 0, {}

  for mapId, spec in pairs(MapEdits.newMaps(store, game)) do
    local m = MapEdits.bucket(store, game, mapId, false)
    for _, w in ipairs((m and m.addedWarps) or {}) do
      -- ALREADY LINKED DOORS ARE LEFT ALONE. A reader may have set a
      -- destination by hand, and re-deriving it from the cartridge would
      -- overwrite their answer with the one they had already rejected.
      if w.destMap == nil and w.destSourceMap ~= nil then
        local dest, idx, note = resolveDestination(S, store, game, w,
                                                   spec.originGame)
        if dest then
          w.destMap = dest
          w.destWarp = idx or 1
          linked = linked + 1
          if note then notes[#notes + 1] = note end
        end
      end
    end
  end

  if linked > 0 then
    -- Onto the live defs, or the doors are connected in the store and still
    -- broken in the map the reader is looking at.
    MapEdits.applyAll(store, game, S.data.maps, S.data.tilesets, S.data.sprites)
    S.mapEditsDirty = true
    S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  end
  return linked, notes
end

-- ---------------------------------------------------------------------------
-- landing it
-- ---------------------------------------------------------------------------

-- Import `row` as a new editor map. Returns the new id and a report, or nil
-- and a reason.
--
-- `opts.tileset` overrides the source's own choice, for the case where this
-- build has no tileset of that name. `opts.name` names the map.
function RomMapImport.importMap(S, session, row, opts)
  opts = opts or {}
  local def = row and row.def
  if not (def and type(def.blocks) == "table") then
    return nil, "that map has no block data"
  end

  -- THE TILESET IS CHECKED BEFORE ANYTHING IS COPIED. It is the one thing that
  -- can make the whole import meaningless, and it is answerable from two table
  -- lookups.
  local tilesets = (S.data and S.data.tilesets) or {}
  local wanted = opts.tileset or def.tileset
  local notes = {}
  if not wanted or not tilesets[wanted] then
    -- BRING THE TILESET WITH IT rather than refusing.
    --
    -- A block id means "row N of this tileset's block table", so a map whose
    -- tileset is missing is not a degraded map, it is rubble -- and refusing
    -- was the honest answer only while there was nothing to be done about it.
    -- There is: the source game's tileset is right there in its own dataset,
    -- and adopting it under a namespaced id cannot disturb anything local.
    local adopted, why = RomMapImport.adoptTileset(S, session, def.tileset)
    if not adopted then
      return nil, string.format("%s is drawn with %s, which is not here: %s",
        tostring(row.id), tostring(wanted or "an unknown tileset"),
        tostring(why))
    end
    wanted = adopted
    tilesets = (S.data and S.data.tilesets) or tilesets
    notes[#notes + 1] = string.format("brought %s across as %s",
      tostring(def.tileset), adopted)
  end
  if wanted ~= def.tileset and not (tilesets[wanted] or {}).adopted then
    notes[#notes + 1] = string.format(
      "drawn against %s instead of %s - block ids may not line up",
      wanted, tostring(def.tileset))
  end

  local width = math.max(1, math.floor(def.width or 1))
  local height = math.max(1, math.floor(def.height or 1))
  -- COPIED, not referenced: this table belongs to the other game's dataset,
  -- and the editor writes `def.blocks` in place the moment anyone paints.
  local blocks = {}
  for i = 1, width * height do blocks[i] = def.blocks[i] or 0 end

  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  local game = RomMapImport.gameOf(S)

  local id = MapEdits.createMap(store, game, {
    name = opts.name or row.id,
    width = width, height = height,
    tileset = wanted,
    borderBlock = def.borderBlock or 0,
    blocks = blocks,
    -- STAMPED WITH WHERE IT CAME FROM. The local id is freshly minted and
    -- says nothing about the cartridge; this pair is what lets a door
    -- imported from the same game find this map later. See relinkWarps.
    originGame = session and session.version or nil,
    originMap = row.id,
  })
  if not id then return nil, "the map could not be created" end

  -- WARPS AND OBJECTS AFTER THE MAP, and through `addWarp`/`addObject` rather
  -- than on the spec: `MapEdits.MAP_FIELDS` carries neither, so a spec with
  -- them would have them dropped by `typedCopy` -- an import that reported
  -- success and landed a map with no doors in it.
  local warps, objects = 0, 0
  for srcIndex, wp in ipairs(def.warps or {}) do
    if wp.x and wp.y and not wp.removed then
      -- THE DESTINATION IS REMEMBERED, NOT RESOLVED, and not dropped either.
      --
      -- It names a map in the OTHER game, which right now is either not here
      -- or is a different place with the same id -- so it cannot become
      -- `destMap` yet, and a warp pointing at a map that is not there crashes
      -- on use. But the pair it named is the only record of where this door
      -- went, and throwing it away is what made a copied cave a set of
      -- disconnected floors. Kept here; `relinkWarps` turns it into a real
      -- destination as soon as the other end exists, in either order.
      MapEdits.addWarp(store, game, id, {
        x = wp.x, y = wp.y, destWarp = 1,
        destSourceMap = type(wp.destMap) == "string" and wp.destMap or nil,
        destSourceWarp = tonumber(wp.destWarp) or nil,
        sourceWarp = srcIndex,
      })
      warps = warps + 1
    end
  end
  for _, o in ipairs(def.objects or {}) do
    if o.x and o.y then
      -- The sprite travels as a NAME. Where this build has no sheet of that
      -- name `NPC.resolveSpriteDef` already has a whole cascade for it, and
      -- naming what was actually there beats silently substituting.
      MapEdits.addObject(store, game, id, {
        sprite = o.sprite, x = o.x, y = o.y,
        movement = o.movement, range = o.range, item = o.item,
      })
      objects = objects + 1
    end
  end

  notes[#notes + 1] =
    "encounters, scripts and dialogue did not come across - see the header note"

  MapEdits.applyAll(store, game, S.data.maps, S.data.tilesets, S.data.sprites)

  -- AND NOW THE DOORS, in both directions: this map's, whose other ends may
  -- already be here, and the ones on maps imported earlier that were waiting
  -- for THIS map to arrive.
  local linked, relinkNotes = RomMapImport.relinkWarps(S)
  for _, n in ipairs(relinkNotes or {}) do notes[#notes + 1] = n end
  local open = 0
  do
    local m = MapEdits.bucket(store, game, id, false)
    for _, w in ipairs((m and m.addedWarps) or {}) do
      if w.destMap == nil then open = open + 1 end
    end
  end
  if linked > 0 then
    notes[#notes + 1] = linked .. " door(s) reconnected to their other end"
  end
  if open > 0 then
    notes[#notes + 1] = open .. " door(s) still need a destination - import "
      .. "the map on the other side and they will connect themselves"
  end
  -- SAID AT IMPORT, not only at export.
  --
  -- This is the moment the dependency is created, and the moment the reader
  -- has the context to understand it -- they just chose the cartridge. Told
  -- only at export, it arrives weeks later attached to a button press that
  -- has nothing obviously to do with it.
  --
  -- It is also the honest framing of what just happened: the map is HERE, and
  -- the art it is drawn with is still over there, in a cache that belongs to
  -- the other game. Nothing was copied that could be handed on.
  notes[#notes + 1] = string.format(
    "this map is drawn from %s's own art, so anything exported with it will "
    .. "need %s imported to work", tostring(session.name or session.version),
    tostring(session.name or session.version))
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return id, { blocks = #blocks, warps = warps, objects = objects,
               linked = linked, open = open, notes = notes }
end

return RomMapImport
