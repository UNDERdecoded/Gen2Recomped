local M = {}
function M.new(root, backend, version, api, format, noMod)
  local T = require("tests.modkit")
  love.event = love.event or {}
  local Version = require("src.core.GameVersion")
  Version.set(version)
  -- Load the real host callbacks without booting/importing a cartridge.
  dofile("main.lua")
  local entryUpdate = love.update
  local function upvalue(fn, name)
    for i = 1, 100 do
      local n, value = debug.getupvalue(fn, i)
      if not n then
        break
      end
      if n == name then
        return i, value
      end
    end
  end
  -- Gen1 decorates love.update with its native frame profiler.
  local _, original = upvalue(entryUpdate, "gameUpdate")
  local update = original or entryUpdate
  local function set(name, value)
    local owner, index = update, upvalue(update, name)
    if not index then
      owner, index = entryUpdate, upvalue(entryUpdate, name)
    end
    if not index then
      local _, iterations = upvalue(update, "scriptedIterations")
      if iterations then
        owner, index = iterations, upvalue(iterations, name)
      end
    end
    assert(index, "missing native update upvalue: " .. name)
    debug.setupvalue(owner, index, value)
  end
  local files = {}
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_core_update/" .. path, "rb"))
    files["mods/portable_core_update/" .. path] = f:read("*a")
    f:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/portable_core_update/manifest.json"]))
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_core_update/manifest.json"] = Json.encode(manifest)
  local generation = Version.generation()
  local data = backend == "gen1" and generation == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_core_update" }, {
    data = data,
    generation = generation,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  local game = { calls = 0, dts = {}, mods = result.loader, data = data }
  function game:update(dt)
    self.calls = self.calls + 1
    self.dts[#self.dts + 1] = dt
    return "ignored native result", nil, "tail"
  end
  set("Game", game)
  set("speedOverride", nil)
  local hostPolls = 0
  if backend == "gen1" then
    require("src.core.HostDisplay").setBackend({
      update = function()
        hostPolls = hostPolls + 1
      end,
    })
  else
    -- Isolate the unrelated watts service; retain love.update's real routing.
    set("walkerTick", function()
      hostPolls = hostPolls + 1
    end)
  end
  local exports = result.loader.exports.portable_core_update
  return {
    T = T,
    result = result,
    game = game,
    api = api,
    format = format,
    exports = exports,
    public = exports and exports.api,
    set = set,
    update = entryUpdate,
    bridge = require("src.core.PlatformHooks"),
    hostPolls = function()
      return hostPolls
    end,
    close = function()
      if backend == "gen1" then
        require("src.core.HostDisplay").setBackend(nil)
      end
      if result.loader._closeModInput then
        result.loader:_closeModInput()
      end
      result.release()
    end,
  }
end
return M
