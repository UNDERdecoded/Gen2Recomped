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
  local e = assert(game.mods.exports.portable_held_content, "install held-definition example")
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
  assert(V.generation() == 2, "Gen-2 held definitions only")
  assert(e.state.available, "public held definitions unavailable")
  local held = e.api.content.held_items
  local record = assert(held:get("LEFTOVERS"))
  assert(record.heldEffect == "HELD_BERRY" and record.heldParameter == 7, "public definition missing")
  local b = fresh(100)
  local lost = 0
  local off = e.api.events:on("battle.damage_dealt", function(ctx)
    if ctx.target.mon.nickname == "PLAYER" then
      lost = lost + ctx.damage
    end
  end)
  U.tap(game, "a")
  assert(b.phase == "moveSelect", "native FIGHT missing")
  U.tap(game, "a")
  drain(b)
  off()
  assert(b.turnCount == 1 and lost > 0, "actual native turn and opponent damage missing")
  assert(b.player.mon.hp == 100 - lost + 7, "native registered definition must heal exactly seven")
  assert(not b.player.mon.item, "native registered Berry must consume actual held item")
  record.heldParameter = 222
  assert(held:get("LEFTOVERS").heldParameter == 7, "unified definition read must be detached")
  local ok = pcall(function()
    held:patch("LEFTOVERS", { heldParameter = 9 })
  end)
  assert(not ok, "native content must remain frozen")
  print("PORTABILITY_HELD_CONTENT_PASS " .. V.get())
  love.event.quit(0)
end
