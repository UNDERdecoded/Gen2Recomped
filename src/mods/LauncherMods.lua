-- Launcher-side mod surface (18/launcher redesign): the mods panel runs
-- BEFORE Game:load, so this NEVER loads a mod entry chunk -- it scans
-- manifests only.  The full loader (src/mods/Loader.lua) still owns the real
-- load at boot; this reads the same options.mods enable-state the loader
-- writes, derives per-mod status with the pure ManagerState.resolveToggle,
-- installs a dropped/chosen .zip into a "mods/<id>/" tree, and uninstalls a
-- mod by removing that tree + clearing options.mods[id].
--
-- Where that tree lives is CacheFs's call, not love.filesystem's: a portable
-- install (portable.txt beside the executable) keeps its mods in the game
-- folder like everything else it owns, and only the OS save directory
-- otherwise (#330 -- love.filesystem.write always resolves to the save dir,
-- so the installer used to strand every mod in appdata).  Reads stay on
-- love.filesystem: the portable folder is on the physfs read path either way
-- (it IS the source for a `love <gamedir>` run, and CacheFs mounts it for a
-- fused build), which is why those mods still loaded while landing in the
-- wrong place.
--
-- The same split decides where a mod is FOUND, and that has a sharp edge: a
-- non-portable install never reads the game folder at all, so a mod unzipped
-- next to the executable -- where most games would want it -- is not wrong so
-- much as invisible, with an empty panel and no error to explain it.
-- adoptStrays looks in those folders anyway (a scoped mount that comes down
-- again, CacheFs.withMounted) and copies what it finds into the tree the game
-- really reads, so the mistake costs a line of notice rather than a support
-- thread.
--
-- Split in two: the pure derivation (deriveList, locateRoot, pickStrays) has
-- no love and no filesystem, so the engine tier can table-drive it; the
-- discovery, install, uninstall, and stray-scan paths reach for
-- love.filesystem and SaveData.

local Manifest = require("src.mods.Manifest")
local ManagerState = require("src.mods.ManagerState")
local ModGens = require("src.mods.ModGens")
local Semver = require("src.mods.Semver")
local Version = require("src.core.Version")
local SaveData = require("src.core.SaveData")
local CacheFs = require("src.import.CacheFs")

local LauncherMods = {}

-- ------- pure status derivation

-- A hard-dependency / conflict / version verdict for one manifest.  mods is
-- the id -> validated-manifest map resolveToggle reads (its dependencySpecs,
-- conflictSpecs, version and game_version are exactly the fields the loader's
-- Manifest.validate produced); enabledSet is the current desired enable-set.
local function statusFor(mods, id, enabledSet, enabled)
  local m = mods[id]
  -- conflict only bites an enabled mod: resolveToggle's conflict list is
  -- bidirectional (this mod's conflicts spec vs an enabled other, and an
  -- enabled other's spec vs this mod), which is exactly the launcher chip.
  if enabled then
    local r = ManagerState.resolveToggle(mods, id, true, enabledSet)
    if #r.conflicts > 0 then
      local otherId = r.conflicts[1]
      local other = mods[otherId]
      return "conflict",
        "Conflicts with " .. ((other and other.name) or otherId)
    end
  end
  -- warn: the engine is outside the mod's game_version range
  if m.game_version
      and not Semver.satisfies(Version.engine, m.game_version) then
    return "warn", "Needs engine " .. m.game_version
      .. " (have " .. Version.engine .. ")"
  end
  -- warn: a hard dependency is absent, switched off, or the wrong version.
  -- resolveToggle would cascade-enable a merely-disabled dep rather than flag
  -- it, so the disabled case is judged straight off the manifest here.
  for _, spec in ipairs(m.dependencySpecs or {}) do
    local dep = mods[spec.id]
    if not dep then
      return "warn", "Needs " .. spec.id .. " (not installed)"
    elseif not enabledSet[spec.id] then
      return "warn", "Needs " .. spec.id .. " (disabled)"
    elseif spec.range
        and not Semver.satisfies(dep.version, spec.range) then
      return "warn", "Needs " .. spec.id .. " " .. spec.range
    end
  end
  return "ok", "Ready"
end

-- deriveList(manifests, options) -> the panel row list, pure.
-- manifests is an array of validated manifests (Manifest.validate output);
-- options is the options table (only options.mods is read).  Rows come back
-- sorted by id so the panel order is stable.
function LauncherMods.deriveList(manifests, options)
  local mods = options and options.mods or {}
  local ordered = {}
  for _, m in ipairs(manifests) do ordered[#ordered + 1] = m end
  table.sort(ordered, function(a, b) return a.id < b.id end)

  local byId, enabledSet, genSet, forceSet = {}, {}, {}, {}
  for _, m in ipairs(ordered) do
    byId[m.id] = m
    -- THE MASTER SWITCH, which is the one the dependency and conflict
    -- resolution below asks about.  A mod narrowed to one generation is still
    -- "on" for that purpose: two mods that conflict conflict wherever they
    -- both run, and answering per generation here would need the panel to
    -- know which game the player is about to start -- which it does not.
    -- The chips are carried alongside so the row can draw them.
    local on = ModGens.active(mods[m.id], nil)
    if on == nil then on = not m.experimental end
    if on then enabledSet[m.id] = true end
    genSet[m.id] = ModGens.gensOf(mods[m.id])
    forceSet[m.id] = ModGens.forcedOf(mods[m.id])
  end

  local out = {}
  for _, m in ipairs(ordered) do
    local enabled = enabledSet[m.id] == true
    local status, detail = statusFor(byId, m.id, enabledSet, enabled)
    local raw = m.raw or {}
    local badge = tostring(raw.category or m.profile or "MOD"):upper()
    if m.experimental then badge = "EXPERIMENTAL" end
    -- A mod whose declared base file is missing is installed and enabled but
    -- cannot do anything; the row carries that so the panel can offer IMPORT
    -- instead of leaving the player to guess (see src/mods/ModImports.lua).
    local ModImports = require("src.mods.ModImports")
    -- A base file the player already gave another mod satisfies this one too
    -- (see ModImports' shared store); do that before asking what is missing,
    -- so a second Stadium 2 mod is simply ready.
    ModImports.adoptShared(m)
    local needs = ModImports.missing(m)
    out[#out + 1] = {
      id = m.id,
      name = m.name or m.id,
      requiredImports = ModImports.of(m),
      missingImports = needs,
      -- A DIFFERENT KIND OF MISSING. `missingImports` is a FILE the player has
      -- to hand over; this is a CARTRIDGE THEY HAVE TO HAVE IMPORTED, which
      -- needs nothing handed over and cannot be satisfied by dropping a file
      -- into the mod folder.
      --
      -- A map pack exported from the map editor is the case: it carries maps
      -- copied out of another game and references that game's tilesets rather
      -- than shipping them, so it is inert -- and worse than inert, it asserts
      -- in MapLoader -- until the player has imported that game themselves.
      -- The row carries it so the panel can say which game and offer to go
      -- import it, instead of the player installing a map pack that crashes.
      requiredGames = m.requiredGames,
      -- Declared map ids, for a panel that has to describe a pack BEFORE it
      -- has loaded and can be asked. nil on anything exported before the
      -- field existed.
      maps = m.maps,
      missingGames = (function()
        if not (m.requiredGames and m.requiredGames[1]) then return nil end
        local okA, AT = pcall(require, "src.import.AdoptedTileset")
        if not okA then return nil end
        local want = {}
        for _, row in ipairs(m.requiredGames) do want[#want + 1] = row.version end
        return AT.missing(want)
      end)(),
      manifestPath = m.path,
      -- The FILE the mod declares its options in, carried through so the
      -- launcher can offer those options without loading the mod. Mods have
      -- been able to declare options since the loader gained options:define,
      -- and nothing has ever rendered them -- a mod could ship 40 settings and
      -- the player had no way to reach one.
      optionsSchema = m.options_schema,
      version = m.version,
      badge = badge,
      description = m.description or "",
      enabled = enabled,
      -- Which generations this mod reaches while it is on (see ModGens).  All
      -- three unless the player has said otherwise, so a row that has never
      -- been touched draws three lit chips and behaves exactly as it used to.
      gens = genSet[m.id] or { true, true, true },
      -- The generations the MOD says it works in, so the card can show a chip
      -- the player cannot usefully turn on (see ModGens.supported).  nil on
      -- every mod that declares nothing, which is every mod predating it.
      supportedGens = m.generations,
      -- ...and the generations the player has overruled that claim for, so a
      -- chip the mod says it cannot fill can still be drawn as one the player
      -- deliberately lit (see ModGens.forced).  All false on every row nobody
      -- has overruled, which is nearly all of them.
      forcedGens = forceSet[m.id],
      status = status,
      statusDetail = detail,
      github = m.github,
      -- the creator's donation link, for the card's "Support the creator"
      -- button (Manifest.validate accepts http(s) only)
      support = m.support,
      updateCheck = m.updateCheck ~= false,
      experimental = m.experimental == true,
    }
  end
  return out
end

-- The option rows a mod declares, or nil when it declares none.
--
-- The IN-GAME mod manager already renders these (ManagerState:schemaFor and
-- buildOptionRows) -- this is the same schema read from the launcher, so the
-- settings can be reached without booting a game first. The two must agree:
-- the row types accepted here are the ones OPTION_TYPES accepts there, or a
-- mod's option would exist in one place and not the other.
--
-- Read from the DECLARED FILE rather than by running the mod: the launcher
-- must never execute mod entry code (that is the whole reason discover()
-- validates manifests and loads no chunks), and the schema file is data --
-- every shipped one is a bare `return { ... }`. ManagerState can read the
-- loader's captured schema instead because by then the mod has run; in the
-- launcher nothing has, and nothing should.
--
-- It is still Lua, so it is loaded with an EMPTY environment: a schema file
-- that tries to do anything other than return a table has nothing to do it
-- with. A malformed one returns nil and the mod simply shows no options, which
-- is what it looked like before this existed.
--
-- The environment is installed with setfenv rather than load()'s fourth
-- argument. This runs on LuaJIT, where `load` is the 5.1 two-argument form
-- unless the build opted into 5.2 compatibility -- passing a mode and an env
-- there is not an error, it is two ignored arguments, and the schema would
-- have been compiled against the real globals while this comment claimed
-- otherwise. setfenv is the 5.1 spelling and is what LuaJIT actually has.
local function loadSandboxed(src, name)
  local compile = loadstring or load
  local chunk, err = compile(src, name)
  if not chunk then return nil, err end
  if setfenv then setfenv(chunk, {}) end
  return chunk
end

-- The row types a mod may declare. `text` is listed because ManagerState
-- accepts it and dropping it here would hide the option entirely; the
-- launcher shows it read-only rather than pretending it is not there (its
-- editor is a keyboard applet the settings panel does not have).
--
-- `action` is the ONE deliberate divergence from ManagerState's OPTION_TYPES.
-- An action row is a button whose press is delivered to the mod as an event,
-- and out here no mod has run: there is nothing listening and nothing the
-- press could reach. A row that draws as a button and does nothing when
-- pressed is worse than a row that is not there, so the launcher omits them
-- and the in-game manager -- where the mod is live -- is where they appear.
LauncherMods.OPTION_TYPES = {
  toggle = true, choice = true, number = true, text = true,
}

function LauncherMods.optionRows(row)
  if not (row and row.optionsSchema and row.manifestPath) then return nil end
  local fs = love and love.filesystem
  if not (fs and fs.read) then return nil end
  local src = fs.read(row.manifestPath .. "/" .. row.optionsSchema)
  if not src then return nil end
  local chunk = loadSandboxed(src, "@" .. row.id .. "/options")
  if not chunk then return nil end
  local ok, rows = pcall(chunk)
  if not (ok and type(rows) == "table") then return nil end
  local out = {}
  for _, r in ipairs(rows) do
    -- A row with no key cannot be stored and a row of an unknown type cannot
    -- be drawn; both are dropped rather than rendered as a control that does
    -- nothing when pressed. The accepted set mirrors ManagerState's
    -- OPTION_TYPES apart from `action` (see above) -- `number` and `text`
    -- were missing here at first, which would have hidden two kinds of option
    -- from the launcher that the in-game manager shows, and left the player
    -- to conclude the launcher was showing them a partial list without ever
    -- saying so.
    if type(r) == "table" and type(r.key) == "string" and r.key ~= ""
       and LauncherMods.OPTION_TYPES[r.type] then
      out[#out + 1] = r
    end
  end
  if #out == 0 then return nil end
  return out
end

-- Current value of one mod option: the stored one, else the schema's default.
-- Same precedence the loader's own options:get and ManagerState:optionValue
-- use, so what the launcher shows is what the mod will read.
--
-- The `~= nil` tests are not decoration. `stored[key] or row.default` reads a
-- stored `false` as unset and hands back the default forever -- so a toggle
-- the player turned OFF would come back ON every time they looked at it, and
-- nothing about that looks like a bug in a boolean read.
function LauncherMods.optionValue(options, modId, row)
  local stored = options and options.modOptions and options.modOptions[modId]
  if stored ~= nil and stored[row.key] ~= nil then return stored[row.key] end
  return row.default
end

-- Write one mod option into the options table IN PLACE. The caller saves --
-- saveOptions rewrites the whole file per call, and a settings panel steps
-- one row at a time.
function LauncherMods.setOptionValue(options, modId, key, value)
  options.modOptions = options.modOptions or {}
  options.modOptions[modId] = options.modOptions[modId] or {}
  options.modOptions[modId][key] = value
  return options
end

-- locateRoot(paths) -> the mod-root prefix inside a mounted archive, pure.
-- paths is a shallow listing: top-level file names as-is, and for a top-level
-- directory a "<dir>/manifest.json" entry when it holds one.  Returns "" when
-- the manifest sits at the archive root, "<dir>" when a single top-level
-- folder holds it, or nil + a user-presentable reason.
function LauncherMods.locateRoot(paths)
  for _, p in ipairs(paths) do
    if p == "manifest.json" then return "" end
  end
  local topDirs, seen, hasManifest = {}, {}, {}
  for _, p in ipairs(paths) do
    local top, rest = p:match("^([^/]+)/(.+)$")
    if top then
      if not seen[top] then
        seen[top] = true
        topDirs[#topDirs + 1] = top
      end
      if rest == "manifest.json" then hasManifest[top] = true end
    end
  end
  if #topDirs == 1 and hasManifest[topDirs[1]] then return topDirs[1] end
  if #topDirs > 1 then
    return nil, "the .zip must contain a single mod folder"
  end
  return nil, "no manifest.json found in the .zip"
end

-- pickStrays(found, installed) -> the rows worth adopting, pure.
-- found is an array of { id, name, folder, path } in scan order (game folder
-- order, then directory order); installed is the id -> true set of what the
-- game can already see.  An installed id is dropped -- the player has a
-- working copy and the loose folder is just where they first put it -- and a
-- duplicate id across two game folders keeps the first, the same first-wins
-- rule discover() uses.  Sorted by id so the notice reads the same every time.
function LauncherMods.pickStrays(found, installed)
  installed = installed or {}
  local out, seen = {}, {}
  for _, row in ipairs(found or {}) do
    local id = row.id
    if id and not installed[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = { id = id, name = row.name or id,
                        folder = row.folder, path = row.path }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- isReadableRoot(folder, source, cacheRoot) -> is folder already on the
-- physfs read path, pure.  source is love.filesystem.getSource(), cacheRoot
-- the mounted portable game folder (CacheFs.root()); a fused build has both,
-- and they are different paths (the archive inside the executable vs the
-- folder beside it).  Either one's mods/ is readable already, so nothing in
-- it is a stray -- and the portable folder must additionally never be handed
-- to CacheFs.withMounted: PHYSFS_mount reports success for a directory
-- already in the search path WITHOUT adding a second entry, so the paired
-- unmount tears down the one real mount and the panel loses every mod in the
-- game folder (#413).
function LauncherMods.isReadableRoot(folder, source, cacheRoot)
  if not folder or folder == "" then return false end
  return folder == source or folder == cacheRoot
end

-- ------- discovery (love.filesystem)

local function decodeManifest(raw, path)
  local Json = require("src.link.Json")
  local data, decodeErr = Json.decode(raw)
  if not data then return nil, decodeErr end
  local ok, manifest = pcall(Manifest.validate, data, path)
  if not ok then return nil, manifest end
  return manifest
end

-- The root a mod must be inside to count, or nil when every home counts.
--
-- Only a CUSTOM folder confines: portable mode's game folder has always been
-- one of several legitimate homes (a mod dropped beside the executable, a dev
-- checkout in the source's own mods/), and narrowing those would hide mods
-- nobody moved and nobody asked to move.
function LauncherMods.confinedRoot()
  local ok, report = pcall(CacheFs.rootReport)
  if ok and type(report) == "table" and report.kind == "custom" then
    return report.path
  end
  return nil
end

-- Is this love.filesystem path a real entry under `root`?  Asked with io.*
-- against the real path, because love.filesystem is exactly the thing that
-- cannot tell one home from another.
function LauncherMods.underRoot(root, path)
  if not (root and path) then return false end
  local real = LauncherMods.realPath(root, path)
  local handle = io.open(real .. CacheFs.SEP .. "manifest.json", "rb")
  if handle then handle:close() return true end
  -- a folder with no manifest is not a mod anyway, but answer honestly for
  -- anything else that asks
  handle = io.open(real, "rb")
  if handle then handle:close() return true end
  return false
end

-- The mods sitting in a home that is no longer the one in use: their folder
-- names, for a line on the panel telling the player they exist and how to
-- bring them over.  Empty when nothing is confined.
function LauncherMods.strandedMods()
  local fs = love and love.filesystem
  local root = LauncherMods.confinedRoot()
  if not (fs and root and fs.getInfo("mods")) then return {} end
  local out = {}
  for _, name in ipairs(fs.getDirectoryItems("mods") or {}) do
    local path = "mods/" .. name
    local info = fs.getInfo(path)
    if info and (info.type == "directory" or info.type == "symlink")
       and fs.getInfo(path .. "/manifest.json")
       and not LauncherMods.underRoot(root, path) then
      out[#out + 1] = name
    end
  end
  return out
end

-- Scan "mods/" one level deep for valid manifests (mirrors Loader:_discover,
-- but validates only -- no entry chunk is ever loaded).  First id wins on a
-- duplicate.  Returns an array of validated manifests.
local function discover()
  local fs = love and love.filesystem
  local out = {}
  if not (fs and fs.getInfo and fs.getDirectoryItems) then return out end
  -- A fused portable build keeps its mods in the game folder next to the
  -- executable; resolving the cache root is what mounts that folder onto the
  -- physfs read path, so this is what makes those mods enumerable at all
  -- (#330).  A source run needs nothing (the game folder IS the source), and
  -- the launcher's readiness check has usually resolved it already; the call
  -- is cached and idempotent.
  CacheFs.root()
  if not fs.getInfo("mods") then return out end
  -- THE CHOSEN FOLDER IS THE ONLY HOME ONCE THERE IS ONE.
  --
  -- love.filesystem lists every home at once, which is right for reading a
  -- mod and wrong as a permanent state: after the game-data folder changed,
  -- the panel went on showing mods still sitting in the old one, a re-install
  -- landed beside them under a new folder name, and a base file declared by
  -- both was written twice.  Reported as "all of my mods are showing in the
  -- launcher but theyre not in my new location", with a log of two 1.4 GB
  -- streams to prove it.
  --
  -- So when a custom root is live, a mod counts only if it is IN it.  The ones
  -- left behind are not lost and not deleted -- MOVE EXISTING DATA HERE brings
  -- them over, and LauncherMods.strandedMods below is what the panel says
  -- about them in the meantime.
  local confine = LauncherMods.confinedRoot()
  local seen = {}
  for _, name in ipairs(fs.getDirectoryItems("mods")) do
    local path = "mods/" .. name
    local info = fs.getInfo(path)
    -- a dev-linked mod dir (ln -s) reports type "symlink" even with
    -- setSymlinksEnabled(true); see the matching note in Loader:_discover.
    if confine and not LauncherMods.underRoot(confine, path) then
      info = nil
    end
    if info and (info.type == "directory" or info.type == "symlink") then
      local raw = fs.read(path .. "/manifest.json")
      if raw then
        local manifest = decodeManifest(raw, path)
        if manifest and not seen[manifest.id] then
          seen[manifest.id] = true
          out[#out + 1] = manifest
        end
      end
    end
  end
  return out
end

-- list() -> the mods-panel rows for the current install.  Reads the same
-- options.mods enable-state the loader persists, so a toggle here is what the
-- game sees on its next boot.
function LauncherMods.list()
  local ok, result = pcall(function()
    local options = SaveData.loadOptions()
    local manifests = discover()
    -- A RENAMED MOD COLLECTS ITS OLD STATE HERE TOO.  The launcher runs before
    -- any game does, so without this the first thing a player sees after a
    -- mod changed its id is that mod's rows sitting at their defaults -- and
    -- them changing one back would write under the new id and strand the old
    -- entry for good.  Same rules as the loader's pass: nothing is taken from
    -- an id that is itself installed, nothing overwrites state the new id
    -- already has, and the file is written only when something moved.
    if require("src.mods.ModRename").adoptOptions(options, manifests) then
      SaveData.saveOptions(options)
    end
    return LauncherMods.deriveList(manifests, options)
  end)
  if not ok then
    -- a single bad options/mod file must not blank the launcher
    return {}
  end
  return result or {}
end

-- setEnabled(id, enabled): persist options.mods[id] in the exact shape
-- Loader:_saveState writes (a plain boolean), so the running game and the
-- in-game ManagerState pick it up unchanged.
function LauncherMods.setEnabled(id, enabled)
  local options = SaveData.loadOptions()
  options.mods = options.mods or {}
  -- ...through ModGens, so flicking the master switch KEEPS the per-generation
  -- chips.  Writing a bare boolean here would reset them every time, which is
  -- exactly what "off and on again" must not cost the player.
  options.mods[id] = ModGens.withEnabled(options.mods[id], enabled)
  SaveData.saveOptions(options)
  return true
end

-- setGeneration(id, generation, want): one of the three chips under a mod's
-- switch.  Same single-write shape as setEnabled, and ModGens decides what
-- the master does about it (turning a generation on turns the mod on).
function LauncherMods.setGeneration(id, generation, want)
  local options = SaveData.loadOptions()
  options.mods = options.mods or {}
  options.mods[id] = ModGens.withGen(options.mods[id], generation, want)
  SaveData.saveOptions(options)
  return true
end

-- setForcedGeneration(id, generation, want): the player overruling the mod's
-- own `generations` claim for one generation.  Separate call from
-- setGeneration on purpose -- the panel asks before it gets here, and a plain
-- chip press must never turn into an override by accident.
function LauncherMods.setForcedGeneration(id, generation, want)
  local options = SaveData.loadOptions()
  options.mods = options.mods or {}
  options.mods[id] = ModGens.withForced(options.mods[id], generation, want)
  SaveData.saveOptions(options)
  return true
end

-- setAllGenerations(rows, generation, want): the per-generation bulk buttons.
-- `rows` is a list of ids; one options write for the lot, like setAllEnabled.
function LauncherMods.setAllGenerations(ids, generation, want)
  local options = SaveData.loadOptions()
  options.mods = options.mods or {}
  for _, id in ipairs(ids or {}) do
    options.mods[id] = ModGens.withGen(options.mods[id], generation, want)
  end
  SaveData.saveOptions(options)
  return true
end

-- setAllEnabled(ids, enabled): the launcher's Enable all / Disable all buttons
-- (#647).  Writes exactly the options.mods shape setEnabled does, but loads and
-- saves once for the whole list: saveOptions rewrites the whole options file per
-- call, so looping setEnabled over a big mods folder is one disk write per mod
-- and leaves a half-applied state behind if one of them fails.
function LauncherMods.setAllEnabled(ids, enabled)
  local options = SaveData.loadOptions()
  options.mods = options.mods or {}
  for _, id in ipairs(ids or {}) do
    options.mods[id] = ModGens.withEnabled(options.mods[id], enabled)
  end
  SaveData.saveOptions(options)
  return true
end

-- ------- install (love.filesystem)

-- Read a .zip source into bytes.  A string is an external absolute path (like
-- a chosen ROM) read with io.*, falling back to a save-dir-relative
-- love.filesystem read; a love DroppedFile is opened the way RomImporter
-- ingests dropped ROMs.
local function readArchive(source)
  local t = type(source)
  if (t == "userdata" or t == "table") and type(source.open) == "function" then
    local ok = source:open("r")
    if not ok then return nil, "could not open the dropped file" end
    local data = source:read(source:getSize())
    source:close()
    if not data then return nil, "the dropped file could not be read" end
    return data
  end
  if t == "string" then
    local f = io.open(source, "rb")
    if f then
      local data = f:read("*a")
      f:close()
      if not data then return nil, "could not read " .. source end
      return data
    end
    if love and love.filesystem then
      local data = love.filesystem.read(source)
      if data then return data end
    end
    return nil, "could not open " .. source
  end
  return nil, "unsupported archive source"
end

-- Shallow listing of a mounted archive shaped for locateRoot: files by name,
-- and for each top-level directory a "<dir>/manifest.json" marker only when it
-- actually holds one (so a lone folder with no manifest still reads as empty).
local function topLevelPaths(mount)
  local fs = love.filesystem
  local paths = {}
  for _, name in ipairs(fs.getDirectoryItems(mount)) do
    local info = fs.getInfo(mount .. "/" .. name)
    if info and info.type == "directory" then
      if fs.getInfo(mount .. "/" .. name .. "/manifest.json", "file") then
        paths[#paths + 1] = name .. "/manifest.json"
      end
    else
      paths[#paths + 1] = name
    end
  end
  return paths
end

-- Copy the mounted archive subtree at `src` to the install path `dst`.  Reads
-- come from love.filesystem (the .zip is mounted there); every write goes
-- through CacheFs so it lands in the portable game folder when portable.txt is
-- in play and in the OS save directory otherwise (#330).  No explicit mkdir:
-- CacheFs.write creates the parent chain on both paths, which also means an
-- empty folder inside the .zip is simply not carried over (it holds nothing).
local function copyTree(src, dst)
  local fs = love.filesystem
  for _, name in ipairs(fs.getDirectoryItems(src)) do
    local s = src .. "/" .. name
    local d = dst .. "/" .. name
    local info = fs.getInfo(s)
    if info and info.type == "directory" then
      local ok, err = copyTree(s, d)
      if not ok then return nil, err end
    else
      local data = fs.read(s)
      if data == nil then return nil, "could not read " .. name end
      local ok, err = CacheFs.write(d, data)
      if not ok then return nil, "could not write " .. name .. ": " .. tostring(err) end
    end
  end
  return true
end

-- Delete an installed mod subtree.  Enumeration stays on love.filesystem (the
-- portable game folder is on its read path), but the deletes go through
-- CacheFs so a portable install's real files actually go away instead of
-- love.filesystem no-opping outside the save directory (#330).  Directories
-- are removed after their children, since rmdir refuses a non-empty one.
-- ------- reaching the game folder's real files

-- A love.filesystem path (forward slashes, rooted at a mount) as a real path
-- under `root`.
function LauncherMods.realPath(root, rel)
  return root .. CacheFs.SEP .. (rel:gsub("/", CacheFs.SEP))
end

-- Every real directory love.filesystem might be reading `mods/` out of: the
-- portable game folder when portable mode is on, and otherwise the same game
-- folders portable mode LOOKS in -- next to the .exe, inside the .app, the
-- source directory of a `love <gamedir>` run.  A mod dropped in any of them
-- shows up in the panel, so a delete has to be able to reach all of them.
function LauncherMods.gameFolderRoots()
  local roots, seen = {}, {}
  local function add(dir)
    if type(dir) == "string" and dir ~= "" and not seen[dir] then
      seen[dir] = true
      roots[#roots + 1] = dir
    end
  end
  add(CacheFs.root())
  for _, dir in ipairs(SaveData.gameFolders() or {}) do add(dir) end
  return roots
end

-- The real folder holding this mod path, found by its manifest, or nil when
-- only the save directory has it.  Used for the message when a delete cannot
-- finish -- "it is still there" is no use without "and it is HERE".
function LauncherMods.realFolder(path)
  for _, root in ipairs(LauncherMods.gameFolderRoots()) do
    local base = LauncherMods.realPath(root, path)
    local f = io.open(base .. CacheFs.SEP .. "manifest.json", "rb")
    if f then f:close() return base end
  end
  return nil
end

-- A CHECKOUT IS NOT AN INSTALL, and this is the one folder the launcher must
-- not delete.
--
-- A mod author keeps the mod's own repository in mods/ and works in it -- the
-- DramaticShapes folder in this very tree is a git checkout with its history,
-- its branches and its unpushed work in it.  Uninstall removes a directory
-- recursively and nothing restores it, so obeying that click would destroy
-- work the launcher never installed and cannot put back.  Saying so, with the
-- path, costs one message and is recoverable; the alternative is not.
--
-- Probed on the REAL filesystem rather than through love.filesystem: physfs
-- is a merged read-only view with its own rules about what it lists, and a
-- guard that silently fails to see .git is worse than no guard at all.  ".git"
-- is tested as a FILE too, which is what a worktree or a submodule has.
local VCS_PROBES = { ".git/HEAD", ".git", ".hg/00changelog.i", ".svn/format" }

function LauncherMods.checkoutAt(path)
  for _, root in ipairs(LauncherMods.gameFolderRoots()) do
    local base = LauncherMods.realPath(root, path)
    for _, probe in ipairs(VCS_PROBES) do
      local f = io.open(base .. CacheFs.SEP .. (probe:gsub("/", CacheFs.SEP)), "rb")
      if f then f:close() return base end
    end
  end
  return nil
end

-- `roots` are REAL game-folder paths to delete from as well, and only an
-- explicit uninstall passes any.
--
-- THE DELETE THAT COULD NOT REACH THE FILES.
--
-- Reported from play twice over: "issue for people that want to delete mods or
-- delete dramatic shapes, it says they're not installed but they appear in the
-- launcher", and then "deleting the dramatic shapes mod still doesn't work".
-- The first half was the id/folder mismatch (folderFor); this is the second,
-- and it is the bigger one.
--
-- love.filesystem READS a mod from two places -- the save directory and the
-- game folder -- and can only WRITE to the first.  A mod unzipped next to the
-- executable, or a checkout sitting in the game folder's own mods/, therefore
-- survived every delete: CacheFs reaches the game folder ONLY in portable
-- mode, and without portable.txt both branches collapse to
-- love.filesystem.remove, which no-ops outside the save directory.  The
-- launcher then reported "Deleted <mod>" and the row came straight back,
-- because the manifest it was reading had never been touched.
--
-- So the real files are removed too, under whichever game folder actually has
-- them (SaveData.gameFolders is the same list portable mode looks in).  The
-- enumeration still comes off love.filesystem, which is the only merged view
-- of the two homes; the deletes just no longer stop at the save directory.
local function removeTree(path, roots)
  local fs = love.filesystem
  local info = fs.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(fs.getDirectoryItems(path)) do
      removeTree(path .. "/" .. child, roots)
    end
    CacheFs.removeDir(path)
    for _, root in ipairs(roots or {}) do
      CacheFs.rmdirReal(LauncherMods.realPath(root, path))
    end
  else
    CacheFs.remove(path)
    for _, root in ipairs(roots or {}) do
      os.remove(LauncherMods.realPath(root, path))
    end
  end
  -- A portable install can still be carrying a pre-#330 copy in the OS save
  -- directory, which is where every install used to land and which physfs
  -- searches first.  CacheFs only touched the game folder, so clear the
  -- save-directory twin too or that copy would keep the mod alive; outside
  -- portable mode this repeats the delete CacheFs just did and no-ops.
  fs.remove(path)
end

-- ------- strays: mods dropped beside the game that it cannot see

-- love.filesystem looks in two places for "mods/": the save directory, and --
-- portable installs only -- the game folder, which CacheFs mounts.  A player
-- who unzips a mod next to the executable of an ordinary install, which is
-- where very nearly every other game would want it, gets no error and no mod.
-- The MODS panel simply stays empty, and there is nothing on screen to
-- suggest the files are twenty centimetres away in the wrong folder.
--
-- The scan mounts each game folder at a private mount point just long enough
-- to list mods/ inside it and drops it again (CacheFs.withMounted), so the
-- read path the game actually runs on is never touched and a stray can never
-- shadow a real file.
local STRAY_MOUNT = "stray_scan"

-- Run fn(mountedModsRoot) for each game folder that has a readable mods/
-- directory, one mount at a time.  Folders already on the read path are
-- skipped (isReadableRoot): the physfs source, which is every `love <gamedir>`
-- dev run, and the portable game folder CacheFs mounted, where re-mounting is
-- what used to drop the mount (#413).
local function eachStrayRoot(fn)
  local SaveData_ = require("src.core.SaveData")
  local fs = love and love.filesystem
  if not fs then return end
  local source = fs.getSource and fs.getSource()
  local cacheRoot = CacheFs.root()
  local seen = {}
  for _, folder in ipairs(SaveData_.gameFolders() or {}) do
    if not seen[folder]
      and not LauncherMods.isReadableRoot(folder, source, cacheRoot) then
      seen[folder] = true
      CacheFs.withMounted(folder, STRAY_MOUNT, function()
        local root = STRAY_MOUNT .. "/mods"
        if fs.getInfo(root) then fn(root, folder) end
      end)
    end
  end
end

-- Every valid mod folder sitting in a game folder's mods/, in scan order.
-- Only reads.  The rows carry the mounted path, which is live for the length
-- of the mount and dead after it -- copying has to happen inside the same
-- scan, which is why adoption is a flag here rather than a second pass.
local function findStrays(fs, adopt, installed)
  local found, adopted = {}, {}
  eachStrayRoot(function(root, folder)
    local batch = {}
    for _, name in ipairs(fs.getDirectoryItems(root)) do
      local path = root .. "/" .. name
      local info = fs.getInfo(path)
      if info and info.type == "directory" then
        local raw = fs.read(path .. "/manifest.json")
        local manifest = raw and decodeManifest(raw, path)
        if manifest then
          batch[#batch + 1] = { id = manifest.id,
                                name = manifest.name or manifest.id,
                                folder = folder, path = path }
        end
      end
    end
    -- filtered per mount, so a copy only ever runs for a row that survived
    -- the pure rules -- and so the second game folder sees the first one's
    -- ids as taken
    for _, row in ipairs(LauncherMods.pickStrays(batch, installed)) do
      if adopt then
        -- same root pin installZip uses: the mods tree is shared by Red and
        -- Blue, never version-prefixed (#330)
        local savedPrefix = CacheFs.prefix
        CacheFs.prefix = ""
        local dest = "mods/" .. row.id
        local copied, copyErr = copyTree(row.path, dest)
        if not copied then removeTree(dest) end
        CacheFs.prefix = savedPrefix
        if not copied then row.err = copyErr or "could not copy the files" end
      end
      installed[row.id] = true
      row.path = nil                    -- dead once this mount comes down
      adopted[#adopted + 1] = row
      found[#found + 1] = row
    end
  end)
  return LauncherMods.pickStrays(found, {})
end

-- The strays, optionally adopted.  A folder whose id the game can already see
-- is left out: the player has a working copy, and the loose one is just where
-- they first put it.  Rows that failed to copy come back with .err set.
local function scanStrays(adopt)
  local fs = love and love.filesystem
  if not fs then return {} end
  local installed = {}
  for _, m in ipairs(discover()) do installed[m.id] = true end
  return findStrays(fs, adopt, installed)
end

-- strays() -> the rows, nothing copied.
function LauncherMods.strays() return scanStrays(false) end

-- adoptStrays() -> the rows, each one copied into the mods tree the game
-- really reads (rows carrying .err failed).  Idempotent: a second call finds
-- the ids installed and returns nothing, so the panel can run this on every
-- open without duplicating anything or nagging twice.  The loose folder is
-- deliberately left where it is -- deleting files outside the save directory
-- on the player's behalf is not this function's call to make.
function LauncherMods.adoptStrays() return scanStrays(true) end

-- installZip(source [, opts]) -> true, id  |  nil, errString
-- source is an external path or a love DroppedFile.  The archive is validated
-- BEFORE anything is copied; every path unmounts and clears the staged temp
-- file, and a failed copy rolls its partial tree back.  A dropped file outside
-- the save dir is staged into a save-dir temp first, because
-- love.filesystem.mount only reaches a save-directory-relative path.
-- opts.replace = true uninstalls an existing same-id mod first (updates /
-- rollbacks).  opts.expectId, when set, refuses a zip whose manifest id differs.
-- Returns true, id, installedVersion  |  nil, errString.  The version is the
-- one the INSTALLED manifest.json declares, which is not always the one the
-- release it came from claims -- see installFromRelease.
-- WHERE A MOD THIS MACHINE HAS NEVER SEEN SHOULD GO.
--
-- `mods/<id>` normally, and that is what every install has used -- but the
-- name may already be taken by a tree that is NOT this mod: a folder whose id
-- differs only in case (see folderFor), a hand-unzipped folder with no
-- manifest at all, or a leftover from a mod that was renamed.  Refusing there
-- is what locked the second mod out; taking the folder would be worse.
--
-- So: find a free name.  The folder is an implementation detail -- discover()
-- lists a mod by the id its manifest declares and folderFor finds it by
-- reading manifests, so nothing downstream cares what the directory is called.
local function freeInstallPath(fs, id)
  local base = "mods/" .. id
  if not fs.getInfo(base) then return base end
  for n = 2, 99 do
    local candidate = ("%s-%d"):format(base, n)
    if not fs.getInfo(candidate) then return candidate end
  end
  return nil, ("could not find a free folder for '%s' under mods/"):format(id)
end

function LauncherMods.installZip(source, opts)
  local ok, result, err, version = pcall(LauncherMods._installZipInner, source, opts)
  if not ok then return nil, "import failed: " .. tostring(result) end
  return result, err, version
end

-- MANY AT ONCE.
--
-- Asked for directly: "add a way to mass import mods".  Installing a folder of
-- releases one dialog at a time is the shape of the complaint, and it gets
-- worse the more mods somebody has -- reinstalling a whole collection after
-- moving machines was a dozen round trips through a file picker.
--
-- ONE SUMMARY, NOT N NOTICES.  Each source is installed by exactly the path a
-- single import takes (installZip, magic bytes and manifest validation and
-- all), and the results are collected rather than announced: a run of twelve
-- that installs eleven wants one line saying which one did not, not eleven
-- lines that scroll the failure off the panel.
--
-- ALREADY-INSTALLED IS NOT A FAILURE HERE.  A mass import is nearly always
-- "give me everything in this folder", and half of it being present already is
-- the normal case rather than a mistake, so those are counted separately and
-- reported as skipped.  `opts.replace` turns them into reinstalls for a caller
-- that means it.
--
-- Returns { installed = {names}, skipped = {names}, failed = {{name, err}} }.
function LauncherMods.installMany(sources, opts)
  opts = opts or {}
  local out = { installed = {}, skipped = {}, failed = {} }
  for _, source in ipairs(sources or {}) do
    local label = type(source) == "string"
      and (source:match("[^/\\]+$") or source)
      or (source.getFilename and source:getFilename()) or "archive"
    local okOne, name, err = pcall(LauncherMods.installZip, source, opts)
    if okOne and name then
      out.installed[#out.installed + 1] = tostring(name)
    else
      local why = tostring((okOne and err) or name or "import failed")
      -- "a mod named 'x' is already installed" is the one refusal that means
      -- the player already has what they asked for
      if why:find("already installed", 1, true) then
        out.skipped[#out.skipped + 1] = label
      else
        out.failed[#out.failed + 1] = { name = label, err = why }
      end
    end
  end
  return out
end

-- The .zip files directly inside a folder, and one level under it -- so both
-- "a folder of zips" and "a folder of per-mod folders each holding its
-- release" work, which are the two ways anybody actually keeps them.
--
-- An EXTERNAL absolute path, so this cannot use love.filesystem: the folder a
-- player points at is on their disk, not on the physfs read path.  CacheFs's
-- scoped mount is how the stray-adoption scan already reaches outside, and
-- this borrows it rather than opening a second door.
function LauncherMods.zipsInFolder(path)
  if type(path) ~= "string" or path == "" then return nil, "no folder given" end
  if not (love and love.filesystem) then return nil, "needs LOVE" end
  local mount = "mod_bulk_mount"
  if not love.filesystem.mount(path, mount) then
    return nil, "that folder could not be opened: " .. tostring(path)
  end
  local found = {}
  local sep = path:find("\\", 1, true) and "\\" or "/"
  local okScan = pcall(function()
    for _, entry in ipairs(love.filesystem.getDirectoryItems(mount)) do
      local info = love.filesystem.getInfo(mount .. "/" .. entry)
      if info and info.type == "file" and entry:lower():match("%.zip$") then
        found[#found + 1] = path .. sep .. entry
      elseif info and info.type == "directory" then
        for _, sub in ipairs(
            love.filesystem.getDirectoryItems(mount .. "/" .. entry)) do
          local si = love.filesystem.getInfo(mount .. "/" .. entry .. "/" .. sub)
          if si and si.type == "file" and sub:lower():match("%.zip$") then
            found[#found + 1] = path .. sep .. entry .. sep .. sub
          end
        end
      end
    end
  end)
  love.filesystem.unmount(mount)
  if not okScan then return nil, "that folder could not be read" end
  table.sort(found)
  if #found == 0 then return nil, "no .zip files in " .. tostring(path) end
  return found
end

-- One line describing an installMany result, for the panel's notice.
function LauncherMods.summarize(res)
  if not res then return false, "nothing to import" end
  local parts = {}
  if #res.installed > 0 then
    parts[#parts + 1] = ("Installed %d: %s"):format(#res.installed,
      table.concat(res.installed, ", "))
  end
  if #res.skipped > 0 then
    parts[#parts + 1] = ("%d already installed"):format(#res.skipped)
  end
  if #res.failed > 0 then
    local names = {}
    for _, f in ipairs(res.failed) do names[#names + 1] = f.name end
    parts[#parts + 1] = ("%d failed: %s"):format(#res.failed,
      table.concat(names, ", "))
    -- the FIRST reason, in full: a list of names with no cause is a support
    -- thread, and one cause usually explains all of them
    parts[#parts + 1] = tostring(res.failed[1].err)
  end
  if #parts == 0 then return false, "nothing was imported" end
  return #res.installed > 0 and #res.failed == 0, table.concat(parts, "\n")
end

function LauncherMods._installZipInner(source, opts)
  opts = opts or {}
  if not (love and love.filesystem) then
    return nil, "mod install needs LOVE"
  end
  local fs = love.filesystem
  local data, readErr = readArchive(source)
  if not data then return nil, readErr end

  -- Cheap magic-byte check before anything is staged.  Every real zip starts
  -- "PK"; a Mac MTP copy leaves "._name.zip" resource forks that do not, and
  -- without this they reach the mount and fail as "could not be opened",
  -- which reads like a corrupt mod rather than a file to ignore.
  if not (type(data) == "string" and #data >= 4 and data:sub(1, 2) == "PK") then
    local label = type(source) == "string" and (source:match("[^/\\]+$") or source)
      or "archive"
    return nil, "not a zip file: " .. tostring(label)
      .. " (need a real .zip; skip Mac ._ files from MTP)"
  end

  local mount = "mod_import_mount"
  local tmp, mountKey = nil, nil
  local mounted = false

  -- In-memory mount first (PHYSFS_mountMemory, via FileData).  The staged
  -- write-then-mount path below reopens a file it has just written, which
  -- Horizon refuses -- the Switch answers "file already open" and the whole
  -- import failed as "that .zip could not be opened".  Mounting the bytes
  -- never touches the filesystem twice, so it works there and everywhere.
  if fs.newFileData then
    local archiveName = ("mod_import_%d_%d.zip"):format(
      os.time(), math.random(0, 999999))
    local okFd, fd = pcall(fs.newFileData, data, archiveName)
    if okFd and fd and fs.mount(fd, mount) then
      mounted = true
      mountKey = fd
    end
  end

  if not mounted then
    -- Fallback: stage into a save-dir temp so a path mount can reach it.
    tmp = ("mod_import_%d_%d.zip"):format(os.time(), math.random(0, 999999))
    local okw, writeErr = fs.write(tmp, data)
    if not okw then
      return nil, "could not stage the .zip: " .. tostring(writeErr)
    end
    if not fs.mount(tmp, mount) then
      fs.remove(tmp)
      return nil, "that .zip could not be opened"
    end
    mountKey = tmp
  end

  local function cleanup()
    pcall(fs.unmount, mountKey)
    if tmp then fs.remove(tmp) end
  end

  local prefix, rootErr = LauncherMods.locateRoot(topLevelPaths(mount))
  if not prefix then
    cleanup()
    return nil, rootErr
  end
  local root = prefix == "" and mount or (mount .. "/" .. prefix)

  local raw = fs.read(root .. "/manifest.json")
  if not raw then
    cleanup()
    return nil, "the .zip has no readable manifest.json"
  end
  local manifest, manifestErr = decodeManifest(raw, root)
  if not manifest then
    cleanup()
    return nil, "invalid mod manifest: " .. tostring(manifestErr)
  end
  if opts.expectId and manifest.id ~= opts.expectId then
    cleanup()
    return nil, ("zip is for '%s', expected '%s'")
      :format(manifest.id, opts.expectId)
  end

  -- ...AND IT REPLACES THE COPY THAT IS ACTUALLY THERE.
  --
  -- Same mismatch uninstall had (see folderFor): the id and the folder are two
  -- names, and asking for "mods/<id>" misses a mod whose folder is called
  -- something else.  Installing over one then reported it as NOT already
  -- installed and copied a second tree beside it -- two folders declaring one
  -- id, which discover() resolves by taking whichever it reaches first and the
  -- loader reports as a duplicate.  An update would have done worse: it would
  -- have removed a folder that was not there and left the old version loading.
  -- ...and "already installed" means a tree that DECLARES THIS ID, not a
  -- folder that happens to share its name.  See folderFor: on Windows
  -- `mods/Dramatic_shape` and `mods/DRAMATIC_SHAPE` are one directory, so an
  -- unrelated mod was being told it was already here and could not be
  -- installed at all.  A name that is taken by somebody else simply gets a
  -- different one (freeInstallPath).
  local dest = LauncherMods.folderFor(manifest.id)
  if not dest then
    local free, freeErr = freeInstallPath(fs, manifest.id)
    if not free then
      cleanup()
      return nil, freeErr
    end
    dest = free
  end
  if fs.getInfo(dest) then
    if not opts.replace then
      cleanup()
      return nil, "a mod named '" .. manifest.id .. "' is already installed"
    end
    -- ...AND AN UPDATE MUST NOT SHADOW A WORKING TREE.
    --
    -- The same folder the delete refuses to remove (see checkoutAt): if the
    -- installed copy is a checkout, it lives in the game folder, which this
    -- build can only WRITE to in portable mode.  So the update would go to the
    -- save directory instead and win the physfs search by sitting in front of
    -- the checkout -- the author's own edits silently stop taking effect while
    -- the folder they are editing looks untouched.  That is a worse failure
    -- than not updating, and it is invisible.  The checkout is the install;
    -- say so and let them pull.
    local checkout = LauncherMods.checkoutAt(dest)
    if checkout and not opts.allowCheckout then
      cleanup()
      return nil, ("'%s' is installed as a source checkout at %s -- update it "
                   .. "there (git pull), or delete that folder and install the "
                   .. "release"):format(manifest.id, checkout)
    end
    -- drop the old tree before copy; enable-flag is preserved (uninstall
    -- would clear it, which would surprise an update).  Save-directory only:
    -- an install is not an uninstall and has no business deleting files out of
    -- somebody's game folder.
    local savedPrefix = CacheFs.prefix
    CacheFs.prefix = ""
    removeTree(dest)
    CacheFs.prefix = savedPrefix
  end

  -- CacheFs.prefix steers ROM-cache writes into a version subtree (blue/...);
  -- the mods tree is shared by Red and Blue, so pin the prefix to the root for
  -- the copy and the rollback, then hand back whatever the launcher had set
  -- (an import coroutine leaves it pointed at that version -- RomImporter.lua).
  -- No fs.createDirectory("mods") here any more: CacheFs.write creates the
  -- parent chain in both homes, and doing it through love.filesystem would
  -- only ever make the directory in the save dir (#330).
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = ""
  local copied, copyErr = copyTree(root, dest)
  if not copied then removeTree(dest) end
  CacheFs.prefix = savedPrefix
  if not copied then
    cleanup()
    return nil, copyErr or "could not copy the mod files"
  end

  -- ...AND THE COPY HAS TO BE THE ONE THE GAME WILL READ.
  --
  -- Everything above writes through CacheFs, which lands in the save directory
  -- unless portable mode is on -- and love.filesystem reads BOTH homes.  The
  -- save directory is searched first, so the new files win; this checks that
  -- rather than trusting it, because when it is not true the symptom is a
  -- launcher that says "Updated to 0.7.47" and then goes on reporting 0.7.47
  -- as available forever, with nothing anywhere to say why.
  local landed = fs.read(dest .. "/manifest.json")
  local got = landed and decodeManifest(landed, dest) or nil
  if got and manifest.version and got.version ~= manifest.version then
    cleanup()
    return nil, ("installed %s %s, but %s still reads %s -- an older copy in "
                 .. "%s is in front of it"):format(
      manifest.id, tostring(manifest.version), dest, tostring(got.version),
      LauncherMods.realFolder(dest) or "the game folder")
  end

  cleanup()
  return true, manifest.id, manifest.version
end

-- Install (or replace) a mod from a GitHub release zip URL.
-- Returns true, version  |  nil, errString. Soft-fails: download / install /
-- cleanup errors never throw into the launcher UI.
function LauncherMods.installFromRelease(modId, release)
  local ok, result, err, mismatch = pcall(function()
    if type(modId) ~= "string" or modId == "" then
      return nil, "missing mod id"
    end
    if type(release) ~= "table" or not release.zip or not release.zip.url then
      return nil, "release has no downloadable .zip"
    end
    local ModUpdate = require("src.mods.ModUpdate")
    local tmpName = ("mod_update_%s_%s.zip"):format(
      tostring(modId), tostring(release.version or os.time()))
    local localPath, dlErr = ModUpdate.downloadZip(release.zip.url, tmpName,
      release.zip.size)
    if not localPath then return nil, dlErr end
    local installed, res, version = LauncherMods.installZip(localPath, {
      replace = true, expectId = modId,
    })
    pcall(love.filesystem.remove, localPath)
    if not installed then return nil, res end

    -- A RELEASE'S NUMBER AND ITS MANIFEST'S NUMBER ARE TWO DIFFERENT CLAIMS.
    --
    -- Reported from play: "updating ... keeps saying it updated but that
    -- 0.7.47 is available".  It did update, and 0.7.47 was still available,
    -- and both were true: DramaticShapes-Gen2Recomped-0.7.47.zip carries a
    -- manifest.json that says `"version": "0.7.40"`.  The release is named by
    -- its tag and the INSTALLED version is read from the manifest, so the
    -- update check compares 0.7.47 against 0.7.40 again on the next pass, and
    -- offers the same update forever.  Nothing is broken on either side of
    -- that comparison; the zip is mis-stamped, and no number the launcher has
    -- can tell it so on its own.
    --
    -- So the version handed back is the one that is actually installed, never
    -- the tag -- "Updated to 0.7.40" after clicking 0.7.47 is a sentence that
    -- points straight at the packaging -- and the disagreement is named
    -- outright as a third return, because otherwise the loop is silent.
    local mismatch = nil
    if release.version and version and version ~= release.version then
      mismatch = ("release %s installed, but its manifest.json says %s -- the "
                  .. "zip is mis-stamped, so this update will keep being "
                  .. "offered until the manifest matches the tag")
        :format(tostring(release.version), tostring(version))
    end
    return true, version or release.version or res, mismatch
  end)
  if not ok then return nil, "install failed: " .. tostring(result) end
  return result, err, mismatch
end

-- Install a mod listed in a community index (src/mods/ModIndex.lua).
-- The index only ever tells us WHERE the zip is; resolving that URL is
-- ModIndex's job and installing it is installFromRelease's, so this is the
-- seam between them and nothing about the archive is special-cased.  expectId
-- comes from the listing, so a feed that points an entry at somebody else's
-- zip fails the manifest check instead of installing the wrong mod.
-- Returns true, version | nil, errString.
function LauncherMods.installFromIndex(entry)
  local ok, result, err, mismatch = pcall(function()
    if type(entry) ~= "table" or type(entry.id) ~= "string" then
      return nil, "index entry has no mod id"
    end
    local ModIndex = require("src.mods.ModIndex")
    local release, why = ModIndex.releaseFor(entry)
    if not release then
      return nil, why or "this mod cannot be installed from the index"
    end
    return LauncherMods.installFromRelease(entry.id, release)
  end)
  if not ok then return nil, "install failed: " .. tostring(result) end
  return result, err, mismatch
end

-- uninstall(id) -> true  |  nil, errString
-- Removes mods/<id>/ from wherever it was installed (the portable game folder
-- or the save directory, CacheFs decides -- #330) and clears options.mods[id]
-- so the loader and in-game manager no longer see it.  Rejects missing ids.
-- Does not touch other mods' enable state.
-- WHICH FOLDER A MOD ID ACTUALLY LIVES IN.
--
-- Reported from play: "experiencing issue for people that want to delete mods
-- or delete dramatic shapes, it says they're not installed but they appear in
-- the launcher as if it's installed".  Both halves were true at once, and the
-- reason is that a mod's ID and its FOLDER are two different names.
--
-- discover() lists a mod under the id its manifest declares and throws the
-- folder away; uninstall then went looking for "mods/<id>".  Those agree for
-- anything the launcher installed itself (installZip unzips to mods/<id>) and
-- routinely do not for anything unzipped by hand: DRAMATIC_SHAPE's manifest
-- declares `Gen2Recomped-DramaticShapes`, so the panel offered a row it could
-- not then find, and said so in the one wording that reads as nonsense next to
-- a visible row -- "not installed".
--
-- A folder whose name IS the id still wins first, so nothing the launcher put
-- there changes path; only a mismatch pays for the scan.
--
-- ...BUT THE FAST PATH HAS TO PROVE ITSELF, and that is the second half of the
-- same confusion.  Reported from play: with DRAMATIC_SHAPE installed, another
-- author's mod would not install at all -- "a mod named 'Dramatic_shape' is
-- already installed" -- for a mod that was not this one and had never been
-- installed.
--
-- `getInfo("mods/Dramatic_shape")` answered TRUE, because the folder on disk
-- is `mods/DRAMATIC_SHAPE` and Windows (and macOS by default) does not
-- distinguish the two.  So a folder belonging to somebody else was handed back
-- as this id's home, and the installer read that as "you already have this".
-- Two mods whose ids differ only in case are two mods, and one of them was
-- locked out of the machine by the other's folder name.
--
-- Reading the manifest costs one small file on the path that used to cost
-- nothing, and only for a hit -- a miss still falls straight through to the
-- scan below, which has always confirmed the id.
local function folderDeclares(fs, path, id)
  local info = fs.getInfo(path)
  if not (info and (info.type == "directory" or info.type == "symlink")) then
    return false
  end
  local raw = fs.read(path .. "/manifest.json")
  local manifest = raw and decodeManifest(raw, path) or nil
  return manifest ~= nil and manifest.id == id
end

function LauncherMods.folderFor(id)
  local fs = love and love.filesystem
  if not (fs and fs.getInfo and fs.getDirectoryItems) then return nil end
  -- the portable game folder has to be on the read path before either the
  -- direct hit or the scan can see anything (#330)
  CacheFs.root()
  local direct = "mods/" .. id
  if folderDeclares(fs, direct, id) then return direct end
  if not fs.getInfo("mods") then return nil end
  for _, name in ipairs(fs.getDirectoryItems("mods")) do
    local path = "mods/" .. name
    if folderDeclares(fs, path, id) then return path end
  end
  return nil
end

function LauncherMods.uninstall(id)
  if type(id) ~= "string" or id == "" then
    return nil, "missing mod id"
  end
  if id:find("[/\\]") or id == "." or id == ".." then
    return nil, "invalid mod id"
  end
  if not (love and love.filesystem) then
    return nil, "mod uninstall needs LOVE"
  end
  local fs = love.filesystem
  local dest = LauncherMods.folderFor(id)
  if not dest then
    return nil, "mod '" .. id .. "' is not installed"
  end
  local checkout = LauncherMods.checkoutAt(dest)
  if checkout then
    return nil, ("'%s' is a source checkout at %s -- delete that folder "
                 .. "yourself; the launcher will not remove a repository it "
                 .. "did not install"):format(id, checkout)
  end
  -- same root pin as installZip: the mods tree is not version-prefixed (#330)
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = ""
  removeTree(dest, LauncherMods.gameFolderRoots())
  CacheFs.prefix = savedPrefix

  -- ...AND THEN CHECK, because this used to report a delete it had not done.
  --
  -- The old uninstall returned true whatever happened: every branch of
  -- removeTree is best-effort and none of them answers.  With the files out of
  -- reach that produced "Deleted <mod>" followed by the same row, at the same
  -- version, still there -- the single most confusing way for this to fail.
  -- The manifest is the test, because the manifest is what discover() reads:
  -- while it is still readable the mod IS still installed, whatever is left of
  -- the rest of the tree.
  if fs.getInfo(dest .. "/manifest.json") then
    local where = LauncherMods.realFolder(dest)
    return nil, ("could not delete '%s': its files are still at %s"):format(
      id, where or dest)
  end

  -- Drop the enable flag so a reinstall of the same id starts from the
  -- loader's default (enabled) rather than a stale false.
  local options = SaveData.loadOptions()
  if options.mods and options.mods[id] ~= nil then
    options.mods[id] = nil
    SaveData.saveOptions(options)
  end
  return true
end

return LauncherMods
