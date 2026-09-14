-- `mod.imports` and `mod.cache`: the two things a ported mod asks the host for
-- before it can do any work.
--
-- Both already existed here under other names, which is the whole point of
-- this file.  A mod written against the Gen 1 port says
--
--   local rom = mod.imports:read("stadium2", offset, 0x8000)
--   mod.cache:write("models/pikachu.bin", blob)
--
-- and this engine's answers to those two questions are src/mods/ModImports.lua
-- and src/mods/Storage.lua.  So this is an ADAPTER and not a second
-- implementation: `imports` IS ModImports.api, and `cache` is the Gen 1
-- spelling of mod.storage's byte side.  Writing either one out again would
-- give the engine two import tables that drift apart and two blob stores with
-- different sandboxes -- and the sandbox is the part that has to be right.
--
-- ------- what this deliberately does NOT do
--
-- No host paths and no filesystem handles leave this file.  An import can
-- only be addressed by an id the calling mod's own manifest declares, and a
-- cache key can only land inside that mod's namespace: both id and key are
-- validated by the module that owns the namespace, not here.

local ModImports = require("src.mods.ModImports")
local ModStorage = require("src.mods.Storage")

local ImportAccess = {}

ImportAccess.MAX_READ_BYTES = 8 * 1024 * 1024
-- One cache write.  mod.storage has no ceiling of its own -- it is the store
-- a mod puts a decoded 300 MB asset pack in, a key at a time -- but a SINGLE
-- key that large is a mod holding the whole thing in a Lua string, which is
-- the allocation that kills the process rather than the disk.  A mod with
-- more than this splits it, which is what the store is shaped for anyway.
ImportAccess.MAX_CACHE_WRITE_BYTES = 64 * 1024 * 1024

local function parentOf(path)
  return path:match("^(.*)/[^/]+$")
end

local function copyInfo(info)
  if not info then return nil end
  return { type = info.type, size = info.size, modtime = info.modtime }
end

local function safePath(rel)
  if type(rel) ~= "string" or rel == "" then return nil end
  if rel:sub(1, 1) == "/" then return nil end
  if rel:find("\\", 1, true) then return nil end
  if rel:match("^%a:") then return nil end
  local parts = {}
  for segment in rel:gmatch("[^/]+") do
    if segment == ".." then return nil end
    if segment ~= "." then parts[#parts + 1] = segment end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "/")
end

local function makeCache(modId, fs)
  local store = ModStorage.new(modId, fs)
  local cache = { modId = modId }
  local root = "mod_cache/" .. modId
  local function pathFor(rel, what)
    local safe = safePath(rel)
    if not safe then
      error(("%s must stay inside its root, got %q"):format(what, tostring(rel)), 0)
    end
    return root .. "/" .. safe
  end
  local cache = {}

  function cache:write(rel, bytes)
    if type(bytes) ~= "string" then
      return false, "invalid_value", "mod.cache:write takes a byte string"
    end
    if #bytes > ImportAccess.MAX_CACHE_WRITE_BYTES then
      return false, "too_large",
             ("mod.cache:write is capped at %d bytes a key; split generated "
              .. "data across keys"):format(ImportAccess.MAX_CACHE_WRITE_BYTES)
    end
    local path = pathFor(rel, "mod.cache:write")
    local parent = parentOf(path)
    if parent and fs.createDirectory then
      local ok = fs.createDirectory(parent)
      if ok == false then return nil, "could not create cache directory" end
    end
    if not fs.write then return nil, "cache writes are unavailable" end
    return fs.write(path, bytes)
  end

  function cache:read(rel)
    local path = pathFor(rel, "mod.cache:read")
    if not fs.read then return nil, "cache reads are unavailable" end
    return fs.read(path)
  end

  -- size and kind without paying for the payload; see Storage:stat

  function cache:info(rel)
    local path = pathFor(rel, "mod.cache:info")
    if not fs.getInfo then return nil end
    return copyInfo(fs.getInfo(path))
  end

  function cache:exists(rel)
    local info = self:info(rel)
    return info ~= nil and info.type == "file"
  end

  function cache:delete(rel)
    local path = pathFor(rel, "mod.cache:delete")
    if not fs.remove then return nil, "cache deletion is unavailable" end
    return fs.remove(path)
  end
  cache.storage = store
  return cache
end
-- `read` is the mod-folder reader the loader already has (relative path in,
-- bytes out).  It is passed through to ModImports.api unchanged so an
-- injected filesystem in a test reaches the same files the sandbox does.

function ImportAccess.new(manifest, fs, read)
  local cacheFs = fs
  local imports = {}

  function imports:info(id)
    local spec = manifest.requiredImports or {}
    for _, s in ipairs(spec) do
      if s.id == id then
        local path
        if s.root == "save" then
          path = s.file
        else
          path = manifest.path .. "/" .. s.file
        end
        local markerPath = manifest.path .. "/.required-import-" .. id .. ".validated"
        local markerExists = fs.getInfo and fs.getInfo(markerPath)
        local info = fs.getInfo and fs.getInfo(path)
        if info then
          return {
            id = s.id,
            name = s.name,
            file = s.file,
            size = info.size,
            required = s.required ~= false,
            validated = markerExists ~= nil,
          }
        end
      end
    end
    return nil
  end

  function imports:have(id)
    local info = self:info(id)
    return info ~= nil
  end

  function imports:list()
    local spec = manifest.requiredImports or {}
    local out = {}
    for _, s in ipairs(spec) do
      out[#out + 1] = { id = s.id, name = s.name, file = s.file }
    end
    return out
  end

  function imports:read(id, offset, length)
    local spec = manifest.requiredImports or {}
    for _, s in ipairs(spec) do
      if s.id == id then
        local path
        if s.root == "save" then
          path = s.file
        else
          path = manifest.path .. "/" .. s.file
        end
        if fs.read then
          local data = fs.read(path)
          if data then
            offset, length = tonumber(offset) or 0, tonumber(length) or #data
            return data:sub(offset + 1, offset + length)
          end
        end
      end
    end
    return nil
  end

  return imports, makeCache(manifest.id, cacheFs, read)
end

return ImportAccess
