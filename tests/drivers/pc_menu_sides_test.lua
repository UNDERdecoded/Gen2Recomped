-- Driver: Bill's PC vs player's PC top menus (#176).  Both should open
-- on the left (pokered BillsPCMenu / PlayersPCMenu TextBoxBorder at 0,0).
--   SHOT_DIR=/tmp/pc_sides POKEPORT_DRIVER=tests/drivers/pc_menu_sides_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local BoxMenu = require("src.ui.BoxMenu")
  local PlayerPC = require("src.ui.PlayerPC")

  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_MET_BILL = true

  game.stack:push(BoxMenu.new(game))
  U.wait(5)
  local bills = game.stack:top()
  U.log(("bills tx=%d ty=%d tw=%d th=%d"):format(
        bills.tx, bills.ty, bills.tw, bills.th))
  U.shot(game, DIR .. "/pc_0_bills.png")
  U.wait(8) -- let async captureScreenshot flush before pop
  game.stack:pop()
  U.wait(2)

  game.stack:push(PlayerPC.new(game))
  U.wait(5)
  local player = game.stack:top()
  U.log(("player tx=%d ty=%d tw=%d th=%d"):format(
        player.tx, player.ty, player.tw, player.th))
  U.shot(game, DIR .. "/pc_1_player.png")
  U.wait(8)

  local sameSide = player.tx == bills.tx and player.ty == bills.ty
  U.log(sameSide and "PASS: both menus share top-left origin"
                   or "FAIL: menus not on the same side")
  U.log("DONE")
  love.event.quit()
end
