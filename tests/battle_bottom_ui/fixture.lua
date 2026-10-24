local M = {}
function M.new(root, backend, version, api, format, noMod)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local generation = Version.generation()
  local files = {}
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_battle_bottom_ui/" .. path, "rb"))
    files["mods/portable_battle_bottom_ui/" .. path] = file:read("*a")
    file:close()
  end
  local Json = require("src.link.Json")
  local manifest = assert(Json.decode(files["mods/portable_battle_bottom_ui/manifest.json"]))
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_battle_bottom_ui/manifest.json"] = Json.encode(manifest)
  local data = backend == "gen1" and generation == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_battle_bottom_ui" }, {
    data = data,
    generation = generation,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  local restores = {}
  local function patch(owner, name, value)
    local old = owner[name]
    restores[#restores + 1] = function()
      owner[name] = old
    end
    owner[name] = value
  end
  local counters = { ink = 0, field = 0, actors = 0, hud = 0 }
  local function ink()
    counters.ink = counters.ink + 1
  end
  local Font = require("src.render.Font")
  for _, key in ipairs({ "drawBox", "drawDialogueBox", "draw", "drawCode", "drawHPBar" }) do
    patch(Font, key, ink)
  end
  local Input = require("src.core.Input")
  Input:init()
  local stack = setmetatable({}, { __index = require("src.core.StateStack") })
  stack:init()
  local game = { stack = stack, input = Input, data = data, save = { options = {} }, options = {} }
  local class =
    require(backend == "gen1" and generation == 2 and "src.ui.gen2.BattleState" or "src.battle.BattleState")
  local battle = setmetatable({
    game = game,
    data = data,
    save = game.save,
    phase = "contract",
    frame = 0,
    shown = {},
    fx = {},
    battle = { player = {}, enemy = {} },
    printMessage = function() end,
  }, { __index = class })
  local Ui
  local visibility = require("src.battle.UIVisibility")
  local drawBottom
  if backend == "gen1" and generation == 2 then
    local Chrome = require("src.ui.gen2.Chrome")
    patch(Chrome, "box", ink)
    patch(Chrome, "printThrough", ink)
    drawBottom = function()
      battle:drawBottom(0)
    end
  elseif backend == "gen1" and generation == 3 then
    Ui = require("src.core.game3.battle.ui")
    Ui.reset({ headless = true })
    Ui.bindState(battle, { options = {} })
    local Chrome = require("src.ui.game3.battle_chrome")
    patch(Chrome, "drawPanel", ink)
    patch(Chrome, "drawPostDexBg", function()
      counters.field = counters.field + 1
    end)
    local image = love.graphics.newImage("bottom-contract-sprite.png")
    Ui._caughtDexScene = {
      pal = {
        fx = function()
          return nil
        end,
      },
      sprite = { img = image, x = 0, y = 0, scaleY = 1 },
    }
    local draw = love.graphics.draw
    patch(love.graphics, "draw", function(img, ...)
      if img == image then
        counters.actors = counters.actors + 1
      end
      return draw(img, ...)
    end)
    drawBottom = function()
      Ui.draw(240, 160, true)
    end
  else
    drawBottom = function()
      battle:drawTextArea()
    end
  end
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local function textBox()
    return TextBox.new(game, "PORTABLE", nil, { drawFrame = true })
  end
  local function choiceBox(callback)
    return ChoiceBox.new(game, callback or function() end, { noSound = true })
  end
  local exports = result.loader.exports.portable_battle_bottom_ui
  return {
    T = T,
    result = result,
    game = game,
    battle = battle,
    stack = stack,
    backend = backend,
    generation = generation,
    api = api,
    format = format,
    exports = exports,
    public = exports and exports.api,
    patch = patch,
    input = Input,
    counters = counters,
    textBox = textBox,
    choiceBox = choiceBox,
    visible = function()
      if Ui then
        return Ui.bottomUIVisible()
      end
      return battle:bottomUIVisible()
    end,
    inherited = function(state, query)
      if Ui then
        return Ui.bottomUIVisible(state, query)
      end
      return visibility.bottomVisible(state, query)
    end,
    draw = function()
      for key in pairs(counters) do
        counters[key] = 0
      end
      drawBottom()
      return counters.ink > 0
    end,
    close = function()
      if Ui then
        Ui.reset({ headless = true })
      end
      for i = #restores, 1, -1 do
        restores[i]()
      end
      if result.loader._closeModInput then
        result.loader:_closeModInput()
      end
      result.release()
    end,
  }
end
return M
