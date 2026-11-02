-- The in-game bake: turns the player's own Emerald ROM into the voxel data
-- (lib/bake, run in a love.thread by lib/BakeThread.lua) and drops it in the
-- save directory's e3ds_voxel/, where lib/Data.lua already looks.
--
-- WHERE THE ROM COMES FROM.  The engine never keeps a cartridge after its
-- import: the launcher reads the file (a desktop path, an Android SAF copy,
-- an iOS picker copy), extracts it and lets it go -- Android even deletes its
-- copy.  So the mod declares the ROM in manifest.json's `required_imports`
-- (src/mods/ModImports.lua), the engine's own route for "a mod needs a base
-- file it cannot ship": the launcher's MODS panel and the in-game mod manager
-- both grow an EMERALD ROM row on every platform (desktop file dialog,
-- Android/iOS picker, console imports/ inbox), checked by MD5 and stored at
-- save-dir e3ds_voxel/emerald.gba.  Before asking, ModImports.acquire looks
-- where the player may already have put it (imports/, the save folder, the
-- shared base-file bank) -- silently.
--
-- WHAT COUNTS AS BAKED.  generated/ (a developer's bake/bake.py) wins and is
-- never re-baked.  Otherwise e3ds_voxel/ is trusted when its stamp matches
-- BakeJob.stamp(): the bake code's version, the ROM's SHA-1 and both pinned
-- asset commits.  A stale stamp still draws what is there while a fresh bake
-- runs; a folder with the files and no stamp at all (copied in by hand) is
-- taken as it is -- unless incomplete.txt says a bake was caught writing
-- it (then it is stale).  The thread streams its outputs to .part files
-- and only renames them into place once the whole bake has succeeded.

local V = ...
local Data = V.require("Data")

local BakeJob = {}

-- Bump when lib/bake's OUTPUT changes (not for speed or memory work that
-- keeps the bytes), so every player's e3ds_voxel/ is baked again.
BakeJob.VERSION = 1
BakeJob.IMPORT_ID = "emerald_rom"
BakeJob.STAMP = "stamp.txt"
-- present while a finished bake moves its outputs into place (BakeThread):
-- a folder with it was caught half-written and is never trusted
BakeJob.PARTIAL = "incomplete.txt"
BakeJob.OUTPUTS = { "regions.bin", "signposts.bin", "relief.bin", "buildings.bin", "layouts.lua" }
BakeJob.CHANNELS = { "e3ds_voxel_bake_in", "e3ds_voxel_bake_out", "e3ds_voxel_bake_http" }

-- idle | running | done | failed | need_rom
BakeJob.state = "idle"
BakeJob.progress = 0
BakeJob.label = nil
BakeJob.message = nil      -- the sentence for the player when failed / need_rom
BakeJob.code = nil         -- network | rom | memory | bake | no_rom
BakeJob.changedAt = 0      -- love.timer time of the last state change
BakeJob.onDone = nil       -- function() after a successful bake

local function now() return love.timer and love.timer.getTime() or os.clock() end

local function setState(state, message, code)
  BakeJob.state, BakeJob.message, BakeJob.code = state, message, code
  BakeJob.changedAt = now()
end

local function engine(name)
  local ok, m = pcall(require, name)
  return ok and m or nil
end

-- ------------------------------------------------------------- the stamp --

function BakeJob.romSha1()
  local GameVersion = engine("src.core.GameVersion")
  local info = GameVersion and GameVersion.info and GameVersion.info("emerald")
  return info and info.sha1 or nil
end

-- the stamp text; "{rom}" stays a placeholder for the thread to fill in
function BakeJob.stamp(romSha1)
  local Bake = V.require("bake/Bake")
  return table.concat({
    "e3ds-voxel-stamp 1",
    "bake " .. tostring(BakeJob.VERSION),
    "rom " .. (romSha1 or "{rom}"),
    "assets " .. Bake.ASSET_COMMIT,
    "trees " .. Bake.TREE_COMMIT,
  }, "\n") .. "\n"
end

local function saveInfo(rel)
  return love.filesystem and love.filesystem.getInfo("e3ds_voxel/" .. rel, "file")
end

-- generated/ holds a complete developer bake
function BakeJob.devData()
  if not (V.mod and V.mod.info) then return false end
  for _, name in ipairs(BakeJob.OUTPUTS) do
    local info = V.mod:info("generated/" .. name)
    if not (info and info.type == "file") then return false end
  end
  return true
end

-- "dev" | "fresh" | "unstamped" | "stale" | "missing"
function BakeJob.dataState()
  if BakeJob.devData() then return "dev" end
  for _, name in ipairs(BakeJob.OUTPUTS) do
    if not saveInfo(name) then return "missing" end
  end
  if saveInfo(BakeJob.PARTIAL) then return "stale" end
  if not saveInfo(BakeJob.STAMP) then return "unstamped" end
  local have = love.filesystem.read("e3ds_voxel/" .. BakeJob.STAMP)
  local sha1 = BakeJob.romSha1()
  if sha1 and have == BakeJob.stamp(sha1) then return "fresh" end
  -- a stamp written for another ROM SHA-1 than the engine's Emerald is
  -- still "this bake's version" if only the ROM line differs and we cannot
  -- name the ROM; otherwise it is stale
  if not sha1 and have and have:gsub("rom %x+", "rom {rom}") == BakeJob.stamp() then return "fresh" end
  return "stale"
end

-- Does the row being on call for a bake?
function BakeJob.wanted()
  local s = BakeJob.dataState()
  return s == "missing" or s == "stale"
end

-- --------------------------------------------------------------- the ROM --

local function importEntry()
  local ModImports = engine("src.mods.ModImports")
  local manifest = V.mod and V.mod.manifest
  if not (ModImports and manifest) then return nil end
  for _, entry in ipairs(ModImports.of(manifest) or {}) do
    if entry.id == BakeJob.IMPORT_ID then return ModImports, manifest, entry end
  end
  return nil
end

-- The ROM's bytes, or nil + why.  Looks only where the player already put
-- it: the declared import, then (silently) wherever ModImports.acquire looks.
function BakeJob.findRom()
  local imports = V.mod and V.mod.imports
  if imports and imports.have and imports:have(BakeJob.IMPORT_ID) then
    local bytes = imports:read(BakeJob.IMPORT_ID)
    if bytes then return bytes end
  end
  local ModImports, manifest, entry = importEntry()
  if ModImports then
    local ok, how = ModImports.acquire(manifest, entry)
    if ok then
      V.log("Emerald ROM found (%s)", tostring(how))
      local bytes = imports and imports:read(BakeJob.IMPORT_ID)
      if bytes then return bytes end
    elseif how then
      return nil, how      -- found a file, but it was not the right one
    end
  end
  return nil
end

-- The explicit "choose your ROM" step (the options row): a desktop file
-- dialog, the Android/iOS picker (answered later; BakeJob.poll consumes it),
-- or the sentence naming the inbox on a console.
function BakeJob.pickRom()
  local ModImports, manifest, entry = importEntry()
  if not ModImports then return false, "this engine cannot import base files for mods" end
  local ok, message = ModImports.choose(manifest, entry)
  if ok == nil then BakeJob.picking = true end
  return ok, message
end

-- No ROM to bake from: say where it goes (`message` from ModImports when
-- it has a better sentence, e.g. a console's imports/ folder).
function BakeJob.needRom(message)
  setState("need_rom", message and tostring(message)
    or "E3DS 3D needs your Emerald ROM once: Mods > Zallax's Emerald 3DS Voxels > EMERALD ROM",
    "no_rom")
  return BakeJob.message
end

-- -------------------------------------------------------------- the job --

local thread
local inCh, outCh, httpCh

local function sources()
  local out, list = {}, {}
  local function addDir(dir)
    for _, name in ipairs(V.mod:list(dir) or {}) do
      local rel = dir .. "/" .. name
      local info = V.mod:info(rel)
      if info and info.type == "directory" then
        addDir(rel)
      elseif name:match("%.lua$") then
        list[#list + 1] = rel
      end
    end
  end
  addDir("lib/bake")
  for _, rel in ipairs(list) do out[rel] = V.mod:read(rel) end
  return out
end

-- Start a bake from these ROM bytes (or the ROM found by findRom).  Returns
-- true, or false + the sentence that is now BakeJob.message.
function BakeJob.start(rom)
  if BakeJob.state == "running" then return true end
  if not (love.thread and love.thread.newThread) then
    setState("failed", "this build has no threads to bake in", "bake")
    return false, BakeJob.message
  end
  local why
  if not rom then rom, why = BakeJob.findRom() end
  if not rom then
    BakeJob.needRom(why and ("Wrong ROM for the 3DS voxels: " .. tostring(why)) or nil)
    return false, BakeJob.message
  end
  local code = rom:sub(0xAC + 1, 0xB0)
  local recipeBlob = V.mod:read("lib/bake/recipes/" .. code .. ".vtree")
  if not recipeBlob then
    setState("failed", ("That ROM (game code %q) is not Pokemon Emerald"):format(code), "rom")
    return false, BakeJob.message
  end
  local HostShell = engine("src.core.HostShell")
  local transport, transportWhy
  if HostShell and HostShell.transport then transport, transportWhy = HostShell.transport() end
  local threadCode = V.mod:read("lib/BakeThread.lua")
  if not threadCode then
    setState("failed", "lib/BakeThread.lua is missing -- reinstall the mod", "bake")
    return false, BakeJob.message
  end
  love.filesystem.createDirectory("e3ds_voxel/cache")

  inCh = love.thread.getChannel(BakeJob.CHANNELS[1])
  outCh = love.thread.getChannel(BakeJob.CHANNELS[2])
  httpCh = love.thread.getChannel(BakeJob.CHANNELS[3])
  inCh:clear(); outCh:clear(); httpCh:clear()
  inCh:push({
    modPath = V.mod.path or "mods/EMERALD_3DS_VOXEL",
    jit = (jit and jit.status and jit.status()) and true or false,
    transport = transport or "none",
    transportWhy = transportWhy,
    saveDir = love.filesystem.getSaveDirectory(),
    userAgent = "Gen2Recomp-EMERALD_3DS_VOXEL",
    stamp = BakeJob.stamp(),
    stampName = BakeJob.STAMP,
    partialName = BakeJob.PARTIAL,
    -- a channel table must be flat: the output names as one string
    outputs = table.concat(BakeJob.OUTPUTS, ","),
  })
  inCh:push(rom)
  inCh:push(recipeBlob)
  inCh:push(sources())
  thread = love.thread.newThread(threadCode)
  thread:start(BakeJob.CHANNELS[1], BakeJob.CHANNELS[2], BakeJob.CHANNELS[3])
  BakeJob.progress, BakeJob.label = 0, "Starting"
  BakeJob.startedAt = now()
  setState("running")
  V.log("baking the voxels from the ROM in a thread (transport %s)", tostring(transport or transportWhy))
  return true
end

-- Answer one Android download request: love.system.httpDownload is a JNI
-- call, made from here (the main thread), into the save directory.
local function serviceHttp(msg)
  local HostShell = engine("src.core.HostShell")
  local ok, err = false, "no network transport"
  if HostShell and HostShell.httpDownload then
    local saveDir = love.filesystem.getSaveDirectory()
    ok, err = HostShell.httpDownload(msg.url, saveDir .. "/" .. msg.dest, "Gen2Recomp-EMERALD_3DS_VOXEL")
  end
  httpCh:push({ ok = ok and true or false, err = err and tostring(err) or nil })
end

local FRIENDLY = {
  network = "Could not download Emerald 3DS's tree art and generator data -- check the connection and try again",
  rom = "Your ROM does not match Emerald 3DS's recipe (a modified or bad dump?)",
  memory = "Ran out of memory building the voxels",
}

-- Once a frame: progress, Android downloads, the end of the job, a mobile
-- ROM pick landing.
function BakeJob.poll()
  if BakeJob.picking then
    local ModImports, manifest, entry = importEntry()
    if ModImports then
      local ok, message = ModImports.poll(manifest, entry)
      if ok then
        BakeJob.picking = nil
        ModImports.announce(manifest, entry, false)
      elseif message then
        BakeJob.picking = nil
        setState("need_rom", "Wrong ROM for the 3DS voxels: " .. tostring(message), "no_rom")
      end
    end
  end
  if BakeJob.state ~= "running" or not thread then return end
  while true do
    local msg = outCh:pop()
    if not msg then break end
    if msg.kind == "progress" then
      -- every part of the bake reports as it goes (the relief and the
      -- building models through Session parts), so the bar is just that;
      -- never backwards
      BakeJob.progress = math.max(BakeJob.progress or 0, tonumber(msg.f) or 0)
      BakeJob.label = msg.label or BakeJob.label
    elseif msg.kind == "log" then
      V.log("%s", tostring(msg.text))
    elseif msg.kind == "http" then
      serviceHttp(msg)
    elseif msg.kind == "done" then
      thread = nil
      BakeJob.progress = 1
      V.log("voxels baked in %.0f s (ROM %s)", now() - (BakeJob.startedAt or now()), tostring(msg.rom))
      setState("done")
      if BakeJob.onDone then BakeJob.onDone() end
      return
    elseif msg.kind == "error" then
      thread = nil
      V.log("bake failed (%s): %s", tostring(msg.code), tostring(msg.message))
      local friendly = FRIENDLY[msg.code]
      setState("failed", friendly and (friendly .. ": " .. tostring(msg.message)) or
        ("Building the voxels failed: " .. tostring(msg.message)), msg.code or "bake")
      return
    end
  end
  -- a thread that died below its own error handler (out of memory in C,
  -- a syntax error in a source) reports here instead
  local err = thread and thread:getError()
  if err then
    thread = nil
    V.log("bake thread died: %s", tostring(err))
    local code = tostring(err):find("memory", 1, true) and "memory" or "bake"
    setState("failed", (FRIENDLY[code] or "Building the voxels failed") .. ": " .. tostring(err), code)
  elseif thread and not thread:isRunning() and BakeJob.state == "running" then
    -- finished without a word: read what is left on the channel next frame
    if outCh:getCount() == 0 then
      thread = nil
      setState("failed", "Building the voxels stopped without finishing", "bake")
    end
  end
end

function BakeJob.running() return BakeJob.state == "running" end

return BakeJob
