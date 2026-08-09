-- Driver: a ball thrown at a trainer's mon is blocked, with the animation and
-- the turn it costs (#291).  ItemUseBall branches to ThrowBallAtTrainerMon
-- before it prints the "used <ITEM>" line (engine/items/item_effects.asm:109-113,
-- 2292-2303), and TossBallAnimation's .BlockBall plays TOSS_ANIM,
-- SFX_FAINT_THUD, BLOCKBALL_ANIM (engine/battle/animations.asm:2629-2637).
--   POKEPORT_DRIVER=tests/drivers/trainer_ball_bug291_test.lua SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local OPP, ROSTER, BALL = "OPP_YOUNGSTER", 1, "POKE_BALL"

  -- ---- preconditions neither the eye nor the ear can separate ------------
  -- A missing anim program plays nothing, a missing sfx key is a silent no-op
  -- in Sound.play, and a missing text entry falls back to a differently cased
  -- literal.  All three read as the bug.
  local ma = game.data.battle_anims and game.data.battle_anims.moveAnims
  check("TOSS_ANIM has an extracted animation program",
        ma ~= nil and ma.TOSS_ANIM ~= nil)
  check("BLOCKBALL_ANIM has an extracted animation program",
        ma ~= nil and ma.BLOCKBALL_ANIM ~= nil)
  local sfx = game.data.audio and game.data.audio.sfx
  check("SFX_FAINT_THUD resolves as Faint_Thud",
        sfx ~= nil and sfx.Faint_Thud ~= nil)
  local t1 = game.data.text and game.data.text._ThrowBallAtTrainerMonText1
  local t2 = game.data.text and game.data.text._ThrowBallAtTrainerMonText2
  check("_ThrowBallAtTrainerMonText1 is in the generated text",
        type(t1) == "string")
  check("_ThrowBallAtTrainerMonText2 is in the generated text",
        type(t2) == "string")
  if type(t1) == "string" then
    U.log("block line reads:", (t1:gsub("\n", " / ")))
    check("it is the ROM's lower-case \"trainer\", not \"The TRAINER\"",
          t1:find("The trainer", 1, true) ~= nil)
  end
  check("trainer class " .. OPP .. " is in the data",
        game.data.trainers ~= nil and game.data.trainers[OPP] ~= nil)
  check("the ball item exists", game.data.items[BALL] ~= nil)

  -- the thud is the middle beat of the three, and a muted run cannot tell it
  -- from a thud that never plays
  local vol = game.save.options and game.save.options.sfxVol
  U.log("audio device present:", love.audio ~= nil,
        "  SFX VOL (0-7):", tostring(vol))
  if not love.audio or vol == 0 then
    U.log("WARNING: sound output is off, so the FAINT THUD below will be",
          "inaudible; raise SFX VOL in OPTION first")
  end

  game.save.player.name = "bryan"
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  -- exactly one bag entry, so the bag cursor starts on the ball
  game.save.inventory = { [BALL] = 5 }
  check("the bag holds " .. BALL, (game.save.inventory[BALL] or 0) > 0)

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
  check("battle kind is trainer (a wild throw is the control, not this)",
        battle.kind == "trainer")
  battle.onFinish = function() end
  ow:pushBattle(battle)

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

  local function waitUntil(cond, frames)
    for _ = 1, (frames or 120) do
      if cond() then return true end
      U.wait(1)
    end
    return cond()
  end

  check("reached the FIGHT/PKMN/ITEM/RUN menu",
        tapUntil(function() return battle.phase == "menu" end, 60))

  -- The 2x2 command menu is fight/pkmn/item/run (BattleState.lua:1378-1387,
  -- DisplayBattleMenu): one press of DOWN from FIGHT lands on ITEM.
  U.tap(game, "down")
  U.wait(6)
  check("cursor is on ITEM", battle.menuIndex == 3)
  U.tap(game, "a")     -- open the bag
  U.wait(20)
  U.tap(game, "a")     -- A on the only entry: no USE/TOSS box mid-battle
  U.wait(6)

  -- Poll rather than sleep, so the arc is caught on the frame it starts.
  local sawToss = waitUntil(function() return battle.animName == "TOSS_ANIM" end,
                            180)
  check("the ball was thrown from the real bag (TOSS_ANIM playing)", sawToss)
  if sawToss then
    check("toss screenshot reached disk",
          U.shot(game, DIR .. "/bug291_toss.png"))
    U.log("captured", DIR .. "/bug291_toss.png")
  end

  local sawBlock = waitUntil(
    function() return battle.animName == "BLOCKBALL_ANIM" end, 240)
  check("the trainer's block animation played (#291)", sawBlock)
  if sawBlock then
    check("block screenshot reached disk",
          U.shot(game, DIR .. "/bug291_blockball.png"))
    U.log("captured", DIR .. "/bug291_blockball.png")
  end

  -- Stop on the block text, so the box is up at hand-off and the human's own A
  -- press is what starts the foe's turn.
  waitUntil(function()
    return battle.shown and battle.shown[1] ~= nil and not battle.animPlaying
  end, 240)
  check("block text screenshot reached disk",
        U.shot(game, DIR .. "/bug291_block_text.png"))
  U.log("captured", DIR .. "/bug291_block_text.png")
  check("the ball was consumed by the throw",
        (game.save.inventory[BALL] or 0) == 4)

  -- ---- hand off, then stay out of the way --------------------------------
  U.log("A POKe BALL has been thrown at the trainer's RATTATA; the box is the")
  U.log("result. No \"bryan used POKe BALL!\" line: just the arc, a FAINT THUD, the")
  U.log("BLOCKBALL flash, the block text, then the foe attacking, because the")
  U.log("throw costs the turn (#291). Wild battles do still print the used line.")

  while true do
    coroutine.yield()
  end
end
