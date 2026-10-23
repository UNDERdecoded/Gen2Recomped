local F = {}
function F.new(root, backend, version, api)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local s = dofile(root .. "/tests/render_contract/fixture.lua").new(backend, version, root)
  local Loader = require("src.mods.Loader")
  if backend == "gen1" then
    dofile(root .. "/tools/portable-world-check/gen1_reference.lua").install(Loader, s.handle)
  end
  local Json = require("src.link.Json")
  local files = {}
  for _, name in ipairs({ "main.lua", "WorldAdapter.lua", "Atlas.lua", "RenderPass.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_oasc_world/" .. name, "rb"))
    files["mods/portable_oasc_world/" .. name] = f:read("*a")
    f:close()
  end
  local manifest = assert(Json.decode(files["mods/portable_oasc_world/manifest.json"]))
  manifest.api = api
  files["mods/portable_oasc_world/manifest.json"] = Json.encode(manifest)
  local run = T.sdk.loadMods(
    { "mods/portable_oasc_world" },
    { data = T.fixtures.fresh(), fs = T.sdk.memfs(files) }
  )
  assert(#run.errors == 0, "identical example must load")
  run.loader.game = s.game
  local exports = assert(run.loader.exports.portable_oasc_world)
  assert(not exports.unavailable, exports.unavailable)

  return { state = s, run = run, exports = exports }
end
return F
