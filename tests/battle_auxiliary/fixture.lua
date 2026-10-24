local M = {}
function M.new(root, version, api, format, noMod)
  local T = require("tests.modkit")
  require("src.core.GameVersion").set(version)
  local Json, files = require("src.link.Json"), {}
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_battle_auxiliary/" .. name, "rb"))
    files["mods/portable_battle_auxiliary/" .. name] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/portable_battle_auxiliary/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_battle_auxiliary/manifest.json"] = Json.encode(manifest)
  local data = T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_battle_auxiliary" }, {
    data = data,
    generation = require("src.core.GameVersion").generation(),
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  local game = { data = data, save = require("src.core.SaveData").newGame(), sessionStartedAt = 1 }
  game.input = setmetatable({}, { __index = require("src.core.Input") })
  game.input:init()
  game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
  game.stack:init()
  game.save.party = { require("src.pokemon.Pokemon").new(data, "FIXMON_A", 20) }
  result.loader.game = game
  require("src.render.Font").load(data)
  local b = require("src.battle.BattleState").newWild(game, "FIXMON_C", 10)
  b:syncSides()
  b.phase, b.frame, b.queue = "menu", 0, {}
  b.gen4CursorActive = true
  b.menuIndex, b.moveIndex = 1, 1
  game.stack.states = { b }
  local exports = result.loader.exports.portable_battle_auxiliary
  return {
    T = T,
    game = game,
    battle = b,
    exports = exports,
    result = result,
    api = api,
    press = function(start, right)
      local direction = require("src.core.GameVersion").generation() >= 4 and "down" or "right"
      game.input.pressed = { start = start, [direction] = right }
      b:update(1 / 60)
    end,
    close = function()
      result.release()
    end,
  }
end
return M
