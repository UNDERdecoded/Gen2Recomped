-- Graphics performance tier: one knob that scales the port's optional,
-- non-faithful presentation extras down for weaker hardware.
--
-- The heavy extras are all things the Game Boy never had and this port
-- adds on top: the whole-screen 3D TILT (transforms the entire map as a
-- ground plane), the GBC FX post-process shader (a fullscreen pass), and
-- survey ZOOM (zooming out renders the connected neighbor maps -- a lot of
-- extra overdraw).  A hard FPS ceiling caps present cost on top of that.
-- None of this touches game logic, which is fixed-step off dt
-- (src/core/FixedStep.lua), so every tier plays identically; they differ
-- only in how much optional eye-candy the renderer is allowed to do.
--
-- WHAT THIS CANNOT SEE, AND WHICH MATTERS ON AN INSTALL WITH A WORLD MOD.
-- The four things below are all 2D presentation extras this port adds, and
-- a mod that OWNS the world pass can legitimately switch two of them off
-- for good: DRAMATIC_SHAPE holds TILT and GBC FX at zero and drops both
-- OPTIONS rows for as long as it is installed, because TILT is the flat
-- fake of what its own pass does for real and GBC FX is a full-screen
-- present over the top of it.  On such an install `tilt` and `gbcfx` are
-- already zero before this clamps them, so two of the four caps here are
-- no-ops and the row moves the survey zoom and the FPS ceiling alone.
-- That is not a bug in either side, but it does mean the tier is only as
-- useful as what the mod itself does with it -- and the way a mod does
-- that is to read `Performance.tier` (the RESOLVED tier, never "auto",
-- written by applyOptions below) and scale its own work against it.  See
-- lib/Tier.lua in DRAMATIC_SHAPE for the worked example.
--
-- The tier is persisted as save.options.performance:
--   auto      pick a default from the device (see detect())
--   high      everything on -- the historical behavior
--   balanced  no TILT, no GBC FX (kept: survey zoom, colors, uncapped FPS)
--   low       no TILT, no GBC FX, no survey zoom, FPS capped
--
-- AUTO only chooses the *default* for the current device; every tier is
-- selectable in OPTIONS, so a heuristic that guesses wrong is one row away
-- from being overridden.  The clamps are applied live in Game:applyOptions
-- against the stored options without rewriting them, so raising the tier
-- restores exactly the TILT / GBC FX / ZOOM / FPS the player had.
--
-- Zero requires: loads during love.conf and under plain Lua for tools and
-- tests, the same way src/core/GameVersion.lua does.

local Performance = {}

-- P2 is independently reversible. Tier rows can reduce the idle budget or
-- tune the collector without changing the persisted presentation options.
Performance.gcBudget = true
-- P3: cache hot-path dependencies and reuse engine-private presentation data.
Performance.hotPathHoist = true
-- P4: independent world-draw closure, list and protection optimization.
Performance.worldDrawHoist = true
-- P5: palette upload batching and cropped zone quads.
Performance.paletteZoneCache = true
Performance.GC_PAUSE = 120
Performance.GC_STEP_MUL = 300
Performance.GC_BUDGET_SECONDS = 0.0005

-- Option-row order (auto first, then most to least capable).
Performance.TIERS = { "auto", "high", "balanced", "low" }

Performance.LABELS = {
  auto = "AUTO",
  high = "HIGH",
  balanced = "BALANCED",
  low = "LOW",
}

-- What each concrete tier permits.  `auto` is resolved to one of these
-- before caps are read, so it has no row here.  fpsMax = false means no
-- extra ceiling (the player's own MAX FPS still applies).
Performance.CAPS = {
  high     = { tilt = true,  gbcfx = true,  survey = true,  fpsMax = false },
  balanced = { tilt = false, gbcfx = false, survey = true,  fpsMax = false },
  low      = { tilt = false, gbcfx = false, survey = false, fpsMax = 60 },
}
for _, caps in pairs(Performance.CAPS) do
  caps.gcPause = Performance.GC_PAUSE
  caps.gcStepMul = Performance.GC_STEP_MUL
  caps.gcBudgetSeconds = Performance.GC_BUDGET_SECONDS
end

-- Live resolved tier (never "auto"); Game:applyOptions sets it and the
-- renderer / options row read it back.  Defaults to the unclamped tier so
-- a pre-boot launcher behaves exactly as it always did.
Performance.tier = "high"

local function loveOS()
  if love and love.system and love.system.getOS then
    return love.system.getOS()
  end
  return nil
end

local function processorCount()
  if love and love.system and love.system.getProcessorCount then
    return love.system.getProcessorCount()
  end
  return nil
end

-- CPU architecture via LuaJIT's jit.arch when present: "arm"/"arm64" on
-- phones and PortMaster handhelds, "x86"/"x64" on desktops.  nil under a
-- plain-Lua tool or test with no jit table, which resolves to HIGH (no
-- clamping) so tooling is never surprised.
local function cpuArch()
  return (jit and jit.arch) or nil
end

-- Default tier for the current device.  Deliberately conservative: only
-- the platforms that are reliably weak drop below HIGH, and AUTO is always
-- overridable, so a wrong guess costs one OPTIONS row.  A normal
-- multi-core desktop -- the common case, and every existing install whose
-- options.lua predates this option -- resolves to HIGH and behaves exactly
-- as before.
function Performance.detect()
  local os = loveOS()
  local arch = cpuArch()
  local isArm = arch == "arm" or arch == "arm64"
  local cores = processorCount()

  -- PortMaster-style ARM Linux handhelds (e.g. the RG34XXSP the project
  -- already ships a build for): the weakest target here.
  if isArm and os ~= "Android" and os ~= "iOS" then
    return "low"
  end
  -- Phones and tablets: GBC FX is already force-disabled here (issue #136);
  -- balanced additionally drops the 3D tilt, the heaviest remaining extra.
  if os == "Android" or os == "iOS" then
    return "balanced"
  end
  -- Desktop: a dual-core (or single-core) box is the low-end line.
  if cores and cores <= 2 then
    return "balanced"
  end
  return "high"
end

-- Fold a stored option value to a concrete tier, resolving "auto" (and any
-- hand-edited garbage) through detect().
function Performance.resolve(value)
  if value == "high" or value == "balanced" or value == "low" then
    return value
  end
  return Performance.detect()
end

-- Normalize a stored value to a valid option id (keeps "auto"); a bad value
-- degrades to auto so a corrupt options.lua still lands on something sane.
function Performance.normalize(value)
  for _, id in ipairs(Performance.TIERS) do
    if value == id then return id end
  end
  return "auto"
end

-- Row label for a stored value: the tier's own name (AUTO / HIGH / ...).
function Performance.label(value)
  return Performance.LABELS[Performance.normalize(value)]
end

-- Concrete caps for a stored option value (resolving auto).
function Performance.caps(value)
  return Performance.CAPS[Performance.resolve(value)]
end

-- Resolve the tier for these options, record it live, and return its caps.
-- Called from Game:applyOptions, which clamps the live presentation modules
-- against the returned caps.
function Performance.applyOptions(opts)
  local tier = Performance.resolve(opts and opts.performance)
  Performance.tier = tier
  return Performance.CAPS[tier]
end

-- Cycle the OPTIONS row: auto -> high -> balanced -> low -> auto (dir -1
-- reverses).  Lua's `%` is non-negative for a positive modulus, so a
-- negative dir wraps correctly.
function Performance.cycle(value, dir)
  value = Performance.normalize(value)
  local i = 1
  for idx, id in ipairs(Performance.TIERS) do
    if id == value then i = idx break end
  end
  local n = #Performance.TIERS
  local nextIdx = (i - 1 + (dir or 1)) % n + 1
  return Performance.TIERS[nextIdx]
end

return Performance
