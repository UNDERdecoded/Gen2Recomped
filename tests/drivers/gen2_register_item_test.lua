-- Driver: Gen2's registerable key items reach the SELECT button.
--
-- ItemAttributes' property byte carries CANT_SELECT (1<<6) and CANT_TOSS
-- (1<<7), and Pack.ItemBallsKey_LoadSubmenu builds USE/GIVE/TOSS/SEL/QUIT out
-- of them.  The extractor read only the pocket byte, so nothing knew which
-- items could be registered and the pack never offered SEL at all.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_register_item_test.lua love .
local U = require("tests.drivers.util")

return function(game)
  local Bag = require("src.inventory.Bag")
  local BagMenu = require("src.ui.BagMenu")

  local pass, fail = 0, 0
  local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. what)
  end

  U.newGame(game)
  U.wait(20)

  -- 1. the property bits survived extraction ----------------------------
  local byKey = {}
  for id, def in pairs(game.data.items) do
    if def.key and def.key ~= "TERU_SAMA" then byKey[def.key] = id end
  end

  local WANT = { "BICYCLE", "ITEMFINDER", "OLD_ROD", "GOOD_ROD", "SUPER_ROD" }
  for _, key in ipairs(WANT) do
    local def = game.data.items[byKey[key] or ""]
    check(def ~= nil and def.registerable == true,
      key .. " is registerable")
  end

  -- ...and nothing else real is.  TERU-SAMA is the unused filler item, which
  -- carries a blank property byte in the ROM and never enters the bag.
  local extra = {}
  for _, def in pairs(game.data.items) do
    if def.registerable and def.key ~= "TERU_SAMA" then
      local wanted = false
      for _, key in ipairs(WANT) do if def.key == key then wanted = true end end
      if not wanted then extra[#extra + 1] = tostring(def.key) end
    end
  end
  check(#extra == 0, "no other item is registerable (" ..
    table.concat(extra, ",") .. ")")

  local potion = game.data.items[byKey.POTION or ""]
  check(potion ~= nil and not potion.registerable, "a POTION is not")
  check(potion ~= nil and not potion.cantToss, "and a POTION is tossable")
  local bike = game.data.items[byKey.BICYCLE or ""]
  check(bike ~= nil and bike.cantToss == true, "the BICYCLE is not tossable")

  -- 2. the pack offers SEL, and only on those items ----------------------
  local Menu = require("src.ui.Menu")
  local function submenuLabels(id)
    Bag.add(game.save, id, 1, game.data)
    local pocket = BagMenu.pocketOf(game.data.items[id], id)
    local index = 1
    for i, p in ipairs(BagMenu.POCKETS) do
      if p.key == pocket then index = i end
    end
    local list = BagMenu.new(game, { pocketIndex = index })
    game.stack:push(list)
    U.wait(4)
    for i, item in ipairs(list.items) do
      if item.value == id then list.index = i end
    end
    U.tap(game, "a")
    U.wait(6)
    local menu = game.stack:top()
    local labels = {}
    for _, o in ipairs((menu ~= list and menu.items) or {}) do
      labels[#labels + 1] = tostring(o.label)
    end
    while game.stack:top() ~= game.overworld do game.stack:pop() end
    U.wait(2)
    return table.concat(labels, "/"), menu ~= list
  end

  local rodLabels, opened = submenuLabels(byKey.GOOD_ROD)
  check(opened, "the pack opens a submenu on the GOOD ROD")
  check(rodLabels:find("SEL", 1, true) ~= nil,
    "the GOOD ROD submenu offers SEL (" .. rodLabels .. ")")
  local potionLabels = submenuLabels(byKey.POTION)
  check(potionLabels:find("SEL", 1, true) == nil,
    "a POTION's does not (" .. potionLabels .. ")")

  -- 3. SELECT in the overworld runs the registration ---------------------
  game.save.registeredItem = nil
  check(BagMenu.useRegistered(game) == false, "SELECT with nothing does nothing")

  game.save.registeredItem = byKey.GOOD_ROD
  U.teleport(game, "OLIVINE_CITY", 10, 10, "down")
  U.wait(10)
  check(BagMenu.useRegistered(game) == true,
    "SELECT uses the registered GOOD ROD")
  while game.stack:top() ~= game.overworld do game.stack:pop() end
  U.wait(2)

  -- a registration the player no longer holds is dropped, not run
  Bag.remove(game.save, byKey.GOOD_ROD, 99)
  check(BagMenu.useRegistered(game) == false,
    "SELECT with the item gone does nothing")
  check(game.save.registeredItem == nil, "and clears the registration")

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit(fail == 0 and 0 or 1)
end
