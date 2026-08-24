-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Put one map back the way the cartridge had it.
--
-- WHY THIS IS NOT `undo` IN A LOOP. Undo walks back through the states this
-- session produced; it cannot reach past the frame the editor opened, and a map
-- edited last week is already at its starting point as far as the stack is
-- concerned. Reset is about the CARTRIDGE's version, which is a different
-- question with a different answer.
--
-- WHY IT IS NOT JUST "DROP THE EDIT BUCKET". Dropping the patches fixes what
-- the NEXT launch builds and leaves this session's map exactly as it was: the
-- tile painter writes `def.blocks` in place, adding an NPC appends to
-- `def.objects`, and `Data:load` laid every stored patch onto the live def at
-- boot. So the live def is not "the original plus a store" -- it IS the edited
-- map, and there is nothing left in memory to subtract the edits from.
--
-- SO THE ORIGINAL IS RE-READ FROM DISK. `require("data.generated.maps")` is no
-- use: `package.loaded` holds the very table that was mutated. `love.filesystem
-- .load` goes to the file, which is the extractor's output and has never been
-- touched by the editor -- the whole point of the patch-store design. That is
-- the same escape hatch `Data.seedMissingGen2Tilesets` uses to read a sibling
-- version's tilesets without disturbing the loaded one.
--
-- A SESSION SNAPSHOT IS THE FALLBACK, not the primary: it is only as old as the
-- moment this editor first drew the map, so on a map edited in a previous
-- session it restores to "how it looked when I opened it", which is not what
-- the button says. Used only when the file cannot be read, and it says so.

local MapEdits = require("tools.map-editor.MapEdits")

local MapReset = {}

-- Where the extractor's own maps table lives, under whatever prefix this
-- version's cache is mounted at. Both spellings are tried because a portable
-- install writes into the game folder and a normal one into the save
-- directory, and `love.filesystem` searches both.
MapReset.SOURCES = { "data/generated/maps.lua" }

local pristineCache = nil

-- The unedited maps table, read from the file rather than from `package.loaded`.
--
-- Cached for the session: it is a few hundred kilobytes of Lua and a reset is
-- not a per-frame operation, but reading it once per press on a big map would
-- be a visible stall.
function MapReset.pristine()
  if pristineCache ~= nil then return pristineCache or nil end
  pristineCache = false
  if not (love and love.filesystem and love.filesystem.load) then return nil end
  for _, path in ipairs(MapReset.SOURCES) do
    local info = love.filesystem.getInfo and love.filesystem.getInfo(path, "file")
    if info then
      local chunk = love.filesystem.load(path)
      if chunk then
        local ok, maps = pcall(chunk)
        if ok and type(maps) == "table" then
          pristineCache = maps
          return maps
        end
      end
    end
  end
  return nil
end

-- Drop the cache, for a re-import: the file underneath has been rewritten and
-- a reset against the old one would restore a map that no longer exists.
function MapReset.forget()
  pristineCache = nil
end

-- REMEMBER HOW A MAP LOOKED WHEN IT WAS FIRST DRAWN.
--
-- Called from the preview each time a map is opened. Only the two arrays the
-- editor mutates in place are kept, and only for maps not already remembered --
-- copying a hundred maps' block arrays would cost more than the feature.
function MapReset.remember(S, mapId, def)
  if not (S and mapId and type(def) == "table") then return false end
  S._resetSnaps = S._resetSnaps or {}
  if S._resetSnaps[mapId] then return false end
  local snap = { blocks = nil, objects = nil, warps = nil }
  if type(def.blocks) == "table" then
    local b = {}
    for i, v in ipairs(def.blocks) do b[i] = v end
    snap.blocks = b
  end
  local function copyList(list)
    if type(list) ~= "table" then return nil end
    local out = {}
    for i, rec in ipairs(list) do
      local c = {}
      for k, v in pairs(rec) do c[k] = v end
      out[i] = c
    end
    return out
  end
  snap.objects = copyList(def.objects)
  snap.warps = copyList(def.warps)
  S._resetSnaps[mapId] = snap
  return true
end

-- What a reset would throw away, so the confirmation can say it rather than
-- asking "are you sure?" about an unnamed quantity.
function MapReset.describe(store, game, mapId)
  local n = MapEdits.count and MapEdits.count(store, game, mapId) or 0
  return n
end

-- Is this a map the cartridge ever had?
--
-- An editor-created map has no original to go back to, and silently deleting it
-- under a button called RESET would be the worst possible reading. Refused,
-- with the thing they probably meant.
function MapReset.isEditorMap(S, mapId)
  local def = S and S.data and S.data.maps and S.data.maps[mapId or ""]
  return (def and def.editorCreated) == true
end

-- Put `mapId` back. Returns a report, or nil and a reason.
function MapReset.reset(S, mapId)
  mapId = mapId or (S and S.mapId)
  if not (S and mapId) then return nil, "no map open" end
  if MapReset.isEditorMap(S, mapId) then
    return nil, mapId .. " was created here; it has no cartridge original - "
      .. "use DELETE THIS MAP in the warp tool instead"
  end
  local def = S.data and S.data.maps and S.data.maps[mapId]
  if not def then return nil, "that map is not in this import" end

  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  local game = tostring(S.version or v or "unknown")

  local dropped = MapReset.describe(store, game, mapId)

  -- THE STORE FIRST. Everything below rebuilds the live def, and rebuilding it
  -- while the patches are still there would have `applyAll` lay them straight
  -- back on.
  local g = store.games and store.games[game]
  if g and g.maps then g.maps[mapId] = nil end

  -- THE LIVE DEF, from the file where possible.
  local how = nil
  local src = MapReset.pristine()
  local base = src and src[mapId] or nil
  if type(base) == "table" then
    -- Only the fields the editor can change. Replacing the whole def would
    -- also drop what `Data:load` seeded onto it after the read -- aliases, the
    -- id, connection back-references -- and a map missing those does not load.
    if type(base.blocks) == "table" then
      local b = {}
      for i, val in ipairs(base.blocks) do b[i] = val end
      def.blocks = b
    end
    local function restoreList(list)
      if type(list) ~= "table" then return nil end
      local out = {}
      for i, rec in ipairs(list) do
        local c = {}
        for k, val in pairs(rec) do c[k] = val end
        out[i] = c
      end
      return out
    end
    if base.objects then def.objects = restoreList(base.objects) end
    if base.warps then def.warps = restoreList(base.warps) end
    if base.borderBlock ~= nil then def.borderBlock = base.borderBlock end
    how = "cartridge"
  else
    local snap = S._resetSnaps and S._resetSnaps[mapId]
    if not snap then
      return nil, "could not read the original: data/generated/maps.lua is "
        .. "not readable and this map was not snapshotted"
    end
    if snap.blocks then
      local b = {}
      for i, val in ipairs(snap.blocks) do b[i] = val end
      def.blocks = b
    end
    if snap.objects then def.objects = snap.objects end
    if snap.warps then def.warps = snap.warps end
    how = "session"
  end

  -- THE OVERLAYS THE VOXEL PATH READS BY REFERENCE. `publishVoxels` assigns the
  -- live bucket onto the def, so with the bucket gone these are pointing at a
  -- table that is no longer anybody's -- and the mod resolves shapes from them
  -- every frame.
  def.voxelEdits, def.voxelTileEdits, def.voxelClassPins = nil, nil, nil

  -- and every cache that would otherwise answer with the edited world
  pcall(function() require("src.world.MapLoader").evict(mapId) end)
  pcall(function()
    require("tools.map-editor.ModShapes").invalidate(mapId)
  end)
  S.pv3D, S.pv3DKey = nil, nil
  S.voxClasses, S.voxClassesFor, S.pvClassesFor = nil, nil, nil
  S.pvSel, S.pvCell = nil, nil
  S._pvCenteredFor = nil
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return { dropped = dropped, how = how }
end

return MapReset
