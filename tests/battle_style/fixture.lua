local F = {}

function F.new(root, version, api, format, noMod)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version or "red")
  local data = T.fixtures.fresh()
  local files = {}
  for _, name in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/portable_battle_style/" .. name, "rb"))
    files["mods/portable_battle_style/" .. name] = f:read("*a")
    f:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/portable_battle_style/manifest.json"]))
  manifest.api, manifest.callback_format = api or 2, format or "native"
  files["mods/portable_battle_style/manifest.json"] = Json.encode(manifest)
  local run = T.sdk.loadMods(noMod and {} or { "mods/portable_battle_style" }, {
    data = data,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#run.errors == 0, table.concat(run.errors, "\n"))
  assert(
    noMod or type(run.loader.exports.portable_battle_style.set) == "function",
    "consumer exports missing"
  )
  require("src.render.Font").load(data)
  require("src.battle.TypeChart").load(data)
  local Pokemon = require("src.pokemon.Pokemon")
  local SaveData = require("src.core.SaveData")
  local Battle = require("src.battle.BattleState")
  local function battle(style)
    local save = SaveData.newGame()
    save.player.name = "RED"
    save.options.battleStyle = style
    save.party = { Pokemon.new(data, "FIXMON_A", 30), Pokemon.new(data, "FIXMON_B", 30) }
    local pushed = {}
    local game = {
      data = data,
      save = save,
      stack = {
        top = function()
          return nil
        end,
        push = function(_, state)
          pushed[#pushed + 1] = state
        end,
        pop = function() end,
      },
    }
    local b = Battle.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
    b.participants = {}
    b.queue = {}
    return b, save, pushed
  end
  local function faint(b)
    b.enemyParty[1].hp = 0
    b.enemy.mon = b.enemyParty[1]
    b:enemyMonFainted()
    local offered = false
    for _, row in ipairs(b.queue) do
      if row.text and row.text:find("about to use", 1, true) then
        offered = true
      end
    end
    return offered
  end
  return {
    T = T,
    run = run,
    exports = run.loader.exports.portable_battle_style,
    battle = battle,
    faint = faint,
    close = run.release,
  }
end

return F
