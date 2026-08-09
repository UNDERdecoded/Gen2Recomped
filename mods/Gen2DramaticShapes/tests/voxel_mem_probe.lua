-- Driver: measure voxel-mode memory growth over the Pallet -> Mt Moon
-- trek. Teleports along the chain with voxel engaged, and after each map
-- prints the Lua heap (post-collect), LOVE texture memory, and the size
-- of the voxel mod's retained caches -- so the 4.9GB growth decomposes
-- into named pools.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local clock = (love.timer and love.timer.getTime) or os.clock

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[mem] DRAMATIC_SHAPE mod not loaded")
    return
  end
  local V = handle.lib

  local CHAIN = {
    { "PALLET_TOWN", 10, 8 },
    { "ROUTE_1", 10, 18 },
    { "VIRIDIAN_CITY", 20, 20 },
    { "ROUTE_2", 8, 30 },
    { "VIRIDIAN_FOREST", 17, 24 },
    { "ROUTE_2", 8, 10 },
    { "PEWTER_CITY", 18, 20 },
    { "ROUTE_3", 20, 5 },
    { "ROUTE_4", 10, 5 },
    { "MT_MOON_1F", 15, 20 },
  }

  game:keypressed("6")   -- voxel 15
  U.wait(20)

  local lastLua = 0
  for i, step in ipairs(CHAIN) do
    local t0 = clock()
    U.teleport(game, step[1], step[2], step[3], "down")
    U.wait(30)   -- let the voxel frame build meshes for map + neighbors
    local buildT = clock() - t0
    collectgarbage("collect")
    collectgarbage("collect")
    local luaKB = collectgarbage("count")
    local stats = love.graphics.getStats()
    print(("[mem] %-18s lua=%7.1fMB (+%6.1f) tex=%7.1fMB images=%4d canvases=%3d fonts=%d  t=%5.0fms")
      :format(step[1], luaKB / 1024, (luaKB - lastLua) / 1024,
              (stats.texturememory or 0) / 1048576,
              stats.images or -1, stats.canvases or -1, stats.fonts or -1,
              buildT * 1000))
    lastLua = luaKB
  end

  -- decompose the retained Lua heap: drop the mod's caches one at a time
  -- and re-collect, so each pool's share is named
  local ChunkMesher = V.require("ChunkMesher")
  local Structures = V.require("Structures")
  collectgarbage("collect")
  local before = collectgarbage("count")
  ChunkMesher.invalidate()       -- drops mesh cache AND Structures cache
  collectgarbage("collect")
  collectgarbage("collect")
  local after = collectgarbage("count")
  print(("[mem] voxel caches held %.1fMB of Lua heap (%.1f -> %.1f)")
    :format((before - after) / 1024, before / 1024, after / 1024))
  local stats = love.graphics.getStats()
  print(("[mem] texture memory after invalidate: %.1fMB (meshes are not textures; GPU mesh memory is untracked)")
    :format((stats.texturememory or 0) / 1048576))
  print("[mem] done")
end
