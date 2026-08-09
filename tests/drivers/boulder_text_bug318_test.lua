-- Manual check that a boulder answers an A press (#318).
-- Every boulder points at BoulderText (pokered home/overworld_text.asm:16),
-- i.e. _BoulderText "This requires\nSTRENGTH to move!", which the extractor
-- stores as an asm label with no text: resolveText returned nil and A did
-- nothing.  The data half is asserted in tests/parity_asm_plain_text.lua.
--   POKEPORT_DRIVER=tests/drivers/boulder_text_bug318_test.lua POKEPORT_IDENTITY=bug318 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  -- pokered data/maps/objects/VictoryRoad1F.asm: BOULDER3 sits at (2, 10) with
  -- wall to its east and west, so the only free approach is the floor below it.
  -- Talking to a boulder needs no STRENGTH and no badge.
  local MAP = "VICTORY_ROAD_1F"
  local BOULDER = "VICTORYROAD1F_BOULDER3"
  local TEXT = "TEXT_VICTORYROAD1F_BOULDER3"
  local MAP_LABEL = "VictoryRoad1F"
  local STAND = { x = 2, y = 11, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- a missing string, a renamed label and an unreached fallback all show up as
  -- the same nothing-happens the bug did
  local text = game.data:resolveText(MAP_LABEL, TEXT)
  check(MAP_LABEL .. "/" .. TEXT .. " resolves to a string",
        type(text) == "string" and text ~= "")
  check("it is _BoulderText verbatim", text == game.data.text._BoulderText)
  check("it mentions STRENGTH",
        type(text) == "string" and text:find("STRENGTH", 1, true) ~= nil)
  if type(text) == "string" then
    U.log("boulder text reads:", (text:gsub("\n", " / ")))
  end

  -- park the player against the boulder
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  local function boulderIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == BOULDER then return n end
    end
    return nil
  end

  -- re-reads game.overworld every call: the fallback below teleports again and
  -- that rebuilds the state and its npc list
  local function facingTheBoulder()
    local ow = game.overworld
    local rock = ow and boulderIn(ow)
    if not rock then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == rock
  end

  local ow = game.overworld
  local rock = ow and boulderIn(ow)
  check("boulder object loaded on " .. MAP, rock ~= nil)

  if rock and not facingTheBoulder() then
    -- a map edit or a mod moved the object: fall back to any free walkable
    -- neighbour.  {dx, dy, facing} is the offset from the boulder to the stand
    -- cell plus the direction that looks back at it, so +1 on x means left.
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = rock.cellX + s[1], rock.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("approach cell (%d, %d) is blocked, standing on")
                :format(STAND.x, STAND.y), cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing against the boulder", facingTheBoulder())

  -- press A here so the log can tell "no text entry" from "the press never
  -- reached the boulder"; on screen the two look identical
  local TextBox = require("src.render.TextBox")
  U.tap(game, "a")
  U.wait(30)

  local top = game.stack:top()
  local isBox = getmetatable(top) == TextBox
  check("pressing A opened a text box", isBox)
  if isBox then
    local shown = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do shown[#shown + 1] = line end
    end
    local joined = table.concat(shown, " / ")
    U.log("box reads:", joined)
    check("the box is the boulder line, not something else",
          joined:find("STRENGTH", 1, true) ~= nil)
    local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
    U.shot(game, SHOT_DIR .. "/bug318_boulder.png")
    U.log("captured", SHOT_DIR .. "/bug318_boulder.png")
  end

  U.log("The boulder has been talked to already; the box on screen is that.")
  U.log("It should type \"This requires\" / \"STRENGTH to move!\" and wait for")
  U.log("A or B.  Before #318 the press did nothing at all: no box, no sound.")
  U.log("Two more boulders on this floor, at (5,15) and (14,2).")

  while true do
    coroutine.yield()
  end
end
