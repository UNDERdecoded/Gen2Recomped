package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.script_state")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local function fixture(version)
  return Contract.fixture("tests/api3_contract", "gen2", version or "red")
end
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", version)
  T.check(ok, version .. " shared state actions: " .. tostring(why))
end
for _, rows in ipairs({
  { { "give_money", 1 }, { "take_item", "UNKNOWN" } },
  { { "jump", "end" }, { "mark_seen", "UNKNOWN" } },
  { { "give_money", -1 } },
  { { "take_money", 0.5 } },
  { { "give_money", math.huge } },
  { { "check_money", "10" } },
  { { "take_coins", false } },
  { { "take_item", "POTION", 0 } },
  { { "take_item", "POTION", 1000 } },
  { { "check_dex_owned", -1 } },
  { { "heal_party", true } },
  { { "check_item", {} } },
}) do
  local f = fixture()
  local runner = f.ow.runner
  T.eq(f.exports.queue(rows), nil, "whole invalid program declined")
  T.eq(f.wallet(), 100, "money prefix not executed")
  T.eq(f.quantity(), 3, "inventory untouched")
  T.eq(f.ow.runner, runner, "no runner installed on refusal")
  T.eq(f.exports.result().done, 0, "no completion on refusal")
end
for _, store in ipairs({ "money", "coins", "inventory", "bagOrder", "pokedex", "party" }) do
  local f = fixture()
  f.game.save[store] = false
  local row = ({
    money = { "give_money", 1 },
    coins = { "take_coins", 1 },
    inventory = { "take_item", "POTION" },
    bagOrder = { "take_item", "POTION" },
    pokedex = { "mark_seen", "MEW" },
    party = { "heal_party" },
  })[store]
  T.eq(f.exports.queue({ { "set_flag", "mod:prefix" }, row }), nil, "malformed " .. store .. " declined")
  T.eq(f.exports.get("mod:prefix"), false, "store failure prevents prefix")
  T.eq(f.game.save[store], false, "malformed store not overwritten")
end
do
  local f = fixture()
  f.game.save.party[1].stats = nil
  T.eq(
    f.exports.queue({ { "give_money", 1 }, { "heal_party" } }),
    nil,
    "malformed party record refused up front"
  )
  T.eq(f.wallet(), 100, "party refusal preserves wallet")
end
for _, version in ipairs({ "red", "gold", "firered", "emerald" }) do
  local f = fixture(version)
  f.game.save.money = 999990
  T.check(
    f.exports.queue({ { "give_money", 50 }, { "take_coins", 999 }, { "take_item", "POTION", 999 } }),
    "bounded state operations admitted"
  )
  f:drain()
  T.eq(f.wallet(), version == "red" and 1000040 or 999999, "native generation wallet cap")
  T.eq(f.game.save.coins, 0, "coin subtraction saturates at zero")
  T.eq(f.quantity(), 0, "item subtraction removes available quantity only")
  T.eq(#f.game.save.bagOrder, 0, "native bag order entry removed")
end
do
  local f = fixture()
  f.game.save.money = 9007199254740991
  T.eq(f.exports.queue({ { "set_flag", "mod:prefix" }, { "give_money", 1 } }), nil, "wallet overflow refused")
  T.eq(f.exports.get("mod:prefix"), false, "overflow refusal prevents prefix")
  T.eq(f.game.save.money, 9007199254740991, "overflow cannot round native wallet")
end
do
  local f = fixture()
  T.check(
    f.exports.queue({ { "check_dex_owned" }, { "jump_if_false", "end" }, { "set_flag", "mod:owned" } }),
    "default dex threshold admitted"
  )
  f:drain()
  T.eq(f.exports.get("mod:owned"), true, "default dex threshold is one")
end
do
  local f = fixture()
  T.check(f.exports.queue({ { "wait", 1 }, { "take_item", "POTION", 1 } }), "state action waits")
  f.game.save.inventory = false
  f:drain()
  T.eq(f.exports.result().success, false, "changed live store fails safely")
  T.eq(f.game.save.inventory, false, "changed malformed store not overwritten")
end
do
  local f = fixture()
  local rows = { { "wait", 1 }, { "give_money", 10 } }
  T.check(f.exports.queue(rows), "copy program admitted")
  rows[2][2] = 100
  f:drain()
  T.eq(f.wallet(), 110, "accepted scalar arguments detached")
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love =
  saved[2], saved[3], saved[4], saved[5], saved[6]
T.finish("Portable script state actions")
