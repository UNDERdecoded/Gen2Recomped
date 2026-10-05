-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) PARTICLE SYSTEM -- the thing that finally throws the
-- picture.
--
-- Everything upstream of this is reading: `Gen4MoveAnim` decodes the program
-- that says `loadparticlesystem 0, 40`, and `Gen4Particle` reads what is at
-- index 40 -- its textures and its emitters' fields. This is the other kind of
-- work: a per-frame simulation that spawns particles, moves them and draws
-- them. Nothing here is decoded from the cartridge, because there is nothing
-- left to decode; it is the cartridge's own arithmetic, re-implemented.
--
-- AND THE ARITHMETIC IS PRET'S, NOT INVENTED. `lib/spl/src/spl_emitter.c` and
-- `spl_emit.c` are the Nitro particle library decompiled, and the three
-- formulas that matter are copied from them rather than reasoned out:
--
--   * AIR RESISTANCE is `velocity * (airResistance + 384) / 512` every frame.
--     That constant is `FX32_CONST(0.09375)`, which makes 128 the NEUTRAL
--     value -- (128 + 384) / 512 is exactly 1. Reading the field as a straight
--     0-255 damping factor would make every particle in the game slow down.
--   * A PARTICLE'S VELOCITY at birth is `normalize(spawnOffset) * magPos +
--     axis * magAxis`, so an emitter that spawns at a POINT has no direction
--     to normalise and the library substitutes a random unit vector. Without
--     that special case a point emitter emits nothing that moves.
--   * A LIFETIME IS ALWAYS AT LEAST ONE FRAME (`... + 1` in spl_emit.c), which
--     is the difference between a particle that flashes and one that never
--     draws at all.
--
-- WHAT IS DELIBERATELY NOT HERE: the behaviour blocks -- gravity, magnet,
-- spin, convergence, collision plane. `Gen4Particle` reports which ones an
-- emitter carries and this applies none of them, so a particle here flies
-- straight where the cartridge would curve it. That is a NAMED gap, reported
-- per system in `missing`, not a silent approximation.
--
-- AND THE THIRD DIMENSION IS FLATTENED. Platinum renders these through the
-- DS's 3D unit; this port draws a 2D battle. x and y are used as screen
-- offsets and z only orders the draw, which is the honest reduction rather
-- than a claim that the two look identical.

local Gen4Particle = require("src.import.Gen4Particle")

local Gen4ParticleSystem = {}
local System = {}
System.__index = System

local floor, sqrt, max, min = math.floor, math.sqrt, math.max, math.min

-- THE RESOURCE FLAG BITS, from `SPLResourceFlags` in spl_resource.h. Only the
-- ones this file reads are named; the block selectors live in Gen4Particle.
local FLAG_HAS_ROTATION = 12
local FLAG_RANDOM_INIT_ANGLE = 13
local FLAG_RANDOMIZE_LOOPED_ANIM = 20
local FLAG_DRAW_CHILDREN_FIRST = 21
local FLAG_HIDE_PARENT = 22

-- DECLARED ABOVE EVERY USE. A file-local called from a line above its own
-- `local` resolves as a GLOBAL, comes back nil and raises -- which is what
-- `tools/lua_use_before_local.py` exists for, and what cost this port two real
-- bugs already.
local function bitOf(word, bit)
  return floor((tonumber(word) or 0) / 2 ^ bit) % 2 == 1
end

-- THE DRAWN COLOUR IS THE PARTICLE'S TIMES THE EMITTER'S.
--
-- `spl_draw.c` ends every draw path with
--     G3_Color(GX_RGB(ptclR * emtrR >> 5, ptclG * emtrG >> 15,
--                     ptclB * emtrB >> 25))
-- and because `GX_RGB_G_` and `GX_RGB_B_` mask without shifting down, all three
-- of those reduce to the same thing: a 5-bit modulate, `particle * emitter / 32`.
--
-- !! THIS WAS THE BIGGEST REMAINING VISUAL GAP AND IT IS PURE DATA. 1,160 of the
-- cartridge's 1,468 emitters carry a NON-WHITE colour -- effect 0's is orange
-- (255, 98, 0), effect 2's is blue (0, 148, 255) -- and a particle is BORN with
-- its emitter's colour (`ptcl->color = header->color` in spl_emit.c) whether or
-- not a colour animation ever runs. Drawing them white made four fifths of the
-- game's particles grey blobs.
local function modulate(a, b)
  if not a then return b end
  if not b then return a end
  return {
    floor((a[1] or 0) * (b[1] or 0) / 255),
    floor((a[2] or 0) * (b[2] or 0) / 255),
    floor((a[3] or 0) * (b[3] or 0) / 255),
  }
end

local function mixColour(from, to, k)
  if not (from and to) then return to or from end
  if k < 0 then k = 0 elseif k > 1 then k = 1 end
  return {
    floor((from[1] or 0) + ((to[1] or 0) - (from[1] or 0)) * k),
    floor((from[2] or 0) + ((to[2] or 0) - (from[2] or 0)) * k),
    floor((from[3] or 0) + ((to[3] or 0) - (from[3] or 0)) * k),
  }
end

-- The library's own neutral point for air resistance: FX32_CONST(0.09375).
Gen4ParticleSystem.AIR_BIAS = 384
Gen4ParticleSystem.AIR_SCALE = 512

-- THE POOL IS TWO HUNDRED PARTICLES, AND THAT IS A HARD LIMIT, NOT A HINT.
--
-- `include/particle_system.h` states three: MAX_PARTICLE_SYSTEMS 16,
-- MAX_EMITTERS 20, MAX_PARTICLES 200. The first two corroborate the script
-- macros' own operand ranges -- "particleSystem (0-15)" and "emitterIndex
-- (0-19)" -- which is a pleasant way to find out a header is the same header.
--
-- The third changes what is on the screen. `SPLEmitter_EmitParticles` and
-- `SPLEmitter_EmitChildren` both take their particle off a FIXED FREE LIST and
-- `return` the moment it comes back NULL, so a burst that asks for more than the
-- pool holds simply stops getting them. Without the cap this port peaked at 302
-- of an emitter's own particles and 1,260 children -- a spray seven times denser
-- than the DS can draw, which is the kind of wrong that looks like enthusiasm.
--
-- THE REDUCTION, NAMED: the cartridge's pool belongs to a PARTICLE SYSTEM -- one
-- loaded SPA slot -- and is shared by every emitter created from it. Here it is
-- per `System`, which is one resource's emitters. For a move that creates one
-- emitter per slot the two are the same thing; for one that creates several from
-- a single slot this port is more generous than the DS.
Gen4ParticleSystem.MAX_PARTICLES = 200
Gen4ParticleSystem.MAX_EMITTERS = 20
Gen4ParticleSystem.MAX_SYSTEMS = 16

-- WHICH AXES A SCALE ANIMATION TOUCHES, from SPLScaleAnimDir. `spl_draw.c` sets
-- `sclY = baseScale` and `sclX = baseScale * aspectRatio`, then multiplies the
-- animation into one axis, the other, or both. Measured over the cartridge: 1,293
-- emitters animate both, 41 only X, 134 only Y -- and never a fourth value, which
-- is what a wrong bit offset in a 3-bit field would have produced.
-- `textureS = FX32_ONE << textureTileCountS`, and the field is two bits, so the
-- repeat is one of four powers of two. Spelled out rather than computed for the
-- reason in the spawn comment.
Gen4ParticleSystem.REPEATS = { [0] = 1, 2, 4, 8 }

Gen4ParticleSystem.SCALE_DIR_XY = 0
Gen4ParticleSystem.SCALE_DIR_X = 1
Gen4ParticleSystem.SCALE_DIR_Y = 2

-- A PARTICLE IS NOT SQUARE. `aspectRatio` runs from 0.0298 to 7.9998 across the
-- cartridge and 445 of the 1,468 emitters set it to something other than 1, so
-- drawing one scale on both axes squashes or stretches a third of the game's
-- particles. It multiplies X only.
local function scaleOf(p)
  local base = p.baseScale or 0
  local anim = p.animScale or 1
  local sx = base * (p.aspect or 1)
  local sy = base
  local dir = p.scaleDir or 0
  if dir == Gen4ParticleSystem.SCALE_DIR_X then
    sx = sx * anim
  elseif dir == Gen4ParticleSystem.SCALE_DIR_Y then
    sy = sy * anim
  else
    sx, sy = sx * anim, sy * anim
  end
  return sx, sy
end

-- A particle's world units are fixed point; this is how many screen pixels one
-- unit is worth. NOT from the cartridge -- Platinum's are 3D world units under
-- a perspective camera, and there is no exchange rate to read. Named as a
-- port-side constant so it is obvious it is a choice, and set from the one
-- thing that can be measured: Scratch's claw is a 64-pixel texture at
-- baseScale 0.83 and has to land on a Pokemon about that size.
Gen4ParticleSystem.UNITS_TO_PIXELS = 32

-- WHERE THE EMITTER IS, IN PIXELS, RELATIVE TO ITS ORIGIN.
--
-- Normally nothing: the emitter sits at whatever its callback's origin resolves
-- to and every particle is drawn as an offset from that one point. Three script
-- functions MOVE an emitter instead -- `MoveEmitterA2BLinear`,
-- `MoveEmitterA2BParabolic` and `RevolveEmitter` call `SPLEmitter_SetPosX/Y`
-- every frame -- and the player drives `self.emitterX` / `self.emitterY` to say
-- so.
--
-- !! AND THE POSITION HAS TO BE REMEMBERED PER PARTICLE, NOT PER SYSTEM. A
-- particle that has left the emitter does not follow it: it was born at a point
-- and flies from there. Adding the emitter's CURRENT position at draw time would
-- drag the whole burst along behind it -- a moving picture of an emitter rather
-- than a moving emitter -- and that difference is the entire visible effect of a
-- travelling projectile. So `spawn` copies the position onto the particle and the
-- draw reads the particle's copy.

-- Emission shapes, from SPLEmissionType. Only the ones that occur are given
-- their own arm; the rest fall back to a point, which is the shape that cannot
-- put a particle in the wrong place.
Gen4ParticleSystem.EMISSION = {
  POINT = 0, SPHERE_SURFACE = 1, CIRCLE_BORDER = 2, CIRCLE_BORDER_UNIFORM = 3,
  SPHERE = 4, CIRCLE = 5, CYLINDER_SURFACE = 6, CYLINDER = 7,
  HEMISPHERE_SURFACE = 8, HEMISPHERE = 9,
}

-- A SEEDED GENERATOR, because a battle that replays the same move must look the
-- same twice and because a check cannot assert anything about a system driven
-- by a real die.
-- MULTIPLIED IN TWO HALVES, because the game runs on LuaJIT and a LuaJIT
-- number is a double. `state * 1103515245` reaches 2.4e18 -- past 2^53 -- and
-- silently drops its low bits there, while Lua 5.3 (`texlua`, which the checks
-- were written on) multiplies integers exactly. So the game and the check ran
-- two different random streams: `gen4_particle_check` measured the corpus at
-- 17,829 units under texlua and 17,910 under LuaJIT, and 34 target crossings
-- against 28. The same split `Gen4MoveAnimPlayer.lcrngNext` already uses:
-- `state * lo` stays under 2^47, and only `hi`'s product modulo 2^15 can reach
-- bits below 2^31, so every term is exact on both interpreters.
local MUL_HI, MUL_LO = 16838, 20077   -- 1103515245 = 16838 * 65536 + 20077
local function nextRandom(state)
  local lo = state * MUL_LO
  local hi = (state * MUL_HI) % 32768
  state = (lo + hi * 65536 + 12345) % 2147483648
  return state, state / 2147483648
end

-- TWO WAYS IN, ONE SIMULATION.
--
-- `new` takes the raw SPA bytes and is what a check or a tool holding the
-- cartridge uses. `fromEmitters` takes the emitter list the `gen4_particles`
-- stage put in the cache and is what the RUNNING GAME uses, because the running
-- game never opens the ROM. They must not be two implementations: everything
-- below the constructor is shared, so a simulation proved through one route is
-- the same simulation on the other, and the wiring check asserts the two agree
-- frame for frame rather than trusting that sentence.
function Gen4ParticleSystem.fromEmitters(emitters, textures, head)
  -- AN EMPTY EMITTER LIST IS A VALID SYSTEM, and refusing one cost 34 effects
  -- their system on the first run of this: the cartridge really does ship 34
  -- particle files with no emitter in them, they legitimately throw nothing,
  -- and the check counts them apart from the ones that are silent by mistake.
  -- `#emitters == 0` in this guard turned all 34 into build failures.
  if type(emitters) ~= "table" then return nil end
  local self = setmetatable({}, System)
  self.textures = textures
  self.emitters = emitters
  self.header = head
  -- ALL ELEVEN BLOCKS ARE APPLIED NOW, so this list is EMPTY -- and it stays
  -- here, empty, rather than being deleted. A missing-features list that gets
  -- removed the day it empties is one nobody notices the next time something is
  -- left out, and the check asserts it is empty rather than assuming it.
  --
  -- It was eight of eleven, then one (the child resource), then none.
  --
  -- WHAT IS LEFT IS NOT BLOCKS BUT DRAW MODES -- flag fields, named in
  -- `DRAW_GAPS` below with the reason each one cannot be honoured by a flat 2D
  -- blit. APPLIED is also not the same as DRAWN: the rotation, the two scales and
  -- the colour are computed per particle and handed to the draw callback, so
  -- whether they reach the screen is the caller's business.
  Gen4ParticleSystem.NOT_APPLIED = Gen4ParticleSystem.NOT_APPLIED or {}
  self.missing = {}
  for _, e in ipairs(emitters) do
    -- A CACHED EMITTER MAY HAVE LOST ITS `blocks` SET and still be usable: that
    -- set only says which selectors were on, and `parsed` carries the contents.
    for bit in pairs(e.blocks or {}) do
      local name = Gen4Particle.EMITTER_BLOCK_NAMES[bit]
      if name and Gen4ParticleSystem.NOT_APPLIED[name] then
        self.missing[name] = (self.missing[name] or 0) + 1
      end
    end
  end
  return self
end

-- ONE RESOURCE OUT OF A LOADED SET.
--
-- `loadparticlesystem <slot> <member>` loads a whole SPA file; the emitter
-- commands that follow name a RESOURCE inside it -- pret's macro comment is
-- exact: "resourceID: The resource ID inside the particle resource to use".
-- So the running game almost never simulates a whole file at once, and a system
-- built for a battle holds the one resource the program asked for. The ids are
-- 0-based in the script and the emitter list is 1-based, which is the only
-- arithmetic here and the easiest thing in the file to get wrong.
function Gen4ParticleSystem.resource(emitters, id)
  if type(emitters) ~= "table" then return nil end
  local one = emitters[(tonumber(id) or 0) + 1]
  if not one then return nil end
  return Gen4ParticleSystem.fromEmitters({ one })
end

function Gen4ParticleSystem.new(file)
  local textures, head = Gen4Particle.textures(file)
  local emitters = textures and Gen4Particle.emitters(file)
  if not (textures and emitters) then return nil end
  return Gen4ParticleSystem.fromEmitters(emitters, textures, head)
end

-- start(seed) -> the system, ready to step
function System:start(seed)
  self.rng = (tonumber(seed) or 1) % 2147483648
  if self.rng == 0 then self.rng = 1 end
  self.frame = 0
  -- TWO LISTS, AND `live` COUNTS ONLY THE FIRST.
  --
  -- `particles` are the emitter's own; `children` are the ones those particles
  -- emit. They are kept apart because the cartridge keeps them apart -- separate
  -- lists, separate lifetimes, separate animation functions, an optional
  -- separate draw order -- and because every corpus floor in the check was
  -- measured against the emitter's own particles. Folding children into `live`
  -- would move those numbers for a reason that has nothing to do with what they
  -- measure.
  self.particles = {}
  self.children = {}
  self.live = 0
  self.liveChildren = 0
  -- HOW OFTEN THE POOL RAN DRY. Counted rather than ignored: it is the difference
  -- between "this effect is dense" and "this effect is denser than the hardware,
  -- and the extra was thrown away".
  self.starved = 0
  -- THE FRACTIONAL CARRY BELONGS TO THE RUN, NOT TO THE EMITTER, and it was on
  -- the emitter table until the player started instantiating single resources
  -- out of a shared set. Two emitters of the same resource alive at once -- both
  -- halves of a two-sided move, say -- then share one carry, and each one's
  -- remainder cancels the other's. Keyed by index on the system instead, so the
  -- resource tables the cache handed over are never written to at all.
  self.carry = {}
  for k = 1, #self.emitters do self.carry[k] = 0 end
  return self
end

function System:random()
  local v
  self.rng, v = nextRandom(self.rng)
  return v
end

-- SPLRandom_ScaledRangeFX32 scales a value DOWN by up to `attenuation/255`;
-- DoubleScaledRange does the same about the value's own midpoint. Both are
-- randomisation that only ever shrinks, which is why a particle is never
-- faster or longer-lived than its emitter says.
-- THE TWO RANDOMISATION MACROS, AND THEY ARE NOT INTERCHANGEABLE.
--
-- `spl_random.h` defines both, and `spl_emit.c` picks between them per field:
--   ScaledRangeFX32(num, range)       = (num * (255 - ((range * r8) >> 8))) >> 8
--   DoubleScaledRangeFX32(num, range) = (num * (255 + range - ((range * r8) >> 7))) >> 8
-- The first ONLY REDUCES. The second is centred and can reach nearly TWICE num.
-- LIFETIME uses the first; BASE SCALE AND BOTH INITIAL VELOCITIES use the
-- second -- and this file used one hand-written "reduce by a random fraction"
-- for all three, so every particle with a non-zero scale or velocity
-- attenuation was systematically too small and too slow. 
--
-- Note the 255/256 in both: even with range 0 the value comes back very
-- slightly under itself. That is the cartridge's arithmetic, not a rounding
-- slip, and it is kept rather than tidied.
function System:rand8()
  return floor(self:random() * 256) % 256
end

function System:scaledRange(value, range)
  value = value or 0
  range = range or 0
  return value * (255 - floor(range * self:rand8() / 256)) / 256
end

function System:doubleScaledRange(value, range)
  value = value or 0
  range = range or 0
  return value * (255 + range - floor(range * self:rand8() / 128)) / 256
end

-- SPLRandom_BetweenFX32(min, max): a value in [min, max) where both ends are
-- INTEGERS scaled into fx32. Used for the angular velocity, whose ends are the
-- header's minRotation/maxRotation in index units.
function System:between(low, high)
  low = low or 0
  high = high or 0
  return low + (high - low) * self:random()
end

-- A random unit vector, for the point-emitter case the library special-cases.
function System:randomUnit()
  local x, y, z = self:random() * 2 - 1, self:random() * 2 - 1, self:random() * 2 - 1
  local n = sqrt(x * x + y * y + z * z)
  if n < 1e-6 then return 0, 1, 0 end
  return x / n, y / n, z / n
end

-- Where in the emitter's shape a particle is born, in world units.
function System:spawnOffset(f)
  local E = Gen4ParticleSystem.EMISSION
  local kind = (f.flags or 0) % 16
  local r = f.radius or 0
  if kind == E.POINT then return 0, 0, 0 end
  if kind == E.SPHERE_SURFACE or kind == E.HEMISPHERE_SURFACE then
    local x, y, z = self:randomUnit()
    if kind == E.HEMISPHERE_SURFACE then y = math.abs(y) end
    return x * r, y * r, z * r
  end
  if kind == E.SPHERE or kind == E.HEMISPHERE then
    local x, y, z = self:randomUnit()
    local d = r * self:random()
    if kind == E.HEMISPHERE then y = math.abs(y) end
    return x * d, y * d, z * d
  end
  if kind == E.CIRCLE_BORDER or kind == E.CIRCLE_BORDER_UNIFORM
     or kind == E.CIRCLE then
    local a = self:random() * 2 * math.pi
    local d = (kind == E.CIRCLE) and (r * self:random()) or r
    return math.cos(a) * d, math.sin(a) * d, 0
  end
  -- the two cylinders
  local a = self:random() * 2 * math.pi
  local d = (kind == E.CYLINDER) and (r * self:random()) or r
  local len = (f.length or 0) * (self:random() - 0.5)
  return math.cos(a) * d, math.sin(a) * d, len
end

-- The per-frame velocity multiplier, in ONE place so that a check can measure
-- the same arithmetic the simulation runs rather than a copy of it. Every
-- emitter byte in the cartridge lands this at 1.0 or below, so particles only
-- ever slow down; a wrong shift here turns the whole game's particles into
-- runaways and nothing downstream would notice, because every other measure of
-- a particle is a lower bound.
function Gen4ParticleSystem.airMultiplier(f)
  return ((f and f.airResistance or 0) + Gen4ParticleSystem.AIR_BIAS)
         / Gen4ParticleSystem.AIR_SCALE
end

-- WHAT A FLAT 2D BLIT CANNOT DO, with the reason beside each -- the same
-- discipline as `Gen4MoveAnimPlayer.NOT_NEEDED`: a skip that is argued is a skip
-- somebody can disagree with, and a skip that is silent is a bug waiting.
Gen4ParticleSystem.DRAW_GAPS = {
  drawType = "billboard vs directional-billboard vs polygon needs a 3D pass; "
             .. "everything here is drawn as a flat billboard",
  useViewSpace = "there is no view matrix to be in",
  -- THESE THREE SAID "same" UNTIL THE CHECK REFUSED THEM. It requires every
  -- reason to be a sentence, and "same" is a cross-reference pretending to be
  -- one -- which is exactly the shape of an unargued skip.
  polygonRotAxis = "which axis a polygon particle spins about, and nothing here "
                   .. "draws a polygon particle",
  polygonReferencePlane = "which plane a polygon particle is built in, for the "
                          .. "same absent polygon",
  dpolFaceEmitter = "turns a directional polygon to face its emitter; there is "
                    .. "no directional polygon to turn",
  -- textureTileCount WAS HERE AND IS NOT ANY MORE: `textureS = FX32_ONE <<
  -- textureTileCountS` is a power-of-two repeat across the quad, the draw
  -- callback carries both counts, and 647 emitters get their tiling.
  flipTexture = "no emitter in the cartridge sets either flip, so this is "
                .. "unreachable rather than unimplemented",
  fixedPolygonID = "polygon ids order the DS's own depth buffer; this port "
                   .. "sorts by z instead",
  dbbScale = "the directional-billboard scale, which needs the directional "
             .. "draw type first",
}

-- THE FREE LIST, AS A NUMBER. `SPLList_PopFront` returning NULL is what stops
-- the cartridge emitting; asking here whether the pool has room is the same
-- question with the list left out.
function System:hasRoom()
  return self:total() < Gen4ParticleSystem.MAX_PARTICLES
end

function System:spawn(emitter)
  if not self:hasRoom() then
    self.starved = (self.starved or 0) + 1
    return
  end
  local f = emitter.fields
  if not f then return end
  local ox, oy, oz = self:spawnOffset(f)
  -- normalize(offset), or a random direction when the emitter is a point --
  -- the library's own special case, and without it a point emitter is still.
  local n = sqrt(ox * ox + oy * oy + oz * oz)
  local nx, ny, nz
  if n < 1e-6 then nx, ny, nz = self:randomUnit()
  else nx, ny, nz = ox / n, oy / n, oz / n end
  local magPos = self:doubleScaledRange(f.initVelPos,
                                        f.randomAttenuation.initVel)
  local magAxis = self:doubleScaledRange(f.initVelAxis,
                                         f.randomAttenuation.initVel)
  local ax, ay, az = f.axis[1] or 0, f.axis[2] or 0, f.axis[3] or 0
  -- WHICH COLOUR THIS PARTICLE IS BORN WITH. Normally the emitter's; with
  -- `randomStartColor` set, one of {curve start, emitter, curve end} chosen by the
  -- particle's index, which is why the colour ANIMATION is skipped entirely for
  -- those emitters -- pret drops it from the animation list in the same breath.
  local startColour = f.colour
  local colourAnim = emitter.parsed and emitter.parsed.colorAnim
  if colourAnim and colourAnim.randomStartColor then
    local three = { colourAnim.start, f.colour, colourAnim.finish }
    startColour = three[(#self.particles % 3) + 1] or f.colour
  end
  -- "Life is always at least 1 frame" -- pret's own comment beside the + 1.
  local life = floor(self:scaledRange(f.particleLifeTime,
                                      f.randomAttenuation.lifeTime)) + 1
  -- THE BASE SCALE IS DRAWN ONCE. Writing `doubleScaledRange(...)` into three
  -- fields of the same particle drew three DIFFERENT random values for one
  -- scale -- and, worse, consumed two extra numbers from a seeded stream, which
  -- moved every later particle in the run. The corpus travel and the magnet
  -- crossing count both shifted, and neither had anything to do with scale. One
  -- draw, three fields.
  local born = self:doubleScaledRange(f.baseScale,
                                      f.randomAttenuation.baseScale)
  self.particles[#self.particles + 1] = {
    x = (f.basePos[1] or 0) + ox,
    y = (f.basePos[2] or 0) + oy,
    z = (f.basePos[3] or 0) + oz,
    -- WHERE THE EMITTER WAS WHEN THIS PARTICLE WAS BORN. Zero unless something is
    -- moving the emitter; see the note beside UNITS_TO_PIXELS for why it is stored
    -- here rather than read at draw time.
    bx = self.emitterX or 0, by = self.emitterY or 0,
    vx = nx * magPos + ax * magAxis,
    vy = ny * magPos + ay * magAxis,
    vz = nz * magPos + az * magAxis,
    age = 0,
    life = life,
    -- THE SCALE AND THE ALPHA EACH COME IN TWO PARTS, which is how the
    -- animation blocks reach the screen: `baseScale` and `baseAlpha` are set
    -- once at birth, `animScale` and `animAlpha` are rewritten every frame by
    -- the curves, and the drawn values are the products. pret's own defaults
    -- are animScale = 1.0 and animAlpha = 31, so a resource with no animation
    -- draws exactly its base values.
    baseScale = born,
    animScale = 1,
    baseAlpha = f.baseAlpha or 0,
    animAlpha = 31,
    -- ...and the two products, refreshed each frame for the draw path.
    scale = born,
    scaleX = born * (f.aspectRatio or 1),
    scaleY = born,
    alpha = (f.baseAlpha or 0) / 31,
    texture = f.textureIndex or 0,
    air = Gen4ParticleSystem.airMultiplier(f),
    -- ROTATION. `hasRotation` (bit 12) gives the particle an angular velocity
    -- between the header's two rotation bounds; `randomInitAngle` (bit 13)
    -- starts it anywhere instead of at `initAngle`.
    rotation = bitOf(f.flags, FLAG_RANDOM_INIT_ANGLE) and self:random() * 65536
               or (f.initAngle or 0),
    spin = bitOf(f.flags, FLAG_HAS_ROTATION)
           and self:between(f.minRotation or 0, f.maxRotation or 0) or 0,
    -- WHERE THE EMITTER WAS, kept per particle because the collision plane is
    -- measured from it: a particle's position is RELATIVE to its emitter, so
    -- the plane's absolute height only means something with the emitter's own
    -- height beside it.
    emitterY = f.basePos[2] or 0,
    -- BORN WITH THE EMITTER'S COLOUR, which is what `ptcl->color = header->color`
    -- says. `randomStartColor` instead picks one of three -- the curve's two ends
    -- and the emitter's own -- by the particle's index, so the emitter colour is
    -- the middle of that set as well as the default.
    colour = startColour,
    emitterColour = f.colour,
    -- TILE COUNTS. `textureS = FX32_ONE << textureTileCountS`, so the field is a
    -- power-of-two repeat across the quad: 534 emitters tile 2x2, 67 tile 2x1 and
    -- 46 tile 1x2. Passed to the draw callback rather than applied here, because
    -- repeating a texture is the blitter's business.
    -- INTEGERS, NOT `2 ^ n`. In Lua 5.3 `2 ^ 0` is 1.0 and the value travels to
    -- the draw callback as a float -- the same trap the SPA shape word set once,
    -- where a width came out 32.0 and every consumer expecting an integer
    -- quietly took a float. `REPEATS` spells the four values out.
    tileS = Gen4ParticleSystem.REPEATS[f.textureTileCountS or 0] or 1,
    tileT = Gen4ParticleSystem.REPEATS[f.textureTileCountT or 0] or 1,
    -- WHO IS DRAWN, AND IN WHICH ORDER. `hideParent` (bit 22) means only the
    -- children are visible -- a resource whose whole point is the spray, not the
    -- thing spraying -- and `drawChildrenFirst` (bit 21) puts the children
    -- behind. Both are per-emitter, so they ride on the particle rather than on
    -- the system: one system can hold emitters that disagree.
    aspect = f.aspectRatio or 1,
    scaleDir = f.scaleAnimDir or 0,
    hidden = bitOf(f.flags, FLAG_HIDE_PARENT),
    layer = bitOf(f.flags, FLAG_DRAW_CHILDREN_FIRST) and 1 or 0,
    -- WHAT THE ANIMATIONS NEED AND THE PARTICLE MUST CARRY ITSELF. A system can
    -- hold several emitters, so none of this may live on the system: the loop
    -- length, the colour curve's peak (the emitter's own colour) and the
    -- per-particle phase offset that stops every looping particle animating in
    -- lockstep are all read off the emitter ONCE, here.
    blocks = emitter.parsed,
    loopFrames = f.loopFrames,
    peakColour = f.colour,
    offset = bitOf(f.flags, FLAG_RANDOMIZE_LOOPED_ANIM)
             and floor(self:random() * 256) or 0,
  }
  self.live = self.live + 1
end

-- ---------------------------------------------------------------------------
-- THE CHILD RESOURCE -- `SPLEmitter_EmitChildren` in spl_emit.c, and the second
-- half of `SPLEmitter_Update` in spl_emitter.c.
--
-- 821 of the cartridge's emitters carry one: a particle that emits particles of
-- its own. A child inherits its parent's position, a FRACTION of its velocity,
-- a fraction of its CURRENT scale (base times anim, not base alone) and its
-- parent's current alpha as a new base -- so a child of a faded parent starts
-- faded.
--
-- FOUR THINGS ABOUT CHILDREN THAT ARE NOT THE PARENT'S RULES, and every one is
-- easy to write the parent's way by accident:
--   1. THE LIFE RATE IS `(age << 8) / lifeTime` -- age * 256 / lifeTime, the
--      obvious formula. The parent's two stored factors are NOT used, even
--      though the emitter writes them onto the child.
--   2. THE CHILD HAS ITS OWN TWO ANIMATIONS, not the parent's four:
--      `SPLAnim_ChildScale` ramps 1.0 -> endScale over the whole life and
--      `SPLAnim_ChildAlpha` fades 31 -> 0. Neither loops.
--   3. THE BEHAVIOURS ARE OPTIONAL: they apply to children only when the child
--      resource's own `usesBehaviors` flag is set.
--   4. THE SCALE RATIO IS `(scaleRatio + 1) / 64`, not / 256 -- a u8 over 64, so
--      a ratio of 63 means the child is the same size as its parent and the
--      field can also ENLARGE it. Reading it as /256 makes every child four
--      times too small.
-- ---------------------------------------------------------------------------

Gen4ParticleSystem.CHILD_ROT_NONE = 0
Gen4ParticleSystem.CHILD_ROT_ANGLE = 1
Gen4ParticleSystem.CHILD_ROT_ANGLE_AND_VELOCITY = 2

function System:emitChildren(p, child)
  local count = floor(child.emissionCount or 0)
  if count <= 0 then return end
  -- velocityRatio is a u8 over 256.
  local velRatio = (child.velocityRatio or 0) / 256
  local parentScale = (p.baseScale or 0) * (p.animScale or 1)
  for _ = 1, count do
    -- MID-BATCH, not before it: the cartridge pops one particle per child and
    -- returns as soon as the list is empty, so a request for six children with
    -- room for two gets two.
    if not self:hasRoom() then
      self.starved = (self.starved or 0) + 1
      return
    end
    local rotation, spin = 0, 0
    local kind = child.rotationType or 0
    if kind == Gen4ParticleSystem.CHILD_ROT_ANGLE then
      rotation = p.rotation or 0
    elseif kind == Gen4ParticleSystem.CHILD_ROT_ANGLE_AND_VELOCITY then
      rotation, spin = p.rotation or 0, p.spin or 0
    end
    self.children[#self.children + 1] = {
      x = p.x, y = p.y, z = p.z,
      -- A CHILD IS BORN AT ITS PARENT, so it inherits the PARENT'S base rather
      -- than the emitter's current one: by the time a child appears the emitter
      -- may be somewhere else entirely, and the child belongs to the particle it
      -- came from.
      bx = p.bx or 0, by = p.by or 0,
      vx = (p.vx or 0) * velRatio + self:signedRange(child.randomInitVelMag),
      vy = (p.vy or 0) * velRatio + self:signedRange(child.randomInitVelMag),
      vz = (p.vz or 0) * velRatio + self:signedRange(child.randomInitVelMag),
      age = 0,
      life = max(1, child.lifeTime or 1),
      baseScale = parentScale * ((child.scaleRatio or 0) + 1) / 64,
      animScale = 1,
      -- THE PARENT'S CURRENT ALPHA BECOMES THE CHILD'S BASE, by the same
      -- `base * (anim + 1) >> 5` the draw path uses -- so the two are the same
      -- arithmetic in two places by design, not by accident.
      baseAlpha = floor((p.baseAlpha or 0) * ((p.animAlpha or 31) + 1) / 32),
      animAlpha = 31,
      scale = parentScale * ((child.scaleRatio or 0) + 1) / 64,
      scaleX = parentScale * ((child.scaleRatio or 0) + 1) / 64
               * (p.aspect or 1),
      scaleY = parentScale * ((child.scaleRatio or 0) + 1) / 64,
      alpha = (floor((p.baseAlpha or 0) * ((p.animAlpha or 31) + 1) / 32)) / 31,
      texture = child.textureIndex or 0,
      air = p.air,
      rotation = rotation,
      spin = spin,
      emitterY = p.emitterY,
      -- THE OTHER LAYER FROM ITS PARENT'S, whichever that is.
      layer = (p.layer == 0) and 1 or 0,
      -- BOTH COME FROM THE EMITTER'S HEADER, not the child block -- `spl_draw.c`
      -- is one function for parents and children and reads
      -- `emitter->resource->header` for the aspect and the animation direction.
      aspect = p.aspect,
      scaleDir = p.scaleDir,
      colour = child.useChildColour and child.colour or p.colour,
      emitterColour = p.emitterColour,
      tileS = p.tileS,
      tileT = p.tileT,
      -- The child's own blocks: the behaviours only when it asks for them, and
      -- never the parent's four animations.
      blocks = child.usesBehaviors and p.blocks or nil,
      child = child,
    }
    self.liveChildren = self.liveChildren + 1
  end
end

-- WHEN A PARENT EMITS. `emissionDelay` is a FRACTION OF THE PARENT'S LIFETIME as
-- a u8, so the delay in frames is `lifeTime * emissionDelay / 256` -- pret's own
-- comment names the >> 8 as that division. After it passes, every
-- `emissionInterval` frames.
function System:childDue(p, child)
  local delay = (p.life or 1) * (child.emissionDelay or 0) / 256
  local d = (p.age or 0) - delay
  if d < 0 then return false end
  return floor(d) % max(1, child.emissionInterval or 1) == 0
end

-- A CHILD'S LIFE RATE, and it is NOT the parent's arithmetic: pret writes
-- `(ptcl->age << 8) / ptcl->lifeTime` for children and the factor-based version
-- for parents. Two formulas in one file, three lines apart, and they do not agree
-- at every age -- so this is spelled out rather than shared.
function Gen4ParticleSystem.childLifeRate(age, life)
  life = max(1, tonumber(life) or 1)
  -- THE `% 256` IS THE HARDWARE, NOT TIDINESS. pret assigns this into a `u8`, and
  -- `(age << 8) / lifeTime` reaches exactly 256 on the child's LAST frame -- so it
  -- wraps to 0 and the child snaps back to its birth scale and alpha for one
  -- frame before it dies. The parent's formula cannot do this: `floor(65535/L)*L`
  -- never exceeds 65535, so its rate stays inside 0..255 by construction. Two
  -- formulas three lines apart in the same file, and only one of them wraps.
  return floor((tonumber(age) or 0) * 256 / life) % 256
end

function System:animateChild(p)
  local child = p.child
  if not child then return end
  local r = Gen4ParticleSystem.childLifeRate(p.age, p.life)
  if child.hasScaleAnim then
    -- ramps 1.0 at birth to endScale at death
    local endScale = child.endScale or 1
    p.animScale = endScale + ((endScale - 1) * (r - 255)) / 255
  end
  if child.hasAlphaAnim then
    p.animAlpha = ((255 - r) * 31) / 255
  end
end

-- ---------------------------------------------------------------------------
-- THE ANIMATION BLOCKS -- `lib/spl/src/spl_anim.c`, four functions, one each.
--
-- All four are driven by a LIFE RATE on a 0..255 scale rather than by frames,
-- which is what makes one curve fit particles of any lifetime. pret computes it
-- as `(lifeTimeFactor * age) >> 8` with `lifeTimeFactor = 0xFFFF / lifeTime`,
-- and stores it in a u8 -- so a LOOPING animation gets its wrap for free from
-- the truncation, using a loop factor over `loopFrames` instead.
-- ---------------------------------------------------------------------------

-- EXPOSED, so a check can assert the arithmetic itself rather than only its
-- consequences. `255 * age / life` looks like the same thing and is not: at
-- life 6, age 5 pret's version gives 213 and the obvious one gives 212, and a
-- whole-corpus measurement barely notices a difference like that.
function Gen4ParticleSystem.lifeRate(age, life)
  life = max(1, tonumber(life) or 1)
  return floor(floor(65535 / life) * (tonumber(age) or 0) / 256)
end

function Gen4ParticleSystem.loopRate(age, loopFrames, offset)
  local frames = max(1, tonumber(loopFrames) or 1)
  return (floor(tonumber(offset) or 0)
          + floor(floor(65535 / frames) * (tonumber(age) or 0) / 256)) % 256
end

local function lifeRate(p)
  return Gen4ParticleSystem.lifeRate(p.age, p.life)
end

local function loopRate(p, loopFrames)
  return Gen4ParticleSystem.loopRate(p.age, loopFrames, p.offset)
end

-- The three-point curve both the scale and the alpha animations use: rise to
-- `mid` by `inAt`, hold, then fall to `finish` from `outAt`. The two guards are
-- for the degenerate curves the cartridge does contain -- `inAt` of 0 and
-- `outAt` of 255 -- which in C simply never take the dividing branch or divide
-- by zero at exactly r = 255.
local function threePoint(r, startValue, midValue, endValue, curve)
  local inAt = (curve and curve.inAt) or 0
  local outAt = (curve and curve.outAt) or 255
  startValue = startValue or 0
  midValue = midValue or 0
  endValue = endValue or 0
  if r < inAt then
    return startValue + (r * (midValue - startValue)) / inAt
  elseif r < outAt then
    return midValue
  elseif outAt >= 255 then
    return endValue
  end
  return endValue + ((r - 255) * (endValue - midValue)) / (255 - outAt)
end

function System:animate(p, blocks)
  if not blocks then return end

  local scaleAnim = blocks.scaleAnim
  if scaleAnim then
    local r = scaleAnim.loop and loopRate(p, p.loopFrames) or lifeRate(p)
    p.animScale = threePoint(r, scaleAnim.start, scaleAnim.mid,
                             scaleAnim.finish, scaleAnim.curve)
  end

  local alphaAnim = blocks.alphaAnim
  if alphaAnim then
    local r = alphaAnim.loop and loopRate(p, p.loopFrames) or lifeRate(p)
    local value = threePoint(r, alphaAnim.start, alphaAnim.mid,
                             alphaAnim.finish, alphaAnim.curve)
    p.animAlpha = self:scaledRange(value, alphaAnim.randomRange)
  end

  -- THE COLOUR CURVE'S MIDDLE POINT IS THE EMITTER'S OWN COLOUR, not a third
  -- field in the block: `SPLAnim_Color` reads `header->color` for the peak and
  -- the block only carries the two ends. Worth stating because the block looks
  -- self-contained and is not.
  local colourAnim = blocks.colorAnim
  if colourAnim and not colourAnim.randomStartColor then
    local r = colourAnim.loop and loopRate(p, p.loopFrames) or lifeRate(p)
    local c = colourAnim.curve or {}
    local inAt, peakAt, outAt = c.inAt or 0, c.peakAt or 0, c.outAt or 255
    local peak = p.peakColour or colourAnim.start or { 255, 255, 255 }
    if r < inAt then
      p.colour = colourAnim.start
    elseif r < peakAt then
      p.colour = colourAnim.interpolate
        and mixColour(colourAnim.start, peak, (r - inAt) / max(1, peakAt - inAt))
        or peak
    elseif r < outAt then
      p.colour = colourAnim.interpolate
        and mixColour(peak, colourAnim.finish, (r - peakAt) / max(1, outAt - peakAt))
        or colourAnim.finish
    else
      p.colour = colourAnim.finish
    end
  end

  local texAnim = blocks.texAnim
  if texAnim and not texAnim.randomizeInit then
    local r = texAnim.loop and loopRate(p, p.loopFrames) or lifeRate(p)
    for i = 1, (texAnim.frameCount or 0) do
      if r < (texAnim.step or 0) * i then
        p.texture = texAnim.textures[i] or p.texture
        break
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- THE BEHAVIOUR BLOCKS -- `lib/spl/src/spl_behavior.c`, six functions.
--
-- Five of the six contribute to an ACCELERATION that is added to the velocity
-- AFTER air resistance has been applied to it; spin and convergence act on the
-- POSITION directly. That ordering is pret's and it matters: an acceleration
-- applied before the decay would be damped in the same frame it was added.
-- ---------------------------------------------------------------------------

function System:behave(p, blocks, ax, ay, az)
  if not blocks then return ax, ay, az end

  local gravity = blocks.gravity
  if gravity then
    ax = ax + (gravity.x or 0)
    ay = ay + (gravity.y or 0)
    az = az + (gravity.z or 0)
  end

  local rng = blocks.random
  if rng and (p.age or 0) % max(1, rng.interval or 1) == 0 then
    ax = ax + self:signedRange(rng.x)
    ay = ay + self:signedRange(rng.y)
    az = az + self:signedRange(rng.z)
  end

  -- A MAGNET PULLS TOWARDS ITS TARGET AND DAMPS THE VELOCITY WHILE IT DOES:
  -- the term is force * ((target - position) - velocity), so a particle already
  -- moving that way is pulled less. Subtracting the velocity is easy to leave
  -- out and turns a magnet into a spring that overshoots forever.
  local magnet = blocks.magnet
  if magnet then
    local force = magnet.force or 0
    ax = ax + force * (((magnet.x or 0) - p.x) - p.vx)
    ay = ay + force * (((magnet.y or 0) - p.y) - p.vy)
    az = az + force * (((magnet.z or 0) - p.z) - p.vz)
  end

  local spin = blocks.spin
  if spin then
    -- Index units: 0x10000 is a full turn, applied EVERY FRAME.
    local a = (spin.angle or 0) * 2 * math.pi / 65536
    local c, s = math.cos(a), math.sin(a)
    if spin.axis == Gen4Particle.SPIN_AXIS_X then
      p.y, p.z = p.y * c - p.z * s, p.y * s + p.z * c
    elseif spin.axis == Gen4Particle.SPIN_AXIS_Y then
      p.z, p.x = p.z * c - p.x * s, p.z * s + p.x * c
    else
      p.x, p.y = p.x * c - p.y * s, p.x * s + p.y * c
    end
  end

  -- THE PLANE IS ABSOLUTE AND THE PARTICLE IS RELATIVE, which is the whole
  -- reason each particle remembers where its emitter was. Both arms of pret's
  -- test are kept: a plane can be crossed from either side.
  local plane = blocks.collisionPlane
  if plane then
    local y = plane.y or 0
    local ey = p.emitterY or 0
    local crossed = (ey < y and ey + p.y > y) or (ey >= y and ey + p.y < y)
    if crossed then
      p.y = y - ey
      if plane.kind == Gen4Particle.COLLISION_BOUNCE then
        p.vy = -(p.vy * (plane.elasticity or 0))
      else
        p.age = p.life          -- KILL: the cartridge ages it out on the spot
      end
    end
  end

  -- CONVERGENCE MOVES THE PARTICLE, IT DOES NOT ACCELERATE IT. pret's own
  -- comment says so: "similar to SPLMagnetBehavior, but it acts directly on the
  -- particle's position instead of its acceleration".
  local converge = blocks.convergence
  if converge then
    local force = converge.force or 0
    p.x = p.x + force * ((converge.x or 0) - p.x)
    p.y = p.y + force * ((converge.y or 0) - p.y)
    p.z = p.z + force * ((converge.z or 0) - p.z)
  end

  return ax, ay, az
end

-- SPLRandom_RangeFX32(num): uniform in [-num, num).
function System:signedRange(value)
  value = value or 0
  if value == 0 then return 0 end
  return value * (floor(self:random() * 512) % 512 - 256) / 256
end

-- One frame. Returns true while anything is alive or still to be emitted.
function System:update()
  self.frame = self.frame + 1
  local age = self.frame - 1

  for slot, e in ipairs(self.emitters) do
    local f = e.fields
    if f then
      local interval = max(1, f.emissionInterval or 1)
      local started = age >= (f.startDelay or 0)
      local within = (f.emitterLifeTime or 0) == 0
                     or (age - (f.startDelay or 0)) < f.emitterLifeTime
      if started and within and (age - (f.startDelay or 0)) % interval == 0 then
        -- A FRACTIONAL EMISSION COUNT ACCUMULATES; it does not round down.
        --
        -- `emissionCount` is fixed point and is genuinely fractional in the
        -- cartridge, and `spl_emit.c` carries the remainder between beats:
        --     total = emissionCount + carry
        --     spawn floor(total); carry = total - floor(total)
        -- Flooring each beat independently instead makes any emitter under 1.0
        -- emit NOTHING, EVER. Driving all 485 move effects found exactly one:
        -- member 394 emits 0.743 per beat -- about three particles every four
        -- beats -- and produced an empty animation until this carried.
        -- (pret's own header calls this field "doesn't seem to be used"; it is
        -- used, four lines into SPLEmitter_EmitParticles, and 394 is the proof.)
        self.carry[slot] = (self.carry[slot] or 0) + (f.emissionCount or 0)
        local whole = floor(self.carry[slot])
        self.carry[slot] = self.carry[slot] - whole
        for _ = 1, whole do self:spawn(e) end
      end
    end
  end

  -- THE ORDER IS PRET'S, AND IT IS NOT ARBITRARY (SPLEmitter_Update):
  --   animations, then acceleration = 0, then the behaviours, then rotation,
  --   then AIR RESISTANCE ON THE VELOCITY, then the acceleration added, then
  --   the position moved.
  -- An acceleration added before the decay would be damped in the same frame it
  -- was applied, which is a difference a gravity block would show immediately.
  local keep, n = {}, 0
  for _, p in ipairs(self.particles) do
    self:animate(p, p.blocks)
    local ax, ay, az = self:behave(p, p.blocks, 0, 0, 0)
    p.rotation = (p.rotation or 0) + (p.spin or 0)
    p.vx = p.vx * p.air + ax
    p.vy = p.vy * p.air + ay
    p.vz = p.vz * p.air + az
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.z = p.z + p.vz
    -- THE TWO PRODUCTS THE DRAW PATH READS. Refreshed here rather than in
    -- `draw` so a caller that never draws still sees the same numbers a check
    -- would -- and so `animScale` and `animAlpha` have exactly one consumer.
    p.scaleX, p.scaleY = scaleOf(p)
    p.scale = p.scaleY          -- kept: Y is the axis the aspect does not touch
    p.alpha = ((p.baseAlpha or 0) * ((p.animAlpha or 31) + 1) / 32) / 31
    if p.alpha < 0 then p.alpha = 0 elseif p.alpha > 1 then p.alpha = 1 end
    -- CHILDREN ARE EMITTED AFTER THE PARENT HAS MOVED, which is where pret does
    -- it -- so a child starts at its parent's NEW position, not its old one.
    local child = p.blocks and p.blocks.childResource
    if child and self:childDue(p, child) then self:emitChildren(p, child) end
    p.age = p.age + 1
    if p.age <= p.life then n = n + 1; keep[n] = p end
  end
  self.particles = keep
  self.live = n

  -- THE CHILDREN, on their own rules: their own two animations, the behaviours
  -- only if they asked for them, then the same air-resistance-then-acceleration
  -- order the parents use.
  local kidsKept, kids = {}, 0
  for _, p in ipairs(self.children) do
    self:animateChild(p)
    local ax, ay, az = self:behave(p, p.blocks, 0, 0, 0)
    p.rotation = (p.rotation or 0) + (p.spin or 0)
    p.vx = p.vx * p.air + ax
    p.vy = p.vy * p.air + ay
    p.vz = p.vz * p.air + az
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.z = p.z + p.vz
    p.scaleX, p.scaleY = scaleOf(p)
    p.scale = p.scaleY          -- kept: Y is the axis the aspect does not touch
    p.alpha = ((p.baseAlpha or 0) * ((p.animAlpha or 31) + 1) / 32) / 31
    if p.alpha < 0 then p.alpha = 0 elseif p.alpha > 1 then p.alpha = 1 end
    p.age = p.age + 1
    if p.age <= p.life then kids = kids + 1; kidsKept[kids] = p end
  end
  self.children = kidsKept
  self.liveChildren = kids

  local pending = false
  for _, e in ipairs(self.emitters) do
    local f = e.fields
    if f and (f.emitterLifeTime or 0) > 0
       and age < (f.startDelay or 0) + f.emitterLifeTime then
      pending = true
    end
  end
  return n > 0 or kids > 0 or pending
end

-- total() -> how many particles of both kinds are alive.
function System:total()
  return (self.live or 0) + (self.liveChildren or 0)
end

-- draw(originX, originY, drawTexture)
--
-- `drawTexture(index, x, y, scaleX, scaleY, alpha, rotation, colour, tileS,
-- tileT)` is the caller's, so this file needs no graphics library and can be exercised headlessly -- which
-- is the only reason a particle system can have a check at all.
--
-- `rotation` is handed over in RADIANS rather than the cartridge's index units,
-- because every drawing library this could reach takes radians and converting
-- in one place beats converting in each caller. `colour` is nil unless a colour
-- animation gave the particle one, so a caller can leave it alone.
function System:draw(originX, originY, drawTexture)
  if not drawTexture then return 0 end
  local U = Gen4ParticleSystem.UNITS_TO_PIXELS
  -- BOTH LISTS, BY LAYER THEN BY DEPTH. The layer carries `drawChildrenFirst`
  -- and a hidden parent is left out entirely, which is what `hideParent` means:
  -- 821 emitters have children and some of them exist only to spray.
  local order = {}
  for _, p in ipairs(self.particles) do
    if not p.hidden then order[#order + 1] = p end
  end
  for _, p in ipairs(self.children) do order[#order + 1] = p end
  table.sort(order, function(a, b)
    local la, lb = a.layer or 0, b.layer or 0
    if la ~= lb then return la < lb end
    return (a.z or 0) < (b.z or 0)
  end)
  local drawn = 0
  for _, p in ipairs(order) do
    -- THE PARTICLE'S OWN BASE, not the emitter's current one. `by` is in the
    -- screen's frame (+y down) and the particle's own `y` is in the library's
    -- (+y up), which is why one is added and the other subtracted.
    drawTexture(p.texture, (originX or 0) + (p.bx or 0) + p.x * U,
                (originY or 0) + (p.by or 0) - p.y * U, p.scaleX or p.scale,
                p.scaleY or p.scale, p.alpha,
                ((p.rotation or 0) % 65536) * 2 * math.pi / 65536,
                modulate(p.colour, p.emitterColour), p.tileS, p.tileT)
    drawn = drawn + 1
  end
  return drawn
end

Gen4ParticleSystem.System = System
return Gen4ParticleSystem
