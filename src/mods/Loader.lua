local Json = require("src.link.Json")
local Logger = require("src.core.Logger")
-- Hoisted deliberately: the dev-mode require shim attributes every src.* require
-- made while Runtime.currentMod is set to THAT MOD, and both uses below sit
-- inside that window.  Requiring it here resolves it once, at load, with no
-- mod in scope, so a mod is never blamed for an engine require it did not make.
local ModImports = require("src.mods.ModImports")
local ImportAccess = require("src.mods.ImportAccess")
local SaveData = require("src.core.SaveData")
local Data = require("src.core.Data")
local Version = require("src.core.Version")
local Assets = require("src.render.Assets")
local ModUI = require("src.ui.ModUI")
local PortableScripts = require("src.mods.PortableScripts")
local Api3Warp = require("src.mods.Api3Warp")
local AssetTransform = require("src.mods.AssetTransform")
local Manifest = require("src.mods.Manifest")
local Merge = require("src.mods.Merge")
local Registry = require("src.mods.Registry")
local Schemas = require("src.mods.Schemas")
local Capabilities = require("src.mods.Capabilities")
local Semver = require("src.mods.Semver")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local ModStorage = require("src.mods.Storage")
local WorldReads = require("src.mods.WorldReads")
local Runtime = require("src.mods.Runtime")
local BattleSnapshots = require("src.mods.BattleSnapshots")
local UIActions = require("src.mods.UIActions")
local ModGens = require("src.mods.ModGens")
local ModSeams = require("src.mods.ModSeams")
local WorldActions = require("src.world.WorldActions")
local WorldOverview = require("src.mods.WorldOverview")
-- Module-name aliases for mods written against the Gold port's per-generation
-- layout (src.world.gen2.Player and friends).  Installed here because this is
-- the module that loads mods: the searcher has to be in place before the
-- first mod's main.lua runs, and nothing else needs it at all.
require("src.core.ModCompat").install()

local Loader = {}
Loader.__index = Loader

local MOD_STATE_FILE = "mod_state.lua" -- legacy migration only

-- walk a dotted target path without creating anything; the base view a
-- registry folds against must never perturb Data on a mod-free boot
local function resolvePath(root, path)
  local node = root
  for key in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then return nil end
    node = node[key]
  end
  return node
end

local function readManifest(fs, root)
  local raw, err = fs.read(root .. "/manifest.json")
  if not raw then return nil, err end
  local data, decodeErr = Json.decode(raw)
  if not data then return nil, decodeErr end
  local ok, manifest = pcall(Manifest.validate, data, root)
  if not ok then return nil, manifest end
  return manifest
end

-- the ordering contract every phase walks in: priority ascending, ties by id
local function orderedIds(mods, filter)
  local ids = {}
  for id, mod in pairs(mods) do
    if not filter or filter(mod) then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b)
    local pa, pb = mods[a].manifest.priority, mods[b].manifest.priority
    if pa == pb then return a < b end
    return pa < pb
  end)
  return ids
end

-- ------- dev-mode permissions tripwire
-- Attribution only: the shim delegates unconditionally and blocks nothing.
-- Installed once per process and only when the loader runs in dev mode, so a
-- player build has zero interposition.

local devShim = { installed = false, permissions = {}, warned = {}, depth = 0 }

-- the src.* modules the mod surface points authors at: another mod's
-- exports carry a version string that wants range-checking before use, and
-- ChipAsm is the authoring path for chip music and sfx
local SUPPORTED_REQUIRES = {
  ["src.mods.Semver"] = true,
  ["src.audio.ChipAsm"] = true,
  ["src.pokemon.Stats"] = true, -- Stats.isShiny / calc for indicator mods
}

local function scanRequire(name)
  local modId = Runtime.currentMod
  if not modId or type(name) ~= "string" then return end
  local granted = devShim.permissions[modId] or {}
  local function warnOnce(permission)
    local key = modId .. "|" .. permission .. "|" .. name
    if devShim.warned[key] then return end
    devShim.warned[key] = true
    Logger.warn("[%s] undeclared %s require: %s", modId, permission, name)
  end
  -- link modules are the one place a mod can reach the wire, so network is
  -- the permission that governs them
  if name:match("^src%.link%.") then
    if not granted.network then warnOnce("network") end
  elseif name:match("^src%.") and not SUPPORTED_REQUIRES[name]
      and not granted.engine_internals then
    warnOnce("engine_internals")
  end
end

-- the genuine require, captured before the shim can replace it
local rawRequire = require

-- a module the loader pulls in late on the mod's behalf.  The mod asked for
-- a facade, not for this module nor for whatever it drags in, so the whole
-- load runs at shim depth and neither level is attributed to the mod.
local function engineRequire(name)
  devShim.depth = devShim.depth + 1
  local ok, module = pcall(rawRequire, name)
  devShim.depth = devShim.depth - 1
  if not ok then return nil end
  return module
end

function Loader:_installDevShim()
  for id, mod in pairs(self.mods) do
    devShim.permissions[id] = mod.manifest.permissionSet
  end
  if devShim.installed then return end
  devShim.installed = true
  local delegate = require
  _G.require = function(name, ...)
    -- only the mod's own call is the mod's doing; whatever that module
    -- requires in turn is the engine wiring itself up
    if devShim.depth == 0 then scanRequire(name) end
    devShim.depth = devShim.depth + 1
    local ok, result = pcall(delegate, name, ...)
    devShim.depth = devShim.depth - 1
    if not ok then error(result, 0) end
    return result
  end
end

-- opts.fs injects a filesystem (read/getInfo/load/getDirectoryItems, plus
-- write where enable-state should persist) so the loader runs headless under
-- plain Lua; the default is love.filesystem.  opts.dev forces the dev-mode
-- tripwire on for tests that cannot set the environment.
function Loader.new(opts)
  local dev = opts and opts.dev
  if dev == nil then
    dev = os.getenv("POKEPORT_DEV") == "1" or _G.POKEPORT_DEV_MODE == true
  end
  local self = setmetatable({
    mods = {}, loaded = {}, errors = {}, initialized = false,
    events = Events.new(), hooks = Hooks.new(), content = {}, assets = {},
    exports = {}, apis = {}, migrations = {}, order = {},
    modSave = {}, modOptions = {}, optionSchemas = {},
    optionStatus = {}, imageCache = {},
    fs = (opts and opts.fs) or (love and love.filesystem),
    dev = dev,
    -- the plain game: built-ins only, no mod discovered (the launcher's
    -- backdrop -- see Game:load's `loadWithoutMods`)
    noMods = (opts and opts.noMods) and true or nil,
  }, Loader)
  assert(self.fs, "Loader.new requires opts.fs when love is unavailable")
  for name, spec in pairs(Schemas.REGISTRIES) do
    self.content[name] = Registry.new(name, spec)
  end
  self.disabled = {}
  return self
end

-- WHICH GENERATION THIS BOOT IS.
--
-- The loader runs inside a game that has already been chosen, so "is this mod
-- on" has a generation to be answered for -- see src/mods/ModGens.lua.  Read
-- through a pcall and answered as nil when nothing is set: a headless harness
-- constructs a Loader with no version selected, and there the per-generation
-- chips simply do not apply and every mod resolves on its master switch.
function Loader:_generation()
  local okV, GameVersion = pcall(require, "src.core.GameVersion")
  if not okV then return nil end
  local okG, gen = pcall(GameVersion.generation)
  return okG and gen or nil
end

function Loader:_loadState()
  self.disabled = {}
  local options = SaveData.loadOptions(self.fs)
  local gen = self:_generation()
  for id, value in pairs(options.mods or {}) do
    -- `false` still means off, and a bare `true` still means on -- ModGens
    -- only has anything to say about the record form, which is written the
    -- moment a player unticks one of a mod's generation chips.
    if ModGens.active(value, gen) == false then self.disabled[id] = true end
  end
  -- mod.options reads through this; M11 owns writing it back
  self.modOptions = options.modOptions or {}
  -- Migrate the original prototype manager's separate state file into the
  -- normal persistent options file once.  New Game never resets options.
  if next(options.mods or {}) == nil and self.fs.getInfo
      and self.fs.getInfo(MOD_STATE_FILE) then
    local chunk = self.fs.load(MOD_STATE_FILE)
    -- `chunk and pcall(chunk)` truncates to one value, so state came back nil
    -- however well the chunk ran and the migration below never fired once:
    -- the guard has to be a statement for pcall's second return to survive.
    local ok, state = false, nil
    if chunk then ok, state = pcall(chunk) end
    if ok and type(state) == "table" then
      for id, disabled in pairs(state) do
        if disabled then
          options.mods[id] = false
          self.disabled[id] = true
        end
      end
      if self.fs.write then SaveData.saveOptions(options, self.fs) end
    end
  end
end

-- Move the enable state and options of any mod whose id has changed onto its
-- new id.  Runs once per launch and writes at most once ever per rename:
-- adoptOptions only moves a key when the new id has no state of its own and
-- the old id is not itself an installed mod, so the launch after a rename
-- finds nothing left to do.
function Loader:_adoptRenames()
  local ok, moved = pcall(function()
    local options = SaveData.loadOptions(self.fs)
    if not require("src.mods.ModRename").adoptOptions(options, self.mods) then
      return false
    end
    if self.fs.write then SaveData.saveOptions(options, self.fs) end
    return true
  end)
  -- Re-read what _loadState read before the manifests were known.  Skipped
  -- when nothing moved, which is every launch but the one after a rename.
  if ok and moved then self:_loadState() end
end

-- THE IN-GAME SWITCH IS STILL THE MASTER SWITCH -- with one asymmetry.
--
-- The manager has no per-generation chips of its own (they live in the
-- launcher), so its switch has to keep meaning what its label says:
--
--   OFF  writes the master, which is off EVERYWHERE, exactly as it always
--        was -- and with every chip ticked that is still the plain `false` the
--        loader has written since it was written.  The chips are kept, so
--        turning it back on in the launcher restores the selection.
--   ON   writes the master AND this generation's chip, because the other way
--        round is a switch that cannot be switched: a mod the player narrowed
--        to Gen 1 shows here as disabled under Emerald, and flipping only the
--        master would leave it not loading and the switch snapping back.
--
-- ONLY WHAT CHANGED, which matters more than it looks.  This used to restate
-- every mod's flag on every save, and doing that through ModGens would rewrite
-- the record of mods nobody touched -- losing chips the player set in the
-- launcher as a side effect of toggling something else.  Comparing against the
-- stored resolution first means an unchanged mod is not written at all.
function Loader:_saveState()
  -- a read-only injected fs keeps enable toggles in-memory only
  if not self.fs.write then return end
  local options = SaveData.loadOptions(self.fs)
  options.mods = options.mods or {}
  local gen = self:_generation()
  for id, mod in pairs(self.mods) do
    local want = not self.disabled[id]
    local experimental = mod.manifest and mod.manifest.experimental
    if ModGens.resolve(options.mods[id], gen, experimental) ~= want then
      options.mods[id] = want
        and ModGens.withGen(options.mods[id], gen, true)
        or ModGens.withEnabled(options.mods[id], false)
    end
  end
  SaveData.saveOptions(options, self.fs)
end

function Loader:setEnabled(id, enabled)
  if not self.mods[id] then return false end
  self.disabled[id] = not enabled
  self.mods[id].enabled = enabled
  -- the same mod under another id (Terrarium / Dramatic Shapes) cannot run
  -- beside this one: switching this on switches that off, as the launcher's
  -- menu does (ModCopies.switchOn)
  local mates = {}
  if enabled then
    pcall(function()
      mates = require("src.mods.ModCopies").slotMates(self.mods, id)
    end)
    for _, mate in ipairs(mates) do
      self.disabled[mate] = true
      self.mods[mate].enabled = false
    end
  end
  self:_saveState()
  if enabled and self.fs.write then
    pcall(function()
      local options = SaveData.loadOptions(self.fs)
      require("src.mods.ModCopies").switchOn(options, id, self.mods)
      SaveData.saveOptions(options, self.fs)
    end)
  end
  return true
end

function Loader:_discover()
  if not self.fs.getDirectoryItems then return end
  -- POKEPORT_NO_MODS=1: a verification run against the plain game, without
  -- touching the user's saved enable flags
  if os.getenv("POKEPORT_NO_MODS") == "1" or self.noMods then return end
  local roots = { "mods" }
  -- THE SAME CONFINEMENT THE LAUNCHER APPLIES.  When the player has chosen a
  -- game-data folder, a mod counts only if it is in it -- and the game has to
  -- agree with the panel about that, or the launcher hides a mod and the game
  -- loads it anyway, which is the worst of both answers.  nil (and so no
  -- filtering at all) for an injected fs, a portable install and the ordinary
  -- save-directory case, which is every setup that predates the setting.
  -- Only when this loader is running on the REAL love.filesystem: a test's
  -- injected fs has its own tree with no relationship to any root on disk, and
  -- filtering it against one would discover nothing at all.
  local confine = nil
  if love and love.filesystem and self.fs == love.filesystem then
    local okLM, LauncherMods = pcall(require, "src.mods.LauncherMods")
    if okLM and LauncherMods and LauncherMods.confinedRoot then
      local okRoot, root = pcall(LauncherMods.confinedRoot)
      if okRoot then confine = root end
    end
  end
  -- EVERY COPY, THEN ONE PER ID (src/mods/ModCopies.lua).  This used to keep
  -- whichever folder getDirectoryItems listed first and file the others as
  -- "duplicate mod id" errors -- so which version ran depended on directory
  -- order, an older copy could win over the update next to it, and the same
  -- folder name in the save directory and the game folder loaded as one mod
  -- stitched together from both.  A dev-linked mod dir (ln -s) reports type
  -- "symlink" and is scanned like a directory.
  local ModCopies = require("src.mods.ModCopies")
  local fs = self.fs
  local scan = ModCopies.scan(fs, {
    root = roots[1],
    decode = function(raw, path)
      local data, decodeErr = Json.decode(raw)
      if not data then return nil, decodeErr end
      local ok, manifest = pcall(Manifest.validate, data, path)
      if not ok then return nil, manifest end
      return manifest
    end,
    -- with a chosen game-data folder only it and the game's own source
    -- count, decided per copy so a stale save-directory copy in front of
    -- the chosen folder's cannot hide it
    allowReal = confine and require("src.mods.ModCopies").confinedTo(confine) or nil,
    -- peeking inside a zip needs the real filesystem
    peekZip = (love and love.filesystem and fs == love.filesystem) and nil or false,
  })
  for id, copy in pairs(scan.winners) do
    self.mods[id] = { manifest = copy.manifest, path = copy.path,
                      home = copy.home, where = copy.where }
  end
  self.ignoredCopies = {}
  for _, row in ipairs(scan.ignored) do
    local c, w = row.copy, row.winner
    self.ignoredCopies[#self.ignoredCopies + 1] = {
      id = c.id, version = c.version, path = c.where or c.path, home = c.home,
      winner = w.where or w.path, winnerVersion = w.version, reason = row.reason,
    }
    Logger.info("mod %s: loading %s %s from %s; ignoring the copy at %s -- %s",
      tostring(c.id), tostring(w.version), w.home or "?", tostring(w.where or w.path),
      tostring(c.where or c.path), tostring(row.reason))
  end
  self.zipNotes = {}
  for _, z in ipairs(scan.zips) do
    self.zipNotes[#self.zipNotes + 1] = z
    if z.status == "newer" or z.status == "not_installed" then
      Logger.warn("mods: %s", z.note)
    else
      Logger.info("mods: %s", z.note)
    end
  end
  for _, note in ipairs(scan.notes) do Logger.warn("mods: %s", note) end
  for _, bad in ipairs(scan.invalid) do
    Logger.warn("mod %s ignored: %s", bad.path, tostring(bad.err))
  end
  local ok, err = pcall(self._warnShadowed, self)
  if not ok then
    Logger.debug("mod shadow check: %s", tostring(err))
  end
end

-- A MOD THE SAVE DIRECTORY IS SHADOWING, SAID OUT LOUD.
--
-- love.filesystem reads `mods/` out of TWO homes -- the save directory and
-- the game folder -- and it searches the SAVE DIRECTORY FIRST.  So a copy
-- left there wins over the checkout the author is editing, and LauncherMods
-- already names the symptom in its own words: "the author's own edits
-- silently stop taking effect while the folder they are editing looks
-- untouched.  That is a worse failure than not updating, and it is
-- invisible."
--
-- Reported from play: "when pressing the button mapped to select in the
-- options its still just adjusting the voxels and not working properly not
-- using my registered item in gen3" -- with the change that stops it doing
-- exactly that sitting in the checkout, unread, behind a save-directory copy
-- of the same mod from two days earlier.  Every file said what it should
-- have said; the running game was reading a different one, and nothing
-- anywhere mentioned that a second one existed.
--
-- THIS IS NOT AN ERROR.  Installing a release over a checkout is a
-- legitimate thing to do and the mod loads fine either way.  It is one line
-- in the log naming BOTH files, which is all it ever needed to stop being
-- invisible -- and only when the two differ, so an install of the same build
-- says nothing.
--
-- The read is its own field so a test can stand in for the disk: this is the
-- one check in the loader that deliberately goes around love.filesystem,
-- because love.filesystem is precisely what cannot see the difference.
function Loader.readRealFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

function Loader:_warnShadowed()
  local fs = self.fs
  if not (fs and fs.getSaveDirectory) then return end
  local saveRoot = fs.getSaveDirectory()
  if type(saveRoot) ~= "string" or saveRoot == "" then return end
  local ok, Launcher = pcall(require, "src.mods.LauncherMods")
  if not (ok and type(Launcher) == "table"
          and type(Launcher.realFolder) == "function") then
    return
  end
  local sep = package.config:sub(1, 1)
  local read = Loader.readRealFile
  for id, mod in pairs(self.mods) do
    local okReal, gameDir = pcall(Launcher.realFolder, mod.path)
    gameDir = okReal and type(gameDir) == "string" and gameDir or nil
    if gameDir then
      local saveDir = saveRoot .. sep .. (mod.path:gsub("/", sep))
      -- the entry chunk is what a mod's behaviour lives in; the manifest is
      -- the fallback so a mod whose entry is named something else is still
      -- compared rather than skipped
      local said = false
      for _, name in ipairs({ "main.lua", "manifest.json" }) do
        if not said then
          local mine = read(saveDir .. sep .. name)
          local theirs = read(gameDir .. sep .. name)
          if mine and theirs and mine ~= theirs then
            said = true
            Logger.warn("mod %s: the copy in the save directory is the one "
                        .. "being loaded and it is NOT the one in the game "
                        .. "folder -- love.filesystem searches the save "
                        .. "directory first, so edits here do nothing until "
                        .. "that copy is refreshed or removed.  loaded: %s "
                        .. "// ignored: %s", id, saveDir .. sep .. name,
                        gameDir .. sep .. name)
          end
        end
      end
    end
  end
end

-- ------- validate and resolve

-- a failed mod keeps the user's enable flag (the manager still shows it as
-- enabled-but-broken) and is treated as absent by every later phase
function Loader:_fail(mod, state, reason)
  if mod.failed then return end
  mod.failed, mod.state, mod.failure = true, state, reason
  self.errors[#self.errors + 1] = mod.manifest.id .. ": " .. reason
  Logger.error("mod %s failed: %s", mod.manifest.id, reason)
end

local function isActive(mod)
  -- a superseded mod keeps the player's flag and simply does not run: another
  -- enabled copy of the same mod does (src/mods/ModCopies.lua)
  return mod.enabled and not mod.failed and not mod.superseded
end

function Loader:_exists(path)
  if not self.fs.getInfo then return true end
  return self.fs.getInfo(path) ~= nil
end

-- static per-manifest checks that need the filesystem or the engine version.
-- Enabled mods only: a mod the user switched off is not a boot problem
function Loader:_validate()
  for _, id in ipairs(orderedIds(self.mods, isActive)) do
    local mod = self.mods[id]
    local manifest = mod.manifest
    local reason
    if not self:_exists(mod.path .. "/" .. manifest.entry) then
      reason = "entry file missing: " .. manifest.entry
    elseif manifest.options_schema
        and not self:_exists(mod.path .. "/" .. manifest.options_schema) then
      reason = "options_schema file missing: " .. manifest.options_schema
    elseif manifest.assets_transforms
        and not self:_exists(mod.path .. "/" .. manifest.assets_transforms) then
      reason = "assets_transforms file missing: " .. manifest.assets_transforms
    elseif manifest.game_version then
      local ok, err = Semver.satisfies(Version.engine, manifest.game_version)
      if not ok then
        reason = ("needs game version %s, engine is %s")
          :format(manifest.game_version, Version.engine)
        if err then reason = reason .. " (" .. err .. ")" end
      end
    end
    if reason then self:_fail(mod, "invalid", reason) end
  end
end

-- hard dependencies must exist, be enabled, have survived, and satisfy their
-- range; run to a fixpoint so failures propagate to dependents transitively
function Loader:_enforceDependencies()
  local changed = true
  while changed do
    changed = false
    for _, id in ipairs(orderedIds(self.mods, isActive)) do
      local mod = self.mods[id]
      for _, spec in ipairs(mod.manifest.dependencySpecs) do
        local dep = self.mods[spec.id]
        local reason
        if not dep then
          reason = "missing dependency: " .. spec.id
        elseif not dep.enabled then
          reason = ("dependency %s is disabled"):format(spec.id)
        elseif dep.failed then
          reason = ("dependency %s failed to load"):format(spec.id)
        elseif dep.superseded then
          reason = ("dependency %s is not loaded: %s"):format(spec.id,
            tostring(dep.supersededBy))
        elseif spec.range
            and not Semver.satisfies(dep.manifest.version, spec.range) then
          reason = ("needs %s@%s, found %s")
            :format(spec.id, spec.range, dep.manifest.version)
        end
        if reason then
          self:_fail(mod, "blocked_dependency", reason)
          changed = true
          break
        end
      end
    end
  end
end

-- Tarjan SCC over the hard-dependency graph: only a cycle's own members
-- fail, so an unrelated mod beside a cycle still loads
function Loader:_failCycles()
  local mods = self.mods
  local counter, stack, onStack, index, low = 0, {}, {}, {}, {}
  local cycles = {}
  local function connect(id)
    counter = counter + 1
    index[id], low[id] = counter, counter
    stack[#stack + 1] = id
    onStack[id] = true
    local selfEdge = false
    for _, spec in ipairs(mods[id].manifest.dependencySpecs) do
      local dep = mods[spec.id]
      if spec.id == id then selfEdge = true end
      if dep and isActive(dep) and spec.id ~= id then
        if not index[spec.id] then
          connect(spec.id)
          if low[spec.id] < low[id] then low[id] = low[spec.id] end
        elseif onStack[spec.id] and index[spec.id] < low[id] then
          low[id] = index[spec.id]
        end
      end
    end
    if low[id] == index[id] then
      local component = {}
      repeat
        local top = table.remove(stack)
        onStack[top] = false
        component[#component + 1] = top
      until top == id
      if #component > 1 or selfEdge then cycles[#cycles + 1] = component end
    end
  end
  for _, id in ipairs(orderedIds(mods, isActive)) do
    if not index[id] then connect(id) end
  end
  for _, component in ipairs(cycles) do
    table.sort(component)
    local trace = table.concat(component, " -> ") .. " -> " .. component[1]
    for _, id in ipairs(component) do
      self:_fail(mods[id], "blocked_dependency", "circular dependency: " .. trace)
    end
  end
end

-- the declaring mod loses: it asserted the incompatibility, and judging every
-- claim against one snapshot makes a mutual pair fail together
function Loader:_enforceConflicts()
  local doomed = {}
  for _, id in ipairs(orderedIds(self.mods, isActive)) do
    local mod = self.mods[id]
    for _, spec in ipairs(mod.manifest.conflictSpecs) do
      local other = self.mods[spec.id]
      if other and isActive(other)
          and (not spec.range
            or Semver.satisfies(other.manifest.version, spec.range)) then
        doomed[#doomed + 1] = { mod = mod,
          reason = ("conflicts with %s %s"):format(spec.id, other.manifest.version) }
        break
      end
    end
  end
  for _, entry in ipairs(doomed) do
    self:_fail(entry.mod, "conflict", entry.reason)
  end
end

-- Kahn over the surviving graph with the ready set kept in (priority, id)
-- order, so dependencies come first and the rest matches the v1 contract
function Loader:_order()
  local pending, indegree, dependents = {}, {}, {}
  for _, id in ipairs(orderedIds(self.mods, isActive)) do
    pending[id], indegree[id] = true, 0
  end
  for id in pairs(pending) do
    local manifest = self.mods[id].manifest
    local function edge(depId)
      if not pending[depId] or depId == id then return end
      dependents[depId] = dependents[depId] or {}
      dependents[depId][#dependents[depId] + 1] = id
      indegree[id] = indegree[id] + 1
    end
    for _, spec in ipairs(manifest.dependencySpecs) do edge(spec.id) end
    -- optional dependencies order without requiring anything
    for _, spec in ipairs(manifest.optionalSpecs) do edge(spec.id) end
  end
  local ordered = {}
  local function nextId()
    local best
    for id in pairs(pending) do
      if indegree[id] == 0 then
        if not best then
          best = id
        else
          local pa, pb = self.mods[id].manifest.priority,
            self.mods[best].manifest.priority
          if pa < pb or (pa == pb and id < best) then best = id end
        end
      end
    end
    if best then return best end
    -- optional dependencies can close a loop the hard-dependency cycle check
    -- deliberately ignores; break it at the lowest-ordered id rather than
    -- silently dropping the mods
    local leftovers = {}
    for id in pairs(pending) do leftovers[#leftovers + 1] = id end
    if #leftovers == 0 then return nil end
    table.sort(leftovers)
    Logger.warn("optional dependency loop broken at %s", leftovers[1])
    return leftovers[1]
  end
  while true do
    local id = nextId()
    if not id then break end
    pending[id], indegree[id] = nil, nil
    ordered[#ordered + 1] = self.mods[id]
    for _, dependent in ipairs(dependents[id] or {}) do
      if indegree[dependent] then indegree[dependent] = indegree[dependent] - 1 end
    end
  end
  return ordered
end

-- merge order is a property of the target paths, never of pairs(): a
-- whole-table registry ("audio") has to land before the granular ones nested
-- under it ("audio.sfx"), or its subtable swap discards every id they already
-- wrote into the object it replaces.  A strict prefix always has fewer
-- segments, so shallowest-first buys that; the name breaks ties so the same
-- content always merges the same way.
function Loader:_mergeOrder()
  local names, depth = {}, {}
  for name, registry in pairs(self.content) do
    names[#names + 1] = name
    local segments = 0
    for _ in (registry.spec.target or ""):gmatch("[^%.]+") do
      segments = segments + 1
    end
    depth[name] = segments
  end
  table.sort(names, function(a, b)
    if depth[a] ~= depth[b] then return depth[a] < depth[b] end
    return a < b
  end)
  return names
end

function Loader:_resolve()
  self:_enforceDependencies()
  self:_failCycles()
  self:_enforceDependencies()
  self:_enforceConflicts()
  self:_enforceDependencies()
  return self:_order()
end

-- per-registry accessor bound to one mod: schema violations are load
-- errors for api 2 mods and attributed warnings for api 1 (compat), and a
-- deprecated name warns once per mod on first use
function Loader:_contentApi(mod, registry, deprecation)
  local loader = self
  local modId = mod.manifest.id
  local apiLevel = mod.manifest.api or 1
  local warned = false
  local function note()
    if deprecation and not warned then
      warned = true
      Logger.warn("[%s] %s", modId, deprecation)
    end
  end
  local function validate(mode, id, value)
    local ok, err = Schemas.check(registry.spec, registry.name, id, value, mode)
    if ok then return end
    if apiLevel >= 2 then error(err, 0) end
    Logger.warn("[%s] %s", modId, err)
  end
  return {
    register = function(_, id, value)
      note()
      validate("register", id, value)
      loader:_journal(registry.name)
      return registry:register(id, value, modId)
    end,
    override = function(_, id, value)
      note()
      validate("override", id, value)
      loader:_journal(registry.name)
      return registry:override(id, value, modId)
    end,
    patch = function(_, id, partial)
      note()
      validate("patch", id, partial)
      loader:_journal(registry.name)
      return registry:patch(id, partial, modId)
    end,
    remove = function(_, id)
      note()
      loader:_journal(registry.name)
      return registry:remove(id, modId)
    end,
    get = function(_, id)
      note()
      return registry:get(id)
    end,
    each = function()
      note()
      return registry:each()
    end,
  }
end

-- mod.commands is sugar over the commands registry; the engine's own verbs
-- are registered there too, so replacing one has to say override
function Loader:_registerCommand(modId, verb, fn)
  assert(type(verb) == "string" and verb ~= "", "command verb is required")
  assert(type(fn) == "function", "command handler must be a function")
  self:_journal("commands")
  return self.content.commands:register(verb, fn, modId)
end

-- WHICH COPY OF A MOD IS ACTUALLY RUNNING.
--
-- A version string answers this only when the author bumps it, and during
-- development nobody does -- so a session that loaded a file edited thirty
-- seconds ago and one that loaded yesterday's log the same line.  Four rounds
-- of "it is still broken" turned out to be four launches that predated the
-- fix, and from the log there was no way to tell.
--
-- So the load line carries the mod's NEWEST file and when it was written.  It
-- costs one directory walk per mod per boot, two levels deep and capped,
-- because the point is a stamp rather than an inventory: a mod's source lives
-- in its root and in lib/, and a file newer than both is not what got loaded
-- anyway.
local FRESHNESS_CAP = 600

function Loader.freshness(fs, root)
  if not (fs and fs.getDirectoryItems and fs.getInfo and root) then return "" end
  local newest, newestName, seen = 0, nil, 0
  local function scan(dir, depth)
    local okList, items = pcall(fs.getDirectoryItems, dir)
    if not (okList and type(items) == "table") then return end
    for _, name in ipairs(items) do
      if seen >= FRESHNESS_CAP then return end
      local path = dir .. "/" .. name
      local okInfo, info = pcall(fs.getInfo, path)
      if okInfo and type(info) == "table" then
        if info.type == "directory" then
          if depth < 1 then scan(path, depth + 1) end
        else
          seen = seen + 1
          local t = tonumber(info.modtime)
          if t and t > newest then newest, newestName = t, name end
        end
      end
    end
  end
  scan(root, 0)
  if newest <= 0 then return "" end
  local when = os.date("!%Y-%m-%d %H:%M:%SZ", newest)
  return (" (newest file %s, %s)"):format(tostring(newestName), when)
end

function Loader:_api(mod)
  local loader = self
  local modId = mod.manifest.id
  -- WHICH GAME THE MOD IS RUNNING IN, read once, here.
  --
  -- From a log where every line is the same gap wearing a different coat, on
  -- a mod that has a working generation 3 path:
  --
  --   [runtime] environment api=unknown
  --   Colosseum UI runtime compatibility: gen1            <- on Emerald
  --   ColosseumDex mark routing blocked: host generation unavailable
  --   Gen 2 Colosseum battle transition class unavailable <- a white screen
  --   pokemon.PIKACHU.types[1]: unresolved reference to type_chart "ELECTR"
  --
  -- A mod that spans generations has to know which one it is in before it
  -- chooses a data set, a battle transition or a type chart -- and there was
  -- nothing on this table to ask.  `engineRequire("src.core.GameVersion")`
  -- reaches it, but a mod written against another port's layout does not know
  -- that name, and the failure is not an error: it falls back to generation 1
  -- and every symptom downstream reads as an engine fault.
  --
  -- Read once, when the api is built -- which is after the version is chosen
  -- and before the mod's entry chunk runs -- and handed over as VALUES.  A
  -- mod holding these can no more change the running game than it could
  -- before, and the generation cannot move under it: a version change is a
  -- new game and a new load.
  local hostGen, hostId, hostInfo = 1, nil, nil
  do
    local okV, GameVersion = pcall(engineRequire, "src.core.GameVersion")
    if okV and GameVersion then
      local okG, g = pcall(GameVersion.generation)
      if okG and tonumber(g) then hostGen = tonumber(g) end
      local okI, id = pcall(GameVersion.get)
      if okI then hostId = id end
      local okN, info = pcall(GameVersion.info)
      if okN then hostInfo = info end
    end
  end
  -- Capture pristine ID aliases before mod merges; the facade resolves Game only on a read.
  local battle = BattleSnapshots.new(function() return loader:_game(true) end, loader)
  local engineVersion
  do
    local okE, V = pcall(engineRequire, "src.core.Version")
    engineVersion = okE and V and V.engine or nil
  end
  local api = {
    id = modId,
    version = mod.manifest.version,
    path = mod.path,
    -- WHETHER THE HOST IS IN DEV MODE, as a plain boolean.
    --
    -- A mod ported from the Gen 1 project asks this to decide whether to
    -- register its developer-only diagnostics (an overlay, a debug command).
    -- It is read once here and copied, so the answer a mod gets is a value
    -- and not a door: nothing about it reaches the loader, the process
    -- environment or the dev-mode require shim.
    developer = loader.dev == true,
    -- THE ENGINE'S OWN MODULES, by name.
    --
    -- A mod chunk already runs under the engine's searcher, so plain `require`
    -- reaches them -- but that is a fact about the loader that no mod should
    -- have to discover, and a mod that wraps `require` for its own libs (this
    -- is common) loses it.  Named here so the seam is a documented field
    -- rather than a coincidence.  Read-only in the sense that matters: it
    -- returns the same module table the engine holds, so a mod that mutates
    -- one is changing the engine, exactly as it always was.
    engineRequire = engineRequire,
    battle = battle,
    -- 1 to 5.  The one field worth reaching for before anything else.
    generation = hostGen,
    -- the version id the launcher started: "red", "crystal", "emerald",
    -- "platinum", "heartgold", "soulsilver", "black", "white", "prism",
    -- "polishedcrystal"
    gameVersion = hostId,
    -- ...and the same three plus the trimmings, for a mod that would rather
    -- read one table than three fields.  `name` is what the game calls
    -- itself, not an id to branch on -- branch on `generation` or `version`.
    host = {
      generation = hostGen,
      version = hostId,
      name = hostInfo and hostInfo.displayName or hostId,
      label = hostInfo and hostInfo.label or hostId,
      engine = engineVersion,
      modApi = (function()
        local okE, V = pcall(engineRequire, "src.core.Version")
        return okE and V and V.modApi or nil
      end)(),
      developer = loader.dev == true,
    },
    -- a deep copy: what a mod does to its own view never reaches the loader
    manifest = Merge.deepCopy(mod.manifest),
    callbackFormat = mod.manifest.callback_format or "native",
    content = {},
    exports = {},
    DELETE = Registry.DELETE,
    events = {
      on = function(_, name, callback, priority)
        return loader.events:on(name, callback, priority, modId)
      end,
      once = function(_, name, callback, priority)
        return loader.events:once(name, callback, priority, modId)
      end,
      -- mods broadcast under their own prefix only, so no mod can forge an
      -- engine event; exports stay the call-style channel
      emit = function(_, name, payload)
        local prefix = "mod." .. modId .. "."
        if type(name) ~= "string" or name:sub(1, #prefix) ~= prefix then
          error(("[%s] mods may only emit %s* events"):format(modId, prefix), 0)
        end
        return loader.events:emit(name, payload)
      end,
    },
    hooks = { wrap = function(_, name, callback, priority)
      return loader.hooks:wrap(name, callback, priority, modId)
    end },
    -- Per-mod action/revision state, with the existing lazy widget builders.
    -- Reading the facade early must not construct Game or a native screen.
    ui = UIActions.new(function() return loader:_game(true) end, loader, ModUI),
    -- namespaced per mod; M11 backs these with save.modData /
    -- options.modOptions, the shape mods compile against is already final
    save = {
      get = function(_, key, default)
        local bucket = loader.modSave[modId]
        local value = bucket and bucket[key]
        if value == nil then return default end
        return value
      end,
      set = function(_, key, value)
        local bucket = loader.modSave[modId]
        if not bucket then
          bucket = {}
          loader.modSave[modId] = bucket
        end
        bucket[key] = value
      end,
    },
    options = {
      define = function(_, schema)
        assert(type(schema) == "table", "options schema must be a table of rows")
        for _, row in ipairs(schema) do
          assert(type(row) == "table" and type(row.key) == "string" and row.key ~= "",
            "each options row needs a string key")
        end
        loader.optionSchemas[modId] = schema
        return schema
      end,
      get = function(_, key)
        local stored = loader.modOptions[modId]
        if stored ~= nil and stored[key] ~= nil then return stored[key] end
        for _, row in ipairs(loader.optionSchemas[modId] or {}) do
          if row.key == key then return row.default end
        end
        return nil
      end,
      -- Publish the live VALUE shown on an `action` row: "47/210", "DONE",
      -- nil to clear. Display only -- nothing is stored, nothing is saved,
      -- and a mod can only ever write under its own id -- so a long job
      -- reports its progress on the very row that started it.
      -- `text` may also be a FUNCTION returning the text, which is what a
      -- running job wants: the manager calls it as it redraws, so progress
      -- moves on screen without the mod polling a clock it may not have.
      status = function(_, key, text)
        assert(type(key) == "string" and key ~= "",
          "options status needs a row key")
        local bucket = loader.optionStatus[modId]
        if not bucket then
          bucket = {}
          loader.optionStatus[modId] = bucket
        end
        if text == nil or type(text) == "function" then
          bucket[key] = text
        else
          bucket[key] = tostring(text)
        end
        return bucket[key]
      end,
    },
    commands = { register = function(_, verb, fn)
      return loader:_registerCommand(modId, verb, fn)
    end },
    -- M11 runs these against save.meta; recording them is what M2 owes
    migrations = { add = function(_, since, fn)
      assert(type(since) == "string" and since ~= "",
        "migrations need the version they upgrade from")
      assert(type(fn) == "function", "migration must be a function")
      local list = loader.migrations[modId]
      if not list then
        list = {}
        loader.migrations[modId] = list
      end
      list[#list + 1] = { since = since, apply = fn }
      return fn
    end },
    log = {
      info = function(_, fmt, ...) Logger.info("[%s] " .. fmt, modId, ...) end,
      warn = function(_, fmt, ...) Logger.warn("[%s] " .. fmt, modId, ...) end,
      error = function(_, fmt, ...) Logger.error("[%s] " .. fmt, modId, ...) end,
    },
  }
  self.exports[modId] = api.exports
  if api.callbackFormat == "unified" then
    engineRequire("src.mods.UnifiedCallbacks").install(loader, api, modId, hostGen)
  end
  -- a handle, not the mod object: {id, version, exports} or nil when the
  -- other mod is absent, disabled, failed, or has not run yet.  Tolerates
  -- mod:find(id) as well as the documented mod.find(id).
  api.find = function(first, second)
    local otherId = second == nil and first or second
    local other = loader.mods[otherId]
    if not other or not isActive(other) then return nil end
    local exports = loader.exports[otherId]
    if exports == nil then return nil end
    return { id = otherId, version = other.manifest.version, exports = exports }
  end
  for name, registry in pairs(self.content) do
    local deprecation = registry.spec.deprecated
      and ("the %s registry is deprecated; use %s")
        :format(name, registry.spec.deprecated.useInstead)
    api.content[name] = self:_contentApi(mod, registry, deprecation)
  end
  for alias, canonical in pairs(Schemas.ALIASES) do
    api.content[alias] = self:_contentApi(mod, self.content[canonical],
      ("the %s registry is deprecated; use %s"):format(alias, canonical))
  end
  api.contentFormat = mod.manifest.content_format or "native"
  if api.contentFormat == "unified" then
    api.content = engineRequire("src.mods.UnifiedContent").new(loader, mod, api.content, hostGen)
  end
  -- assets keeps the v1 alias to the content accessors and adds the file
  -- helpers on top, so mod.assets.pokemon and mod.assets:image both resolve
  -- A RELATIVE PATH STAYS RELATIVE.
  --
  -- mod.assets:path, mod:read and the two listers below all end in a bare
  -- concatenation onto mod.path, and love.filesystem is rooted at the save
  -- directory plus the game folder -- so `mod:list("../OTHER_MOD")` is not a
  -- host-filesystem escape, but it IS a walk out of this mod and into the
  -- next one's folder, which is the sandbox these accessors exist to draw.
  -- Enumeration makes it worth closing: reading a path you guessed is one
  -- thing, listing a neighbour's folder to find out what to guess is another.
  --
  -- Returns nil for anything that leaves the mod, and the caller answers the
  -- way it answers a missing file -- an escape is not a special error, it is
  -- simply not there.
  local function within(relative)
    if type(relative) ~= "string" then return nil end
    if relative == "" then return mod.path end
    if relative:sub(1, 1) == "/" or relative:find("^%a:") then return nil end
    if relative:find("\\", 1, true) then return nil end
    local parts = {}
    for segment in relative:gmatch("[^/]+") do
      if segment == ".." then return nil end
      if segment ~= "." then parts[#parts + 1] = segment end
    end
    if not parts[1] then return mod.path end
    return mod.path .. "/" .. table.concat(parts, "/")
  end

  -- WHAT IS AT A PATH INSIDE THIS MOD, and WHAT IS IN A FOLDER OF IT.
  --
  -- A mod that ships a folder of optional content -- one file per species, a
  -- pack of maps -- has to be able to see what actually arrived, and until
  -- now the only answer was mod:read on a name it had to already know.  Sorted
  -- because love.filesystem.getDirectoryItems is not: a mod that walks the
  -- list and builds an index off it would otherwise order itself differently
  -- on a different machine.
  local function listIn(relative)
    local dir = within(relative)
    local fs = loader.fs
    if not (dir and fs and fs.getDirectoryItems) then return {} end
    local items = fs.getDirectoryItems(dir) or {}
    local out = {}
    for i = 1, #items do out[i] = items[i] end
    table.sort(out)
    return out
  end

  local function infoIn(relative)
    local path = within(relative)
    local fs = loader.fs
    if not (path and fs and fs.getInfo) then return nil end
    local info = fs.getInfo(path)
    if not info then return nil end
    -- a copy, not love's own record: what a mod does to it stays with the mod
    return { type = info.type, size = info.size, modtime = info.modtime }
  end

  api.assets = setmetatable({
    path = function(_, relative) return mod.path .. "/" .. relative end,
    list = function(_, relative) return listIn(relative) end,
    info = function(_, relative) return infoIn(relative) end,
    image = function(_, relative)
      local full = mod.path .. "/" .. relative
      local cached = loader.imageCache[full]
      if cached then return cached end
      assert(love and love.graphics,
        ("[%s] mod.assets:image needs a graphics context"):format(modId))
      local image = love.graphics.newImage(full)
      loader.imageCache[full] = image
      return image
    end,
  }, { __index = api.content })
  function api:read(relative)
    local path = self.path .. "/" .. relative
    return loader.fs.read(path)
  end
  -- the same two on the api itself, because a Gen 1 mod spells them mod:list
  -- and mod:info rather than mod.assets:list
  function api:list(relative) return listIn(relative) end
  function api:info(relative) return infoIn(relative) end
  -- `required_imports`: base files the player supplies (see
  -- src/mods/ModImports.lua).  They are written into the mod's own folder, so
  -- mod:read already reaches them -- this is the polite way to ask whether one
  -- has arrived before starting a long extract.
  --
  -- ...AND `mod.cache`, WHICH IS mod.storage UNDER THE GEN 1 NAME.  Both come
  -- from one call so the pair is built the same way for every mod; see
  -- src/mods/ImportAccess.lua for why neither is a second implementation.
  api.imports, api.cache = ImportAccess.new(mod.manifest, loader.fs,
    function(rel)
      local data = loader.fs.read(mod.path .. "/" .. rel)
      -- a copy read through its own mount (ModCopies) still finds a base
      -- file the player imported into the folder under its logical name
      if data == nil and mod.manifest.path and mod.manifest.path ~= mod.path then
        data = loader.fs.read(mod.manifest.path .. "/" .. rel)
      end
      return data
    end)
  -- Capture the host selected for this API, as with generation/gameVersion.
  -- Probing must not instantiate mod.world/mod.game or register callbacks.
  function api:supports(surface, name)
    return Capabilities.supports(surface, name, hostId)
  end
  -- mod.world / mod.game / mod.storage all materialize on first touch, for
  -- the same reason: a headless load must not drag the world stack in.
  -- Battle capability queries can also be installed before Game exists.
  BattleSnapshots.withCapabilities(api)
  UIActions.withCapabilities(api)
  -- The Game the facade acts on is still being wired when the entry chunk
  -- runs.  mod.storage is the bulk counterpart to mod.save -- one sandboxed
  -- namespace per mod for payloads too large to belong in a save file.
  -- When capability queries are installed, these additive methods exist on
  -- every host; individual actions still validate native version and state.
  if api.supports then
    local supports = api.supports
    function api:supports(surface, name)
      if surface == "world" and WorldActions.supports(name) then return true end
      return supports(self, surface, name)
    end
  end
  local world, storage
  local overviewContext = WorldOverview.install(api, loader)
  local readContext = WorldReads.context(loader)
  -- Capability queries are optional on older API-2 hosts. When present,
  -- report the additive readers without constructing Game or the world.
  if api.supports then
    local supports = api.supports
    function api:supports(surface, name)
      if surface == "world" and WorldReads.supports(name) then return true end
      return supports(self, surface, name)
    end
  end
  setmetatable(api, PortableScripts.wrap({ __index = function(_, key)
    if key == "game" then return loader:_game() end
    if key == "storage" then
      -- Do not pass loader.fs when it is love.filesystem: that always writes
      -- the OS save directory and leaves modstorage/ on internal storage.
      -- Storage.fsOr routes the live LOVE fs through CacheFs.dataFs.
      if not storage then storage = ModStorage.new(modId, loader.fs) end
      return storage
    end
    if key ~= "world" then return nil end
    if world then return world end
    local game = loader:_game()
    local module = game and engineRequire("src.world.WorldAPI")
    if not module then return nil end
    world = module.new(game, modId, readContext)
    world.overviewContext = overviewContext
    return world
  end }, api, loader, mod.manifest))
  -- When capability queries are installed, report the selected content
  -- format's actual availability. Other surfaces retain their host query.
  if api.contentFormat == "unified" and api.supports then
    local supports, content = api.supports, api.content
    api.supports = function(self, surface, name)
      local handle = type(name) == "string" and content[name]
      if surface == "content" and handle and handle.supports then return handle:supports() end
      return supports(self, surface, name)
    end
  end
  if (mod.manifest.api or 1) >= 3 then
    engineRequire("src.mods.Api3").install(api, loader, readContext, overviewContext, engineRequire)
  end
  return api
end

-- the live Game.  An injected reference wins so a headless caller can hand
-- over a stub; otherwise the boot singleton, whose stack and overworld fill
-- in after this loader returns -- holding the table keeps the facade live.
function Loader:_game(loadedOnly)
  if self.game then return self.game end
  -- Observational facades must not bootstrap Game from an early/headless read.
  if loadedOnly then
    local game = package.loaded["src.core.Game"]
    return type(game) == "table" and game or nil
  end
  return engineRequire("src.core.Game")
end

function Loader:_loadMod(mod)
  local path = mod.path .. "/" .. mod.manifest.entry
  local chunk, err = self.fs.load(path)
  if not chunk then error(err or ("unable to load " .. path)) end
  -- A mod whose declared base file never arrived loads fine and then does
  -- nothing, which from the log looks identical to a mod that is simply
  -- quiet.  Say which file is missing (src/mods/ModImports.lua).
  do
    for _, row in ipairs(ModImports.missing(mod.manifest) or {}) do
      Logger.warn("[%s] needs %s at %s; import it from the mods panel",
        mod.manifest.id, tostring(row.entry.name), tostring(row.entry.file))
    end
  end
  local api = self:_api(mod)
  -- KEEP THE API OBJECT, not only its exports.
  --
  -- `self.exports[id]` has always been the mod's published surface, and that is
  -- what OTHER MODS see.  What was thrown away is the api the mod itself holds
  -- -- mod.imports, mod.cache, mod.assets -- which is exactly what you need
  -- when a mod reports that its base file is missing while every engine-side
  -- check says it is there.  Asking a freshly built api the same question
  -- cannot answer that, because the whole question is whether the object the
  -- mod is holding differs from the one the engine would build.
  self.apis = self.apis or {}
  self.apis[mod.manifest.id] = api
  local result = chunk(api)
  if type(result) == "function" then result(api) end
  -- a mod that replaced the table wholesale (mod.exports = {...}) still
  -- publishes what its dependents will see
  self.exports[mod.manifest.id] = api.exports
end

-- remember which registries a mod touched so a failing entry chunk can be
-- undone with one owner-wide op purge per registry
function Loader:_journal(name)
  local journal = self.journal
  if journal then journal[name] = true end
end

-- a failing mod leaves zero residue: its ops are dropped before the merge
-- loop ever runs, and every subscription, export, command, option schema and
-- migration it took goes with them.  The journal only exists around an
-- entry chunk; a later failure (script validation) purges every registry.
function Loader:_rollback(modId)
  Api3Warp.cancelAll(self, modId)
  PortableScripts.cancelAll(self, modId, "mod rolled back")
  for name in pairs(self.journal or self.content) do
    self.content[name]:rollback(modId)
  end
  self.events:removeOwner(modId)
  self.hooks:removeOwner(modId)
  self.exports[modId] = nil
  self.optionSchemas[modId] = nil
  self.optionStatus[modId] = nil
  self.migrations[modId] = nil
  self.modSave[modId] = nil
end

-- a mod that explicitly swears it stays link-compatible while writing into a
-- link-relevant registry gets one attributed warning; the default for a
-- content profile is not a claim, so only a written affects_link is judged.
-- The fingerprint itself is derived from merged data either way (M12)
function Loader:_checkLinkClaims(mod)
  if mod.manifest.raw.affects_link ~= false then return end
  for name, registry in pairs(self.content) do
    if Manifest.LINK_REGISTRIES[name] then
      for _, list in pairs(registry.ops) do
        for _, entry in ipairs(list) do
          if entry.owner == mod.manifest.id then
            Logger.warn("[%s] declares affects_link = false but writes to %s",
              mod.manifest.id, name)
            return
          end
        end
      end
    end
  end
end

-- ------- script validation (09 §4.9)

-- Every row list reachable from a map_scripts contribution is checked
-- against the merged command set once all entry chunks have run, before the
-- merge writes the chains home.  Findings fail an api 2 owner outright --
-- the mod is purged like an entry-chunk error -- while api 1 and engine
-- owners keep the v1 runtime skip and get attributed warnings.
function Loader:_validateScripts()
  local registry = self.content.map_scripts
  if not registry or next(registry.ops) == nil then return end
  local MapScripts = engineRequire("src.script.MapScripts")
  if not MapScripts then return end
  local commands = self.content.commands
  local function lookup(verb) return commands:get(verb) ~= nil end
  local failed = false
  for mapId in pairs(registry.ops) do
    local chain = registry:chain(mapId)
    local owners = registry:chainOwners(mapId)
    for i = 1, #chain do
      local findings = MapScripts.validateContribution(chain[i], lookup)
      if #findings > 0 then
        local owner = owners[i]
        local mod = owner and self.mods[owner]
        local reason = ("map_scripts %s: %s"):format(mapId,
          table.concat(findings, "; "))
        if mod and (mod.manifest.api or 1) >= 2 then
          self:_fail(mod, "failed", reason)
          failed = true
        else
          Logger.warn("[%s] %s", tostring(owner or Schemas.ENGINE), reason)
        end
      end
    end
  end
  if not failed then return end
  -- purge the failed mods and whatever dependency enforcement takes with
  -- them, exactly as an entry-chunk failure would have
  self:_enforceDependencies()
  for i = #self.loaded, 1, -1 do
    local mod = self.loaded[i]
    if mod.failed then
      self:_rollback(mod.manifest.id)
      table.remove(self.loaded, i)
    end
  end
  for i = #self.order, 1, -1 do
    local mod = self.mods[self.order[i]]
    if mod and mod.failed then table.remove(self.order, i) end
  end
end

-- ------- audio provenance
-- An audio def only fails when its cue fires, long after the load phase has
-- handed its report to the manager, so the merge leaves behind who wrote
-- each def for Music/Sound to name in the failure (13.3).  Engine records
-- stay unstamped on purpose: they resolve to "base", which Runtime.reportError
-- keeps out of the manager's error feed because no mod can be blamed for them.

local AUDIO_OWNERS = {
  music = "songs", sfx = "sfx", cries = "cries", map_songs = "mapSongs",
}

local function stampAudioOwners(data, name, registry)
  local key = AUDIO_OWNERS[name]
  if not key then return end
  local owners = Data.ensure(data, "audio._owners")
  local map = owners[key] or {}
  for id in pairs(registry.ops) do
    local owner = registry.owners[id]
    -- a tombstoned id has no def left to attribute, and a resurrected one
    -- belongs to whoever wrote it last
    if owner == nil or owner == Schemas.ENGINE or registry:get(id) == nil then
      map[id] = nil
    else
      map[id] = owner
    end
  end
  owners[key] = map
end

function Loader:load(data)
  Api3Warp.cancelAll()
  PortableScripts.cancelAll(nil, nil, "mods reloaded")
  -- A SECOND LOAD IN ONE PROCESS STARTS FROM THE ENGINE, NOT FROM THE LAST
  -- LOAD'S MODS.  EXIT GAME -> launcher -> Play runs every mod's main.lua
  -- again (and the launcher backdrop boots the plain game in between); the
  -- wraps and flags the previous load put on engine tables come off first.
  ModSeams.unwindAll()
  self.baseData = data
  -- every registry folds against the pristine view of its Data target;
  -- resolution is lazy so optional namespaces may appear later
  for _, registry in pairs(self.content) do
    local target = registry.spec.target
    if target then
      registry.base = function()
        return data and resolvePath(data, target)
      end
    end
  end
  -- vanilla content is registrations too, and they land before discovery so
  -- a mod's register collides with the engine's and has to say override
  require("src.mods.Builtins").install(self.content, data)
  self:_loadState()
  self:_discover()
  -- A RENAMED MOD COLLECTS ITS OLD STATE, now and not before: adoption needs
  -- the manifests, and the manifests are what _discover just read.  _loadState
  -- above therefore ran against the pre-adoption options and has to be redone
  -- -- which is why this refreshes what it read rather than only writing the
  -- file.  See src/mods/ModRename.lua for what it will and will not move.
  self:_adoptRenames()
  -- Experimental mods stay off until the player opts in: a missing
  -- options.mods entry normally means enabled, but experimental flips that.
  do
    local options = SaveData.loadOptions(self.fs)
    local modsOpt = options.mods or {}
    local gen = self:_generation()
    -- SAID ONCE PER BOOT, because a mod picking the wrong generation is
    -- invisible from the engine's side and expensive from the mod's: the
    -- author of one spent a session chasing a white screen that was its own
    -- Gen 2 battle bridge installing itself under Emerald.  This line is what
    -- a report can be checked against.
    do
      local okV, GameVersion = pcall(require, "src.core.GameVersion")
      local id = okV and GameVersion and select(2, pcall(GameVersion.get))
      Logger.info("mods: host is generation %s (%s) -- mod.generation, "
        .. "mod.gameVersion and mod.host carry it", tostring(gen),
        tostring(id or "?"))
    end
    for id, mod in pairs(self.mods) do
      if not self.disabled[id] and mod.manifest.experimental
          and ModGens.active(modsOpt[id], gen) ~= true then
        self.disabled[id] = true
      end
      -- A MOD DOES NOT LOAD WHERE IT SAYS IT DOES NOT WORK.
      --
      -- The player's chips are a choice about where they WANT a mod; the
      -- manifest's `generations` is the mod's own claim about where it
      -- FUNCTIONS, and the claim wins.  A mod run outside it does not fail
      -- cleanly -- it half-applies, and then every symptom reads as an engine
      -- fault: a dex bridge refusing to route and saying so once a frame, a
      -- screen bridge left installed with no transition to draw, type names
      -- resolving against a chart that never had them.
      --
      -- Said out loud, because a mod that vanishes without explanation is the
      -- other way to waste somebody's evening.
      --
      -- ...UNLESS THE PLAYER HAS SAID OTHERWISE, which is the door in that
      -- refusal (ModGens.permits).  The claim is the author's, and an author
      -- who has just taught a Gen 1/Gen 2 mod Hoenn -- or a player willing to
      -- find out what breaks -- must not be locked out until a new release
      -- ships.  A forced mod loads and says loudly that it is outside its own
      -- claim, so the next log still reads straight.
      if not self.disabled[id] then
        local ok, why = ModGens.permits(mod.manifest, modsOpt[id], gen)
        local claim = table.concat(mod.manifest.generations or {}, "/")
        if not ok then
          self.disabled[id] = true
          mod.unsupportedGeneration = gen
          Logger.info("%s is for generation %s; this is generation %s, so it is "
            .. "not loaded", id, claim, tostring(gen))
        elseif why == "forced" then
          mod.forcedGeneration = gen
          Logger.warn("%s says it is for generation %s and this is generation "
            .. "%s -- loading it anyway because you asked. Anything that "
            .. "misbehaves from here is the mod running somewhere it was not "
            .. "written for, not the engine.", id, claim, tostring(gen))
        end
      end
    end
  end
  for id, mod in pairs(self.mods) do
    mod.enabled = not self.disabled[id]
    mod.state = mod.enabled and "pending" or "disabled"
  end
  -- ONE ENABLED COPY PER MOD.  Two ids can be one mod: a launcher copy
  -- (install_source_id), a rename (previous_ids), a fork that kept the
  -- parent's old id (ModCopies.ALIASES).  Both enabled used to mean both
  -- entry chunks ran -- two sets of wraps, two sets of option rows, and the
  -- second one failing half-way on a registry collision with its residue
  -- left on the engine.  The one the player switched on runs (the most
  -- recent switch, else the slot's original -- ModCopies.choose); the other
  -- is reported.  The launcher normally keeps only one of them on.
  do
    local switchedOn = {}
    pcall(function()
      switchedOn = SaveData.loadOptions(self.fs).modSwitchedOn or {}
    end)
    local ok, losers = pcall(require("src.mods.ModCopies").supersede, self.mods,
      function(id, mod) return mod.enabled end, switchedOn)
    for _, row in ipairs(ok and losers or {}) do
      local mod = self.mods[row.id]
      mod.superseded = true
      mod.supersededBy = row.winner
      mod.state = "superseded"
      mod.failure = ("not loaded: %s"):format(row.note)
      Logger.warn("mod %s %s is not loaded -- %s (%s); switch that one off to "
        .. "use this one", row.id, tostring(mod.manifest.version), row.note,
        row.reason)
    end
  end
  -- the two lifecycle events mods do their late installs in are journaled
  -- like an entry chunk (Terrarium reinstalls its whole Colosseum runtime on
  -- mods.loaded; DRAMATIC_SHAPE wires its battle seams on game.ready)
  do
    local events = self.events
    local emit0 = events.emit
    local LIFECYCLE = { ["mods.loaded"] = true, ["game.ready"] = true }
    events.emit = function(bus, name, payload)
      if not LIFECYCLE[name] then return emit0(bus, name, payload) end
      local token = ModSeams.open("lifecycle:" .. tostring(name))
      local ok, err = pcall(emit0, bus, name, payload)
      ModSeams.close(token)
      if not ok then error(err, 0) end
    end
  end
  -- `require("mods.<id>...")` reads the copy chosen above, under one name
  pcall(function()
    local ModCopies = require("src.mods.ModCopies")
    ModCopies.setActive(self.mods)
    ModCopies.installSearcher()
  end)
  -- engine call sites reach these buses -- and this error feed, for failures
  -- that only surface at play time -- through Runtime from here on
  Runtime.install(self.events, self.hooks, self.errors)
  self:_validate()
  local ordered = self:_resolve()
  if self.dev then self:_installDevShim() end
  for _, mod in ipairs(ordered) do
    -- a mod ahead of this one may have failed and taken its dependents with
    -- it, so the order list is filtered as it is walked
    if isActive(mod) then
      local modId = mod.manifest.id
      self.journal = {}
      -- the dev tripwire attributes requires to whoever is running
      Runtime.currentMod = modId
      -- what the entry chunk does to the engine's own tables is journaled,
      -- so a failed chunk leaves none of it behind and the next load in this
      -- process starts from the engine as it was (src/mods/ModSeams.lua)
      local seams = ModSeams.open(modId)
      local success, err = pcall(self._loadMod, self, mod)
      ModSeams.close(seams)
      Runtime.currentMod = nil
      if not success then
        self:_rollback(modId)
        ModSeams.unwindOwner(modId)
      end
      self.journal = nil
      if success then
        mod.state = "loaded"
        self.loaded[#self.loaded + 1] = mod
        self.order[#self.order + 1] = modId
        self:_checkLinkClaims(mod)
        Logger.info("loaded mod %s %s%s", modId, mod.manifest.version,
                    Loader.freshness(self.fs, mod.path))
      else
        self:_fail(mod, "failed", tostring(err))
        self:_enforceDependencies()
      end
    end
  end
  -- the commands registry is final once every entry chunk has run, so
  -- each map_scripts contribution's rows can be judged before they merge
  self:_validateScripts()
  -- merge: fold every touched id from its pristine base value and write it
  -- home, creating the Data namespace when the base modules never shipped
  -- one.  A registry nobody wrote to -- engine included -- is skipped, so
  -- the namespaces that appear are exactly the ones with content behind them.
  for _, name in ipairs(self:_mergeOrder()) do
    local registry = self.content[name]
    local spec = registry.spec
    if data and spec.target and next(registry.ops) ~= nil then
      local target = Data.ensure(data, spec.target)
      if spec.write then
        -- ids that do not map one-to-one onto target keys (type_chart's
        -- ordered rows, battle_anims' per-kind subtables) place themselves
        spec.write(target, registry)
      elseif spec.semantics == "compose" then
        for id in pairs(registry.ops) do
          local chain = registry:chain(id)
          if #chain == 0 then
            -- an emptied chain still has to say which kind of empty it is:
            -- a tombstone keeps the (empty) chain so the consumer drops its
            -- own base contribution too, while a chain nobody wrote to
            -- leaves the id untouched and base dispatches as it always did
            if registry:chainReplacesBase(id) then
              target[id] = { replacesBase = true }
            else
              target[id] = nil
            end
          else
            -- owner records ride the chain under a named key ipairs
            -- skips, so the consumer can attribute each contribution
            -- (map_scripts builds runner sources from these)
            local owners = registry:chainOwners(id)
            for i = 1, #chain do
              local owner = owners[i]
              local mod = owner and self.mods[owner]
              owners[i] = { modId = mod and owner or nil,
                            strict = mod and (mod.manifest.api or 1) >= 2 or nil }
            end
            chain.owners = owners
            -- an override chain is a total conversion: the consumer must
            -- leave its own base contribution out (09 4.4)
            chain.replacesBase = registry:chainReplacesBase(id) or nil
            target[id] = chain
          end
        end
      else
        local tombstones = {}
        for id in pairs(registry.ops) do
          local value = registry:get(id)
          if value == nil then
            tombstones[#tombstones + 1] = id
          else
            target[id] = value
          end
        end
        -- tombstones survive the fold as an explicit delete pass so
        -- consumers see the id as absent, not as a stale record
        for _, id in ipairs(tombstones) do target[id] = nil end
      end
      stampAudioOwners(data, name, registry)
    end
  end
  -- dangling f.id references are attributed to the id's last writer;
  -- api 1 mods keep the warning-only compat path
  if data then
    for _, problem in ipairs(Schemas.crossValidate(self, data)) do
      local ownerMod = problem.owner and self.mods[problem.owner]
      local apiLevel = ownerMod and (ownerMod.manifest.api or 1) or 1
      local message = tostring(problem.owner or "?") .. ": " .. problem.message
      if apiLevel >= 2 then
        self.errors[#self.errors + 1] = message
        Logger.error("%s", message)
      else
        Logger.warn("%s", message)
      end
    end
  end
  -- WHICH MAP PACK WINS, where the player has said.
  --
  -- Two packs may patch the same map, and the fold's own answer is "whichever
  -- loaded last" -- defined, but not a decision anybody made. The map editor
  -- records a per-map choice in options.lua; this is where it takes effect, so
  -- the game honours it without the editor having to be involved.
  --
  -- AFTER THE MERGE, before the freeze: `preferOwner` only changes how the ops
  -- are read, so the affected ids have to be folded again and written home.
  -- (It works after the freeze too -- it appends nothing -- but doing it here
  -- keeps the merged table and the registry in step at every later reader.)
  --
  -- Wholly pcall-guarded and entirely optional: a build with no options file,
  -- or a choice naming a pack that is no longer installed, must load exactly
  -- as it did before this existed.
  if data then
    pcall(function()
      local SaveData = require("src.core.SaveData")
      local opts = SaveData.loadOptions(love and love.filesystem)
      local wins = opts and opts.mapPackWins
      if type(wins) ~= "table" then return end
      local registry = self.content.maps
      if not (registry and registry.preferOwner) then return end
      local target = data.maps
      for mapId, owner in pairs(wins) do
        if type(mapId) == "string" and type(owner) == "string"
           and registry.ops[mapId] then
          registry:preferOwner(mapId, owner)
          if type(target) == "table" then
            target[mapId] = registry:get(mapId)
          end
        end
      end
    end)
  end

  -- content freezes at the merge boundary; the event/hook buses stay open
  -- so mods may subscribe at any point for the life of the process
  for _, registry in pairs(self.content) do
    registry:freeze()
  end
  -- the load set is final here, so every surviving mod's recipe builds its
  -- derived art before the resolver is first asked to serve it; stamped, so
  -- a boot that changed nothing pays only the stat
  AssetTransform.run(self)
  -- and the same final load set becomes the asset search path, so an
  -- overrides/ file or a transform's output shadows the generated cache
  -- from the next image load on.  No mods means an empty search path,
  -- which resolves every path to itself (14 §asset resolution).
  Assets.installLoader(self)
  self.events:emit("mods.loaded", { loader = self, data = data })
  self.initialized = true
  return #self.errors == 0
end

-- the manager reads api, profile, permissions, per-mod state and the load
-- order from here; enabled stays the user's flag so a failed mod still
-- renders as enabled-but-broken instead of silently switching itself off
function Loader:status()
  local available, loaded = {}, {}
  for _, mod in pairs(self.mods) do
    local manifest = {}
    for key, value in pairs(mod.manifest) do manifest[key] = value end
    manifest.enabled = mod.enabled ~= false
    manifest.state = mod.state or (manifest.enabled and "loaded" or "disabled")
    manifest.error = mod.failure
    available[#available + 1] = manifest
    if manifest.state == "loaded" then loaded[#loaded + 1] = manifest end
  end
  table.sort(available, function(a, b) return a.id < b.id end)
  table.sort(loaded, function(a, b) return a.id < b.id end)
  return { available = available, loaded = loaded, errors = self.errors,
    order = self.order,
    -- the copies that were found and NOT loaded, and why (ModCopies): an
    -- older version beside a newer one, the other home's copy, a zip
    ignored = self.ignoredCopies or {}, zips = self.zipNotes or {} }
end

-- BACK TO THE LAUNCHER WITH NOTHING OF THE LAST GAME'S MODS STILL RUNNING.
--
-- main.lua's returnToLauncher lets go of the Game and raises the launcher in
-- the same process.  The mods' wraps on engine tables, their globals and
-- preload entries, their listeners on the live buses and their asset search
-- path were all still in place: the launcher (and the plain-game backdrop it
-- boots) ran on a modded engine whose mod instance nothing drives any more,
-- and the next Play loaded every mod on top of what the last one left.
function Loader.teardown()
  Api3Warp.cancelAll()
  PortableScripts.cancelAll(nil, nil, "mods unloaded")
  local undone = select(1, ModSeams.unwindAll())
  pcall(function()
    Runtime.install(Events.new(), Hooks.new(), nil)
    Runtime.currentMod = nil
  end)
  pcall(function() Assets.installLoader(nil) end)
  return undone
end

return Loader
