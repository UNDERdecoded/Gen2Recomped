-- Voxel world mode: what the engine's PERFORMANCE tier costs THIS mod.
--
-- The engine already owns a tier -- src/core/Performance.lua, one OPTIONS
-- row, four tiers (auto / high / balanced / low), resolved live by
-- Game:applyOptions -- and every one of the four things it scales
-- (`tilt`, `gbcfx`, `survey`, `fpsMax`) is a Game-Boy-era 2D extra. Two of
-- them this mod takes away outright: `pinEngineFx` in main.lua holds TILT
-- and GBC FX at zero and drops both rows for as long as the mod is
-- installed, deliberately (TILT is the flat fake of what this mode does for
-- real, GBC FX is a full-screen present pass over the diorama). So on a
-- machine running this mod the engine's tier moves the survey zoom and the
-- FPS ceiling and NOTHING ELSE -- which is exactly the complaint: the
-- OPTIONS row says PERFORMANCE and the diorama costs the same at every rung
-- of it.
--
-- This is where the tier reaches the diorama. It does not own a setting of
-- its own and it never writes one: it READS the engine's resolved tier and
-- hands back a table of ceilings, and each module clamps its own live level
-- against its own field at the one function every reader already goes
-- through (ShadowMap.available, Water.level, AntiAlias.samples). That shape
-- was chosen over a switch statement in the renderer for one reason: a
-- ceiling that is `nil` clamps nothing, so HIGH takes the SAME code path it
-- always did, arrives at the same number, and draws the same pixels. The
-- tier cannot regress the look it is not lowering.
--
-- WHAT IS CAPPED, AND WHY THOSE THREE. Measured on this box with the mod's
-- own instrumentation (lib/Perf.lua, DS_PERF=1) standing in Petalburg Woods
-- with the terrain built and nothing left to mesh:
--
--   ShadowMap.draw   53% of VoxelScene.render
--   Voxel3D.draw     46%
--   everything else  under 1% together
--
-- The sun is HALF the frame, and it is half the frame because it redraws
-- the entire terrain mesh from the light EVERY frame -- 202 sun passes in
-- 202 rendered frames. Nothing about the terrain moved; what moved was an
-- NPC's walk phase, and `shadowSignature` rightly says the map is stale the
-- moment any caster does. So the two levers here are the sun's RESOLUTION
-- and the sun's RATE, and the third is the water's reflective march, which
-- is fill rate rather than geometry and only bites on a map with a lake in
-- it.
--
-- WHAT IS DELIBERATELY NOT CAPPED is in NOTES.md under g3-throttle-283: the
-- border ring's depth, the neighbour maps, and the round-tree hull
-- resolution -- which is 99.5% of a forest map's quads and the single
-- biggest number in the whole mode, and is refused here because it is baked
-- into the mesh and a tier that re-bakes on a menu keypress is a tier that
-- hitches for four seconds when you touch it.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Tier = {}

-- The engine's module, or nil under a headless tool that has no `src` on
-- the path. Cached: `caps()` is read once per pass per frame and a pcall'd
-- require per read would be the most expensive thing in this file.
local Performance = nil
local triedRequire = false
local function engineTier()
  if not triedRequire then
    triedRequire = true
    local ok, m = pcall(require, "src.core.Performance")
    Performance = (ok and type(m) == "table") and m or nil
  end
  -- `Performance.tier` is the RESOLVED tier and never "auto": the engine
  -- writes it in Performance.applyOptions, which Game:applyOptions calls on
  -- boot and again on every keypress of the row. A host without the module
  -- -- the offline mesh tools, the relief harness -- answers HIGH, which is
  -- the no-clamp path, so no tool's numbers can move because this exists.
  local t = Performance and Performance.tier
  if t == "balanced" or t == "low" then return t end
  return "high"
end

-- ------- the ceilings
--
-- A field left nil is NOT CAPPED, and every field is nil at HIGH. Read the
-- table as "the most this tier will allow", never as "what this tier sets":
-- a player on BALANCED who has already turned WATER off keeps it off.
--
--   shadows    false takes the sun pass away entirely and VoxelScene falls
--              back to the flat decal shadows it already keeps for a driver
--              that cannot make the canvas -- so LOW is not a mode with no
--              shadows, it is the mode the port shipped before the sun pass
--              existed. Measured saving: the whole 53%.
--   shadowRes  the top rung of ShadowMap.SIZES this tier will allocate.
--              1024 is a quarter of 2048's texels and a quarter of its fill
--              on every sun pass; the cost is a softer shadow edge, which
--              on a diorama read at this zoom is most of one display pixel.
--   shadowHz   the sun redraws at most once every N frames WHILE ONLY THE
--              CAST HAS MOVED. A camera move, a zoom, a map arriving, the
--              clock turning the sun -- all of those still redraw on the
--              frame they happen, because a shadow map fitted to the wrong
--              frustum is not a late shadow, it is a wrong one. What is
--              delayed is strictly "somebody took a step", where the error
--              is at most three frames of a walker's own shadow lagging
--              their feet by a pixel or two.
--   water      the top rung of Water.level(): 2 FULL (the screen-space
--              march that samples the depth texture twenty-odd times per
--              water pixel), 1 SKY (the sun, the moon and the sky alone),
--              0 OFF. Geometry is untouched at every rung -- the water
--              surface is the same mesh -- so this is pure fill rate, and
--              it buys nothing at all on a map with no water on it.
--   waterCast  the top rung of Water.castLevel(): 1 paints the CAST into
--              the reflection copy so people, Pokemon and the player show
--              up in the water, 0 leaves them out. The only part of the
--              water that costs DRAW CALLS rather than fill rate -- every
--              card on screen a second time, which in Lilycove is a hundred
--              and thirty-odd -- so it is capped separately from `water`,
--              which is pure fill.
--
--              It is redundant against the row above it at both capped
--              tiers and is written anyway. BALANCED and LOW already hold
--              `water` at or below SKY, and Water.castLevel answers 0 on
--              its own wherever there is no march for the mirror to feed --
--              so this ceiling never fires today. It exists because "the
--              crowd is not drawn twice at BALANCED" is a fact about what
--              this tier can afford, not a side effect of what the WATER
--              ceiling happens to be, and a ceiling that is only true by
--              consequence is one change away from quietly not being true.
--   aa         the top rung of AntiAlias.samples(). The row's own help
--              already calls it "the most expensive row in the mod": 2X is
--              half again as many pixels in each direction and 4X twice, on
--              every pass in the frame including the sun's.
--   waterPlanar the top rung of Water.planarLevel(): 1 renders the whole
--              scene a SECOND time, mirrored in the water plane, so that
--              people standing beside a lake are in it -- which the
--              screen-space march provably cannot do (0 of ~100,000 water
--              pixels for a figure on Route 104's bridge deck, DERIVED).
--              The most expensive thing this mod can be asked for: it is not
--              fill rate OR draw calls, it is the frame again -- every
--              terrain mesh, the grass, the flowers and every card, into a
--              full-size colour canvas with its own depth buffer.
--
--              UNLIKE `waterCast` THIS CEILING IS NOT REDUNDANT. That one
--              only ever repeats what the `water` ceiling already said; this
--              one is an independent fact. A tier that can afford the march
--              -- twenty-odd texture reads on the water's own pixels -- may
--              still be nowhere near able to afford the scene twice, and
--              HIGH is exactly such a tier on a laptop. It is nil here
--              anyway, because the row itself is OFF by default (see
--              Water.planarLevel): what a tier must never do is turn a
--              player's OWN choice on, and a ceiling cannot.
local CAPS = {
  high     = { shadows = true,  shadowRes = nil,  shadowHz = nil,
               waterRaySteps = 12, waterRayRefine = 3,
               water = nil, waterCast = nil, waterPlanar = nil, aa = nil },
  balanced = { shadows = true,  shadowRes = 1024, shadowHz = 3,
               waterRaySteps = 12, waterRayRefine = 3,
               water = 1,   waterCast = 0,   waterPlanar = 0,   aa = 2 },
  low      = { shadows = false, shadowRes = 1024, shadowHz = 0,
               waterRaySteps = 12, waterRayRefine = 3,
               water = 0,   waterCast = 0,   waterPlanar = 0,   aa = 0 },
}

-- Bumped whenever the resolved tier changes. Nothing in the mod needs to
-- invalidate a GPU object over it -- every clamp below is read live, and
-- the sun's own staleness test redraws the map on the first frame after a
-- tier goes back up -- but a reader that wants to know is better served by
-- a counter than by comparing strings.
Tier.rev = 0
Tier.name = "high"

-- The ceilings in force. Call it; do not cache it. It is a table index off
-- a field read, it is called a handful of times per frame, and caching it
-- is how a row stops taking effect until the map is reloaded.
function Tier.caps()
  local t = engineTier()
  if t ~= Tier.name then
    Tier.name = t
    Tier.rev = Tier.rev + 1
  end
  return CAPS[t] or CAPS.high
end

-- `value` clamped to this tier's ceiling for `field`; unchanged where the
-- tier names no ceiling, which is every field at HIGH.
function Tier.clamp(field, value)
  local cap = Tier.caps()[field]
  if cap == nil or type(cap) ~= "number" then return value end
  if type(value) ~= "number" then return value end
  return (value > cap) and cap or value
end

return Tier
