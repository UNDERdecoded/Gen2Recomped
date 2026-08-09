-- Parity (#567): the bike shop boy's line depends on whether the voucher
-- has been redeemed.
--
-- Oracle: scripts/BikeShop.asm BikeShopYoungsterText -- CheckEvent
-- EVENT_GOT_BICYCLE, jr nz .gotBike.  Before the exchange he grumbles that
-- BIKEs are way expensive; after it he admires yours.  The port reads the
-- bag instead of the event, because the BICYCLE is a key item and cannot
-- be tossed, and because saves written before the clerk started setting
-- the event still have the bike.
--
-- The near miss this pins is the one #535 hit: a row-list branch whose
-- jump target is off by one runs off the end of the list and prints
-- nothing at all, which looks exactly like the NPC having no script.
--
-- Self-contained: `luajit tests/parity_bike_shop_youngster_bug567.lua`;
-- also globbed by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity bike shop youngster (#567)")
local check, eq = S.check, S.eq

local Commands = require("src.script.Commands")
local Flags = require("src.script.Flags")
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local SaveData = require("src.core.SaveData")
local ScriptRunner = require("src.script.ScriptRunner")
local StateStack = require("src.core.StateStack")
local mapScripts = require("data.scripts.init")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
require("src.render.Font").load(Data)

local script = mapScripts.talkScript("BIKE_SHOP", "TEXT_BIKESHOP_YOUNGSTER")
check(type(script) == "table", "the boy is a row-list talk script")

-- an unreachable or out-of-range jump is a silent NPC, so validate first
do
  local problems = ScriptRunner.validate(script)
  eq(#problems, 0,
     "the row list validates (" .. (problems[1] or "no findings") .. ")")
end

local shown = {}
local origShow = Commands.show_text
Commands.show_text = function(ctx, textId, subs)
  shown[#shown + 1] = textId
  return origShow(ctx, textId, subs)
end

local function talk()
  shown = {}
  StateStack:init()
  local ow = { map = { id = "BIKE_SHOP", def = { label = "BikeShop" } },
               npcs = {}, entities = {} }
  local runner = ScriptRunner.new(Game, ow)
  runner:run(script, { npc = { def = {}, facePlayer = function() end },
                       overworld = ow })
  local guard = 0
  while runner:isRunning() and guard < 3000 do
    guard = guard + 1
    Input.pressed = { a = true }
    StateStack:update(1 / 60)
    runner:update()
  end
  Input.pressed = {}
  return not runner:isRunning()
end

local EXPENSIVE = "_BikeShopYoungsterTheseBikesAreExpensiveText"
local COOL = "_BikeShopYoungsterCoolBikeText"

check(Data.text[EXPENSIVE] and Data.text[EXPENSIVE]:find("expensive", 1, true),
      "the pre-bike line is the way-expensive one")
check(Data.text[COOL] and Data.text[COOL]:find("cool", 1, true),
      "the post-bike line admires your BIKE")

-- ------------------------------------------------- before the exchange
do
  Game.save = SaveData.newGame()
  check(talk(), "the empty-handed talk completes")
  eq(table.concat(shown, ","), EXPENSIVE,
     "with no BICYCLE he complains about the price, once")
end

-- holding the voucher is still "before": the exchange has not happened
do
  Game.save = SaveData.newGame()
  Game.save.inventory.BIKE_VOUCHER = 1
  check(talk(), "the voucher-in-hand talk completes")
  eq(table.concat(shown, ","), EXPENSIVE,
     "a voucher is not a BICYCLE, so he still says they are expensive (#567)")
end

-- ------------------------------------------------- after the exchange
do
  Game.save = SaveData.newGame()
  Game.save.inventory.BICYCLE = 1
  Flags.set(Game.save, "EVENT_GOT_BICYCLE")
  check(talk(), "the post-exchange talk completes")
  eq(table.concat(shown, ","), COOL,
     "with the BICYCLE he admires it, once, and nothing follows (#567)")
  check(talk() and table.concat(shown, ",") == COOL,
        "and he keeps saying it on every later visit")
end

-- a save written before the clerk set EVENT_GOT_BICYCLE still has the bike
do
  Game.save = SaveData.newGame()
  Game.save.inventory.BICYCLE = 1
  check(talk(), "the old-save talk completes")
  eq(table.concat(shown, ","), COOL,
     "the bag decides, so an older save reads right too")
end

Commands.show_text = origShow
S.finish()
