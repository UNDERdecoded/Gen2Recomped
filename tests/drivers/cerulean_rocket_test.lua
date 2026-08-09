-- Driver: Cerulean TM28 Rocket despawn fade (#170).
-- Skips the fight (EVENT_BEAT set), talks through the TM return, and
-- captures a mid-fade frame while CeruleanHideRocket runs.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  table.insert(game.save.party, Pokemon.new(game.data, "BLASTOISE", 50))
  game.save.flags.EVENT_BEAT_CERULEAN_ROCKET_THIEF = true
  -- Rocket at (30,8); stand south and face him
  U.teleport(game, "CERULEAN_CITY", 30, 9, "up")
  local ow = game.overworld

  local function mashUntil(cond, label, cap)
    for _ = 1, cap or 600 do
      if cond() then return true end
      if game.stack:top() ~= ow then U.tap(game, "a") end
      U.wait(3)
    end
    U.log("TIMEOUT waiting for " .. label)
    return false
  end

  U.shot(game, DIR .. "/cerulean_rocket_00_before.png")
  U.tap(game, "a")
  U.wait(20)
  U.shot(game, DIR .. "/cerulean_rocket_01_return_tm.png")

  local function rocketAlive()
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == "CERULEANCITY_ROCKET" then return true end
    end
    return false
  end

  -- Prefer mid fade-in (rocket already toggled off, screen still dark),
  -- matching pokered's post-HideObject GBFadeInFromBlack frames.
  local midShot = false
  for _ = 1, 900 do
    local overlay = ow.fadeOverlay
    local alpha = overlay and overlay.alpha or 0
    if not midShot and alpha > 0.35 and alpha < 0.95 and not rocketAlive() then
      U.shot(game, DIR .. "/cerulean_rocket_02_mid_fade.png")
      midShot = true
    end
    if midShot and not ow.fadeOverlay and game.stack:top() == ow
       and not ow.runner:isRunning() then
      break
    end
    if game.stack:top() ~= ow then U.tap(game, "a") end
    U.wait(2)
  end
  U.log("mid-fade shot:", tostring(midShot))
  mashUntil(function()
    return game.stack:top() == ow and not ow.runner:isRunning()
           and not ow.fadeOverlay
  end, "idle after hide", 200)
  U.wait(10)
  U.shot(game, DIR .. "/cerulean_rocket_03_after.png")

  local names = {}
  for _, n in ipairs(ow.npcs or {}) do
    names[#names + 1] = n.def and n.def.name or "?"
  end
  local toggles = game.save.objectToggles and game.save.objectToggles.CERULEAN_CITY
  U.log("rocket alive:", tostring(rocketAlive()))
  U.log("rocket toggle:", tostring(toggles and toggles.CERULEANCITY_ROCKET))
  U.log("got TM28:", tostring(game.save.flags.EVENT_GOT_TM28))
  U.log("npcs:", table.concat(names, ","))
end
