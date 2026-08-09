-- #330: a portable install must keep installed mods in the game folder.
-- love.filesystem has one write directory (the OS save dir) and it is not
-- relocatable, so installs landed in appdata and remove() could not touch the
-- game folder at all.  Reads merge both trees, which is why nothing looked
-- wrong.  The fake below reads from three places and writes to one, like
-- physfs; the game folder is real on disk, so the assertions are real files.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("portable mod install")
local check, eq = S.check, S.eq

local FsIo = require("tests.fs_io")
local SaveData = require("src.core.SaveData")

-- ---------------------------------------------------------------- sandbox
local WIN = FsIo.isWindows

local function mkdirp(path)
  if WIN then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
  end
end

local function rmrf(path)
  if WIN then
    os.execute('rmdir /s /q "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('rm -rf "' .. path .. '" 2>/dev/null')
  end
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function writeReal(path, body)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(body)
  f:close()
  return true
end

local function fileBody(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local TMP = (os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp")
  :gsub("[/\\]+$", "")
local SANDBOX = ("%s/pokeport_bug330_%d_%d"):format(TMP, os.time(),
  math.random(1, 999999))
-- Where portable.txt would sit, next to the executable.  Deliberately NOT
-- given one: SaveData's detection is cached process-wide, and a later suite
-- must not inherit a temp directory.  portableBaseDir() is stubbed instead.
local GAME_FOLDER = SANDBOX .. "/game"
local ZIP_PATH = SANDBOX .. "/portable_probe.zip"

mkdirp(GAME_FOLDER)
do
  local f = io.open(ZIP_PATH, "wb")
  if f then
    -- readArchive only has to read SOME bytes: the mount is stubbed below
    f:write("PK\003\004 stand-in for a mod .zip")
    f:close()
  end
end
check(FsIo.isDir(GAME_FOLDER), "sandbox game folder created at " .. GAME_FOLDER)
check(fileExists(ZIP_PATH), "sandbox .zip staged at " .. ZIP_PATH)

local MOD_ID = "portable_probe"

local function manifestJson(id, name)
  return ('{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua"}')
    :format(id, name)
end

-- one top-level mod folder, one nested subfolder, so the recursive copy and
-- the recursive delete are both exercised
local ARCHIVE = {
  [MOD_ID .. "/manifest.json"] = manifestJson(MOD_ID, "Portable Probe"),
  [MOD_ID .. "/main.lua"] = "return function() end\n",
  [MOD_ID .. "/data/extra.txt"] = "nested payload\n",
}

-- ---------------------------------------------------------------- fake physfs
-- Three read sources, one write sink -- the real asymmetry of the bug.
local realFs = FsIo.new(GAME_FOLDER)
local save, saveDirs, arch = {}, {}, {}

local function resetTrees()
  for k in pairs(save) do save[k] = nil end
  for k in pairs(saveDirs) do saveDirs[k] = nil end
  for k in pairs(arch) do arch[k] = nil end
end

-- the immediate child of `name` that `key` lies under, or nil
local function dirChild(key, name)
  if name == nil or name == "" then return key:match("^[^/]+") end
  local prefix = name .. "/"
  if key:sub(1, #prefix) ~= prefix then return nil end
  return key:sub(#prefix + 1):match("^[^/]+")
end

local function mapInfo(map, name, kind)
  if map[name] ~= nil then return { type = kind or "file" } end
  for key in pairs(map) do
    if dirChild(key, name) then return { type = "directory" } end
  end
  return nil
end

local vfs = {}

function vfs.write(name, data)
  -- physfs writes to the save directory and nowhere else, portable or not
  save[name] = data
  return true
end

function vfs.read(name)
  if arch[name] ~= nil then return arch[name] end
  if save[name] ~= nil then return save[name] end
  local body = realFs.read(name)
  return body
end

function vfs.remove(name)
  -- likewise: love.filesystem.remove never reaches outside the save directory
  save[name] = nil
  saveDirs[name] = nil
  return true
end

function vfs.createDirectory(name)
  saveDirs[name] = true
  return true
end

function vfs.getInfo(name, kind)
  local info = mapInfo(arch, name)
    or mapInfo(save, name)
    or mapInfo(saveDirs, name, "directory")
    or realFs.getInfo(name)
  if info and kind and info.type ~= kind then return nil end
  return info
end

function vfs.getDirectoryItems(name)
  local seen, items = {}, {}
  local function add(child)
    if child and not seen[child] then
      seen[child] = true
      items[#items + 1] = child
    end
  end
  for key in pairs(arch) do add(dirChild(key, name)) end
  for key in pairs(save) do add(dirChild(key, name)) end
  for key in pairs(saveDirs) do add(dirChild(key, name)) end
  local info = realFs.getInfo(name)
  if info and info.type == "directory" then
    for _, child in ipairs(realFs.getDirectoryItems(name)) do add(child) end
  end
  table.sort(items)
  return items
end

function vfs.load(name)
  local body = vfs.read(name)
  if not body then return nil, "no file" end
  return load(body, name)
end

function vfs.mount(_, point)
  for rel, body in pairs(ARCHIVE) do arch[point .. "/" .. rel] = body end
  return true
end

function vfs.unmount()
  for k in pairs(arch) do arch[k] = nil end
  return true
end

-- a source run: the game folder IS the physfs source, which is the branch
-- CacheFs takes when it does not need an FFI mount
function vfs.getSource() return GAME_FOLDER end
function vfs.getSaveDirectory() return SANDBOX .. "/os-save-dir" end

-- ---------------------------------------------------------------- module swap
local savedLoveFs = love.filesystem
local savedPortableBaseDir = SaveData.portableBaseDir
local savedCacheFs = package.loaded["src.import.CacheFs"]
local savedLauncherMods = package.loaded["src.mods.LauncherMods"]

-- CacheFs caches its resolved root (and its mkdir probe) at module level, so
-- each half of this suite needs its own copy.  Both are restored at the end.
local function freshModules(portableDir)
  package.loaded["src.import.CacheFs"] = nil
  package.loaded["src.mods.LauncherMods"] = nil
  SaveData.portableBaseDir = function() return portableDir end
  local LauncherMods = require("src.mods.LauncherMods")
  local CacheFs = require("src.import.CacheFs")
  return LauncherMods, CacheFs
end

local function saveTreeKeys(prefix)
  local hits = {}
  for key in pairs(save) do
    if key:sub(1, #prefix) == prefix then hits[#hits + 1] = key end
  end
  table.sort(hits)
  return hits
end

local function listedIds(rows)
  local ids = {}
  for _, row in ipairs(rows) do ids[#ids + 1] = row.id end
  table.sort(ids)
  return ids
end

local function contains(list, want)
  for _, v in ipairs(list) do if v == want then return true end end
  return false
end

local ffiAvailable = pcall(require, "ffi")

local function run()
  love.filesystem = vfs

  -- ------------------------------------------------- not portable: unchanged
  -- No portable.txt: the mods tree stays in the OS save directory.
  local plainMods, plainCache = freshModules(nil)
  resetTrees()
  eq(plainCache.root(), nil, "with no portable folder the cache root stays unset")

  local ok, id = plainMods.installZip(ZIP_PATH)
  check(ok == true, "a non-portable install still succeeds (" .. tostring(id) .. ")")
  eq(id, MOD_ID, "and reports the manifest id")
  check(save["mods/" .. MOD_ID .. "/manifest.json"] ~= nil,
    "a non-portable install still lands in the OS save directory")
  check(save["mods/" .. MOD_ID .. "/data/extra.txt"] ~= nil,
    "including nested files")
  check(not FsIo.isDir(GAME_FOLDER .. "/mods"),
    "and writes nothing at all next to the game")

  check(contains(listedIds(plainMods.list()), MOD_ID),
    "the mods panel lists it")
  local uok = plainMods.uninstall(MOD_ID)
  check(uok == true, "a non-portable uninstall succeeds")
  eq(#saveTreeKeys("mods/"), 0,
    "and clears the save-directory tree, so the row stays gone")

  if plainCache.removeDir then
    saveDirs["mods/ghost"] = true
    plainCache.removeDir("mods/ghost")
    check(saveDirs["mods/ghost"] == nil,
      "CacheFs.removeDir falls back to love.filesystem when not portable")
  else
    check(false, "CacheFs.removeDir exists (the uninstall counterpart to its"
      .. " windowless mkdir -- #330)")
  end

  -- ------------------------------------------------- portable: the fix
  if not ffiAvailable then
    print("[#330] no FFI on this interpreter, so CacheFs keeps the cache in"
      .. " the save directory by design: the portable half was skipped")
    return
  end

  local portableMods, portableCache = freshModules(GAME_FOLDER)
  resetTrees()
  eq(portableCache.root(), GAME_FOLDER,
    "portable.txt's folder becomes the cache root")

  -- The launcher leaves CacheFs.prefix on whichever version it last imported,
  -- but the mods tree is shared, so this must NOT land in blue/mods/.
  portableCache.prefix = "blue/"
  ok, id = portableMods.installZip(ZIP_PATH)
  eq(portableCache.prefix, "blue/",
    "installZip hands the version prefix back to the launcher")
  portableCache.prefix = ""

  check(ok == true, "a portable install succeeds (" .. tostring(id) .. ")")
  eq(id, MOD_ID, "and reports the manifest id")

  local installed = GAME_FOLDER .. "/mods/" .. MOD_ID
  check(fileExists(installed .. "/manifest.json"),
    "the mod's manifest is a real file in the game folder, next to the"
    .. " executable (#330)")
  eq(fileBody(installed .. "/manifest.json"),
    ARCHIVE[MOD_ID .. "/manifest.json"],
    "with the bytes from the .zip")
  check(fileExists(installed .. "/main.lua"), "the entry chunk came with it")
  check(fileExists(installed .. "/data/extra.txt"),
    "and so did the nested folder's contents")
  check(not FsIo.isDir(GAME_FOLDER .. "/blue"),
    "nothing landed under the version prefix (mods are shared by Red and Blue)")
  eq(#saveTreeKeys("mods/"), 0,
    "and nothing was stranded in the OS save directory")

  check(contains(listedIds(portableMods.list()), MOD_ID),
    "the mods panel lists the game-folder copy")

  -- ------------------------------------------------- portable uninstall
  local uerr
  uok, uerr = portableMods.uninstall(MOD_ID)
  check(uok == true, "a portable uninstall succeeds (" .. tostring(uerr) .. ")")
  check(not fileExists(installed .. "/manifest.json"),
    "uninstall deletes the real files out of the game folder (#330)")
  check(not fileExists(installed .. "/data/extra.txt"),
    "including the nested ones")
  check(not FsIo.isDir(installed .. "/data"),
    "the emptied subfolder is removed too")
  check(not FsIo.isDir(installed),
    "and so is the mod folder, so the row does not come back on the next launch")
  check(not contains(listedIds(portableMods.list()), MOD_ID),
    "the mods panel no longer lists it")

  -- ------------------------------------------------- a mod already on disk
  -- The other half of the report: a mod carried over from another machine.
  -- Uninstall used to delete nothing, so the row was back on the next launch.
  local shipped = "shipped_probe"
  local shippedDir = GAME_FOLDER .. "/mods/" .. shipped
  mkdirp(shippedDir .. "/data")
  local wrote = writeReal(shippedDir .. "/manifest.json",
      manifestJson(shipped, "Shipped Probe"))
    and writeReal(shippedDir .. "/main.lua", "return function() end\n")
    and writeReal(shippedDir .. "/data/extra.txt", "carried over\n")
  check(wrote, "staged a mod that was already sitting in the game folder")
  check(contains(listedIds(portableMods.list()), shipped),
    "the panel lists it (reads have always found the game folder)")
  uok, uerr = portableMods.uninstall(shipped)
  check(uok == true, "uninstalling it succeeds (" .. tostring(uerr) .. ")")
  check(not fileExists(shippedDir .. "/manifest.json"),
    "and it really is deleted off the disk this time (#330)")
  check(not fileExists(shippedDir .. "/data/extra.txt"), "nested files too")
  check(not FsIo.isDir(shippedDir),
    "the folder is gone, so it does not come back on the next launch")
  check(not contains(listedIds(portableMods.list()), shipped),
    "and the panel row stays gone")

  -- ------------------------------------------------- the pre-fix leftover
  -- Upgrading from a buggy build leaves a copy in appdata, which physfs
  -- searches first, so uninstall has to clear that too.
  local legacy = "legacy_twin"
  save["mods/" .. legacy .. "/manifest.json"] = manifestJson(legacy, "Legacy Twin")
  save["mods/" .. legacy .. "/main.lua"] = "return function() end\n"
  check(contains(listedIds(portableMods.list()), legacy),
    "a pre-fix copy in the OS save directory shows up in the panel")
  uok = portableMods.uninstall(legacy)
  check(uok == true, "uninstalling it succeeds")
  eq(#saveTreeKeys("mods/" .. legacy), 0,
    "and a pre-fix copy stranded in the OS save directory is cleared too")
end

local ok, err = pcall(run)

love.filesystem = savedLoveFs
SaveData.portableBaseDir = savedPortableBaseDir
package.loaded["src.import.CacheFs"] = savedCacheFs
package.loaded["src.mods.LauncherMods"] = savedLauncherMods
rmrf(SANDBOX)

if not ok then check(false, "suite raised: " .. tostring(err)) end

S.finish()
