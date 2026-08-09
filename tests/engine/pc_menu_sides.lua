-- Bill's PC vs player's PC top-menu origin/size (#176).
-- ROM-free: uses the fixture dataset so CI (no data/generated/) stays green.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

local SaveData = require("src.core.SaveData")
local BoxMenu = require("src.ui.BoxMenu")
local PlayerPC = require("src.ui.PlayerPC")

local game = {
  data = Data,
  save = SaveData.newGame(),
  stack = { push = function() end },
}

local bills = BoxMenu.new(game)
local player = PlayerPC.new(game)

T.eq(bills.tx, 0, "Bill's PC TextBoxBorder at x=0")
T.eq(player.tx, 0, "Player's PC TextBoxBorder at x=0")
T.eq(player.ty, 0, "Player's PC at y=0")
T.eq(player.tw, 16, "Player's PC width (players_pc.asm c=$e +2)")
T.eq(player.th, 10, "Player's PC height (players_pc.asm b=$8 +2)")
T.check(player.tx == bills.tx and player.ty == bills.ty,
        "both PC menus share the same top-left origin")
local labelTiles = 2 + #"WITHDRAW ITEM"
T.check(player.tx + labelTiles <= player.tx + player.tw - 1,
        "WITHDRAW ITEM fits inside the Player's PC border")

T.finish("pc_menu_sides")
