-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The map editor's edit store: a PATCH over the extracted data, never a rewrite.
--
-- THE ONE DESIGN DECISION EVERYTHING ELSE FOLLOWS. Extracted map data is
-- regenerated from the cartridge every time a ROM is (re-)imported -- that is
-- the whole point of the importer, and this session alone has shipped three
-- fixes that only reach a player through a re-import. If the editor wrote its
-- changes INTO data/generated_*, every one of them would be destroyed by the
-- next import, silently, and the player would have no way to tell an edit that
-- was lost from one they never made.
--
-- So edits live in their own file, keyed by version and map, and are applied
-- ON TOP of whatever the current extraction produced. A re-import replaces the
-- base and keeps every edit. The cost is that an edit can go stale -- an object
-- index that no longer exists, a tile outside a resized map -- and `apply`
-- reports those rather than dropping them silently, because an edit the player
-- made and cannot see is the failure mode worth being loud about.
--
-- WHERE IT LIVES: the LOVE save directory, beside options.lua and the saves --
-- not the game folder. Same reasoning as SaveData: the game directory may be
-- read-only (an .app bundle, a packaged .love, a console), and an editor that
-- can only save on some installs is worse than one that saves consistently
-- somewhere findable.
--
-- SHAPE
--
--   { version = 1,
--     games = {
--       crystal = {
--         maps = {
--           ROUTE_29 = {
--             -- terrain, keyed "x,y" so a sparse edit costs one entry
--             voxels  = { ["12,7"] = { h = 32, art = "cliff" } },
--             -- patches to objects the cartridge already has, keyed by the
--             -- object's own `index` (NOT its position in the list: a patch
--             -- has to survive the list being reordered)
--             objects = { [3] = { x = 5, y = 6, text = "...", ... } },
--             -- objects the editor invented. `index` is assigned on apply,
--             -- after the cartridge's, so it can never collide with one.
--             added   = { { sprite = "SPRITE_GRAMPS", x = 4, y = 9, ... } },
--             -- cartridge objects the editor deleted, by index
--             removed = { [7] = true },
--           },
--         },
--       },
--     },
--   }
--
-- Every field in an `objects` patch is optional and overrides exactly itself,
-- so an edit to a sprite does not freeze that object's coordinates at whatever
-- they were when the edit was made.

local MapEdits = {}

MapEdits.FORMAT = 1
MapEdits.FILENAME = "map_edits.lua"

-- Fields an object patch may carry. Anything not in here is refused rather
-- than written: a typo'd key would otherwise round-trip through the file and
-- do nothing, which reads as "the editor did not save my change".
--
-- The first group is the cartridge's own object_event record (see
-- RomExtractorGen2's object emission); the rest are the editor's additions.
MapEdits.OBJECT_FIELDS = {
  sprite = "string",       -- SPRITE_* id
  x = "number", y = "number",
  movement = "string",     -- STAY | WALK | SPIN
  range = "string",        -- facing for STAY, roam/spin kind otherwise
  big = "boolean",         -- 2x2 footprint (Snorlax / Lapras dolls)
  eventFlag = "string",    -- EVENT_G2_nnnn; absent = always visible
  hidden = "boolean",
  timeOfDay = "number",    -- MORN/DAY/NITE bitmask
  -- what the object DOES
  text = "string",         -- plain dialogue, the common case
  script = "table",        -- lowered script rows, for anything text cannot say
  item = "string",         -- ITEM_* for a ball/item object
  -- a trainer, and the team they fight with
  -- The KEY of a row in `data.trainers`, e.g. OPP_YOUNGSTER -- not the bare
  -- class name. `BattleState.newTrainer` does `data.trainers[oppClass]` and
  -- ASSERTS on a miss, so a hand-typed "YOUNGSTER" is not a trainer with a
  -- wrong label, it is a crash the moment the player walks into its line of
  -- sight. The editor picks it from the table for that reason.
  trainerClass = "string",
  trainerName = "string",
  -- A TEAM THE AUTHOR BUILT, rather than an index into one the cartridge
  -- shipped. `trainerParty` below picks a party out of `trainerClass`; this is
  -- for the NPC nobody wrote a party for.
  --
  -- An array of slots in the shape BattleState.newTrainer already consumes:
  -- { species, level, moves = {...}, dvs, statExp, stats, happiness }. Stored
  -- as the engine's own shape on purpose -- a private editor format would need
  -- a translation step, and a translation step is a second place for a team to
  -- be subtly wrong.
  trainerTeam = "table",
  -- HOW FAR THEY SEE, in blocks, along the way they are facing.
  --
  -- The cartridge keeps this in a TRAINER HEADER keyed by (map label, object
  -- index) -- not on the object -- so an NPC the editor invented has no header
  -- and reads range 0, which means "never notices anyone". That is why an
  -- added trainer only ever fought when talked to.
  --
  -- Stored on the object so an authored trainer can have one at all, and so a
  -- cartridge trainer's can be changed without rewriting a header table the
  -- next ROM import would overwrite. Absent means "use the header's", which is
  -- what every unedited trainer wants; 0 means "talk to me", which is a real
  -- answer the cartridge itself uses for gym trainers and the Karate Master.
  sightRange = "number",
  -- WHICH TRAINER INSIDE THE CLASS. Gen 2 packs several rosters into one
  -- class (`partyNames`) and the runtime reads this to tell them apart --
  -- `newTrainer(Game, d.trainerClass, d.trainerParty)`. It had no way of
  -- being set, so every editor-made trainer was silently the first one.
  trainerParty = "number",
  party = "table",         -- { { species=, level=, moves={} }, ... }
  intro = "string", defeat = "string", -- before the battle / on losing
}

-- NO `mat` FIELD, deliberately. An earlier cut had one, and it was exactly the
-- thing this allow-list exists to prevent: TileShape has no material or colour
-- concept -- a shape is { class, h, art, flat, authored } and colour comes from
-- the tileset atlas (GoldColorAtlas), not from the shape -- so `mat` would have
-- saved to disk, survived a reload, and done nothing forever. A field that
-- persists and has no consumer is worse than a missing feature: it looks like
-- it works. If a material concept is ever added to the renderer, add it here
-- at the same time and not before.
-- A warp record, from RomExtractorGen2's warp_event emission:
--   { y, x, destWarp, destMap }
-- `destWarp` is 1-BASED and indexes the DESTINATION map's warp list -- it is
-- which warp you arrive at, not a coordinate. The extractor already clamps it
-- with math.max(1, ...) because a 0 in the cartridge means "the first one".
-- `destMap` is a map id; the extractor also emits the special values
-- "LAST_WARP" (go back where you came from) and, in map scripts, "LAST_MAP".
MapEdits.WARP_FIELDS = {
  x = "number", y = "number",
  destMap = "string",
  destWarp = "number",
  -- WHERE THIS DOOR WENT IN THE GAME IT CAME FROM, kept alongside where it
  -- goes HERE. A warp copied out of another cartridge names a map by that
  -- cartridge's id and a warp by its index in that map's list, and neither
  -- means anything locally until the map on the other end has been imported
  -- too -- which may be in ten minutes, or never. Dropping the pair (which is
  -- what used to happen) makes the door unresolvable forever; keeping it makes
  -- the link a question that can be answered later, by `relinkWarps`.
  destSourceMap = "string",
  destSourceWarp = "number",
  -- And this warp's OWN index in the source map, so a door arriving from the
  -- other side can find it. `destWarp` is a position in a list, and the list
  -- an import builds is not the list the cartridge had -- warps with no
  -- coordinates are skipped -- so the numbers have to be translated rather
  -- than copied.
  sourceWarp = "number",
}

-- A whole map the editor invented. Only the fields a map cannot render without
-- are required; everything else is optional and the runtime already has a
-- default for it. `blocks` is a FLAT array of width*height block ids -- see
-- Map.lua's `def.blocks[by * def.width + bx + 1]`, which is also why width and
-- height are in 32px BLOCKS and not cells or pixels.
MapEdits.MAP_FIELDS = {
  name = "string",
  width = "number", height = "number",
  tileset = "string",
  borderBlock = "number",
  blocks = "table",
  music = "string",
  palette = "string",
  environment = "string",
  -- WHICH CARTRIDGE THIS MAP WAS COPIED OUT OF, and what it was called there.
  -- An imported map is given a fresh local id (the cartridge's may already be
  -- taken, and two imports of the same map must not collide), so the original
  -- name is the only way anything can ask "is the map this door wants already
  -- here". Absent on a map the editor invented from nothing, which is correct:
  -- there is no cartridge to point back at.
  originGame = "string",
  originMap = "string",
}

-- A CHARACTER SHEET THE PLAYER BROUGHT.
--
-- Same shape as the fields `data.sprites` carries and `SpriteRenderer.new`
-- reads, and no more: `image` is a path, `frames` is how many 16px cells are
-- stacked down it, `walker` says whether the last three are the walk poses.
-- `big` with `width`/`height` is the 32x32 doll case (Snorlax, Lapras), which
-- SpriteRenderer detects from the image anyway but which the record has to
-- agree with or the frame count fights the quad.
--
-- NOT `index`. That is an OverworldSprites row number -- a claim on a slot in
-- the cartridge's own table -- and an imported sheet has no business claiming
-- one: the id is how the editor and the mod refer to it, and the id is enough.
MapEdits.SPRITE_FIELDS = {
  image = "string",
  frames = "number",
  walker = "boolean",
  big = "boolean",
  width = "number", height = "number",
  trueColor = "boolean",
  source = "string",
}

MapEdits.VOXEL_FIELDS = {
  h = "number",            -- height in world pixels (the profile's own unit)
  art = "string",          -- the shape/art class TileShape would otherwise derive
  -- HOW THE ARTWORK IS WORN, separately from WHAT the square is.
  --
  -- `art` above names a CLASS -- wall, roof, cylinder -- and a class carries
  -- its own fold. That is one control for two decisions, and they are not the
  -- same decision: a thing can be a `wall` for every purpose the detector
  -- cares about and still need its drawing standing up rather than lying
  -- down, or read per pixel so its gaps stay gaps.
  --
  -- It has a REAL CONSUMER, which is the only reason it is here: `Structures`
  -- dispatches the form off `s.art` on the shape TileShape returns
  -- (`s.art == "billboard"`, `== "post"`, `== "cylinder"` ...), so replacing
  -- that one string is the whole of it -- no change to the mesher, no new
  -- field for anything downstream to ignore.
  fold = "string",
  -- SUB-TILE HEIGHTS: `{ res = 2|4|8, h = { ... } }`.
  --
  -- `h` alone is one number for the whole 8px tile, which is as fine as the
  -- shape contract goes. This is the finer grid under it: `res` subdivisions
  -- per axis -- 2 for 4px squares, 4 for 2px, 8 for 1px -- and `res * res`
  -- heights, row-major from the tile's north-west corner.
  --
  -- It has a real consumer: ChunkMesher's box branch emits one little box per
  -- sub-square when a shape carries this, and takes its ordinary tile-sized
  -- path when it does not. A tile with no `sub` renders exactly as it always
  -- did, which is what makes this safe to add.
  sub = "table",
  -- NO `solid`. TileShape's override path reads `o.art` and `o.h` and
  -- nothing else, so a walkability flag stored here reached no consumer --
  -- it saved, it loaded, and the world was unchanged. Removed rather than
  -- left in as a field a future reader might believe: typedCopy now
  -- refuses it, which is the loud version of what was already happening.
}

-- ---------------------------------------------------------------------------
-- storage
-- ---------------------------------------------------------------------------

local function fs()
  return love and love.filesystem or nil
end

local function serialise(value, indent)
  indent = indent or ""
  local t = type(value)
  if t == "string" then return string.format("%q", value) end
  if t == "number" or t == "boolean" then return tostring(value) end
  if t ~= "table" then return "nil" end

  -- Sorted keys: the file is meant to be diffable and hand-readable. A table
  -- that reorders itself every save turns "what did I change" into a wall.
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return tostring(a) < tostring(b) end
    return type(a) == "number"
  end)

  local out, inner = { "{" }, indent .. "  "
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and k:match("^[%a_][%w_]*$")
      and (k .. " = ")
      or ("[" .. serialise(k) .. "] = ")
    out[#out + 1] = inner .. key .. serialise(value[k], inner) .. ","
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out, "\n")
end

MapEdits.serialise = serialise

function MapEdits.empty()
  return { version = MapEdits.FORMAT, games = {} }
end

function MapEdits.load()
  local f = fs()
  if not (f and f.getInfo and f.getInfo(MapEdits.FILENAME)) then
    return MapEdits.empty()
  end
  local src = f.read(MapEdits.FILENAME)
  if type(src) ~= "string" or src == "" then return MapEdits.empty() end
  local chunk = loadstring or load
  local ok, fn = pcall(chunk, "return " .. src, "@" .. MapEdits.FILENAME)
  if not ok or not fn then return MapEdits.empty(), "map_edits.lua did not parse" end
  local ok2, data = pcall(fn)
  if not ok2 or type(data) ~= "table" then
    return MapEdits.empty(), "map_edits.lua did not return a table"
  end
  data.version = data.version or MapEdits.FORMAT
  data.games = type(data.games) == "table" and data.games or {}
  return data
end

function MapEdits.save(store)
  local f = fs()
  if not (f and f.write) then return false, "no writable filesystem" end
  if type(store) ~= "table" then return false, "nothing to save" end
  store.version = MapEdits.FORMAT
  local body = "-- Gen2Recomped map editor. Generated; safe to hand-edit.\n"
    .. "-- Patches over the EXTRACTED map data, so a ROM re-import keeps these.\n"
    .. serialise(store) .. "\n"
  local ok, err = f.write(MapEdits.FILENAME, body)
  if not ok then return false, tostring(err) end
  -- WHAT WAS ACTUALLY WRITTEN, AND UNDER WHICH GAME KEY.
  --
  -- "Map edits saved" is the editor's own word for it and it cannot see the
  -- two things that make an edit vanish between here and the next boot: the
  -- key the store is filed under, and whether the rows are in it at all. The
  -- game reads this file under `GameVersion.current`, which is a different
  -- variable set on a different code path -- so a store written under
  -- `crystal` and read under `red` is a save that worked, a load that worked,
  -- and an edit nobody can find.
  pcall(function()
    local Logger = require("src.core.Logger")
    local parts = {}
    for game, g in pairs(store.games or {}) do
      local maps, added = 0, 0
      for _, m in pairs(g.maps or {}) do
        maps = maps + 1
        added = added + #((m and m.added) or {})
      end
      local news = 0
      for _ in pairs(g.newMaps or {}) do news = news + 1 end
      parts[#parts + 1] = string.format("%s: %d map(s), %d added object(s), "
                                        .. "%d new map(s)", game, maps, added,
                                        news)
    end
    Logger.info("map editor: saved %d bytes to %s%s [%s]", #body,
      (f.getSaveDirectory and (f.getSaveDirectory() .. "/")) or "",
      MapEdits.FILENAME,
      (#parts > 0) and table.concat(parts, "; ") or "EMPTY - nothing stored")
  end)
  return true
end

-- ---------------------------------------------------------------------------
-- reading and writing one map's edits
-- ---------------------------------------------------------------------------

local function bucket(store, game, mapId, create)
  if type(store) ~= "table" or not game or not mapId then return nil end
  local games = store.games
  if not games then
    if not create then return nil end
    games = {}
    store.games = games
  end
  local g = games[game]
  if not g then
    if not create then return nil end
    g = { maps = {} }
    games[game] = g
  end
  g.maps = g.maps or {}
  local m = g.maps[mapId]
  if not m then
    if not create then return nil end
    m = {}
    g.maps[mapId] = m
  end
  return m
end

MapEdits.bucket = bucket

local function typedCopy(patch, allowed)
  local out, rejected = {}, nil
  for k, v in pairs(patch or {}) do
    local want = allowed[k]
    if want and (type(v) == want or v == nil) then
      out[k] = v
    else
      rejected = rejected or {}
      rejected[#rejected + 1] = tostring(k)
    end
  end
  return out, rejected
end

-- `nil` for a field CLEARS it, which is how an edit is undone. Passing an
-- empty patch removes the object's entry entirely rather than leaving a `{}`
-- behind, so a file with no edits in it really is empty.
-- MERGE a field patch into whatever this index is already carrying, rather
-- than replacing it.
--
-- Callers write ONE FIELD AT A TIME -- the panels have a stepper per
-- coordinate and a chooser per name -- so a replacing setter meant the last
-- field edited was the only one kept. It was invisible while a panel wrote
-- through `bucket` by hand (Objects.lua does), and it bit the moment a second
-- panel used the setter: writing an NPC's script on the SCRIPTS tab discarded
-- the sprite that had just been picked for it on OBJECTS, with no error and
-- nothing on screen until the next reload.
--
-- Clearing an index is `patch == nil` at the call site, which the setters
-- handle before they get here; there is deliberately no way to unset a single
-- FIELD, because a table cannot carry a nil to mean it and no caller needs one.
local function mergePatch(into, index, clean, rejected)
  if next(clean) == nil then return rejected end
  local existing = into[index]
  if existing then
    for k, v in pairs(clean) do existing[k] = v end
  else
    into[index] = clean
  end
  return rejected
end

function MapEdits.setObject(store, game, mapId, index, patch)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.objects = m.objects or {}
  if patch == nil then
    m.objects[index] = nil
    return true
  end
  local clean, rejected = typedCopy(patch, MapEdits.OBJECT_FIELDS)
  return true, mergePatch(m.objects, index, clean, rejected)
end

function MapEdits.setVoxel(store, game, mapId, x, y, patch)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.voxels = m.voxels or {}
  local key = string.format("%d,%d", math.floor(x), math.floor(y))
  if patch == nil then
    m.voxels[key] = nil
    return true
  end
  local clean, rejected = typedCopy(patch, MapEdits.VOXEL_FIELDS)
  if next(clean) == nil then
    m.voxels[key] = nil
  else
    m.voxels[key] = clean
  end
  return true, rejected
end

-- Warps are patched by INDEX like objects, for the same reason: the list can be
-- reordered by a re-import and a positional patch would then land on the wrong
-- door.
function MapEdits.setWarp(store, game, mapId, index, patch)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.warps = m.warps or {}
  if patch == nil then
    m.warps[index] = nil
    return true
  end
  local clean, rejected = typedCopy(patch, MapEdits.WARP_FIELDS)
  return true, mergePatch(m.warps, index, clean, rejected)
end

-- ---------------------------------------------------------------------------
-- minted tileset blocks
-- ---------------------------------------------------------------------------

-- A CELL IS NOT A BLOCK, and the map only stores blocks.
--
-- Gen 2 map data is one block id per 32x32 block; a block is a 4x4 grid of 8px
-- tiles and FOUR 16px cells. So "change the art on this cell" has nowhere to
-- go: writing a different block id repaints all four cells, which is what the
-- editor did and what it looked like -- pressing + on one tile changed the
-- square around it.
--
-- The way to change one cell is to MINT a block: copy the block the cell sits
-- in, replace that cell's quadrant (its four tiles and its collision class),
-- append the result to the tileset, and point the cell at the new id. Three
-- neighbours keep their art because they are still the same drawing; the cell
-- changes because it is now a different block that differs only there.
--
-- KEYED BY CONTENT, NOT BY ID. The id a minted block lands on is `however many
-- blocks the tileset already had, plus its position in this list` -- and a
-- re-import can change the first half of that. Storing the number would leave
-- every edited cell pointing at whatever block happened to take that slot. So
-- the store holds a KEY, the apply pass resolves keys to ids after appending,
-- and a map's block patch may hold either a number (a cartridge block) or one
-- of these keys.
MapEdits.MINT_PREFIX = "MINT:"

local function mintKey(tilesetId, n)
  return string.format("%s%s:%d", MapEdits.MINT_PREFIX, tostring(tilesetId), n)
end

function MapEdits.isMintKey(v)
  return type(v) == "string" and v:sub(1, #MapEdits.MINT_PREFIX) == MapEdits.MINT_PREFIX
end

local function tilesetBucket(store, game, tilesetId, create)
  store.games = store.games or {}
  local g = store.games[game]
  if not g then
    if not create then return nil end
    g = { maps = {} }
    store.games[game] = g
  end
  if not g.tilesets then
    if not create then return nil end
    g.tilesets = {}
  end
  local t = g.tilesets[tilesetId]
  if not t then
    if not create then return nil end
    t = { blocks = {} }
    g.tilesets[tilesetId] = t
  end
  return t
end

MapEdits.tilesetBucket = tilesetBucket

-- Mint a block, or return the key of an identical one already minted.
--
-- The dedupe is not an optimisation. Painting a row of ten cells the same way
-- would otherwise mint ten identical blocks, and a tileset has a finite id
-- space -- Gen 2 block ids are a byte, and the map stores them as one.
function MapEdits.mintBlock(store, game, tilesetId, tiles, coll)
  if type(tiles) ~= "table" or #tiles ~= 16 then return nil, "need 16 tiles" end
  local t = tilesetBucket(store, game, tilesetId, true)
  if not t then return nil end
  t.blocks = t.blocks or {}

  local function same(a, b, n)
    for i = 1, n do if a[i] ~= b[i] then return false end end
    return true
  end
  for i, existing in ipairs(t.blocks) do
    if same(existing.tiles, tiles, 16)
       and same(existing.coll or {}, coll or {}, 4) then
      return mintKey(tilesetId, i)
    end
  end

  local copyT, copyC = {}, {}
  for i = 1, 16 do copyT[i] = tiles[i] end
  for i = 1, 4 do copyC[i] = (coll or {})[i] end
  t.blocks[#t.blocks + 1] = { tiles = copyT, coll = copyC }
  return mintKey(tilesetId, #t.blocks)
end

-- ---------------------------------------------------------------------------
-- what lives in the grass
-- ---------------------------------------------------------------------------

-- WILD ENCOUNTERS, per map and per terrain.
--
-- Gen 2 stores one encounter table per MAP, not per patch: every square of
-- tall grass on Route 29 rolls against the same seven slots, and the game has
-- no concept of "this corner has Rattata and that one has Sentret". Three sets
-- of those seven exist -- morning, day and night -- and water and the three
-- fishing rods carry their own. That is the whole shape, and an editor that
-- offered per-patch tables would be offering something the roll cannot read.
--
-- Stored as a WHOLE terrain table rather than as a patch of one, unlike almost
-- everything else in this file. A slot list is seven entries whose meaning is
-- entirely positional -- slot 4 is the 20/256 bucket -- so a sparse patch
-- keyed by index would silently mean something different the moment the
-- buckets changed length, and the buckets are per record.
MapEdits.WILD_TERRAINS = { "grass", "water" }
MapEdits.WILD_TIMES = { "day", "morn", "nite" }

function MapEdits.wilds(store, game, mapId)
  local m = bucket(store, game, mapId, false)
  return (m and m.wilds) or nil
end

-- The table the GAME would roll against, edit applied: the stored override for
-- this terrain and time if there is one, else the import's own.
--
-- One reader for the panel and the apply both, because "what does this map do
-- now" has to have a single answer -- two implementations of the resolution
-- order is how a panel comes to show a world the game will not build.
function MapEdits.wildTable(store, game, mapId, base, terrain, time)
  time = time or "day"
  local mine = MapEdits.wilds(store, game, mapId)
  local edited = mine and mine[terrain] and mine[terrain][time]
  if edited then return edited, true end
  local from = base and base[terrain]
  if not from then return nil, false end
  if time ~= "day" then
    return (from.byTime and from.byTime[time]) or from, false
  end
  return from, false
end

-- `tbl` is `{ rate = n, slots = { { species =, level = }, ... } }`, or nil to
-- drop the override and go back to the cartridge's own.
function MapEdits.setWildTable(store, game, mapId, terrain, time, tbl)
  if type(terrain) ~= "string" then return false end
  time = time or "day"
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  if tbl == nil then
    if m.wilds and m.wilds[terrain] then m.wilds[terrain][time] = nil end
    if m.wilds and m.wilds[terrain] and next(m.wilds[terrain]) == nil then
      m.wilds[terrain] = nil
    end
    if m.wilds and next(m.wilds) == nil then m.wilds = nil end
    return true
  end
  if type(tbl) ~= "table" then return false end
  -- COPIED, not referenced. The caller's table is usually the IMPORT's own
  -- record -- the panel starts an edit from what is already there -- and
  -- storing it by reference would make every later change to the override a
  -- change to the extracted data too, which the next re-import would then
  -- appear to lose.
  local copy = { rate = math.max(0, math.min(255, math.floor(tonumber(tbl.rate) or 0))),
                 slots = {} }
  for i, slot in ipairs(tbl.slots or {}) do
    if type(slot) == "table" then
      copy.slots[i] = { species = tostring(slot.species or "SPECIES_001"),
                        level = math.max(1, math.min(100,
                          math.floor(tonumber(slot.level) or 5))) }
    end
  end
  if type(tbl.buckets) == "table" then
    copy.buckets = {}
    for i, b in ipairs(tbl.buckets) do copy.buckets[i] = b end
  end
  m.wilds = m.wilds or {}
  m.wilds[terrain] = m.wilds[terrain] or {}
  m.wilds[terrain][time] = copy
  return true
end

function MapEdits.wildEditCount(store, game, mapId)
  local w = MapEdits.wilds(store, game, mapId)
  if not w then return 0 end
  local n = 0
  for _, byTime in pairs(w) do
    for _ in pairs(byTime) do n = n + 1 end
  end
  return n
end

-- Lay the overrides onto a live `encounters` table.
--
-- Not part of `applyToMap`: that one is handed a map DEF, and encounters are a
-- separate dataset keyed by the same map id. Passed the table so this file
-- stays ignorant of where Data keeps it.
function MapEdits.applyWilds(store, game, encounters)
  if type(encounters) ~= "table" then return 0 end
  local g = store and store.games and store.games[game]
  if not (g and g.maps) then return 0 end
  local applied = 0
  for mapId, m in pairs(g.maps) do
    if type(m.wilds) == "table" then
      local rec = encounters[mapId]
      if not rec then rec = {}; encounters[mapId] = rec end
      for terrain, byTime in pairs(m.wilds) do
        local into = rec[terrain]
        if not into then into = { rate = 0, slots = {} }; rec[terrain] = into end
        for time, tbl in pairs(byTime) do
          -- DAY IS THE RECORD ITSELF, not an entry under byTime: that is the
          -- shape Encounter.atTime reads -- it falls back to the record when
          -- the time key is missing -- and writing day into byTime instead
          -- would leave the plain roll untouched.
          local target = into
          if time ~= "day" then
            into.byTime = into.byTime or {}
            into.byTime[time] = into.byTime[time] or {}
            target = into.byTime[time]
          end
          target.rate = tbl.rate
          target.slots = tbl.slots
          if tbl.buckets then target.buckets = tbl.buckets end
          applied = applied + 1
        end
      end
    end
  end
  return applied
end

-- ---------------------------------------------------------------------------
-- the voxel profile's own knobs, per tileset
-- ---------------------------------------------------------------------------

-- A voxel profile carries two kinds of thing per tileset: the HEIGHT each
-- class stands at, and the OPTIONS that say how that class is built -- how far
-- a bin tapers, whether a bookcase's panes sink behind their frame, how tall a
-- detected column may rise. Both are authored content, and until now the only
-- way to change one was to open the mod's data file in a text editor.
--
-- Keyed by the voxel SOURCE as well as the tileset, because two installed mods
-- disagree about the same tileset on purpose -- that disagreement is what the
-- source selector exists for, and an edit made while looking at one mod's
-- world must not silently reshape the other's.
--
-- These are edits to how a tileset RENDERS, so they live in the tileset bucket
-- beside the minted blocks rather than under any one map: change the wall
-- height for TilesetJohto and every Johto route changes, which is the point.
-- ---------------------------------------------------------------------------
-- the same statement, about one map
-- ---------------------------------------------------------------------------

-- LOCALLY OR GLOBALLY, and the difference is the whole point.
--
-- "This drawing is a tree" is usually true everywhere the drawing appears --
-- that is what makes a tile pin worth having. But sometimes it is true only
-- here: the same six tiles are Ilex Forest's canopy and the Lake of Rage's
-- shoreline scrub, and a pin that fixed one broke the other. So the same
-- statement can be made about ONE MAP instead, and the two compose -- the
-- map's answer over the tileset's, most specific wins.
--
-- Stored on the map rather than in a second tileset table, because that is
-- what it is about, and because a map's edits already travel together: delete
-- the map's bucket and the local pins go with it, which is the behaviour
-- anybody would predict.
function MapEdits.mapTilePins(store, game, mapId)
  local m = bucket(store, game, mapId, false)
  return (m and m.classPins) or {}
end

function MapEdits.setMapTilePin(store, game, mapId, tile, class)
  tile = tonumber(tile)
  if not tile or tile < 0 then return false end
  if class ~= nil and (type(class) ~= "string" or class == "") then return false end
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  if class == nil then
    if m.classPins then
      m.classPins[math.floor(tile)] = nil
      if next(m.classPins) == nil then m.classPins = nil end
    end
    return true
  end
  m.classPins = m.classPins or {}
  m.classPins[math.floor(tile)] = class
  return true
end

-- The tileset's pins with this map's laid over them: one table, which is what
-- the shape resolver is handed and all it can read.
function MapEdits.effectiveTilePins(store, game, mapId, tilesetId)
  local out = {}
  for tile, cls in pairs(MapEdits.tilePins(store, game, tilesetId)) do
    out[tile] = cls
  end
  for tile, cls in pairs(MapEdits.mapTilePins(store, game, mapId)) do
    out[tile] = cls
  end
  return out
end

-- ---------------------------------------------------------------------------
-- named tileset profiles
-- ---------------------------------------------------------------------------

-- A PROFILE IS A NAMED BUNDLE OF THE SAME EDITS, SHARED BY THE TILESETS
-- ASSIGNED TO IT.
--
-- Everything above is keyed by tileset id, which is right until you have said
-- the same thing about four of them. Johto, the modern Johto set and the two
-- gate sets draw the same trees from the same six tiles, and pinning them as
-- cylinders was four identical pieces of work that then had to be kept in step
-- by hand -- and the fourth one is always the one that gets missed.
--
-- So a tileset can be ASSIGNED a profile, and while it is, its edits are
-- stored in that profile instead of in the tileset's own bucket. That is the
-- whole mechanism: one editing surface, and the assignment decides where the
-- writes land and who else sees them. Assign four tilesets to "Johto trees"
-- and a pin made while looking at any of them is a pin all four now have.
--
-- Unassigning leaves the profile alone and drops the tileset back to whatever
-- it had of its own -- which is deliberately NOT the same as deleting: a
-- profile is content, and content that vanishes when the last user stops using
-- it is content nobody can experiment with.
local function profileStore(store, game, create)
  store.games = store.games or {}
  local g = store.games[game]
  if not g then
    if not create then return nil end
    g = { maps = {} }
    store.games[game] = g
  end
  if not g.voxelProfiles then
    if not create then return nil end
    g.voxelProfiles = {}
  end
  return g.voxelProfiles
end

function MapEdits.listProfiles(store, game)
  local ps = profileStore(store, game, false)
  local out = {}
  for name in pairs(ps or {}) do out[#out + 1] = name end
  table.sort(out)
  return out
end

-- Which profile a tileset is assigned, or nil for "its own edits only".
function MapEdits.profileOf(store, game, tilesetId)
  local t = tilesetBucket(store, game, tilesetId, false)
  local name = t and t.profile
  if not name then return nil end
  -- An assignment naming a profile that no longer exists is a dangling one,
  -- and reporting it as live would show an empty profile's edits (none) as if
  -- they were the tileset's. Treated as unassigned; the row can be re-picked.
  local ps = profileStore(store, game, false)
  if not (ps and ps[name]) then return nil end
  return name
end

function MapEdits.createProfile(store, game, name, fromTilesetId)
  if type(name) ~= "string" or name:match("^%s*$") then return false, "name it" end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  local ps = profileStore(store, game, true)
  if ps[name] then return false, "there is already a profile called that" end
  local seed = { voxel = {}, pins = {} }
  -- SEEDED FROM THE TILESET IT WAS MADE ON, when there is one. Making a
  -- profile is almost always "what I have here, but shared" -- starting it
  -- empty would silently throw that away and look like the assignment having
  -- reverted everything.
  if fromTilesetId then
    local t = tilesetBucket(store, game, fromTilesetId, false)
    if t then
      for src, v in pairs(t.voxel or {}) do
        local copy = {}
        if v.heights then
          copy.heights = {}
          for k, hv in pairs(v.heights) do copy.heights[k] = hv end
        end
        if v.options then
          copy.options = {}
          for k, ov in pairs(v.options) do copy.options[k] = ov end
        end
        seed.voxel[src] = copy
      end
      for tile, cls in pairs(t.pins or {}) do seed.pins[tile] = cls end
    end
  end
  ps[name] = seed
  return true
end

function MapEdits.deleteProfile(store, game, name)
  local ps = profileStore(store, game, false)
  if not (ps and ps[name]) then return false end
  ps[name] = nil
  -- and every assignment to it, or those tilesets keep a dangling name that
  -- the picker would offer to re-select
  local g = store.games and store.games[game]
  for _, t in pairs((g and g.tilesets) or {}) do
    if t.profile == name then t.profile = nil end
  end
  return true
end

-- `name` nil unassigns.
function MapEdits.assignProfile(store, game, tilesetId, name)
  if name ~= nil then
    local ps = profileStore(store, game, false)
    if not (ps and ps[name]) then return false, "no such profile" end
  end
  local t = tilesetBucket(store, game, tilesetId, true)
  if not t then return false end
  t.profile = name
  return true
end

-- WHERE A TILESET'S EDITS ACTUALLY LIVE: its assigned profile, or itself.
--
-- One function, used by both bucket helpers below, so a read and a write can
-- never disagree about which of the two they are talking to -- which would
-- show an edit landing and then not being there.
local function editHome(store, game, tilesetId, create)
  local name = MapEdits.profileOf(store, game, tilesetId)
  if name then
    local ps = profileStore(store, game, create)
    local p = ps and ps[name]
    if p then
      p.voxel = p.voxel or {}
      p.pins = p.pins or {}
      return p
    end
  end
  return tilesetBucket(store, game, tilesetId, create)
end

MapEdits.editHome = editHome

local function voxelBucket(store, game, tilesetId, sourceId, create)
  local t = editHome(store, game, tilesetId, create)
  if not t then return nil end
  local key = tostring(sourceId or "builtin")
  if not t.voxel then
    if not create then return nil end
    t.voxel = {}
  end
  local v = t.voxel[key]
  if not v then
    if not create then return nil end
    v = {}
    t.voxel[key] = v
  end
  return v
end

MapEdits.voxelBucket = voxelBucket

-- `{ heights = {...}, options = {...} }` for a tileset, or an empty table.
-- Shaped to be handed straight to `VoxelClasses.setOverrides`.
function MapEdits.voxelOverrides(store, game, tilesetId, sourceId)
  local v = voxelBucket(store, game, tilesetId, sourceId, false)
  if not v then return {} end
  return { heights = v.heights, options = v.options }
end

-- WHICH CLASS A TILE ID IS, for a whole tileset.
--
-- This is the single biggest lever the profile has and the one the editor
-- could not reach: it is how a drawing gets to be a round tree canopy instead
-- of a box, a staircase instead of a slab, a shelf instead of a wall. The mod
-- states them by hand for the tilesets it has been through; everything it has
-- not is left to the automatic detector, and where the detector reads a
-- drawing wrong the only remedy was to edit the mod's data file.
--
-- KEYED BY TILESET AND NOT BY SOURCE, unlike the heights beside it. A pin says
-- what a DRAWING is -- "these six tiles are a tree" -- and the drawing does not
-- change when a different voxel mod is selected. A class HEIGHT is the mod's
-- own vocabulary and does change, which is why that one carries the source. A
-- pin naming a class the selected mod has never heard of simply does not
-- resolve, which is the same thing that happens to the profile's own pins.
local function pinBucket(store, game, tilesetId, create)
  local t = editHome(store, game, tilesetId, create)
  if not t then return nil end
  if not t.pins then
    if not create then return nil end
    t.pins = {}
  end
  return t.pins
end

function MapEdits.tilePins(store, game, tilesetId)
  return pinBucket(store, game, tilesetId, false) or {}
end

-- `class` nil REMOVES the pin -- back to whatever the mod says, which is not
-- the same as pinning it to the fallback.
function MapEdits.setTilePin(store, game, tilesetId, tile, class)
  tile = tonumber(tile)
  if not tile or tile < 0 then return false end
  if class ~= nil and (type(class) ~= "string" or class == "") then return false end
  local pins = pinBucket(store, game, tilesetId, true)
  if not pins then return false end
  pins[math.floor(tile)] = class
  return true
end

function MapEdits.clearTilePins(store, game, tilesetId)
  local t = editHome(store, game, tilesetId, false)
  if not (t and t.pins) then return 0 end
  local n = 0
  for _ in pairs(t.pins) do n = n + 1 end
  t.pins = nil
  return n
end

-- Set a class's height for one tileset. `nil` REMOVES the override rather than
-- writing a zero -- "back to what the mod says" and "flat on the floor" are
-- different answers and there has to be a way to say the first one.
function MapEdits.setClassHeight(store, game, tilesetId, sourceId, class, h)
  if type(class) ~= "string" or class == "" then return false end
  if h ~= nil and type(h) ~= "number" then return false end
  local v = voxelBucket(store, game, tilesetId, sourceId, true)
  if not v then return false end
  if h == nil then
    if v.heights then v.heights[class] = nil end
  else
    v.heights = v.heights or {}
    v.heights[class] = math.floor(h)
  end
  return true
end

-- Set one render option. Same nil-clears rule, and the same reason.
function MapEdits.setVoxelOption(store, game, tilesetId, sourceId, key, value)
  if type(key) ~= "string" or key == "" then return false end
  local kind = type(value)
  if value ~= nil and kind ~= "number" and kind ~= "boolean"
     and kind ~= "string" then
    return false
  end
  local v = voxelBucket(store, game, tilesetId, sourceId, true)
  if not v then return false end
  if value == nil then
    if v.options then v.options[key] = nil end
  else
    v.options = v.options or {}
    v.options[key] = value
  end
  return true
end

-- How many voxel-profile edits a tileset carries, so a panel can say so and a
-- RESET button knows whether it has anything to do.
function MapEdits.voxelEditCount(store, game, tilesetId, sourceId)
  local v = voxelBucket(store, game, tilesetId, sourceId, false)
  if not v then return 0 end
  local n = 0
  for _ in pairs(v.heights or {}) do n = n + 1 end
  for _ in pairs(v.options or {}) do n = n + 1 end
  return n
end

function MapEdits.clearVoxelEdits(store, game, tilesetId, sourceId)
  local v = voxelBucket(store, game, tilesetId, sourceId, false)
  if not v then return 0 end
  local n = MapEdits.voxelEditCount(store, game, tilesetId, sourceId)
  v.heights, v.options = nil, nil
  return n
end

-- ---------------------------------------------------------------------------
-- borrowing art from another tileset
-- ---------------------------------------------------------------------------

-- A BLOCK'S SIXTEEN NUMBERS ARE INDICES INTO ITS OWN ATLAS.
--
-- The thirty-eight tilesets a Gen 2 import carries have thirty-seven different
-- atlases between them, so copying a block's numbers into another tileset does
-- not copy the picture -- it draws whatever happens to sit at those indices
-- there, which is not similar art, it is noise. Bringing a drawing across
-- means copying the PIXELS: appending the source tiles to the destination
-- atlas and pointing the new block at where they landed.
--
-- STORED AS A RECIPE, NOT AS INDICES. The obvious version records the index
-- each borrowed tile was given -- and that index is only correct against the
-- atlas as it was at the moment of the borrow. Re-import, and the tileset has
-- a different number of tiles; borrow again, and the base has moved. So a
-- borrowed tile is stored as WHERE IT CAME FROM, and a minted block refers to
-- it by a negative slot number -- `-3` is "the third tile this tileset has
-- borrowed" -- which is resolved to a real index at apply time against
-- whatever the atlas is then. Negative because a real tile index never is, so
-- the two can share the same sixteen-number array with no flag beside it.
MapEdits.BORROW_SLOT = -1        -- documentation: slot k is stored as -k

local function borrowList(store, game, tilesetId, create)
  local t = tilesetBucket(store, game, tilesetId, create)
  if not t then return nil end
  if not t.borrowed then
    if not create then return nil end
    t.borrowed = {}
  end
  return t.borrowed
end

function MapEdits.borrowedTiles(store, game, tilesetId)
  return borrowList(store, game, tilesetId, false) or {}
end

-- The slot a (tileset, tile) pair occupies, borrowing it if it is new.
--
-- Deduped, and not as an optimisation: a block is sixteen tiles and a town's
-- worth of borrowed blocks would otherwise append the same grass tile a
-- hundred times, growing the atlas by a hundred rows of identical art that the
-- renderer then has to hold in memory.
local function borrowSlot(list, fromTileset, tile)
  for i, e in ipairs(list) do
    if e.from == fromTileset and e.tile == tile then return i end
  end
  list[#list + 1] = { from = fromTileset, tile = tile }
  return #list
end

-- Copy one block's art from another tileset, and mint a block that uses it.
-- Returns the mint key, or nil and a reason.
function MapEdits.borrowBlock(store, game, destTileset, srcTileset, srcBlockId,
                              tilesets)
  if destTileset == srcTileset then
    return nil, "that is this map's own tileset - paint it directly"
  end
  local src = tilesets and tilesets[srcTileset]
  local dst = tilesets and tilesets[destTileset]
  if not (src and type(src.blocks) == "table") then
    return nil, "the source tileset has no blocks"
  end
  if not (dst and type(dst.blocks) == "table") then
    return nil, "this map's tileset has no blocks"
  end
  local block = src.blocks[(srcBlockId or 0) + 1]
  if not block then
    return nil, "block " .. tostring(srcBlockId) .. " is not in " .. tostring(srcTileset)
  end

  local list = borrowList(store, game, destTileset, true)
  if not list then return nil, "could not open the tileset's edit bucket" end

  local tiles, coll = {}, {}
  for i = 1, 16 do
    tiles[i] = -borrowSlot(list, srcTileset, block[i] or 0)
  end
  -- The collision comes across too. A drawing borrowed without it is a wall
  -- you can walk through or a floor you cannot -- and the class is part of
  -- what the block IS, not decoration on top of it.
  for q = 1, 4 do
    coll[q] = (src.collision and src.collision[(srcBlockId or 0) * 4 + q]) or 0
  end
  return MapEdits.mintBlock(store, game, destTileset, tiles, coll)
end

-- How many 8px tiles a tileset's atlas holds right now.
-- ---------------------------------------------- borrowed tiles, applied
--
-- MOVED TO src/import/BorrowedTiles.lua, whole, and re-exported here so every
-- existing caller keeps working.
--
-- Not tidying: an exported map pack has to rebuild these on the RECEIVING
-- machine, out of that machine's own cartridge, and `tools/` is not in a
-- player build (scripts/pack_love.sh ships tools/save-editor and
-- tools/map-editor for the editor itself, but a mod may not depend on either).
-- Leaving the applier here meant a pack could carry the recipe and have
-- nothing able to follow it. Same argument, same destination, as
-- AdoptedTileset -- read that file's header.
local BorrowedTiles = require("src.import.BorrowedTiles")

MapEdits.tileCapacity = BorrowedTiles.tileCapacity
MapEdits.borrowLayout = BorrowedTiles.borrowLayout
MapEdits.resolveBorrowed = BorrowedTiles.resolveBorrowed
local tileCapacity = BorrowedTiles.tileCapacity


function MapEdits.applyTilesets(store, game, tilesets)
  local g = store and store.games and store.games[game]
  if not (g and g.tilesets and type(tilesets) == "table") then return {}, nil end
  return BorrowedTiles.apply(game, g.tilesets, tilesets)
end

-- WHAT AN EXPORT HAS TO CARRY for the receiving machine to rebuild these.
--
-- The store's bucket, minus anything that is only true here. `baseBlocks` is
-- the tileset's length BEFORE this session's mints, which is what the other
-- end checks its own against -- see BorrowedTiles.applyOne.
--
-- Recipes only: `borrowed` is { from = <tileset>, tile = n }, a reference to
-- the reader's own cartridge, and a minted block is sixteen tile indices --
-- the same class of thing a map's `blocks` array already is, and no pixels.
function MapEdits.tilesetRecipes(store, game, tilesets)
  local g = store and store.games and store.games[game]
  if not (g and g.tilesets) then return nil end
  local out, any = {}, false
  for tilesetId, t in pairs(g.tilesets) do
    local blocks, borrowed = {}, {}
    for i, minted in ipairs(t.blocks or {}) do
      local tiles = {}
      for k = 1, 16 do tiles[k] = (minted.tiles or {})[k] or 0 end
      local coll = {}
      for q = 1, 4 do coll[q] = (minted.coll or {})[q] or 0 end
      blocks[i] = { tiles = tiles, coll = coll }
    end
    for i, e in ipairs(t.borrowed or {}) do
      borrowed[i] = { from = e.from, tile = e.tile }
    end
    if blocks[1] or borrowed[1] then
      local ts = tilesets and tilesets[tilesetId]
      local base = nil
      if ts and type(ts.blocks) == "table" then
        base = #ts.blocks
        for _ in pairs(ts._mintedAt or {}) do base = base - 1 end
      end
      out[tilesetId] = { blocks = blocks, borrowed = borrowed,
                         baseBlocks = base }
      any = true
    end
  end
  return any and out or nil
end

-- A single BLOCK of the map grid, keyed "bx,by" -> block id.
--
-- This is the one edit that changes the ground itself rather than what stands
-- on it, and warps are why it has to exist. On Gen 2 `Map:warpAtCell` refuses
-- to return a warp whose cell is not an ENTRANCE collision class -- so a warp
-- dropped on plain floor is inert, silently, and no amount of editing the warp
-- record fixes it. Being able to lay the doorway block under it is what makes
-- "set a warp" mean anything.
--
-- Stored sparsely by coordinate rather than as a whole `blocks` array: a route
-- is 20x18 blocks and a rewritten array would bury a two-block change in 360
-- unchanged numbers, and would also go stale the moment a re-import changed
-- the map's size.
-- A voxel override on ONE 8px TILE rather than on the 16px cell.
--
-- TileShape.at is called per tile -- `at(map, tx, ty)` -- and only the CELL
-- override was read, so the finest thing the editor could shape was a 16x16
-- square: four tiles moving together. A cell is 2x2 tiles, so this is four
-- times the resolution through a consumer whose contract is already per tile.
--
-- NOT per pixel. The mesher carves per pixel, but the HEIGHT it carves to
-- comes from the shape this returns, and making that vary inside a tile is a
-- change to Structures' column builder rather than to the shape it reads.
-- Stopping at the tile is where the existing contract stops.
function MapEdits.setTileVoxel(store, game, mapId, tx, ty, patch)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.tiles = m.tiles or {}
  local key = string.format("%d,%d", math.floor(tx), math.floor(ty))
  if patch == nil then
    m.tiles[key] = nil
    if next(m.tiles) == nil then m.tiles = nil end
    return true
  end
  local clean, rejected = typedCopy(patch, MapEdits.VOXEL_FIELDS)
  if next(clean) == nil then m.tiles[key] = nil else m.tiles[key] = clean end
  return true, rejected
end

function MapEdits.setBlock(store, game, mapId, bx, by, blockId)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.blocks = m.blocks or {}
  local key = string.format("%d,%d", math.floor(bx), math.floor(by))
  if blockId == nil then
    m.blocks[key] = nil
  elseif MapEdits.isMintKey(blockId) then
    m.blocks[key] = blockId
  else
    m.blocks[key] = math.floor(blockId)
  end
  if next(m.blocks) == nil then m.blocks = nil end
  return true
end

-- A field of the MAP RECORD itself on a cartridge map -- borderBlock, name,
-- music, and the rest of MAP_FIELDS.
--
-- createMap already carries these for maps the editor invents; this is the
-- same fields for maps that came out of the ROM, and borderBlock is why it
-- exists. The border block is what fills every cell outside the map's
-- rectangle, so "make this the border" is a one-value edit with a visible
-- effect on every edge of the map at once -- and there was nowhere to put it.
--
-- `blocks` is refused here even though MAP_FIELDS names it: a whole-array
-- patch on a cartridge map would go stale the moment a re-import changed the
-- map's size, and setBlock already stores the sparse per-coordinate form that
-- does not.
function MapEdits.setMapField(store, game, mapId, key, value)
  if key == "blocks" then return false, { "blocks" } end
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.map = m.map or {}
  local clean, rejected = typedCopy({ [key] = value }, MapEdits.MAP_FIELDS)
  if next(clean) == nil then return false, rejected end
  for k, v in pairs(clean) do m.map[k] = v end
  return true, rejected
end

function MapEdits.addWarp(store, game, mapId, warp)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  local clean, rejected = typedCopy(warp, MapEdits.WARP_FIELDS)
  m.addedWarps = m.addedWarps or {}
  m.addedWarps[#m.addedWarps + 1] = clean
  return #m.addedWarps, rejected
end

function MapEdits.removeWarp(store, game, mapId, index, removed)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.removedWarps = m.removedWarps or {}
  m.removedWarps[index] = removed ~= false or nil
  return true
end

-- ---------------------------------------------------------------------------
-- whole new maps
-- ---------------------------------------------------------------------------

-- Ids are prefixed so a new map can never collide with a cartridge one, and so
-- anything reading data.maps can tell at a glance where a map came from.
MapEdits.NEW_MAP_PREFIX = "EDIT_MAP_"

function MapEdits.newMapId(store, game, name)
  local g = store and store.games and store.games[game]
  local maps = (g and g.newMaps) or {}
  local slug = tostring(name or ""):upper():gsub("[^A-Z0-9]+", "_")
  slug = slug:gsub("^_+", ""):gsub("_+$", "")
  if slug ~= "" and not maps[MapEdits.NEW_MAP_PREFIX .. slug] then
    return MapEdits.NEW_MAP_PREFIX .. slug
  end
  local n = 1
  while maps[string.format("%s%03d", MapEdits.NEW_MAP_PREFIX, n)] do n = n + 1 end
  return string.format("%s%03d", MapEdits.NEW_MAP_PREFIX, n)
end

-- `blocks` is filled rather than left sparse: Map.lua indexes it directly and a
-- nil in the middle of a map is a hole the renderer has no answer for.
-- ---------------------------------------------------------------------------
-- imported character sheets
-- ---------------------------------------------------------------------------
--
-- WHY THESE LIVE IN THE EDIT STORE AND NOT IN A MOD FOLDER.
--
-- A mod can already register a sprite (`mod.content.sprites:register`) and the
-- merge puts it straight into `data.sprites`, which is where the editor's
-- picker and `NPC.resolveSpriteDef` both read. That is the shipping format and
-- the export writes exactly it. But a sheet has to be usable the moment it is
-- imported -- picked in the NPC editor, seen on the map, seen in 3D -- and
-- writing a mod, installing it and restarting to find out the frame count was
-- wrong is not an editing loop. So the store holds it, the editor applies it
-- live, and EXPORT turns it into the mod a player installs.
--
-- The PIXELS are not in the store. The store is a Lua source file and a PNG in
-- it would be a base64 blob nobody can read or diff; the image is written
-- beside the extended atlases in `editor/sprites/`, and the store keeps the
-- path -- the same split `extendAtlas` already makes.
MapEdits.SPRITE_PREFIX = "SPRITE_EDIT_"

local function spriteBucket(store, game, create)
  if type(store) ~= "table" or not game then return nil end
  if create then
    store.games = store.games or {}
    store.games[game] = store.games[game] or { maps = {} }
    store.games[game].sprites = store.games[game].sprites or {}
  end
  local g = store.games and store.games[game]
  return g and g.sprites or nil
end

-- A free id, from the name the reader gave the sheet. Slugged the same way a
-- new map's is, and prefixed, so a sheet can never collide with a cartridge
-- SPRITE_* -- `register` on an existing id is a hard error in the mod loader,
-- and finding that out at install time rather than at import time would be the
-- worst possible moment.
function MapEdits.newSpriteId(store, game, name, existing)
  local slug = tostring(name or ""):upper():gsub("[^%w]+", "_"):gsub("^_+", "")
                                          :gsub("_+$", "")
  local taken = spriteBucket(store, game, false) or {}
  local function free(id)
    return taken[id] == nil and not (existing and existing[id])
  end
  if slug ~= "" then
    local id = MapEdits.SPRITE_PREFIX .. slug
    if free(id) then return id end
    for n = 2, 99 do
      local alt = string.format("%s%s_%d", MapEdits.SPRITE_PREFIX, slug, n)
      if free(alt) then return alt end
    end
  end
  for n = 1, 999 do
    local id = string.format("%s%03d", MapEdits.SPRITE_PREFIX, n)
    if free(id) then return id end
  end
  return nil
end

function MapEdits.setSprite(store, game, id, spec)
  local s = spriteBucket(store, game, spec ~= nil)
  if not s then return false end
  if spec == nil then
    s[id] = nil
    return true
  end
  local clean, rejected = typedCopy(spec, MapEdits.SPRITE_FIELDS)
  if not clean.image then return false, "a sprite needs an image path" end
  clean.frames = math.max(1, math.floor(clean.frames or 1))
  s[id] = clean
  return true, rejected
end

function MapEdits.sprites(store, game)
  return spriteBucket(store, game, false) or {}
end

function MapEdits.deleteSprite(store, game, id)
  return MapEdits.setSprite(store, game, id, nil)
end

-- Lay the imported sheets onto `data.sprites`.
--
-- Copied rather than assigned by reference: SpriteRenderer caches per record
-- and the editor hands the same table to the preview, so a shared table means
-- an edit to `frames` reaches a renderer that has already sliced its quads.
-- The copy is three fields deep and costs nothing.
--
-- An id that already exists is SKIPPED, not overwritten -- the prefix makes
-- that near-impossible, and if it ever happens the cartridge sheet is the one
-- the maps refer to.
function MapEdits.applySprites(store, game, sprites)
  if type(sprites) ~= "table" then return 0, nil end
  local s = spriteBucket(store, game, false)
  if not s then return 0, nil end
  local n, stale = 0, nil
  for id, spec in pairs(s) do
    if sprites[id] ~= nil and not (sprites[id] or {}).editorImported then
      stale = stale or {}
      stale[#stale + 1] = id .. ": a cartridge sheet already uses this id"
    else
      local def = { id = id, editorImported = true }
      for k, v in pairs(spec) do def[k] = v end
      sprites[id] = def
      n = n + 1
    end
  end
  return n, stale
end

-- ---------------------------------------------------------------------------
-- events, and the flags they turn on
-- ---------------------------------------------------------------------------
--
-- AN EVENT IS STORED AS ITS PARTS, NOT AS ITS SCRIPT. The rows are DERIVED --
-- `MapEvents.lower` builds them from the beats every time they are needed --
-- and storing the derivation instead would mean an event that can be run and
-- not edited: open it again and all you have is nine rows of `jump_if_false`
-- with no way back to "a guard stops you until you have the badge". The rows
-- are cheap to rebuild and the intent is impossible to recover.
--
-- WHICH ALSO MEANS THE LOWERING CAN IMPROVE. A bug in how a beat becomes rows
-- is fixed for every event ever made the moment it is fixed once, because no
-- event carries a copy of the old answer.
local function eventBucket(store, game, mapId, create)
  local m = bucket(store, game, mapId, create)
  if not m then return nil end
  if not m.events then
    if not create then return nil end
    m.events = {}
  end
  return m.events
end

-- Sorted by id so the list does not reshuffle between frames -- `pairs` order
-- is not stable and a list that reorders itself is a list nobody can point at.
function MapEdits.events(store, game, mapId)
  local b = eventBucket(store, game, mapId, false)
  if not b then return {} end
  local ids = {}
  for id in pairs(b) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for i, id in ipairs(ids) do out[i] = b[id] end
  return out
end

function MapEdits.setEvent(store, game, mapId, id, ev)
  local b = eventBucket(store, game, mapId, ev ~= nil)
  if not b then return false end
  if ev == nil then
    b[id] = nil
    if next(b) == nil then
      local m = bucket(store, game, mapId, false)
      if m then m.events = nil end
    end
    return true
  end
  b[id] = ev
  return true
end

-- Ids are per map and never reused: another event's condition may name this
-- one, and a recycled id would silently point the condition at whatever took
-- the slot.
function MapEdits.newEventId(store, game, mapId)
  local b = eventBucket(store, game, mapId, true) or {}
  local n = 1
  while b[string.format("EV_%03d", n)] do n = n + 1 end
  return string.format("EV_%03d", n)
end

-- THE FLAG REGISTRY. `Flags.set(save, name)` takes any string and `save.flags`
-- is a plain table, so a flag needs nothing from the engine to exist -- it
-- exists the moment something sets it. This list is not the flags; it is the
-- NAMES this project has invented, so the event that opens the door can pick
-- the flag from a list rather than the author retyping it. A misspelled flag
-- is the worst failure this system has: both halves work perfectly and the
-- door simply never opens.
local function flagBucket(store, game, create)
  if type(store) ~= "table" or not game then return nil end
  if create then
    store.games = store.games or {}
    store.games[game] = store.games[game] or { maps = {} }
    store.games[game].flags = store.games[game].flags or {}
  end
  local g = store.games and store.games[game]
  return g and g.flags or nil
end

function MapEdits.flags(store, game)
  local b = flagBucket(store, game, false)
  if not b then return {} end
  local out = {}
  for i, name in ipairs(b) do out[i] = name end
  return out
end

function MapEdits.addFlag(store, game, name)
  if type(name) ~= "string" or name == "" then return false, "no name" end
  local b = flagBucket(store, game, true)
  if not b then return false, "could not open the flag list" end
  for _, existing in ipairs(b) do
    if existing == name then return false, name .. " already exists" end
  end
  b[#b + 1] = name
  return true
end

function MapEdits.removeFlag(store, game, name)
  local b = flagBucket(store, game, false)
  if not b then return false end
  for i, existing in ipairs(b) do
    if existing == name then
      table.remove(b, i)
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- the tilesets a map paints from
-- ---------------------------------------------------------------------------
--
-- A MAP DEF HAS EXACTLY ONE `tileset`, AND THAT IS NOT NEGOTIABLE. The block
-- array is a list of indices into that one tileset's block table, the
-- collision reader takes its classes from the same record, and the renderer
-- bakes one atlas per map. There is nowhere in the format -- or in this
-- engine's world pipeline -- to put a second one.
--
-- SO "USING TWO TILESETS" MEANS SOMETHING SLIGHTLY DIFFERENT, and it is worth
-- being exact about what, because the alternative is a reader who thinks the
-- map now carries two tilesets and is surprised by every consequence of it
-- not doing so. The map's own tileset ABSORBS art from the others: each block
-- painted from another tileset has its sixteen tile graphics copied into this
-- one's atlas and a block minted to point at them (`borrowBlock`). The result
-- is one tileset, as the format requires, containing art from several.
--
-- WHAT THIS LIST IS, THEN. Not a second tileset on the map -- a record of
-- which tilesets the reader has said this map may draw from. It exists so the
-- editor knows when NOT to ask: the first block from a new tileset is a
-- decision (it grows this map's atlas, permanently, and every map sharing that
-- tileset carries the growth), and the two hundredth is not a decision at all,
-- it is the middle of laying a floor.
--
-- THE MAP'S OWN TILESET IS NEVER IN HERE. It is on the def, it cannot be
-- removed, and listing it would mean two places to keep in step.
local function paletteList(store, game, mapId, create)
  local m = bucket(store, game, mapId, create)
  if not m then return nil end
  if not m.tilesets then
    if not create then return nil end
    m.tilesets = {}
  end
  return m.tilesets
end

-- Every extra tileset this map paints from, in the order they were added.
--
-- ORDER OF ADDITION, not sorted: it is the order the reader built the map in,
-- and a list that reshuffles itself when a name happens to sort earlier is a
-- list nobody can point at.
function MapEdits.mapTilesets(store, game, mapId)
  local list = paletteList(store, game, mapId, false)
  if not list then return {} end
  local out = {}
  for i, id in ipairs(list) do out[i] = id end
  return out
end

-- Is `tilesetId` one this map can paint from without asking?
--
-- `ownId` is the map's own tileset and is always yes. Passed in rather than
-- looked up because this module never sees `data.maps` -- it is the store's
-- side of the editor and the def is the caller's business.
function MapEdits.mapUsesTileset(store, game, mapId, tilesetId, ownId)
  if tilesetId == nil then return false end
  if ownId ~= nil and tilesetId == ownId then return true end
  for _, id in ipairs(MapEdits.mapTilesets(store, game, mapId)) do
    if id == tilesetId then return true end
  end
  return false
end

-- Add one. Returns true if it went in, false plus a reason otherwise.
--
-- ADDING THE MAP'S OWN IS A NO-OP AND SAYS SO rather than being an error: the
-- caller is usually a prompt that fired on a stale comparison, and refusing
-- loudly there would put an error box in front of somebody who did nothing
-- wrong.
function MapEdits.addMapTileset(store, game, mapId, tilesetId, ownId)
  if type(tilesetId) ~= "string" or tilesetId == "" then
    return false, "no tileset named"
  end
  if ownId ~= nil and tilesetId == ownId then
    return false, tilesetId .. " is already this map's own tileset"
  end
  local list = paletteList(store, game, mapId, true)
  if not list then return false, "could not open this map's edit bucket" end
  for _, id in ipairs(list) do
    if id == tilesetId then return false, tilesetId .. " is already on this map" end
  end
  list[#list + 1] = tilesetId
  return true
end

-- Take one off the list.
--
-- WHAT THIS DOES NOT DO: unpick the art. Blocks already borrowed stay borrowed
-- and the map keeps drawing exactly as it did -- they are minted blocks in
-- this map's own tileset now and several maps may be pointing at them.
-- Removing is "stop offering me this one", not "undo what I painted", and the
-- caller should say so. Undoing a paint is what undo is for.
function MapEdits.removeMapTileset(store, game, mapId, tilesetId)
  local list = paletteList(store, game, mapId, false)
  if not list then return false end
  for i, id in ipairs(list) do
    if id == tilesetId then
      table.remove(list, i)
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- borrowing, resolved to something paintable
-- ---------------------------------------------------------------------------

-- `borrowBlock` mints, and a mint is a KEY -- a string, resolved to a real
-- block id only once `applyTilesets` has appended it and extended the atlas.
-- Every caller that wants to PAINT with the result therefore has to do the
-- same three steps in the same order, and both callers that existed had their
-- own copy of them.
--
-- Returns the live block id and the mint key, or nil and a reason. The id is a
-- number the renderer can index a block array with, which is the only form
-- `paintCell` and `paint` accept.
function MapEdits.borrowLive(store, game, destTileset, srcTileset, srcBlockId,
                             tilesets)
  local key, why = MapEdits.borrowBlock(store, game, destTileset, srcTileset,
                                        srcBlockId, tilesets)
  if not key then return nil, why end
  local ids, stale = MapEdits.applyTilesets(store, game, tilesets)
  local live = ids and ids[key]
  if live == nil then
    -- THE HONEST FAILURE, AND THE REAL REASON. The borrow is recorded and
    -- will resolve on the next load; what could not happen is the atlas
    -- extension, which needs love.image and a writable save folder.
    --
    -- The reason comes from `applyTilesets` rather than being guessed at
    -- here: "the atlas could not be extended" is four different problems
    -- wearing one sentence, and the reader can only act on the one they
    -- actually have.
    for _, why in ipairs(stale or {}) do
      if tostring(why):find(destTileset, 1, true) then
        return nil, tostring(why)
      end
    end
    return nil, "the copied art could not be given a block id - the tileset "
      .. "atlas could not be extended"
  end
  return live, key
end

-- ---------------------------------------------------------------------------
-- tilesets adopted from another imported game
-- ---------------------------------------------------------------------------
--
-- A map copied out of Gold names `TilesetJohto`, and a Crystal build has one of
-- those, so the block ids line up and nothing has to move. A map copied out of
-- RED names `Tileset_Overworld`, which a Gen 2 build has never heard of -- and
-- a block id against a tileset that is not there is not a degraded map, it is
-- no map at all.
--
-- So the tileset comes WITH it. The record is copied out of the other game's
-- `tilesets.lua` and registered here under a namespaced id (`TilesetX@gold`),
-- which is the whole trick: a name that cannot collide with a local tileset,
-- so adopting one never changes how an existing map draws.
--
-- THE ART STAYS WHERE IT IS. Its `image` is rewritten to the other version's
-- cache prefix -- `gold/assets/generated/tilesets/x.png` -- which
-- `love.filesystem` can already see, because every version's cache is a folder
-- beside this one's. Copying the PNG would be a second copy to keep in step
-- with a re-import; a path is not.
MapEdits.TILESET_SUFFIX = "@"

local function importedBucket(store, game, create)
  if type(store) ~= "table" or not game then return nil end
  if create then
    store.games = store.games or {}
    store.games[game] = store.games[game] or { maps = {} }
    store.games[game].adoptedTilesets =
      store.games[game].adoptedTilesets or {}
  end
  local g = store.games and store.games[game]
  return g and g.adoptedTilesets or nil
end

function MapEdits.adoptedTilesets(store, game)
  return importedBucket(store, game, false) or {}
end

-- Record one. `spec` is the other game's tileset table, already rewritten.
function MapEdits.setAdoptedTileset(store, game, id, spec)
  local b = importedBucket(store, game, spec ~= nil)
  if not b then return false end
  if spec == nil then
    b[id] = nil
    return true
  end
  if type(spec) ~= "table" or type(spec.blocks) ~= "table" then
    return false, "that is not a tileset record"
  end
  b[id] = spec
  return true
end

-- Lay them onto `data.tilesets`.
--
-- SKIPPED rather than overwritten when the id is already taken: the namespaced
-- suffix makes that near-impossible, and if it ever happens the local tileset
-- is the one every existing map is drawn against.
function MapEdits.applyAdoptedTilesets(store, game, tilesets)
  if type(tilesets) ~= "table" then return 0, nil end
  local b = importedBucket(store, game, false)
  if not b then return 0, nil end
  local n, stale = 0, nil
  for id, spec in pairs(b) do
    if tilesets[id] ~= nil and not (tilesets[id] or {}).adopted then
      stale = stale or {}
      stale[#stale + 1] = id .. ": a tileset of this name is already here"
    else
      local copy = { id = id, adopted = true }
      for k, v in pairs(spec) do copy[k] = v end
      -- BACK-FILL WHAT AN OLDER ADOPTION DID NOT CARRY.
      --
      -- `tilePairs` is the case: a Gen 1 set's elevation edges -- the pairs of
      -- individually-walkable tiles that may not be crossed, which is the only
      -- thing making a Cerulean Cave ledge a ledge. Sets adopted before those
      -- travelled have none, and the alternative to topping them up here is
      -- re-importing the map, which throws away every edit made since.
      --
      -- Read, not stored: this runs on the GAME's boot as well as the
      -- editor's, and the game has no business rewriting the editor's file.
      if copy.tilePairs == nil and copy.adoptedFrom and copy.adoptedName then
        local okA, AT = pcall(require, "src.import.AdoptedTileset")
        if okA and type(AT) == "table" and type(AT.tilePairs) == "function" then
          local okP, pairs_ = pcall(AT.tilePairs, copy.adoptedFrom,
                                    copy.adoptedName)
          if okP and type(pairs_) == "table" then copy.tilePairs = pairs_ end
        end
      end
      tilesets[id] = copy
      n = n + 1
    end
  end
  return n, stale
end

function MapEdits.createMap(store, game, spec)
  if type(store) ~= "table" or not game then return nil end
  store.games = store.games or {}
  store.games[game] = store.games[game] or { maps = {} }
  local g = store.games[game]
  g.newMaps = g.newMaps or {}

  local clean = typedCopy(spec or {}, MapEdits.MAP_FIELDS)
  clean.width = math.max(1, math.floor(clean.width or 10))
  clean.height = math.max(1, math.floor(clean.height or 9))
  clean.tileset = clean.tileset or "OVERWORLD"
  clean.borderBlock = clean.borderBlock or 0
  clean.name = clean.name or "New map"
  if type(clean.blocks) ~= "table" or #clean.blocks ~= clean.width * clean.height then
    local fill = clean.borderBlock
    clean.blocks = {}
    for i = 1, clean.width * clean.height do clean.blocks[i] = fill end
  end

  local id = MapEdits.newMapId(store, game, clean.name)
  g.newMaps[id] = clean
  return id, clean
end

function MapEdits.deleteMap(store, game, mapId)
  local g = store and store.games and store.games[game]
  if not (g and g.newMaps) then return false end
  if g.newMaps[mapId] == nil then return false end
  g.newMaps[mapId] = nil
  if g.maps then g.maps[mapId] = nil end
  return true
end

-- The local id of the map imported from (`originGame`, `originMap`), if one
-- has been. This is the lookup that lets a door copied out of another
-- cartridge find its other end here.
--
-- BOTH HALVES MATTER. `CERULEAN_CAVE_2F` in Red and `CERULEAN_CAVE_2F` in Blue
-- are the same place; in a romhack that renamed its maps they are not, and
-- linking across on the id alone would send a door somewhere nobody asked for.
function MapEdits.mapByOrigin(store, game, originGame, originMap)
  if not (originGame and originMap) then return nil end
  local g = store and store.games and store.games[game]
  for id, spec in pairs((g and g.newMaps) or {}) do
    if spec.originGame == originGame and spec.originMap == originMap then
      return id, spec
    end
  end
  return nil
end

-- Every cartridge this game's edits DEPEND ON, sorted, or nil for none.
--
-- WHY THIS IS DERIVED AND NOT DECLARED. A requirement nobody typed is a
-- requirement nobody forgets: it is already written down twice -- a map copied
-- out of Blue carries `originGame`, and the tileset that came with it carries
-- `adoptedFrom` -- and reading it back is exact, where asking the author to
-- remember is not. Someone who imports one cave in March and exports in June
-- will not remember, and the person who installs the result is the one who
-- pays for it.
--
-- BOTH SOURCES MATTER, and neither implies the other. A map imported from Blue
-- whose tileset happened to exist locally adopts nothing; a tileset adopted for
-- one map is used by every later map drawn against it. Either one alone still
-- means the recipient needs that cartridge.
function MapEdits.sourceGames(store, game)
  local g = store and store.games and store.games[game]
  if not g then return nil end
  local seen, out = {}, {}
  local function add(version)
    if type(version) ~= "string" or version == "" then return end
    if seen[version] then return end
    seen[version] = true
    out[#out + 1] = version
  end
  for _, spec in pairs(g.newMaps or {}) do add(spec.originGame) end
  for _, spec in pairs(g.adoptedTilesets or {}) do add(spec.adoptedFrom) end
  if #out == 0 then return nil end
  table.sort(out)
  return out
end

function MapEdits.newMaps(store, game)
  local g = store and store.games and store.games[game]
  return (g and g.newMaps) or {}
end

function MapEdits.addObject(store, game, mapId, object)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  local clean, rejected = typedCopy(object, MapEdits.OBJECT_FIELDS)
  m.added = m.added or {}
  m.added[#m.added + 1] = clean
  return #m.added, rejected
end

function MapEdits.removeObject(store, game, mapId, index, removed)
  local m = bucket(store, game, mapId, true)
  if not m then return false end
  m.removed = m.removed or {}
  m.removed[index] = removed ~= false or nil
  return true
end

-- ---------------------------------------------------------------------------
-- applying them
-- ---------------------------------------------------------------------------

-- Patch one map definition in place. Returns the number of edits applied and a
-- list of STALE ones -- edits whose target no longer exists because the map
-- changed under them. Callers should surface that list: an edit the player
-- made and can no longer see is exactly the thing this store exists to avoid.
function MapEdits.applyToMap(store, game, mapId, def, mintIds)
  local m = bucket(store, game, mapId, false)
  if not (m and type(def) == "table") then return 0, nil end
  local applied, stale = 0, nil
  local function drop(what) stale = stale or {}; stale[#stale + 1] = what end

  def.objects = def.objects or {}

  -- index -> the record carrying it, so a patch survives reordering
  local byIndex = {}
  for _, obj in ipairs(def.objects) do
    if obj.index then byIndex[obj.index] = obj end
  end

  for index, patch in pairs(m.objects or {}) do
    local obj = byIndex[index]
    if obj then
      for k, v in pairs(patch) do obj[k] = v end
      obj.edited = true
      applied = applied + 1
    else
      drop(string.format("object %s no longer exists", tostring(index)))
    end
  end

  -- Removals AFTER patches: patching something that is about to be removed is
  -- harmless, and doing it in this order means an index appearing in both does
  -- not depend on pairs() order.
  if next(m.removed or {}) ~= nil then
    local kept = {}
    for _, obj in ipairs(def.objects) do
      if not (obj.index and m.removed[obj.index]) then
        kept[#kept + 1] = obj
      else
        applied = applied + 1
      end
    end
    def.objects = kept
  end

  -- Added objects take indices ABOVE every cartridge one, so the editor can
  -- never hand out an index the next import will also use.
  local maxIndex = 0
  for _, obj in ipairs(def.objects) do
    if type(obj.index) == "number" and obj.index > maxIndex then
      maxIndex = obj.index
    end
  end
  -- APPLY MUST BE RE-RUNNABLE, and appending made it exactly once-runnable.
  --
  -- `Data:load` calls this once, so the bug never showed there. The EDITOR
  -- calls it every time it lands an import, reconnects a door or resolves a
  -- borrowed block -- and each of those laid every added object and every
  -- added warp onto the live def AGAIN. Three imports in a session and a map
  -- had three copies of every NPC it had gained, stacked on the same tile,
  -- and three copies of every door.
  --
  -- The slot is the identity: `editorSlot` is this record's position in the
  -- store's own list and does not move. Finding it means this is a re-apply
  -- and the record is UPDATED where it stands, which also keeps the index and
  -- the id it was given the first time -- both of which other maps' warps and
  -- the editor's own patches point at.
  local slotObj = {}
  for _, obj in ipairs(def.objects) do
    if obj.added and type(obj.editorSlot) == "number" then
      slotObj[obj.editorSlot] = obj
    end
  end
  for i, object in ipairs(m.added or {}) do
    local existing = slotObj[i]
    local copy = existing or {}
    if existing then
      -- Cleared first: a field the reader removed from the store has to
      -- disappear from the def too, and merging over the top would leave it.
      for k in pairs(copy) do
        if k ~= "index" and k ~= "id" then copy[k] = nil end
      end
    end
    for k, v in pairs(object) do copy[k] = v end
    copy.index = existing and existing.index or (maxIndex + i)
    copy.id = string.format("%s_EDIT_%03d", mapId, i)
    copy.name = copy.name or copy.id
    copy.source = "MAP_EDITOR"
    copy.added = true
    -- THE SLOT THE EDITOR WRITES BACK THROUGH. `added` alone says "the editor
    -- made this"; it does not say WHICH entry of `m.added` to patch when the
    -- player edits it again. Objects.lua sets this when it creates an object
    -- and so a first session works -- but on the next load the object comes
    -- back through here instead, and without this line every re-edit of an
    -- added NPC would write to the live table, find `m.added[nil]`, and be
    -- silently dropped on save.
    copy.editorSlot = i
    copy.sprite = copy.sprite or "SPRITE_GRAMPS"
    copy.x = copy.x or 0
    copy.y = copy.y or 0
    copy.movement = copy.movement or "STAY"
    copy.range = copy.range or "DOWN"
    if not existing then def.objects[#def.objects + 1] = copy end
    applied = applied + 1
  end

  -- MAP FIELDS first of all: borderBlock decides what fills every cell outside
  -- the rectangle, so a block edit or a warp check reading the map back has to
  -- see the new one, not the cartridge's.
  for k, v in pairs(m.map or {}) do
    if k ~= "blocks" then
      def[k] = v
      applied = applied + 1
    end
  end

  -- BLOCKS, before anything that reads the ground back. `def.blocks` is
  -- a flat array indexed by/width, and an out-of-range coordinate is dropped
  -- rather than appended: writing past the end would grow the array and leave
  -- a hole between the old end and the new entry, which the renderer reads as
  -- a nil block id.
  if next(m.blocks or {}) ~= nil and def.blocks and def.width and def.height then
    for key, id in pairs(m.blocks) do
      local bx, by = key:match("^(-?%d+),(-?%d+)$")
      bx, by = tonumber(bx), tonumber(by)
      -- A minted block is stored as a KEY and only becomes a number once
      -- applyTilesets has appended it. Unresolved means the tileset it was
      -- minted for is not in this import -- dropped rather than written,
      -- because writing the key itself would put a STRING where the renderer
      -- indexes a block array with a number.
      local resolved = id
      if MapEdits.isMintKey(id) then
        resolved = mintIds and mintIds[id]
        if resolved == nil then
          drop(string.format("block %s: its minted tile is not in this import",
                             tostring(key)))
        end
      end
      if resolved == nil then
        -- already reported
      elseif bx and by and bx >= 0 and by >= 0
             and bx < def.width and by < def.height then
        def.blocks[by * def.width + bx + 1] = resolved
        applied = applied + 1
      else
        drop(string.format("block %s is outside this map", tostring(key)))
      end
    end
  end

  -- WARPS, patched by index and then extended, exactly like objects. Kept in
  -- the same order the cartridge had them because `destWarp` on OTHER maps
  -- points INTO this list by position -- reordering it would silently redirect
  -- every door that arrives here.
  if next(m.warps or {}) ~= nil or next(m.removedWarps or {}) ~= nil
     or #(m.addedWarps or {}) > 0 then
    def.warps = def.warps or {}
    for index, patch in pairs(m.warps or {}) do
      local warp = def.warps[index]
      if warp then
        for k, v in pairs(patch) do warp[k] = v end
        applied = applied + 1
      else
        drop(string.format("warp %s no longer exists", tostring(index)))
      end
    end
    -- Removals blank the SLOT rather than compacting the list, for the reason
    -- above: another map's destWarp is an index into this list. A removed warp
    -- becomes inert (no destination) and every later warp keeps its number.
    for index in pairs(m.removedWarps or {}) do
      if def.warps[index] then
        def.warps[index] = { x = -1, y = -1, destMap = nil, destWarp = 1,
                             removed = true }
        applied = applied + 1
      end
    end
    -- THE SAME RE-RUN RULE AS ADDED OBJECTS ABOVE, and it matters more here:
    -- another map's `destWarp` is an INDEX into this list, so a re-apply that
    -- appended a second copy of every door did not merely duplicate them, it
    -- moved the numbers every arriving warp was counting on.
    local slotWarp = {}
    for _, wp in ipairs(def.warps) do
      if wp.added and type(wp.editorSlot) == "number" then
        slotWarp[wp.editorSlot] = wp
      end
    end
    for i, warp in ipairs(m.addedWarps or {}) do
      local existing = slotWarp[i]
      local copy = existing or {}
      if existing then
        for k in pairs(copy) do copy[k] = nil end
      end
      for k, v in pairs(warp) do copy[k] = v end
      copy.x = copy.x or 0
      copy.y = copy.y or 0
      copy.destWarp = copy.destWarp or 1
      copy.added = true
      copy.editorSlot = i
      if not existing then def.warps[#def.warps + 1] = copy end
      applied = applied + 1
    end
  end

  -- THE EVENTS, LOWERED, onto the def where the STEP HANDLER reads them.
  --
  -- Lowered here rather than stored lowered (see the note on the event bucket)
  -- and laid on at apply time rather than only when the editor publishes them,
  -- so a map loaded by the GAME -- with no editor open at all -- carries its
  -- events like any other map data.
  if next(m.events or {}) ~= nil then
    local okE, MapEvents = pcall(require, "tools.map-editor.MapEvents")
    if okE and type(MapEvents) == "table" and MapEvents.lower then
      local steps = {}
      for _, ev in pairs(m.events) do
        if ev.trigger == "talk" and ev.object then
          for _, obj in ipairs(def.objects or {}) do
            if obj.index == ev.object then
              obj.script = MapEvents.lower(ev, mapId)
              applied = applied + 1
            end
          end
        elseif ev.x and ev.y then
          steps[#steps + 1] = { x = ev.x, y = ev.y, id = ev.id,
                                name = ev.name,
                                script = MapEvents.lower(ev, mapId) }
          applied = applied + 1
        end
      end
      -- SORTED, because `pairs` is not ordered and two events on the same cell
      -- would otherwise fire in whichever order the table happened to hand
      -- them over -- different on the next load, for no reason anyone could
      -- see.
      table.sort(steps, function(p1, p2)
        return tostring(p1.id) < tostring(p2.id)
      end)
      def.events = (#steps > 0) and steps or nil
    end
  end

  -- THE MAP'S EXTRA TILESETS, onto the def where the editor reads them back.
  --
  -- Nothing in the GAME reads this: the art was copied into the map's own
  -- tileset when it was painted and the map draws from that one record like
  -- every other map. It is here so the editor, on the next load, still knows
  -- which tilesets this map was being built from and does not ask again about
  -- every one of them.
  if #(m.tilesets or {}) > 0 then
    local list = {}
    for i, id in ipairs(m.tilesets) do list[i] = id end
    def.extraTilesets = list
    applied = applied + 1
  end

  -- Voxel edits ride on the def for the renderer to read; nothing in the flat
  -- 2D game looks at them, so a game without the voxel mod is unaffected.
  if next(m.voxels or {}) ~= nil then
    def.voxelEdits = m.voxels
    applied = applied + 1
  end
  -- Per-TILE overrides ride on their own field. Kept apart from voxelEdits
  -- rather than merged into it because the keys mean different things -- one
  -- is a cell coordinate and the other a tile coordinate, and "3,4" is a valid
  -- and different place in each.
  if next(m.tiles or {}) ~= nil then
    def.voxelTileEdits = m.tiles
    applied = applied + 1
  end
  -- Tile-id pins come from the TILESET's bucket rather than this map's, so
  -- every map drawn with that tileset gets them -- which is what "this drawing
  -- is a tree" means. Laid on here because the shape resolver is handed a map
  -- and has no other way to reach them.
  if def.tileset then
    local pins = MapEdits.effectiveTilePins(store, game, mapId, def.tileset)
    if next(pins) ~= nil then
      def.voxelClassPins = pins
      applied = applied + 1
    end
  end

  return applied, stale
end

-- Put THIS session's voxel overrides on a map def, right now.
--
-- WHY THIS IS SEPARATE FROM `applyToMap`. The full apply runs once, at
-- Data:load, from a store read off disk -- so the def a map is built from
-- carries the edits as they were when the game booted. The editor holds its
-- own store in memory and writes into that, and the two are different tables:
-- an override typed on the voxel tab landed in the editor's copy and the
-- viewport went on resolving against the boot-time one. Save, restart, and it
-- appeared -- which is indistinguishable from "the editor does not work".
--
-- Assigned by REFERENCE, not copied. `m.voxels` is the live bucket, so once
-- this has run the def and the store are the same table and every subsequent
-- keystroke is visible without re-publishing. The re-publish still has to
-- happen each frame because a bucket may not exist yet when the map is opened
-- and is created by the first edit.
--
-- Cleared when the last override goes: leaving a stale table behind would make
-- CLEAR MAP look like it had not worked.
function MapEdits.publishVoxels(store, game, mapId, def)
  if type(def) ~= "table" then return false end
  local m = bucket(store, game, mapId, false)
  local cells = m and m.voxels
  local tiles = m and m.tiles
  local changed = (def.voxelEdits ~= cells) or (def.voxelTileEdits ~= tiles)
  def.voxelEdits = (cells and next(cells) ~= nil) and cells or nil
  def.voxelTileEdits = (tiles and next(tiles) ~= nil) and tiles or nil

  -- and the pins, which ride on the map def for the same reason the overrides
  -- do: the shape resolver is handed a map and nothing else. The tileset's and
  -- this map's, composed -- most specific wins.
  local pins = def.tileset
    and MapEdits.effectiveTilePins(store, game, mapId, def.tileset) or nil
  def.voxelClassPins = (pins and next(pins) ~= nil) and pins or nil
  return changed
end

-- Apply every map's edits for one game. `maps` is data.maps; `tilesets` is
-- data.tilesets, needed because a per-cell tile edit mints a block into one.
function MapEdits.applyAll(store, game, maps, tilesets, sprites)
  if type(maps) ~= "table" then return 0, nil end
  local g = store and store.games and store.games[game]
  if not g then return 0, nil end
  local total, stale = 0, nil

  -- IMPORTED SHEETS BEFORE ANYTHING ELSE. An object patch may name one, and a
  -- map that renders before the sheet is on `data.sprites` falls through
  -- NPC.resolveSpriteDef to SPRITE_RED -- which looks exactly like the import
  -- having failed. `sprites` is optional: the older three-argument call is
  -- still the one Data:load makes for a build with no sheet support.
  if sprites ~= nil then
    local n, s = MapEdits.applySprites(store, game, sprites)
    total = total + n
    if s then
      stale = stale or {}
      for _, entry in ipairs(s) do stale[#stale + 1] = entry end
    end
  end

  -- ADOPTED TILESETS BEFORE THE MINTS. A minted block is appended INTO a
  -- tileset, and one adopted from another game is not there until this has
  -- run -- so a cell painted onto an imported map would mint into nothing.
  do
    local n, s = MapEdits.applyAdoptedTilesets(store, game, tilesets or {})
    total = total + n
    if s then
      stale = stale or {}
      for _, entry in ipairs(s) do stale[#stale + 1] = entry end
    end
  end

  -- MINTED BLOCKS FIRST OF ALL. A map's block patch may name one by key, and
  -- the id that key resolves to does not exist until the append has run.
  local mintIds, mintStale = MapEdits.applyTilesets(store, game, tilesets or {})
  if mintStale then
    stale = stale or {}
    for _, entry in ipairs(mintStale) do stale[#stale + 1] = entry end
  end

  -- NEW MAPS FIRST, so a map the editor invented can then carry object, warp
  -- and voxel edits of its own like any other. Injected rather than merged:
  -- these ids exist nowhere in the cartridge, so there is nothing to merge
  -- with, and a collision would mean the prefix scheme has been broken.
  for id, spec in pairs(g.newMaps or {}) do
    if maps[id] == nil then
      local def = {}
      for k, v in pairs(spec) do def[k] = v end
      def.id = id
      def.editorCreated = true
      def.objects = def.objects or {}
      def.warps = def.warps or {}
      maps[id] = def
      total = total + 1
    else
      stale = stale or {}
      stale[#stale + 1] =
        id .. ": a cartridge map already uses this id; the new one was skipped"
    end
  end

  if not g.maps then return total, stale end
  for mapId in pairs(g.maps) do
    local def = maps[mapId]
    if def then
      local n, s = MapEdits.applyToMap(store, game, mapId, def, mintIds)
      total = total + n
      if s then
        stale = stale or {}
        for _, entry in ipairs(s) do
          stale[#stale + 1] = mapId .. ": " .. entry
        end
      end
    else
      stale = stale or {}
      stale[#stale + 1] = mapId .. ": the map itself is not in this import"
    end
  end

  -- TILE PINS REACH EVERY MAP THAT USES THE TILESET, not only the maps that
  -- happen to carry edits of their own. The loop above visits `g.maps`, and a
  -- pin lives in the TILESET's bucket -- so a player who pinned six tiles as
  -- trees and edited no map at all would have seen nothing happen anywhere.
  for tilesetId in pairs(g.tilesets or {}) do
    -- through `tilePins`, not off the bucket: a tileset assigned a profile
    -- keeps its pins IN that profile, and reading the bucket directly would
    -- publish nothing for exactly the tilesets that share their answer.
    if next(MapEdits.tilePins(store, game, tilesetId)) ~= nil then
      for id, def in pairs(maps) do
        if type(def) == "table" and def.tileset == tilesetId then
          -- COMPOSED PER MAP, and this loop runs AFTER the per-map one -- so
          -- writing the tileset's pins bare here would clobber the map's own,
          -- which applyToMap had just laid on. Every map that shares a tileset
          -- still gets its own answer.
          def.voxelClassPins =
            MapEdits.effectiveTilePins(store, game, id, tilesetId)
          total = total + 1
        end
      end
    end
  end
  return total, stale
end

-- How many edits a map is carrying, for the picker's "edited" badge.
function MapEdits.count(store, game, mapId)
  local m = bucket(store, game, mapId, false)
  if not m then return 0 end
  local n = 0
  for _ in pairs(m.objects or {}) do n = n + 1 end
  for _ in pairs(m.voxels or {}) do n = n + 1 end
  for _ in pairs(m.tiles or {}) do n = n + 1 end
  for _ in pairs(m.removed or {}) do n = n + 1 end
  for _ in pairs(m.warps or {}) do n = n + 1 end
  for _ in pairs(m.blocks or {}) do n = n + 1 end
  for _ in pairs(m.map or {}) do n = n + 1 end
  for _ in pairs(m.removedWarps or {}) do n = n + 1 end
  for _ in pairs(m.events or {}) do n = n + 1 end
  n = n + #(m.added or {}) + #(m.addedWarps or {}) + #(m.tilesets or {})
  return n
end

-- Every map this game has edits for, sorted -- the picker's "edited" filter.
-- Every edited map's bucket for `game`, keyed by map id.
--
-- The buckets themselves rather than their ids, because the callers that want
-- this want to COUNT what is in them -- how many objects were added, how many
-- maps are touched -- and a panel reaching into `store.games[g].maps` to do
-- that is a panel that has to be found and changed the day the store's shape
-- moves.
function MapEdits.mapsOf(store, game)
  local g = store and store.games and store.games[game]
  return (g and g.maps) or {}
end

function MapEdits.editedMaps(store, game)
  local g = store and store.games and store.games[game]
  local out = {}
  for mapId in pairs((g and g.maps) or {}) do out[#out + 1] = mapId end
  table.sort(out)
  return out
end

return MapEdits
