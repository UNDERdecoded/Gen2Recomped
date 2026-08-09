-- Driver: the bedroom PC (Red's House 2F) must open the player's item PC
-- directly (WITHDRAW/DEPOSIT/TOSS/LOG OFF), NOT the Pokemon Center multi-PC
-- main menu (SOMEONE'S PC / <name>'s PC / LOG OFF).  #228
--
-- pokered: the bedroom PC's hidden-object callback is OpenRedsPC
-- (engine/events/hidden_objects/players_pc.asm) which runs the PlayerPC
-- predef, versus the Pokemon Center PC callback which shows DisplayPCMainMenu.
--
--   SHOT_DIR=/tmp/bug228 POKEPORT_DRIVER=tests/drivers/pc_bug228_test.lua \
--     POKEPORT_IDENTITY=bug228 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Menu = require("src.ui.Menu")

  local pass = true
  local function check(cond, msg)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end

  -- Stand at (0,2) facing up so facingCell() = (0,1), the bedroom PC tile
  -- (field.lua hiddenExtras.pcTiles.REDS_HOUSE_2F = {{facing="up",x=0,y=1}}).
  U.teleport(game, "REDS_HOUSE_2F", 0, 2, "up")
  -- teleport bypasses New Game, which seeds pcItems={POTION=1}
  -- (src/core/SaveData.lua); seed it so the withdraw list has content.
  game.save.pcItems = game.save.pcItems or { POTION = 1 }

  U.tap(game, "a") -- interact -> tryHiddenObject -> the bedroom PC
  U.wait(8)

  local menu = game.stack:top()
  check(getmetatable(menu) == Menu, "a PC menu opened on A-press")
  U.shot(game, DIR .. "/pc_bug228_bedroom_menu.png")

  -- Inspect labels: the multi-PC main menu carries SOMEONE'S/BILL'S/<name>'s
  -- PC entries; the player's item PC does not.
  local labels = {}
  if menu and menu.items then
    for _, it in ipairs(menu.items) do
      labels[#labels + 1] = tostring(it.label)
    end
  end
  U.log("labels: " .. table.concat(labels, " | "))

  local function has(pat)
    for _, l in ipairs(labels) do
      if l:lower():find(pat, 1, true) then return true end
    end
    return false
  end

  -- BUG present if the multi-PC main menu opened.
  check(not has("someone"), "no SOMEONE'S PC entry (not the box-PC main menu)")
  check(not has("bill"),    "no BILL'S PC entry")
  check(not has("prof.oak"),"no PROF.OAK's PC entry")
  check(not has("'s pc"),   "no <name>'s PC entry (bedroom PC skips box storage)")

  -- CORRECT: the player's item PC opened first-row WITHDRAW ITEM.
  check(has("withdraw item"), "player item PC opened (WITHDRAW ITEM present)")
  check(menu and menu.items and menu.items[1]
        and tostring(menu.items[1].label) == "WITHDRAW ITEM",
        "first row is WITHDRAW ITEM")

  -- Visual proof: open the withdraw list to show the seeded POTION.
  if menu and menu.items and menu.items[1]
     and tostring(menu.items[1].label) == "WITHDRAW ITEM" then
    U.tap(game, "a") -- WITHDRAW ITEM
    U.wait(8)
    U.shot(game, DIR .. "/pc_bug228_withdraw.png")
  end

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
  love.event.quit(pass and 0 or 1)
end
