-- Driver: reproduce #224 - "Level up health bar inches down".
--
-- On a level-up during battle, Gen 1 (engine/battle/experience.asm) raises
-- the mon's current HP by (newMaxHP - oldMaxHP) and redraws the active
-- battler's HP bar UP to reflect the higher current HP.  Our data layer is
-- correct (Experience.lua:84 applies the current-HP delta), but the on-screen
-- numerator - the battler's shownHP (the value the HUD bar/number use) - was
-- never advanced on level-up, while the denominator (mon.stats.hp) jumped
-- instantly.  So the drawn fill FRACTION fell (e.g. 8/20 -> 8/22) instead of
-- rising to 10/22.
--
-- Setup: a SQUIRTLE at L5 with 8/oldMax HP and exp one point below the level-6
-- threshold; a single wild KO crosses it.  The driver asserts the player HP
-- bar's shownHP rises to the new current HP DURING the level-up messages
-- (before the menu-phase safety net at BattleState.lua:1099 would mask it).
-- Fails on the buggy build (shownHP stuck at 8); passes once fixed.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")

  -- deterministic mon: pin DVs to the max so the HP numbers are identical
  -- across the before/after runs (Stats.randomDVs consumes rng(0,15))
  local squirtle = Pokemon.new(game.data, "SQUIRTLE", 5, function(_, b) return b end)
  local def = game.data.pokemon.SQUIRTLE
  local oldHP = 8
  squirtle.hp = oldHP -- partly depleted so the bar is well under full
  -- one point below the level-6 exp threshold: a single kill levels up once
  squirtle.exp = Growth.expForLevel(def.growthRate, 6, game.data.growth_rates) - 1
  game.save.party = { squirtle }
  local oldMax = squirtle.stats.hp

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  -- weak enemy: 1 HP so the first TACKLE KOs; speed pinned to 1 so SQUIRTLE
  -- always moves first (no enemy turn to muddy the HP math); rng pinned to
  -- the low end so every roll hits (Damage.accuracyRoll: rng(0,255) < acc)
  local battle = BattleState.newWild(game, "SLOWPOKE", 2)
  battle.onFinish = function() end
  battle.rng = function(a, _) return a end
  battle.enemy.mon.hp = 1
  battle.enemy.mon.stats.speed = 1
  ow:pushBattle(battle)

  -- mash through the intro to the FIGHT menu
  for _ = 1, 240 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(3)
  end
  if battle.phase ~= "menu" then error("bug224: never reached the FIGHT menu") end

  -- HP box at L5: the menu safety net snaps shownHP to mon.hp, so 8/oldMax
  U.shot(game, DIR .. "/bug224_menu.png")

  -- FIGHT -> first move (TACKLE, slot 1) -> KO
  U.tap(game, "a") -- FIGHT
  for _ = 1, 60 do
    if battle.phase == "moveSelect" then break end
    U.wait(1)
  end
  if battle.phase ~= "moveSelect" then error("bug224: never reached move select") end
  U.tap(game, "a") -- TACKLE

  -- Monitor the level-up messages.  The bar must animate from oldHP toward
  -- the new current HP while phase == 'messages' (before finish/menu-snap).
  local maxShown = oldHP
  local caughtUp = false
  local shotGrew, shotRisen = false, false
  for _ = 1, 600 do
    U.wait(1)
    U.tap(game, "a") -- advance text / dismiss the stat box (never skips the
                     -- time-based drain), so we reach the HP-bar redraw
    if battle.phase == "messages" and battle.player.mon.level >= 6 then
      local sh = battle.player.shownHP or battle.player.mon.hp
      maxShown = math.max(maxShown, sh)
      if not shotGrew then
        -- first L6 messages frame: buggy build already shows the shrunk bar
        -- (8/newMax) here, and it never recovers
        U.shot(game, DIR .. "/bug224_grew.png")
        shotGrew = true
      end
      if not shotRisen and sh >= oldHP + 1.0 then
        -- the bar has climbed at least a full HP: capture it mid-rise
        U.shot(game, DIR .. "/bug224_hpbar.png")
        shotRisen = true
      end
      if sh >= squirtle.hp - 0.5 then
        caughtUp = true
        break
      end
    end
    if game.stack:top() ~= battle then break end -- battle finished/popped
  end

  -- data-layer sanity (Experience.lua): one level gained, max HP grew, and
  -- current HP rose by the max-HP delta
  if battle.player.mon.level ~= 6 then
    error("bug224: expected level 6, got " .. tostring(battle.player.mon.level))
  end
  local newMax = squirtle.stats.hp
  if not (newMax > oldMax) then
    error("bug224: max HP did not grow (oldMax=" .. tostring(oldMax) ..
          ", newMax=" .. tostring(newMax) .. "); repro is meaningless")
  end
  local expectHP = math.min(newMax, oldHP + (newMax - oldMax))
  if squirtle.hp ~= expectHP then
    error("bug224: current HP wrong: got " .. tostring(squirtle.hp) ..
          ", expected " .. tostring(expectHP))
  end

  -- THE BUG: the on-screen bar must have risen to the new current HP during
  -- the messages phase.  On the buggy build shownHP stays stuck at oldHP.
  if not caughtUp then
    error("bug224: HP bar did not rise on level-up - shownHP stuck at " ..
          tostring(maxShown) .. " (oldHP=" .. tostring(oldHP) ..
          "), mon.hp=" .. tostring(squirtle.hp) .. "/" .. tostring(newMax))
  end

  U.log("bug224 OK: L6, HP " .. tostring(squirtle.hp) .. "/" .. tostring(newMax) ..
        ", bar rose from " .. tostring(oldHP) .. " to " .. tostring(maxShown))
end
