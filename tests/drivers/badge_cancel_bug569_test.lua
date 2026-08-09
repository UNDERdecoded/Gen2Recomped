-- The Cerulean badge man's list needs a CANCEL row (#569).
-- CeruleanBadgeHouseMiddleAgedManText loops DisplayListMenuID over
-- .BadgeItemList and takes `jr c, .done` out (pokered
-- scripts/CeruleanBadgeHouse.asm); PrintListMenuEntries prints
-- ListMenuCancelText at the list's $FF terminator, so CANCEL is a real row
-- and choosing it sets carry the same way B does.
--   POKEPORT_DRIVER=tests/drivers/badge_cancel_bug569_test.lua POKEPORT_IDENTITY=bug569 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ListMenu = require("src.ui.ListMenu")
  local TextBox = require("src.render.TextBox")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- pokered data/maps/objects/CeruleanBadgeHouse.asm: the middle-aged man is
  -- object_event 5, 3, STAY, so he never wanders off the tile; the floor to
  -- his west is the natural approach.
  local MAP = "CERULEAN_BADGE_HOUSE"
  local NPC = "CERULEANBADGEHOUSE_MIDDLE_AGED_MAN"
  local STAND = { x = 4, y = 3, facing = "right" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- a renamed or unextracted text label reads on screen exactly like the
  -- missing row did: nothing happens
  local t = game.data.text
  for _, key in ipairs({
    "_CeruleanBadgeHouseMiddleAgedManText",
    "_CeruleanBadgeHouseMiddleAgedManWhichBadgeText",
    "_CeruleanBadgeHouseMiddleAgedManVisitAnyTimeText",
    "_CeruleanBadgeHouseBoulderBadgeText",
  }) do
    check(key .. " resolves to a string", type(t[key]) == "string")
  end

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  local function manIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == NPC then return n end
    end
    return nil
  end

  local function facingTheMan()
    local ow = game.overworld
    local man = ow and manIn(ow)
    if not man then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == man
  end

  local ow = game.overworld
  local man = ow and manIn(ow)
  check("the badge man is on " .. MAP, man ~= nil)

  if man and not facingTheMan() then
    -- a map edit moved him: take any free walkable neighbour instead.
    -- {dx, dy, facing} is the offset from him to the stand cell plus the
    -- direction that looks back, so +1 on x means facing left.
    local sides = {
      { -1, 0, "right" }, { 1, 0, "left" }, { 0, 1, "up" }, { 0, -1, "down" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = man.cellX + s[1], man.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("approach cell is blocked, standing on", cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing in front of the badge man", facingTheMan())

  -- talk, then mash through the greeting and the "Which badge?" prompt
  U.tap(game, "a")
  U.wait(20)
  -- the greeting runs three pages before the "Which badge?" prompt, so give
  -- the mash room; an A landing mid-type only speeds that page up
  local list
  for _ = 1, 60 do
    local top = game.stack:top()
    if getmetatable(top) == ListMenu then list = top break end
    if getmetatable(top) == TextBox then U.tap(game, "a") end
    U.wait(10)
  end
  check("talking to him opened the badge list", list ~= nil)

  if list then
    local labels = {}
    for i, item in ipairs(list.items) do labels[i] = item.label end
    U.log("badge list rows:", table.concat(labels, " "))
    check("the list has the eight badges plus one more row", #list.items == 9)
    local last = list.items[#list.items]
    check("the last row is CANCEL", last.label == "CANCEL")
    check("the CANCEL row carries no badge to describe", last.value == nil)

    -- scroll it into view so the screenshot shows the row, not just the data
    for _ = 1, #list.items do
      if list.index == #list.items then break end
      U.tap(game, "down")
      U.wait(3)
    end
    check("cursor reached CANCEL", list.index == #list.items)
    check("badge list screenshot",
          U.shot(game, SHOT_DIR .. "/bug569_badge_list.png"))

    U.tap(game, "a")
    U.wait(25)
    local top = game.stack:top()
    check("CANCEL closed the list", getmetatable(top) ~= ListMenu)
    check("CANCEL printed the goodbye line, like B does",
          getmetatable(top) == TextBox)
    check("goodbye screenshot",
          U.shot(game, SHOT_DIR .. "/bug569_after_cancel.png"))
    U.tap(game, "a")
    U.wait(25)
  end

  U.log("The goodbye line has been dismissed; press A on the man to run the")
  U.log("list again.  CANCEL should be the ninth row under EARTHBADGE and")
  U.log("should close the whole conversation with \"Visit any time\" -- the")
  U.log("near miss is a CANCEL that only closes the list and drops you back")
  U.log("on the \"Which badge?\" prompt.  The badge rows above it are the")
  U.log("control: each prints its description and returns to the list.")
  U.log("Screenshots are under " .. SHOT_DIR)

  while true do
    coroutine.yield()
  end
end
