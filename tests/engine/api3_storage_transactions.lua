-- Public mod.storage contract: data-only transactions, namespace isolation,
-- deterministic listing, recovery, and failure retention.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("mod storage")
local Loader = require("src.mods.Loader")
local Runtime = require("src.mods.Runtime")
local Storage = require("src.mods.PlaythroughStorage")
local Version = require("src.core.Version")

local savedEvents, savedHooks = Runtime.events, Runtime.hooks

local function manifest(id)
  return ('{"id":"%s","name":"%s","version":"1.0.0",'):format(id, id)
    .. '"entry":"main.lua","api":3,"profile":"content"}'
end

local function memfs(files)
  local fs = { files = files, failTmp = false, failMain = false }

  function fs.read(path)
    return files[path]
  end
  function fs.write(path, body)
    if fs.failTmp and path:sub(-4) == ".tmp" then
      return false, "tmp denied"
    end
    if fs.failMain and (path:sub(-4) == ".lua" or path:sub(-4) == ".bin") then
      return false, "main denied"
    end
    files[path] = body
    return true
  end
  function fs.remove(path)
    files[path] = nil
    return true
  end
  function fs.createDirectory()
    return true
  end
  function fs.getInfo(path)
    if files[path] then
      return { type = "file" }
    end
    local prefix = path .. "/"
    for key in pairs(files) do
      if key:sub(1, #prefix) == prefix then
        return { type = "directory" }
      end
    end
    return nil
  end
  function fs.load(path)
    if not files[path] then
      return nil, "no file: " .. path
    end
    return load(files[path], path)
  end
  function fs.getDirectoryItems(path)
    local prefix, seen, out = path .. "/", {}, {}
    for key in pairs(files) do
      if key:sub(1, #prefix) == prefix then
        local child = key:sub(#prefix + 1):match("^[^/]+")
        if child and not seen[child] then
          seen[child] = true
          out[#out + 1] = child
        end
      end
    end
    table.sort(out)
    return out
  end
  return fs
end

local function game(version, playthroughId)
  return {
    save = {
      version = version,
      meta = { format = 4, mods = {}, playthroughId = playthroughId },
    },
  }
end

local files = {
  ["mods/alpha/manifest.json"] = manifest("alpha"),
  -- mod.exports, not _G: a mod's globals are its own (src/mods/Sandbox.lua)
  ["mods/alpha/main.lua"] = [[
return function(mod) mod.exports.storage = mod.storage end
]],
  ["mods/beta/manifest.json"] = manifest("beta"),
  ["mods/beta/main.lua"] = [[
return function(mod) mod.exports.storage = mod.storage end
]],
}
local fs = memfs(files)
local loader = Loader.new({ fs = fs })
local current = game("red", "play-a")
loader.game = current
T.check(loader:load({}) == true, "storage fixture mods load")

local alpha = (loader.exports.alpha or {}).storage
local beta = (loader.exports.beta or {}).storage
T.check(
  type(alpha) == "table" and type(beta) == "table",
  "Loader exposes mod.storage through the public mod object"
)
if type(alpha) ~= "table" or type(beta) ~= "table" then
  Runtime.events, Runtime.hooks = savedEvents, savedHooks
  T.finish()
end

-- Removing scope identity or exposing a mutable private slot id breaks this.
local context = alpha:context(current)
T.same(context, {
  engineVersion = Version.engine,
  gameVersion = "red",
  playthroughId = "play-a",
}, "context exposes stable engine/game/playthrough compatibility identity")

-- Data-only write/read. The literal expected table is independent of storage.
local payload = { format = 1, nested = { money = 1234 }, flags = { a = true } }
local ok, code, message = alpha:write(current, "states/quick/q1", payload)
T.check(ok == true, "data-only payload writes: " .. tostring(code or message))
local loaded = alpha:read(current, "states/quick/q1")
T.same(loaded, payload, "stored payload roundtrips as data")
T.check(
  loaded ~= payload and loaded.nested ~= payload.nested,
  "read returns decoded data rather than the caller's live table"
)

T.check(
  type(alpha.writeBytes) == "function" and type(alpha.readBytes) == "function",
  "mod.storage exposes opaque byte read/write methods"
)
if type(alpha.writeBytes) == "function" and type(alpha.readBytes) == "function" then
  local binary = "MESH\0\1\255\128\nreturn _G.MOD_STORAGE_EXECUTED = true"
  local binaryOk, binaryCode, binaryMessage = alpha:writeBytes(current, "states/quick/blob", binary)
  T.check(binaryOk == true, "opaque bytes write exactly: " .. tostring(binaryCode or binaryMessage))
  local binaryLoaded, binaryReadCode = alpha:readBytes(current, "states/quick/blob")
  T.eq(binaryLoaded, binary, "opaque bytes round-trip without text or Lua decoding")
  T.eq(binaryReadCode, nil, "successful opaque byte read has no error")
  T.eq(_G.MOD_STORAGE_EXECUTED, nil, "Lua-looking opaque bytes are never executed")

  local emptyOk = alpha:writeBytes(current, "binary/empty", "")
  T.check(emptyOk == true, "empty opaque byte payloads are valid")
  T.eq(alpha:readBytes(current, "binary/empty"), "", "empty opaque byte payloads round-trip")

  local badBytes, badBytesCode = alpha:writeBytes(current, "binary/bad-type", { byte = true })
  T.check(not badBytes and badBytesCode == "invalid_bytes", "non-string opaque payloads are rejected")

  local savedLimit = Storage.MAX_BYTES
  Storage.MAX_BYTES = 4
  local tooLarge, tooLargeCode = alpha:writeBytes(current, "binary/too-large", "12345")
  Storage.MAX_BYTES = savedLimit
  T.check(
    not tooLarge and tooLargeCode == "size_limit",
    "opaque payloads over the per-key limit are rejected"
  )

  local tableConflict, tableConflictCode = alpha:writeBytes(current, "states/quick/q1", "table-key-conflict")
  T.check(
    not tableConflict and tableConflictCode == "type_conflict",
    "bytes cannot replace a table record without deletion"
  )
  local wrongType, wrongTypeCode = alpha:read(current, "states/quick/blob")
  T.check(
    wrongType == nil and wrongTypeCode == "type_mismatch",
    "table reads identify byte records as the wrong storage type"
  )
end

local bad, badCode = alpha:write(current, "states/bad", { callback = function() end })
T.check(not bad and badCode == "encode_failed", "functions are rejected with a stable data-only error")

local escaped, escapedCode = alpha:write(current, "../escape", {})
T.check(not escaped and escapedCode == "invalid_key", "path traversal is rejected before persistence")

-- Logical enumeration is deterministic and prefix-scoped.
T.check(alpha:write(current, "states/quick/zeta", { n = 2 }), "write zeta")
T.check(alpha:write(current, "states/quick/alpha", { n = 1 }), "write alpha")
T.check(alpha:write(current, "settings", { enabled = true }), "write settings")
local keys = alpha:list(current, "states/quick")
T.same(
  keys,
  { "states/quick/alpha", "states/quick/blob", "states/quick/q1", "states/quick/zeta" },
  "list returns sorted logical keys under the requested prefix"
)

-- Mod, playthrough, and game namespaces cannot observe each other.
local missing, missingCode = beta:read(current, "states/quick/q1")
T.check(missing == nil and missingCode == "not_found", "another mod cannot read the first mod's payload")
if type(alpha.readBytes) == "function" then
  missing, missingCode = beta:readBytes(current, "states/quick/blob")
  T.check(
    missing == nil and missingCode == "not_found",
    "another mod cannot read the first mod's opaque payload"
  )
end
missing, missingCode = alpha:read(game("red", "play-b"), "states/quick/q1")
T.check(missing == nil and missingCode == "not_found", "another playthrough cannot read the payload")
missing, missingCode = alpha:read(game("blue", "play-a"), "states/quick/q1")
T.check(missing == nil and missingCode == "not_found", "another game version cannot read the payload")
if type(alpha.readBytes) == "function" then
  missing, missingCode = alpha:readBytes(game("red", "play-b"), "states/quick/blob")
  T.check(missing == nil and missingCode == "not_found", "another playthrough cannot read the opaque payload")
  missing, missingCode = alpha:readBytes(game("blue", "play-a"), "states/quick/blob")
  T.check(
    missing == nil and missingCode == "not_found",
    "another game version cannot read the opaque payload"
  )
end

-- Find the implementation-owned file only to inject corruption; assertions stay
-- on public read behavior, not the path shape.
local function mainFor(fragment)
  for path in pairs(files) do
    if path:find(fragment, 1, true) and path:sub(-4) == ".lua" then
      return path
    end
  end
end

local function byteMainFor(fragment)
  for path in pairs(files) do
    if path:find(fragment, 1, true) and path:sub(-4) == ".bin" then
      return path
    end
  end
end

local q1Main = mainFor("q1")
T.check(type(q1Main) == "string", "failure fixture locates the persisted q1")
files[q1Main] = "not a serialized table"
loaded, code = alpha:read(current, "states/quick/q1")
T.same(loaded, payload, "corrupt main recovers the last verified payload")
T.eq(code, nil, "successful recovery is a normal read")

-- A failed replacement cannot destroy the prior verified value.
T.check(alpha:write(current, "replace", { version = 1 }), "seed replace value")
fs.failTmp = true
ok, code = alpha:write(current, "replace", { version = 2 })
fs.failTmp = false
T.check(not ok and code == "write_failed", "staging failure is reported")
T.same(alpha:read(current, "replace"), { version = 1 }, "staging failure leaves the prior value readable")

if type(alpha.writeBytes) == "function" and type(alpha.readBytes) == "function" then
  T.check(alpha:writeBytes(current, "binary/recover", "old-bytes"), "seed opaque recovery value")
  local recoverMain = byteMainFor("binary/recover")
  T.check(type(recoverMain) == "string", "failure fixture locates opaque recovery data")
  files[recoverMain] = nil
  T.eq(
    alpha:readBytes(current, "binary/recover"),
    "old-bytes",
    "missing opaque main recovers the last verified backup"
  )

  T.check(alpha:writeBytes(current, "binary/replace", "version-1"), "seed opaque replacement value")
  fs.failTmp = true
  ok, code = alpha:writeBytes(current, "binary/replace", "version-2")
  fs.failTmp = false
  T.check(not ok and code == "write_failed", "opaque staging failure is reported")
  T.eq(
    alpha:readBytes(current, "binary/replace"),
    "version-1",
    "opaque staging failure leaves the prior value readable"
  )

  fs.failMain = true
  ok, code = alpha:writeBytes(current, "binary/replace", "version-3")
  fs.failMain = false
  T.check(not ok and code == "write_failed", "opaque replacement failure is reported")
  T.eq(
    alpha:readBytes(current, "binary/replace"),
    "version-1",
    "opaque replacement failure leaves the prior value readable"
  )

  local byteConflict, byteConflictCode = alpha:write(current, "binary/replace", { version = 3 })
  T.check(
    not byteConflict and byteConflictCode == "type_conflict",
    "tables cannot replace a byte record without deletion"
  )

  T.check(alpha:writeBytes(current, "binary/delete", "delete-me"), "seed opaque delete target")
  T.check(alpha:delete(current, "binary/delete") == true, "delete removes an opaque record")
  missing, missingCode = alpha:readBytes(current, "binary/delete")
  T.check(missing == nil and missingCode == "not_found", "deleted opaque key is unavailable")
end

-- Delete is exact and idempotent-not-found is explicit.
T.check(alpha:write(current, "delete/me", { yes = true }), "seed delete target")
T.check(alpha:write(current, "delete/keep", { yes = true }), "seed delete neighbor")
T.check(alpha:delete(current, "delete/me") == true, "delete removes its target")
missing, missingCode = alpha:read(current, "delete/me")
T.check(missing == nil and missingCode == "not_found", "deleted key is unavailable")
T.same(alpha:read(current, "delete/keep"), { yes = true }, "delete leaves neighboring keys untouched")

-- No-mod parity: constructing/loading an empty loader creates no storage bytes.
local emptyFiles, emptyFs = {}, nil
emptyFs = memfs(emptyFiles)
local emptyLoader = Loader.new({ fs = emptyFs })
emptyLoader.game = current
T.check(emptyLoader:load({}) == true, "no-mod loader still boots")
T.eq(next(emptyFiles), nil, "no-mod boot creates no storage paths or files")

Runtime.events, Runtime.hooks = savedEvents, savedHooks
Runtime.currentMod = nil

T.finish()
