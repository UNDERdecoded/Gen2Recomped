-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Drawing a Gen 4 model, which is the first real 3D this engine does itself.
--
-- The voxel mod has its own 3D and the tilt ground quad is one mesh with one
-- shader, but the engine core has never had a general "here is a mesh, draw
-- it" path -- so Platinum's 590 buildings, Giratina on the title, the field
-- effects and Professor Rowan's briefcase all had geometry sitting in the
-- cache with nothing able to put it on screen.
--
-- THIS IS DELIBERATELY SELF-CONTAINED.  It does not register a pipeline, does
-- not touch the world pass, and does not ask the Renderer for anything: a
-- screen creates one of these, draws it into its own canvas, and throws it
-- away.  The reason is that the first thing to use it is the starter select --
-- a menu with three Poke Balls in a briefcase -- which has no world behind it
-- and no business being part of the world's pipeline.  When the map meshes
-- arrive they will want the pipeline; a menu does not, and building for the
-- harder case first would mean neither worked.
--
-- WHAT DEPTH COSTS.  A 3D scene needs a depth buffer, which means a canvas
-- created with one and `setDepthMode` around the draw.  Both are restored
-- afterwards, unconditionally, because this runs inside somebody else's draw
-- and leaving either set turns the next 2D blit into a puzzle.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")
-- The pose walk lives with the reader that produced the bytecode.  Requiring
-- an importer from a renderer is not pretty; having the same walk written
-- twice and drifting apart would be worse, and this is the walk that decides
-- where every shape stands.
local Gen4Nsbmd = require("src.import.Gen4Nsbmd")

local Gen4Model = {}
Gen4Model.__index = Gen4Model

-- Matches Gen4ModelPack: a vertex is fourteen bytes and a coordinate is fx16.
-- 16, not 14: the last three bytes are the normal, as three signed bytes.
--
-- Platinum's display lists issue NORMAL and no COLOR -- the DS lights in
-- hardware -- so a vertex whose normal was dropped in packing keeps the
-- decoder's white default, and every polygon draws with no directional term.
-- That is what made the whole of Sinnoh read flat under a correct camera.
local VERTEX_BYTES = 16
-- What it was before the normal was added.  Kept so a cache written by an
-- older import is READ correctly rather than read confidently and wrongly.
local LEGACY_VERTEX_BYTES = 14
local FX16 = 4096
local UV_UNITS = 16

-- The vertex shader takes a model-view-projection matrix and nothing else.
--
-- `TransformProjectionMatrix` is LOVE's own 2D transform and is deliberately
-- ignored: the whole point here is to put clip-space coordinates out directly,
-- and mixing the two would apply the 2D camera to a 3D scene.
-- ...AND A TEXTURE TRANSFORM, which is what a Gen 4 texture animation is.
--
-- `bm_anime`'s BTA0 animations scroll, scale and rotate a material's texture
-- coordinates -- that is how Platinum's water moves and its fountains run.
-- THE UNITS ARE NORMALISED, measured rather than assumed: every scroll in that
-- archive runs its translate from 0.0 to exactly -1.0 over its own frame count
-- (the waterfall to -2.0, which is two cycles in the same time) with scale held
-- at 1.0.  A translate that lands on whole units is one full wrap of the
-- texture; texel units would have run to 16 or 64 and do not.
--
-- This port's UVs are already divided by the texture's size when the mesh is
-- built, so the transform applies directly with nothing to convert.
--
-- Two vectors rather than a mat3 because a 2x2 and an offset is all a texture
-- SRT is, and because every shape sends them on every draw -- including the
-- overwhelming majority that are identity.  Sending them ALWAYS is deliberate:
-- a uniform that is declared and not sent reads as zero, and a zero texture
-- matrix collapses every coordinate to one texel, which is a model drawn in a
-- single flat colour.
-- `yCut` IS WHAT MAKES WALK-BEHIND POSSIBLE.
--
-- Every fragment carries the model-space height it came from, and the pixel
-- stage drops the ones at or below the cut.  Drawing a building twice -- once
-- whole, under the sprites, and once with everything below head height cut
-- away, over them -- is what lets a character pass BEHIND a house: the roof
-- and upper walls are painted after the sprite, the ground floor is not, and
-- somebody standing in front of the door is still drawn in front of it.
--
-- The default is a number no geometry reaches, so a caller that does not ask
-- for a cut gets the whole model.  It is SENT ON EVERY DRAW rather than left
-- unset, because an unset uniform reads as zero and zero would quietly cut
-- every model in the game off at the waist.
local SHADER = [[
varying float vModelY;
varying float vModelZ;
#ifdef VERTEX
uniform mat4 mvp;
// x = how much a unit of HEIGHT spreads; y = THE HEIGHT IT SPREADS ABOUT.
//
// The datum is not 0 and assuming it was is a measured fault.  The factor is
// exactly 1 at y = heightSpread.y, so that is the plane the picture pivots
// around -- and the plane it has to be is THE ONE THE SPRITES STAND ON, since
// they are placed by the flat projection and get no spread at all.  Twinleaf's
// ground is at y = 16, so anchoring at 0 scaled the whole ground plane about
// the screen centre while the characters on it stayed put: 50.6% of ground
// pixels moved at the CARTRIDGE rung and 65.5% at rung 30.  Reported from play
// as standing "a few blocks back" from a building one tile away, and as the
// player looking "smaller than i should be" -- the world was being scaled up
// around them and they were not.
uniform vec2 heightSpread;
// THE CARD'S OWN AXIS, and the angle every card turns about it.
//
// `BillboardPivot.xy` is the card's centre in x and z; `.z` is 1 on a card.
// `billboardYaw` is the camera's heading, and it is ZERO on every pass that is
// not a free camera -- which is what leaves the field and tilt views
// arithmetically identical, since a rotation by zero is the identity.
//
// ABOUT Y ONLY.  Requested: trees *"should always face the players camera"*
// but *"also dont change when looking up or down"*.  A full look-at billboard
// tips the card back as the camera rises and the trees appear to lie down; a
// turn about the vertical keeps the cartridge's own 35-degree lean exactly as
// authored and only spins it to face you.
attribute vec3 BillboardPivot;
uniform float billboardYaw;

vec4 turnToCamera(vec4 v)
{
    if (BillboardPivot.z < 0.5) { return v; }
    vec2 d = v.xz - BillboardPivot.xy;
    float sa = sin(billboardYaw);
    float ca = cos(billboardYaw);
    // THE SIGN IS THE ENGINE'S, not a textbook's.  `Gen4View:follow` puts the
    // eye at `x - sin(yaw) * r, z + cos(yaw) * r` -- the x term is NEGATIVE --
    // so a rotation written the usual way turns the cards the wrong way and
    // doubles the error instead of cancelling it.  Measured with a camera
    // built by `Gen4View` itself: the wrong sign collapsed a card from 6264
    // painted pixels to 188 at 60 degrees.
    v.xz = BillboardPivot.xy + vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
    return v;
}
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 turned = turnToCamera(vertex_position);
    vModelY = turned.y;
    vModelZ = turned.z;
    vec4 p = mvp * turned;
    // THE ONE PERSPECTIVE TERM, and the reason it is here and not in `mvp`.
    //
    // A tree's top is nearer the eye than its base by `h * cos(pitch)`, so the
    // cartridge's camera spreads it outward from the screen centre by
    // `D / (D - h*cos(pitch))`.  That factor multiplies the vertex's SCREEN
    // OFFSET by a function of its HEIGHT -- a product of two coordinates,
    // which no 4x4 matrix can express.  It has to be a per-vertex divide, so
    // it lives here.
    //
    // Screen centre is NDC (0,0) because the matrix is built per frame around
    // the camera, so scaling p.xy about the origin IS spreading from the
    // centre of the view.  At h = 0 the factor is exactly 1, which is what
    // keeps the GROUND PLANE pixel-identical -- and therefore every sprite,
    // every collision pick and every screen-row-to-tile-row answer the
    // overworld already computes.
    float s = 1.0 - (turned.y - heightSpread.y) * heightSpread.x;
    if (s < 0.25) { s = 0.25; }
    p.xy /= s;
    return p;
}
#endif
#ifdef PIXEL
uniform vec4 uvRotScale;
uniform vec2 uvTranslate;
uniform float yCut;
// (lo, hi] in model z: a band of the cut pass that is left unpainted -- the
// ground just BEHIND the player, see Gen4Ground:livePass. Empty by default.
uniform vec2 zKeep;
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen)
{
    if (vModelY <= yCut) { discard; }
    if (vModelZ > zKeep.x && vModelZ <= zKeep.y) { discard; }
    vec2 t = vec2(uvRotScale.x * uv.x + uvRotScale.y * uv.y,
                  uvRotScale.z * uv.x + uvRotScale.w * uv.y) + uvTranslate;
    vec4 texel = Texel(tex, t);
    // A Gen 4 texture keeps colour 0 transparent, and a transparent texel must
    // not write depth -- otherwise the hole punched through a leaf or a strap
    // occludes whatever is behind it.  Discarding is what makes that correct
    // rather than merely usually correct.
    if (texel.a < 0.5) { discard; }
    return texel * colour;
}
#endif
]]

-- THE SAME SHADER WITHOUT THE HEIGHT CUT, kept as a fallback.
--
-- The cut needs a `varying`, and a varying is the one part of this shader that
-- a driver can reasonably refuse -- GLES wants a precision qualifier, and some
-- older GL profiles are fussy about declaring one outside the stage blocks.
-- If it will not compile, losing walk-behind is a much smaller loss than
-- losing every model in the game, which is what `ensureShader` returning nil
-- costs: `draw` bails on a nil shader and the whole world goes black.
local SHADER_NO_CUT = [[
#ifdef VERTEX
uniform mat4 mvp;
// x = how much a unit of HEIGHT spreads; y = THE HEIGHT IT SPREADS ABOUT.
//
// The datum is not 0 and assuming it was is a measured fault.  The factor is
// exactly 1 at y = heightSpread.y, so that is the plane the picture pivots
// around -- and the plane it has to be is THE ONE THE SPRITES STAND ON, since
// they are placed by the flat projection and get no spread at all.  Twinleaf's
// ground is at y = 16, so anchoring at 0 scaled the whole ground plane about
// the screen centre while the characters on it stayed put: 50.6% of ground
// pixels moved at the CARTRIDGE rung and 65.5% at rung 30.  Reported from play
// as standing "a few blocks back" from a building one tile away, and as the
// player looking "smaller than i should be" -- the world was being scaled up
// around them and they were not.
uniform vec2 heightSpread;
// THE CARD'S OWN AXIS, and the angle every card turns about it.
//
// `BillboardPivot.xy` is the card's centre in x and z; `.z` is 1 on a card.
// `billboardYaw` is the camera's heading, and it is ZERO on every pass that is
// not a free camera -- which is what leaves the field and tilt views
// arithmetically identical, since a rotation by zero is the identity.
//
// ABOUT Y ONLY.  Requested: trees *"should always face the players camera"*
// but *"also dont change when looking up or down"*.  A full look-at billboard
// tips the card back as the camera rises and the trees appear to lie down; a
// turn about the vertical keeps the cartridge's own 35-degree lean exactly as
// authored and only spins it to face you.
attribute vec3 BillboardPivot;
uniform float billboardYaw;

vec4 turnToCamera(vec4 v)
{
    if (BillboardPivot.z < 0.5) { return v; }
    vec2 d = v.xz - BillboardPivot.xy;
    float sa = sin(billboardYaw);
    float ca = cos(billboardYaw);
    // THE SIGN IS THE ENGINE'S, not a textbook's.  `Gen4View:follow` puts the
    // eye at `x - sin(yaw) * r, z + cos(yaw) * r` -- the x term is NEGATIVE --
    // so a rotation written the usual way turns the cards the wrong way and
    // doubles the error instead of cancelling it.  Measured with a camera
    // built by `Gen4View` itself: the wrong sign collapsed a card from 6264
    // painted pixels to 188 at 60 degrees.
    v.xz = BillboardPivot.xy + vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
    return v;
}
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 turned = turnToCamera(vertex_position);
    vec4 p = mvp * turned;
    float s = 1.0 - (turned.y - heightSpread.y) * heightSpread.x;
    if (s < 0.25) { s = 0.25; }
    p.xy /= s;
    return p;
}
#endif
#ifdef PIXEL
uniform vec4 uvRotScale;
uniform vec2 uvTranslate;
vec4 effect(vec4 colour, Image tex, vec2 uv, vec2 screen)
{
    vec2 t = vec2(uvRotScale.x * uv.x + uvRotScale.y * uv.y,
                  uvRotScale.z * uv.x + uvRotScale.w * uv.y) + uvTranslate;
    vec4 texel = Texel(tex, t);
    if (texel.a < 0.5) { discard; }
    return texel * colour;
}
#endif
]]

local shader
local shaderCuts = false

local function ensureShader()
  if shader ~= nil then return shader or nil end
  local ok, made = pcall(love.graphics.newShader, SHADER)
  if ok and made then
    shader, shaderCuts = made, true
    return shader
  end
  Logger.warn("gen4 model: the mesh shader with the height cut would not "
              .. "compile (%s) -- falling back to the plain one, so models "
              .. "still draw but nothing will occlude a sprite",
              tostring(made))
  local plainOk, plain = pcall(love.graphics.newShader, SHADER_NO_CUT)
  if not plainOk or not plain then
    Logger.error("gen4 model: the mesh shader would not compile (%s); "
                 .. "no 3D model will draw", tostring(plain))
    shader = false
    return nil
  end
  shader, shaderCuts = plain, false
  return shader
end

-- Whether this device got the shader that can cut a model off at a height.
-- The canopy pass asks, because baking one that cannot cut would paint whole
-- buildings over the sprites instead of only their roofs.
function Gen4Model.cutsHeight()
  ensureShader()
  return shaderCuts
end

-- ---------------------------------------------------------------------------
-- Matrices
-- ---------------------------------------------------------------------------

-- Row-major 4x4s, as flat sixteen-element tables, because that is the layout
-- Shader:send takes and converting once here beats converting at every draw.
local function identity()
  return { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 }
end

local function multiply(a, b)
  local out = {}
  for row = 0, 3 do
    for col = 0, 3 do
      local sum = 0
      for k = 0, 3 do
        sum = sum + a[row * 4 + k + 1] * b[k * 4 + col + 1]
      end
      out[row * 4 + col + 1] = sum
    end
  end
  return out
end

function Gen4Model.perspective(fovY, aspect, near, far)
  local f = 1 / math.tan(fovY / 2)
  return {
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) / (near - far), (2 * far * near) / (near - far),
    0, 0, -1, 0,
  }
end

-- THE OTHER PROJECTION THE CARTRIDGE USES.
--
-- Three hundred of Platinum's 593 map headers are CAMERA_TYPE_INTERIOR_-
-- ORTHOGRAPHIC -- every ordinary room, the player's bedroom included -- and
-- `Camera_ComputeProjectionMatrix` really does build an orthographic box for
-- them.  A perspective matrix at the same numbers is not an approximation of
-- that, it is a different picture: an orthographic camera has no parallax at
-- all, which is exactly what the cartridge wants indoors.
--
-- `halfHeight` is in WORLD UNITS at the target plane, which is the form the
-- cartridge states it in (`top = tan(fovY) * distance`).
function Gen4Model.orthographic(halfHeight, aspect, near, far)
  local h = (tonumber(halfHeight) or 1)
  if h < 1e-6 then h = 1e-6 end
  local w = h * (tonumber(aspect) or 1)
  near, far = tonumber(near) or 1, tonumber(far) or 4096
  if far - near < 1e-6 then far = near + 1 end
  return {
    1 / w, 0, 0, 0,
    0, 1 / h, 0, 0,
    0, 0, -2 / (far - near), -(far + near) / (far - near),
    0, 0, 0, 1,
  }
end

-- A camera that looks at a point from a distance, around it and above it.
-- Spelled out rather than composed from a `lookAt` because the only thing that
-- ever moves it is a turntable, and two angles read better than an eye vector.
function Gen4Model.orbit(target, distance, yaw, pitch)
  local cy, sy = math.cos(yaw), math.sin(yaw)
  local cp, sp = math.cos(pitch), math.sin(pitch)
  local rotateY = {
    cy, 0, -sy, 0,
    0, 1, 0, 0,
    sy, 0, cy, 0,
    0, 0, 0, 1,
  }
  local rotateX = {
    1, 0, 0, 0,
    0, cp, sp, 0,
    0, -sp, cp, 0,
    0, 0, 0, 1,
  }
  local translate = identity()
  translate[4] = -(target and target[1] or 0)
  translate[8] = -(target and target[2] or 0)
  translate[12] = -(target and target[3] or 0)
  local back = identity()
  back[12] = -(distance or 1)
  return multiply(back, multiply(rotateX, multiply(rotateY, translate)))
end

-- Exported beside the two camera helpers, because a caller that builds its own
-- view and projection has to combine them and re-deriving a 4x4 multiply at
-- every call site is how two of them end up disagreeing.
Gen4Model.multiply = multiply

-- A camera placed where the cartridge puts it, looking where it looks.
--
-- `orbit` above is the right shape for a turntable and the wrong one for a
-- scripted shot: Platinum's title camera is two POINTS that interpolate --
-- eye (0, 192, 600) to (-64, 192, 484) over sixty frames, target fixed at
-- (0, 100, -18) -- and turning a pair of points into a distance and two
-- angles to hand to `orbit` would throw away the straight line between them.
function Gen4Model.lookAt(eye, target, up)
  up = up or { 0, 1, 0 }
  local fx, fy, fz = target[1] - eye[1], target[2] - eye[2], target[3] - eye[3]
  local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
  if fl < 1e-6 then fl = 1 end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local sx = fy * up[3] - fz * up[2]
  local sy = fz * up[1] - fx * up[3]
  local sz = fx * up[2] - fy * up[1]
  local sl = math.sqrt(sx * sx + sy * sy + sz * sz)
  -- Looking straight down the up axis: any side vector will do, and picking
  -- one is better than dividing by zero.
  if sl < 1e-6 then sx, sy, sz, sl = 1, 0, 0, 1 end
  sx, sy, sz = sx / sl, sy / sl, sz / sl
  local ux = sy * fz - sz * fy
  local uy = sz * fx - sx * fz
  local uz = sx * fy - sy * fx
  return {
    sx, sy, sz, -(sx * eye[1] + sy * eye[2] + sz * eye[3]),
    ux, uy, uz, -(ux * eye[1] + uy * eye[2] + uz * eye[3]),
    -fx, -fy, -fz, (fx * eye[1] + fy * eye[2] + fz * eye[3]),
    0, 0, 0, 1,
  }
end

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

local FORMAT = {
  { "VertexPosition", "float", 3 },
  { "VertexTexCoord", "float", 2 },
  -- FLOAT, NOT BYTE, AND THAT IS A BUG FIX RATHER THAN A PREFERENCE.
  --
  -- LOVE hands a "byte" vertex attribute to the shader UNNORMALISED -- the
  -- fragment stage sees 0..255, not 0..1 -- so `texel * colour` came out at
  -- 255x the texel and clamped to white for EVERY value.  Measured at the
  -- smallest scale that can show it: a 1x1 white texture on a three-vertex
  -- mesh renders pixel-identical at vertex colour 255 and at 128 under "byte",
  -- and 1.000 against 0.502 under "float", on both the custom shader and
  -- LOVE's default one.
  --
  -- So this format could never have shown a vertex colour at all.  It did not
  -- matter while every vertex in the cache was white; it is the second half of
  -- why lighting the world changed nothing, and it would have quietly eaten
  -- the first half.
  { "VertexColor", "float", 4 },
  -- WHERE THIS VERTEX'S CARD TURNS, and whether it turns at all.
  --
  -- x and y are the card's centre in the chunk's own x and z; z is 1 on a
  -- camera-facing card and 0 on everything else.  It is PER VERTEX rather than
  -- per shape because a terrain shape is every tree on the chunk at once --
  -- `tree2_01` reaches 240 separate quads in one shape -- and they each have
  -- to turn about themselves, not about the shape's middle.
  --
  -- Local to this file, so Gen 1/2/3 are untouched: they have their own model
  -- modules and never see this format.
  { "BillboardPivot", "float", 3 },
}

-- A vertex that is not part of a card. Shared rather than built per vertex,
-- because most of Sinnoh is not a tree.
local NO_PIVOT = { 0, 0, 0 }

-- WHICH FACES THE CARTRIDGE AUTHORED TO FACE THE CAMERA.
--
-- Platinum builds a tree as a flat quad leaning back toward its fixed camera,
-- and that lean is a single exact normal: (0, 0.819, 0.575).  Measured over
-- the whole cartridge it appears on `tree01`, `tree2_01`, `tree04_2`,
-- `conttree_b/t`, `conttree2_b/t`, `tree3_02`, `bf_tree03` and nothing else --
-- 60,273 triangles across 45 materials.  Walls are (1,0,0) or (0,0,1), the
-- ground is (0,1,0), and `searock` and `imped` lean at a DIFFERENT 45 degrees,
-- so none of them are caught.
--
-- Two simpler rules were tried and thrown away.  "Taller than it is flat"
-- catches every dungeon wall and step.  "Made only of 4-vertex quads" is
-- better -- a tree shape really is 56 to 240 loose quads while a wall is 6-
-- and 8-vertex boxes -- but the FLAT quads are the sea, the lakes and the
-- grass floor, and standing those on end would take the world apart.
--
-- The normal is computed from the geometry rather than read from the vertex,
-- because a cache imported before normals were carried is 14 bytes a vertex
-- and has none.  The lighting pass measured the same normal independently off
-- a 16-byte cache, which is a second source for it.
local TREE_NY, TREE_NZ, TREE_TOL = 0.819, 0.575, 0.04

-- billboardPivots(shape, positions, count) -> per-vertex pivot, card count
--
-- Each card gets its OWN centre, found by walking the shape's triangles as a
-- graph: a card is one connected component, and every one of them is exactly
-- four vertices.
-- HOW MANY TIMES A CARD REPEATS ITS TEXTURE ACROSS ITS WIDTH, above which it
-- is a CONTINUOUS STRIP and not a tree.
--
-- Reported from play, twice: *"the border trees ... rotating as a large group
-- of trees instead of individually above their trunks"*, and again after the
-- pivot was moved to the base -- *"many groups of trees canopys are still
-- pivoting as if theyre rows rather than from the trunk of every tree"*.
--
-- The second report is not a pivot fault.  Measured: 100% of card components
-- are exactly one quad, so nothing is being merged.  What IS happening is that
-- Platinum draws a forest border as ONE CARD -- `conttree` is *continuous*
-- tree -- 256 world units wide and 20 tall, repeating a 64-pixel texture four
-- times.  All 2,956 `conttree_t` cards and all 3,738 `conttree2_t` cards are
-- wider than 48 units; the widest are 256.  A quad cannot bend, so there is no
-- pivot that turns those four trees individually: the geometry for them does
-- not exist.
--
-- SUBDIVIDING THEM WAS TRIED AND ABANDONED.  Splitting a strip at its texture
-- tiles needs the repeat count to be a whole number, and across the cartridge
-- **23,171 of 30,147 cards have a non-integer u-span over texture width** --
-- the UVs address sub-rectangles, not whole tiles. There is no derivable place
-- to cut, and cutting at a guessed one would break a strip into panels that
-- swing apart at the seams.
--
-- So a strip is left exactly as the cartridge drew it, which is what it was
-- authored for, and only cards that really are one tree turn to face you.
-- 1.5 rather than 2 so a card that repeats "about twice" is treated as the
-- strip it is.
-- 1.25, NOT 1.5, AND THE DIFFERENCE IS THE WHOLE OF REPORT #188.
--
-- Reported from play a third time: *"some of the trees are pivoting together
-- for example 3 trees are pivoting from one point"*.
--
-- Measured over all 666 chunks of the cartridge, u-span divided by texture
-- width lands on clean values -- and 2,396 components sit at EXACTLY 1.50:
--
--     0.66 x6328   0.53 x6279   0.34 x6272     <- single trees
--     4.00 x3534 (excluded)   2.50 x1187 (excluded)   2.00 x1159 (excluded)
--     1.50 x2396   <- ON the old threshold, and the test is `>`, so KEPT
--     1.00 x2250   <- a single tree, correctly kept
--
-- A strict `>` against 1.5 lets every one of those 2,396 through, and at a
-- 64-wide texture that component is 96 world units across: THREE 32-unit
-- trees turning about one pivot, which is the report word for word.
--
-- 1.25 rather than 1.4 or 1.49 because it is the MIDDLE OF A MEASURED GAP:
-- 21,758 components are at or under 1.00 repeats, 2,396 are at 1.50, and
-- only EIGHTEEN of 30,147 lie strictly between the two.  A threshold in an
-- empty gap cannot be knocked over by float wobble in the s16 divide, which
-- is exactly what setting it on 1.5 and testing with `>=` would risk.
local STRIP_REPEATS = 1.25

-- ...AND A `conttree` IS NEVER ONE TREE, WHICH THE CARTRIDGE SAYS IN THE NAME.
--
-- `conttree` is CONTINUOUS tree.  The u-span test is a proxy -- it reads the
-- texture's repeat, not the quad's size -- and it misses the strips whose UVs
-- are stretched rather than tiled.  The name does not miss them, and the
-- separation is total:
--
--     conttree* components   n=10,217  min width 64.0  median 128  max 256
--                            AT OR UNDER 40 UNITS: ZERO
--     every other component  n=19,930  median 33      98.3% at or under 40
--
-- The narrowest `conttree` in the game is 64 units, which is already two
-- trees; an ordinary tree card is 33.  There is no overlap to argue about.
--
-- Effect, measured: billboarded cards wider than 48 units fall from 4,493
-- (18.6% of all cards) to 51 (0.3%), and the widest from 96.0 to 85.3.  The
-- name rule alone does most of it -- 18.6% to 0.4% -- and the threshold trims
-- the rest.
local function isContinuousStrip(shape)
  local name = shape and shape.texture
  return type(name) == "string" and name:find("conttree", 1, true) ~= nil
end

local function billboardPivots(shape, positions, count, textureWidth)
  local parent = {}
  for i = 1, count do parent[i] = i end
  local function find(a)
    while parent[a] ~= a do parent[a] = parent[parent[a]]; a = parent[a] end
    return a
  end
  local function union(a, b)
    a, b = find(a), find(b)
    if a ~= b then parent[a] = b end
  end

  local card = {}
  local indices = shape.indices or ""
  for t = 0, (shape.triangleCount or 0) - 1 do
    local at = t * 6
    local a1, a2, b1, b2, c1, c2 = indices:byte(at + 1, at + 6)
    if not c2 then break end
    local a = a1 + a2 * 256 + 1
    local b = b1 + b2 * 256 + 1
    local cc = c1 + c2 * 256 + 1
    local pa, pb, pc = positions[a], positions[b], positions[cc]
    if pa and pb and pc then
      union(a, b)
      union(b, cc)
      local ux, uy, uz = pb[1] - pa[1], pb[2] - pa[2], pb[3] - pa[3]
      local vx, vy, vz = pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3]
      local nx = uy * vz - uz * vy
      local ny = uz * vx - ux * vz
      local nz = ux * vy - uy * vx
      local len = math.sqrt(nx * nx + ny * ny + nz * nz)
      if len > 1e-6 then
        nx, ny, nz = nx / len, ny / len, nz / len
        -- The winding decides the sign and both windings occur, so the test is
        -- made on the upward-pointing form of the normal.
        if ny < 0 then nx, ny, nz = -nx, -ny, -nz end
        if math.abs(nx) < TREE_TOL
           and math.abs(ny - TREE_NY) < TREE_TOL
           and math.abs(math.abs(nz) - TREE_NZ) < TREE_TOL then
          card[a], card[b], card[cc] = true, true, true
        end
      end
    end
  end

  -- A CARD TURNS ABOUT WHERE IT STANDS, not about its middle.
  --
  -- Reported from play, with a screenshot: *"the border trees to the town seem
  -- to be rotating billboards weird as a large group of trees instead of
  -- individually above their trunks"*.
  --
  -- The first version pivoted on the component's CENTROID, and a leaning card's
  -- centroid is not above its base -- the cartridge tilts them 35 degrees back,
  -- so the middle of the quad hangs behind the trunk.  Measured on Twinleaf's
  -- own border: every `conttree_b` card's centroid is 13.9 units behind its
  -- base and every `conttree_t` card's is 9.0 to 12.3.  Turning each about that
  -- point swings it through an arc it never should have left, which reads as
  -- the whole tree line sweeping sideways -- and because the trunk's offset
  -- (13.9) and the canopy's (12.3) DIFFER, the two halves of one tree come
  -- apart as they turn.
  --
  -- So the pivot is the middle of the card's LOWEST edge: the line where it
  -- meets the ground, which is the trunk. A trunk and the canopy above it
  -- share that axis even though they are separate components, so they stay
  -- together.
  -- A CONTINUOUS STRIP IS NOT A TREE -- see `STRIP_REPEATS` above.
  --
  -- Measured per component rather than per shape, because `conttree_b` mixes
  -- single cards with 256-wide strips in the same shape.
  local tw = tonumber(textureWidth)
  if tw and tw > 0 then
    local ulo, uhi = {}, {}
    for i = 1, count do
      if card[i] then
        local r = find(i)
        local u = positions[i][4]
        if u then
          if ulo[r] == nil or u < ulo[r] then ulo[r] = u end
          if uhi[r] == nil or u > uhi[r] then uhi[r] = u end
        end
      end
    end
    local strip = {}
    for r, lo in pairs(ulo) do
      if (uhi[r] - lo) > STRIP_REPEATS * tw then strip[r] = true end
    end
    if next(strip) then
      for i = 1, count do
        if card[i] and strip[find(i)] then card[i] = nil end
      end
    end
  end

  -- OUTSIDE the `tw` block on purpose: the name is readable whether or not the
  -- texture loaded, and a cache with no textures should still not billboard a
  -- forest border as one card.
  if isContinuousStrip(shape) then
    for i = 1, count do card[i] = nil end
  end

  local lowest = {}
  for i = 1, count do
    if card[i] then
      local r = find(i)
      local y = positions[i][2]
      if lowest[r] == nil or y < lowest[r] then lowest[r] = y end
    end
  end
  -- Half a unit: a card's base edge is flat, and the packed coordinates
  -- quantise to about a sixtieth of a unit, so this catches the base and
  -- nothing above it.
  local BASE_BAND = 0.5
  local sumX, sumZ, n = {}, {}, {}
  for i = 1, count do
    if card[i] then
      local r = find(i)
      if positions[i][2] - lowest[r] <= BASE_BAND then
        sumX[r] = (sumX[r] or 0) + positions[i][1]
        sumZ[r] = (sumZ[r] or 0) + positions[i][3]
        n[r] = (n[r] or 0) + 1
      end
    end
  end
  -- A card lying exactly flat has no "lowest edge" to speak of and every
  -- vertex lands in the band, which gives the centroid -- the right answer
  -- for something with no height to lean.
  local cards = 0
  for _ in pairs(n) do cards = cards + 1 end

  local out = {}
  for i = 1, count do
    if card[i] then
      local r = find(i)
      out[i] = { sumX[r] / n[r], sumZ[r] / n[r], 1 }
    else
      out[i] = NO_PIVOT
    end
  end
  return out, cards
end

local function s16(data, at)
  local a, b = data:byte(at + 1, at + 2)
  if not b then return 0 end
  local value = a + b * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

-- One axis of a normal, back out of a signed byte.  Nil past the end of the
-- string, which is how a shorter vertex from an older cache announces itself
-- rather than silently reading into its neighbour.
local function s8(data, at)
  local byte = data:byte(at + 1)
  if not byte then return nil end
  if byte >= 128 then byte = byte - 256 end
  return byte / 127
end

-- new(record) -> model, or nil when the record carries nothing drawable.
--
-- `record` is one entry of the cache's `gen4_models`: a name, a position scale
-- and a list of shapes, each with its packed vertices, its packed indices and
-- the texture its material wears.
-- HOW FAR A GENERATED SHADOW SITS ABOVE THE FLOOR, in world units.
--
-- Small enough to read as contact and large enough to beat the depth buffer's
-- resolution at this camera's distances; a shadow written at exactly the floor
-- height fights the floor and stipples.
local SHADOW_LIFT = 0.25

-- The cartridge's own shadow translucency, 9 of 31, stated here because
-- `SHADOW_ALPHA` is declared far below this and Lua scope runs downward.
local SHADOW_ALPHA_FRACTION = 9 / 31

-- HOW FAR FROM THE CARTRIDGE'S OWN DRAWING SCALE A WALL COURSE MAY SIT.
-- One octave either side of one texel per world unit; the measurements behind
-- it are in `addBackWall`'s caller, where the bands are chosen.
local WALL_SCALE_LO, WALL_SCALE_HI = 0.5, 2.0
-- ...AND HOW LITTLE OF THE TEXTURE A FACE MAY SHOW AND STILL BE A COURSE.
-- A rect a couple of texels across is a colour, not a picture, however
-- plausible its vertical scale: `c1_s02`'s worst offender spreads TWO texels
-- of u over 65.81 units.  There is a clean gap in the measurements -- the
-- flat-colour faces span 0.9 to 2.0 texels and the real courses 10 to 64 --
-- so this sits in the gap rather than on a slope.
local WALL_MIN_TEXELS = 4

-- ---------------------------------------------------------------------------
-- THE GRASS A WILD POKEMON LIVES IN, STOOD UP
-- ---------------------------------------------------------------------------
--
-- Requested: *"make the grass billboards that stand up and always face the
-- camera"*, and then, when the first attempt stood up the wrong layer,
-- *"looks like your making the wrong grass a billboard its supposed to be the
-- grass wild pokemon are in"*.
--
-- WHICH LAYER, and why a name is the right way to ask.  Sinnoh's ground is
-- drawn in layers, each its own polygon with its own material, and the
-- cartridge separates the lawn from the encounter grass exactly that way:
-- `ngrass` against `nectgr`.  The renderer cannot ask the other question --
-- "is this tile TALL_GRASS" -- because the behaviour byte is a movement-layer
-- fact that the terrain cache does not carry; it holds geometry and height and
-- nothing else.  So the material is the question that can be asked here, and
-- it is the cartridge's own answer rather than a guess about one.
--
-- MEASURED, ON THE ART, why the lawn must not be in this list.  Every ground
-- tile in the set is 100% opaque -- there is no cut-out anywhere -- so a card
-- made from one is a solid rectangle, and what decides whether that reads as
-- grass is how much of the tile is decoration rather than flat field colour.
-- `ngrass` is 57.4% one flat green over four colours; `nectgr` is 21.1% flat
-- over nine, the rest leaf. Stood up, the first is a green slab that blanks
-- out the path behind it and the second is a clump of leaves.
--
-- The list is names because only names are available, and it is one table so
-- that importing another region's texture set is a one-line change. Only the
-- materials that have actually been LOOKED at are in it.
--
-- THE OTHER GRASS-ISH NAMES, now that they ARE extracted -- the note that used
-- to sit here said they were not, and that stopped being true some imports ago.
-- Census over all 666 land chunks, then each texture opened and viewed:
--
--   `ngrass` (224 shapes) -- OUT. The lawn: 4 colours, 86.7% one flat green,
--     border 100%. Stood up it is a slab that blanks the path behind it.
--   `bf_ngrass` (9) -- OUT, and it is the same thing under another area's
--     prefix: 8 colours, 66.4% flat, border 90.6%, and it looks like a lawn.
--   `l_grass_u` / `_m` / `_d` (16 between them) -- OUT, and this one is worth
--     the sentence: stacked u-m-d they form ONE CONTINUOUS COLUMN of grass
--     blades three tiles tall, with the ground band at the foot of `_d`. That
--     is grass the cartridge ALREADY DRAWS STANDING, on a vertical face.
--     Standing it again would double it, and there is nothing to cut out --
--     the blades run edge to edge, which is why their border agreement is
--     12-23% against `nectgr`'s 85.9%.
--   `s_grass` (20) -- IN. A dark spiky clump on red soil: 10 colours, 41.4%
--     flat, border 67.2%. Structurally the same picture as `nectgr` -- a plant
--     with a uniform field colour around it -- which is exactly what the
--     cut-out below needs and what makes a card read as a clump.
--
--   `nectgr` (97) -- IN, the original: 8 colours, 32.8% flat, border 85.9%.
--
-- The `grow_*` singles and `gym04_daigrass02` are one shape each and have not
-- been looked at; one shape is not worth a card until someone has.
local GRASS_MATERIALS = { nectgr = true, s_grass = true }

-- THE TILE'S BACKGROUND, CUT OUT.
--
-- A ground tile is opaque all the way across -- the whole set is, there is no
-- alpha anywhere in it -- so a card made from one is a rectangle, and stood up
-- the plant reads as a clump inside a visible pale box.
--
-- What that box is, is the GROUND: a tile has to meet the ground seamlessly on
-- all four sides, so the colour running round its border is the field it sits
-- in.  Measured on `nectgr`, 63.3% of the border is (82,255,148) and that is
-- also the tile's commonest colour overall at 21.1% -- the border and the whole
-- agree, which is what says it is a background and not a pattern.  On a
-- VERTICAL card that colour is behind the plant rather than under it, so it is
-- made transparent and the model shader's own alpha cut removes it.
--
-- The flat quad keeps the untouched texture.  Only the standing card wears
-- this one, and it is derived from the cartridge's own pixels rather than
-- drawn.
local grassCutouts = {}
local function grassCutout(path)
  if not path then return nil end
  local hit = grassCutouts[path]
  if hit ~= nil then return hit or nil end
  local okData, data = pcall(function()
    return love.image.newImageData(Assets.resolve(path))
  end)
  if not (okData and data) then grassCutouts[path] = false return nil end
  local w, h = data:getDimensions()
  if w < 3 or h < 3 then grassCutouts[path] = false return nil end
  local counts, best, bestN = {}, nil, 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      if x == 0 or y == 0 or x == w - 1 or y == h - 1 then
        local r, g, b = data:getPixel(x, y)
        local key = ("%d,%d,%d"):format(r * 255, g * 255, b * 255)
        local n = (counts[key] or 0) + 1
        counts[key] = n
        if n > bestN then bestN, best = n, key end
      end
    end
  end
  -- A border with no colour of its own is not a background.
  if not best or bestN < (2 * (w + h) - 4) * 0.5 then
    grassCutouts[path] = false
    return nil
  end
  local br, bg, bb = best:match("^(%d+),(%d+),(%d+)$")
  br, bg, bb = tonumber(br), tonumber(bg), tonumber(bb)
  data:mapPixel(function(_, _, r, g, b, a)
    if math.floor(r * 255 + 0.5) == br and math.floor(g * 255 + 0.5) == bg
       and math.floor(b * 255 + 0.5) == bb then
      return r, g, b, 0
    end
    return r, g, b, a
  end)
  local okImg, img = pcall(love.graphics.newImage, data)
  if not (okImg and img) then grassCutouts[path] = false return nil end
  img:setFilter("nearest", "nearest")
  img:setWrap("repeat", "repeat")
  grassCutouts[path] = img
  return img
end
-- One standing card per TILE, not per triangle: a chunk's grass is merged into
-- quads that span two tiles as often as one, so the triangles are grouped back
-- onto the tile grid the cartridge measured (`tileUnits`, 16).
--
-- The card is as tall as it is wide, because the texture is square and drawing
-- it at any other aspect stretches art that was painted at 16x16.  It stands
-- on the LOWEST corner of its tile so it plants in sloping ground rather than
-- floating over it, and it wears the tile's own UV rectangle, so a chunk whose
-- grass sits in a corner of the atlas gets that corner and not the whole sheet.
local function addGrassCards(self, shape, vertices, positions, tileUnits)
  local image = grassCutout(shape.image)
  if not image then return false end
  local indices = shape.indices or ""
  local half = tileUnits * 0.5
  local tiles, order = {}, {}

  -- ONE CARD PER TILE THE SHAPE ACTUALLY COVERS, and the previous version could
  -- not do that however it was keyed.
  --
  -- It grouped TRIANGLES by the tile their centre fell in and then took that
  -- group's min/max UV as the card's rectangle. Measured over all 666 chunks,
  -- **2,812 of nectgr's 3,440 triangles (81.7%) span more than one tile**, and
  -- the commonest case is exactly 2x2 (924 of them, then 2x1 and 1x2 at 288 and
  -- 284, and 4x4 at 182). A quad covering 2x2 tiles has a UV range two texture
  -- widths across in each axis, so the card wore the texture FOUR TIMES in one
  -- square -- reported as *"some are rendered with 2x2 grass textures in a
  -- square for 1 tile"*. The same group's min y is the low corner of the whole
  -- patch rather than of one tile, so on sloping ground the card started below
  -- the ground: *"some are but are too tall instead of starting at the ground"*.
  -- One fault, two symptoms.
  --
  -- Keying cannot fix it, because no key splits a triangle that covers several
  -- tiles. So the walk is the other way round: for every tile a triangle
  -- touches, ask the TRIANGLE what the ground and the texture do at that tile's
  -- centre. A tile is claimed by the first triangle that actually contains its
  -- centre, so a tile is never built twice and never averaged across a seam.
  for t = 0, (shape.triangleCount or 0) - 1 do
    local at = t * 6
    local a1, a2, b1, b2, c1, c2 = indices:byte(at + 1, at + 6)
    if not c2 then break end
    local ia = a1 + a2 * 256 + 1
    local ib = b1 + b2 * 256 + 1
    local ic = c1 + c2 * 256 + 1
    local pa, pb, pc = positions[ia], positions[ib], positions[ic]
    local va, vb, vc = vertices[ia], vertices[ib], vertices[ic]
    if pa and pb and pc and va and vb and vc then
      -- THE PLANE OF THE TRIANGLE IN THE GROUND AXES. A grass quad is flat and
      -- its mapping is linear, so y, u and v are each an affine function of
      -- (x, z) and one barycentric solve serves all three.
      local det = (pb[3] - pc[3]) * (pa[1] - pc[1])
                + (pc[1] - pb[1]) * (pa[3] - pc[3])
      if math.abs(det) > 1e-6 then
        local xlo = math.min(pa[1], pb[1], pc[1])
        local xhi = math.max(pa[1], pb[1], pc[1])
        local zlo = math.min(pa[3], pb[3], pc[3])
        local zhi = math.max(pa[3], pb[3], pc[3])
        -- The nudge keeps a quad whose edge sits exactly on a tile boundary
        -- from claiming the tile beyond it -- the corner-vs-centre problem the
        -- old comment describes, arriving from the other side.
        local tx0 = math.floor(xlo / tileUnits + 1e-4)
        local tx1 = math.floor((xhi - 1e-4) / tileUnits)
        local tz0 = math.floor(zlo / tileUnits + 1e-4)
        local tz1 = math.floor((zhi - 1e-4) / tileUnits)
        for tz = tz0, tz1 do
          for tx = tx0, tx1 do
            local key = ("%d,%d"):format(tx, tz)
            if not tiles[key] then
              local cx = (tx + 0.5) * tileUnits
              local cz = (tz + 0.5) * tileUnits
              local w1 = ((pb[3] - pc[3]) * (cx - pc[1])
                        + (pc[1] - pb[1]) * (cz - pc[3])) / det
              local w2 = ((pc[3] - pa[3]) * (cx - pc[1])
                        + (pa[1] - pc[1]) * (cz - pc[3])) / det
              local w3 = 1 - w1 - w2
              -- INSIDE THIS TRIANGLE, with a hair of slack so a centre landing
              -- exactly on the shared edge of two triangles is not dropped by
              -- both of them.
              if w1 >= -1e-4 and w2 >= -1e-4 and w3 >= -1e-4 then
                local function lerp(fa, fb, fc) return w1 * fa + w2 * fb + w3 * fc end
                -- HOW FAST THE TEXTURE RUNS OVER THE GROUND, solved on this
                -- triangle rather than assumed to be one tile per repeat: a
                -- chunk whose grass sits in a corner of the atlas has its own
                -- rate, and that is what decides the card's rectangle.
                local iu = ((pb[3] - pc[3]) * (va[4] - vc[4])
                          + (pc[3] - pa[3]) * (vb[4] - vc[4])) / det
                local iv = ((pa[1] - pc[1]) * (vb[5] - vc[5])
                          + (pc[1] - pb[1]) * (va[5] - vc[5])) / det
                local u = lerp(va[4], vb[4], vc[4])
                local v = lerp(va[5], vb[5], vc[5])
                local tile = {
                  cx = cx, cz = cz,
                  -- THE GROUND AT THIS TILE'S OWN CENTRE, which is the whole of
                  -- the "too tall" fix: a group minimum over a 4x4 patch of
                  -- slope is metres below the tile the card stands on.
                  y = lerp(pa[2], pb[2], pc[2]),
                  -- EXACTLY ONE TILE OF TEXTURE, in each axis, whichever way
                  -- the mapping runs. The old rectangle was the whole merged
                  -- quad's and repeated once per tile it spanned.
                  uLo = u - iu * half, uHi = u + iu * half,
                  vLo = v - iv * half, vHi = v + iv * half,
                }
                tiles[key] = tile
                order[#order + 1] = tile
              end
            end
          end
        end
      end
    end
  end

  local verts, map = {}, {}
  local lo = { math.huge, math.huge, math.huge }
  local hi = { -math.huge, -math.huge, -math.huge }
  for _, tile in ipairs(order) do
    local cx, cz = tile.cx, tile.cz
    local y0, y1 = tile.y, tile.y + tileUnits
    local base = #verts
    -- The pivot is the card's FOOT, so it turns about where it is planted --
    -- the same rule the trees needed, and for the same reason.
    verts[#verts + 1] =
      { cx - half, y0, cz, tile.uLo, tile.vHi, 1, 1, 1, 1, cx, cz, 1 }
    verts[#verts + 1] =
      { cx + half, y0, cz, tile.uHi, tile.vHi, 1, 1, 1, 1, cx, cz, 1 }
    verts[#verts + 1] =
      { cx + half, y1, cz, tile.uHi, tile.vLo, 1, 1, 1, 1, cx, cz, 1 }
    verts[#verts + 1] =
      { cx - half, y1, cz, tile.uLo, tile.vLo, 1, 1, 1, 1, cx, cz, 1 }
    map[#map + 1] = base + 1; map[#map + 1] = base + 2; map[#map + 1] = base + 3
    map[#map + 1] = base + 1; map[#map + 1] = base + 3; map[#map + 1] = base + 4
    if cx - half < lo[1] then lo[1] = cx - half end
    if cx + half > hi[1] then hi[1] = cx + half end
    if y0 < lo[2] then lo[2] = y0 end
    if y1 > hi[2] then hi[2] = y1 end
    if cz < lo[3] then lo[3] = cz end
    if cz > hi[3] then hi[3] = cz end
  end
  if #verts == 0 then return false end

  local okMesh, mesh =
    pcall(love.graphics.newMesh, FORMAT, verts, "triangles", "static")
  if not (okMesh and mesh) then return false end
  pcall(mesh.setVertexMap, mesh, map)
  mesh:setTexture(image)
  self.shapes[#self.shapes + 1] = {
    mesh = mesh, name = (shape.name or "grass") .. "Cards", index = nil,
    material = shape.texture, image = image,
    lo = lo, hi = hi,
  }
  return true
end
-- ---------------------------------------------------------------------------
-- SPLITTING A WALL COURSE INTO ITS SIDING AND ITS GLASS
-- ---------------------------------------------------------------------------
--
-- Reported from play: *"the houses have repeating window textures maybe just
-- do one window and fill the rest with the wood texture"*.
--
-- Correct, and the cause is that not every band is a course.  `t1_s01`'s wall
-- rect is 36 x 30 texels of siding-window-siding, and the cartridge puts it on
-- ONE quad per side wall -- a panel with a window in it, never repeated.
-- `t1_h01`'s rect really is a course and really does tile, twice per side wall
-- and mirrored.  Tiling both gives one right wall and one wall of windows.
--
-- WHAT SEPARATES THEM IS PURE WHITE.  Read off the two textures: `t1_h01`'s
-- band runs from 0.542 to 0.821 luminance and never touches white, while
-- `t1_s01`'s glass is exactly 1.000 against siding at 0.756 to 0.871.  Glass
-- is the only thing in a Platinum house wall drawn at the palette's white, and
-- a band with none in it is siding all the way across.
--
-- The FRAME around the glass is found without a second number: among the
-- columns that carry no white, the profile that occurs most often is the
-- siding (on `t1_s01`, ten columns of thirty-six), and the window block is
-- grown outward from the glass for as long as the next column is not that
-- profile.  That takes in the grey surround and the two courses beside it and
-- stops at the first real siding column -- exactly, with nothing tuned.
local bandSplitCache = {}
local function splitWallBand(path, band, tw, th)
  if not (path and band and tw and th) then return nil end
  local key = ("%s|%d|%d|%d|%d"):format(path,
    band.uLo * 16, band.uHi * 16, band.vLo * 16, band.vHi * 16)
  local hit = bandSplitCache[key]
  if hit ~= nil then return hit or nil end

  -- `Assets.image` hands back a placeholder for a path that is not there --
  -- that is what buried the indoor shadows for a whole pass -- so the pixels
  -- are read with the call that RAISES instead.
  local okData, data = pcall(function()
    return love.image.newImageData(Assets.resolve(path))
  end)
  if not (okData and data) then bandSplitCache[key] = false return nil end

  local u0, v0 = math.floor(band.uLo), math.floor(band.vLo)
  local w = math.floor(band.uHi - band.uLo + 0.5)
  local h = math.floor(band.vHi - band.vLo + 0.5)
  if w < 2 or h < 1 then bandSplitCache[key] = false return nil end

  local profile, white = {}, {}
  for i = 0, w - 1 do
    local parts, hasWhite = {}, false
    for j = 0, h - 1 do
      local okPx, r, g, b = pcall(data.getPixel, data,
                                  (u0 + i) % tw, (v0 + j) % th)
      if not okPx then bandSplitCache[key] = false return nil end
      if r >= 0.999 and g >= 0.999 and b >= 0.999 then hasWhite = true end
      parts[#parts + 1] = ("%d,%d,%d"):format(r * 255, g * 255, b * 255)
    end
    profile[i] = table.concat(parts, ";")
    white[i] = hasWhite
  end

  local first, last
  for i = 0, w - 1 do
    if white[i] then
      if first == nil then first = i end
      last = i
    end
  end
  -- No glass: the whole band is siding and tiles as it always did.
  if first == nil then bandSplitCache[key] = false return nil end

  local counts, sidingProfile, sidingCount = {}, nil, 0
  for i = 0, w - 1 do
    if not white[i] then
      local n = (counts[profile[i]] or 0) + 1
      counts[profile[i]] = n
      if n > sidingCount then sidingCount, sidingProfile = n, profile[i] end
    end
  end
  if not sidingProfile then bandSplitCache[key] = false return nil end

  while first > 0 and profile[first - 1] ~= sidingProfile do first = first - 1 end
  while last < w - 1 and profile[last + 1] ~= sidingProfile do last = last + 1 end

  -- The widest unbroken run of siding left over is what the wall is filled
  -- with.  Courses are horizontal, so any slice of them tiles invisibly.
  local bestLo, bestHi, runLo = nil, nil, nil
  for i = 0, w do
    local siding = (i < w) and (profile[i] == sidingProfile) or false
    if siding and runLo == nil then runLo = i end
    if not siding and runLo ~= nil then
      if bestLo == nil or (i - runLo) > (bestHi - bestLo + 1) then
        bestLo, bestHi = runLo, i - 1
      end
      runLo = nil
    end
  end
  if bestLo == nil then bandSplitCache[key] = false return nil end

  local out = {
    fillLo = band.uLo + bestLo, fillHi = band.uLo + bestHi + 1,
    featLo = band.uLo + first, featHi = band.uLo + last + 1,
  }
  bandSplitCache[key] = out
  return out
end

-- CLOSE A BUILDING'S MISSING BACK.
--
-- Requested: *"the backs of buildings are blank which is normal for the rom but
-- we should find a way to fill the back with a texture that fits in"*, and
-- later *"they should use textures from the building they are a part of so they
-- look natural"*.
--
-- The cartridge really does omit it -- the camera only ever looks north, so the
-- north face is never seen and was never modelled.  Measured on Twinleaf's own
-- house `t1_h01`: 158 triangles, **0 facing north**, against 50 south, 43 east,
-- 41 west and 24 up.  `c1_b02b` has 2 north against 96 south.
--
-- EDGE-LOOP CAPPING WAS THE PLAN AND IT DOES NOT WORK HERE.  Capping needs a
-- boundary loop, and this geometry has no boundary: `t1_h01` has **273 open
-- edges of 360** because the walls are separate quads that share no vertices.
-- There is no loop to walk.
--
-- So the back is built from the building's own WALLS instead: their outline
-- gives its shape, their outermost planes give its width and the plane it
-- stands on, and one of their faces gives the course it is tiled with.  Four
-- separate measurements, each with its own note below, and the whole point of
-- taking them from the walls is that a back built this way has no numbers of
-- its own to be wrong.
--
-- Right for a boxy house, which is what Sinnoh's are; an L-shaped building
-- gets a flat back across its extent rather than a fitted one, and that is the
-- honest limit of a single plane.
--
-- WHAT THIS COSTS, measured: with the back on, Twinleaf drawn at the cartridge
-- rung is pixel-identical to Twinleaf without it -- 0 differing pixels of
-- 307,200 -- and the third-person view from the FRONT differs by 21, while the
-- view from BEHIND differs by 15.7 per cent.  A control that changes nothing
-- where nothing should change and everything where it should.
local function addBackWall(self)
  local north, south = 0, 0
  local widest, widestArea = nil, -1
  for _, shape in ipairs(self.shapes) do
    north = north + (shape.facing and shape.facing.north or 0)
    south = south + (shape.facing and shape.facing.south or 0)
    -- THE SHAPE WHOSE WALL COURSE COVERS THE MOST OF THE BUILDING, not the
    -- one with the most side-facing triangles.  A count is not an area: a
    -- flight of steps can carry more east/west triangles than the wall behind
    -- it.
    local area = shape.wallBand and shape.wallBand.area or -1
    if area > widestArea then widestArea, widest = area, shape end
  end
  -- ...AND IF NO SHAPE HAS A COURSE, THE BIGGEST PLAIN WALL INSTEAD.
  local flat
  if not (widest and widest.wallBand) then
    local best = -1
    for _, shape in ipairs(self.shapes) do
      local fb = shape.flatBand
      if fb and shape.image and fb.area > best then
        best, widest, flat = fb.area, shape, fb
      end
    end
  end
  -- A model with no south face at all is not a building with a missing back.
  -- Whether it ALREADY has a back is decided further down, against the
  -- opening this would actually fill, because a ratio of triangle counts got
  -- that wrong for the two buildings it matters most for.
  if south == 0 then return false end
  local _ = north
  if not (widest and widest.image and (widest.wallBand or flat)) then
    return false
  end
  -- A flat wall is a band whose rectangle is a point: one cell wide, one row
  -- tall, the same texel everywhere.  Everything below then works unchanged --
  -- the triangle wave has no span to sweep, the sawtooth no height to climb,
  -- and `splitWallBand` declines a rect it cannot read a column from.
  local band = widest.wallBand
  -- THE TEXTURE'S OWN SIZE, because the mesh format wants 0..1 and the band
  -- was measured in texels.
  --
  -- This is the fault the first version shipped with, and it was visible from
  -- ten feet away: a texel count was written straight into a 0..1 coordinate,
  -- so a 64-pixel texture repeated sixty-four times faster than it should and
  -- every back wall came out as noise.  Reported as *"doesnt seem to be using
  -- the right scale of texture"* -- which it was not, by a factor of `tw`.
  local okW, tw = pcall(widest.image.getWidth, widest.image)
  local okH, th = pcall(widest.image.getHeight, widest.image)
  if not (okW and okH and tw and th and tw > 0 and th > 0) then return false end

  local lo = { math.huge, math.huge, math.huge }
  local hi = { -math.huge, -math.huge, -math.huge }
  for _, shape in ipairs(self.shapes) do
    if shape.lo and shape.hi then
      for k = 1, 3 do
        if shape.lo[k] < lo[k] then lo[k] = shape.lo[k] end
        if shape.hi[k] > hi[k] then hi[k] = shape.hi[k] end
      end
    end
  end
  if lo[1] > hi[1] or lo[2] > hi[2] then return false end
  if not band then
    band = { uLo = flat.u, uHi = flat.u, vLo = flat.v, vHi = flat.v,
             vAtFoot = flat.v, yFoot = lo[2],
             width = (hi[1] - lo[1]) + 1, height = (hi[2] - lo[2]) + 1,
             area = flat.area }
  end

  -- A FLAT PANEL IS NOT A BUILDING WITH A MISSING BACK.
  --
  -- `door01` passed the north/south test -- a door faces south and has no
  -- north side, exactly like a house -- and would have got a wall the size of
  -- the door standing behind it.  It is 3.9 deep against 19.5 wide; a Twinleaf
  -- house is 44 deep against 67.  What separates them is DEPTH: a thing with
  -- no depth has no inside to close, and its "back" is the wall it is stuck to.
  local width = hi[1] - lo[1]
  local height = hi[2] - lo[2]
  local depth = hi[3] - lo[3]
  local across = (width > height) and width or height
  if across < 1e-6 or depth < across * 0.25 then return false end

  -- IT FOLLOWS THE BUILDING'S SILHOUETTE, not its bounding box.
  --
  -- The first version was one rectangle across the whole box, and the
  -- CARTRIDGE view changed by 3,887 pixels when it should not have changed at
  -- all: a gabled roof slopes down to the eaves, so a rectangle reaching the
  -- RIDGE height sticks out past the roof on both sides, and those corners
  -- showed as two red triangles over every house.
  --
  -- THE OUTLINE COMES FROM THE WALL TRIANGLES, NOT FROM WHOLE SHAPES.
  --
  -- Three separate adjustments -- inset the height, move to the wall line,
  -- shrink the box -- each moved the stray-pixel count by about ten, which is
  -- the signature of guessing at a cause rather than finding one.  The cause
  -- is that the ROOF overhangs the walls on every axis, so a silhouette that
  -- includes it puts a wall out under the eaves on all sides at once.
  --
  -- Excluding whole shapes whose faces mostly point up was the first attempt
  -- and it excludes nothing on the buildings that matter: `t1_h01` is ONE
  -- shape carrying its walls and its roof together.  `wallTris` lists the
  -- triangles that are not up- or down-facing, so the silhouette is the walls'
  -- and the gable end's -- which is exactly the outline a back should fill.
  -- NORTH IS -Z -- AND THE WALL LINE IS NOT THE BOX'S NORTH EDGE.
  --
  -- The box's north extent is the ROOF OVERHANG, which reaches further north
  -- than the walls do.  Placing the back there put it out under the eaves
  -- where the roof does not cover it, and it showed from the front as thin
  -- vertical slivers at each gable corner -- 259 stray pixels on a view that
  -- must not change.  Tucking it half a unit lower barely moved that (253),
  -- which is what said the fault was depth and not height.
  --
  -- Nor is it the SHAPE's north edge, which was the next guess and no better:
  -- `t1_h01` is one shape carrying its walls and its roof, so its north edge
  -- IS the overhang, at -22.00.
  --
  -- Nor is it the plane of the faces wearing the wall COURSE, which was the
  -- guess after that and is the one that shipped.  Reported from play:
  -- *"theyre a bit too far inside of the house rather than fitting on the
  -- back"*, and that is exactly right -- `t1_h01`'s chosen course is worn by
  -- two quads that stop at -13.75 while the walls carry on to -19.75, so the
  -- back stood six units inside its own house.  A course is a texture, and
  -- where a texture stops is not where a building stops.
  --
  -- It is the northmost WALL FACE: every triangle that is not up- or
  -- down-facing, which is the same set the silhouette is drawn from.  Measured
  -- over six buildings it agrees with the northmost east/west face every time
  -- and sits 1 to 3 units south of the bounding box -- the roof overhang,
  -- which is the one thing it has to exclude.
  -- ...AND IT IS NOT SIMPLY THE NORTHMOST WALL FACE EITHER.
  --
  -- `c1_b01a`'s northmost wall stands two units proud of the house and is a
  -- PLINTH: the cross-section there is eight triangles reaching 11.30 where
  -- the building is 102 tall, and a back drawn to it came out with no height
  -- and was dropped.  So the wall planes are tried from the north inward and
  -- the first one where the building is still at least half its own height is
  -- taken.  There is no slope to sit on: the rejected plane is 11 per cent of
  -- the height and the accepted one 96, while every other building measured
  -- passes at its very first plane at 100.
  local candidates, seenZ = {}, {}
  for _, shape in ipairs(self.shapes) do
    for _, zw in ipairs(shape.wallZs or {}) do
      local q = math.floor(zw * 16 + 0.5)
      if not seenZ[q] then seenZ[q] = true; candidates[#candidates + 1] = zw end
    end
  end
  table.sort(candidates)
  local enough = lo[2] + (hi[2] - lo[2]) * 0.5
  local wallZ
  for _, zc in ipairs(candidates) do
    local top = -math.huge
    for _, shape in ipairs(self.shapes) do
      local pos, tri = shape.outline, shape.tris
      for t = 1, (pos and tri and #tri or 0), 3 do
        local pa, pb, pc = pos[tri[t]], pos[tri[t + 1]], pos[tri[t + 2]]
        if pa and pb and pc then
          local zl = (pa[3] < pb[3] and pa[3] or pb[3])
          if pc[3] < zl then zl = pc[3] end
          local zh = (pa[3] > pb[3] and pa[3] or pb[3])
          if pc[3] > zh then zh = pc[3] end
          if zl <= zc and zh >= zc then
            if pa[2] > top then top = pa[2] end
            if pb[2] > top then top = pb[2] end
            if pc[2] > top then top = pc[2] end
          end
        end
      end
    end
    if top >= enough then wallZ = zc break end
  end
  if not wallZ then
    for _, shape in ipairs(self.shapes) do
      local zw = shape.wallZLo
      if zw and (wallZ == nil or zw < wallZ) then wallZ = zw end
    end
  end
  if not wallZ then wallZ = (widest.lo and widest.lo[3]) or lo[3] end
  -- The cross-section is taken at the wall plane itself and the quad is drawn
  -- a twentieth of a unit south of it.  Sectioning at the drawn plane instead
  -- drops every flat face that ENDS at the wall line -- zero z extent, so it
  -- crosses nothing -- and `c1_b01a`'s back collapsed to no height at all.
  local zSection = wallZ
  local z = wallZ + 0.05

  -- ...AND IT IS TUCKED A LITTLE UNDER THE ROOFLINE.
  --
  -- The silhouette is sampled on a sixteenth-of-a-unit grid, so a sloping
  -- gable leaves a staircase whose corners can stand a fraction proud of the
  -- real roof edge.  Half a unit of inset puts the wall under the roof rather
  -- than through it, and is invisible from behind because the roof covers it.
  local INSET = 0.5

  local xs, seen = {}, {}
  for _, shape in ipairs(self.shapes) do
    local pos, tri = shape.outline, shape.tris
    for t = 1, (pos and tri and #tri or 0), 3 do
      local pa, pb, pc = pos[tri[t]], pos[tri[t + 1]], pos[tri[t + 2]]
      if pa and pb and pc then
        local zlo = (pa[3] < pb[3] and pa[3] or pb[3])
        if pc[3] < zlo then zlo = pc[3] end
        local zhi = (pa[3] > pb[3] and pa[3] or pb[3])
        if pc[3] > zhi then zhi = pc[3] end
        if zlo <= zSection and zhi >= zSection then
          for e = 1, 3 do
            local v = (e == 1 and pa) or (e == 2 and pb) or pc
            local key = math.floor(v[1] * 16 + 0.5)
            if not seen[key] then seen[key] = true; xs[#xs + 1] = key end
          end
        end
      end
    end
  end
  if #xs < 2 then return false end
  table.sort(xs)


  -- THE WALL IS TILED WITH ITS OWN COURSE, not stretched across the span.
  --
  -- `t1_h01`'s side wall is TWO quads that share an edge, 11.75 units wide
  -- each, and the second one runs its u backwards -- 28 texels forwards, then
  -- 28 texels back.  The cartridge mirrors the course rather than repeating
  -- it, which is why the wall has no visible seam down its middle.  The back
  -- is tiled the same way, so it matches the sides it joins at the corner.
  --
  -- u is therefore a triangle wave, and CONTINUOUS at every band edge, so one
  -- value per x is well defined no matter which cell a breakpoint is read in.
  -- The wall's own x extent, from the silhouette rather than the box -- the
  -- box's is the roof's.
  local wallXLo, wallXHi = xs[1] / 16, xs[#xs] / 16
  -- WHAT THE WALL IS FILLED WITH: the band's siding, with its window taken
  -- out and set aside to be stamped once.  `splitWallBand` returns nil for a
  -- band that is siding all the way across, and then the whole band tiles as
  -- before.
  local split = splitWallBand(widest.imagePath, band, tw, th)
  local density = (band.uHi - band.uLo) / band.width
  local tileULo = split and split.fillLo or band.uLo
  local tileUHi = split and split.fillHi or band.uHi
  local tileW = (tileUHi - tileULo) / density
  if not (tileW > 1e-6) then tileULo, tileUHi, tileW = band.uLo, band.uHi, band.width end
  local uSpan = tileUHi - tileULo
  local function uAt(x)
    local t = (x - wallXLo) / tileW
    local cell = math.floor(t)
    local f = t - cell
    if cell % 2 ~= 0 then f = 1 - f end
    return (tileULo + uSpan * f) / tw
  end
  -- v REPEATS rather than mirroring, because a course of siding read upside
  -- down is not a course of siding.  A sawtooth is discontinuous at each row
  -- edge, so it is evaluated against a KNOWN row instead of from y alone, and
  -- the rows are cut exactly on those edges below.
  local vFoot = band.vAtFoot
  local vHead = (vFoot == band.vHi) and band.vLo or band.vHi
  local function vAt(row, y)
    local f = (y - (band.yFoot + row * band.height)) / band.height
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    return (vFoot + (vHead - vFoot) * f) / th
  end

  -- THE BACK IS NO WIDER THAN THE SIDES IT JOINS.
  --
  -- The silhouette is the building's cross-section and it includes the FRONT
  -- facade, which on `t1_h01` reaches 32 units either side while the side
  -- walls stand at 29.  Three units of back wall then stood proud of each
  -- corner and showed from the front as a red sliver down both houses --
  -- 3,805 pixels on a view that must not change.
  --
  -- Clamping to the outermost east/west planes either does nothing or pulls
  -- in: measured over twelve placed buildings it never widened one.
  do
    -- ...AND ONLY THE SIDE WALLS THAT REACH THE BACK PLANE.
    --
    -- A building with a wide front and a narrow back has no single width, and
    -- taking the widest anywhere left a back wall standing several pixels
    -- proud of the near corner of the house closest to the camera -- 1,592 of
    -- the 1,757 stray pixels left in the front view came from that one
    -- building.
    -- A CLAMP THAT MAY DECLINE.
    --
    -- The section's own width is the roof's, so it has to be pulled in to the
    -- walls -- but only where the wall being pulled to is the SAME wall.  The
    -- side planes crossing the back are tried first and the outermost planes
    -- second, and each side takes the first candidate that moves it by no more
    -- than a tenth of the section's width.
    --
    -- Insisting on the crossing planes was tried and it is far too strong:
    -- `t1_s01`, `t1_s02` and `t2_s02` have nothing at the back plane but a
    -- narrow pair of faces, and their backs collapsed to a 7.5-unit sliver on
    -- a 90-unit house, while `t2_s01`'s lost its whole right half.
    local secLo, secHi = xs[1] / 16, xs[#xs] / 16
    local limit = (secHi - secLo) * 0.1
    local crossLo, crossHi, anyLo, anyHi
    for _, shape in ipairs(self.shapes) do
      local pl = shape.sidePlanes
      for i = 1, (pl and #pl or 0), 3 do
        local px = pl[i]
        anyLo = (anyLo == nil or px < anyLo) and px or anyLo
        anyHi = (anyHi == nil or px > anyHi) and px or anyHi
        if pl[i + 1] <= zSection and pl[i + 2] >= zSection then
          crossLo = (crossLo == nil or px < crossLo) and px or crossLo
          crossHi = (crossHi == nil or px > crossHi) and px or crossHi
        end
      end
    end
    --
    -- The tenth-of-the-width test chooses BETWEEN the two candidates; it does
    -- not decide whether to clamp at all.  A back wider than every side wall
    -- the building owns is wrong however far apart they are, so the outermost
    -- plane is taken unconditionally when neither candidate is close -- which
    -- is what was left showing as a four-pixel strip down the near corner of
    -- the house closest to the camera, on a building whose roof overhangs by
    -- more than a tenth of its width.
    local function pick(current, cross, any, inward)
      if cross and (cross - current) * inward > 0
         and (cross - current) * inward <= limit then return cross end
      if any and (any - current) * inward > 0
         and (any - current) * inward <= limit then return any end
      if any and (any - current) * inward > 0 then return any end
      return current
    end
    local sxLo = pick(secLo, crossLo, anyLo, 1)
    local sxHi = pick(secHi, crossHi, anyHi, -1)
    -- ...AND THE CLADDING'S OWN PLANE BEATS THE OUTERMOST FACE WHEN THEY ARE
    -- THE SAME WALL.
    --
    -- `t1_h01`'s outermost east/west faces stand at 29.00 and its clapboard at
    -- 28.00: a one-unit strip of trim on the same wall.  A back drawn to 29
    -- reaches a unit past the cladding and is visible from the front as a
    -- clapboard sliver down the house's corner, which is what 846 stray pixels
    -- looked like when cropped and enlarged.
    --
    -- A tenth of the building's width separates the two cases cleanly on the
    -- twelve buildings placed here: where the course's plane and the outermost
    -- plane are the same wall they differ by 0.04 to 5 per cent (t1_h01 1.7,
    -- c1_b01 3, c1_school1 2 to 3.5, t1_s01 0.7 to 5), and where they are
    -- genuinely different walls -- a course worn only by a narrow pair of
    -- faces, or a wing that the course does not reach -- they differ by 14, 37
    -- and 45.  Nothing measured falls between.
    if sxLo and sxHi and sxHi > sxLo and band.xLo and band.xHi then
      local span = (sxHi - sxLo) * 0.1
      if band.xLo > sxLo and (band.xLo - sxLo) <= span then sxLo = band.xLo end
      if band.xHi < sxHi and (sxHi - band.xHi) <= span then sxHi = band.xHi end
    end
    if sxLo and sxHi and sxHi > sxLo then
      local kLo = math.floor(sxLo * 16 + 0.5)
      local kHi = math.floor(sxHi * 16 + 0.5)
      if kLo > xs[1] or kHi < xs[#xs] then
        local keep = {}
        for _, k in ipairs(xs) do
          if k > kLo and k < kHi then keep[#keep + 1] = k end
        end
        table.insert(keep, 1, kLo)
        keep[#keep + 1] = kHi
        xs = keep
      end
      wallXLo, wallXHi = kLo / 16, kHi / 16
    end
  end

  -- Cut the wall on the band edges as well as the silhouette's corners, so
  -- every cell carries one unbroken run of the course.
  do
    local extra = {}
    local k = 1
    while true do
      local x = wallXLo + k * tileW
      if x >= wallXHi - 1e-6 then break end
      local key = math.floor(x * 16 + 0.5)
      if not seen[key] then seen[key] = true; extra[#extra + 1] = key end
      k = k + 1
      if k > 4096 then break end
    end
    for _, key in ipairs(extra) do xs[#xs + 1] = key end
    if #extra > 0 then table.sort(xs) end
  end

  -- THE ROOFLINE, AS THE UPPER ENVELOPE OF THE CROSS-SECTION AT z.
  --
  -- Taking the highest VERTEX at each sampled x is not the outline -- it is a
  -- sample of it, and the two disagree wherever a triangle spans an x that
  -- carries no vertex of its own.  Looked at from behind, that showed as two
  -- pale spikes standing above `t1_h01`'s gable and a dark wedge beside them
  -- where the wall stopped short and the roof's underside showed through.
  --
  -- Asking each triangle how high it reaches AT this x answers the same
  -- question exactly: the envelope's breakpoints are triangle corners, so
  -- sampling at every corner and at every band edge loses nothing between
  -- them.
  --
  -- AND ONLY THE TRIANGLES THAT CROSS THE BACK PLANE, which is the fix that
  -- the raised inset and the three rear-plane choices could not be: taking the
  -- outline over the WHOLE model gives the building's tallest cross-section
  -- anywhere, and Twinleaf's two-storey houses are tall at the FRONT and low
  -- at the back.  Their backs were drawn to the front block's height and stood
  -- up behind their own roofs -- 312 stray pixels in the cartridge view,
  -- entirely on those houses, with the single-storey ones clean.  Raising the
  -- inset eightfold only took it to 217, which is what said the height was not
  -- the fault.
  --
  -- The roof is included here where the walls are not.  Over the hole the back
  -- is closing there IS no wall, so the roof's underside is the only thing
  -- that states the shape of the opening -- and it states it exactly: on
  -- `t1_h01` the cross-section reads 72.50 at the ridge and 50.63 at the
  -- cladding line, which is the gable.
  local column = {}
  do
    local kept = {}
    for _, key in ipairs(xs) do
      -- `best` is the section's answer; `spare` is the whole model's, used
      -- only where the section has nothing to say.
      --
      -- `c1_b01a`'s northmost wall face is a low plinth standing two units
      -- proud of the house, so the section at the back plane is eight
      -- triangles reaching 11.30 where the building is 98 tall -- and the back
      -- came out with no height at all and was dropped.  Where the section is
      -- silent the model's own outline answers instead, which is what this did
      -- before the section existed.
      local x, best, spare = key / 16, nil, nil
      for _, shape in ipairs(self.shapes) do
        local pos, tri = shape.outline, shape.tris
        for t = 1, (pos and tri and #tri or 0), 3 do
          local pa, pb, pc = pos[tri[t]], pos[tri[t + 1]], pos[tri[t + 2]]
          if pa and pb and pc then
            local xa, xb, xc = pa[1], pb[1], pc[1]
            local xlo = (xa < xb and xa or xb); if xc < xlo then xlo = xc end
            local xhi = (xa > xb and xa or xb); if xc > xhi then xhi = xc end
            local zlo = (pa[3] < pb[3] and pa[3] or pb[3])
            if pc[3] < zlo then zlo = pc[3] end
            local zhi = (pa[3] > pb[3] and pa[3] or pb[3])
            if pc[3] > zhi then zhi = pc[3] end
            local crosses = (zlo <= zSection and zhi >= zSection)
            if x >= xlo - 0.03125 and x <= xhi + 0.03125 then
              -- the three edges, and any corner standing on this x
              for e = 1, 3 do
                local p = (e == 1 and pa) or (e == 2 and pb) or pc
                local q = (e == 1 and pb) or (e == 2 and pc) or pa
                local dx = q[1] - p[1]
                if dx > 1e-6 or dx < -1e-6 then
                  local f = (x - p[1]) / dx
                  if f >= 0 and f <= 1 then
                    local y = p[2] + (q[2] - p[2]) * f
                    if crosses then
                      if best == nil or y > best then best = y end
                    elseif spare == nil or y > spare then spare = y
                    end
                  end
                end
                if p[1] >= x - 0.03125 and p[1] <= x + 0.03125 then
                  if crosses then
                    if best == nil or p[2] > best then best = p[2] end
                  elseif spare == nil or p[2] > spare then spare = p[2]
                  end
                end
              end
            end
          end
        end
      end
      if best == nil then best = spare end
      if best then
        local y = best - INSET
        column[key] = (y > lo[2]) and y or lo[2]
        kept[#kept + 1] = key
      end
    end
    xs = kept
  end
  if #xs < 2 then return false end

  -- IS THERE ALREADY A BACK HERE?  Asked against the opening, not by counting
  -- triangles.
  --
  -- The old test -- north-facing triangles must be under a tenth of the
  -- south-facing ones -- threw out the Pokemon Centre and the Poke Mart, the
  -- two buildings in Sinnoh a player walks behind most, and it threw them out
  -- for the wrong reason twice over: their roofs contributed most of those
  -- "north" faces, and what vertical north wall they do have covers only part
  -- of the opening.  Reported: *"the pokemarts, and pokemon centers are
  -- missing backs still"*.
  --
  -- Comparing like with like instead: the wall area that already faces north
  -- AT the back plane, against the area this would add.  A model whose back is
  -- genuinely modelled covers its own opening and is left alone; one that
  -- covers a third of it gets the rest.
  do
    local opening = 0
    for i = 1, #xs - 1 do
      local w = (xs[i + 1] - xs[i]) / 16
      local h0 = column[xs[i]] - lo[2]
      local h1 = column[xs[i + 1]] - lo[2]
      opening = opening + w * (h0 + h1) * 0.5
    end
    local covered = 0
    for _, shape in ipairs(self.shapes) do
      local nw = shape.northWalls
      for i = 1, (nw and #nw or 0), 2 do
        if nw[i] <= wallZ + 1 and nw[i] >= wallZ - 1 then
          covered = covered + nw[i + 1]
        end
      end
    end
    if opening <= 1e-6 or covered >= opening * 0.9 then return false end
  end

  local rowLo = math.floor((lo[2] - band.yFoot) / band.height)
  local vertices, map = {}, {}
  for i = 1, #xs - 1 do
    local x0, x1 = xs[i] / 16, xs[i + 1] / 16
    local y0, y1 = column[xs[i]], column[xs[i + 1]]
    local top = (y0 > y1) and y0 or y1
    local rowHi = math.floor((top - band.yFoot) / band.height)
    for row = rowLo, rowHi do
      local rb = band.yFoot + row * band.height
      local rt = rb + band.height
      -- Each corner is clipped to the roofline above it and the ground below,
      -- so a gable ends as a wedge rather than a staircase.
      local function clip(y, cap)
        if y < lo[2] then return lo[2] end
        if y > cap then return cap end
        return y
      end
      local a0, a1 = clip(rb, y0), clip(rt, y0)
      local b0, b1 = clip(rb, y1), clip(rt, y1)
      if (a1 - a0) > 1e-4 or (b1 - b0) > 1e-4 then
        local ua, ub = uAt(x0), uAt(x1)
        local base = #vertices
        vertices[#vertices + 1] =
          { x0, a0, z, ua, vAt(row, a0), 1, 1, 1, 1, 0, 0, 0 }
        vertices[#vertices + 1] =
          { x1, b0, z, ub, vAt(row, b0), 1, 1, 1, 1, 0, 0, 0 }
        vertices[#vertices + 1] =
          { x1, b1, z, ub, vAt(row, b1), 1, 1, 1, 1, 0, 0, 0 }
        vertices[#vertices + 1] =
          { x0, a1, z, ua, vAt(row, a1), 1, 1, 1, 1, 0, 0, 0 }
        map[#map+1] = base + 1; map[#map+1] = base + 2; map[#map+1] = base + 3
        map[#map+1] = base + 1; map[#map+1] = base + 3; map[#map+1] = base + 4
      end
    end
  end
  -- ONE WINDOW, where the cartridge puts one.
  --
  -- Stamped rather than tiled, at the height the side wall carries it and
  -- centred across the back, with the band's own full v range so its courses
  -- run straight into the siding either side of it.  It sits a fiftieth of a
  -- unit north of the wall, which is in front of it from every angle that can
  -- see the back at all.
  if split and #vertices > 0 then
    local featW = (split.featHi - split.featLo) / density
    local mid = (wallXLo + wallXHi) * 0.5
    local fx0, fx1 = mid - featW * 0.5, mid + featW * 0.5
    local fy0 = band.yFoot
    local fy1 = fy0 + band.height
    -- Only where there is wall to put it on: it must fit between the corners
    -- and stand below the roofline at both of its own edges.
    local room = true
    if not (featW > 1e-6 and fx0 > wallXLo and fx1 < wallXHi and fy0 >= lo[2]) then
      room = false
    else
      for _, key in ipairs(xs) do
        local kx = key / 16
        if kx >= fx0 - 1e-6 and kx <= fx1 + 1e-6 and column[key] < fy1 then
          room = false
          break
        end
      end
    end
    if room then
      local fz = z - 0.02
      local ua, ub = split.featLo / tw, split.featHi / tw
      local va, vb = vAt(0, fy0), vAt(0, fy1)
      local base = #vertices
      vertices[#vertices + 1] = { fx0, fy0, fz, ua, va, 1, 1, 1, 1, 0, 0, 0 }
      vertices[#vertices + 1] = { fx1, fy0, fz, ub, va, 1, 1, 1, 1, 0, 0, 0 }
      vertices[#vertices + 1] = { fx1, fy1, fz, ub, vb, 1, 1, 1, 1, 0, 0, 0 }
      vertices[#vertices + 1] = { fx0, fy1, fz, ua, vb, 1, 1, 1, 1, 0, 0, 0 }
      map[#map+1] = base + 1; map[#map+1] = base + 2; map[#map+1] = base + 3
      map[#map+1] = base + 1; map[#map+1] = base + 3; map[#map+1] = base + 4
    end
  end

  if #vertices == 0 then return false end
  local okMesh, mesh =
    pcall(love.graphics.newMesh, FORMAT, vertices, "triangles", "static")
  if not (okMesh and mesh) then return false end
  pcall(mesh.setVertexMap, mesh, map)
  mesh:setTexture(widest.image)
  self.shapes[#self.shapes + 1] = {
    mesh = mesh, name = "backWall", index = nil,
    material = widest.material, image = widest.image,
    lo = { lo[1], lo[2], z }, hi = { hi[1], hi[2], z },
  }
  return true
end

-- addGroundShadow(model, path) -> did it add one?
--
-- Requested: *"implement shadows for indoor objects"*.
--
-- THE CARTRIDGE DOES NOT HAVE THESE, and that was measured before writing a
-- line of it.  153 of the 590 prop models carry real shadow geometry -- a
-- material named `h_kage`, which this file already gives a reduced alpha --
-- but they are the OUTDOOR props.  Of the models actually placed on maps, the
-- most common are interior furniture and every one of them carries none:
-- `ref01` 203 placements, `sofa01` 109, `table02` 82, `chair03` 78, `bed_h01`
-- 57, `plant01` 34 -- **zero shadow shapes each**.
--
-- So this is GENERATED, not extracted, and it is only added where the
-- cartridge left a gap: a model that already has a `kage` shape keeps its own.
--
-- Added as a SHAPE on the model rather than as a draw in the ground pass,
-- because the props are drawn from four different places (the bake, the live
-- pass, the canopy pass and the free pass) and a shadow that has to be added
-- to each is a shadow that will be missing from one.
local function addGroundShadow(self, path)
  for _, shape in ipairs(self.shapes) do
    if tostring(shape.material or ""):lower():find("kage", 1, true) then
      return false
    end
  end
  local lo = { math.huge, math.huge, math.huge }
  local hi = { -math.huge, -math.huge, -math.huge }
  for _, shape in ipairs(self.shapes) do
    if shape.lo and shape.hi then
      for k = 1, 3 do
        if shape.lo[k] < lo[k] then lo[k] = shape.lo[k] end
        if shape.hi[k] > hi[k] then hi[k] = shape.hi[k] end
      end
    end
  end
  -- A model whose shapes reported no box at all has nothing to sit under.
  if lo[1] > hi[1] or lo[3] > hi[3] then return false end
  local okImage, image = pcall(Assets.image, path)
  if not (okImage and image) then return false end

  -- THE TRANSLUCENCY IS CARRIED ON THE VERTEX, not left to `shapeAlpha`.
  --
  -- Measured: with the alpha coming only from the material name, the shadow
  -- painted 0.161,0.192,0.259 over a PALE floor and the identical colour over
  -- a DARK one -- the same patch either way, which is what opaque looks like.
  -- A plain 29%-alpha rectangle in the same harness reads 0.608 over that pale
  -- floor, so blending itself is working; the alpha simply was not arriving.
  --
  -- The shader multiplies `texel * colour` and `colour` is LOVE's vertex
  -- colour times the draw colour, so putting it here makes it independent of
  -- what `shapeAlpha` decides -- and a generated shadow should not depend on
  -- being named well enough to be recognised.
  local a = SHADOW_ALPHA_FRACTION
  local y = lo[2] + SHADOW_LIFT
  local vertices = {
    { lo[1], y, lo[3], 0, 0, 1, 1, 1, a, 0, 0, 0 },
    { hi[1], y, lo[3], 1, 0, 1, 1, 1, a, 0, 0, 0 },
    { hi[1], y, hi[3], 1, 1, 1, 1, 1, a, 0, 0, 0 },
    { lo[1], y, hi[3], 0, 1, 1, 1, 1, a, 0, 0, 0 },
  }
  local okMesh, mesh =
    pcall(love.graphics.newMesh, FORMAT, vertices, "triangles", "static")
  if not (okMesh and mesh) then return false end
  pcall(mesh.setVertexMap, mesh, { 1, 2, 3, 1, 3, 4 })
  mesh:setTexture(image)
  self.shapes[#self.shapes + 1] = {
    mesh = mesh, name = "groundShadow",
    -- NO INDEX, so `pose[shape.index]` finds nothing and the shadow is placed
    -- by the model's own matrix.  A posed model -- most of them pose to
    -- identity -- would otherwise need a joint this shape does not belong to.
    index = nil,
    -- NAMED `kage` on purpose: `shapeAlpha` reads that and gives it the
    -- cartridge's own shadow translucency, so a generated shadow is exactly as
    -- dark as an extracted one.
    material = "kage",
    image = image,
    lo = { lo[1], y, lo[3] }, hi = { hi[1], y, hi[3] },
  }
  return true
end

function Gen4Model.new(record)
  if type(record) ~= "table" or type(record.shapes) ~= "table" then return nil end
  if not ensureShader() then return nil end

  local self = setmetatable({}, Gen4Model)
  self.name = record.name
  self.posScale = record.posScale or 1
  self.bounds = record.bounds
  self.shapes = {}
  -- The model's own node transforms and the bytecode that arranges them.  A
  -- model whose nodes are all identity -- most of them -- poses to identity
  -- and costs nothing; the briefcase's do the work.
  self.nodes = record.nodes or {}
  self.ops = record.ops or {}

  for _, shape in ipairs(record.shapes) do
    local image
    if shape.image then
      local ok, loaded = pcall(Assets.image, shape.image)
      if ok and loaded then
        image = loaded
        -- Nearest, always: these are 16 and 64 pixel textures on a model that
        -- will be drawn several times their own size, and smoothing them turns
        -- a Poke Ball's seam into a smear.
        image:setFilter("nearest", "nearest")
        image:setWrap("repeat", "repeat")
      end
    end

    -- The texture's own size is what turns a coordinate in sixteenths of a
    -- texel into the 0-1 the sampler wants.  Without an image there is nothing
    -- to divide by and the shape draws untextured, which is what an untextured
    -- material means anyway.
    local tw, th = 1, 1
    if image then tw, th = image:getDimensions() end

    local count = shape.vertexCount or 0
    local vertices = {}
    -- Kept alongside, because classifying a card needs the whole triangle and
    -- the loop below sees one vertex at a time.
    -- Also collected for the back-wall cap, which needs the face normals to
    -- know whether a back is missing and which wall is a plain side.
    local positions = (record.billboard or record.capBack) and {} or nil
    local grassPending
    local uLo, uHi = math.huge, -math.huge
    -- THE STRIDE THIS CACHE WAS WRITTEN WITH, measured off the record rather
    -- than assumed from the constant.
    --
    -- The vertex grew from 14 bytes to 16 when the normal was added, and a
    -- cache imported before that change is still on disk in every install that
    -- has not re-imported.  Reading a 14-byte buffer at a 16-byte stride does
    -- not fail -- it misaligns EVERY vertex after the first, so the world comes
    -- back as confetti with no error anywhere.  Dividing the buffer by the
    -- vertex count is the one question that has a right answer on both.
    local stride = VERTEX_BYTES
    if count > 0 and shape.vertices then
      local measured = math.floor(#shape.vertices / count)
      if measured == LEGACY_VERTEX_BYTES or measured == VERTEX_BYTES then
        stride = measured
      end
    end
    local lit = (stride >= VERTEX_BYTES)
    -- THE LIGHT, if this caller brought one.  `shade(nx, ny, nz)` answers a
    -- multiplier per channel and is built by `Gen4Shade` from the map's own
    -- area-light template -- which is why it arrives as an argument rather
    -- than being looked up here: this file is handed shapes by the ground
    -- (which knows the map) and by screens that have no map at all, and a
    -- model with no light must keep drawing exactly as it did.
    local shade = record.shade
    -- The shape's own box, kept while the vertices are still here.  It is what
    -- `framing` works from: the header states a bounding box too, but it does
    -- not agree with the geometry on two thirds of this cartridge's models, so
    -- the measured one is the one to trust.
    local lo = { math.huge, math.huge, math.huge }
    local hi = { -math.huge, -math.huge, -math.huge }
    for i = 0, count - 1 do
      local at = i * stride
      local r, g, b = shape.vertices:byte(at + 11, at + 13)
      r, g, b = r or 255, g or 255, b or 255
      if shade and lit then
        -- The normal, back out of its three signed bytes.  Absent on a cache
        -- imported before the stride changed, and `s8` answers nil there --
        -- which leaves the colour alone rather than multiplying it by a
        -- normal that is really the first two bytes of the next vertex.
        local nx, ny, nz = s8(shape.vertices, at + 13),
                           s8(shape.vertices, at + 14),
                           s8(shape.vertices, at + 15)
        if nx and ny and nz then
          local lr, lg, lb = shade(nx, ny, nz)
          r = r * (lr or 1)
          g = g * (lg or 1)
          b = b * (lb or 1)
        end
      end
      local x = s16(shape.vertices, at) / FX16 * self.posScale
      local y = s16(shape.vertices, at + 2) / FX16 * self.posScale
      local z = s16(shape.vertices, at + 4) / FX16 * self.posScale
      if x < lo[1] then lo[1] = x end
      if y < lo[2] then lo[2] = y end
      if z < lo[3] then lo[3] = z end
      if x > hi[1] then hi[1] = x end
      if y > hi[2] then hi[2] = y end
      if z > hi[3] then hi[3] = z end
      vertices[i + 1] = {
        x, y, z,
        s16(shape.vertices, at + 6) / UV_UNITS / tw,
        s16(shape.vertices, at + 8) / UV_UNITS / th,
        -- ...and back to the 0..1 the float attribute wants.
        r / 255, g / 255, b / 255, 1,
        -- filled in below, once the triangles say which vertices are cards
        0, 0, 0,
      }
      if positions then
        -- the TEXEL coordinate, not the 0..1 one: the strip test compares it
        -- against the texture's own width, so it has to be in texture units.
        local texel = s16(shape.vertices, at + 6) / UV_UNITS
        -- ...AND THE TEXEL V, which the back wall's band needs.  Kept beside
        -- the u rather than derived later because this is the only place the
        -- raw vertex is still in hand.
        positions[i + 1] = { x, y, z, texel,
                             s16(shape.vertices, at + 8) / UV_UNITS }
        if texel < uLo then uLo = texel end
        if texel > uHi then uHi = texel end
      end
    end

    -- WHICH OF THESE ARE CARDS, and where each one turns.
    --
    -- Only when the caller asked: `record.billboard` is set for terrain chunks
    -- and NOT for buildings, and that is measured rather than tidy.  Run over
    -- `build_model.narc` the same classifier catches 184 triangles -- a school
    -- roof, a fountain, a shop front -- that happen to sit at the tree's lean
    -- and would then swing to face the camera.  The cartridge's trees live in
    -- the terrain, so that is where the rule is allowed to apply.
    if positions then
      -- ONLY WHEN THE TEXTURE REALLY LOADED.  `tw` falls back to 1, and a
      -- width of 1 would make the strip test reject every card with a u span
      -- over 1.5 texels -- which is all of them.  Passing nil there skips the
      -- test and billboards on the geometry alone, which is what a cache with
      -- no textures should do rather than silently doing nothing.
      local pivots, cards =
        billboardPivots(shape, positions, count, image and tw or nil)
      if cards > 0 then
        for i = 1, count do
          local v, pv = vertices[i], pivots[i]
          v[10], v[11], v[12] = pv[1], pv[2], pv[3]
        end
        self.cards = (self.cards or 0) + cards
      end
      -- ...AND THE GRASS STANDS UP, where the material says a wild Pokemon
      -- lives in it.  The flat quad stays: from the cartridge's own camera the
      -- card is edge-on and what you see is still the ground tile.
      if record.tileUnits and record.tileUnits > 0
         and GRASS_MATERIALS[tostring(shape.texture or "")] then
        grassPending = { shape = shape, positions = positions }
      end
    end
    if stride == LEGACY_VERTEX_BYTES and not Gen4Model.saidLegacy then
      Gen4Model.saidLegacy = true
      Logger.warn("gen4 model: this cache's vertices are %d bytes and carry no "
                  .. "normal, so nothing can be lit -- the world will draw "
                  .. "correctly and FLAT until the ROM is imported again",
                  LEGACY_VERTEX_BYTES)
    end

    if #vertices > 0 then
      local map = {}
      for i = 0, (shape.triangleCount or 0) * 3 - 1 do
        local a, b = shape.indices:byte(i * 2 + 1, i * 2 + 2)
        -- Back to one-based, which is what setVertexMap takes.
        map[i + 1] = (a + b * 256) + 1
      end

      local okMesh, mesh =
        pcall(love.graphics.newMesh, FORMAT, vertices, "triangles", "static")
      if okMesh and mesh then
        if #map > 0 then pcall(mesh.setVertexMap, mesh, map) end
        if image then mesh:setTexture(image) end
        -- WHICH WAY THIS SHAPE'S FACES POINT, and how densely it is textured.
        --
        -- Both are for the back-wall cap: the counts say whether a model has a
        -- north side at all, and the density lets a generated wall wear the
        -- side wall's texture at the side wall's own scale rather than
        -- stretched across the span.
        local facing, wallBand, bands, tris, sideXLo, sideXHi, wallZLo
        local sidePlanes, wallZs, northArea, southArea, northWalls, flatBand
        if record.capBack and positions then
          facing = { north = 0, south = 0, east = 0, west = 0, up = 0, down = 0 }
          local indices = shape.indices or ""
          for t = 0, (shape.triangleCount or 0) - 1 do
            local at2 = t * 6
            local a1, a2, b1, b2, c1, c2 = indices:byte(at2 + 1, at2 + 6)
            if not c2 then break end
            local pa = positions[a1 + a2 * 256 + 1]
            local pb = positions[b1 + b2 * 256 + 1]
            local pc = positions[c1 + c2 * 256 + 1]
            if pa and pb and pc then
              -- EVERY triangle is kept, roof included.  The back plugs the
              -- building's CROSS-SECTION at the back plane, and over the hole
              -- it is closing the only thing there is to measure is the roof.
              tris = tris or {}
              tris[#tris + 1] = a1 + a2 * 256 + 1
              tris[#tris + 1] = b1 + b2 * 256 + 1
              tris[#tris + 1] = c1 + c2 * 256 + 1
              local ux, uy, uz = pb[1]-pa[1], pb[2]-pa[2], pb[3]-pa[3]
              local vx, vy, vz = pc[1]-pa[1], pc[2]-pa[2], pc[3]-pa[3]
              local nx = uy*vz - uz*vy
              local ny = uz*vx - ux*vz
              local nz = ux*vy - uy*vx
              local len = math.sqrt(nx*nx + ny*ny + nz*nz)
              if len > 1e-6 then
                nx, ny, nz = nx/len, ny/len, nz/len
                local ax, ay, az = math.abs(nx), math.abs(ny), math.abs(nz)
                local upright = (ay >= ax and ay >= az)
                if upright then
                  facing[ny > 0 and "up" or "down"] =
                    facing[ny > 0 and "up" or "down"] + 1
                else
                  -- A WALL VERTEX, and the back's silhouette is drawn from
                  -- these alone.
                  --
                  -- The outline used to be every vertex of every shape that
                  -- was not MOSTLY roof, which is a per-shape test -- and
                  -- `t1_h01` is a single shape carrying its walls and its roof
                  -- together, so nothing was ever excluded and the silhouette
                  -- was the ROOF's.  The back then reached out under the eaves
                  -- on both sides and showed from the FRONT as red slivers
                  -- down each house: 9,742 pixels on a view that must not
                  -- change at all.
                  --
                  -- Sorting triangles rather than shapes costs nothing here --
                  -- the normals are already in hand for `facing` -- and gives
                  -- the outline of the WALLS, which is the thing a back wall
                  -- has to match.
                  -- HOW FAR NORTH THE WALLS REACH.  North is -z.
                  local zw = pa[3]
                  if pb[3] < zw then zw = pb[3] end
                  if pc[3] < zw then zw = pc[3] end
                  if wallZLo == nil or zw < wallZLo then wallZLo = zw end
                  wallZs = wallZs or {}
                  wallZs[#wallZs + 1] = zw
                end
                if upright then -- counted above
                elseif az >= ax then
                  facing[nz > 0 and "south" or "north"] =
                    facing[nz > 0 and "south" or "north"] + 1
                  -- A ROOF SLOPE IS NOT A WALL, and the counts above cannot
                  -- tell them apart: a rear roof pitch leaning more north than
                  -- up is filed as "north" here.  Measured, the two do not
                  -- overlap at all -- every vertical wall in this cartridge
                  -- reads |ny| = 0.00 or 0.01, and every sloping face between
                  -- 0.34 and 0.69 -- so the walls are counted separately, by
                  -- AREA, which is the quantity the coverage test needs.
                  if ay < 0.2 then
                    local tarea = len * 0.5
                    if nz > 0 then
                      southArea = (southArea or 0) + tarea
                    else
                      northArea = (northArea or 0) + tarea
                      local zn = pa[3]
                      if pb[3] < zn then zn = pb[3] end
                      if pc[3] < zn then zn = pc[3] end
                      northWalls = northWalls or {}
                      northWalls[#northWalls + 1] = zn
                      northWalls[#northWalls + 1] = tarea
                    end
                  end
                else
                  facing[nx > 0 and "east" or "west"] =
                    facing[nx > 0 and "east" or "west"] + 1
                  -- THE OUTERMOST PLANES AT WHICH THIS MODEL HAS A SIDE WALL.
                  -- Every east/west face, gated or not: a back wider than the
                  -- sides it joins shows past the corner from the FRONT, and
                  -- this is the only measurement that says where they are.
                  sideXLo = (sideXLo == nil or pa[1] < sideXLo) and pa[1] or sideXLo
                  sideXHi = (sideXHi == nil or pa[1] > sideXHi) and pa[1] or sideXHi
                  -- ...AND THE STRETCH OF z EACH ONE COVERS, because a
                  -- building that is wide at the front and narrow at the back
                  -- has no single width.  Kept flat, three numbers per face.
                  local zs = pa[3]; local ze = pa[3]
                  if pb[3] < zs then zs = pb[3] end
                  if pc[3] < zs then zs = pc[3] end
                  if pb[3] > ze then ze = pb[3] end
                  if pc[3] > ze then ze = pc[3] end
                  sidePlanes = sidePlanes or {}
                  sidePlanes[#sidePlanes + 1] = pa[1]
                  sidePlanes[#sidePlanes + 1] = zs
                  sidePlanes[#sidePlanes + 1] = ze
                  -- THE COURSE THIS BUILDING'S WALLS ARE CLAD IN, as a
                  -- rectangle in both world and texel space.
                  --
                  -- The number this replaces was an aggregate: the shape's
                  -- whole u range over its whole span.  On `t1_h01` that is
                  -- 93.9 texels over 64 units, because `polygon0` carries the
                  -- porch and the chimney as well as the walls -- while a real
                  -- wall quad measures 28 texels over 11.75 units.  An
                  -- aggregate of unrelated faces is not a density.
                  --
                  -- A side wall's triangles are right halves of axis-aligned
                  -- quads, so ONE triangle's own z/y extent IS the quad's.
                  --
                  -- WHICH quad the back should copy is decided by two measured
                  -- things, and neither is "the biggest one".
                  --
                  -- Biggest-in-world was tried and it is wrong on every
                  -- building measured.  `t1_h01`'s largest side face is 12.00 x
                  -- 32.50 units showing 5 x 6 texels -- a flat colour stretched
                  -- over a panel -- while the clapboard course beside it is
                  -- 11.75 x 28.50 showing 28 x 30.  `c1_b02b`'s largest is 48 x
                  -- 72 units showing 0.9 x 1.6.  Tiled from those the back came
                  -- out a flat dark grey, which is exactly what one texel
                  -- stretched sixty units wide looks like.
                  --
                  -- Biggest-in-TEXELS was tried next and it is wrong too: on
                  -- `t1_s01` it picks a shape whose material is named `light`
                  -- and which wears the whole 64 x 64 atlas on a single quad --
                  -- a decal, not a course -- and the back came back covered in
                  -- smeared windows.
                  --
                  -- WHAT ACTUALLY SEPARATES THEM IS SCALE.  Platinum's building
                  -- art is drawn at screen scale, so a course of siding is
                  -- about ONE TEXEL PER WORLD UNIT vertically.  Measured across
                  -- nine buildings, every real wall course lands between 0.91
                  -- and 1.58 (t1_h01 1.05, c1_b02b 1.13, t1_s01 1.13, c1_s02
                  -- 1.09, l2_s02b 0.91, gym00 1.58, r212s02 1.21, shelf08 0.96)
                  -- while the stretched panels sit at 0.02 to 0.21 and the
                  -- squeezed decals at 2.06 to 7.53.  A window of one octave
                  -- either side of the drawing scale keeps the courses and
                  -- drops both kinds of junk.
                  --
                  -- Only the VERTICAL density is gated.  Courses run
                  -- horizontally, so their height is what is drawn to scale;
                  -- their width may be squeezed because it tiles, and `t1_h01`
                  -- squeezes it to 2.38.
                  --
                  -- It is a scale window and not a proof.  The nearest thing it
                  -- excludes is that `light` face at 2.06, which is close to the
                  -- bound; a building whose siding is drawn at half scale would
                  -- be rejected by this and would need a different rule.
                  local zA = pa[3]; local zB = pb[3]; local zC = pc[3]
                  local zMin = (zA < zB and zA or zB); if zC < zMin then zMin = zC end
                  local zMax = (zA > zB and zA or zB); if zC > zMax then zMax = zC end
                  local yA = pa[2]; local yB = pb[2]; local yC = pc[2]
                  local yMin = (yA < yB and yA or yB); if yC < yMin then yMin = yC end
                  local yMax = (yA > yB and yA or yB); if yC > yMax then yMax = yC end
                  local uA, uB, uC = pa[4], pb[4], pc[4]
                  local vA, vB, vC = pa[5], pb[5], pc[5]
                  local uMin = (uA < uB and uA or uB); if uC < uMin then uMin = uC end
                  local uMax = (uA > uB and uA or uB); if uC > uMax then uMax = uC end
                  local vMin = (vA < vB and vA or vB); if vC < vMin then vMin = vC end
                  local vMax = (vA > vB and vA or vB); if vC > vMax then vMax = vC end
                  local dz, dy = zMax - zMin, yMax - yMin
                  local dens = (dy > 1e-6) and ((vMax - vMin) / dy) or 0
                  -- THE BIGGEST SIDE WALL, whatever its texture does.
                  --
                  -- Four of Sinnoh's shops -- the Veilstone restaurant, the
                  -- Hearthome market, `c7_s04` and `c10_s02` -- are not clad
                  -- in a course at all: their side walls carry a u span of
                  -- 0.0 texels, so the cartridge paints them from a single
                  -- texel and there is no scale to match.  They got no back.
                  -- Where there is no course to copy, the back is painted from
                  -- that same texel, which fits in exactly because it is the
                  -- colour the walls already are.
                  if dz * dy > (flatBand and flatBand.area or 0) then
                    flatBand = { area = dz * dy, u = uA, v = vA,
                                 width = dz, height = dy, yFoot = yMin }
                  end
                  if dz > 1e-6 and dy > 1e-6
                     and (uMax - uMin) >= WALL_MIN_TEXELS
                     and (vMax - vMin) >= WALL_MIN_TEXELS
                     and dens >= WALL_SCALE_LO and dens <= WALL_SCALE_HI then
                    -- ...AND THE SAME RECT ON MORE FACES BEATS A BIGGER ONE ON
                    -- fewer, because a course is what a building REPEATS.  The
                    -- world area is summed per distinct texel rect.
                    bands = bands or {}
                    local key = ("%d,%d,%d,%d"):format(
                      uMin * 16 + 0.5, uMax * 16 + 0.5,
                      vMin * 16 + 0.5, vMax * 16 + 0.5)
                    local b = bands[key]
                    if not b then
                      -- WHICH END OF V IS THE BOTTOM, read off the face rather
                      -- than assumed: Gen 4 textures run v downward, so the
                      -- wall's foot carries the LARGER v -- but that is a
                      -- convention, and the vertex says it outright.
                      local vFoot = vA
                      if yB < yA and yB <= yC then vFoot = vB
                      elseif yC < yA and yC < yB then vFoot = vC end
                      b = { area = 0, width = dz, height = dy,
                            uLo = uMin, uHi = uMax, vLo = vMin, vHi = vMax,
                            vAtFoot = vFoot, yFoot = yMin,
                            xLo = math.huge, xHi = -math.huge,
                            zLo = math.huge }
                      bands[key] = b
                    end
                    b.area = b.area + dz * dy
                    -- WHERE THE SIDE WALLS STAND.  An east/west face is planar
                    -- in x, so the faces wearing this course mark the two
                    -- planes the back has to span -- and NOT one unit further,
                    -- which is what the model's bounding box would have given.
                    if pa[1] < b.xLo then b.xLo = pa[1] end
                    if pa[1] > b.xHi then b.xHi = pa[1] end
                    -- ...AND HOW FAR NORTH THEY REACH.  North is -z, so the
                    -- smallest z on the faces wearing this course is the plane
                    -- the back belongs on.  Taking it from the shape's bounding
                    -- box instead put the back out under the ROOF's north
                    -- overhang, where nothing covers it.
                    if zMin < b.zLo then b.zLo = zMin end
                    if b.area > (wallBand and wallBand.area or 0) then
                      wallBand = b
                    end
                  end                end
              end
            end
          end
          if wallBand and not (wallBand.width > 1e-6 and wallBand.height > 1e-6
                               and wallBand.uHi > wallBand.uLo
                               and wallBand.vHi > wallBand.vLo) then
            wallBand = nil
          end
        end
        self.shapes[#self.shapes + 1] =
          { mesh = mesh, name = shape.name, index = shape.index,
            matrixSlots=shape.matrixSlots,
            bindVertices=shape.matrixSlots and vertices or nil,
            facing = facing, wallBand = wallBand,
            -- the WALL vertices, for the back wall's silhouette
            outline = record.capBack and positions or nil,
            tris = record.capBack and tris or nil,
            sideXLo = sideXLo, sideXHi = sideXHi, wallZLo = wallZLo,
            sidePlanes = sidePlanes, wallZs = wallZs, flatBand = flatBand,
            northArea = northArea, southArea = southArea,
            northWalls = northWalls,
            imagePath = record.capBack and shape.image or nil,
            -- The MATERIAL, kept because a texture animation names one.  It
            -- was being dropped here, which is why nothing could have driven
            -- an animation even once the animation was decoded.
            material = shape.material,
            image = image,
            lo = lo, hi = hi }
        -- ...AND THE STANDING CARDS AFTER IT, as a shape of their own so they
        -- can wear the cut-out copy of the texture while the flat quad keeps
        -- the original.
        if grassPending then
          addGrassCards(self, grassPending.shape, vertices,
                        grassPending.positions, record.tileUnits)
          grassPending = nil
        end
      else
        Logger.warn("gen4 model %s: shape %s would not build (%s)",
                    tostring(record.name), tostring(shape.name), tostring(mesh))
      end
    end
  end

  if #self.shapes == 0 then return nil end
  if record.capBack then
    self.generatedBack = addBackWall(self) or nil
  end
  if record.groundShadow then
    self.generatedShadow = addGroundShadow(self, record.groundShadow) or nil
  end
  return self
end

-- The highest point of any of this model's shapes, in its own units.
--
-- Measured off the geometry rather than read from the header, for the reason
-- `framing` gives: the header's bounding box disagrees with the vertices on two
-- thirds of this cartridge's models.  Cached, because the ground asks once per
-- prop per bake and the answer cannot change.
function Gen4Model:topY()
  if self.topCache then return self.topCache end
  local top = 0
  for _, shape in ipairs(self.shapes or {}) do
    if shape.hi and shape.hi[2] and shape.hi[2] > top then top = shape.hi[2] end
  end
  self.topCache = top
  return top
end

-- framing(pose) -> centre, distance
--
-- The model's own centre and how far away a camera has to sit to see all of
-- it, measured off the geometry IN THE POSE IT WILL BE DRAWN IN.  A pose
-- matters here: the briefcase's three Poke Balls are 60 units apart only once
-- their nodes have placed them, and framing the unposed shapes would put the
-- camera close enough to lose two of them off the sides.
function Gen4Model:framing(pose)
  pose = pose or self:restPose()
  local lo = { math.huge, math.huge, math.huge }
  local hi = { -math.huge, -math.huge, -math.huge }
  for _, shape in ipairs(self.shapes) do
    local m = pose[shape.index]
    for corner = 0, 7 do
      local p = {
        (corner % 2 == 0) and shape.lo[1] or shape.hi[1],
        (math.floor(corner / 2) % 2 == 0) and shape.lo[2] or shape.hi[2],
        (math.floor(corner / 4) % 2 == 0) and shape.lo[3] or shape.hi[3],
      }
      if m then
        p = {
          m[1] * p[1] + m[2] * p[2] + m[3] * p[3] + m[4],
          m[5] * p[1] + m[6] * p[2] + m[7] * p[3] + m[8],
          m[9] * p[1] + m[10] * p[2] + m[11] * p[3] + m[12],
        }
      end
      for k = 1, 3 do
        if p[k] < lo[k] then lo[k] = p[k] end
        if p[k] > hi[k] then hi[k] = p[k] end
      end
    end
  end
  if lo[1] > hi[1] then return { 0, 0, 0 }, 4 end
  local centre = { (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2 }
  local extent = math.max(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3])
  return centre, math.max(0.001, extent) * 1.8
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

-- The rest pose: every shape's place with the model's own node transforms.
-- Built once and kept, because a model with identity nodes would otherwise
-- redo the same walk every frame to arrive at nothing.
function Gen4Model:restPose()
  if not self.rest then
    local nodes = self.nodes
    self.rest = Gen4Nsbmd.pose(self.ops, function(index)
      local node = nodes[index + 1]
      return node and node.matrix
    end)
  end
  return self.rest
end

-- posed(matrixOf) -> { [shape index] = 4x4 }
--
-- The same walk with somebody else's matrices: `matrixOf(node)` returns a
-- joint animation's frame, and a node the animation does not cover falls back
-- to the model's own.  That fallback is not a nicety -- an animation with
-- fewer joints than the model has nodes would otherwise collapse the rest to
-- the origin, which reads as geometry gone missing rather than as a mismatch.
function Gen4Model:posed(matrixOf)
  if not matrixOf then return self:restPose() end
  local nodes = self.nodes
  return Gen4Nsbmd.pose(self.ops, function(index)
    return matrixOf(index) or (nodes[index + 1] and nodes[index + 1].matrix)
  end)
end

-- draw(viewProjection, pose) -- into whatever canvas is set.
--
-- One matrix send per shape rather than one per model, because each shape
-- stands where its node puts it.  `pose` is what `restPose` or `posed`
-- returned; leaving it out draws the rest pose.
--
-- The depth mode is set and RESTORED here rather than left to the caller.
-- This is called from inside a screen's draw, and a depth test left switched
-- on makes the next ordinary 2D draw vanish or show through in ways that look
-- like a bug in the thing that comes after it.
-- One of a flipbook's frames, by the path the import stage wrote it under.
-- Cached per model, and a path that will not load is remembered as `false` so
-- a missing frame is asked for once rather than once a frame.
function Gen4Model:frameImage(path)
  if type(path) ~= "string" then return nil end
  self.frames = self.frames or {}
  if self.frames[path] == nil then
    local ok, loaded = pcall(Assets.image, path)
    if ok and loaded then
      loaded:setFilter("nearest", "nearest")
      loaded:setWrap("repeat", "repeat")
      self.frames[path] = loaded
    else
      Logger.warn("gen4 model %s: animation frame %s would not load",
                  tostring(self.name), tostring(path))
      self.frames[path] = false
    end
  end
  return self.frames[path] or nil
end

-- The identity texture transform, sent for every shape that has no animation
-- on it -- which is nearly all of them, nearly all of the time.
local UV_IDENTITY = { 1, 0, 0, 1 }
local UV_NO_SHIFT = { 0, 0 }

-- draw(viewProjection, pose, materials)
--
-- `materials` is optional and maps a MATERIAL NAME to what this frame does to
-- it: `{ uv = { a, b, c, d, tx, ty }, image = <path> }`.  Both halves are
-- optional -- a BTA0 supplies the first, a BTP0 the second -- and a material
-- with no entry draws exactly as it did before this parameter existed.
--
-- `image` is a PATH and the loading is done here, once per path, because the
-- caller is a per-frame animation evaluator and asking it to hold LOVE Images
-- would put an asset cache in a file that has no business owning one.
local NO_CUT = -1.0e9

-- A MATERIAL'S POLYGON ALPHA, 0..31, and what to do when the cache predates it.
--
-- `polyAttr` bits 16..20 are the DS's per-material alpha and 31 is opaque.  A
-- building's ground shadow is 9 -- measured off `funsui` in the cartridge,
-- where the two ordinary materials are 31 and `h_kage` is 9.  Without it every
-- shadow drew at full strength, and its texture is a 16x16 of palette index 0
-- which on that material is opaque BLACK, not transparent: *"there are shadows
-- for the houses but they're showing as black"*.  They were exactly black.
local ALPHA_MAX = 31

-- THE FALLBACK IS A MEASUREMENT, NOT A GUESS.  `h_kage` is the cartridge's one
-- shadow texture and it is 9/31 on every material that wears it, so a cache
-- written before `alpha` existed can still be drawn correctly by name.  It
-- costs one string match on 153 of the 590 building models and lets the fix
-- land without a re-import; a cache that carries the real value never consults
-- it.
local SHADOW_ALPHA = 9
-- EITHER NAME, not the first one that exists.  This read `shape.material or
-- shape.texture`, which is an or where the question is an either: a material
-- and the texture it wears are different strings and on this cartridge only
-- one of them tends to say `kage`.
--
-- Counted over all 666 land chunks: 17 shadow materials say `kage` in both
-- names, 11 say it only in the TEXTURE (`chair4`, `counter2`, `shelf2`,
-- `lambert7`, `isu:lambert9` all wear `h_kage` or `m_dun06_kage`) and 2 say it
-- only in the MATERIAL (`kage`, with no texture at all).  Reading whichever
-- came first therefore missed 11 or 2 of the 30 depending on which field the
-- caller happened to carry -- and terrain began carrying `material` in the
-- same pass as this comment, which would have moved it from the 2 to the 11.
local function shapeAlpha(shape)
  local stated = tonumber(shape.alpha)
  if stated then return math.min(stated, ALPHA_MAX) / ALPHA_MAX end
  local material = tostring(shape.material or ""):lower()
  local texture = tostring(shape.texture or ""):lower()
  if material:find("kage", 1, true) or texture:find("kage", 1, true) then
    return SHADOW_ALPHA / ALPHA_MAX
  end
  return 1
end

-- No spread at all, which is what every caller that is not the live ground
-- pass wants: a Poke Ball on a menu screen has no camera to be off the centre
-- of.  SENT ON EVERY DRAW for the reason `yCut` is -- an unset uniform reads
-- as zero, and here zero happens to be the right answer, but relying on that
-- is how the texture matrix collapsed every model to one texel.
local NO_SPREAD = { 0, 0 }

-- WHICH WAY THE CAMERA IS LOOKING, for the cards to turn to face.
--
-- Module state rather than a `draw` argument because every caller that is not
-- the free ground pass wants zero, and threading a parameter through all of
-- them to say "no" invites the one that forgets.  Zero is the identity here,
-- so a caller that never touches it renders exactly as it did.  `Gen4Ground`
-- sets it immediately before its chunk draws and puts it back to zero after.
Gen4Model.billboardYaw = 0
-- A model-z band the height cut leaves unpainted, or nil. Set per chunk by
-- the canopy pass; see `Gen4Ground:livePass`.
Gen4Model.zKeep = nil

-- `depthCompare` defaults to "less", which is right for every pass that draws
-- a piece of geometry ONCE.
--
-- It is a parameter because the canopy pass draws the SAME terrain twice --
-- first with the colour mask off to lay down depth, then again with a height
-- cut to paint the part that goes over the sprites -- and the second draw's
-- fragments sit at EXACTLY the depth the first one wrote.  Under "less" every
-- one of them is rejected, so that pass painted nothing at all and the tree
-- canopy never went over anybody.  "lequal" is what lets a second draw of the
-- same surface through.
function Gen4Model:draw(viewProjection, pose, materials, yCut, spread, depthCompare)
  local g = love.graphics
  if not (shader and viewProjection) then return false end
  pose = pose or self:restPose()
  local previousShader = g.getShader()
  local mode, write = g.getDepthMode()
  local culling = g.getMeshCullMode()
  -- ...AND THE COLOUR, which is the one piece of shared state this function
  -- changed and did not put back.  See the restore at the foot of the loop.
  local pr, pg, pb, pa = g.getColor()

  g.setShader(shader)
  g.setDepthMode(depthCompare or "less", true)
  -- BACK FACES ARE NOT CULLED, and that is the cartridge's own choice rather
  -- than laziness: a DS polygon carries its own front/back flags in its
  -- material, plenty of Gen 4 geometry is single-sided sheets meant to be seen
  -- from either side, and culling them uniformly loses the far wall of the
  -- briefcase.  With a depth buffer the cost of drawing both is a few
  -- overdrawn pixels.
  g.setMeshCullMode("none")
  g.setColor(1, 1, 1, 1)
  if shaderCuts then
    shader:send("yCut", tonumber(yCut) or NO_CUT)
    -- Only meaningful with a cut, and cleared otherwise -- an unset uniform
    -- reads as (0, 0), an empty band, but stating it is what keeps a stale
    -- band from one pass out of the next.
    local band = yCut and Gen4Model.zKeep
    shader:send("zKeep", band and { band[1], band[2] } or { 1.0e9, -1.0e9 })
  end
  shader:send("heightSpread", spread or NO_SPREAD)
  -- SENT ON EVERY DRAW, for the reason `yCut` and `heightSpread` are: an unset
  -- uniform reads as zero, and relying on that is how the texture matrix once
  -- collapsed every model to a single texel.
  shader:send("billboardYaw", tonumber(Gen4Model.billboardYaw) or 0)
  for _, shape in ipairs(self.shapes) do
    -- Per shape, because a model mixes opaque walls with a translucent shadow
    -- and one colour for the whole model would make one of them wrong.
    g.setColor(1, 1, 1, shapeAlpha(shape))
    local place = pose[shape.index]
    if shape.matrixSlots and pose.stack then
      -- A display list can restore a different joint for every vertex.
      -- Giratina's tentacles share shapes but use separate matrix slots.
      for i,v in ipairs(shape.bindVertices) do
        local slot=shape.matrixSlots:byte(i)
        local m=pose.stack[slot] or place
        local x,y,z=v[1],v[2],v[3]
        if m then
          x,y,z=m[1]*x+m[2]*y+m[3]*z+m[4],
                m[5]*x+m[6]*y+m[7]*z+m[8],
                m[9]*x+m[10]*y+m[11]*z+m[12]
        end
        shape.mesh:setVertex(i,x,y,z,unpack(v,4))
      end
      place=nil
    end
    shader:send("mvp", place and multiply(viewProjection, place) or viewProjection)

    local state = materials and shape.material and materials[shape.material]
    local uv = state and state.uv
    if uv then
      shader:send("uvRotScale", { uv[1], uv[2], uv[3], uv[4] })
      shader:send("uvTranslate", { uv[5] or 0, uv[6] or 0 })
    else
      shader:send("uvRotScale", UV_IDENTITY)
      shader:send("uvTranslate", UV_NO_SHIFT)
    end

    -- A BTP0 swaps which picture the material wears.  Swapped back afterwards
    -- rather than left: the mesh is shared with the baked copy of this model,
    -- and a texture left on it is a door stuck open everywhere else it appears.
    local swapped = state and state.image and self:frameImage(state.image)
    if swapped then shape.mesh:setTexture(swapped) end
    g.draw(shape.mesh)
    if swapped then
      if shape.image then shape.mesh:setTexture(shape.image)
      else shape.mesh:setTexture() end
    end
  end

  g.setMeshCullMode(culling)
  g.setDepthMode(mode, write)
  g.setShader(previousShader)
  -- THE COLOUR GOES BACK TOO, AND NOT PUTTING IT BACK MADE EVERY CHARACTER
  -- SEE-THROUGH.
  --
  -- Reported from play, repeatedly: *"the npc and player sprites are still see
  -- through specifically with the 3d camera on in tilted views and first and
  -- third person"*, and before that as Rowan alone.
  --
  -- The loop above sets `setColor(1, 1, 1, shapeAlpha(shape))` PER SHAPE, which
  -- is right -- a model mixes opaque walls with a translucent shadow. But the
  -- colour is global graphics state, so whatever the LAST shape asked for was
  -- still in force when this returned. `SpriteRenderer` sets no colour of its
  -- own; it inherits. So a character drawn after a chunk whose final shape was
  -- translucent was drawn AT THAT SHAPE'S ALPHA.
  --
  -- Indoors is where it showed worst because indoors is where those shapes are:
  -- `shade`, `stair_d01_shade`, `table01_1_shade` and `dun_shadow` all state
  -- 12/31, so a character came out at about 39% opacity -- which is exactly
  -- "see through" and not a depth or sorting fault at all.
  --
  -- THE OTHER THREE RESTORES WERE ALREADY HERE, which is what makes this an
  -- omission rather than a design: the function knew it was borrowing shared
  -- state and put back the cull mode, the depth mode and the shader. The
  -- `setColor(1, 1, 1, 1)` at the top of the loop is the same knowledge, said
  -- once at the wrong end.
  --
  -- AND IT PREDATES THE TERRAIN ALPHA WORK but was made much wider by it: the
  -- `kage` name fallback already gave 9/31 to kage-named shapes, so this bit
  -- wherever a model happened to end on one -- Rowan's room. Carrying the
  -- cartridge's real alpha for 155 materials turned a few rooms into most of
  -- them.
  g.setColor(pr, pg, pb, pa)
  return true
end

-- A canvas that can hold a depth buffer, which an ordinary one cannot.
--
-- Returned as a pair because LOVE wants them handed back together
-- (`setCanvas { colour, depthstencil = depth }`), and a caller that kept only
-- the colour one would get a scene with no depth test and no error.
-- THE DEPTH FORMATS TO TRY, best first.
--
-- `depth24` alone is not a safe ask.  It is the common desktop format and the
-- one to prefer, but plenty of drivers -- Intel integrated parts and anything
-- going through ANGLE especially -- expose only the packed depth+stencil
-- combination, and a few mobile-derived ones only ever offer `depth16`.  A
-- single ask meant one unsupported format turned the WHOLE 3D path off and
-- left a flat world that looked like a bug in the camera rather than a
-- capability that was never there.
local DEPTH_FORMATS = { "depth24", "depth24stencil8", "depth32f", "depth16" }

-- Worked out once: `newCanvas` is not free to call speculatively, and the
-- answer cannot change while the game is running.
local depthFormat, depthChecked = nil, false

local function chooseDepthFormat()
  if depthChecked then return depthFormat end
  depthChecked = true
  -- ASK BEFORE TRYING.  `getCanvasFormats` is the driver's own list, so a
  -- format it does not name is one no amount of retrying will produce.
  local ok, supported = pcall(love.graphics.getCanvasFormats)
  for _, format in ipairs(DEPTH_FORMATS) do
    if not ok or supported == nil or supported[format] then
      local made, canvas = pcall(love.graphics.newCanvas, 8, 8,
                                 { format = format, readable = false })
      if made and canvas then
        depthFormat = format
        if canvas.release then canvas:release() end
        Logger.info("gen4 model: depth buffer format %s", format)
        return depthFormat
      end
    end
  end
  Logger.warn("gen4 model: no depth canvas format available (tried %s); "
              .. "3D models cannot be drawn on this device",
              table.concat(DEPTH_FORMATS, ", "))
  return nil
end

function Gen4Model.newTarget(width, height)
  local format = chooseDepthFormat()
  if not format then return nil end
  local okColour, colour = pcall(love.graphics.newCanvas, width, height)
  if not okColour or not colour then return nil end
  local okDepth, depth = pcall(love.graphics.newCanvas, width, height,
                               { format = format, readable = false })
  if not okDepth or not depth then
    -- Without a depth buffer the model would draw in submission order, which
    -- on a solid object means the back of it in front.  Better to draw nothing
    -- and say why.
    Logger.warn("gen4 model: %s canvas of %dx%d failed (%s); "
                .. "3D models cannot be drawn at this size",
                format, width, height, tostring(depth))
    return nil
  end
  colour:setFilter("nearest", "nearest")
  return colour, depth
end

return Gen4Model
