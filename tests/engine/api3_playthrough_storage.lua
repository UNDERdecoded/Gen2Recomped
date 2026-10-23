package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Fixture = dofile("tests/playthrough_storage/fixture.lua")
local Cases = dofile("tests/playthrough_storage/cases.lua")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  local f = Fixture.new(".", "gen2", version)
  Cases.run(f, version)
  dofile("tests/playthrough_storage/lifecycle.lua").run(f, version)
  f.close()
end
-- Drive the actual native save/slot lifecycle, not synthetic storage handles.
for _, version in ipairs({ "red", "gold", "firered", "platinum" }) do
  local f = Fixture.new(".", "gen2", version)
  local S, e, fs, files = f.Save, f.e, f.fs, f.files
  local function new()
    return { save = S.newGame({ version = version }) }
  end
  local vanilla = new()
  T.eq(vanilla.save.meta.playthroughId, nil, "no-mod New Game has no storage identity")
  T.check(S.save(vanilla.save), "vanilla progress saves")
  local loaded = assert(S.load(version))
  T.eq(loaded.meta.playthroughId, nil, "unused vanilla load remains identity-free")
  local progress = {}
  for path, bytes in pairs(files) do
    if path:match("^save[^/]*%.lua$") then
      progress[path] = bytes
    end
  end
  local first = { save = loaded }
  local id = assert(e.context(first)).playthroughId
  T.check(type(id) == "string" and id ~= "", "legacy storage receives opaque identity")
  for path, bytes in pairs(progress) do
    T.eq(files[path], bytes, "legacy allocation never rewrites progress")
  end
  T.check(e.write(first, "progress/value", { n = 12 }), "legacy mod state writes")
  T.check(S.saveOptions(S.defaultOptions(), fs), "stale options snapshot writes")
  local persisted = S.loadOptions(fs).playthroughIds
  T.eq(
    persisted and persisted[version] and persisted[version].legacy,
    id,
    "stale option writers cannot erase a requested storage identity"
  )
  S.resetSlotState()
  local resumed = { save = assert(S.load(version)) }
  T.eq(e.context(resumed).playthroughId, id, "legacy promotion/restart retains identity")
  T.eq(e.read(resumed, "progress/value").n, 12, "legacy state survives slot migration")
  T.check(S.save(resumed.save, {}), "identified progress saves")
  S.resetSlotState()
  resumed.save = assert(S.load(version))
  T.eq(resumed.save.meta.playthroughId, id, "normal save stamps and reloads identity")
  local boot = new()
  local ghost = e.context(boot).playthroughId
  T.check(ghost ~= id, "boot/new-game skeleton has separate identity")
  boot.stack = { states = { { screenId = "TitleState" } } }
  local title = assert(e.selected(boot))
  T.eq(title:context().playthroughId, id, "init-time storage cannot replace title's real save")
  T.eq(title:read("progress/value").n, 12, "title reads selected durable mod state")
  T.eq(type(title:context().normalSavedAt), "number", "title includes normal save chronology")
  fs.fail = ".tmp"
  T.eq(S.save(boot.save, {}), false, "failed normal save remains a failed save")
  fs.fail = nil
  T.eq(e.selected(boot):context().playthroughId, id, "failed normal save cannot replace title identity")
  T.check(S.save(boot.save, {}), "new playthrough commits")
  local nextBoot = new()
  nextBoot.stack = boot.stack
  T.eq(e.selected(nextBoot):context().playthroughId, ghost, "committed new game becomes title selection")
  local sourceId = boot.save.meta.playthroughId
  local sourceSlot = S.activeSlot(version)
  local copySlot = assert(S.createSlot(version))
  T.check(S.writeSlot(version, copySlot, boot.save), "identified save imports to another slot")
  T.eq(boot.save.meta.playthroughId, sourceId, "import never mutates source identity")
  S.setActiveSlot(version, copySlot)
  local imported = { save = assert(S.load(version)) }
  T.check(e.context(imported).playthroughId ~= sourceId, "duplicate slot receives distinct storage scope")
  T.eq(
    S.buildMeta({}, imported.save.meta).playthroughId,
    imported.save.meta.playthroughId,
    "mod-set stamp retains identity"
  )
  local external = S.loadOptions(fs)
  external.saveSlots[version].active = sourceSlot
  S.saveOptions(external, fs)
  local localTitle = new()
  localTitle.stack = boot.stack
  T.eq(
    e.selected(localTitle):context().playthroughId,
    imported.save.meta.playthroughId,
    "another launcher's selection cannot reroute this process's native slot"
  )
  S.setActiveSlot(version, copySlot)
  T.check(S.deleteSlot(version, copySlot), "identified slot deletes")
  local opts = S.loadOptions(fs)
  T.eq(opts.playthroughIds[version][copySlot], nil, "deleted slot loses routing binding")
  S.setActiveSlot(version, sourceSlot)
  S.resetSlotState()
  T.eq(S.load(version).meta.playthroughId, sourceId, "original slot remains unchanged")
  f.close()
end
-- Identity allocation must not change the next gameplay RNG result.
do
  local f = Fixture.new(".", "gen2", "red")
  local game = { save = f.Save.newGame({ version = "red" }) }
  math.randomseed(318)
  local expected = math.random()
  math.randomseed(318)
  f.e.context(game)
  T.eq(math.random(), expected, "storage identity never consumes gameplay RNG")
  f.close()
end
-- Reject an unavailable persistence backend before attempting identity I/O.
do
  local f = Fixture.new(".", "gen2", "red")
  local write = f.fs.write
  f.fs.write = nil
  local _, code = f.e.context({ save = { version = "red" } })
  T.eq(code, "storage_unavailable", "read-only backend cannot allocate a scope")
  f.fs.write = write
  f.fs.fail = ".tmp"
  local game = { save = f.Save.newGame({ version = "red" }) }
  local context = f.e.context(game)
  T.eq(context, nil, "failed identity write cannot claim durable scope")
  T.eq(game.save.meta.playthroughId, nil, "failed allocation leaves no committed identity")
  f.close()
end
-- API 1/2 retain the original installation-wide cache semantics and bytes.
for _, api in ipairs({ 1, 2 }) do
  local f = Fixture.new(".", "gen2", "red")
  local Store = require("src.mods.Storage")
  local legacy = Store.new("portable_storage", f.fs)
  T.check(legacy:write({}, "old/value", { n = api }), "legacy cache writes")
  T.eq(legacy:read({}, "old/value").n, api, "legacy cache survives")
  local Json = require("src.link.Json")
  local path = "mods/portable_storage/manifest.json"
  local manifest = Json.decode(f.files[path])
  manifest.api = api
  f.files[path] = Json.encode(manifest)
  local loaded = T.sdk.loadMods(
    { "mods/portable_storage" },
    { fs = f.fs, generation = 1, data = T.fixtures.fresh(), dev = false }
  )
  T.eq(#loaded.errors, 0, "legacy SDK consumer loads")
  T.eq(
    loaded.loader.exports.portable_storage.read({}, "old/value").n,
    api,
    "legacy SDK uses unchanged cache namespace"
  )
  local _, code = f.e.read(f.game("new_scope"), "old/value")
  T.eq(code, "not_found", "portable storage does not guess legacy cache ownership")
  T.eq(legacy:read({}, "old/value").n, api, "portable reads retain legacy cache bytes")
  loaded.release()
  f.close()
end
Version.set(old)
T.finish("API-3 portable storage and native playthrough lifecycle")
