-- Regression (#518): without a BICYCLE, the Route 16/18 gate guard must
-- still shove the player one tile aside after refusing them, not leave
-- them parked against the counter.
--
-- pokered's Route16Gate1FGuardScript / Route18Gate1FGuardScript (scripts/
-- Route16Gate1F.asm, Route18Gate1F.asm) print the refusal text, then
-- simulate one PAD_RIGHT step (StartSimulatingJoypadStates) and only clear
-- wJoyIgnore once that step lands. data/scripts/story5.lua's bikeGateGuard
-- walked the player up to the counter and stopped there -- the ported
-- refusal text played, but nothing ever moved the player off the doorway.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.ROUTE_16_GATE_1F) then Data:load() end

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local MapLoader = require("src.world.MapLoader")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity bike gate shove (#518)")
local check, eq = S.check, S.eq

-- ground truth: data/generated/maps.lua ROUTE_16_GATE_1F.objects, the guard
-- sits at (4,5) behind a solid counter row (row 6); rows 7-10 south of it
-- are the open waiting area bikeGateGuard's coords cover.
local r16 = MapLoader.load(Data, "ROUTE_16_GATE_1F")
check(r16:isWalkableCell(4, 7), "the counter-adjacent stop cell (4,7) is walkable")
check(r16:isWalkableCell(5, 7), "the shove target (5,7) is walkable")
check(not r16:isWalkableCell(4, 6), "row 6 (the counter) blocks straight through")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()

-- stub TextBox the way parity_A.lua drives gym leader text: a bare table
-- capturing (text, onDone) so the test can dismiss it without pagination.
local realTB = package.loaded["src.render.TextBox"]
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { text = text, onDone = done } end,
}

local mapScripts = require("data.scripts.init")
local hooks = mapScripts.get("ROUTE_16_GATE_1F")
check(hooks and hooks.onStep, "ROUTE_16_GATE_1F has an onStep hook")

-- one 16-frame step per fixed update, same as parity_ledge_seam_hop.lua
local function runFrames(ow, n)
  for _ = 1, n do
    ow:updateScriptMoves()
    ow.player:update()
  end
end

-- dismiss the top stubbed box the way TextBox:update does: pop, then onDone
local function dismissTop()
  local box = Game.stack:pop()
  if box.onDone then box.onDone() end
  return box
end

local function standNoBike(x, y, facing)
  Game.save = SaveData.newGame()
  Game.save.inventory.BICYCLE = nil
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, "ROUTE_16_GATE_1F", x, y, facing or "up")
  local ow = Game.stack:top()
  ow.player.moving = false
  return ow
end

-- --- approaching from three tiles out: walk-up then shove -----------------
do
  local ow = standNoBike(4, 10)
  local handled = hooks.onStep(Game, ow, ow.player.cellX, ow.player.cellY)
  check(handled, "onStep claims the coordinate trigger without a BICYCLE")

  local box1 = Game.stack:top()
  check(box1 ~= nil, "the wait-up refusal text box opened")
  check(box1.text:find("Wait up", 1, true) ~= nil
        or box1.text:find("Excuse me", 1, true) ~= nil,
        "first box is the guard's stop line")
  dismissTop()

  local box2 = Game.stack:top()
  check(box2 ~= nil, "the second (explanation) box opened")
  eq(box2.text, Data.text._Route16Gate1FGuardNoPedestriansAllowedText,
     "second box is the guard's no-pedestrians explanation, verbatim")
  dismissTop()

  check(#ow.scriptMoves > 0 or ow.player.moving,
        "closing the explanation queues the walk-up-then-shove movement")
  runFrames(ow, 200)
  check(not ow.player.moving, "the scripted movement has settled")
  eq(#ow.scriptMoves, 0, "no scripted move is left hanging")
  eq(ow.player.cellX, 5, "the player ends one tile right of the counter (#518 shove)")
  eq(ow.player.cellY, 7, "the player ends on the counter-adjacent row, not further")
end

-- --- already standing at the counter-adjacent row: shove with no walk-up --
do
  local ow = standNoBike(4, 7)
  local handled = hooks.onStep(Game, ow, ow.player.cellX, ow.player.cellY)
  check(handled, "onStep still claims it when already adjacent to the counter")
  dismissTop() -- wait-up
  dismissTop() -- explanation
  runFrames(ow, 200)
  check(not ow.player.moving, "the shove-only movement has settled")
  eq(#ow.scriptMoves, 0, "no scripted move is left hanging")
  eq(ow.player.cellX, 5, "still ends one tile right (#518 shove with dist=0)")
  eq(ow.player.cellY, 7, "y is unchanged since there was no walk-up needed")
end

-- --- control: a BICYCLE in the bag lets the trigger pass through untouched
do
  local ow = standNoBike(4, 10)
  ow.player.moving = false
  Game.save.inventory.BICYCLE = true
  local handled = hooks.onStep(Game, ow, ow.player.cellX, ow.player.cellY)
  check(not handled, "with a BICYCLE, onStep does not intercept the step")
  check(Game.stack:top() == ow, "no text box opened when riding a BICYCLE")
end

package.loaded["src.render.TextBox"] = realTB

S.finish()
