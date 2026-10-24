-- Bounded imported-data battle input/queue check. Use an isolated identity.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable legacy migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION"), "wrong imported cartridge")
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
  local e = assert(game.mods.exports.portable_enemy_pp, "install PP observer example")
  local Pokemon, Battle = require("src.pokemon.Pokemon"), require("src.battle.BattleState")
  local species, tackle
  for id, def in pairs(game.data.pokemon) do
    if def.name == "MEW" then
      species = id
      break
    end
  end
  for id, def in pairs(game.data.moves) do
    if def.name == "TACKLE" then
      tackle = id
      break
    end
  end
  assert(species and tackle, "native imported metadata missing")
  local previous = game.save.options.ruleset
  assert(
    previous == require("src.core.SaveData").optionsFor(V.get()).ruleset,
    "new save preserves persisted choice"
  )
  -- Existing explicit choices are intentionally preserved. Opt into AUTO only
  -- in memory for this disposable battle; do not write installation options.
  game.save.options.ruleset = false
  game.save.options.textSpeed, game.save.options.animations = 1, false
  local world = game.overworld
  local function fresh()
    local p = Pokemon.new(game.data, species, 30)
    p.hp, p.stats.hp, p.moves = 500, 500, { { id = tackle, pp = 10 } }
    game.save.party = { p }
    local b = Battle.newWild(game, species, 30)
    local move = { id = tackle, pp = 2 }
    b.enemy.mon.hp, b.enemy.mon.stats.hp = 500, 500
    b.enemy.mon.moves, b.enemy.curMoves = { move }, { move }
    b.rng = function(lo)
      return lo or 0
    end
    b.queue, b.phase, b.afterQueue, b.menuIndex = {}, "menu", "menu", 1
    game.stack.states = { world, b }
    return b, move
  end
  local b, move = fresh()
  local gen = V.generation()
  local expected = ({ "gen1_faithful", "gen2_finite_pp", "gen3_emerald" })[gen]
  assert(b.ruleset.name == expected, "native automatic ruleset")
  for turn = 1, 3 do
    local beforeHP = b.player.mon.hp
    U.tap(game, "a")
    assert(b.phase == "moveSelect", "native FIGHT input did not open move selection")
    U.tap(game, "a")
    for _ = 1, 1800 do
      if b.phase == "menu" then
        break
      end
      U.tap(game, "a")
    end
    assert(b.phase == "menu", "native result queue did not return to menu")
    local wanted = gen == 1 and 2 or math.max(0, 2 - turn)
    assert(move.pp == wanted, "native enemy PP after complete input/queue turn")
    local view = assert(e.read())
    assert(view.moves[1].id == "TACKLE" and view.moves[1].pp == wanted, "public observer PP")
    assert(b.player.mon.hp < beforeHP, "native enemy must still damage player after depletion")
    if turn == 3 and gen > 1 then
      assert(b:enemyAction().id == "STRUGGLE", "depleted native AI fallback")
    end
  end
  -- A deliberately selected legacy rule must still win on a new battle.
  game.save.options.ruleset = "gen1_faithful"
  b, move = fresh()
  assert(b.ruleset.name == "gen1_faithful", "explicit legacy choice lost")
  move.pp = 0
  assert(b:enemyAction().id == tackle, "explicit unlimited rule refuses dry move")
  b:performMove(b.enemy, b.player, move)
  assert(move.pp == 0, "explicit legacy PP changed")
  print("PORTABILITY_ENEMY_PP_PASS " .. V.get() .. " prior=" .. tostring(previous))
  love.event.quit(0)
end
