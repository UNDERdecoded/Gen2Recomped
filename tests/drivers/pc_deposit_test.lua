-- Driver: Player's PC deposit "How many?" with >7 bag stacks (#174).
-- pokered PrintListMenuEntries shows 4 names; PrintText + quantity box
-- must not overlap the list.
--   SHOT_DIR=/tmp/pc_deposit POKEPORT_DRIVER=tests/drivers/pc_deposit_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local PlayerPC = require("src.ui.PlayerPC")
  local ListMenu = require("src.ui.ListMenu")
  local QuantityBox = require("src.ui.QuantityBox")
  local Bag = require("src.inventory.Bag")

  local pass = true
  local function check(cond, msg)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end
  local function topIs(mt) return getmetatable(game.stack:top()) == mt end

  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  game.save.pcItems = {}
  -- >7 distinct depositable stacks (bug reproduces only then)
  local seed = {
    "POTION", "SUPER_POTION", "ANTIDOTE", "AWAKENING", "BURN_HEAL",
    "ICE_HEAL", "PARLYZ_HEAL", "FULL_HEAL", "REPEL", "POKE_BALL",
  }
  for _, id in ipairs(seed) do Bag.add(game.save, id, 5) end
  check(#seed > 7, "seeded more than 7 bag stacks")

  game.stack:push(PlayerPC.new(game))
  U.wait(4)
  U.tap(game, "down"); U.wait(1) -- DEPOSIT ITEM
  U.tap(game, "a"); U.wait(4)
  check(topIs(ListMenu), "DEPOSIT ITEM list opened")
  local list = game.stack:top()
  check(list.rows == 4, "deposit list uses 4 rows like PrintListMenuEntries")
  check(list.messageBox == true, "deposit list uses messageBox footer")
  check(#list.items > 7, "list has more than 7 depositable items")
  U.shot(game, DIR .. "/pc_deposit_0_list.png")

  -- pick first non-key stack (seed items are all quantity-prompted)
  U.tap(game, "a"); U.wait(4)
  check(topIs(QuantityBox), "quantity box on stack")
  check(list.footer == "How many?", "How many? footer set")
  U.shot(game, DIR .. "/pc_deposit_1_how_many.png")

  -- layout probe: list rows stay above the text box (ty=12 → y=96)
  local drawn = {}
  local Font = require("src.render.Font")
  local savedDraw, savedBox = Font.draw, Font.drawBox
  Font.draw = function(text, x, y)
    drawn[#drawn + 1] = { kind = "text", text = tostring(text), x = x, y = y }
    return savedDraw(text, x, y)
  end
  Font.drawBox = function(tx, ty, tw, th)
    drawn[#drawn + 1] = { kind = "box", tx = tx, ty = ty, tw = tw, th = th }
    return savedBox(tx, ty, tw, th)
  end
  game.stack:draw()
  Font.draw, Font.drawBox = savedDraw, savedBox

  local howY, qtyBox, textBox, maxItemY
  for _, d in ipairs(drawn) do
    if d.kind == "text" and d.text == "How many?" then howY = d.y end
    if d.kind == "box" and d.ty == 9 and d.tw == 5 then qtyBox = d end
    if d.kind == "box" and d.tx == 0 and d.ty == 12 and d.tw == 20 then
      textBox = d
    end
    if d.kind == "text" and tostring(d.text):match("^x%d") and d.y then
      if not maxItemY or d.y > maxItemY then maxItemY = d.y end
    end
  end
  check(howY == 112, "How many? sits on text-box first line (y=112)")
  check(textBox ~= nil, "bottom PrintText box drawn")
  check(qtyBox ~= nil, "quantity box at pokered row 9")
  check(maxItemY and maxItemY <= 72, "last visible item row above qty/text (y<=72)")
  if maxItemY and howY then
    check(maxItemY + 8 <= howY, "item glyphs do not overlap How many?")
  end

  U.tap(game, "a"); U.wait(6) -- confirm x01
  U.shot(game, DIR .. "/pc_deposit_2_stored.png")
  check(type(list.footer) == "string" and list.footer:find("stored", 1, true),
        "stored-via-PC footer after deposit")

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
  love.event.quit(pass and 0 or 1)
end
