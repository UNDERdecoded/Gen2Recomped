-- Parity (#568): the bike shop clerk runs the original sale, price window
-- and all.
--
-- Oracle: scripts/BikeShop.asm BikeShopClerkText.  Three ways in --
-- EVENT_GOT_BICYCLE, a BIKE VOUCHER in the bag, or the sales pitch -- and
-- the pitch is a menu, not a line: TextBoxBorder hlcoord 0,0 b=4 c=15
-- holding BikeShopMenuText / BikeShopMenuPrice, PrintText
-- BikeShopClerkDoYouLikeItText, HandleMenuInput over two rows, then
-- BikeShopCantAffordText for BICYCLE and BikeShopComeAgainText for either
-- answer.  Nothing erases that window before TextScriptEnd, so it stays up
-- underneath both closing lines.
--
-- The voucher path's atomicity is pokered's `jr nc, .BagFull`: the voucher
-- is only spent once GiveItem actually took the BICYCLE.
--
-- Drives the real StateStack and Input; the window's pixels are the
-- driver's half (tests/drivers/bike_shop_bug568_test.lua).
--
-- Self-contained: `luajit tests/parity_bike_shop_clerk_bug568.lua`; also
-- globbed by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity bike shop clerk (#568)")
local check, eq = S.check, S.eq

local Bag = require("src.inventory.Bag")
local Flags = require("src.script.Flags")
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local TextBox = require("src.render.TextBox")
local mapScripts = require("data.scripts.init")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
require("src.render.Font").load(Data)

local clerk = mapScripts.talkScript("BIKE_SHOP", "TEXT_BIKESHOP_CLERK")
check(type(clerk) == "function",
      "the clerk is a hand-ported talk handler, not extracted flavor text")

-- what each box was built with, in order
local boxes = {}
local realNew = TextBox.new
TextBox.new = function(game, text, onDone, opts)
  boxes[#boxes + 1] = text
  return realNew(game, text, onDone, opts)
end

local done
local function begin(save)
  Game.save = save
  StateStack:init()
  boxes, done = {}, false
  clerk(Game, { map = { id = "BIKE_SHOP", def = { label = "BikeShop" } },
                npcs = {}, entities = {} },
        { def = {}, facePlayer = function() end },
        function() done = true end)
end

local function step(frames, btn)
  for _ = 1, frames do
    Input.pressed = btn and { [btn] = true } or {}
    StateStack:update(1 / 60)
    Input.pressed = {}
  end
end

-- mash A until the stack drains (the whole conversation) or we give up
local function mash(limit)
  for _ = 1, limit or 2000 do
    if not StateStack:top() then return true end
    step(1, "a")
  end
  return false
end

-- the price window is the one state on this stack that is not a text box
local function windowState()
  for _, state in ipairs(StateStack.states) do
    if getmetatable(state) ~= TextBox then return state end
  end
end

local function inStack(state)
  for _, s in ipairs(StateStack.states) do
    if s == state then return true end
  end
  return false
end

local t = Data.text

-- ------------------------------------------------- you already have one
do
  local save = SaveData.newGame()
  save.inventory.BICYCLE = 1
  Flags.set(save, "EVENT_GOT_BICYCLE")
  begin(save)
  check(mash(), "the how-do-you-like-it talk ends")
  eq(#boxes, 1, "one box, no menu")
  eq(boxes[1], t._BikeShopClerkHowDoYouLikeYourBicycleText,
     "he asks how you like your new BICYCLE")
  check(done, "and hands input back")
end

-- a save from before the clerk set the event still owns the bike
do
  local save = SaveData.newGame()
  save.inventory.BICYCLE = 1
  begin(save)
  check(mash(), "the older-save talk ends")
  eq(boxes[1], t._BikeShopClerkHowDoYouLikeYourBicycleText,
     "the bag alone is enough to skip the sale")
end

-- ------------------------------------------------------- the exchange
do
  local save = SaveData.newGame()
  save.inventory.BIKE_VOUCHER = 1
  begin(save)
  check(mash(), "the voucher exchange runs to the end")
  eq(#boxes, 2, "two boxes: oh-that's-a-voucher, then the exchange")
  eq(boxes[1], t._BikeShopClerkOhThatsAVoucherText, "he spots the voucher")
  eq(boxes[2], t._BikeShopExchangedVoucherText, "and makes the trade")
  eq(save.inventory.BICYCLE, 1, "the BICYCLE is in the bag")
  check(not save.inventory.BIKE_VOUCHER, "the BIKE VOUCHER is spent")
  check(Flags.get(save, "EVENT_GOT_BICYCLE"), "EVENT_GOT_BICYCLE is set")
  check(done, "and the talk hands input back")
end

-- .BagFull: GiveItem refused, so nothing is spent (jr nc, .BagFull)
do
  local save = SaveData.newGame()
  save.inventory.BIKE_VOUCHER = 1
  local filler = 0
  for id in pairs(Data.items) do
    if id ~= "BICYCLE" and id ~= "BIKE_VOUCHER" and Bag.add(save, id, 1) then
      filler = filler + 1
    end
  end
  check(filler > 0 and not Bag.add(save, "BICYCLE", 1), "the bag is full")
  begin(save)
  check(mash(), "the full-bag talk ends")
  eq(boxes[2], t._BikeShopBagFullText, "he tells you to make room")
  check(not save.inventory.BICYCLE, "no BICYCLE while there is no room")
  eq(save.inventory.BIKE_VOUCHER, 1, "and the voucher is not burned")
  check(not Flags.get(save, "EVENT_GOT_BICYCLE"), "nor the event set")
end

-- --------------------------------------------------------- the sale
-- Welcome, the pitch, the BICYCLE/CANCEL window, can't-afford, come-again.
do
  local save = SaveData.newGame()
  local money = save.money
  begin(save)

  -- the welcome line waits for a button like any other box
  eq(boxes[1], t._BikeShopClerkWelcomeText, "he welcomes you to the shop")
  eq(#StateStack.states, 1, "and nothing else is up yet")
  for _ = 1, 400 do
    if #StateStack.states > 1 then break end
    step(1, "a")
  end
  eq(boxes[2], t._BikeShopClerkDoYouLikeItText, "then the pitch")

  -- the pitch box types out and pops itself (PrintText straight into
  -- HandleMenuInput), leaving the window holding the screen
  local window
  for _ = 1, 400 do
    window = windowState()
    if window and StateStack:top() == window then break end
    step(1)
  end
  check(window ~= nil, "a price window is pushed under the pitch (#568)")
  check(StateStack:top() == window, "and it takes over when the pitch pops")
  eq(#StateStack.states, 1, "the pitch box is gone, the window is not")
  check(type(window.footer) == "table" and #window.footer > 0,
        "the window keeps the pitch line in the bottom box, so it never blanks")
  eq(window.index, 1, "the cursor starts on BICYCLE (wCurrentMenuItem 0)")

  -- HandleMenuInput with wMenuWrappingEnabled clear: two rows, no wrap
  step(1, "up")
  eq(window.index, 1, "up on the first row stays put")
  step(1, "down")
  eq(window.index, 2, "down moves to CANCEL")
  step(1, "down")
  eq(window.index, 2, "down again stays on CANCEL, it does not wrap")
  step(1, "up")
  eq(window.index, 1, "and up comes back to BICYCLE")

  -- buy it: ¥1000000 is out of reach, then he sees you out
  step(1, "a")
  eq(boxes[3], t._BikeShopCantAffordText, "BICYCLE answers with can't-afford")
  check(inStack(window), "the window is still up behind that line")
  for _ = 1, 400 do
    if boxes[4] then break end
    step(1, "a")
  end
  eq(boxes[4], t._BikeShopComeAgainText, "then come back again some time")
  check(inStack(window), "and the window is still up behind that one too")

  check(mash(), "the sale ends")
  eq(#boxes, 4, "four text boxes plus the window: the original's five")
  check(not inStack(window), "the window comes down with the last line")
  eq(#StateStack.states, 0, "the stack is back to the overworld")
  check(done, "and the talk hands input back")
  eq(save.money, money, "browsing costs nothing")
  check(not save.inventory.BICYCLE, "and sells nothing")
  check(not Flags.get(save, "EVENT_GOT_BICYCLE"), "the event stays clear")
end

-- CANCEL skips the can't-afford line (.cancel jumps straight to come-again)
do
  begin(SaveData.newGame())
  local window
  for _ = 1, 800 do
    window = windowState()
    if window and StateStack:top() == window then break end
    step(1, "a")
  end
  check(window ~= nil, "the window comes up on the cancel run too")
  step(1, "down")
  step(1, "a")
  eq(boxes[3], t._BikeShopComeAgainText,
     "CANCEL goes straight to come-again, no can't-afford")
  check(mash(), "the cancel run ends")
  eq(#boxes, 3, "three boxes on the cancel path")
end

-- B is the same .cancel branch (bit B_PAD_B, a)
do
  begin(SaveData.newGame())
  local window
  for _ = 1, 800 do
    window = windowState()
    if window and StateStack:top() == window then break end
    step(1, "a")
  end
  check(window ~= nil, "the window comes up on the B run too")
  step(1, "b")
  eq(boxes[3], t._BikeShopComeAgainText, "B backs out the same way CANCEL does")
  check(mash(), "the B run ends")
  eq(#boxes, 3, "three boxes when you back out")
end

TextBox.new = realNew
S.finish()
