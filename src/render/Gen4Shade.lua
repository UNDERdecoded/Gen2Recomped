-- Gen4Shade: turning an area light template into a per-vertex tint.
--
-- WHY THIS FILE EXISTS AT ALL.
--
-- Reported from play, five times: *"it looks like the 59 degree one but its
-- like a flat rendering"*.  The tilt was right, the geometry was right, and
-- the world still read as a sticker -- because EVERY VERTEX IN SINNOH IS
-- WHITE.  Measured, not guessed: over Route 201's chunk 5 (1,264 vertices),
-- Twinleaf's chunk 0 (3,226) and the `t1_h01` house (304), the number of
-- DISTINCT vertex colours is exactly one, and it is 255,255,255.
--
-- That is not a bug in the extraction.  Platinum's map display lists issue
-- NORMAL commands and no COLOR commands, because the DS's geometry engine
-- computes each vertex's colour in hardware from the normal and the area
-- light.  A port that replays the vertices and drops the lighting therefore
-- draws a tree's side at exactly the brightness of its top, and a house wall
-- at exactly the brightness of its roof.  There is no form anywhere, and no
-- amount of correct projection puts it back.
--
-- ---------------------------------------------------------------------------
-- THE EQUATION, AND WHY IT IS THIS ONE
-- ---------------------------------------------------------------------------
--
-- `Gen4AreaLight` deliberately ships `lambert()` and nothing else, and the
-- reason is recorded there: the obvious combination --
-- `diffuse * lightColour * lambert + ambient * lightColour + emission` -- was
-- written, measured, and taken back out, because summed over member 0 it
-- pinned THIRTEEN OF FIFTEEN templates to exactly 1.000 on every channel.  It
-- could not tell a dawn from a noon.
--
-- So this file does not try again at the absolute calibration, which needs a
-- frame compared against the cartridge and has not had one.  It states the
-- part that follows from the extracted numbers and CANNOT saturate:
--
--     lit(N)   = sum over enabled lights of  max(0, -N.L) * lightColour
--     shade(N) = k + (1 - k) * lit(N) / lit(UP)
--
-- with `k` -- the direction-INDEPENDENT share of a surface's colour -- taken
-- from the cartridge's own two rows as `ambient / (ambient + diffuse)`, per
-- channel.
--
-- THE ANCHOR IS THE GROUND PLANE, and that choice is the whole safety
-- argument.  Dividing by `lit(0,1,0)` makes a face whose normal points
-- straight up come out at EXACTLY 1.0, so the flat ground -- which is most of
-- every outdoor map, and every ground shape in chunk 5 is at exactly y=16 --
-- is left at the brightness it already had.  Nothing can go dark, nothing can
-- blow out, and the result is bounded in [k, 1] by construction.  What
-- changes is only what SHOULD change: a vertical face, which the cartridge's
-- sun (light 0's vector is dominated by y = -3600 of 4096, pointing down)
-- barely reaches, falls to the ambient share.
--
-- That is a normalisation, and it is stated rather than hidden: the ratios
-- between faces are the cartridge's, the overall level is ours, and the day
-- someone compares a frame against the hardware, only the anchor moves.
--
-- N IS Y-UP, settled in `Gen4AreaLight` by the same sun vector rather than
-- assumed.

local Gen4AreaLight = require("src.import.Gen4AreaLight")

local Gen4Shade = {}

-- The five-bit channel the cartridge's colours are on.
local CHANNEL_MAX = Gen4AreaLight.CHANNEL_MAX

-- forTemplate(template) -> shade(nx, ny, nz) -> r, g, b, each 0..1
--
-- Nil when the template has no enabled light, which is the honest answer for
-- a member that lights nothing: the caller leaves the vertex colour alone
-- rather than multiplying by a fabricated one.
function Gen4Shade.forTemplate(template)
  if type(template) ~= "table" then return nil end

  -- Flattened out of the parse tree once, because this runs per vertex over
  -- 3,226 of them per chunk and 666 chunks exist.
  local lights, count = {}, 0
  for _, light in pairs(template.lights or {}) do
    local u, c = light.unit, light.colour
    if u and c then
      count = count + 1
      lights[count] = {
        u[1] or 0, u[2] or 0, u[3] or 0,
        (c[1] or 0) / CHANNEL_MAX,
        (c[2] or 0) / CHANNEL_MAX,
        (c[3] or 0) / CHANNEL_MAX,
      }
    end
  end
  if count == 0 then return nil end

  -- `lit` is the diffuse sum alone; the ambient share is applied afterwards as
  -- a floor, so that the two cannot add up past full the way the combined
  -- equation did.
  local function lit(nx, ny, nz)
    local r, g, b = 0, 0, 0
    for i = 1, count do
      local L = lights[i]
      local v = -(nx * L[1] + ny * L[2] + nz * L[3])
      if v > 0 then
        r = r + v * L[4]
        g = g + v * L[5]
        b = b + v * L[6]
      end
    end
    return r, g, b
  end

  -- THE DIRECTION-INDEPENDENT SHARE, from the cartridge's own rows.  A ratio,
  -- so it is immune to the saturation that killed the absolute equation: a
  -- template whose rows are both full white still answers 0.5 rather than 1.
  local amb, dif = template.ambient or {}, template.diffuse or {}
  local function share(i)
    local a, d = amb[i] or 0, dif[i] or 0
    if a + d <= 0 then return 1 end
    return a / (a + d)
  end
  local kr, kg, kb = share(1), share(2), share(3)

  -- The anchor.  Computed once, here, rather than per vertex.
  local ur, ug, ub = lit(0, 1, 0)

  local function channel(v, up, k)
    -- A channel no light reaches from above cannot be normalised against
    -- itself; leaving it at 1 keeps that channel exactly as it is now, which
    -- is the one answer that cannot be wrong in a new direction.
    if up <= 0 then return 1 end
    local out = k + (1 - k) * (v / up)
    if out < 0 then return 0 end
    if out > 1 then return 1 end
    return out
  end

  return function(nx, ny, nz)
    local r, g, b = lit(nx or 0, ny or 1, nz or 0)
    return channel(r, ur, kr), channel(g, ug, kg), channel(b, ub, kb)
  end
end

-- forMap(arealight, member, hour, minute) -> shade, template, index
--
-- The whole lookup in one call: the member a map's `areaLight` names, the
-- band that member is in at this clock, and the tint for it.  The band rule
-- is `Gen4AreaLight.activeAt` rather than a copy of it -- the rule is subtle
-- (`>` and not `>=`, falling back to index 0 to wrap midnight) and two
-- spellings of it is how the two drift.
-- THE BAND'S OVERALL LEVEL -- the part the ground-plane anchor above cannot
-- see. Reported: no map gets darker at night. The DS lights a vertex as
--
--     emission + sum over lights of (diffuse * colour * max(0, -N.L)
--                                    + ambient * colour)
--
-- clamped to 31 per channel (G3_MaterialColor / G3_LightColor, the template's
-- rows 5..8 and its lights). Taken for the UP normal, band by band, and
-- divided by the member's BRIGHTEST band, it is 1 at the brightest hour and
-- the cartridge's own ratio otherwise -- HeartGold's member 0 runs 0.69 at
-- midnight, 1.0 at noon and 0.65 at dusk, with the night's blue from its
-- 11,11,16 sun. Where the sum saturates in every band (Platinum's member 0
-- reaches 31 on most of them, the indoor members on all) the ratio is 1 and
-- nothing changes. Only shapes lit by NORMAL take it, as only those take the
-- light on the DS.
--
-- WHICH LIGHTS, ON PLATINUM: the ones the MATERIAL enables. A model's
-- polygon attribute bits 0..3 (NNSG3dResMat polyAttr, kept by the map
-- models -- AreaLight_UseGlobalModelAttributes takes the template's light
-- and material colours global, NOT its polygon attributes) say which of the
-- four lights reach it. MEASURED over land_data.narc's 666 chunks: of 7,346
-- terrain materials 4,300 enable light 0 alone, 2,955 none (the unlit
-- ones), 48 lights 0 + 1, 43 light 3 (+0). Platinum's templates keep lights
-- 2 and 3 at full white for the people and props, and summed in they pin
-- every band to 31 -- which is why its nights stayed as bright as noon. So
-- Platinum's level takes light 0 only (LIT_MASK_PLATINUM); HeartGold /
-- SoulSilver keep every light, as tuned.
Gen4Shade.LIT_MASK_PLATINUM = 1
local levelCache = setmetatable({}, { __mode = "k" })
local function absoluteUp(template, mask)
  local tot = { 0, 0, 0 }
  local dif, amb, emi = template.diffuse or {}, template.ambient or {}, template.emission or {}
  for _, L in pairs(template.lights or {}) do
    local u, c = L.unit, L.colour
    local bit = 2 ^ (tonumber(L.index) or 0)
    if mask and math.floor(mask / bit) % 2 == 0 then u = nil end
    if u and c then
      local v = math.max(0, -(u[2] or 0))
      for i = 1, 3 do
        local lc = (c[i] or 0) / CHANNEL_MAX
        tot[i] = tot[i] + (dif[i] or 0) / CHANNEL_MAX * lc * v + (amb[i] or 0) / CHANNEL_MAX * lc
      end
    end
  end
  for i = 1, 3 do tot[i] = math.min(1, tot[i] + (emi[i] or 0) / CHANNEL_MAX) end
  return tot
end
function Gen4Shade.levelFor(templates, template, mask)
  if type(templates) ~= "table" or type(template) ~= "table" then return 1, 1, 1 end
  local cache = levelCache[templates]
  if not cache then cache = {}; levelCache[templates] = cache end
  local ref = cache[mask or "all"]
  if ref == nil then
    local best, bestSum = nil, -1
    for _, t in ipairs(templates) do
      local a = absoluteUp(t, mask)
      local s = a[1] + a[2] + a[3]
      if s > bestSum then best, bestSum = a, s end
    end
    ref = best or false
    cache[mask or "all"] = ref
  end
  if not ref then return 1, 1, 1 end
  local a = absoluteUp(template, mask)
  local function ratio(i) if (ref[i] or 0) <= 0 then return 1 end return math.min(1, a[i] / ref[i]) end
  return ratio(1), ratio(2), ratio(3)
end

function Gen4Shade.forMap(arealight, member, hour, minute)
  local members = arealight and arealight.members
  local templates = members and member and members[member]
  if not templates then return nil end
  local template, index = Gen4AreaLight.activeAtClock(templates, hour, minute)
  if not template then return nil end
  local inner = Gen4Shade.forTemplate(template)
  if not inner then return nil, template, index end
  -- THE DEFAULT MASK, for a shape whose cache carries no `lights` (imported
  -- before gen4-light-mask-v1): light 0 on Platinum (the 4,300 of 7,346
  -- measured above), every light on HeartGold / SoulSilver, as tuned
  local default
  pcall(function()
    local GV = require("src.core.GameVersion")
    if GV.family(GV.get()) == "platinum" then default = Gen4Shade.LIT_MASK_PLATINUM end
  end)
  -- PER MATERIAL: `shade(nx, ny, nz, lights)` takes the shape's own light
  -- mask (polyAttr bits 0..3, Gen4ModelPack `lights`). A mask of 0 -- no
  -- light reaches the material -- is NOT LIT AT ALL: the geometry engine
  -- computes a NORMAL's colour only from the lights POLYGON_ATTR enables, and
  -- with none the vertex keeps its COLOR (or the diffuse-as-vertex-colour
  -- bit, which AreaLight_UseGlobalModelAttributes leaves off: Platinum's
  -- ModelAttributes_SetDiffuseReflection(.., FALSE, ..)). So 1, 1, 1 -- no
  -- form, no night (the DS hardware rule, GBATEK "DS 3D Polygon Light
  -- Parameters"; the area-light side READ FROM CODE)
  local levels = {}
  local function level(m)
    local key = m or "default"
    local l = levels[key]
    if not l then
      local mask = m
      if mask == nil then mask = default end
      if mask == 0 then mask = default end
      local lr, lg, lb = Gen4Shade.levelFor(templates, template, mask)
      l = { lr, lg, lb }
      levels[key] = l
    end
    return l
  end
  local shade = function(nx, ny, nz, lights)
    if tonumber(lights) == 0 then return 1, 1, 1 end
    local r, g, b = inner(nx, ny, nz)
    local l = level(tonumber(lights))
    return r * l[1], g * l[2], b * l[3]
  end
  return shade, template, index
end

-- Which band a member is in, without building a tint for it.  This is what
-- the ground compares frame to frame to decide whether its baked meshes have
-- gone stale: a mesh carries its light baked into the vertex colours, so a
-- new band is a rebuild and not merely a re-bake.
function Gen4Shade.bandFor(arealight, member, hour, minute)
  local members = arealight and arealight.members
  local templates = members and member and members[member]
  if not templates then return 0 end
  local _, index = Gen4AreaLight.activeAtClock(templates, hour, minute)
  return index or 0
end

-- ---------------------------------------------------------------------------
-- DAY AND NIGHT, FOR THE SKY
-- ---------------------------------------------------------------------------
--
-- Requested: *"a nighttime variant as well based on the time it should fade
-- between the two and ensure were using the games day and night lighting
-- system as well"*.
--
-- THE TINT ABOVE CANNOT ANSWER THIS, and its own comment says why: it is
-- ratio-normalised against the ground plane on purpose, so "a template whose
-- rows are both full white still answers 0.5 rather than 1".  That is the right
-- call for shading a wall and it makes the tint blind to the clock -- it reports
-- the SHAPE of the light and never its level.  Asking it for a day/night signal
-- would be asking a measurement that cannot fail.
--
-- NOR IS THERE A TIME-OF-DAY TABLE TO READ.  Gen 2 and Gen 3 both have one and
-- both are extracted (`GetTimeOfDay`, `TimeOfDayTable`); Platinum has none in
-- anything extracted here.  Searched by name across `src/` -- and that search
-- does find the Gen 2 and Gen 3 tables, so it is known to be able to return
-- something.
--
-- WHAT IS ACTUALLY IN THE CARTRIDGE is member 0's fifteen area-light keyframes,
-- and the day cycle is in exactly one row of them: LIGHT 0's COLOUR.  Light 0 is
-- the only light in any of the fifteen with a real direction
-- (0.46, -0.88, -0.11 at midnight -- the sun); lights 2 and 3 carry the
-- degenerate (0, 0, 1) in all fifteen and say nothing about a direction at all.
-- So light 0 is the sun, and its colour is the only row in the table that traces
-- a day:
--
--     00:00  11,11,16      12:00  22,22,20      18:30  17,13,10
--     04:00  11,11,16      15:00  24,24,20      19:00  16,13,10
--     04:30  12,12,18      15:30  22,22,18      20:00  11,12,15
--     05:00  12,12,22      17:00  20,18,16      24:00  11,11,16
--     08:00  15,15,22      18:00  19,16,12
--
-- Keyframes 1 and 15 are byte-identical at 00:00 and 24:00, which is what makes
-- this a CYCLIC KEYFRAME LIST rather than fifteen flat spans.
--
-- A KEYFRAME IS NIGHT WHEN ITS SUN COLOUR IS STILL THE MIDNIGHT ONE, and the
-- threshold is not a taste.  Distances from the 00:00 anchor run 0.00, 0.00,
-- 1.41, then 2.45, with the far end at 18.81, so the gap between 1.41 and 2.45
-- is a real break: ANY cut between 8% and 12% of the spread selects the same
-- four keyframes -- 00:00, 04:00, 20:00 and 24:00.
--
-- THAT PUTS THE NIGHT AT 20:00 -> 04:00, WHICH IS PLATINUM'S OWN NIGHT PERIOD,
-- arrived at from the sun colours alone with neither boundary typed in here.
-- The two agreeing is the check on this whole derivation -- it is the part that
-- could have come out wrong and did not.
--
-- AND THE FADE IS THE KEYFRAME SPACING ITSELF, nothing invented: night falls
-- across 19:00 -> 20:00 (an hour) and lifts across 04:00 -> 04:30 (half an
-- hour), because those are where the cartridge put its keyframes.  A fade
-- length I chose would be the one number in this file with no source.

-- As a fraction of the member's own sun-colour spread -- see the break above.
local NIGHT_CUT = 0.10

-- Keyed on the templates table, which is the parse tree and lives as long as the
-- game does; weak so a reloaded cartridge does not pin the old one.
local nightCurves = setmetatable({}, { __mode = "k" })

-- Light 0, by its index rather than its slot: `lights` is 1-based with holes
-- (member 0 fills 1, 3 and 4 for indices 0, 2 and 3), so the slot number is not
-- the light number.
local function sunColour(template)
  for _, light in pairs(type(template) == "table" and template.lights or {}) do
    if light.index == 0 and light.colour then return light.colour end
  end
  return nil
end

-- nightCurve(templates) -> { {halfSeconds, 0 or 1}, ... } in clock order, or nil
local function nightCurve(templates)
  local cached = nightCurves[templates]
  if cached ~= nil then return cached or nil end

  local ref = sunColour(templates[1])
  if not ref then nightCurves[templates] = false return nil end

  local dist, far = {}, 0
  for i = 1, #templates do
    local c = sunColour(templates[i])
    if not c then nightCurves[templates] = false return nil end
    local dr = (c[1] or 0) - (ref[1] or 0)
    local dg = (c[2] or 0) - (ref[2] or 0)
    local db = (c[3] or 0) - (ref[3] or 0)
    local d = math.sqrt(dr * dr + dg * dg + db * db)
    dist[i] = d
    if d > far then far = d end
  end

  -- A MEMBER WHOSE SUN NEVER MOVES CARRIES NO DAY AT ALL -- members 1 and 2, the
  -- 483 indoor maps, are exactly this, constant across all fifteen bands.  `nil`
  -- rather than 0, so a caller cannot read "constant light" as "permanent noon".
  if far <= 0 then nightCurves[templates] = false return nil end

  local curve = {}
  for i = 1, #templates do
    curve[i] = { templates[i].endTime or 0, (dist[i] / far <= NIGHT_CUT) and 1 or 0 }
  end
  nightCurves[templates] = curve
  return curve
end

-- nightness(arealight, member, hour, minute) -> 0..1, or nil
--
-- 0 is full day, 1 is full night, and in between is a keyframe span the
-- cartridge chose.  Nil when the member carries no day cycle, which is the
-- honest answer rather than a fabricated noon.
function Gen4Shade.nightness(arealight, member, hour, minute)
  local members = arealight and arealight.members
  local templates = members and member and members[member]
  if type(templates) ~= "table" or #templates < 2 then return nil end
  local curve = nightCurve(templates)
  if not curve then return nil end

  local t = Gen4AreaLight.clockTime(hour, minute)
  for i = 1, #curve - 1 do
    local a, b = curve[i], curve[i + 1]
    if t >= a[1] and t < b[1] then
      if a[2] == b[2] then return a[2] end
      local span = b[1] - a[1]
      if span <= 0 then return b[2] end
      return a[2] + (b[2] - a[2]) * ((t - a[1]) / span)
    end
  end
  -- The list spans 00:00 to 24:00 inclusive and a wall clock cannot leave it, so
  -- this is the wrap keyframe and not a gap.
  return curve[#curve][2]
end

return Gen4Shade
