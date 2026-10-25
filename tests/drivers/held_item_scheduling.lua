-- Imported-data native input/held-effect/result-queue smoke. Isolated only.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
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
  local e = assert(game.mods.exports.portable_held_item, "install held-item example")
  local P, Battle = require("src.pokemon.Pokemon"), require("src.battle.BattleState")
  local species, tackle, leftovers, splash
  for id, def in pairs(game.data.pokemon) do
    if def.name == "MEW" then
      species = id
      break
    end
  end
  for id, def in pairs(game.data.moves) do
    if def.name == "TACKLE" then
      tackle = id
    end
    if def.name == "SPLASH" then
      splash = id
    end
  end
  for id, def in pairs(game.data.items) do
    if def.name == "LEFTOVERS" then
      leftovers = id
      break
    end
  end
  assert(species and tackle and leftovers and splash, "imported native metadata missing")
  game.save.options.ruleset = false
  game.save.options.textSpeed, game.save.options.animations = 1, false
  local world = game.overworld
  local function fresh(hp)
    local p = P.new(game.data, species, 30)
    p.hp, p.stats.hp, p.nickname, p.item = hp or 300, 500, "PLAYER", leftovers
    p.moves = { { id = tackle, pp = 10 } }
    game.save.party = { p }
    local b = Battle.newWild(game, species, 30)
    b.enemy.mon.hp, b.enemy.mon.stats.hp, b.enemy.mon.nickname = 500, 500, "ENEMY"
    b.enemy.mon.item, b.enemy.mon.heldItem = leftovers, nil
    b.enemy.mon.moves = { { id = tackle, pp = 10 } }
    b.enemy.curMoves = b.enemy.mon.moves
    b.rng = function(lo)
      return lo or 0
    end
    b.queue, b.phase, b.afterQueue, b.menuIndex = {}, "menu", "menu", 1
    b.introSlide, b.fx = 0, {}
    game.stack.states = { world, b }
    e.state.mode, e.state.trigger, e.state.holder, e.state.requiresItem = "delegate", nil, nil, true
    e.state.calls, e.state.seen, e.state.views, e.state.selected = 0, {}, {}, nil
    return b
  end
  local function drain(b)
    for _ = 1, 4000 do
      if b.phase == "menu" then
        return
      end
      U.tap(game, "a")
    end
    error("native held-item result queue did not settle")
  end
  assert(V.generation() == 3, "GBA scheduling smoke only")
  local b = fresh(100)
  b.player.mon.item, b.enemy.mon.item = nil, nil
  b.enemy.mon.moves = { { id = splash, pp = 10 } }
  b.enemy.curMoves = b.enemy.mon.moves
  e.state.mode, e.state.trigger, e.state.holder = "override", "residual", "PLAYER"
  e.state.effect, e.state.parameter, e.state.requiresItem = "HELD_BERRY", 7, false
  U.tap(game, "a")
  assert(b.phase == "moveSelect", "native FIGHT missing")
  U.tap(game, "a")
  drain(b)
  assert(b.turnCount == 1, "exactly one native turn")
  -- Four scans after each action; normal turn check and four post-turn scans.
  assert(b.player.mon.hp == 191, "native action/residual grants must heal 13*7")
  assert(e.state.seen.residual >= 13, "native held reads missing")

  b = fresh(20)
  b.player.mon.status = "PSN"
  e.state.mode, e.state.trigger, e.state.holder = "override", "residual", "PLAYER"
  e.state.effect, e.state.parameter = "HELD_HEAL_POISON", 0
  b:endOfTurn()
  b.phase = "messages"
  drain(b)
  assert(b.player.mon.hp == 20 and not b.player.mon.status, "cure must precede lethal poison")
  assert(not b.player.faintQueued and not b.result, "cured holder must remain in battle")
  assert(not b.player.mon.item, "native item consumed")

  b = fresh(100)
  b.player.mon.item, b.enemy.mon.item = nil, nil
  e.stop()
  b:endOfTurn()
  assert(b.player.mon.hp == 100 and e.state.calls == 0, "unsubscribe restores native empty hands")
  print("PORTABILITY_HELD_ITEM_SCHEDULING_PASS " .. V.get())
  love.event.quit(0)
end
