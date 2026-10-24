package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, version, api, format = unpack(arg)
local Fixture = dofile(root .. "/tests/encounter_table/fixture.lua")
local f = Fixture.new(root, backend, version, tonumber(api), format)
local old = math.random
local oldLove = love and love.math and love.math.random
math.random = function()
  error("preview consumed RNG")
end
if oldLove then
  love.math.random = math.random
end
local rows = dofile(root .. "/tests/encounter_table/cases.lua").run(f)
math.random = old
if oldLove then
  love.math.random = oldLove
end
f.close()
-- Failed entry must remove the real public subscription.
for _, failing in ipairs({ false, true }) do
  local control = Fixture.new(root, backend, version, tonumber(api), format, not failing, failing)
  if failing then
    control.T.check(#control.result.errors > 0, "entry error recorded")
  end
  for _, link in ipairs(require("src.mods.Runtime").hooks.chains["encounter.table"] or {}) do
    control.T.check(link.owner ~= "portable_encounter_table", "no-mod/rollback has no owned callback")
  end
  local baseline = assert(
    control.nativeApi.world:effectiveEncounters(
      "PROBE",
      "grass",
      control.generation == 2 and { daytime = "DAY" } or {}
    )
  )
  rows[#rows + 1] =
    { label = failing and "rollback" or "no mod", chance = baseline.chance, dist = baseline.dist }
  control.close()
end
print("ENCOUNTER_TABLE_CONTRACT " .. require("src.link.Json").encode(rows))
f.T.finish("portable native encounter previews")
