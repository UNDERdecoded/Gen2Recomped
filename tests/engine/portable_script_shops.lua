package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_shops")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(v, native)
  local f = Contract.fixture("tests/api3_contract", "gen2", v or "red")
  f.game.save.money = 1000
  if native then
    f.game.data.constants = f.game.data.constants or {}
    f.game.data.constants.gen3MartText = { buy = "BUY", sell = "SELL", quit = "QUIT" }
  end
  return f
end
local function queue(f)
  return f.exports.queue({ { "open_mart", "SHOP" }, { "set_flag", "mod:after" } })
end
local function finishChoice(f)
  f:tick("a")
  for _ = 1, 20 do
    f:tick()
  end
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared shop contract: " .. tostring(why))
end
for _, change in ipairs({
  "unknown",
  "invalid_price",
  "unknown_item",
  "empty",
  "sparse",
  "wallet",
  "inventory",
  "overflow",
}) do
  local f = fixture()
  local ref = "SHOP"
  if change == "unknown" then
    ref = "UNKNOWN"
  elseif change == "invalid_price" then
    f.game.data.items.POTION.price = -1
  elseif change == "unknown_item" then
    f.game.data.text_pointers.SHOP_HOME.SHOP.mart = { "UNKNOWN" }
  elseif change == "empty" then
    f.game.data.text_pointers.SHOP_HOME.SHOP.mart = {}
  elseif change == "sparse" then
    f.game.data.text_pointers.SHOP_HOME.SHOP.mart[3] = "POTION"
  elseif change == "wallet" then
    f.game.save.money = false
  elseif change == "inventory" then
    f.game.save.inventory.POTION = -1
  else
    f.game.save.money = 9007199254740991
  end
  T.eq(
    f.exports.queue({ { "set_flag", "mod:prefix" }, { "open_mart", ref } }),
    nil,
    "invalid shop preflight: " .. change
  )
  T.eq(f.exports.get("mod:prefix"), false, "invalid suffix prevents prefix")
  T.eq(f.game.stack:top(), f.ow, "preflight opens no native UI")
end
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local f = fixture(v)
  T.check(queue(f), v .. " native classic shop admitted")
  local root = f.game.stack:top()
  f:tick("a")
  local list = f.game.stack:top()
  T.eq(getmetatable(list), require("src.ui.ListMenu"), "native buy list opened")
  f:tick("a")
  local quantity = f.game.stack:top()
  local oldQuantity = quantity.onDone
  T.eq(getmetatable(quantity), require("src.ui.QuantityBox"), "native quantity picker opened")
  f:tick("a")
  local choice = f.game.stack:top()
  local oldChoice = choice.onChoose
  finishChoice(f)
  T.eq(f.quantity(), 4, "native bag receives purchase")
  T.eq(f.game.save.money, 900, "native wallet charged once")
  oldQuantity(99)
  oldChoice(true)
  T.eq(f.quantity(), 4, "old quantity/confirm callbacks cannot replay purchase")
  T.eq(f.game.save.money, 900, "old callbacks cannot charge again")
  T.eq(f.game.stack:top(), list, "nested callbacks retain native list")
  f:close()
  f:drain()
  T.eq(f.exports.result().success, true, "shop quit resumes script")
  T.eq(f.exports.get("mod:after"), true, "script runs after native close")
  root.onCancel()
  oldQuantity(1)
  oldChoice(true)
  T.eq(f.game.stack:top(), f.ow, "finished UI cannot reopen a child")
end
for _, v in ipairs({ "red", "gold", "firered", "emerald" }) do
  local f = fixture(v)
  T.check(queue(f), "native sale admitted")
  f.game.stack:top().index = 2
  f:tick("a")
  f:tick("a")
  local quantity = f.game.stack:top()
  quantity.qty = 3
  f:tick("a")
  finishChoice(f)
  T.eq(f.quantity(), 0, "native sale removes full item stack")
  T.eq(f.game.save.money, 1150, "native sale credits half price")
  T.eq(#f.game.save.bagOrder, 0, "native sale removes stale bag order entry")
  f:close()
  f:drain()
  T.eq(f.exports.result().success, true, "native sale closes normally")
end
for _, change in ipairs({ "rollback", "save", "data", "price", "inventory", "removed" }) do
  local f = fixture()
  T.check(queue(f), "shop before live change")
  f:tick("a")
  f:tick("a")
  local quantity = f.game.stack:top()
  local callback = quantity.onDone
  local overlay = {}
  f.game.stack:push(overlay)
  if change == "rollback" then
    f.loader:_rollback("script_shops")
  elseif change == "price" then
    f.game.data.items.POTION.price = 200
  elseif change == "inventory" then
    f.game.save.inventory = { POTION = 3 }
  elseif change == "removed" then
    table.remove(f.game.stack.states, 2)
  else
    f.game[change] = {}
  end
  f.loader.hooks:call("input.step", function() end, f.game, 1 / 60)
  T.eq(f.exports.result().success, false, "live context/item change cancels shop")
  T.eq(f.game.stack:top(), overlay, "foreign overlay survives shop cancellation")
  T.eq(#f.game.stack.states, 2, "only owned nested screens removed")
  callback(1)
  T.eq(#f.game.stack.states, 2, "stale quantity cannot open a confirmation")
end
for _, v in ipairs({ "firered", "emerald" }) do
  local f = fixture(v, true)
  T.check(queue(f), v .. " native Gen3 counter admitted")
  local root = f.game.stack:top()
  f:tick("a")
  local counter = f.game.stack:top()
  T.eq(getmetatable(counter), require("src.ui.Gen3ShopMenu"), "Gen3 buy counter selected")
  f:tick("a")
  local asking = counter.asking
  local oldQuantity = asking and asking.onDone
  T.check(asking, "native Gen3 inline quantity opened")
  f:tick("a")
  local box = f.game.stack:top()
  local oldChoice = box.choice
  for _ = 1, 2000 do
    f:tick("a")
    if f.quantity() == 4 then
      break
    end
  end
  T.eq(f.quantity(), 4, "native Gen3 confirmation purchases item")
  T.eq(f.game.save.money, 900, "native Gen3 wallet charged once")
  oldQuantity(5)
  oldChoice(true)
  T.eq(f.quantity(), 4, "old Gen3 inline callbacks cannot replay")
  T.eq(f.game.save.money, 900, "old Gen3 callbacks cannot charge again")
  f:close()
  f:drain()
  T.eq(f.exports.result().success, true, "native Gen3 counter closes")
end
-- A retained confirmation is inert under a foreign overlay, then the native
-- answer still works after that overlay closes.
do
  local f = fixture()
  T.check(queue(f), "shop before foreign confirmation overlay")
  f:tick("a")
  f:tick("a")
  f:tick("a")
  local choice = f.game.stack:top()
  local callback = choice.onChoose
  local overlay = {}
  f.game.stack:push(overlay)
  callback(true)
  T.eq(f.quantity(), 3, "foreign overlay blocks direct confirmation")
  T.eq(f.game.save.money, 1000, "foreign overlay blocks debit")
  f.game.stack:pop()
  finishChoice(f)
  T.eq(f.quantity(), 4, "legitimate answer still works after overlay")
  f:close()
  f:drain()
end
for _, v in ipairs({ "firered", "emerald" }) do
  local f = fixture(v, true)
  T.check(queue(f), "Gen3 quantity before cancellation")
  f:tick("a")
  f:tick("a")
  local counter = f.game.stack:top()
  local old = counter.asking.onDone
  f:tick("b")
  old(1)
  T.eq(f.game.stack:top(), counter, "cancelled inline quantity cannot create confirmation")
  T.eq(f.quantity(), 3, "cancelled inline quantity cannot give item")
  f:tick("a")
  local current = counter.asking
  old(1)
  T.eq(counter.asking, current, "old inline callback cannot replace a new request")
  f:close()
  f:drain()
end
for _, v in ipairs({ "firered", "emerald" }) do
  local f = fixture(v, true)
  T.check(queue(f), "Gen3 native sale admitted")
  f.game.stack:top().index = 2
  f:tick("a")
  f:tick("a")
  local quantity = f.game.stack:top()
  if v == "firered" then
    T.eq(getmetatable(quantity), require("src.ui.Gen3ShopMenu"), "FireRed native inline sale quantity")
    T.check(quantity.asking, "FireRed sale quantity is active")
    quantity.asking.qty = 2
  else
    T.eq(getmetatable(quantity), require("src.ui.QuantityBox"), "Emerald native bag sale quantity")
    quantity.qty = 2
  end
  f:tick("a")
  for _ = 1, 2000 do
    f:tick("a")
    if f.quantity() == 1 then
      break
    end
  end
  T.eq(f.quantity(), 1, "Gen3 native sale removes selected quantity")
  T.eq(f.game.save.money, 1100, "Gen3 native sale credits wallet")
  f:close()
  f:drain()
  T.eq(f.exports.result().success, true, "Gen3 native sale returns to script")
end
for _, phase in ipairs({ "classic_quantity", "classic_choice", "gen3_quantity", "gen3_choice" }) do
  local native = phase:find("gen3", 1, true) ~= nil
  local f = fixture(native and "emerald" or "red", native)
  T.check(queue(f), "native shop before phase unload")
  f:tick("a")
  f:tick("a")
  local callbacks = {}
  if native then
    callbacks[#callbacks + 1] = f.game.stack:top().asking.onDone
  else
    callbacks[#callbacks + 1] = f.game.stack:top().onDone
  end
  if phase:find("choice", 1, true) then
    f:tick("a")
    local state = f.game.stack:top()
    callbacks[#callbacks + 1] = native and state.choice or state.onChoose
  end
  local overlay = {}
  f.game.stack:push(overlay)
  f.loader:_rollback("script_shops")
  for _, fn in ipairs(callbacks) do
    fn(1)
    fn(true)
  end
  T.eq(f.game.stack:top(), overlay, "unload keeps foreign overlay")
  T.eq(#f.game.stack.states, 2, "unload removes exact native shop screens")
  T.eq(f.quantity(), 3, "retired purchase callback cannot grant item")
  T.eq(f.game.save.money, 1000, "retired purchase callback cannot debit wallet")
end
for _, v in ipairs({ "red", "gold", "firered", "emerald" }) do
  local f = fixture(v)
  f.game.data.maps[f.dest].label = "SHOP_DEST"
  f.game.data.text_pointers.SHOP_DEST = { DEST_SHOP = { mart = { "POTION" } } }
  T.check(
    f.exports.queue({ { "warp", f.dest, 1, 1 }, { "open_mart", "DEST_SHOP" }, { "set_flag", "mod:after" } }),
    "destination shop preflight"
  )
  f:arrive()
  f:complete()
  f:tick()
  T.check(f.game.stack:top() ~= f.ow, "destination native shop opens after arrival")
  f:close()
  f:drain()
  T.eq(f.exports.result().success, true, "destination native shop resumes program")
  f = fixture(v)
  f.game.data.maps[f.dest].label = "SHOP_DEST"
  f.game.data.text_pointers.SHOP_DEST = { DEST_SHOP = { mart = { "UNKNOWN" } } }
  T.eq(
    f.exports.queue({ { "warp", f.dest, 1, 1 }, { "open_mart", "DEST_SHOP" } }),
    nil,
    "invalid destination stock refuses whole script"
  )
  T.eq(#f.trace, 0, "invalid future stock prevents warp")
end
for _, change in ipairs({ "wallet", "inventory", "stock" }) do
  local f = fixture()
  T.check(f.exports.queue({ { "wait", 1 }, { "open_mart", "SHOP" } }), "deferred shop admitted")
  if change == "wallet" then
    f.game.save.money = false
  elseif change == "inventory" then
    f.game.save.inventory = false
  else
    f.game.data.items.POTION.price = -1
  end
  f:drain()
  T.eq(f.exports.result().success, false, "live shop stores revalidated")
  T.eq(f.game.stack:top(), f.ow, "bad live data opens no native shop")
end
do
  local f = fixture()
  local overlay = {}
  local Screens = require("src.ui.Screens")
  f.game.data.screens = {
    ShopMenu = {
      new = function(game, stock, onQuit)
        f.loader:_rollback("script_shops")
        game.stack:push(overlay)
        return require("src.ui.ShopMenu").new(game, stock, onQuit)
      end,
    },
  }
  Screens.invalidate()
  T.check(queue(f), "shop admitted before constructor hook retires owner")
  T.eq(f.exports.result().success, false, "constructor retirement cancels program")
  T.eq(f.game.stack:top(), overlay, "constructor retirement preserves foreign overlay")
  T.eq(#f.game.stack.states, 2, "late native root removed after constructor returns")
  Screens.invalidate()
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script shops")
