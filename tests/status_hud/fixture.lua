local M = {}
function M.new(root, backend, version, api, format, noMod)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local generation = Version.generation()
  local files, Json = {}, require("src.link.Json")
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local file = assert(io.open(root .. "/examples/portable_status_hud/" .. path, "rb"))
    files["mods/portable_status_hud/" .. path] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/portable_status_hud/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_status_hud/manifest.json"] = Json.encode(manifest)
  local data = backend == "gen1" and generation == 3 and T.sdk.gen3Data() or T.fixtures.fresh()
  local result = T.sdk.loadMods(noMod and {} or { "mods/portable_status_hud" }, {
    data = data,
    generation = generation,
    fs = T.sdk.memfs(noMod and {} or files),
    dev = false,
  })
  assert(#result.errors == 0, table.concat(result.errors, "\n"))
  local restores, counters = {}, { ink = 0 }
  local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function()
      owner[key] = old
    end
    owner[key] = value
  end
  local function ink()
    counters.ink = counters.ink + 1
    return 16
  end
  local Input = require("src.core.Input")
  Input:init()
  local stack = setmetatable({}, { __index = require("src.core.StateStack") })
  stack:init()
  local game = { stack = stack, input = Input, data = data, save = { options = {} }, options = {} }
  local b, Ui, draw
  if backend == "gen1" and generation == 3 then
    patch(require("src.core.game3.battle.pic_coords"), "active", function()
      return { front = {}, back = {}, elev = {} }
    end)
    local State = require("src.core.game3.battle.state")
    local function mon(species)
      return {
        species = species,
        nickname = "CONTRACT",
        level = 20,
        hp = 60,
        maxHp = 60,
        attack = 30,
        defense = 30,
        speed = 30,
        spAtk = 30,
        spDef = 30,
        moves = { 33 },
        pp = { 35 },
        maxPp = { 35 },
        item = 0,
        ability = 0,
      }
    end
    b = State.new({ playerParty = { mon(4) }, foeParty = { mon(16) }, wild = true })
    Ui = require("src.core.game3.battle.ui")
    Ui.reset({ headless = true })
    Ui.bindState(b, { options = {} })
    local Anim = require("src.core.game3.battle.anim")
    Anim.reset({ headless = true })
    for id = 0, 1 do
      Anim.setShown(id, State.battler(b, id))
    end
    -- Spy at the healthbox leaf, leaving the native GBA compositor/predicate intact.
    patch(require("src.core.game3.battle.healthbox"), "draw", ink)
    draw = function()
      Ui.draw(240, 160, true)
    end
  else
    local class =
      require(backend == "gen1" and generation == 2 and "src.ui.gen2.BattleState" or "src.battle.BattleState")
    local function side()
      return {
        name = "CONTRACT",
        mon = { species = "FIXMON_A", level = 20, hp = 60, stats = { hp = 60 } },
        shownHP = 60,
      }
    end
    b = setmetatable({
      game = game,
      data = data,
      phase = "contract",
      frame = 0,
      shown = {},
      fx = {},
      player = side(),
      enemy = side(),
      ballRows = {},
      showEnemyHud = true,
      showPlayerHud = true,
    }, { __index = class })
    local Font = require("src.render.Font")
    for _, name in ipairs({ "draw", "drawCode", "drawBox" }) do
      patch(Font, name, ink)
    end
    if backend == "gen1" and generation == 2 then
      local Chrome = require("src.ui.gen2.Chrome")
      patch(Chrome, "printThrough", ink)
      patch(Chrome, "printRightThrough", ink)
      b.hud = {
        available = function()
          return true
        end,
        drawEnemyFrame = ink,
        drawPlayerFrame = ink,
        drawExpBar = ink,
      }
      b.activeMon = function(self, side)
        return self[side].mon
      end
      b.name = function()
        return "CONTRACT"
      end
      b.hudCleared = function()
        return false
      end
      b.statusTag = function()
        return nil
      end
      b.genderSymbol = function()
        return nil
      end
      b.caughtMarkerVisible = function()
        return false
      end
      b.hudHp = function()
        return 60
      end
      b.drawHpBar = ink
      draw = function()
        b:drawEnemyHud()
        b:drawPlayerHud()
      end
    else
      b.growInScale = function()
        return nil
      end
      b.colorMode = function()
        return false
      end
      b.demoHidesPlayer = function()
        return false
      end
      draw = function()
        b:drawHUDs(0)
      end
    end
  end
  local exports = result.loader.exports.portable_status_hud
  return {
    T = T,
    result = result,
    game = game,
    battle = b,
    stack = stack,
    input = Input,
    api = api,
    generation = generation,
    exports = exports,
    public = exports and exports.api,
    patch = patch,
    visible = function()
      if Ui then
        return Ui.statusHUDVisible()
      end
      return b:statusHUDVisible()
    end,
    draw = function()
      counters.ink = 0
      draw()
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
