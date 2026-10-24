-- Imported-data native HUD/GPU probe, without a normal SAVE action.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable legacy migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION"), "wrong cartridge")
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
  local e = assert(game.mods.exports.portable_caught_marker, "install caught marker example")
  local species
  for id, def in pairs(game.data.pokemon) do
    if def.name == "MEW" then
      species = id
      break
    end
  end
  assert(species, "imported Mew missing")
  local dex = game.save.pokedex
  dex.owned, dex.caught = dex.owned or {}, dex.caught or {}
  dex.owned[species], dex.caught[species] = true, true
  local mon = require("src.pokemon.Pokemon").new(game.data, species, 30)
  mon.hp, mon.stats.hp = 100, 100
  game.save.party = { mon }
  local b = require("src.battle.BattleState").newWild(game, species, 30)
  b.phase, b.frame, b.fx, b.shown = "contract", 0, {}, {}
  b.introBalls, b.showPlayerBack, b.showEnemyTrainer, b.enemySendingOut = false, true, false, false
  game.stack.states = { game.overworld, b }
  local g, captured = love.graphics
  local function capture(mode)
    e.state.mode = mode
    -- A new native presented Pokémon refreshes GBA's cached healthbox verdict.
    b.enemy.mon = require("src.mods.Merge").deepCopy(b.enemy.mon)
    local canvas = g.newCanvas(V.isGen3() and 240 or 160, V.isGen3() and 160 or 144)
    g.push("all")
    g.setCanvas(canvas)
    g.clear(1, 1, 1, 1)
    g.setShader()
    b:drawHUDs(0)
    g.pop()
    local data = canvas:newImageData()
    canvas:release()
    captured = data
    return data:getString()
  end
  local hidden = capture("hide")
  local shown = capture("show")
  assert(hidden ~= shown, "native marker must change actual HUD pixels")
  local shot = os.getenv("POKEPORT_CAUGHT_SHOT")
  if shot then
    local f = assert(io.open(shot, "wb"))
    f:write(captured:encode("png"):getString())
    f:close()
  end
  assert(capture("nil") == hidden and capture("zero") == hidden, "strict native boolean verdict")
  assert(capture("native") == (V.generation() == 1 and hidden or shown), "generation-native marker default")
  dex.owned[species], dex.caught[species] = nil, nil
  assert(capture("show") == hidden, "native ownership gate precedes forced show")
  dex.owned[species], dex.caught[species] = true, true
  b.kind = "trainer"
  assert(capture("show") == hidden, "native trainer exclusion")
  b.kind = "wild"
  if V.isGen3() then
    b.enemy.shownStatus = "PSN"
    local calls = e.state.calls
    local statusShown = capture("show")
    assert(capture("hide") == statusShown and e.state.calls == calls, "native GBA status takes precedence")
    b.enemy.shownStatus = nil
  end
  local off = e.api.hooks:wrap("battle.status_hud_visible", function()
    return false
  end)
  local calls = e.state.calls
  capture("show")
  assert(e.state.calls == calls, "hidden native HUD must not query marker")
  off()
  e.stop()
  local calls = e.state.calls
  assert(capture("show") == (V.generation() == 1 and hidden or shown), "unsubscribe restores native draw")
  assert(e.state.calls == calls, "unsubscribe removes callback")
  print("PORTABILITY_CAUGHT_MARKER_PASS " .. V.get())
  love.event.quit(0)
end
