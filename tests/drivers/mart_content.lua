-- Imported Gold, actual ROM-IR lowering, script coroutine and UI input.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == "gold", "this imported-data smoke uses Gold")
  local title
  for _ = 1, 120 do
    local top = game.stack:top()
    if top and type(top.onNewGame) == "function" then
      title = top
      break
    end
    U.tap(game, "start")
    U.wait(5)
  end
  assert(title, "native title missing")
  title.onNewGame()
  U.wait(60)
  local world = assert(game.overworld, "native New Game missing")
  local e = assert(game.mods.exports.portable_mart_content, "install public mart example")
  assert(e.available, "public mart registry unavailable")
  local keys = {}
  for id, def in pairs(game.data.items) do
    if def.name == "ULTRA BALL" or def.name == "ULTRA_BALL" then
      keys.ball = id
    end
    if def.name == "NUGGET" then
      keys.nugget = id
    end
  end
  assert(keys.ball and keys.nugget, "imported item names missing")
  assert(game.data.map_scripts.marts[0][1] == keys.ball, "public ID did not reach native stock")
  local unit = game.data.items[keys.ball].price
  local Runner, VM = require("src.script.ScriptRunner"), require("src.script.Gen2ScriptVM")
  require("src.script.Gen2Commands")
  local function run(kind)
    game.stack.states = { world }
    local runner = Runner.new(game, world)
    world.runner = runner
    local scripts = game.data.map_scripts.scripts
    local label = "__portable_mart_" .. kind
    scripts[label] = { { "pokemart", kind, 0 }, { "end" } }
    local rows = assert(VM.compile(game.data, label))
    runner:run(rows)
    assert(runner:isRunning(), "native shop failed to yield")
    return runner
  end
  local function tap(key)
    U.tap(game, key)
    U.wait(20)
  end
  game.save.money, game.save.inventory, game.save.bagOrder, game.save.bargainShop = 10000, {}, {}, {}
  local runner = run(0)
  for _ = 1, 4 do
    tap("a")
  end
  assert(game.save.inventory[keys.ball] == 1, "native ordinary buy did not grant item")
  assert(game.save.money == 10000 - unit, "ordinary buy did not use native item price")
  tap("b")
  tap("b")
  assert(not runner:isRunning(), "ordinary close did not resume real script coroutine")
  local balance = game.save.money
  runner = run(2)
  for _ = 1, 3 do
    tap("a")
  end
  assert(game.save.inventory[keys.nugget] == 1, "native bargain did not grant item")
  assert(game.save.money == balance - 500, "native bargain ignored explicit price")
  assert(game.save.bargainShop[keys.nugget], "native bargain did not record sold item")
  tap("a")
  assert(
    game.save.money == balance - 500 and game.save.inventory[keys.nugget] == 1,
    "sold-out item bought twice"
  )
  tap("b")
  assert(not runner:isRunning(), "bargain close did not resume real script coroutine")
  runner = run(2)
  tap("a")
  assert(
    game.save.money == balance - 500 and game.save.inventory[keys.nugget] == 1,
    "reopened bargain lost sold state"
  )
  tap("b")
  assert(not runner:isRunning(), "reopened bargain remained blocked")
  local row = e.api.content.marts:get("0")
  row[1] = "CORRUPTED"
  assert(e.api.content.marts:get("0")[1] == "ULTRA_BALL", "public read was not detached")
  assert(not pcall(function()
    e.api.content.marts:patch("0", {})
  end), "late public write was not frozen")
  print("PORTABILITY_MART_CONTENT_PASS gold")
  love.event.quit(0)
end
