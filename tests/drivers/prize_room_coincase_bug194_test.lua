-- Driver: #194 Celadon prize room must require the COIN CASE.
-- engine/menus/prize_menu.asm CeladonPrizeMenu gates the prize window on the
-- COIN CASE: IsItemInBag COIN_CASE first, and with no case it prints
-- RequireCoinCaseText and returns without ever opening a window; only with the
-- case does it print ExchangeCoinsForPrizesText and then show the prize list.
-- The port used to open "PRIZES (COINS)" unconditionally with no intro line.
--
-- The three prize counters are bg-event signs at cells (2,2),(4,2),(6,2) in
-- GAME_CORNER_PRIZE_ROOM (data/generated/maps.lua).  Stand south of vendor 1
-- and press A: no-case -> require box and NO list; has-case -> exchange box,
-- then the prize list; cancel returns to the overworld (onCancel == done).
--
--   SHOT_DIR=/tmp/prize194 POKEPORT_IDENTITY=bug194 POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/prize_room_coincase_bug194_test.lua love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  os.execute("mkdir -p " .. DIR)

  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local ListMenu = require("src.ui.ListMenu")

  -- a party so nothing else blocks overworld interaction
  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 5) }
  game.save.inventory = game.save.inventory or {}
  game.save.coins = game.save.coins or 0

  local function topMeta() return getmetatable(game.stack:top()) end
  -- let a TextBox finish typing its current page (self.waiting) so shots
  -- capture the full line instead of a mid-typewriter frame
  local function settleText(maxFrames)
    for _ = 1, maxFrames or 40 do
      local top = game.stack:top()
      if getmetatable(top) == TextBox and top.waiting then break end
      U.wait(1)
    end
  end
  local function pageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local parts = {}
    for _, page in ipairs(top.pages or {}) do
      if type(page) == "table" then
        for _, line in ipairs(page) do parts[#parts + 1] = tostring(line) end
      end
    end
    return table.concat(parts, " ")
  end

  -- ===== CASE 1: NO COIN CASE -> require box, prize list NEVER opens =====
  game.save.inventory.COIN_CASE = nil
  -- stand at (2,3) facing up; the faced cell is vendor sign 1 at (2,2)
  U.teleport(game, "GAME_CORNER_PRIZE_ROOM", 2, 3, "up")
  local ow = game.overworld
  U.shot(game, DIR .. "/prize_room_0_before.png")

  U.tap(game, "a")
  -- scan several frames: a ListMenu must NEVER appear without the case
  local sawListNoCase, sawRequire = false, false
  for _ = 1, 60 do
    if topMeta() == ListMenu then sawListNoCase = true end
    if topMeta() == TextBox and pageText():find("COIN CASE", 1, true) then
      sawRequire = true
    end
    U.wait(1)
  end
  U.log("no-case: sawRequire", sawRequire, "sawList", sawListNoCase)
  settleText(40)
  U.shot(game, DIR .. "/prize_room_1_nocase_requiretext.png")
  assert(sawRequire,
    "no-case: 'A COIN CASE is required!' box never shown (#194)")
  assert(not sawListNoCase,
    "no-case: prize ListMenu opened without a COIN CASE (#194)")

  -- dismiss the require box; back to the overworld with no list ever opened
  U.tap(game, "a")
  for _ = 1, 30 do
    if game.stack:top() == ow then break end
    U.tap(game, "a")
    U.wait(1)
  end
  assert(game.stack:top() == ow, "no-case: did not return to overworld")

  -- ===== CASE 2: HAS COIN CASE -> exchange box, then the prize list =====
  game.save.inventory.COIN_CASE = 1
  U.tap(game, "a") -- talk to the same vendor sign again
  local sawExchange = false
  for _ = 1, 60 do
    if topMeta() == TextBox and
       (pageText():find("exchange", 1, true) or
        pageText():find("coins for prizes", 1, true)) then
      sawExchange = true
      break
    end
    U.wait(1)
  end
  U.log("has-case: sawExchange", sawExchange)
  settleText(140)
  U.shot(game, DIR .. "/prize_room_2_exchange.png")
  assert(sawExchange,
    "has-case: 'We exchange your coins for prizes.' never shown (#194)")

  -- advance past the exchange line; the prize list must then open
  local sawList = false
  for _ = 1, 60 do
    if topMeta() == ListMenu then sawList = true break end
    U.tap(game, "a")
    U.wait(1)
  end
  U.log("has-case: sawList", sawList, "title",
        (sawList and game.stack:top().title) or "-")
  U.shot(game, DIR .. "/prize_room_3_menu.png")
  assert(sawList, "has-case: prize ListMenu never opened after exchange text")
  assert(game.stack:top().title == "PRIZES (COINS)",
    "has-case: opened list is not the prize window")

  -- cancel returns to the overworld (onCancel == done)
  U.tap(game, "b")
  for _ = 1, 30 do
    if game.stack:top() == ow then break end
    U.wait(1)
  end
  assert(game.stack:top() == ow, "has-case: cancel did not return to overworld")
  U.log("prize_room_coincase_bug194_test: ok")
end
