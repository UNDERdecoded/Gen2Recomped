-- Imported native UI smoke in an isolated in-memory New Game.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION") and V.generation() == 3, "wrong imported version")
  local e = assert(game.mods.exports.portable_gba_menu_prose, "install public menu-prose example")
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
  game.stack.states = { world }
  local species
  for id, def in pairs(game.data.pokemon) do
    if def.name == "CHARMANDER" then
      species = id
      break
    end
  end
  assert(species, "imported species missing")
  game.save.party =
    { require("src.pokemon.Pokemon").new(game.data, species, 5, function(lo)
      return lo or 0
    end) }
  local Font, captured = require("src.render.Font"), {}
  local original = Font.draw
  Font.draw = function(text, ...)
    captured[text] = true
    return original(text, ...)
  end
  local party = require("src.ui.Gen3PartyMenu").new(game, {})
  game.stack:push(party)
  U.wait(15)
  assert(captured.MOD_FOOTER, "native party render did not draw separate cancel label")
  U.tap(game, "a")
  U.wait(12)
  assert(party.submenu and party.submenu[1].label == "MOD_SUMMARY", "native party actions ignored prose")
  assert(captured.MOD_SUMMARY and captured.MOD_CANCEL, "native party submenu did not render overrides")
  U.tap(game, "a")
  U.wait(12)
  assert(game.stack:top() ~= party, "translated SUMMARY did not open native summary")
  U.tap(game, "b")
  U.wait(10)
  assert(game.stack:top() == party, "native summary did not return to party")
  U.tap(game, "a")
  U.wait(4)
  local item
  for i, row in ipairs(party.submenu) do
    if row.action == "item" then
      item = i
    end
  end
  assert(item, "native ITEM action missing")
  party.subIndex = item
  U.tap(game, "a")
  U.wait(10)
  assert(
    party.submenu[1].label == "MOD_GIVE" and party.submenu[2].label == "MOD_TAKE",
    "native item actions ignored prose"
  )
  assert(captured.MOD_GIVE and captured.MOD_TAKE, "native item submenu did not draw prose")
  U.tap(game, "b")
  U.wait(4)
  assert(party.submenu == nil, "native submenu cancel changed")
  U.tap(game, "b")
  U.wait(6)
  assert(game.stack:top() == world, "native party did not close")
  if V.get() == "firered" then
    local potion
    for id, def in pairs(game.data.items) do
      if def.name == "POTION" then
        potion = id
        break
      end
    end
    assert(potion, "imported Potion missing")
    game.save.pcItems = { [potion] = 1 }
    local pc = require("src.ui.Gen3PlayerPC").new(game, {})
    game.stack:push(pc)
    U.tap(game, "a")
    U.wait(6) -- native ITEM STORAGE
    U.tap(game, "a")
    U.wait(10) -- native WITHDRAW ITEM
    local list = game.stack:top()
    assert(
      list.titleText and list:titleText() == "MOD_PC_TITLE" and list.nativeProse,
      "Player PC did not route native title label"
    )
    assert(captured.MOD_PC_TITLE and captured.MOD_FOOTER, "native Item-PC render missed title/cancel")
    U.tap(game, "a")
    U.wait(10)
    local submenu = game.stack:top()
    assert(submenu ~= list and submenu.entries, "native Item-PC submenu missing")
    local entries = submenu:entries()
    assert(
      entries[1].label == "MOD_PC_WITHDRAW" and entries[2].label == "MOD_PC_GIVE",
      "native Item-PC rows ignored prose"
    )
    assert(captured.MOD_PC_WITHDRAW and captured.MOD_PC_GIVE, "native Item-PC rows not rendered")
    U.tap(game, "down")
    U.tap(game, "down")
    U.tap(game, "a")
    U.wait(6)
    assert(
      game.stack:top() == list and list.transientWindow == nil,
      "translated CANCEL changed native action"
    )
    assert(game.save.pcItems[potion] == 1, "cancel changed inventory")
    U.tap(game, "b")
    U.wait(6)
    assert(game.stack:top() ~= list, "native Item-PC did not close")
  end
  Font.draw = original
  local ok, err = pcall(function()
    e.api.content.rom_text:override("gText_Withdraw", "LATE")
  end)
  assert(not ok and tostring(err):find("frozen", 1, true), "late public prose mutation accepted")
  print("PORTABILITY_GBA_MENU_PROSE_PASS " .. V.get())
  love.event.quit(0)
end
