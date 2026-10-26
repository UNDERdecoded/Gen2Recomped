local mod = ...
local moves = mod.content.moves
local report = { initial = assert(moves:get("POUND")).effect, effects = {} }
for _, id in ipairs({
  "SLEEP_EFFECT",
  "BURN_SIDE_EFFECT1",
  "BURN_SIDE_EFFECT2",
  "SPECIAL_UP1_EFFECT",
  "SPECIAL_DOWN_SIDE_EFFECT",
  "NO_ADDITIONAL_EFFECT",
}) do
  assert(moves:patch("POUND", { effect = id }))
  local row = assert(moves:get("POUND"))
  assert(row.effect == id)
  report.effects[#report.effects + 1] = row.effect
  if mod.generation > 1 then
    assert(moves:patch("POUND", { secondaryChance = 25 }))
    assert(moves:get("POUND").secondaryChance == 25)
    report.chance = 25
  end
  local detached = assert(moves:get("POUND"))
  assert(moves:override("POUND", detached))
  assert(moves:get("POUND").effect == id)
end
local value, why = moves:patch("POUND", { effect = "native:1:not_original" })
assert(value == nil and type(why) == "string")
assert(moves:get("POUND").effect == "NO_ADDITIONAL_EFFECT")
assert(moves:patch("POUND", { effect = "SLEEP_EFFECT" }))
report.final = moves:get("POUND").effect
report.preflight = true
mod.exports.report = function()
  return report
end
