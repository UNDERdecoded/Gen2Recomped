-- Driver: scrolling text must stay inside its box (#314).  Opens the real
-- _HallOfFameOakText so the reported moment is watchable without beating
-- the Elite Four; tests/parity_text_scroll_bounds.lua asserts the bound.
-- pokered never scrolls sub-tile: ScrollTextUpOneLine (home/text.asm:283)
-- copies whole rows.  No POKEPORT_SPEED: the typewriter races the scroll.
--   POKEPORT_DRIVER=tests/drivers/text_scroll_bug314_test.lua POKEPORT_IDENTITY=bug314 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")

  local TEXT_KEY = "_HallOfFameOakText"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- a box only scrolls when the text carries \v (cont) markers, so a text
  -- with none would look fine while proving nothing
  local text = game.data.text[TEXT_KEY]
  check(TEXT_KEY .. " is in the extracted text", type(text) == "string")
  local conts = 0
  for _ in tostring(text):gmatch("\v") do conts = conts + 1 end
  check("it carries \\v cont markers (this is what scrolls)", conts > 0)
  U.log("   " .. TEXT_KEY .. " has", conts, "cont markers and",
        select(2, tostring(text):gsub("\f", "")), "page breaks")

  local probe = TextBox.new(game, "probe")
  U.log("   box rows: line1Y =", probe.line1Y, " line2Y =", probe.line2Y,
        " bottom border row starts at y =",
        (probe.boxTy + probe.boxTh - 1) * 8)
  check("the two text rows are two tiles apart",
        probe.line2Y - probe.line1Y == 16)

  local speed = game.save.options and game.save.options.textSpeed
  U.log("TEXT SPEED (1 fast / 3 mid / 5 slow):", tostring(speed))
  if speed == 5 then
    U.log("NOTE: the overlap is easiest to catch on FAST text speed, where")
    U.log("      the typewriter most often beats the four-frame scroll.")
  end

  -- a plain background, so the box border is easy to read against it
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(10)

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local box = TextBox.new(game, text)
  game.stack:push(box)
  U.wait(24)
  U.shot(game, SHOT_DIR .. "/bug314_hof_speech.png")
  U.log("captured", SHOT_DIR .. "/bug314_hof_speech.png")

  -- scrollPx starts at 8 and drains 2 per drawn frame, so any overlap is
  -- on screen for about four frames: capture it rather than blink past it
  local shots, scrolls = 0, 0
  for _ = 1, 240 do
    if box.waiting then
      U.tap(game, "a")
      U.wait(1)
      if (box.scrollPx or 0) > 0 then
        scrolls = scrolls + 1
        if shots < 2 then
          shots = shots + 1
          U.shot(game, SHOT_DIR .. "/bug314_midscroll_" .. shots .. ".png")
          U.log("captured mid-scroll frame", shots,
                "scrollPx =", box.scrollPx)
        end
      end
    end
    if box.done or game.stack:top() ~= box then break end
    U.wait(1)
  end
  check("the box actually scrolled at least once", scrolls > 0)

  -- hand off, then stay out of the way
  U.log("Oak's Hall of Fame speech is open and already a few scrolls in.")
  U.log("Press A through the rest: as each line slides up, no glyph may")
  U.log("touch the box's bottom border (#314).  The blinking arrow is fine.")
  U.log("Re-run on FAST text speed if nothing shows.")

  while true do
    coroutine.yield()
  end
end
