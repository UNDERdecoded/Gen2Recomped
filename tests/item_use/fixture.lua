local M = {}
function M.new(root, backend, version, api, format, noMod, failing, nativeAlias)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local data = T.fixtures.fresh()
  local defs = {
    POTION = { name = "POTION" },
    SUPER_POTION = { name = "SUPER POTION" },
    ANTIDOTE = { name = "ANTIDOTE" },
    ETHER = { name = "ETHER" },
    REPEL = { name = "REPEL" },
    POKE_BALL = { name = "POKe BALL", ball = "POKE_BALL" },
    POKE_DOLL = { name = "POKe DOLL" },
    X_ATTACK = { name = "X ATTACK" },
    OLD_ROD = { name = "OLD ROD", keyItem = true },
    BICYCLE = { name = "BICYCLE", keyItem = true },
    MOON_STONE = { name = "MOON STONE" },
    TM_01 = { name = "TM01", machine = { kind = "TM", move = "FIX_CUT", number = 1 } },
    INVALID = { name = "INVALID" },
  }
  local index = 50
  for id, def in pairs(defs) do
    def.id, def.index, def.price, def.tossable = id, index, 100, true
    index = index + 1
    data.items[id] = def
  end
  if nativeAlias then
    data.items.ITEM_777 = data.items.POTION
    data.items.ITEM_777.id, data.items.ITEM_777.key = "ITEM_777", "POTION"
    data.items.POTION = nil
  end
  data.text = data.text or {}
  data.text._GotOnBicycleText1, data.text._GotOnBicycleText2 = "ON", "BIKE"
  data.text._GotOffBicycleText1, data.text._GotOffBicycleText2 = "OFF", "BIKE"
  data.field.bikeRiding = { maps = { "FIX_TOWN" }, tilesets = { "FIX_OUT" } }
  local Json, files = require("src.link.Json"), {}
  for _, name in ipairs({ "manifest.json", "main.lua" }) do
    local file = assert(io.open(root .. "/examples/portable_item_use/" .. name, "rb"))
    files["mods/portable_item_use/" .. name] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/portable_item_use/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  manifest.games = { "all" }
  files["mods/portable_item_use/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/portable_item_use/main.lua"] = files["mods/portable_item_use/main.lua"]
      .. '\nerror("intentional item entry failure")'
  end
  local result = T.sdk.loadMods(
    noMod and {} or { "mods/portable_item_use" },
    { data = data, fs = T.sdk.memfs(files), dev = false }
  )
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local game = { data = data, save = require("src.core.SaveData").newGame(), sessionStartedAt = 1 }
  game.save.version, game.save.player.name = version, "PROBE"
  game.input = setmetatable({}, { __index = require("src.core.Input") })
  game.input:init()
  game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
  game.stack:init()
  game.save.party = { require("src.pokemon.Pokemon").new(data, "FIXMON_A", 12) }
  game.save.party[1].nickname = "PROBE"
  require("src.render.Font").load(data)
  result.loader.game = game
  local world = { isOverworld = true, map = { id = "FIX_TOWN", def = { tileset = "FIX_OUT" } }, player = {} }
  game.world, game.overworld = world, world
  local f = {
    T = T,
    game = game,
    result = result,
    e = result.loader.exports.portable_item_use,
    api = api,
    backend = backend,
    version = version,
    world = world,
  }
  function f.press(key)
    game.input.pressed = { [key] = true }
    local top = assert(game.stack:top(), "no native menu")
    top:update(1 / 60)
    game.input.pressed = {}
  end
  function f.begin(id, inBattle)
    game.save.inventory, game.save.bagOrder = {}, {}
    require("src.inventory.Bag").add(game.save, id, 3, data)
    local mon = game.save.party[1]
    mon.hp, mon.status = mon.stats.hp - 25, nil
    if id == "ANTIDOTE" then
      mon.status = "PSN"
    end
    if id == "ETHER" then
      mon.moves[1].pp = 0
    end
    local battle
    if inBattle then
      battle = require("src.battle.BattleState").newWild(game, "FIXMON_C", 10)
      battle:syncSides()
      battle.phase, battle.frame, battle.queue = "menu", 0, {}
    end
    f.battle = battle
    game.stack.states = { battle or world }
    local list = require("src.ui.BagMenu").new(game, { battle = battle })
    game.stack:push(list)
    f.list = list
    for i, row in ipairs(list.items) do
      if row.value == id then
        list.index = i
        break
      end
    end
    f.press("a")
    local option = game.stack:top()
    if
      option ~= list
      and option.items
      and option.items[1]
      and type(option.items[1].onSelect) == "function"
    then
      f.press("a")
    end
    return list
  end
  function f.target()
    -- Machines print/ask before opening the party picker. Advance those
    -- native screens with real input rather than invoking their callbacks.
    for _ = 1, 1000 do
      if type(game.stack:top().onSwitch) == "function" then
        break
      end
      f.press("a")
    end
    local menu = assert(game.stack:top(), "missing party picker")
    assert(type(menu.onSwitch) == "function", "native party picker expected")
    f.picker = menu
    f.press("a")
  end
  function f.move()
    local TextBox = require("src.render.TextBox")
    for _ = 1, 500 do
      if getmetatable(game.stack:top()) ~= TextBox then
        break
      end
      f.press("a")
    end
    local menu = assert(game.stack:top())
    assert(type(menu.onChoose) == "function", "native move picker expected")
    f.press("a")
  end
  function f.count(id)
    return game.save.inventory[id] or 0
  end
  function f.close()
    result.release()
  end
  return f
end
return M
