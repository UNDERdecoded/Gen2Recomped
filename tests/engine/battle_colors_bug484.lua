-- Cycling COLORS during a battle must keep the battle song (#484).  The
-- pack change rebuilds the live map's baked atlas through
-- OverworldState:reloadMap, and that used to re-enter the map: setMap's
-- PlayMapMusic put the route theme over the battle theme.  ReloadMapData
-- (home/reload_tiles.asm) only re-reads the map view and the tileset
-- patterns; map music comes from LoadMapData alone (home/overworld.asm,
-- gated on BIT_NO_MAP_MUSIC), so a reload is not a map entry.
-- The other half matters as much: the hotkey must still work in a battle,
-- so a "fix" that gates key 2 off while BattleState is on top fails here.
--   luajit tests/engine/battle_colors_bug484.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local OverworldState = require("src.world.OverworldController")

-- OverworldController takes its collaborators as file-locals, and Game is
-- only bound when a real state enters; swapping the upvalues is how
-- tests/mod_world_tests.lua drives one of these methods with no dataset.
local function setUpvalue(fn, name, value)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then
      debug.setupvalue(fn, i, value)
      return true
    end
    i = i + 1
  end
end

local emitted = {}
for _, up in ipairs({
  { "MapLoader", { invalidate = function() end,
                   invalidateAll = function() end } },
  { "Collision", { load = function() end } },
  { "Game", { data = {} } },
  { "Logger", { warn = function() end, error = function() end } },
  { "Runtime", { emit = function(name, payload)
                   emitted[#emitted + 1] = { name = name, payload = payload }
                 end } },
}) do
  check(setUpvalue(OverworldState.reloadMap, up[1], up[2]),
        "reloadMap still closes over " .. up[1])
end

-- A state stub with just what reloadMap reads: the live map, the player's
-- cell, and a setMap that records the opts instead of loading anything.
-- `shrank` makes the reloaded map report the player's cell out of bounds
-- once, which is the only way past the first setMap.
local function newState(mapId, shrank)
  local calls, entered = {}, 0
  return {
    map = { id = mapId, inBounds = function() return true end },
    player = { cellX = 5, cellY = 5, facing = "down" },
    neighbors = {},
    calls = calls,
    setMap = function(self, id, x, y, facing, opts)
      calls[#calls + 1] = { id = id, x = x, y = y, facing = facing, opts = opts }
      entered = entered + 1
      local ok = not (shrank and entered == 1)
      self.map = { id = id, inBounds = function() return ok end }
    end,
    healPoint = function() return { map = "PALLET_TOWN", x = 3, y = 6 } end,
  }
end

local live = newState("ROUTE_1")
OverworldState.reloadMap(live, "ROUTE_1", "colors")
eq(#live.calls, 1, "reloading the live map re-enters it exactly once")
local opts = live.calls[1].opts or {}
check(opts.keepMusic == true,
      "the reload keeps whatever song is playing (#484): a COLORS cycle "
      .. "during a battle must not start the route theme")
eq(opts.via, "reload", "and it is still tagged as a reload, not a warp")
check(opts.seamless == true, "with no transition wipe")
eq(live.calls[1].x, 5, "the player is put back on the cell they were on")
eq(live.calls[1].y, 5, "on both axes")

-- the escape hatch under it is a genuine map change, and PlayMapMusic
-- belongs there: the player is being sent to a heal point
local shrunk = newState("ROUTE_1", true)
OverworldState.reloadMap(shrunk, "ROUTE_1", "colors")
eq(#shrunk.calls, 2, "a map that shrank under the player sends them away")
eq(shrunk.calls[2].id, "PALLET_TOWN", "to their heal point")
check(not (shrunk.calls[2].opts or {}).keepMusic,
      "and that one starts the destination's own music")

local other = newState("ROUTE_1")
OverworldState.reloadMap(other, "VIRIDIAN_CITY", "colors")
eq(#other.calls, 0, "reloading a map that is not live touches nothing")
check(emitted[#emitted] and emitted[#emitted].name == "map.reloaded",
      "map.reloaded still fires either way")

-- The hotkey half, end to end through the real Game and PaletteFX: with a
-- battle on top the COLORS key is not gated off, and every press moves one
-- rung down the ladder.
local Game = require("src.core.Game")
local PaletteFX = require("src.render.PaletteFX")

local reloads = {}
local ow = {
  map = { id = "ROUTE_1" },
  reloadMap = function(_, id, reason)
    reloads[#reloads + 1] = { id = id, reason = reason }
  end,
}
Game.overworld = ow -- PaletteFX.setMode reaches the live overworld this way

local battle = { isOpaque = true } -- stands in for BattleState on the stack
local session = {
  overworld = ow,
  save = { options = {} },
  stack = { states = { ow, battle },
            top = function(self) return self.states[#self.states] end },
  writeOptions = function() end,
}

local seen, start = {}, PaletteFX.mode
for _ = 1, #PaletteFX.MODES do
  Game.keypressed(session, "2")
  seen[#seen + 1] = PaletteFX.mode
end
eq(#reloads, #PaletteFX.MODES,
   "every COLORS press in a battle still rebuilds the map's atlas")
eq(reloads[1].reason, "colors", "tagged as the COLORS cycle")
eq(reloads[1].id, "ROUTE_1", "on the map the player is standing on")

local distinct = {}
for _, mode in ipairs(seen) do distinct[mode] = true end
local count = 0
for _ in pairs(distinct) do count = count + 1 end
eq(count, #PaletteFX.MODES,
   "the palette visibly cycles: one press per mode walks the whole ladder")
eq(PaletteFX.mode, start, "and lands back where it started")
eq(session.save.options.colors, PaletteFX.mode,
   "the choice is written to options like it is in the overworld")

-- the pre-existing gate is unchanged: a script driving the overworld still
-- holds the key off, because reloadMap rebuilds the live NPC array
local busy = {
  overworld = ow,
  save = { options = {} },
  stack = { states = { ow }, top = function(self) return self.states[1] end },
  writeOptions = function() end,
}
ow.runner = { isRunning = function() return true end }
local before = PaletteFX.mode
local reloadsBefore = #reloads
Game.keypressed(busy, "2")
eq(PaletteFX.mode, before, "a running map script still holds COLORS off")
eq(#reloads, reloadsBefore, "and nothing reloads under it")

T.finish("battle_colors_bug484")
