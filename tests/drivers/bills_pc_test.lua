-- Driver: Bill's PC (#177) -- chrome (What? / BOX No. / <PK><MN>) and
-- withdraw/deposit returning to BillsPCMenu instead of closing the PC.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Boxes = require("src.pokemon.Boxes")
  local Menu = require("src.ui.Menu")
  local ListMenu = require("src.ui.ListMenu")
  local TextBox = require("src.render.TextBox")
  local Pokemon = require("src.pokemon.Pokemon")

  local pass = true
  local function check(cond, msg)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end
  local function topIs(mt) return getmetatable(game.stack:top()) == mt end
  local function topMenu()
    local top = game.stack:top()
    return getmetatable(top) == Menu and top or nil
  end
  local function mash(btn, cond, frames)
    for _ = 1, frames or 120 do
      if cond() then return true end
      U.tap(game, btn)
      U.wait(3)
    end
    return false
  end

  -- party + box stocked so withdraw and deposit both work
  game.save.party = {
    Pokemon.new(game.data, "PIKACHU", 12),
    Pokemon.new(game.data, "EEVEE", 10),
  }
  Boxes.ensure(game.save)
  game.save.currentBox = 1
  game.save.boxes[1] = {
    Pokemon.new(game.data, "SPEAROW", 8),
    Pokemon.new(game.data, "RATTATA", 6),
  }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_MET_BILL = true

  -- PC tile at (13,3); stand on (13,4) facing up
  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  local ow = game.overworld

  U.tap(game, "a") -- open PC
  U.wait(6)
  check(topIs(Menu), "PC main menu opened")
  U.tap(game, "a") -- BILL'S PC
  U.wait(8)
  local bills = topMenu()
  check(bills ~= nil, "Bill's PC menu opened")
  check(bills and bills.items[1] and bills.items[1].label:find("<PK>", 1, true),
        "WITHDRAW label includes <PK><MN> icon tokens")
  U.shot(game, DIR .. "/bills_pc_1_menu.png")

  -- WITHDRAW first box mon
  U.tap(game, "a") -- WITHDRAW
  U.wait(8)
  check(topIs(ListMenu), "withdraw list opened")
  U.tap(game, "a") -- pick SPEAROW
  U.wait(6)
  check(topIs(Menu), "withdraw mon submenu opened")
  U.tap(game, "a") -- WITHDRAW action
  U.wait(6)
  check(mash("a", function() return topIs(TextBox) end, 60),
        "withdraw shows taken-out text")
  -- let the typewriter finish so the shot shows the taken-out line
  for _ = 1, 90 do
    local tb = game.stack:top()
    if getmetatable(tb) == TextBox and (tb.waiting or tb.done) then break end
    U.wait(2)
  end
  U.shot(game, DIR .. "/bills_pc_2_withdraw_text.png")
  check(mash("a", function()
    local m = topMenu()
    return m and m.items and m.items[1]
      and tostring(m.items[1].label):find("WITHDRAW", 1, true)
  end, 120), "after withdraw, back on Bill's PC menu")
  check(#game.save.party == 3, "party gained the withdrawn mon")
  check(#game.save.boxes[1] == 1, "box lost the withdrawn mon")
  U.shot(game, DIR .. "/bills_pc_3_menu_after_withdraw.png")

  -- DEPOSIT party lead (PIKACHU)
  U.tap(game, "down") -- DEPOSIT
  U.wait(2)
  U.tap(game, "a")
  U.wait(8)
  check(topIs(ListMenu), "deposit list opened")
  U.tap(game, "a") -- first party mon
  U.wait(6)
  check(topIs(Menu), "deposit mon submenu opened")
  U.tap(game, "a") -- DEPOSIT action
  U.wait(6)
  check(mash("a", function() return topIs(TextBox) end, 60),
        "deposit shows stored text")
  for _ = 1, 90 do
    local tb = game.stack:top()
    if getmetatable(tb) == TextBox and (tb.waiting or tb.done) then break end
    U.wait(2)
  end
  U.shot(game, DIR .. "/bills_pc_4_deposit_text.png")
  check(mash("a", function()
    local m = topMenu()
    return m and m.items and m.items[1]
      and tostring(m.items[1].label):find("WITHDRAW", 1, true)
  end, 120), "after deposit, back on Bill's PC menu")
  check(#game.save.party == 2, "party lost the deposited mon")
  check(#game.save.boxes[1] == 2, "box gained the deposited mon")
  U.shot(game, DIR .. "/bills_pc_5_menu_after_deposit.png")

  -- still inside the PC (not back on the overworld)
  check(game.stack:top() ~= ow, "PC still open after transfers")
  check(not topIs(ListMenu), "not stuck in a transfer list")

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
end
