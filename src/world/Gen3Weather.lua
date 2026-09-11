-- ---------------------------------------------------------------------------
-- HOENN'S WEATHER, ON THE FIELD.
--
-- Every Gen 3 map header carries a weather byte; 90 maps in Hoenn set one and
-- the region's scripts set several more.  The byte has been read since the map
-- headers went in, and named since the weather stage went in -- and until now
-- the only thing that ever asked for it was the BATTLE, which cares about
-- four of the sixteen.  Standing on Route 113 in the ash, or on the seafloor,
-- or in the fog on Route 120, looked exactly like standing in Littleroot.
--
-- WHAT IS THE CARTRIDGE'S AND WHAT IS NOT, stated plainly because the
-- difference matters when someone comes back to this:
--
--   THE CARTRIDGE'S -- which weathers exist, what they are called, which map
--   gets which, and which of them a battle inherits.  All of that is read out
--   of the dump (constants.gen3WeatherNames, the map header's byte,
--   constants.gen3BattleWeather) and none of it is stated here.
--
--   NOT THE CARTRIDGE'S -- what a raindrop LOOKS like.  Emerald draws its
--   weather with sprite sheets and a palette blend, and neither is extracted
--   yet, so the particles below are this port's own reconstruction: the
--   direction, density and speed of each are chosen to read as the thing the
--   cartridge names, and they are not measurements.  When the sheets are
--   extracted this module is where they land, and the shape of it -- a veil
--   colour plus a list of particles -- is the shape that art fits into.
--
-- Deterministic on purpose.  The particle field is seeded from the weather's
-- own name and advanced by a frame count, so the same weather at the same
-- frame draws the same thing every time -- which is what lets the suite
-- assert that ash falls and sand blows sideways rather than asserting that
-- something was drawn.
-- ---------------------------------------------------------------------------

local Gen3Weather = {}

-- ---------------------------------------------------------------------------
-- what each weather looks like
--
--   veil    {r, g, b, a} laid over the field, or nil
--   count   particles on screen
--   vx, vy  pixels a frame, so a sign is a direction and a zero is stillness
--   size    {w, h} of one particle
--   colour  {r, g, b, a}
--   wrap    "fall" (top to bottom), "rise", "blow" (right to left)
--   flash   frames between lightning, or nil
-- ---------------------------------------------------------------------------
local LOOKS = {
  -- the two that draw nothing.  SUNNY is 51 of the 90 maps that set a
  -- weather at all, and it is the ordinary daylight those maps already have;
  -- painting anything over it would be worse than painting nothing.
  NONE = false,
  SUNNY = false,

  SUNNY_CLOUDS = {
    count = 6, vx = -0.10, vy = 0, size = { 34, 7 }, wrap = "blow",
    colour = { 1, 1, 1, 0.20 },
  },

  RAIN = {
    veil = { 0.10, 0.13, 0.22, 0.20 },
    count = 80, vx = -1.1, vy = 4.4, size = { 1, 7 }, wrap = "fall",
    colour = { 0.72, 0.80, 0.95, 0.55 },
  },
  DOWNPOUR = {
    veil = { 0.08, 0.10, 0.19, 0.30 },
    count = 110, vx = -1.5, vy = 6.0, size = { 1, 10 }, wrap = "fall",
    colour = { 0.72, 0.80, 0.95, 0.62 },
  },
  RAIN_THUNDERSTORM = {
    veil = { 0.06, 0.07, 0.15, 0.36 },
    count = 110, vx = -1.8, vy = 6.4, size = { 1, 11 }, wrap = "fall",
    colour = { 0.75, 0.82, 0.97, 0.65 },
    flash = 220,
  },

  SNOW = {
    veil = { 0.85, 0.90, 1.00, 0.10 },
    count = 85, vx = -0.35, vy = 1.1, size = { 2, 2 }, wrap = "fall",
    colour = { 1, 1, 1, 0.85 },
  },

  -- the ash on Route 113, which is the one weather with a place in it: it
  -- falls straight down and it is the colour of the ash the soot bag fills
  -- with
  VOLCANIC_ASH = {
    veil = { 0.62, 0.60, 0.58, 0.16 },
    count = 110, vx = -0.15, vy = 1.3, size = { 2, 2 }, wrap = "fall",
    colour = { 0.90, 0.88, 0.85, 0.80 },
  },

  SANDSTORM = {
    veil = { 0.80, 0.70, 0.44, 0.22 },
    count = 90, vx = -6.5, vy = 0.5, size = { 9, 1 }, wrap = "blow",
    colour = { 0.94, 0.86, 0.62, 0.55 },
  },

  FOG_HORIZONTAL = {
    veil = { 0.86, 0.88, 0.90, 0.30 },
    count = 14, vx = -0.22, vy = 0, size = { 96, 12 }, wrap = "blow",
    colour = { 1, 1, 1, 0.22 },
  },
  FOG_DIAGONAL = {
    veil = { 0.86, 0.88, 0.90, 0.26 },
    count = 14, vx = -0.30, vy = 0.16, size = { 72, 10 }, wrap = "blow",
    colour = { 1, 1, 1, 0.22 },
  },

  UNDERWATER = {
    veil = { 0.10, 0.30, 0.60, 0.28 },
    count = 0,
  },
  UNDERWATER_BUBBLES = {
    veil = { 0.10, 0.30, 0.60, 0.24 },
    count = 44, vx = 0.10, vy = -0.9, size = { 3, 3 }, wrap = "rise",
    colour = { 0.85, 0.95, 1.00, 0.60 },
  },

  -- no particles, only the light: SHADE is what the cartridge puts on the
  -- covered places and DROUGHT is Groudon's route
  SHADE = { veil = { 0.05, 0.05, 0.12, 0.26 }, count = 0 },
  DROUGHT = { veil = { 1.00, 0.86, 0.55, 0.20 }, count = 0 },

  ABNORMAL = {
    veil = { 0.20, 0.16, 0.26, 0.32 },
    count = 14, vx = -0.55, vy = 0, size = { 40, 9 }, wrap = "blow",
    colour = { 0.55, 0.50, 0.65, 0.35 },
  },
}

-- ---------------------------------------------------------------------------
-- THE TWO ROUTES THAT CYCLE.
--
-- Routes 119 and 123 do not have a weather; they have a SEQUENCE, and the
-- cartridge names that with its own two values rather than with a weather --
-- which is why they are 20 and 21 in the name table with a gap below them
-- rather than sitting in the run of sixteen.  Both are the same shape: mostly
-- clear, with rain arriving and passing.
--
-- The lengths are this port's, not the cartridge's.
-- ---------------------------------------------------------------------------
local CYCLES = {
  ROUTE119_CYCLE = { "SUNNY", "RAIN", "RAIN_THUNDERSTORM", "RAIN" },
  ROUTE123_CYCLE = { "SUNNY", "SUNNY", "RAIN", "SUNNY" },
}
Gen3Weather.CYCLES = CYCLES

-- The dataset's own tables, when the import read them.  The two above are the
-- same four steps and are here so a cache imported before extractMapSections
-- learned to read them still cycles the way the cartridge does.
-- ---------------------------------------------------------------------------
-- ...AND IN A BATTLE.
--
-- Reported from play: "in battle when there are weather effects theyre not
-- showing properly".  They were not showing at all.  The battle has modelled
-- weather since the ruleset went in -- it drives the damage, the accuracy,
-- CLOUD NINE and AIR LOCK -- and nothing ever drew it, so a Rain Dance was
-- four turns of text and no rain.
--
-- WHICH LOOK BELONGS TO WHICH BATTLE WEATHER IS THE CARTRIDGE'S OWN ANSWER,
-- read backwards.  constants.gen3BattleWeather is the map-weather -> battle-
-- weather table the import lifts out of the dump: RAIN, RAIN_THUNDERSTORM and
-- DOWNPOUR all become WEATHER_RAIN in a battle, SNOW becomes HAIL, DROUGHT
-- becomes SUN.  Inverting it gives the field weather a battle weather looks
-- like without a single name being chosen here -- and where several field
-- weathers map onto one battle weather (rain has three), the one whose name
-- IS the battle weather wins, and failing that the first in sorted order, so
-- the answer does not depend on table iteration.
--
-- A dataset with no such table falls back to the four names that are spelled
-- the same on both sides, which is three of the four.
local BATTLE_FALLBACK = {
  RAIN = "RAIN", SANDSTORM = "SANDSTORM", HAIL = "SNOW", SUN = "DROUGHT",
}

function Gen3Weather.forBattle(weather, constants)
  if type(weather) ~= "string" or weather == "" then return nil end
  local table_ = type(constants) == "table" and constants.gen3BattleWeather
  if type(table_) == "table" then
    local best = nil
    local names = {}
    for field, battle in pairs(table_) do
      if battle == weather then names[#names + 1] = field end
    end
    table.sort(names)
    for _, field in ipairs(names) do
      -- a cycle is a sequence, not a look: it names no particles of its own
      if not CYCLES[field] then
        if field == weather then best = field break end
        best = best or field
      end
    end
    if best then return best end
  end
  return BATTLE_FALLBACK[weather]
end

function Gen3Weather.setCycles(record)
  if type(record) ~= "table" then return false end
  local out = {}
  for key in pairs(CYCLES) do
    local list = record[key]
    if type(list) == "table" and #list > 0 then out[key] = list end
  end
  if not next(out) then return false end
  for key, list in pairs(out) do CYCLES[key] = list end
  return true
end

-- THE WEATHER ACTUALLY BEING DRAWN.
--
-- A cycling route picks its step with the SAVE's cycle stage, not with a
-- clock: gSaveBlock1Ptr + $2F is a byte the cartridge advances by the number
-- of days that have passed, and 0AEF9E reads it and indexes the route's own
-- four-byte table with it.  So the weather on Routes 119 and 123 does not
-- change while you are playing -- it is whatever today's stage says, all day.
--
-- This used to run on the FRAME counter, a few hundred frames a step, which
-- is what made the rain arrive and leave every twenty seconds and left the
-- route showing a handful of clouds most of the time.
function Gen3Weather.resolve(name, frame, stage)
  local cycle = CYCLES[name]
  if not cycle or #cycle == 0 then return name end
  local at = math.floor(tonumber(stage) or 0) % #cycle
  return cycle[at + 1] or cycle[1]
end

function Gen3Weather.look(name, frame, stage)
  local resolved = Gen3Weather.resolve(name, frame, stage)
  local look = LOOKS[resolved]
  if look == false then return nil, resolved end
  return look, resolved
end

-- Does this weather draw anything at all?  Two thirds of the maps that set a
-- weather set SUNNY, and the honest answer for those is no.
function Gen3Weather.draws(name, frame, stage)
  local look = Gen3Weather.look(name, frame, stage)
  if not look then return false end
  return (look.veil ~= nil) or ((look.count or 0) > 0)
end

-- ---------------------------------------------------------------------------
-- THE PARTICLE FIELD
--
-- Seeded from the weather's name so it is the same field every time, and
-- placed by a frame count rather than accumulated -- a particle's position is
-- a function of the frame, not of how many times something was updated, so a
-- dropped frame cannot make the rain drift.
-- ---------------------------------------------------------------------------

local function seedOf(name)
  local seed = 0
  for i = 1, #name do
    seed = (seed * 31 + name:byte(i)) % 65536
  end
  return seed + 1
end

-- AN EVEN SCATTER, WHICH IS NOT THE SAME AS A RANDOM ONE.
--
-- The first version of this multiplied a counter and read consecutive outputs
-- for a particle's x and its y.  Consecutive outputs of a weak generator are
-- CORRELATED, so every flake of snow, every speck of ash and every grain of
-- sand landed on the same diagonal, and Hoenn's weather came out looking like
-- tinsel.  Strengthening the generator did not fix it: the runtime is LuaJIT,
-- where every number is a double, so a hash built on 32-bit multiplies loses
-- exactly the low bits it lives on.
--
-- So not a hash at all.  The R2 low-discrepancy sequence walks the unit
-- square in two irrational strides taken from the plastic number -- the two
-- dimensional analogue of the golden ratio -- and spreads points EVENLY by
-- construction rather than by luck.  Measured over a 6x4 grid of the screen
-- it fills all twenty-four cells with between one and five particles each and
-- leaves x and y correlated below 0.12, which the suite asserts.
--
-- Even spread is the actual requirement -- rain should not clump -- so this
-- is the right instrument rather than a cheaper stand-in for randomness.
local PLASTIC = 1.32471795724474602596
local STRIDE_X = 1 / PLASTIC
local STRIDE_Y = 1 / (PLASTIC * PLASTIC)
local STRIDE_RATE = 1 / (PLASTIC * PLASTIC * PLASTIC)

-- where in the square a weather's own field starts, so two weathers on
-- screen back to back are not the same pattern
local function offsetsOf(seed)
  return (seed * STRIDE_Y) % 1, (seed * STRIDE_X) % 1,
         (seed * STRIDE_RATE) % 1
end

-- Where every particle of `name` is at `frame`, in a `w` by `h` field.
-- Returns a list of { x, y, w, h }.
function Gen3Weather.particles(name, frame, w, h, stage)
  local look, resolved = Gen3Weather.look(name, frame, stage)
  local out = {}
  if not look or (look.count or 0) <= 0 then return out, resolved end
  w, h = w or 240, h or 160
  frame = frame or 0
  local offX, offY, offRate = offsetsOf(seedOf(resolved))
  local pw, ph = look.size[1], look.size[2]
  -- the field a particle wraps inside is the screen plus one particle, so a
  -- streak leaves and enters rather than blinking out at the edge
  local spanX, spanY = w + pw, h + ph
  for i = 1, look.count do
    local ox = ((offX + STRIDE_X * i) % 1) * spanX
    local oy = ((offY + STRIDE_Y * i) % 1) * spanY
    -- A PER-PARTICLE SPEED, so the field does not move as one sheet -- and
    -- the speed has to be a QUADRATIC function of the index rather than a
    -- linear one.  Both coordinates above are linear in i; a speed that is
    -- also linear in i is an affine function of the starting position, so the
    -- lattice stays a lattice however long it runs and at some frames the
    -- whole field collapses into bands with a quarter of the screen bare.
    -- A quadratic Weyl sequence is equidistributed and is not affine in i,
    -- which breaks that relationship.  The suite measures the coverage at
    -- several frames rather than one, because one frame cannot see this.
    local spin = (offRate + STRIDE_RATE * i * i) % 1
    local rate = 0.7 + spin * 0.6
    local x = (ox + (look.vx or 0) * rate * frame) % spanX - pw
    local y = (oy + (look.vy or 0) * rate * frame) % spanY - ph
    out[#out + 1] = { x = x, y = y, w = pw, h = ph }
  end
  return out, resolved
end

-- The lightning, as a 0..1 brightness.  Nonzero for a handful of frames every
-- `flash` frames and zero the rest of the time, which is what makes it a
-- flash rather than a strobe.
function Gen3Weather.flash(name, frame, stage)
  local look, resolved = Gen3Weather.look(name, frame, stage)
  if not (look and look.flash) then return 0 end
  local at = (frame or 0) % look.flash
  if at < 3 then return 0.55 end
  if at < 5 then return 0.20 end
  if at >= 8 and at < 10 then return 0.35 end
  return 0, resolved
end

-- ---------------------------------------------------------------------------
-- DRAWING IT
--
-- Screen space, over the field and under the text box -- which is where the
-- overworld's other full-screen effects (the poison flicker) already go.
-- ---------------------------------------------------------------------------
function Gen3Weather.draw(name, frame, w, h, stage)
  local look, resolved = Gen3Weather.look(name, frame, stage)
  if not look then return false end
  w, h = w or 240, h or 160

  local veil = look.veil
  if veil then
    love.graphics.setColor(veil[1], veil[2], veil[3], veil[4])
    love.graphics.rectangle("fill", 0, 0, w, h)
  end

  local colour = look.colour
  if colour and (look.count or 0) > 0 then
    love.graphics.setColor(colour[1], colour[2], colour[3], colour[4])
    for _, p in ipairs(Gen3Weather.particles(name, frame, w, h, stage)) do
      love.graphics.rectangle("fill", math.floor(p.x), math.floor(p.y),
                              p.w, p.h)
    end
  end

  local bolt = Gen3Weather.flash(name, frame, stage)
  if bolt > 0 then
    love.graphics.setColor(1, 1, 1, bolt)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end

  love.graphics.setColor(1, 1, 1, 1)
  return true, resolved
end

Gen3Weather.LOOKS = LOOKS

return Gen3Weather
