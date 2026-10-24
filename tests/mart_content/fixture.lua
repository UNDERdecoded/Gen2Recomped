local F = {}
function F.new(root, backend, version, api, format, mode, source)
  local T, V = require("tests.modkit"), require("src.core.GameVersion")
  V.set(version)
  local gen, Json = V.generation(), require("src.link.Json")
  local keys = { POTION = 18, ANTIDOTE = 9, ULTRA_BALL = 2, NUGGET = 36 }
  local data = { items = {}, constants = { generation = gen }, text = {} }
  local function key(id)
    return backend == "gen2" and gen == 2 and ("ITEM_%03d"):format(keys[id]) or id
  end
  for id, index in pairs(keys) do
    data.items[key(id)] =
      { id = key(id), index = index, name = id:gsub("_", " "), price = 1200, pocket = "ITEM" }
  end
  local shelves = {
    [0] = { key("POTION"), key("ANTIDOTE") },
    [33] = { key("POTION") },
    bargain = { { item = key("NUGGET"), price = 4500 } },
  }
  if backend == "gen1" then
    data.gen2Marts = {
      generation = 2,
      source = "fixture",
      lists = { [1] = shelves[0], [34] = shelves[33] },
      bargain = shelves.bargain,
    }
  else
    data.map_scripts = { marts = shelves }
  end
  local files, name = {}, "portable_mart_content"
  for _, path in ipairs({ "main.lua", "manifest.json" }) do
    local f = assert(io.open(root .. "/examples/" .. name .. "/" .. path, "rb"))
    files["mods/" .. name .. "/" .. path] = f:read("*a")
    f:close()
  end
  local manifest = Json.decode(files["mods/" .. name .. "/manifest.json"])
  manifest.api, manifest.games, manifest.content_format = api, { version }, format
  manifest.gen2compat = api < 3 and true or nil
  files["mods/" .. name .. "/manifest.json"] = Json.encode(manifest)
  files["mods/" .. name .. "/case.txt"] = mode
  if source then
    files["mods/" .. name .. "/main.lua"] = "local mod=...; mod.exports.api=mod; " .. source
  end
  if mode == "stack" then
    files["mods/mart_overlay/manifest.json"] = Json.encode({
      id = "mart_overlay",
      name = "Mart overlay",
      version = "1.0.0",
      api = api,
      games = { version },
      gen2compat = api < 3 and true or nil,
      content_format = format,
      dependencies = { name },
      entry = "main.lua",
    })
    files["mods/mart_overlay/main.lua"] = 'local mod=...; mod.content.marts:patch("0", {"ANTIDOTE"})'
  end
  if mode == "no-mod" then
    files = {}
  end
  local r = T.sdk.loadMods(mode == "no-mod" and {} or { "mods/" .. name }, {
    data = data,
    fs = T.sdk.memfs(files),
    generation = gen,
    dev = false,
  })
  local f = { T = T, result = r, data = data, key = key, gen = gen, backend = backend, mode = mode }
  f.e = r.loader.exports[name]
  function f.shelf(id)
    if backend == "gen1" then
      local Mart = require("src.ui.gen2.MartMenu")
      return id == "bargain" and Mart.bargainRows(data.gen2Marts)
        or Mart.inventory(data.gen2Marts, tonumber(id))
    end
    return require("src.inventory.Gen2MartStock").get(data, tonumber(id), id == "bargain" and 2 or 0)
  end
  function f.purchase(bargain, qty)
    local save = { player = { money = 100000 }, money = 100000, inventory = {}, bagOrder = {} }
    local game = { data = data, save = save }
    local id, cost
    if backend == "gen1" then
      local Mart = require("src.ui.gen2.MartMenu")
      local menu = Mart.new(game, { martId = 0, martType = bargain and "BARGAIN" or "STANDARD" })
      local entry = menu.entries[1]
      if not entry then
        return nil
      end
      id, cost = entry.id, entry.price * qty
      menu.qtyItem, menu.qty = entry, qty
      menu:completePurchase(cost)
      if bargain then
        menu:offerToBuy()
      end
      return save.player.money, save.inventory[id], (save.bargainShop or {})[id] == true, entry.price
    end
    game.stack = setmetatable({}, { __index = require("src.core.StateStack") })
    game.stack:init()
    local stock = f.shelf(bargain and "bargain" or "0")
    if not stock or #stock == 0 then
      return nil
    end
    local menu = require("src.ui.ShopMenu").new(game, stock, nil, { bargain = bargain })
    game.stack:push(menu)
    if not bargain then
      menu.items[1].onSelect()
      menu = game.stack:top()
    end
    local entry = menu.items[1]
    id = entry.value
    menu.onChoose(entry)
    local quantity = game.stack:top()
    quantity.onDone(qty)
    local choice = game.stack:top()
    choice.onChoose(true)
    if bargain then
      menu.onChoose(entry)
    end
    local unit = bargain and stock[1].price or data.items[id].price
    return save.money, save.inventory[id], (save.bargainShop or {})[id] == true, unit
  end
  function f.close()
    r.release()
  end
  return f
end
return F
