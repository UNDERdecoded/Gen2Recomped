-- Eye check on the Viridian caterpillar speech (#250): no test can judge
-- "the text went by too fast to read".
-- pokered text/ViridianCity.asm spells that answer with line, cont and para,
-- which TextBox maps to \n, \v and \f.  The port's literal fallback (the label
-- has no leading underscore, so it is not in text.lua) had all three as \n.
--   POKEPORT_DRIVER=tests/drivers/caterpillar_text_bug250_test.lua POKEPORT_IDENTITY=bug250 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local MAP = "VIRIDIAN_CITY"
  local NPC = "VIRIDIANCITY_YOUNGSTER2"
  local TEXT = "TEXT_VIRIDIANCITY_YOUNGSTER2"

  -- a missing handler, or an NPC who wandered off, ends in "no text", which is
  -- not the same failure as "text that does not wait"
  local mapScripts = require("data.scripts.init")
  check("a hand-ported handler exists for " .. TEXT,
        mapScripts.talkScript(MAP, TEXT) ~= nil)

  -- the page break and the scroll are what make the box wait for a button
  local TextBox = require("src.render.TextBox")
  local desc = "CATERPIE has no\npoison, but\vWEEDLE does.\fWatch out for its\nPOISON STING!"
  local pages = TextBox.paginate(desc)
  check("the description spans two pages (para -> \\f)", #pages == 2)
  check("page 1 is three lines (text + line + cont)",
        pages[1] ~= nil and #pages[1] == 3)
  check("page 2 is two lines (para + line)",
        pages[2] ~= nil and #pages[2] == 2)
  -- contBefore marks the line the box holds on until a button press
  check("line 3 waits for a button before scrolling in",
        pages.contBefore and pages.contBefore[1] and pages.contBefore[1][3] == true)

  U.teleport(game, MAP, 30, 26, "up")
  U.wait(30)

  local function target()
    for _, n in ipairs(game.overworld and game.overworld.npcs or {}) do
      if n.def and n.def.name == NPC then return n end
    end
    return nil
  end

  local npc = target()
  check("the youngster is loaded on " .. MAP, npc ~= nil)
  -- pin the wander: he strolls out from under the A press between reads
  if npc then npc.wanders = false end

  -- pokered data/maps/objects/ViridianCity.asm puts him at (30,25), so (30,26)
  -- faces him; if a map edit moves him, the fallback below picks a free
  -- walkable neighbour instead of parking the player at a wall.
  local function facingTarget()
    local ow = game.overworld
    if not (ow and npc) then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == npc
  end

  if npc and not facingTarget() then
    local ow = game.overworld
    for _, s in ipairs({ { 0, 1, "up" }, { 1, 0, "left" },
                         { -1, 0, "right" }, { 0, -1, "down" } }) do
      local cx, cy = npc.cellX + s[1], npc.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("approach cell blocked, standing on", cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing in front of the youngster", facingTarget())

  U.log("Press A to talk, answer YES, and read the description.")
  U.log("It should stop for you three times, and the page should CLEAR before")
  U.log("'Watch out for its POISON STING!' -- under #250 all six lines poured")
  U.log("past in one go.  Answering NO is the control: one line, no waits.")

  while true do
    coroutine.yield()
  end
end
