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
  local species, tackle, leftovers
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
  for id, def in pairs(game.data.items) do
    if def.name == "LEFTOVERS" then
      leftovers = id
      break
    end
  end
  assert(species and tackle and leftovers, "imported native metadata missing")
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
  for _, mode in ipairs({ "suppress", "override" }) do
    local b = fresh(240)
    e.state.mode, e.state.trigger, e.state.holder = mode, "residual", "PLAYER"
    e.state.effect, e.state.parameter = "HELD_BERRY", 7
    local lost = 0
    local off = e.api.events:on("battle.damage_dealt", function(ctx)
      if ctx.target.mon.nickname == "PLAYER" then lost = lost + ctx.damage end
    end)
    U.tap(game, "a")
    assert(b.phase == "moveSelect", "native FIGHT did not open move selection")
    U.tap(game, "a")
    drain(b)
    off()
    local ctx = assert(e.state.selected, "native player's held read missing")
    assert(ctx.mon.species == "MEW" and ctx.item == "LEFTOVERS", "portable imported held IDs")
    assert(
      b.player.mon.hp == 240 - lost + (mode == "override" and 7 or 0),
      "native input/HP follows held decision"
    )
    assert((b.player.mon.item ~= nil) == (mode ~= "override"), "native held consumption")
  end
  local b = fresh()
  b:endOfTurn()
  b.phase = "messages"
  drain(b)
  assert(b.player.mon.hp == 331 and b.player.mon.item == leftovers, "native delegated Leftovers")
  b = fresh()
  b.enemy.mon.hp = 1
  e.state.mode, e.state.trigger, e.state.holder = "override", "endure", "ENEMY"
  e.state.effect, e.state.parameter = "HELD_FOCUS_BAND", 256
  b:performMove(b.player, b.enemy, b.player.mon.moves[1])
  b.phase = "messages"
  drain(b)
  assert(b.enemy.mon.hp == 1 and e.state.seen.endure, "native lethal hit honors held endurance")
  if V.generation() == 3 then
    b = fresh()
    b.player.stages.attack = -2
    e.state.mode, e.state.trigger, e.state.holder = "override", "check", "PLAYER"
    e.state.effect = "HELD_RESTORE_STATS"
    require("src.battle.HeldItems").onEntry(b, b.player)
    b.phase = "messages"
    drain(b)
    assert(b.player.stages.attack == 0 and b.player.mon.item == nil, "native entry White Herb substitution")
    b = fresh()
    e.state.mode, e.state.trigger, e.state.holder = "override", "run", "PLAYER"
    e.state.effect = "HELD_ESCAPE"
    b.menuIndex = 4
    U.tap(game, "a")
    assert(b.result == "run" and e.state.seen.run, "native RUN menu uses public held escape")
    -- Stop at the in-battle result before finish/afterBattle/save processing.
  end
  b = fresh()
  e.stop()
  b:endOfTurn()
  assert(e.state.calls == 0 and b.player.mon.hp == 331, "native held unsubscribe")
  print("PORTABILITY_HELD_ITEM_PASS " .. V.get())
  love.event.quit(0)
end
