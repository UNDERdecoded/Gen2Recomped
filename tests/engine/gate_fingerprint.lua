-- The fingerprint gate (21-testing-and-ci "the fingerprint gate").
--
-- The link fingerprint is a deterministic digest of the link surface --
-- species, moves, type_chart, statuses, move_effects, constants, link
-- fields.  Hashing it over the fixture dataset with no mods and pinning
-- the result catches the failure mode nothing else does: an accidental
-- edit to a *built-in* registry record.  That would not fail a schema
-- check, would not fail a no-mod parity gate that only compares data to
-- itself, and would silently make two builds of the same engine refuse to
-- link.  Here it flips one hex string and fails.
--
-- Regenerate deliberately after auditing each changed surface section; see
-- tests/goldens/fixture_fingerprint.md. Never update expected values automatically.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Fingerprint = require("src.link.Fingerprint")

local GOLDEN = "tests/goldens/fixture_fingerprint.txt"

local function readGolden(path)
  local handle = io.open(path, "r")
  if not handle then return nil end
  local value = handle:read("*l")
  handle:close()
  return value and value:gsub("%s+$", "")
end

local data = T.fixtures.fresh()
local run = T.sdk.loadNone({ data = data })
T.eq(#run.errors, 0, "the fixture dataset loads with no mods and no errors")

local actual = Fingerprint.compute(data, {})
local golden = readGolden(GOLDEN)

T.check(golden ~= nil, "the committed fixture fingerprint golden exists: " .. GOLDEN)
T.eq(actual, golden, "fixture fingerprint matches the committed golden")

-- Section pins make a registry addition reviewable without treating a whole
-- digest change as permission to bless unrelated species or move changes.
local sectionFile = assert(io.open("tests/goldens/fixture_fingerprint_sections.txt", "r"))
local expectedSections = {}
for line in sectionFile:lines() do
  local name, expected = line:match("^(%S+)%s+(%x+)$")
  if name then expectedSections[name] = expected end
end
sectionFile:close()
local sectionCount = 0
for name, body in Fingerprint.surface(data, {}):gmatch("%[([^%]]+)%]([^%[]*)") do
  sectionCount = sectionCount + 1
  T.eq(Fingerprint.digest("[" .. name .. "]" .. body), expectedSections[name],
    "audited fixture surface section: " .. name)
  expectedSections[name] = nil
end
T.eq(sectionCount, 7, "the fixture has seven populated fingerprint sections")
T.eq(next(expectedSections), nil, "all committed section pins were checked")

-- Platinum's four dynamic-power effects were added in 3252aec. They are
-- native full handlers, and removing any one must change link compatibility.
local sinnoh = {
  "POWER_BASED_ON_LOW_SPEED", "INCREASE_POWER_WITH_MORE_HP",
  "DOUBLE_POWER_WHEN_BELOW_HALF", "DOUBLE_POWER_HEAL_SLEEP",
}
for _, id in ipairs(sinnoh) do
  T.eq(data.move_effects[id].kind, "full", "Sinnoh effect is registered: " .. id)
  local copy = T.fixtures.fresh()
  local copyRun = T.sdk.loadNone({ data = copy })
  copy.move_effects[id] = nil
  T.neq(Fingerprint.compute(copy, {}), actual, "omitting " .. id .. " changes compatibility")
  copyRun.release()
end

-- determinism: same data, same digest.  A fingerprint that folded a table
-- address or a pairs() order would pass once and fail in CI.
T.eq(Fingerprint.compute(data, {}), actual, "the fingerprint is stable within a process")

local second = T.fixtures.fresh()
local secondRun = T.sdk.loadNone({ data = second })
T.eq(Fingerprint.compute(second, {}), actual,
  "a freshly built fixture dataset digests identically")
secondRun.release()

-- the mutation test the plan asks be verified in review, run instead: a
-- changed built-in record MUST move the hash.  If any of these pass
-- unchanged the gate is decorative.
local mutations = {
  {
    name = "a species base stat",
    apply = function(d) d.pokemon.FIXMON_A.baseStats.attack =
      d.pokemon.FIXMON_A.baseStats.attack + 1 end,
  },
  {
    name = "a move's power",
    apply = function(d) d.moves.FIX_TACKLE.power = d.moves.FIX_TACKLE.power + 1 end,
  },
  {
    name = "a move's type",
    apply = function(d) d.moves.FIX_TACKLE.type = "FIRE" end,
  },
  {
    name = "a type-chart matchup",
    apply = function(d) d.type_chart.matchups[1].multiplier = 40 end,
  },
  {
    -- replaced, not edited in place: Builtins hands the same record table
    -- to every dataset it merges into, so mutating one of its fields would
    -- corrupt the other datasets in this process (see followUps)
    name = "a built-in type category",
    apply = function(d)
      local types = d.type_chart.types
      if types and types.NORMAL then
        types.NORMAL = { name = "NORMAL", category = "special" }
      end
    end,
  },
  {
    name = "a built-in status record",
    apply = function(d)
      local id = next(d.statuses or {})
      if id then d.statuses[id] = { mutated = true } end
    end,
  },
  {
    name = "a built-in move effect",
    apply = function(d)
      local id = next(d.move_effects or {})
      if id then d.move_effects[id] = { mutated = true } end
    end,
  },
  {
    name = "a link-surface constant",
    apply = function(d) d.constants.levelCap = d.constants.levelCap - 1 end,
  },
}

for _, mutation in ipairs(mutations) do
  local mutated = T.fixtures.fresh()
  local mutatedRun = T.sdk.loadNone({ data = mutated })
  mutation.apply(mutated)
  T.neq(Fingerprint.compute(mutated, {}), actual,
    "mutating " .. mutation.name .. " moves the fingerprint")
  mutatedRun.release()
end

-- no mutation above leaked into this dataset; if one did, every assertion
-- after it would be measuring a corrupted baseline
T.eq(Fingerprint.compute(data, {}), actual,
  "the mutation cases left the gate's own dataset untouched")

-- a mod in the hello moves the digest too, which is what makes a one-sided
-- install detectable at handshake time rather than at desync time
T.neq(Fingerprint.compute(data, { { id = "gate_mod", version = "1.0.0", affectsLink = true } }),
  actual, "a link-affecting mod in the hello moves the fingerprint")

-- ...and a mod that declares it does not affect link must not
T.eq(Fingerprint.compute(data, { { id = "cosmetic", version = "1.0.0", affectsLink = false } }),
  actual, "a mod that does not affect link leaves the fingerprint alone")

run.release()

T.finish("gate_fingerprint")
