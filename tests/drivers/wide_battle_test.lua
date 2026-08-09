-- Driver: BATTLE LAYOUT = WIDE.  Opens a wild battle on the 304x144
-- surface, captures the command screen, the 2x2 move menu and a player-side
-- send-out POOF, and checks the surface is handed back on the way out.
--   POKEPORT_DRIVER=tests/drivers/wide_battle_test.lua \
--     POKEPORT_IDENTITY=wide POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local Renderer = require("src.render.Renderer")

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.options.battleLayout = "wide"
  -- MEW's back pic is a large 2x sprite: it catches a side region drawn
  -- twice, which would leak detached pieces of it into the far right.
  game.save.party = { Pokemon.new(game.data, "MEW", 100) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(60)

  local battle = BattleState.newWild(game, "PIDGEY", 3, { onFinish = function() end })
  game.overworld:pushBattle(battle)
  U.wait(360)

  check("the battle is on top", getmetatable(game.stack:top()) == BattleState)
  check("the battle asked for the 304x144 surface",
        Renderer.uiWidth == 304 and Renderer.uiHeight == 144)

  battle.introSlide = 0
  battle.introBalls = nil
  battle.showEnemyTrainer = false
  battle.showPlayerBack = false
  battle.enemySendingOut = false
  battle.sendingOut = false
  battle.phase = "menu"
  battle.menuIndex = 1
  U.wait(2)
  check("command screenshot", U.shot(game, DIR .. "/wide_command.png"))

  battle.phase = "moveSelect"
  battle.moveIndex = 1
  if #battle.player.curMoves >= 2 then
    U.tap(game, "right")
    U.wait(2)
    check("RIGHT crosses the move grid", battle.moveIndex == 2)
  end
  U.wait(2)
  check("move menu screenshot", U.shot(game, DIR .. "/wide_moves.png"))

  -- Freeze a player-side POOF on a populated frame: it must composite once,
  -- at the player anchor, and never repeat on the right.
  battle.phase = "messages"
  battle.current = nil
  battle.animPlayer:start("POOF_ANIM", false)
  battle.animPlayer.stepIndex = 3
  battle.animPlaying = true
  check("send-out POOF screenshot", U.shot(game, DIR .. "/wide_poof.png"))
  battle.animPlaying = false

  game.stack:pop()
  -- a fast driver resumes several logic steps per rendered frame; leave
  -- enough yields for the next Game:draw to resolve the overworld surface
  U.wait(12)
  check("leaving the battle restores the Game Boy surface",
        Renderer.uiWidth == 160 and Renderer.uiHeight == 144)

  U.log(failures == 0 and "WIDE_BATTLE_PASS" or "WIDE_BATTLE_FAIL",
        ("surface=%dx%d"):format(Renderer.uiWidth, Renderer.uiHeight))
  love.event.quit(failures == 0 and 0 or 1)
end
