-- Regression: map-connection seam steps must show walk frames (issue #93).
--
-- A hitch inside setMap (neighbor rebuild / map-song start) made the next
-- real-time dt huge; FixedStep catch-up then advanced many walk frames
-- before the next draw, which looked like a slide with no leg animation.
-- crossConnection now discards that catch-up, starts a fresh animClock,
-- and defers PlayMapMusic until the seam step lands.
--
-- Self-contained; run via `luajit tests/parity_seam_walk_anim.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local FixedStep = require("src.core.FixedStep")
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local Music = require("src.core.Music")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local OW = require("src.world.OverworldController")
local S = require("tests.harness").suite("parity seam walk anim")
local check, eq = S.check, S.eq

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack
StateStack:init()
Game.save = SaveData.newGame()
Game.overworld = OW

while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "PALLET_TOWN", 10, 0, "up")
local ow = Game.stack:top()
local north = ow.map:connection("north")
check(north and north.map == "ROUTE_1", "Pallet north connects to ROUTE_1")

-- simulate a post-hitch catch-up budget waiting in the accumulator
FixedStep.accum = 0.24
local played = {}
local realPlayMap = Music.playMap
Music.playMap = function(data, mapId, onBike, surfing)
  played[#played + 1] = mapId
  return realPlayMap(data, mapId, onBike, surfing)
end

check(ow:crossConnection("up", north) == true, "Pallet -> Route 1 crosses")
eq(ow.map.id, "ROUTE_1", "landed on ROUTE_1")
eq(FixedStep.accum, 0, "seam cross discards FixedStep catch-up")
eq(ow.pendingSeamMusic, "ROUTE_1", "map music deferred across the seam step")
eq(#played, 0, "PlayMapMusic not called inside setMap for the seam")
eq(ow.player.animClock, 0, "seam step starts a fresh walk-cycle clock")
check(ow.player.moving, "seam step is in progress")

local sawWalk = false
local phases = {}
for _ = 1, 20 do
  ow:update(1 / 60)
  phases[#phases + 1] = ow.player:walkPhase()
  if ow.player:walkPhase() == 1 then sawWalk = true end
  if not ow.player.moving and not ow.pendingSeamMusic then break end
end
check(sawWalk, "seam step shows at least one walk frame")
-- mid-cycle: frames 4..11 of a fresh animClock are walk
local midWalk = false
for i = 4, 11 do
  if phases[i] == 1 then midWalk = true break end
end
check(midWalk, "fresh animClock puts walk frames in the middle of the seam step")
eq(ow.pendingSeamMusic, nil, "deferred music flushed after the seam step")
eq(played[1], "ROUTE_1", "PlayMapMusic runs once the seam step lands")

Music.playMap = realPlayMap
S.finish()
