local M = {}
function M.new(root, backend, version, api, format, noMod)
  local T = require("tests.modkit")
  local Version, Json = require("src.core.GameVersion"), require("src.link.Json")
  Version.set(version)
  local files = {}
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_level_visible/" .. name, "rb"))
    files["mods/portable_level_visible/" .. name] = file:read("*a")
    file:close()
  end
  local actualFormat = api >= 3 and "unified" or (backend == "gen1" and "native" or format)
  local manifest = Json.decode(files["mods/portable_level_visible/manifest.json"])
  manifest.api, manifest.callback_format = api, backend == "gen2" and format or nil
  files["mods/portable_level_visible/manifest.json"] = Json.encode(manifest)
  local data = T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_level_visible" }, {
    data = data,
    generation = Version.generation(),
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  local restores = {}
  local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function()
      owner[key] = old
    end
    owner[key] = value
  end
  local game = { data = data, save = { options = {} } }
  local mon = require("src.pokemon.Pokemon").new(data, "FIXMON_A", 42)
  local e = result.loader.exports.portable_level_visible
  return {
    T = T,
    game = game,
    mon = mon,
    data = data,
    result = result,
    exports = e,
    api = api,
    format = actualFormat,
    backend = backend,
    patch = patch,
    visible = function(where, value)
      return require("src.ui.LevelDisplay").visible(value or mon, where, game)
    end,
    close = function()
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
