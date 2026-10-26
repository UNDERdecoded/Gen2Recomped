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
local ImportFiles = require("src.mods.ImportFiles")

local ModImports = {}

-- The launcher's own trees -- the shared base-file bank under imports/base/
-- and the copy written into a mod's own folder -- follow the player's chosen
-- game-data folder, which love.filesystem cannot reach: it always resolves a
-- write to the OS save directory.  CacheFs.dataFs reads and enumerates through
-- love.filesystem (every home at once, including the chosen root, which is
-- mounted) and routes writes and removes at whichever root is live.
--
-- Falls back to love.filesystem when CacheFs is unavailable, which is how the
-- headless tests run: they inject their own fs and never load it.
local function fs()
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.dataFs then
    local okFs, handle = pcall(CacheFs.dataFs)
    if okFs and handle then return handle end
  end
  return love and love.filesystem
end

-- A declared import, normalised.  `file` is where the mod expects to read it
-- from, relative to the mod folder; everything else is validation.
-- THE SAME GAME IN MORE THAN ONE DUMP.
--
-- A cartridge has one md5 and a manifest names it.  A disc does not: the USA
-- release of a GameCube title exists as several good dumps, and a mod that
-- wants any of them was writing both hashes into the one `md5` string --
-- "aaa..., bbb..." -- which then matched NOTHING.  `check` compared the whole
-- string against a digest, so the import could never be accepted, and
-- `sharedKey` used it as a FILENAME, comma and space included.
--
-- So the field takes either shape: one hash, several in a string, or a list.
-- Every 32-hex run is taken and the rest is ignored, which also absorbs the
-- stray whitespace that comes with writing two of them by hand.  `md5` stays
-- a single string -- it is what names the shared bank and nothing else should
-- have to learn a new shape -- and `md5s` carries the full set for the one
-- place that compares.
local function dense(value,label)
  assert(type(value)=="table",label.." must be an array")
  local count=0
  for key in pairs(value) do
    count=count+1
    assert(type(key)=="number" and key%1==0 and key>=1 and key<=#value,label.." must be an array")
  end
  assert(count==#value,label.." must be an array")
end

local function md5Set(raw)
  local out,seen = {},{}
  local function add(value)
    assert(type(value)=="string","import md5 values must be strings")
    for hash in value:lower():gmatch("[^%s,;]+") do
      assert(#hash==32 and hash:match("^%x+$"),"invalid import md5")
      if not seen[hash] then seen[hash]=true;out[#out+1]=hash end
    end
  end
  if type(raw) == "table" then
    for _, value in ipairs(raw) do add(value) end
  elseif raw~=nil then
    add(raw)
  end
  return out[1], out[1] and out or nil
end

-- "474336453031" or { "...", "..." } -> a list of lowercase hex strings, or
-- nil.  Odd-length or non-hex entries are dropped rather than guessed at: a
-- half-read signature that matches half a file is worse than no check.
local function magicSet(raw)
  if raw == nil then return nil end
  local list = (type(raw) == "table") and raw or { raw }
  local out = {}
  for _, value in ipairs(list) do
    if type(value) == "string" then
      local hex = value:gsub("%s", ""):lower()
      if #hex > 0 and #hex % 2 == 0 and hex:match("^%x+$") then
        out[#out + 1] = hex
      end
    end
  end
  return out[1] and out or nil
end

local function normalise(raw, index, required)
  assert(type(raw) == "table", "import entries must be objects")
  local file = raw.file
  assert(type(file) == "string" and file ~= "", "import file is required")
  assert(not file:find("[%z\1-\31\\:]") and file:sub(1,1) ~= "/", "unsafe import file")
  for part in file:gmatch("[^/]+") do
    assert(part ~= "." and part ~= "..", "unsafe import file")
  end
  assert(not file:find("//",1,true) and file:sub(-1) ~= "/", "unsafe import file")
  local id = raw.id or ("import" .. index)
  assert(type(id) == "string" and id:match("^[%w_%-]+$"), "invalid import id")
  assert(raw.name==nil or type(raw.name)=="string" and raw.name~="", "invalid import name")
  local description=raw.description
  if description==nil then description=raw.hint end
  assert(description==nil or type(description)=="string" and description~="", "invalid import description")
  assert(raw.root == nil or raw.root == "mod" or raw.root == "save" or raw.root == "root", "invalid import root")
  assert(raw.verify == nil or raw.verify == "mod", "import verify must be mod")
  local size, maxSize = tonumber(raw.size), tonumber(raw.max_size)
  for key, value in pairs({size=raw.size,max_size=raw.max_size,magic_offset=raw.magic_offset}) do
    local n = tonumber(value)
    assert(n and n == n and n < math.huge and n % 1 == 0
      and n >= (key == "magic_offset" and 0 or 1), "invalid import " .. key)
  end
  assert(not (size and maxSize) or size <= maxSize, "import size exceeds max_size")
  -- WHERE the mod reads it from.  "mod" (the default) is inside the mod's own
  -- folder, which is all a sandboxed `mod:read` can reach.  "save" is the
  -- PhysFS root -- the save directory and the game folder, searched under one
  -- name -- and some mods genuinely want that: STADIUM2_OVERWORLD_MODELS
  -- looks for `baseroms/stadium2.z64` there and nowhere else, so writing its
  -- cartridge into the mod folder satisfied the manifest and left the mod
  -- still reporting no ROM.  The `..`/absolute guard above applies to both.
  local root = (raw.root == "save" or raw.root == "root") and "save" or "mod"
  assert(root~="save" or not file:match("^imports/staging/") and not file:match("^imports/validated/"), "import path uses engine-owned metadata")
  if type(raw.md5)=="table" then dense(raw.md5,"import md5") end
  local first, all = md5Set(raw.md5)
  if raw.md5 ~= nil then
    local delegated = raw.verify=="mod" and type(raw.md5)=="table" and next(raw.md5)==nil
    assert(first or delegated, "import md5 must contain a 32-character hexadecimal digest")
  end
  local extensions
  if raw.extensions ~= nil then
    dense(raw.extensions,"import extensions")
    assert(type(raw.extensions) == "table" and #raw.extensions > 0, "import extensions must be an array")
    extensions = {}
    for _, ext in ipairs(raw.extensions) do
      assert(type(ext) == "string" and ext:match("^%.?[%w]+$"), "invalid import extension")
      extensions[#extensions+1] = "." .. ext:gsub("^%.", ""):lower()
    end
  end
  local magic = magicSet(raw.magic)
  if raw.magic ~= nil then
    local values = type(raw.magic) == "table" and raw.magic or {raw.magic}
    dense(values,"import magic")
    assert(magic and #magic == #values, "invalid import magic")
    for _, hex in ipairs(magic) do
      assert((tonumber(raw.magic_offset) or 0) + #hex/2 <= 8*1024*1024, "import signature exceeds bounded read limit")
    end
  end
  local portable = (raw.root == nil or raw.portable == true) and not file:find("/",1,true)
  return {
    id = id,
    name = tostring(raw.name or raw.id or file),
    description = description,
    file = file,
    relativeFile = portable and ("baseroms/" .. file) or file,
    portable = portable,
    required = required ~= false,
    root = root,
    format = type(raw.format) == "string" and raw.format:lower() or nil,
    -- WHAT TO RUN ONCE THE FILE IS THERE.
    --
    -- A base file is the start of the mod's work, not the end of the engine's,
    -- and for a disc that work is a long extraction.  A mod can subscribe to
    -- `imports.ready` for this, which is the general answer -- but subscribing
    -- is Lua, and this whole contract is otherwise declarative: the manifest
    -- already says what file it needs and where to put it, so it may as well
    -- say what to call when it lands.  The value names an export the mod
    -- publishes (mod.exports.<name>); anything else is ignored.
    onReady = type(raw.on_ready) == "string" and raw.on_ready ~= ""
      and raw.on_ready or nil,
    -- BYTES THAT PROVE IT IS THE RIGHT FILE, when a hash cannot.
    --
    -- `md5` is the proper answer and is only checked when the file fits this
    -- device's hash budget -- never, for a 1.4 GB disc.  So a disc could match
    -- on size, import cleanly, and be the wrong REGION: a PAL Colosseum
    -- (GC6P01) is byte-for-byte the same length as the USA one (GC6E01) the
    -- mod needs, and the mod only found out after the copy, from inside its
    -- own structural check, as "not structurally valid".
    --
    -- A few bytes at a known offset settle that in constant time at any size.
    -- A list means alternatives (several good dumps, several regions a mod
    -- actually supports); hex, because a game id is bytes and quoting them as
    -- text invites an encoding to get in the way.
    magic = magic,
    magicOffset = math.max(0, math.floor(tonumber(raw.magic_offset) or 0)),
    size = size,
    max_size = maxSize,
    extensions = extensions,
    verify = raw.verify,
    md5 = first,
    md5s = all,
  }
end

-- Manifest.validate hands the parsed list straight through; this is also the
-- reader for a raw manifest table, so the launcher can ask before a mod loads.
function ModImports.parse(raw, field)
  field = field or "required_imports"
  local list = raw and raw[field]
  if list == nil then return nil end
  dense(list,field)
  local out = {}
  for index, entry in ipairs(list) do
    local row = normalise(entry, index, field ~= "optional_imports")
    if row then out[#out + 1] = row end
  end
  return out[1] and out or nil
end

function ModImports.of(manifest)
  if type(manifest) ~= "table" then return nil end
  local out = {}
  for _, list in ipairs({ModImports.required(manifest) or {}, ModImports.optional(manifest) or {}}) do
    for _, entry in ipairs(list) do out[#out+1] = entry end
  end
  return out[1] and out or nil
end

function ModImports.required(manifest)
  if type(manifest) ~= "table" then return nil end
  return manifest.requiredImports or ModImports.parse(manifest.raw or manifest)
end

function ModImports.optional(manifest)
  if type(manifest) ~= "table" then return nil end
  return manifest.optionalImports or ModImports.parse(manifest.raw or manifest,"optional_imports")
end

-- The extensions a picker should offer for one entry.  `format` names a family
-- rather than a single suffix, because a console ROM legitimately arrives in
-- more than one byte order and the mod normalises them itself.
ModImports.FORMATS = {
  n64 = { "z64", "n64", "v64" },
  gb = { "gb", "gbc" },
  gba = { "gba" },
  nds = { "nds" },
  -- A DISC, which is the same argument as a cartridge's byte orders and then
  -- some.  Asked for by a mod that wants a Pokemon Colosseum disc: a GameCube
  -- dump is `.gcm` from some rippers, `.iso` from most, and `.ciso`/`.rvz`
  -- once somebody has compressed it -- all the same disc, and a mod that
  -- declared one spelling refused the other three.
  --
  -- A `format` is only needed when a mod will take MORE than one suffix: with
  -- none, extensions() falls back to the suffix of the declared `file`, which
  -- is why a manifest naming `baseroms/colosseum.iso` already works for a
  -- player whose dump happens to be spelled that way.
  gamecube = { "gcm", "iso", "ciso", "rvz" },
  wii = { "iso", "wbfs", "rvz", "nkit" },
  zip = { "zip" },
}

function ModImports.extensions(entry)
  if not entry then return {} end
  if entry.extensions then
    local out = {}
    for _, ext in ipairs(entry.extensions) do out[#out+1] = ext:gsub("^%.", "") end
    return out
  end
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

-- THE BANK DOES NOT HAVE TO HOLD THE BYTES.
--
-- A `root = "save"` entry already puts the file at the PhysFS root under a
-- stable name that no mod owns and no uninstall removes -- `baseroms/`, for a
-- cartridge.  Banking a SECOND 64 MB copy of it under imports/base/ buys
-- nothing and is a third of a gigabyte for three mods.  So once such a copy
-- exists the bank is downgraded to a one-line pointer at it.
--
-- A `root = "mod"` entry still banks real bytes: that file lives inside a mod
-- folder and goes away with the mod, so the copy is the only thing that keeps
-- the next mod from asking for the cartridge again.
--
-- A pointer whose target has since been deleted simply reads as "nothing
-- banked" and the ordinary import flow asks for the file -- the store is a
-- convenience, never the only copy of anything the player cannot replace.
function ModImports.sharedPointerPath(entry)
  local key = ModImports.sharedKey(entry)
  return key and (SHARED_DIR .. "/" .. key .. ".path") or nil
end

-- Read a shared copy back, or nil.  Follows a pointer bank.
function ModImports.shared(entry)
  local f = fs()
  if not f then return nil end
  local path = ModImports.sharedPath(entry)
  if path and f.getInfo(path, "file") then return f.read(path) end

  local ptr = ModImports.sharedPointerPath(entry)
  if not (ptr and f.getInfo(ptr, "file")) then return nil end
  local target = tostring(f.read(ptr) or ""):gsub("%s+$", "")
  if target == "" then return nil end
  local info = f.getInfo(target, "file")
  if not info then return nil end
  -- cheap guard before 64 MB is read: the pointer is only as good as the file
  -- still sitting at the other end of it
  if entry.size and info.size and info.size ~= entry.size then return nil end
  return f.read(target)
end

-- ...and the same lookup answering a PATH, which is what the streaming
-- installer wants.  A pointer bank can aim at a 1.4 GB disc, so the one caller
-- that used to read it whole is exactly the one that must not.
function ModImports.sharedSource(entry)
  local f = fs()
  if not f then return nil end
  local path = ModImports.sharedPath(entry)
  if path and f.getInfo(path, "file") then return path end
  local ptr = ModImports.sharedPointerPath(entry)
  if not (ptr and f.getInfo(ptr, "file")) then return nil end
  local target = tostring(f.read(ptr) or ""):gsub("%s+$", "")
  if target == "" then return nil end
  local info = f.getInfo(target, "file")
  if not info then return nil end
  if not ImportFiles.layout(entry,f,target,info) then return nil end
  return target
end

-- HOW BIG A BASE FILE THE BANK WILL HOLD A COPY OF.
--
-- The bank exists so a second mod wanting the same file does not send the
-- player looking for it again, and for a 64 MB cartridge a copy is a fair
-- price.  A DISC IS NOT: a GameCube dump is about 1.4 GB, so banking one
-- turns a single import into nearly three gigabytes on disk -- and the player
-- is never told, because the bank is silent by design.
--
-- Above this, the bank keeps a POINTER at the copy that was just written
-- instead (the same one-line record a `root = "save"` entry already gets).  It
-- is a weaker promise -- uninstalling the mod that owns the folder takes the
-- target with it, and the next mod asks again -- but "ask again" is a far
-- better failure than quietly filling a disk.
ModImports.MAX_BANK_BYTES = 256 * 1024 * 1024

local bankPointer

-- Point the bank at a copy that already exists at a stable path, and drop the
-- byte bank if one was taken earlier (that is the 64 MB this reclaims).
function bankPointer(entry, path)
  local f = fs()
  local ptr = ModImports.sharedPointerPath(entry)
  if not (f and ptr and path) then return end
  local bytes = ModImports.sharedPath(entry)
  local banked = bytes and f.getInfo(bytes, "file")
  if f.getInfo(ptr, "file") and not banked then return end
  if f.createDirectory then
    f.createDirectory("imports")
    f.createDirectory(SHARED_DIR)
  end
  local called,written=pcall(f.write,ptr,path)
  if not called or not written or f.read(ptr)~=path then return end
  if banked and f.remove then
    -- only after the pointer is on disk, so a crash between the two leaves
    -- the store with a copy too many rather than none at all
    pcall(f.remove, bytes)
    Logger.info("mod import: shared store now points at %s (freed %d bytes)",
      path, tonumber(banked.size) or 0)
  end
end

-- Satisfy every entry a mod declares from the shared store, silently.  Called
-- when the launcher builds its list, so a second mod that wants a cartridge
-- the player already gave the first one is simply ready.
-- AUTOMATIC ADOPTION HAS A SIZE CEILING, and it is the same ceiling that
-- decides whether the bank keeps bytes or a pointer.
--
-- The bank exists so a player who hands over a 64 MB Stadium cartridge for one
-- mod is not asked for it again by the next: silently satisfying the second
-- mod is the whole feature.  That reasoning holds while "satisfying" costs a
-- few tens of megabytes.  It stops holding at a GameCube disc, where it means
-- the launcher writes 1.4 GB per declaring mod, on every launch that finds one
-- unsatisfied, without anybody asking -- reported from a log showing two
-- back-to-back 1.4 GB streams into two mod folders before the window was even
-- up.
--
-- So above MAX_BANK_BYTES the bank still remembers WHERE the file is (that is
-- what the pointer is for, and it is what stops the player having to find it
-- again), but putting a second copy inside a second mod is a decision with a
-- price, and the player makes it by pressing Import base file on that mod's
-- card.  One press, one stream, and nothing happens behind their back.
function ModImports.autoAdoptLimit()
  return ModImports.MAX_BANK_BYTES
end

function ModImports.adoptShared(manifest)
  local adopted = 0
  for _, row in ipairs(ModImports.missing(manifest) or {}) do
    local banked = ModImports.sharedSource(row.entry)
    local size = nil
    if banked then
      local f = fs()
      local info = f and f.getInfo(banked, "file")
      size = info and info.size or row.entry.size
    end
    -- An unknown size is treated as small: every base file that predates this
    -- was, and refusing to adopt something we cannot measure would turn a
    -- working setup into one that asks again for no reason.
    local tooBig = size ~= nil and size > ModImports.autoAdoptLimit()
    if banked and not tooBig
       and ModImports.installFrom(manifest, row.entry,
                                  { savePath = banked },
                                  { fromShared = true }) then
      adopted = adopted + 1
    end
  end
  return adopted
end

-- Where the file lands.  A mod folder under the save directory is writable; a
-- mod baked into a read-only source tree is not, and there the write simply
-- fails and says so rather than pretending.
--
-- `root = "save"` puts it at the top of the LOVE save directory instead of
-- inside the mod, which is what a mod declares when the file is big and shared
-- (a 64 MB cartridge two mods both extract from).  Worth knowing when the
-- panel says "ready" and the mod folder looks empty: for those entries the
-- file was never meant to be in the mod folder at all.  ModImports.describe
-- below is what the card prints so that is not a guess.
function ModImports.pathFor(manifest, entry, handle)
  if not entry then return nil end
  if entry.root == "save" then return entry.file end
  if not (manifest and manifest.path) then return nil end
  local canonical = manifest.path .. "/" .. (entry.relativeFile or entry.file)
  local legacy = manifest.path .. "/" .. entry.file
  handle = handle or fs()
  if canonical ~= legacy and handle and handle.getInfo
      and not handle.getInfo(canonical,"file") and handle.getInfo(legacy,"file") then
    return legacy
  end
  return canonical
end

-- Both declared spellings resolve to the same existing file, without copying
-- a player's legacy import or exposing a path outside this mod's declarations.
function ModImports.resolveRead(manifest, relative, handle)
  for _, entry in ipairs(ModImports.of(manifest) or {}) do
    if entry.root ~= "save" and (relative == entry.file or relative == entry.relativeFile) then
      return ModImports.pathFor(manifest,entry,handle)
    end
  end
  return nil
end

-- A one-line "where is it" for the launcher.  "<name>: ready" on its own was
-- true and useless -- it says a file exists without saying which file or
-- where, so a player looking in the mod folder for a `root = "save"` entry
-- reasonably concludes the panel is lying.
function ModImports.describe(manifest, entry)
  local path = ModImports.pathFor(manifest, entry)
  if not path then return tostring(entry and entry.name or "file") end
  -- a mod-folder path already names the mod folder; only the save-dir case
  -- needs the prefix, and that is exactly the case that confused people
  local where = (entry.root == "save") and ("save dir/" .. path) or path
  -- ...and if it is in the shared store, SAY SO.  adoptShared installs a file
  -- the player gave a DIFFERENT mod, silently, when the launcher builds its
  -- list -- correct, declared by the manifest, and completely invisible: the
  -- report this answers is "it is auto-installing the ROM and I don't know
  -- where it is getting this from".
  local f = fs()
  local bank = ModImports.sharedPath(entry)
  local ptr = ModImports.sharedPointerPath(entry)
  local shared = f ~= nil
    and ((bank ~= nil and f.getInfo(bank, "file") ~= nil)
      or (ptr ~= nil and f.getInfo(ptr, "file") ~= nil))
  return ("%s: ready (%s)%s"):format(tostring(entry.name), where,
    shared and " -- shared with your other mods that want this file" or "")
end

-- A declaration is satisfied only by a validated file. Invalid existing
-- files are reported and retained; validation never deletes player imports.
function ModImports.have(manifest, entry, handle)
  local f = handle or fs()
  local path = ModImports.pathFor(manifest, entry, f)
  local called,layout,why = pcall(ImportFiles.validate,entry,f,path)
  if not called then return false,tostring(layout) end
  return layout~=nil, why, layout
end

-- Every unsatisfied entry for one mod, or nil when it needs nothing.
function ModImports.missing(manifest, optional, handle)
  local list = optional and ModImports.optional(manifest) or ModImports.required(manifest)
  if not list then return nil end
  local out = {}
  for _, entry in ipairs(list) do
    local ok, why = ModImports.have(manifest, entry, handle)
    if not ok then
      out[#out + 1] = { entry = entry, reason = why }
    end
  end
  return out[1] and out or nil
end

function ModImports.satisfied(manifest)
  return ModImports.missing(manifest) == nil
end

-- Validate a caller-owned byte string through the same bounded range path.
function ModImports.check(entry,bytes)
  if type(bytes)~="string" or bytes=="" then return false,"that file is empty" end
  local memory={getInfo=function()return {type="file",size=#bytes}end,
    readRange=function(_,at,length)return bytes:sub(at+1,at+length)end}
  local row,why=ImportFiles.validate(entry,memory,"bytes")
  return row~=nil,why
end

-- Validate and install.  Returns true, or false + why.  `fromShared` skips
-- banking the bytes again (they came out of the store).
function ModImports.install(manifest, entry, bytes, fromShared)
  if type(bytes)~="string" or bytes=="" then return false,"that file is empty" end
  return ModImports.installFrom(manifest,entry,{bytes=bytes},{fromShared=fromShared})
end

-- ---------------------------------------------------------------------------
-- COPYING A BASE FILE WITHOUT HOLDING IT
--
-- Reported from play: importing a ROM from the launcher was crashing it.  Every
-- path here read the whole file into one Lua string -- the picker's, the
-- inbox's, the mod folder's -- and then `install` held that string while
-- love.data.hash walked it, while love.filesystem.write copied it out, and
-- while keepShared wrote a second copy.  For a 64 MB Stadium 2 cartridge that
-- is a couple of hundred megabytes live at once, which a desktop shrugs off
-- and an Android heap does not; for the 1.4 GB GameCube disc a mod now wants
-- it cannot work anywhere.
--
-- So the bytes are STREAMED: a megabyte at a time, source to destination, with
-- one chunk live.  Peak memory stops depending on the size of the file, which
-- is the whole of the fix -- a phone copies a disc as comfortably as a
-- cartridge, and a 32-bit build never has to find a contiguous 1.4 GB.
--
-- Hashes are incremental too. Validation therefore has the same bounded
-- memory use for a cartridge, a large optical image and a phone import.
-- A completed file is published only after its declared checks succeed.
-- ---------------------------------------------------------------------------

ModImports.COPY_CHUNK = 1024 * 1024

-- Legacy allocation hint retained for callers; streamed import validation
-- no longer skips a checksum above this size.  Deliberately conservative: the number is a budget for one transient
-- allocation on top of everything the launcher or the running game is already
-- holding, not a measure of free memory.
function ModImports.hashLimit()
  local os_ = love and love.system and love.system.getOS and love.system.getOS()
  if os_ == "Android" or os_ == "iOS" then return 24 * 1024 * 1024 end
  -- A 32-bit process has about 2 GB of address space for everything, and it
  -- fragments; a 64 MB cartridge is already an uncomfortable single block.
  local arch = jit and jit.arch
  if arch and arch ~= "x64" and arch ~= "arm64" and arch ~= "mips64" then
    return 48 * 1024 * 1024
  end
  return 256 * 1024 * 1024
end

-- A reader over either kind of path, with the size known up front and nothing
-- read until it is asked for.  `savePath` is a PhysFS name (the inbox, a mod
-- folder); `path` is an absolute one off a native picker.
function ModImports.openSource(source)
  local f = fs()
  if type(source)=="table" and type(source.bytes)=="string" then
    local body,at=source.bytes,0
    return {size=#body,read=function(n)
      local data=body:sub(at+1,at+n);at=at+#data
      return #data>0 and data or nil
    end,close=function()end}
  end
  if type(source) == "table" and source.savePath then
    if not (f and f.newFile) then return nil, "no filesystem" end
    local info = f.getInfo(source.savePath, "file")
    if not info then return nil, "that file is not there any more" end
    local made,handle = pcall(f.newFile,source.savePath)
    if not made or not handle then return nil,"that file could not be opened" end
    local called,ok = pcall(handle.open,handle,"r")
    if not called or not ok then pcall(handle.close,handle);return nil, "that file could not be opened" end
    return {
      size = info.size,
      read = function(n)
        local chunk = handle:read(n)
        return (chunk and #chunk > 0) and chunk or nil
      end,
      close = function() pcall(handle.close, handle) end,
    }
  end
  local path = type(source) == "table" and source.path or source
  if type(path) ~= "string" then return nil, "no file given" end
  local handle = io.open(path, "rb")
  if not handle then
    -- a save-dir-relative name handed in as a plain string
    if f and f.getInfo(path, "file") then
      return ModImports.openSource({ savePath = path })
    end
    return nil, "that file could not be opened"
  end
  local size = handle:seek("end")
  handle:seek("set")
  return {
    size = size,
    read = function(n)
      local chunk = handle:read(n)
      return (chunk and #chunk > 0) and chunk or nil
    end,
    close = function() pcall(handle.close, handle) end,
  }
end

-- Copy `reader` to a PhysFS path a chunk at a time.  Returns the bytes
-- written, or nil plus a reason -- and cleans up a half-written file, because
-- a truncated cartridge that LOOKS installed is the worst of the outcomes
-- (the mod finds a file, reads garbage, and blames the dump).
-- `head`, when given, is bytes already taken off the front of `reader` -- the
-- signature check consumes a prefix, and a stream cannot be rewound, so those
-- bytes have to be written back before the rest or the copy is short by
-- exactly that much.
local function streamTo(reader, path, head, options)
  options=options or {}
  local f = fs()
  if not (f and f.newFile) then return nil, "no writable filesystem" end
  local dir = path:match("^(.*)/[^/]*$")
  if dir and f.createDirectory then f.createDirectory(dir) end
  local out = f.newFile(path)
  if not out then return nil,"could not create import staging file" end
  local called,opened, openErr = pcall(out.open,out,"w")
  if not called or not opened then
    pcall(out.close,out)
    return nil, ("could not write %s (%s)"):format(path, tostring(openErr))
  end
  local written,pending=0,""
  local layout=options.layout or {offset=0,width=1}
  local skip=layout.offset
  local digest=options.hash and require("src.mods.StreamMD5").new() or nil
  local function consume(raw)
    local data=raw
    if skip>0 then local n=math.min(skip,#data);data=data:sub(n+1);skip=skip-n end
    data=pending..data
    local full=math.floor(#data/layout.width)*layout.width
    pending=data:sub(full+1)
    data=ImportFiles.swap(data:sub(1,full),layout.width)
    if digest then digest:update(data) end
    local output=options.canonical and data or raw
    if #output>0 then
      local ok,err=out:write(output)
      if not ok then error(err or "could not write import",0) end
      written=written+#output
    end
  end
  local ok,err=pcall(function()
    if head and #head>0 then consume(head) end
    while true do
      local chunk,readErr=reader.read(ModImports.COPY_CHUNK)
      if not chunk then if readErr then error(readErr,0) end;break end
      if #chunk==0 then break end
      consume(chunk)
    end
    if #pending>0 or skip>0 then error("incomplete import stream",0) end
  end)
  local closed,closeResult=pcall(out.close,out)
  if not ok or not closed or closeResult==false then
    if f.remove then pcall(f.remove,path) end
    return nil,tostring(err or "could not finish import")
  end
  return written,nil,digest and digest:final()
end

local importSerial=0
local function incoming(path)
  importSerial=importSerial+1
  return "imports/staging/"..require("src.mods.StreamMD5").new():update(path):final().."-"..importSerial..".part"
end

local function publish(f,from,to)
  if f.rename then return f.rename(from,to) end
  local source=require("src.core.SaveSafety").realPath(f,from)
  local target=require("src.core.SaveSafety").realPath(f,to)
  if source and target then return require("src.net.DownloadPublish")(source,target) end
  return nil,"atomic import publication is unavailable"
end

local function bankPublished(entry,path)
  if entry.root=="save" then bankPointer(entry,path);return end
  local f=fs()
  local stat=f.getInfo(path,"file")
  if not stat or not stat.size or stat.size>ModImports.MAX_BANK_BYTES then bankPointer(entry,path);return end
  local bank=ModImports.sharedPath(entry)
  if not bank or f.getInfo(bank,"file") then return end
  local reader=ModImports.openSource({savePath=path})
  if not reader then return end
  local staged=incoming(bank)
  local written=streamTo(reader,staged)
  reader.close()
  local info=f.getInfo(staged,"file")
  if written==stat.size and info and info.size==written then publish(f,staged,bank) end
  if f.remove and f.getInfo(staged,"file") then f.remove(staged) end
end

-- Install from a FILE rather than from bytes.
--
-- Returns ok, why, notes -- where `notes` is a sentence about what could not
-- be verified, or nil when everything was.
-- matchMagic(entry, prefix) -> true, or false plus what was there instead.
-- `prefix` is the first bytes of the candidate, at least magicOffset + the
-- signature length.  Separate from the reading so it can be tested without a
-- filesystem, and so `have` can use it later without re-deriving the rule.
function ModImports.matchMagic(entry, prefix)
  if not (entry and entry.magic) then return true end
  local want = entry.magic
  local at = (entry.magicOffset or 0) + 1
  local need = 0
  for _, hex in ipairs(want) do need = math.max(need, #hex / 2) end
  local got = tostring(prefix or ""):sub(at, at + need - 1)
  local hexGot = got:gsub(".", function(c) return ("%02x"):format(c:byte()) end)
  for _, hex in ipairs(want) do
    if hexGot:sub(1, #hex) == hex then return true end
  end
  -- Printable where it is printable: a disc's game id is ASCII, and "GC6P01"
  -- next to "GC6E01" is a diagnosis anybody can read, where two hex strings
  -- are a puzzle.
  local shown = got:gsub("%c", "."):gsub("[\128-\255]", ".")
  return false, shown, hexGot
end

function ModImports.installFrom(manifest, entry, source, opts)
  opts = opts or {}
  local f = fs()
  local path = ModImports.pathFor(manifest, entry, f)
  if not (path and f) then return false, "no writable mod folder" end
  local reader, why = ModImports.openSource(source)
  if not reader then return false, why end
  local need = entry.format == "n64" and 516 or 0
  for _, hex in ipairs(entry.magic or {}) do
    need = math.max(need,(entry.magicOffset or 0)+#hex/2)
  end
  need = math.min(need,reader.size or need)
  local prefix = ""
  if need>0 then
    local called,result=pcall(reader.read,need)
    if not called then reader.close();return false,tostring(result) end
    prefix=result
  end
  if type(prefix) ~= "string" or #prefix ~= need then
    reader.close();return false,"source import could not be read"
  end
  local probe = {readRange=function(_,offset,length)return prefix:sub(offset+1,offset+length)end}
  local layout,layoutErr = ImportFiles.layout(entry,probe,"source",{size=reader.size})
  if not layout then reader.close();return false,layoutErr end
  if not ModImports.matchMagic(entry,prefix) then
    reader.close();return false,"import signature does not match declaration"
  end
  local made,staged = pcall(incoming,path)
  if not made then reader.close();return false,tostring(staged) end
  local streamed,written,streamErr,value = pcall(streamTo,reader,staged,prefix,{
    layout=layout,canonical=entry.portable==true,
    hash=entry.md5~=nil and entry.verify~="mod",
  })
  reader.close()
  if not streamed then streamErr,written=tostring(written),nil end
  local function clean()
    if f.remove then pcall(f.remove,staged) end
    ImportFiles.invalidate(f,staged)
  end
  local expected = entry.portable and layout.size or reader.size
  if written ~= expected then
    clean();return false,streamErr or "source import changed while copying"
  end
  local stagedInfo=f.getInfo(staged,"file")
  if not stagedInfo or stagedInfo.size~=written then
    clean();return false,"copied import is incomplete"
  end
  local valid,verifyErr = ImportFiles.record(entry,f,staged,value)
  if not valid then clean();return false,verifyErr end
  local called,published,publishErr = pcall(publish,f,staged,path)
  if not called or not published then
    clean();return false,tostring(publishErr or published or "could not publish import")
  end
  ImportFiles.invalidate(f,staged)
  ImportFiles.invalidate(f,path)
  valid,verifyErr = ImportFiles.record(entry,f,path,value)
  if not valid then return false,verifyErr end
  if not opts.fromShared then
    local banked,bankErr = pcall(bankPublished,entry,path)
    if not banked then Logger.warn("import shared copy unavailable: %s",tostring(bankErr)) end
  end
  Logger.info("mod import: %s -> %s (%d bytes, streamed and validated)",entry.id,path,written)
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
      local info = ModImports.accepts(entry, name) and f.getInfo(path, "file")
      -- size off getInfo first: a save dir with several cartridges in it must
      -- not read every one of them into memory to reject them by hash
      -- ...and the PATH is the answer, not the bytes: installFrom streams it
      -- from here and never has the whole cartridge in hand.  The hash is
      -- checked there, where the decision about whether it can be afforded
      -- lives.
      if info and (not entry.size or info.size == nil
                   or info.size == entry.size) then
        return path
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
          return path
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
  -- IS IT ALREADY THERE?  Asked FIRST, and it was not asked at all.
  --
  -- Without this the next branch finds the file in the shared bank and
  -- installs it again -- over a copy byte-for-byte identical to itself.  For
  -- the 64 MB cartridge this API was written for that was a wasteful no-op
  -- nobody noticed.  For a 1.4 GB disc it is 1.4 GB rewritten every time the
  -- player presses the mod's own import button, and then a return of "used the
  -- one you already imported", which reads like a refusal and is why a mod
  -- stopped there instead of going on to extract.
  --
  -- `present` is its own answer rather than folded into "shared", so a mod can
  -- tell "I have just fetched this for you" from "it was already in place"
  -- without parsing the sentence.
  if ModImports.have(manifest, entry) == true then
    return true, "present"
  end
  local banked = ModImports.sharedSource(entry)
  if banked then
    local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                  { savePath = banked },
                                                  { fromShared = true })
    if ok then return true, "shared", notes end
    return false, why
  end
  -- Both of these answer a PATH now, and installFrom streams it: the file may
  -- be a 1.4 GB disc and the point is never to hold one.
  local path = ModImports.fromModFolder(manifest, entry)
  if path then
    local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                  { savePath = path })
    if ok then return true, "mod folder", notes end
    return false, why
  end
  path = ModImports.fromInbox(entry)
  if path then
    local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                  { savePath = path })
    if ok then return true, "inbox", notes end
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
      -- STREAMED, and removed only once it has landed.  This is the Android
      -- path, which is exactly where reading a 64 MB cartridge into one string
      -- was killing the process -- and the pick is a real file in the save
      -- directory, so there is nothing to hold.
      local ok, why, notes = ModImports.installFrom(manifest, entry,
                                                    { savePath = name })
      f.remove(name)
      return ok, notes or why or "that is not the right file"
    end
  end
  return false
end

-- TELL THE MOD ITS BASE FILE IS THERE.
--
-- A base file is not the end of anything -- it is the START of whatever the
-- mod does with it, which for a disc is usually an extraction that takes
-- minutes.  The engine has no idea what that is, so the only correct thing it
-- can do is say "it is here" and get out of the way.
--
-- Without this the manager's row was a dead end: a player with the file
-- already in place pressed it, got "ALREADY IMPORTED", and nothing ran -- the
-- engine had swallowed the one press that was meant to start the work.
--
-- `already` distinguishes "this just arrived" from "you pressed the row and it
-- was already here", because a mod may want to build on the first and rebuild
-- on the second.  Returns whether anything was actually listening, so the
-- caller can tell a press that started something from one that did not.
ModImports.READY_EVENT = "imports.ready"

function ModImports.announce(manifest, entry, already)
  if not (manifest and entry) then return false end
  local ok, Runtime = pcall(require, "src.mods.Runtime")
  if not (ok and type(Runtime) == "table" and Runtime.emit) then return false end
  -- `wants` is the cheap guard the rest of the engine uses, and here it is
  -- also the ANSWER: no listener means no mod asked to be told, which is what
  -- the manager reports instead of pretending something began.
  if Runtime.wants and not Runtime.wants(ModImports.READY_EVENT) then
    return false
  end
  Runtime.emit(ModImports.READY_EVENT, {
    mod = manifest.id,
    import = entry.id,
    file = entry.file,
    already = already and true or false,
  })
  return true
end

-- WHAT THE ENGINE ACTUALLY SEES for one entry, in one line, for a log.
--
-- A mod that reports "not imported" while the panel beside it says READY is
-- two components disagreeing about the same file, and every way of guessing
-- which one is wrong costs a round trip with somebody who just wants to play.
-- This says, from the engine's side: which ids are declared, which one was
-- asked for, where that file is expected, and whether it is there.
-- `live` is the mod's OWN imports object when the caller can reach it (the
-- loader keeps one per mod).  That is the last thing this cannot otherwise
-- see: every check here can read correct against a freshly built api while the
-- object the mod is actually holding answers differently, and those are two
-- completely different bugs.
function ModImports.diagnose(manifest, entry, live)
  local ids = {}
  for _, row in ipairs(ModImports.of(manifest) or {}) do
    ids[#ids + 1] = tostring(row.id)
  end
  local path = entry and ModImports.pathFor(manifest, entry) or nil
  local f = fs()
  local info = (f and path) and f.getInfo(path, "file") or nil
  local ok, why = false, nil
  if entry then ok, why = ModImports.have(manifest, entry) end
  -- ...AND WHAT THE MOD-FACING API ITSELF ANSWERS, asked through the same
  -- public call a mod makes.  Everything above is the engine checking its own
  -- bookkeeping, and all of it can be right while `mod.imports:info(id)` still
  -- hands a mod nil -- which is the disagreement worth splitting, because one
  -- answer means the engine is wrong and the other means the mod is holding a
  -- different object than it thinks.
  local apiSays = "?"
  pcall(function()
    local probe = ModImports.api(manifest, nil)
    local row = probe and probe.info and probe.info(nil, entry and entry.id)
    apiSays = row and ("row(ready=" .. tostring(row.ready) .. ")") or "nil"
  end)
  -- ...and the same question put to the object the MOD is holding.
  local liveSays = "unavailable"
  if live then
    liveSays = "?"
    pcall(function()
      if type(live.info) ~= "function" then
        liveSays = "no info fn (" .. type(live.info) .. ")"
        return
      end
      -- THE SECOND RETURN IS THE ANSWER.  `info` answers (row) or (nil, why),
      -- and a wrapper around it -- a mod normalising CISO/trimmed disc images,
      -- say -- puts its whole diagnosis in that second value.  Throwing it
      -- away left "nil" on its own, which says something failed and nothing
      -- about what, and cost several rounds of guessing.
      local row, why = live:info(entry and entry.id)
      liveSays = row and ("row(ready=" .. tostring(row.ready) .. ")")
                 or ("nil(" .. tostring(why) .. ")")
      -- ALWAYS list what the live object declares, and emphatically not only
      -- when the lookup succeeded: a nil lookup is the case this line exists
      -- for, and the list beside it is what says WHY -- an id spelled
      -- differently, a shorter list, or an empty one because the object was
      -- built from a manifest that declared nothing.  Printing it only on
      -- success withheld the evidence in precisely the failure it was added
      -- to explain.
      if type(live.list) == "function" then
        local declared = {}
        for _, r in ipairs(live:list() or {}) do
          declared[#declared + 1] = tostring(r.id)
        end
        liveSays = liveSays .. " of [" .. table.concat(declared, ",") .. "]"
      end
      -- WHEN THE LOOKUP FAILED, SAY WHAT THE OBJECT ACTUALLY IS.
      --
      -- Naming the one method that was missing produced a riddle -- an object
      -- with `info` and no `list` matches neither the imports api nor the
      -- cache, and every guess at which third thing it might be cost another
      -- round trip.  The object's own shape answers that in one line and needs
      -- no theory at all.
      if not row then
        local shape = {}
        for k, v in pairs(live) do shape[#shape + 1] = tostring(k) .. "=" .. type(v) end
        table.sort(shape)
        if #shape > 12 then
          shape[13] = "..."
          for i = #shape, 14, -1 do shape[i] = nil end
        end
        liveSays = liveSays .. " shape{" .. table.concat(shape, " ") .. "}"
        local mt = getmetatable(live)
        if mt then liveSays = liveSays .. "+mt" end
      end
    end)
  end
  -- AND THE RANGE READ ITSELF, which is what a wrapper is built on: a mod
  -- normalising a disc image reads its header and tables through
  -- mod.imports:read(id, offset, length) before it will call the file valid.
  -- Sixteen bytes from the front, as hex -- a GameCube disc opens with its
  -- game id, so this is both "does the read path work" and "is this the disc
  -- it claims to be", and those are the two remaining suspects.
  local head = "?"
  pcall(function()
    local probe = ModImports.api(manifest, nil)
    local bytes, err = probe.read(nil, entry and entry.id, 0, 16)
    if type(bytes) ~= "string" then
      head = "nil(" .. tostring(err) .. ")"
      return
    end
    local hex = {}
    for i = 1, #bytes do hex[i] = ("%02X"):format(bytes:byte(i)) end
    head = ("%d:%s |%s|"):format(#bytes, table.concat(hex),
                                 (bytes:gsub("%c", ".")))
  end)
  return ("mod=%s declared=[%s] asked=%s path=%s onDisk=%s have=%s api:info=%s api:read=%s mod:info=%s%s")
    :format(tostring(manifest and manifest.id),
            table.concat(ids, ","),
            tostring(entry and entry.id),
            tostring(path),
            info and tostring(info.size) or "no",
            tostring(ok),
            apiSays,
            head,
            liveSays,
            why and (" (" .. tostring(why) .. ")") or "")
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
--   true,  message, how   installed (or already in place)
--   nil,   message        a picker was opened; poll() will finish it
--   false, message        nothing doing; the message says where to put the file
--
-- `how` is the third return so a mod can branch on the OUTCOME rather than on
-- the wording -- "present", "shared", "mod folder", "inbox" or "picked".  A mod
-- that only reads the first two values is unaffected, which is every mod
-- written before this.
function ModImports.choose(manifest, entry)
  if not (manifest and entry) then return false, "nothing to import" end
  local ok, how = ModImports.acquire(manifest, entry)
  if ok then
    if how == "present" then
      -- Phrased as a STATE, not as something that was just declined.  "Used
      -- the one you already imported" was true and read as a refusal.
      return true, tostring(entry.name) .. " is ready", how
    elseif how == "shared" then
      return true, "Used the " .. tostring(entry.name) .. " you already imported",
             how
    elseif how == "mod folder" then
      return true, "Found your " .. tostring(entry.name) .. " in the mod folder",
             how
    end
    return true, "Imported " .. tostring(entry.name), how
  end
  if how then return false, how end   -- found something, but it was wrong

  local path = ModImports.pickPath(entry)
  if path then
    local okInstall, why, notes =
      ModImports.installFrom(manifest, entry, { path = path })
    if okInstall then
      return true, notes or ("Imported " .. tostring(entry.name)), "picked"
    end
    return false, why
  end

  if mobilePick() then
    return nil, "Choose your " .. tostring(entry.name) .. " in the file picker."
  end
  return false, ModImports.hint(entry)
end

-- HOW MUCH OF AN IMPORT ONE `read` MAY HAND BACK.
--
-- The files behind this API are cartridges: STADIUM2_IMPORTER's is a 64 MB
-- N64 ROM.  A mod walking one in chunks is the normal case, and a slice API
-- that loads the whole file per call allocates 64 MB per chunk -- which is
-- the difference between working and an out-of-memory kill on Android and
-- the Deck.  Below is what one sliced read may return; a mod that wants more
-- than this asks again with a further offset.
--
-- A WHOLE-FILE read (no offset, no length) is NOT capped: it is the call a
-- mod makes once, deliberately, for a file it already declared the size of.
ModImports.MAX_READ_BYTES = 8 * 1024 * 1024

-- One slice of a file without reading the rest of it.
--
-- love.filesystem.newFile/seek/read is the only path that actually avoids the
-- allocation; an injected fs in a test has read() and nothing else, so this
-- returns nil there and the caller falls back to reading whole and cutting.
-- Never the other way around: the fallback is the slow path, not the default.

-- The mod-facing view, hung off the mod api as `mod.imports`.  A mod that
-- wants to be polite can ask whether its base file arrived before it starts,
-- rather than failing halfway through an extract.
--
-- ------- this table is a published API, so it only ever GROWS
--
-- `list`, `have`, `path` and `read` are what mods written against this engine
-- already call, and every field `list` returns is one a mod filters on --
-- `format` to offer the right extensions, `size` to size a progress bar,
-- `root` to tell a mod-folder file from a save-dir one.  A revision that
-- narrows any of them breaks a mod silently, at the one moment the mod is
-- trying to find out whether it can run at all.  `info` and the offset/length
-- arguments to `read` are additions on top; nothing above them moved.
function ModImports.api(manifest, read, handle)
  local function filesystem() return handle or fs() end
  local list = ModImports.of(manifest) or {}
  local byId = {}
  for _, entry in ipairs(list) do byId[entry.id] = entry end
  local api
  api = {
    list = function()
      local copy = {}
      for index, entry in ipairs(list) do
        local extensions
        if entry.extensions then
          extensions={};for i,ext in ipairs(entry.extensions) do extensions[i]=ext end
        end
        copy[index] = { id = entry.id, name = entry.name, file = entry.file,
                        root = entry.root, format = entry.format,
                        size = entry.size, required = entry.required ~= false,
                        max_size = entry.max_size, extensions = extensions }
      end
      return copy
    end,
    -- ...and WHY NOT, when not.  ModImports.have checks the declared size as
    -- well as existence -- a half-copied cartridge is the failure this API is
    -- for -- and the reason it gives is the one the launcher shows.
    have = function(_, id)
      local entry = byId[id]
      if not entry then return false, "no import declared with that id" end
      local ok, why = ModImports.have(manifest, entry, filesystem())
      return ok == true, why
    end,
    path = function(_, id)
      local entry = byId[id]
      return entry and entry.file or nil
    end,
    -- Everything the mod declared about one import plus what is on disk now.
    -- `ready` is the same answer `have` gives, so a mod needs one call rather
    -- than two to decide whether to start.
    info = function(_, id)
      local entry = byId[id]
      if not entry then return nil end
      local ok, why, layout = ModImports.have(manifest, entry, filesystem())
      if entry.portable and not ok then return nil,why end
      local row = { id = entry.id, name = entry.name, file = entry.file,
                    root = entry.root, format = entry.format,
                    size = entry.size, ready = ok == true, reason = why,
                    required = entry.required ~= false,
                    md5 = layout and layout.md5, verified = layout and layout.verified }
      local f = filesystem()
      local at = ModImports.pathFor(manifest, entry, f)
      local on = f and at and f.getInfo(at, "file") or nil
      if on then
        row.bytes = on.size
        row.modtime = on.modtime
      end
      -- A MANIFEST NEED NOT DECLARE A SIZE, and `size` is the field a mod
      -- bounds a chunked read with.  An entry for a disc image that does not
      -- declare one -- because the same title ships in more than one length,
      -- or because nobody wanted a 1.4 GB number in a JSON file -- left `size`
      -- nil, and a mod that reads it to work out how many chunks to ask for
      -- stops there with "import size is unavailable" even though the file is
      -- sitting right beside it and `bytes` already knew how long it was.
      --
      -- The declared size still WINS when there is one: it is the number
      -- `have` refuses a half-copied file against, and a fallback that
      -- overrode it would quietly turn that check into a tautology.  This only
      -- fills a hole.
      if entry.portable and layout then row.size = layout.size
      elseif row.size == nil then row.size = row.bytes end
      return row
    end,
    -- `read(id)` is the whole file; `read(id, offset, length)` is a slice,
    -- capped at MAX_READ_BYTES so chunking a cartridge stays chunked.
    read = function(_, id, offset, length)
      local entry = byId[id]
      if not entry then return nil,"undeclared import: "..tostring(id) end
      local f=filesystem()
      local path=ModImports.pathFor(manifest,entry,f)
      local valid,why,layout=ModImports.have(manifest,entry,f)
      if not valid then return nil,why end
      if entry.portable then
        if offset==nil or length==nil then return nil,"offset and length are required" end
        return ImportFiles.canonicalRange(f,path,layout,tonumber(offset),tonumber(length))
      end
      local whole = function()
        if entry.root == "save" then
          local f = filesystem()
          return f and f.read(entry.file) or nil
        end
        if not read then return nil end
        return read(entry.relativeFile or entry.file)
      end
      if offset == nil and length == nil then return whole() end
      local at = math.floor(tonumber(offset) or 0)
      if at < 0 then return nil, "offset must not be negative" end
      local want = math.floor(tonumber(length) or ModImports.MAX_READ_BYTES)
      if want < 0 then return nil, "length must not be negative" end
      if want > ModImports.MAX_READ_BYTES then
        return nil, ("a sliced read is capped at %d bytes; ask again with a "
                     .. "further offset"):format(ModImports.MAX_READ_BYTES)
      end
      if want == 0 then return "" end
      local size=layout and layout.physicalSize
      if size and at+want>size then return nil,"import read is out of bounds" end
      local cut = path and ImportFiles.range(f,path,at,want,size)
      if cut ~= nil then return cut end
      if size and size>ModImports.MAX_READ_BYTES then return nil,"bounded file access is unavailable" end
      local body = whole()
      if not body then return nil end
      return body:sub(at + 1, at + want)
    end,
  }
  return api
end

return ModImports
