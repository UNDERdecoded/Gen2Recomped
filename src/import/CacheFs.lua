-- Routes ROM-derived cache I/O (data/generated, assets/generated and the
-- rom-cache.complete marker) to the right place.
--
-- Normally the cache lives in LÖVE's per-user OS save directory and is
-- written through love.filesystem.  In portable mode it lives in the game
-- folder next to the executable instead (the folder holding portable.txt --
-- see SaveData), so nothing is left on the host machine.  That folder is
-- written with raw io.* (love.filesystem can only write to the save dir) and
-- read back through love.filesystem, require and love.graphics.newImage --
-- which works because the folder is on the physfs read path:
--
--   * Source runs (`love <gamedir>`, what the Play-* launchers use): the
--     folder IS the physfs source, so it is already readable.
--   * Fused builds (the packaged .app/.exe): the folder sits next to the
--     executable and is NOT normally readable, so CacheFs mounts it onto the
--     read path via PhysFS.  love.filesystem.mount refuses external folders,
--     but the underlying PHYSFS_mount (exported from love's framework) allows
--     them; we call it through LuaJIT's FFI.
--
-- Directories in the portable folder are created with a plain mkdir syscall
-- via FFI rather than os.execute, so importing never flashes a console window
-- on Windows (issue #74 -- the old per-file `os.execute("mkdir")` froze the
-- app behind a storm of one-frame cmd.exe windows).
--
-- Portable mode is desktop-only (Windows/Linux/macOS); on Android/iOS the
-- source is a read-only package with no game folder to write into, so
-- SaveData.isPortable() is false there.  Android can still redirect the
-- cache through SaveData.dataDir() (phone vs SD card / a writable tree),
-- which this module mounts the same way as a desktop custom folder.

local CacheFs = {}

local SEP = package.config:sub(1, 1)

-- Cache-relative paths are prefixed with this before every read/write, so a
-- Blue/Yellow import lands under its GameVersion.cachePrefix (blue/, yellow/)
-- while a Red import keeps the historical root.  The launcher sets it per
-- import / per readiness check; it stays "" for Red.  Runtime *reads*
-- (require / newImage) do NOT go through here -- CacheFs.mountVersion overlays
-- the active version's subtree onto the un-prefixed paths instead.
CacheFs.prefix = ""

local function withPrefix(rel)
  local p = CacheFs.prefix
  if p == nil or p == "" then return rel end
  return p .. rel
end

-- lazily-resolved windowless mkdir: function(absolutePath) or false when
-- FFI is unavailable (the cache then stays on the save directory)
local mkdirFn = nil

local function resolveMkdir()
  if mkdirFn ~= nil then return mkdirFn end
  mkdirFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return mkdirFn end
  if ffi.os == "Windows" then
    -- kernel32 is reliably resolvable through ffi.C on Windows (the engine
    -- already binds it in DiscordPresence); CreateDirectoryA returns
    -- nonzero on success and 0 when the directory already exists -- both
    -- fine, the result is ignored.
    pcall(ffi.cdef,
      "int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);")
    local resolved = pcall(function() return ffi.C.CreateDirectoryA end)
    if resolved then
      mkdirFn = function(path) pcall(ffi.C.CreateDirectoryA, path, nil) end
    end
  else
    pcall(ffi.cdef, "int mkdir(const char *pathname, unsigned int mode);")
    local resolved = pcall(function() return ffi.C.mkdir end)
    if resolved then
      mkdirFn = function(path) pcall(ffi.C.mkdir, path, 493) end -- 0755
    end
  end
  return mkdirFn
end

-- Lazily-resolved windowless rmdir, the mirror of resolveMkdir above:
-- function(absolutePath) or false when FFI is unavailable.  Both syscalls
-- refuse a non-empty directory, so a caller has to delete the files first.
local rmdirFn = nil

local function resolveRmdir()
  if rmdirFn ~= nil then return rmdirFn end
  rmdirFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return rmdirFn end
  if ffi.os == "Windows" then
    pcall(ffi.cdef, "int RemoveDirectoryA(const char *lpPathName);")
    local resolved = pcall(function() return ffi.C.RemoveDirectoryA end)
    if resolved then
      rmdirFn = function(path) pcall(ffi.C.RemoveDirectoryA, path) end
    end
  else
    pcall(ffi.cdef, "int rmdir(const char *pathname);")
    local resolved = pcall(function() return ffi.C.rmdir end)
    if resolved then
      rmdirFn = function(path) pcall(ffi.C.rmdir, path) end
    end
  end
  return rmdirFn
end

-- Mount an external directory onto the physfs read path (appended, so the
-- game's own source always wins a name clash).  Returns true on success.
--
-- PHYSFS_mount is exported by love's own binary.  How ffi finds it differs
-- per platform: on macOS/Linux the symbol is in the default namespace, so
-- ffi.C resolves it; on Windows it lives in love.dll, which ffi.C does NOT
-- search, so love.dll is loaded explicitly with ffi.load("love").  Try the
-- default first, then love.
local physfsMountFn = nil
local function resolveMount()
  if physfsMountFn ~= nil then return physfsMountFn end
  physfsMountFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return physfsMountFn end
  pcall(ffi.cdef,
    "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  local libs = {
    function() return ffi.C end,
    function() return ffi.load("love") end,
    -- Android loads love as liblove.so; ffi.C does not search it.
    function() return ffi.load("liblove.so") end,
  }
  for _, getlib in ipairs(libs) do
    local okl, lib = pcall(getlib)
    if okl and lib then
      local oks, fn = pcall(function() return lib.PHYSFS_mount end)
      if oks and fn then
        physfsMountFn = function(d, mountPoint, append)
          if append == nil then append = true end
          local okr, ret = pcall(fn, d, mountPoint or "", append and 1 or 0)
          return okr and ret ~= 0
        end
        break
      end
    end
  end
  return physfsMountFn
end

-- EVERY MOUNT THIS MODULE MAKES, recorded, so a root change can take the old
-- root's mounts back off the read path.  Without this an A -> B folder change
-- leaves A ahead of B for the rest of the process and the player sees the
-- setting "not take" -- which is one half of the bug this list exists for.
--
-- `how` is how it went on ("ffi" | "jni" | "love"), because only the first
-- can be taken off again by absolute path and only the first can PREPEND:
-- love.system.mountDirectory takes neither a mount point nor a position.
local ourMounts = {}

-- Mounts that could not be undone, so the read path still carries a home the
-- setting has moved away from.  rootReport surfaces it as `restart`.
local staleMounts = false

-- SET WHEN THE LIVE ROOT CANNOT BE PUT AHEAD OF THE SAVE DIRECTORY AT ALL.
--
-- Prepending needs PHYSFS_mount, because it is the only one of the three
-- mount mechanisms that takes a position and a mount point.  Where the symbol
-- does not resolve -- an Android APK whose liblove.so the FFI cannot reach,
-- so love.system.mountDirectory is all there is -- the chosen folder can be
-- made VISIBLE and cannot be made to WIN, and any copy of the same file still
-- sitting in the save directory goes on answering for it.  Measured on that
-- arm: CacheFs.read says the chosen folder and love.filesystem.read says the
-- save directory, for the same path.
--
-- A restart does not fix this one; moving or deleting the old copy does.  So
-- it is reported separately from `restart`, and the launcher says which.
local shadowRisk = false

-- append (default true): the game's own source wins a name clash, matching
-- how the portable cache root has always been mounted.  Pass false to
-- prepend, so the mounted tree wins -- used to overlay the active version's
-- cache on top of the root (Red) copy and the source, and to put the LIVE
-- game-data folder ahead of the save directory (which PhysFS always searches
-- before any appended mount, so an appended custom root loses to every stale
-- file still sitting in AppData).
--
-- mountPoint (default ""): where in the virtual tree `dir` appears.  A
-- non-empty one is what makes a prepend SAFE -- the folder can then only ever
-- serve names under that point, so pointing the setting at a folder that
-- happens to contain a conf.lua cannot shadow the game's own.
local function mountReadable(dir, append, mountPoint)
  mountPoint = mountPoint or ""
  local fn = resolveMount()
  if fn and fn(dir, mountPoint, append) then
    ourMounts[#ourMounts + 1] =
      { dir = dir, point = mountPoint, append = append, how = "ffi" }
    return true
  end
  -- Android: PHYSFS_mount through the JNI bridge (love.system.mountDirectory)
  -- rather than love.filesystem.mount, which refuses paths outside the save
  -- dir -- and the phone/SD gamedata folder is a sibling of that save dir.
  --
  -- IT TAKES NEITHER ARGUMENT.  It appends, at "", always.  So it cannot
  -- serve a prepend or a mount point, and asking it to would silently produce
  -- the appended mount that loses to the save directory -- the failure this
  -- parameter exists to fix.  A caller that needs a position is told no.
  if mountPoint == "" and append ~= false
      and love and love.system and type(love.system.mountDirectory) == "function" then
    local ok, mounted = pcall(love.system.mountDirectory, dir)
    if ok and mounted then
      ourMounts[#ourMounts + 1] =
        { dir = dir, point = mountPoint, append = append, how = "jni" }
      return true
    end
  end
  if love and love.filesystem and love.filesystem.mount then
    local ok, mounted =
      pcall(love.filesystem.mount, dir, mountPoint, append ~= false)
    if ok and mounted then
      ourMounts[#ourMounts + 1] =
        { dir = dir, point = mountPoint, append = append, how = "love" }
      return true
    end
  end
  return false
end

-- PHYSFS_unmount, resolved the same way PHYSFS_mount is.  Only
-- CacheFs.unmountVersion needs it: the launcher can open the save editor on
-- one game's cache and then Play the other, and an overlay left mounted
-- would win the read path for the rest of the process.
local physfsUnmountFn = nil
local function resolveUnmount()
  if physfsUnmountFn ~= nil then return physfsUnmountFn end
  physfsUnmountFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return physfsUnmountFn end
  pcall(ffi.cdef, "int PHYSFS_unmount(const char *oldDir);")
  local libs = {
    function() return ffi.C end,
    function() return ffi.load("love") end,
    -- Android loads love as liblove.so; ffi.C does not search it.
    function() return ffi.load("liblove.so") end,
  }
  for _, getlib in ipairs(libs) do
    local okl, lib = pcall(getlib)
    if okl and lib then
      local oks, fn = pcall(function() return lib.PHYSFS_unmount end)
      if oks and fn then
        physfsUnmountFn = function(d)
          local okr, ret = pcall(fn, d)
          return okr and ret ~= 0
        end
        break
      end
    end
  end
  return physfsUnmountFn
end

-- PHYSFS_getMountPoint, resolved the same way: a non-NULL return means `dir`
-- is already somewhere in the search path.  withMounted needs it because
-- PHYSFS_mount reports success for an already-mounted directory without
-- adding a second entry, so its unmount would drop a mount it did not make
-- (#413).
local physfsMountPointFn = nil
local function resolveMountPoint()
  if physfsMountPointFn ~= nil then return physfsMountPointFn end
  physfsMountPointFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return physfsMountPointFn end
  pcall(ffi.cdef, "const char *PHYSFS_getMountPoint(const char *dir);")
  local libs = {
    function() return ffi.C end,
    function() return ffi.load("love") end,
    -- Android loads love as liblove.so; ffi.C does not search it.
    function() return ffi.load("liblove.so") end,
  }
  for _, getlib in ipairs(libs) do
    local okl, lib = pcall(getlib)
    if okl and lib then
      local oks, fn = pcall(function() return lib.PHYSFS_getMountPoint end)
      if oks and fn then
        physfsMountPointFn = function(d)
          local okr, ret = pcall(fn, d)
          return okr and ret ~= nil and ret ~= ffi.NULL
        end
        break
      end
    end
  end
  return physfsMountPointFn
end

-- THE TWO TREES THE LIVE ROOT MUST WIN, prepended at their own mount points.
--
-- Mounting the chosen folder at "" with append=true is enough to make its
-- files VISIBLE and not enough to make them WIN: PhysFS searches the write
-- directory (LOVE's save directory) ahead of every appended mount, so a
-- cache that was imported before the folder was chosen goes on answering
-- every require() and newImage() while the new import fills the new folder.
-- Measured: write 'NEW-CUSTOM' through CacheFs.write after setDataDir and
-- love.filesystem.read hands back the save directory's 'OLD-SAVEDIR'.
--
-- So the root's own generated trees are additionally PREPENDED, each at its
-- own mount point.  The mount point is what keeps this safe: the folder can
-- only ever serve data/generated/... and assets/generated/..., which the game
-- source never ships (.gitignore excludes both), so nothing of the game's own
-- can be shadowed by whatever else is in the folder a player picked.
local function prependRootTrees(root)
  if type(root) ~= "string" or root == "" then return false end
  if not resolveMount() then
    -- No mechanism can position a mount on this build.  The root is still
    -- mounted (appended, by the JNI bridge), so writes and fresh reads work;
    -- what cannot be guaranteed is winning against a stale duplicate.
    shadowRisk = true
    return false
  end
  local any = false
  for _, tree in ipairs({ "data/generated", "assets/generated" }) do
    local real = root .. SEP .. tree:gsub("/", SEP)
    if mountReadable(real, false, tree) then any = true end
  end
  return any
end

-- The portable game folder when the cache should live there, else nil.
-- Resolved (and, for a fused build, mounted) once and cached.  Requires a
-- desktop portable install (SaveData) and a working windowless mkdir.
local portableRoot = nil
local portableResolved = false
local function resolvePortableRoot()
  if portableResolved then return portableRoot end
  portableResolved = true
  portableRoot = nil
  if not resolveMkdir() then return nil end
  local base = require("src.core.SaveData").portableBaseDir()
  if not base then return nil end
  if love.filesystem.getSource and base == love.filesystem.getSource() then
    -- source run: the folder is already the physfs source
    portableRoot = base
  elseif mountReadable(base) then
    -- fused build: base is next to the executable; mount it so io.* writes
    -- there are visible to love.filesystem/require/newImage
    portableRoot = base
    prependRootTrees(base)
  end
  return portableRoot
end

-- The player's chosen game-data folder when the cache should live there,
-- else nil.  Same two requirements as portable mode -- a windowless mkdir and
-- a folder love.filesystem can be made to READ back -- because the cache is
-- written with io.* and then read by require/newImage, and a folder that only
-- half satisfies that is an import that appears to succeed and a game that
-- cannot find its own data.
--
-- Unlike the portable folder this one is never the physfs source, so the
-- mount is not an optimisation: without it a fused build writes a perfectly
-- good cache nothing can read.  Failing the mount therefore falls back to the
-- save directory rather than proceeding into that trap.
local customRoot = nil
local customResolved = false
local customWhy = nil            -- why a chosen folder is NOT in use
local function resolveCustomRoot()
  if customResolved then return customRoot end
  customResolved = true
  customRoot, customWhy = nil, nil
  if not resolveMkdir() then
    customWhy = "this build cannot create folders outside the save directory"
    return nil
  end
  local ok, base = pcall(function()
    return require("src.core.SaveData").dataDir()
  end)
  if not (ok and base) then
    -- Not an error: no folder chosen, or SaveData already refused the stored
    -- one and has its own reason (dataDirProblem) for the panel to show.
    return nil
  end
  if love.filesystem.getSource and base == love.filesystem.getSource() then
    customRoot = base
  elseif mountReadable(base) then
    customRoot = base
    prependRootTrees(base)
  else
    customWhy = "that folder could not be added to the read path"
    pcall(function()
      local Logger = require("src.core.Logger")
      Logger.warn(
        "game-data folder %s could not be mounted; using the save directory",
        tostring(base))
      -- Drained now rather than left in the buffer.  This warning explains a
      -- setting that appears to have been ignored, and it is exactly the sort
      -- of line a launch produces one of -- far under the 64 the logger waits
      -- for before it writes anything at all.
      Logger.flush()
    end)
  end
  return customRoot
end

-- PORTABLE FIRST.  A portable copy has already said where it keeps its
-- things, and it says so with a file sitting next to the executable, which
-- beats a line in an options file the portable copy may not even be reading.
function CacheFs.root()
  return resolvePortableRoot() or resolveCustomRoot()
end

-- WHICH ROOT IS ACTUALLY IN USE, and why, as one answer.
--
-- This exists because there were two of them.  SaveData.dataDir() says whether
-- the player's chosen folder is READABLE AND WRITABLE, and CacheFs decides
-- whether the cache can actually live there -- which additionally needs the
-- folder on the PhysFS read path, because the cache is written with io.* and
-- read back by require/newImage.  Those two can disagree, and when they did,
-- the launcher panel read SaveData and said "games will be installed in D:\..."
-- while every byte went on going to the save directory.  Reported exactly that
-- way: "changing the install path doesnt work ... it goes straight back to
-- writing files in appdata".
--
-- So: ONE authority, and it is this one, because it is the one the writes go
-- through.  `kind` is "portable" | "custom" | "save"; `why` is set only when a
-- folder was chosen and is not being used.
function CacheFs.rootReport()
  local portable = resolvePortableRoot()
  if portable then
    return { kind = "portable", path = portable, restart = staleMounts,
             shadowed = shadowRisk }
  end
  local custom = resolveCustomRoot()
  if custom then
    return { kind = "custom", path = custom, restart = staleMounts,
             shadowed = shadowRisk }
  end
  local why = customWhy
  if not why then
    local ok, problem = pcall(function()
      return require("src.core.SaveData").dataDirProblem()
    end)
    if ok then why = problem end
  end
  local path = nil
  pcall(function() path = love.filesystem.getSaveDirectory() end)
  return { kind = "save", path = path, why = why, restart = staleMounts,
           shadowed = shadowRisk }
end

-- Drop the resolved root so the next call re-reads the setting, AND take the
-- old root's mounts back off the read path.
--
-- IT USED NOT TO UNMOUNT, on the grounds that "a read path with a folder on
-- it nothing asks about is harmless".  It is not harmless: PhysFS answers a
-- name from the first mount that has it, so a folder left on the path goes on
-- answering for every file it still holds.  Change the setting from A to B
-- and A keeps serving the cache -- which is a setting that visibly does
-- nothing, for the whole session, with no message to say why.
--
-- What the old comment was right about is the hazard: unmounting a folder an
-- open image was streamed from is not safe.  So this takes down only the
-- mounts THIS MODULE made (ourMounts), it only does so through PHYSFS_unmount
-- or love.filesystem.unmount, and anything it cannot take down sets
-- staleMounts -- which rootReport turns into `restart` so the panel can say
-- "restart to finish applying" instead of lying by omission.
function CacheFs.forgetRoot()
  local keep = {}
  local unmount = resolveUnmount()
  for _, m in ipairs(ourMounts) do
    local done = false
    if m.how == "ffi" and unmount then
      done = unmount(m.dir) and true or false
    elseif m.how == "love" and love and love.filesystem and love.filesystem.unmount then
      local ok, res = pcall(love.filesystem.unmount, m.dir)
      done = (ok and res) and true or false
    end
    if not done then
      -- The JNI bridge has no unmount at all, and a refused PHYSFS_unmount is
      -- a mount something else is holding.  Either way the old home is still
      -- in front of the new one until the process restarts.
      keep[#keep + 1] = m
      staleMounts = true
    end
  end
  ourMounts = keep
  customResolved = false
  customRoot = nil
  customWhy = nil
end

-- Whether a folder change left a previous home on the read path, so the
-- setting will not fully take effect until the game restarts.  Read by
-- rootReport; the launcher turns it into a line on the settings panel.
function CacheFs.restartNeeded()
  return staleMounts
end

-- Whether a copy of the cache left in a previous home can still win the read
-- path on this build, because nothing here can position a mount.  See
-- shadowRisk above; unlike restartNeeded, a restart does not clear it.
function CacheFs.shadowRisk()
  return shadowRisk
end

local function realPath(root, rel)
  return root .. SEP .. rel:gsub("/", SEP)
end

-- create every parent directory of `rel` under `root` (best effort; an
-- already-existing directory is fine, a genuine failure surfaces when the
-- subsequent io.open write fails)
local function tryMkdirs(path)
  if type(path) ~= "string" or path == "" then return end
  -- Android: Java File.mkdirs() is the call that actually creates trees on
  -- shared storage. FFI mkdir(2) often returns EACCES there even when a
  -- one-file probe at the folder root succeeded -- which is LuaWriter's
  -- "access denied" on data/generated during a ROM import.
  if love and love.system and type(love.system.mkdirs) == "function" then
    pcall(love.system.mkdirs, path)
  end
  local mkdir = resolveMkdir()
  if mkdir then mkdir(path) end
end

-- Create a real directory (and only that one -- no parents), for callers
-- outside this module that need the same windowless mkdir: SaveData proves a
-- chosen game-data folder is writable and may have to create it first.
-- Defined BELOW tryMkdirs on purpose: above it, `tryMkdirs` named a global
-- that does not exist, every call raised, and SaveData's pcall turned a
-- folder that merely did not exist yet into "could not be written to".
function CacheFs.mkdirReal(path)
  if type(path) ~= "string" or path == "" then return false end
  tryMkdirs(path)
  return true
end

local function ensureParents(root, rel)
  local parts = {}
  for part in rel:gmatch("[^/]+") do parts[#parts + 1] = part end
  local cur = root
  tryMkdirs(root)
  for i = 1, #parts - 1 do
    cur = cur .. SEP .. parts[i]
    tryMkdirs(cur)
  end
end

-- write cache-relative `rel` (forward-slash path) with the given bytes;
-- returns ok, err like love.filesystem.write
function CacheFs.write(rel, data)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    ensureParents(root, rel)
    local f, err = io.open(realPath(root, rel), "wb")
    if not f then return false, err end
    local written, writeError = f:write(data)
    local closed, closeError = f:close()
    if not written then return false, writeError end
    if not closed then return false, closeError end
    return true
  end
  local parent = rel:match("^(.*)/[^/]+$")
  if parent and not love.filesystem.createDirectory(parent) then
    local info = love.filesystem.getInfo(parent)
    local reason = info and ("a " .. info.type .. " already exists there")
      or "unknown reason"
    return false, "could not create " .. parent .. ": " .. reason
  end
  return love.filesystem.write(rel, data)
end

-- read cache-relative `rel`; returns the bytes or nil
function CacheFs.read(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    local f = io.open(realPath(root, rel), "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end
  return love.filesystem.read(rel)
end

-- does cache-relative `rel` exist as a file?
function CacheFs.exists(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    local f = io.open(realPath(root, rel), "rb")
    if not f then return false end
    f:close()
    return true
  end
  return love.filesystem.getInfo(rel, "file") ~= nil
end

-- remove a single cache-relative file
function CacheFs.remove(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    os.remove(realPath(root, rel))
    return
  end
  love.filesystem.remove(rel)
end

-- Remove a single cache-relative directory once its files are gone.  Needed
-- because os.remove cannot delete a directory on Windows and
-- love.filesystem.remove never reaches outside the save directory, so the
-- portable game folder gets the same FFI-syscall treatment as its mkdir
-- (issue #74: os.execute would flash a console window per call).  Used by the
-- mod installer so an uninstall leaves nothing behind (#330).
function CacheFs.removeDir(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    local rmdir = resolveRmdir()
    if rmdir then rmdir(realPath(root, rel)) end
    return
  end
  love.filesystem.remove(rel)
end

-- rmdir on a REAL absolute path, for a caller that already knows where the
-- directory is rather than a cache-relative one.
--
-- The mod uninstaller needs this: a mod unzipped next to the executable lives
-- in the game folder whether or not portable mode is on, and
-- love.filesystem.remove never reaches outside the save directory, so without
-- a real rmdir an uninstall could empty a mod's folders and never remove them.
function CacheFs.rmdirReal(path)
  if type(path) ~= "string" or path == "" then return end
  local rmdir = resolveRmdir()
  if rmdir then rmdir(path) end
end


-- ---------------------------------------------------------------------------
-- THE LAUNCHER'S OWN DATA, in whichever root is live.
--
-- Everything above is the ROM cache, which is version-prefixed.  The launcher
-- keeps three other trees that are not: installed mods (mods/), per-mod
-- storage (modstorage/) and the shared base-file bank (imports/base/, where a
-- 1.4 GB disc lands).  All three were on love.filesystem, which always
-- resolves to the OS save directory -- so a player who pointed the game-data
-- folder at another drive watched their imports move and everything else stay
-- exactly where it was.  Reported as "changing the install path doesnt work
-- for everything".
--
-- THE SPLIT IS READS vs WRITES, and it is not a compromise -- it is the only
-- correct arrangement:
--
--   * READS and ENUMERATION stay on love.filesystem, because it already sees
--     every home at once.  The save directory, the game folder and the chosen
--     root are all on the PhysFS search path, so `getDirectoryItems("mods")`
--     returns the union without knowing any of this exists.  Routing reads at
--     the live root instead would make a mod installed before the setting
--     changed invisible rather than merely stale.
--   * WRITES and REMOVES go through the root, because love.filesystem cannot
--     reach outside the save directory at all.
--
-- Which is exactly the split the mod installer already used for the portable
-- folder (#330); this is that seam, named, so the other two trees can share
-- it instead of each growing their own half of it.
local function rawRoot() return CacheFs.root() end

-- write/createDirectory/remove without the cache prefix.  The prefix belongs
-- to ROM-derived data; mods/ and modstorage/ are not per-cartridge and must
-- not be filed under whichever version was imported last.
function CacheFs.rawWrite(rel, data)
  local root = rawRoot()
  if root then
    ensureParents(root, rel)
    local f, err = io.open(realPath(root, rel), "wb")
    if not f then return false, err end
    f:write(data)
    f:close()
    return true
  end
  local parent = rel:match("^(.*)/[^/]+$")
  if parent then love.filesystem.createDirectory(parent) end
  return love.filesystem.write(rel, data)
end

function CacheFs.rawCreateDirectory(rel)
  local root = rawRoot()
  if root then
    local cur = root
    tryMkdirs(cur)
    for part in rel:gmatch("[^/]+") do
      cur = cur .. SEP .. part
      tryMkdirs(cur)
    end
    return true
  end
  return love.filesystem.createDirectory(rel)
end

-- BOTH HOMES, deliberately.  A mod installed before the folder changed sits in
-- the save directory and the one installed after sits in the chosen root;
-- love.filesystem shows them as one list, so "delete this" has to mean both or
-- an uninstall silently leaves half a mod behind for the loader to find.
function CacheFs.rawRemove(rel)
  local root = rawRoot()
  if root then os.remove(realPath(root, rel)) end
  if love.filesystem then love.filesystem.remove(rel) end
  return true
end

function CacheFs.rawRemoveDir(rel)
  local root = rawRoot()
  if root then
    local rmdir = resolveRmdir()
    if rmdir then rmdir(realPath(root, rel)) end
  end
  if love.filesystem then love.filesystem.remove(rel) end
  return true
end

-- A love.filesystem-shaped File for a path under the live root.
--
-- Only WRITING needs this.  A read goes through love.filesystem, which can
-- open a file in the chosen root already -- the root is mounted -- so the
-- shim below implements the write side and hands reads back to love.
-- A love.filesystem-shaped File for a path under the live root.
--
-- TWO CONTRACTS HAVE TO MATCH, and getting either wrong is silent:
--
--   * love.filesystem.newFile(path, mode) returns a file ALREADY OPEN when a
--     mode is given, and a closed one when it is not.  A caller that passes a
--     mode never calls :open, so a shim that only opens inside :open hands
--     back a handle whose every read returns nil -- which is not an error
--     anywhere, it is just no data.  That is what broke a mod reading its own
--     disc image in ranges: mod.imports:read(id, offset, length) goes through
--     ModImports' `slice`, which does exactly `newFile(path, "r")` and then
--     seeks -- so the mod saw an unreadable file, could not validate the disc,
--     and reported the disc as not imported while every check around it said
--     it was there.
--   * love's File:seek(pos) takes an absolute position; io's file:seek takes
--     (whence, offset).  Passing love's one-argument form to an io handle sets
--     the whence to a number and lands nowhere near the requested offset --
--     silently, again, because both return a number.
--
-- So the handle records WHICH kind it opened and every method dispatches on
-- that, rather than sniffing for a method name and hoping.
local function realFile(rel)
  local handle, kind, mode = nil, nil, nil

  local file = {}

  -- love.filesystem.newFile is absent in a headless test's stub, and the
  -- guards this shim sits behind test for `newFile` on the FILESYSTEM, which
  -- is always present here -- so the absence has to be answered by failing to
  -- open rather than by indexing nil.  Every caller already handles a handle
  -- that will not open; none of them survives an error thrown inside one.
  local function loveNewFile(path)
    local lfs = love and love.filesystem
    if not (lfs and type(lfs.newFile) == "function") then return nil end
    return lfs.newFile(path)
  end

  function file:open(m)
    mode = m or "r"
    -- READS go through love.filesystem: it already sees every home, including
    -- the live root (which is mounted), so a file written before the folder
    -- changed is still readable.  Only writes need the real path.
    if mode == "r" then
      local lf = loveNewFile(rel)
      if not lf then return false, "no file" end
      local ok, err = lf:open("r")
      if not ok then return false, err end
      handle, kind = lf, "love"
      return true
    end
    local root = rawRoot()
    if not root then
      local lf = loveNewFile(rel)
      if not lf then return false, "no file" end
      local ok, err = lf:open(mode)
      if not ok then return false, err end
      handle, kind = lf, "love"
      return true
    end
    ensureParents(root, rel)
    local f, err = io.open(realPath(root, rel), mode == "a" and "ab" or "wb")
    if not f then return false, err end
    handle, kind = f, "io"
    return true
  end

  function file:write(chunk)
    if not handle then return false, "not open" end
    if mode == "r" then return false, "opened for reading" end
    if kind == "io" then
      local ok, err = pcall(handle.write, handle, chunk)
      if not ok then return false, err end
      return true
    end
    return handle:write(chunk)
  end

  function file:read(n)
    if not handle then return nil end
    return handle:read(n)
  end

  -- Absolute position, love's spelling, whichever handle is underneath.
  function file:seek(pos)
    if not handle then return false end
    if kind == "io" then
      local at = handle:seek("set", pos)
      return at ~= nil
    end
    return handle:seek(pos)
  end

  function file:close()
    if handle and handle.close then pcall(handle.close, handle) end
    handle, kind = nil, nil
    return true
  end

  return file
end

local dataFsCache = nil

-- The filesystem the launcher's own trees should use.  Shaped like
-- love.filesystem so it drops into the modules that already take an `fs`.
function CacheFs.dataFs()
  if dataFsCache then return dataFsCache end
  -- A READ HAS TO RESOLVE THE ROOT FIRST.  The chosen folder is only on the
  -- PhysFS path because resolveCustomRoot mounted it, and that runs the first
  -- time anything asks CacheFs.root().  A reader that goes straight to
  -- love.filesystem before any writer has asked sees a folder that is not
  -- mounted yet -- so a mod installed in the chosen folder was invisible on a
  -- launch whose first act was to list mods.  One call, memoised behind
  -- customResolved, and the union is actually a union.
  local function mounted(fn)
    return function(...)
      CacheFs.root()
      return fn(...)
    end
  end
  dataFsCache = {
    -- reads and enumeration: every home at once
    getInfo = mounted(function(...) return love.filesystem.getInfo(...) end),
    getDirectoryItems = mounted(function(...) return love.filesystem.getDirectoryItems(...) end),
    read = mounted(function(...) return love.filesystem.read(...) end),
    load = mounted(function(...) return love.filesystem.load(...) end),
    getSaveDirectory = function() return love.filesystem.getSaveDirectory() end,
    getSource = function() return love.filesystem.getSource() end,
    -- writes and removes: the live root
    write = function(rel, data) return CacheFs.rawWrite(rel, data) end,
    createDirectory = function(rel) return CacheFs.rawCreateDirectory(rel) end,
    remove = function(rel) return CacheFs.rawRemove(rel) end,
    removeDir = function(rel) return CacheFs.rawRemoveDir(rel) end,
    -- `mode` given means ALREADY OPEN, exactly as love.filesystem does it --
    -- see realFile.  Returning an unopened handle here reads as an empty file
    -- rather than as a failure, which is the worst shape a bug can take.
    newFile = function(rel, mode)
      local file = realFile(rel)
      if mode == nil then return file end
      local ok = file:open(mode)
      if not ok then return nil end
      return file
    end,
  }
  return dataFsCache
end

-- The platform's path separator, so a caller building a real path out of a
-- love.filesystem one does not have to re-derive it.
CacheFs.SEP = SEP

-- Remove the game-folder copy of a cache subtree before a fresh import, so a
-- cache-format bump does not leave orphaned files behind.  No-op when the
-- portable cache is inactive (the save-directory copy is cleared by
-- RomImporter's own removeTree).  The tree is enumerated through
-- love.filesystem (the game folder is mounted) and the real files deleted
-- with os.remove; empty directories are harmless and left in place.
function CacheFs.removeTree(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if not root then return end
  local function walk(r)
    local info = love.filesystem.getInfo(r)
    if not info then return end
    if info.type == "directory" then
      for _, child in ipairs(love.filesystem.getDirectoryItems(r)) do
        walk(r .. "/" .. child)
      end
    else
      os.remove(realPath(root, r))
    end
  end
  walk(rel)
end

-- Overlay the active version's extracted cache onto the un-prefixed read
-- paths, so require("data.generated.*") and love.graphics.newImage(
-- "assets/generated/*") resolve to that version's files.  Red lives at the
-- cache root and needs nothing; non-Red versions (blue/, yellow/, …) are
-- *prepended* so they win over any Red copy at the root and over the game
-- source.  Called once at boot, before Game:load (main.lua).  Returns true
-- when nothing was needed or the mount succeeded.
-- A file every import writes, used to ask the read path a yes/no question:
-- "is the active version's cache actually reachable un-prefixed right now?"
local PROBE = "data/generated/constants.lua"

local function overlayVisible()
  return love.filesystem.getInfo(PROBE, "file") ~= nil
end

-- Mount the version's two generated trees at their UN-PREFIXED paths, in
-- addition to mounting the version folder at "".
--
-- Ported from gen1recomp, whose Switch build works and which does both.  Its
-- note on this reads "PhysFS directory non-merge (archive data/ vs save
-- generated)": mounting gold/ at "" is not sufficient there, while a mount
-- whose mount point IS data/generated is.  I could not reproduce the exact
-- PhysFS rule that makes the difference, so treat the mechanism as unproven
-- and the behaviour as measured: on love-nx, mounting only the version folder
-- left the files unreachable and Play died with
-- "could not overlay gold/ onto the read path" while gold/data/generated was
-- sitting there populated.  Doing both is cheap and is what the working
-- implementation does.
-- FROM THE LIVE ROOT, not from a save-directory-relative name.
--
-- This is where the game-data folder setting came apart.  The mount source
-- used to be the bare relative name `platinum/data/generated`, and
-- love.filesystem.mount resolves a relative source against the SAVE
-- DIRECTORY and nowhere else -- so this could only ever mount the save
-- directory's copy, never the chosen folder's.  It is also the LAST prepend
-- mountVersion makes, which put the stale copy at the very front of the read
-- path: measured, after an import into a chosen folder, CacheFs.read said
-- 'NEW-CUSTOM' and love.filesystem.read (what require and newImage use) said
-- 'OLD-SAVEDIR' for the same logical file.  Every byte went to the right
-- place and the game read none of it.
--
-- So: mount by ABSOLUTE PATH under whichever root is live, and fall back to
-- the save-dir-relative name only when the save directory IS the live root.
local function mountGeneratedTrees(prefix)
  local root = CacheFs.root()
  local mounted = false
  for _, tree in ipairs({ "data/generated", "assets/generated" }) do
    local src, dest = prefix .. tree, tree
    if root then
      local real = (root .. SEP .. src):gsub("/", SEP)
      if mountReadable(real, false, dest) then mounted = true end
    elseif love.filesystem and love.filesystem.mount
        and love.filesystem.getInfo(src, "directory") then
      if love.filesystem.mount(src, dest, false) then
        ourMounts[#ourMounts + 1] =
          { dir = src, point = dest, append = false, how = "love" }
        mounted = true
      end
    end
  end
  return mounted
end

function CacheFs.mountVersion(version)
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  if prefix == "" then return true end            -- Red: already at the root
  local sub = prefix:gsub("/+$", "")              -- "blue/" / "yellow/" -> bare dir

  -- Nothing to overlay: this version was never imported.  Say so plainly
  -- rather than reporting a mount failure for a cache that does not exist.
  if not love.filesystem.getInfo(sub .. "/" .. PROBE, "file") then
    return false, "no imported cache at " .. sub .. "/"
  end

  -- The cache root is the portable game folder when active, else LÖVE's OS
  -- save directory (where love.filesystem wrote blue/... or yellow/...).
  local base = CacheFs.root()
  if not base and love.filesystem.getSaveDirectory then
    base = love.filesystem.getSaveDirectory()
  end
  if not base then return false, "no cache root" end

  -- Three mechanisms, applied in order and then VERIFIED.  Verification
  -- matters because the FFI path reports success from the C return value
  -- alone, which is worthless where the symbol does not really resolve: on
  -- the Switch (love-nx, statically linked, no dlopen) it can hand back a
  -- non-zero value having mounted nothing.  Asking the read path whether the
  -- file is now visible cannot be faked.

  -- 1. Whole version folder at "", by save-dir-relative name.  No FFI, and
  --    it is enough wherever PhysFS has no colliding data/ to shadow it.
  --
  --    ONLY WHEN THE SAVE DIRECTORY IS THE LIVE ROOT.  A relative mount
  --    source resolves against the save directory, so with a chosen folder in
  --    use this prepends the folder the player moved AWAY from -- ahead of
  --    step 2, which prepends the one they moved to.
  if not CacheFs.root()
      and love.filesystem.mount and love.filesystem.getInfo(sub, "directory") then
    if love.filesystem.mount(sub, "", false) then
      ourMounts[#ourMounts + 1] =
        { dir = sub, point = "", append = false, how = "love" }
    end
  end

  -- 2. The same folder by absolute path, for a portable desktop install
  --    whose cache root is not the save directory at all.
  mountReadable(base .. SEP .. sub, false)

  -- 3. The generated trees onto their un-prefixed paths.  This is the one
  --    that works on console, and it is deliberately unconditional: 1 and 2
  --    can each "succeed" and still leave the files shadowed.
  mountGeneratedTrees(prefix)

  if overlayVisible() then return true end

  -- Last resort: stop needing a mount at all.
  --
  -- love-nx's PhysFS will not overlay a save-directory folder by any route
  -- tried above, so on the Switch every non-Red game was unplayable -- the
  -- files sat in crystal/data/generated and nothing could see them.  Rather
  -- than keep guessing at mount flags, redirect the only two things that
  -- ever read those paths: the module loader behind
  -- require("data.generated.*"), and the image loaders behind
  -- love.graphics.newImage("assets/generated/*").  Both go through
  -- love.filesystem.read, which reaches the save directory with no mounting
  -- whatsoever.
  if CacheFs.installPrefixShim(prefix) and overlayVisible() then return true end

  return false, "could not overlay " .. sub .. "/ onto the read path"
end

-- Which version prefix the shim currently redirects to; nil = shim inert.
--
-- This is a MUTABLE cell that the installed closures read at call time, not a
-- value baked into them, and that distinction is the whole point.  The first
-- version of this shim captured `prefix` as an upvalue and re-ran the whole
-- installation whenever a different prefix arrived, which stacked a second set
-- of love.filesystem wrappers over the first and pushed a second searcher in
-- front of it -- each layer still pointing at the version before it.  Nothing
-- ever removed a layer either, so opening the save editor on Gold, closing it
-- and then pressing Play on Crystal left Gold's redirect in the chain: the
-- probe found Gold's files, mountVersion reported success, and Crystal ran on
-- Gold's species and map tables.
local shimPrefix = nil
-- Separate from shimPrefix so re-pointing never re-wraps: love.filesystem.read
-- can only be wrapped once safely (a second wrap makes the first one's
-- "unwrapped" reference a wrapper, and there is then no way back out).
local shimInstalled = false

-- Does `path` exist un-prefixed?  If not, does it exist under the active
-- version prefix?  Only the second case is rewritten, so a file the game
-- genuinely ships (assets/logo/...) is never touched.  Reads shimPrefix live,
-- so clearing it makes every wrapper below a pass-through.
local shimRealRead, shimRealGetInfo

local function shimRedirect(path)
  local prefix = shimPrefix
  if not prefix or prefix == "" then return path end
  if type(path) ~= "string" then return path end
  if not (path:sub(1, 15) == "data/generated/"
          or path:sub(1, 17) == "assets/generated/") then
    return path
  end
  if shimRealGetInfo(path, "file") then return path end
  local alt = prefix .. path
  if shimRealGetInfo(alt, "file") then return alt end
  return path
end

-- Redirect data/generated + assets/generated reads to <prefix>... .  Returns
-- true when the shim is in place and the probe should be re-run.
function CacheFs.installPrefixShim(prefix)
  if prefix == "" then return false end
  if shimInstalled then
    -- Already wrapped: just re-point it.  Cheap, and it cannot stack.
    shimPrefix = prefix
    return true
  end
  shimPrefix = prefix
  shimInstalled = true

  local fs = love.filesystem
  shimRealRead, shimRealGetInfo = fs.read, fs.getInfo
  CacheFs._redirect = shimRedirect

  -- 1. require("data.generated.constants").  LÖVE's own module searcher asks
  --    PhysFS directly, so it cannot be reached by wrapping love.filesystem;
  --    this searcher goes in front of it and reads the bytes itself.
  local searchers = package.searchers or package.loaders
  if searchers then
    table.insert(searchers, 1, function(name)
      -- Inert while no prefix is active, so an uninstalled shim cannot answer
      -- for a version whose cache is mounted normally.
      local prefix_ = shimPrefix
      if not prefix_ or prefix_ == "" then return nil end
      local leaf = name:match("^data%.generated%.(.+)$")
      if not leaf then return nil end
      local path = prefix_ .. "data/generated/" .. leaf:gsub("%.", "/") .. ".lua"
      local data = shimRealRead(path)
      if type(data) ~= "string" then
        return "\n\tno file '" .. path .. "' (version cache shim)"
      end
      local chunk, err = loadstring and loadstring(data, "@" .. path)
        or load(data, "@" .. path)
      if not chunk then return "\n\t" .. tostring(err) end
      return chunk
    end)
  end

  -- 2. Everything that loads a generated asset by path.  Wrapped rather than
  --    fixed at the call sites because there are dozens of those, spread
  --    across the UI, the battle screen and the overworld.
  fs.read = function(path, ...) return shimRealRead(shimRedirect(path), ...) end
  fs.getInfo = function(path, ...) return shimRealGetInfo(shimRedirect(path), ...) end

  local g = love.graphics
  if g then
    for _, name in ipairs({ "newImage", "newFont", "newImageFont" }) do
      local real = g[name]
      if type(real) == "function" then
        g[name] = function(a, ...)
          if type(a) == "string" then a = shimRedirect(a) end
          return real(a, ...)
        end
      end
    end
  end
  if love.image and type(love.image.newImageData) == "function" then
    local real = love.image.newImageData
    love.image.newImageData = function(a, ...)
      if type(a) == "string" then a = shimRedirect(a) end
      return real(a, ...)
    end
  end

  -- Native decoders bypass fs.read and call PhysFS directly. Switch cannot
  -- mount the version overlay, so sounds need the same redirect as images.
  for _, entry in ipairs({{love.audio,'newSource'},{love.sound,'newSoundData'}}) do
    local module,name=entry[1],entry[2]
    if module and type(module[name])=='function' then
      local real=module[name]
      module[name]=function(a,...)
        if type(a)=='string' then a=shimRedirect(a) end
        return real(a,...)
      end
    end
  end

  return true
end

-- Make the shim inert.  The wrappers stay in place (unwrapping
-- love.filesystem.read safely is not possible once anything else may have
-- wrapped it in turn), but with no prefix they are pass-throughs, which is
-- exactly what an unmounted version needs.
function CacheFs.clearPrefixShim()
  shimPrefix = nil
end

-- Which prefix the shim is currently serving, or nil.  Tests and callers that
-- need to reason about read-path state use this instead of poking the local.
function CacheFs.activePrefixShim()
  return shimPrefix
end

-- Undo mountVersion.  A process normally mounts exactly one version and then
-- boots it, but the launcher can open the save editor on a Blue/Yellow save,
-- close it, and press Play on Red: with that version's subtree still
-- prepended, Red's require("data.generated.*") and its generated art would
-- silently resolve to the other game's files.  Callers must also drop the
-- generated modules from package.loaded (src.core.Data:unloadGenerated) --
-- unmounting alone only fixes the read path, not what require already cached.
--
-- Returns true when nothing was mounted or the unmount took.  Red is a no-op
-- because its cache lives at the root and was never overlaid.
function CacheFs.unmountVersion(version)
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  if prefix == "" then return true end
  local sub = prefix:gsub("/+$", "")
  local base = CacheFs.root()
  if not base and love.filesystem.getSaveDirectory then
    base = love.filesystem.getSaveDirectory()
  end
  local done = false
  -- The read-path redirect is part of "this version is mounted" and has to
  -- come down with the mounts.  Leaving it up is the same silent-wrong-data
  -- failure the mount unwinding below exists to prevent, except it survives
  -- every unmount call because it is not a mount at all.
  if shimPrefix == prefix then
    CacheFs.clearPrefixShim()
    done = true
  end
  local fn = resolveUnmount()
  if fn and base then
    done = fn(base .. SEP .. sub) or done
  end
  -- also drop the love.filesystem.mount fallback, which registers the folder
  -- under its bare name rather than its absolute path
  if love.filesystem.unmount then
    done = love.filesystem.unmount(sub) or done
    -- ...and the two generated trees mountVersion overlays onto the
    -- un-prefixed paths.  Leaving these mounted is worse than leaving the
    -- folder mount: they sit directly on data/generated and assets/generated,
    -- so the next version to boot would silently read this one's files.
    done = love.filesystem.unmount(prefix .. "data/generated") or done
    done = love.filesystem.unmount(prefix .. "assets/generated") or done
  end
  return done
end

-- Mount `dir` at `mountPoint` for the length of `fn()`, then take it back off
-- the read path and hand back whatever fn returned.
--
-- Every other mount here is permanent and lands at the physfs root: this one
-- exists to *look* at a folder the game has deliberately not mounted, which
-- is a different job.  The mods panel uses it to read a mods/ folder sitting
-- beside the executable of a non-portable install (LauncherMods.strays).
-- Because it unmounts again, and because a non-empty mountPoint keeps the
-- tree in its own corner of the namespace while it is up, a folder inspected
-- this way can never shadow a game file or change what the running game
-- resolves -- which is what makes it safe to point at a folder whose contents
-- nobody has validated.
--
-- Returns nil when the mount is unavailable (no ffi, no PHYSFS symbol, the
-- mount was refused, or `dir` is already on the read path), which callers must
-- treat as "could not look", not as "nothing there".  An error inside fn still
-- unmounts before it propagates.
function CacheFs.withMounted(dir, mountPoint, fn)
  if not dir or dir == "" then return nil end
  local mount, unmount = resolveMount(), resolveUnmount()
  if not (mount and unmount) then return nil end
  -- A directory already in the search path cannot be borrowed: PHYSFS_mount
  -- returns success without adding an entry, and the unmount below would then
  -- remove the mount somebody else is relying on -- for the portable game
  -- folder, the one that makes its cache and mods readable at all (#413)
  local mountedAt = resolveMountPoint()
  if mountedAt and mountedAt(dir) then return nil end
  if not mount(dir, mountPoint, true) then return nil end
  local ok, res = pcall(fn)
  unmount(dir)
  if not ok then error(res, 0) end
  return res
end

return CacheFs
