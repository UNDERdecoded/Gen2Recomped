-- Driver for #169: poison status icon must appear AFTER move anim +
-- "was poisoned!" text, not during the "used POISONPOWDER!" announce.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local mon = Pokemon.new(game.data, "BULBASAUR", 12)
  mon.moves[1] = { id = "POISONPOWDER", pp = 20 }
  mon.moves[2] = { id = "TACKLE", pp = 20 }
  table.insert(game.save.party, 1, mon)
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  -- force hit + make the foe never act (skip second half of the turn)
  battle.rng = function(a, b) return a or 0 end
  battle.enemyAction = function() return nil end
  ow:pushBattle(battle)

  local function waitFor(cond, max)
    for _ = 1, max or 600 do
      if cond() then return true end
      U.wait(1)
    end
    return false
  end
  local function mashUntil(cond, max)
    for _ = 1, max or 80 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return false
  end

  mashUntil(function() return battle.phase == "menu" end)
  U.shot(game, DIR .. "/poison_0_menu.png")

  U.tap(game, "a"); U.wait(8) -- FIGHT
  U.tap(game, "a"); U.wait(2) -- POISONPOWDER

  -- announce: "BULBASAUR used POISONPOWDER!" -- no PSN on HUD yet
  waitFor(function()
    return battle.current and battle.current.text
      and battle.current.text:find("POISONPOWDER", 1, true)
  end, 120)
  U.shot(game, DIR .. "/poison_1_announce.png")
  U.log(("announce shownStatus=%s mon.status=%s"):format(
    tostring(battle.enemy.shownStatus), tostring(battle.enemy.mon.status)))

  -- mash through announce into the move anim / poisoned text
  local sawAnim, sawText = false, false
  for _ = 1, 200 do
    if battle.animPlaying or battle.animName == "POISONPOWDER" then
      if not sawAnim then
        sawAnim = true
        U.shot(game, DIR .. "/poison_2_anim.png")
        U.log(("anim shownStatus=%s"):format(tostring(battle.enemy.shownStatus)))
      end
    end
    if battle.current and battle.current.text
       and battle.current.text:find("poisoned", 1, true) then
      if not sawText then
        sawText = true
        U.shot(game, DIR .. "/poison_3_text.png")
        U.log(("text shownStatus=%s"):format(tostring(battle.enemy.shownStatus)))
      end
    end
    if battle.enemy.shownStatus == "PSN" and sawText then
      U.shot(game, DIR .. "/poison_4_icon.png")
      U.log("HUD PSN revealed after poisoned text")
      break
    end
    U.tap(game, "a")
    U.wait(2)
  end

  waitFor(function() return battle.phase == "menu" end, 200)
  U.shot(game, DIR .. "/poison_5_menu.png")
  U.log(("final shownStatus=%s"):format(tostring(battle.enemy.shownStatus)))
end
