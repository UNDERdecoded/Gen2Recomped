-- This exact entry and manifest run on both engines. No engine imports,
-- format switches or engine-specific branches belong in this fixture.
local mod = ...
local world, battle = mod.world, mod.battle
assert(type(world) == "table" and type(battle) == "table", "early handles")
local function refused(value, reason)
  assert(value == nil and type(reason) == "string" and #reason > 0, tostring(reason))
end
refused(world:party())
refused(battle:snapshot())
local no, why = mod:supports("world", "not_a_method")
assert(no == false and type(why) == "string")
assert(mod:supports("content", "pokemon"))
assert(mod:supports("hooks", "evolution.check"))
assert(mod:supports("events", "pokemon.received"))
assert(mod:supports("world", "party"))
-- Known API-3 names are registrable even when this host cannot execute them.
mod.hooks:wrap("render.output", function(next, ctx)
  return next(ctx)
end)
mod.events:on("checkpoint.restored", function() end)
local c = mod.content
assert(c.pokemon:has("MEW"))
assert(c.maps:supports() and c.maps.available)
assert(c.maps:has("ABSENT_MAP") == false)
local map = assert(c.maps:get("PROBE"))
map.width = 99
assert(c.maps:get("PROBE").width == 2)
for id, row in c.maps:each() do
  if id == "api3Probe" then
    row.value = 88
  end
end
assert(c.maps:get("PROBE").width == 2)
local before = assert(c.pokemon:get("MEW"))
assert(before.id == "MEW" and before.baseStats.hp == 100)
assert(before.level1Moves[1] == "POUND")
assert(before.baseStats.special == 100)
assert(c.moves:get("POUND").effect == "NO_ADDITIONAL_EFFECT")
before.baseStats.hp = 222
assert(c.pokemon:get("MEW").baseStats.hp == 100, "detached read")
assert(c.pokemon:patch("MEW", { baseStats = { hp = 101 } }))
assert(c.moves:patch("POUND", { power = 45 }))
assert(c.items:patch("POTION", { price = 123 }))
local found = false
for id, row in c.pokemon:each() do
  if id == "MEW" then
    found = true
    assert(row.baseStats.hp == 101)
  end
end
assert(found)
local report = { species = "MEW", hp = 101, move = "POUND", power = 45, price = 123 }
local function monCheck(mon)
  assert(mon.species == "MEW" and mon.nickname == "Scout" and mon.name == "Scout")
  assert(mon.status == "PSN", "short status")
  assert(type(mon.shiny) == "boolean", "shiny presentation")
  assert(mon.stats.special == 24 and mon.stats.hp == 40, "common stats")
  assert(mon.moves[1].id == "POUND" and mon.moves[1].pp == 30 and mon.moves[1].maxPp == 35)
end
mod.events:on("pokemon.received", function(payload)
  monCheck(payload.mon)
  payload.mon.hp = 1
  report.event = true
end)
mod.hooks:wrap("evolution.check", function(next, game, mon, evolution, trigger)
  monCheck(mon)
  mon.hp, mon.status = 27, "BRN"
  mon.stats.special = 31
  report.hook = true
  report.special = 31
  return next(game, mon, evolution, trigger)
end)
mod.events:on("mod.portable.probe", function(payload)
  report.custom = payload.value
end)
mod.events:emit("mod.portable.probe", { value = 7 })
mod.exports.exercise = function()
  local first = assert(world:party())
  monCheck(first[1])
  first[1].hp = 1
  assert(world:party()[1].hp == 30, "detached party")
  report.party = true
  report.status, report.shiny = first[1].status, first[1].shiny
  assert(world:getFlag("mod:contract.flag") == false)
  assert(world:setFlag("mod:contract.flag", true))
  assert(world:getFlag("mod:contract.flag") == true)
  assert(world:setFlag("mod:contract.flag", false))
  assert(world:getFlag("mod:contract.flag") == false)
  report.flags = true
end
mod.exports.snapshot = function()
  local first = assert(battle:snapshot())
  assert(first.kind == "wild" and first.prompt == "menu")
  monCheck(first.player)
  assert(first.player.hp == 30 and first.player.maxHp == 40)
  assert(type(first.revision) == "number" and first.revision > 0)
  first.player.hp = 1
  assert(battle:snapshot().player.hp == 30, "detached battle snapshot")
  refused(battle:submit({ id = 1, revision = first.revision, kind = "not_an_intent" }))
  report.battle =
    { kind = first.kind, prompt = first.prompt, species = first.player.species, status = first.player.status }
end
mod.exports.late = function()
  local ok, value, reason = pcall(function()
    return c.moves:patch("POUND", { power = 99 })
  end)
  assert(not ok or (value == nil and type(reason) == "string"), "frozen content")
end
mod.exports.world, mod.exports.battle, mod.exports.report = world, battle, report
