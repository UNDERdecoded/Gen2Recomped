-- Actual imported-data loader/read/freeze smoke; isolated identity only.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION"), "wrong imported game")
  local function check(stage)
    local e = assert(game.mods.exports.portable_ai_class_content, "install portable class example")
    local h, id = e.api.content.ai_classes, "PORTABLE_METADATA_CLASS"
    assert(
      e.state.writeDetached and e.state.readDetached and e.state.iterationDetached,
      "entry metadata snapshots"
    )
    local current = assert(h:get(id), "missing portable class")
    assert(current.item == "POTION" and current.uses == 2, "portable imported item reference")
    local raw = assert(game.data.ai_classes[id], "missing native class fold")
    local item = assert(game.data.items[raw.item], "native item target missing")
    assert(item.name == "POTION", "native class references actual imported Potion")
    local physical = raw.item
    current.item, current.uses = "UNKNOWN_ITEM", 99
    assert(
      raw.item == physical and raw.uses == 2 and h:get(id).item == "POTION",
      "read cannot alter runtime class"
    )
    local found
    for key, value in h:each() do
      if key == id then
        assert(value.item == "POTION", "portable class iteration")
        value.item = "UNKNOWN_ITEM"
        found = true
      end
    end
    assert(found and raw.item == physical, "iteration cannot alter runtime class")
    local ok, reason = pcall(function()
      h:patch(id, { item = "POTION" })
    end)
    assert(not ok and tostring(reason):find("frozen", 1, true), "runtime metadata writes stay frozen")
    print("PORTABILITY_AI_CLASS_CONTENT_CASE " .. V.get() .. " " .. stage)
  end
  check("title")
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
  U.wait(30)
  title.onNewGame()
  U.wait(60)
  assert(game.save and game.overworld, "native New Game missing")
  check("new-game")
  print("PORTABILITY_AI_CLASS_CONTENT_PASS " .. V.get())
  love.event.quit(0)
end
