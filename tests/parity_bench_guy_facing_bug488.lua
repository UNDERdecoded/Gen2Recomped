-- Parity (#488): the Vermilion, Saffron and Fuchsia Pokemon Center bench
-- guys answer an A press.
--
-- Oracle: engine/events/hidden_events/bench_guys.asm PrintBenchGuyText
-- compares wSpritePlayerStateData1FacingDirection against the facing byte
-- in BenchGuyTextPointers, which is SPRITE_FACING_LEFT for all twelve
-- seats (data/events/bench_guys.asm).  The SPRITE_FACING_* value in a map's
-- hidden_event row is wHiddenEventFunctionArgument instead, and pokered's
-- own macro comment says those "do not actually prevent the player from
-- interacting with them in any direction" (data/events/hidden_events.asm).
-- Four maps park SPRITE_FACING_UP there.  Gating the seat on that byte
-- rather than on the pointer table's facing asked for a facing that cannot
-- reach the bench at all: (0,4) is a wall cell whose only walkable
-- neighbour is (1,4) to the east, so those four guys were mute.
--
-- The manifest has carried both bytes as `facing` (hidden_event) and
-- `textFacing` (BenchGuyTextPointers) all along; this pins which one the
-- interact path is allowed to read.
--
-- Self-contained: `luajit tests/parity_bench_guy_facing_bug488.lua`; also
-- globbed by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity bench guy facing (#488)")
local check, eq = S.check, S.eq

local MapLoader = require("src.world.MapLoader")
local OverworldState = require("src.world.OverworldController")
local SaveData = require("src.core.SaveData")
local TextBox = require("src.render.TextBox")
require("src.render.Font").load(Data)

-- tryHiddenObject reads the `Game` upvalue OverworldState:enter() normally
-- sets during a real boot; rewire it at the one closure under test, the
-- way tests/parity_D.lua does for the Safari counters.
local pushed
local fakeGame = {
  data = Data,
  save = SaveData.newGame(),
  stack = { push = function(_, state) pushed = state end },
}
local function bindGame(fn, game)
  local i = 1
  while true do
    local name = debug.getupvalue(fn, i)
    if not name then return false end
    if name == "Game" then debug.setupvalue(fn, i, game); return true end
    i = i + 1
  end
end
check(bindGame(OverworldState.tryHiddenObject, fakeGame),
      "tryHiddenObject binds the Game upvalue")

local benchGuys = Data.field.hiddenExtras.benchGuys

-- what the box that opens actually reads, so a seat that opens the wrong
-- guy's line still fails
local function boxText(box)
  local lines = {}
  for _, page in ipairs(box and box.pages or {}) do
    for _, line in ipairs(page) do lines[#lines + 1] = line end
  end
  return table.concat(lines, " ")
end

local function pressA(mapId, x, y, facing)
  pushed = nil
  local self_ = setmetatable({
    map = { id = mapId },
    player = { facing = facing },
  }, { __index = OverworldState })
  local handled = self_:tryHiddenObject(x, y)
  return handled, pushed
end

-- The four seats whose hidden_event byte is SPRITE_FACING_UP -- the ones
-- that went silent -- plus Pewter as the control: it stores
-- SPRITE_FACING_LEFT in both places, so it talked either way and proves
-- the harness itself reaches the bench-guy branch.
local SEATS = {
  { "VERMILION_POKECENTER", "up",   "universally" },
  { "SAFFRON_POKECENTER",   "up",   "TEAM ROCKET" },
  { "FUCHSIA_POKECENTER",   "up",   "SAFARI ZONE" },
  { "CINNABAR_POKECENTER",  "up",   "canceling" },
  { "PEWTER_POKECENTER",    "left", "JIGGLYPUFF" },
}

for _, seat in ipairs(SEATS) do
  local mapId, hiddenByte, phrase = seat[1], seat[2], seat[3]
  local h = benchGuys[mapId] and benchGuys[mapId][1]
  check(h ~= nil, mapId .. " has a bench guy entry")
  if h then
    eq(h.facing, hiddenByte, mapId .. " hidden_event byte is " .. hiddenByte)
    eq(h.textFacing, "left",
       mapId .. " BenchGuyTextPointers facing is SPRITE_FACING_LEFT")

    -- the bug: facing the seat from the only cell you can stand on
    local handled, box = pressA(mapId, h.x, h.y, "left")
    check(handled, mapId .. " bench guy answers A from the east (#488)")
    check(getmetatable(box) == TextBox, mapId .. " bench guy opens a text box")
    check(boxText(box):find(phrase, 1, true) ~= nil,
          ("%s bench guy says his own line (%s)"):format(mapId, phrase))

    -- PrintBenchGuyText's facing test: every other direction falls through
    for _, wrong in ipairs({ "up", "down", "right" }) do
      local ok = pressA(mapId, h.x, h.y, wrong)
      check(not ok,
            ("%s bench guy stays quiet when faced %s"):format(mapId, wrong))
    end
  end
end

-- Every labelled seat, not just the five above: reachable from the east,
-- silent from anywhere else.  A new center inherits the invariant.
local labelled = 0
for mapId, list in pairs(benchGuys) do
  for _, h in ipairs(list) do
    if h.text then
      labelled = labelled + 1
      eq(h.textFacing, "left", mapId .. " seat is faced from the left")
      check((pressA(mapId, h.x, h.y, "left")),
            mapId .. " seat answers A from the east")
      check(not (pressA(mapId, h.x, h.y, "up")),
            mapId .. " seat ignores an A press from below")
    end
  end
end
eq(labelled, 12, "all twelve BenchGuyTextPointers seats are covered")

-- The geometry behind the symptom: the seat cell is the bench wall, the
-- floor tile east of it is where the player stands, and nothing is ever
-- walkable to the south or west.  A player who walks up from (0,3) and
-- faces down gets nothing here, exactly as in the original -- the seat is
-- keyed to one facing, not to whichever side you happen to arrive from.
for mapId, list in pairs(benchGuys) do
  for _, h in ipairs(list) do
    if h.text then
      local map = MapLoader.load(Data, mapId)
      check(not map:isWalkableCell(h.x, h.y),
            mapId .. " seat cell (0,4) is the bench itself, not floor")
      check(map:isWalkableCell(h.x + 1, h.y),
            mapId .. " the cell east of the seat is where the player stands")
      check(not map:isWalkableCell(h.x, h.y + 1),
            mapId .. " nothing stands south of the seat")
      check(not map:isWalkableCell(h.x - 1, h.y),
            mapId .. " nothing stands west of the seat")
    end
  end
end

S.finish()
