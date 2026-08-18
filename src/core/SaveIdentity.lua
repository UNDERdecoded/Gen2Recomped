-- One-time migration off the shared LÖVE identity (desktop only).
--
-- Desktop gen1recomp and Gen2Recomped both shipped t.identity = "pokemon-love2d",
-- so on a machine running both they shared %APPDATA%/LOVE/pokemon-love2d and
-- fought over options.lua and the saves/ tree, which the two projects write
-- with different conventions.  The desktop build now owns "Gen2Recomp"; this
-- module copies a player's existing progress across the first time the new
-- folder is used, so the rename is invisible to anyone upgrading.
--
-- Mobile keeps the old identity (conf.lua): Android's save directory is
-- package-scoped, so there was never a collision there to fix.
--
-- Design rules, learned the hard way:
--   * COPY, never move.  gen1recomp still needs the legacy folder intact.
--   * Never overwrite a file that already exists in the destination.  A player
--     who already booted a build that could not migrate has real saves in the
--     new folder; those must win, and the legacy files they are missing should
--     still come across.
--   * Never let a failure here stop the game booting.  A lost migration is
--     recoverable (the source folder is untouched); a failed boot is not.

local SaveIdentity = {}

SaveIdentity.LEGACY_IDENTITY = "pokemon-love2d"

-- Written into the new folder once the copy has been attempted, so a normal
-- boot costs one getInfo and nothing else.
local MARKER = "migrated-from-pokemon-love2d.txt"

-- Save-directory entries worth carrying over.  Each must be a name that does
-- NOT also exist in the game source tree: love.filesystem's read view merges
-- the save directory over the source, so copying a name the source also owns
-- (src, data, assets, main.lua, ...) would duplicate the game into the save
-- folder.  getRealDirectory is checked as well, belt and braces.
local MIGRATE_ROOTS = {
  "saves",        -- per-version save slots
  "options.lua",  -- settings, key bindings, active slot
}

-- Top-level save<suffix>.lua files (save.lua, save_gold.lua, ...) plus their
-- .bak siblings.  Matched by pattern rather than listed, so a version added
-- later still migrates.
local ROOT_FILE_PATTERN = "^save[%w_%-]*%.lua%.?%w*$"

local MAX_FILE_BYTES = 8 * 1024 * 1024
local MAX_TOTAL_BYTES = 256 * 1024 * 1024
local MAX_DEPTH = 6

local function fs()
  return love and love.filesystem
end

local function log(level, fmt, ...)
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and Logger and Logger[level] then Logger[level](fmt, ...) end
end

-- True when `path` is served by the currently-mounted save directory rather
-- than by the game source.  Guards against copying the shipped tree.
local function fromSaveDir(path)
  local f = fs()
  if not (f and f.getRealDirectory and f.getSaveDirectory) then return true end
  local real = f.getRealDirectory(path)
  if not real then return false end
  local save = f.getSaveDirectory()
  if not save then return false end
  -- normalise separators; Windows hands back backslashes in places
  real = real:gsub("\\", "/")
  save = save:gsub("\\", "/")
  return real:sub(1, #save) == save
end

local function collect(path, out, depth)
  local f = fs()
  if depth > MAX_DEPTH then return end
  local info = f.getInfo(path)
  if not info then return end
  if info.type == "file" then
    if fromSaveDir(path) and (info.size or 0) <= MAX_FILE_BYTES then
      out[#out + 1] = path
    end
    return
  end
  if info.type ~= "directory" then return end
  for _, name in ipairs(f.getDirectoryItems(path)) do
    collect(path .. "/" .. name, out, depth + 1)
  end
end

-- Read the legacy folder into memory.  Everything migrated is small (saves are
-- tens of KB), so buffering is simpler and safer than juggling two mounts.
local function readLegacy()
  local f = fs()
  local paths = {}
  for _, root in ipairs(MIGRATE_ROOTS) do
    collect(root, paths, 1)
  end
  for _, name in ipairs(f.getDirectoryItems("")) do
    if name:match(ROOT_FILE_PATTERN) then collect(name, paths, 1) end
  end

  local files, total = {}, 0
  for _, path in ipairs(paths) do
    local contents = f.read(path)
    if contents then
      total = total + #contents
      if total > MAX_TOTAL_BYTES then break end
      files[#files + 1] = { path = path, contents = contents }
    else
      log("warn", "save migration: could not read '%s'", tostring(path))
    end
  end
  return files
end

-- Write back, skipping anything the destination already has.  Returns copied,
-- skipped.
local function writeAll(files)
  local f = fs()
  local copied, skipped = 0, 0
  for _, entry in ipairs(files) do
    local existing = f.getInfo(entry.path)
    if existing and fromSaveDir(entry.path) then
      skipped = skipped + 1
    else
      local dir = entry.path:match("^(.*)/[^/]*$")
      if dir then f.createDirectory(dir) end
      local ok, err = f.write(entry.path, entry.contents)
      if ok then
        copied = copied + 1
      else
        log("warn", "save migration: could not write '%s' (%s)",
          tostring(entry.path), tostring(err))
      end
    end
  end
  return copied, skipped
end

-- Call once, as early in love.load as possible and before anything reads or
-- writes the save directory.  Returns the number of files copied.
function SaveIdentity.migrateLegacy()
  local f = fs()
  if not (f and f.setIdentity and f.getIdentity) then return 0 end

  -- DESKTOP ONLY, and now actually enforced.
  --
  -- The whole point of this module is that two LOVE games shared one
  -- %APPDATA%/LOVE folder.  That collision only exists where the save
  -- directory is keyed by t.identity -- Windows, Linux and macOS.  On the
  -- Switch (love-nx) the save directory is the title's own save-data
  -- archive: there is no "pokemon-love2d" folder to migrate FROM, and
  -- setIdentity means REMOUNTING that archive, twice, on the boot path
  -- before the first save is ever read.  Console save mounts are not
  -- something to remount speculatively for a folder that cannot exist.
  -- Android and iOS are package-scoped for the same reason (see conf.lua,
  -- which deliberately keeps the old identity there).
  local ok, Platform = pcall(require, "src.core.Platform")
  if ok and Platform and Platform.detect then
    local p = Platform.detect()
    if p.console or p.mobile then return 0 end
  end

  local current = f.getIdentity()
  if not current or current == SaveIdentity.LEGACY_IDENTITY then return 0 end
  -- Already attempted: nothing to do, and no identity juggling on a warm boot.
  if f.getInfo(MARKER) then return 0 end

  local ok, result = pcall(function()
    -- love.filesystem.setIdentity returns NOTHING in LÖVE 11 (it returned a
    -- boolean in 0.x).  Testing its result is why an earlier version of this
    -- module bailed out every single time and left players staring at an
    -- empty save folder -- confirm the switch by reading getIdentity back.
    f.setIdentity(SaveIdentity.LEGACY_IDENTITY)
    if f.getIdentity() ~= SaveIdentity.LEGACY_IDENTITY then return 0 end

    -- From here the legacy folder is mounted; restore `current` on every path
    -- out, including an error raised inside readLegacy.
    local readOk, files = pcall(readLegacy)
    f.setIdentity(current)
    if f.getIdentity() ~= current then
      -- Could not get back to our own folder; do not write anything.
      error("could not restore identity '" .. tostring(current) .. "'", 0)
    end
    if not readOk then error(tostring(files), 0) end
    if not files or #files == 0 then return 0 end

    local copied, skipped = writeAll(files)
    log("info", "save migration: copied %d file(s) (%d already present) from "
      .. "'%s' into '%s'", copied, skipped, SaveIdentity.LEGACY_IDENTITY,
      current)
    return copied
  end)

  -- Whatever happened, the game must end up on its own identity.
  if f.getIdentity() ~= current then pcall(f.setIdentity, current) end

  if not ok then
    log("warn", "save migration failed (the legacy folder is untouched; "
      .. "continuing): %s", tostring(result))
    return 0
  end

  -- Only claim the migration is done once we are safely back on our own
  -- identity, so a failed run retries on the next boot instead of latching.
  pcall(f.write, MARKER,
    "Gen2Recomped copied saves out of the LOVE/" .. SaveIdentity.LEGACY_IDENTITY
    .. " folder on first run.\nThat folder was left untouched and still "
    .. "belongs to gen1recomp.\nDelete this file to run the copy again.\n")

  return result or 0
end

return SaveIdentity
