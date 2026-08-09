-- Driver: Pallet intro (Oak escort → starter → rival ambush) plus the
-- #158 parcel-return / rival-join / Pokédex-gift cutscene.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  -- start two rows south: the trigger is the step ONTO row y=1
  -- (PalletTownDefaultScript's wYCoord == 1 check)
  U.teleport(game, "PALLET_TOWN", 10, 3, "up")
  local ow = game.overworld

  -- press A only when a dialog is open (mashing at the overworld would
  -- re-interact with whatever the player faces)
  local function mashUntil(cond, label, cap)
    for _ = 1, cap or 400 do
      if cond() then return true end
      if game.stack:top() ~= ow then
        U.tap(game, "a")
      end
      U.wait(4)
    end
    U.log("TIMEOUT waiting for " .. label)
    return false
  end
  local function idle()
    return game.stack:top() == ow and not ow.runner:isRunning()
           and #ow.scriptMoves == 0 and not ow.transitioning
           and not ow.emote -- cutscene DelayFrames/bubble holds
  end

  -- trigger Oak (two steps north onto row 1)
  U.hold(game, "up", 40)
  U.wait(30)
  U.shot(game, DIR .. "/oak_1_heywait.png")
  U.wait(90) -- auto-close + "!" bubble
  U.shot(game, DIR .. "/oak_2_bubble.png")
  U.wait(120) -- Oak's zigzag walk up from (8,5)
  U.shot(game, DIR .. "/oak_3_follow.png")
  -- dismiss "It's unsafe!" (multi-page), then catch the escort mid-walk
  mashUntil(function() return game.stack:top() == ow end, "unsafe text", 200)
  U.wait(130)
  U.shot(game, DIR .. "/oak_3b_escort.png")
  mashUntil(function() return ow.map.id == "OAKS_LAB" end, "lab entry", 900)
  U.shot(game, DIR .. "/oak_4_arrived.png")
  mashUntil(idle, "walk-in done", 600)
  U.shot(game, DIR .. "/oak_5_at_desk.png")
  U.log("in lab at:", ow.player.cellX, ow.player.cellY)

  -- the walk-in ends at (5,3) below Oak; to the middle ball:
  -- down to (5,4) -> right to (7,4) -> face up at SQUIRTLE's ball
  U.hold(game, "down", 18)
  U.wait(10)
  U.hold(game, "right", 34)
  U.wait(20) -- let the second step land before turning
  U.tap(game, "up")
  U.wait(10)
  U.log("at ball:", ow.player.cellX, ow.player.cellY, ow.player.facing)
  U.tap(game, "a")
  U.wait(40)
  U.shot(game, DIR .. "/oak_6_ball_prompt.png")
  U.tap(game, "a") -- YES
  mashUntil(function() return #game.save.party > 0 end, "starter", 200)
  U.shot(game, DIR .. "/oak_7_got_starter.png")
  -- step away from the ball first: A-mash while facing it re-opens
  -- its dialog forever
  U.hold(game, "down", 20)
  mashUntil(idle, "rival pick done", 400)
  U.shot(game, DIR .. "/oak_8_rival_picked.png")
  U.log("party:", game.save.party[1] and game.save.party[1].species,
        "pos:", ow.player.cellX, ow.player.cellY)

  -- head for the door: rival ambush -> battle.  Exact single steps
  -- left to column 4 (column 3 runs into the lab table), then south.
  for _ = 1, 3 do
    U.hold(game, "left", 16)
    U.wait(12)
  end
  U.hold(game, "down", 120)
  U.wait(30)
  U.shot(game, DIR .. "/oak_9_ambush.png")
  local BattleSeen = false
  for _ = 1, 200 do
    if game.stack:top() ~= ow and game.stack:top() and game.stack:top().kind then
      BattleSeen = true
      break
    end
    U.tap(game, "a")
    U.wait(4)
  end
  U.wait(60)
  U.shot(game, DIR .. "/oak_10_battle.png")
  mashUntil(idle, "battle over", 1500)
  U.wait(30)
  U.shot(game, DIR .. "/oak_11_after_battle.png")
  U.log("final:", ow.map.id, ow.player.cellX, ow.player.cellY,
        "battled:", tostring(game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB),
        "battleSeen:", tostring(BattleSeen))

  -- ---- #158: return Oak's Parcel → rival joins → Pokédex gift ----
  local Flags = require("src.script.Flags")
  Flags.set(game.save, "EVENT_GOT_OAKS_PARCEL")
  game.save.inventory.OAKS_PARCEL = 1
  -- desk Oak + both dexes visible; rival hidden until the script shows
  -- him.  Keep the starter-ball hides from the pick (Squirtle + Bulbasaur).
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.objectToggles.OAKS_LAB = {
    OAKSLAB_OAK1 = true,
    OAKSLAB_OAK2 = false,
    OAKSLAB_RIVAL = false,
    OAKSLAB_POKEDEX1 = true,
    OAKSLAB_POKEDEX2 = true,
    OAKSLAB_SQUIRTLE_POKE_BALL = false,
    OAKSLAB_BULBASAUR_POKE_BALL = false,
  }
  U.teleport(game, "OAKS_LAB", 5, 3, "up")
  ow = game.overworld
  U.wait(20)
  U.shot(game, DIR .. "/oak_12_parcel_ready.png")
  U.tap(game, "a")
  U.wait(40)
  U.shot(game, DIR .. "/oak_13_deliver.png")
  local rivalSeen, atDeskShot, leaveShot = false, false, false
  for _ = 1, 1200 do
    if idle() and Flags.get(game.save, "EVENT_GOT_POKEDEX")
       and not ow:npcByIndex(1) then
      break
    end
    local rival = ow:npcByIndex(1)
    local top = game.stack:top()
    if rival and not rivalSeen then
      rivalSeen = true
      U.wait(24)
      U.shot(game, DIR .. "/oak_14_rival_arrive.png")
    end
    if rival and rival.cellY <= 3 and not atDeskShot then
      atDeskShot = true
      U.shot(game, DIR .. "/oak_14b_rival_at_desk.png")
    end
    if rival and rival.cellY >= 6 and Flags.get(game.save, "EVENT_GOT_POKEDEX")
       and not leaveShot then
      leaveShot = true
      U.shot(game, DIR .. "/oak_14c_rival_leave.png")
    end
    if top ~= ow then
      U.tap(game, "a")
    end
    U.wait(4)
  end
  mashUntil(idle, "pokedex cutscene done", 600)
  U.shot(game, DIR .. "/oak_15_after_pokedex.png")
  local toggles = game.save.objectToggles and game.save.objectToggles.OAKS_LAB
  local rivalAfter = ow:npcByIndex(1)
  U.log("parcel:",
        "gotDex=", tostring(Flags.get(game.save, "EVENT_GOT_POKEDEX")),
        "oakGot=", tostring(Flags.get(game.save, "EVENT_OAK_GOT_PARCEL")),
        "rivalSeen=", tostring(rivalSeen),
        "rivalGone=", tostring(rivalAfter == nil),
        "atDesk=", tostring(atDeskShot),
        "dex1=", tostring(toggles and toggles.OAKSLAB_POKEDEX1),
        "dex2=", tostring(toggles and toggles.OAKSLAB_POKEDEX2),
        "route22=", tostring(Flags.get(game.save, "EVENT_ROUTE22_RIVAL_WANTS_BATTLE")))
end
