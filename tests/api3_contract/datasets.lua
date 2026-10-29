-- Native cache formats differ; the mod and assertions are identical.
local M = {}
function M.fixture(root, backend, version)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/datasets%.lua$")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local gen = Version.generation(version)
  local data = dofile(codeRoot .. "/run.lua").dataFor(backend, gen)
  local writer = require("src.import.LuaWriter")
  local prefix = Version.cachePrefix(version)
  local files = {}
  if backend == "gen1" then
    local Contract = require("src.import.CacheContract")
    if gen < 3 then
      require("tests.modkit.dataset_view_fixture").cache(files, version, {
        pokemon = data.pokemon,
        moves = data.moves,
        items = data.items,
        maps = data.maps,
        trainers = data.trainers,
        encounters = data.encounters,
        type_chart = data.type_chart,
      })
    else
      files[prefix .. "rom-cache.complete"] = Contract.markerFor(version)
      for _, path in ipairs(Contract.requiredFiles(version, true)) do
        files[prefix .. path] = path:match("%.lua$") and writer.encode({}) or "fixture"
      end
      local p = data.gen3Pokemon
      for _, key in ipairs({
        "names",
        "types",
        "stats",
        "abilities",
        "abilityNames",
        "meta",
        "learnsets",
        "evolutions",
        "dex",
        "moveNames",
      }) do
        local file = ({ abilityNames = "ability_names", moveNames = "move_names" })[key] or key
        files[prefix .. "data/generated/gba/pokemon/" .. file .. ".lua"] =
          writer.encode(p[({ meta = "_speciesMeta" })[key] or "_" .. key] or {})
      end
      files[prefix .. "data/generated/maps.lua"] = writer.encode(data.maps)
      files[prefix .. "data/generated/gba/pokemon/battle_moves.lua"] =
        writer.encode(data.gen3Moves._rom or {})
      files[prefix .. "data/generated/gba/items/pack.lua"] = writer.encode({ items = data.gen3Items._byId })
    end
  else
    local Contract = require("src.import.RomImporter").datasetContract(version)
    files[prefix .. "rom-cache.complete"] = Contract.marker
    for _, name in ipairs(Contract.modules) do
      files[prefix .. "data/generated/" .. name .. ".lua"] = writer.encode(data[name] or {})
    end
  end
  files[prefix .. "assets/generated/probe.png"] = "PNG"
  local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
  end
  for _, name in ipairs({ "manifest.json", "main.lua" }) do
    files["mods/datasets/" .. name] = read(root .. "/mods/datasets/" .. name)
  end
  local fs = {
    read = function(path)
      return files[path]
    end,
    getInfo = function(path)
      if files[path] then
        return { type = "file", size = #files[path] }
      end
      if path == "mods" or path == "mods/datasets" then
        return { type = "directory" }
      end
    end,
    getDirectoryItems = function(path)
      return path == "mods" and { "datasets" } or {}
    end,
    load = function(path)
      return loadstring(assert(files[path]), "@" .. path)
    end,
  }
  local loader = require("src.mods.Loader").new({ fs = fs, dev = false, generation = gen, version = version })
  loader._game = function()
    error("dataset access must not bootstrap Game")
  end
  assert(loader:load(data), table.concat(loader.errors, "; "))
  return { loader = loader, exports = assert(loader.exports.datasets), files = files, fs = fs, prefix = prefix }
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  local before = require("src.core.GameVersion").get()
  local report, why = f.exports.inspect(version)
  assert(report, why)
  assert(require("src.core.GameVersion").get() == before)
  assert(f.exports.open("not_a_version") == nil)
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
