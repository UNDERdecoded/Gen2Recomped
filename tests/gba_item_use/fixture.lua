local M = {}
function M.new(root, backend, version, api, format, noMod, failing)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  Version.set(version)
  local rows = {
    { 13, "POTION", "heal", { heal = true, amount = 20 }, {} },
    { 22, "SUPER_POTION", "heal", { heal = true, amount = 50 }, {} },
    { 17, "AWAKENING", "status", { cures = { "SLP" } }, { [4] = 32 } },
    { 24, "REVIVE", "revive", { revive = true, amount = "half" }, {} },
    { 34, "ETHER", "pp", { pp = "one", amount = 10 }, { [5] = 24, [7] = 10 } },
    { 86, "REPEL", "repel", nil, nil },
    { 260, "COIN_CASE", "coin_case", nil, nil },
    { 360, "BICYCLE", "bike", nil, nil },
    { 259, "MACH_BIKE", "bike", nil, nil },
    { 85, "ESCAPE_ROPE", "escape", nil, nil },
    { 262, "OLD_ROD", "rod", nil, nil },
    { 43, "WHITE_FLUTE", "black_white_flute", nil, nil },
    { 42, "BLACK_FLUTE", "black_white_flute", nil, nil },
    { 289, "TM_01", "tm", nil, nil },
    { 195, "EVERSTONE", "none", nil, nil },
    { 999, "UNKNOWN", "none", nil, nil },
  }
  local data = backend == "gen1" and T.sdk.gen3Data() or T.fixtures.fresh()
  local nativeIds, pack = {}, { items = {} }
  data.items, data.constants = data.items or {}, data.constants or {}
  data.constants.gen3ItemEffects = {}
  for _, row in ipairs(rows) do
    local number, key, kind, effect, bytes = unpack(row)
    local id = backend == "gen1" and number or ("ITEM_%03d"):format(number)
    nativeIds[key] = id
    if backend == "gen1" then
      data.gen3Items._byId[number] = { name = key:gsub("_", " "), pocket = "ITEMS", price = 100 }
    else
      data.items[id] =
        { id = id, name = key:gsub("_", " "), key = key, index = number, price = 100, pocket = "ITEM" }
      if key == "TM_01" then
        data.items[id].machine = { kind = "TM", number = 1, move = "FIX_CUT" }
      end
      if effect then
        data.constants.gen3ItemEffects[id] = effect
      end
    end
    local bytesRow = {}
    for i = 1, 7 do
      bytesRow[i] = (bytes or {})[i] or 0
    end
    pack.items[number] =
      { name = key:gsub("_", " "), pocket = "ITEMS", fieldUse = kind, price = 100, effect = bytesRow }
  end
  data.maps.FIX_FIELD = {
    id = "FIX_FIELD",
    name = "FIX FIELD",
    width = 4,
    height = 4,
    bikingAllowed = 1,
    allowCycling = true,
    allowEscaping = false,
  }
  local Json, files = require("src.link.Json"), {}
  for _, name in ipairs({ "manifest.json", "main.lua" }) do
    local file = assert(io.open(root .. "/examples/portable_gba_item_use/" .. name, "rb"))
    files["mods/portable_gba_item_use/" .. name] = file:read("*a")
    file:close()
  end
  local manifest = Json.decode(files["mods/portable_gba_item_use/manifest.json"])
  manifest.api, manifest.callback_format = api, format
  files["mods/portable_gba_item_use/manifest.json"] = Json.encode(manifest)
  if failing then
    files["mods/portable_gba_item_use/main.lua"] = files["mods/portable_gba_item_use/main.lua"]
      .. '\nerror("intentional GBA item entry failure")'
  end
  if noMod then
    files["mods/portable_gba_item_use/manifest.json"], files["mods/portable_gba_item_use/main.lua"] = nil, nil
  end
  local result = T.sdk.loadMods(
    noMod and {} or { "mods/portable_gba_item_use" },
    { data = data, fs = T.sdk.memfs(files), dev = false, generation = 3 }
  )
  if not failing then
    assert(#result.errors == 0, table.concat(result.errors, "\n"))
  end
  local game = {
    data = data,
    save = {
      version = version,
      options = {},
      player = { name = "PROBE" },
      party = {},
      inventory = {},
      flags = {},
    },
  }
  local restores = {}
  local function patch(owner, key, value)
    local old = owner[key]
    restores[#restores + 1] = function()
      owner[key] = old
    end
    owner[key] = value
  end
  local mon
  local bag, use, count
  if backend == "gen1" then
    local Items = require("src.core.game3.items_data")
    for _, key in ipairs({ "_pack", "_byId", "_byName" }) do
      patch(Items, key, Items[key])
    end
    Items.installPack(pack)
    local Pokemon = require("src.core.game3.pokemon")
    patch(Pokemon, "_battleMoves", { [33] = { pp = 35 }, [52] = { pp = 25 } })
    patch(Pokemon, "_tmhm", { machines = { [0] = 52 }, learnsets = { [4] = { lo = 1, hi = 0 } } })
    patch(Pokemon, "_moveNames", { [33] = "TACKLE", [52] = "EMBER" })
    patch(Pokemon, "_speciesMeta", data.gen3Pokemon._speciesMeta)
    local Runtime = require("src.core.game3.runtime")
    patch(Runtime, "_game", game)
    local text = {}
    for _, key in ipairs({
      "gText_PkmnWokeUp2",
      "gText_PkmnHPRestoredByVar2",
      "gText_PkmnWokeUp",
      "gText_PkmnReturnedToNormal",
      "gText_PkmnRecoveredFromPoison",
      "gText_PkmnBurnHealed",
      "gText_PkmnWasDefrosted",
      "gText_PkmnCuredOfParalysis",
      "gText_PPWasRestored",
      "gText_WontHaveEffect",
      "gText_CoinCase",
      "gText_PlayerUsedVar2",
      "gText_RepelEffectsLingered",
      "gText_CantDismountBike",
      "gText_OakForbidsUseOfItemHere",
      "gText_DadsAdvice",
      "gText_PkmnLearnedMove3",
      "gText_PkmnAlreadyKnows",
      "gText_PkmnCantLearnMove",
      "gText_PkmnNeedsToReplaceMove",
      "gText_MoveNotLearned",
      "gText_UsedVar2WildLured",
      "gText_UsedVar2WildRepelled",
      "gText_OakThisIsntTheTime",
      "gText_ThereIsNoPokemon",
    }) do
      text[key] = { { t = "text", s = key }, { t = "eos" } }
    end
    patch(require("src.core.game3.scripting.space"), "bundle", { text = text, events = {} })
    mon = {
      species = 4,
      nickname = "PROBE",
      level = 12,
      hp = 15,
      maxHp = 40,
      friendship = 70,
      moves = { 33 },
      pp = { 0 },
    }
    game.session = {
      version = version,
      name = "PROBE",
      map = "FIX_FIELD",
      party = { mon },
      coins = 27,
      flags = {},
      vars = {},
    }
    local player = require("src.core.game3.player")
    for name, value in pairs({
      cellX = 2,
      cellY = 2,
      px = 32,
      py = 32,
      facing = "down",
      moving = false,
      surfing = false,
      underwater = false,
      biking = false,
    }) do
      patch(player, name, value)
    end
    game.save.party = game.session.party
    local Bag = require("src.core.game3.bag")
    bag = Bag.new()
    game.session.bag = bag
    use = function(id, slot, move)
      return require("src.core.game3.item_use").useField(game.session, bag, id, slot, move)
    end
    count = function(id)
      return Bag.get(bag, id)
    end
  else
    mon = {
      species = "FIXMON_A",
      nickname = "PROBE",
      level = 12,
      hp = 15,
      stats = { hp = 40 },
      moves = { { id = "FIX_TACKLE", pp = 0 } },
    }
    game.save.party = { mon }
    game.save.coins = 27
    local World = require("src.world.OverworldController")
    local bound = false
    for i = 1, 40 do
      local name, old = debug.getupvalue(World.bikeAllowed, i)
      if not name then
        break
      end
      if name == "Game" then
        debug.setupvalue(World.bikeAllowed, i, game)
        restores[#restores + 1] = function()
          debug.setupvalue(World.bikeAllowed, i, old)
        end
        bound = true
        break
      end
    end
    assert(bound, "missing native world Game binding")
    local def = data.maps.FIX_FIELD
    def.tileset, def.blockPx, def.blocks = "FIX_OUT", 16, {}
    for i = 1, 16 do
      def.blocks[i] = 1
    end
    local player = setmetatable(
      { cellX = 2, cellY = 2, facing = "down" },
      { __index = require("src.world.Player") }
    )
    game.overworld = setmetatable(
      { map = require("src.world.Map").new(def, data.tilesets.FIX_OUT), player = player },
      { __index = World }
    )
    bag = game.save.inventory
    use = function(id, slot, move)
      return require("src.inventory.Gen3FieldUse").call(game, id, slot, move)
    end
    count = function(id)
      return bag[id] or 0
    end
  end
  result.loader.game = game
  game.mods = result.loader
  local second = require("src.mods.Merge").deepCopy(mon)
  second.hp, second.nickname = 5, "SECOND"
  game.save.party[2] = second
  local function fill()
    if backend == "gen1" then
      local Bag = require("src.core.game3.bag")
      Bag.clear(bag)
      for _, id in pairs(nativeIds) do
        Bag.add(bag, id, 3)
      end
    else
      for _, id in pairs(nativeIds) do
        bag[id] = 3
      end
    end
  end
  fill()
  local function press(key)
    game.input.pressed = key and { [key] = true } or {}
    assert(game.stack:top()):update(1 / 60)
    game.input.pressed = {}
  end
  local function nativePicker(key)
    assert(backend == "gen2", "Gen2 native UI fixture")
    local Data = require("src.core.Data")
    for _, name in ipairs({ "items", "constants", "pokemon", "moves", "audio" }) do
      patch(Data, name, data[name])
    end
    require("src.render.Font").load(data)
    game.input = setmetatable({}, { __index = require("src.core.Input") })
    game.input:init()
    game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
    game.stack:init()
    game.stack.states = { game.overworld }
    local menu = require("src.ui.Gen3BagMenu").new(game, {})
    game.stack:push(menu)
    for i, row in ipairs(menu.rows) do
      if row.id == nativeIds[key] then
        menu.index = i
        break
      end
    end
    for _ = 1, 1200 do
      if getmetatable(game.stack:top()) == require("src.ui.Gen3PartyMenu") then
        break
      end
      press("a")
    end
    assert(
      getmetatable(game.stack:top()) == require("src.ui.Gen3PartyMenu"),
      "native GBA party picker expected"
    )
    return menu, game.stack:top()
  end
  local function fullMoves()
    if backend == "gen1" then
      mon.moves, mon.pp = { 33, 10, 45, 98 }, { 35, 35, 40, 30 }
    else
      data.moves.FIX_EXTRA = { name = "EXTRA", type = "NORMAL", pp = 30, power = 40, accuracy = 100 }
      mon.moves = {}
      for _, id in ipairs({ "FIX_TACKLE", "FIX_SCRATCH", "FIX_EMBERISH", "FIX_EXTRA" }) do
        mon.moves[#mon.moves + 1] = { id = id, pp = data.moves[id].pp }
      end
    end
  end
  return {
    fullMoves = fullMoves,
    T = T,
    e = result.loader.exports.portable_gba_item_use,
    game = game,
    mon = mon,
    bag = bag,
    result = result,
    use = function(key, slot, move)
      return use(nativeIds[key] or key, slot, move)
    end,
    id = nativeIds,
    count = function(key)
      return count(nativeIds[key] or key)
    end,
    fill = fill,
    patch = patch,
    backend = backend,
    api = api,
    version = version,
    canonicalIds = api >= 3 or (backend == "gen2" and api == 2 and format == "unified"),
    second = second,
    nativePicker = nativePicker,
    press = press,
    flute = function()
      if backend ~= "gen1" then
        return game.save.gen3Flute
      end
      local flags = require("src.core.game3.field_moves").SYS_FLAGS
      return game.session.flags[flags.WHITE_FLUTE_ACTIVE] and "white"
        or game.session.flags[flags.BLACK_FLUTE_ACTIVE] and "black"
        or nil
    end,
    biking = function()
      return backend == "gen1" and game.session.biking == true
        or backend == "gen2" and game.save.onBike == true
    end,
    pp = function()
      return backend == "gen1" and mon.pp[1] or mon.moves[1].pp
    end,
    close = function()
      for i = #restores, 1, -1 do
        restores[i]()
      end
      result.release()
    end,
  }
end
return M
