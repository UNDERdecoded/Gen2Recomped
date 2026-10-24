-- Imported-data input, native queue and faint/replacement smoke. Isolated only.
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
  local e = assert(game.mods.exports.portable_field_residual, "install field residual example")
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
  game.save.options.ruleset = false
  game.save.options.textSpeed, game.save.options.animations = 1, false
  local world = game.overworld
  local function mon()
    local p = Pokemon.new(game.data, species, 30)
    p.hp, p.stats.hp, p.moves = 500, 500, { { id = tackle, pp = 10 } }
    return p
  end
  local function fresh(double)
    game.save.party = { mon() }
    local b = Battle.newWild(game, species, 30)
    b.enemy.mon.hp, b.enemy.mon.stats.hp = 500, 500
    b.enemy.mon.moves = { { id = tackle, pp = 10 } }
    b.enemy.curMoves = b.enemy.mon.moves
    if double then
      local second = Battle.newWild(game, species, 30)
      second.enemy.mon.hp, second.enemy.mon.stats.hp = 500, 500
      local p = mon()
      second.player.mon = p
      game.save.party[2] = p
      b.enemyParty = { b.enemy.mon, second.enemy.mon }
      b.double = true
      b:placeBattler(2, second.player)
      b:placeBattler(3, second.enemy)
      b:syncSides()
    end
    b.field.tokens = { { id = "probe", state = { intensity = 4 } } }
    b.rng = function(lo)
      return lo or 0
    end
    b.queue, b.phase, b.afterQueue, b.menuIndex = {}, "menu", "menu", 1
    b.introSlide, b.fx = 0, {}
    game.stack.states = { world, b }
    e.state.calls, e.state.faints, e.state.awards = 0, 0, 0
    e.state.requests, e.state.mode = {}, "none"
    return b
  end
  local function drain(b, settled)
    for _ = 1, 4000 do
      if settled and b.result then
        return
      end
      if not settled and b.phase == "menu" then
        return
      end
      U.tap(game, "a")
    end
    error("native field/faint result queue did not settle")
  end
  local b = fresh()
  e.state.requests = {
    { side = "player", amount = 3, message = "Player field damage" },
    { side = "enemy", amount = 7, message = "Enemy field damage" },
  }
  U.tap(game, "a")
  assert(b.phase == "moveSelect", "native FIGHT did not open move selection")
  U.tap(game, "a")
  drain(b)
  local ctx = assert(e.state.last)
  assert(e.state.calls == 1 and ctx.turn == 1, "real turn must dispatch field once")
  assert(b.player.mon.hp == ctx.battlers.player.hp - 3, "native turn player field HP")
  assert(b.enemy.mon.hp == ctx.battlers.enemy.hp - 7, "native turn enemy field HP")
  b = fresh()
  e.state.mode = "mutate"
  b:endOfTurn()
  b.phase = "messages"
  drain(b)
  assert(b.player.mon.hp == 500, "detached snapshot edit changed live HP")
  assert(b.field.tokens[1].state.intensity == 4, "detached token edit changed live field")
  for _, reverse in ipairs({ false, true }) do
    b = fresh()
    local p, n = { side = "player", amount = 99999 }, { side = "enemy", amount = 99999 }
    e.state.requests = reverse and { n, p } or { p, n }
    b:endOfTurn()
    b.phase = "messages"
    drain(b, true)
    assert(b.result == "lose", "native terminal field batch must lose")
    assert(e.state.awards == 0, "native terminal field batch must not award EXP")
    assert(e.state.faints == (V.generation() == 2 and 2 or 1), "native generation faint announcements")
    -- Stop at the in-battle result; never run finish/blackout/save processing.
  end
  if V.generation() == 3 then
    b = fresh(true)
    local reserve = mon()
    b.enemyParty[3] = reserve
    e.state.requests = { { side = "enemy", battlerId = 3, amount = 99999 } }
    b:endOfTurn()
    b.phase = "messages"
    drain(b)
    assert(b:battlerAt(3).mon == reserve, "native GBA field KO must fill empty flank")
    assert(e.state.faints == 1 and e.state.awards > 0, "native GBA flank faint/EXP")
    b = fresh(true)
    for id = 0, 3 do
      e.state.requests[#e.state.requests + 1] = {
        side = id % 2 == 0 and "player" or "enemy",
        battlerId = id,
        amount = 99999,
      }
    end
    b:endOfTurn()
    b.phase = "messages"
    drain(b, true)
    assert(
      b.result == "lose" and e.state.awards == 0 and e.state.faints == 2,
      "native GBA simultaneous double KO must have player loss authority"
    )
  end
  b = fresh()
  e.stop()
  b:endOfTurn()
  assert(e.state.calls == 0 and b.enemy.mon.hp == 500, "native unsubscribe")
  print("PORTABILITY_FIELD_RESIDUAL_PASS " .. V.get())
  love.event.quit(0)
end
