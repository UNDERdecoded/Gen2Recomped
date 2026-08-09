-- Soft reset from inside a battle (#563): A+B+SELECT+START held together
-- drops back to the title, the way _Joypad's `cp PAD_BUTTONS` (pokered
-- engine/joypad.asm:6) reads the raw pad ahead of the wJoyIgnore masking
-- that a battle turn leans on.  Counting and touch-overlay halves are
-- asserted in tests/engine/soft_reset_bug563.lua; this is the ear and eye
-- half -- music cutting to the title theme, unsaved progress gone.
--   POKEPORT_DRIVER=tests/drivers/soft_reset_bug563_test.lua POKEPORT_IDENTITY=bug563 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Input = require("src.core.Input")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local CHORD = { "a", "b", "start", "select" }

  -- The driver presses GB buttons by name, so it proves the chord is read
  -- but says nothing about which keys reach it.  Print the live map for the
  -- hand-off instead of hard-coding key names into the notes.
  local function keysFor(btn)
    local keys = {}
    for key, action in pairs(Input.keyBindings or {}) do
      if action == btn then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return table.concat(keys, " / ")
  end

  U.log("#563 soft reset: machine checks")
  check("Input:softResetHeld exists", type(Input.softResetHeld) == "function")
  check("Input:softResetStep exists", type(Input.softResetStep) == "function")
  for _, btn in ipairs(CHORD) do
    local keys = keysFor(btn)
    check(btn:upper() .. " has a key bound (" .. keys .. ")", keys ~= "")
  end

  local musicVol = game.save.options and game.save.options.musicVol
  if musicVol == 0 then
    U.log("musicVol is 0: the battle music cutting to the title theme is the")
    U.log("main thing to listen for, so raise it in OPTION before judging")
  else
    U.log("musicVol", tostring(musicVol),
          "-- the battle theme should stop dead and the title theme start")
  end

  -- ---- a battle to reset out of -----------------------------------------

  game.save.party = {
    Pokemon.new(game.data, "SQUIRTLE", 30),
    Pokemon.new(game.data, "PIDGEOTTO", 28),
  }
  game.save.player.name = "RED"

  -- data/generated/maps.lua ROUTE_1: (5, 5) is open walkable ground.  The
  -- battle is pushed straight in rather than encountered, so the cell only
  -- has to be somewhere the player can legally stand.
  local START = { x = 5, y = 5 }
  U.teleport(game, "ROUTE_1", START.x, START.y, "down")
  U.wait(10)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(START.x, START.y) then
    -- a map edit moved the path: take the nearest walkable cell instead
    local sx, sy
    for r = 1, 6 do
      for dy = -r, r do
        for dx = -r, r do
          if not sx and ow.map:isWalkableCell(START.x + dx, START.y + dy) then
            sx, sy = START.x + dx, START.y + dy
          end
        end
      end
      if sx then break end
    end
    if sx then
      U.log(("(%d, %d) is blocked, standing on"):format(START.x, START.y), sx, sy)
      U.teleport(game, "ROUTE_1", sx, sy, "down")
      U.wait(10)
      ow = game.overworld
    end
  end
  check("the overworld is up on ROUTE_1", ow ~= nil)

  -- something to reset away from: a fight in progress and 2 unsaved mon
  local function enterBattle()
    local battle = BattleState.newWild(game, "RATTATA", 12)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    for _ = 1, 400 do
      if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
      U.wait(1)
    end
    return battle
  end

  local battle = enterBattle()
  check("the battle reached the screen", game.stack:top() == battle)
  check("battle screenshot reached disk",
        U.shot(game, DIR .. "/bug563_battle.png"))

  -- ---- hold the chord ----------------------------------------------------

  -- A real hold is one press edge and then sustained state, so queue the
  -- edge once and only keep `state` alive after that.  Re-queueing every
  -- frame would feed the battle 40 A presses and run the fight away before
  -- the countdown ever finished.  Stops the moment the title appears: the
  -- driver has no key-up, so a hold left running past the reset would press
  -- A on the title's first frame and start a new game by itself.
  local function holdChord(frames, extra)
    local buttons = { unpack(CHORD) }
    if extra then buttons[#buttons + 1] = extra end
    for frame = 1, frames do
      for _, btn in ipairs(buttons) do
        if frame == 1 then table.insert(game.input.pressQueue, btn) end
        game.input.state[btn] = true
      end
      coroutine.yield()
      local top = game.stack:top()
      if top and top.screenId == "TitleState" then break end
    end
    for _, btn in ipairs(buttons) do game.input.state[btn] = false end
  end

  -- Control case first: `cp PAD_BUTTONS` is an equality, so the same four
  -- buttons plus a direction is not the combo however long it is held.  If
  -- this one resets, the port is masking the read instead of comparing it.
  holdChord(40, "up")
  U.wait(5)
  check("four buttons plus UP for 40 frames does NOT reset",
        game.stack:top() == battle)

  -- 16 polls is the countdown Init seeds hSoftReset with (home/init.asm:81);
  -- 60 frames leaves room for it without hiding an off-by-one, which the
  -- engine suite pins exactly.
  holdChord(60)
  U.wait(20)

  local top = game.stack:top()
  check("the chord dropped the battle for the title",
        top ~= nil and top.screenId == "TitleState")
  check("the battle state is gone from the stack", top ~= battle)
  check("no button is left held into the title", not game.input:isDown("a"))
  check("title screenshot reached disk", U.shot(game, DIR .. "/bug563_title.png"))

  -- the title must not act on the still-held buttons on its own first frames
  U.wait(60)
  check("the title is still up a second later, not a menu it auto-picked",
        game.stack:top() == top)

  -- ---- hand off inside a fresh battle ------------------------------------

  -- Handing the pad over needs a party again.  A player who did this for
  -- real would be picking CONTINUE here and getting whatever was last saved,
  -- which is the point of the reset -- this is only the driver restocking.
  game.save.party = {
    Pokemon.new(game.data, "SQUIRTLE", 30),
    Pokemon.new(game.data, "PIDGEOTTO", 28),
  }
  U.teleport(game, "ROUTE_1", START.x, START.y, "down")
  U.wait(10)
  local again = enterBattle()
  check("a second battle is up for the manual attempt", game.stack:top() == again)

  U.log("The driver already did this once: /tmp/shots/bug563_battle.png is the")
  U.log("fight it was in, bug563_title.png is where it landed.  There is a")
  U.log("fresh RATTATA battle on screen now for you to repeat it by hand.")
  U.log("Hold " .. keysFor("a") .. " (A) + " .. keysFor("b") .. " (B) + "
        .. keysFor("start") .. " (START) + " .. keysFor("select") .. " (SELECT)")
  U.log("together for about a third of a second.  The battle theme should cut")
  U.log("out and the title come back with its own music; CONTINUE from there")
  U.log("gives you the last save, so the fight and anything after it is gone.")
  U.log("Add any arrow key to the four and nothing should happen at all.  A")
  U.log("quick tap of all four in passing must not reset either, and letting")
  U.log("one go a beat early must start the count over rather than resume it.")
  U.log("Control case if it does nothing: QUIT in the START menu runs the same")
  U.log("return-to-title, so if QUIT works the pad read is what to look at.")
  U.log("For the on-screen overlay, re-run with POKEPORT_TOUCH=1: the mouse is")
  U.log("one finger there, so the combo cannot be reached at all on desktop.")
  U.log(("checks: %d passed, %d failed"):format(pass, fail))

  while true do
    coroutine.yield()
  end
end
