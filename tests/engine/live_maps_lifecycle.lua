package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Version = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local LiveMaps = require("src.world.LiveMaps")
local Fixture = dofile("tests/live_maps/fixture.lua")
local Cases = dofile("tests/live_maps/cases.lua")
local old = Version.get()
for _, version in ipairs(Version.ORDER) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = Fixture.new(".", "gen2", version, mode[1], mode[2])
    f.commonEvents = true -- Gen2's real shared overworld produces events on every host.
    local world, e = f.world, f.e
    T.eq(e.api:supports("events", "world.live_maps_preparing"), true, "native preparing capability")
    T.eq(e.api:supports("events", "world.live_maps_updated"), true, "native updated capability")
    Cases.run(f)
    if mode[1] < 3 then
      local maps = e.maps()
      T.eq(maps[2].x, 2 * f.pixel / 16, "legacy reader retains cell coordinates")
      T.eq(maps[2].ox, nil, "legacy reader shape is preserved")
    else
      T.eq(e.api:supports("world", "liveMaps"), true, "API-3 reader supports native host")
      local neighbors = world.neighbors
      world.neighbors = { neighbors[1], neighbors[1], { map = neighbors[1].map, ox = -16, oy = 32 } }
      local placements = e.maps()
      T.eq(#placements, 4, "API-3 retains native placement order and duplicates")
      T.eq(placements[4].ox, -16, "same map at another offset is retained")
      world.neighbors = neighbors
      f.game.world, f.game.overworld = nil, nil
      local missing, why = e.maps()
      T.eq(missing, nil, "API-3 query without a world is safe")
      T.eq(why, "no overworld", "API-3 missing-world reason")
      f.game.world, f.game.overworld = world, world
    end
    local once = 0
    e.api.events:once("world.live_maps_updated", function()
      once = once + 1
    end)
    f.rebuild()
    f.rebuild()
    T.eq(once, 1, "once unsubscribes from native event")
    local calls = 0
    local off = e.api.events:on("world.live_maps_preparing", function()
      calls = calls + 1
      T.eq(world.preparingLiveMaps, true, "preparation callback owns preparation phase")
      local legacy = require("src.mods.WorldReads").liveMaps(world)
      T.eq(legacy[2].x, 2 * f.pixel / 16, "legacy offsets are ready during preparation")
      f.game.data.maps.EAST.objects = {
        {
          index = 1,
          name = "LIVE_GHOST",
          sprite = "SPRITE_FIX_NPC",
          movement = "STAY",
          range = "NONE",
          x = 0,
          y = 0,
        },
      }
    end)
    f.rebuild()
    T.eq(calls, 1, "preparing runs once before native ghost construction")
    T.eq(#world.ghosts, 1, "preparation changes reach actual ghost builder")
    T.eq(world.ghosts[1].npc.id, "EAST_obj_1", "native NPC was constructed")
    off()
    local before = #e.events
    local failure = e.api.events:on("world.live_maps_preparing", function()
      error("intentional listener failure")
    end, 100)
    f.rebuild()
    T.eq(#e.events, before + 2, "failed listener does not prevent either lifecycle notification")
    T.eq(world.preparingLiveMaps, nil, "failed listener leaves no preparation flag")
    failure()
    before = #e.events
    local nested = e.api.events:on("world.live_maps_preparing", function()
      f.rebuild()
    end, 100)
    f.rebuild()
    T.eq(#e.events, before + 2, "nested rebuild does not recursively notify preparation")
    T.eq(world.preparingLiveMaps, nil, "nested rebuild restores preparation flag")
    nested()
    before = #e.events
    e.stop()
    e.stop()
    f.rebuild()
    T.eq(#e.events, before, "consumer unsubscribe stops native delivery")
    f.close()
    local failed = Fixture.new(".", "gen2", version, mode[1], mode[2], true)
    T.check(#failed.result.errors > 0, "entry failure is recorded")
    failed.rebuild()
    for _, name in ipairs({ "world.live_maps_preparing", "world.live_maps_updated" }) do
      for _, entry in ipairs(Runtime.events.listeners[name] or {}) do
        T.check(entry.owner ~= "portable_live_maps", "entry rollback removes owned listener")
      end
    end
    failed.close()
  end
end
-- No-listener rebuilds never allocate a snapshot; data-only reads never load maps.
do
  local f = Fixture.new(".", "gen2", "red", 3, "unified")
  Runtime.install(require("src.mods.Events").new(), require("src.mods.Hooks").new(), {})
  local snapshot = LiveMaps.snapshot
  LiveMaps.snapshot = function()
    error("unsubscribed snapshot allocation")
  end
  local ok = pcall(f.rebuild)
  LiveMaps.snapshot = snapshot
  T.eq(ok, true, "native hot path skips snapshots without listeners")
  f.close()
end
Version.set(old)
T.finish("portable live-map events and API-3 pixel placements")
