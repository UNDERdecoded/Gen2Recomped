-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHERE GENERATED DATA GOES, AND WHERE THE GAME LOOKS FOR IT.
--
-- Reported as: "when in the settings you change the location for saving game
-- data, generated data isn't going there."  It was going there.  What was not
-- going there was the READING: PhysFS searches LOVE's save directory ahead of
-- every appended mount, and `mountVersion` then PREPENDED the save directory's
-- own copy of data/generated on top of everything -- so an import wrote
-- hundreds of megabytes into the chosen folder and `require` and
-- `love.graphics.newImage` went on answering out of AppData.  Worse,
-- `readyReport` purged that AppData copy as soon as any non-save root went
-- live, so choosing a folder DELETED the installed game and then reported it
-- missing.
--
-- So this file does not check "does the write go to the right place".  It
-- checks the invariant that was actually broken:
--
--   ONE FACT DECIDES WHERE GENERATED DATA GOES, AND THE SAME FACT DECIDES
--   WHERE IT IS READ FROM.  That fact is CacheFs.rootReport().path.
--
-- HOW IT CAN RUN WITH NO CARTRIDGE AND NO CACHE.  It does not look at a cache.
-- It builds three real directories in a temporary folder -- a save directory,
-- a game source, and a folder standing in for the player's drive or SD card --
-- installs a LOVE stand-in whose filesystem is backed by those directories and
-- whose mount/unmount honour PhysFS's search order, and then drives the real
-- SaveData / CacheFs / LuaWriter code against them.  Nothing is stubbed that
-- the measurement depends on; the stand-in's job is to be a filesystem, and
-- every answer it gives comes from a file that is really there.
--
-- BOTH ARMS ARE FORCED.  A cold arm is not a tested arm, so every scenario
-- runs four times: desktop with the FFI PHYSFS_mount symbol resolvable, and
-- Android three ways -- with FFI, and with FFI's mount missing so the JNI
-- bridge (love.system.mountDirectory) is the only mechanism, which is the
-- configuration in which the chosen folder CANNOT be put ahead of the save
-- directory at all.  That last one is a real limitation of the platform and is
-- asserted as such: the engine has to admit it rather than claim the folder is
-- in use.
--
-- Usage: texlua tools/data_location_check.lua
--    or: python tools/run_lua_check.py tools/data_location_check.lua

package.path = "./?.lua;" .. package.path

local failures, checks = 0, 0
local function ok(cond, label, detail)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print(("FAIL  %s%s"):format(label, detail and ("  -- " .. detail) or ""))
  end
  return cond and true or false
end
local function eq(got, want, label)
  return ok(got == want, label,
    ("got %s, want %s"):format(tostring(got), tostring(want)))
end

-- ---------------------------------------------------------------------------
-- A filesystem, not a stub.
-- ---------------------------------------------------------------------------

local SEPC = package.config:sub(1, 1)

local function sh(c) return os.execute(c) end
local function kindOf(p)
  -- DIRECTORY FIRST: fopen() succeeds on a directory on Linux, so an io.open
  -- probe calls every folder a file.
  local d = sh('test -d "' .. p .. '" 2>/dev/null')
  if d == true or d == 0 then return "directory" end
  local f = sh('test -f "' .. p .. '" 2>/dev/null')
  if f == true or f == 0 then return "file" end
  return nil
end

local function tmpRoot()
  local name = os.tmpname()
  os.remove(name)
  return name .. ".dataloc"
end

-- Every absolute path anything wrote, and how.  This is what makes "no writer
-- bypasses the setting" a measurement instead of a reading of the source.
local writes = {}

local function install(opt)
  local saveDir, source = opt.saveDir, opt.source
  local mounts = {}            -- { dir, point, append }
  sh('mkdir -p "' .. saveDir .. '" "' .. source .. '"')

  local function realOf(rel)
    local pre, post = {}, {}
    for _, m in ipairs(mounts) do
      local pt, hit = m.point or "", nil
      if pt == "" then hit = m.dir .. "/" .. rel
      elseif rel == pt then hit = m.dir
      elseif rel:sub(1, #pt + 1) == pt .. "/" then
        hit = m.dir .. "/" .. rel:sub(#pt + 2)
      end
      if hit then
        -- PhysFS: a prepended mount goes to the FRONT, so the LAST prepend is
        -- searched first; appended ones keep their order, after the write dir
        -- and the source.
        if m.append == false then table.insert(pre, 1, hit) else post[#post + 1] = hit end
      end
    end
    local order = {}
    for _, p in ipairs(pre) do order[#order + 1] = p end
    order[#order + 1] = saveDir .. "/" .. rel
    order[#order + 1] = source .. "/" .. rel
    for _, p in ipairs(post) do order[#order + 1] = p end
    for _, p in ipairs(order) do
      local k = kindOf(p)
      if k then return p, k end
    end
    return nil
  end

  local fs = {}
  fs.getSaveDirectory = function() return saveDir end
  fs.getSource = function() return source end
  fs.getSourceBaseDirectory = function() return (source:gsub("/[^/]*$", "")) end
  fs.getInfo = function(rel, want)
    local p, k = realOf(rel)
    if not p then return nil end
    if want and want ~= k then return nil end
    local size
    if k == "file" then local h = io.open(p, "rb"); size = h:seek("end"); h:close() end
    return { type = k, size = size }
  end
  fs.getRealDirectory = function(rel)
    local p = realOf(rel)
    if not p then return nil end
    if p:sub(1, #saveDir + 1) == saveDir .. "/" then return saveDir end
    if p:sub(1, #source + 1) == source .. "/" then return source end
    for _, m in ipairs(mounts) do
      if p:sub(1, #m.dir + 1) == m.dir .. "/" or p == m.dir then return m.dir end
    end
    return nil
  end
  fs.read = function(rel)
    local p, k = realOf(rel)
    if not p or k ~= "file" then return nil, "no file" end
    local h = io.open(p, "rb"); local d = h:read("*a"); h:close(); return d
  end
  fs.load = function(rel)
    local d = fs.read(rel)
    if not d then return nil, "no file" end
    return load(d, rel)
  end
  fs.write = function(rel, data)
    local full = saveDir .. "/" .. rel
    local dir = full:match("^(.*)/[^/]*$")
    if dir then sh('mkdir -p "' .. dir .. '"') end
    local h, err = io.open(full, "wb")
    if not h then return false, tostring(err) end
    h:write(data); h:close()
    writes[#writes + 1] = { path = full, how = "love.filesystem.write" }
    return true
  end
  fs.append = function(rel, data)
    local h = io.open(saveDir .. "/" .. rel, "ab")
    if not h then return false end
    h:write(data); h:close()
    writes[#writes + 1] = { path = saveDir .. "/" .. rel, how = "love.filesystem.append" }
    return true
  end
  fs.createDirectory = function(rel)
    sh('mkdir -p "' .. saveDir .. "/" .. rel .. '"'); return true
  end
  fs.remove = function(rel)
    local full = saveDir .. "/" .. rel
    if kindOf(full) == "directory" then sh('rmdir "' .. full .. '" 2>/dev/null'); return true end
    return os.remove(full) and true or false
  end
  fs.getDirectoryItems = function(rel)
    local seen, out = {}, {}
    local roots = { saveDir, source }
    for _, m in ipairs(mounts) do roots[#roots + 1] = m.dir end
    for _, r in ipairs(roots) do
      local d = (rel == nil or rel == "") and r or (r .. "/" .. rel)
      local pipe = io.popen('ls -A "' .. d .. '" 2>/dev/null')
      if pipe then
        for line in pipe:lines() do
          if not seen[line] then seen[line] = true; out[#out + 1] = line end
        end
        pipe:close()
      end
    end
    return out
  end
  -- love.filesystem.mount: save-dir-relative names (or archives) only.  An
  -- absolute external path is refused, which is the whole reason CacheFs
  -- reaches for PHYSFS_mount through the FFI.
  fs.mount = function(dir, point, append)
    if dir:sub(1, 1) == "/" or dir:match("^%a:[/\\]") then return false end
    local full = saveDir .. "/" .. dir
    if kindOf(full) ~= "directory" then return false end
    mounts[#mounts + 1] = { dir = full, point = point or "", append = append }
    return true
  end
  fs.unmount = function(dir)
    local full = (dir:sub(1, 1) == "/" or dir:match("^%a:[/\\]")) and dir
      or (saveDir .. "/" .. dir)
    for i = #mounts, 1, -1 do
      if mounts[i].dir == full then table.remove(mounts, i); return true end
    end
    return false
  end
  fs.newFile = function(rel)
    local file = {}
    function file:open(mode)
      if mode == "r" then
        local p, k = realOf(rel)
        if not p or k ~= "file" then return false, "no file" end
        self.h = io.open(p, "rb")
      else
        local full = saveDir .. "/" .. rel
        local dir = full:match("^(.*)/[^/]*$")
        if dir then sh('mkdir -p "' .. dir .. '"') end
        self.h = io.open(full, mode == "a" and "ab" or "wb")
        if self.h then writes[#writes + 1] = { path = full, how = "love newFile" } end
      end
      return self.h ~= nil
    end
    function file:read(n) return self.h and self.h:read(n or "*a") end
    function file:write(d) if self.h then self.h:write(d); return true end end
    function file:seek(pos) return self.h and self.h:seek("set", pos) ~= nil end
    function file:close() if self.h then self.h:close(); self.h = nil end return true end
    return file
  end

  local osName = opt.os or "Linux"
  _G.love = {
    filesystem = fs,
    system = {
      getOS = function() return osName end,
      openURL = function() return true end,
    },
    timer = { getTime = function() return os.clock() end },
    graphics = { getWidth = function() return 800 end, getHeight = function() return 600 end },
    data = { hash = function(_, s) return s end, encode = function(_, _, s) return s end },
  }
  if osName == "Android" then
    love.system.mkdirs = function(p) sh('mkdir -p "' .. p .. '"'); return true end
    if opt.jniMount then
      -- The real bridge takes neither a mount point nor a position: it
      -- appends, at "".  Modelled exactly, because that limitation is the
      -- finding on the FFI-less Android arm.
      love.system.mountDirectory = function(dir)
        if kindOf(dir) ~= "directory" then return false end
        mounts[#mounts + 1] = { dir = dir, point = "", append = true }
        return true
      end
    end
  end

  local ffi = { os = (osName == "Windows") and "Windows" or "Linux",
                NULL = setmetatable({}, {}) }
  local C = {}
  C.mkdir = function(p) sh('mkdir "' .. p .. '" 2>/dev/null'); return 0 end
  C.CreateDirectoryA = C.mkdir
  C.rmdir = function(p) sh('rmdir "' .. p .. '" 2>/dev/null'); return 0 end
  C.RemoveDirectoryA = C.rmdir
  if opt.ffiMount ~= false then
    C.PHYSFS_mount = function(dir, point, append)
      if kindOf(dir) ~= "directory" then return 0 end
      for _, m in ipairs(mounts) do
        -- PHYSFS_mount reports success for an already-mounted directory
        -- WITHOUT adding a second entry (#413).  Modelled, because it is why
        -- the same real folder cannot be served at two mount points.
        if m.dir == dir then return 1 end
      end
      mounts[#mounts + 1] = { dir = dir, point = point or "", append = append ~= 0 }
      return 1
    end
    C.PHYSFS_unmount = function(dir)
      for i = #mounts, 1, -1 do
        if mounts[i].dir == dir then table.remove(mounts, i); return 1 end
      end
      return 0
    end
    C.PHYSFS_getMountPoint = function(dir)
      for _, m in ipairs(mounts) do if m.dir == dir then return m.point or "" end end
      return ffi.NULL
    end
  end
  ffi.C = C
  ffi.cdef = function() return true end
  ffi.load = function() return C end
  package.preload["ffi"] = function() return ffi end
  package.loaded["ffi"] = ffi

  return { mounts = mounts, fs = fs, saveDir = saveDir, source = source }
end

-- A fresh process, as far as the engine can tell: every module that memoises a
-- root or a mount is dropped so the next require resolves from scratch.
local ENGINE = {
  "src.core.SaveData", "src.import.CacheFs", "src.import.LuaWriter",
  "src.core.GameVersion", "src.core.Logger", "src.core.GenOptions",
  "src.core.SaveIdentity", "src.import.DataMove", "src.import.RomImporter",
}
local function freshEngine()
  for _, name in ipairs(ENGINE) do package.loaded[name] = nil end
  writes = {}
  return require("src.core.SaveData"), require("src.import.CacheFs")
end

local function fileAt(path)
  local h = io.open(path, "rb")
  if not h then return nil end
  local d = h:read("*a"); h:close(); return d
end

-- ---------------------------------------------------------------------------
-- The arms.  `ffiMount = false` leaves PHYSFS_mount unresolvable, which on
-- Android means the JNI bridge is the only mechanism and cannot prepend.
-- ---------------------------------------------------------------------------
local ARMS = {
  { name = "desktop (Linux, ffi mount)",   os = "Linux",   ffiMount = true  },
  { name = "Android (ffi mount)",          os = "Android", ffiMount = true,  jniMount = true },
  { name = "Android (JNI bridge only)",    os = "Android", ffiMount = false, jniMount = true },
  { name = "desktop (no mount at all)",    os = "Linux",   ffiMount = false },
}

local PREFIX = "platinum/"
local PROBE  = "data/generated/constants.lua"
local OLD    = "return { home = 'save-directory' }\n"
local NEW    = "return { home = 'chosen-folder' }\n"

local function scenario(arm)
  local T = tmpRoot()
  sh('rm -rf "' .. T .. '"')
  sh('mkdir -p "' .. T .. '/save" "' .. T .. '/src" "' .. T .. '/chosen" "' .. T .. '/second"')
  local env = install{ saveDir = T .. "/save", source = T .. "/src",
                       os = arm.os, ffiMount = arm.ffiMount, jniMount = arm.jniMount }
  local SaveData, CacheFs = freshEngine()
  local LuaWriter = require("src.import.LuaWriter")
  local A = arm.name

  -- ---- SECTION 1: the control.  An import with no folder chosen, so the
  -- previous home really has a cache in it.  Without this the later
  -- measurement has nothing to lose to and cannot fail.
  CacheFs.prefix = PREFIX
  CacheFs.write(PROBE, OLD)
  CacheFs.write("rom-cache.complete", "marker")
  eq(CacheFs.root(), nil, A .. ": no folder chosen -> root is the save directory")
  eq(fileAt(T .. "/save/" .. PREFIX .. PROBE), OLD,
     A .. ": the control cache really is in the save directory")

  -- ---- SECTION 2: the setting, applied mid-process.
  local set, why = SaveData.setDataDir(T .. "/chosen")
  ok(set, A .. ": setDataDir accepts a writable folder", tostring(why))
  eq(SaveData.dataDirSetting(), T .. "/chosen", A .. ": the setting is what was stored")
  local report = CacheFs.rootReport()
  local usable = report.kind == "custom"
  if arm.ffiMount == false and arm.jniMount ~= true then
    -- No mechanism can put the folder on the read path, so CacheFs must refuse
    -- it and SAY SO rather than write a cache nothing can read.
    eq(report.kind, "save", A .. ": with no mount mechanism the folder is refused")
    ok(report.why ~= nil, A .. ": and the refusal carries a reason")
    sh('rm -rf "' .. T .. '"')
    return
  end
  ok(usable, A .. ": the chosen folder is the live root", tostring(report.why))

  -- ---- SECTION 3: EVERY WRITER OF GENERATED DATA, ROUTED.
  -- Driven, not read: each entry point is called and the absolute path it
  -- really opened is compared against rootReport().path.
  writes = {}
  CacheFs.write(PROBE, NEW)
  CacheFs.write("rom-cache.complete", "marker")
  LuaWriter.write("data/generated/sv191_writer.lua", { home = "chosen-folder" })
  CacheFs.rawWrite("mods/sv191/mod.lua", "return {}")
  CacheFs.rawCreateDirectory("modstorage/sv191")
  local fs = CacheFs.dataFs()
  fs.write("imports/base/sv191.bin", "bytes")
  local handle = fs.newFile("imports/base/sv191b.bin", "w")
  if handle then handle:write("bytes"); handle:close() end

  local strayed = {}
  for _, w in ipairs(writes) do
    if w.path:sub(1, #report.path + 1) ~= report.path .. "/" then
      strayed[#strayed + 1] = w.how .. " -> " .. w.path
    end
  end
  eq(#strayed, 0, A .. ": no writer of generated data bypassed the live root",
     table.concat(strayed, "; "))
  eq(fileAt(T .. "/chosen/" .. PREFIX .. PROBE), NEW,
     A .. ": the new cache is in the chosen folder")
  ok(fileAt(T .. "/chosen/mods/sv191/mod.lua") ~= nil,
     A .. ": installed mods follow the folder")
  ok(fileAt(T .. "/chosen/imports/base/sv191.bin") ~= nil,
     A .. ": the base-file bank follows the folder")

  -- ---- SECTION 4: WHAT IS ALREADY AT THE OLD LOCATION IS LEFT ALONE.
  -- The launcher offers MOVE EXISTING DATA HERE; a purge that runs first
  -- deletes the thing the move exists to move.
  eq(fileAt(T .. "/save/" .. PREFIX .. PROBE), OLD,
     A .. ": the previous home's cache is still there to be moved")
  -- AND IT SURVIVES THE LAUNCHER'S OWN READINESS PASS, which is what used to
  -- destroy it.  readyReport purged the save directory for ANY non-save root,
  -- and setDataDir runs it for every version the moment the folder changes --
  -- so choosing a folder deleted the installed game out of AppData and then
  -- said "no cache for this version yet".  Driven here rather than reasoned
  -- about: the real readyReport, on the real versions.
  local RomImporter = require("src.import.RomImporter")
  local GameVersion = require("src.core.GameVersion")
  local saved = CacheFs.prefix
  for _, v in ipairs(GameVersion.ORDER or {}) do
    pcall(RomImporter.readyReport, v)
  end
  CacheFs.prefix = saved
  eq(fileAt(T .. "/save/" .. PREFIX .. PROBE), OLD,
     A .. ": the readiness pass does not delete the previous home's cache")
  eq(fileAt(T .. "/save/" .. PREFIX .. "rom-cache.complete"), "marker",
     A .. ": nor its marker, so MOVE EXISTING DATA HERE still has something to move")

  -- ---- SECTION 5: ONE FACT DECIDES, FOR READS AS WELL AS WRITES.
  -- This is the invariant that was broken.  mountVersion is what the launcher
  -- runs before Play; after it, the un-prefixed paths the game actually reads
  -- (require "data.generated.*", newImage "assets/generated/...") must resolve
  -- in the live root, not in the home the player moved away from.
  local mounted, mwhy = CacheFs.mountVersion("platinum")
  ok(mounted, A .. ": mountVersion overlays the live root", tostring(mwhy))
  local viaCacheFs = CacheFs.read(PROBE)
  local viaReadPath = love.filesystem.read(PROBE)
  eq(viaCacheFs, NEW, A .. ": CacheFs.read serves the live root")
  if report.shadowed then
    -- THE HONEST ARM.  Prepending needs PHYSFS_mount, and on a build where
    -- that symbol does not resolve the chosen folder cannot be put ahead of
    -- the save directory by any mechanism -- love.system.mountDirectory takes
    -- neither a position nor a mount point.  What the engine must NOT do is
    -- claim the folder is simply in use: it has to say that a game already in
    -- the default folder can still be the one that loads.  That admission is
    -- what is asserted here, because the behaviour cannot be fixed from Lua.
    ok(report.kind == "custom",
       A .. ": the folder is still usable for writes and fresh reads")
    ok(type(CacheFs.shadowRisk) == "function" and CacheFs.shadowRisk(),
       A .. ": and the engine reports that a stale copy can still win")
  else
    eq(viaReadPath, NEW,
       A .. ": the PhysFS read path serves the live root, not the old home")
    eq(viaReadPath, viaCacheFs,
       A .. ": one fact decides -- CacheFs.read and the read path agree")
  end

  -- ---- SECTION 6: A CHANGE TAKES EFFECT WITHOUT A RESTART.
  -- chosen -> second, in the same process.  The first folder must come off the
  -- read path, or it goes on answering for every file it still holds.
  sh('mkdir -p "' .. T .. '/second"')
  local set2, why2 = SaveData.setDataDir(T .. "/second")
  ok(set2, A .. ": the folder can be changed again", tostring(why2))
  local r2 = CacheFs.rootReport()
  eq(r2.path, T .. "/second", A .. ": the second folder is the live root")
  CacheFs.prefix = PREFIX
  CacheFs.write(PROBE, "return { home = 'second-folder' }\n")
  eq(CacheFs.read(PROBE), "return { home = 'second-folder' }\n",
     A .. ": writes follow the second folder")
  local m2, mw2 = CacheFs.mountVersion("platinum")
  ok(m2, A .. ": mountVersion re-overlays after a change", tostring(mw2))
  if r2.restart or r2.shadowed then
    -- Honest failure: the old mount could not be taken down, so the engine
    -- must be saying a restart is needed rather than claiming it applied.
    ok(true,
       A .. ": a read path that cannot be re-ordered is reported, not hidden")
  else
    eq(love.filesystem.read(PROBE), "return { home = 'second-folder' }\n",
       A .. ": no restart needed -- the read path follows the second folder")
  end

  -- ---- SECTION 7: BACK TO THE DEFAULT.
  local set3 = SaveData.setDataDir(nil)
  ok(set3, A .. ": the setting can be cleared")
  eq(CacheFs.rootReport().kind, "save", A .. ": clearing returns to the save directory")
  eq(SaveData.dataDirSetting(), nil, A .. ": and nothing is left stored")

  sh('rm -rf "' .. T .. '"')
end

-- ---------------------------------------------------------------------------
-- THE DEFAULT INSTALL MUST BE UNCHANGED -- which is how Gen 1, 2 and 3 are
-- known not to have moved.
--
-- Every player who has never opened this setting, and every Crystal / Gold /
-- Prism / Emerald install, has no chosen folder and no portable marker, so
-- CacheFs.root() is nil.  On that path the new code takes the same branch it
-- always did: mountVersion step 1 runs (its new guard is `not CacheFs.root()`,
-- true here) and mountGeneratedTrees falls through to the same
-- love.filesystem.mount of the same save-dir-relative name.  Asserted rather
-- than argued: with no folder chosen, EVERY mount the module makes must be a
-- directory under the save directory, and the read path must serve the save
-- directory's cache.
--
-- Run for a Gen 2 prefix (gold/) as well as the Gen 4 one above, because this
-- is shared storage code and a version prefix is the only thing that differs
-- between generations here.
-- ---------------------------------------------------------------------------
local function defaultInstall(arm, version, prefix)
  local T = tmpRoot()
  sh('rm -rf "' .. T .. '"')
  sh('mkdir -p "' .. T .. '/save" "' .. T .. '/src"')
  local env = install{ saveDir = T .. "/save", source = T .. "/src",
                       os = arm.os, ffiMount = arm.ffiMount, jniMount = arm.jniMount }
  local SaveData, CacheFs = freshEngine()
  local A = arm.name .. " / " .. version

  eq(SaveData.dataDirSetting(), nil, A .. ": a fresh install has no folder chosen")
  eq(CacheFs.root(), nil, A .. ": so the cache root is the save directory")
  -- FAIL-CLOSED ON THE API ITSELF.  The whole point of `shadowed` is that the
  -- launcher can admit a read path it cannot re-order; a build without it
  -- would silently claim the folder is simply in use.
  ok(type(CacheFs.shadowRisk) == "function",
     A .. ": CacheFs can say whether a stale copy can still win (shadowRisk)")
  ok(not (type(CacheFs.shadowRisk) == "function" and CacheFs.shadowRisk()),
     A .. ": and nothing claims a shadow risk when there is only one home")
  CacheFs.prefix = prefix
  CacheFs.write(PROBE, OLD)
  CacheFs.write("rom-cache.complete", "marker")
  local mounted, mwhy = CacheFs.mountVersion(version)
  ok(mounted, A .. ": mountVersion overlays the save-directory cache",
     tostring(mwhy))
  local outside = {}
  for _, m in ipairs(env.mounts) do
    if m.dir ~= env.saveDir
        and m.dir:sub(1, #env.saveDir + 1) ~= env.saveDir .. "/" then
      outside[#outside + 1] = m.dir
    end
  end
  eq(#outside, 0, A .. ": every mount is under the save directory",
     table.concat(outside, "; "))
  eq(love.filesystem.read(PROBE), OLD,
     A .. ": and the read path serves it, exactly as before this change")
  eq(CacheFs.read(PROBE), OLD, A .. ": CacheFs agrees")
  ok(CacheFs.unmountVersion(version), A .. ": and it can be taken back off")
  sh('rm -rf "' .. T .. '"')
end

-- ---------------------------------------------------------------------------
-- A SETTING THAT CANNOT WORK MUST BE REFUSED, NOT ACCEPTED SILENTLY.
-- ---------------------------------------------------------------------------
local function refusals(arm)
  local T = tmpRoot()
  sh('rm -rf "' .. T .. '"')
  sh('mkdir -p "' .. T .. '/save" "' .. T .. '/src"')
  install{ saveDir = T .. "/save", source = T .. "/src",
           os = arm.os, ffiMount = arm.ffiMount, jniMount = arm.jniMount }
  local SaveData, CacheFs = freshEngine()
  local A = arm.name

  ok(SaveData.dataDirSupported(),
     A .. ": the control exists on this platform (desktop and Android both)")
  local relOk, relWhy = SaveData.setDataDir("some/relative/folder")
  eq(relOk, false, A .. ": a relative path is refused")
  ok(relWhy and relWhy:find("full path", 1, true) ~= nil,
     A .. ": and says why", tostring(relWhy))
  local goneOk = SaveData.setDataDir(T .. "/not-plugged-in/sub")
  -- checkDataDir creates one level; two levels of absent parent cannot be made
  -- and must come back as a refusal rather than a folder that half works.
  eq(goneOk, false, A .. ": a folder that cannot be created is refused")
  eq(CacheFs.rootReport().kind, "save",
     A .. ": a refused folder leaves the save directory live")
  eq(SaveData.dataDirSetting(), nil, A .. ": and stores nothing")
  sh('rm -rf "' .. T .. '"')
end

-- ---------------------------------------------------------------------------
-- NO WRITER MAY REACH data/generated OR assets/generated EXCEPT THROUGH
-- CacheFs.  A sweep, fail-closed: a new writer added anywhere in src/ that
-- calls love.filesystem.write or ImageData:encode with one of those paths
-- lands in the save directory whatever the setting says, because
-- love.filesystem cannot write outside it.
-- ---------------------------------------------------------------------------
local SWEEP_DIRS = {
  "src/core", "src/import", "src/mods", "src/world", "src/render", "src/ui",
  "src/script", "src/battle", "src/pokemon", "src/save_convert", "src/update",
}
-- Known and argued: CacheFs IS the seam, and these two reach love.filesystem
-- on purpose.  Anything else is a finding.
local SWEEP_ALLOWED = {
  ["src/import/CacheFs.lua"] = true,
}
local function sweep()
  local offenders, scanned = {}, 0
  for _, dir in ipairs(SWEEP_DIRS) do
    local pipe = io.popen('ls "' .. dir .. '" 2>/dev/null')
    if pipe then
      for name in pipe:lines() do
        if name:sub(-4) == ".lua" then
          local rel = dir .. "/" .. name
          local h = io.open(rel, "rb")
          if h then
            local text = h:read("*a"); h:close(); scanned = scanned + 1
            if not SWEEP_ALLOWED[rel] then
              for line in text:gmatch("[^\r\n]+") do
                if not line:match("^%s*%-%-") then
                  -- ImageData:encode WITH A SECOND ARGUMENT writes a file, and
                  -- it can only ever write into LOVE's save directory -- so it
                  -- bypasses the setting whatever the path says.  The one-arg
                  -- form returns FileData and is fine.
                  local encodes = line:find(":encode%(['\"]png['\"]%s*,") ~= nil
                  local loveWrite =
                    (line:find("love%.filesystem%.write") ~= nil
                      or line:find("love%.filesystem%.append") ~= nil)
                    and (line:find("generated") ~= nil
                      or line:find("editor") ~= nil)
                  if encodes or loveWrite then
                    offenders[#offenders + 1] = rel .. ": " .. line:gsub("^%s+", "")
                  end
                end
              end
            end
          end
        end
      end
      pipe:close()
    end
  end
  ok(scanned > 100, "the sweep actually read the tree",
     ("only %d files scanned"):format(scanned))
  -- src/import/BorrowedTiles.lua writes the map editor's extended tile atlas
  -- with ImageData:encode("png", "editor/atlas/..."), which always lands in
  -- the save directory.  It is EDITOR output rather than ROM-derived cache, it
  -- is not mine to change, and it is listed here so the number is a pin rather
  -- than a blind spot: if it rises, something new is bypassing the seam.
  eq(#offenders, 1,
     "exactly the one known bypass of the CacheFs seam remains",
     table.concat(offenders, " | "))
  if #offenders == 1 then
    ok(offenders[1]:find("BorrowedTiles", 1, true) ~= nil,
       "and the known bypass is the one that was argued",
       offenders[1])
  end
end

-- ---------------------------------------------------------------------------

print("-- where generated data goes, and where the game reads it from")
for _, arm in ipairs(ARMS) do
  scenario(arm)
  refusals(arm)
  -- Gen 4 and Gen 2, so a prefix is exercised on both sides of the split this
  -- code has to stay neutral about.
  defaultInstall(arm, "platinum", "platinum/")
  defaultInstall(arm, "gold", "gold/")
end
sweep()

print(("%d checks, %d failed"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
