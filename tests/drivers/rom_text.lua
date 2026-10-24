-- Bounded imported-data proof: native prose reader, storage UI and VM isolation.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION"), "wrong imported version")
  local e = assert(game.mods.exports.portable_rom_text, "install public prose example")
  assert(e.available, "native prose registry unavailable")
  local title
  for _ = 1, 120 do
    local top = game.stack:top()
    if top and type(top.onNewGame) == "function" then
      title = top
      break
    end
    U.tap(game, "start")
    U.wait(4)
  end
  assert(title, "native title missing")
  title:onNewGame()
  local world = assert(game.overworld, "native New Game missing")
  game.save.player.name = "PROBE"
  game.stack.states = { world }
  if V.generation() == 2 then
    local b = setmetatable({ data = game.data }, { __index = require("src.battle.BattleState") })
    local value = b:romText("_WokeUpText", "%s fallback", "PROBE")
    assert(value == "PROBE PROSE{DONE}", "native battle prose helper ignored override")
    assert(game.data.text._WokeUpText == e.after, "legacy native label reader missed projection")
    local box = require("src.render.TextBox").new(game, value)
    game.stack:push(box)
    assert(table.concat(box.pages[1], "|") == "PROBE PROSE", "native box printed prose end marker")
    U.wait(10)
    for _ = 1, 50 do
      if game.stack:top() == world then
        break
      end
      U.tap(game, "a")
      U.wait(3)
    end
    assert(game.stack:top() == world, "native prose box did not close")
    assert(
      e.scriptBefore == nil and e.scriptAfter == "PRIVATE SCRIPT",
      "same-label registry isolation failed"
    )
    local runner = require("src.script.ScriptRunner").new(game, world)
    runner:run({ { "show_text", "_WokeUpText" } })
    local scriptBox = assert(game.stack:top())
    assert(table.concat(scriptBox.pages[1], "|") == "PRIVATE SCRIPT", "native VM used engine prose")
    U.wait(10)
    for _ = 1, 50 do
      if game.stack:top() == world then
        break
      end
      U.tap(game, "a")
      U.wait(3)
    end
    assert(game.stack:top() == world and not runner:isRunning(), "native private script did not resume")
  else
    assert(V.generation() == 3, "driver requires imported Gen 2/3")
    local menu = require("src.ui.Gen3StorageMenu").new(game, {})
    game.stack:push(menu)
    for i = 1, 5 do
      assert(menu.items[i].label == "MOD_ROW_" .. i, "native storage label binding missing")
      assert(menu.items[i].describe == "MOD_DESC_" .. i, "native storage description binding missing")
    end
    U.wait(10)
    U.tap(game, "b")
    U.wait(6)
    assert(game.stack:top() == world, "native storage menu did not close")
    local again = require("src.ui.Gen3StorageMenu").new(game, {})
    assert(again.items[1].label == "MOD_ROW_1", "native reopened storage lost prose overlay")
    game.stack:push(again)
    U.wait(6)
    U.tap(game, "b")
    U.wait(6)
    assert(game.stack:top() == world, "reopened native storage menu did not close")
  end
  local ok, err = pcall(function()
    e.api.content.rom_text:override("_WokeUpText", "LATE")
  end)
  assert(not ok and tostring(err):find("frozen", 1, true), "late public prose write was not frozen")
  print("PORTABILITY_ROM_TEXT_PASS " .. V.get())
  love.event.quit(0)
end
