package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
local E = require("src.mods.UnifiedEffects")
local C = require("src.mods.MoveEffectContract")
local Native = require("src.battle.MoveEffects").RECORDS
local function registered(id)
  return Native[id] ~= nil
end
local accepted = 0
for id, bindings in pairs(C.bindings) do
  for g, row in pairs(bindings) do
    local gen = tonumber(g)
    local old = { id = row.semantic == 37 and "REST" or row.semantic == 130 and "SONICBOOM" or "POUND" }
    local plan, why = E.write(id, gen, old, registered)
    if plan then
      accepted = accepted + 1
      T.check(registered(plan.effect), "accepted effect has actual handler " .. g .. ":" .. id)
      if gen > 1 then
        plan.effectChance = plan.probability and math.floor(plan.probability * 256 / 100 + 0.5)
      end
      T.eq(
        E.read(plan.effect, gen, plan),
        ({ HIT = "NO_ADDITIONAL_EFFECT", SLEEP = "SLEEP_EFFECT" })[id] or id,
        "authored canonical effect read " .. g .. ":" .. id
      )
    else
      T.check(type(why) == "string", "unrepresentable mapping has reason")
    end
  end
end
T.check(accepted > 300, "reference matrix exercises hundreds of native bindings")
local Contract = require("tests.api3_contract.effects")
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared effect contract: " .. tostring(why))
end
for gen = 1, 3 do
  local custom = assert(E.write("mod:custom", gen, nil, function(id)
    return id == "mod:custom"
  end))
  T.eq(custom.effect, "mod:custom", "registered custom native effect selected")
  T.eq(E.read(custom.effect, gen, custom), "mod:custom", "custom canonical identity")
  T.eq(E.write("unknown", gen, nil, registered), nil, "unknown handler refused")
  T.eq(E.write("native:" .. gen .. ":made_up", gen, nil, registered), nil, "forged opaque effect refused")
  T.eq(
    E.write("native:" .. gen .. ":unhandled", gen, { effect = "unhandled" }, registered).effect,
    "unhandled",
    "original opaque identity retained"
  )
end
for _, id in ipairs({
  "FOLLOW_ME",
  "HELPING_HAND",
  "MAGIC_COAT",
  "SNATCH",
  "IMPRISON",
  "ASSIST",
  "NATURE_POWER",
  "SECRET_POWER",
}) do
  T.eq(E.write(id, 3, nil, registered), nil, "missing native Gen3 handler refused " .. id)
end
for _, v in ipairs({ "gold", "firered" }) do
  Version.set(v)
  local gen = Version.generation()
  local plan = assert(E.write("SPECIAL_UP1_EFFECT", gen, { id = "POUND" }, registered))
  local user = { name = "TEST", isPlayer = true, mon = { hp = 20, stats = { hp = 20 } }, stages = {} }
  local target = { name = "TARGET", mon = { hp = 20, stats = { hp = 20 } }, stages = {} }
  Native[plan.effect].run({ battle = { data = {} }, user = user, target = target, move = plan })
  T.eq(user.stages.spatk, 1, "actual handler raises Special Attack")
  T.eq(user.stages.special, nil, "actual handler avoids Gen1 Special stage")
  T.eq(user.stages.spdef, nil, "actual handler does not raise Special Defense")
  plan = assert(E.write("SPECIAL_DOWN_SIDE_EFFECT", gen, { id = "POUND" }, registered))
  plan.effectChance = 85
  Native[plan.effect].run({ battle = {
    data = {},
    rng = function()
      return 0
    end,
  }, user = user, target = target, move = plan })
  T.eq(target.stages.spdef, -1, "actual handler lowers Special Defense")
  plan = assert(E.write("BURN_SIDE_EFFECT1", gen, { id = "POUND" }, registered))
  plan.effectChance = math.floor(plan.probability * 256 / 100 + 0.5)
  plan.id, plan.type = "POUND", "FIRE"
  local battle = {
    data = {},
    rng = function()
      return 25
    end,
  }
  Native[plan.effect].run({ battle = battle, user = user, target = target, move = plan })
  T.eq(target.mon.status, "BRN", "native burn lands below converted threshold")
  target.mon.status = nil
  battle.rng = function()
    return 26
  end
  Native[plan.effect].run({ battle = battle, user = user, target = target, move = plan })
  T.eq(target.mon.status, nil, "native burn misses at converted threshold")
end
for gen = 2, 3 do
  local old = { id = "POUND", effect = "BURN_SIDE_EFFECT1", effectChance = 27 }
  local public = E.read(old.effect, gen, old)
  local plan, changed = E.write(public, gen, old, registered)
  T.eq(plan.effect, old.effect, "original raw effect roundtrip")
  T.eq(changed, false, "roundtrip does not rewrite original odds")
  T.eq(E.chance(old, gen), 11, "native fraction projected to whole percent")
  T.eq(
    E.write("NO_ADDITIONAL_EFFECT", 4, old, registered),
    nil,
    "later generation changing effect still unavailable"
  )
  T.eq(E.read(999, 4, {}), nil, "DS opaque selector retains diagnostic-only behavior")
end
-- Registry operations use the adapter before journaling; refusals are atomic.
local function load(gen, entry, odds)
  Version.set(gen == 1 and "red" or gen == 2 and "gold" or "firered")
  local data = require("tests.api3_contract.run").dataFor("gen2", gen)
  local loader
  local fs = {
    read = function(path)
      if path:match("manifest.json$") then
        return '{"id":"probe","name":"Probe","version":"1.0.0","api":3,"games":["gen1","gen2","gen3"],"entry":"main.lua"}'
      end
    end,
    getInfo = function(path)
      if path:match("^mods/probe/.+%.%w+$") then
        return { type = "file" }
      end
      if path == "mods" or path == "mods/probe" then
        return { type = "directory" }
      end
    end,
    getDirectoryItems = function(path)
      return path == "mods" and { "probe" } or {}
    end,
    load = function()
      return function(api)
        entry(api, loader, data)
      end
    end,
  }
  data.moves.POUND.effect = "BURN_SIDE_EFFECT1"
  data.moves.POUND.effectChance = odds or 27
  if gen == 3 then
    data.moves.POUND.gen3Effect = 4
    data.moves.POUND.secondaryChance = 11
  end
  loader = require("src.mods.Loader").new({ fs = fs, dev = false, generation = gen, version = Version.get() })
  loader._game = function()
    error("content must not bootstrap Game")
  end
  loader:load(data)
  T.eq(#loader.errors, 0, "public effect mod loads")
  return data
end
for gen = 2, 3 do
  local data = load(gen, function(mod, loader)
    local moves = mod.content.moves
    local row = assert(moves:get("POUND"))
    T.eq(row.secondaryChance, 11, "public native odds projection")
    assert(moves:override("POUND", row))
    T.eq(moves:get("POUND").native.effectChance, 27, "detached override keeps exact native odds")
    local operations = #loader.content.moves.ops.POUND
    T.eq(moves:patch("POUND", { effect = "SNATCH" }), nil, "unimplemented effect operation refused")
    T.eq(#loader.content.moves.ops.POUND, operations, "failed mapping adds no operation")
    T.check(not pcall(function()
      moves:patch("POUND", { secondaryChance = 101 })
    end), "invalid percent rejected")
    T.eq(#loader.content.moves.ops.POUND, operations, "invalid chance adds no operation")
    assert(moves:patch("POUND", { effect = "FLINCH_SIDE_EFFECT2", secondaryChance = 5 }))
    T.eq(moves:get("POUND").effect, "FLINCH_SIDE_EFFECT2", "authored alias persists after odds edit")
    assert(moves:patch("POUND", { effect = "BURN_SIDE_EFFECT1", secondaryChance = 0 }))
    T.eq(moves:get("POUND").secondaryChance, 0, "zero probability retained")
  end)
  local target = { name = "TARGET", mon = { hp = 20, stats = { hp = 20 } }, stages = {} }
  Native[data.moves.POUND.effect].run({
    battle = {
      data = {},
      rng = function()
        return 0
      end,
    },
    user = {},
    target = target,
    move = data.moves.POUND,
  })
  T.eq(target.mon.status, nil, "actual handler respects explicit zero instead of native default")
end
for gen = 2, 3 do
  local data = load(gen, function(mod)
    local moves = mod.content.moves
    assert(moves:override("POUND", assert(moves:get("POUND"))))
    T.eq(
      moves:get("POUND").native._api3EffectChance,
      nil,
      "untouched zero-byte roundtrip preserves native fallback"
    )
    assert(moves:patch("POUND", { secondaryChance = 0 }))
    T.eq(moves:get("POUND").native._api3EffectChance, true, "explicit zero patch arms native zero semantics")
  end, 0)
end
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod = saved[2], saved[3], saved[4], saved[5]
love = saved[6]
T.finish()
