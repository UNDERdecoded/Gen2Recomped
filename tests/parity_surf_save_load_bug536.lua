-- Regression (#536): a save made mid-surf must resume mid-surf.
--
-- wWalkBikeSurfState (ram/wram.asm) sits inside wMainDataStart..wMainDataEnd,
-- the range engine/menus/save.asm block-copies into sMainData on save and
-- back out on load, so the original persists the surf state across a save.
-- OverworldState:captureSave now writes save.player.surfing and
-- OverworldState:setMap's boot path (opts.via == "boot", only taken from
-- :enter, which every StateStack push runs through) restores it before
-- Music/PikachuFollower see the player. Before the fix, self.player.surfing
-- was never serialized at all, so a reload always came back on foot;
-- Collision.canMove (src/world/Collision.lua) then picks land tile-pairs for
-- a non-surfing mover, which never permit standing on a water cell, so the
-- reload could softlock on the water tile the save was made on.
--
-- Self-contained; run via `luajit tests/parity_surf_save_load_bug536.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROUTE_20) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity surf save/load (#536)")
local check, eq = S.check, S.eq

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack
StateStack:init()

-- ground truth from parity_cinnabar_east_surf.lua: ROUTE_20 (0,8) is water.
local r20 = require("src.world.MapLoader").load(Data, "ROUTE_20")
check(r20:isWaterCell(0, 8), "ROUTE_20 (0,8) is water")

-- --- a save made mid-surf on a water cell resumes surfing --------------
Game.save = SaveData.newGame()
Game.save.player.surfing = true
while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "ROUTE_20", 0, 8, "left")
local ow = Game.stack:top()
eq(ow.player.surfing, true, "boot onto a water cell with surfing=true restores surfing")
-- sprite/movement mode: Player:pose() (src/world/Player.lua) only ever
-- selects surfSprite when self.surfing is truthy, so this is the same
-- switch that put the walking sheet back on a surfing player pre-fix
local sprite = ow.player:pose()
check(sprite == ow.player.surfSprite,
      "restored surfing selects the surf sprite sheet, not the walking one")

-- --- a save made on foot on land resumes on foot ------------------------
Game.save = SaveData.newGame()
Game.save.player.surfing = false
while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "PALLET_TOWN", 5, 6, "down")
ow = Game.stack:top()
eq(ow.player.surfing, false, "boot onto land with surfing=false stays on foot")

-- --- saves written before #536 (no surfing field at all) default safely -
Game.save = SaveData.newGame()
Game.save.player.surfing = nil
while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "PALLET_TOWN", 5, 6, "down")
ow = Game.stack:top()
check(not ow.player.surfing, "a pre-#536 save with no surfing field boots on foot, not truthy-nil")

-- --- the true round trip: captureSave -> a fresh boot reads it back back ---
Game.save = SaveData.newGame()
while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "ROUTE_20", 0, 8, "left")
ow = Game.stack:top()
ow.player.surfing = true -- player mounted SURF while already standing on water
local captured = SaveData.newGame()
ow:captureSave(captured)
eq(captured.player.map, "ROUTE_20", "captureSave records the map")
eq(captured.player.x, 0, "captureSave records x")
eq(captured.player.y, 8, "captureSave records y")
eq(captured.player.surfing, true, "captureSave records surfing=true")

-- reload from that captured save: a brand-new boot must come back surfing
Game.save = captured
while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, captured.player.map, captured.player.x, captured.player.y,
  captured.player.facing)
ow = Game.stack:top()
eq(ow.player.surfing, true,
   "round trip: captureSave -> reboot restores surfing on the same water cell")

S.finish()
