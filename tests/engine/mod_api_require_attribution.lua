package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Json = require("src.link.Json")
local warnings = {}
local oldWarn = Logger.warn
Logger.warn = function(fmt, ...)
  local line = string.format(fmt, ...)
  warnings[#warnings + 1] = line
  return oldWarn(fmt, ...)
end
local files = {}
local function add(id, entry, permissions)
  files["mods/" .. id .. "/manifest.json"] = Json.encode({
    id = id,
    name = id,
    version = "1.0.0",
    api = 2,
    entry = "main.lua",
    permissions = permissions or {},
  })
  files["mods/" .. id .. "/main.lua"] = entry
end
add(
  "a_public",
  [[
  local mod = ...
  mod.exports = {
    generation = mod.generation,
    cache = type(mod.cache),
    storage = type(mod.storage),
    world = type(mod.world),
    content = type(mod.content),
  }
]]
)
add("b_factory_failure", [[error("failed API factory must not execute entry")]])
add(
  "c_internal",
  [[
  local mod = ...
  require("src.core.GameVersion")
  require("src.core.GameVersion")
  local ok = pcall(require, "src.link.PermissionProbeAbsent")
  mod.exports = { missingNetworkModule = not ok }
]]
)
add(
  "d_returned_initializer",
  [[
  return function(mod)
    require("src.battle.TypeChart")
    mod.exports = { initialized = true }
  end
]]
)
add(
  "e_declared",
  [[
  local mod = ...
  require("src.core.GameVersion")
  pcall(require, "src.link.PermissionProbeAbsent")
  mod.exports = { initialized = true }
]],
  { "engine_internals", "network" }
)
add(
  "f_supported",
  [[
  local mod = ...
  require("src.mods.Semver")
  require("src.pokemon.Stats")
  mod.exports = { initialized = true }
]]
)
local fs = T.sdk.memfs(files)
local oldFs = love.filesystem
-- Native loader.fs identity selects the real cache-routing facade. All
-- filesystem reads/writes remain in memory, including Logger's output.
love.filesystem = fs
local loader = Loader.new({ fs = fs, dev = true })
local api0 = loader._api
loader._api = function(self, mod)
  if mod.manifest.id == "b_factory_failure" then
    require("src.core.GameVersion")
    error("intentional engine API factory failure")
  end
  return api0(self, mod)
end
local ok, err = pcall(loader.load, loader, T.fixtures.fresh())
love.filesystem = oldFs
Logger.warn = oldWarn
T.check(ok, "cold real dev loader completes despite one failed factory: " .. tostring(err))
local function ownWarnings(id, permission)
  local out = {}
  for _, line in ipairs(warnings) do
    if line:find("[" .. id .. "] undeclared " .. permission .. " require:", 1, true) then
      out[#out + 1] = line
    end
  end
  return out
end
T.check(loader.exports.a_public, "public entry executes")
if loader.exports.a_public then
  T.eq(loader.exports.a_public.cache, "table", "public cache facade is usable")
  T.eq(loader.exports.a_public.storage, "table", "lazy public storage facade is usable")
  T.eq(loader.exports.a_public.world, "table", "public world facade is usable")
  T.eq(loader.exports.a_public.content, "table", "content facade is usable")
end
T.eq(
  #ownWarnings("a_public", "engine_internals"),
  0,
  "engine-owned public API imports are not attributed to mod"
)
T.eq(
  #ownWarnings("b_factory_failure", "engine_internals"),
  0,
  "engine factory failure emits no false import warning"
)
T.eq(loader.exports.b_factory_failure, nil, "failed factory publishes no exports")
T.check(#loader.errors >= 1, "factory error remains visible")
T.eq(#ownWarnings("c_internal", "engine_internals"), 1, "actual private mod import still warns exactly once")
T.eq(#ownWarnings("c_internal", "network"), 1, "actual missing network import still warns")
T.check(
  loader.exports.c_internal and loader.exports.c_internal.missingNetworkModule,
  "missing module error remains catchable"
)
T.eq(
  #ownWarnings("d_returned_initializer", "engine_internals"),
  1,
  "returned mod initializer retains attribution"
)
T.check(
  loader.exports.d_returned_initializer and loader.exports.d_returned_initializer.initialized,
  "returned initializer executes"
)
T.eq(#ownWarnings("e_declared", "engine_internals"), 0, "declared internal permission remains respected")
T.eq(#ownWarnings("e_declared", "network"), 0, "declared network permission remains respected")
T.eq(#ownWarnings("f_supported", "engine_internals"), 0, "supported imports remain warning-free")
T.eq(Runtime.currentMod, nil, "load restores mod attribution after factory failure")
print("DEV_API_ATTRIBUTION_RESULT " .. Json.encode({
  publicWarnings = #ownWarnings("a_public", "engine_internals"),
  privateWarnings = #ownWarnings("c_internal", "engine_internals"),
  networkWarnings = #ownWarnings("c_internal", "network"),
  initializerWarnings = #ownWarnings("d_returned_initializer", "engine_internals"),
}))
T.finish("native dev API require attribution")
