-- Driver: Gen2 day/night wild tables, Unown letter forms and the Ruins of
-- Alph wall-puzzle data.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_daynight_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Encounter = require("src.world.Encounter")
  local Sprites = require("src.pokemon.Sprites")

  local pass, fail = 0, 0
  local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. what)
  end

  U.newGame(game)
  U.wait(20)

  local data = game.data

  -- ---------------------------------------------------------- day/night
  local withTime, differing = 0, 0
  for _, def in pairs(data.encounters or {}) do
    local grass = def.grass
    if grass and grass.byTime and grass.byTime.morn and grass.byTime.nite then
      withTime = withTime + 1
      local day = grass.slots[1]
      local nite = grass.byTime.nite.slots[1]
      if day and nite and day.species ~= nite.species then
        differing = differing + 1
      end
    end
  end
  check(withTime > 50, "grass tables carry morn/nite slot sets (" .. withTime .. ")")
  check(differing > 10,
    "night wilds actually differ from day wilds (" .. differing .. " tables)")

  local sample
  for _, def in pairs(data.encounters or {}) do
    if def.grass and def.grass.byTime then sample = def.grass break end
  end
  check(sample ~= nil, "found a grass table with time-of-day sets")
  if sample then
    check(Encounter.atTime(sample, "DAY") == sample,
      "DAY resolves to the base grass table")
    check(Encounter.atTime(sample, "NIGHT") == sample.byTime.nite,
      "NIGHT resolves to the nite table")
    check(Encounter.atTime(sample, "MORNING") == sample.byTime.morn,
      "MORNING resolves to the morn table")
  end
  check(Encounter.atTime(nil, "NIGHT") == nil, "no table resolves to nothing")

  local tod = game.overworld and game.overworld:timeOfDay()
  -- a mod may rename the period through the world.tod hook, so accept the
  -- vanilla spellings, their NIGHT/MORN aliases, and the extra dusk/dawn
  -- periods the shipped Dramatic Shapes cycle adds (EVENING, DAWN, DUSK)
  check(tod == "MORNING" or tod == "MORN" or tod == "DAY"
    or tod == "NITE" or tod == "NIGHT"
    or tod == "EVENING" or tod == "DAWN" or tod == "DUSK",
    "the overworld reports a Gen2 clock period (" .. tostring(tod) .. ")")

  -- ------------------------------------------------------- Unown letters
  local unown
  for _, def in pairs(data.pokemon or {}) do
    if def.name == "UNOWN" then unown = def break end
  end
  check(unown ~= nil, "the UNOWN species record exists")
  if unown then
    check(type(unown.forms) == "table" and #unown.forms == 26,
      "UNOWN carries 26 letter forms")
    local distinct, n = {}, 0
    for _, form in ipairs(unown.forms or {}) do
      if not distinct[form.spriteFront] then
        distinct[form.spriteFront] = true
        n = n + 1
      end
    end
    check(n == 26, "every letter has its own front pic (" .. n .. ")")

    -- GetUnownLetter: all-zero DVs -> letter 1 (A); all-15 DVs -> 26 (Z)
    check(Sprites.formIndex(unown,
      { dvs = { attack = 0, defense = 0, speed = 0, special = 0 } }) == 1,
      "DVs 0/0/0/0 give letter A")
    check(Sprites.formIndex(unown,
      { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } }) == 26,
      "DVs 15/15/15/15 give letter Z")
    check(Sprites.formIndex(unown,
      { dvs = { attack = 6, defense = 6, speed = 6, special = 6 } })
      == Sprites.formIndex(unown,
      { dvs = { attack = 7, defense = 7, speed = 7, special = 7 } }),
      "only the middle two DV bits pick the letter")

    local seen, reached = {}, 0
    for atk = 0, 15 do
      for dv = 0, 15 do
        local i = Sprites.formIndex(unown,
          { dvs = { attack = atk, defense = dv, speed = atk, special = dv } })
        if i and not seen[i] then seen[i] = true reached = reached + 1 end
      end
    end
    check(reached > 10, "a DV sweep reaches many letters (" .. reached .. ")")

    local path = Sprites.path(data, unown.id, "front",
      { mon = { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } } })
    check(path == unown.forms[26].spriteFront,
      "Sprites.path picks the letter's pic for a live mon")
    check(Sprites.path(data, unown.id, "front") == unown.spriteFront,
      "with no mon the dex still gets the default pic")

    local other
    for _, def in pairs(data.pokemon or {}) do
      if def.name == "PIKACHU" then other = def break end
    end
    check(other ~= nil and Sprites.formIndex(other, { dvs = { attack = 15 } }) == nil,
      "a formless species has no form index")
  end

  -- ---------------------------------------------------------- the puzzle
  local puzzle = data.unown_puzzle
  check(type(puzzle) == "table", "the unown_puzzle dataset loaded")
  if type(puzzle) == "table" then
    check(puzzle.width == 6 and puzzle.height == 6, "the board is 6x6")
    check(#puzzle.start == 16, "16 start positions")
    check(#puzzle.solved == 36, "a 36-cell solved configuration")
    check(#puzzle.puzzles == 4, "4 pictures (Kabuto/Omanyte/Aerodactyl/Ho-Oh)")
    check(puzzle.puzzles[1].name == "kabuto",
      "picture 0 is Kabuto, matching the chamber's `setval 0`")

    local UnownPuzzle = require("src.ui.UnownPuzzle")
    local state = UnownPuzzle.new(game, 0, function() end)
    check(not state:solved(), "the start layout is not already solved")
    local placed = 0
    for i = 1, 36 do if state.board[i] ~= 0 then placed = placed + 1 end end
    check(placed == 16, "all 16 pieces are on the board at the start")
    for i = 1, 36 do state.board[i] = puzzle.solved[i] end
    check(state:solved(), "the ROM's solved configuration reads as solved")
  end

  -- the wall script reaches the puzzle now that special 41 is lowered
  local Gen2ScriptVM = require("src.script.Gen2ScriptVM")
  local rows = Gen2ScriptVM.compile(data, "S44_44DE")
  local sawPuzzle = false
  for _, row in ipairs(rows or {}) do
    if row[1] == "g2_unown_puzzle" then sawPuzzle = true end
  end
  check(sawPuzzle, "the Kabuto chamber wall script runs the puzzle")

  -- ------------------------------------------------------ the Gen2 pack
  local BagMenu = require("src.ui.BagMenu")
  check(#BagMenu.POCKETS == 4, "the pack has four pockets")
  local counts = {}
  for _, def in pairs(data.items or {}) do
    local p = BagMenu.pocketOf(def, def.id)
    counts[p] = (counts[p] or 0) + 1
  end
  check((counts.ITEM or 0) > 100,
    "most items live in the ITEM pocket (" .. tostring(counts.ITEM) .. ")")
  check((counts.TM_HM or 0) == 57, "all 50 TMs and 7 HMs are in TM/HM")
  check((counts.BALL or 0) >= 10,
    "the balls have their own pocket (" .. tostring(counts.BALL) .. ")")
  check((counts.KEY_ITEM or 0) > 5 and (counts.KEY_ITEM or 0) < 60,
    "key items are a small pocket, not everything ("
    .. tostring(counts.KEY_ITEM) .. ")")

  local ball = data.items.ITEM_005
  check(ball ~= nil and ball.pocket == "BALL" and not ball.keyItem,
    "POKe BALL is a ball, not a key item")

  -- a pocketed bag lists only its page
  local Bag = require("src.inventory.Bag")
  game.save.bagOrder = nil
  for id in pairs(game.save.inventory) do
    if not Bag.isBadge(id) then game.save.inventory[id] = nil end
  end
  Bag.add(game.save, "ITEM_005", 5, data)   -- POKe BALL
  Bag.add(game.save, "ITEM_017", 1, data)   -- a plain item
  local bag = BagMenu.new(game, {})
  check(bag.onPocketSwitch ~= nil, "the Gen2 bag pages with LEFT/RIGHT")
  check(#bag.items == 1 and bag.items[1].value ~= "ITEM_005",
    "the ITEM page hides the balls")
  bag.onPocketSwitch(bag, 1)
  check(bag.title == "BALLS" and #bag.items == 1
    and bag.items[1].value == "ITEM_005",
    "RIGHT turns to the BALLS page")
  check(bag.pocketIndex == 1, "the pack art follows the page")

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
end
