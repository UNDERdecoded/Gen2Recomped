local M = {}
function M.new(root, backend, version, api, format, noMod)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local generation = Version.generation()
  local files = {}
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_logic_speed/" .. path, "rb"))
    files["mods/portable_logic_speed/" .. path] = file:read("*a")
    file:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/portable_logic_speed/manifest.json"]))
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_logic_speed/manifest.json"] = Json.encode(manifest)
  local data = backend == "gen1" and generation == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_logic_speed" }, {
    data = data,
    generation = generation,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  local module = "src.core.Game"
  if backend == "gen1" and generation > 1 then
    module = module .. generation
  end
  local Game = require(module)
  local function owner(speed)
    local opts = { speed = speed, speedOverworld = speed, speedBattle = speed, speedMenu = speed }
    local game = setmetatable({
      generation = generation,
      phase = "field",
      data = data,
      mods = result.loader,
      save = { options = opts },
      options = opts,
      stack = { states = { { isOverworld = true } } },
      resolves = 0,
    }, { __index = Game })
    function game:_resolveLogicSpeed()
      self.resolves = self.resolves + 1
      return Game._resolveLogicSpeed(self)
    end
    return game
  end
  local g = owner(4)
  -- Host-specific state fixtures exercise the actual native speedLocked method.
  local keys = { "src.core.game3.link", "src.core.game3.minigames.common" }
  local saved = {}
  for _, key in ipairs(keys) do
    saved[key] = package.loaded[key]
  end
  local function lock(kind)
    g.linkSession, g.linkNet = nil, nil
    g.stack.states = { { isOverworld = true } }
    if backend == "gen1" and generation == 3 then
      package.loaded[keys[1]] = { link = kind == "link" and true or nil }
      package.loaded[keys[2]] = {
        isActive = function()
          return kind == "fixed"
        end,
      }
    elseif kind == "link" then
      g.linkSession = true
    elseif kind == "fixed" then
      g.stack.states = { { isFixedSpeed = true }, { isMenu = true } }
    end
  end
  local exports = result.loader.exports.portable_logic_speed
  return {
    T = T,
    result = result,
    game = g,
    owner = owner,
    lock = lock,
    backend = backend,
    generation = generation,
    api = api,
    format = format,
    exports = exports,
    public = exports and exports.api,
    close = function()
      for _, key in ipairs(keys) do
        package.loaded[key] = saved[key]
      end
      if result.loader._closeModInput then
        result.loader:_closeModInput()
      end
      result.release()
    end,
  }
end
return M
