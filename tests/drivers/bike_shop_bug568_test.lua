-- Look at the two boxes a test cannot judge: the bike shop's BICYCLE/CANCEL
-- price window (#568) and a Pokemon Center bench guy answering A (#488).
-- Oracle: scripts/BikeShop.asm BikeShopClerkText (TextBoxBorder 0,0 b=4 c=15
-- over BikeShopMenuText/BikeShopMenuPrice) and data/events/bench_guys.asm.
-- The logic halves are asserted in tests/parity_bike_shop_clerk_bug568.lua
-- and tests/parity_bench_guy_facing_bug488.lua.
--   POKEPORT_DRIVER=tests/drivers/bike_shop_bug568_test.lua POKEPORT_IDENTITY=bug568 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function boxOnScreen()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local lines = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    return top, table.concat(lines, " / ")
  end

  -- A missing string or a renamed label goes quiet in exactly the way both
  -- bugs did, so resolve everything first and say so before anyone looks.
  local t = game.data.text
  for _, label in ipairs({ "_BikeShopClerkWelcomeText",
      "_BikeShopClerkDoYouLikeItText", "_BikeShopCantAffordText",
      "_BikeShopComeAgainText", "_VermilionPokecenterGuyText" }) do
    check(label .. " resolves", type(t[label]) == "string" and t[label] ~= "")
  end
  check("BICYCLE is an item the window can name",
        game.data.items.BICYCLE ~= nil)

  local seat = (game.data.field.hiddenExtras.benchGuys.VERMILION_POKECENTER
                or {})[1]
  check("the Vermilion bench guy is in the generated data", seat ~= nil)
  check("his seat is faced from the left (BenchGuyTextPointers)",
        seat and seat.textFacing == "left")

  if failures > 0 then
    U.log(failures, "check(s) failed above; the screens below will not tell")
    U.log("you anything the log has not already said.")
  end

  -- ------------------------------------------------------------- #488
  -- data/events/hidden_events.asm parks the seat at (0,4); it is the bench
  -- wall itself, so the player stands on the floor tile east of it.  The
  -- cell north of the seat is walkable too and is the control: in the
  -- original, PrintBenchGuyText only answers a LEFT facing, so an A press
  -- from up there does nothing, and that is correct.
  local BENCH = { map = "VERMILION_POKECENTER", x = seat and seat.x or 0,
                  y = seat and seat.y or 4 }

  U.teleport(game, BENCH.map, BENCH.x, BENCH.y - 1, "down")
  U.wait(10)
  U.tap(game, "a")
  U.wait(20)
  check("facing the seat from the north stays silent, like the original",
        boxOnScreen() == nil)

  -- the seat's own approach, with a fallback in case a map edit walls it in
  local stand = { x = BENCH.x + 1, y = BENCH.y, facing = "left" }
  if not game.overworld.map:isWalkableCell(stand.x, stand.y) then
    for _, side in ipairs({ { -1, 0, "right" }, { 0, 1, "up" }, { 0, -1, "down" } }) do
      local cx, cy = BENCH.x + side[1], BENCH.y + side[2]
      if game.overworld.map:isWalkableCell(cx, cy) then
        U.log("the floor east of the seat is gone; standing at", cx, cy)
        stand = { x = cx, y = cy, facing = side[3] }
        break
      end
    end
  end
  U.teleport(game, BENCH.map, stand.x, stand.y, stand.facing)
  U.wait(10)
  U.tap(game, "a")
  U.wait(90) -- let the first page finish typing before the shot
  local box, text = boxOnScreen()
  check("A from the east opens the bench guy's box (#488)", box ~= nil)
  if box then
    U.log("bench guy reads:", text)
    check("it is his line about no universally strong POKeMON",
          text:find("universally", 1, true) ~= nil)
    check("screenshot on disk",
          U.shot(game, SHOT_DIR .. "/bug488_bench_guy.png"))
    U.log("captured", SHOT_DIR .. "/bug488_bench_guy.png")
    U.tap(game, "a")
    U.wait(20)
  end

  -- ------------------------------------------------------------- #568
  -- pokered data/maps/objects/BikeShop.asm: the clerk stands at (6,2)
  -- behind the counter row, so the player talks across it from (6,4).
  -- Clear the bike and the voucher so the talk takes the sales pitch.
  game.save.inventory.BICYCLE = nil
  game.save.inventory.BIKE_VOUCHER = nil
  game.save.flags.EVENT_GOT_BICYCLE = nil

  U.teleport(game, "BIKE_SHOP", 6, 4, "up")
  U.wait(10)

  local ow = game.overworld
  local clerk
  for _, n in ipairs(ow.npcs or {}) do
    if n.def and n.def.name == "BIKESHOP_CLERK" then clerk = n end
    -- the middle-aged woman paces; park her so she cannot wander into shot
    if n.def and n.def.name == "BIKESHOP_MIDDLE_AGED_WOMAN" then
      n.frozen = true
    end
  end
  check("the clerk is on the map", clerk ~= nil)

  -- talking across a counter reads one cell further, so the stand cell is
  -- two south of him; fall back to any free neighbour if the shop is redrawn
  local function facingTheClerk()
    local w = game.overworld
    local fx, fy = w.player:facingCell()
    if w:npcAtCell(fx, fy) == clerk then return true end
    if not w.map:isCounterCell(fx, fy) then return false end
    local Collision = require("src.world.Collision")
    local bx, by = Collision.target(fx, fy, w.player.facing)
    return w:npcAtCell(bx, by) == clerk
  end
  if clerk and not facingTheClerk() then
    for _, side in ipairs({ { 0, 2, "up" }, { 0, 1, "up" }, { 0, -1, "down" },
                            { 1, 0, "left" }, { -1, 0, "right" } }) do
      local cx, cy = clerk.cellX + side[1], clerk.cellY + side[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("(6,4) no longer reaches the counter; standing at", cx, cy)
        U.teleport(game, "BIKE_SHOP", cx, cy, side[3])
        U.wait(10)
        break
      end
    end
  end
  check("the player is at the counter", facingTheClerk())

  U.tap(game, "a")
  U.wait(20)
  local _, welcome = boxOnScreen()
  check("A opens the welcome line", welcome ~= nil)
  if welcome then U.log("clerk reads:", welcome) end

  -- mash through the welcome box; the pitch box then types itself out and
  -- pops on its own, handing the screen to the price window
  local window
  for _ = 1, 200 do
    local top = game.stack:top()
    if top ~= game.overworld and getmetatable(top) ~= TextBox then
      window = top
      break
    end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the price window is up and holding input (#568)", window ~= nil)
  if window then
    check("the cursor starts on BICYCLE", window.index == 1)
    check("it kept the pitch line for the bottom box",
          type(window.footer) == "table" and #window.footer > 0)
    check("screenshot on disk",
          U.shot(game, SHOT_DIR .. "/bug568_price_window.png"))
    U.log("captured", SHOT_DIR .. "/bug568_price_window.png")
  end

  U.log("The window on screen is the shop menu: BICYCLE over CANCEL at the")
  U.log("top left, \194\1651000000 beside the BICYCLE row, cursor on BICYCLE, and")
  U.log("\"It's a cool BIKE! Do you want it?\" still in the bottom box under it.")
  U.log("Input is live. Up and down move between the two rows and clamp -- the")
  U.log("cursor must not wrap. A buys, B or CANCEL backs out; either way the")
  U.log("window has to stay on screen behind the closing lines and only")
  U.log("disappear with \"Come back again some time!\". A window that vanishes")
  U.log("the moment you answer, or a bottom box that blanks while the menu is")
  U.log("up, is the near miss to watch for. Talk to him again to replay it.")
  U.log("The boy by the door is the control: he has no menu, just a line.")

  while true do
    coroutine.yield()
  end
end
