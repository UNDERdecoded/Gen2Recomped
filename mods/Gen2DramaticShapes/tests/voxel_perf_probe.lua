-- Driver: diagnose the voxel mode-switch hitch and map-seam artifacts.
--
-- Three passes, all printed:
--   1. Teleport to Route 1, engage voxel, and time every build-side
--      function (Structures, ChunkMesher, meshes, atlases) plus per-frame
--      wall time, so the mode-switch hitch decomposes into named costs.
--   2. Rebuild the seam-band geometry CPU-side and list every quad that
--      rises above the ground plane near the Route 1 / Pallet seam, to
--      name the source of the stray pixels.
--   3. Walk across the seam both ways logging the ground height the
--      voxel pass would stand the player on each frame (the "hop").
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "shots"
  local clock = (love.timer and love.timer.getTime) or os.clock

  U.teleport(game, "ROUTE_1", 10, 30, "down")
  U.wait(10)

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[perf] DRAMATIC_SHAPE mod not loaded")
    return
  end
  local V = handle.lib
  local Structures = V.require("Structures")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel3D = V.require("Voxel3D")
  local TerrainAtlas = V.require("TerrainAtlas")
  local TileShape = V.require("TileShape")

  -- ---- pass 1: instrument the build ----
  local stats, order = {}, {}
  local function wrap(tbl, name, label, argLabel)
    local orig = tbl[name]
    if not orig then print("[perf] missing " .. label); return end
    tbl[name] = function(...)
      local t0 = clock()
      local r1, r2, r3 = orig(...)
      local dt = clock() - t0
      local lbl = label
      if argLabel then
        local extra = argLabel(...)
        if extra then lbl = label .. "[" .. tostring(extra) .. "]" end
      end
      local s = stats[lbl]
      if not s then
        s = { n = 0, total = 0, max = 0 }
        stats[lbl] = s
        order[#order + 1] = lbl
      end
      s.n = s.n + 1
      s.total = s.total + dt
      if dt > s.max then s.max = dt end
      return r1, r2, r3
    end
  end
  local mapId = function(map) return map.id end
  wrap(Structures, "forMap", "Structures.forMap", mapId)
  wrap(Structures, "extractObjects", "Structures.extractObjects")
  wrap(Structures, "buildVolume", "Structures.buildVolume")
  wrap(Structures, "buildObject", "Structures.buildObject")
  wrap(Structures, "buildGrass", "Structures.buildGrass")
  wrap(Structures, "buildCylinders", "Structures.buildCylinders")
  wrap(Structures, "buildStairs", "Structures.buildStairs")
  wrap(Structures, "buildBookcases", "Structures.buildBookcases")
  wrap(ChunkMesher, "geometry", "ChunkMesher.geometry", mapId)
  wrap(ChunkMesher, "build", "ChunkMesher.build", mapId)
  wrap(Voxel3D, "newMesh", "Voxel3D.newMesh")
  wrap(TerrainAtlas, "forMap", "TerrainAtlas.forMap", mapId)

  -- engage voxel level 2 (35 degrees) like the player: 6, then 6 again
  local frameTimes = {}
  game:keypressed("6")
  for i = 1, 30 do
    local f0 = clock()
    coroutine.yield()
    frameTimes[i] = clock() - f0
  end
  game:keypressed("6")
  for i = 31, 60 do
    local f0 = clock()
    coroutine.yield()
    frameTimes[i] = clock() - f0
  end
  U.shot(game, DIR .. "/perf_route1_voxel.png")

  local sorted = {}
  for _, lbl in ipairs(order) do sorted[#sorted + 1] = lbl end
  table.sort(sorted, function(a, b) return stats[a].total > stats[b].total end)
  print("[perf] ---- build stats (sorted by total) ----")
  for _, lbl in ipairs(sorted) do
    local s = stats[lbl]
    print(("[perf] %-50s n=%5d total=%8.1fms max=%7.1fms")
      :format(lbl, s.n, s.total * 1000, s.max * 1000))
  end
  print("[perf] ---- frame spikes over 25ms ----")
  for i, ft in ipairs(frameTimes) do
    if ft > 0.025 then
      print(("[perf] frame %02d: %.1fms"):format(i, ft * 1000))
    end
  end

  -- ---- pass 2: seam-band geometry scan ----
  local function scanQuads(tag, verts, ox, oy, zlo, zhi, xlo, xhi)
    local n = 0
    for i = 1, #verts, 4 do
      local minX, minY, minZ = math.huge, math.huge, math.huge
      local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
      for j = i, i + 3 do
        local v = verts[j]
        local x, y, z = v[1] + ox, v[2], v[3] + oy
        if x < minX then minX = x end
        if x > maxX then maxX = x end
        if v[2] < minY then minY = y end
        if y > maxY then maxY = y end
        if z < minZ then minZ = z end
        if z > maxZ then maxZ = z end
      end
      if maxY > 0.01 and minZ < zhi and maxZ > zlo
         and (not xlo or (minX < xhi and maxX > xlo)) then
        n = n + 1
        if n <= 60 then
          print(("[seam] %s x[%6.1f..%6.1f] y[%5.1f..%5.1f] z[%6.1f..%6.1f]")
            :format(tag, minX, maxX, minY, maxY, minZ, maxZ))
        end
      end
    end
    print(("[seam] %s: %d raised quads in band"):format(tag, n))
  end
  local function flatQuads(list)
    -- Structures object/grass quad lists ({v1..v4, uv=..} entries) -> verts
    local verts = {}
    for _, q in ipairs(list) do
      for j = 1, 4 do verts[#verts + 1] = q[j] end
    end
    return verts
  end

  local ow = game.overworld
  print("[seam] current map: " .. tostring(ow.map.id))
  local masks = {}
  for _, nb in ipairs(ow.neighbors or {}) do
    masks[#masks + 1] = { nb.ox, nb.oy, nb.ox + nb.map.def.width * 32,
                          nb.oy + nb.map.def.height * 32 }
    print(("[seam] neighbor %-16s ox=%d oy=%d"):format(nb.map.id, nb.ox, nb.oy))
  end
  local seamZ = ow.map.def.height * 32
  local zlo, zhi = seamZ - 24, seamZ + 24
  print(("[seam] scanning band z=[%d..%d] (Route 1 south edge at %d)")
    :format(zlo, zhi, seamZ))
  do
    local verts = ChunkMesher.geometry(ow.map, false, masks)
    scanQuads("cur.full ", verts, 0, 0, zlo, zhi)
    local S = Structures.forMap(ow.map)
    scanQuads("cur.grass", flatQuads(S.grassQuads), 0, 0, zlo, zhi)
    scanQuads("cur.objs ", flatQuads(S.objectQuads), 0, 0, zlo, zhi)
  end
  for _, nb in ipairs(ow.neighbors or {}) do
    local verts = ChunkMesher.geometry(nb.map, true)
    scanQuads("nb." .. nb.map.id, verts, nb.ox, nb.oy, zlo, zhi)
    local S = Structures.forMap(nb.map)
    scanQuads("nb." .. nb.map.id .. ".grass", flatQuads(S.grassQuads),
              nb.ox, nb.oy, zlo, zhi)
  end

  -- ---- pass 3: cross the seam both ways, logging ground height ----
  local function crossLog(fromMap, x, y, dir, steps, tag)
    U.teleport(game, fromMap, x, y, dir)
    U.wait(20)
    print(("[hop] ---- %s: %s (%d,%d) heading %s ----")
      :format(tag, fromMap, x, y, dir))
    for i = 1, steps do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      local f0 = clock()
      coroutine.yield()
      local ft = clock() - f0
      local o = game.overworld
      local p = o.player
      local m = o.map
      local shapes = TileShape.forMap(m)
      local s = shapes[m:cellTile(p.cellX, p.cellY)]
      local g = 0
      if s and s.art ~= "stair" and s.h > 0 then g = s.h end
      if not m:inBounds(p.cellX, p.cellY) or g ~= 0 or ft > 0.025 then
        print(("[hop] f%02d map=%-14s cell=(%d,%d) py=%.0f inB=%s gh=%d cls=%s ft=%.0fms")
          :format(i, m.id, p.cellX, p.cellY, p.py,
                  tostring(m:inBounds(p.cellX, p.cellY)), g,
                  s and s.class or "?", ft * 1000))
      end
      game.input.state[dir] = false
    end
    local o = game.overworld
    print(("[hop] end map=%s cell=(%d,%d)")
      :format(o.map.id, o.player.cellX, o.player.cellY))
  end
  crossLog("ROUTE_1", 10, 34, "down", 60, "route1 -> pallet")
  U.shot(game, DIR .. "/perf_pallet_after_cross.png")
  crossLog("PALLET_TOWN", 10, 1, "up", 60, "pallet -> route1")
  U.shot(game, DIR .. "/perf_route1_after_cross.png")

  print("[perf] done")
end
