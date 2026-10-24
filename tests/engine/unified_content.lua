-- Synthetic extractor-shaped datasets; all mod changes go through Loader.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Manifest = require("src.mods.Manifest")
local Merge = require("src.mods.Merge")
local DELETE = Merge.DELETE
local Registry = require("src.mods.Registry")
local Runtime = require("src.mods.Runtime")
local original = Version.get()
local function raises(fn, fragment)
  return T.raises(fn, fragment, "rejects " .. fragment)
end
local versions = { "red", "crystal", "emerald", "platinum", "black" }
local function fixture(gen)
  local ds = gen >= 4
  local keys = { mon = ds and 25 or gen == 2 and "SPECIES_025" or "PIKACHU",
    into = ds and 26 or gen == 2 and "SPECIES_026" or "RAICHU",
    move = ds and 33 or gen == 2 and "MOVE_033" or "TACKLE",
    item = ds and 17 or gen == 2 and "ITEM_017" or "POTION",
    trainer = ds and 7 or "OPP_PROBE" }
  local stats = { hp = 35, attack = 55, defense = 40, speed = 90, special = 50 }
  if gen > 1 then stats.spatk, stats.spdef = 50, 60 end
  if ds then stats.spAttack, stats.spDefense = 50, 60 end
  local mon = { id = keys.mon, name = "Pikachu", dex = 25, types = { "NORMAL" },
    baseStats = stats, catchRate = 190, baseExp = 82, growthRate = "MEDIUM_FAST",
    level1Moves = { keys.move }, learnset = { { level = 9, move = keys.move } }, tmhm = { keys.move },
    evolutions = { ds and { method = "level", target = keys.into, param = 20, methodId = 4, paramKind = "level" }
      or { method = "LEVEL", species = keys.into, level = 20 } },
    spriteFront = "synthetic-front.png", spriteBack = "synthetic-back.png", frontSize = 7,
    customNative = { sentinel = "retained" } }
  if gen >= 3 then mon.evYield = { speed = 2 }; mon.abilities = { "STATIC" } end
  local into = Merge.deepCopy(mon); into.id, into.name, into.dex, into.evolutions = keys.into, "Raichu", 26, {}
  local move = { id = keys.move, name = "Tackle", type = "NORMAL", power = 35, accuracy = 95, pp = 35,
    effect = "NO_ADDITIONAL_EFFECT", priority = 0, untouchedTarget = 6 }
  if ds then move.class, move.classId, move.typeId, move.gen4Effect = "physical", 0, 0, 0 end
  local item = { id = keys.item, name = "Potion", price = 300, tossable = true, heldEffect = 27 }
  local party = { { species = keys.mon, level = 12, item = gen > 1 and keys.item or nil,
    moves = { keys.move }, customIV = 31 } }
  local trainer = { id = keys.trainer, name = "Probe", parties = { party }, baseMoney = 10, aiMods = { 9 } }
  if ds then trainer.party = party; trainer.nativeFlag = 17 end
  local grass = { rate = 20, slots = { { species = keys.mon, level = 5 }, { species = keys.into, level = 7 } },
    buckets = { 128, 256 } }
  if gen == 2 then
    grass.byTime = { morn = Merge.deepCopy(grass), nite = Merge.deepCopy(grass) }
    grass.byTime.nite.rate = 10
  elseif gen == 3 then
    grass.rateMax, grass.bucketSpan, grass.buckets = 180, 100, { 50, 100 }
    grass.slots[1].level, grass.slots[1].min, grass.slots[1].max = nil, 4, 6
  end
  local data = { pokemon = { [keys.mon] = mon, [keys.into] = into }, moves = { [keys.move] = move },
    items = { [keys.item] = item }, trainers = { [keys.trainer] = trainer },
    encounters = { ROUTE_PROBE = { grass = grass } }, constants = { generation = gen }, audio = {} }
  if ds then
    data.items.ITEM_017 = item
    data.encounters = { [1] = { grassRate = 20, grass = { { species = keys.mon, level = 5, chance = 100 } } } }
  end
  return data, keys
end
local function run(gen, body, format, extra, supplied, selected)
  Version.set(selected or versions[gen])
  local data, keys = fixture(gen)
  data = supplied or data
  local mods = { probe = { entry = body, format = format or "unified" } }
  for id, spec in pairs(extra or {}) do mods[id] = spec end
  local loader
  local fs = {
    read = function(path)
      local id = path:match("^mods/([^/]+)/manifest.json$")
      local mod = id and mods[id]
      if mod then return ('{"id":"%s","name":"Probe","version":"1.0.0","api":2,"entry":"main.lua","content_format":"%s","priority":%d}')
        :format(id, mod.format or "unified", mod.priority or 0) end
    end,
    getDirectoryItems = function(path)
      if path ~= "mods" then return {} end
      local out = {}; for id in pairs(mods) do out[#out + 1] = id end; return out
    end,
    getInfo = function(path)
      if path:match("main.lua$") or path:match("manifest.json$") then return { type = "file" } end
      if path == "mods" or path:match("^mods/[^/]+$") then return { type = "directory" } end
    end,
    load = function(path)
      local id = path:match("^mods/([^/]+)/main.lua$")
      if mods[id] then return function(api) return mods[id].entry(api, loader) end end
    end,
  }
  loader = Loader.new({ fs = fs, dev = false })
  loader._game = function() error("content must not load Game") end
  loader:load(data)
  return loader.apis.probe, loader, data, keys
end
local function ok(value, reason) assert(value, reason) end
local function ops(registry) local n = 0; for _, rows in pairs(registry.ops) do n = n + #rows end; return n end
local function dataOnly(v)
  if type(v) == "function" then return "<function>" end
  if type(v) ~= "table" then return v end
  local out = {}; for k, sub in pairs(v) do out[k] = dataOnly(sub) end; return out
end

-- Native defaults, manifest rejection and registry numeric-ID confinement.
raises(function() Manifest.validate({ id = "bad", name = "bad", version = "1", entry = "main.lua", api = 1,
  content_format = "unified" }, "mods/bad") end, "unified content requires mod API 2")
raises(function() Manifest.validate({ id = "bad", name = "bad", version = "1", entry = "main.lua", api = 2,
  content_format = "unifed" }, "mods/bad") end, "content_format must be native or unified")
raises(function() Registry.new("legacy"):patch(25, {}) end, "id is required")

local savedLove = love; love = nil
for gen = 1, 5 do
  local api, loader, data, keys = run(gen, function(mod)
    T.eq(mod.contentFormat, "unified", "manifest selects unified content in entry")
    if mod.supports then
      T.eq(mod:supports("content", "encounters"), gen <= 3, "host query follows selected content format")
      T.eq(mod:supports("hooks", "battle.damage"), true, "other capability surfaces retain host query")
    end
    local pokemon = assert(mod.content.pokemon:get("PIKACHU"))
    T.eq(pokemon.id, "PIKACHU", "canonical species identity")
    T.eq(pokemon.level1Moves[1], "TACKLE", "canonical starting move")
    T.eq(pokemon.evolutions[1].species, "RAICHU", "canonical evolution target")
    T.eq(pokemon.baseStats.special, 50, "canonical Special")
    T.eq(pokemon.baseStats.specialDefense, gen > 1 and 60 or nil, "split Special retained")
    pokemon.baseStats.hp = 99
    pokemon.native.customNative.sentinel = "local"
    T.eq(mod.content.pokemon:get("PIKACHU").baseStats.hp, 35, "read is detached")
    local _, why = mod.content.pokemon:patch("PIKACHU", pokemon)
    T.check(why and why:find("read%-only"), "native diagnostics cannot be written")
    ok(mod.content.pokemon:patch("PIKACHU", { baseStats = { special = 70 } }))
    ok(mod.content.moves:patch("TACKLE", { power = 45 }))
    ok(mod.content.items:patch("POTION", { price = 100 }))
    local trainerId = gen >= 4 and "7" or "OPP_PROBE"
    local trainer = assert(mod.content.trainers:get(trainerId))
    T.eq(trainer.parties[1][1].species, "PIKACHU", "canonical trainer species")
    T.eq(trainer.parties[1][1].moves[1], "TACKLE", "canonical trainer moves")
    trainer.parties[1][1].level = 18
    ok(mod.content.trainers:patch(trainerId, { parties = trainer.parties }))
    local _, whyMissing = mod.content.moves:patch("ABSENT", { power = 5 })
    T.check(whyMissing ~= nil, "absent patch declines with reason")
    local encounter = mod.content.encounters
    if gen <= 3 then
      T.check(encounter:supports(), "GB/GBA encounter adapter available")
      local row = assert(encounter:get("ROUTE_PROBE"))
      row.grass.slots[1].species = "RAICHU"
      ok(encounter:patch("ROUTE_PROBE", { grass = { slots = row.grass.slots } }))
    else
      local available, why = encounter:supports()
      T.check(available == false and type(why) == "string", "DS encounters explicitly unsupported")
      local result, err = encounter:patch("1", { grass = { rate = 10 } })
      T.check(result == nil and type(err) == "string", "DS encounter writes decline safely")
    end
  end)
  T.eq(loader.mods.probe.state, "loaded", versions[gen] .. ": real entry/merge succeeds")
  T.eq(#loader.errors, 0, versions[gen] .. ": no cross-reference errors")
  T.eq(data.pokemon[keys.mon].baseStats.special, 70, "native Special alias updated")
  T.eq(data.pokemon[keys.mon].baseStats.spdef, gen > 1 and 70 or nil, "native Special Defense updated")
  T.eq(data.pokemon[keys.mon].customNative.sentinel, "retained", "native extensions survive")
  T.eq(data.moves[keys.move].power, 45, "native move power updated")
  T.eq(data.moves[keys.move].untouchedTarget, 6, "native move targeting preserved")
  T.eq(data.items[keys.item].price, 100, "native item price updated")
  T.eq(data.items[keys.item].heldEffect, 27, "native held effect preserved")
  T.eq(data.trainers[keys.trainer].parties[1][1].level, 18, "native trainer party updated")
  T.eq(data.trainers[keys.trainer].parties[1][1].customIV, 31, "native trainer metadata preserved")
  T.eq(api.content.pokemon:get("PIKACHU").baseStats.special, 70, "read works after merge/freeze")
  if gen >= 4 then
    T.eq(data.items.ITEM_017.price, 100, "DS item string alias updated together with numeric ID")
    T.eq(api.content.items:get("POTION").price, 100, "DS alias identity survives merge")
    T.same(data.trainers[keys.trainer].party, data.trainers[keys.trainer].parties[1], "DS party aliases stay synchronized")
  end
  raises(function() api.content.moves:patch("TACKLE", { power = 99 }) end, "frozen")
  local count = 0
  for id, row in api.content.items:each() do count = count + 1; T.eq(id, row.id, "iterator canonical ID") end
  T.eq(count, 1, "iterator coalesces native aliases")
end
love = savedLove or require("tests.love_stub")

-- No-op canonical round trips preserve every native field and native format.
for gen = 1, 5 do
  local _, baseline = run(gen, function() end, "native")
  local _, canonical, data = run(gen, function(mod)
    local kinds = { "pokemon", "moves", "items", "trainers" }
    if gen <= 3 then kinds[#kinds + 1] = "encounters" end
    for _, kind in ipairs(kinds) do
      for id, record in mod.content[kind]:each() do ok(mod.content[kind]:override(id, record)) end
    end
  end)
  T.eq(canonical.mods.probe.state, "loaded", "round-trip load succeeds")
  T.same(dataOnly(data), dataOnly(baseline.baseData), versions[gen] .. ": full native round-trip parity")
end

-- Unsupported/malformed operations must append nothing and preserve input.
for gen = 1, 5 do
  local _, loader = run(gen, function(mod)
    local pokemon = mod.content.pokemon
    local before = mod.content.pokemon:get("PIKACHU")
    local invalid = { baseStats = { hp = 0 } }
    raises(function() pokemon:patch("PIKACHU", invalid) end, "invalid")
    T.eq(invalid.baseStats.hp, 0, "invalid caller payload untouched")
    raises(function() pokemon:patch("PIKACHU", { base_stats = {} }) end, "unknown")
    raises(function() pokemon:patch("PIKACHU", { baseStats = DELETE }) end, "required")
    raises(function() pokemon:patch("PIKACHU", { learnset = { [2] = { level = 4, move = "TACKLE" } } }) end, "contiguous")
    local cyclic = {}; cyclic.foo = cyclic
    raises(function() pokemon:patch("PIKACHU", cyclic) end, "cyclic")
    raises(function() mod.content.moves:patch("TACKLE", { power = 0 / 0 }) end, "non-finite")
    local result, reason = pokemon:patch("PIKACHU", { level1Moves = { "MISSING" } })
    T.check(result == nil and reason:find("unknown moves ID", 1, true), "unknown cross-generation reference refuses")
    T.same(pokemon:get("PIKACHU"), before, "failed operations leave effective record intact")
  end)
  T.eq(loader.mods.probe.state, "loaded", "caught refusals do not disable mod")
  T.eq(ops(loader.content.pokemon), 0, "refused operations leave no Pokemon op log")
end

-- Empty lists, append/prepend, DELETE and stacking with native mods.
local _, lists, data = run(2, function(mod)
  ok(mod.content.pokemon:patch("PIKACHU", { learnset = {} }))
  T.eq(#mod.content.pokemon:get("PIKACHU").learnset, 0, "empty list clears immediately")
  ok(mod.content.pokemon:patch("PIKACHU", { learnset = { __append = { { level = 10, move = "TACKLE" } } } }))
  ok(mod.content.pokemon:patch("PIKACHU", { learnset = { __prepend = { { level = 5, move = "TACKLE" } } } }))
  ok(mod.content.pokemon:patch("PIKACHU", { tmhm = mod.DELETE }))
end, "unified", {
  earlier = { format = "native", priority = -1, entry = function(mod)
    mod.content.pokemon:patch("SPECIES_025", { baseStats = { attack = 80 } })
  end },
  later = { format = "native", priority = 1, entry = function(mod)
    mod.content.pokemon:patch("SPECIES_025", { baseStats = { defense = 75 } })
  end },
})
T.eq(lists.mods.probe.state, "loaded", "list and native stacking load")
T.eq(data.pokemon.SPECIES_025.learnset[1].level, 5, "prepend before append")
T.eq(data.pokemon.SPECIES_025.learnset[2].level, 10, "append retains order")
T.eq(#data.pokemon.SPECIES_025.tmhm, 0, "DELETE materializes empty native list")
T.eq(data.pokemon.SPECIES_025.baseStats.attack, 80, "earlier native patch preserved")
T.eq(data.pokemon.SPECIES_025.baseStats.defense, 75, "later native patch preserved")

-- An entry failure rolls every canonical/native alias operation back.
for gen = 1, 5 do
  local _, loader, data, keys = run(gen, function(mod)
    ok(mod.content.items:patch("POTION", { price = 1 }))
    ok(mod.content.pokemon:patch("PIKACHU", { baseStats = { hp = 100 } }))
    error("intentional entry failure")
  end)
  T.eq(loader.mods.probe.state, "failed", "entry failure attributed")
  T.eq(data.items[keys.item].price, 300, "failed item edit rolled back")
  T.eq(data.pokemon[keys.mon].baseStats.hp, 35, "failed species edit rolled back")
  if gen >= 4 then T.eq(data.items.ITEM_017.price, 300, "failed DS alias edit rolled back") end
end

-- Native consumers see the result, rather than merely passing schema checks.
local _, nativeLoader, data, keys = run(2, function(mod)
  ok(mod.content.pokemon:patch("PIKACHU", { baseStats = { specialAttack = 90, specialDefense = 95 } }))
  ok(mod.content.trainers:patch("OPP_PROBE", { parties = { { { species = "RAICHU", level = 18, moves = { "TACKLE" } } } } }))
  ok(mod.content.encounters:patch("ROUTE_PROBE", { grass = { rate = 32,
    slots = { { species = "RAICHU", level = 8 }, { species = "PIKACHU", level = 9 } } } }))
end)
T.eq(nativeLoader.mods.probe.state, "loaded", "consumer probe loads")
local Pokemon = require("src.pokemon.Pokemon")
local mon = Pokemon.new(data, keys.mon, 10, function(a) return a end)
T.check(mon.stats.spatk ~= nil and mon.stats.spdef ~= nil, "native Pokemon constructor keeps split stat model")
local Encounter = require("src.world.Encounter")
for _, time in ipairs({ "MORNING", "DAY", "NIGHT" }) do
  local tableAtTime = Encounter.atTime(data.encounters.ROUTE_PROBE.grass, time)
  local encountered = Encounter.rollTable(tableAtTime, function(a) return a end)
  T.eq(encountered.species, keys.into, time .. ": native encounter chooses translated species")
  T.eq(encountered.level, 8, time .. ": native encounter uses translated level")
end
local Battle = require("src.battle.BattleState")
local game = { data = data, save = { options = {}, player = {}, party = {} } }
local party = Battle.buildTrainerParty(game, keys.trainer, 1, data.trainers[keys.trainer].parties[1])
T.eq(party[1].species, keys.into, "native trainer builder receives translated species")
T.eq(party[1].level, 18, "native trainer builder receives translated level")

-- Every registered version selects the same format using its own host
-- generation. The facade captures that generation before entry execution.
for _, version in ipairs(Version.ORDER) do
  local gen = Version.generation(version)
  local _, loader, data, key = run(gen, function(mod)
    T.eq(mod.gameVersion, version, "selected host identity: " .. version)
    mod.generation, mod.host.generation = 99, 99
    Version.set("red")
    ok(mod.content.moves:patch("TACKLE", { power = 42 }))
  end, "unified", nil, nil, version)
  T.eq(loader.mods.probe.state, "loaded", version .. ": captured host format works")
  T.eq(data.moves[key.move].power, 42, version .. ": same portable patch reaches native data")
end

-- Canonical IDs are based on this ROM's names, not official numeric IDs.
local hacked = fixture(2)
hacked.pokemon.SPECIES_777 = hacked.pokemon.SPECIES_025
hacked.pokemon.SPECIES_025 = nil
local _, hackLoader, hackData = run(2, function(mod)
  ok(mod.content.pokemon:patch("PIKACHU", { baseStats = { hp = 65 } }))
end, "unified", nil, hacked)
T.eq(hackLoader.mods.probe.state, "loaded", "relocated ROM-hack species ID resolves")
T.eq(hackData.pokemon.SPECIES_777.baseStats.hp, 65, "no hard-coded National Dex lookup")

local ambiguous = fixture(2)
ambiguous.pokemon.SPECIES_999 = Merge.deepCopy(ambiguous.pokemon.SPECIES_025)
local _, ambiguity = run(2, function(mod)
  local value, why = mod.content.pokemon:get("PIKACHU")
  T.check(value == nil and why:find("ambiguous", 1, true), "ambiguous name has a diagnostic")
  local changed, reason = mod.content.pokemon:patch("PIKACHU", { catchRate = 1 })
  T.check(changed == nil and reason:find("ambiguous", 1, true), "ambiguous writes cannot choose a record")
  raises(function() mod.content.pokemon:each() end, "ambiguous")
end, "unified", nil, ambiguous)
T.eq(ops(ambiguity.content.pokemon), 0, "ambiguity leaves no ops")

-- New string-key records can be registered without changing legacy schema
-- behavior. Existing numeric records can be patched, not allocated blindly.
for gen = 1, 5 do
  local _, loader, data = run(gen, function(mod)
    local new = { id = "CUSTOM_ITEM", name = "Custom item", price = 42 }
    local saved = Merge.deepCopy(new)
    local changed, why = mod.content.items:register("CUSTOM_ITEM", new)
    if gen < 4 then
      T.check(changed == true, "string-key item registration succeeds")
      T.eq(mod.content.items:get("CUSTOM_ITEM").price, 42, "registration immediately readable")
      raises(function() mod.content.items:register("CUSTOM_ITEM", new) end, "already registered")
    else T.check(changed == nil and why:find("storage", 1, true), "DS allocation declines without a native slot") end
    T.same(new, saved, "registration input remains detached")
    local payload = { price = 123 }
    ok(mod.content.items:patch("POTION", payload))
    payload.price = 999
    T.eq(mod.content.items:get("POTION").price, 123, "later caller mutation cannot edit op log")
    local record = assert(mod.content.pokemon:get("PIKACHU"))
    local changed, reason = mod.content.pokemon:patch("PIKACHU", { baseStats = { specialAttack = 99 } })
    if gen == 1 then
      T.check(changed == nil and reason:find("split", 1, true), "Gen 1 split stat rejected atomically")
      T.same(mod.content.pokemon:get("PIKACHU"), record, "rejected split retains native record")
    else T.eq(changed, true, "later generation accepts split stat") end
    raises(function() mod.content.pokemon:patch("PIKACHU", { types = mod.DELETE }) end, "cannot be deleted")
    raises(function() mod.content.pokemon:patch("PIKACHU", { baseStats = { specialDefense = mod.DELETE } }) end, "cannot delete")
  end)
  T.eq(loader.mods.probe.state, "loaded", "registration/refusal cases survive load")
  T.eq(data.items.CUSTOM_ITEM and data.items.CUSTOM_ITEM.price, gen < 4 and 42 or nil, "only supported registrations reach Data")
end

-- Probability units are uniform (a fraction out of 256) and lossless.
local _, rates, rateData = run(3, function(mod)
  local before = mod.content.encounters:get("ROUTE_PROBE")
  T.eq(before.grass.rate, 20 * 256 / 180, "GBA rate is projected into common units")
  local changed, why = mod.content.encounters:patch("ROUTE_PROBE", { grass = { rate = 31 } })
  T.check(changed == nil and why:find("representable", 1, true), "unrepresentable GBA rate rejected")
  T.same(mod.content.encounters:get("ROUTE_PROBE"), before, "rejected rate leaves slots/weights intact")
  ok(mod.content.encounters:patch("ROUTE_PROBE", { grass = { rate = 30 * 256 / 180 } }))
end)
T.eq(rateData.encounters.ROUTE_PROBE.grass.rate, 30, "representable rate maps exactly to native span")

-- Native DS parser output is edited through the same facade. Its class
-- selector and numeric evolution target remain consistent for real consumers.
local parsed = fixture(4)
local bytes = { 0, 0, 0, 35, 0, 95, 35, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local chars = {}; for i, byte in ipairs(bytes) do chars[i] = string.char(byte) end
parsed.moves[33] = assert(require("src.import.Gen4Moves").parse(table.concat(chars)))
parsed.moves[33].id, parsed.moves[33].name = 33, "Tackle"
local _, parsedLoader, parsedData = run(4, function(mod)
  ok(mod.content.moves:patch("TACKLE", { category = "special", power = 50 }))
  ok(mod.content.pokemon:patch("PIKACHU", { evolutions = { { method = "LEVEL", level = 15, species = "RAICHU" } } }))
end, "unified", nil, parsed)
T.eq(parsedLoader.mods.probe.state, "loaded", "native parser-produced data accepts canonical edits")
T.eq(parsedData.moves[33].class, "special", "native DS class updated")
T.eq(parsedData.moves[33].classId, 1, "native DS class selector updated")
local Evolution = require("src.pokemon.Evolution")
local target = Evolution.pendingFor({ data = parsedData, save = { options = {} } },
  { species = 25, level = 15 }, { kind = "levelup" })
T.eq(target, 26, "native evolution consumer follows translated numeric target")

-- Removing a target retains post-merge reference checks, including numeric
-- trainer references and the otherwise hidden Gen 2 night slot table.
for _, gen in ipairs({ 2, 4 }) do
  local _, loader = run(gen, function(mod) ok(mod.content.pokemon:remove("RAICHU")) end)
  T.check(#loader.errors > 0, "removed native evolution/encounter target is diagnosed")
  T.check(table.concat(loader.errors, "\n"):find("probe", 1, true) ~= nil, "reference failure attributed to removing mod")
end
local _, removal, removedData = run(4, function(mod)
  local trainer = mod.content.trainers:get("7")
  trainer.parties[1][1].item = nil
  ok(mod.content.trainers:patch("7", { parties = trainer.parties }))
  ok(mod.content.items:remove("POTION"))
  T.eq(mod.content.items:has("POTION"), false, "tombstone immediately hidden in canonical view")
end)
T.eq(#removal.errors, 0, "valid alias removal has no dangling reference")
T.check(removedData.items[17] == nil and removedData.items.ITEM_017 == nil, "numeric/string aliases tombstoned together")

-- Preferences must still choose original patch operations, not snapshots of
-- earlier mods' changes captured into an adapter's replacement record.
local _, arbitration, arbitrationData = run(2, function(mod, loader)
  ok(mod.content.pokemon:patch("PIKACHU", { baseStats = { hp = 75 } }))
  loader.content.pokemon:preferOwner("SPECIES_025", "probe")
end, "unified", {
  earlier = { format = "native", priority = -1, entry = function(mod)
    mod.content.pokemon:patch("SPECIES_025", { baseStats = { attack = 80 } })
  end },
})
T.eq(arbitrationData.pokemon.SPECIES_025.baseStats.hp, 75, "preferred canonical patch remains")
T.eq(arbitrationData.pokemon.SPECIES_025.baseStats.attack, 55, "set-aside native patch does not leak through a snapshot")

-- The extractor keeps abbreviated GBA type keys, not the Gen 1 keys.
local types = fixture(3)
types.type_chart = { types = { NORMAL = { category = "physical" }, PSYCHC = { category = "special" } }, matchups = {} }
types.moves.TACKLE.type = "PSYCHC"
local _, typeLoader, typeData = run(3, function(mod)
  T.eq(mod.content.moves:get("TACKLE").type, "PSYCHIC_TYPE", "abbreviated GBA type is canonical on read")
  ok(mod.content.moves:patch("TACKLE", { type = "PSYCHIC_TYPE" }))
  ok(mod.content.pokemon:patch("PIKACHU", { types = { "PSYCHIC_TYPE" } }))
end, "unified", nil, types)
T.eq(#typeLoader.errors, 0, "canonical type resolves to actual native registry")
T.eq(typeData.moves.TACKLE.type, "PSYCHC", "native abbreviated move type retained")
T.eq(typeData.pokemon.PIKACHU.types[1], "PSYCHC", "species type references translated")

-- A pre-existing unmapped native move selector must not become a dangling
-- registry ID merely because a balance mod changes its power.
local opaque = fixture(4)
opaque.moves[33].effect, opaque.moves[33].gen4Effect = 999, 999
local _, opaqueLoader, opaqueData = run(4, function(mod)
  local record = mod.content.moves:get("TACKLE")
  T.check(record.effect == nil and record.native.effect == 999, "opaque selector exposed only in native diagnostics")
  ok(mod.content.moves:patch("TACKLE", { power = 65 }))
end, "unified", nil, opaque)
T.eq(#opaqueLoader.errors, 0, "untouched numeric effect selector has no false reference error")
T.eq(opaqueData.moves[33].gen4Effect, 999, "opaque native selector survives patch")

-- Default/explicit native mode continues to expose live native records.
local default = Manifest.validate({ id = "native", name = "Native", version = "1", entry = "main.lua", api = 2 }, "mods/native")
T.eq(default.content_format, "native", "omitted format remains native")
local _, native = run(2, function(mod)
  T.eq(mod.contentFormat, "native", "native manifest uses original facade")
  T.check(mod.content.pokemon:get("PIKACHU") == nil, "native facade does not invent aliases")
  mod.content.pokemon:patch("SPECIES_025", { baseStats = { attack = 99 } })
end, "native")
T.eq(native.baseData.pokemon.SPECIES_025.baseStats.attack, 99, "native patch still has original behavior")

-- Full read/modify/write of one time must not flatten the others to DAY.
local timeData = fixture(2)
timeData.encounters.ROUTE_PROBE.grass.byTime.morn.rate = 5
timeData.encounters.ROUTE_PROBE.grass.byTime.morn.slots[1].level = 2
local _, timeLoader, editedTimes = run(2, function(mod)
  local record = mod.content.encounters:get("ROUTE_PROBE")
  record.grass.times.NITE.slots[1].level = 11
  ok(mod.content.encounters:override("ROUTE_PROBE", record))
end, "unified", nil, timeData)
T.eq(timeLoader.mods.probe.state, "loaded", "time-specific detached edit succeeds")
T.eq(editedTimes.encounters.ROUTE_PROBE.grass.rate, 20, "time edit preserves day rate")
T.eq(editedTimes.encounters.ROUTE_PROBE.grass.byTime.morn.rate, 5, "time edit preserves distinct morning rate")
T.eq(editedTimes.encounters.ROUTE_PROBE.grass.byTime.morn.slots[1].level, 2, "time edit preserves distinct morning slots")
T.eq(editedTimes.encounters.ROUTE_PROBE.grass.byTime.nite.slots[1].level, 11, "time edit changes only requested night slot")

local _, mixedTimeLoader, mixedTimeData = run(2, function(mod)
  local record = mod.content.encounters:get("ROUTE_PROBE")
  record.grass.rate = 30
  record.grass.times.NITE.slots[1].level = 12
  ok(mod.content.encounters:override("ROUTE_PROBE", record))
end)
T.eq(mixedTimeData.encounters.ROUTE_PROBE.grass.byTime.nite.rate, 30, "inherited night rate cannot undo shared edit")
T.eq(mixedTimeData.encounters.ROUTE_PROBE.grass.byTime.nite.slots[1].level, 12, "explicit night slot edit survives shared rate")

local _, conflictingStats = run(2, function(mod)
  raises(function() mod.content.pokemon:patch("PIKACHU", { baseStats = { special = 50, specialAttack = 80 } }) end, "conflicting")
end)
T.eq(ops(conflictingStats.content.pokemon), 0, "conflicting stat aliases leave no ops")

-- The unsupported DS writer must not disable native reference auditing.
local seasonal = fixture(5)
seasonal.encounters[1].seasons = { winter = { grass = { { species = 26, level = 8, chance = 100 } } } }
local _, seasonalLoader = run(5, function(mod)
  ok(mod.content.pokemon:patch("PIKACHU", { evolutions = {} }))
  ok(mod.content.pokemon:remove("RAICHU"))
end, "unified", nil, seasonal)
T.check(table.concat(seasonalLoader.errors, "\n"):find("seasons.winter.grass", 1, true) ~= nil,
  "DS seasonal encounter target is included in removal diagnostics")

-- Class item references use the same canonical boundary as party item refs.
for gen = 1, 3 do
  local input, keys = fixture(gen)
  if gen == 3 then
    input.items.ITEM_013, input.items.POTION = input.items.POTION, nil
    input.items.ITEM_013.id = "ITEM_013"
    input.trainers[keys.trainer].parties[1][1].item = "ITEM_013"
    keys.item = "ITEM_013"
  end
  local api, loader, data = run(gen, function(mod, loading)
    local handle = mod.content.ai_classes
    local row = handle:register("AI_PORTABLE", { kind = "class", uses = 1, item = "POTION" })
    T.eq(row.item, "POTION", "class register result uses canonical item")
    row.uses = 99
    T.eq(handle:get("AI_PORTABLE").uses, 1, "class register result is detached")
    local before = ops(loading.content.ai_classes)
    local value, reason = handle:patch("AI_PORTABLE", { item = "UNKNOWN_ITEM" })
    T.eq(value, nil, "unknown class item is refused before a write")
    T.check(reason:find("unknown items ID", 1, true) ~= nil, "unknown class item explains refusal")
    T.eq(ops(loading.content.ai_classes), before, "unknown class item records no operation")
    raises(function() handle:patch("AI_PORTABLE", { uses = math.huge }) end, "non-finite")
    local cyclic = {}; cyclic.item = cyclic
    raises(function() handle:patch("AI_PORTABLE", cyclic) end, "cyclic record")
    handle:patch("AI_PORTABLE", { item = DELETE })
    T.eq(handle:get("AI_PORTABLE").item, nil, "class optional item can be deleted")
    handle:override("AI_PORTABLE", { kind = "class", uses = 2, item = "POTION" })
    for id, iterated in handle:each() do
      if id == "AI_PORTABLE" then iterated.item = "UNKNOWN_ITEM" end
    end
    T.eq(handle:get("AI_PORTABLE").item, "POTION", "class iteration is detached")
  end, "unified", nil, Merge.deepCopy(input))
  T.eq(#loader.errors, 0, "canonical class reference passes native validation")
  T.eq(data.ai_classes.AI_PORTABLE.item, keys.item, "native class consumer receives physical item key")
  raises(function() api.content.ai_classes:patch("AI_PORTABLE", { item = "POTION" }) end, "frozen")
  local _, failed, rolledBack = run(gen, function(mod)
    mod.content.ai_classes:register("AI_ROLLBACK", { uses = 1, item = "POTION" })
    error("intentional class entry failure")
  end, "unified", nil, Merge.deepCopy(input))
  T.eq(failed.mods.probe.state, "failed", "class entry failure attributed")
  T.eq(rolledBack.ai_classes.AI_ROLLBACK, nil, "class registration rolls back with failed owner")
  local _, removed = run(gen, function(mod)
    mod.content.ai_classes:register("AI_DANGLING", { uses = 1, item = "POTION" })
    mod.content.items:remove("POTION")
  end, "unified", nil, Merge.deepCopy(input))
  T.check(#removed.errors > 0, "class item retains native dangling-reference diagnostics")
  local _, legacy, legacyData = run(gen, function(mod)
    mod.content.ai_classes:register("AI_NATIVE", { uses = 1, item = keys.item })
  end, "native", nil, Merge.deepCopy(input))
  T.eq(#legacy.errors, 0, "legacy native class references still load")
  T.eq(legacyData.ai_classes.AI_NATIVE.item, keys.item, "legacy class item key is unchanged")
end

Version.set(original)
T.finish("unified content")
