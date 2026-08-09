-- Driver: which building models exist, and how much of this map is
-- claimed by objects?
--
-- Buildings.build matches every profiled template against the whole map
-- and stamps each hit, so two templates whose tile grids both match one
-- drawing stamp TWO models into the same cells.
--
-- READ THE CAVEAT BEFORE TRUSTING THIS. Buildings.stats() reports the
-- module's `models` cache, which is keyed "<tileset>:<index>" and is
-- GLOBAL AND CUMULATIVE for the session -- it lists every model built
-- since boot, including ones from maps visited earlier, and says nothing
-- about where they were placed. It is a memoisation table, not a
-- placement log. Reading it as "what is on this map" will convince you a
-- foreign building has stamped here when it has not.
--
-- To answer "does template X place on map Y", match its `tiles` grid
-- against the map's tile grid OFFLINE (the map and tileset tables the
-- ROM importer writes into the player's own cache -- see
-- tools/voxel-survey.md for the paths) -- no engine needed, and it gives
-- you the coordinates.
-- And note a drawing can STRADDLE A MAP BOUNDARY (the Pokemon Tower's
-- roof is on ROUTE_10, its facade on LAVENDER_TOWN), in which case no
-- single map's grid holds the whole thing and each half meshes alone.
--
--   BUILD_MAP=LAVENDER_TOWN POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/voxel_building_probe.lua lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapId = os.getenv("BUILD_MAP") or "LAVENDER_TOWN"
  U.teleport(game, mapId, tonumber(os.getenv("BUILD_X") or "3"),
             tonumber(os.getenv("BUILD_Y") or "5"), "up")
  U.wait(10)

  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  local Structures = V and V.require("Structures")
  local Buildings = V and V.require("Buildings")
  local ow = game.overworld
  if not (Structures and Buildings and ow and ow.map) then
    print("[bld] mod or map unavailable")
    return
  end

  -- placements are recorded as the templates are stamped, so force the
  -- analysis first
  Structures.forMap(ow.map)

  print(("[bld] %s"):format(mapId))
  local stats = Buildings.stats and Buildings.stats() or {}
  local keys = {}
  for k in pairs(stats) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local s = stats[k]
    print(("[bld]   %-24s voxels=%s shell=%s quads=%s"):format(
      k, tostring(s.voxels), tostring(s.shell), tostring(s.quads)))
  end

  -- and the per-cell truth: which cells a building claimed
  local S = Structures.forMap(ow.map)
  local def = ow.map.def
  local claimed = 0
  for ty = 0, def.height * 4 - 1 do
    for tx = 0, def.width * 4 - 1 do
      if S.skip[(ty + 64) * 4096 + (tx + 64)] then claimed = claimed + 1 end
    end
  end
  print(("[bld]   tiles claimed by objects/buildings: %d"):format(claimed))
  print("[bld] done")
end
