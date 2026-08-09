-- Voxel world mode: a building voxelized from its own sprite.
--
-- A Game Boy overworld building is a fake-3D projection that packs several
-- different 3D facings into one flat drawing: the roof is drawn as if seen
-- from above, the facade as if seen face-on, and the sloped ends as
-- diagonal silhouettes. Raising the whole footprint as one box (what the
-- generic volume path does) folds all three into a wall, so a house comes
-- out as a cube wearing its own elevation.
--
-- This module does the other thing: it classifies each BAND of the drawing
-- by the surface it depicts and applies the matching operation per band --
-- the pipeline written up in assets/docs/buidling_to_voxel/. Two rules govern it:
--
--   1. Every visible voxel colour is a real texel of the drawing. Nothing
--      is invented but the geometry the sprite implies and never paints
--      (undersides, the depth behind the facade), and those wear the
--      drawing's own four shades.
--   2. The sprite is ground truth, not the tile grid. The silhouette, the
--      taper rate, the eave height and every window are MEASURED off the
--      pixels; the profile only says which rows are roof and which are
--      facade.
--
-- The pipeline, per template (see data/voxel_heights.lua `buildings`):
--
--   read     composite the building out of the atlas and flood its
--            silhouette in from the border through light pixels only --
--            the black outline and the #555 shading together are the
--            boundary, and a "not black" test eats the shaded flanks.
--   measure  the topmost drawn row of each column IS the roof's elevation
--            profile (the drawn taper is the slope); the facade's panes
--            are the non-black regions its black frames seal off.
--   build    facade rows extrude straight back over the footprint, the
--            awning band juts past them, panes sink one voxel, and the
--            roof lays the top-facing rows flat -- level over the
--            plateau, stepping down the drawn taper at the ends -- then
--            overwrites the walls it intersects.
--   emit     cull to the shell and merge runs of texel-adjacent faces into
--            single quads, so a 90k-voxel house ships as ~2k quads.
--
-- One model is built per template and stamped at every placement: Red's
-- and Blue's houses are the same seven-placement drawing, so they cost one
-- build between them. mods/DRAMATIC_SHAPE/tools/building_voxels.py is the
-- reference implementation of the same algorithm and prints the voxel and
-- shell counts this one must agree with.
--
-- Purely presentational, like everything else in the mod: the tiles a
-- building claims keep the collision, warps and triggers they always had.

-- the mod namespace (see main.lua): V.data loads a shipped data file
local V = ...

local Budget = V.require("BuildBudget")

local Buildings = {}

-- The four GB shades, lightest first (same cutoffs as Structures.shadeClass,
-- which reasons about the same art).
local WHITE, GREY, DARK, BLACK = 0, 1, 2, 3

-- A pane is a window or a doorway: a non-black region the drawing seals
-- off behind its own black frame. Anything wider or taller than this is a
-- band of the facade itself -- a siding course, the awning's grey field --
-- and must stay flush.
local RECESS_MAX = 24

-- Face shades, matching the rest of the mod's objects: the south face is
-- the drawing itself and draws at full brightness.
local SHADE = { top = 0.95, south = 1.0, north = 0.68,
                side = 0.78, bottom = 0.5 }

-- ------- how far a merged run may reach: the tile lattice
--
-- Merging is what keeps a 90k-voxel house down to ~2k quads, and under a
-- straight projection a run may be as long as it likes -- a straight line
-- is a straight line however finely it is cut. THE WORLD CURVE IS NOT
-- STRAIGHT. It drops every vertex by the square of its distance from the
-- focus (see WorldCurve), so a quad's interior is the CHORD of a parabola
-- its neighbours draw the arc of: a run of length L hangs k*L^2/4 below
-- the short quads butted against it, and the join tears open.
--
-- Nothing bounded a run's length before, and the runs that ran away were
-- the ones wearing a CONSTANT texel -- the roof's black eave outline, its
-- fascia, the shaded underside -- because a flat run has no art to break
-- it. Those reached 102px across a gym, which at V-CURVE 3 hangs some
-- three world pixels under the roof surface beside it: the eave tore off
-- the roof and the drop showed the building's dark interior through the
-- slot. (Strip runs, the drawing marching along the atlas, break at the
-- tileset's own boundaries and were never the problem.)
--
-- So a run stops at the next 8px lattice line. Buildings are stamped at
-- tx*8 (see stamp), so the model's lattice IS the map's: every quad in the
-- scene -- terrain, props, this -- now ends on the same lines, every join
-- is vertex-for-vertex, and the bend carries them together. What is left
-- is the sag WITHIN one cell, k*64/4, which is under a twentieth of a
-- world pixel at any rung.
--
-- It costs quads on a dense city map (Cerulean's object stream goes from
-- 35.7k to 41.6k, and its longest edge from 102px to 8px) and it costs them
-- whether the curve is on or not, which is the deliberate trade: the mesh
-- is cached per map and built asynchronously over seconds, so meshing for
-- the curve's sake only when the curve is on would mean rebuilding every
-- live map on a keypress.
local CELL = 8

-- How far a run starting at `a` may go before it crosses the next lattice
-- line. Floor-mod, so the awning's negative z lands on the same lines the
-- positive side does.
local function runCap(a)
  return CELL - a % CELL
end

local function keyOf(tx, ty)
  return (ty + 64) * 4096 + (tx + 64)
end

local function shadeOf(r, g, b, a)
  if a == 0 then return WHITE end
  local v = math.min(r, g, b)
  if v <= 0.25 then return BLACK end
  if v <= 0.55 then return DARK end
  if v <= 0.85 then return GREY end
  return WHITE
end

-- The shape profile ships with the mod; absent or broken simply means no
-- building templates, and every building falls back to the volume path.
local spec = nil
local function profile()
  if spec == nil then
    local ok, s = pcall(V.data, "voxel_heights")
    spec = (ok and type(s) == "table") and s or false
  end
  return spec or nil
end

local models = {}          -- "<tileset>:<index>" -> prebuilt local quads

-- ------------------------------------------------------------------ read --

-- Composite the template out of the atlas and flood the silhouette in from
-- the border. Returns flat arrays indexed y * W + x.
--
-- `topRows`, when a template carries it, is extra drawing rows composited
-- ABOVE the matched grid: rows of the same drawing that are not on the
-- map this template places on. The Pokemon Tower is the case that needs
-- it -- the drawing straddles the LAVENDER_TOWN / ROUTE_10 boundary, its
-- roof band and top window courses standing in the route's last rows, so
-- no single map's grid holds the whole building. The matcher never sees
-- topRows (placement is still by `tiles` alone); they exist so the MODEL
-- is built from the complete drawing and the tower rises to its real
-- height instead of folding as two half-buildings.
local function read(t, data, perRow)
  local tiles = t.tiles
  if t.topRows then
    tiles = {}
    for _, row in ipairs(t.topRows) do tiles[#tiles + 1] = row end
    for _, row in ipairs(t.tiles) do tiles[#tiles + 1] = row end
  end
  local bh, bw = #tiles, #t.tiles[1]
  local W, H = bw * 8, bh * 8
  local col, ax, ay = {}, {}, {}
  for sy = 0, H - 1 do
    Budget.tick()
    local row = tiles[math.floor(sy / 8) + 1]
    for sx = 0, W - 1 do
      local tile = row[math.floor(sx / 8) + 1]
      local px = (tile % perRow) * 8 + sx % 8
      local py = math.floor(tile / perRow) * 8 + sy % 8
      local i = sy * W + sx
      ax[i], ay[i] = px, py
      local r, g, b, a = data:getPixel(px, py)
      col[i] = shadeOf(r, g, b, a)
    end
  end

  local outside = {}
  local queue, n = {}, 0
  local function seed(x, y)
    local i = y * W + x
    if not outside[i] and col[i] <= GREY then
      outside[i] = true
      n = n + 1
      queue[n] = i
    end
  end
  -- The flood comes in from the border, which assumes the drawing is
  -- bounded by its own outline on every side. A drawing trimmed flush to
  -- its art -- one whose base course is a row of brick rather than the
  -- black threshold every other building stands on -- names the sides it
  -- runs off in `seal`, and the flood does not seed there. Without it the
  -- flood climbs in through the light mortar and hollows the wall out.
  local seal = t.seal or ""
  local function sealed(side) return string.find(seal, side, 1, true) ~= nil end
  for x = 0, W - 1 do
    if not sealed("n") then seed(x, 0) end
    if not sealed("s") then seed(x, H - 1) end
  end
  for y = 0, H - 1 do
    if not sealed("w") then seed(0, y) end
    if not sealed("e") then seed(W - 1, y) end
  end
  while n > 0 do
    local i = queue[n]
    n = n - 1
    local x, y = i % W, math.floor(i / W)
    if x + 1 < W then seed(x + 1, y) end
    if x > 0 then seed(x - 1, y) end
    if y + 1 < H then seed(x, y + 1) end
    if y > 0 then seed(x, y - 1) end
  end

  local inside = {}
  for i = 0, W * H - 1 do inside[i] = not outside[i] end

  -- `scrub` names pixel rects where the drawing paints an object standing
  -- ON the surface (Red's potted plant on the dining tabletop). The object
  -- keeps its own standee -- the template's `keep` leaves its tiles
  -- unclaimed -- so the band beneath it is the one surface the drawing
  -- implies but never paints clear: every rect pixel takes the field
  -- shade, sourced from the first field texel outside the rects, and the
  -- model's top comes out as the plain surface the object sat on.
  if t.scrub then
    local function inRect(x, y)
      for _, r in ipairs(t.scrub) do
        if x >= r[1] and x <= r[3] and y >= r[2] and y <= r[4] then
          return true
        end
      end
      return false
    end
    local donor = nil
    for i = 0, W * H - 1 do
      if col[i] == GREY and inside[i]
         and not inRect(i % W, math.floor(i / W)) then
        donor = i
        break
      end
    end
    for i = 0, W * H - 1 do
      if inRect(i % W, math.floor(i / W)) then
        col[i] = GREY
        ax[i], ay[i] = ax[donor], ay[donor]
        inside[i] = true
      end
    end
  end
  return { W = W, H = H, col = col, ax = ax, ay = ay, inside = inside }
end

-- --------------------------------------------------------------- measure --

local function measure(sp, t)
  local W, H = sp.W, sp.H
  local roofRows = t.roofRows

  -- The drawn taper IS the slope: the first drawn row of a column is how
  -- far the roof has stepped down by the time it reaches that column.
  local top = {}
  for x = 0, W - 1 do
    local r = roofRows
    for y = 0, roofRows - 1 do
      if sp.inside[y * W + x] then r = y break end
    end
    top[x] = r
  end

  -- The drawing's own ground line: the row after the last drawn one. A
  -- building ends on the black threshold row it stands on (ground == H),
  -- but furniture is drawn standing on open floor -- the lab table's
  -- legs stop two rows short of its grid -- and extruding against H
  -- would float it that far above its own plot.
  local ground = roofRows
  for sy = H - 1, roofRows, -1 do
    local drawn = false
    for sx = 0, W - 1 do
      if sp.inside[sy * W + sx] then drawn = true break end
    end
    if drawn then
      ground = sy + 1
      break
    end
  end

  local wallH = ground - roofRows
  local ytop = wallH - 1 + t.slab

  -- Side faces must not come out as slabs of outline black: where the
  -- drawing's own pixel is the outline, walk inward for the first painted
  -- colour, which is what the flanks of the real thing would show.
  local interior = {}
  for sy = roofRows, H - 1 do
    for sx = 0, W - 1 do
      local i = sy * W + sx
      local src = i
      if sp.inside[i] and sp.col[i] == BLACK then
        local step = sx < W / 2 and 1 or -1
        for d = 1, 3 do
          local nx = sx + step * d
          if nx >= 0 and nx < W then
            local ni = sy * W + nx
            if sp.inside[ni] and sp.col[ni] ~= BLACK then
              src = ni
              break
            end
          end
        end
      end
      interior[i] = src
    end
  end

  -- Panes: the facade's non-black pixels split into regions across the
  -- black frames, and a region small enough to be a window or a doorway
  -- sinks a voxel. Frames stay proud, so the pane behind them reads as
  -- glass set into the wall -- and a nested frame (the door's own little
  -- window) layers for free.
  local recess, seen = {}, {}
  for sy = roofRows, H - 1 do
    for sx = 0, W - 1 do
      local i0 = sy * W + sx
      if not seen[i0] and sp.inside[i0] and sp.col[i0] ~= BLACK then
        local cells, stack = {}, { i0 }
        seen[i0] = true
        local x0, x1, y0, y1 = sx, sx, sy, sy
        local function step(nx, ny)
          if nx < 0 or nx >= W or ny < roofRows or ny >= H then return end
          local ni = ny * W + nx
          if not seen[ni] and sp.inside[ni] and sp.col[ni] ~= BLACK then
            seen[ni] = true
            stack[#stack + 1] = ni
          end
        end
        while #stack > 0 do
          local i = table.remove(stack)
          cells[#cells + 1] = i
          local cx, cy = i % W, math.floor(i / W)
          if cx < x0 then x0 = cx end
          if cx > x1 then x1 = cx end
          if cy < y0 then y0 = cy end
          if cy > y1 then y1 = cy end
          step(cx + 1, cy)
          step(cx - 1, cy)
          step(cx, cy + 1)
          step(cx, cy - 1)
        end
        if x1 - x0 < RECESS_MAX and y1 - y0 < RECESS_MAX then
          for _, i in ipairs(cells) do recess[i] = true end
        end
      end
    end
  end

  -- The pane rule reads a LIGHT region the drawing seals behind a BLACK
  -- frame. A drawing built the other way round -- the healing machine's
  -- dark screens sealed behind their own white bezels -- inverts under
  -- it: every lit edge sinks and the black panes stand proud, a black
  -- lattice a voxel off the face. `panes = false` says the drawing does
  -- not carry the rule's polarity, so the facade stays flush.
  if t.panes == false then recess = {} end

  -- One representative texel per shade, taken from the building's own art:
  -- the roof's fascia and its undersides are geometry the drawing implies
  -- but never paints, and they must still wear its palette (and pick up
  -- whatever SGB recolouring the atlas carries).
  local shadeTexel = {}
  for i = 0, sp.W * sp.H - 1 do
    if sp.inside[i] and not shadeTexel[sp.col[i]] then
      shadeTexel[sp.col[i]] = i
    end
  end
  for s = WHITE, BLACK do
    shadeTexel[s] = shadeTexel[s] or shadeTexel[BLACK] or 0
  end

  -- Depth is the MATCHED footprint, not the sprite height. The two are
  -- the same number for every whole-drawing template (the sprite is
  -- built from `tiles` alone), but a template with `topRows` has a
  -- sprite taller than its footprint -- the tower's 16-row drawing
  -- stands on the 8 rows of it that are actually on the map, and D = H
  -- would have pushed its body 64px south into the town plaza.
  -- `depth` (in tile rows) names the plot when the grid runs PAST it
  -- onto ground the drawing merely stands its legs on: the lab table's
  -- third row is the walkable cell the player faces it from, and the
  -- full-grid depth would stand the model in their path.
  -- `depth` names the plot in TILE ROWS, which is the right grain for a
  -- building. `depthPx` names it in voxels, for an object whose real
  -- depth is not a whole tile row -- the Bike Shop toolbox is a box
  -- standing in the middle of its own cell, not a thing that fills a plot.
  return { top = top, ytop = ytop,
           D = t.depthPx or ((t.depth or #t.tiles) * 8),
           ground = ground,
           recess = recess, interior = interior, shadeTexel = shadeTexel }
end

-- ----------------------------------------------------------------- build --

-- A desk with separately-classified objects on it (a template's `parts`
-- list): the methodology's region classification at part granularity.
-- Upright parts anchor their drawn bottom row to the desk's top plane
-- and wear their own drawn tops as lids; flat parts (a keyboard, a
-- sheet of paper) lie one voxel proud at drawn row = depth row -- the
-- same 1:1 the tabletop itself is drawn with, so an object's height ON
-- the drawing is its position ON the desk. The desk is the lab-table
-- slab + base; its lid is the one synthesized surface in the model
-- (the objects cover every drawn pixel of the tabletop), continued
-- from the sibling tables' pattern in the drawing's own shades.
-- tools/building_voxels.py `build_desk_set` is the reference twin.
local function deskSetModel(sp, pr, t)
  local W, H, D = sp.W, sp.H, pr.D
  local ground = pr.ground
  local col, inside = sp.col, sp.inside
  local vox = {}
  local function key(x, y, z) return (y * D + z) * W + x end
  local function put(x, y, z, i) vox[key(x, y, z)] = i end

  -- de-outline walk bounded to the part, so a part's side faces show
  -- its own material and never the neighbour's (the sprite-wide walk
  -- the facade path uses would cross the black seam between units)
  local function interiorAt(sx, sy, lo, hi)
    local i = sy * W + sx
    if col[i] ~= BLACK then return sx end
    local step = sx < math.floor((lo + hi) / 2) and 1 or -1
    for d = 1, 3 do
      local nx = sx + step * d
      if nx >= lo and nx <= hi then
        local ni = sy * W + nx
        if inside[ni] and col[ni] ~= BLACK then return nx end
      end
    end
    return sx
  end

  -- The parts list, shared by every base piece: a desk plane or an
  -- open tray rim alike, `plane` is simply the height they ride.
  local ytop = 0
  local function buildParts(plane)
    for _, p in ipairs(t.parts) do
      Budget.tick()
      local x0, x1 = p.x[1], p.x[2]
      if p.kind == "flat" then
        -- drawn row = depth row by default; `z` renames the origin when
        -- the flat sits below the desk's own drawn top span (the Center
        -- PC's keyboard). `at` names the sheet's own height when it does
        -- not lie on the desk plane (the healing machine's keyboard is a
        -- shelf mounted on the cabinet's side); `thick` gives it a body
        -- -- layers below the sheet repeating each column's own texel,
        -- the same continuation rule every synthesized surface follows.
        local r0 = p.rows[1]
        local z0 = p.z or r0
        local atY = p.at or plane
        local thick = p.thick or 1
        if atY > ytop then ytop = atY end
        for sy = r0, p.rows[2] do
          local z = z0 + (sy - r0)
          if z >= 0 and z < D then
            for sx = x0, x1 do
              if inside[sy * W + sx] then
                for y = math.max(0, atY - thick + 1), atY do
                  put(sx, y, z, sy * W + sx)
                end
              end
            end
          end
        end
      elseif p.kind == "box" then
        -- A BOX part is a drawn rect standing at its own drawn
        -- elevation -- equipment attached to the machine rather than an
        -- object on the desk plane. The rows are face-on art: the top
        -- row's drawn height IS the box's top (ground - 1 - r0,
        -- measured), and the box runs down to `base` (default the drawn
        -- extent; 0 continues it to the floor, the legs-continue rule).
        -- Height beyond the drawn rows fills the way a roof band does:
        -- rows before `cycle` map 1:1 from the top, rows after it 1:1
        -- from the bottom -- the healing machine hoses' foot lands ON
        -- the floor -- and the cycle window repeats between.
        local r0, r1 = p.rows[1], p.rows[2]
        local c0 = p.cycle and p.cycle[1] or r1
        local c1 = p.cycle and p.cycle[2] or r1
        local pz = p.z or 0
        local pd = p.depth
        local top = pr.ground - 1 - r0
        local bot = p.base or (pr.ground - 1 - r1)
        local nTop, nBot = c0 - r0, r1 - c1
        if top > ytop then ytop = top end
        for y = bot, top do
          local k, j = top - y, y - bot
          local sy
          if k < nTop then
            sy = r0 + k
          elseif j < nBot then
            sy = r1 - j
          else
            sy = c0 + (k - nTop) % (c1 - c0 + 1)
          end
          for sx = x0, x1 do
            local i = sy * W + sx
            if inside[i] then
              local ix = interiorAt(sx, sy, x0, x1)
              for z = pz, pz + pd - 1 do
                if z >= 0 and z < D then
                  local px = (z == pz or z == pz + pd - 1) and sx or ix
                  put(sx, y, z, sy * W + px)
                end
              end
            end
          end
        end
      elseif p.kind == "iso" then
        -- An ISO part is drawn in 2:1 isometric -- a box TURNED 45
        -- degrees to the map, so one rhombus carries its top, its front
        -- and its side at once and no band or facade split can reach
        -- them. Un-projecting it is that projection run backwards: the
        -- box stands as a real diamond in plan and every voxel wears the
        -- texel the drawing paints where that voxel projects TO. The
        -- drawn top lands on the top, the screen on the screen-facing
        -- side and the flank on the flank, and nothing is segmented by
        -- hand -- which is the only way to get this right, because the
        -- three faces meet on a diagonal no rectangle can name.
        --
        -- Everything but the depth centre falls out of the drawn rect,
        -- because the projection fixes it: the half-width is the drawn
        -- rhombus's x radius, HALF that again its z radius (2:1 is what
        -- makes it isometric), the near corner's drawn row is the base
        -- rhombus's front tip, and whatever drawn height is left once
        -- that rhombus is accounted for is the box's own height. Bill's
        -- computer: rx 6, rz 3, base centre row 10, and 6 voxels tall --
        -- which puts its left corner's vertical edge at drawn rows
        -- 4..10, exactly where the drawing paints one.
        --
        -- `plan` is the one thing the drawing CANNOT state: 2:1 is the
        -- projection, not the object, so reading rz as the plan radius
        -- too builds a box half as deep as it is wide -- a slab, not the
        -- cube the drawing depicts. `plan` names the real z radius and
        -- the drawn row is scaled into it, so a cube is `plan = rx` and
        -- the drawing still lands on it pixel for pixel.
        local pr0, pr1 = p.rows[1], p.rows[2]
        local rx = math.floor((x1 - x0 + 1) / 2)
        local rz = math.floor(rx / 2)
        local plan = p.plan or rz
        local oy = pr1 - rz
        local h = oy - rz - pr0
        local ytp = plane + h
        if ytp > ytop then ytop = ytp end
        for sx = x0, x1 do
          -- doubled, so a rect of even width keeps its centre between
          -- two columns instead of limping one to the left
          local dx2 = 2 * sx - (x0 + x1)
          for dz = -plan, plan do
            local z = p.z + dz
            local d2 = math.abs(dx2) * plan + 2 * math.abs(dz) * rx
            if z >= 0 and z < D and d2 <= (2 * rx + 1) * plan then
              -- the plan row scaled back into the drawn rhombus
              local dzs = math.floor((2 * dz * rz + plan) / (2 * plan))
              for y = 0, h do
                local sy = oy + dzs - y
                local i = sy * W + sx
                if sy >= pr0 and sy <= pr1 and inside[i] then
                  put(sx, plane + y, z, i)
                end
              end
            end
          end
        end
      else
        local tr0, tr1 = p.top[1], p.top[2]
        local fr0, fr1 = p.facade[1], p.facade[2]
        local pd = p.depth
        -- `rise` lifts a part off the desk's top plane and `z` names its
        -- back-most depth row (the field a flat part already carries). An
        -- object STANDING on a desk needs neither: it starts on the plane
        -- at the plot's back. The healing machine's console needs both --
        -- it stands in the FRONT map row of a grid whose back row is the
        -- wall band it leans against, and its screen head is MOUNTED on
        -- the console's front two voxels above the body's top. Both come
        -- off the drawing, not off taste.
        local base = plane + (p.rise or 0)
        local pz = p.z or 0
        local ytp = base + (fr1 - fr0)
        if ytp > ytop then ytop = ytp end
        -- `inset` sinks an authored pane one voxel: the pane rule
        -- applied by hand, for a part whose screen IS sealed behind its
        -- own black frame while the template's `panes = false` (set for
        -- the polarity-inverted panel elsewhere in the same drawing)
        -- blocks the global pass. Same mechanism as a recess: the front
        -- voxel is simply not placed.
        local ins = p.inset
        for sx = x0, x1 do
          -- the lid: the part's drawn top laid across its depth from the
          -- back, last row continuing forward; the front lid row is the
          -- facade's own top row -- the drawn front-top edge.  `stretch`
          -- maps the drawn band over the whole depth instead, the tray's
          -- rule: for a part authored DEEPER than its drawing (the house
          -- stool grown past its drawn seat), clamping would print the
          -- last row as a long smear off the back band's edge.
          for z = pz, pz + pd - 1 do
            local front = z == pz + pd - 1
            local sy
            if front then
              sy = fr0
            elseif p.stretch then
              sy = math.min(tr0 + math.floor((z - pz) * (tr1 - tr0 + 1)
                                             / (pd - 1)), tr1)
            else
              sy = math.min(tr0 + z - pz, tr1)
            end
            while sy <= tr1 and not inside[sy * W + sx] do sy = sy + 1 end
            local ok = sy <= tr1 or (front and inside[fr0 * W + sx])
            if ok and z >= 0 and z < D then
              put(sx, ytp, z, (front and fr0 or sy) * W + sx)
            end
          end
          -- the body: facade rows anchored to the part's own base
          for sy = fr0 + 1, fr1 do
            local y = base + (fr1 - sy)
            local i = sy * W + sx
            if inside[i] then
              local ix = interiorAt(sx, sy, x0, x1)
              for z = pz, pz + pd - 1 do
                if z >= 0 and z < D then
                  if z == pz + pd - 1 then
                    local sunk = ins and sx >= ins.x[1] and sx <= ins.x[2]
                                 and sy >= ins.rows[1] and sy <= ins.rows[2]
                    if not sunk and not pr.recess[i] then put(sx, y, z, i) end
                  elseif z == pz then
                    put(sx, y, z, i)
                  else
                    put(sx, y, z, sy * W + ix)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- A TRAY is an open container -- the drawing looks down INTO it, so its
  -- top-view band is not a lid but the inside of the box, and the model
  -- has to be hollow. Bands, all measured 1:1 like any other band table:
  -- `top` is the opening (drawn row -> depth row), `front` the near wall
  -- seen face-on (drawn row -> elevation), `x` the box's outer span and
  -- `inner` the opening's, so the difference between them is the wall.
  -- Four walls stand to the rim, the floor slab lies `floor` voxels thick
  -- under the opening, and the cavity between them is left as AIR -- which
  -- is the whole point, and what an extruded facade can never be. Parts (a
  -- standing lid) then ride the rim like any object on a desk's plane.
  if t.tray then
    local tr = t.tray
    local top0 = tr.top[1]
    local fr0, fr1 = tr.front[1], tr.front[2]
    local bx0, bx1 = tr.x[1], tr.x[2]
    local ix0, ix1 = tr.inner[1], tr.inner[2]
    local floor = tr.floor or 0
    local plane = fr1 - fr0 + 1            -- the rim: the wall's height
    -- Which drawn row lies at depth z. The far rim is the band's first
    -- row and the near rim the front wall's own, and the drawn inside
    -- STRETCHES over whatever depth is between them: a box deeper than
    -- its drawing has rows to spare is the ordinary case once the plot
    -- stops being the grid, and the alternative -- running out of rows
    -- and repeating the last one -- would print the wrench twice.
    local lo, hi = top0 + 1, tr.top[2] - 1     -- the drawn inside
    local span = math.max(1, D - 3)            -- interior depth rows - 1
    local function trayRow(z)
      if z == 0 then return top0 end
      if z == D - 1 then return fr0 end
      return lo + math.floor((z - 1) * (hi - lo) / span)
    end
    for sx = bx0, bx1 do
      Budget.tick()
      for z = 0, D - 1 do
        local hollow = sx >= ix0 and sx <= ix1 and z > 0 and z < D - 1
        for y = 0, (hollow and floor or plane - 1) do
          if hollow or y == plane - 1 then
            -- the opening seen from above: the tray's own floor and
            -- whatever lies in it -- and the rim is the same band where
            -- the wall meets it
            local i = trayRow(z) * W + sx
            if inside[i] then put(sx, y, z, i) end
          else
            -- the wall below the rim: the front band folded up it, the
            -- drawn face on the front and back layers and the de-outlined
            -- interior between, exactly as a facade extrudes.
            --
            -- NO recess pass here, and it must stay that way: a pane sinks
            -- by DELETING its front voxel so the one behind becomes the
            -- pane, and a container's wall is one voxel thick -- there is
            -- nothing behind it, so the front panel simply opened a hole
            -- straight into the box and you could see the wrench through it.
            local sy = fr1 - y
            local i = sy * W + sx
            if inside[i] then
              local px = (z == 0 or z == D - 1) and sx
                         or interiorAt(sx, sy, bx0, bx1)
              put(sx, y, z, sy * W + px)
            end
          end
        end
      end
    end
    if plane > ytop then ytop = plane end
    buildParts(plane)
    return { at = function(x, y, z)
               if x < 0 or x >= W or y < 0 or z < 0 or z >= D then
                 return nil
               end
               return vox[key(x, y, z)]
             end,
             W = W, ytop = ytop, zmin = 0, zmax = D - 1 }
  end

  -- No base piece at all: the drawing IS its parts (the house stool -- a
  -- seat and its legs, nothing under them but floor). The plane the parts
  -- anchor to is the ground itself.
  if not t.desk then
    buildParts(0)
    return { at = function(x, y, z)
               if x < 0 or x >= W or y < 0 or z < 0 or z >= D then
                 return nil
               end
               return vox[key(x, y, z)]
             end,
             W = W, ytop = ytop, zmin = 0, zmax = D - 1 }
  end

  -- The desk's top plane. Usually the drawing states it: the fascia and
  -- base rows it paints below the objects ARE the front face, and their
  -- row count is the height. Bill's desk paints neither inside its grid
  -- -- its apron is drawn into the WALKABLE cell in front, and that cell
  -- is left out on purpose so the chair standing there keeps its own
  -- tiles -- so `plane` names the height directly and the body below the
  -- lid is synthesized: the band table's own rim treatment, a shaded box
  -- closed by the outline where it meets the floor, in the drawing's
  -- shades via shadeTexel.
  local f0, f1 = t.desk.fascia[1], t.desk.fascia[2]
  local b0, b1 = t.desk.base[1], t.desk.base[2]
  local plane = (b1 - b0 + 1) + (f1 - f0 + 1)

  -- The desk's own PLOT, when the grid holds more than the desk. Bill's
  -- grid runs on into the walkable cell, because the drawing puts the
  -- desk's apron AND the chair pushed up to it in the same tiles -- so
  -- the desk box has to stop at its own cell (`depth`) and stand on its
  -- own ground line rather than the grid's, which the chair's feet set
  -- eight rows lower. The base band's last row IS that ground line by
  -- definition, and for every desk drawn inside its own grid it is the
  -- measured one to the row (lab table, lab computers, Center PC, the
  -- Bike Shop toolbox), so this changes nothing for them.
  -- ...and in voxels (`depthPx`) plus a back origin (`z`) when the desk
  -- is shallower than a tile row and leans against something: the
  -- healing machine's cabinet is 10 deep -- its drawn top band's 9 rows
  -- plus the front edge -- standing against the wall band, so its box
  -- runs z 16..25 of a 32-deep plot.
  local deskD = t.desk.depthPx or (t.desk.depth and t.desk.depth * 8) or D
  local dz0 = t.desk.z or 0
  local dz1 = dz0 + deskD - 1
  local deskG = b1 + 1
  -- ...and the desk's COLUMNS (`x`), when the grid is wider than the
  -- desk: the healing machine's grid carries its flanking hoses and
  -- keyboard, and the cabinet is only the middle 16 columns.
  local dx0 = t.desk.x and t.desk.x[1] or 0
  local dx1 = t.desk.x and t.desk.x[2] or W - 1

  -- The WALL element: the band the machine backs onto, whose tiles this
  -- grid claims. The drawing shows it only as the stripe background
  -- around the tower (the same standing as the potted plants' floor),
  -- so the block cycles the drawing's own stripe unit -- real pixels of
  -- column `x`, rows `cycle` -- at wall-band height over the back plot,
  -- exactly what the neighbouring cells' `wall` pins render.
  if t.wall then
    local wl = t.wall
    local c0, c1 = wl.cycle[1], wl.cycle[2]
    local cn = c1 - c0 + 1
    local wx = wl.x or 0
    for y = 0, wl.h - 1 do
      Budget.tick()
      local sy = c0 + (wl.h - 1 - y) % cn
      for sx = 0, W - 1 do
        for z = 0, wl.depthPx - 1 do
          put(sx, y, z, sy * W + wx)
        end
      end
    end
  end

  -- the base band, extruded exactly like every lab table's
  for sy = b0, b1 do
    Budget.tick()
    local y = deskG - 1 - sy
    for sx = dx0, dx1 do
      if inside[sy * W + sx] then
        local ix = interiorAt(sx, sy, dx0, dx1)
        for z = dz0, dz1 do
          local px = (z == dz0 or z == dz1) and sx or ix
          put(sx, y, z, sy * W + px)
        end
      end
    end
  end
  for i in pairs(pr.recess) do
    local sy = math.floor(i / W)
    local sx = i % W
    if sy >= b0 and sy <= b1 and sx >= dx0 and sx <= dx1 then
      vox[key(sx, deskG - 1 - sy, dz1)] = nil
    end
  end

  -- the slab: fascia rows wrap every side
  for sy = f0, f1 do
    Budget.tick()
    local y = plane - 1 - (sy - f0)
    for sx = dx0, dx1 do
      for z = dz0, dz1 do put(sx, y, z, sy * W + sx) end
    end
  end

  if t.desk.top then
    -- The lid wears the desk's own drawn top band -- the drawing DOES
    -- paint this tabletop (the healing machine's white top face with
    -- its lit west and shaded east strips), so nothing is synthesized
    -- where it is visible: band rows map back-to-front, the first
    -- fascia row is the drawn front-top edge, same rule as an upright
    -- part's lid. Where a part's drawing occludes the band (the monitor
    -- standing on it), the lid continues the nearest strip BESIDE the
    -- part -- still the drawing's own pixels, the same sibling-pattern
    -- rule every synthesized lid follows.
    local tr0, tr1 = t.desk.top[1], t.desk.top[2]
    for z = dz0, dz1 do
      Budget.tick()
      local sy = z == dz1 and f0 or math.min(tr0 + (z - dz0), tr1)
      for sx = dx0, dx1 do
        local px = sx
        for _, p in ipairs(t.parts) do
          local px0, px1 = p.x[1], p.x[2]
          local r0, r1
          if p.kind == "flat" or p.kind == "iso" or p.kind == "box" then
            r0, r1 = p.rows[1], p.rows[2]
          else
            r0, r1 = p.top[1], p.facade[2]
          end
          if sx >= px0 and sx <= px1 and sy >= r0 and sy <= r1 then
            px = (sx - px0 < px1 - sx) and (px0 - 1) or (px1 + 1)
            px = math.max(dx0, math.min(dx1, px))
            break
          end
        end
        put(sx, plane - 1, z, sy * W + px)
      end
    end
  else
    -- the lid continues the sibling tables' top -- black rim, white
    -- highlight courses along the north and west, grey field
    local field = t.desk.lid == "white" and WHITE or GREY
    for sx = dx0, dx1 do
      for z = dz0, dz1 do
        local shade = field
        if sx == dx0 or sx == dx1 or z == dz0 or z == dz1 then
          shade = BLACK
        elseif sx == dx0 + 1 or z == dz0 + 1 then
          shade = WHITE
        end
        put(sx, plane - 1, z, pr.shadeTexel[shade])
      end
    end
  end

  if plane > ytop then ytop = plane end
  buildParts(plane)

  return { at = function(x, y, z)
             if x < 0 or x >= W or y < 0 or z < 0 or z >= D then return nil end
             return vox[key(x, y, z)]
           end,
           W = W, ytop = ytop, zmin = 0, zmax = D - 1 }
end

-- The voxel model as a lookup: `at(x, y, z)` is the index of the sprite
-- pixel that voxel wears, or nil. Build ORDER is expressed as lookup
-- order -- roof first, so it overwrites the walls it intersects, and walls
-- are trimmed to its underside so nothing pokes through the surface.
local function model(sp, pr, t)
  if t.parts then return deskSetModel(sp, pr, t) end
  local W, H, D = sp.W, sp.H, pr.D
  local slab, roofRows = t.slab, t.roofRows
  local top, ytop, ground = pr.top, pr.ytop, pr.ground

  -- The roof's drawn span. A sprite inset from its box (B03) leaves outer
  -- columns undrawn in the roof band; they carry no roof at all, and the
  -- rim treatment belongs to the outermost drawn columns instead of the
  -- box edge.
  local x0d, x1d
  for x = 0, W - 1 do
    if top[x] < roofRows then
      x0d = x0d or x
      x1d = x
    end
  end
  local ledge0, ledge1 = nil, nil
  if t.ledge then ledge0, ledge1 = t.ledge[1], t.ledge[2] end

  local rz0, rz1 = 0, D - 1 + (t.frontEave or 0)
  local back, front = t.roofBack, t.roofFront
  local cyc0, cyc1 = t.roofCycle[1], t.roofCycle[2]
  local cycN = cyc1 - cyc0 + 1

  -- Which drawn row lies at depth z. The drawing looks at the roof from
  -- the north, so its top rows ARE the far edge and its bottom rows the
  -- eave over the facade. The band is shallower than the building, so the
  -- rims map one row per voxel and the middle cycles a run whose period is
  -- the course rhythm -- picked up where the north rim left off, which
  -- continues both the course lines and the roof texture seamlessly.
  local roofSy = {}
  for z = rz0, rz1 do
    local df, db = z - rz0, rz1 - z          -- from the north / south edge
    if df < back then
      roofSy[z] = df
    elseif db < front then
      roofSy[z] = roofRows - 1 - db
    else
      roofSy[z] = cyc0 + (df - cyc0) % cycN
    end
  end

  local T = {}
  for x = 0, W - 1 do T[x] = ytop - top[x] end

  local function at(x, y, z)
    if x < 0 or x >= W then return nil end
    local tx = T[x]

    -- roof: a solid of constant thickness following the elevation profile
    if top[x] < roofRows
        and y > tx - slab and y <= tx and z >= rz0 and z <= rz1 then
      if y == tx and x > x0d and x < x1d and z > rz0 and z < rz1 then
        -- the surface itself. Clamping the row into the column's first
        -- drawn row keeps the flank battens running down the slope
        -- instead of falling off the silhouette.
        local sy = roofSy[z]
        if sy < top[x] then sy = top[x] end
        return sy * W + x
      end
      -- The rim reproduces the eave the drawing itself paints under the
      -- roof: a black outline, a shaded fascia, closed by the outline
      -- again. (A GREY fascia band -- what the first cut had -- comes out
      -- WHITE once the atlas is recoloured and turns every sloped end
      -- into a black-and-white zip.) Under the surface it is all shadow.
      local outer = x == x0d or x == x1d or z == rz0 or z == rz1
      if not outer then return pr.shadeTexel[DARK] end
      if y == tx or y == tx - slab + 1 then return pr.shadeTexel[BLACK] end
      return pr.shadeTexel[DARK]
    end

    -- trimmed: under the slope. A column with no roof over it has no
    -- underside to trim to, and must not be cut away by a profile the
    -- drawing never set.
    if top[x] < roofRows and y > tx - slab then return nil end

    -- the awning: the band juts two voxels past the walls, front and back
    if ledge0 and (z == -2 or z == -1 or z == D or z == D + 1) then
      local sy = ground - 1 - y
      if sy >= ledge0 and sy <= ledge1 and sp.inside[sy * W + x] then
        return sy * W + x
      end
      return nil
    end

    -- the facade, extruded straight back over the footprint. Rows map
    -- against the measured ground line, not the grid's last row: the two
    -- differ only for furniture standing on open floor (see measure).
    if z < 0 or z >= D then return nil end
    local sy = ground - 1 - y
    local i = sy * W + x
    if y == 0 and not sp.inside[i] and sy > 0 and sp.inside[i - W] then
      -- the drawing's last row is the ground the building stands on, so
      -- its base course is one row up; without this the walls float a
      -- voxel over their own plot
      sy, i = sy - 1, i - W
    end
    if not sp.inside[i] then return nil end
    if z == D - 1 then
      if pr.recess[i] then return nil end
      return i
    end
    if z == 0 then return i end
    return pr.interior[i]
  end

  return { at = at, W = W, ytop = ytop,
           zmin = ledge0 and -2 or 0,
           zmax = math.max(rz1, ledge0 and (D + 1) or 0) }
end

-- ------------------------------------------------------------------ emit --

-- Cull to the shell and merge. A run of faces collapses into one quad when
-- its texels are the SAME (a flat-coloured strip, which is most of a side
-- face) or ADJACENT IN THE ATLAS along the run (the drawing continuing
-- across the face, which is most of a front face or a roof top). Both keep
-- every texel exactly where the sprite put it.
local function emit(m, sp, atlasW, atlasH)
  local W = m.W
  local quads = { voxels = 0, shell = 0 }
  local cell = {}                        -- (y, z, x) -> sprite pixel index

  local zmin, zmax, ytop = m.zmin, m.zmax, m.ytop
  local zn = zmax - zmin + 1
  local function ci(x, y, z)
    if x < 0 or x >= W or y < 0 or y > ytop or z < zmin or z > zmax then
      return nil
    end
    return cell[(y * zn + (z - zmin)) * W + x]
  end
  for y = 0, ytop do
    Budget.tick()
    for z = zmin, zmax do
      local base = (y * zn + (z - zmin)) * W
      for x = 0, W - 1 do
        local v = m.at(x, y, z)
        cell[base + x] = v
        if v then quads.voxels = quads.voxels + 1 end
      end
    end
  end
  -- the shell: what survives hidden-face culling. Counted here rather than
  -- derived from the quads because it is the number
  -- tools/building_voxels.py checks this build against.
  for y = 0, ytop do
    Budget.tick()
    for z = zmin, zmax do
      for x = 0, W - 1 do
        if ci(x, y, z) and not (ci(x + 1, y, z) and ci(x - 1, y, z)
            and ci(x, y + 1, z) and ci(x, y - 1, z)
            and ci(x, y, z + 1) and ci(x, y, z - 1)) then
          quads.shell = quads.shell + 1
        end
      end
    end
  end

  -- u/v of a run: `n` texels starting at sprite pixel `i`, stepping along
  -- the atlas when the run is a strip and standing still when it is flat.
  local function uvOf(i, strip, n)
    local x0 = sp.ax[i]
    local y0 = sp.ay[i]
    local x1 = strip and (x0 + n) or (x0 + 1)
    return (x0 + 0.05) / atlasW, (x1 - 0.05) / atlasW,
           (y0 + 0.05) / atlasH, (y0 + 1 - 0.05) / atlasH
  end

  local function put(c1, c2, c3, c4, uv, shade)
    quads[#quads + 1] = { c1, c2, c3, c4, uv = uv, shade = shade }
  end

  -- How far a run of exposed faces reaches from `x`, and whether it is a
  -- strip (texels marching along the atlas) or flat (one texel repeated).
  local function runX(y, z, dx, dy, dz, x)
    local i0 = ci(x, y, z)
    local strip, n = nil, 1
    local cap = runCap(x)
    while n < cap do
      local nx = x + n
      local i = ci(nx, y, z)
      if not i or ci(nx + dx, y + dy, z + dz) then break end
      local prev = ci(nx - 1, y, z)
      if sp.ay[i] ~= sp.ay[prev] then break end
      local d = sp.ax[i] - sp.ax[prev]
      if d == 1 then
        if strip == false then break end
        strip = true
      elseif d == 0 then
        if strip == true then break end
        strip = false
      else
        break
      end
      n = n + 1
    end
    return i0, strip == true, n
  end

  -- ---- faces along +-Z (the facade, the roof's rims): merge along x ----
  for _, d in ipairs({ 1, -1 }) do
    local shade = d == 1 and SHADE.south or SHADE.north
    for y = 0, ytop do
      Budget.tick()
      for z = zmin, zmax do
        local x = 0
        while x < W do
          if ci(x, y, z) and not ci(x, y, z + d) then
            local i, strip, n = runX(y, z, 0, 0, d, x)
            local u0, u1, v0, v1 = uvOf(i, strip, n)
            local zf = d == 1 and (z + 1) or z
            if d == 1 then
              put({ x, y, zf }, { x + n, y, zf },
                  { x + n, y + 1, zf }, { x, y + 1, zf },
                  { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, shade)
            else
              put({ x + n, y, zf }, { x, y, zf },
                  { x, y + 1, zf }, { x + n, y + 1, zf },
                  { { u1, v1 }, { u0, v1 }, { u0, v0 }, { u1, v0 } }, shade)
            end
            x = x + n
          else
            x = x + 1
          end
        end
      end
    end
  end

  -- ---- faces along +-Y (roof surfaces, undersides): merge along x ----
  for _, d in ipairs({ 1, -1 }) do
    local shade = d == 1 and SHADE.top or SHADE.bottom
    for y = 0, ytop do
      Budget.tick()
      -- the underside of the bottom layer is the ground it stands on
      if not (d == -1 and y == 0) then
        for z = zmin, zmax do
          local x = 0
          while x < W do
            if ci(x, y, z) and not ci(x, y + d, z) then
              local i, strip, n = runX(y, z, 0, d, 0, x)
              local u0, u1, v0, v1 = uvOf(i, strip, n)
              local yf = d == 1 and (y + 1) or y
              if d == 1 then
                put({ x, yf, z }, { x + n, yf, z },
                    { x + n, yf, z + 1 }, { x, yf, z + 1 },
                    { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, shade)
              else
                put({ x, yf, z + 1 }, { x + n, yf, z + 1 },
                    { x + n, yf, z }, { x, yf, z },
                    { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, shade)
              end
              x = x + n
            else
              x = x + 1
            end
          end
        end
      end
    end
  end

  -- ---- faces along +-X (the flanks): merge along z, one texel each ----
  for _, d in ipairs({ 1, -1 }) do
    for y = 0, ytop do
      for x = 0, W - 1 do
        local z = zmin
        while z <= zmax do
          local i = ci(x, y, z)
          if i and not ci(x + d, y, z) then
            local n, cap = 1, runCap(z)
            while n < cap and z + n <= zmax do
              local j = ci(x, y, z + n)
              if j ~= i or ci(x + d, y, z + n) then break end
              n = n + 1
            end
            local u0, u1, v0, v1 = uvOf(i, false, n)
            local xf = d == 1 and (x + 1) or x
            if d == 1 then
              put({ xf, y, z + n }, { xf, y, z },
                  { xf, y + 1, z }, { xf, y + 1, z + n },
                  { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                  SHADE.side)
            else
              put({ xf, y, z }, { xf, y, z + n },
                  { xf, y + 1, z + n }, { xf, y + 1, z },
                  { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                  SHADE.side)
            end
            z = z + n
          else
            z = z + 1
          end
        end
      end
    end
  end

  return quads
end

-- ------------------------------------------------------------- placement --

-- Does the template's tile grid sit at (tx, ty)?
local function matches(S, t, tx, ty)
  local tiles = t.tiles
  for r = 1, #tiles do
    local row = tiles[r]
    for c = 1, #row do
      if S.tileAt[keyOf(tx + c - 1, ty + r - 1)] ~= row[c] then
        return false
      end
    end
  end
  return true
end

-- Find every placement of every template for this map's tileset, build one
-- model per template, and stamp it. Returns nothing; the quads land in
-- S.objectQuads and the tiles are claimed so the volume path never boxes a
-- building this module has already modelled.
function Buildings.build(S, map, data, perRow)
  if not data then return end
  local tileset = map.tileset
  local s = profile()
  local list = s and s.buildings and s.buildings[tileset.id]
  if not list then return end

  local atlasW = tileset.imageWidth or 128
  local atlasH = tileset.imageHeight or 48
  local tw, th = map.def.width * 4, map.def.height * 4
  local quads = S.objectQuads

  for index, t in ipairs(list) do
    if type(t.tiles) == "table" and #t.tiles > 0 then
      local bh, bw = #t.tiles, #t.tiles[1]
      local first = t.tiles[1][1]
      local built = nil
      for ty = 0, th - bh do
        Budget.tick()
        for tx = 0, tw - bw do
          -- A placement never stamps into cells another template already
          -- claimed. Templates are matched independently, and one
          -- drawing can satisfy two grids: the Pokemon Tower's upper
          -- twelve rows on ROUTE_10 are a standard 6-cell block tile for
          -- tile, so `gabled_block_6x6` matched there and stood a whole
          -- second building behind the tower. First claim wins, so the
          -- list order below is the priority order -- the tower's own
          -- templates come first precisely so they take those cells.
          local free = S.tileAt[keyOf(tx, ty)] == first
          if free then
            for r = 0, bh - 1 do
              for c = 0, bw - 1 do
                if S.skip[keyOf(tx + c, ty + r)] then
                  free = false
                  break
                end
              end
              if not free then break end
            end
          end
          if free and matches(S, t, tx, ty) then
            if not built then
              local key = tileset.id .. ":" .. index
              if not models[key] then
                if t.claimOnly then
                  -- claim the cells, stamp nothing: the drawing here is
                  -- the off-map half of a building another map models in
                  -- full (the tower's roof rows on ROUTE_10 -- Lavender's
                  -- placement composites them via topRows). Left to the
                  -- detector they stood as a second half-building.
                  models[key] = {}
                else
                  local sp = read(t, data, perRow)
                  local pr = measure(sp, t)
                  models[key] = emit(model(sp, pr, t), sp, atlasW, atlasH)
                end
              end
              built = models[key]
            end
            Buildings.stamp(S, map, built, tx, ty, bw, bh, t)
          end
        end
      end
    end
  end
end

-- One placement: claim its tiles (so the detector leaves them alone and
-- the mesher paints ground under them) and copy the model into place.
--
-- Two template fields alter what a claim means, for a drawing that
-- carries a STANDEE on its surface (Red's potted plant on the dining
-- table). `keep` names tile ids the stamp must NOT claim: their authored
-- pins stay live, so the standee scan still stands the object exactly as
-- it always did. `support` is the model's top plane in voxels: the claim
-- shape carries it as its height, which is what tells that scan the
-- standee's shelf -- a plain claim stays at h = 0, and Structures treats
-- a building claim with height as a full model (skip, never a second
-- box; see its support branches).
function Buildings.stamp(S, map, quads, tx, ty, bw, bh, t)
  local shape = { class = "building", h = (t and t.support) or 0,
                  art = "building", flat = false, authored = true }
  local keep = nil
  if t and t.keep then
    keep = {}
    for _, id in ipairs(t.keep) do keep[id] = true end
  end

  -- the ground the building stands on: the commonest flat tile around its
  -- feet, so a house on a path keeps its path
  local votes, best, bestN = {}, nil, 0
  local function vote(x, y)
    local k = keyOf(x, y)
    local ns = S.shapeAt[k]
    if ns and ns.flat and ns.class ~= "void" then
      local tile = S.tileAt[k]
      votes[tile] = (votes[tile] or 0) + 1
      if votes[tile] > bestN then best, bestN = tile, votes[tile] end
    end
  end
  for c = 0, bw - 1 do
    vote(tx + c, ty - 1)
    vote(tx + c, ty + bh)
  end
  for r = 0, bh - 1 do
    vote(tx - 1, ty + r)
    vote(tx + bw, ty + r)
  end

  for r = 0, bh - 1 do
    for c = 0, bw - 1 do
      local k = keyOf(tx + c, ty + r)
      if keep and keep[S.tileAt[k]] then
        -- unclaimed by request: the tile keeps its pin (the plant's
        -- cutout pool) and the standee scan finds it there. Only the
        -- ground is set now, so the scan's own claim of these tiles has
        -- the building's floor to paint when no flat tile touches a
        -- cluster ringed by its own furniture.
        S.ground[k] = best or false
      else
        S.shapeAt[k] = shape
        S.skip[k] = true
        S.ground[k] = best or false
      end
    end
  end

  local mx, mz = tx * 8, ty * 8
  local out = S.objectQuads
  for _, q in ipairs(quads) do
    out[#out + 1] = {
      { q[1][1] + mx, q[1][2], q[1][3] + mz },
      { q[2][1] + mx, q[2][2], q[2][3] + mz },
      { q[3][1] + mx, q[3][2], q[3][3] + mz },
      { q[4][1] + mx, q[4][2], q[4][3] + mz },
      uv = q.uv, shade = q.shade,
      -- placements only ever scan the BODY, so a building is always this
      -- map's own structure: the mesher's edge keep-rules must not eat
      -- the parts that poke past the boundary (an edge-row house's eave
      -- juts frontEave voxels into the neighbour's airspace, and the
      -- neighbour-body mask read that overhang as a ring scrap -- which
      -- opened the roof rim into the sky from across the seam)
      own = true,
    }
  end
end

-- What the models built so far cost, keyed "<tileset>:<index>": the voxel
-- and shell counts tools/building_voxels.py checks this implementation
-- against (Stage 5 of the methodology), and the quad count that ships.
function Buildings.stats()
  local out = {}
  for key, quads in pairs(models) do
    out[key] = { voxels = quads.voxels, shell = quads.shell,
                 quads = #quads }
  end
  return out
end

-- Drop the prebuilt models (hot reload, or a mod shadowing the profile).
function Buildings.invalidate()
  spec = nil
  models = {}
end

return Buildings
