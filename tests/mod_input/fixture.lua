local M = {}
function M.new(root, backend, version, api, format)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local generation = Version.generation()
  local Input = require("src.core.Input")
  local files, paths = {}, {}
  local Json = require("src.link.Json")
  local function read(path)
    local f = assert(io.open(root .. "/examples/portable_mod_input/" .. path, "rb"))
    local bytes = f:read("*a")
    f:close()
    return bytes
  end
  local manifest = assert(Json.decode(read("manifest.json")))
  for _, id in ipairs({ "portable_mod_input", "portable_mod_input_peer" }) do
    paths[#paths + 1] = "mods/" .. id
    manifest.id, manifest.api, manifest.callback_format = id, api, format
    files["mods/" .. id .. "/manifest.json"] = Json.encode(manifest)
    files["mods/" .. id .. "/main.lua"] = read("main.lua")
  end
  local data = backend == "gen1" and generation == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local result =
    T.sdk.loadMods(paths, { generation = generation, data = data, fs = T.sdk.memfs(files), dev = false })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  Input:init()
  local game = {
    input = Input,
    mods = result.loader,
    data = data,
    save = { options = {} },
    stack = {
      states = {},
      top = function()
        return nil
      end,
    },
  }
  result.loader.game = game
  local f = {
    T = T,
    result = result,
    Input = Input,
    game = game,
    primary = assert(result.loader.exports.portable_mod_input),
    peer = assert(result.loader.exports.portable_mod_input_peer),
    files = files,
    paths = paths,
  }
  function f.ready()
    result.loader.events:emit("game.ready", { game = game })
  end
  function f.close()
    result.loader:releaseModInput()
    result.release()
  end
  return f
end
return M
