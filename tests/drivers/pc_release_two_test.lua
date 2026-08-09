-- Driver: Bill's PC RELEASE two mons in one list session (#171).
--   SHOT_DIR=/tmp/pc_release POKEPORT_DRIVER=tests/drivers/pc_release_two_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Boxes = require("src.pokemon.Boxes")
  local BoxMenu = require("src.ui.BoxMenu")
  local ListMenu = require("src.ui.ListMenu")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local TextBox = require("src.render.TextBox")

  local pass = true
  local function check(cond, msg)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end
  local function topIs(mt) return getmetatable(game.stack:top()) == mt end
  local function mash(btn, cond, n)
    for _ = 1, (n or 240) do
      if cond() then return true end
      U.tap(game, btn)
      U.wait(2)
    end
    return false
  end

  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_MET_BILL = true
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1

  local box = Boxes.active(game.save)
  for i = #box, 1, -1 do box[i] = nil end
  box[1] = Pokemon.new(game.data, "RATTATA", 5)
  box[2] = Pokemon.new(game.data, "PIDGEY", 6)
  box[3] = Pokemon.new(game.data, "CATERPIE", 4)
  check(#box == 3, "seeded 3 boxed mons")

  game.stack:push(BoxMenu.new(game))
  U.wait(4)
  U.tap(game, "down"); U.wait(1)
  U.tap(game, "down"); U.wait(1)
  U.tap(game, "a") -- RELEASE
  check(mash("a", function() return topIs(ListMenu) end, 20), "RELEASE list opened")
  U.shot(game, DIR .. "/pc_release_0_list.png")

  local function releaseOne(label)
    check(topIs(ListMenu), label .. ": still on release list")
    local before = #Boxes.active(game.save)
    U.tap(game, "a") -- pick current row
    check(mash("a", function() return topIs(ChoiceBox) end), label .. ": confirm choice")
    U.shot(game, DIR .. "/pc_release_" .. label .. "_confirm.png")
    U.tap(game, "up"); U.wait(1) -- defaultNo -> YES
    U.tap(game, "a")
    check(mash("a", function()
      return topIs(ListMenu) or (#game.stack.states > 0 and topIs(TextBox) == false)
    end), label .. ": bye text advancing")
    check(mash("a", function() return topIs(ListMenu) end), label .. ": back on list")
    local after = #Boxes.active(game.save)
    check(after == before - 1, label .. ": box count " .. before .. " -> " .. after)
    U.shot(game, DIR .. "/pc_release_" .. label .. "_list.png")
  end

  releaseOne("1st")
  releaseOne("2nd")

  check(#Boxes.active(game.save) == 1, "one mon remains after two releases")
  check(topIs(ListMenu), "still in RELEASE list without re-entering")
  U.shot(game, DIR .. "/pc_release_done.png")

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
  love.event.quit(pass and 0 or 1)
end
