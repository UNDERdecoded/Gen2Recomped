-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A real 3D viewport for the map editor: perspective camera, depth buffer,
-- one textured mesh built from the map's own heights and artwork.
--
-- WHY NOT THE MOD'S RENDERER. Voxel3D + ChunkMesher + Structures is the thing
-- that draws the world in game, and reusing it would be the highest-fidelity
-- answer. It is also 300KB of mod code that loads through the mod loader's `V`
-- context, wants shadow maps, a sun, a world curve and a sky, and cannot be
-- run from inside the save-editor shell without dragging all of it in. So this
-- is a second renderer, and the honest way to build a second renderer is to
-- match the first one's CONVENTIONS exactly and say where it stops:
--
--   * the same axes -- X east, Y up, Z south (VoxelScene)
--   * the same face shading -- Voxel3D.FACE_SHADE, read from the mod when it
--     is reachable so the two cannot drift
--   * the same heights -- TileShape, through the editor's own VoxelClasses
--   * the same camera ladder -- VoxelState's 15/35/50/75 degrees
--
-- THE GEOMETRY IS VOXELS, NOT BOXES. A cell is not extruded as a 16x16 slab:
-- its artwork is read pixel by pixel, the drawing's silhouette is cut out of
-- the background the same way Structures cuts it, and every surviving pixel
-- becomes a 1-unit column. That is what makes a fence a row of pickets with
-- daylight between them instead of a wall, and a tree a tree instead of a
-- textured cube. A world unit is one artwork pixel here exactly as it is in
-- the mod, so a 16px cell is 16 units and the class heights need no scaling.
--
-- WHAT IT DOES NOT DO: structure grouping (a building is meshed cell by cell,
-- not as one connected thing), the standee depth pools, conditional pins,
-- shadows, water, weather, day/night. Those are Structures' work and they need
-- the whole map's topology, not one cell's drawing.
--
-- EVERY GPU CALL IS GUARDED. `available()` answers false on a headless run, on
-- a driver with no depth canvas, and where the shader will not build -- and
-- the caller falls back to the flat projection rather than losing the panel.

local VoxelClasses = require("tools.map-editor.VoxelClasses")
-- The selected mod's REAL TileShape and Structures, loaded and asked directly.
-- See ModShapes.lua: the editor used to re-derive both and got a different
-- world for its trouble.
local ModShapes = require("tools.map-editor.ModShapes")

-- LuaJIT (the runtime) has the 5.1 global; 5.3 moved it. Named once so a
-- headless run under either can load this file.
local unpack = unpack or table.unpack

local Viewport3D = {}

local CELL = 16

-- Matching Voxel3D.FACE_SHADE. Read from the mod first so a retune there is
-- picked up here; these numbers are the fallback, not a second opinion.
local FACE_SHADE = { east = 0.84, west = 0.72, top = 1.00,
                     south = 0.90, north = 0.68 }

-- How thick a standing prop is, in voxels. Structures' PINNED_DEPTH, and the
-- reason it is per class: a fence post is a solid stake and a signpost is a
-- plate on a stick, and giving both the same body closes the gaps in the one
-- that is mostly gaps.
-- Structures' PLANTER_SPRAY.depth: how thin a crown capped to a spray of
-- leaves is. Uncapped, a crown is a ball and fills the cell.
local PLANTER_SPRAY_DEPTH = 5

local PINNED_DEPTH = { billboard = 10, prop = 5, stool = 10, cutout = 1,
                       column = 6, console = 10, post = 6, signpost = 2,
                       bike = 2 }
local DEFAULT_DEPTH = 5
do
  local ok, V3 = pcall(require, "mods.STADIUM2_OVERWORLD_MODELS.lib.Voxel3D")
  if ok and type(V3) == "table" and type(V3.FACE_SHADE) == "table" then
    local m = V3.FACE_SHADE
    FACE_SHADE = {
      east = m[1] or FACE_SHADE.east, west = m[2] or FACE_SHADE.west,
      top = m[3] or FACE_SHADE.top,
      south = m[5] or FACE_SHADE.south, north = m[6] or FACE_SHADE.north,
    }
  end
end

-- ---------------------------------------------------------------------------
-- matrices (column-major, the layout LOVE's mat4 uniforms take)
-- ---------------------------------------------------------------------------

local function matMul(a, b)
  local o = {}
  for c = 0, 3 do
    for r = 0, 3 do
      local sum = 0
      for k = 0, 3 do sum = sum + a[k * 4 + r + 1] * b[c * 4 + k + 1] end
      o[c * 4 + r + 1] = sum
    end
  end
  return o
end

local function matPerspective(fovY, aspect, near, far)
  local f = 1 / math.tan(fovY / 2)
  local o = {}
  for i = 1, 16 do o[i] = 0 end
  o[1] = f / aspect
  o[6] = f
  o[11] = (far + near) / (near - far)
  o[12] = -1
  o[15] = (2 * far * near) / (near - far)
  return o
end

local function normalise(x, y, z)
  local d = math.sqrt(x * x + y * y + z * z)
  if d < 1e-9 then return 0, 0, 0 end
  return x / d, y / d, z / d
end

local function matOrtho(l, r, b, t, n, f)
  local o = {}
  for i = 1, 16 do o[i] = 0 end
  o[1] = 2 / (r - l)
  o[6] = 2 / (t - b)
  o[11] = -2 / (f - n)
  o[13] = -(r + l) / (r - l)
  o[14] = -(t + b) / (t - b)
  o[15] = -(f + n) / (f - n)
  o[16] = 1
  return o
end

local function matLookAt(ex, ey, ez, tx, ty, tz)
  local fx, fy, fz = normalise(tx - ex, ty - ey, tz - ez)
  -- up is +Y; when the camera looks straight down the cross product
  -- degenerates, so the pitch is clamped short of vertical by the caller
  -- cross(forward, up) with up = +Y reduces to (-fz, 0, fx)
  local sx, sy, sz = normalise(-fz, 0, fx)
  local ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
  return {
    sx, ux, -fx, 0,
    sy, uy, -fy, 0,
    sz, uz, -fz, 0,
    -(sx * ex + sy * ey + sz * ez),
    -(ux * ex + uy * ey + uz * ez),
    (fx * ex + fy * ey + fz * ez), 1,
  }
end

-- ---------------------------------------------------------------------------
-- the shader
-- ---------------------------------------------------------------------------

-- Deliberately small. The mod's scene shader carries shadow lookups, a world
-- curve and a wireframe variant; none of that is what an editor preview is
-- for, and every uniform it would need is another thing that can fail to
-- build on a driver the editor still has to open on.
-- DO NOT DECLARE VertexColor. LOVE's own vertex preamble already declares
-- VertexPosition, VertexTexCoord and VertexColor, so an `attribute vec4
-- VertexColor;` here is a GLSL REDEFINITION and the whole shader fails to
-- compile. That is not a cosmetic bug: newShader returns nil, available()
-- returns false, and the viewport silently falls back to the flat projection
-- forever. It looks exactly like "the 3D view does not work" with nothing on
-- screen to say why -- which is what it was.
--
-- The per-vertex shade needs no plumbing either. LOVE's preamble assigns
-- VaryingColor from VertexColor, and `effect`'s first parameter IS
-- VaryingColor -- so the face shading arrives as `color` with nothing declared
-- and nothing passed.
local SHADER = [[
#ifdef VERTEX
uniform mat4 vp;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  return vp * vec4(vertex_position.xyz, 1.0);
}
#endif
#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
  vec4 t = Texel(tex, uv);
  if (t.a < 0.5) discard;
  return vec4(t.rgb * color.rgb, 1.0);
}
#endif
]]

local shader, shaderTried, shaderError = nil, false, nil
-- Declared UP HERE, not beside the canvases it describes: unavailableReason
-- below reads it, and a `local` further down would leave that read looking at
-- a global that is nil until the first draw.
local canvasFailed = false

local function getShader()
  if shaderTried then return shader end
  shaderTried = true
  if not (love.graphics and love.graphics.newShader) then
    shaderError = "no love.graphics.newShader"
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, SHADER)
  if ok and sh then
    shader = sh
  else
    -- KEPT, and shown. A shader that will not build is the single most likely
    -- reason this viewport is not on screen, and a silent fallback gives the
    -- reader nothing to act on. The driver's own message is the whole
    -- diagnosis.
    shaderError = tostring(sh)
    shader = nil
  end
  return shader
end

-- Why the 3D path is unavailable, or nil when it is available. Shown in the
-- panel footer.
-- The reason there is no 3D picture, whatever stage it failed at. Callers ask
-- this ONE question rather than assembling an answer from several, because
-- assembling it is how the panel ended up claiming an installed module was
-- missing.
function Viewport3D.whyNoPicture()
  return Viewport3D.unavailableReason() or Viewport3D.lastDrawError
    or "the 3D pass did not run"
end

function Viewport3D.unavailableReason()
  if not (love.graphics and love.graphics.newCanvas and love.graphics.newMesh
          and love.graphics.setDepthMode) then
    return "this LOVE build has no depth-buffer support"
  end
  if getShader() == nil then
    return "shader would not build: " .. tostring(shaderError or "unknown")
  end
  if canvasFailed then
    return "no depth canvas could be created on this driver"
  end
  return nil
end

function Viewport3D.available()
  return Viewport3D.unavailableReason() == nil
end

-- ---------------------------------------------------------------------------
-- the mesh
-- ---------------------------------------------------------------------------

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  { "VertexColor", "byte", 4 },
}

-- ---------------------------------------------------------------------------
-- structures
-- ---------------------------------------------------------------------------

-- A volume is as tall as its structure is DRAWN.
--
-- This is Structures' rule 4, and without it a world is uniformly 16px high:
-- every solid cell took its class default and a six-row house came out the
-- same height as the kerb outside it. The mod says it plainly -- "each column
-- rises to the height the structure is actually DRAWN. A column's run gives
-- its extent, repetition caps it".
--
-- So: walk each TILE COLUMN, find the unbroken run of solid tiles the column
-- sits in, and the run's height is its length in rows times eight. A single
-- solid cell is two rows and comes out 16px, which is why every wall in the
-- game already looked right and nothing else did.
--
-- REPETITION IS THE OTHER HALF. Johto's border forest repeats a two-row canopy
-- for forty rows; measured literally that is a 320px wall of tree, and the mod
-- calls that out by name -- it has to be "rows of 16px trees, not a monolith".
-- So a run that repeats is capped to the repeat's own drawn unit. A house's
-- rows are all different, find no repeat, and keep their full height.
--
-- The scan below is Structures' rather than a period search of my own. That
-- matters: an independent measurement of the same drawing is a second answer,
-- and where it differs from the mod's the editor shows a world the game will
-- not build. So the run scan, its `max(k, 2)` floor, its trim-foot clause and
-- its region consensus are all transcribed from lib/Structures.lua.
local STRUCT_MAX_ROWS = 6          -- Structures' MAX_ROWS: 48px

-- A COLUMN'S OWN READING, to Structures' letter (its run scan, ~line 2685).
--
-- The run is [north .. front] going down the screen, and the drawn unit is its
-- extent unless the drawing repeats -- anchored at the FRONT tile and scanning
-- back for the first row that draws the same thing. `max(k, 2)` is why an
-- ordinary wall whose two rows are identical stays 16px instead of collapsing
-- to 8: a cell is the smallest a structure can be, because collision is stated
-- per cell.
--
-- The second clause is the TRIM FOOT, and it is not an optimisation. A cliff
-- plateau ends its south edge in a rounded corner tile; the corner never
-- recurs, so the anchor scan finds no repeat and the column reads its whole
-- capped extent -- a 48px fin standing out of a 16px mesa. When the two rows
-- directly above the front are identical, the column is that repeat wearing a
-- trim foot: one course plus the trim.
local function columnUnit(tileAt, tx, north, front)
  local extent = front - north + 1
  local unit, fromRepeat = math.min(extent, STRUCT_MAX_ROWS), false
  if extent > 1 then
    local t0 = tileAt(tx, front)
    for k = 1, extent - 1 do
      if tileAt(tx, front - k) == t0 then
        unit = math.min(math.max(k, 2), STRUCT_MAX_ROWS)
        fromRepeat = true
        break
      end
    end
    if not fromRepeat and extent > 2
       and tileAt(tx, front - 1) == tileAt(tx, front - 2) then
      unit = 2
      fromRepeat = true
    end
  end
  return unit, fromRepeat, extent
end

-- Height in world units for every solid tile of the map, keyed ty * W2 + tx
-- where W2 is the map's width in TILES.
--
-- Two passes, because a building is not a column. The first measures each tile
-- column on its own; the second lets the REGION -- one connected structure --
-- decide, and that is the half that was missing. A house's doorway column
-- reads a doorway, its window column reads a window, its plain courses repeat:
-- read individually they disagree, and a house came out as a row of slabs of
-- different heights with a notch where its door is. Structures resolves that
-- by consensus: the region's dominant height wins, and a column whose reading
-- came from a repeat adopts it WHEN TALLER -- the courses above a doorway
-- repeat internally but belong to a 48px house -- while a column that read its
-- full extent keeps it, so an attached low wing stays low.
function Viewport3D.structureHeights(map, solidCell)
  local def = map.def
  local W2, H2 = def.width * 4, def.height * 4
  local WC, HC = def.width * 2, def.height * 2
  local heights = {}
  local function tileAt(tx, ty)
    local ok, t = pcall(map.tileAt, map, tx, ty)
    return ok and t or nil
  end
  local function solidC(cx, cy)
    if cx < 0 or cy < 0 or cx >= WC or cy >= HC then return false end
    return solidCell(cx, cy) and true or false
  end
  local function solid(tx, ty)
    if tx < 0 or ty < 0 or tx >= W2 or ty >= H2 then return false end
    return solidC(math.floor(tx / 2), math.floor(ty / 2))
  end

  -- ONE CONNECTED THING = ONE REGION. Four-neighbour flood over solid CELLS,
  -- the granularity collision is stated at. Diagonal touching is deliberately
  -- not connected: two buildings that meet at a corner are two buildings, and
  -- joining them would hand one the other's height.
  local region, regionOf = {}, 0
  for cy = 0, HC - 1 do
    for cx = 0, WC - 1 do
      if solidC(cx, cy) and not region[cy * WC + cx] then
        regionOf = regionOf + 1
        local stack = { { cx, cy } }
        region[cy * WC + cx] = regionOf
        while #stack > 0 do
          local n = table.remove(stack)
          local px, py = n[1], n[2]
          local nb = { { px + 1, py }, { px - 1, py },
                       { px, py + 1 }, { px, py - 1 } }
          for _, q in ipairs(nb) do
            local k = q[2] * WC + q[1]
            if solidC(q[1], q[2]) and not region[k] then
              region[k] = regionOf
              stack[#stack + 1] = q
            end
          end
        end
      end
    end
  end

  -- PASS 1: every run's own reading, and a vote per region.
  local runs = {}
  local votes, repeatVotes = {}, {}
  for tx = 0, W2 - 1 do
    local ty = 0
    while ty < H2 do
      if solid(tx, ty) then
        local north = ty
        while ty < H2 and solid(tx, ty) do ty = ty + 1 end
        local front = ty - 1
        local unit, fromRepeat = columnUnit(tileAt, tx, north, front)
        local rid = region[math.floor(front / 2) * WC + math.floor(tx / 2)]
        runs[#runs + 1] = { tx = tx, north = north, front = front,
                            unit = unit, fromRepeat = fromRepeat, rid = rid }
        if rid then
          local h = unit * 8
          votes[rid] = votes[rid] or {}
          votes[rid][h] = (votes[rid][h] or 0) + 1
          if fromRepeat then
            repeatVotes[rid] = repeatVotes[rid] or {}
            repeatVotes[rid][h] = (repeatVotes[rid][h] or 0) + 1
          end
        end
      else
        ty = ty + 1
      end
    end
  end

  -- the dominant height per region; ties break TALL, as Structures' does
  local mode = {}
  for rid, tally in pairs(votes) do
    local modeH, modeN = 16, 0
    for h, n in pairs(tally) do
      if n > modeN or (n == modeN and h > modeH) then modeH, modeN = h, n end
    end
    mode[rid] = modeH
  end

  -- PASS 2: adopt, and write.
  for _, r in ipairs(runs) do
    local h = r.unit * 8
    local modeH = r.rid and mode[r.rid]
    if r.fromRepeat and modeH and modeH > h then h = modeH end
    for y = r.north, r.front do heights[y * W2 + r.tx] = h end
  end
  return heights, W2
end

-- ---------------------------------------------------------------------------
-- the silhouette
-- ---------------------------------------------------------------------------

-- Structures.shadeClass, to the letter. The thresholds decide which pixels the
-- flood can walk through, so a different set here would carve a different
-- silhouette from the one the game builds -- the shapes would be nearly right,
-- which is worse than obviously wrong.
local function shadeClass(v)
  if v <= 0.25 then return "black" end
  if v <= 0.55 then return "dark" end
  if v <= 0.85 then return "light" end
  return "white"
end

-- Which pixels of a 16x16 cell canvas are the DRAWING rather than the ground
-- behind it.
--
-- Mirrors Structures' rule: flood the OUTSIDE inward from the border through
-- everything that is not the dark outline, and whatever the flood could not
-- reach is the object. Gen 2 art has no alpha -- the background is a colour,
-- not transparency -- so a silhouette can only be found by what encloses it,
-- and the black outline is what does the enclosing.
--
-- The fallback matters as much as the rule. When the first flood keeps almost
-- nothing (an object drawn as a solid dark mass with no outline, its base
-- running flush to the canvas edge -- the flood walks straight in through the
-- dark and guts it) the second flood treats dark as body instead of as
-- passable. Structures measures that at an eighth of the canvas and so does
-- this.
local function silhouette(sample)
  local N = 16
  local cls = {}
  for py = 0, N - 1 do
    for px = 0, N - 1 do
      local r, g, b, a = sample(px, py)
      cls[py * N + px] = (a == 0) and "off" or shadeClass(math.min(r, g, b))
    end
  end

  local function floodOutside(passable)
    local out, stack = {}, {}
    local function seed(i)
      if not out[i] and passable[cls[i]] then
        out[i] = true
        stack[#stack + 1] = i
      end
    end
    for px = 0, N - 1 do seed(px); seed((N - 1) * N + px) end
    for py = 0, N - 1 do seed(py * N); seed(py * N + N - 1) end
    while #stack > 0 do
      local i = table.remove(stack)
      local px, py = i % N, math.floor(i / N)
      if px > 0 then seed(i - 1) end
      if px < N - 1 then seed(i + 1) end
      if py > 0 then seed(i - N) end
      if py < N - 1 then seed(i + N) end
    end
    return out
  end

  local mask = {}
  local out = floodOutside({ off = true, dark = true, light = true, white = true })
  local enclosed = 0
  for i = 0, N * N - 1 do
    if not out[i] then
      mask[i] = true
      if cls[i] ~= "black" then enclosed = enclosed + 1 end
    end
  end
  if enclosed < N * N / 8 then
    out = floodOutside({ off = true, light = true, white = true })
    for i = 0, N * N - 1 do
      mask[i] = (not out[i] and cls[i] ~= "off") or nil
    end
  end
  return mask
end

Viewport3D.silhouette = silhouette
Viewport3D.shadeClass = shadeClass

-- The height of one cell, from the same places the 2D preview reads: the
-- editor's tile override, then its cell override, then the class the tileset's
-- collision resolves to.
local function heightAt(ctx, cx, cy)
  -- THE MOD'S OWN ANSWER, WHEN IT CAN BE ASKED, AND NOTHING ELSE.
  --
  -- Everything below this branch is the editor working the shape out for
  -- itself -- the tile pins, the collision map, the class table, the run scan.
  -- All of it is a SECOND implementation of what lib/TileShape.lua and
  -- lib/Structures.lua already do, and a second implementation of a rule is a
  -- second answer to it. It is kept only for the case where the mod cannot be
  -- loaded at all; where it can, the editor stops guessing.
  --
  -- Two steps, in the mesher's own order (ChunkMesher's `heightAt`): a tile
  -- that belongs to a measured RUN answers with the run's height, and every
  -- other tile answers with its shape's. Not "the run wins only for walls",
  -- which is what the editor used to do -- a run is what a drawn building IS,
  -- and the class beneath it is only what the cell would have been without it.
  --
  -- Overrides need no branch here: the mod reads `def.voxelTileEdits` and
  -- `def.voxelEdits` at the top of TileShape.at, so an edit is already in the
  -- shape by the time it arrives -- and the editor and the game are then
  -- honouring the same edit through the same code, which is the only way the
  -- two pictures can be trusted to agree.
  if ctx.modAt then
    local shape = ctx.modAt(cx, cy)
    if shape then
      local h = tonumber(shape.h) or 0
      -- A COORDINATE OVERRIDE OUTRANKS THE RUN, here as in the mesher.
      -- Structures drops the run over an overridden tile, but this fallback
      -- asks for the run separately -- so without the same test the editor's
      -- own picture would keep showing the building's height on a tile the
      -- game now draws at the height that was typed in.
      local run = (not shape.override) and ctx.modRun
                  and ctx.modRun(cx, cy) or nil
      if run then
        h = run
      elseif ctx.classH then
        -- THE PROFILE PANEL'S OWN CLASS HEIGHTS, on top of the mod's answer.
        -- The mod resolves what a cell IS; this is the reader saying how tall
        -- that class stands in this tileset, and without it a height changed
        -- on the VOXELS tab moved a number in a panel and nothing else.
        --
        -- Only where there is NO measured run. A run is how tall a drawn
        -- building actually is -- Structures measured it from the artwork --
        -- and a class default is what the cell would have been without one.
        -- Letting the default overrule the measurement would flatten every
        -- house on the map the moment `wall` was nudged by two pixels.
        local over = ctx.classH[shape.class or ""]
        if over then h = over end
      end
      return h, shape.class or "wall", shape.art
    end
  end

  local tileKey = (cx * 2) .. "," .. (cy * 2)
  local o = ctx.tileEdits and ctx.tileEdits[tileKey]
  if not o then o = ctx.cellEdits and ctx.cellEdits[cx .. "," .. cy] end
  if o then
    local spec = ctx.info[o.art or ""]
    -- THIRD RETURN IS THE ART. It used to be an unread `authored` flag, and
    -- leaving the boolean there once the caller started reading the slot made
    -- every overridden cell fold as a plain box -- a `post` pinned by hand
    -- came out as a crate.
    return tonumber(o.h) or (spec and spec.h) or 0, o.art or "ground",
           spec and spec.art or nil
  end
  -- TILE PINS FIRST, then the collision class, then the cell rules. That is
  -- TileShape's order and the order matters: a pin is the mod stating what its
  -- own drawing IS, and it outranks anything derived from where the drawing
  -- happens to sit. Without this every hand-pinned tile -- the furniture in
  -- every interior -- resolved by walkability instead and came out flat floor
  -- or a 16px wall, which is what "not the actual height" was.
  --
  -- The cell's BOTTOM-LEFT tile is the one asked about, because that is the
  -- tile the engine judges a cell by (see the profile's own note on why rules
  -- 2 and 3 work at cell granularity).
  local class = nil
  if ctx.pins and ctx.tileOf then
    local tile = ctx.tileOf(cx, cy)
    if tile then class = ctx.pins[tile] end
  end
  local cls = ctx.classOf(cx, cy)
  class = class or (ctx.profileColl and cls and ctx.profileColl[cls]) or nil
  if not class then
    -- TileShape's rules 2 and 3, ASKED OF THE ENGINE rather than guessed.
    --
    -- The first version tested the collision byte by hand -- $00, $01 and the
    -- entrance range as ground, everything else as wall. Gen 2 has far more
    -- walkable classes than that, so most of a map's floor came out as 16px
    -- walls: a route meshed into a maze and an interior into a checkerboard of
    -- blocks. The tileset ships its own walkable list and Map answers from it,
    -- which is the same source the player's feet use.
    local water = ctx.isWater and ctx.isWater(cx, cy)
    local walk = ctx.isWalkable and ctx.isWalkable(cx, cy)
    if water == true then
      class = "water"
    elseif walk == true then
      class = "ground"
    elseif walk == nil then
      -- UNKNOWN, not "no". The wrappers answer nil when Map cannot be asked at
      -- all -- a partial import, a tileset with no walkable list. Treating that
      -- as "not walkable" turned every cell of every such map into a 16px
      -- wall, which is a solid grey box where a world should be. The coarse
      -- byte test is a poor answer; a map made entirely of walls is a worse
      -- one, and it looks like the viewport is broken rather than the import.
      if cls == nil then class = "void"
      elseif cls == 0x00 or cls == 0x01 or (cls >= 0x60 and cls <= 0x7F) then
        class = "ground"
      else
        class = "wall"
      end
    elseif cls == nil then
      class = "void"
    else
      class = "wall"
    end
  end
  local spec = ctx.info[class]
  -- A MEASURED height beats the class default, but ONLY for the class the
  -- fallback hands out. `wall` is what an unauthored solid becomes, so that is
  -- the one that should rise to whatever it is drawn as; a pinned class or a
  -- collision-class pin is a STATED answer and keeps its own height.
  if class == "wall" and ctx.structH then
    local h = ctx.structH(cx, cy)
    if h and h > 0 then return h, class, spec and spec.art or nil end
  end
  return (spec and spec.h) or 0, class, spec and spec.art or nil
end

Viewport3D.heightAt = heightAt

local function pushQuad(verts, map, tex, shade, alpha, p1, p2, p3, p4)
  local base = #verts
  local c = math.floor(shade * 255)
  local a = math.floor((alpha or 1) * 255)
  local corners = { p1, p2, p3, p4 }
  local uv = { { tex[1], tex[2] }, { tex[3], tex[2] },
               { tex[3], tex[4] }, { tex[1], tex[4] } }
  for i = 1, 4 do
    verts[#verts + 1] = { corners[i][1], corners[i][2], corners[i][3],
                          uv[i][1], uv[i][2], c, c, c, a }
  end
  map[#map + 1] = base + 1; map[#map + 1] = base + 2; map[#map + 1] = base + 3
  map[#map + 1] = base + 1; map[#map + 1] = base + 3; map[#map + 1] = base + 4
end

-- Build the whole visible mesh once. Rebuilt when the map, the edits or the
-- window change -- never per frame: a Kanto route is 1440 cells and roughly
-- twenty thousand triangles, which is nothing to draw and a great deal to
-- rebuild sixty times a second.
-- `opts.countOnly` builds the vertex list and returns the counts without
-- touching the GPU, which is how the mesh topology gets tested at all: a
-- headless run has no love.graphics to make a mesh with.
function Viewport3D.build(S, map, opts)
  opts = opts or {}
  if not opts.countOnly and not Viewport3D.available() then return nil end
  local renderer = map.renderer
  local image = renderer and renderer.image
  if not image then return nil end
  local iw, ih = image:getDimensions()
  local tileset = map.tileset
  local perRow = tileset.tilesPerRow or math.max(1, math.floor(iw / 8))

  local def = map.def
  -- ONE ANSWER TO "WHICH MOD", USED BY EVERY READ BELOW. See the note at the
  -- resolver: nil is read differently by VoxelClasses and ModShapes, so it is
  -- resolved here and never passed on.
  local sourceId = VoxelClasses.resolveId(S.voxelSource)
  -- `S.voxelSource` names which installed mod's voxel data to resolve against.
  -- Two mods will disagree on purpose -- a class list is authored content --
  -- so the editor has to be told whose world it is showing.
  local _, info = VoxelClasses.list(def.tileset, sourceId)
  local okProfile, profile = pcall(function()
    local src = VoxelClasses.sourceFor(sourceId)
    return src and src.profile and require(src.profile) or nil
  end)
  profile = okProfile and profile or nil
  local coll = tileset.collision

  local pins = {}
  local okPins, gotPins = pcall(VoxelClasses.tilePins, def.tileset, sourceId)
  if okPins and type(gotPins) == "table" then pins = gotPins end

  -- The tileset's RENDER OPTIONS, resolved: schema default, then the profile,
  -- then the editor's own change. Only the ones this mesher actually models
  -- are read here -- see VoxelClasses.OPTIONS, where a row says whether the
  -- preview honours it. Reading one it does not model would be worse than not
  -- reading it: the panel would show a control that appears to work.
  -- NOT `opts`: that is this function's own parameter, and shadowing it here
  -- made `opts.countOnly` read the render options instead -- so every build
  -- took the draw path, found no canvas under the test harness, and returned
  -- nil. A whole suite went red on a name.
  local renderOpts = {}
  local okOpts, gotOpts = pcall(VoxelClasses.options, def.tileset, sourceId)
  if okOpts and type(gotOpts) == "table" then
    for _, o in ipairs(gotOpts) do renderOpts[o.key] = o.value end
  end

  -- Solidity for the structure pass: a cell is part of a structure when it is
  -- neither walkable nor water. Asked once per cell and memoised -- the run
  -- walk visits every tile of every column and would otherwise ask the engine
  -- four times per cell.
  local solidMemo = {}
  local function solidCell(cx, cy)
    local key = cy * (def.width * 2) + cx
    local v = solidMemo[key]
    if v ~= nil then return v end
    local okW, water = pcall(map.isWaterCell, map, cx, cy)
    local okK, walk = pcall(map.isWalkableCell, map, cx, cy)
    -- Unknown counts as NOT solid. A map whose walkability cannot be asked
    -- would otherwise become one continuous structure and rise to the cap.
    v = (okW and okK) and not (water or walk) or false
    solidMemo[key] = v
    return v
  end

  local structOK, structH, structW2 = pcall(Viewport3D.structureHeights,
                                            map, solidCell)
  if not structOK then structH, structW2 = nil, nil end

  -- THE MOD'S OWN RESOLVER, if the selected source ships one. This is the
  -- difference between showing what the game draws and showing this file's
  -- opinion of it; every branch below it is the fallback for when it cannot be
  -- had. The reason is kept and published, because "the viewport is guessing"
  -- is something the reader has to be able to find out.
  --
  -- RESOLVED TO A CONCRETE ID FIRST. `S.voxelSource` is nil until the reader
  -- picks one by hand, and nil does not mean the same thing on both sides of
  -- this call: VoxelClasses reads it as "whichever mod is installed" (every
  -- other line in this function went through that), while ModShapes reads it
  -- as "no mod at all". So the class names came from the mod and the shapes
  -- did not, and 3D opened on built-in geometry wearing the mod's vocabulary.
  local resolver, resolverWhy = nil, nil
  if not opts.noMod then
    resolver, resolverWhy = ModShapes.resolver(map, sourceId)
  end
  -- The reader's own per-tileset class heights, from the profile panel. Read
  -- through VoxelClasses because that is where the editor's store is bound;
  -- this file has no idea which store or which game is open, and should not.
  local classH = nil
  do
    local okO, over = pcall(VoxelClasses.overrides, def.tileset, sourceId)
    if okO and type(over) == "table" and type(over.heights) == "table"
       and next(over.heights) ~= nil then
      classH = over.heights
    end
  end

  Viewport3D.lastResolver = resolver and resolver.id or nil
  Viewport3D.lastRun = (resolver and resolver.runHeight) and true or false
  Viewport3D.lastResolverWhy = resolver and (resolver.structures and nil
    or ModShapes.lastError) or resolverWhy

  local ctx = {
    info = info,
    pins = pins,
    -- the cell's bottom-left TILE, the one the engine judges a cell by
    modAt = resolver and function(cx, cy)
      return resolver.at(cx * 2, cy * 2 + 1)
    end or nil,
    modRun = (resolver and resolver.runHeight) and function(cx, cy)
      return resolver.runHeight(cx * 2, cy * 2 + 1)
    end or nil,
    -- ONLY the editor's own overrides, never the profile's: the mod already
    -- applied its own per-tileset heights when it resolved the shape, and
    -- applying them a second time here would be this file having an opinion
    -- about the mod's data again.
    classH = classH,
    -- the cell's bottom-left TILE is the one its run is measured on, the same
    -- tile the collision and the pins are read from
    structH = structH and function(cx, cy)
      return structH[(cy * 2 + 1) * structW2 + (cx * 2)]
    end or nil,
    -- the cell's bottom-left tile: cy * 2 + 1 is the lower tile row, the same
    -- one TileRenderer redraws for grass occlusion and the one collision reads
    tileOf = function(cx, cy)
      local ok, t = pcall(map.tileAt, map, cx * 2, cy * 2 + 1)
      return ok and t or nil
    end,
    profileColl = type(profile) == "table" and profile.collision or nil,
    cellEdits = def.voxelEdits,
    tileEdits = def.voxelTileEdits,
    -- Map's own answers, wrapped so heightAt never has to hold a map. Both are
    -- pcall'd: a partially imported tileset can leave either raising, and a
    -- viewport that will not open is a worse answer than one that reads a few
    -- cells as wall.
    -- nil means "cannot be asked", which is NOT the same as false. See the
    -- fallback in heightAt: conflating the two makes a whole map of walls.
    isWater = function(cx, cy)
      if type(map.isWaterCell) ~= "function" then return nil end
      local ok, r = pcall(map.isWaterCell, map, cx, cy)
      if not ok then return nil end
      return r and true or false
    end,
    isWalkable = function(cx, cy)
      if type(map.isWalkableCell) ~= "function" then return nil end
      local ok, r = pcall(map.isWalkableCell, map, cx, cy)
      if not ok then return nil end
      return r and true or false
    end,
    classOf = function(cx, cy)
      if not (coll and def.blocks) then return nil end
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local id
      if bx < 0 or by < 0 or bx >= def.width or by >= def.height then
        id = def.borderBlock or 0
      else
        id = def.blocks[by * def.width + bx + 1] or 0
      end
      return coll[id * 4 + (cx % 2) + (cy % 2) * 2 + 1]
    end,
  }

  local W, H = map.widthCells, map.heightCells
  -- Both, in one pass: the class decides HOW a cell is meshed (flat quad or
  -- carved silhouette) and the height decides how tall. Resolving them
  -- separately would run the override lookup twice per cell.
  -- `arts` is the mod's own fold for the cell, kept beside the class rather
  -- than looked up from it. A mod may resolve a class this editor's table has
  -- never heard of, and rediscovering the fold from the name would hand that
  -- cell the default upright box -- a tree drawn as a crate.
  local heights, classes, arts = {}, {}, {}
  for cy = 0, H - 1 do
    for cx = 0, W - 1 do
      local h, class, art = heightAt(ctx, cx, cy)
      heights[cy * W + cx] = h
      classes[cy * W + cx] = class
      arts[cy * W + cx] = art
    end
  end

  -- ------------------------------------------------------------------------
  -- THE MOD'S OWN GEOMETRY, when it can be had
  -- ------------------------------------------------------------------------
  --
  -- Everything from here to the end of the cell loop is the editor building
  -- the world out of boxes and flat plates. That was never going to look like
  -- the game: a tree canopy is a hull cut from the drawing's own outline and
  -- rounded in depth, a staircase is real treads, a bookcase is a collapsed
  -- rank with its panes sunk behind their frame, a building's face folds the
  -- artwork upright band by band. None of that follows from a height, and all
  -- of it came out as a crate.
  --
  -- lib/ChunkMesher.lua builds every one of those, and has a synchronous
  -- GPU-free entry point meant for callers like this one. So when the selected
  -- mod ships it, the vertices below are the GAME'S, converted only in colour
  -- format -- the mod carries one shade per vertex, this mesh carries RGBA
  -- bytes, and the geometry, the winding and the UVs are untouched.
  --
  -- The heights and classes resolved above are still computed and still kept:
  -- they are what the selection marker stands on, what the ray-pick tests and
  -- what the census reports. Only the geometry is handed over.
  local verts, vmap = {}, {}
  local modGeo = nil
  if resolver then
    local mv, mi = ModShapes.geometry(map, sourceId)
    if mv and mi and #mv > 0 then
      for k = 1, #mv do
        local q = mv[k]
        local shade = tonumber(q[6]) or 1
        local c = math.max(0, math.min(255, math.floor(shade * 255 + 0.5)))
        verts[k] = { q[1], q[2], q[3], q[4], q[5], c, c, c, 255 }
      end
      for k = 1, #mi do vmap[k] = mi[k] end
      modGeo = true
    end
  end
  Viewport3D.lastGeometry = modGeo and (sourceId or "?") or nil

  local halfTexel = 0.5

  -- A CEILING, because the worst case is not the typical one. A cell carves to
  -- at most 256 columns, and a heavily dithered drawing can leave them
  -- isolated -- every pixel its own island with four exposed sides. That is
  -- 1280 quads for one cell where a solid blob is eighty, and a route of them
  -- would be millions of triangles built one at a time on the main thread.
  --
  -- Stopping is the honest failure: the build returns what it has plus the
  -- fact that it stopped, and the panel says so. Silently thinning the mesh
  -- would show a map with holes in it and no reason given.
  local VERT_BUDGET = 900000
  local truncated = false

  -- UV for one 8px TILE, and for one PIXEL inside the atlas. The pixel form
  -- takes the texel's own centre: a voxel is one colour, and sampling its
  -- middle is the only way to get that colour rather than a blend with its
  -- neighbour.
  local function tileUV(tile)
    local tx = (tile % perRow) * 8
    local ty = math.floor(tile / perRow) * 8
    return { (tx + halfTexel) / iw, (ty + halfTexel) / ih,
             (tx + 8 - halfTexel) / iw, (ty + 8 - halfTexel) / ih }
  end
  local function pixelUV(tile, px, py)
    local tx = (tile % perRow) * 8 + px
    local ty = math.floor(tile / perRow) * 8 + py
    local u = (tx + 0.5) / iw
    local v = (ty + 0.5) / ih
    return { u, v, u, v }
  end

  -- THE ARTWORK'S PIXELS, for the silhouette. Read from the source image data
  -- rather than from the renderer's atlas, because a love Image cannot be read
  -- back -- but the mesh is TEXTURED with the renderer's atlas, so the shapes
  -- come from here and the colours come from whatever the 2D view is showing.
  -- That keeps a GBC-recoloured world looking like itself in 3D.
  local okData, atlas = pcall(function()
    return require("src.render.Assets").imageData(tileset.image)
  end)
  atlas = okData and atlas or nil
  local atlasW, atlasH = 0, 0
  if atlas then atlasW, atlasH = atlas:getDimensions() end

  local maskCache = {}
  local function cellMask(cx, cy)
    if not atlas then return nil end
    local key = cx .. "," .. cy
    local cached = maskCache[key]
    if cached ~= nil then return cached or nil end
    local tiles = {}
    for row = 0, 1 do
      for col = 0, 1 do
        tiles[row * 2 + col] = map:tileAt(cx * 2 + col, cy * 2 + row) or 0
      end
    end
    local m = silhouette(function(px, py)
      local tile = tiles[math.floor(py / 8) * 2 + math.floor(px / 8)] or 0
      local ax = (tile % perRow) * 8 + (px % 8)
      local ay = math.floor(tile / perRow) * 8 + (py % 8)
      if ax >= atlasW or ay >= atlasH then return 0, 0, 0, 0 end
      return atlas:getPixel(ax, ay)
    end)
    maskCache[key] = m or false
    return m
  end

  -- A run of pixels along X at one height, as one quad. Merging matters: a
  -- 16x16 cell is 256 columns and a route is 1440 cells, so unmerged tops
  -- alone would be a third of a million quads. A run never crosses an 8px
  -- tile boundary, because two neighbouring tiles are not neighbours in the
  -- atlas and a single quad cannot sample both.
  local function pushRun(y, z0, x0, x1, tile, py, shade)
    local u0 = ((tile % perRow) * 8 + (x0 % 8) + halfTexel) / iw
    local u1 = ((tile % perRow) * 8 + (x1 % 8) + 1 - halfTexel) / iw
    local v = (math.floor(tile / perRow) * 8 + py + 0.5) / ih
    local c = math.floor(shade * 255)
    local base = #verts
    verts[#verts + 1] = { x0,     y, z0,     u0, v, c, c, c, 255 }
    verts[#verts + 1] = { x1 + 1, y, z0,     u1, v, c, c, c, 255 }
    verts[#verts + 1] = { x1 + 1, y, z0 + 1, u1, v, c, c, c, 255 }
    verts[#verts + 1] = { x0,     y, z0 + 1, u0, v, c, c, c, 255 }
    vmap[#vmap + 1] = base + 1; vmap[#vmap + 1] = base + 2
    vmap[#vmap + 1] = base + 3; vmap[#vmap + 1] = base + 1
    vmap[#vmap + 1] = base + 3; vmap[#vmap + 1] = base + 4
  end

  -- HOW A CLASS IS BUILT. The profile is explicit: the mesher "voxelizes small
  -- props per pixel at their real drawn height with transparency, and raises
  -- EVERYTHING ELSE as a volume". The first version of this carved everything
  -- that was not flat, which is the opposite -- so a house was eaten by its
  -- own dithering and a wall came out as a lace curtain. A wall is a wall.
  --
  --   flat    one quad on the ground        ground, water, void
  --   volume  a box, art on top, folded sides   wall, tree, roof, terrace...
  --   carve   per-pixel columns, gaps kept  fences, plants, signs, shelves
  local FORM = {
    flat = "flat", grass = "flat", flower = "flat",
    top = "volume", upright = "volume", stair = "volume",
    billboard = "carve", post = "carve", cylinder = "carve",
    canopy = "carve", planter = "carve", bookcase = "carve",
    relief = "carve",
  }

  for cy = 0, H - 1 do
    if modGeo or truncated then break end
    for cx = 0, W - 1 do
      if #verts > VERT_BUDGET then truncated = true break end
      local h = heights[cy * W + cx] or 0
      local class = classes[cy * W + cx]
      local spec = info[class or ""]
      local artOf = arts[cy * W + cx] or (spec and spec.art) or "upright"
      local form = FORM[artOf] or "volume"
      local x0, z0 = cx * CELL, cy * CELL

      -- The height of the ground a carved prop stands ON: the lowest of its
      -- four neighbours, so a plant on a terrace sits on the terrace rather
      -- than growing out of the floor two courses below it.
      local function groundUnder()
        local g = nil
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx2, nz2 = cx + d[1], cy + d[2]
          if nx2 >= 0 and nz2 >= 0 and nx2 < W and nz2 < H then
            local nh = heights[nz2 * W + nx2] or 0
            local nc = classes[nz2 * W + nx2]
            local nart = arts[nz2 * W + nx2]
              or (info[nc or ""] or {}).art or "upright"
            local nform = FORM[nart] or "volume"
            if nform == "flat" and (g == nil or nh < g) then g = nh end
          end
        end
        return g or 0
      end

      local base = (form == "carve") and groundUnder() or 0
      local top = (form == "flat") and h or math.max(h, base)

      -- THE TOP. Always four 8px quads, one per tile: a cell's four tiles are
      -- four separate places in the atlas and cannot be one quad.
      local topY = (form == "carve") and base or top
      for row = 0, 1 do
        for col = 0, 1 do
          local tile = map:tileAt(cx * 2 + col, cy * 2 + row)
          if tile then
            local u = tileUV(tile)
            local ax, az = x0 + col * 8, z0 + row * 8
            pushQuad(verts, vmap, u, FACE_SHADE.top, 1,
              { ax, topY, az }, { ax + 8, topY, az },
              { ax + 8, topY, az + 8 }, { ax, topY, az + 8 })
          end
        end
      end

      if form == "volume" and top > 0 then
        -- SIDES, only toward a LOWER neighbour: a face between two blocks of
        -- the same height is never seen and is most of the mesh.
        --
        -- The artwork folds up the face 8px band at a time, alternating the
        -- drawing's two tile rows -- TileShape's own rule, and why a two-course
        -- wall reads as the wall drawn twice rather than its top row stretched.
        local function nh(dx, dz)
          local nx2, nz2 = cx + dx, cy + dz
          if nx2 < 0 or nz2 < 0 or nx2 >= W or nz2 >= H then return 0 end
          return heights[nz2 * W + nx2] or 0
        end
        local function bandedFace(dx, dz, shade, tileFor, corners)
          local bottom = nh(dx, dz)
          if bottom >= top then return end
          local bands = math.max(1, math.ceil((top - bottom) / 8))
          for b = 0, bands - 1 do
            local y0 = bottom + b * 8
            local y1 = math.min(top, y0 + 8)
            for i = 0, 1 do
              local tile = tileFor(i, b)
              if tile then
                local p = corners(i, y0, y1)
                pushQuad(verts, vmap, tileUV(tile), shade, 1, p[1], p[2], p[3], p[4])
              end
            end
          end
        end
        local function rowFor(b) return 1 - (b % 2) end

        bandedFace(0, 1, FACE_SHADE.south,
          function(i, b) return map:tileAt(cx * 2 + i, cy * 2 + rowFor(b)) end,
          function(i, y0, y1)
            local ax = x0 + i * 8
            return { { ax, y1, z0 + CELL }, { ax + 8, y1, z0 + CELL },
                     { ax + 8, y0, z0 + CELL }, { ax, y0, z0 + CELL } }
          end)
        bandedFace(0, -1, FACE_SHADE.north,
          function(i, b) return map:tileAt(cx * 2 + i, cy * 2 + rowFor(b)) end,
          function(i, y0, y1)
            local ax = x0 + i * 8
            return { { ax + 8, y1, z0 }, { ax, y1, z0 },
                     { ax, y0, z0 }, { ax + 8, y0, z0 } }
          end)
        bandedFace(1, 0, FACE_SHADE.east,
          function(i, b) return map:tileAt(cx * 2 + rowFor(b), cy * 2 + i) end,
          function(i, y0, y1)
            local az = z0 + i * 8
            return { { x0 + CELL, y1, az + 8 }, { x0 + CELL, y1, az },
                     { x0 + CELL, y0, az }, { x0 + CELL, y0, az + 8 } }
          end)
        bandedFace(-1, 0, FACE_SHADE.west,
          function(i, b) return map:tileAt(cx * 2 + rowFor(b), cy * 2 + i) end,
          function(i, y0, y1)
            local az = z0 + i * 8
            return { { x0, y1, az }, { x0, y1, az + 8 },
                     { x0, y0, az + 8 }, { x0, y0, az } }
          end)

      elseif form == "carve" and h > 0 then
        -- A STANDING PROP: the drawing STOOD UP, not laid down.
        --
        -- This is the difference between a fence and a bed of spikes. A cell's
        -- artwork for a prop is a FRONT ELEVATION -- the picture you see
        -- looking at the thing -- so its pixel rows are HEIGHT, not depth. The
        -- first version read them as a top-down footprint and extruded each
        -- pixel upward, which turned a row of pickets into a row of needles
        -- one pixel square and sixteen tall, and a plant into a hairbrush.
        --
        -- So: pixel (px, py) becomes a voxel at x = px, y = the drawing's own
        -- row counted up from the ground, z = a band `depth` voxels thick
        -- centred in the cell. The silhouette still decides which pixels
        -- exist, which is what keeps the daylight between the pickets.
        local mask = cellMask(cx, cy)
        if mask then
          local depth = PINNED_DEPTH[class or ""] or DEFAULT_DEPTH
          -- PLANTER SPRAY. A potted plant's crown is a flat spray of leaves; a
          -- TREE's crown is a ball, and capping one to the other's depth is
          -- exactly what makes a planter read as thin. The mod switches
          -- between the two with `planter_spray` per tileset, so a tileset
          -- that borrows the class for a real tree turns it off -- and the
          -- preview has to follow, or the editor shows spray where the game
          -- draws a ball.
          if class == "planter" or class == "canopy" then
            depth = renderOpts.planter_spray == false
                    and CELL or PLANTER_SPRAY_DEPTH
          end
          depth = math.max(1, math.min(CELL, depth))
          local zNear = z0 + (CELL - depth) / 2
          local zFar = zNear + depth
          -- The drawing is 16 rows; the class height says how tall those rows
          -- stand. Scaled rather than assumed 1:1 so an 8px-high class does
          -- not draw a 16-unit prop.
          local rowH = h / 16

          for py = 0, 15 do
            for px = 0, 15 do
              if mask[py * 16 + px] then
                local tile = map:tileAt(cx * 2 + math.floor(px / 8),
                                        cy * 2 + math.floor(py / 8))
                if tile then
                  local uv = pixelUV(tile, px % 8, py % 8)
                  local wx = x0 + px
                  local yTop = base + (16 - py) * rowH
                  local yBot = base + (15 - py) * rowH
                  local function solid(dx, dy)
                    local nx2, ny2 = px + dx, py + dy
                    if nx2 < 0 or ny2 < 0 or nx2 > 15 or ny2 > 15 then return false end
                    return mask[ny2 * 16 + nx2] and true or false
                  end
                  -- SOUTH and NORTH are the two big faces: the drawing itself,
                  -- seen from the front and from behind. Always drawn -- the
                  -- prop is a thin plate and both of its faces are outside.
                  pushQuad(verts, vmap, uv, FACE_SHADE.south, 1,
                    { wx, yTop, zFar }, { wx + 1, yTop, zFar },
                    { wx + 1, yBot, zFar }, { wx, yBot, zFar })
                  pushQuad(verts, vmap, uv, FACE_SHADE.north, 1,
                    { wx + 1, yTop, zNear }, { wx, yTop, zNear },
                    { wx, yBot, zNear }, { wx + 1, yBot, zNear })
                  -- The edges, only where the drawing stops -- which is what
                  -- gives a picket its thickness and a gap its emptiness.
                  if not solid(1, 0) then
                    pushQuad(verts, vmap, uv, FACE_SHADE.east, 1,
                      { wx + 1, yTop, zFar }, { wx + 1, yTop, zNear },
                      { wx + 1, yBot, zNear }, { wx + 1, yBot, zFar })
                  end
                  if not solid(-1, 0) then
                    pushQuad(verts, vmap, uv, FACE_SHADE.west, 1,
                      { wx, yTop, zNear }, { wx, yTop, zFar },
                      { wx, yBot, zFar }, { wx, yBot, zNear })
                  end
                  if not solid(0, -1) then
                    pushQuad(verts, vmap, uv, FACE_SHADE.top, 1,
                      { wx, yTop, zNear }, { wx + 1, yTop, zNear },
                      { wx + 1, yTop, zFar }, { wx, yTop, zFar })
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- WHAT THE BUILD ACTUALLY DECIDED, carried out with the mesh.
  --
  -- The census is the single most useful number when a map looks wrong: "64
  -- cells, all of them wall" says the walkability lookup failed, and a floor
  -- that resolved to wall is a raised slab with sides -- which is exactly what
  -- a room looks like when it is floating above its own grid. The bounding box
  -- says whether the geometry is where the camera thinks it is.
  local census, minB, maxB = {}, { 1e30, 1e30, 1e30 }, { -1e30, -1e30, -1e30 }
  for i = 0, W * H - 1 do
    local c = classes[i] or "?"
    census[c] = (census[c] or 0) + 1
  end
  for _, vt in ipairs(verts) do
    for k = 1, 3 do
      if vt[k] < minB[k] then minB[k] = vt[k] end
      if vt[k] > maxB[k] then maxB[k] = vt[k] end
    end
  end
  if #verts == 0 then minB, maxB = { 0, 0, 0 }, { 0, 0, 0 } end
  local top = {}
  for c, n in pairs(census) do top[#top + 1] = { c, n } end
  table.sort(top, function(a, b) return a[2] > b[2] end)

  if opts.countOnly then
    -- `dumpTo` writes the raw vertex and index lists out so the mesh can be
    -- rasterised outside LOVE and LOOKED AT. That is not a debugging luxury:
    -- this viewport shipped four times without ever drawing a frame, because
    -- every test covered a part and none covered the picture.
    if opts.dumpTo then
      local f = io.open(opts.dumpTo, "w")
      if f then
        f:write("v ", #verts, " i ", #vmap, "\n")
        for _, vt in ipairs(verts) do
          f:write(table.concat(vt, " "), "\n")
        end
        f:write("--\n")
        for _, ix in ipairs(vmap) do f:write(ix, "\n") end
        f:close()
      end
    end
    return { heights = heights, classes = classes, W = W, H = H,
             count = #vmap / 3, verts = #verts, truncated = truncated,
             carved = atlas ~= nil, modGeo = modGeo or false,
             census = top, bmin = minB, bmax = maxB }
  end
  if #verts == 0 then return nil end
  local ok, mesh = pcall(love.graphics.newMesh, FORMAT, verts, "triangles", "static")
  if not ok or not mesh then return nil end
  pcall(mesh.setVertexMap, mesh, vmap)
  pcall(mesh.setTexture, mesh, image)
  -- `texture` is kept beside the mesh so the SOLID shading mode can take the
  -- atlas off and put the same one back. Reaching for map.renderer.image at
  -- that point would work today and break the first time a build outlives the
  -- renderer it came from.
  return { mesh = mesh, texture = image, heights = heights, classes = classes,
           W = W, H = H, count = #vmap / 3, verts = #verts,
           truncated = truncated, carved = atlas ~= nil,
           modGeo = modGeo or false,
           census = top, bmin = minB, bmax = maxB }
end

-- ---------------------------------------------------------------------------
-- drawing
-- ---------------------------------------------------------------------------

-- `canvasFailed` (declared with the shader state above) is set once a depth
-- canvas has been asked for and refused, so the reason can be reported rather
-- than the viewport just staying blank.
local depthCanvas, colorCanvas, canvasW, canvasH

local DEPTH_FORMATS = { "depth24", "depth24stencil8", "depth32f", "depth16" }

-- The display's pixel-to-unit ratio. A canvas is allocated in PIXELS while
-- everything the panel measures -- the viewport rect, the draw position -- is
-- in DPI-scaled units. On a 125% or 150% Windows display those differ, and a
-- canvas made at the viewport's unit size is short of pixels: it comes out
-- soft, and every edge in it lands between two real pixels.
local function dpiScale()
  if love.window and love.window.getDPIScale then
    local ok, d = pcall(love.window.getDPIScale)
    if ok and type(d) == "number" and d > 0 then return d end
  end
  return 1
end

Viewport3D.dpiScale = dpiScale

local function ensureTargets(w, h)
  canvasFailed = false
  local dpi = dpiScale()
  w = math.max(1, math.floor(w * dpi))
  h = math.max(1, math.floor(h * dpi))
  if colorCanvas and canvasW == w and canvasH == h then return true end
  if colorCanvas and colorCanvas.release then pcall(colorCanvas.release, colorCanvas) end
  if depthCanvas and depthCanvas.release then pcall(depthCanvas.release, depthCanvas) end
  colorCanvas, depthCanvas = nil, nil
  local ok, c = pcall(love.graphics.newCanvas, w, h)
  if not ok or not c then canvasFailed = true; return false end

  -- A hand-made depth attachment, IF one of the formats takes. When none does,
  -- `d` stays nil and the draw asks LOVE for a temporary depth buffer instead
  -- -- which is not a degraded mode, just a different way of getting one.
  -- Only a target with no depth AT ALL is a failure, and that is checked by
  -- trying the automatic form here rather than discovering it mid-frame.
  local d
  for _, format in ipairs(DEPTH_FORMATS) do
    local ok2, made = pcall(love.graphics.newCanvas, w, h,
                            { format = format, readable = false })
    if ok2 and made then d = made break end
  end
  if not d then
    local okAuto = pcall(function()
      love.graphics.setCanvas({ c, depth = true })
      love.graphics.setCanvas()
    end)
    if not okAuto then
      pcall(love.graphics.setCanvas)
      pcall(c.release, c)
      canvasFailed = true
      return false
    end
  end
  colorCanvas, depthCanvas, canvasW, canvasH = c, d, w, h
  return true
end

-- The camera, from the state the panel keeps: `pvAngle` is the pitch away from
-- straight down (the game's ladder), `pvYaw` the orbit, `pvDist` the distance.
-- The camera's own frame: forward, right and up, from the orbit angles. Every
-- caller that needs a direction -- panning, ray-building, the axis gizmo --
-- wants the same three vectors, and deriving them twice is how they drift.
function Viewport3D.basis(S)
  -- Clamped clear of both poles. `up` is +Y, and at a pitch of exactly 0 or
  -- 90 the cross product that builds `right` degenerates to a zero vector --
  -- the view matrix comes out full of NaNs and the viewport goes black with
  -- nothing logged.
  local pitch = math.rad(math.max(1.5, math.min(88.5, S.pvAngle or 35)))
  local yaw = S.pvYaw or 0
  local sp, cp = math.sin(pitch), math.cos(pitch)
  local sy, cy2 = math.sin(yaw), math.cos(yaw)
  -- forward = from the eye toward the focus
  local fx, fy, fz = -sp * sy, -cp, -sp * cy2
  local rx, ry, rz = normalise(-fz, 0, fx)
  local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx
  return fx, fy, fz, rx, ry, rz, ux, uy, uz
end

-- THE SAME MATRIX, FLIPPED IN Y, FOR RENDERING INTO A CANVAS.
--
-- LOVE's own TransformProjectionMatrix carries a Y flip when a canvas is
-- bound: a GL framebuffer's row zero is at the BOTTOM, and the canvas is later
-- drawn as an image whose row zero is at the TOP, so something has to invert
-- and LOVE does it in the projection. A shader that returns raw clip space --
-- which this one does, because it has its own camera -- never receives that,
-- so everything it draws lands vertically mirrored.
--
-- It is not subtle once seen and it is invisible until then: a mirrored world
-- still looks like a world. The floor filled the top of the view and the
-- furniture hung below it, which reads as the map standing on end rather than
-- as the image being upside down.
--
-- Kept OUT of `camera` on purpose. The grid, the axes and the selection box
-- are drawn to the SCREEN after the canvas is blitted, and they need the
-- unflipped matrix; flipping in one place and not the other is what would put
-- the furniture and the world on opposite sides of the view.
function Viewport3D.canvasMatrix(vp)
  local out = {}
  for i = 1, 16 do out[i] = vp[i] end
  -- Row 1 of a column-major mat4 is elements 2, 6, 10, 14: clip-space Y.
  out[2], out[6], out[10], out[14] = -vp[2], -vp[6], -vp[10], -vp[14]
  return out
end

function Viewport3D.focusOf(S, built)
  local f = S.pvFocus
  return (f and f.x) or (built.W * CELL / 2),
         (f and f.y) or 0,
         (f and f.z) or (built.H * CELL / 2)
end

function Viewport3D.camera(S, built, w, h)
  local fx, fy, fz = Viewport3D.basis(S)
  local focusX, focusY, focusZ = Viewport3D.focusOf(S, built)
  local dist = S.pvDist or (math.max(built.W, built.H) * CELL * 0.7)

  local ex, ey, ez = focusX - fx * dist, focusY - fy * dist, focusZ - fz * dist
  local view = matLookAt(ex, ey, ez, focusX, focusY, focusZ)

  -- THE DEPTH RANGE, SIZED TO THE SCENE.
  --
  -- near = 4, far = 20000 is a ratio of five thousand to one, and depth
  -- precision is spent almost entirely on the first few units of that: at the
  -- couple of hundred units where a map actually sits, neighbouring surfaces
  -- land on the same depth value and the buffer cannot separate them. The
  -- symptom is a floor that shimmers and swims over the walls as the camera
  -- moves -- it reads as the geometry being unstable rather than the
  -- projection being badly scaled.
  --
  -- A map is a few hundred units across, so the range is derived from the
  -- camera distance and the map's own diagonal and nothing is wasted.
  local span = math.sqrt((built.W * CELL) ^ 2 + (built.H * CELL) ^ 2)
  local far = math.max(64, dist + span * 1.5)
  local near = math.max(1, math.min(dist * 0.05, far / 500))

  local proj
  if S.pvOrtho then
    -- ORTHOGRAPHIC, sized so the same dolly distance frames the same amount of
    -- world as the perspective camera would -- otherwise every switch between
    -- the two is also a jarring zoom.
    local halfH = dist * math.tan(math.rad(45) / 2)
    local halfW = halfH * (w / math.max(1, h))
    proj = matOrtho(-halfW, halfW, -halfH, halfH, -far, far)
  else
    proj = matPerspective(math.rad(45), w / math.max(1, h), near, far)
  end
  return matMul(proj, view), { ex, ey, ez }
end

-- Move the focus across the camera's own plane -- what a pan is. In world
-- units scaled by distance, so a drag moves the same number of SCREEN pixels
-- whether the camera is inches away or across the map.
function Viewport3D.pan(S, built, dxPixels, dyPixels, viewH)
  local _, _, _, rx, ry, rz, ux, uy, uz = Viewport3D.basis(S)
  local dist = S.pvDist or 400
  local scale = (2 * dist * math.tan(math.rad(45) / 2)) / math.max(1, viewH)
  local fxp, fyp, fzp = Viewport3D.focusOf(S, built)
  S.pvFocus = {
    x = fxp - (rx * dxPixels - ux * dyPixels) * scale,
    y = fyp - (ry * dxPixels - uy * dyPixels) * scale,
    z = fzp - (rz * dxPixels - uz * dyPixels) * scale,
  }
end

-- Put the whole map (or one cell) in view. The distance is derived from the
-- field of view rather than guessed, so a 4x4 room and a 40x36 route both
-- arrive framed instead of one filling the screen and the other a speck.
function Viewport3D.frame(S, built, cell)
  if cell then
    S.pvFocus = { x = cell.cx * CELL + CELL / 2,
                  y = (built.heights and built.heights[cell.cy * built.W + cell.cx]) or 0,
                  z = cell.cy * CELL + CELL / 2 }
    S.pvDist = CELL * 6
    return
  end
  local w, d = built.W * CELL, built.H * CELL
  S.pvFocus = { x = w / 2, y = 0, z = d / 2 }
  S.pvDist = (math.max(w, d) * 0.6) / math.tan(math.rad(45) / 2)
end

-- The standard axis-aligned views, named the way every 3D tool names them.
-- The axis-aligned views go ORTHOGRAPHIC, the user view stays perspective.
--
-- That is what "flat" means and it is what every 3D tool does: a plan view
-- under a perspective camera still has the floor receding to a vanishing
-- point, so TOP looked tilted rather than flat and the ground appeared to lean
-- away. An orthographic top view is a true plan -- parallel edges stay
-- parallel and a square cell is a square.
Viewport3D.VIEWS = {
  { id = "top",   label = "TOP",   angle = 1.5,  yaw = 0,            ortho = true },
  { id = "front", label = "FRONT", angle = 88.5, yaw = 0,            ortho = true },
  { id = "side",  label = "SIDE",  angle = 88.5, yaw = math.pi / 2,  ortho = true },
  { id = "user",  label = "USER",  angle = 35,   yaw = math.rad(35), ortho = false },
}

function Viewport3D.setView(S, id)
  for _, v in ipairs(Viewport3D.VIEWS) do
    if v.id == id then
      S.pvAngle, S.pvYaw, S.pvViewName = v.angle, v.yaw, v.id
      S.pvOrtho = v.ortho and true or false
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- viewport furniture
-- ---------------------------------------------------------------------------

-- Project a world point to viewport pixels, or nil when it is behind the eye.
-- The grid, the axes and the selection box are drawn as LINES on top of the
-- rendered mesh rather than as geometry inside it, so they cost nothing to
-- rebuild and never end up inside the depth test fighting the terrain.
local function projector(vp, w, h)
  return function(wx, wy, wz)
    local cx = vp[1]*wx + vp[5]*wy + vp[9]*wz + vp[13]
    local cy = vp[2]*wx + vp[6]*wy + vp[10]*wz + vp[14]
    local cw = vp[4]*wx + vp[8]*wy + vp[12]*wz + vp[16]
    if cw <= 1e-6 then return nil end
    return (cx / cw + 1) / 2 * w, (1 - cy / cw) / 2 * h
  end
end

local function line3(project, x, y, a, b)
  local ax, ay = project(a[1], a[2], a[3])
  local bx, by = project(b[1], b[2], b[3])
  if not (ax and bx) then return end
  love.graphics.line(x + ax, y + ay, x + bx, y + by)
end

-- The ground grid, one line per map BLOCK (32 units) with a heavier line every
-- four. Blocks, not cells: a block is the unit the map data is actually in, so
-- a grid on cells would draw twice as many lines that mean half as much.
-- THE PEOPLE, IN THE 3D VIEW.
--
-- The 3D world was terrain and nothing else -- no NPCs at all -- so the one
-- question the view is best placed to answer ("does that person stand where I
-- think, on top of that ledge or behind it?") could only be asked in 2D. And
-- an editor showing a world with nobody in it does not look like the game.
--
-- SCREEN BILLBOARDS, not mesh quads. A sprite in the mesh would have to be
-- rebuilt whenever an NPC moved -- which is every drag -- and rebuilding a
-- route's mesh per frame is exactly what the build cache exists to avoid. So
-- each object is one projected point and one 2D blit, drawn after the terrain
-- and scaled by its own distance.
--
-- The cost is honest and worth naming: these do not depth-test against the
-- terrain, so an NPC behind a building shows through it. In an editor that is
-- the right trade -- you want to see the person you are about to move, and a
-- person hidden by scenery reads as one that is not there.
-- WARPS, IN THE 3D VIEW.
--
-- The 3D world had no warp markers at all, so the SHOW switch had nothing to
-- switch there and a door was invisible in the one view that shows what a
-- doorway is cut into. Drawn as a ring on the ground of the cell, in screen
-- space and after the terrain -- deliberately not depth-tested, for the same
-- reason the selection ring is not: a marker you cannot see because a wall is
-- in front of it is a marker that is not doing its job.
--
-- A blanked warp is parked off-map at -1,-1 on purpose, so it is skipped
-- rather than drawn in the corner where it would look like a real door.
local function drawWarpMarkers(project, x, y, built, S, map)
  if S.pvShowWarps == false then return end
  local def = map and map.def
  if not (def and def.warps) then return end

  love.graphics.setLineWidth(2)
  for i, wp in ipairs(def.warps) do
    if wp.x and wp.y and wp.x >= 0 and wp.y >= 0
       and wp.x < built.W and wp.y < built.H then
      local h = (built.heights and built.heights[wp.y * built.W + wp.x]) or 0
      local wx, wz = wp.x * CELL + CELL / 2, wp.y * CELL + CELL / 2
      -- ON the cell's own surface, not at zero: a door cut into a terrace is
      -- on the terrace, and a ring on the floor below it points at the wall.
      local sx, sy = project(wx, math.max(0, h), wz)
      local ex = sx and project(wx + CELL, math.max(0, h), wz)
      if sx and ex then
        local scale = math.abs(ex - sx) / CELL
        if scale > 0.02 and scale < 40 then
          local r = 8 * scale
          love.graphics.setColor(0.27, 0.59, 1, wp.added and 0.95 or 0.7)
          love.graphics.rectangle("line", x + sx - r, y + sy - r, r * 2, r * 2)
          if S.warpSelected == i then
            love.graphics.setColor(0.27, 0.59, 1, 1)
            love.graphics.rectangle("line", x + sx - r - 3, y + sy - r - 3,
                                    r * 2 + 6, r * 2 + 6)
          end
        end
      end
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

-- The ring round the object being EDITED, and nothing else.
--
-- The sprites themselves are drawn inside the depth pass (see
-- `buildBillboards`), where the terrain can occlude them the way it does in
-- the game. This marker deliberately is not: a selection you cannot see
-- because a wall is in front of it is a selection you cannot find, and finding
-- it is the entire job of a marker.
local function drawObjectMarkers(project, x, y, built, S, map)
  local def = map and map.def
  if not (def and def.objects and S.objSelected) then return end
  local o = def.objects[S.objSelected]
  if not (o and o.x and o.y) then return end

  local h = (built.heights and built.heights[o.y * built.W + o.x]) or 0
  local wx, wz = o.x * CELL + CELL / 2, o.y * CELL + CELL / 2
  local sx, sy = project(wx, math.max(0, h), wz)
  if not sx then return end
  -- Sized from the cell it stands on, measured on screen, so the ring shrinks
  -- with distance exactly as the ground does.
  local ex = project(wx + CELL, math.max(0, h), wz)
  local scale = ex and math.abs(ex - sx) / CELL or 1
  if not (scale > 0.02 and scale < 40) then return end

  love.graphics.setColor(0.24, 0.88, 0.54, 1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x + sx - 9 * scale, y + sy - 19 * scale,
                          18 * scale, 19 * scale)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, 1)
end

Viewport3D.drawObjectMarkers = drawObjectMarkers
Viewport3D.drawWarpMarkers = drawWarpMarkers

-- ---------------------------------------------------------------------------
-- the people, DEPTH-TESTED
-- ---------------------------------------------------------------------------

-- The screen billboards above were honest and wrong: they are drawn after the
-- terrain has already been blitted out of the canvas, so nothing can occlude
-- them and every NPC shows through the building it is standing behind. In a
-- town that is worse than not drawing them -- a person on the far side of the
-- Mart appears to be standing in front of it.
--
-- So they go INSIDE the depth pass, as real quads: one camera-facing rectangle
-- per object, in world space, drawn with the same shader and the same depth
-- test as the terrain. The shader already discards texels below half alpha, so
-- the cutout comes for free.
--
-- ONE MESH PER SHEET. A mesh carries one texture, and a town draws six or
-- eight different sheets -- so the objects are grouped by the image they come
-- from and each group is its own small mesh. They are rebuilt every frame
-- because a billboard faces the CAMERA, and the camera moves; a hundred
-- objects is four hundred vertices, which is nothing next to the terrain's
-- hundred thousand.
local billboardMeshes = {}

function Viewport3D.releaseBillboards()
  for _, m in pairs(billboardMeshes) do
    if m and m.release then pcall(m.release, m) end
  end
  billboardMeshes = {}
end

-- CYLINDRICAL, not spherical: a person stands up. The quad turns about Y to
-- face the camera and never tilts, so looking down on a town shows people
-- standing rather than lying on the ground like decals.
function Viewport3D.buildBillboards(S, built, map, sprite)
  local def = map and map.def
  if S.pvShowObjects == false then return nil end
  if not (def and def.objects and sprite and love.graphics
          and love.graphics.newMesh) then
    return nil
  end
  local yaw = S.pvYaw or 0
  local rx, rz = math.cos(yaw), -math.sin(yaw)

  local groups = {}
  for i, o in ipairs(def.objects) do
    if o.x and o.y then
      -- THE SAME FACING THE FLAT MAP DRAWS. The resolver takes the object's
      -- `range` and answers with the row for it plus whether that row has to
      -- be mirrored; passing nothing means every person in the 3D world faces
      -- south while the 2D one beside it does not.
      local image, quad, sw, sh, flip = sprite(S, o.sprite, o.range)
      if image and quad and quad.getViewport then
        local okV, qx, qy, qw, qh = pcall(quad.getViewport, quad)
        local iw, ih = image:getDimensions()
        if okV and iw and ih then
          local g = groups[image]
          if not g then g = { verts = {}, map = {} }; groups[image] = g end
          local h = (built.heights
                     and built.heights[o.y * built.W + o.x]) or 0
          if h < 0 then h = 0 end
          local cx = o.x * CELL + CELL / 2
          local cz = o.y * CELL + CELL / 2
          -- HALF A CELL EACH WAY, so a 16px sheet occupies exactly the cell it
          -- stands on -- the same size the 2D map draws it at.
          local half = sw / 2
          local x0, z0 = cx - rx * half, cz - rz * half
          local x1, z1 = cx + rx * half, cz + rz * half
          local yb, yt = h, h + sh
          -- A HAIR TOWARD THE CAMERA. A person standing against a wall shares
          -- that wall's plane, and two coplanar surfaces fight in the depth
          -- buffer -- the sprite flickers in and out as the camera moves.
          local nx, nz = -rz * 0.5, rx * 0.5
          local u0, v0 = qx / iw, qy / ih
          local u1, v1 = (qx + qw) / iw, (qy + qh) / ih
          -- A MIRROR IS A UV SWAP HERE, not a negative scale: these are
          -- vertices in a mesh, and flipping the geometry would turn the
          -- quad inside out and cull it.
          if (flip or 1) < 0 then u0, u1 = u1, u0 end
          local base = #g.verts
          local C = 255
          g.verts[#g.verts + 1] = { x0 + nx, yt, z0 + nz, u0, v0, C, C, C, 255 }
          g.verts[#g.verts + 1] = { x1 + nx, yt, z1 + nz, u1, v0, C, C, C, 255 }
          g.verts[#g.verts + 1] = { x1 + nx, yb, z1 + nz, u1, v1, C, C, C, 255 }
          g.verts[#g.verts + 1] = { x0 + nx, yb, z0 + nz, u0, v1, C, C, C, 255 }
          g.map[#g.map + 1] = base + 1; g.map[#g.map + 1] = base + 2
          g.map[#g.map + 1] = base + 3; g.map[#g.map + 1] = base + 1
          g.map[#g.map + 1] = base + 3; g.map[#g.map + 1] = base + 4
        end
      end
    end
  end

  local out = {}
  for image, g in pairs(groups) do
    if #g.verts > 0 then
      local okM, mesh = pcall(love.graphics.newMesh, FORMAT, g.verts,
                              "triangles", "stream")
      if okM and mesh then
        pcall(mesh.setVertexMap, mesh, g.map)
        pcall(mesh.setTexture, mesh, image)
        out[#out + 1] = mesh
      end
    end
  end
  return (#out > 0) and out or nil
end

-- The editor hands in its own sprite resolver rather than this file growing
-- one: Preview already caches sheets for the 2D overlay, and two caches of the
-- same images in one process is two chances to show the last cartridge's art.
Viewport3D.spriteResolver = nil

local function drawGrid(project, x, y, built)
  local w, d = built.W * CELL, built.H * CELL
  love.graphics.setLineWidth(1)
  for i = 0, built.W / 2 do
    local wx = i * 32
    love.graphics.setColor(1, 1, 1, (i % 4 == 0) and 0.20 or 0.09)
    line3(project, x, y, { wx, 0, 0 }, { wx, 0, d })
  end
  for i = 0, built.H / 2 do
    local wz = i * 32
    love.graphics.setColor(1, 1, 1, (i % 4 == 0) and 0.20 or 0.09)
    line3(project, x, y, { 0, 0, wz }, { w, 0, wz })
  end
  -- The map's own border in WARM grey, not blue: Z is blue, and drawing the
  -- border in the axis colour put two unrelated blue lines on screen that read
  -- as two axes pointing different ways.
  love.graphics.setColor(0.85, 0.80, 0.62, 0.5)
  love.graphics.setLineWidth(2)
  line3(project, x, y, { 0, 0, 0 }, { w, 0, 0 })
  line3(project, x, y, { w, 0, 0 }, { w, 0, d })
  line3(project, x, y, { w, 0, d }, { 0, 0, d })
  line3(project, x, y, { 0, 0, d }, { 0, 0, 0 })
  love.graphics.setLineWidth(1)
end

-- THE THREE WORLD AXES, through the origin, in the colours every 3D tool uses:
-- X red, Y green, Z blue.
--
-- The ground grid says how big a cell is; the axes say which way the world
-- runs, and in an orbit with no horizon that is not otherwise recoverable.
-- Gen 2's map data is described entirely in those directions -- a warp's
-- destination, a connection's edge, an NPC's facing -- so "which way is north"
-- is a question the editor has to be able to answer at a glance.
--
-- Y is drawn BOTH ways from the origin and X and Z only forward, because the
-- map occupies the positive quadrant: a negative arm would run off into the
-- void behind the world and read as geometry.
local function drawAxes(project, x, y, built, Kit)
  -- Sized to the MAP, not to a fraction of it. An axis longer than the world
  -- it describes is the biggest thing on screen and reads as geometry; these
  -- stop at the map's own edge, which is also where they are useful.
  local span = math.max(built.W, built.H) * CELL
  local up = math.min(span * 0.5, 96)
  local axes = {
    { to = { span, 0, 0 },   c = { 0.95, 0.35, 0.35 }, label = "X  east" },
    { to = { 0, up, 0 },     c = { 0.40, 0.95, 0.45 }, label = "Y  up" },
    { to = { 0, 0, span },   c = { 0.40, 0.60, 1.00 }, label = "Z  south" },
  }
  love.graphics.setLineWidth(2)
  for _, a in ipairs(axes) do
    love.graphics.setColor(a.c[1], a.c[2], a.c[3], 0.9)
    line3(project, x, y, { 0, 0, 0 }, a.to)
    local ex, ey = project(a.to[1], a.to[2], a.to[3])
    if ex and Kit then
      love.graphics.setColor(a.c[1], a.c[2], a.c[3], 1)
      love.graphics.circle("fill", x + ex, y + ey, 3)
      Kit.text("small", a.label, x + ex + 6, y + ey - 7,
               { a.c[1] * 255, a.c[2] * 255, a.c[3] * 255 })
    end
  end
  love.graphics.setLineWidth(1)
end

-- A wire box round the selected cell, standing to its own height so it reads
-- as a volume rather than a square painted on the floor.
-- EVERY SELECTED CELL, not just the primary.
--
-- The 2D overlay learned about the selection set and this did not, so in 3D --
-- which is where most of the shaping happens -- shift-clicking six cells drew
-- one box and the other five were invisible. The tools were acting on all six;
-- only the picture disagreed, which is the worst way for it to be wrong.
local function drawSelectionSet(project, x, y, built, S, drawOne)
  for key in pairs(S.pvSel or {}) do
    local kx, ky = key:match("^(-?%d+),(-?%d+)$")
    if kx then
      drawOne(project, x, y, built,
              { cx = tonumber(kx), cy = tonumber(ky) }, true)
    end
  end
  if S.pvCell then drawOne(project, x, y, built, S.pvCell, false) end
end

local function drawSelection(project, x, y, built, cell, secondary)
  if not cell then return end
  local cx, cy = cell.cx, cell.cy
  if cx < 0 or cy < 0 or cx >= built.W or cy >= built.H then return end
  local h = math.max(2, (built.heights and built.heights[cy * built.W + cx]) or 0)
  local x0, z0 = cx * CELL, cy * CELL
  local x1, z1 = x0 + CELL, z0 + CELL
  -- The same yellow throughout: a member of the selection is not a different
  -- kind of thing from the primary, so it is not a different colour -- only a
  -- thinner line, so the one the inspector is reading is still findable.
  love.graphics.setColor(1, 0.85, 0.2, secondary and 0.7 or 0.95)
  love.graphics.setLineWidth(secondary and 1 or 2)
  for _, yy in ipairs({ 0, h }) do
    line3(project, x, y, { x0, yy, z0 }, { x1, yy, z0 })
    line3(project, x, y, { x1, yy, z0 }, { x1, yy, z1 })
    line3(project, x, y, { x1, yy, z1 }, { x0, yy, z1 })
    line3(project, x, y, { x0, yy, z1 }, { x0, yy, z0 })
  end
  line3(project, x, y, { x0, 0, z0 }, { x0, h, z0 })
  line3(project, x, y, { x1, 0, z0 }, { x1, h, z0 })
  line3(project, x, y, { x1, 0, z1 }, { x1, h, z1 })
  line3(project, x, y, { x0, 0, z1 }, { x0, h, z1 })
  love.graphics.setLineWidth(1)
end

-- The axis gizmo, bottom-left. Not decoration: in an orbit with no horizon
-- there is nothing else that says which way north is, and "north" is how every
-- warp, connection and movement in the map data is described.
local AXES = {
  { dx = 1, dy = 0, dz = 0, label = "E", r = 0.95, g = 0.35, b = 0.35 },
  { dx = 0, dy = 1, dz = 0, label = "UP", r = 0.4, g = 0.95, b = 0.45 },
  { dx = 0, dy = 0, dz = -1, label = "N", r = 0.4, g = 0.6, b = 1.0 },
}

local function drawGizmo(S, x, y, size)
  local _, _, _, rx, ry, rz, ux, uy, uz = Viewport3D.basis(S)
  local cx, cy = x + size / 2, y + size / 2
  local r = size / 2 - 10
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", cx, cy, size / 2)
  for _, a in ipairs(AXES) do
    -- the axis projected onto the camera's own right/up plane, which is what
    -- an orientation gizmo is: no perspective, just which way it points
    local sx = a.dx * rx + a.dy * ry + a.dz * rz
    local sy = -(a.dx * ux + a.dy * uy + a.dz * uz)
    love.graphics.setColor(a.r, a.g, a.b, 0.95)
    love.graphics.setLineWidth(2)
    love.graphics.line(cx, cy, cx + sx * r, cy + sy * r)
    love.graphics.circle("fill", cx + sx * r, cy + sy * r, 3)
  end
  love.graphics.setLineWidth(1)
end

Viewport3D.drawGizmo = drawGizmo

-- Why the last draw did not produce a frame, or nil. EVERY early exit sets
-- it, and so does the render pcall.
--
-- The bare `pcall` this used to be threw the error away, so a draw that failed
-- was indistinguishable from one that never ran -- and the panel, having
-- nothing better, reported "the 3D module is not installed" about a module
-- that was installed and working. That is the second time on this feature that
-- a discarded error message cost days: the shader's compile error was the
-- first. An error that is caught and dropped is worse than one that escapes.
Viewport3D.lastDrawError = nil

-- `Kit` is optional and only used for the axis labels; the viewport draws
-- without it, just unlabelled.
function Viewport3D.draw(S, built, x, y, w, h, Kit)
  Viewport3D.lastDrawError = nil
  local function fail(why)
    Viewport3D.lastDrawError = why
    return false
  end
  if not built then return fail("no mesh was built for this map") end
  if not built.mesh then return fail("the build produced no geometry") end
  local sh = getShader()
  if not sh then return fail("no shader: " .. tostring(shaderError)) end
  if not ensureTargets(w, h) then
    return fail("no render target could be created at "
                .. math.floor(w) .. "x" .. math.floor(h))
  end

  -- Aspect from the CANVAS, which is what is actually being rendered into.
  -- Using the rect's units instead is right only while the DPI ratio is 1.
  local vp = Viewport3D.camera(S, built, canvasW, canvasH)
  Viewport3D.lastStats = {
    rectW = math.floor(w), rectH = math.floor(h),
    canvasW = canvasW, canvasH = canvasH, dpi = dpiScale(),
    depth = depthCanvas and "canvas" or "automatic",
    tris = built.count, truncated = built.truncated, carved = built.carved,
    dist = S.pvDist, angle = S.pvAngle, ortho = S.pvOrtho and true or false,
    census = built.census, bmin = built.bmin, bmax = built.bmax,
    W = built.W, H = built.H,
  }

  local prevShader = love.graphics.getShader()
  local prevCanvas = { love.graphics.getCanvas() }

  -- THE SCISSOR HAS TO COME OFF BEFORE THE CANVAS GOES ON.
  --
  -- A scissor is in the coordinates of whatever target is bound. The caller
  -- sets one over the viewport RECT -- say (250, 180, 726, 470) on screen --
  -- and then this binds a 726x470 canvas whose own coordinates start at (0,0).
  -- The scissor does not follow: it keeps its numbers and now clips the canvas
  -- from (250, 180), so the left quarter and the top third of the render are
  -- thrown away. What survives is a rectangle of world with a hard straight
  -- edge down it, which does not line up with the grid and axes drawn
  -- afterwards in screen space -- and reads as the map being the wrong size,
  -- in the wrong place, and cut off.
  --
  -- The canvas needs no scissor anyway: it is exactly the viewport's size, so
  -- its own edges are the clip.
  local okPrevScissor, prevScissorState = pcall(function()
    return { love.graphics.getScissor() }
  end)
  prevScissorState = okPrevScissor and prevScissorState or {}
  pcall(love.graphics.setScissor)

  local ok, err = pcall(function()
    -- `depth = true` asks LOVE for the depth buffer rather than attaching one
    -- built here. Fewer parameters, and every one of them is a way to end up
    -- with a target that renders but never depth-tests -- which draws the mesh
    -- in index order, so a far floor painted after a near wall covers it and
    -- the world appears to swim as the camera turns.
    --
    -- The hand-made canvas stays as the fallback for a build that will not
    -- give us the automatic one.
    if depthCanvas then
      love.graphics.setCanvas({ colorCanvas, depthstencil = depthCanvas })
    else
      love.graphics.setCanvas({ colorCanvas, depth = true })
    end
    love.graphics.clear(0.06, 0.07, 0.10, 1, true, true)
    love.graphics.setDepthMode("lequal", true)
    -- "none", not "back": a side face's winding depends on which way it points
    -- and getting one of the four wrong would delete a wall rather than
    -- mis-shade it. Depth sorting is doing the real work here anyway.
    love.graphics.setMeshCullMode("none")
    -- SHADING MODE. "textured" is the world; "solid" drops the artwork so the
    -- geometry itself is readable (what you want when checking a silhouette);
    -- "wire" is the mesh. Blender's three, for the same reasons.
    if S.pvShading == "wire" then
      love.graphics.setWireframe(true)
    end
    love.graphics.setShader(sh)
    -- ONE two-dimensional table, not four separate ones.
    --
    -- Shader:send(name, layout, matrix) takes a single table of four tables
    -- for one mat4. Passing the four columns as four ARGUMENTS is the
    -- signature for an ARRAY of four matrices, and against a plain `uniform
    -- mat4` that raises -- inside this pcall, which then swallowed it. The
    -- viewport drew nothing, reported nothing, and the panel guessed.
    -- THE CANVAS MATRIX, not the screen one -- see canvasMatrix above.
    local cm = Viewport3D.canvasMatrix(vp)
    sh:send("vp", "column", {
      { cm[1], cm[2], cm[3], cm[4] },
      { cm[5], cm[6], cm[7], cm[8] },
      { cm[9], cm[10], cm[11], cm[12] },
      { cm[13], cm[14], cm[15], cm[16] },
    })
    if S.pvShading == "solid" then
      -- the mesh carries its face shading in VertexColor, so drawing it
      -- against a flat white texture keeps the lighting and drops the art
      love.graphics.setColor(1, 1, 1, 1)
      pcall(built.mesh.setTexture, built.mesh)
      love.graphics.draw(built.mesh)
      pcall(built.mesh.setTexture, built.mesh, built.texture)
    else
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(built.mesh)
    end

    -- THE PEOPLE, in the same pass and under the same depth test -- which is
    -- the whole reason they are here rather than blitted over the finished
    -- picture. Drawn after the terrain so a sprite in front wins the depth
    -- test on merit rather than on paint order.
    local bbs = Viewport3D.buildBillboards(S, built, S._pvMap,
                                           Viewport3D.spriteResolver)
    if bbs and S.pvShading ~= "wire" then
      love.graphics.setColor(1, 1, 1, 1)
      for _, m in ipairs(bbs) do
        love.graphics.draw(m)
        if m.release then pcall(m.release, m) end
      end
    end

    love.graphics.setShader()
    pcall(love.graphics.setWireframe, false)
    love.graphics.setDepthMode()
    love.graphics.setMeshCullMode("none")
    love.graphics.setCanvas(unpack(prevCanvas))
  end)

  -- Whatever happened above, the pipeline state has to come back or every
  -- panel drawn after this one inherits a depth test and an empty shader.
  if prevScissorState[1] then
    pcall(love.graphics.setScissor, unpack(prevScissorState))
  else
    pcall(love.graphics.setScissor)
  end
  pcall(love.graphics.setShader, prevShader)
  pcall(love.graphics.setDepthMode)
  pcall(love.graphics.setMeshCullMode, "none")
  if not ok then
    pcall(love.graphics.setCanvas, unpack(prevCanvas))
    return fail("render failed: " .. tostring(err))
  end

  love.graphics.setColor(1, 1, 1, 1)
  -- Drawn back DOWN by the same ratio it was allocated up by, so a
  -- full-resolution canvas lands exactly on the viewport rect.
  local inv = 1 / dpiScale()
  love.graphics.draw(colorCanvas, x, y, 0, inv, inv)

  -- The furniture goes on TOP of the rendered frame, in screen space. Drawn
  -- here rather than into the depth pass on purpose: a grid that is depth
  -- tested disappears under the terrain it exists to measure.
  --
  -- CLIPPED TO THE VIEWPORT. These are world lines projected to screen, so an
  -- axis that leaves the view keeps going: the Y axis and its label ran up out
  -- of the panel and across the editor's title bar. The mesh never did that
  -- because it lives inside a canvas; the furniture has no such edge unless it
  -- is given one.
  -- pcall'd, and the previous scissor restored by hand: the headless stub used
  -- by the tests has no getScissor, and a viewport that will not open under a
  -- test is a viewport that stops being tested.
  local okScissor, prevScissor = pcall(function()
    return { love.graphics.getScissor() }
  end)
  prevScissor = okScissor and prevScissor or {}
  pcall(love.graphics.setScissor, math.floor(x), math.floor(y),
        math.ceil(w), math.ceil(h))
  local project = projector(vp, w, h)
  if S.pvGrid ~= false then
    drawGrid(project, x, y, built)
    drawAxes(project, x, y, built, Kit)
  end
  -- ONLY THE MARKERS now: the sprites themselves are in the depth pass above,
  -- where the terrain can hide them. What is left here is the ring round the
  -- object being edited, which is deliberately NOT depth-tested -- a selection
  -- you cannot see because a wall is in front of it is a selection you cannot
  -- find.
  drawWarpMarkers(project, x, y, built, S, S._pvMap)
  drawObjectMarkers(project, x, y, built, S, S._pvMap)
  drawSelectionSet(project, x, y, built, S, drawSelection)
  if prevScissor[1] then
    pcall(love.graphics.setScissor, unpack(prevScissor))
  else
    pcall(love.graphics.setScissor)
  end
  love.graphics.setColor(1, 1, 1, 1)
  return true
end

-- ---------------------------------------------------------------------------
-- picking
-- ---------------------------------------------------------------------------

-- Which cell is under a point in the viewport.
--
-- Marched, not inverted. In a perspective view a screen point is a RAY, and
-- which cell it hits depends on the heights along it -- a wall four cells
-- north can stand in front of the floor the ray would otherwise reach. So the
-- ray is stepped through the height field and the first column it enters wins,
-- which is the same answer the picture gives.
-- WORLD POINT -> SCREEN PIXEL, the other direction from `pick`.
--
-- Every 2D overlay the editor draws -- the warp squares, the event tiles, the
-- walkable wash -- lives in `drawOverlays`, which runs only in the flat view:
-- the 3D viewport draws to its own canvas with its own camera, so the cell
-- rectangles the flat path paints have nowhere to go. That is why turning the
-- walkable overlay on while the 3D view was up did nothing at all, and why it
-- looked like the switch was dead rather than the picture being the wrong one.
--
-- The camera already builds a view-projection matrix; this is that matrix
-- applied to a point, divided through by w, and mapped into the viewport's
-- rectangle. Returns nil for anything behind the camera, which is the one
-- case the divide cannot express -- a point at w <= 0 comes back mirrored
-- through the origin and lands somewhere plausible and completely wrong.
function Viewport3D.project(vp, wx, wy, wz, x, y, w, h)
  if type(vp) ~= "table" then return nil end
  local cx = vp[1] * wx + vp[5] * wy + vp[9] * wz + vp[13]
  local cy = vp[2] * wx + vp[6] * wy + vp[10] * wz + vp[14]
  local cw = vp[4] * wx + vp[8] * wy + vp[12] * wz + vp[16]
  if cw <= 0.0001 then return nil end
  local ndcX, ndcY = cx / cw, cy / cw
  return x + (ndcX * 0.5 + 0.5) * w, y + (0.5 - ndcY * 0.5) * h, cw
end

-- The cell grid's four corners on screen, at the height the cell stands at.
--
-- ON TOP OF THE COLUMN, not on the ground: a wash painted at y = 0 under a
-- building is under the building, and the one thing a walkable overlay must
-- do is be visible over the thing it is describing.
function Viewport3D.cellQuad(S, built, cx, cy, x, y, w, h)
  if not built then return nil end
  local vp = Viewport3D.camera(S, built, w, h)
  local hgt = (built.heights and built.heights[cy * built.W + cx]) or 0
  local x0, z0 = cx * CELL, cy * CELL
  local pts = {}
  local corners = { { x0, z0 }, { x0 + CELL, z0 },
                    { x0 + CELL, z0 + CELL }, { x0, z0 + CELL } }
  for i, c in ipairs(corners) do
    local sx, sy = Viewport3D.project(vp, c[1], hgt + 0.5, c[2], x, y, w, h)
    if not sx then return nil end
    pts[i * 2 - 1], pts[i * 2] = sx, sy
  end
  return pts
end

function Viewport3D.pick(S, built, px, py, x, y, w, h)
  if not built then return nil end
  local vp, eye = Viewport3D.camera(S, built, w, h)
  -- unproject two points down the ray by inverting the view-projection is
  -- avoidable: the camera's basis is known, so the ray is built directly
  local focusX = (S.pvFocus and S.pvFocus.x) or (built.W * CELL / 2)
  local focusZ = (S.pvFocus and S.pvFocus.z) or (built.H * CELL / 2)
  local focusY = (S.pvFocus and S.pvFocus.y) or 0

  local fx, fy, fz = normalise(focusX - eye[1], focusY - eye[2], focusZ - eye[3])
  -- right = normalise(cross(forward, up)) with up = +Y, which reduces to
  -- (-fz, 0, fx); up' = cross(right, forward)
  local rx, ry, rz = normalise(-fz, 0, fx)
  local ux, uy, uz = ry * fz - rz * fy, rz * fx - rx * fz, rx * fy - ry * fx

  local aspect = w / math.max(1, h)
  local tanHalf = math.tan(math.rad(45) / 2)
  local ndcX = ((px - x) / w) * 2 - 1
  local ndcY = 1 - ((py - y) / h) * 2
  local dx = fx + rx * (ndcX * tanHalf * aspect) + ux * (ndcY * tanHalf)
  local dy = fy + ry * (ndcX * tanHalf * aspect) + uy * (ndcY * tanHalf)
  local dz = fz + rz * (ndcX * tanHalf * aspect) + uz * (ndcY * tanHalf)
  dx, dy, dz = normalise(dx, dy, dz)

  -- March in world units. The step is a quarter of a cell: fine enough that a
  -- 4px lip is not stepped over, coarse enough that a route-length ray is a
  -- few thousand samples rather than tens of thousands.
  local step = CELL / 4
  local maxDist = math.max(built.W, built.H) * CELL * 4
  local ex, ey, ez = eye[1], eye[2], eye[3]
  local t = 0
  while t < maxDist do
    t = t + step
    local wx, wy, wz = ex + dx * t, ey + dy * t, ez + dz * t
    if wy < -64 then break end
    local cx = math.floor(wx / CELL)
    local cy = math.floor(wz / CELL)
    if cx >= 0 and cy >= 0 and cx < built.W and cy < built.H then
      local ch = built.heights[cy * built.W + cx] or 0
      if wy <= ch then return cx, cy end
    end
  end
  return nil
end

function Viewport3D.release()
  if colorCanvas and colorCanvas.release then pcall(colorCanvas.release, colorCanvas) end
  if depthCanvas and depthCanvas.release then pcall(depthCanvas.release, depthCanvas) end
  colorCanvas, depthCanvas, canvasW, canvasH = nil, nil, nil, nil
end

return Viewport3D
