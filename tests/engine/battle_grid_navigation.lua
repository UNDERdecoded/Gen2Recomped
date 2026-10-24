package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Fixture = dofile("tests/battle_grid/fixture.lua")
local Cases = dofile("tests/battle_grid/cases.lua")
local Version = require("src.core.GameVersion")
local Navigation = require("src.battle.MoveNavigation")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    local b, e, game = f.battle(), f.exports, f.game
    local native = Version.generation() >= 3
    T.eq(f.grid(), native, "native default is unchanged")
    Cases.run(f)
    if mode[1] >= 3 then
      local off = e.api.hooks:wrap("battle.move_grid_navigation", function(next)
        next()
        return next()
      end, 100)
      local calls = e.seen.calls
      T.eq(f.grid(), true, "API 3 retains downstream grid")
      T.eq(e.seen.calls, calls + 1, "API 3 repeated next is cached")
      off()
    end
    e.mode("grid")
    b.phase, b.mimicMoves, b.mimicIndex = "mimicSelect", b.player.curMoves, 1
    f.press("down")
    T.eq(b.mimicIndex, 3, "native Mimic copy menu uses shared grid")
    e.mode("list")
    b.mimicIndex = 1
    f.press("down")
    T.eq(b.mimicIndex, 2, "native Mimic copy menu can use list")
    b.phase = "moveSelect"
    if Version.generation() <= 2 then
      game.save.options.battleLayout = "wide"
      e.mode("list")
      local calls = e.seen.calls
      T.eq(f.grid(), Version.generation() == 1, "Gen1 wide stays fixed; Gen2 wide can choose list")
      if Version.generation() == 1 then
        T.eq(e.seen.calls, calls, "Gen1 wide bypasses predicate")
      end
      game.save.options.battleLayout = "classic"
    end
    local calls = e.seen.calls
    e.stop()
    e.stop()
    T.eq(f.grid(), native, "unsubscribe restores native mode")
    T.eq(e.seen.calls, calls, "unsubscribe stops callbacks")
    if Version.isGen3() then
      f.double(true)
      f.count(4)
      f.index(1)
      T.eq(f.press("left"), 1, "native GBA double clamps left without wrappers")
      T.eq(f.press("up"), 1, "native GBA double clamps top without wrappers")
      T.eq(f.press("right"), 2, "native GBA double moves to existing neighbour")
      T.eq(f.press("down"), 4, "native GBA double moves to lower row")
      f.double(false)
    end
    local input = setmetatable({}, {
      __index = function()
        error("empty grid read input")
      end,
    })
    T.eq(Navigation.navigate(b, 1, 0, input), nil, "empty grid does not read input")
    f.close()
  end
end
Version.set(old)
T.finish("portable battle.move_grid_navigation native controllers")
