-- Parity test: the Hall of Fame dex rating runs through the standard
-- PrintText text box (#314).
-- Self-contained: run via `luajit tests/parity_hof_rating.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
--
-- pokered's HoFDisplayPlayerStats (engine/movie/hall_of_fame.asm) prints
-- three texts back to back through HoFPrintTextAndDelay -> PrintText, each
-- followed by 120 DelayFrames: _DexSeenOwnedText, _DexRatingText
-- ("POKéDEX Rating:"), then the tier line copied into wDexRatingText by
-- DisplayDexRating (engine/events/pokedex_rating.asm).  PrintText is the
-- standard two-row bottom box, so the tier text's `cont` (\v) rows scroll
-- inside it -- each with the original's ▼ + A/B wait (_ContText ->
-- ManualTextScroll), even mid-ceremony.
--
-- The port instead hand-drew a 6-row box and flattened \v into plain
-- newlines with drawTextBlock, so a 3+ row rating ("You finally got at /
-- least 50 species! / Be sure to get ...") painted its third row on top of
-- the bottom border and dropped the rest (#314).
--
-- The invariant: after the stat boxes, the induction pushes TextBox states
-- for the seen/owned counts, the "POKéDEX Rating:" header, and the tier
-- text, in that order, and each closes itself after the 120-frame hold.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end
local S = require("tests.harness").suite("parity HoF dex rating")
local check, eq = S.check, S.eq

local SaveData = require("src.core.SaveData")
local TextBox = require("src.render.TextBox")
local HallOfFame = require("src.ui.HallOfFame")

local pressed = {}
local fakeInput = { wasPressed = function(_, b) return pressed[b] or false end,
                    isDown = function() return false end }

local stack = { states = {} }
function stack:push(s, ...) table.insert(self.states, s) if s.enter then s:enter(...) end end
function stack:pop() local s = table.remove(self.states) if s and s.exit then s:exit() end return s end
function stack:top() return self.states[#self.states] end

local game = { data = Data, input = fakeInput, stack = stack,
               save = SaveData.newGame() }
game.save.party = { { species = "PIKACHU", level = 81, hp = 100,
                      stats = { hp = 100 },
                      moves = { { id = "THUNDERBOLT", pp = 35 } } } }
-- 55 owned lands in the Own50To59 tier from the issue's screenshot
local seen, owned = {}, {}
for i = 1, 55 do seen[i] = true; owned[i] = true end
game.save.pokedex = { seen = seen, owned = owned }

-- record every TextBox the induction pushes, with its full text
local shown = {}
local realNew = TextBox.new
TextBox.new = function(g, text, onDone, opts)
  local self = realNew(g, text, onDone, opts)
  local lines = {}
  for _, page in ipairs(self.pages) do
    for _, line in ipairs(page) do lines[#lines + 1] = line end
  end
  shown[#shown + 1] = { text = table.concat(lines, " "), opts = opts }
  return self
end

local done = false
stack:push(HallOfFame.new(game, function() done = true end))

-- drive the induction with A held: mashing skips the mon phases; the dex
-- texts must still run their course on their own
pressed.a = true
local guard = 0
while not done and guard < 30000 do
  guard = guard + 1
  local top = stack:top()
  if top and top.update then top:update(1 / 60) end
end
pressed.a = nil
TextBox.new = realNew -- restore: run_tests dofiles all parity suites in one process

check(done, "induction runs to completion")
eq(#shown, 3, "three text boxes follow the stat boxes (seen/owned, header, rating)")
check(shown[1] ~= nil and shown[1].text:find("Seen", 1, true) ~= nil
      and shown[1].text:find("55", 1, true) ~= nil,
      "first box is the seen/owned count, got: " ..
      tostring(shown[1] and shown[1].text))
check(shown[2] ~= nil and shown[2].text:find("Rating", 1, true) ~= nil,
      "second box is the POKéDEX Rating: header, got: " ..
      tostring(shown[2] and shown[2].text))
check(shown[3] ~= nil and shown[3].text:find("least 50 species!", 1, true) ~= nil,
      "third box is the Own50To59 tier text, got: " ..
      tostring(shown[3] and shown[3].text))

-- HoFPrintTextAndDelay = PrintText + 120 DelayFrames: each box pops itself
-- after the hold (the rating's `cont` rows still wait for A/B, exactly like
-- pokered's _ContText -> ManualTextScroll -- the A held above walks them)
for i, box in ipairs(shown) do
  check(box.opts and box.opts.auto ~= nil,
        ("box %d auto-closes after its 120-frame hold"):format(i))
end

S.finish()
