-- Declared native inputs, independent of either engine's order calculation.
local cases = {}
local function add(name, values)
  values = values or {}
  values.name = name
  cases[#cases + 1] = values
end
add("user-faster", { speeds = { 100, 101 }, expected = 0 })
add("target-faster", { speeds = { 101, 100 }, expected = 1 })
add("tie-even", { expected = 0, tie = 0 })
add("tie-odd", { expected = 2, tie = 1 })
add("tie-high-even", { expected = 0, tie = 65534 })
add("tie-high-odd", { expected = 2, tie = 65535 })
for stage = -6, 6 do
  for _, speed in ipairs({ 0, 1, 3, 7, 51, 101, 255, 65535 }) do
    add(
      "stage-" .. stage .. "-speed-" .. speed,
      { speeds = { speed, 101 }, stages = { stage, -stage }, tie = 1 }
    )
  end
end
for _, weather in ipairs({ 0, 1, 2, 4, 7, 32, 64, 96, 97 }) do
  for _, ability in ipairs({ 0, 33, 34 }) do
    add(
      "weather-" .. weather .. "-ability-" .. ability,
      { speeds = { 7, 5 }, weather = weather, abilities = { ability, ability }, stages = { 1, -1 } }
    )
  end
end
for _, ability in ipairs({ 13, 76 }) do
  for _, hp in ipairs({ 0, 100 }) do
    add("right-weather-suppressor-" .. ability .. "-hp-" .. hp, {
      double = true,
      weather = 7,
      speeds = { 101, 100 },
      abilities = { 0, 33, ability, 0 },
      hps = { 100, 100, hp, 100 },
    })
    add("unused-slot-not-suppressor-" .. ability .. "-hp-" .. hp, {
      double = false,
      weather = 7,
      speeds = { 101, 100 },
      abilities = { 0, 33, ability, 0 },
      hps = { 100, 100, hp, 100 },
    })
  end
end
for _, mode in ipairs({ "ordinary", "link", "frontier", "recorded" }) do
  for _, player in ipairs({ 0, 2 }) do
    add(
      "badge-" .. mode .. "-player-" .. player,
      { double = true, user = 1, target = player, speeds = { 100, 109, 100, 109 }, badge = true, mode = mode }
    )
  end
end
for _, status in ipairs({ 0, 64, 72, 0x80000040, "PAR", "PARALYSIS", "PSN", "SLP" }) do
  add("paralysis-" .. tostring(status), { speeds = { 10, 39 }, statuses = { 0, status } })
end
for _, word in ipairs({ 0, 130, 131, 13106, 13107, 13108, 65534, 65535 }) do
  for _, chance in ipairs({ 0, 1, 20, 100, 255 }) do
    add("claw-word-" .. word .. "-chance-" .. chance, {
      speeds = { 100, 10 },
      effects = { 0, 26 },
      parameters = { 0, chance },
      word = word,
    })
    add("double-claw-word-" .. word .. "-chance-" .. chance, {
      speeds = { 100, 10 },
      effects = { 26, 26 },
      parameters = { chance, chance },
      word = word,
      tie = 1,
    })
  end
end
add("brace-weather-paralysis-flooring", {
  speeds = { 3, 7 },
  effects = { 24, 24 },
  abilities = { 0, 33 },
  weather = 7,
  statuses = { 0, "PAR" },
  stages = { 1, -1 },
})
add(
  "enigma-per-battler",
  { speeds = { 100, 10 }, enigma = true, effects = { 24, 26 }, parameters = { 0, 20 }, word = 0 }
)
add(
  "enigma-threshold",
  { speeds = { 100, 10 }, enigma = true, effects = { 24, 26 }, parameters = { 0, 20 }, word = 13107 }
)
add("priority-is-ignored", { speeds = { 100, 10 }, priorities = { -7, 7 }, expected = 1 })
add("priority-does-not-break-speed-tie", { priorities = { -7, 7 }, expected = 2, tie = 1 })
for user = 0, 3 do
  for target = 0, 3 do
    add("roles-" .. user .. "-" .. target, {
      double = true,
      user = user,
      target = target,
      speeds = { 97, 99, 101, 103 },
      effects = { 24, 0, 26, 0 },
      parameters = { 0, 0, 20, 0 },
      word = 13107,
    })
  end
end
return cases
