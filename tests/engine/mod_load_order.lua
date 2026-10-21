-- ROM-free end-to-end ordering: saved options -> dependency resolver ->
-- entry chunks, registry winners and asset override precedence.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Order = require("src.mods.LoadOrder")
local Loader = require("src.mods.Loader")
local SaveData = require("src.core.SaveData")
local Json = require("src.link.Json")
local Manifest = require("src.mods.Manifest")

local function fsFor(files)
  return {
    read = function(p) return files[p] end,
    write = function(p, s) files[p] = s; return true end,
    remove = function(p) files[p] = nil; return true end,
    rename = function(a, b) files[b], files[a] = files[a], nil; return true end,
    createDirectory = function() return true end,
    getInfo = function(p)
      if files[p] then return { type = "file", size = #files[p] } end
      for key in pairs(files) do
        if key:sub(1, #p + 1) == p .. "/" then return { type = "directory" } end
      end
    end,
    getDirectoryItems = function(p)
      local out, seen = {}, {}
      for key in pairs(files) do
        if key:sub(1, #p + 1) == p .. "/" then
          local child = key:sub(#p + 2):match("^[^/]+")
          if child and not seen[child] then out[#out + 1], seen[child] = child, true end
        end
      end
      table.sort(out)
      return out
    end,
    load = function(p) return loadstring(files[p] or "", "@" .. p) end,
  }
end

local entries = { { id = "a", priority = 10 }, { id = "b", priority = -10 },
  { id = "c", priority = 10 } }
T.same(Order.materialize(nil, entries), { "b", "a", "c" }, "default is priority then id")
T.same(Order.normalize(false), {}, "invalid options use defaults")
T.same(Order.normalize({ "c", false, "c", 42, "", "b" }), { "c", "b" },
  "duplicates and non-ids are ignored")
local saved = { "c", "absent", "a" }
T.same(Order.materialize(saved, entries), { "c", "absent", "a", "b" },
  "new mods append deterministically; absent ids survive")
local moved, changed = Order.move(saved, entries, { entries[1], entries[3] }, "a", -1)
T.check(changed, "filtered move succeeds")
T.same(moved, { "a", "absent", "c", "b" }, "filtered move leaves hidden slots alone")
T.same(saved, { "c", "absent", "a" }, "a move never mutates its input")
local _, boundary = Order.move(nil, entries, nil, "b", -1)
T.eq(boundary, false, "first mod cannot move earlier")
local _, missing = Order.move(nil, entries, nil, "ghost", 1)
T.eq(missing, false, "unknown id cannot move")
T.check(Order.same(nil, { "b", "a", "c" }, entries), "equivalent default orders compare equal")

local function boot(order, specs, disabled)
  local files = { ["options.lua"] = SaveData.encode({ modOrder = order, mods = disabled }) }
  for _, spec in ipairs(specs) do
    local raw = { id = spec.id, name = spec.id, version = "1.0.0", entry = "main.lua",
      priority = spec.priority, dependencies = spec.dependencies,
      optional_dependencies = spec.optional_dependencies }
    files["mods/" .. spec.id .. "/manifest.json"] = Json.encode(raw)
    files["mods/" .. spec.id .. "/main.lua"] = spec.fail and 'error("fixture failure")'
      or ('local mod = ...; mod.content.text:override("ORDER_TEXT", %q)'):format(spec.id)
    files["mods/" .. spec.id .. "/overrides/sprites/order.png"] = "fixture"
  end
  local fs = fsFor(files)
  local loader, data = Loader.new({ fs = fs, dev = false }), { text = { ORDER_TEXT = "BASE" } }
  loader:load(data)
  return loader, data, fs, files
end

local specs = { { id = "a", priority = 10 }, { id = "b", priority = -10 },
  { id = "c", priority = 10 } }
local loader, data = boot(nil, specs)
T.same(loader.order, { "b", "a", "c" }, "legacy options preserve entry-chunk order")
T.eq(data.text.ORDER_TEXT, "c", "legacy registry winner is unchanged")
loader, data = boot({ "c", "a", "b" }, specs)
T.same(loader.order, { "c", "a", "b" }, "saved order overrides manifest priority among eligible mods")
T.eq(data.text.ORDER_TEXT, "b", "later-loaded content wins")
T.eq(require("src.render.Assets").loader:overrideOrder()[1].id, "b", "later-loaded asset override wins too")
T.same(loader.requestedOrder, { "c", "a", "b" }, "boot preference snapshot is retained")
T.eq(loader.mods.a.manifest.priority, 10, "ordering never rewrites a manifest")

local chain = { { id = "addon", dependencies = { "base" } },
  { id = "base", dependencies = { "core" } }, { id = "core" } }
loader = boot({ "addon", "base", "core" }, chain)
T.same(loader.order, { "core", "base", "addon" }, "transitive dependencies override requested order")
loader = boot({ "addon", "base", "core" }, chain, { base = false })
T.same(loader.order, { "core" }, "saved order cannot bypass a disabled dependency")
T.eq(loader.mods.addon.state, "blocked_dependency", "blocked dependency remains visible")
loader = boot({ "addon", "base" }, {
  { id = "addon", optional_dependencies = { "base" } }, { id = "base" } })
T.same(loader.order, { "base", "addon" }, "present optional dependency still loads first")
loader = boot({ "addon", "missing" }, {
  { id = "addon", optional_dependencies = { "missing" } } })
T.same(loader.order, { "addon" }, "absent optional dependency is harmless")
loader = boot({ "b", "a", "c" }, {
  { id = "a", dependencies = { "b" } }, { id = "b", dependencies = { "a" } }, { id = "c" } })
T.same(loader.order, { "c" }, "saved order never bypasses hard dependency cycles")
loader = boot({ "addon", "base", "safe" }, {
  { id = "addon", dependencies = { "base" } }, { id = "base", fail = true }, { id = "safe" } })
T.same(loader.order, { "safe" }, "entry failure blocks dependents while unrelated mods survive")
loader = boot({ "b", "a" }, {
  { id = "a", optional_dependencies = { "b" } },
  { id = "b", optional_dependencies = { "a" } } })
T.same(loader.order, { "a", "b" }, "optional cycles retain the original deterministic fallback")

local fs = fsFor({})
local opts = SaveData.defaultOptions()
opts.modOrder, opts.mods, opts.speed = { "c", "absent", "a" }, { a = false }, 2
T.check(SaveData.saveOptions(opts, fs) ~= nil, "options save succeeds")
local reloaded = SaveData.loadOptions(fs)
T.same(reloaded.modOrder, opts.modOrder, "order survives options serialization")
T.eq(reloaded.mods.a, false, "order storage preserves enable state")
T.eq(reloaded.speed, 2, "order storage preserves unrelated settings")
local GenOptions = require("src.core.GenOptions")
T.eq(GenOptions.canOverride("modOrder"), false, "load order is installation-wide")

local LM = require("src.mods.LauncherMods")
local manifests = {}
for _, m in ipairs(specs) do
  manifests[#manifests + 1] = Manifest.validate({ id = m.id, name = m.id,
    version = "1.0.0", entry = "main.lua", priority = m.priority })
end
local rows = LM.deriveList(manifests, { modOrder = { "c", "a", "b" } })
local Sidebar = require("src.import.LauncherSidebar")
rows = Sidebar.filterMods(rows, nil, nil, "order")
T.eq(rows[1].id, "c", "launcher displays requested load order")
T.eq(rows[3].id, "b", "launcher displays requested last mod")
rows[2].description = "unique-search-marker"
T.eq(Sidebar.filterMods(rows, "unique-search-marker", nil, "order")[1].id, "a", "search still works in order view")
T.eq(Sidebar.filterMods(rows, nil, nil, "name")[1].id, "a", "alphabetic browsing is unchanged")

-- The launcher's actual discovery and atomic options writer, over the same
-- injected filesystem as the loader. Only physical mounting is bypassed.
local _, _, liveFs = boot({ "c", "absent", "a", "b" }, specs, { b = false })
_G.love = require("tests.love_stub")
love.filesystem = liveFs
local CacheFs = require("src.import.CacheFs")
local oldRoot, oldConfine, oldPortable = CacheFs.root, LM.confinedRoot, SaveData.portableFs
CacheFs.root, LM.confinedRoot, SaveData.portableFs = function() end, function() end, function() end
T.check(LM.moveInOrder("a", -1, { { id = "a" }, { id = "c" } }), "launcher move saves successfully")
local persisted = SaveData.loadOptions()
T.same(persisted.modOrder, { "a", "absent", "c", "b" }, "launcher retains filtered and absent positions on disk")
T.eq(persisted.mods.b, false, "launcher move preserves disabled mods")
local before = liveFs.read("options.lua")
T.eq(LM.moveInOrder("ghost", 1), false, "launcher rejects absent target")
T.eq(liveFs.read("options.lua"), before, "rejected move does not rewrite options")
T.check(LM.resetOrder(), "launcher reset saves successfully")
T.same(SaveData.loadOptions().modOrder, {}, "reset clears the preference on disk")
local oldWrite = liveFs.write
liveFs.write = function() return false, "read only" end
local ok, err = LM.moveInOrder("a", 1)
T.eq(ok, false, "failed persistence is reported")
T.check(type(err) == "string", "failed persistence gives a reason")
liveFs.write = oldWrite
T.same(SaveData.loadOptions().modOrder, {}, "failed save leaves previous preference intact")
CacheFs.root, LM.confinedRoot, SaveData.portableFs = oldRoot, oldConfine, oldPortable

Loader.teardown()
T.finish("mod load order")
