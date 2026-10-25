local M = {}
function M.new(root, backend, version, api, format, noMod)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local Input = require("src.core.Input")
  local name = backend == "gen1"
      and (version == "gold" and "Game2" or (version == "firered" or version == "emerald") and "Game3" or "Game")
    or "Game"
  local Game = require("src.core." .. name)
  local files = {}
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_input/" .. path, "rb"))
    files["mods/portable_input/" .. path] = f:read("*a")
    f:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/portable_input/manifest.json"]))
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_input/manifest.json"] = Json.encode(manifest)
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_input" }, {
    data = T.fixtures.fresh(),
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  Input:init()
  local f = {
    T = T,
    result = result,
    Input = Input,
    Game = Game,
    version = version,
    api = api,
    public = result.loader.exports.portable_input and result.loader.exports.portable_input.api,
    exports = result.loader.exports.portable_input,
  }
  local zoom = {}
  local game = setmetatable({
    input = Input,
    mods = result.loader,
    data = result.data,
    save = { options = {} },
    phase = "world",
    stack = {
      top = function()
        return nil
      end,
    },
    zoomStep = function(_, delta)
      zoom[#zoom + 1] = delta
    end,
    zoomView = function()
      return nil
    end,
  }, { __index = Game })
  f.game, f.zoom = game, zoom
  result.loader.game = game
  f.pad = {
    getName = function()
      return "Contract Gamepad"
    end,
    isGamepadDown = function()
      return false
    end,
    getGamepadAxis = function()
      return 0
    end,
  }
  function f.close()
    result.release()
  end
  return f
end
return M
