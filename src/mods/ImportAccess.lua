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
ImportAccess.MAX_READ_BYTES = ModImports.MAX_READ_BYTES

-- One cache write.  mod.storage has no ceiling of its own -- it is the store
-- a mod puts a decoded 300 MB asset pack in, a key at a time -- but a SINGLE
-- key that large is a mod holding the whole thing in a Lua string, which is
-- the allocation that kills the process rather than the disk.  A mod with
-- more than this splits it, which is what the store is shaped for anyway.
ImportAccess.MAX_CACHE_WRITE_BYTES = 64 * 1024 * 1024

-- mod.cache: installation-scoped generated data, in the Gen 1 port's spelling.
--
-- Same store as mod.storage (modstorage/<mod-id>/), same sandbox, same key
-- rules -- what differs is the signature.  mod.storage takes the live game as
-- its first argument so a later revision can scope by it; the Gen 1 API never
-- had one, and a ported mod calling cache:read("key") must not silently pass
-- "key" as the game.  So the game argument is dropped here and nowhere else.
--
-- Errors come back as `nil/false, code, message` -- the store's own shape, not
-- narrowed, so `local blob, err = mod.cache:read(k)` puts the machine-readable
-- code in `err` and "not_found" is a normal answer rather than a failure.
local function makeCache(modId, fs)
  local store = ModStorage.new(modId, fs)
  local cache = { modId = modId }

  function cache:write(key, bytes)
    if type(bytes) ~= "string" then
      return false, "invalid_value", "mod.cache:write takes a byte string"
    end
    if #bytes > ImportAccess.MAX_CACHE_WRITE_BYTES then
      return false, "too_large",
             ("mod.cache:write is capped at %d bytes a key; split generated "
              .. "data across keys"):format(ImportAccess.MAX_CACHE_WRITE_BYTES)
    end
    return store:writeBytes(nil, key, bytes)
  end

  function cache:read(key) return store:readBytes(nil, key) end
  function cache:delete(key) return store:delete(nil, key) end
  function cache:list(prefix) return store:list(nil, prefix) end

  -- size and kind without paying for the payload; see Storage:stat
  function cache:info(key) return store:stat(nil, key) end

  function cache:exists(key)
    return store:stat(nil, key) ~= nil
  end

  -- the store underneath, for a mod that wants the game-scoped signatures or
  -- context(); handed over rather than hidden, because it is the same sandbox
  cache.storage = store
  return cache
end

-- `read` is the mod-folder reader the loader already has (relative path in,
-- bytes out).  It is passed through to ModImports.api unchanged so an
-- injected filesystem in a test reaches the same files the sandbox does.
function ImportAccess.new(manifest, fs, read)
  assert(type(manifest) == "table", "import access needs a manifest")
  return ModImports.api(manifest, read, fs), makeCache(manifest.id, fs)
end

return ImportAccess
