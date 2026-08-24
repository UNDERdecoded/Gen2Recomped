-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The overworld as one picture: every map that connects to the open one, laid
-- out where it actually sits.
--
-- WHY. The editor works one map at a time, which is the right unit for
-- painting and the wrong one for everything else. A route's edge has to line
-- up with its neighbour's; a warp goes somewhere; a new map has to be joined
-- to the world at a particular offset. All of that is invisible from inside a
-- single map, and the only way to check it was to launch the game and walk.
--
-- THE LAYOUT COMES OUT OF THE ENGINE'S OWN ARITHMETIC, not a second guess at
-- it. `OverworldController:connectionLanding` is the shipping rule:
--
--     up:    destX = curX - offset*2,  destY = destH - 1
--     down:  destX = curX - offset*2,  destY = 0
--     left:  destY = curY - offset*2,  destX = destW - 1
--     right: destY = curY - offset*2,  destX = 0
--
-- A crossing must not move the player in world space, so for `up`: A-local
-- cell cx sits at world cell ax*2 + cx, and the same point on B is
-- bx*2 + (cx - offset*2). Equal gives bx = ax + offset. The landing row is
-- B's LAST row against A's first, so by*2 + (B.height*2 - 1) = ay*2 - 1,
-- i.e. by = ay - B.height. The other three follow the same way.
--
-- Positions are in BLOCKS, like `offset` and like a map's own width/height.
-- Cells are twice that; pixels are sixteen times. Mixing the three is the
-- commonest way to get a seam one tile out, so nothing here speaks in cells.

local WorldAtlas = {}

-- How far the walk will go. A connection graph is small in practice -- Johto
-- and Kanto together are a few hundred maps -- but a malformed import can
-- contain a cycle that the visited set already stops, and this is the second
-- belt: a bounded walk cannot hang the editor while someone is looking at it.
WorldAtlas.MAX_MAPS = 400

local DIRS = { "north", "south", "east", "west" }

-- Where the neighbour's origin sits, given this map's origin and size.
--
-- Split out and named because it is the whole of the arithmetic above, and a
-- test can state each case against the derivation rather than against a
-- picture of the result.
function WorldAtlas.place(dir, x, y, w, h, nw, nh, offset)
  offset = tonumber(offset) or 0
  if dir == "north" then return x + offset, y - nh end
  if dir == "south" then return x + offset, y + h end
  if dir == "west"  then return x - nw, y + offset end
  if dir == "east"  then return x + w, y + offset end
  return nil
end

-- The inverse of `place`: where a map sits, given a NEIGHBOUR it names and
-- where that neighbour sits.
--
-- WHY THE INVERSE IS NEEDED AT ALL. `place` walks forward along a connection,
-- which is enough for a cartridge -- every one of Crystal's 142 connections is
-- symmetric, so the forward walk reaches everything. An EDIT STORE is not a
-- cartridge: a copied map names the original as its neighbour and the original
-- does not name it back, so a forward walk from the original can never reach
-- it. Dropping those is how a map that is plainly joined to Johto ends up
-- drawn as an island of its own.
--
-- Each case is `place` solved for the other side, and nothing else:
--   north:  A = (x + o, y - A.h)   =>  x = A.x - o,      y = A.y + A.h
--   south:  A = (x + o, y + h)     =>  x = A.x - o,      y = A.y - h
--   west:   A = (x - A.w, y + o)   =>  x = A.x + A.w,    y = A.y - o
--   east:   A = (x + w,   y + o)   =>  x = A.x - w,      y = A.y - o
function WorldAtlas.placeFrom(dir, ax, ay, aw, ah, w, h, offset)
  offset = tonumber(offset) or 0
  if dir == "north" then return ax - offset, ay + ah end
  if dir == "south" then return ax - offset, ay - h end
  if dir == "west"  then return ax + aw, ay - offset end
  if dir == "east"  then return ax - w, ay - offset end
  return nil
end

-- Lay out the world around `rootId`.
--
-- Returns { maps = { [id] = { id, def, x, y, w, h } }, bounds = {...},
--           conflicts = { ... } } -- or nil when the root is not a map.
--
-- CONFLICTS ARE REPORTED, NOT RESOLVED. A map reachable by two different
-- routes can be placed twice, in two different spots, and that means the
-- connection data disagrees with itself -- a real authoring mistake, and one
-- that is invisible in a single-map view. The first placement wins (so the
-- picture stays drawable) and the disagreement is handed back to be shown.
-- `opts.skip` is a set of map ids that already belong to another region. The
-- walk stops at them instead of walking through.
--
-- WITHOUT IT A MAP CAN BE IN EVERY REGION AT ONCE, and that is not a corner
-- case -- it is what an edit store does. `world()` only ever refused to START
-- a component at a map another one had claimed; it never stopped a later walk
-- from re-entering one. So an import carrying eleven edited copies of Johto's
-- maps produced eleven regions of 32 maps, every one of them anchored on New
-- Bark Town, because every walk reached the real New Bark Town and took the
-- whole of Johto with it. The picture was ten slabs of rubble sitting between
-- Johto and Kanto, each a complete duplicate of Johto.
--
-- A map belongs to exactly one region. This is where that becomes true rather
-- than merely intended.
function WorldAtlas.build(data, rootId, opts)
  opts = opts or {}
  local maps = data and data.maps
  local skip = opts.skip or {}
  local root = maps and maps[rootId or ""]
  if not root or skip[rootId] then return nil end

  local out, conflicts = {}, {}
  local order = {}
  local queue = { { id = rootId, x = 0, y = 0 } }
  local n = 0

  while #queue > 0 and n < (opts.max or WorldAtlas.MAX_MAPS) do
    local job = table.remove(queue, 1)
    local def = (not skip[job.id]) and maps[job.id] or nil
    if def then
      local seen = out[job.id]
      if seen then
        if seen.x ~= job.x or seen.y ~= job.y then
          conflicts[#conflicts + 1] = {
            id = job.id, at = { seen.x, seen.y }, also = { job.x, job.y },
            from = job.from, dir = job.dir,
          }
        end
      else
        n = n + 1
        local w = math.max(1, math.floor(def.width or 1))
        local h = math.max(1, math.floor(def.height or 1))
        out[job.id] = { id = job.id, def = def, x = job.x, y = job.y,
                        w = w, h = h }
        order[#order + 1] = job.id
        for _, dir in ipairs(DIRS) do
          local conn = def.connections and def.connections[dir]
          local ndef = conn and maps[conn.map]
          if ndef then
            local nw = math.max(1, math.floor(ndef.width or 1))
            local nh = math.max(1, math.floor(ndef.height or 1))
            local nx, ny = WorldAtlas.place(dir, job.x, job.y, w, h, nw, nh,
                                            conn.offset)
            if nx then
              queue[#queue + 1] = { id = conn.map, x = nx, y = ny,
                                    from = job.id, dir = dir }
            end
          elseif conn then
            -- A connection naming a map this import does not have. Worth
            -- saying: it is exactly what a half-ported region looks like, and
            -- from inside one map it is silent.
            conflicts[#conflicts + 1] = { id = conn.map, missing = true,
                                          from = job.id, dir = dir }
          end
        end
      end
    end
  end

  -- ONE-WAY NEIGHBOURS, placed by the inverse. Repeated until nothing new
  -- lands, because a copy can name another copy; bounded by the same budget
  -- the forward walk uses so a malformed import cannot spin here.
  if opts.reverse ~= false then
    local added = true
    while added and n < (opts.max or WorldAtlas.MAX_MAPS) do
      added = false
      for id, def in pairs(maps) do
        if not out[id] and not skip[id] and type(def) == "table"
           and def.connections then
          for _, dir in ipairs(DIRS) do
            local conn = def.connections[dir]
            local anchor = conn and out[conn.map]
            if anchor then
              local w = math.max(1, math.floor(def.width or 1))
              local h = math.max(1, math.floor(def.height or 1))
              local nx, ny = WorldAtlas.placeFrom(dir, anchor.x, anchor.y,
                                                  anchor.w, anchor.h, w, h,
                                                  conn.offset)
              if nx then
                n = n + 1
                out[id] = { id = id, def = def, x = nx, y = ny, w = w, h = h }
                order[#order + 1] = id
                added = true
              end
              break
            end
          end
        end
      end
    end
  end

  local bounds = { x0 = 0, y0 = 0, x1 = 0, y1 = 0 }
  local first = true
  for _, m in pairs(out) do
    if first then
      bounds.x0, bounds.y0 = m.x, m.y
      bounds.x1, bounds.y1 = m.x + m.w, m.y + m.h
      first = false
    else
      bounds.x0 = math.min(bounds.x0, m.x)
      bounds.y0 = math.min(bounds.y0, m.y)
      bounds.x1 = math.max(bounds.x1, m.x + m.w)
      bounds.y1 = math.max(bounds.y1, m.y + m.h)
    end
  end

  return { maps = out, order = order, bounds = bounds, conflicts = conflicts,
           root = rootId, truncated = (#queue > 0) }
end

-- ---------------------------------------------------------------- the world
--
-- WHY `build` WAS NEVER THE WHOLE PICTURE.
--
-- `build` walks OUT from one map along connections, so what it draws is the
-- connected component the open map is in -- and a Pokemon world is not one
-- component. Johto and Kanto touch only through Tohjo Falls and Victory Road,
-- which are INDOOR maps reached by warps and carry no connections at all, so
-- the outdoor graph falls into (at least) two pieces. Standing in Azalea Town
-- the world view could show Johto and had no way even to know Kanto existed.
-- Gen 1 has Kanto and its own islands; Prism has a world of its own shape
-- entirely, which is the case that settles the design: nothing here may
-- assume how many regions there are or what they are called.
--
-- SO THE REGIONS ARE THE COMPONENTS OF THE GRAPH, computed rather than
-- listed. That answers correctly for every cartridge and every romhack,
-- including one whose regions nobody has named yet, and it is the only
-- statement about regions this data can actually support.
--
-- ONLY MAPS WITH CONNECTIONS ARE IN THE WORLD. Every shop, gym and bedroom is
-- a map with no connections, reached by a warp; treating each as its own
-- one-map region would bury the world under six hundred squares. A map that
-- connects to nothing is not part of the overworld's shape -- it is furniture
-- inside it.
--
-- THE SPACE BETWEEN REGIONS IS NOT REAL, and the view says so. Inside a region
-- every offset is the engine's own arithmetic; between two regions there is no
-- arithmetic at all, because the cartridge never places them in one space. So
-- they are packed side by side to be looked at, and that packing is presented
-- as a layout choice rather than as geography.

WorldAtlas.REGION_GAP = 4        -- blocks of empty between packed regions
WorldAtlas.MINOR_REGION = 2      -- maps: at or under this, a scrap not a region

-- Does this map take part in the overworld's shape at all?
local function hasConnection(def)
  local conns = def and def.connections
  if type(conns) ~= "table" then return false end
  for _, dir in ipairs(DIRS) do
    if conns[dir] then return true end
  end
  return false
end

-- The lowest landmark id in a region, or nil where the import has none.
--
-- A map def carries `landmark`, the entry it lights on the town map, and the
-- cartridge numbers those IN ORDER: New Bark Town is 1 and Johto counts up
-- from there; Kanto starts at 47 with Pallet Town. So the lowest landmark in a
-- region is its FIRST place -- which is both the name a player would give the
-- region and, across regions, the order they were meant to be seen in.
--
-- Nothing here requires that to be true. A romhack that numbers its landmarks
-- differently gets a different first place and a different order, which is
-- still ITS first place and ITS order; an import with no landmarks at all
-- falls back to size, which is what this did before.
function WorldAtlas.firstLandmark(atlas)
  local bestId, bestLm = nil, nil
  for _, id in ipairs((atlas and atlas.order) or {}) do
    local lm = tonumber((atlas.maps[id].def or {}).landmark)
    -- ZERO IS "NO LANDMARK", not the first one. LANDMARK_SPECIAL is 0 and
    -- every map that is not a place on the town map carries it, so taking the
    -- minimum literally named Johto after whichever unnamed map happened to be
    -- walked first -- MAP_G18_N04 in one real import.
    if lm and lm > 0 and (bestLm == nil or lm < bestLm) then
      bestId, bestLm = id, lm
    end
  end
  return bestLm, bestId
end

-- What to call a region.
--
-- THE ANCHOR, NOT THE BIGGEST THING IN IT. This used to answer with the
-- region's largest city, which gave Johto "CIANWOOD CITY" and Kanto "CELADON
-- CITY" -- both true, neither the name anybody reaches for, and a rule that
-- can hand two regions the same word when a map pack brings a second copy of a
-- city in. Where landmarks exist the anchor is the region's FIRST place, which
-- is New Bark Town and Pallet Town; where they do not it is the biggest city,
-- then town, then map, exactly as before.
function WorldAtlas.regionName(atlas)
  local _, firstId = WorldAtlas.firstLandmark(atlas)
  if firstId and (firstId:find("_CITY$") or firstId:find("_TOWN$")) then
    return (firstId:gsub("_", " "))
  end

  local best, bestRank, bestArea = firstId, -1, -1
  for _, id in ipairs((atlas and atlas.order) or {}) do
    local m = atlas.maps[id]
    local rank = 0
    if id:find("_CITY$") then rank = 2
    elseif id:find("_TOWN$") then rank = 1 end
    local area = m.w * m.h
    if rank > bestRank or (rank == bestRank and area > bestArea) then
      best, bestRank, bestArea = id, rank, area
    end
  end
  if not best then return "REGION" end
  return (best:gsub("_", " "))
end

-- HOW FAR APART THE TWO PLACEMENTS ARE, in blocks.
--
-- A CONFLICT IS NOT AUTOMATICALLY A MISTAKE, and calling every one of them one
-- was wrong. Gen 2's Kanto contains cycles that do not close: walk Celadon ->
-- Saffron -> Lavender -> Route 12 -> Route 13 -> Route 14 and you land one
-- block from where Celadon -> Route 16 -> 17 -> 18 -> Fuchsia -> Route 15 ->
-- Route 14 puts you. Every edge involved is symmetric and every offset is
-- exact -- verified against the cartridge, all 142 connections, none of them
-- odd -- so there is no error to find. The game never draws two branches at
-- once, so it never has to reconcile them, and the shrunken Kanto simply does
-- not embed in a plane.
--
-- So the editor reports the DISTANCE and lets the reader judge. One or two
-- blocks is the cartridge being itself; twenty is somebody's connection being
-- wrong, and that is worth interrupting for.
function WorldAtlas.conflictDrift(c)
  if not (c and c.at and c.also) then return nil end
  return math.max(math.abs(c.at[1] - c.also[1]),
                  math.abs(c.at[2] - c.also[2]))
end

WorldAtlas.SEAM_DRIFT = 2       -- blocks: at or under this, it is the cartridge

-- Every region, packed into one picture.
--
-- Returns { regions = { { name, atlas, x, y, w, h, count } , ... },
--           maps = { [id] = { id, def, x, y, w, h, region } },
--           order = { id, ... }, bounds = {...}, conflicts = {...},
--           byMap = { [id] = regionIndex } } -- or nil with no world at all.
function WorldAtlas.world(data, opts)
  opts = opts or {}
  local maps = data and data.maps
  if type(maps) ~= "table" then return nil end

  -- Sorted so the picture is the same every time it is built: `pairs` order
  -- is not stable, and a world that rearranges itself between frames is
  -- unreadable even when every square is in the right place.
  local ids = {}
  for id, def in pairs(maps) do
    if type(id) == "string" and hasConnection(def) then ids[#ids + 1] = id end
  end
  table.sort(ids)

  -- THE COMPONENTS FIRST, THEN ONE LAYOUT PER COMPONENT.
  --
  -- This used to start a walk at every id the last walk had not claimed, which
  -- is not the same thing as finding the connected components and is wrong in
  -- both directions. An edit store carrying eleven copies of Johto's maps gave
  -- eleven regions of 32 maps because each copy rooted a fresh walk that
  -- reached the real New Bark Town; and stopping those walks at claimed maps
  -- only turned each copy into a one-map island of its own, when a map joined
  -- to Johto by a connection IS part of Johto.
  --
  -- WHAT THE GROUPING IS ACTUALLY FOR, now that `build` walks both ways: it
  -- picks ONE root per component, and picks it by the data rather than by
  -- whichever id sorted first -- so the picture is the same whichever map the
  -- reader has open. `build` would still reach the same maps from a worse
  -- root; it would just draw them somewhere else each time.
  --
  -- A component is the closure of the connection relation taken as UNDIRECTED:
  -- a connection from X to Y joins them whether or not Y names X back, because
  -- the two maps are adjacent on the ground either way. That is one pass, it
  -- is exact, and it does not depend on which map the walk happens to start
  -- from -- which is what the per-root version could never say.
  local groupOf, groups = {}, {}
  for _, id in ipairs(ids) do
    if not groupOf[id] then
      local group = { id }
      groupOf[id] = group
      groups[#groups + 1] = group
      local queue, at = { id }, 1
      while at <= #queue do
        local cur = queue[at]
        at = at + 1
        local def = maps[cur]
        for _, dir in ipairs(DIRS) do
          local conn = def and def.connections and def.connections[dir]
          local other = conn and conn.map
          if other and maps[other] and not groupOf[other] then
            groupOf[other] = group
            group[#group + 1] = other
            queue[#queue + 1] = other
          end
        end
        -- ...and the other way: a map NAMED by this one's neighbour list is
        -- joined to it, and so is a map that names THIS one. Both scans are
        -- needed because a connection can be one-way in the data.
        for other, odef in pairs(maps) do
          if not groupOf[other] and odef.connections then
            for _, dir in ipairs(DIRS) do
              local conn = odef.connections[dir]
              if conn and conn.map == cur then
                groupOf[other] = group
                group[#group + 1] = other
                queue[#queue + 1] = other
                break
              end
            end
          end
        end
      end
    end
  end

  local seen, regions, conflicts = {}, {}, {}
  local budget = opts.max or WorldAtlas.MAX_MAPS
  for _, group in ipairs(groups) do
    -- ROOTED AT THE COMPONENT'S OWN ANCHOR, so the layout is the same picture
    -- whichever map the reader happens to have open: the lowest real landmark
    -- in the component, which is its first place on the town map.
    table.sort(group)
    local root, rootLm = group[1], nil
    for _, id in ipairs(group) do
      local lm = tonumber((maps[id] or {}).landmark)
      if lm and lm > 0 and (rootLm == nil or lm < rootLm) then
        root, rootLm = id, lm
      end
    end
    if budget > 0 then
      local atlas = WorldAtlas.build(data, root, { max = budget, skip = seen })
      if atlas and next(atlas.maps) then
        local count = 0
        for mid in pairs(atlas.maps) do seen[mid] = true; count = count + 1 end
        budget = budget - count
        for _, c in ipairs(atlas.conflicts or {}) do
          conflicts[#conflicts + 1] = c
        end
        local b = atlas.bounds
        regions[#regions + 1] = {
          atlas = atlas, count = count,
          name = WorldAtlas.regionName(atlas),
          w = math.max(1, b.x1 - b.x0), h = math.max(1, b.y1 - b.y0),
        }
      end
    end
  end
  if #regions == 0 then return nil end

  -- IN THE ORDER THE CARTRIDGE COUNTS THEM. Sorting by size put Kanto (35
  -- outdoor maps) to the LEFT of Johto (31), which is backwards on every map
  -- of that world anybody has ever seen -- and size is not a fact about where
  -- a region belongs anyway. The first landmark is: Johto starts at 1 and
  -- Kanto at 47, so ordering by it puts them the way round a player expects,
  -- and does the same for a romhack that numbers its own regions in its own
  -- order. An import with no landmarks keeps the old size ordering.
  for _, r in ipairs(regions) do
    r.landmark = WorldAtlas.firstLandmark(r.atlas)
  end

  -- THE SCRAPS GO LAST, so the real regions end up next to each other.
  --
  -- An overworld graph is not only its regions. A pair of maps somebody joined
  -- while trying something out is a component; so is a map pack's two-room
  -- island; so is anything a half-finished connection leaves stranded. Sorted
  -- purely by landmark, ten of those landed BETWEEN Johto and Kanto -- each
  -- with a caption and a plate as wide as its own bounds -- and the two things
  -- the reader opened the view to compare were pushed a screen apart by
  -- rubble. Which is what "tons of stray maps in between the two regions"
  -- means.
  --
  -- MINOR IS A SIZE, NOT A JUDGEMENT, and nothing is hidden: the scraps keep
  -- their chips, their plates and their maps, and are simply not allowed to
  -- stand between two regions of a hundred maps. Two is the line because a
  -- region of three connected maps is a place and a region of two is a pair.
  for _, r in ipairs(regions) do
    r.minor = r.count <= WorldAtlas.MINOR_REGION
  end
  table.sort(regions, function(a, b)
    if a.minor ~= b.minor then return b.minor end
    if a.landmark and b.landmark and a.landmark ~= b.landmark then
      return a.landmark < b.landmark
    end
    if (a.landmark == nil) ~= (b.landmark == nil) then
      return a.landmark ~= nil
    end
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)

  -- NO TWO REGIONS WEAR THE SAME NAME. Two chips reading "CIANWOOD CITY (32)"
  -- are two chips the reader cannot tell apart, and a map pack that brings in
  -- another cartridge's cities makes that likely rather than exotic.
  local used = {}
  for _, r in ipairs(regions) do
    local name, n = r.name, 1
    while used[name] do
      n = n + 1
      name = string.format("%s (%d)", r.name, n)
    end
    used[name] = true
    r.name = name
  end

  -- AND THE ANCHOR ITSELF, kept beside the name. A chip is narrow and
  -- `NEW_BARK_TOWN_2` and `NEW_BARK_TOWN_3` both end up drawn as "NEW BARK
  -- T..." -- so the one thing that tells two regions apart is the first thing
  -- the ellipsis eats. The view can show this instead when it has to.
  for _, r in ipairs(regions) do
    local _, anchorId = WorldAtlas.firstLandmark(r.atlas)
    r.anchor = anchorId or (r.atlas.order or {})[1]
  end

  -- ONE ROW, LEFT TO RIGHT, IN THAT ORDER.
  --
  -- The wrapping grid this replaces put the fourth region under the first and
  -- turned an ordering into a seating plan -- which is unreadable precisely
  -- because the gaps between regions carry no meaning to read. A strip says
  -- one thing and says it clearly: these are the regions, in the cartridge's
  -- own order. The view pans, so a strip wider than the window is not a
  -- problem the layout has to solve.
  --
  -- Aligned along their TOPS rather than centred: a region's own shape is the
  -- thing being looked at, and centring makes two regions of different height
  -- look like they are at different latitudes.
  local gap = WorldAtlas.REGION_GAP
  local cx = 0
  for _, r in ipairs(regions) do
    r.x, r.y = cx, 0
    cx = cx + r.w + gap
  end

  local out, order, byMap = {}, {}, {}
  for ri, r in ipairs(regions) do
    local b = r.atlas.bounds
    for _, id in ipairs(r.atlas.order) do
      local m = r.atlas.maps[id]
      -- Placed once, by the region that claimed it: `seen` stops a second
      -- region ever walking into a map this one already holds, so there is no
      -- ambiguity about which offset applies.
      if not out[id] then
        out[id] = { id = id, def = m.def, w = m.w, h = m.h,
                    x = r.x + (m.x - b.x0), y = r.y + (m.y - b.y0),
                    region = ri }
        order[#order + 1] = id
        byMap[id] = ri
      end
    end
  end

  local bounds = { x0 = 0, y0 = 0, x1 = 0, y1 = 0 }
  local first = true
  for _, r in ipairs(regions) do
    if first then
      bounds.x0, bounds.y0, bounds.x1, bounds.y1 = r.x, r.y, r.x + r.w, r.y + r.h
      first = false
    else
      bounds.x0 = math.min(bounds.x0, r.x)
      bounds.y0 = math.min(bounds.y0, r.y)
      bounds.x1 = math.max(bounds.x1, r.x + r.w)
      bounds.y1 = math.max(bounds.y1, r.y + r.h)
    end
  end

  return { regions = regions, maps = out, order = order, bounds = bounds,
           conflicts = conflicts, byMap = byMap,
           truncated = budget <= 0 }
end

-- The map under a world block position, or nil. Later placements win, which
-- matches the draw order so the thing you click is the thing on top.
function WorldAtlas.at(atlas, bx, by)
  if not atlas then return nil end
  local hit = nil
  for _, id in ipairs(atlas.order or {}) do
    local m = atlas.maps[id]
    if m and bx >= m.x and bx < m.x + m.w and by >= m.y and by < m.y + m.h then
      hit = m
    end
  end
  return hit
end

return WorldAtlas
