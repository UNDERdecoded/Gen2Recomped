-- Voxel world mode: water, and what it reflects.
--
-- Every other surface in this mode is opaque and is drawn once, inside the
-- terrain mesh, by the scene shader. Water is neither: it is a MIRROR, and
-- a mirror cannot be drawn until the thing it reflects already exists. So
-- the water surface is lifted out of the terrain mesh at build time
-- (ChunkMesher's water sink) and drawn as its own pass, after the world and
-- before the characters, by the shader below.
--
-- WHAT IT REFLECTS, in the order the shader resolves them:
--
--   the sky      the reflected direction is put through the SAME matrix the
--                frame is drawn with, as a point at infinity, and the canvas
--                row that lands on is looked up on Sky's own band ramp --
--                the identical texture, dither and display-mode transform
--                the painted sky uses. So the sky in the lake is the sky
--                over it: blue at noon, gold at dusk, navy under the moon,
--                and it meets the painted sky at the waterline with no seam.
--
--   the sun,     hung by ANGLE rather than by screen position, because a
--   the moon     reflected body is usually off the top of the frame and a
--                projected point is meaningless out there. The angular
--                radius is Sky.discRadius converted through the camera's own
--                field of view, so the disc on the water is exactly as big
--                as the disc in the sky -- craters, dithered rim, the
--                sunset's loom and all. This is also the specular: a low sun
--                lays a broken gold path across the water on its own, out of
--                the reflection rather than out of a highlight term.
--
--   the world    SCREEN SPACE. The reflected ray is walked forward in world
--                space, each step projected through the same matrix, looking
--                for where it passes behind what the depth buffer holds --
--                then binary-refined onto the contact and read out of a copy
--                of the frame as it stood before the water went down. Shore
--                trees, buildings, ledges and cliffs land in the water
--                because they are on screen; where the ray leaves the frame
--                or finds nothing, the sky above answers instead, which is
--                what makes the far half of a lake sky and the near half
--                scenery without a seam between them.
--
--   the cast     the walkers, the NPCs, the authored figures and a staged
--                battle's two Pokemon. Awkward, and settled by drawing them
--                twice: Gen 1 draws people OVER the world and water is
--                world, so a surfing player has to composite after the
--                water, and a reflection can only hold what came before it.
--                So they are painted into the reflection copy alone
--                (Voxel3D.beginWater), in the picture the water reflects and
--                not yet in the picture it is drawn into.
--
-- WHAT IT CANNOT REFLECT is what no screen-space reflection can: anything
-- that is not in the frame. A tree just off the top edge is not in the water
-- below it, and a ray that runs off the side of the screen fades into the
-- sky rather than ending on a line.
--
-- THE SURFACE ITSELF is not flat. It is a heightfield of one-world-pixel
-- columns, each standing a whole number of pixels tall and rising and
-- falling as waves, walked by the view ray in the pixel shader -- so the
-- bars occlude each other and show their sides without a single extra
-- vertex. See WAVE_HEIGHT and relief().
--
-- THE PASS ITSELF, and why it is shaped this way. The scene canvas carries a
-- READABLE depth canvas (Voxel3D), and a texture cannot be sampled while it
-- is bound as a render target -- so for the length of this pass the depth
-- buffer is DETACHED and the shader does the depth test itself, comparing
-- its own fragment depth against the texture it just stopped writing to.
-- That is the same test the hardware would have run, so a tree in front of a
-- pond still hides it; what it costs is depth WRITES, which water has no use
-- for anyway (it is flat, it never overlaps itself, and everything drawn
-- after it stands on top of it by construction).
--
-- Falls back all the way down. No readable depth canvas, a driver that will
-- not compile this, or the row set to OFF and the water mesh is simply drawn
-- by the ordinary scene shader -- flat animated water, exactly what the mode
-- drew before any of this existed.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local Sky = V.require("Sky")
local DayNight = V.require("DayNight")
local ShadowMap = V.require("ShadowMap")
local Mat4 = V.require("Mat4")

local Water = {}

-- ------- the row
--
-- Three rungs rather than a toggle, because the two halves of this cost
-- very different things. SKY is a handful of instructions per water pixel
-- and no extra buffers read; FULL adds the screen-space march, which is the
-- part that samples a depth texture twenty-odd times. A phone that wants the
-- sunset on the lake but not the ray march has somewhere to stand.
Water.KEY = "water"
Water.LABEL = "WATER"

Water.setting = ModSetting.new(Water.KEY, Water.LABEL,
                               { "full", "sky", "off" },
                               { "FULL", "SKY", "OFF" })

function Water.level()
  local v = Water.setting:get()
  if v == "off" then return 0 end
  if v == "sky" then return 1 end
  return 2
end

-- Whether the reflective pass should run at all (either rung above OFF).
function Water.enabled()
  return Water.level() > 0
end

-- ------- the look, in constants
--
-- FRESNEL. Water reflects almost nothing looked straight down at and almost
-- everything looked along, which is Schlick's curve -- and taken literally
-- it hands the top rung a mirror and the other four nothing at all. This
-- mode's rungs are named for the camera's tilt off VERTICAL, so 15 is a
-- near-overhead camera meeting the water at 15 degrees off its normal:
-- honest Schlick gives that about 2%, and even a generous floor of 0.14 was
-- invisible.
--
-- So the floor is lifted a long way above water's true 0.04 and the exponent
-- softened from 5 to 2: the SHAPE is still the honest one -- a low camera
-- still gets much more of it than a high one -- but the bottom of the curve
-- is a pond rather than a painted tile.
Water.FRESNEL_FLOOR = 0.34
Water.FRESNEL_CEIL = 0.92
Water.FRESNEL_POWER = 2.0

-- THE HORIZON LEAN, which is the other half of why the steeper rungs showed
-- nothing -- and the bigger half.
--
-- A reflection off flat water points as far ABOVE the horizon as the eye is
-- above the water. At the top rung that is 15 degrees: the reflected ray
-- grazes the sky's pale end, sweeps the sun's own path and travels far
-- enough across the screen for the march to find the shoreline. At the 15
-- rung it is 75 degrees -- straight up. Up there the sky's bands are at
-- their DARKEST (deep blue over blue water, which is no picture at all), the
-- sun and moon sit at about 6 degrees of squashed elevation and are nowhere
-- near it, and the screen-space ray leaves the top of the frame in two
-- steps. All three of those are correct, and together they are a lake with
-- nothing in it.
--
-- So the reflected direction LEANS toward the way this camera is looking, by
-- however far the camera is from having a horizon in frame. That is a
-- deliberate stylisation and it is worth being exact about what it costs and
-- what it does not:
--
--   at the rung where the horizon IS in frame the lean is ZERO, so the one
--   place the join can actually be seen -- the waterline, where the lake
--   meets the painted sky -- is still the exact reflection it was.
--
--   at the rungs where the horizon is above the top edge there is no join to
--   break, and what the lean buys is the whole of the effect: the pale bands,
--   the sunset, the moon's path, and a screen-space ray that travels ACROSS
--   the diorama instead of straight out of it.
--
-- It leans toward an ELEVATION rather than by a weight, and that matters.
-- Mixing the ray a fixed fraction of the way toward horizontal sounds like
-- the same thing and is not: the ray it starts from is different at every
-- rung, so a fixed fraction lands them all somewhere different, and the
-- middle rungs came out worst of all -- further from the sun than the
-- steepest one. Aimed at an elevation, every rung below the top one puts its
-- reflection where the TOP rung puts its own, which is the one place the
-- effect is known to work.
--
-- Measured off Voxel3D.descent -- the sine of how far below horizontal the
-- view runs -- so it answers for the battle's placed camera too, which has
-- no rung to be asked about.
Water.LEAN_FROM = 0.30         -- descent where the lean starts: the top rung's
Water.LEAN_FULL = 0.55         -- and where it is complete
-- the elevation it aims at: the one the top rung's own reflection sits at,
-- stated as that same descent so the two cannot drift apart
Water.LEAN_ELEV = math.asin(Water.LEAN_FROM)

function Water.lean(descent)
  local span = Water.LEAN_FULL - Water.LEAN_FROM
  local t = ((descent or 0) - Water.LEAN_FROM) / span
  if t <= 0 then return 0 end
  return t < 1 and t or 1
end

-- ------- the waves
--
-- Not a normal map. The surface is a HEIGHTFIELD of one-world-pixel columns
-- -- the same unit every other voxel in this mode is built from, and exactly
-- one texel of the water tile (a tile is 8 texels across 8 world pixels) --
-- and every column stands at a whole number of pixels. So the water is a
-- field of little square bars rising and falling on their own, which is what
-- water made of pixels should look like from a camera that can see it in 3D.
--
-- It is drawn without any extra geometry. The mesh is still one flat quad
-- per tile; the columns are found by walking the view ray down through the
-- slab in the pixel shader (relief mapping) and taking the first one it
-- meets. That is what makes them read as SOLID rather than as shading: a
-- tall bar hides the shorter ones behind it, you see the SIDE of the ones
-- facing you, and the whole field parallaxes against the plane as the camera
-- moves. The side faces wear the mesh's own direction shading
-- (Voxel3D.FACE_SHADE, sent in rather than restated) so a wave crest is lit
-- like every other voxel in the world.
--
-- HEIGHT is in world pixels: the tallest a column may stand above the plane
-- the quad is drawn on, and so both the amplitude and the number of rungs a
-- crest can climb through (five gives six).
--
-- It is well past the 2px recess TileShape sinks water into, which is a
-- deliberate look rather than an oversight: the crests are RELIEF, drawn
-- inside the water quad's own screen footprint, so a bar that reaches above
-- the shoreline cannot actually spill over the bank -- it is clipped at the
-- water's edge like everything else this pass draws. What it buys is a
-- surface with real swell in it instead of a two-rung terrace.
Water.WAVE_HEIGHT = 5

-- ------- the trains
--
-- Each is { fx, fz, speed, weight }. The vector is the train's DIRECTION and
-- its frequency in one -- the crest runs across it, and two pi over its
-- length is the wavelength in world pixels -- and `speed` is what walks it.
--
-- The first one dominates, and that weighting is the whole difference
-- between water and soup: a wave has a direction, and its crest is a line
-- running across it for as far as the surface goes. Three trains of equal
-- weight cancel and reinforce in patches instead, and the field comes out as
-- round islands of raised pixels with no travel to them.
--
-- Long, too: the dominant wavelength is about forty world pixels, five
-- tiles, so a crest is a run of hundreds of columns at one height with a
-- step down either side. Pitched anywhere near a pixel they stop being waves
-- and become static -- every column its own island.
--
-- Read into the shader source rather than sent as uniforms, so the rate
-- below can be derived from the same numbers the field is built out of.
Water.WAVE_TRAINS = {
  { 0.150, 0.062, 1.60, 0.60 },
  { 0.058, 0.132, -1.05, 0.29 },
  { -0.041, 0.033, 0.55, 0.11 },
}

-- ------- and what keeps them from reading as one pattern
--
-- Three fixed trains are still an exactly periodic field: every forty-odd
-- pixels of sea wears the same crest at the same height, and a lake's worth
-- of that reads as wallpaper. Real swell varies two ways a sum of sines
-- cannot: waves arrive in SETS -- a few tall ones, then a lull -- and a
-- crest line curves as it runs rather than ruling itself across the whole
-- surface. Both are put back with one long-wavelength field each, riding
-- the DOMINANT train only; the two lesser trains stay plain, because they
-- are texture rather than structure and three modulators is soup again.
--
-- Both wear the trains' own shape, { fx, fz, speed, x }: a direction whose
-- length is the spatial frequency, a phase rate, and what the field does.
-- Their wavelengths sit four to five times the carrier's, far enough apart
-- that neither reads as a wave itself -- the swell as slow weather over the
-- crests, the bend as the crests' own drift.
--
-- THE SWELL scales the dominant train's amplitude; `x` is the DEPTH of the
-- deepest lull, as the fraction of the train it takes away. It runs roughly
-- along the carrier's own direction and slower than it, which is a wave
-- group's honest habit (deep-water groups travel at about half the phase
-- speed) -- so sets of crests swell up, march a while, and hand over to a
-- calm patch that is itself moving.
Water.WAVE_SWELL = { 0.0325, 0.0134, 0.55, 0.35 }

-- THE BEND adds a slow wobble to the dominant train's phase; `x` is the
-- wobble's reach in RADIANS of carrier phase. 1.1 radians against a carrier
-- of about forty pixels bows a crest some seven pixels off its line over
-- the bend's own hundred-and-seventy-five -- a visible curve, not a
-- scribble -- and it runs ACROSS the carrier, which is the direction a
-- crest line actually wanders. What it costs is exactness in waveRate's
-- derivation: the carrier's local frequency now breathes around the number
-- the rate is derived from, so the one-pixel step is the average step
-- rather than every step's. The step CLOCK is untouched; only how far a
-- bowed stretch of crest moves on one tick varies, and by under a pixel.
Water.WAVE_BEND = { -0.0138, 0.0333, 0.35, 1.10 }

-- ------- and the beat they move on
--
-- The surface does not slide, it advances in STEPS, off the engine's own
-- frame counter -- the move that makes this read as art rather than as a
-- simulation someone forgot to stylise. A surface built out of whole pixels
-- that crawls between them smoothly gives away that the quantisation is
-- only skin deep.
--
-- 12 a second, a shade under the 15 hand-drawn pixel art is usually
-- animated at: the crests were hurrying, and a big wave is slower than a
-- sprite's walk cycle. Still a clean divisor of the engine's 60, so every
-- step spans the same whole number of frames.
Water.WAVE_FPS = 12

-- How far the dominant train advances each of those steps, in WORLD PIXELS.
-- One is the honest choice for a stepped surface: the whole field shifts by
-- exactly one pixel per frame, so nothing ever lands half-way between two.
-- The rate below is derived from it rather than tuned beside it, so changing
-- a wavelength moves the speed with it instead of quietly desynchronising.
Water.WAVE_PIXELS_PER_STEP = 1

-- Radians of wave phase per second. A train travels `speed / frequency`
-- world pixels per radian of phase, so the phase that moves the dominant one
-- a pixel is its frequency over its speed -- times the step rate.
function Water.waveRate()
  local t = Water.WAVE_TRAINS[1]
  local freq = math.sqrt(t[1] * t[1] + t[2] * t[2])
  local speed = math.abs(t[3])
  if not (freq > 0 and speed > 0) then return 0 end
  return Water.WAVE_PIXELS_PER_STEP * (freq / speed) * Water.WAVE_FPS
end
-- Relief samples down through the slab. With the stride pinned at one world
-- pixel (see WAVE_STRIDE) this is also how FAR the march can see: sixteen
-- samples, sixteen pixels of parallax, which covers the slab at every rung
-- but the very lowest and leaves the rest to fade out honestly.
--
-- The pass early-outs entirely (see relief) whenever the camera is steep
-- enough that the whole slab projects to under a pixel across, which is most
-- of the ladder -- so the cost of this only lands where it buys something.
Water.WAVE_STEPS = 16

-- The furthest one relief sample may travel ACROSS the surface, in world
-- pixels -- which is what bounds how far the march runs in total.
--
-- The march's reach is the slab's depth over the ray's descent, so it grows
-- without limit as the camera flattens: at the top rung, fragments near the
-- horizon look along the water at a few degrees and the reach runs to
-- hundreds of world pixels. Spread over a fixed number of samples that steps
-- clean over whole crests, and the surface comes apart into streaks running
-- away from the eye. Capping the span is what keeps a sample worth taking;
-- what it costs is parallax on the far water, where the columns are under a
-- pixel across and there was nothing left to see anyway.
--
-- This is the FLOOR on it. The stride the march actually takes is a SCREEN
-- pixel's worth of surface, which is the only rate that makes sense:
--
--   up close, a screen pixel is a fraction of a world pixel, so the stride
--   sits on this floor of one world pixel and the march visits every column
--   on its path. It has to: a column is one world pixel wide, a longer
--   stride steps over columns, and which ones it misses changes from
--   fragment to fragment -- neighbouring pixels landing on different columns
--   at different heights wearing different faces. That is peppery noise.
--
--   far away, a screen pixel already spans several world pixels, so a stride
--   that matches it skips columns the screen could not have resolved anyway.
--   Holding it at one world pixel out there does not buy detail, it just
--   runs out of samples -- and a march that runs out stops part-way down the
--   slab and reports the surface as flat, which is why the lowest rung lost
--   its waves entirely across the whole middle distance.
Water.WAVE_STRIDE = 1

-- How far the wave field's own gradient tilts the REFLECTION. A multiplier
-- on the SMOOTH surface's slope, not on the stepped one -- see waveNormal
-- for why that distinction is the whole difference between a moon on the
-- water and confetti. The field's gradient peaks around 0.06 per world
-- pixel, so this lands the steepest faces about twelve degrees off vertical:
-- enough to sweep a low sun or moon into a broken glitter path down the
-- lake, and not so much that the sky's own bands come apart.
Water.WAVE_SLOPE = 3.5
-- and how far the horizon lean is allowed to open that up, since it squashes
-- the same tilt on its way past (see LEAN_FROM)
Water.WAVE_SLOPE_LEAN = 1.5

-- THE MARCH. Steps are in world pixels and lengthen as they go: near the
-- surface the reflection needs precision (a shoreline is a few pixels), far
-- from it reach matters more than accuracy, and a geometric ramp gets both
-- out of one loop. RAY_STEPS is compiled in -- GLSL wants a constant bound.
Water.RAY_STEPS = 24
Water.RAY_REFINE = 5           -- halvings once a crossing is found
Water.RAY_STEP = 3.0           -- world pixels in the first step
-- and the ratio each step after it. 3 x (1.18^24 - 1) / 0.18 is about 930
-- world pixels of reach -- three view-heights, past which a reflection is
-- faded out anyway (see the tail fade in march) and the sky is the honest
-- answer: distant water reflects haze, which is what the bands already are.
Water.RAY_GROW = 1.18
-- How far behind the depth buffer a crossing may land and still count, as a
-- multiple of the depth the step itself covered. A ray that dives far past
-- what it crossed went BEHIND a thin thing rather than hitting it -- the
-- classic screen-space smear, where a tree between the camera and the pond
-- paints itself across the water -- and this is the test that drops it.
Water.RAY_THICK = 1.6
Water.EDGE_FADE = 0.14         -- reflection eased off over this much of the frame

-- ------- the shader
--
-- The scene shader's own vertex path, plus the world position the geometry
-- was actually DRAWN at -- after the world curve, because that is the space
-- the surface the eye MEETS lives in: which wave column a screen pixel is
-- looking at is a question about the geometry as drawn, and relief() answers
-- it there. (The curve only ever moves Y, so a fragment's world XZ is the
-- same on both sides of it and the ripple can be measured off this one too.)
--
-- WHAT IT REFLECTS is worked out on the other side of the bend, in the FLAT
-- world, and this is the same rule the rest of the mode keeps: the curve
-- tips the world away and the things standing on it do not lean with it (see
-- WorldCurve -- buildings stay upright, shadows are resolved before the bend
-- and ride along). A lake is one of those things. Reflect off the bowl the
-- bend has made instead and the far half of a pond is a mirror tilted twenty
-- degrees: it throws the ray past the vertical, where the sky ramp's own
-- measure -- a screen row, through the frame's matrix -- swings from one end
-- of the ramp to the other across a single column, and the pond comes out
-- with hard-edged patches of the wrong sky stamped into it -- the overhead
-- band and the horizon band abutting in the middle of a lake, which reads as
-- something other than water showing through. The same tilt sends the
-- screen-space march grazing along the bank instead of over it, which is the
-- other half: the dock and the roofs smeared across the harbour.
--
-- So the reflection is taken with the flat view ray about the flat normal,
-- exactly as it would be with the curve off -- and the MARCH still has to
-- walk the world as drawn, because that is what the depth buffer holds. Both
-- at once: the ray is straight in the flat world, and project() bends each
-- sample on its way to the screen, which is the same displacement the vertex
-- stage applies and therefore lands in the same place the geometry did.
local SHADER_SRC = [[
varying float vShade;
varying vec3 vSun;
// World position, as drawn -- and a varying that cannot ride GLSL ES's
// mediump fragment default: everything below floors it into columns and
// marches it through the frame's matrices, and a route's coordinates run
// to a few thousand, where fp16 has no fraction left at all. The same
// reasoning the scene shader's vGrid states at length.
varying LOVE_HIGHP_OR_MEDIUMP vec3 vBent;

#ifdef VERTEX
uniform mat4 vp;
uniform mat4 model;
uniform mat4 sunVP;
uniform vec3 curve;          // xy = the focus in world XZ, z = k; 0 = off
attribute float VertexShade;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vShade = VertexShade;
  vec4 w = model * vertex_position;
  vSun = (sunVP * w).xyz;
  if (curve.z > 0.0) {
    vec2 cd = w.xz - curve.xy;
    w.y -= dot(cd, cd) * curve.z;
  }
  vBent = w.xyz;
  return vp * w;
}
#endif

#ifdef PIXEL
// Everything below works in WORLD units through the frame's own matrices,
// and GLSL ES defaults fragment floats to mediump -- fp16, out of fraction
// by a coordinate of two thousand and quantising a depth into steps the
// march falls straight through. Worse than wrong pictures: `vp` is
// declared by BOTH stages, the vertex side's default is highp, and GLSL ES
// refuses to LINK a uniform whose precision the two stages disagree on --
// which is not broken water but NO water shader at all, the flat fallback
// with nothing in the log. One statement lifts the whole stage; the guard
// keeps the odd GPU without fragment highp compiling, and such a driver
// falls back to flat water exactly as it did before this pass existed.
#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#endif
#endif
uniform mat4 vp;
uniform vec3 eye;
uniform vec2 screen;         // the canvas, in pixels
uniform float cell;          // one diorama pixel, in canvas pixels
uniform float pxAngle;       // radians of view one screen pixel subtends
// The same bend the vertex stage applied. This stage has to undo it to get
// back to the flat world it reflects in, and re-apply it on every marched
// sample to get back to the screen. Declared in both stages, like `vp`, and
// both are highp here.
uniform vec3 curve;          // xy = the focus in world XZ, z = k; 0 = off

// How far the bend has pushed the world down at world XZ `q` -- the vertex
// stage's own displacement, as a number this stage can add and subtract.
// Zero when the curve is off, which is the shader's "skip it" everywhere.
float bendDrop(vec2 q) {
  if (curve.z <= 0.0) return 0.0;
  vec2 d = q - curve.xy;
  return dot(d, d) * curve.z;
}

// the sun's own pass, exactly as the scene shader reads it
uniform Image sunMap;
uniform float sunDark;
uniform float sunBias;
uniform vec2 sunTexel;
uniform vec3 dayTint;

// the frame as it stood before the water went down, and its depth. The
// depth sampler is qualified because GLSL ES defaults samplers to LOWP no
// matter what floats are set to, and eight bits of depth is a march with
// nothing to land on. The frame copy is honest 8-bit colour and can stay.
uniform Image reflectTex;
uniform LOVE_HIGHP_OR_MEDIUMP Image depthTex;

uniform float rays;          // 0 = sky only, 1 = march the screen too
uniform vec3 lookFlat;       // the way the horizon lies from this camera
uniform float lean;          // and how far the reflection tilts toward it
uniform float leanElev;      // the elevation it aims at, in radians
uniform float waveHeight;    // the tallest column, in whole world pixels
uniform float waveSlope;     // how far a column's neighbours tilt its normal
uniform float waveSlopeLean; // and how far the horizon lean may open that up
uniform float waveT;
uniform vec4 faceShade;      // the mesh's own direction shading: E, W, S, N
uniform vec2 atlasSize;      // the tileset atlas, in texels
uniform float fresnelFloor;
uniform float fresnelCeil;
uniform float fresnelPower;
uniform float rayStep;
uniform float rayGrow;
uniform float rayThick;
uniform float edgeFade;

// the sky, as Sky paints it
uniform Image skyRamp;
uniform float skyCount;
uniform float skyEdge;       // the sky's bottom, in canvas pixels
uniform float skyStart;      // where the checker begins inside a band
uniform float skyOn;         // 0 indoors: there is no sky to reflect

// and what hangs in it
uniform vec3 bodyDir;
uniform float bodyOn;
uniform float bodyMoon;
uniform float bodyAng;       // the disc's angular radius, in radians
uniform vec3 bodyCore;
uniform vec3 bodyMain;
uniform vec3 bodyDark;
uniform float glowAmt;
uniform float glowReach;     // in radians, like bodyAng
uniform vec3 glowColor;

#ifdef VOXEL_GRID
uniform float gridDark;
uniform float gridWidth;
#endif

// ------- the sun's pass (the scene shader's, verbatim)

// One shadow tap: 1 where the sun reaches, 0 where something blocks it --
// EXCEPT that water declines one kind of blocker.
//
// The sun pass marks the cast in the blue channel (ShadowMap.sprites), and
// water ignores those. A character standing at a lake's edge laid a hard
// cut-out of its own sprite across the surface, and on something that is
// already showing the sky, the shoreline and the trees behind it, a
// silhouette of somebody reads as a sticker on the water rather than as a
// shadow in it. Everything the WORLD casts -- trees, buildings, cliffs,
// ledges -- still shades it, which is the half that was worth having.
float sunLit(vec2 uv, float z) {
  vec4 c = Texel(sunMap, uv);
  return max(step(z, c.r + c.g * (1.0 / 255.0)), c.b);
}

float sunlight(vec3 p) {
  if (sunDark <= 0.0) return 1.0;
  if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) {
    return 1.0;
  }
  vec2 e = min(p.xy, 1.0 - p.xy);
  float edge = smoothstep(0.0, 0.06, min(e.x, e.y));
  if (edge <= 0.0) return 1.0;
  float z = p.z - sunBias;
  float lit = sunLit(p.xy + sunTexel * vec2(-0.5, -0.5), z)
            + sunLit(p.xy + sunTexel * vec2( 0.5, -0.5), z)
            + sunLit(p.xy + sunTexel * vec2(-0.5,  0.5), z)
            + sunLit(p.xy + sunTexel * vec2( 0.5,  0.5), z);
  return 1.0 - sunDark * edge * (1.0 - lit * 0.25);
}

#ifdef VOXEL_GRID
// The wireframe, ruled on the COLUMNS rather than on the flat sheet they
// stand on.
//
// The scene shader reads a mesh's own model space, and for water that is the
// base plane -- so it would draw a grid across a flat sheet and ignore the
// bars entirely, which is the one thing that would give away that they are
// bars. What has to be outlined is what is actually SEEN: the column the ray
// landed on, at the height it landed at, so every voxel of water reads as
// its own block with its own edges.
//
// `p` is that hit; `base` is the smooth plane under it, and the derivative
// comes from THERE. `p` jumps a whole column between neighbouring fragments,
// so fwidth() of it reports a step rather than a scale and every column edge
// would blow out into a band. The plane underneath is smooth, and is the
// same scale in x and z that the columns are built on.
//
// `axis` is the direction the face does not vary along -- the top's own y,
// or a side's x or z. Its distance to the nearest plane is a constant zero,
// and taken at face value it floods the whole face solid; pushed out of
// reach it simply drops out, exactly as the scene shader's own seam handles
// the axis a face's normal points along.
float columnSeam(vec3 p, vec3 base, float axis) {
  vec3 w = fwidth(base);
  float wide = max(w.x, w.z);
  // the plane has no vertical extent of its own to measure, so y borrows
  // the horizontal scale -- it sets a line's THICKNESS and nothing else
  w.y = wide;
  vec3 d = abs(fract(p + 0.5) - 0.5);
  vec3 px = d / max(w, vec3(1e-6));
  if (axis < 0.5) { px.y += 1e6; }
  else if (axis < 1.5) { px.x += 1e6; }
  else { px.z += 1e6; }
  float near = min(min(px.x, px.y), px.z);
  // Fade out where a column is too small on screen to hold a line at all,
  // or the far water turns into a flat wash of seams rather than a grid.
  //
  // It holds on further than the scene shader's own does. That one is ruling
  // seams across whole 16px walls and roofs; these are one world pixel
  // apart, so the fade starts biting while the water is still perfectly
  // readable -- and at the lowest rung, where the middle distance is most of
  // the frame, it took the grid off nearly all of it. Full lines by a pixel
  // and a half of screen space, gone under three quarters of one.
  float span = 1.0 / max(wide, 1e-6);
  float fade = clamp((span - 0.75) * 1.35, 0.0, 1.0);
  return fade * clamp(gridWidth * 0.5 + 0.5 - near, 0.0, 1.0);
}
#endif

// ------- the sky, by direction

vec3 bandAt(float i) {
  return Texel(skyRamp,
               vec2((clamp(i, 0.0, skyCount - 1.0) + 0.5) / skyCount, 0.5)).rgb;
}

// Where a DIRECTION lands on the sky's own gradient, as a band coordinate
// in [0, count]: 0 is straight overhead, count the horizon.
//
// Measured by putting the direction through the very matrix the frame is
// drawn with, as a point at infinity -- which is how Voxel3D finds both the
// vanishing line and the sun's place on the canvas. So the reflected sky and
// the painted sky are answering the same question with the same arithmetic,
// and they agree at the waterline for free at any pitch, fov or zoom.
//
// A direction whose w comes out negative is BEHIND the camera plane, which
// for an upward reflection means near-vertical: the top band, overhead.
float skyPos(vec3 d) {
  vec4 c = vp * vec4(d, 0.0);
  if (c.w <= 1e-6) return 0.0;
  float py = (c.y / c.w * 0.5 + 0.5) * screen.y;
  float row = floor(py / cell) * cell;
  return clamp(row / max(skyEdge, 1.0), 0.0, 1.0) * skyCount;
}

// `parity` is the diorama checkerboard this fragment sits on -- the same
// one Sky's own dither is cut from, so the reflected gradient breaks up in
// the same 8-bit way rather than being the one smooth thing in the frame.
vec3 skyAt(vec3 d, float parity) {
  float pos = skyPos(d);
  float base = min(floor(pos), skyCount - 1.0);
  vec3 c = bandAt(base);
  if (base < skyCount - 1.0 && (pos - base) > skyStart && parity < 0.5) {
    c = bandAt(base + 1.0);
  }
  return c;
}

float crater(vec2 p, vec2 c, float r) {
  vec2 dd = p - c;
  return step(dot(dd, dd), r * r);
}

// The sun or moon, and the twilight warmth around it, laid over the bands.
//
// By ANGLE, not by screen position: the reflected direction usually
// projects off the top of the frame entirely, where screen distances stop
// meaning anything. bodyAng is Sky.discRadius run back through the camera's
// field of view, so this disc is the same size as the painted one.
vec3 bodyAt(vec3 d, vec3 c, float parity) {
  if (bodyOn <= 0.0) return c;
  float ang = acos(clamp(dot(d, bodyDir), -1.0, 1.0));
  if (glowAmt > 0.0) {
    float g = glowAmt * pow(clamp(1.0 - ang / glowReach, 0.0, 1.0), 2.0);
    float lvl = floor(g * 4.0);
    if (g * 4.0 - lvl > 0.5 && parity < 0.5) { lvl += 1.0; }
    c = mix(c, glowColor, min(lvl / 3.0, 1.0) * 0.65);
  }
  if (ang > bodyAng) return c;
  float t = ang / bodyAng;
  // the dithered rim, exactly as the painted disc keeps one parity of its
  // outer ring of cells
  if (t > 0.86 && parity < 0.5) return c;
  vec3 disc = (t <= 0.5) ? bodyCore : bodyMain;
  if (bodyMoon > 0.5) {
    // disc-local coordinates: a frame built off world up, so the craters
    // sit on the moon the same way round every night
    vec3 t1 = normalize(cross(vec3(0.0, 1.0, 0.0), bodyDir));
    vec2 dc = vec2(dot(d, t1), dot(d, cross(bodyDir, t1))) / bodyAng;
    float k = 0.0;
//@CRATERS
    if (k > 0.0) { disc = bodyDark; }
  }
  return disc;
}

// ------- the screen-space march

// A point as (uv, depth, valid), through the very matrix the frame was drawn
// with. The uv and the depth are the same numbers the hardware wrote -- the
// clip-space Y flip is already baked into `vp`, and a canvas texture's v runs
// the same way its pixel rows do, so one 0.5x+0.5 answers for both.
//
// The point arrives in the FLAT world -- the space the ray is straight in --
// and is bent here, by the same displacement the vertex stage applied, so it
// lands exactly where the geometry it is being compared against landed. That
// split is the whole trick: the reflection is worked out in a world that has
// not been tipped, and every sample of it is tipped on the way to the screen,
// so the march reads the depth buffer it actually has.
vec4 project(vec3 p) {
  p.y -= bendDrop(p.xz);
  vec4 c = vp * vec4(p, 1.0);
  if (c.w <= 1e-6) return vec4(0.0, 0.0, 0.0, 0.0);
  return vec4(c.xy / c.w * 0.5 + 0.5, c.z / c.w * 0.5 + 0.5, 1.0);
}

// Walk the reflected ray until it passes behind the depth buffer. Returns
// the colour found in .rgb and how much of it to believe in .a -- 0 for a
// ray that left the frame, ran out of steps, or crossed something it went
// straight through rather than landed on.
vec4 march(vec3 origin, vec3 dir) {
  vec4 miss = vec4(0.0, 0.0, 0.0, 0.0);
  vec3 a = origin;
  vec4 pa = project(a);
  if (pa.w < 0.5) return miss;
  float len = rayStep;
  for (int i = 0; i < RAY_STEPS; i++) {
    vec3 b = a + dir * len;
    vec4 pb = project(b);
    if (pb.w < 0.5) return miss;
    if (pb.x < 0.0 || pb.x > 1.0 || pb.y < 0.0 || pb.y > 1.0) return miss;
    float scene = Texel(depthTex, pb.xy).r;
    if (pb.z > scene) {
      // how much depth this one step covered: the yardstick for whether
      // the crossing is a surface or a thin thing the ray shot past
      float span = max(abs(pb.z - pa.z), 1e-7);
      if (pb.z - scene > span * rayThick) return miss;
      // binary-refine onto the contact
      vec3 lo = a;
      vec3 hi = b;
      for (int k = 0; k < RAY_REFINE; k++) {
        vec3 m = (lo + hi) * 0.5;
        vec4 pm = project(m);
        if (pm.z > Texel(depthTex, pm.xy).r) { hi = m; } else { lo = m; }
      }
      vec4 hit = project(hi);
      if (hit.w < 0.5) return miss;
      // Ease out at the frame's rim, where the reflection is about to run
      // off the only evidence there is -- and with distance travelled, so a
      // long ray hands back to the sky instead of ending on a hard edge.
      //
      // The distance term is doing two jobs. It hides the march's own tail,
      // where the steps are longest and a grazing crossing is least likely
      // to be a real surface -- and it is also true: distant water reflects
      // haze rather than detail, and the haze is what the bands underneath
      // already are. The small floor keeps a genuine far hit as a trace
      // rather than deleting it.
      vec2 e = min(hit.xy, 1.0 - hit.xy);
      float edge = smoothstep(0.0, edgeFade, min(e.x, e.y));
      float far = 1.0 - clamp(float(i) / float(RAY_STEPS), 0.0, 1.0);
      return vec4(Texel(reflectTex, hit.xy).rgb, edge * (0.15 + 0.85 * far));
    }
    a = b;
    pa = pb;
    len *= rayGrow;
  }
  return miss;
}

// ------- the surface, as a field of pixel-tall columns

// How high the column at world pixel `q` stands, in WHOLE world pixels.
//
// Whole, because that is what makes them BARS: a column is a voxel like
// every other voxel in this mode, one unit on a side, and a surface that
// stepped in fractions would just be a smooth wave with extra arithmetic.
// Three crossing wave trains, so the field has no readable repeat inside a
// lake's worth of pixels.
//
// The SMOOTH surface underneath, 0 to 1 -- the thing the columns are a
// quantisation of. Summed from Water.WAVE_TRAINS, which is where the trains
// and the reasoning behind their weights live; pasted in rather than sent,
// so the speed derived from those same numbers cannot drift from the field
// they describe.
float waveRaw(vec2 q) {
  float h = 0.0;
//@TRAINS
  return h * 0.5 + 0.5;
}

// and the voxel surface: that field, in whole world pixels.
float waveAt(vec2 q) {
  if (waveHeight <= 0.0) return 0.0;
  return floor(waveRaw(q) * waveHeight + 0.5);
}

// The tilt this column reflects with -- taken from the SMOOTH field, not
// from the stepped one, and this is the difference between a moon on the
// water and confetti.
//
// Floored heights are integers, so their differences are integers too: a
// column's neighbours are level with it or a whole pixel off, and nothing in
// between. Build the normal out of THOSE and the reflected ray can only ever
// point in about five directions -- straight up, or rotated by twice the
// arctangent of one step, or of two. A flat sky does not mind; the sun and
// the moon are discs barely two degrees across, and a ray that jumps in
// eighteen-degree increments simply steps over them. The lake goes dark and
// the odd column that happens to land dead on flares -- which is exactly
// what "the moon doesn't reflect right" looks like.
//
// The columns are an approximation of a real surface, and light reflects off
// the surface being approximated. So the SHAPE stays quantised -- it is what
// you see, and it is the whole point -- while the normal is read off the
// smooth field the shape is made from. Still one answer per column, because
// `q` is an integer: pixel-quantised in space, continuous in value, which
// puts the glitter path back without softening a single edge.
//
// Forward differences over one pixel: three samples, and the answer only has
// to say which way this piece of the surface leans.
vec3 waveNormal(vec2 q, float tilt) {
  float h = waveRaw(q);
  float e = waveRaw(q + vec2(1.0, 0.0)) - h;
  float s = waveRaw(q + vec2(0.0, 1.0)) - h;
  return normalize(vec3(-e * tilt, 1.0, -s * tilt));
}


// Walk the view ray down through the wave slab and return the column it
// actually meets -- RELIEF MAPPING, and the whole reason the bars read as
// solid rather than as a pattern painted on a flat sheet.
//
// The mesh is still one flat quad per tile, so what gets rasterised is the
// point where the ray crosses the BASE plane. The visible surface is
// somewhere above that, and the two differ by more the lower the camera
// sits. So the ray is walked BACKWARD to the top of the slab and then
// stepped down: the first column whose top it falls below is what the eye is
// looking at, and everything shorter behind that column is hidden by it for
// free, because the march simply never reaches it.
//
// A step that lands below a column's top having just ARRIVED in that column
// is looking at its side; one that was already there and fell through is
// looking at its top. That is the whole of the face test, and it is what
// gives a crest a lit face and a shaded one.
//
// `axis` names which way the face it found points -- 0 top, 1 east/west, 2
// north/south -- because the wireframe needs to know the one direction the
// face does not vary along (see columnSeam).
void relief(vec3 base, vec3 dir, out vec3 hit, out vec2 col, out float face,
            out float axis) {
  col = floor(base.xz);
  hit = base;
  face = 1.0;
  axis = 0.0;
  float dy = -dir.y;
  // a ray running level along the surface has no slab to walk through, and
  // dividing by its descent would send the start point to infinity
  if (waveHeight <= 0.0 || dy < 0.02) return;
  float across = length(dir.xz);
  float reach = waveHeight / dy;
  // How far across the surface the whole slab displaces the answer. Under
  // half a pixel it cannot pick a different column than the one already
  // under the fragment, so the march would spend its samples arriving where
  // it started -- which is exactly the case at the steep rungs, where the
  // camera looks nearly straight down the columns and there is no side of a
  // bar to see anyway.
  float span = reach * across;
  if (span < 0.5) {
    hit.y = base.y + waveAt(col);
    return;
  }
  // and the other end: `reach` grows as one over the descent, so a grazing
  // ray asks for hundreds of world pixels of march from a fixed number of
  // samples.
  //
  // What one sample is worth is a SCREEN pixel of surface, so that is the
  // stride (see WAVE_STRIDE). A screen pixel covers this much of the water:
  // the distance to the eye times the angle one pixel subtends, opened out
  // by the obliquity -- a surface seen edge-on runs away far faster per
  // pixel than one seen face-on. Floored at a world pixel, because up close
  // a finer stride than the columns themselves buys nothing and skipping
  // them costs everything.
  float dist = length(base - eye);
  float stride = max(WAVE_STRIDE, dist * pxAngle / dy);
  float maxSpan = float(WAVE_STEPS) * stride;
  if (span > maxSpan) { reach = maxSpan / max(across, 1e-4); }
  vec3 top = base - dir * reach;
  vec2 wasCol = floor(top.xz);
  for (int i = 1; i <= WAVE_STEPS; i++) {
    vec3 p = mix(top, base, float(i) / float(WAVE_STEPS));
    vec2 q = floor(p.xz);
    float y = base.y + waveAt(q);
    if (p.y <= y) {
      col = q;
      hit = vec3(p.x, y, p.z);
      vec2 d = q - wasCol;
      if (abs(d.x) + abs(d.y) < 0.5) {
        face = 1.0;                                  // fell through the top
        axis = 0.0;
      } else if (abs(d.x) > abs(d.y)) {
        face = (d.x > 0.0) ? faceShade.y : faceShade.x;   // west : east
        axis = 1.0;
      } else {
        face = (d.y > 0.0) ? faceShade.w : faceShade.z;   // north : south
        axis = 2.0;
      }
      return;
    }
    wasCol = q;
  }
}

// The water's own art, read at the column the ray landed on rather than at
// the fragment's own place on the flat quad -- otherwise the bars parallax
// away and the pixels they are made of stay behind on the plane.
//
// Read off the COLUMN, not off the fragment.
//
// One world pixel is one atlas texel exactly, and the mesher lays a tile's
// eight texels across its eight world pixels -- so the column at world
// (cx, cz) wears texel (cx mod 8, cz mod 8) and nothing else. That makes the
// lookup exact, and far more importantly STABLE: the art a column shows
// depends only on where that column stands in the world, so it cannot swim
// as the camera moves and two fragments that landed on the same column
// cannot disagree about it.
//
// Offsetting the fragment's own uv by the parallax instead makes the art
// depend on how far the march happened to travel -- and wherever the march
// skipped a column, neighbouring fragments picked texels several apart. That
// is what peppered the surface with noise, and why it cleared up in patches:
// the patches are where the march was not skipping.
//
// The tile origin is the FRAGMENT's, so the lookup can never leave the tile
// this quad was built to sample -- the same bleed the mesher's INSET stops.
vec2 waveUV(vec2 tc, vec2 col) {
  vec2 texel = 1.0 / atlasSize;
  vec2 tile = 8.0 * texel;
  vec2 org = floor(tc / tile) * tile;
  return org + (mod(col, 8.0) + 0.5) * texel;
}

// The float parameters are pinned to mediump BECAUSE the stage default is
// not: LOVE's own header forward-declares effect() under its default, and
// at least one mobile compiler (Samsung's Xclipse, in so many words) holds
// that a definition whose parameter precisions differ from its prototype's
// is a second function of the same name, and refuses the pair. The params
// can afford it -- the colour is a colour, and tc/sc arrived through
// LOVE's mediump plumbing whatever this signature says -- and the maths
// below runs on the stage default the moment the values touch a local.
vec4 effect(mediump vec4 color, Image tex, mediump vec2 tc, mediump vec2 sc) {
  // THE DEPTH TEST, done here because the buffer that would have done it is
  // detached for the length of this pass so it can be READ (see the header).
  // Same comparison, same buffer, same result: a building in front of a pond
  // still hides it.
  //
  // Normalised by LOVE's own screen size, not by the `screen` uniform: `sc`
  // arrives in canvas PIXELS, and on a highdpi surface (Android's density
  // is routinely 2.625) a canvas holds that many pixels per canvas UNIT,
  // which is what `screen` counts. Divided by units, uv runs to 2.6 and
  // clamps, and the test reads edge texels for two thirds of the frame --
  // discarding water in blocks and letting the haze backdrop through, which
  // on a phone looked like lakes with pieces missing. love_ScreenSize.xy is
  // the bound canvas's own pixel size, the same units sc is measured in, on
  // every display. (`screen` stays in units: skyPos reads it against cell
  // and skyEdge, which are unit-measured with it.)
  //
  // The buffer now holds THIS SURFACE too (VoxelScene draws the water flat
  // before the pass that reflects it), which is what makes one lake able to
  // hide another -- and it means every fragment here is testing against its
  // own depth. That raises the bar on the fragment's own z: gl_FragCoord is
  // allowed to be MEDIUMP on GLES (and is, on Adreno), and fp16 near the far
  // end of the range steps by about half a thousandth -- which the old test
  // against the terrain far behind the surface never felt, and a comparison
  // of the surface against itself loses outright. Every fragment failed, the
  // pass discarded the whole lake, and Android showed the flat draw
  // underneath. So the depth is recomputed HERE, in highp, from the same
  // vBent and vp the vertex stage used -- full precision on every driver.
  //
  // The slack is sized to what remains after that, which is not rounding:
  // the buffer holds depth interpolated LINEARLY IN SCREEN SPACE, while the
  // recomputation projects the perspective-interpolated vBent -- the exact
  // answer. The two agree at the vertices and drift apart across a quad's
  // interior, by more the bigger the quad stands on screen; on a phone
  // (fit scale 6, water quads hundreds of pixels tall) the drift crosses
  // 1e-5 mid-quad, which discarded the middle of every tile row and looked
  // like flat water with reflective seams. Anything GENUINELY in front of a
  // water pixel is whole world units nearer -- upward of 1e-3 in depth --
  // so 2e-4 clears the drift with room while still catching every occluder.
  vec2 uv = sc / love_ScreenSize.xy;
  vec4 selfC = vp * vec4(vBent, 1.0);
  float selfZ = selfC.z / selfC.w * 0.5 + 0.5;
  if (selfZ > Texel(depthTex, uv).r + 2e-4) discard;

  // THE COLUMN THIS FRAGMENT IS LOOKING AT. Every water pixel is a bar of
  // its own standing a whole number of pixels tall, and the ray decides
  // which one it meets -- so what follows is answered per COLUMN and not per
  // screen pixel: one colour to a bar, at the resolution the water art is
  // drawn at, with no smooth shading anywhere across it. (The depth test
  // above is the one thing that stays per fragment: that is the hardware's
  // own question and it is asked in screen space.)
  //
  // Answered on the FLAT sheet, which is where the bars are a slab of even
  // thickness over a level plane -- the one thing relief() is built on. The
  // bend translates every bar straight down by its own column's drop, so the
  // field keeps its shape and only its height moves; undo that here and the
  // walk is the walk it was written for. Try it in the world as DRAWN
  // instead and the slab is a bowl: the backward step up the ray climbs the
  // bowl's near side as fast as it climbs out of the water, the walk starts
  // inside the sheet, and it hands back a column a pixel or three off -- per
  // fragment, differently, which is a patch of noise rather than parallax.
  vec3 sheet = vec3(vBent.x, vBent.y + bendDrop(vBent.xz), vBent.z);
  vec3 view = normalize(sheet - eye);
  vec3 hit;
  vec2 col;
  float face;
  float axis;
  relief(sheet, view, hit, col, face, axis);
  // and the bar's centre, so a column is sampled and reflected from one
  // place rather than from wherever inside it the fragment happened to land
  vec3 surf = vec3(col.x + 0.5, hit.y, col.y + 0.5);

  vec4 p = Texel(tex, waveUV(tc, col));
  if (p.a < 0.5) discard;
  // `face` is the column's own side shading, which is what makes a crest
  // read as a solid thing with a lit flank rather than as a bright patch
  vec3 base = p.rgb * vShade * face * sunlight(vSun) * dayTint;

  // the reflection follows the WAVES' own shape -- the tilt this column
  // takes from the neighbours it stands beside -- rather than an invented
  // wobble, so the sky and the sun break along the bars instead of across
  // them. Opened up by the lean, which is about to squash it (see below).
  vec3 n = waveNormal(col, waveSlope * (1.0 + lean * waveSlopeLean));
  vec3 r = reflect(view, n);
  // the same reflection off a LEVEL surface, which is what the lean below
  // moves: the difference between the two is this column's own contribution
  vec3 rFlat = reflect(view, vec3(0.0, 1.0, 0.0));
  // The horizon lean (see LEAN_FROM in Water.lua): zero at the rung whose
  // horizon is in frame, so the waterline join is untouched; taking the ray
  // down to the elevation THAT rung reflects at as the camera tips over,
  // where there is no join to break and a straight-up reflection has nothing
  // in it. Applied to the sky, the body AND the march, because the same
  // seventy-five-degree ray that misses the sun also leaves the frame.
  //
  // What is leaned is the LEVEL reflection, with this column's own deflection
  // put back on top afterwards. Leaning the perturbed ray instead sets its
  // elevation outright, which overwrites the very variation the waves are
  // there to provide: at full lean every column on the lake reflects the
  // same elevation, the sky comes out one flat band and the moon -- a disc
  // two degrees wide that the ray now never sweeps past -- vanishes
  // completely. Which is exactly what it did.
  //
  // The ray keeps its own BEARING and is only tipped in elevation, so a
  // reflection still points where the water is pointing it -- and a ray so
  // near vertical that it has no bearing left borrows the camera's.
  if (lean > 0.0) {
    float fl = length(rFlat.xz);
    vec3 bearing = (fl > 1e-3) ? vec3(rFlat.x / fl, 0.0, rFlat.z / fl)
                               : lookFlat;
    float e = mix(asin(clamp(rFlat.y, -1.0, 1.0)), leanElev, lean);
    r = normalize(bearing * cos(e) + vec3(0.0, sin(e), 0.0) + (r - rFlat));
  }

  // The checkerboard the sky's bands and the sunset's glow are dithered on,
  // cut from the WATER's own columns rather than from the screen. Same
  // reasoning the window glint follows in the scene shader: a pattern
  // anchored to the screen has the world sliding through it at zoom speed
  // whenever the camera pans, which strobes. Anchored to the surface,
  // panning moves nothing and only the waves do.
  float parity = mod(col.x + col.y, 2.0);
  vec3 refl = base;
  if (skyOn > 0.5) {
    refl = bodyAt(r, skyAt(r, parity), parity);
  }
  if (rays > 0.5) {
    vec4 hit = march(surf, r);
    refl = mix(refl, hit.rgb, hit.a);
  }

  // Schlick, floored and softened (see FRESNEL_* in Water.lua): the angle
  // still decides, a grazing camera still gets a mirror, and a steep one
  // still gets a pond rather than a flat sticker.
  float ct = clamp(dot(-view, n), 0.0, 1.0);
  float f = fresnelFloor
            + (fresnelCeil - fresnelFloor) * pow(1.0 - ct, fresnelPower);
  vec3 rgb = mix(base, refl, clamp(f, 0.0, 1.0));

#ifdef VOXEL_GRID
  rgb *= 1.0 - gridDark * columnSeam(hit, sheet, axis);
#endif
  return vec4(rgb, 1.0) * color;
}
#endif
]]

-- The crater list is Sky's (Sky.MOON_CRATERS), pasted in as source rather
-- than sent as a uniform array: GLSL ES has no array constructors worth
-- relying on, and the driver bug that cost the sky its bands is exactly
-- what a uniform array of vectors buys. Built from the one list, so the
-- moon on the water can never grow craters the moon in the sky has not.
local function craterSource()
  local out = {}
  for _, c in ipairs(Sky.MOON_CRATERS) do
    out[#out + 1] = ("    k += crater(dc, vec2(%.4f, %.4f), %.4f);")
      :format(c[1], c[2], Sky.CRATER_FRAC)
  end
  return table.concat(out, "\n")
end

Water._craterSource = craterSource     -- named for the suite

-- and the wave trains, pasted in for the same reason: the rate is derived
-- from this table (Water.waveRate), so the field the shader sums has to be
-- the one that table describes rather than a copy of it kept in step by hand.
--
-- The dominant train carries the swell and the bend (see WAVE_SWELL): its
-- phase wobbles by the bend field and its amplitude breathes with the swell
-- envelope, both off the same tables the constants above document. One
-- statement per train either way, which is what the suite counts.
local function trainSource()
  local out = {}
  for i, t in ipairs(Water.WAVE_TRAINS) do
    if i == 1 then
      local s = Water.WAVE_SWELL
      local b = Water.WAVE_BEND
      out[#out + 1] = (
        "  h += sin(dot(q, vec2(%.4f, %.4f)) + waveT * %.4f\n"
        .. "           + %.4f * sin(dot(q, vec2(%.4f, %.4f)) + waveT * %.4f))\n"
        .. "       * %.4f * (1.0 - %.4f * (0.5 + 0.5 *\n"
        .. "           sin(dot(q, vec2(%.4f, %.4f)) + waveT * %.4f)));")
        :format(t[1], t[2], t[3],
                b[4], b[1], b[2], b[3],
                t[4], s[4], s[1], s[2], s[3])
    else
      out[#out + 1] = ("  h += sin(dot(q, vec2(%.4f, %.4f)) + waveT * %.4f)"
                       .. " * %.4f;"):format(t[1], t[2], t[3], t[4])
    end
  end
  return table.concat(out, "\n")
end

Water._trainSource = trainSource       -- named for the suite

local function source(grid)
  local src = SHADER_SRC:gsub("//@CRATERS", (craterSource():gsub("%%", "%%%%")))
  src = src:gsub("//@TRAINS", (trainSource():gsub("%%", "%%%%")))
  local head = ("#define RAY_STEPS %d\n#define RAY_REFINE %d\n"
                .. "#define WAVE_STEPS %d\n#define WAVE_STRIDE %.1f\n")
    :format(Water.RAY_STEPS, Water.RAY_REFINE, Water.WAVE_STEPS,
            Water.WAVE_STRIDE)
  if grid then head = head .. "#define VOXEL_GRID 1\n" end
  return head .. src
end

Water._source = source                 -- named for the suite

-- Two compilations, exactly as Voxel3D keeps two of the scene shader: the
-- wireframe variant needs derivatives, the one thing a driver can refuse,
-- and a refusal must cost the seams on the water and nothing else.
-- nil = untried, false = unavailable.
local shaders = { [false] = nil, [true] = nil }

function Water.shader(grid)
  grid = grid and true or false
  if shaders[grid] == nil then
    if not (love.graphics and love.graphics.newShader) then
      shaders[grid] = false
    else
      local ok, sh = pcall(love.graphics.newShader, source(grid))
      if not ok and V and V.mod and V.mod.log then
        -- once, where it can be read: the fallback is flat water, which is
        -- easy to look at and impossible to diagnose without this line
        V.mod.log:warn("water shader did not compile: %s -- lakes draw flat",
                       tostring(sh))
      end
      shaders[grid] = (ok and sh) or false
    end
  end
  return shaders[grid] or nil
end

-- ------- the pass

local active = nil        -- the shader this pass bound, or nil

-- The ripple phase. Driven by the ENGINE's tile-animation clock, the same
-- 60Hz counter the water tiles rotate on, so the ripple and the art it
-- ripples move off one number rather than drifting against each other.
local function waveTime()
  -- lazily, and through the mod namespace: TerrainAtlas reaches into the
  -- engine's renderer at load time, and nothing about a settings row should
  -- depend on that having happened yet
  local ok, frame = pcall(function()
    return V.require("TerrainAtlas")._animFrame()
  end)
  if not (ok and type(frame) == "number") then return 0 end
  -- floored to the wave beat (see WAVE_FPS). The engine's counter runs at
  -- 60, so this is the frame that step began on.
  local period = 60 / math.max(1, Water.WAVE_FPS)
  return (math.floor(frame / period) * period / 60) * Water.waveRate()
end

Water._waveTime = waveTime

-- Begin the reflective pass.
--
-- `ctx` is everything the pass cannot work out for itself, all of it already
-- computed by whoever set the camera up this frame:
--
--   reflect   the frame so far, as a texture (Voxel3D.beginWater)
--   depth     its depth, likewise
--   vp, eye, curve, screen, cell   the camera, as beginScene sent it
--   skyEdge   where the sky's bottom is, or nil indoors / with no bands
--   grid      whether the voxel wireframe is compiled into this frame
--
-- Returns false when the pass cannot run, in which case the caller draws the
-- water mesh through the ordinary scene shader instead.
function Water.begin(ctx)
  if not (ctx and ctx.reflect and ctx.depth) then return false end
  local level = Water.level()
  if level <= 0 then return false end
  local sh = ctx.grid and Water.shader(true) or nil
  if not sh then sh = Water.shader(false) end
  if not sh then return false end

  love.graphics.setShader(sh)
  love.graphics.setColor(1, 1, 1, 1)
  local function send(name, ...)
    pcall(sh.send, sh, name, ...)
  end

  send("vp", "row", ctx.vp)
  send("eye", ctx.eye)
  send("curve", ctx.curve)
  send("screen", { ctx.screen[1], ctx.screen[2] })
  send("cell", math.max(1, ctx.cell or 1))
  -- how much of the view one screen pixel is worth: what sets the relief
  -- march's stride, so a sample is always about a pixel of surface
  send("pxAngle", (ctx.fov or 1) / math.max(1, ctx.screen[2]))
  send("reflectTex", ctx.reflect)
  send("depthTex", ctx.depth)

  -- the sun's pass, sent the same way and for the same reason the scene
  -- shader sends it: the sampler is declared either way, and leaving one
  -- unbound is a driver-dependent crash rather than a fallback
  local map = ShadowMap.active()
  send("sunVP", "row", map and ShadowMap.uvVP or Mat4.identity())
  local tex = ShadowMap.texture()
  if tex then send("sunMap", tex) end
  local Voxel3D = V.require("Voxel3D")
  send("sunDark", map and Voxel3D.SHADOW_ALPHA or 0)
  send("sunBias", ShadowMap.bias)
  local texel = 1 / ShadowMap.res
  send("sunTexel", { texel, texel })
  send("dayTint", Voxel3D.tint or { 1, 1, 1 })

  send("rays", level >= 2 and 1 or 0)
  -- the horizon lean, and the direction it leans toward (see Water.lean)
  send("lookFlat", ctx.lookFlat or { 0, 0, -1 })
  send("lean", Water.lean(ctx.descent))
  send("leanElev", Water.LEAN_ELEV)
  send("waveHeight", Water.WAVE_HEIGHT)
  send("waveSlope", Water.WAVE_SLOPE)
  send("waveSlopeLean", Water.WAVE_SLOPE_LEAN)
  send("waveT", waveTime())
  -- the columns' side faces wear the MESH's own direction shading, sent in
  -- rather than restated, so a wave crest is lit like every other voxel
  local fs = Voxel3D.FACE_SHADE
  send("faceShade", { fs[1], fs[2], fs[5], fs[6] })   -- east, west, south, north
  send("fresnelFloor", Water.FRESNEL_FLOOR)
  send("fresnelCeil", Water.FRESNEL_CEIL)
  send("fresnelPower", Water.FRESNEL_POWER)
  send("rayStep", Water.RAY_STEP)
  send("rayGrow", Water.RAY_GROW)
  send("rayThick", Water.RAY_THICK)
  send("edgeFade", Water.EDGE_FADE)
  if ctx.grid then
    local VoxelGrid = V.require("VoxelGrid")
    send("gridDark", VoxelGrid.DARK)
    send("gridWidth", VoxelGrid.width())
  end

  Water.sendSky(sh, ctx)
  active = sh
  return true
end

-- The sky half of the uniforms: the band ramp, and whatever hangs in it.
--
-- Split out because it is the part with a "there is none" answer -- indoors,
-- and on any frame whose ramp could not be built -- and that answer has to
-- leave every sampler bound anyway. skyOn 0 reflects the water's own colour
-- back at itself, which is what a pond in a cave does.
function Water.sendSky(sh, ctx)
  local function send(name, ...)
    pcall(sh.send, sh, name, ...)
  end
  local ramp, count = Sky.ramp()
  local edge = ctx.skyEdge
  if not (ramp and count and edge and edge > 0) then
    -- the sampler still has to hold something; the ramp is the only image
    -- this shader has for the job, so bind the frame copy and switch it off
    send("skyRamp", ctx.reflect)
    send("skyCount", 1)
    send("skyEdge", 1)
    send("skyStart", 2)
    send("skyOn", 0)
    send("bodyOn", 0)
    send("glowAmt", 0)
    return
  end
  send("skyRamp", ramp)
  send("skyCount", count)
  send("skyEdge", edge)
  send("skyStart", Sky.DITHER and Sky.DITHER_START or 2)
  send("skyOn", 1)

  local body = DayNight.body()
  if not body then
    send("bodyOn", 0)
    send("glowAmt", 0)
    return
  end
  local amt, glowColor = DayNight.glow()
  local h = ctx.screen[2]
  local cell = math.max(1, ctx.cell or 1)
  -- Sky sizes the disc in canvas pixels; out here the reflected body is
  -- usually off the top of the frame, where a pixel is not a unit any more
  -- -- so it is converted to the ANGLE it subtends through this camera's
  -- own field of view, which is the same number wherever it is looked at.
  local perRadian = h / math.max(1e-4, ctx.fov or 1)
  local rpx = Sky.discRadius(h, cell,
                             { moon = body.moon, glowAmt = amt })
  local shades = Sky.discShades(body.moon)
  local function shade(i)
    local c = shades[i] or shades[#shades] or { 255, 255, 255 }
    return { c[1] / 255, c[2] / 255, c[3] / 255 }
  end
  local twilight = (amt or 0) > 0.25 and not body.moon
  send("bodyOn", 1)
  send("bodyMoon", body.moon and 1 or 0)
  send("bodyDir", { body.dx, body.dy, body.dz })
  send("bodyAng", rpx / perRadian)
  send("bodyCore", shade(1))
  send("bodyMain", shade(twilight and 3 or 2))
  send("bodyDark", shade(3))
  send("glowAmt", (not body.moon) and (amt or 0) or 0)
  send("glowColor", glowColor
       and { glowColor[1] / 255, glowColor[2] / 255, glowColor[3] / 255 }
       or { 1, 0.88, 0.66 })
  send("glowReach", (ctx.screen[1] * Sky.GLOW_REACH) / perRadian)
end

-- Draw one water mesh with `model` applied. Mirrors Voxel3D.draw, minus the
-- camera-ward pull (a flat sheet has nothing to lean over) and the separate
-- sun transform (water is terrain: the sun saw the same matrix).
function Water.draw(mesh, texture, model)
  if not (active and mesh) then return end
  if texture then mesh:setTexture(texture) end
  pcall(active.send, active, "model", "row", model or Mat4.identity())
  -- Per draw rather than per pass, and read off the TEXTURE rather than
  -- assumed: it is what converts a world pixel of the columns' parallax into
  -- the texel of art standing on it, and two maps in one frame can be drawn
  -- from atlases of different sizes.
  if texture and texture.getDimensions then
    local ok, w, h = pcall(texture.getDimensions, texture)
    if ok and w and h then
      pcall(active.send, active, "atlasSize", { w, h })
    end
  end
  love.graphics.draw(mesh)
end

function Water.finish()
  active = nil
end

-- Drop the compiled shaders (window resize, hot reload): they are GPU
-- objects on a context that may not exist any more.
function Water.invalidate()
  for k, sh in pairs(shaders) do
    if sh and sh.release then pcall(sh.release, sh) end
    shaders[k] = nil
  end
  active = nil
end

return Water
