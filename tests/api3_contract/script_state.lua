local M = {}
function M.fixture(root, backend, version, modId)
  local codeRoot = debug.getinfo(1, "S").source:sub(2):match("^(.*)/script_state%.lua$")
  local f = dofile(codeRoot .. "/script_flags.lua").fixture(root, backend, version, modId or "script_state")
  local save, data = f.game.save, f.game.data
  save.money, save.coins = 100, 50
  save.inventory, save.bagOrder = { POTION = 3 }, { "POTION" }
  save.pokedex = { seen = {}, owned = { MEW = true } }
  save.party =
    { { species = "MEW", hp = 1, status = "PSN", stats = { hp = 20 }, moves = { { id = "POUND", pp = 1 } } } }
  f.pp = function()
    return save.party[1].moves[1].pp
  end
  f.seen = function()
    return save.pokedex.seen.MEW == true
  end
  f.quantity = function()
    return save.inventory.POTION or 0
  end
  f.wallet = function()
    return save.money, save.coins
  end
  if backend == "gen1" and f.gen == 1 then
    require("src.core.Data").moves = data.moves -- Native heal uses the active data singleton.
  elseif backend == "gen1" and f.gen == 2 then
    f.ow.game = f.game
    save.player = { money = 100, coins = 50 }
    local World = require("src.world.gen2.World")
    f.ow.money, f.ow.setMoney = World.money, World.setMoney
    f.ow.coins, f.ow.setCoins = World.coins, World.setCoins
    f.ow.healParty = World.healParty
    save.party[1].maxHp = 20
    f.wallet = function()
      return save.player.money, save.player.coins
    end
  elseif backend == "gen1" and f.gen == 3 then
    local pokemon = require("src.core.game3.pokemon")
    for key, value in pairs(data.gen3Pokemon) do
      pokemon[key] = value
    end
    pokemon._byName = { MEW = 151 }
    require("src.core.game3.items_data").installPack({ items = data.gen3Items._byId })
    local Bag = require("src.core.game3.bag")
    save.bag = Bag.new()
    save.bag.pockets.ITEMS = { { id = 13, qty = 3 } }
    save.dex = { seen = {}, caught = { [151] = true }, owned = { [151] = true } }
    save.party =
      { { species = 151, hp = 1, maxHp = 20, status = 8, moves = { 1 }, pp = { 1 }, maxPp = { 35 } } }
    f.pp = function()
      return save.party[1].pp[1]
    end
    f.seen = function()
      return require("src.core.game3.dex").isSeen(save.dex, 151)
    end
    f.quantity = function()
      return Bag.get(save.bag, 13)
    end
  end
  return f
end
function M.run(root, backend, version)
  local f = M.fixture(root, backend, version)
  assert(f.exports.queue({
    { "give_money", 50 },
    { "take_money", 20 },
    { "check_money", 130 },
    { "jump_if_false", "failed" },
    { "take_coins", 12 },
    { "check_item", "POTION" },
    { "jump_if_false", "failed" },
    { "take_item", "POTION", 2 },
    { "check_dex_owned", 1 },
    { "jump_if_false", "failed" },
    { "mark_seen", "MEW" },
    { "heal_party" },
    { "set_flag", "mod:passed" },
    { "jump", "end" },
    { "label", "failed" },
    { "set_flag", "mod:failed" },
  }))
  f:drain()
  assert(f.exports.result().success == true)
  assert(f.exports.get("mod:passed") == true and f.exports.get("mod:failed") == false)
  local money, coins = f.wallet()
  local report = {
    money = money,
    coins = coins,
    items = f.quantity(),
    hp = f.game.save.party[1].hp,
    pp = f.pp(),
    seen = f.seen(),
  }
  assert(
    money == 130
      and coins == 38
      and report.items == 1
      and report.hp == 20
      and report.pp == 35
      and report.seen == true
  )
  f = M.fixture(root, backend, version)
  local value, why = f.exports.queue({ { "give_money", 1 }, { "take_item", "NO_SUCH_ITEM" } })
  assert(value == nil and type(why) == "string")
  assert(f.wallet() == 100 and f.quantity() == 3 and f.exports.result().done == 0)
  report.preflight = true
  print("API3_CONTRACT " .. require("src.link.Json").encode(report))
  return report
end
return M
