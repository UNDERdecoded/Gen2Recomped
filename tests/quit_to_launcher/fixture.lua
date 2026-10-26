local F = {}

function F.new(root, version, api, format, noMod)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version or "red")
  local files = {}
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_quit/" .. name, "rb"))
    files["mods/portable_quit/" .. name] = file:read("*a")
    file:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/portable_quit/manifest.json"]))
  manifest.api = api or 2
  manifest.callback_format = format or "native"
  files["mods/portable_quit/manifest.json"] = Json.encode(manifest)
  local data = Version.generation() == 3 and T.sdk.gen3Data and T.sdk.gen3Data() or T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_quit" }, {
    fs = T.sdk.memfs(noMod and {} or files),
    data = data,
    generation = Version.generation(),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  assert(noMod or result.loader.exports.portable_quit, "portable quit entry did not execute")
  local okBridge, bridge = pcall(require, "src.core.PlatformHooks")
  return {
    T = T,
    result = result,
    exports = result.loader.exports.portable_quit,
    bridge = okBridge and bridge or {},
    api = api or 2,
    close = function()
      if result.loader._closeModInput then
        result.loader:_closeModInput()
      end
      result.release()
    end,
  }
end

return F
