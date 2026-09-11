-- Turning a tile into geometry, the way the game does.
--
-- ONE MODULE, AND IT IS THE ONLY PLACE IN THIS EDITOR THAT KNOWS HOW A
-- SHAPE BECOMES A BOX.  It takes no love.* call and no editor state: a
-- shape record in, a list of quads out.  That is deliberate -- a LOVE
-- companion inside the game can require this file unchanged, and the day
-- one does, there is still only one answer to "how tall is that face".
--
-- IT MIRRORS lib/ChunkMesher.lua, ARITHMETIC FOR ARITHMETIC.  Every
-- constant below was read off that file rather than chosen: the 0.02 UV
-- inset (a sliver, not half a texel -- half a texel squeezes 8 texels of
-- art into a 7-texel sample range and the drawing drifts off the pixel
-- grid), the band crop that maps the TOP of a band to art row 0, the
-- per-pixel depths, the 2px grass slab at the middle of its own tile.
-- Where this file cannot reach what the game reaches -- a volume's height
-- is measured across a whole connected region, and one tile has no region
-- -- it says so through `notes` instead of inventing a number.
--
-- UNITS.  One world pixel = one atlas texel = one unit.  A tile is 8x8, a
-- cell 16x16.  +Y is up, +Z is south (the map's own +y), +X is east.  Tile
-- (tx,ty) spans x [tx*8, tx*8+8], z [ty*8, ty*8+8].

local Mesh = {}

-- A sliver of a texel, to keep a quad's sampling inside its own tile.
Mesh.INSET = 0.02

-- The face brightness table lives in the mod's lib/Voxel3D.lua, which this
-- editor does not load (it is a renderer, not a rule).  These are its
-- shape, not its authority: the preview is lit approximately and the
-- geometry exactly, which is the right way round.
Mesh.FACE_SHADE = { [1] = 0.82, [2] = 0.78, [5] = 1.00, [6] = 0.68 }
Mesh.VOLUME_TOP_SHADE = 0.85
Mesh.ROOF_SHADE = 0.95
Mesh.OBJ_SHADE = { front = 1.0, back = 0.68, side = 0.78, top = 1.0, bottom = 0.55 }

-- east, west, south, north -- the numbers are the mesher's own face ids
Mesh.SIDES = {
  { 1, 0, 1 },
  { -1, 0, 2 },
  { 0, 1, 5 },
  { 0, -1, 6 },
}

Mesh.PINNED_DEPTH = {
  billboard = 10, prop = 5, stool = 10, cutout = 1, column = 6,
  console = 10, post = 6, signpost = 2, bike = 2,
}
Mesh.OBJECT_DEPTH = 6
Mesh.GRASS_THICK = 2
Mesh.FLOWER_THICK = 1
Mesh.SIDE_INSET = 0.03
Mesh.STAIR_STEPS = 4

-- ---------------------------------------------------------------- helpers

local function newSink()
  local q = {}
  -- `pick` is what makes the viewport clickable: a quad remembers what it is
  -- a picture of -- the tile's top face, one side band, or one sub-column of
  -- a sculpt -- so a click can be answered without a second search through
  -- geometry that has already forgotten where it came from.
  return q, function(corners, uvs, shade, pick)
    q[#q + 1] = { corners[1], corners[2], corners[3], corners[4],
                  uv = uvs, shade = shade or 1, pick = pick }
  end
end

-- ctx carries the atlas geometry and the pixel reader:
--   ctx.perRow, ctx.atlasW, ctx.atlasH
--   ctx.pixel(tile, px, py) -> r, g, b, a   (0..1, px/py 0..7)
local function origin(ctx, tile)
  return (tile % ctx.perRow) * 8, math.floor(tile / ctx.perRow) * 8
end

-- One atlas-rect UV, optionally cropped to art rows [vTop, vBot] of 8.
local function uvRect(ctx, tile, vTop, vBot)
  vTop, vBot = vTop or 0, vBot or 8
  local ax, ay = origin(ctx, tile)
  local INSET = Mesh.INSET
  local vi = math.min(INSET, (vBot - vTop) / 4)
  return (ax + INSET) / ctx.atlasW, (ax + 8 - INSET) / ctx.atlasW,
         (ay + vTop + vi) / ctx.atlasH, (ay + vBot - vi) / ctx.atlasH
end

local function topQuad(push, ctx, x0, z0, h, tile, shade)
  local u0, u1, v0, v1 = uvRect(ctx, tile)
  push({ { x0, h, z0 }, { x0 + 8, h, z0 }, { x0 + 8, h, z0 + 8 }, { x0, h, z0 + 8 } },
       { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, shade or 1,
       { kind = "top" })
end

-- Corner order is bottom-left, bottom-right, top-right, top-left as seen
-- from OUTSIDE the box; getting it wrong is a face that vanishes under
-- backface culling in the game and looks fine here.
local function sideQuad(push, ctx, d, x0, z0, y0, y1, tile, vTop, vBot, shade)
  local x1, z1 = x0 + 8, z0 + 8
  local c
  if d == 1 then
    c = { { x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 } }
  elseif d == 2 then
    c = { { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 } }
  elseif d == 5 then
    c = { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 } }
  else
    c = { { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 } }
  end
  local u0, u1, v0, v1 = uvRect(ctx, tile, vTop, vBot)
  push(c, { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, shade or 1,
       { kind = "side", d = d })
end

-- A 1x1x1 world-pixel box wearing ONE texel, for the per-pixel folds.  The
-- texel centre is the anti-drift measure here, not an inset rect: a quad
-- one pixel across sampling a rect would land on its neighbour's texel at
-- the seam.
-- A HORIZONTAL RUN OF PIXELS, AS ONE BOX.
--
-- The per-pixel folds -- billboard, cutout, post, every tree and prop in
-- Hoenn -- emitted a six-face box per lit pixel, of which the front and back
-- are always drawn.  That is a floor of two quads per pixel, and a route of
-- trees is half a million of them.
--
-- Adjacent pixels of the SAME COLOUR are indistinguishable once drawn, so a
-- run of them is one box wearing that colour, pixel for pixel identical to
-- the boxes it replaces.  GB and GBA art is mostly flat colour runs, which is
-- why this is worth doing: the picture does not change and the quad count
-- falls by roughly the average run length.
--
-- The caps are the only subtlety.  A run's west face belongs to its left end
-- and its east face to its right end -- and only when the neighbour there is
-- unlit, because a run that ends on a COLOUR change still has solid pixels
-- beside it and a face drawn there would be an interior wall.
local function pixelRun(push, ctx, x0, x1, y, z0, z1, ax, ay, faces)
  local u = (ax + 0.5) / ctx.atlasW
  local v = (ay + 0.5) / ctx.atlasH
  local uv = { { u, v }, { u, v }, { u, v }, { u, v } }
  local S = Mesh.OBJ_SHADE
  local xa, xb, y1 = x0, x1 + 1, y + 1
  push({ { xa, y, z1 }, { xb, y, z1 }, { xb, y1, z1 }, { xa, y1, z1 } }, uv, S.front)
  push({ { xb, y, z0 }, { xa, y, z0 }, { xa, y1, z0 }, { xb, y1, z0 } }, uv, S.back)
  if faces.west then
    push({ { xa, y, z0 }, { xa, y, z1 }, { xa, y1, z1 }, { xa, y1, z0 } }, uv, S.side)
  end
  if faces.east then
    push({ { xb, y, z1 }, { xb, y, z0 }, { xb, y1, z0 }, { xb, y1, z1 } }, uv, S.side)
  end
end

-- The top and bottom caps are run-merged too, but over a DIFFERENT run: a
-- cap is present where the pixel above (or below) is unlit, which changes
-- along the row independently of colour.  So they are walked separately and
-- may span several colour runs -- they carry one texel's colour across, and
-- a horizontal sliver seen edge-on is not where anyone reads colour.
local function pixelCap(push, ctx, x0, x1, y, z0, z1, ax, ay, top)
  local u = (ax + 0.5) / ctx.atlasW
  local v = (ay + 0.5) / ctx.atlasH
  local uv = { { u, v }, { u, v }, { u, v }, { u, v } }
  local S = Mesh.OBJ_SHADE
  local xa, xb = x0, x1 + 1
  if top then
    local y1 = y + 1
    push({ { xa, y1, z0 }, { xb, y1, z0 }, { xb, y1, z1 }, { xa, y1, z1 } }, uv, S.top)
  else
    push({ { xa, y, z1 }, { xb, y, z1 }, { xb, y, z0 }, { xa, y, z0 } }, uv, S.bottom)
  end
end

-- ------------------------------------------------------- pixel classification

function Mesh.shadeClass(v)
  if v <= 0.25 then return "black" end
  if v <= 0.55 then return "dark" end
  if v <= 0.85 then return "light" end
  return "white"
end

-- Which pixels of a tile are the DRAWING and which are the air around it.
--
-- Three rules, and which one applies is the difference between a potted
-- plant and a smear.  Alpha zero is always air.  For a pinned per-pixel
-- fold the background shades are voted from the drawing's own bounding-box
-- rim (or stated outright, which is what `prop_bg` is for) and then flooded
-- from the aprons, so an enclosed white pixel INSIDE the drawing stays
-- drawing.  BLACK IS NEVER BACKGROUND: it is the outline, and an outline
-- that floods away takes the silhouette with it.
function Mesh.silhouette(ctx, tiles, w, h, opts)
  opts = opts or {}
  local bw, bh = w * 8, h * 8
  local state, src = {}, {}
  local rimVotes = { black = 0, dark = 0, light = 0, white = 0 }

  for ty = 0, h - 1 do
    for tx = 0, w - 1 do
      local tile = tiles[ty * w + tx + 1] or 0
      local ax0, ay0 = origin(ctx, tile)
      for py = 0, 7 do
        for px = 0, 7 do
          local lx, ly = tx * 8 + px, ty * 8 + py
          local i = ly * bw + lx
          src[i] = { ax0 + px, ay0 + py }
          local r, g, b, a = ctx.pixel(tile, px, py)
          if not r then
            state[i] = "cand"
          elseif a == 0 then
            state[i] = "cand"
          else
            state[i] = Mesh.shadeClass(math.min(r, g, b))
            if lx == 0 or ly == 0 or lx == bw - 1 or ly == bh - 1 then
              rimVotes[state[i]] = (rimVotes[state[i]] or 0) + 1
            end
          end
        end
      end
    end
  end

  local bg = {}
  if opts.bg then
    for _, name in ipairs(opts.bg) do bg[name] = true end
  else
    local best, bestN = nil, 0
    for _, name in ipairs({ "white", "light", "dark" }) do
      if (rimVotes[name] or 0) > bestN then best, bestN = name, rimVotes[name] end
    end
    if best then bg[best] = true end
  end

  for i, st in pairs(state) do
    if opts.strict then
      if st == "dark" or st == "light" then state[i] = "cand"
      elseif st == "white" then state[i] = "cand"
      elseif st == "black" then state[i] = "solid" end
    elseif st == "dark" or st == "light" or st == "white" then
      state[i] = bg[st] and "cand" or "solid"
    elseif st == "black" then
      state[i] = "solid"
    end
  end

  -- flood the air in from every edge; a `cand` the flood cannot reach is
  -- enclosed, and enclosed air inside a drawing is part of the drawing
  local queue, seen = {}, {}
  local function push(lx, ly)
    if lx < 0 or ly < 0 or lx >= bw or ly >= bh then return end
    local i = ly * bw + lx
    if seen[i] or state[i] ~= "cand" then return end
    seen[i] = true
    queue[#queue + 1] = { lx, ly }
  end
  for lx = 0, bw - 1 do push(lx, 0) push(lx, bh - 1) end
  for ly = 0, bh - 1 do push(0, ly) push(bw - 1, ly) end
  local qi = 1
  while qi <= #queue do
    local p = queue[qi]; qi = qi + 1
    push(p[1] + 1, p[2]) push(p[1] - 1, p[2])
    push(p[1], p[2] + 1) push(p[1], p[2] - 1)
  end

  -- A pixel is the drawing unless it is a candidate the flood REACHED.
  -- Enclosed air -- the gap inside a bicycle frame, the hole in a doughnut
  -- of a plant -- is unreachable, and unreachable air is part of the
  -- drawing's own silhouette.
  local solid = {}
  for ly = 0, bh - 1 do
    for lx = 0, bw - 1 do
      local i = ly * bw + lx
      solid[i] = not (state[i] == "cand" and seen[i])
    end
  end
  return { w = bw, h = bh, solid = solid, src = src, bg = bg, rim = rimVotes }
end

-- ------------------------------------------------------------- the folds

local function foldFlat(push, ctx, o)
  topQuad(push, ctx, o.x0, o.z0, o.h, o.tile,
          o.art == "upright" and Mesh.VOLUME_TOP_SHADE or 1)
end

local function foldTop(push, ctx, o)
  topQuad(push, ctx, o.x0, o.z0, o.h, o.tile, 1)
end

-- ------------------------------------------------------------ the gable
--
-- A BUILDING IS NOT A BOX WITH A LID.  `run.h` is the top of the FACADE and
-- `run.rise` is the roof above it, and the mesher draws that roof as a real
-- sloped surface -- a ridge down the middle of the run, hipped where the cell
-- beside it is lower, with the two courses either side of the ridge stepping
-- to meet it.  Taking `run.h` and stopping, which is what this file did, is
-- how every house came out as a flat-topped slab: the right HEIGHT and the
-- wrong SHAPE, which is worse than being obviously broken because it looks
-- deliberate.
--
-- The profile of the roof across the run, from ChunkMesher's own `gableH`:
-- `d` is how many rows north of the south eave this cell is, `t` runs 0..1
-- up one side of the ridge and back down the other, and a shed roof only
-- goes up.
local function gableHeight(run, d)
  local gext = run.gableExtent or run.extent or 1
  local mid = gext / 2
  local t
  if run.shedRoof then
    t = d / math.max(1e-6, run.shedRoof)
  elseif d <= mid then
    t = d / math.max(1e-6, mid)
  else
    t = (gext - d) / math.max(1e-6, gext - mid)
  end
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return (run.h or 0) + (run.rise or 0) * t
end

local function gableRoof(push, ctx, o, run, heightAt)
  local x0, z0 = o.x0, o.z0
  local d0 = (run.front or o.ty) - o.ty
  local hS = gableHeight(run, d0)
  local hN = gableHeight(run, d0 + 1)
  local swY, seY, neY, nwY = hS, hS, hN, hN

  -- AN EXPOSED FLANK HIPS.  The outer corner drops a course where the cell
  -- beside it is lower, which is what turns a barn end into a roof.
  local base = run.h or 0
  if heightAt and heightAt(o.tx - 1, o.ty) < base then
    swY = math.max(base, hS - 8)
    nwY = math.max(base, hN - 8)
  end
  if heightAt and heightAt(o.tx + 1, o.ty) < base then
    seY = math.max(base, hS - 8)
    neY = math.max(base, hN - 8)
  end

  local u0, u1, v0, v1 = uvRect(ctx, o.tile)
  push({ { x0, swY, z0 + 8 }, { x0 + 8, seY, z0 + 8 },
         { x0 + 8, neY, z0 }, { x0, nwY, z0 } },
       { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, Mesh.ROOF_SHADE)

  -- close the wedge between this column's roof surface and the facade below
  -- it on any flank that is exposed, or the roof floats
  local function flank(d, xAt)
    local nh = heightAt and heightAt(o.tx + d, o.ty) or 0
    if nh >= base then return end
    local yS = (d < 0) and swY or seY
    local yN = (d < 0) and nwY or neY
    if yS <= base and yN <= base then return end
    local x = xAt
    local c
    if d < 0 then
      c = { { x, base, z0 }, { x, base, z0 + 8 }, { x, yS, z0 + 8 }, { x, yN, z0 } }
    else
      c = { { x, base, z0 + 8 }, { x, base, z0 }, { x, yN, z0 }, { x, yS, z0 + 8 } }
    end
    push(c, { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
         Mesh.FACE_SHADE[d < 0 and 2 or 1] or 0.8)
  end
  flank(-1, x0)
  flank(1, x0 + 8)

  -- and the south eave face, between the facade top and the roof edge
  if hS > base then
    local nh = heightAt and heightAt(o.tx, o.ty + 1) or 0
    if nh < base or true then
      push({ { x0, base, z0 + 8 }, { x0 + 8, base, z0 + 8 },
             { x0 + 8, seY, z0 + 8 }, { x0, swY, z0 + 8 } },
           { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, 1)
    end
  end
end

-- THE FOLD, FROM THE RUN'S OWN ROWS.
--
-- Band k of the face samples the map row k tiles NORTH of the structure's
-- front, clamped to its extent -- and where the drawing repeats, it wraps at
-- the repeat period instead, which is what keeps a forty-row border forest as
-- rows of trees rather than one three-hundred-pixel wall.  The north face
-- walks the drawing the other way so the back is not mirrored art.
local function runBandTile(o, run, band, d)
  local tileAt = o.tileAt
  if not tileAt then return o.tile end
  local bb = band - math.floor((run.base or 0) / 8)
  if bb < 0 then bb = 0 end
  local period = run.fromRepeat and run.unit or nil
  local front = run.front or o.ty
  local north = run.north or o.ty
  local row
  if d == 6 then
    if period and period > 0 then
      row = north + (bb % period)
    else
      row = math.min(front, north + bb)
    end
  else
    if period and period > 0 then
      row = front - (bb % period)
    else
      row = math.max(north, front - bb)
    end
  end
  return tileAt(o.tx, row) or o.tile
end

-- The south face folds the drawing upright, 8px band by band.
--
-- Band k spans world heights [8k, 8k+8) and shows one full tile of art;
-- band 0 is the structure's southmost row and higher bands are the rows
-- north of it.  A tileset editor has ONE row, so every band wears the same
-- drawing -- which is exactly what the mesher does when the row north of a
-- pinned upright is not the same class.  The moment a group is authored,
-- the group's rows supply the bands instead.
local function uprightBandTile(o, band)
  if o.bandTiles and o.bandTiles[band + 1] then return o.bandTiles[band + 1] end
  if o.bandTiles and #o.bandTiles > 0 then
    -- repeating past the top, the way a repeat-aware volume does
    return o.bandTiles[(band % #o.bandTiles) + 1]
  end
  return o.tile
end

local function foldUpright(push, ctx, o)
  -- the top face wears the row ABOVE the folded block, darkened; with one
  -- tile there is no row above, so it wears its own
  local bands = math.max(1, math.ceil(o.h / 8))
  local topTile = uprightBandTile(o, bands)
  topQuad(push, ctx, o.x0, o.z0, o.h, topTile, Mesh.VOLUME_TOP_SHADE)
end

-- -------------------------------------------------------- per-pixel folds

local function perPixel(push, ctx, o, depth, opts)
  local w, h = o.gw or 1, o.gh or 1
  local sil = Mesh.silhouette(ctx, o.gtiles or { o.tile }, w, h, opts)
  local bw, bh = sil.w, sil.h
  local support = opts and opts.support or false
  local z0 = o.z0 + (o.zRow or 0) * 8 + (support and 8 or 0) + (8 - depth) / 2
  local z1 = z0 + depth

  -- the drawing stands on its FEET: the lowest lit row of each connected
  -- component sits on the ground, not the bbox
  local lowest = {}
  for lx = 0, bw - 1 do
    for ly = bh - 1, 0, -1 do
      if sil.solid[ly * bw + lx] then lowest[lx] = ly break end
    end
  end

  local function at(lx, ly)
    if lx < 0 or ly < 0 or lx >= bw or ly >= bh then return false end
    return sil.solid[ly * bw + lx] and true or false
  end

  -- STAND IT ON ITS FEET.  The lowest lit row sits on the ground, not the
  -- bounding box: a plant drawn with two rows of air under it is a plant
  -- standing on the floor, and hanging it from its bbox is how a pot ends
  -- up hovering.
  local low = 0
  for _, ly in pairs(lowest) do if ly > low then low = ly end end
  local baseY = o.baseY or 0

  -- The colour at an ATLAS coordinate.  `sil.src` gives atlas texels; the
  -- pixel reader wants a tile and a texel inside it, and the two are the same
  -- thing written differently.  Cached per call because a run test asks for
  -- the same texel twice.
  local perRow = ctx.perRow or 16
  local cCache = {}
  local function colourAt(ax, ay)
    local k = ay * 4096 + ax
    local c = cCache[k]
    if c == nil then
      local tile = math.floor(ay / 8) * perRow + math.floor(ax / 8)
      local r, g, b, a = ctx.pixel(tile, ax % 8, ay % 8)
      c = r and (math.floor(r * 255) * 16777216 + math.floor(g * 255) * 65536
                 + math.floor(b * 255) * 256 + math.floor((a or 1) * 255))
          or false
      cCache[k] = c
    end
    return c
  end

  for ly = 0, bh - 1 do
    local y = baseY + (low - ly)
    -- the body, in runs of one colour
    local lx = 0
    while lx < bw do
      if at(lx, ly) then
        local s = sil.src[ly * bw + lx]
        local col = colourAt(s[1], s[2])
        local lx2 = lx
        while lx2 + 1 < bw and at(lx2 + 1, ly) do
          local s2 = sil.src[ly * bw + lx2 + 1]
          if colourAt(s2[1], s2[2]) ~= col then break end
          lx2 = lx2 + 1
        end
        pixelRun(push, ctx, o.x0 + lx, o.x0 + lx2, y, z0, z1, s[1], s[2], {
          west = not at(lx - 1, ly),
          east = not at(lx2 + 1, ly),
        })
        lx = lx2 + 1
      else
        lx = lx + 1
      end
    end

    -- the caps, in runs of "the neighbour that way is air"
    for _, top in ipairs({ true, false }) do
      local dy = top and -1 or 1
      if top or y > baseY then
        local cx = 0
        while cx < bw do
          if at(cx, ly) and not at(cx, ly + dy) then
            local s = sil.src[ly * bw + cx]
            local cx2 = cx
            while cx2 + 1 < bw and at(cx2 + 1, ly)
                  and not at(cx2 + 1, ly + dy) do
              cx2 = cx2 + 1
            end
            pixelCap(push, ctx, o.x0 + cx, o.x0 + cx2, y, z0, z1,
                     s[1], s[2], top)
            cx = cx2 + 1
          else
            cx = cx + 1
          end
        end
      end
    end
  end
  return sil
end

-- Grass: a 2px slab standing at the middle of its OWN tile, so a cell's two
-- tile rows sit half a cell apart in depth and a tuft reads as a tuft
-- rather than a wall.  Runs of adjacent lit pixels merge into one quad.
local function foldSlab(push, ctx, o, thick, everyPixel)
  local zMid = 4
  local zB, zF = zMid - thick / 2, zMid + thick / 2
  local ax0, ay0 = origin(ctx, o.tile)
  for iy = 0, 7 do
    local yTop = o.baseY + (8 - iy)
    local yBot = yTop - 1
    local ix = 0
    while ix < 8 do
      local r, g, b, a = ctx.pixel(o.tile, ix, iy)
      local lit = r and (a or 1) > 0 and Mesh.shadeClass(math.min(r, g, b)) ~= "white"
      if lit then
        local ix2 = ix
        if not everyPixel then
          while ix2 + 1 < 8 do
            local r2, g2, b2, a2 = ctx.pixel(o.tile, ix2 + 1, iy)
            local l2 = r2 and (a2 or 1) > 0
                and Mesh.shadeClass(math.min(r2, g2, b2)) ~= "white"
            if not l2 then break end
            ix2 = ix2 + 1
          end
        end
        local u0 = (ax0 + ix + 0.05) / ctx.atlasW
        local u1 = (ax0 + ix2 + 0.95) / ctx.atlasW
        local v0 = (ay0 + iy + 0.05) / ctx.atlasH
        local v1 = (ay0 + iy + 0.95) / ctx.atlasH
        local x0 = o.x0 + ix
        local x1 = o.x0 + ix2 + 1
        push({ { x0, yBot, zF }, { x1, yBot, zF }, { x1, yTop, zF }, { x0, yTop, zF } },
             { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, 1)
        push({ { x1, yBot, zB }, { x0, yBot, zB }, { x0, yTop, zB }, { x1, yTop, zB } },
             { { u1, v1 }, { u0, v1 }, { u0, v0 }, { u1, v0 } }, Mesh.OBJ_SHADE.back)
        local si = Mesh.SIDE_INSET
        push({ { x0 + si, yBot, zB }, { x0 + si, yBot, zF }, { x0 + si, yTop, zF }, { x0 + si, yTop, zB } },
             { { u0, v1 }, { u0, v1 }, { u0, v0 }, { u0, v0 } }, Mesh.OBJ_SHADE.side)
        push({ { x1 - si, yBot, zF }, { x1 - si, yBot, zB }, { x1 - si, yTop, zB }, { x1 - si, yTop, zF } },
             { { u1, v1 }, { u1, v1 }, { u1, v0 }, { u1, v0 } }, Mesh.OBJ_SHADE.side)
        ix = ix2 + 1
      else
        ix = ix + 1
      end
    end
  end
end

-- A round hull cut from the art's own darkest-pixel outline: each art row
-- becomes a disc whose chord is that row's own drawn half-width, so a
-- canopy is round in depth instead of being a box with a tree painted on it.
local function foldRound(push, ctx, o, cellsW, cellsH)
  cellsW, cellsH = cellsW or 1, cellsH or 1
  local N = 8 * (o.gw or (cellsW * 2))
  local rows = 8 * (o.gh or (cellsH * 2))
  local tiles = o.gtiles or { o.tile }
  local gw = o.gw or 1
  local sil = Mesh.silhouette(ctx, tiles, gw, o.gh or 1, { strict = false })
  local bw, bh = sil.w, sil.h
  local mx = o.x0 + bw / 2
  local mz = o.z0 + bw / 2

  for ly = 0, bh - 1 do
    local minx, maxx = nil, nil
    for lx = 0, bw - 1 do
      if sil.solid[ly * bw + lx] then
        minx = minx or lx
        maxx = lx
      end
    end
    if minx then
      local cx = (minx + maxx + 1) / 2
      local r = (maxx - minx + 1) / 2
      local yT = o.baseY + (bh - ly)
      local yB = yT - 1
      local segs = 12
      for s = 0, segs - 1 do
        local a0 = (s / segs) * math.pi * 2
        local a1 = ((s + 1) / segs) * math.pi * 2
        local x0 = o.x0 + cx + math.cos(a0) * r
        local x1 = o.x0 + cx + math.cos(a1) * r
        local z0 = mz + math.sin(a0) * r
        local z1 = mz + math.sin(a1) * r
        -- sample the art at the projected x, so the drawing wraps round
        local px0 = math.max(minx, math.min(maxx, math.floor(cx + math.cos(a0) * r)))
        local px1 = math.max(minx, math.min(maxx, math.floor(cx + math.cos(a1) * r)))
        local s0 = sil.src[ly * bw + px0] or { 0, 0 }
        local s1 = sil.src[ly * bw + px1] or { 0, 0 }
        local u0 = (s0[1] + 0.5) / ctx.atlasW
        local u1 = (s1[1] + 0.5) / ctx.atlasW
        local v = (s0[2] + 0.5) / ctx.atlasH
        local shade = 0.65 + 0.35 * math.max(0, math.sin(a0))
        push({ { x0, yB, z0 }, { x1, yB, z1 }, { x1, yT, z1 }, { x0, yT, z0 } },
             { { u0, v }, { u1, v }, { u1, v }, { u0, v } }, shade)
      end
      if ly == 0 or not sil.solid[(ly - 1) * bw + math.floor(cx)] then
        -- cap the top with the row's own art
        local segsC = 12
        for s = 0, segsC - 1 do
          local a0 = (s / segsC) * math.pi * 2
          local a1 = ((s + 1) / segsC) * math.pi * 2
          local sC = sil.src[ly * bw + math.floor(cx)] or { 0, 0 }
          local u = (sC[1] + 0.5) / ctx.atlasW
          local v = (sC[2] + 0.5) / ctx.atlasH
          push({ { o.x0 + cx, yT, mz },
                 { o.x0 + cx + math.cos(a0) * r, yT, mz + math.sin(a0) * r },
                 { o.x0 + cx + math.cos(a1) * r, yT, mz + math.sin(a1) * r },
                 { o.x0 + cx, yT, mz } },
               { { u, v }, { u, v }, { u, v }, { u, v } }, Mesh.OBJ_SHADE.top)
        end
      end
    end
  end
end

-- Steps rising toward the named side, the full cell deep, treads textured
-- from the drawn staircase.
local function foldStair(push, ctx, o, dir)
  local steps = Mesh.STAIR_STEPS
  local rise = o.h / steps
  local runW = 8 / steps
  local ax, ay = origin(ctx, o.tile)
  for i = 0, steps - 1 do
    local y = rise * (i + 1)
    local sx, sx2
    if dir == "e" then sx, sx2 = o.x0 + i * runW, o.x0 + (i + 1) * runW
    else sx, sx2 = o.x0 + 8 - (i + 1) * runW, o.x0 + 8 - i * runW end
    local u0 = (ax + (sx - o.x0) + 0.05) / ctx.atlasW
    local u1 = (ax + (sx2 - o.x0) - 0.05) / ctx.atlasW
    local v0 = (ay + 0.05) / ctx.atlasH
    local v1 = (ay + 8 - 0.05) / ctx.atlasH
    push({ { sx, y, o.z0 }, { sx2, y, o.z0 }, { sx2, y, o.z0 + 8 }, { sx, y, o.z0 + 8 } },
         { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, 1)
    local fx = (dir == "e") and sx or sx2
    local d = (dir == "e") and 2 or 1
    sideQuad(push, ctx, d, fx - (d == 2 and 0 or 8), o.z0, y - rise, y, o.tile,
             0, 8, Mesh.FACE_SHADE[d])
  end
end

-- The floor drawing raised a few voxels inside its own black outline: a
-- console set down on the floor, not a box with a console on the lid.
local function foldRelief(push, ctx, o)
  local h = o.h > 0 and o.h or 3
  local ax, ay = origin(ctx, o.tile)
  for py = 0, 7 do
    for px = 0, 7 do
      local r, g, b, a = ctx.pixel(o.tile, px, py)
      local lit = r and (a or 1) > 0
      local up = lit and Mesh.shadeClass(math.min(r, g, b)) ~= "black"
      local y = up and h or 0
      local u = (ax + px + 0.5) / ctx.atlasW
      local v = (ay + py + 0.5) / ctx.atlasH
      local uv = { { u, v }, { u, v }, { u, v }, { u, v } }
      local x, z = o.x0 + px, o.z0 + py
      push({ { x, y, z }, { x + 1, y, z }, { x + 1, y, z + 1 }, { x, y, z + 1 } },
           uv, 1)
      if up then
        for _, side in ipairs(Mesh.SIDES) do
          local nx, ny = px + side[1], py + side[2]
          local nlit = false
          if nx >= 0 and ny >= 0 and nx < 8 and ny < 8 then
            local r2, g2, b2, a2 = ctx.pixel(o.tile, nx, ny)
            nlit = r2 and (a2 or 1) > 0 and Mesh.shadeClass(math.min(r2, g2, b2)) ~= "black"
          end
          if not nlit then
            local d = side[3]
            local c
            if d == 5 then c = { { x, 0, z + 1 }, { x + 1, 0, z + 1 }, { x + 1, h, z + 1 }, { x, h, z + 1 } }
            elseif d == 6 then c = { { x + 1, 0, z }, { x, 0, z }, { x, h, z }, { x + 1, h, z } }
            elseif d == 1 then c = { { x + 1, 0, z + 1 }, { x + 1, 0, z }, { x + 1, h, z }, { x + 1, h, z + 1 } }
            else c = { { x, 0, z }, { x, 0, z + 1 }, { x, h, z + 1 }, { x, h, z } } end
            push(c, uv, Mesh.FACE_SHADE[d] or 1)
          end
        end
      end
    end
  end
end

-- --------------------------------------------------------- the sub-tile box

-- res x res sub-columns, each its own little box.  Sides only where the
-- neighbouring sub-column is LOWER, exactly as the tile-sized path does --
-- so the inside of a flat patch costs nothing and only the steps between
-- levels produce faces.  Off the tile's own edge the neighbour is the NEXT
-- TILE's height, so a sculpted tile still closes against the ground beside
-- it rather than leaving a slot you can see through.
local function subBoxes(push, ctx, o, sub, heightAt)
  local res = math.max(1, math.min(8, math.floor(sub.res)))
  local step = 8 / res
  local hs = sub.h
  local base = o.h

  local function subH(i, j)
    if i < 0 or j < 0 or i >= res or j >= res then return nil end
    local v = hs[j * res + i + 1]
    return tonumber(v) or base
  end
  local function subUV(i, j)
    local ax, ay = origin(ctx, o.tile)
    return (ax + i * step) / ctx.atlasW, (ax + (i + 1) * step) / ctx.atlasW,
           (ay + j * step) / ctx.atlasH, (ay + (j + 1) * step) / ctx.atlasH
  end

  for j = 0, res - 1 do
    for i = 0, res - 1 do
      local hh = subH(i, j) or base
      local sx, sz = o.x0 + i * step, o.z0 + j * step
      local u0, u1, v0, v1 = subUV(i, j)
      push({ { sx, hh, sz }, { sx + step, hh, sz },
             { sx + step, hh, sz + step }, { sx, hh, sz + step } },
           { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, 1,
           { kind = "subtop", i = i, j = j, res = res, h = hh })
      for _, side in ipairs(Mesh.SIDES) do
        local ni, nj = i + side[1], j + side[2]
        local nh = subH(ni, nj)
        if nh == nil then
          nh = heightAt and heightAt(o.tx + side[1], o.ty + side[2]) or 0
        end
        if nh < hh then
          local d = side[3]
          local x1, z1 = sx + step, sz + step
          local c
          if d == 5 then c = { { sx, nh, z1 }, { x1, nh, z1 }, { x1, hh, z1 }, { sx, hh, z1 } }
          elseif d == 6 then c = { { x1, nh, sz }, { sx, nh, sz }, { sx, hh, sz }, { x1, hh, sz } }
          elseif d == 1 then c = { { x1, nh, z1 }, { x1, nh, sz }, { x1, hh, sz }, { x1, hh, z1 } }
          else c = { { sx, nh, sz }, { sx, nh, z1 }, { sx, hh, z1 }, { sx, hh, sz } } end
          push(c, { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
               Mesh.FACE_SHADE[d] or 1,
               { kind = "subside", i = i, j = j, res = res, d = d })
        end
      end
    end
  end
end

-- ------------------------------------------------------------- the side pass

-- 8px bands wherever the neighbour is lower.  Band k spans heights
-- [8k, 8k+8) and shows one full tile of art; a partial band CROPS the art
-- rows to match, so nothing ever stretches.
--
-- The crop is the rule worth reading twice: a face spanning [y0,y1] inside
-- band `band` wears art rows vTop = (band*8+8) - y1 to vBot = (band*8+8) -
-- y0.  The TOP of the band is art row 0.  So a 6px ledge beside flat ground
-- shows rows 2..8 -- the BOTTOM of the lip drawing -- and a 2px shoreline
-- lip beside water shows rows 0..2, the top of the ground tile's art.
local function sidePass(push, ctx, o, heightAt)
  local h = o.h
  for _, side in ipairs(Mesh.SIDES) do
    local nh = heightAt and heightAt(o.tx + side[1], o.ty + side[2]) or 0
    local bottom = nh
    if o.class == "bridge" and h - nh > 8 then bottom = h - 8 end
    if bottom < h then
      local d = side[3]
      local b0 = math.floor(bottom / 8)
      local b1 = math.ceil(h / 8) - 1
      for band = b0, b1 do
        local y0 = math.max(bottom, band * 8)
        local y1 = math.min(h, band * 8 + 8)
        if y1 > y0 then
          local src = o.tile
          local shade = Mesh.FACE_SHADE[d] or 1
          if o.run then
            src = runBandTile(o, o.run, band, d)
            if d == 5 then shade = 1 end
          elseif o.art == "upright" then
            src = uprightBandTile(o, band)
            if d == 5 then shade = 1 end
          end
          -- AN AUTHORED BAND WINS, whatever the fold.
          --
          -- Raise a ground tile to 40px and five bands of wall appear wearing
          -- the GRASS drawing, because with no run and no upright fold the
          -- only tile a face knows about is its own.  That is the void: real
          -- geometry with no art that belongs on it.  Where the reader has
          -- named a tile for a band, that is the art -- the same precedence
          -- as everywhere else here, authored over derived.
          if o.bands then
            local b = o.bands[band]
            if b == nil then b = o.bands[-1] end     -- -1 is "every band"
            if type(b) == "number" then src = b end
          end
          sideQuad(push, ctx, d, o.x0, o.z0, y0, y1, src,
                   (band * 8 + 8) - y1, (band * 8 + 8) - y0, shade)
        end
      end
    end
  end
end

-- ------------------------------------------------------------- entry point

-- Build the geometry for ONE tile.
--   shape    { class, h, art, flat, sub }
--   ctx      { perRow, atlasW, atlasH, pixel(tile,px,py) }
--   opts     { tx, ty, tile, heightAt(tx,ty), group = { w, h, tiles } }
-- Returns quads, notes.
function Mesh.tile(shape, ctx, opts)
  local quads, push = newSink()
  local notes = {}
  opts = opts or {}
  local tx, ty = opts.tx or 0, opts.ty or 0
  local o = {
    tx = tx, ty = ty,
    x0 = tx * 8, z0 = ty * 8,
    tile = opts.tile or 0,
    h = shape.h or 0,
    art = shape.art or "upright",
    class = shape.class,
    baseY = 0,
    bandTiles = opts.bandTiles,
    -- authored per-band source tiles, band index -> tile id, with -1 meaning
    -- "every band that has no entry of its own"
    bands = opts.bands,
  }
  if opts.group then
    o.gw, o.gh, o.gtiles = opts.group.w, opts.group.h, opts.group.tiles
  end
  o.run = opts.run
  o.tileAt = opts.tileAt
  local heightAt = opts.heightAt

  if shape.sub and shape.sub.res and shape.sub.h then
    subBoxes(push, ctx, o, shape.sub, heightAt)
    notes[#notes + 1] =
      "sub-tile heights: " .. shape.sub.res .. "x" .. shape.sub.res
      .. " columns -- exported as a coordinate override, not a class pin"
    return quads, notes
  end

  local art = o.art
  if art == "flat" then
    foldFlat(push, ctx, o)
    sidePass(push, ctx, o, heightAt)
  elseif art == "top" then
    foldTop(push, ctx, o)
    sidePass(push, ctx, o, heightAt)
  elseif art == "upright" then
    if o.run and (o.run.rise or 0) > 0 then
      -- a measured building: the box is the facade and the roof is a real
      -- sloped surface on top of it
      gableRoof(push, ctx, o, o.run, heightAt)
    elseif o.run then
      topQuad(push, ctx, o.x0, o.z0, o.h,
              runBandTile(o, o.run, math.max(1, math.ceil(o.h / 8)), 6),
              Mesh.VOLUME_TOP_SHADE)
    else
      foldUpright(push, ctx, o)
    end
    sidePass(push, ctx, o, heightAt)
  elseif art == "billboard" then
    local depth = Mesh.PINNED_DEPTH[o.class] or Mesh.PINNED_DEPTH.billboard
    perPixel(push, ctx, o, depth, { strict = o.class == "cutout",
                                    bg = opts.propBg })
    notes[#notes + 1] = "per-pixel standee at " .. depth .. " voxels deep"
  elseif art == "post" then
    perPixel(push, ctx, o, Mesh.PINNED_DEPTH.post, { strict = true })
    notes[#notes + 1] = "posts are read per CELL in game; the preview shows one tile"
  elseif art == "cylinder" or art == "canopy" or art == "planter" then
    foldRound(push, ctx, o, art == "canopy" and 2 or 1, art == "planter" and 2 or 1)
    notes[#notes + 1] = "round hull cut from the drawing's own half-widths"
    if art == "canopy" then
      notes[#notes + 1] = "canopy is a 2x2-CELL group in game -- pin the group, not the tile"
    end
  elseif art == "grass" then
    foldSlab(push, ctx, o, Mesh.GRASS_THICK, false)
  elseif art == "flower" then
    foldSlab(push, ctx, o, Mesh.FLOWER_THICK, true)
  elseif art == "relief" then
    foldRelief(push, ctx, o)
  elseif art == "stair" then
    foldStair(push, ctx, o, (o.class or ""):match("_w") and "w" or "e")
  elseif art == "bookcase" then
    foldUpright(push, ctx, o)
    sidePass(push, ctx, o, heightAt)
    notes[#notes + 1] =
      "bookcase collapses its RANKS onto one cell in game; the front carries pane relief"
  else
    foldUpright(push, ctx, o)
    sidePass(push, ctx, o, heightAt)
    notes[#notes + 1] = "unknown fold '" .. tostring(art) .. "' -- previewed as upright"
  end

  return quads, notes
end

-- Build a whole grid.  The heights of neighbours come from the same
-- resolver, so face culling and the band crop are the real ones.
function Mesh.grid(grid, resolve, ctx, opts)
  opts = opts or {}
  local quads, push = newSink()
  local notes = {}

  local cacheH = {}
  local function heightAt(tx, ty)
    local k = tx .. "," .. ty
    local v = cacheH[k]
    if v ~= nil then return v end
    local s = resolve(tx, ty)
    v = s and s.h or 0
    cacheH[k] = v
    return v
  end

  for ty = 0, grid.h - 1 do
    for tx = 0, grid.w - 1 do
      local s = resolve(tx, ty)
      if s then
        local q, n = Mesh.tile(s, ctx, {
          tx = tx, ty = ty, tile = grid:tileAt(tx, ty), heightAt = heightAt,
        })
        for _, quad in ipairs(q) do push(quad, quad.uv, quad.shade) end
        if opts.notes then
          for _, note in ipairs(n) do notes[#notes + 1] = note end
        end
      end
    end
  end
  return quads, notes
end

return Mesh
