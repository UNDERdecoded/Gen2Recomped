-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Living with more than one map pack installed.
--
-- A pack is an ordinary mod -- `ModExport` writes a manifest and a generated
-- main.lua whose MAPS table goes in through `mod.content.maps:patch` -- so two
-- of them editing the same map was never an error. The registry folds both
-- claims in load order and the last one wins, silently, and the only way to
-- find out was to open the map and not recognise it.
--
-- THREE THINGS THIS ADDS, and none of them is a new format:
--
--   * WHICH PACKS ARE INSTALLED, and which maps each one claims. Read from the
--     registry's own provenance rather than by parsing anybody's main.lua: the
--     ops already carry their owner, so this is a question the data can answer
--     without a second source of truth to keep in step.
--   * WHERE THEY OVERLAP, as a list of maps with more than one claimant.
--   * WHICH ONE WINS, per map, stored and reapplied on the next boot.
--
-- REMOVING a pack is `LauncherMods.uninstall` and always was -- the editor
-- simply had no door to it. Uninstalling is what "put the cartridge's own maps
-- back" means: with no pack patching a map, the fold is the base value, which
-- is the ROM's.

local MapPacks = {}

-- The registry that holds map claims, or nil in a session with no mod loader
-- (the tests, and a build packed without one).
local function mapsRegistry(S)
  local mods = S and S.mods
  local content = mods and mods.content
  local reg = content and content.maps
  if type(reg) == "table" and type(reg.claimants) == "function" then
    return reg
  end
  return nil
end

MapPacks.registry = mapsRegistry

-- Every loaded mod that claims at least one map, as
-- { id, name, version, maps = { mapId, ... } }, sorted by id.
--
-- "Map pack" is defined by BEHAVIOUR, not by a manifest field: a mod that
-- patches maps is one for this panel's purposes, whether the editor exported
-- it or somebody wrote it by hand. A field would only be a second thing to
-- get wrong, and it would miss every pack exported before it existed.
function MapPacks.list(S)
  local reg = mapsRegistry(S)
  local byOwner = {}
  if reg then
    for _, id in ipairs(reg.order or {}) do
      for _, owner in ipairs(reg:claimants(id)) do
        local row = byOwner[owner]
        if not row then
          row = { id = owner, maps = {}, active = true }
          byOwner[owner] = row
        end
        row.maps[#row.maps + 1] = id
      end
    end
  end

  -- The launcher's own rows: the name, the version, and -- the part claims
  -- cannot tell you -- whether the pack is switched ON. A pack that is
  -- installed and disabled looks exactly like one that has not loaded yet
  -- from in here, and they want opposite advice.
  local rows = {}
  local okL, LauncherMods = pcall(require, "src.mods.LauncherMods")
  if okL and type(LauncherMods) == "table" and LauncherMods.list then
    local okR, got = pcall(LauncherMods.list)
    if okR and type(got) == "table" then
      for _, m in ipairs(got) do rows[m.id] = m end
    end
  end

  for id in pairs(MapPacks._remembered()) do
    -- Only while it is still on disk: a pack uninstalled outside this editor
    -- must not linger as a row nothing can act on.
    if not byOwner[id] and rows[id] then
      byOwner[id] = { id = id, maps = {}, active = false }
    end
  end

  -- WHAT A PACK SAYS IT HAS, where nothing has loaded to prove it.
  --
  -- A pack replacing an earlier version of itself is the case that made this
  -- necessary: the registry still holds the OLD version's claims, so the
  -- dialog showed the previous contents of a pack that had just been replaced,
  -- with nothing to say they were stale. The manifest's own list is read
  -- without running anything, so it describes what is ON DISK now.
  --
  -- The registry still wins wherever it has an answer -- what a mod actually
  -- patched beats what it said it would.
  for id, row in pairs(byOwner) do
    local declared = rows[id] and rows[id].maps
    if type(declared) == "table" and declared[1] then
      row.declared = declared
      if not row.active then
        local copy = {}
        for _, mapId in ipairs(declared) do copy[#copy + 1] = mapId end
        row.maps = copy
      end
    end
  end

  local out = {}
  for owner, row in pairs(byOwner) do
    local m = rows[owner]
    row.name = (m and m.name) or owner
    row.version = m and m.version or nil
    -- Absent from the launcher's list means the folder is gone; treat that as
    -- disabled rather than claiming an enabled state we did not read.
    row.enabled = m and (m.enabled == true) or false
    row.installed = m ~= nil
    -- WHY IT IS NOT PATCHING, when it is installed and switched on.
    --
    -- A pack that declares a cartridge the reader has not imported LOADS and
    -- then declines, so it claims nothing -- which is indistinguishable, from
    -- claims alone, from a pack that has not loaded yet. The panel said
    -- "restart the game to load it" to somebody who had restarted a dozen
    -- times, because the advice was inferred from silence rather than read
    -- from the row that knew.
    row.missingGames = m and m.missingGames or nil
    table.sort(row.maps)
    out[#out + 1] = row
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- Maps claimed by more than one pack: { { map, owners = { id, ... },
-- winner = id or nil }, ... }, sorted by map id.
function MapPacks.conflicts(S)
  local reg = mapsRegistry(S)
  if not reg then return {} end
  local raw = reg:conflicts()
  if not raw then return {} end
  local out = {}
  for id, owners in pairs(raw) do
    out[#out + 1] = { map = id, owners = owners,
                      winner = reg:preferredOwner(id) }
  end
  table.sort(out, function(a, b) return a.map < b.map end)
  return out
end

-- ------------------------------------------------------------- the choice
--
-- STORED IN options.lua, beside the enabled-mod list, because that is the file
-- that already answers "what should the next boot do about mods". The edit
-- store would be the wrong home: it is per-game map data that travels inside
-- an exported pack, and a choice BETWEEN packs is not part of any of them.
local WINS_KEY = "mapPackWins"

local function options()
  local okS, SaveData = pcall(require, "src.core.SaveData")
  if not (okS and SaveData and SaveData.loadOptions) then return nil, nil end
  local fs = love and love.filesystem
  local ok, opts = pcall(SaveData.loadOptions, fs)
  if not (ok and type(opts) == "table") then return nil, SaveData end
  return opts, SaveData
end

-- ------------------------------------------------- packs we know about
--
-- WHY A REMEMBERED LIST AT ALL, when the registry knows who patched what.
--
-- It knows who patched what THIS SESSION. A pack installed a moment ago has
-- not loaded -- the mod set is built once at editor start and once per game
-- boot -- so it claims nothing, and a list built from claims alone showed
-- "no map pack is patching any map" directly under "installed X". Worse, the
-- pack could not then be REMOVED from here, because removal needs a row and
-- there was no row.
--
-- So an install is recorded, and the list below is the union: what is
-- actually patching, plus what is installed and waiting for a restart.
local PACKS_KEY = "mapPacks"

function MapPacks.remember(id)
  if type(id) ~= "string" or id == "" then return end
  local opts, SaveData = options()
  if not (opts and SaveData) then return end
  opts[PACKS_KEY] = type(opts[PACKS_KEY]) == "table" and opts[PACKS_KEY] or {}
  if opts[PACKS_KEY][id] then return end
  opts[PACKS_KEY][id] = true
  pcall(SaveData.saveOptions, opts, love and love.filesystem)
end

-- On the module rather than a local, because `MapPacks.list` is defined
-- ABOVE this and a local would not be in scope there. A field lookup is
-- resolved when it is called, which is what makes the order stop mattering.
function MapPacks._remembered()
  local opts = options()
  local set = opts and opts[PACKS_KEY]
  return type(set) == "table" and set or {}
end

function MapPacks.storedChoices()
  local opts = options()
  local wins = opts and opts[WINS_KEY]
  return type(wins) == "table" and wins or {}
end

-- Choose the pack that owns `mapId`, or pass nil to go back to load order.
--
-- Three things move together and all three have to, or the editor shows one
-- answer and the game gives another: the registry's preference, the merged
-- table the panels draw from, and the options file the next boot reads.
function MapPacks.prefer(S, mapId, owner)
  local reg = mapsRegistry(S)
  if not reg then return false, "no mod registry in this session" end
  reg:preferOwner(mapId, owner)

  -- The merged table, for this one id. The loader writes every id at the end
  -- of a load; re-running that for one changed map would rebuild the world.
  local data = S and S.data
  if data and type(data.maps) == "table" then
    data.maps[mapId] = reg:get(mapId)
  end
  -- The map the editor is looking at may BE this one, and its cached mesh and
  -- tileset are built from the def that just changed.
  pcall(function() require("src.world.MapLoader").evict(mapId) end)

  local opts, SaveData = options()
  if not (opts and SaveData) then return true end
  opts[WINS_KEY] = type(opts[WINS_KEY]) == "table" and opts[WINS_KEY] or {}
  opts[WINS_KEY][mapId] = owner
  pcall(SaveData.saveOptions, opts, love and love.filesystem)
  return true
end

-- Uninstall a pack outright. The maps it claimed fall back to whatever is
-- left underneath -- another pack, or the cartridge.
--
-- The stored choices naming it are dropped in the same breath: a preference
-- for a pack that is gone is a line that can never be satisfied and would sit
-- in options.lua forever, quietly excluding whoever is left.
function MapPacks.remove(S, modId)
  local okL, LauncherMods = pcall(require, "src.mods.LauncherMods")
  if not (okL and type(LauncherMods) == "table" and LauncherMods.uninstall) then
    return false, "this build has no mod installer"
  end
  local ok, deleted, why = pcall(LauncherMods.uninstall, modId)
  if not ok then return false, tostring(deleted) end
  if not deleted then return false, tostring(why or "it could not be removed") end

  local opts, SaveData = options()
  if opts and SaveData and type(opts[PACKS_KEY]) == "table" then
    opts[PACKS_KEY][modId] = nil
    pcall(SaveData.saveOptions, opts, love and love.filesystem)
  end
  if opts and SaveData and type(opts[WINS_KEY]) == "table" then
    local changed = false
    for mapId, owner in pairs(opts[WINS_KEY]) do
      if owner == modId then opts[WINS_KEY][mapId] = nil; changed = true end
    end
    if changed then
      pcall(SaveData.saveOptions, opts, love and love.filesystem)
    end
  end
  return true
end

-- ------------------------------------------------------------ adding one
--
-- WHY THIS LIVES HERE AND NOT IN THE PANEL. There are two pickers with nothing
-- in common but their purpose.
--
-- `RomImporter.chooseFileByExt` is a NATIVE MODAL -- osascript, PowerShell,
-- zenity -- which blocks and returns a path. On any platform it does not know
-- it falls off the end of its if-chain and returns nil, which is what the
-- editor's IMPORT did on Android: opened nothing, waited for nothing, and
-- reported "no file chosen" for a file nobody was offered.
--
-- The mobile picker cannot work that way at all. It is a separate activity
-- (Android SAF) or a sheet (iOS), the app loses focus, and the pick lands in
-- the save directory seconds later. So `beginAdd` STARTS something and
-- `consumePending` finishes it -- the same two-part shape the launcher's own
-- mod import has always had.
--
-- `picked_mod.zip` is reused rather than a name of this feature's own because
-- the destination basename is chosen natively from a fixed set of kinds
-- (love.system.pickFile); adding one means touching the vendored LÖVE tree.
-- It is consumed and deleted the moment it lands, and the launcher is not
-- polling while the editor is up.
local PICK_FILE = "picked_mod.zip"

local function installer()
  local ok, ModImport = pcall(require, "tools.map-editor.ModImport")
  if ok and type(ModImport) == "table" and ModImport.install then
    return ModImport
  end
  return nil
end

local function asyncPicker()
  local os_ = love.system and love.system.getOS and love.system.getOS()
  return (os_ == "Android" or os_ == "iOS") and love.system.pickFile ~= nil
end

-- Shared tail: raise the requirements dialog on success, and say so either
-- way. The panel and the poll both land here so one install cannot report
-- differently from the other.
function MapPacks.finish(S, result, why)
  if result then
    local okIP, ImportPrompt =
      pcall(require, "tools.map-editor.panels.ImportPrompt")
    if okIP and type(ImportPrompt) == "table" then
      ImportPrompt.raise(S, result)
    end
    MapPacks.remember(result.id)
    -- BEFORE the list below is asked anything: the cached rows predate this
    -- install and would not contain the pack that was just added.
    S.packsCache, S.packsConflicts = nil, nil
    -- WHO ELSE CLAIMS THESE MAPS, said at install time rather than after the
    -- restart. The manifest lists what the new pack contains and the other
    -- packs' lists are readable the same way, so the overlap is answerable now
    -- -- which is when the reader can still decide not to install it.
    local clash = {}
    do
      local rows = MapPacks.list(S)
      local mine = nil
      for _, row in ipairs(rows) do
        if row.id == result.id then mine = row.maps end
      end
      if mine and mine[1] then
        local want = {}
        for _, mapId in ipairs(mine) do want[mapId] = true end
        for _, row in ipairs(rows) do
          if row.id ~= result.id then
            for _, mapId in ipairs(row.maps) do
              if want[mapId] then clash[mapId] = true end
            end
          end
        end
      end
    end
    local overlaps = 0
    for _ in pairs(clash) do overlaps = overlaps + 1 end
    -- The mod set is built once per boot, so a pack installed now patches
    -- nothing until the game is restarted. Saying so here is the difference
    -- between "it worked" and "it worked and nothing happened".
    S.packsNotice = "installed " .. tostring(result.id)
      .. " - restart the game to load it"
      .. (overlaps > 0
          and string.format("  (%d map%s also in another pack - pick a winner "
                            .. "here after the restart)", overlaps,
                            overlaps == 1 and "" or "s")
          or "")
  else
    S.packsNotice = "import failed: " .. tostring(why)
  end
  S.pvNotice, S.status = S.packsNotice, S.packsNotice
  pcall(function()
    require("src.core.Logger")[result and "info" or "warn"](
      "%s", tostring(S.packsNotice))
  end)
  return result ~= nil
end

-- Open whichever picker this platform has. Returns false when none opened.
function MapPacks.beginAdd(S)
  local ModImport = installer()
  if not ModImport then
    S.packsNotice = "this build has no map pack installer"
    return false
  end
  if asyncPicker() then
    if love.system.pickFile("mod") then
      S.mapPackPending = true
      S.packsNotice = "choose the pack .zip -- it installs when you come back"
      return true
    end
    S.packsNotice = "could not open the file picker"
    return false
  end
  local okR, RomImporter = pcall(require, "src.import.RomImporter")
  local pick = nil
  if okR and type(RomImporter) == "table" and RomImporter.chooseFileByExt then
    local okP, got = pcall(RomImporter.chooseFileByExt, { "zip" }, "map pack")
    pick = okP and got or nil
  end
  if not pick then
    S.packsNotice = "no file chosen - a map pack is the .zip EXPORT writes"
    return false
  end
  return MapPacks.finish(S, ModImport.install(pick))
end

-- Called every frame while a mobile pick is outstanding.
function MapPacks.consumePending(S)
  if not (S and S.mapPackPending) then return end
  local info = love.filesystem.getInfo
  if not (info and info(PICK_FILE, "file")) then return end
  S.mapPackPending = nil
  local ModImport = installer()
  if not ModImport then
    love.filesystem.remove(PICK_FILE)
    S.packsNotice = "this build has no map pack installer"
    return
  end
  local ok, result, why = pcall(ModImport.install, PICK_FILE)
  -- Removed either way: a pick left in the save dir is consumed by whichever
  -- poll runs next, so a failed import would reappear as a mod install the
  -- moment the launcher came back up.
  love.filesystem.remove(PICK_FILE)
  if not ok then return MapPacks.finish(S, nil, result) end
  return MapPacks.finish(S, result, why)
end

return MapPacks
