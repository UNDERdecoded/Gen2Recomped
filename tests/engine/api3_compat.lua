package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Manifest = require("src.mods.Manifest")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local Json = require("src.link.Json")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, love }
love = nil
local function manifest(api, extra)
  local raw = { id = "probe", name = "Probe", version = "1.0.0", entry = "main.lua", api = api }
  for k, v in pairs(extra or {}) do
    raw[k] = v
  end
  return raw
end
for _, api in ipairs({ 1, 2, 3 }) do
  local m = Manifest.validate(manifest(api))
  local format = api == 3 and "unified" or "native"
  for _, field in ipairs({ "content_format", "callback_format", "script_format" }) do
    T.eq(m[field], format, "API " .. api .. " default " .. field)
  end
end
T.eq(Manifest.validate(manifest()).api, 1, "missing API remains legacy")
for _, field in ipairs({ "content_format", "callback_format", "script_format" }) do
  T.raises(function()
    Manifest.validate(manifest(3, { [field] = "native" }))
  end, "API 3 requires unified", "API 3 refuses contradictory " .. field)
  T.eq(
    Manifest.validate(manifest(2, { [field] = "unified" }))[field],
    "unified",
    "API 2 keeps explicit opt-in"
  )
  T.raises(function()
    Manifest.validate(manifest(1, { [field] = "unified" }))
  end, "mod API 2", "API 1 opt-in remains rejected")
end
T.raises(function()
  Manifest.validate(manifest(4))
end, "provides 3", "future API not silently accepted")
T.raises(function()
  Manifest.validate(manifest(3.5))
end, "positive integer", "fractional API rejected")
local function boot(api, extra, second, version)
  Version.set(version or "red")
  local rows = { probe = manifest(api, extra) }
  if second then
    rows.other = manifest(api, extra)
    rows.other.id = "other"
  end
  local files = {}
  for id, raw in pairs(rows) do
    files["mods/" .. id .. "/manifest.json"] = Json.encode(raw)
    files["mods/" .. id .. "/main.lua"] = "local mod = ...; mod.exports.api = mod"
  end
  local fs = {
    read = function(p)
      return files[p]
    end,
    load = function(p)
      return loadstring(files[p], p)
    end,
    getInfo = function(p)
      if files[p] then
        return { type = "file" }
      end
      if p == "mods" or rows[p:match("^mods/(.*)$")] then
        return { type = "directory" }
      end
    end,
    getDirectoryItems = function(p)
      return p == "mods" and (second and { "probe", "other" } or { "probe" }) or {}
    end,
  }
  local loader = Loader.new({ fs = fs, dev = true })
  local game, probes = nil, 0
  loader._game = function(_, loadedOnly)
    probes = probes + 1
    if api == 3 then
      assert(loadedOnly, "API 3 requested Game bootstrap")
    end
    return game
  end
  T.check(loader:load({ pokemon = {}, moves = {}, items = {} }), "real loader accepts API " .. api)
  local mod = assert(loader.apis.probe)
  return mod, loader, function(value)
    game = value
  end, function()
    return probes
  end
end
-- Real legacy loaders keep native defaults, API-2 status vocabulary and callback catalog.
for _, api in ipairs({ 1, 2 }) do
  local m = boot(api)
  T.eq(m.contentFormat, "native", "legacy content native")
  T.eq(m.callbackFormat, "native", "legacy callbacks native")
  T.eq(m.scriptFormat, "native", "legacy scripts native")
end
do
  local m, loader, attach =
    boot(2, { content_format = "unified", callback_format = "unified", script_format = "unified" })
  local mon = {
    species = "MEW",
    nickname = "Scout",
    hp = 10,
    status = "PSN",
    stats = { hp = 20, special = 9 },
    moves = {},
  }
  attach({
    save = { party = { mon } },
    data = { pokemon = {}, moves = {}, items = {} },
    stack = {
      states = {},
    },
  })
  T.eq(m.world:party()[1].status, "poison", "API-2 unified party status unchanged")
  local seen
  m.events:on("pokemon.received", function(p)
    seen = p.mon.status
  end)
  Runtime.emit("pokemon.received", { mon = mon })
  T.eq(seen, "poison", "API-2 unified event status unchanged")
  T.check(pcall(function()
    m.events:on("checkpoint.restored", function() end)
  end), "API-2 accepts the additive native checkpoint notification")
  T.check(pcall(function()
    m.events:on("intro.boot.copyright", function() end)
  end), "API-2 accepts the additive native boot notification")
end
-- Availability must be honest, and a probe cannot construct Game or attach a world.
do
  local m, loader, attach, probes = boot(3, nil, true)
  T.eq(probes(), 0, "entry does not resolve Game")
  local world, battle = m.world, m.battle
  T.eq(type(world), "table", "world facade exists before Game")
  T.eq(type(world.party), "function", "early world method callable")
  T.eq(type(battle.snapshot), "function", "early battle method callable")
  for _, name in ipairs({
    "spawnNpc",
    "removeNpc",
    "npc",
    "warpTo",
    "toggleObject",
    "replaceBlock",
    "party",
    "current",
    "activeBlockAt",
    "liveMaps",
    "queueScript",
    "getFlag",
    "setFlag",
  }) do
    T.eq(m:supports("world", name), true, "implemented world method " .. name)
  end
  for _, name in ipairs({
    "startWildBattle",
    "invalidateMap",
  }) do
    local available, why = m:supports("world", name)
    T.eq(available, false, "no unverified native promise for " .. name)
    T.check(type(why) == "string", "unavailable reason for " .. name)
    local ok, reason = world[name](world, "bad")
    T.eq(ok, nil, "unsupported method does not dispatch " .. name)
    T.check(reason:find("unsupported:", 1, true), "explicit refusal for " .. name)
  end
  T.eq(probes(), 0, "capability and unsupported calls do not resolve Game")
  T.eq(world:party(), nil, "no-game party refuses safely")
  T.eq(battle:snapshot(), nil, "no-game battle refuses safely")
  T.eq(m.datasets:open("gold"), nil, "unavailable dataset API callable")
  T.eq(m:supports("hooks", "render.output"), false, "recognized output hook is not falsely available")
  T.check(
    pcall(function()
      m.hooks:wrap("render.output", function(next, ctx)
        return next(ctx)
      end)
    end),
    "known absent hook can be registered"
  )
  T.check(
    pcall(function()
      m.events:on("checkpoint.restored", function() end)
    end),
    "known absent event can be registered"
  )
  T.raises(function()
    m.events:on("not.catalogued", function() end)
  end, "unknown unified callback", "unknown API-3 name rejected")
  local save = { party = {}, flags = {}, modData = {} }
  attach({ save = save, data = {}, stack = { states = {} } })
  local flags = {}
  m.events:on("flag.changed", function(p)
    flags[#flags + 1] = { p.name, p.value }
  end)
  T.eq(world:getFlag("mod:quest.finished"), false, "flag read defaults false")
  T.eq(next(save.modData), nil, "flag read allocates no bucket")
  T.check(world:setFlag("mod:quest.finished", true), "private flag set")
  T.check(world:setFlag("mod:quest.finished", true), "setting same flag accepted")
  T.eq(#flags, 1, "unchanged flag emits no duplicate event")
  T.eq(loader.apis.other.world:getFlag("mod:quest.finished"), false, "other mod cannot see flag")
  T.check(world:setFlag("mod:quest.finished", false), "private flag cleared")
  T.eq(save.modData.probe.worldFlags["quest.finished"], nil, "clear removes saved boolean")
  T.same(
    flags,
    { { "mod.probe.quest.finished", true }, { "mod.probe.quest.finished", false } },
    "portable flag notifications"
  )
  T.eq(next(save.flags), nil, "private flags never touch native flags")
  T.eq(world:setFlag("mod:bad", "yes"), nil, "non-boolean flag rejected")
  T.eq(world:setFlag("NATIVE_FLAG", true), nil, "unverified native flag mapping refused")
  T.eq(world:setFlag("mod:", true), nil, "empty private flag rejected")
  save.modData.probe.worldFlags = false
  T.eq(world:setFlag("mod:test", true), nil, "malformed store rejected")
  T.eq(save.modData.probe.worldFlags, false, "malformed store never overwritten")
  attach({ save = { party = {} }, data = {}, stack = { states = {} } })
  T.eq(world:getFlag("mod:quest.finished"), false, "same handle follows replacement save")
  T.eq(m.world, world, "world handle identity stable")
  T.eq(m.battle, battle, "battle handle identity stable")
end
for _, version in ipairs({ "platinum", "black" }) do
  local m = boot(3, nil, false, version)
  T.eq(m:supports("world", "party"), false, "no shared Gen1 contract claimed for " .. version)
  for _, name in ipairs({ "spawnNpc", "removeNpc", "npc" }) do
    T.eq(m:supports("world", name), false, "no shared NPC API promised for " .. version)
  end
  T.eq(m:supports("world", "warpTo"), false, "no shared warp promised for " .. version)
  T.eq(m:supports("world", "toggleObject"), false, "no shared object edits promised for " .. version)
  T.eq(m:supports("world", "replaceBlock"), false, "no shared block edits promised for " .. version)
  local value, why = m.world:party()
  T.eq(value, nil, "unsupported generation call refuses")
  T.check(why:find("unsupported:", 1, true), "unsupported generation is explicit")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, love = saved[2], saved[3], saved[4], saved[5]
T.finish("API 3 entry compatibility")
