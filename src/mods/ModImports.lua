-- Base files a mod needs but cannot ship: `required_imports` in manifest.json.
--
-- Some mods are extractors.  STADIUM2_IMPORTER rips models out of a Pokemon
-- Stadium 2 cartridge; it cannot legally ship the cartridge, and the sandbox
-- gives a mod no way to reach outside its own folder, so the mod's own
-- discovery ends in "the engine sandbox has no scoped external ROM picker".
-- The manifest has always DECLARED the requirement:
--
--   "required_imports": [ {
--       "id": "stadium2_rom", "name": "Pokemon Stadium 2 (USA) ROM",
--       "file": "baseroms/stadium2.z64", "format": "n64",
--       "size": 67108864, "md5": "1561c75d..." } ]
--
-- and the engine ignored the field completely, so the only way to satisfy it
-- was to unzip the release, drop a 64 MB file inside it, re-zip and reinstall.
-- That is the "I can't import the Stadium 2 ROM" report.
--
-- What this module does is simple on purpose: it writes the player's file
-- INTO THE MOD'S OWN FOLDER at the declared path.  Every mod already reads its
-- own folder (`mod:read(relative)`), so a mod needs no new API and no change
-- at all to pick the file up -- STADIUM2_IMPORTER's Discovery.find() looks in
-- exactly the two places this writes to.  The engine's job is only to get the
-- bytes there, and to refuse the wrong file before it does.

local Logger = require("src.core.Logger")

local ModImports = {}

local function fs()
  return love and love.filesystem
end

-- A declared import, normalised.  `file` is where the mod expects to read it
-- from, relative to the mod folder; everything else is validation.
local function normalise(raw, index)
  if type(raw) ~= "table" then return nil end
  local file = raw.file
  if type(file) ~= "string" or file == "" then return nil end
  -- never let a manifest write outside its own folder
  if file:find("%.%.") or file:sub(1, 1) == "/" or file:find("^%a:") then
    return nil
  end
  -- WHERE the mod reads it from.  "mod" (the default) is inside the mod's own
  -- folder, which is all a sandboxed `mod:read` can reach.  "save" is the
  -- PhysFS root -- the save directory and the game folder, searched under one
  -- name -- and some mods genuinely want that: STADIUM2_OVERWORLD_MODELS
  -- looks for `baseroms/stadium2.z64` there and nowhere else, so writing its
  -- cartridge into the mod folder satisfied the manifest and left the mod
  -- still reporting no ROM.  The `..`/absolute guard above applies to both.
  local root = (raw.root == "save" or raw.root == "root") and "save" or "mod"
  return {
    id = tostring(raw.id or ("import" .. index)),
    name = tostring(raw.name or raw.id or file),
    description = type(raw.description) == "string" and raw.description or nil,
    file = file,
    root = root,
    format = type(raw.format) == "string" and raw.format:lower() or nil,
    size = tonumber(raw.size),
    md5 = type(raw.md5) == "string" and raw.md5:lower() or nil,
  }
end

-- Manifest.validate hands the parsed list straight through; this is also the
-- reader for a raw manifest table, so the launcher can ask before a mod loads.
function ModImports.parse(raw)
  local list = raw and raw.required_imports
  if type(list) ~= "table" then return nil end
  local out = {}
  for index, entry in ipairs(list) do
    local row = normalise(entry, index)
    if row then out[#out + 1] = row end
  end
  return out[1] and out or nil
end

function ModImports.of(manifest)
  if type(manifest) ~= "table" then return nil end
  return manifest.requiredImports or ModImports.parse(manifest.raw)
end

-- The extensions a picker should offer for one entry.  `format` names a family
-- rather than a single suffix, because a console ROM legitimately arrives in
-- more than one byte order and the mod normalises them itself.
ModImports.FORMATS = {
  n64 = { "z64", "n64", "v64" },
  gb = { "gb", "gbc" },
  gba = { "gba" },
  nds = { "nds" },
  zip = { "zip" },
}

function ModImports.extensions(entry)
  if not entry then return {} end
  local byFormat = entry.format and ModImports.FORMATS[entry.format]
  if byFormat then return byFormat end
  local suffix = tostring(entry.file or ""):match("%.(%w+)$")
  return suffix and { suffix:lower() } or {}
end

function ModImports.accepts(entry, name)
  local want = ModImports.extensions(entry)
  if #want == 0 then return true end
  local suffix = tostring(name or ""):match("%.(%w+)$")
  if not suffix then return false end
  suffix = suffix:lower()
  for _, ext in ipairs(want) do
    if ext == suffix then return true end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- The shared store
--
-- Two mods can want the SAME base file: STADIUM2_IMPORTER and
-- STADIUM2_OVERWORLD_MODELS both extract from a Pokemon Stadium 2 cartridge.
-- Making the player find and import a 64 MB ROM once per mod is the kind of
-- thing that reads as the feature being broken, so an accepted file is also
-- kept under imports/base/ and any other mod that declares a matching entry
-- is satisfied from there without asking again.
--
-- Matching is by DECLARED IDENTITY -- md5 when the manifest gives one, else
-- id plus size -- not by filename, so two mods that spell the same cartridge
-- differently still share it.
local SHARED_DIR = "imports/base"

function ModImports.sharedKey(entry)
  if not entry then return nil end
  if entry.md5 then return entry.md5 end
  if entry.size then return ("%s-%d"):format(entry.id, entry.size) end
  return entry.id
end

function ModImports.sharedPath(entry)
  local key = ModImports.sharedKey(entry)
  return key and (SHARED_DIR .. "/" .. key .. ".bin") or nil
end

-- Read a shared copy back, or nil.
function ModImports.shared(entry)
  local f = fs()
  local path = ModImports.sharedPath(entry)
  if not (f and path and f.getInfo(path, "file")) then return nil end
  return f.read(path)
end

local function keepShared(entry, bytes)
  local f = fs()
  local path = ModImports.sharedPath(entry)
  if not (f and path) then return end
  if f.getInfo(path, "file") then return end   -- already banked
  if f.createDirectory then
    f.createDirectory("imports")
    f.createDirectory(SHARED_DIR)
  end
  pcall(f.write, path, bytes)
end

-- Satisfy every entry a mod declares from the shared store, silently.  Called
-- when the launcher builds its list, so a second mod that wants a cartridge
-- the player already gave the first one is simply ready.
function ModImports.adoptShared(manifest)
  local adopted = 0
  for _, row in ipairs(ModImports.missing(manifest) or {}) do
    local bytes = ModImports.shared(row.entry)
    if bytes and ModImports.install(manifest, row.entry, bytes, true) then
      adopted = adopted + 1
    end
  end
  return adopted
end

-- Where the file lands.  A mod folder under the save directory is writable; a
-- mod baked into a read-only source tree is not, and there the write simply
-- fails and says so rather than pretending.
function ModImports.pathFor(manifest, entry)
  if not entry then return nil end
  if entry.root == "save" then return entry.file end
  if not (manifest and manifest.path) then return nil end
  return manifest.path .. "/" .. entry.file
end

-- Is one entry already satisfied?  Presence is the test the mod itself makes,
-- so presence is the test here -- a size mismatch is reported but a file that
-- is there is not deleted behind the player's back.
function ModImports.have(manifest, entry)
  local f = fs()
  local path = ModImports.pathFor(manifest, entry)
  if not (f and path) then return false end
  local info = f.getInfo(path, "file")
  if not info then return false end
  if entry.size and info.size and info.size ~= entry.size then
    return false, ("%s is %d bytes; expected %d")
      :format(entry.file, info.size, entry.size)
  end
  return true
end

-- Every unsatisfied entry for one mod, or nil when it needs nothing.
function ModImports.missing(manifest)
  local list = ModImports.of(manifest)
  if not list then return nil end
  local out = {}
  for _, entry in ipairs(list) do
    local ok, why = ModImports.have(manifest, entry)
    if not ok then
      out[#out + 1] = { entry = entry, reason = why }
    end
  end
  return out[1] and out or nil
end

function ModImports.satisfied(manifest)
  return ModImports.missing(manifest) == nil
end

local function md5Of(bytes)
  if not (love and love.data and love.data.hash and love.data.encode) then
    return nil
  end
  local ok, value = pcall(function()
    local digest = love.data.hash("md5", bytes)
    if type(digest) == "userdata" and digest.getString then
      digest = digest:getString()
    end
    return love.data.encode("string", "hex", digest)
  end)
  return ok and value or nil
end

-- N64 cartridge dumps come in three byte orders and only the mod knows which
-- one it wants, so the size and hash checks have to allow all three.  Byte
-- swapping is the mod's job (STADIUM2_IMPORTER's Rom.normalise does it), which
-- is why this converts only for the purpose of CHECKING the hash.
local N64_ORDERS = {
  { magic = "\128\055\018\064", swap = 0 },   -- z64, big endian
  { magic = "\055\128\064\018", swap = 2 },   -- v64, byte swapped
  { magic = "\064\018\055\128", swap = 4 },   -- n64, little endian
}

local function toBigEndian(bytes)
  if #bytes < 4 then return bytes end
  local head = bytes:sub(1, 4)
  for _, order in ipairs(N64_ORDERS) do
    if head == order.magic then
      if order.swap == 0 then return bytes end
      if order.swap == 2 then return (bytes:gsub("(.)(.)", "%2%1")) end
      return (bytes:gsub("(.)(.)(.)(.)", "%4%3%2%1"))
    end
  end
  return bytes
end

-- Check bytes against one entry WITHOUT writing anything.  Returns true, or
-- false plus a sentence the launcher can put on screen.
function ModImports.check(entry, bytes)
  if type(bytes) ~= "string" or bytes == "" then
    return false, "that file is empty"
  end
  if entry.size and #bytes ~= entry.size then
    return false, ("that file is %d bytes; %s needs %d")
      :format(#bytes, entry.name, entry.size)
  end
  if entry.md5 then
    local hash = md5Of(bytes)
    -- an n64 entry accepts any of the three byte orders: hash the big-endian
    -- form, which is what the declared md5 is taken over
    if hash and hash:lower() ~= entry.md5 and entry.format == "n64" then
      hash = md5Of(toBigEndian(bytes))
    end
    if hash and hash:lower() ~= entry.md5 then
      return false, ("that is not the right file (MD5 %s)"):format(hash:sub(1, 8))
    end
  end
  return true
end

-- Validate and install.  Returns true, or false + why.  `fromShared` skips
-- banking the bytes again (they came out of the store).
function ModImports.install(manifest, entry, bytes, fromShared)
  local ok, why = ModImports.check(entry, bytes)
  if not ok then return false, why end
  local f = fs()
  local path = ModImports.pathFor(manifest, entry)
  if not (f and path) then return false, "no writable mod folder" end
  local dir = path:match("^(.*)/[^/]*$")
  if dir and f.createDirectory then f.createDirectory(dir) end
  local wrote, err = f.write(path, bytes)
  if not wrote then
    return false, ("could not write %s (%s)"):format(entry.file, tostring(err))
  end
  if not fromShared then keepShared(entry, bytes) end
  Logger.info("mod import: %s -> %s (%d bytes)", entry.id, path, #bytes)
  return true
end

-- ---------------------------------------------------------------------------
-- Getting the bytes, from anywhere, on any platform
--
-- The launcher's MODS panel was the only place a required import could be
-- satisfied, and only for a mod whose manifest declared one.  That left two
-- holes the reports land in: a mod that ships its own "STADIUM 2 ROM FILE ->
-- CHOOSE" row inside its OPTIONS screen had nothing behind it on desktop (its
-- own picker is Android-only and the engine sandbox hides love.system from
-- mod code), and a mod with no `required_imports` block got no button at all.
--
-- So the acquisition is engine-owned and lives here rather than in the
-- launcher: ManagerState hangs an IMPORT row off every declared entry, in
-- game, on every platform, and the launcher calls the same functions.
-- ---------------------------------------------------------------------------

-- Everywhere a file may already be waiting, in the order it should be trusted.
ModImports.INBOX_DIRS = { SHARED_DIR, "imports", "imports/mods", "" }

-- A file already sitting in the save directory, without asking anyone.
function ModImports.fromInbox(entry)
  local f = fs()
  if not (f and entry) then return nil end
  for _, dir in ipairs(ModImports.INBOX_DIRS) do
    for _, name in ipairs(f.getDirectoryItems(dir) or {}) do
      local path = (dir == "") and name or (dir .. "/" .. name)
      if ModImports.accepts(entry, name) and f.getInfo(path, "file") then
        local bytes = f.read(path)
        if bytes and ModImports.check(entry, bytes) then return bytes, path end
      end
    end
  end
  return nil
end

-- A file the player already dropped INSIDE the mod's own folder.
--
-- This is what people actually do, and it is the most reasonable guess: the
-- mod's README says it wants a Stadium 2 cartridge, so the cartridge goes in
-- the mod's folder.  STADIUM2_OVERWORLD_MODELS then never finds it, because
-- it reads `baseroms/` at the PhysFS root and not its own directory -- so a
-- 64 MB file sat there doing nothing while the mod reported no ROM.  Adopt it.
--
-- Size is checked off getInfo before anything is read, so the common case
-- (nothing there, or the wrong file) never touches 64 MB of disk.
function ModImports.fromModFolder(manifest, entry)
  local f = fs()
  if not (f and entry and manifest and manifest.path) then return nil end
  local roots = { manifest.path }
  local dir = tostring(entry.file):match("^(.*)/[^/]*$")
  if dir then roots[#roots + 1] = manifest.path .. "/" .. dir end
  local target = ModImports.pathFor(manifest, entry)
  for _, root in ipairs(roots) do
    for _, name in ipairs(f.getDirectoryItems(root) or {}) do
      local path = root .. "/" .. name
      if path ~= target and ModImports.accepts(entry, name) then
        local info = f.getInfo(path, "file")
        if info and (not entry.size or info.size == nil
                     or info.size == entry.size) then
          local bytes = f.read(path)
          if bytes and ModImports.check(entry, bytes) then return bytes, path end
        end
      end
    end
  end
  return nil
end

-- Shared store, then the mod's own folder, then the inbox.  No picker, no
-- prompt: this is the "you already gave us this cartridge" path and it must be
-- tried before anything asks.
function ModImports.acquire(manifest, entry)
  local bytes = ModImports.shared(entry)
  if bytes then
    local ok, why = ModImports.install(manifest, entry, bytes, true)
    if ok then return true, "shared" end
    return false, why
  end
  bytes = ModImports.fromModFolder(manifest, entry)
  if bytes then
    local ok, why = ModImports.install(manifest, entry, bytes)
    if ok then return true, "mod folder" end
    return false, why
  end
  bytes = ModImports.fromInbox(entry)
  if bytes then
    local ok, why = ModImports.install(manifest, entry, bytes)
    if ok then return true, "inbox" end
    return false, why
  end
  return false, nil
end

local function commandOutput(command)
  local ok, HostShell = pcall(require, "src.core.HostShell")
  if not ok then return nil end
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  pipe:close()
  result = tostring(result or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return result ~= "" and result or nil
end

-- A native "choose a file" dialog for one entry's extensions.  Deliberately
-- the same three shells the ROM button already uses, so a player who can pick
-- a Game Boy cartridge can pick a base file.  nil means "this platform has no
-- picker", which is a normal answer, not an error.
function ModImports.pickPath(entry)
  local exts = ModImports.extensions(entry)
  if #exts == 0 then return nil end
  if not (love and love.system and love.system.getOS) then return nil end
  local okPlatform, Platform = pcall(require, "src.core.Platform")
  if okPlatform and Platform.canSpawnProcess and not Platform.canSpawnProcess() then
    return nil
  end
  local prompt = "Choose your " .. tostring(entry.name or "file")
  local os_ = love.system.getOS()
  local quoted, globs, semis = {}, {}, {}
  for index, ext in ipairs(exts) do
    quoted[index] = '"' .. ext .. '"'
    globs[index] = "*." .. ext
    semis[index] = "*." .. ext
  end
  if os_ == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {%s})' 2>/dev/null]])
        :format(prompt, table.concat(quoted, ", ")))
  elseif os_ == "Windows" then
    -- the ASCII-temp-name copy the ROM picker does, and for the same reason:
    -- io.open on Windows needs ANSI bytes, and a cartridge path with a
    -- non-ASCII folder in it cannot be opened otherwise
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Base file (" .. table.concat(semis, ";") .. ")|"
        .. table.concat(semis, ";") .. "|All files (*.*)|*.*';",
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_modimport_pick.bin';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput('powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif os_ == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Base file | %s" 2>/dev/null]])
        :format(prompt, table.concat(globs, " ")))
    if path then return path end
    return commandOutput(
      ([[kdialog --getopenfilename "$HOME" "%s|Base file" 2>/dev/null]])
        :format(table.concat(globs, " ")))
  end
  return nil
end

local function readAbsolute(path)
  local file = io.open(path, "rb")
  if file then
    local bytes = file:read("*a")
    file:close()
    if bytes then return bytes end
  end
  local f = fs()
  return f and f.read(path) or nil
end

-- Android / iOS: love.system.pickFile drops the pick into the save directory
-- under a fixed basename and returns immediately, so the answer arrives on a
-- later frame.  ModImports.poll consumes it.
ModImports.PICK_NAMES = { "picked_base.bin", "picked_rom.gb", "picked_rom.gbc",
                          "picked_rom.z64", "picked_rom.n64", "picked_rom.v64" }

local function mobilePick()
  if not (love and love.system and love.system.pickFile) then return false end
  local ok, started = pcall(love.system.pickFile, "base")
  if ok and started then return true end
  ok, started = pcall(love.system.pickFile, "rom")
  return (ok and started) and true or false
end

-- Consume a mobile pick if one has landed.  Safe to call every frame.
function ModImports.poll(manifest, entry)
  local f = fs()
  if not (f and entry) then return false end
  for _, name in ipairs(ModImports.PICK_NAMES) do
    if f.getInfo(name, "file") then
      local bytes = f.read(name)
      f.remove(name)
      if bytes then
        local ok, why = ModImports.install(manifest, entry, bytes)
        return ok, why or "that is not the right file"
      end
    end
  end
  return false
end

-- The line to show when nothing else worked: where to put the file by hand.
function ModImports.hint(entry)
  local f = fs()
  local dir = (f and f.getSaveDirectory and f.getSaveDirectory()) or ""
  local exts = ModImports.extensions(entry)
  return ("Copy your %s (.%s) into:\n%s/imports/")
    :format(tostring(entry.name), table.concat(exts, "/"), dir)
end

-- One call that does the whole thing.  Returns:
--   true,  message   installed
--   nil,   message   a picker was opened; poll() will finish it
--   false, message   nothing doing, and the message says where to put the file
function ModImports.choose(manifest, entry)
  if not (manifest and entry) then return false, "nothing to import" end
  local ok, how = ModImports.acquire(manifest, entry)
  if ok then
    if how == "shared" then
      return true, "Used the " .. tostring(entry.name) .. " you already imported"
    elseif how == "mod folder" then
      return true, "Found your " .. tostring(entry.name) .. " in the mod folder"
    end
    return true, "Imported " .. tostring(entry.name)
  end
  if how then return false, how end   -- found something, but it was wrong

  local path = ModImports.pickPath(entry)
  if path then
    local bytes = readAbsolute(path)
    if not bytes then return false, "could not read that file" end
    local okInstall, why = ModImports.install(manifest, entry, bytes)
    if okInstall then return true, "Imported " .. tostring(entry.name) end
    return false, why
  end

  if mobilePick() then
    return nil, "Choose your " .. tostring(entry.name) .. " in the file picker."
  end
  return false, ModImports.hint(entry)
end

-- The mod-facing view, hung off the mod api as `mod.imports`.  A mod that
-- wants to be polite can ask whether its base file arrived before it starts,
-- rather than failing halfway through an extract.
function ModImports.api(manifest, read)
  local list = ModImports.of(manifest) or {}
  local byId = {}
  for _, entry in ipairs(list) do byId[entry.id] = entry end
  return {
    list = function()
      local copy = {}
      for index, entry in ipairs(list) do
        copy[index] = { id = entry.id, name = entry.name, file = entry.file,
                        root = entry.root, format = entry.format,
                        size = entry.size }
      end
      return copy
    end,
    have = function(_, id)
      local entry = byId[id]
      return entry ~= nil and (ModImports.have(manifest, entry) == true)
    end,
    path = function(_, id)
      local entry = byId[id]
      return entry and entry.file or nil
    end,
    read = function(_, id)
      local entry = byId[id]
      if not entry then return nil end
      if entry.root == "save" then
        local f = fs()
        return f and f.read(entry.file) or nil
      end
      if not read then return nil end
      return read(entry.file)
    end,
  }
end

return ModImports
