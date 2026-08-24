-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Export the map editor's changes as a mod anyone can install.
--
-- WHY A CONTENT MOD AND NOT A COPY OF THE EDIT STORE. The store is a private
-- format keyed by game and map, applied by the editor's own overlay at load --
-- handing someone that file means handing them something only this editor
-- understands, that lands in a save directory they have to find, and that
-- their own edits then collide with. A mod is the thing this engine already
-- has for "here is some changed content": it installs, it toggles, it lists
-- its version, it declares what it touches, and two of them can be on at once.
--
-- So the export RESOLVES the edits and emits them through the content API --
-- `mod.content.maps:patch`, `encounters:patch`, `tilesets:register` -- which
-- is the same door every other content mod comes through. The receiving player
-- needs no map editor at all.
--
-- STORED, NOT DEFLATED. A zip entry can be raw-deflated, and LOVE's compressor
-- emits zlib-wrapped deflate, which is a different thing with a two-byte
-- header a zip reader will reject. Getting that subtly wrong produces an
-- archive that some tools open and others do not -- the worst possible bug in
-- a file you hand to someone else. Method 0 is a length, a CRC and the bytes;
-- there is nothing in it to get subtly wrong, and a mod is Lua text that the
-- filesystem will compress underneath us anyway.

local ModExport = {}

-- ---------------------------------------------------------------------------
-- CRC32
-- ---------------------------------------------------------------------------

-- Table-driven, built once. A zip entry carries the CRC of its uncompressed
-- bytes in two places -- the local header and the central directory -- and a
-- reader that finds them disagreeing calls the archive corrupt, so this is not
-- a checksum anybody can skip.
-- BITWISE, ON AN INTERPRETER THAT MAY NOT HAVE THE OPERATORS.
--
-- The game runs on LuaJIT, which is Lua 5.1: `~`, `>>` and `&` are not
-- operators there, they are a SYNTAX ERROR -- so a file that spells them does
-- not fail at the CRC, it fails to load at all, and the export button is
-- simply missing with nothing in the log about why. LuaJIT ships the `bit`
-- library instead; 5.3 and later have the operators and no `bit`. The 5.3
-- forms are built with `load` so this file's own text never contains them for
-- a 5.1 parser to choke on.
local bxor, rshift, band
do
  local okBit, bit = pcall(require, "bit")
  if okBit and type(bit) == "table" and bit.bxor then
    bxor, rshift, band = bit.bxor, bit.rshift, bit.band
  else
    local chunk = load([[
      return function(a, b) return a ~ b end,
             function(a, n) return a >> n end,
             function(a, b) return a & b end
    ]])
    if chunk then
      bxor, rshift, band = chunk()
    else
      -- Neither: pure arithmetic, which is slow and correct. An export is a
      -- once-a-session operation on a few tens of kilobytes, so slow is a
      -- price worth paying over not working.
      local function bits(a, b, f)
        local r, m = 0, 1
        for _ = 1, 32 do
          local x, y = a % 2, b % 2
          r = r + f(x, y) * m
          a, b, m = (a - x) / 2, (b - y) / 2, m * 2
        end
        return r
      end
      bxor = function(a, b)
        return bits(a % 4294967296, b % 4294967296,
                    function(x, y) return (x ~= y) and 1 or 0 end)
      end
      band = function(a, b)
        return bits(a % 4294967296, b % 4294967296,
                    function(x, y) return (x == 1 and y == 1) and 1 or 0 end)
      end
      rshift = function(a, n)
        return math.floor((a % 4294967296) / 2 ^ n)
      end
    end
  end
end

-- `bit` returns SIGNED 32-bit values; a CRC is unsigned and is written as
-- four little-endian bytes, so it is normalised here rather than at every use.
local function u32(n)
  n = n % 4294967296
  if n < 0 then n = n + 4294967296 end
  return n
end

local crcTable = nil

local function crcInit()
  if crcTable then return crcTable end
  crcTable = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c % 2 == 1 then
        c = bxor(0xEDB88320, rshift(u32(c), 1))
      else
        c = rshift(u32(c), 1)
      end
    end
    crcTable[i] = u32(c)
  end
  return crcTable
end

function ModExport.crc32(str)
  local t = crcInit()
  local crc = 0xFFFFFFFF
  for i = 1, #str do
    crc = u32(bxor(t[band(bxor(u32(crc), str:byte(i)), 0xFF)],
                   rshift(u32(crc), 8)))
  end
  return u32(bxor(u32(crc), 0xFFFFFFFF))
end

local function le16(n)
  n = u32(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function le32(n)
  n = u32(n)
  return string.char(n % 256, math.floor(n / 256) % 256,
                     math.floor(n / 65536) % 256,
                     math.floor(n / 16777216) % 256)
end

-- ---------------------------------------------------------------------------
-- the archive
-- ---------------------------------------------------------------------------

-- `files` is a list of { name, data }, in the order they should appear. Order
-- is kept rather than sorted because a zip's central directory has to describe
-- the entries at the offsets they were actually written to, and the two lists
-- are built in one pass here for exactly that reason.
function ModExport.zip(files)
  local parts, central, offset = {}, {}, 0
  for _, f in ipairs(files) do
    local name, data = f.name, f.data or ""
    local crc = ModExport.crc32(data)
    -- version 2.0, no flags, method 0 (stored), no date -- a zip with no
    -- timestamp reads as 1980, which is honest: this file has no meaningful
    -- modification time, it was generated.
    local local_ = "PK\003\004" .. le16(20) .. le16(0) .. le16(0)
      .. le16(0) .. le16(0)
      .. le32(crc) .. le32(#data) .. le32(#data)
      .. le16(#name) .. le16(0) .. name
    parts[#parts + 1] = local_
    parts[#parts + 1] = data
    central[#central + 1] = "PK\001\002" .. le16(20) .. le16(20) .. le16(0)
      .. le16(0) .. le16(0) .. le16(0)
      .. le32(crc) .. le32(#data) .. le32(#data)
      .. le16(#name) .. le16(0) .. le16(0)
      .. le16(0) .. le16(0) .. le32(0) .. le32(offset) .. name
    offset = offset + #local_ + #data
  end
  local dir = table.concat(central)
  local tail = "PK\005\006" .. le16(0) .. le16(0)
    .. le16(#files) .. le16(#files) .. le32(#dir) .. le32(offset) .. le16(0)
  return table.concat(parts) .. dir .. tail
end

-- ---------------------------------------------------------------------------
-- what goes in it
-- ---------------------------------------------------------------------------

-- JSON strings, for the manifest.
--
-- Only the two escapes that can actually appear here: a backslash and a quote
-- have to be escaped or the file is not JSON, and a newline in a description
-- has to become `\n` or the value runs off the end of its line. A mod name
-- with a tab or a control character in it is not a case worth carrying code
-- for, and the loader would reject the id anyway.
local function jsonString(s)
  s = tostring(s)
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "")
  return '"' .. s .. '"'
end

function ModExport.manifest(spec, requires, mapIds)
  local id = spec.id or "MY_MAP_EDITS"
  local rows = {
    '  "id": ' .. jsonString(id),
    '  "name": ' .. jsonString(spec.name or "My map edits"),
    '  "version": ' .. jsonString(spec.version or "1.0.0"),
    '  "api": 2',
    '  "entry": "main.lua"',
    '  "profile": "content"',
    '  "category": "CONTENT"',
    '  "description": ' .. jsonString(spec.description
      or "Map changes made with the in-game map editor."),
    -- DECLARED, because the loader uses this to order mods and to warn about
    -- overlaps: two map mods that both patch Route 29 is something the player
    -- should be told about rather than discover.
    '  "games": ["gen2"]',
    '  "experimental": false',
  }

  -- DECLARED IN THE MANIFEST, not only in main.lua.
  --
  -- The manifest is the only part of a mod the launcher reads WITHOUT running
  -- it (src/mods/Manifest.lua, and LauncherMods scans manifests alone). A
  -- requirement that lives in the entry file is one the player discovers by
  -- installing and watching it refuse -- which is honest, and still later than
  -- it needed to be. Here it is answerable on the install screen, before the
  -- zip is unpacked.
  -- WHAT IS IN IT, readable without running it.
  --
  -- Same argument as required_games below, applied to the contents: the entry
  -- file's MAPS table is the truth, and it only becomes readable once the mod
  -- has loaded -- which is a boot away from installing. Listed here, the pack
  -- dialog can say what a freshly installed pack contains instead of showing
  -- the previous version's maps until a restart.
  --
  -- Sorted, so re-exporting an unchanged set produces an identical manifest
  -- and a diff of two packs is about their content rather than table order.
  if type(mapIds) == "table" and mapIds[1] then
    local sorted = {}
    for _, id in ipairs(mapIds) do sorted[#sorted + 1] = tostring(id) end
    table.sort(sorted)
    local parts = {}
    for _, id in ipairs(sorted) do
      parts[#parts + 1] = "    " .. jsonString(id)
    end
    rows[#rows + 1] = '  "maps": [\n' .. table.concat(parts, ",\n") .. "\n  ]"
  end

  if type(requires) == "table" and requires[1] then
    local parts = {}
    for _, row in ipairs(requires) do
      parts[#parts + 1] = string.format(
        '    { "version": %s, "name": %s }',
        jsonString(tostring(row.version or "")),
        jsonString(tostring(row.name or row.version or "")))
    end
    rows[#rows + 1] = '  "required_games": [\n'
      .. table.concat(parts, ",\n") .. "\n  ]"
  end

  return "{\n" .. table.concat(rows, ",\n") .. "\n}\n"
end

-- Lua source for a value, good enough for the shapes the editor stores:
-- tables, numbers, strings, booleans. Deliberately not a general serialiser --
-- MapEdits.serialise already is one and this reuses it.
local function serialise(value)
  local ok, ME = pcall(require, "tools.map-editor.MapEdits")
  if ok and type(ME) == "table" and ME.serialise then
    return ME.serialise(value, "")
  end
  return "nil"
end

-- WHICH FIELDS OF A MAP AN EXPORT CARRIES.
--
-- The whole def would be simpler and is wrong: it includes everything the
-- extractor produced, so the mod would restate the entire cartridge map and
-- overwrite anything another mod had done to the parts this editor never
-- touched. Only what the editor can change goes.
ModExport.MAP_FIELDS = {
  "blocks", "objects", "warps", "borderBlock", "name",
  "voxelEdits", "voxelTileEdits", "voxelClassPins",
}

-- AND WHAT AN INVENTED MAP CANNOT DO WITHOUT.
--
-- The list above is a PATCH list: it names the things the editor can change
-- about a map that already exists, and everything else -- which tileset draws
-- it, how big it is, what it is called -- comes from the cartridge's own def
-- underneath.
--
-- A map the editor invented has no def underneath. Exported through the patch
-- list alone it arrived as blocks, objects and warps with no tileset, no
-- width and no height: not a map, a bag of numbers. MapLoader has nothing to
-- draw it with and the reader sees the map missing entirely -- which is
-- exactly what "the maps I created are not in the export" was, and it was not
-- the export dropping them. All six were in the pack; none of them could be
-- built.
--
-- Added ONLY for maps with no cartridge original, because on one that has an
-- original these are the original's -- and restating them would overwrite
-- whatever another mod had done to the parts this editor never touched, which
-- is the whole reason the patch list is short.
ModExport.NEW_MAP_FIELDS = {
  "id", "tileset", "width", "height", "palette", "environment", "music",
  "connections", "signs",
}

-- WARPS, CUT DOWN TO WHAT THE SCHEMA WILL ACTUALLY ACCEPT.
--
-- THIS IS THE ONE THAT SILENTLY ATE WHOLE MAPS, and the mechanism is worth
-- writing down because nothing about it is visible from here.
--
-- `R.maps.warps` is `f.opt(f.list(f.rec{ x, y, destMap, destWarp }))`, and
-- `checkValue`'s list branch recurses with `patchMode = false`:
--
--     checkValue(t.inner, element, path .. "[" .. i .. "]", false, errors)
--
-- So inside a warp, required fields are enforced EVEN IN A PATCH -- and
-- nested records are strict about unknown keys as well (`if hint or not top`,
-- and `top` is never passed down). An editor warp carries `added`,
-- `editorSlot`, `sourceWarp`, `destSourceMap` and `destSourceWarp`, which are
-- bookkeeping this side of the export and unknown fields on the other; and a
-- warp the author has not pointed anywhere yet has no `destMap` at all.
--
-- Either one fails validation. The pack declares `api = 2`, so a failure
-- RAISES, and the generated loader wraps each patch in `pcall` -- so the
-- error is swallowed and the ENTIRE MAP is dropped without a word. A map
-- whose only sin was one unfinished door vanished; a map with no warps at all
-- came through fine. That is exactly "the trees in New Bark Town are there
-- and Route 29 is not".
--
-- So: the four fields the schema names, nothing else, and a warp with no
-- destination is left out rather than shipped as a record that will take its
-- map down with it. It goes nowhere in game either way.
local WARP_FIELDS = { "x", "y", "destMap", "destWarp" }

function ModExport.sanitiseWarps(list)
  if type(list) ~= "table" then return nil, 0 end
  local out, dropped = {}, 0
  for _, w in ipairs(list) do
    if type(w) == "table" and not w.removed
       and type(w.destMap) == "string" and w.destMap ~= "" then
      local clean = {}
      for _, key in ipairs(WARP_FIELDS) do clean[key] = w[key] end
      clean.x = math.max(0, math.floor(tonumber(clean.x) or 0))
      clean.y = math.max(0, math.floor(tonumber(clean.y) or 0))
      -- Warp ids are 1-based and the schema takes any non-negative integer;
      -- a missing one means "the first warp over there", which is what the
      -- editor defaults a new door to.
      clean.destWarp = math.max(0, math.floor(tonumber(clean.destWarp) or 1))
      out[#out + 1] = clean
    else
      dropped = dropped + 1
    end
  end
  return out, dropped
end

-- Connections are keyed by an enum of four directions; anything else in that
-- table is a field the schema will refuse, and refusing takes the map with it.
local CONNECTION_SIDES = { north = true, south = true, east = true, west = true }

local function sanitiseConnections(conn)
  if type(conn) ~= "table" then return nil end
  local out, any = {}, false
  for side, value in pairs(conn) do
    if CONNECTION_SIDES[side] then out[side] = value; any = true end
  end
  return any and out or nil
end

function ModExport.mapPatch(def, invented)
  local out = {}
  for _, key in ipairs(ModExport.MAP_FIELDS) do
    if def[key] ~= nil then out[key] = def[key] end
  end
  if invented then
    for _, key in ipairs(ModExport.NEW_MAP_FIELDS) do
      if def[key] ~= nil then out[key] = def[key] end
    end
    out.connections = sanitiseConnections(out.connections)
  end
  local warps, dropped = ModExport.sanitiseWarps(out.warps)
  out.warps = warps
  return out, dropped
end

-- THE TILE PINS FOR ONE MAP, READ FROM THE STORE RATHER THAN FROM THE DEF.
--
-- `voxelClassPins` is a TILESET-level fact -- "this drawing is a tree" -- and
-- it reaches a map def by being published onto it: `applyToMap` at load, and
-- `publishVoxels` per frame for the map the editor is LOOKING AT. Neither
-- covers "a pin added this session, on a map that is not open".
--
-- Reading the def meant an export carried the pins for whichever maps happened
-- to have them and silently omitted the rest -- New Bark Town went out with
-- its per-cell overrides and no pins at all, so every borrowed tree that was
-- not individually overridden came out as a wall on the other machine. The
-- store is the truth; ask it once per map.
function ModExport.tilePinsFor(ME, store, game, mapId, tileset)
  if not (ME and ME.effectiveTilePins and tileset) then return nil end
  local ok, pins = pcall(ME.effectiveTilePins, store, game, mapId, tileset)
  if not (ok and type(pins) == "table" and next(pins) ~= nil) then return nil end
  local out = {}
  for tile, cls in pairs(pins) do out[tile] = cls end
  return out
end

-- The mod's main.lua: one file, data inline.
--
-- Inline rather than in a data/ file the entry then reads, because a mod's own
-- loader is the only thing that can read its data/ directory and wiring that
-- up is a second mechanism to get wrong for no gain -- this is generated code,
-- and nobody is going to hand-edit the table in the middle of it.
function ModExport.main(spec, maps, encounters, sprites, tilesets, requires,
                        tileEdits)
  local lines = {
    "-- Generated by the Gen2Recomped map editor. Every table below is the",
    "-- RESOLVED content -- the cartridge's map with the edits already applied",
    "-- -- so this mod needs no editor and no edit store to work.",
    "local mod = ...",
    "",
    "local GAME = " .. string.format("%q", tostring(spec.game or "gen2")),
    "",
    "local MAPS = " .. serialise(maps),
    "",
    "local ENCOUNTERS = " .. serialise(encounters),
    "",
    "local SPRITES = " .. serialise(sprites or {}),
    "",
    "-- TILESETS BORROWED FROM ANOTHER CARTRIDGE, BY REFERENCE.",
    "--",
    "-- Each row is a NAME AND A GAME, never the tileset itself: not its",
    "-- blocks, not its collision, not a pixel of its art. Those are the",
    "-- cartridge's, and a mod is a file one player hands another -- so what",
    "-- travels is which game to look in, and the resolution happens against",
    "-- the copy the person installing this imported themselves.",
    "--",
    "-- It is also the only version that works. The art path an adopted",
    "-- tileset carries points into the AUTHOR's cache; resolved here, it",
    "-- points into the reader's.",
    "local TILESETS = " .. serialise(tilesets or {}),
    "",
    "-- The cartridges the tables above are meaningless without.",
    "local REQUIRES = " .. serialise(requires or {}),
    "",
    "-- BORROWED TILES AND MINTED BLOCKS, as recipes.",
    "--",
    "-- Painting a tree out of another tileset does not put a tree in the",
    "-- map: the pixels are appended to the destination tileset's atlas, a",
    "-- block is minted pointing at them, and the map stores that block's ID.",
    "-- Ship the maps alone and the ids point at blocks the receiving machine",
    "-- has never had -- which is a map drawn out of the wrong art, or, for a",
    "-- map built entirely of minted blocks, one that looks absent.",
    "--",
    "-- The extended ATLAS is not shipped: it is cartridge art. What travels",
    "-- is which tileset each tile came from, and the receiving machine",
    "-- rebuilds an identical one from its own extraction.",
    "local TILE_EDITS = " .. serialise(tileEdits or {}),
    "",
    "-- WHICH MAPS A MISSING CARTRIDGE ACTUALLY COSTS.",
    "--",
    "-- This refused the WHOLE pack the moment one required cartridge was",
    "-- not imported, returning before it touched anything. The reasoning",
    "-- was sound -- a map whose tileset cannot resolve makes MapLoader",
    "-- assert -- but the blast radius was not: a pack with one cave copied",
    "-- out of Red also carries every edit made to this game's own maps, and",
    "-- none of those need Red for anything. One missing cartridge discarded",
    "-- the lot, silently, which is what -- importing it made no changes to",
    "-- the maps at all -- actually was.",
    "--",
    "-- The requirement is still declared, still logged and still shown by",
    "-- the launcher. The maps are now judged ONE AT A TIME below, against",
    "-- whether the tileset each of them names actually resolved, so only",
    "-- the ones that genuinely cannot be drawn are held back.",
    "local AdoptedTileset = require(\"src.import.AdoptedTileset\")",
    "local Logger = require(\"src.core.Logger\")",
    "",
    "local want = {}",
    "for _, row in ipairs(REQUIRES) do want[#want + 1] = row.version end",
    "local missing = AdoptedTileset.missing(want)",
    "if missing then",
    "  local text = AdoptedTileset.requirementText(missing, mod and mod.name",
    "                                              or \"This map pack\")",
    "  Logger.warn(\"%s\", text)",
    "  -- Named where the launcher can show it, not only in the log.",
    "  if mod then mod.unmetRequirement = text; mod.missingImports = missing end",
    "end",
    "",
    "-- THE TILESETS BEFORE THE MAPS, both kinds: a map names an adopted",
    "-- tileset, and a map's block ids do not exist until the mints that",
    "-- created them have been appended.",
    "-- The adopted tilesets FIRST: a map naming one is loaded against it.",
    "local unresolved = {}",
    "for id, ref in pairs(TILESETS) do",
    "  local def, why = AdoptedTileset.resolve(ref.from, ref.tileset)",
    "  if def then",
    "    pcall(function() mod.content.tilesets:register(id, def) end)",
    "  else",
    "    unresolved[id] = tostring(why or \"not available\")",
    "    Logger.warn(\"%s: %s could not be resolved (%s)\",",
    "                tostring(mod and mod.id), tostring(id), tostring(why))",
    "  end",
    "end",
    "",
    "-- AND THE BORROWED ART, against this machine's own tilesets.",
    "--",
    "-- Straight onto Data rather than through the content registry: this",
    "-- APPENDS to a live array and swaps the atlas path, which is a whole-",
    "-- record rewrite the registry would have to be handed in full -- and the",
    "-- full record is the cartridge's. The applier reports what it could not",
    "-- do rather than raising; a tileset that refuses leaves its maps drawing",
    "-- the cartridge's own blocks, which is wrong but not silently wrong.",
    "if next(TILE_EDITS) ~= nil then",
    "  local okBT, BorrowedTiles = pcall(require, \"src.import.BorrowedTiles\")",
    "  local okD, Data = pcall(require, \"src.core.Data\")",
    "  if not (okBT and okD and type(Data.tilesets) == \"table\") then",
    "    -- NOTHING IS PATCHED, for the reason the cartridge check above",
    "    -- refuses: a half-applied pack is the worst outcome available. The",
    "    -- maps would land and the blocks they are drawn from would not, so",
    "    -- every borrowed tree comes out as whatever block happens to sit at",
    "    -- that id -- wrong art that looks deliberate. This build predates",
    "    -- src/import/BorrowedTiles.lua; the pack is fine, the engine is old.",
    "    local text = (mod and mod.name or \"This map pack\")",
    "      .. \" needs a newer build: it carries tiles copied between\"",
    "      .. \" tilesets, and this version cannot rebuild them.\"",
    "    Logger.warn(\"%s\", text)",
    "    if mod then mod.unmetRequirement = text end",
    "    return { unmetRequirement = text }",
    "  end",
    "  local _, why, pins = BorrowedTiles.apply(GAME, TILE_EDITS,",
    "                                           Data.tilesets)",
    "  for _, msg in ipairs(why or {}) do",
    "    Logger.warn(\"%s: %s\", tostring(mod and mod.id), tostring(msg))",
    "  end",
    "  -- THE CLASS PINS, ONTO EVERY MAP THAT USES THE TILESET.",
    "  --",
    "  -- A pin says what a DRAWING is -- \"these six tiles are a tree\" -- so it",
    "  -- belongs to the tileset. TileShape reads it off the map, though, so it",
    "  -- has to be laid on each one; a pack that only carried the pins for the",
    "  -- maps it exported left every borrowed tree elsewhere resolving through",
    "  -- the collision class, which on a solid cell is a wall.",
    "  --",
    "  -- The map\'s own pins win: those are the reader\'s decisions.",
    "  if pins then",
    "    for id, patch in pairs(MAPS) do",
    "      local ts = patch.tileset or (Data.maps[id] and Data.maps[id].tileset)",
    "      local add = ts and pins[ts]",
    "      if add then",
    "        local merged = {}",
    "        for tile, cls in pairs(add) do merged[tile] = cls end",
    "        for tile, cls in pairs(patch.voxelClassPins or {}) do",
    "          merged[tile] = cls",
    "        end",
    "        patch.voxelClassPins = merged",
    "      end",
    "    end",
    "  end",
    "end",
    "",
    "-- `patch`, not `register`: these maps already exist, and registering over",
    "-- one would replace it wholesale -- including the fields this editor",
    "-- never touched and another mod may have changed.",
    "local held = 0",
    "for id, patch in pairs(MAPS) do",
    "  -- Held back only when the tileset THIS map names is one that could not",
    "  -- be resolved. A patch with no tileset in it is a patch over a",
    "  -- cartridge map, drawn by the cartridge's own tileset, never at risk.",
    "  local ts = patch.tileset",
    "  if ts and unresolved[ts] then",
    "    held = held + 1",
    "    Logger.warn(\"%s: %s held back - %s is %s\", tostring(mod and mod.id),",
    "                tostring(id), tostring(ts), tostring(unresolved[ts]))",
    "  else",
    "    pcall(function() mod.content.maps:patch(id, patch) end)",
    "  end",
    "end",
    "if held > 0 and mod then mod.heldMaps = held end",
    "for id, patch in pairs(ENCOUNTERS) do",
    "  pcall(function() mod.content.encounters:patch(id, patch) end)",
    "end",
    "-- SHEETS ARE THE OTHER WAY ROUND: `register`, because these ids exist",
    "-- nowhere in the cartridge -- there is nothing to patch. The image path",
    "-- is relative to this mod, and the PNG travels in the zip beside it.",
    "for id, def in pairs(SPRITES) do",
    "  pcall(function() mod.content.sprites:register(id, def) end)",
    "end",
    "",
    "return {}",
  }
  return table.concat(lines, "\n") .. "\n"
end

-- Collect everything the editor has changed, resolved.
function ModExport.build(S, spec)
  spec = spec or {}
  local ok, ME = pcall(require, "tools.map-editor.MapEdits")
  if not ok then return nil, "the edit store is not available" end
  local store = S.mapEdits
  if not store then return nil, "nothing has been edited yet" end

  local game = spec.game or S.version or "unknown"
  local edited = ME.editedMaps(store, tostring(game))
  -- WHICH IDS THE EDITOR INVENTED, read before anything is packed: an invented
  -- map needs its identity fields carried and a cartridge one must not have
  -- them restated. See ModExport.NEW_MAP_FIELDS.
  local gNew = store.games and store.games[tostring(game)]
  local invented = (gNew and gNew.newMaps) or {}
  local maps, n = {}, 0
  -- Doors with nowhere to go, counted so the export can mention them rather
  -- than leaving the author to notice on the other machine.
  local unfinished = 0
  for _, id in ipairs(edited or {}) do
    local def = S.data and S.data.maps and S.data.maps[id]
    if def then
      local patch, lost = ModExport.mapPatch(def, invented[id] ~= nil)
      maps[id] = patch
      patch.voxelClassPins =
        ModExport.tilePinsFor(ME, store, tostring(game), id, def.tileset)
        or patch.voxelClassPins
      unfinished = unfinished + (lost or 0)
      n = n + 1
    end
  end
  -- Maps the editor INVENTED come through the same door: they are already in
  -- `data.maps` by the time the editor can have edited them, so the loop above
  -- has them -- but a new map with no other edit would not be in `editedMaps`.
  local g = store.games and store.games[tostring(game)]
  for id in pairs((g and g.newMaps) or {}) do
    local def = S.data and S.data.maps and S.data.maps[id]
    if def and not maps[id] then
      local patch, lost = ModExport.mapPatch(def, true)
      maps[id] = patch
      patch.voxelClassPins =
        ModExport.tilePinsFor(ME, store, tostring(game), id, def.tileset)
        or patch.voxelClassPins
      unfinished = unfinished + (lost or 0)
      n = n + 1
    end
  end

  local encounters = {}
  for _, id in ipairs(edited or {}) do
    local rec = S.data and S.data.encounters and S.data.encounters[id]
    local w = ME.wilds and ME.wilds(store, tostring(game), id)
    if rec and w then
      encounters[id] = rec
      n = n + 1
    end
  end

  -- ------------------------------------------------------ imported sheets
  --
  -- THE PIXELS TRAVEL WITH THE RECORD, and this is the only part of an export
  -- that is not text. The zip writer is method 0 (stored) with the CRC taken
  -- over the raw bytes and the length used verbatim, so it has always been
  -- byte-clean -- what was missing was anything asking it to carry a file.
  --
  -- A sheet's `image` in the edit store points into the SAVE directory
  -- (`editor/sprites/X.png`), which is a path that exists on this machine and
  -- nowhere else. Rewritten to a mod-relative one on the way out, so the
  -- record in the mod names the file that is sitting next to it in the zip.
  local sprites, assets = {}, {}
  for id, def in pairs((ME.sprites and ME.sprites(store, tostring(game))) or {}) do
    local bytes = nil
    if love and love.filesystem and love.filesystem.read and def.image then
      local okR, raw = pcall(love.filesystem.read, def.image)
      bytes = okR and type(raw) == "string" and #raw > 0 and raw or nil
    end
    if bytes then
      local rel = "sprites/" .. tostring(id) .. ".png"
      local out = {}
      for k, v in pairs(def) do out[k] = v end
      out.image = rel
      out.source = nil            -- "editor import" means nothing to a player
      sprites[id] = out
      assets[#assets + 1] = { name = rel, data = bytes }
      n = n + 1
    end
    -- A sheet whose PNG has gone is SKIPPED rather than exported with a dead
    -- path: a record naming a file that is not in the zip is a mod that
    -- installs cleanly and draws a fallback, which is the worst of both.
  end

  -- ------------------------------------------------- adopted tilesets
  --
  -- BY REFERENCE. The store holds the whole tileset record -- blocks,
  -- collision, palettes, and an art path into the author's own cache -- and
  -- none of it travels. `adoptedFrom` and the source name are enough for the
  -- reader's machine to rebuild the identical record from its OWN extraction,
  -- and they are the only two fields in it that are not the cartridge's.
  local tilesets, requires = {}, {}
  do
    local seen = {}
    for id, spec in pairs((ME.adoptedTilesets
                           and ME.adoptedTilesets(store, tostring(game))) or {}) do
      local from = spec.adoptedFrom
      local name = spec.adoptedName
      if not name then
        -- Adopted before the record carried its source name: recover it from
        -- the namespaced id, which has always held both halves.
        local okA, AT = pcall(require, "src.import.AdoptedTileset")
        if okA then name = (AT.split(id)) end
      end
      if from and name then
        tilesets[id] = { from = from, tileset = name }
        seen[from] = true
        n = n + 1
      end
    end
    -- EVERY source game, not only the ones that contributed a tileset: a map
    -- copied out of Blue whose tileset happened to exist locally still came
    -- out of Blue, and still will not mean anything without it.
    for _, version in ipairs((ME.sourceGames
                              and ME.sourceGames(store, tostring(game))) or {}) do
      seen[version] = true
    end
    local okA, AT = pcall(require, "src.import.AdoptedTileset")
    local versions = {}
    for version in pairs(seen) do versions[#versions + 1] = version end
    table.sort(versions)
    for _, version in ipairs(versions) do
      requires[#requires + 1] = {
        version = version,
        name = okA and AT.displayName(version) or tostring(version):upper(),
      }
    end
  end

  -- WHAT THIS EXPORT ACTUALLY SAW, once, where the reader can see it.
  --
  -- "Nothing has been edited yet" is the one refusal a reader can disagree
  -- with -- they have been editing for an hour -- and it has three quite
  -- different causes that read identically: the store is keyed by a game id
  -- that is not the one being edited, the edited map ids are not in
  -- `data.maps`, or there genuinely are no edits. Only the first two are bugs
  -- and neither is visible from the sentence.
  pcall(function()
    require("src.core.Logger").info(
      "export %s: game=%s, %d edited map(s), %d new, %d adopted tileset(s), "
      .. "%d resolved into the mod, requires=%s",
      tostring(spec.id or "MAP_EDITS"), tostring(game), #(edited or {}),
      (function() local c = 0
         for _ in pairs((g and g.newMaps) or {}) do c = c + 1 end
         return c end)(),
      (function() local c = 0
         for _ in pairs((ME.adoptedTilesets
                         and ME.adoptedTilesets(store, tostring(game))) or {}) do
           c = c + 1 end
         return c end)(),
      n,
      (requires[1] and requires[1].version) or "none")
  end)

  if n == 0 then
    -- The REASON, at the level that separates the three causes above.
    local edits = #(edited or {})
    local news = 0
    for _ in pairs((g and g.newMaps) or {}) do news = news + 1 end
    if edits == 0 and news == 0 then
      return nil, string.format(
        "nothing has been edited yet for '%s' - if you have been editing, the "
        .. "edit store is keyed by a different game id", tostring(game))
    end
    return nil, string.format(
      "%d edited and %d new map(s) are in the store for '%s', but none of "
      .. "them are in this session's map list - nothing could be resolved",
      edits, news, tostring(game))
  end
  -- ------------------------------------------- borrowed art and mints
  --
  -- The half of an edit that lives in the TILESET rather than in the map. A
  -- map's `blocks` array is a list of ids, and an id created by minting a
  -- block out of borrowed tiles means nothing on a machine that has not
  -- minted it. Recipes only -- see MapEdits.tilesetRecipes.
  local tileEdits = ME.tilesetRecipes
    and ME.tilesetRecipes(store, tostring(game), S.data and S.data.tilesets)
    or nil
  if tileEdits then
    for _ in pairs(tileEdits) do n = n + 1 end
  end

  local id = spec.id or "MAP_EDITS"
  local mapIds = {}
  for mapId in pairs(maps) do mapIds[#mapIds + 1] = mapId end
  local files = {
    { name = "manifest.json",
      data = ModExport.manifest(spec, requires, mapIds) },
    { name = "main.lua",
      data = ModExport.main(
        { id = spec.id, name = spec.name, version = spec.version,
          description = spec.description, game = tostring(game) },
        maps, encounters, sprites, tilesets, requires, tileEdits) },
  }
  for _, a in ipairs(assets) do files[#files + 1] = a end
  return files, n, requires, unfinished
end

-- Build and write. Returns the path, or nil and a reason.
function ModExport.write(S, spec)
  local files, nOrWhy, requires, unfinished = ModExport.build(S, spec)
  if not files then return nil, nOrWhy end
  local data = ModExport.zip(files)
  local name = ((spec and spec.id) or "MAP_EDITS"):gsub("[^%w_%-]", "_")
  local path = "exports/" .. name .. ".zip"
  if not (love and love.filesystem and love.filesystem.write) then
    return nil, "no filesystem to write to"
  end
  pcall(function() love.filesystem.createDirectory("exports") end)
  local okW, err = love.filesystem.write(path, data)
  if not okW then return nil, "could not write it: " .. tostring(err) end
  local dir = ""
  pcall(function() dir = love.filesystem.getSaveDirectory() .. "/" end)
  -- THE REQUIREMENT COMES BACK WITH THE PATH, so the author is told what
  -- they just made rather than finding out from the first person who installs
  -- it. Whoever exported this map pack is the only one who can put the
  -- sentence in their release notes, and the only one who currently cannot see
  -- it -- everything works on the machine the maps were imported on.
  return dir .. path, nOrWhy, requires, unfinished
end

return ModExport
