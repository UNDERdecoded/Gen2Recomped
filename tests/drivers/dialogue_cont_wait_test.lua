-- Driver: #163 cont (\\v) must show ▼ and wait for A before scrolling.
-- Talks to VIRIDIANFOREST_YOUNGSTER5 (cont mid-page) and the nearby
-- TRAINER TIPS1 sign (para then conts). Screenshots the ▼ wait frames.
--
--   SHOT_DIR=/tmp/dialogue_cont POKEPORT_DRIVER=tests/drivers/dialogue_cont_wait_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/dialogue_cont"
  local TextBox = require("src.render.TextBox")

  local pass = true
  local function check(cond, msg)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end
  local function topIs(mt) return getmetatable(game.stack:top()) == mt end

  local function waitForTextBox(frames)
    for _ = 1, frames or 60 do
      if topIs(TextBox) then return game.stack:top() end
      U.wait(1)
    end
    return nil
  end

  -- type out until waiting/done without mashing A (held A would only
  -- speed the typewriter; wasPressed edges are what clear waits)
  local function waitUntilPrompt(box, frames)
    for _ = 1, frames or 240 do
      if not topIs(TextBox) then return false end
      if box.waiting or box.done then return true end
      U.wait(1)
    end
    return box.waiting or box.done
  end

  -- ▼ blinks half the time (blink < 30); settle so the shot shows it.
  -- Keep POKEPORT_SPEED=1: scriptedIterations>1 can advance past the
  -- wait in the same rendered frame before love.draw captures.
  local function shotPrompt(box, path)
    for _ = 1, 60 do
      if not (box.waiting or box.done) then break end
      if box.blink < 20 then break end
      U.wait(1)
    end
    U.shot(game, path)
    U.wait(2)
  end

  local function dismissText()
    for _ = 1, 80 do
      if not topIs(TextBox) then return end
      U.tap(game, "a")
      U.wait(2)
    end
  end

  -- Youngster5 @ (27,40): "I ran out of POKé / BALLs to catch" then
  -- \v "POKéMON with!" -- the bug auto-scrolled past this with no ▼.
  U.teleport(game, "VIRIDIAN_FOREST", 27, 41, "up")
  U.tap(game, "a")
  local box = waitForTextBox(90)
  check(box ~= nil, "youngster5 opened a TextBox")
  if box then
    check(waitUntilPrompt(box, 300), "youngster5 reached a prompt")
    check(box.waiting and box.contAdvance,
          "youngster5 first prompt is a cont wait (▼)")
    shotPrompt(box, DIR .. "/dialogue_cont_00_youngster5_arrow.png")
    U.tap(game, "a")
    U.wait(3)
    check(waitUntilPrompt(box, 300), "youngster5 reached para/done after cont")
    shotPrompt(box, DIR .. "/dialogue_cont_01_youngster5_after.png")
    dismissText()
  end

  -- Trainer Tips1 sign @ (24,40): para after title, then two conts.
  U.teleport(game, "VIRIDIAN_FOREST", 24, 41, "up")
  U.tap(game, "a")
  box = waitForTextBox(90)
  check(box ~= nil, "tips1 sign opened a TextBox")
  if box then
    check(waitUntilPrompt(box, 300), "tips1 reached first prompt")
    -- first prompt is the para after "TRAINER TIPS"
    check(box.waiting and not box.contAdvance,
          "tips1 first prompt is a para wait")
    shotPrompt(box, DIR .. "/dialogue_cont_02_tips1_para.png")
    U.tap(game, "a")
    U.wait(3)
    check(waitUntilPrompt(box, 300), "tips1 typed into page 2")
    check(box.waiting and box.contAdvance,
          "tips1 page2 pauses on cont with ▼")
    shotPrompt(box, DIR .. "/dialogue_cont_03_tips1_cont_arrow.png")
    dismissText()
  end

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
end
