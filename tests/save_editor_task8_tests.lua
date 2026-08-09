-- Headless tests for the save editor's map browser behaviour.
-- Run from repo root: luajit tests/save_editor_task8_tests.lua
-- (also chained from tests/run_save_editor_tests.lua so CI covers it)
--
-- The spawn-point writes and the outdoor rule live in tools/save-editor/Ops.lua
-- and are asserted there; the panel-owned bits still tested here are the ones
-- with no other home: map selection, keyboard panning and the zoom clamp.

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

local love_stub = require("tests.love_stub")
love = love_stub

local passed, failed = 0, 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

print("== save editor task 8 (map browser) tests ==")

local Data = require("src.core.Data")
Data:load()

local SaveData = require("src.core.SaveData")
local State = require("State")
local Ops = require("Ops")
local MapLoader = require("src.world.MapLoader")
local MapBrowser = require("MapBrowser")

local function newState()
  local S = State.new()
  S.data = Data
  S.save = SaveData.newGame()
  S.mapId = S.save.player.map -- PALLET_TOWN
  return S
end

-- outdoor detection ---------------------------------------------------

do
  local S = newState()
  local pallet = MapLoader.load(Data, "PALLET_TOWN")
  check(Ops.isOutdoor(S, pallet), "PALLET_TOWN is outdoor (OVERWORLD tileset)")

  local indoor
  for id in pairs(Data.maps) do
    local ok, map = pcall(MapLoader.load, Data, id)
    if ok and not Ops.isOutdoor(S, map) then indoor = map break end
  end
  check(indoor ~= nil, "the dataset has at least one indoor map")

  -- a visited fly spot counts as outdoor even when the tileset does not
  if indoor then
    S.save.visited = S.save.visited or {}
    S.save.visited[indoor.id] = true
    check(Ops.isOutdoor(S, indoor),
          "a visited map counts as outdoor even with an indoor tileset")
    S.save.visited[indoor.id] = nil
  end
end

-- spawn points --------------------------------------------------------

do
  local S = newState()
  S.mapId = "VIRIDIAN_CITY"
  S.mapClickCell = nil
  S.dirty = false

  check(Ops.setPlayerHere(S) == false, "setPlayerHere refuses with no cell selected")
  check(S.dirty == false, "a refused setPlayerHere does not dirty the save")
  check(S.status:match("Click a cell first") ~= nil,
        "a refused setPlayerHere explains itself")

  S.mapClickCell = { cx = 7, cy = 9 }
  check(Ops.setPlayerHere(S) == true, "setPlayerHere writes with a cell selected")
  eq(S.save.player.map, "VIRIDIAN_CITY", "setPlayerHere moves the player's map")
  eq(S.save.player.x, 7, "setPlayerHere moves the player's x")
  eq(S.save.player.y, 9, "setPlayerHere moves the player's y")
  check(S.dirty, "setPlayerHere dirties the save")

  check(Ops.setLastHeal(S) == true, "setLastHeal writes with a cell selected")
  eq(S.save.lastHeal.map, "VIRIDIAN_CITY", "setLastHeal records the map")
  eq(S.save.lastHeal.x, 7, "setLastHeal records the cell")
end

do
  -- lastOutdoor refuses a map the game would not accept as an outdoor source
  local S = newState()
  local indoor
  for id in pairs(Data.maps) do
    local ok, map = pcall(MapLoader.load, Data, id)
    if ok and not Ops.isOutdoor(S, map) then indoor = map break end
  end
  check(indoor ~= nil, "found an indoor map to try")

  S.mapId = indoor.id
  S.mapClickCell = { cx = 1, cy = 1 }
  S.dirty = false
  check(Ops.setLastOutdoor(S, indoor) == false,
        "setLastOutdoor refuses a non-outdoor map")
  check(S.dirty == false, "a refused setLastOutdoor does not dirty the save")
  check(S.status:match("outdoor") ~= nil, "a refused setLastOutdoor explains itself")

  local pallet = MapLoader.load(Data, "PALLET_TOWN")
  S.mapId = "PALLET_TOWN"
  check(Ops.setLastOutdoor(S, pallet) == true, "setLastOutdoor accepts an outdoor map")
  eq(S.save.lastOutdoor.id, "PALLET_TOWN", "setLastOutdoor records the map id")
  eq(S.save.lastOutdoor.x, 1, "setLastOutdoor records the cell")
end

-- panel-owned view state ----------------------------------------------

do
  local S = newState()
  MapBrowser.select(S, "VIRIDIAN_CITY")
  eq(S.mapId, "VIRIDIAN_CITY", "select switches the viewed map")
  eq(S.mapClickCell, nil, "select drops the previous cell selection")
  eq(S._mapCenteredFor, nil,
     "select defers centring to the next draw, which knows the viewport size")
  check(S.status:match("VIRIDIAN_CITY") ~= nil, "select says what it is showing")
end

do
  local S = newState()
  S.mapCamX, S.mapCamY = 0, 0
  MapBrowser.keypressed(S, "right")
  eq(S.mapCamX, 16, "right pans one cell east")
  MapBrowser.keypressed(S, "left")
  eq(S.mapCamX, 0, "left pans back")
  MapBrowser.keypressed(S, "down")
  eq(S.mapCamY, 16, "down pans one cell south")
  MapBrowser.keypressed(S, "w")
  eq(S.mapCamY, 0, "WASD pans as well as the arrows")

  local before = S.mapCamX
  MapBrowser.keypressed(S, "escape")
  eq(S.mapCamX, before, "a non-pan key does not move the camera")
end

do
  local S = newState()
  S.mapZoom = 2
  MapBrowser.wheelmoved(S, 1)
  check(S.mapZoom > 2, "wheel up zooms in")
  for _ = 1, 40 do MapBrowser.wheelmoved(S, 1) end
  eq(S.mapZoom, 4, "zoom clamps at 4x")
  for _ = 1, 80 do MapBrowser.wheelmoved(S, -1) end
  eq(S.mapZoom, 1, "zoom clamps at 1x")
end

print(string.format("save editor task 8 tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
