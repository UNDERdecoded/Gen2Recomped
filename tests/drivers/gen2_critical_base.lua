-- Actual imported-data FIGHT/move/controller smoke in an isolated identity.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION") and V.isGen2(), "wrong imported game")
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
  local e = assert(game.mods.exports.portable_critical_order, "install critical example")
  assert(e.available and game.save and game.overworld, "native mod/New Game missing")
  local P, Battle = require("src.pokemon.Pokemon"), require("src.battle.BattleState")
  local function named(registry, name)
    for id, row in pairs(registry) do
      if row.name == name then
        return id
      end
    end
    error("missing imported record " .. name)
  end
  local species, tackle = named(game.data.pokemon, "MEW"), named(game.data.moves, "TACKLE")
  assert(game.data.moves[tackle].power == 35, "native cartridge Tackle power")
  local function mon(name, level)
    local p = P.new(game.data, species, level or 30)
    p.nickname, p.hp = name, 400
    p.stats = { hp = 400, attack = 50, defense = 50, speed = 50, special = 50, spatk = 50, spdef = 50 }
    p.moves = { { id = tackle, pp = 10 } }
    return p
  end
  game.save.options.ruleset = false
  game.save.options.textSpeed, game.save.options.animations = 1, false
  for _, spec in ipairs({
    { level = 29, critical = false, types = { "NORMAL" }, want = 9 },
    { level = 29, critical = true, types = { "NORMAL" }, want = 17 },
    { level = 29, critical = true, stab = true, types = { "NORMAL" }, want = 25 },
    { level = 1, critical = true, types = { "NORMAL" }, want = 3 },
    { level = 3, critical = true, types = { "NORMAL" }, want = 5 },
    { level = 30, critical = true, types = { "NORMAL" }, want = 17 },
  }) do
    game.save.party = { mon("PLAYER", spec.level) }
    local old = game.data.trainers.PORTABLE_CRITICAL
    game.data.trainers.PORTABLE_CRITICAL = {
      name = "PORTABLE",
      items = {},
      parties = { { { prebuilt = mon("ENEMY") } } },
    }
    local b = Battle.newTrainer(game, "PORTABLE_CRITICAL", 1)
    game.data.trainers.PORTABLE_CRITICAL = old
    b:syncSides()
    b.player.curTypes, b.enemy.curTypes = { spec.stab and "NORMAL" or "FIRE" }, spec.types
    b.player.curStats.speed = 80
    b.rng = function(lo)
      return lo or 0
    end
    b.queue, b.phase, b.afterQueue, b.menuIndex = {}, "menu", "menu", 1
    b.introSlide, b.fx = 0, {}
    game.stack.states = { game.overworld, b }
    e.state.critical, e.state.calls = spec.critical, 0
    U.tap(game, "a")
    assert(b.phase == "moveSelect", "native FIGHT opens moves")
    U.tap(game, "a")
    for _ = 1, 4000 do
      if b.phase == "menu" then
        break
      end
      U.tap(game, "a")
    end
    assert(b.phase == "menu", "native turn did not settle")
    assert(b.enemy.mon.hp == 400 - spec.want, "native Gen-2 critical-base rounding")
    assert(b.player.curMoves[1].pp == 9 and b.enemy.curMoves[1].pp == 9, "native PP accounting")
    assert(e.state.calls == 2, "both native critical decisions use the public consumer")
    print(
      "PORTABILITY_GEN2_CRITICAL_CASE "
        .. V.get()
        .. " "
        .. spec.level
        .. " "
        .. tostring(spec.critical)
        .. " "
        .. tostring(spec.stab or false)
        .. " "
        .. table.concat(spec.types, "/")
        .. " "
        .. spec.want
    )
  end
  print("PORTABILITY_GEN2_CRITICAL_PASS " .. V.get())
  love.event.quit(0)
end
