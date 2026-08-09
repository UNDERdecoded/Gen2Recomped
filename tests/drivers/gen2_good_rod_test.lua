-- Driver: the Good Rod fisherman in Olivine runs the ROM's own script.
--
-- scripts/OlivineGoodRodHouse.asm GoodRodGuru is plain bytecode the Gen2 VM
-- lowers on its own (S51_46FC).  data/scripts/story_gen2.lua carried a
-- hand-ported stand-in for the same TEXT constant, and since init.lua attaches
-- the hand-ported modules AFTER the VM the stand-in won -- with text keys
-- (OfferGoodRodText and friends) that only exist as pret labels, never in the
-- decoded text table.  So the guru said nothing and handed nothing over.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_good_rod_test.lua love .
local U = require("tests.drivers.util")

local MAP = "OLIVINE_GOOD_ROD_HOUSE"
local TEXT = "TEXT_OLIVINE_GOOD_ROD_HOUSE_OBJ_001"
local ROD = "ITEM_059"          -- GOOD_ROD
local FLAG = "EVENT_G2_0024"    -- EVENT_GOT_GOOD_ROD

return function(game)
  local MapScripts = require("src.script.MapScripts")
  local ScriptRunner = require("src.script.ScriptRunner")
  local function held() return game.save.inventory[ROD] or 0 end

  local pass, fail = 0, 0
  local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. what)
  end

  U.newGame(game)
  U.wait(20)

  -- 1. the script the guru runs is the lowered ROM one -------------------
  local rows = MapScripts.talkScript(MAP, TEXT)
  check(type(rows) == "table" and #rows > 0, "the guru has a talk script")
  if type(rows) ~= "table" then
    U.log(("RESULT FAIL (%d pass, %d fail)"):format(pass, fail + 1))
    love.event.quit(1)
    return
  end

  -- the offer rides the g2_yesno row: lowering folds the writetext that
  -- opened the box into the prompt rather than printing the line twice
  local verbs, texts = {}, {}
  for _, row in ipairs(rows) do
    verbs[row[1]] = (verbs[row[1]] or 0) + 1
    if row[1] == "show_text" or row[1] == "g2_yesno" then
      texts[#texts + 1] = row[2]
    end
  end

  check(#ScriptRunner.validate(rows) == 0, "every lowered row resolves")
  check(verbs.g2_yesno ~= nil, "the guru asks before giving")
  check(verbs.give_item ~= nil, "the script gives an item")
  check(verbs.check_flag ~= nil and verbs.set_flag ~= nil,
    "the script gates itself on an event flag")

  local gave, flagged = false, false
  for _, row in ipairs(rows) do
    if row[1] == "give_item" and row[2] == ROD then gave = true end
    if row[1] == "set_flag" and row[2] == FLAG then flagged = true end
  end
  check(gave, "the item is the GOOD ROD (" .. ROD .. ")")
  check(flagged, "the once-only flag is " .. FLAG)

  -- 2. every line it speaks is real ROM text, not a stand-in label -------
  check(#texts >= 3, "the guru has at least three lines (" .. #texts .. ")")
  local spoken = {}
  for _, key in ipairs(texts) do
    local s = game.data.text[key]
    check(type(s) == "string" and #s > 0 and not s:find("{GEN2_TEXT:", 1, true),
      "text " .. key .. " is decoded ROM text")
    spoken[#spoken + 1] = tostring(s)
  end
  local all = table.concat(spoken, "\n")
  check(all:find("fished here", 1, true) ~= nil,
    "the offer is the ROM's \"I've fished here for 30 years\"")
  check(all:find("new angler", 1, true) ~= nil,
    "the handover is the ROM's \"a new angler\"")

  -- 3. and it plays out: walk up, say yes, the rod lands in the bag ------
  game.save.flags = game.save.flags or {}
  game.save.flags[FLAG] = nil
  check(held() == 0, "the bag starts without a Good Rod")

  U.teleport(game, MAP, 2, 4, "up")
  U.wait(20)
  -- four pages of offer, the yes/no, then the handover: tap no faster than
  -- the box types, or the presses land mid-page and are eaten
  for _ = 1, 80 do
    U.tap(game, "a")
    U.wait(14)
    if held() > 0 and game.save.flags[FLAG] then break end
  end
  U.wait(10)

  check(held() == 1,
    "talking to the guru puts one Good Rod in the bag (got "
    .. tostring(held()) .. ")")
  check(game.save.flags[FLAG] == true, "and sets " .. FLAG)

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit(fail == 0 and 0 or 1)
end
