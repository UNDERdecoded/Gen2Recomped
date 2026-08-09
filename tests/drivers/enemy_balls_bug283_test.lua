-- Driver: the foe's party ball row between a KO and the next send-out (#283).
-- pokered ReplaceFaintedEnemyMon (engine/battle/core.asm:892-896) callfars
-- DrawEnemyPokeballs before it falls into EnemySendOut; the port never did.
--   POKEPORT_DRIVER=tests/drivers/enemy_balls_bug283_test.lua \
--     POKEPORT_IDENTITY=bug283 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .   (never under POKEPORT_SPEED: audio-timed)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- roster 1 is RATTATA 11 / EKANS 11 in both versions: two slots, so the row
  -- has a KO'd ball, a live one and four empties to tell apart.
  local OPP, ROSTER = "OPP_YOUNGSTER", 1

  -- ---- preconditions ------------------------------------------------------
  -- Each of these fails silently as "no ball row on screen", same as the bug.

  check("trainer class " .. OPP .. " is in the data",
        game.data.trainers ~= nil and game.data.trainers[OPP] ~= nil)

  -- drawBallRow bails out silently when the sheet will not load, and the
  -- underline comes off the $73/$74/$76/$78 HUD glyph pages
  local ballSheet = love.filesystem.getInfo("assets/generated/battle/balls.png")
  check("assets/generated/battle/balls.png is in the cache", ballSheet ~= nil)
  local okImg = pcall(love.graphics.newImage, "assets/generated/battle/balls.png")
  check("the ball sheet actually decodes", okImg)
  check("BattleState:drawBallRow exists",
        type(BattleState.drawBallRow) == "function")
  local HudTiles = require("src.render.HudTiles")
  check("HudTiles.tile is available for the underline",
        type(HudTiles.tile) == "function")

  -- SHIFT keeps the row up through the whole YES/NO prompt (showEnemyBalls is
  -- not cleared until the send-out act); SET only flashes it for 16 frames.
  game.save.options = game.save.options or {}
  game.save.options.battleStyle = "shift"
  game.save.player.name = "bryan"
  -- two party slots: SHIFT only offers the switch when wPartyCount > 1
  game.save.party = {
    Pokemon.new(game.data, "MEWTWO", 70),
    Pokemon.new(game.data, "CHARIZARD", 50),
  }
  check("a one-shot lead is in the party", game.save.party[1] ~= nil)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)
  local ow = game.overworld
  check("overworld is up to push the battle from", ow ~= nil)

  local ok, battle = pcall(BattleState.newTrainer, game, OPP, ROSTER)
  check("trainer battle constructed", ok and battle ~= nil)
  if not ok then
    U.log("could not start", OPP, "->", tostring(battle))
    while true do coroutine.yield() end
  end
  check("the foe has at least two mons to swap between", #battle.enemyParty >= 2)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  -- tap A until cond(), polling every frame so a one-frame window is caught
  local function tapUntil(cond, taps, gap)
    for _ = 1, (taps or 60) do
      if cond() then return true end
      U.tap(game, "a")
      for _ = 1, (gap or 6) do
        if cond() then return true end
        U.wait(1)
      end
    end
    return cond()
  end

  check("reached the FIGHT/PKMN/ITEM/RUN menu",
        tapUntil(function() return battle.phase == "menu" end, 60))

  -- FIGHT, then the first move: L70 MEWTWO one-shots a L11 RATTATA, so the KO
  -- is the real sequence and not a poked hp value.
  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "a")
  U.wait(10)

  -- Stop the instant showEnemyBalls goes up: that flag is raised exactly where
  -- ReplaceFaintedEnemyMon calls DrawEnemyPokeballs.
  local reached = tapUntil(function() return battle.showEnemyBalls == true end,
                           90, 4)
  check("the foe's first mon was KO'd and the ball row went up (#283)", reached)
  check("the KO'd slot really is fainted",
        battle.enemyParty[1] ~= nil and battle.enemyParty[1].hp <= 0)
  check("a live reserve is still in the row",
        battle.enemyParty[2] ~= nil and battle.enemyParty[2].hp > 0)

  if reached then
    check("row screenshot reached disk",
          U.shot(game, DIR .. "/bug283_balls_after_ko.png"))
    U.log("captured", DIR .. "/bug283_balls_after_ko.png")
    -- a few more presses put the SHIFT prompt on top of the still-visible row
    tapUntil(function() return battle.showEnemyBalls ~= true end, 3, 20)
    check("row screenshot during the SHIFT prompt reached disk",
          U.shot(game, DIR .. "/bug283_balls_with_prompt.png"))
    U.log("captured", DIR .. "/bug283_balls_with_prompt.png")
    U.log("showEnemyBalls is still up at hand-off:",
          tostring(battle.showEnemyBalls))
  end

  -- ---- hand off -----------------------------------------------------------
  U.log("The foe's first mon is KO'd and we are paused before the send-out.")
  U.log("Top left should carry six small Poke Balls running right to left from")
  U.log("(64,16) on a HUD rule: one crossed out, one solid, four empty.")
  U.log("#283 was that corner empty. Press A, the row clears on the send-out.")

  while true do
    coroutine.yield()
  end
end
