-- Driver: SET_PAL_BATTLE_BLACK darkens the whole battle screen while the
-- blackout text is up (#292).  pokered engine/battle/core.asm:1147-1159
-- runs the palette command before the text, and returns early on OAKS_LAB.
-- No POKEPORT_SPEED here: audio runs on its own real-time clock.
--   POKEPORT_DRIVER=tests/drivers/blackout_palette_bug292_test.lua \
--     POKEPORT_IDENTITY=bug292 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local PaletteFX = require("src.render.PaletteFX")

  -- Route 1: no scripted battle, not the Oak's Lab exception, and (5,5) is
  -- open floor there (data/generated/maps.lua).
  local MAP = "ROUTE_1"
  local STAND = { x = 5, y = 5, facing = "down" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- A missing PAL_BLACK looks exactly like the bug on screen.
  local pack = PaletteFX.pack(game.data)
  local BLACK = pack and pack.palettes and pack.palettes.BLACK
  check("the active COLORS pack carries PAL_BLACK", BLACK ~= nil)
  if BLACK then
    U.log("  PAL_BLACK shades:",
          ("0 = %d,%d,%d"):format(BLACK[1][1], BLACK[1][2], BLACK[1][3]),
          ("1 = %d,%d,%d"):format(BLACK[2][1], BLACK[2][2], BLACK[2][3]),
          ("3 = %d,%d,%d"):format(BLACK[4][1], BLACK[4][2], BLACK[4][3]))
    check("shade 0 is the near-white paper", BLACK[1][1] > 200)
    check("shades 1-3 are near-black ink",
          BLACK[2][1] < 90 and BLACK[3][1] < 90 and BLACK[4][1] < 90)
  end

  -- A DMG never had SGB darkening, so the fix deliberately does nothing in
  -- the forced-mono modes and a run in one of them proves nothing.
  local mode = PaletteFX.mode
  local mono = mode == "og" or mode == "og_inv" or mode == "classic"
  U.log("COLORS mode:", tostring(mode), "(" .. PaletteFX.modeLabel(mode) .. ")")
  if mono then
    U.log("WARNING: " .. PaletteFX.modeLabel(mode) .. " is a forced-mono mode.")
    U.log("WARNING: PAL_BLACK is an SGB packet and a DMG never darkened, so")
    U.log("WARNING: nothing below will look dark and that is CORRECT.  Press 2")
    U.log("WARNING: (or set COLORS in OPTION) to SGB / GBC first, then re-run.")
  end
  check("the COLORS mode is one that can show the darkening", not mono)

  -- ---- a losing battle ---------------------------------------------------
  -- One mon on 1 HP against something that outspeeds it.
  game.save.party = { Pokemon.new(game.data, "RATTATA", 3) }
  game.save.party[1].hp = 1
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up on " .. MAP, ow ~= nil)
  check("this is not the Oak's Lab starter-rival exception",
        (ow and ow.map and ow.map.id) ~= "OAKS_LAB")

  local battle = BattleState.newWild(game, "RATICATE", 50)
  battle.onFinish = function() end
  if ow then ow:pushBattle(battle) end
  for _ = 1, 400 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the battle reached the screen", game.stack:top() == battle)

  -- photograph the full-color screen so the "after" shot has a reference
  for _ = 1, 60 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the battle reached its action menu", battle.phase == "menu")
  check("nothing is darkened yet", battle.blackedOut == nil)
  if not U.shot(game, DIR .. "/bug292_1_full_color.png") then
    U.log("FAIL could not capture the full-color battle")
  end

  -- ---- lose it -----------------------------------------------------------
  -- Stop the instant the wipe registers, so the blackout text is still ahead
  -- of the player.
  for _ = 1, 700 do
    if battle.blackedOut then break end
    if battle.result then break end
    U.tap(game, "a")
    U.wait(4)
  end
  if not battle.blackedOut and not battle.result then
    -- the foe kept rolling status moves: take the engine's own faint path
    U.log("the foe never landed a hit; forcing the KO through onFaint")
    battle.player.mon.hp = 0
    battle.nextInsert = 0
    battle:onFaint(battle.player)
    for _ = 1, 400 do
      if battle.blackedOut then break end
      U.tap(game, "a")
      U.wait(4)
    end
  end
  check("the party was wiped out and the screen blacked", battle.blackedOut == true)

  -- Two code paths darken the screen (the zone pass for HUD and bars, a
  -- re-baked pic for the sprites) and both have to fire.
  if BLACK then
    local pals = battle:sgbBattlePals()
    check("all four battle zones are PAL_BLACK",
          pals ~= nil and pals[0] == BLACK and pals[1] == BLACK
          and pals[2] == BLACK and pals[3] == BLACK)
  end

  U.wait(20)
  if not U.shot(game, DIR .. "/bug292_2_blacked_out.png") then
    U.log("FAIL could not capture the blacked-out battle")
  end
  local cur = battle.current
  U.log("box on screen:", cur and cur.text and (cur.text:gsub("\n", " / "))
        or "(between rows)")

  -- ---- hand off ----------------------------------------------------------
  U.log("Your last POKeMON has fainted; press A through the blackout text.")
  U.log("Behind the box the enemy sprite, the HP bar and the HUD should all")
  U.log("be near-black on near-white for both lines (#292).  Compare")
  U.log(DIR .. "/bug292_1_full_color.png with bug292_2_blacked_out.png.")
  U.log("OG / OG INV / CLASSIC and the Oak's lab rival fight never darken.")

  while true do
    coroutine.yield()
  end
end
