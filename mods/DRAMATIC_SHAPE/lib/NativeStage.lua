-- Where a Gen 4 / Gen 5 battle stands on the overworld, and how the camera
-- frames it (NativeGen4 draws it).
--
-- Reported from play: *"for the dramatic shapes 3d battle its too spaced
-- out, many times the pokemon ends up in the bushes or out of view"*.  The
-- old placement projected the cartridge's own battler screen spots onto the
-- ground through a low third-person camera; the foe's spot sits near the top
-- of the screen, which on a camera that low is the horizon -- so the foe
-- landed a dozen tiles away, on a tree line or behind a hedge, and was then
-- snapped to whatever walkable cell was nearest THAT.
--
-- So the stage is chosen on the ground first and the camera is solved to
-- it, rather than the other way round:
--
--   * the player's Pokemon stands on (or right beside) the cell the player
--     is on, the foe two to four cells away along the player's facing --
--     turned a quarter, or about, when the facing has no room -- so the whole
--     fight sits in a four-to-six tile patch round the encounter;
--   * every cell used is one the player could stand on: walkable, not a warp,
--     and water only where the fight is ON water (surfing, or the foe of a
--     fishing battle).  Tall grass is avoided when there is bare ground
--     close by and accepted when there is not (a field of grass is a field);
--   * the camera sits behind the player's side, swung a little to its left,
--     and its distance and aim are SOLVED so the pair spans the same share of
--     the screen whatever the gap turned out to be.
--
-- Pure placement: nothing here moves anybody.  The player's cell, the party
-- and every script are exactly where the battle left them.

local NativeStage = {}

NativeStage.CELL = 16
-- how far apart the two mons stand, in cells, in preference order (3 first;
-- a short gap beats a long one, which is what keeps it inside the patch)
NativeStage.GAPS = { 3, 2, 4 }
NativeStage.GAP_COST = { [2] = 0.8, [3] = 0, [4] = 1.2 }
-- the farthest any participant may stand from the encounter cell (Chebyshev)
NativeStage.REACH = 4
NativeStage.GRASS_COST = 2.5
NativeStage.STEP_COST = 0.08       -- per world unit of height between the pair
NativeStage.BLOCKED_BETWEEN = 6    -- per solid cell on the line between them
-- (a wall between the two is the room next door: last resort, not a cost)
-- facing first, then a quarter turn either way, then turned round
NativeStage.AXIS_COST = { 0, 1.2, 1.2, 2.6 }

-- how tall things are drawn, in TILES for the picture's whole frame (a
-- Pokemon's pic is mostly empty frame: an 80px frame at 2 tiles puts a
-- typical mon at about a tile -- overworld scale)
NativeStage.MON_FRAME_TILES = 2.0
NativeStage.TRAINER_FRAME_TILES = 1.6

-- the camera: swung this far (radians) off the stage's axis, to the player
-- side's left, so the near mon sits low-left and the foe high-right the way
-- the cartridge lays a battle out (its pair is twice as wide as it is tall,
-- so the swing is a big one); risen this many degrees over the default
-- third-person elevation (14 degrees), so the camera looks DOWN onto the
-- patch rather than along the ground into whatever stands round it; and a
-- longer lens than the walking camera's 50 degrees, which stands the eye
-- further back for the same framing and so stops the near side ballooning
-- (at 50 degrees the eye sat four tiles off and the trainer's back filled a
-- third of the screen)
NativeStage.SWING = 0.9
NativeStage.RISE = 22
NativeStage.FOV_Y = 30
-- how far (world units) toward the eye a battler's depth is taken from, so
-- the tufts of the grass it is standing in do not swallow it while a tree
-- or a wall properly in front still does
NativeStage.DEPTH_PULL = 14
-- the solve's targets, as fractions of the battle surface: how far apart the
-- two feet are on screen, and where the middle of them lands
NativeStage.SPAN = 0.42
-- ...of a surface no wider than this: a window-wide battle (NativeWide) shows
-- more of the map either side of the pair, not the same share of a screen
-- that grew only sideways, which blew the pair up past the rows it has
NativeStage.SPAN_WIDTH = 320
NativeStage.MID_X = 0.52
NativeStage.MID_Y = 0.55

local DIRS = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}

local function call(map, name, ...)
  local fn = map and map[name]
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, map, ...)
  if ok then return v end
  return nil
end

-- (ok, grass) for one participant on one cell.  `water` says whether this
-- participant may stand on water.
local function cellOK(map, x, y, water)
  if call(map, "inBounds", x, y) == false then return false end
  if call(map, "warpAtCell", x, y) then return false end
  if call(map, "isWaterCell", x, y) then return water and true or false, false end
  if not call(map, "isWalkableCell", x, y) then return false end
  local grass = call(map, "isEncounterCell", x, y) or call(map, "isGrassCell", x, y)
  return true, grass and true or false
end
NativeStage.cellOK = cellOK

local function rotate(d, quarter)
  -- a quarter turn clockwise on screen (y down): (x, y) -> (-y, x)
  local x, y = d[1], d[2]
  for _ = 1, quarter % 4 do x, y = -y, x end
  return { x, y }
end

-- plan(map, cx, cy, facing, opts) -> stage
--   opts.surfing   the player is on water (both sides may be)
--   opts.fishing   the foe came out of the water ahead (it may be on water)
--   opts.double    two a side
--   opts.groundY   function(cellX, cellY) -> height, to keep the pair on one
--                  level (optional)
-- The stage carries `cells[slot] = { x, y }` for the Gen 4 battler slots
-- (0 player, 1 foe, 2/4 player's pair, 3/5 foe's pair) and `axis`/`right`,
-- the stage's forward and screen-right directions.
function NativeStage.plan(map, cx, cy, facing, opts)
  opts = opts or {}
  local surfing, fishing = opts.surfing and true or false, opts.fishing and true or false
  local f = DIRS[facing] or DIRS.up
  local heightOf = opts.groundY
  local best, bestCost
  local seen = {}
  local function okP(x, y)
    local k = "p" .. x .. "," .. y
    local v = seen[k]
    if v == nil then
      local ok, grass = cellOK(map, x, y, surfing)
      v = ok and { grass } or false
      seen[k] = v
    end
    return v
  end
  local function okE(x, y)
    local k = "e" .. x .. "," .. y
    local v = seen[k]
    if v == nil then
      local ok, grass = cellOK(map, x, y, surfing or fishing)
      v = ok and { grass } or false
      seen[k] = v
    end
    return v
  end
  local R = NativeStage.REACH
  -- REACHABLE FROM WHERE THE PLAYER STANDS, over the same ground: a cell
  -- behind a wall, across a ledge or in the void round a room is open by
  -- the walk test and still the wrong place for half a fight.  A flood over
  -- open cells (water too when the fight is on it) out to the reach plus
  -- one, seeded on the player's cell whatever that cell answers.
  local reach = { [cy * 65536 + cx] = true }
  do
    local q, head = { { cx, cy } }, 1
    while head <= #q do
      local c = q[head]; head = head + 1
      for _, d in pairs(DIRS) do
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local k = ny * 65536 + nx
        if not reach[k] and math.max(math.abs(nx - cx), math.abs(ny - cy)) <= R + 1
           and cellOK(map, nx, ny, surfing or fishing) then
          reach[k] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  local function reached(x, y) return reach[y * 65536 + x] or false end
  for ai = 1, 4 do
    local d = rotate(f, ({ 0, 1, 3, 2 })[ai])
    local r = rotate(d, 1)
    for _, back in ipairs({ 0, -1 }) do
      for _, side in ipairs({ 0, 1, -1 }) do
        local px, py = cx + d[1] * back + r[1] * side, cy + d[2] * back + r[2] * side
        local p = reached(px, py) and okP(px, py)
        if p then
          for _, gap in ipairs(NativeStage.GAPS) do
            for _, lat in ipairs({ 0, 1, -1 }) do
              local ex, ey = px + d[1] * gap + r[1] * lat, py + d[2] * gap + r[2] * lat
              if math.max(math.abs(ex - cx), math.abs(ey - cy)) <= R then
                local e = reached(ex, ey) and okE(ex, ey)
                if e then
                  local cost = NativeStage.AXIS_COST[ai]
                    + math.abs(back) * 0.9 + math.abs(side) * 1.1
                    + NativeStage.GAP_COST[gap] + math.abs(lat) * 0.7
                  -- grass: only where the encounter is not itself a field of
                  -- it is this a cost worth paying; it is added either way and
                  -- a field simply costs every candidate the same
                  if p[1] then cost = cost + NativeStage.GRASS_COST end
                  if e[1] then cost = cost + NativeStage.GRASS_COST end
                  -- solid cells on the straight line between them: a tree
                  -- between the two reads as the fight happening through it
                  for s = 1, gap - 1 do
                    local bx, by = px + d[1] * s, py + d[2] * s
                    if not cellOK(map, bx, by, true) then
                      cost = cost + NativeStage.BLOCKED_BETWEEN
                    end
                  end
                  if heightOf then
                    local okH, h1 = pcall(heightOf, px, py)
                    local okH2, h2 = pcall(heightOf, ex, ey)
                    if okH and okH2 and h1 and h2 then
                      local dh = math.abs(h1 - h2)
                      if dh > 4 then cost = cost + (dh - 4) * NativeStage.STEP_COST end
                    end
                  end
                  if not bestCost or cost < bestCost - 1e-9 then
                    best = { px = px, py = py, ex = ex, ey = ey, d = d, r = r,
                             gap = gap, axis = ai }
                    bestCost = cost
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  if not best then
    -- NOWHERE FITS (a one-cell corridor with a wall ahead, a ledge, a
    -- doorway): stand the pair two cells apart along the facing anyway, so the
    -- fight is at least where the player is rather than a dozen tiles off
    local d = f
    best = { px = cx, py = cy, ex = cx + d[1] * 2, ey = cy + d[2] * 2, d = d,
             r = rotate(d, 1), gap = 2, axis = 0, fallback = true }
    bestCost = math.huge
  end

  local stage = {
    cx = cx, cy = cy, axis = best.axis, gap = best.gap, cost = bestCost,
    double = opts.double and true or false,
    fallback = best.fallback,
    forward = best.d, right = best.r,
    cells = {},
    -- world units per cell offset for a partner that has no cell of its own
    world = {},
  }
  local P, E = { best.px, best.py }, { best.ex, best.ey }
  stage.cells[0], stage.cells[1] = P, E
  -- DOUBLES: the partner on the next cell to the side when that cell is
  -- open, else the two share the cell, half a cell either side of its middle
  -- ...and half a cell further apart than the cells say: the swung camera
  -- foreshortens this axis, and a neighbouring cell left a big mon (a Charizard's
  -- whole frame) standing square in front of its partner
  local SPREAD = NativeStage.CELL / 2
  local r = best.r
  local function pair(c, ok, leftSlot, rightSlot)
    local rx, ry = c[1] + r[1], c[2] + r[2]
    local lx, ly = c[1] - r[1], c[2] - r[2]
    -- the cell to the LEFT first: `right` also leans toward the eye (the
    -- camera is swung round to that side), so a partner put there stands
    -- nearer the lens and low enough to go under the text box
    if ok(lx, ly) then
      stage.cells[leftSlot], stage.cells[rightSlot] = { lx, ly }, c
      stage.world[leftSlot] = { -r[1] * SPREAD, -r[2] * SPREAD }
      stage.world[rightSlot] = { r[1] * SPREAD, r[2] * SPREAD }
    elseif ok(rx, ry) then
      stage.cells[leftSlot], stage.cells[rightSlot] = c, { rx, ry }
      stage.world[leftSlot] = { -r[1] * SPREAD, -r[2] * SPREAD }
      stage.world[rightSlot] = { r[1] * SPREAD, r[2] * SPREAD }
    else
      stage.cells[leftSlot], stage.cells[rightSlot] = c, c
      stage.world[leftSlot] = { -r[1] * 5, -r[2] * 5 }
      stage.world[rightSlot] = { r[1] * 5, r[2] * 5 }
    end
  end
  -- 2 is the player's left, 4 the player's right; the foe's 5 is the left
  -- one on screen and 3 the right (Gen4Battle.BATTLER_POS)
  pair(P, function(x, y) return reached(x, y) and okP(x, y) end, 2, 4)
  pair(E, function(x, y) return reached(x, y) and okE(x, y) end, 5, 3)
  return stage
end

-- The world point (map-local pixels) a slot's feet stand on.
function NativeStage.point(stage, slot)
  local c = stage and stage.cells[slot]
  if not c then return nil end
  local x = c[1] * NativeStage.CELL + NativeStage.CELL / 2
  local z = c[2] * NativeStage.CELL + NativeStage.CELL / 2
  local w = stage.world[slot]
  if w then x, z = x + w[1], z + w[2] end
  return x, z
end

-- The yaw (Gen4View's: 0 looking north, clockwise) the stage's axis points.
function NativeStage.axisYaw(stage)
  local d = stage.forward
  return math.atan2(d[1], -d[2])
end

-- solve(stage, view, View, ground, w, h) -> { x, z, zoom, yaw, rise, baseY }
--
-- The camera this stage is shot from, at rest: the pivot (absolute matrix
-- coordinates, as Gen4View.follow takes them), the third-person zoom, yaw
-- and rise.  A handful of fixed-point steps -- zoom by the ratio of the span
-- to the target, pivot by the screen error over the pixels a unit is worth
-- -- converge in four or five on every stage measured; eight are run.
function NativeStage.solve(stage, view, View, ground, w, h)
  local ox, oz = ground.offsetX or 0, ground.offsetY or 0
  local px, pz = NativeStage.point(stage, 0)
  local ex, ez = NativeStage.point(stage, 1)
  -- DOUBLES frame each side's PAIR: the middle of the two on each side is
  -- what the span and the aim are solved for, so the partner standing a
  -- cell nearer the eye is not left under the text box
  if stage.double then
    local function centre(a, b, fx, fz)
      local ax, az = NativeStage.point(stage, a)
      local bx, bz = NativeStage.point(stage, b)
      if not (ax and bx) then return fx, fz end
      return (ax + bx) / 2, (az + bz) / 2
    end
    px, pz = centre(2, 4, px, pz)
    ex, ez = centre(5, 3, ex, ez)
  end
  local function gy(x, z)
    local ok, v = pcall(ground.groundY, ground, x, z)
    return (ok and v) or 0
  end
  local py, ey = gy(px, pz), gy(ex, ez)
  local baseY = py
  local yaw = NativeStage.axisYaw(stage) - NativeStage.SWING
  local rise = NativeStage.RISE
  local zoom = 1.0
  local mx, mz = (px + ex) / 2, (pz + ez) / 2
  local fx, fz = math.sin(yaw), -math.cos(yaw)     -- flat forward
  local rx, rz = math.cos(yaw), math.sin(yaw)      -- flat right
  view.fovY = NativeStage.FOV_Y
  local look = View.look
  local sol = { x = mx + ox, z = mz + oz, zoom = zoom, yaw = yaw, rise = rise, baseY = baseY }
  for _ = 1, 8 do
    View.look = { orbiting = true, yaw = yaw, rise = rise, zoom = zoom }
    view:follow(mx + ox, mz + oz, 0, baseY)
    View.look = look
    local ax, ay = view:project(px + ox, py, pz + oz, w, h)
    local bx, by, ppu = view:project(ex + ox, ey, ez + oz, w, h)
    if not (ax and bx) then
      zoom = zoom * 1.4
    else
      local span = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
      -- SPAN is for the three-cell gap; a shorter or longer one keeps the
      -- same WORLD scale (two cells apart is closer together on screen, not
      -- a closer camera making everything bigger)
      local gapWorld = math.sqrt((ex - px) ^ 2 + (ez - pz) ^ 2)
      local want = NativeStage.SPAN * math.min(w, NativeStage.SPAN_WIDTH) * math.max(0.4, gapWorld / (3 * NativeStage.CELL))
      if span > 1e-3 then
        zoom = zoom * span / want
      end
      if zoom < 0.25 then zoom = 0.25 elseif zoom > 8 then zoom = 8 end
      local _, _, ppuM = view:project(mx + ox, (py + ey) / 2, mz + oz, w, h)
      ppuM = ppuM or ppu or 1
      local errX = (ax + bx) / 2 - NativeStage.MID_X * w
      -- (a double's pairs reach further down the screen: aim a little higher)
      local errY = (ay + by) / 2 - (NativeStage.MID_Y - (stage.double and 0.07 or 0)) * h
      -- too far right: move the pivot right (the world slides left); too
      -- low: move it back toward the eye (the world rises)
      local e = math.rad(14 + rise)
      local sx = errX / ppuM * 0.8
      local sz = errY / ppuM / math.max(0.35, math.sin(e)) * 0.8
      mx, mz = mx + rx * sx - fx * sz, mz + rz * sx - fz * sz
    end
  end
  sol.x, sol.z, sol.zoom = mx + ox, mz + oz, zoom
  return sol
end

return NativeStage
