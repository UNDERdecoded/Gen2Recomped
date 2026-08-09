-- Driver: regression coverage for #601 "Wrong dialogue when interacting
-- with Prof. Oak's last ball".
--
-- After the player picks a starter and the rival takes his, the leftover
-- ball on the lab table must show "That's PROF.OAK's last Pokémon!" --
-- pret/pokered scripts/OaksLab.asm OaksLabSelectedPokeBallScript jumps
-- every ball handler to OaksLabLastMonScript once EVENT_GOT_STARTER is
-- set (Oak turns to face the player first).  The buggy port fell through
-- to _OaksLabThoseArePokeBallsText ("Those are POKé BALLs...") instead.
--
-- Scenario A (the #601 regression): with a starter already picked, talk
--   to the leftover ball -> Oak faces down, box says "last Pokémon!",
--   and no starter offer/dex appears.  Fails before the fix (the box
--   says "Those are POKé BALLs").
-- Scenario B (guard): with NO starter and not escorted in, the ball still
--   says "Those are POKé BALLs".  Passes before and after the fix.
--
-- Setup: flags are set directly (pick flow never runs), so all three
-- balls stay visible; the player stands left of the Charmander ball
-- (cell 6,3), the leftover slot for the Squirtle pick (rival took the
-- Bulbasaur ball).  The lab battle flag is set so the rival is gone and
-- cannot intercept the talk.  TextBox.new is hooked to capture the raw
-- box text.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local TextBox = require("src.render.TextBox")
  local origNew = TextBox.new
  local lastText
  TextBox.new = function(g, text, ...)
    lastText = text
    return origNew(g, text, ...)
  end

  local function restore()
    TextBox.new = origNew
  end

  local function setFlags(postPick)
    local flags = game.save.flags or {}
    game.save.flags = flags
    flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
    if postPick then
      flags.EVENT_GOT_STARTER = true
      flags.EVENT_CHOSE_SQUIRTLE = true
    else
      flags.EVENT_GOT_STARTER = nil
    end
    -- rival already fought + gone, so he cannot intercept the talk
    flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  end

  -- Talk to the ball at cell 6,3 (Charmander slot): stand one cell left
  -- facing right and press A.  Returns once a TextBox has been built.
  local function talkToBall()
    lastText = nil
    U.teleport(game, "OAKS_LAB", 5, 3, "right")
    U.wait(6)
    for _ = 1, 8 do
      U.tap(game, "a")
      for _ = 1, 30 do
        if lastText then return true end
        U.wait(1)
      end
    end
    return lastText ~= nil
  end

  -- ---- Scenario A: leftover ball after the pick
  setFlags(true)
  local aBoxOpened = talkToBall()
  U.wait(30) -- let the typewriter reveal the line
  U.shot(game, DIR .. "/a_last_ball.png")
  local aText = lastText or "<none>"
  local aPass = aBoxOpened
    and aText:find("last Pokémon!", 1, true) ~= nil
    and aText:find("Those are", 1, true) == nil
  U.log("SCENARIO A box:", aText)
  U.log("SCENARIO A", aPass and "PASS" or "FAIL")

  -- close the box
  for _ = 1, 10 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(2)
  end

  -- ---- Scenario B: pre-escort ball text unchanged
  setFlags(false)
  local bBoxOpened = talkToBall()
  U.wait(30)
  U.shot(game, DIR .. "/b_pre_escort.png")
  local bText = lastText or "<none>"
  local bPass = bBoxOpened
    and bText:find("ThoseArePokeBalls", 1, true) ~= nil
    or bText:find("Those are", 1, true) ~= nil
  U.log("SCENARIO B box:", bText)
  U.log("SCENARIO B", bPass and "PASS" or "FAIL")

  -- restore hooks before any assert so a failure can't leave them installed
  restore()

  U.log("RESULT bug601", (aPass and bPass) and "PASS" or "FAIL")
  assert(aPass,
    "Leftover ball after the pick must say 'That's PROF.OAK's last "
    .. "Pokémon!' (no 'Those are POKé BALLs'); got: " .. aText)
  assert(bPass,
    "Pre-escort balls must keep the 'Those are POKé BALLs' line; got: "
    .. bText)
end
