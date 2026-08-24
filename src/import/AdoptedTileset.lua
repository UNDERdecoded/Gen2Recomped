-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Reading another imported cartridge's tilesets, for maps copied out of it.
--
-- WHY THIS IS IN src/ AND NOT WITH THE MAP EDITOR.
--
-- The editor copies a map out of one game into another -- Cerulean Cave from
-- Blue into Crystal -- and the map is meaningless without the tileset it is
-- drawn against, so the tileset is ADOPTED: registered here under a namespaced
-- id (`TilesetCavern@blue`) that cannot collide with a local one.
--
-- The art is NOT COPIED. Every version's cache is a folder beside this one's,
-- so `blue/assets/generated/tilesets/x.png` is already visible; the record
-- holds a path into the other game's cache and the pixels stay where the
-- importer put them.
--
-- That has a consequence the editor cannot answer for on its own: a mod
-- EXPORTED from those edits carries the reference, and the person installing it
-- has to have imported the same cartridge or there is nothing behind the path.
-- The exported mod therefore has to do this resolution itself, at load, on
-- someone else's machine -- and `tools/` is not in a player build (see
-- scripts/pack_love.sh, which ships only tools/save-editor and the ROM
-- manifests). A mod that required the editor's copy of this logic would work
-- for the author and for nobody else.
--
-- So the logic lives here, where both callers reach it: the editor while
-- adopting, and an exported mod while resolving what the editor adopted.
--
-- WHAT THIS FILE WILL NOT DO. It will not put cartridge content anywhere it
-- can be redistributed. It reads the RECIPIENT's own extraction and hands back
-- a record pointing into it. An export carries the reference -- which game,
-- which tileset -- and never the blocks, the collision or the pixels; those
-- are the cartridge's, and the same rule the repository applies to itself
-- (.gitignore excludes data/generated, assets/generated, the example mod's
-- sprites and even screenshots, "so they are ROM content") applies to anything
-- this engine hands one player to give to another.

local AdoptedTileset = {}

-- The namespaced id an adopted tileset takes.
--
-- `TilesetJohto@gold`, not `TilesetJohto`: a name that cannot collide with a
-- local tileset, so adopting one can never change how an existing map draws.
function AdoptedTileset.id(name, version)
  return tostring(name) .. "@" .. tostring(version)
end

-- The two halves back out of one, or nil when the id is not an adopted one.
function AdoptedTileset.split(id)
  if type(id) ~= "string" then return nil end
  local name, version = id:match("^(.+)@([^@]+)$")
  if not name then return nil end
  return name, version
end

local function gameVersion()
  local ok, GV = pcall(require, "src.core.GameVersion")
  return ok and GV or nil
end

function AdoptedTileset.prefix(version)
  local GV = gameVersion()
  if not GV then return "" end
  local prefix = GV.cachePrefix and GV.cachePrefix(version)
    or (GV.info(version) or {}).cachePrefix
  return tostring(prefix or "")
end

-- What to call this cartridge when telling someone they need it.
--
-- The player knows it as "Pokemon Blue", not as `blue`, and this string ends up
-- in a sentence they read before deciding whether to install something.
function AdoptedTileset.displayName(version)
  local GV = gameVersion()
  local info = GV and GV.info(version) or nil
  return (info and (info.displayName or info.name or info.label))
    or tostring(version or "?"):upper()
end

-- ---------------------------------------------------------------------------
-- reading the other cache
-- ---------------------------------------------------------------------------
--
-- AN ABSOLUTE PATH, OPENED DIRECTLY. This is the only door the mount cannot
-- stand in front of.
--
-- `CacheFs.read` looks right and is not enough: with no portable root -- the
-- ordinary install -- it falls through to `love.filesystem.read(prefix .. rel)`,
-- and for RED the prefix is the empty string, so it asks for
-- `data/generated/maps.lua` on a search path where the RUNNING game's cache is
-- mounted. That returns the mounted game's data. Asking for Red and being handed
-- Crystal is exactly that, and nothing about it looks like an error: the file
-- opened, it parsed, it was full of maps.
function AdoptedTileset.cacheRead(version, rel)
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  local prefix = AdoptedTileset.prefix(version)

  local roots = {}
  if okC and type(CacheFs) == "table" and CacheFs.root then
    local okR, root = pcall(CacheFs.root)
    if okR and type(root) == "string" and root ~= "" then
      roots[#roots + 1] = root
    end
  end
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local okS, dir = pcall(love.filesystem.getSaveDirectory)
    if okS and type(dir) == "string" and dir ~= "" then
      roots[#roots + 1] = dir
    end
  end
  for _, root in ipairs(roots) do
    local path = root .. "/" .. prefix .. rel
    local f = io.open(path, "rb")
    if f then
      local raw = f:read("*a")
      f:close()
      if type(raw) == "string" and #raw > 0 then return raw, path end
    end
  end

  -- Last resort, and only for a NON-EMPTY prefix, where the path names the
  -- version explicitly and the mount cannot be mistaken for it.
  if prefix ~= "" and love and love.filesystem and love.filesystem.read then
    local ok, raw = pcall(love.filesystem.read, prefix .. rel)
    if ok and type(raw) == "string" then return raw, prefix .. rel end
  end
  return nil, prefix .. rel
end

function AdoptedTileset.loadDataset(version, name)
  local raw, path = AdoptedTileset.cacheRead(
    version, "data/generated/" .. name .. ".lua")
  if type(raw) ~= "string" then return nil, path end
  -- Loaded in an EMPTY environment: this is another game's generated data, and
  -- a generated file has no business reaching anything.
  local chunk = load(raw, "@" .. tostring(path), "t", {})
  if type(chunk) ~= "function" then return nil, path end
  local ok, tbl = pcall(chunk)
  if not (ok and type(tbl) == "table") then return nil, path end
  return tbl, path
end

-- Does this version have data we could draw from?
--
-- NOT `RomImporter.isReady`. That answers "is this version ready to PLAY with
-- the current extractor format" -- it checks a format-stamped marker and the
-- full required-file list -- and a dataset written by an older importer fails
-- it while still holding perfectly readable maps. Asking it is why Red, Blue
-- and Yellow were reported as not imported on a machine where they were.
function AdoptedTileset.hasDataset(version)
  local raw = AdoptedTileset.cacheRead(version, "data/generated/maps.lua")
  return type(raw) == "string" and #raw > 0
end

-- ---------------------------------------------------------------------------
-- resolving one
-- ---------------------------------------------------------------------------

-- The tileset record for `name` out of `version`'s cache, with its art path
-- rewritten to point into that cache.
--
-- Returns the record, or nil plus a sentence saying which of the three things
-- was missing -- the game, the tileset, or its art. All three are answerable,
-- and "it did not work" is not an answer anyone can act on.
--
-- THE ART PATH IS CHECKED BEFORE THE RECORD IS HANDED BACK. A tileset
-- registered against a PNG that is not there draws nothing, which is a worse
-- failure than refusing: the map loads, every block is blank, and there is
-- nothing to suggest the cause is a missing import.
-- Build the adopted record from a tileset table already in hand.
--
-- SPLIT FROM `resolve` BECAUSE THE CALLERS DIFFER IN WHAT THEY HAVE, not in
-- what they want. The editor has already opened the source game and holds its
-- tilesets; an exported mod, on someone else's machine, has only a name. Both
-- need the identical record out the other end -- same art-path rewrite, same
-- validation -- and having two places build it is how they drift.
function AdoptedTileset.fromRecord(version, name, src)
  if type(src) ~= "table" or type(src.blocks) ~= "table" then
    return nil, string.format("%s has no tileset called %s",
      AdoptedTileset.displayName(version), tostring(name))
  end

  local copy = {}
  for k, v in pairs(src) do copy[k] = v end
  copy.adopted = true
  copy.adoptedFrom = version
  copy.adoptedName = name

  -- THE ART PATH IS CHECKED BEFORE THE RECORD IS HANDED BACK. A tileset
  -- registered against a PNG that is not there draws nothing, which is a worse
  -- failure than refusing: the map loads, every block is blank, and there is
  -- nothing to suggest the cause is a missing import.
  local prefix = AdoptedTileset.prefix(version)
  if type(src.image) == "string" and prefix ~= "" then
    local path = prefix .. src.image
    local seen = love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo(path, "file")
    if not seen then
      return nil, string.format("%s's art is not readable at %s",
        tostring(name), path)
    end
    copy.image = path
  end
  return copy
end

-- The tileset record for `name` out of `version`'s own cache.
--
-- This is the door an EXPORTED mod comes through: it has a game and a name and
-- nothing else, and the cache it reads is the person-installing-it's.
--
-- Returns the record, or nil plus a sentence saying which of the three things
-- was missing -- the game, the tileset, or its art. All three are answerable,
-- and "it did not work" is not an answer anyone can act on.
function AdoptedTileset.resolve(version, name)
  local tilesets = AdoptedTileset.loadDataset(version, "tilesets")
  if type(tilesets) ~= "table" then
    return nil, string.format("%s has not been imported",
      AdoptedTileset.displayName(version))
  end
  return AdoptedTileset.fromRecord(version, name, tilesets[name])
end

-- ---------------------------------------------------------------------------
-- what a set of edits needs
-- ---------------------------------------------------------------------------

-- Of `versions`, the ones that are not imported here -- each as
-- { version, name } so a caller can name them in a sentence.
--
-- Returns nil when everything is present, so the common case is one `if`.
function AdoptedTileset.missing(versions)
  if type(versions) ~= "table" then return nil end
  local out = {}
  for _, version in ipairs(versions) do
    if version and not AdoptedTileset.hasDataset(version) then
      out[#out + 1] =
        { version = version, name = AdoptedTileset.displayName(version) }
    end
  end
  return out[1] and out or nil
end

-- The sentence a player reads when a mod needs a cartridge they have not
-- imported. One string, built in one place, because it is shown in three --
-- the editor before export, the launcher before install, and the mod's own
-- refusal at load -- and three wordings of the same fact read like three
-- different problems.
-- Join a list of cartridge names the way a sentence would.
local function joinNames(names)
  local parts = {}
  for _, n in ipairs(names) do
    parts[#parts + 1] = type(n) == "table" and (n.name or n.version) or tostring(n)
  end
  if #parts == 0 then return nil end
  if #parts == 1 then return parts[1], 1 end
  if #parts == 2 then return parts[1] .. " and " .. parts[2], 2 end
  return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts], #parts
end

AdoptedTileset.joinNames = joinNames

-- The sentence a player reads when a pack needs a cartridge they have not
-- imported. One string, built in one place, because it is shown in four -- the
-- editor before export, the launcher before install, the importer after one,
-- and the mod's own refusal at load -- and four wordings of the same fact read
-- like four different problems.
--
-- `already` changes the ending and nothing else. After an install "then
-- install this" is not merely redundant, it is wrong: the pack IS installed,
-- and telling someone to do a thing they have just done makes them doubt that
-- it worked.
function AdoptedTileset.requirementText(names, what, already)
  local list, n = joinNames(type(names) == "table" and names or { names })
  if not list then return nil end
  local them = (n and n > 1) and "them" or "it"
  local those = (n and n > 1) and "those games" or "that game"
  if already then
    return string.format(
      "%s uses maps from %s, which %s not imported. Import %s and it will "
      .. "work - nothing here needs reinstalling.",
      what or "This map pack", list, (n and n > 1) and "are" or "is", those)
  end
  return string.format(
    "%s uses maps from %s, and needs %s imported to work. Import %s first, "
    .. "then install this.",
    what or "This map pack", list, them, those)
end

return AdoptedTileset
