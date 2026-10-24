-- Explicit opt-in definition-record boundary. Native registries and gameplay
-- stay authoritative; no save, callback, world or battle data is rewritten.
local Merge = require("src.mods.Merge")
local Schemas = require("src.mods.Schemas")
local Shapes = require("src.mods.UnifiedSchemas")
local Ids = require("src.mods.UnifiedIds")
local U = {}
local copy, DELETE = Merge.deepCopy, Merge.DELETE
local function unsupported(reason) error({ unsupported = reason }, 0) end
local function check(ok, reason) if not ok then error("invalid unified content: " .. reason, 0) end end
local function equal(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}; if seen[a] == b then return true end; seen[a] = b
  for k, v in pairs(a) do if not equal(v, b[k], seen) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function finite(v, seen)
  if type(v) == "number" then check(v == v and math.abs(v) < math.huge, "non-finite number") end
  if type(v) ~= "table" or v == DELETE then return end
  seen = seen or {}; check(not seen[v], "cyclic record"); seen[v] = true
  for k, sub in pairs(v) do finite(k, seen); finite(sub, seen) end
  seen[v] = nil
end
local function list(value, old, convert)
  if value == DELETE then return {} end
  check(type(value) == "table", "expected list")
  if Merge.isWrapper(value) then
    for k in pairs(value) do check(k == "__prepend" or k == "__append", "unknown list extension") end
    local out = {}
    for _, source in ipairs({ value.__prepend or {}, old or {}, value.__append or {} }) do
      for _, row in ipairs(list(source, nil, function(v) return copy(v) end)) do out[#out + 1] = row end
    end
    return list(out, nil, convert)
  end
  local count = 0
  for k in pairs(value) do
    check(type(k) == "number" and k % 1 == 0 and k >= 1 and k <= #value, "expected contiguous list")
    count = count + 1
  end
  check(count == #value, "expected contiguous list")
  local out = {}
  for i, row in ipairs(value) do out[i] = convert(row, i) end
  return out
end
local function resolved(ctx, kind, id)
  check(type(id) == "string" and id ~= "", "expected string " .. kind .. " ID")
  local found, why = ctx.ids:resolve(kind, id)
  if not found then unsupported(why) end
  return found.key
end
local function readIds(ctx, kind, values)
  local out = {}
  for _, id in ipairs(values or {}) do
    if id ~= 0 then out[#out + 1] = ctx.ids:read(kind, id) end
  end
  return out
end
local function writeIds(ctx, kind, values, old)
  return list(values, old, function(id) return resolved(ctx, kind, id) end)
end
-- Gen 3's seven-byte names also produce these spellings (TypeChart's
-- registrant deliberately keeps them authoritative rather than renaming Data).
local TYPE_ALIASES = { PSYCHIC = "PSYCHIC_TYPE", PSYCHC = "PSYCHIC_TYPE",
  MYSTERY = "CURSE_TYPE", FIGHT = "FIGHTING", ELECTR = "ELECTRIC" }
local function typeRead(id) return TYPE_ALIASES[id] or id end
local function typeWrite(ctx, id)
  local registry = ctx.loader.content.type_chart
  local found = registry:get(id) ~= nil and id or nil
  for native, canonical in pairs(TYPE_ALIASES) do
    if canonical == id and registry:get(native) ~= nil then
      if found then unsupported("ambiguous type ID: " .. tostring(id)) end
      found = native
    end
  end
  if found then return found end
  unsupported("unknown type ID: " .. tostring(id))
end
local function reference(ctx, kind, id)
  if ctx.loader.content[kind]:get(id) == nil then unsupported("unknown " .. kind .. " ID: " .. tostring(id)) end
  return id
end

local EVO = {
  level = "LEVEL", useItem = "ITEM", trade = "TRADE", tradeWithItem = "TRADE",
  friendship = "FRIENDSHIP", friendshipDay = "FRIENDSHIP", friendshipNight = "FRIENDSHIP",
  HAPPINESS = "FRIENDSHIP", STAT = "LEVEL",
  levelAtkGreater = "LEVEL", levelAtkLess = "LEVEL", levelAtkEqual = "LEVEL",
}
local function evolutionRead(ctx, row)
  local method = EVO[row.method] or row.method
  local out = { method = method, species = ctx.ids:read("pokemon", row.species or row.target) }
  if method == "LEVEL" then out.level = row.level or row.param end
  if method == "ITEM" then out.item = ctx.ids:read("items", row.item or row.param) end
  if method == "TRADE" then out.item = ctx.ids:read("items", row.heldItem or (row.method == "tradeWithItem" and row.param)) end
  if method == "FRIENDSHIP" then
    out.time = row.timeOfDay or (row.method == "friendshipDay" and "MORNDAY")
      or (row.method == "friendshipNight" and "NITE")
  end
  out.comparison = row.compare or ({ levelAtkGreater = "ATK_GT_DEF", levelAtkLess = "ATK_LT_DEF",
    levelAtkEqual = "ATK_EQ_DEF" })[row.method]
  return out
end
local function evolutionWrite(ctx, row, old)
  if old and equal(row, evolutionRead(ctx, old)) then return copy(old) end
  local method = row.method
  if method ~= "LEVEL" and method ~= "ITEM" and method ~= "TRADE" and method ~= "FRIENDSHIP" then
    unsupported("evolution method has no unified writer: " .. tostring(method))
  end
  if ctx.gen == 1 and (method == "FRIENDSHIP" or row.item and method == "TRADE"
      or row.time or row.comparison) then unsupported("evolution condition has no Gen 1 representation") end
  if ctx.gen >= 4 then
    -- This engine implements the native lowercase level method. Other DS
    -- evolution conditions retain cartridge parameters and lack a safe writer.
    if method ~= "LEVEL" or row.comparison then unsupported("DS evolution condition has no unified writer") end
    check(row.level ~= nil and row.item == nil and row.time == nil, "invalid LEVEL condition")
    return { method = "level", param = row.level, paramKind = "level", methodId = 4,
      target = resolved(ctx, "pokemon", row.species) }
  end
  local out = { method = method, species = resolved(ctx, "pokemon", row.species) }
  if method == "LEVEL" then
    check(row.level ~= nil and row.item == nil and row.time == nil, "invalid LEVEL condition")
    out.level = row.level
    if row.comparison then out.method, out.compare = "STAT", row.comparison end
  elseif method == "ITEM" then
    check(row.item ~= nil and row.level == nil and row.time == nil and row.comparison == nil, "invalid ITEM condition")
    out.item = resolved(ctx, "items", row.item)
  elseif method == "TRADE" then
    check(row.level == nil and row.time == nil and row.comparison == nil, "invalid TRADE condition")
    if row.item then out.heldItem = resolved(ctx, "items", row.item) end
  else
    check(row.level == nil and row.item == nil and row.comparison == nil, "invalid FRIENDSHIP condition")
    out.method, out.timeOfDay = "HAPPINESS", row.time ~= "ANYTIME" and row.time or nil
  end
  return out
end

local readRecord
readRecord = function(ctx, kind, id, raw)
  local out = { id = id, native = copy(raw) }
  for key in pairs(Shapes[kind].fields) do
    if key ~= "native" and key ~= "id" then out[key] = copy(raw[key]) end
  end
  if kind == "pokemon" then
    local stats = raw.baseStats or {}
    out.baseStats = { hp = stats.hp, attack = stats.attack, defense = stats.defense, speed = stats.speed,
      special = stats.special or stats.spatk or stats.spAttack,
      specialAttack = ctx.gen > 1 and (stats.spatk or stats.spAttack) or nil,
      specialDefense = ctx.gen > 1 and (stats.spdef or stats.spDefense) or nil }
    out.types = {}; for i, value in ipairs(raw.types or {}) do out.types[i] = typeRead(value) end
    for _, key in ipairs({ "level1Moves", "tmhm", "eggMoves" }) do
      if raw[key] then out[key] = readIds(ctx, "moves", raw[key]) end
    end
    out.level1Moves, out.learnset, out.evolutions = out.level1Moves or {}, {}, {}
    for i, row in ipairs(raw.learnset or {}) do
      out.learnset[i] = { level = row.level, move = ctx.ids:read("moves", row.move) }
    end
    for i, row in ipairs(raw.evolutions or {}) do out.evolutions[i] = evolutionRead(ctx, row) end
  elseif kind == "moves" then
    out.type = typeRead(raw.type)
    out.category = raw.category or raw.class
    if type(raw.effect) ~= "string" then out.effect = nil end
  elseif kind == "items" then
    if type(raw.effect) ~= "string" then out.effect = nil end
    if raw.machine then out.machine.move = ctx.ids:read("moves", raw.machine.move) end
  elseif kind == "trainers" then
    out.parties = {}
    for i, party in ipairs(raw.parties or (raw.party and { raw.party }) or {}) do
      out.parties[i] = {}
      for j, mon in ipairs(party) do
        out.parties[i][j] = { species = ctx.ids:read("pokemon", mon.species), level = mon.level,
          item = ctx.ids:read("items", mon.item), moves = mon.moves and readIds(ctx, "moves", mon.moves) }
      end
    end
  elseif kind == "encounters" then
    local function areaRead(area)
      if not area then return nil end
      local row = { rate = (area.rate or 0) * 256 / (area.rateMax or 256), slots = {} }
      for i, slot in ipairs(area.slots or {}) do
        row.slots[i] = { species = ctx.ids:read("pokemon", slot.species), level = slot.level,
          minLevel = slot.min, maxLevel = slot.max }
      end
      if area.byTime then
        row.times = { DAY = { rate = row.rate, slots = copy(row.slots) } }
        for key, native in pairs({ MORN = "morn", NITE = "nite" }) do
          if area.byTime[native] then row.times[key] = areaRead(area.byTime[native]) end
        end
      end
      return row
    end
    out.grass, out.water = areaRead(raw.grass), areaRead(raw.water)
  end
  return out
end

local function writeRecord(ctx, kind, id, value, old, mode)
  local previous = old and readRecord(ctx, kind, id, old) or {}
  if value.native ~= nil and not equal(value.native, old or {}) then unsupported("native diagnostics are read-only") end
  if value.id ~= nil then check(value.id == id, "record id differs from operation id") end
  if value.native ~= nil and old then
    -- Detached read/modify/write records carry inherited fields. Convert only
    -- actual edits, so round trips retain native selectors and absent aliases.
    value = copy(value)
    for key, v in pairs(value) do
      if key ~= "id" and key ~= "native" and equal(v, previous[key]) then value[key] = nil end
    end
  end
  local out, replacements = {}, {}
  local function replace(key, v) out[key] = v; replacements[#replacements + 1] = { key } end
  for key, v in pairs(value) do
    if key ~= "native" and key ~= "id" then out[key] = copy(v) end
  end
  if not old then out.id = id end
  if kind == "pokemon" then
    if value.baseStats and value.baseStats ~= DELETE then
      local stats, native = value.baseStats, {}
      for _, stat in pairs(stats) do check(stat ~= DELETE, "cannot delete a native base stat") end
      for _, key in ipairs({ "hp", "attack", "defense", "speed" }) do native[key] = stats[key] end
      local a, b = stats.specialAttack, stats.specialDefense
      if ctx.gen == 1 then
        a, b = a or stats.special or (previous.baseStats or {}).special,
          b or stats.special or (previous.baseStats or {}).special
        if (a or b) and a ~= b then unsupported("Gen 1 cannot split Special") end
        if stats.special and a ~= stats.special then check(false, "conflicting Special values") end
        native.special = stats.special or stats.specialAttack or stats.specialDefense
      else
        -- A patch to special intentionally writes both halves. On detached
        -- read/modify/write records, unchanged split fields are inherited.
        if stats.special ~= nil and (value.native == nil or stats.special ~= (previous.baseStats or {}).special) then
          if value.native ~= nil then
            if a == (previous.baseStats or {}).specialAttack then a = nil end
            if b == (previous.baseStats or {}).specialDefense then b = nil end
          end
          check(a == nil or a == stats.special, "conflicting Special Attack values")
          a, b = a or stats.special, b or stats.special
        elseif stats.special ~= nil and not old then a, b = a or stats.special, b or stats.special end
        native.spatk, native.spdef = a, b
        if a ~= nil then native.special = a end
        if old and old.baseStats and old.baseStats.spAttack ~= nil then native.spAttack = a end
        if old and old.baseStats and old.baseStats.spDefense ~= nil then native.spDefense = b end
      end
      out.baseStats = native
    end
    check(value.types ~= DELETE, "species types cannot be deleted")
    if value.types then
      local types = list(value.types, previous.types, function(t) return typeWrite(ctx, t) end)
      check(#types >= 1 and #types <= 2, "species needs one or two types")
      replace("types", types)
      out.type1, out.type2 = types[1], types[2] or types[1]
    end
    for _, key in ipairs({ "level1Moves", "tmhm", "eggMoves" }) do
      if value[key] ~= nil then replace(key, writeIds(ctx, "moves", value[key], previous[key])) end
    end
    if value.learnset ~= nil then
      replace("learnset", list(value.learnset, previous.learnset, function(row)
        return { level = row.level, move = resolved(ctx, "moves", row.move) }
      end))
    end
    if value.evolutions ~= nil then
      replace("evolutions", list(value.evolutions, previous.evolutions, function(row, i)
        return evolutionWrite(ctx, row, old and old.evolutions and old.evolutions[i])
      end))
    end
    if value.growthRate and value.growthRate ~= DELETE then reference(ctx, "growth_rates", value.growthRate) end
    if ctx.gen == 1 and (value.eggMoves or value.genderRatio or value.eggCycles) then
      unsupported("breeding fields have no Gen 1 representation")
    end
    if not old and ctx.gen >= 3 then unsupported("new species require native EV/ability/storage metadata; patch an existing species") end
  elseif kind == "moves" then
    if value.type and value.type ~= DELETE then
      out.type = typeWrite(ctx, value.type)
      if old and old.typeId and out.type ~= old.type then unsupported("changing a DS type requires native type metadata") end
    end
    if value.effect and value.effect ~= DELETE then
      reference(ctx, "move_effects", value.effect)
      if ctx.gen > 1 and (not old or value.effect ~= old.effect) then unsupported("changing move effects requires a native effect adapter") end
    end
    if value.category ~= nil and old and old.class ~= nil then
      check(value.category ~= DELETE, "native move class cannot be deleted")
      out.class = value.category
      if old.classId ~= nil then out.classId = ({ physical = 0, special = 1, status = 2 })[value.category] end
    end
  elseif kind == "items" then
    if value.index ~= nil and ctx.gen ~= 2 then
      unsupported("explicit item indices require a native generation-specific adapter")
    end
    if value.index ~= nil and value.index ~= DELETE then
      check(value.index <= 255, "Gen-2 item index must be a byte")
      if value.index == 0 and (not old or old.index ~= 0) then unsupported("item index zero is reserved") end
      for key, row in ctx.loader.content.items:each() do
        if row.index == value.index and ctx.ids:read("items", key) ~= id then
          unsupported("item index is already assigned: " .. tostring(value.index))
        end
      end
    end
    if value.machine and value.machine ~= DELETE then
      out.machine.move = resolved(ctx, "moves", value.machine.move)
    end
    for key, registry in pairs({ effect = "item_effects", ball = "balls" }) do
      if value[key] and value[key] ~= DELETE then
        reference(ctx, registry, value[key])
        if ctx.gen > 1 and (not old or value[key] ~= old[key]) then unsupported("changing item behavior requires native metadata") end
      end
    end
  elseif kind == "trainers" and value.parties ~= nil then
    local prior = old and (old.parties or (old.party and { old.party })) or {}
    local parties = list(value.parties, previous.parties, function(party, i)
      return list(party, nil, function(mon, j)
        local native = copy(prior[i] and prior[i][j] or {})
        native.species, native.level = resolved(ctx, "pokemon", mon.species), mon.level
        if ctx.gen == 1 and mon.item then unsupported("held items have no Gen 1 representation") end
        native.item = mon.item and resolved(ctx, "items", mon.item) or nil
        native.moves = mon.moves and writeIds(ctx, "moves", mon.moves) or nil
        return native
      end)
    end)
    replace("parties", parties)
    if old and old.party then
      check(#parties == 1, "native trainer has exactly one party")
      replace("party", parties[1])
    end
  elseif kind == "encounters" then
    local function areaWrite(input, native, before, path)
      if input == DELETE then return DELETE end
      native, before = native or {}, before or {}
      check(input.times ~= DELETE, "native time tables cannot be deleted")
      if input.times then
        input = copy(input)
        if equal(input.rate, before.rate) then input.rate = nil end
        if equal(input.slots, before.slots) then input.slots = nil end
      end
      local result = {}
      if input.rate ~= nil then
        check(input.rate ~= DELETE, "encounter rate cannot be deleted")
        local rate = input.rate * (native.rateMax or 256) / 256
        if math.abs(rate - math.floor(rate + 0.5)) > 1e-8 then unsupported("encounter rate is not representable in native units") end
        result.rate = math.floor(rate + 0.5)
      end
      if input.slots ~= nil then
        local rows = list(input.slots, before.slots, function(slot, i)
          local row = copy((native.slots or {})[i] or {})
          row.species = resolved(ctx, "pokemon", slot.species)
          if slot.level then
            check(slot.minLevel == nil and slot.maxLevel == nil, "conflicting encounter levels")
            row.level, row.min, row.max = slot.level, nil, nil
          else
            check(slot.minLevel ~= nil and slot.maxLevel ~= nil and slot.minLevel <= slot.maxLevel, "invalid encounter level range")
            row.level, row.min, row.max = nil, slot.minLevel, slot.maxLevel
          end
          if slot.chance then unsupported("changing encounter weights requires native buckets") end
          return row
        end)
        if #rows ~= #(native.slots or {}) then unsupported("changing slot count requires native probability buckets") end
        result.slots = rows; local p = copy(path); p[#p + 1] = "slots"; replacements[#replacements + 1] = p
      end
      if input.times then check(ctx.gen == 2 and native.byTime ~= nil, "time-specific encounters require a native time table") end
      if native.byTime then
        result.byTime = {}
        for time, nativeTime in pairs({ MORN = "morn", DAY = "day", NITE = "nite" }) do
          local shared = { rate = input.rate, slots = input.slots }
          -- A full detached record contains inherited times: only explicit
          -- changes override a shared rate/slot patch.
          local specific = input.times and input.times[time]
          if specific and before.times and equal(specific, before.times[time]) then specific = nil end
          if specific then
            for k, v in pairs(specific) do
              if not before.times or not before.times[time] or not equal(v, before.times[time][k]) then shared[k] = v end
            end
          end
          if nativeTime == "day" then
            local d = areaWrite(shared, { rate = native.rate, rateMax = native.rateMax, slots = native.slots }, before, path)
            if d.rate ~= nil then result.rate = d.rate end
            if d.slots then result.slots = d.slots end
          elseif native.byTime[nativeTime] then
            local p = copy(path); p[#p + 1] = "byTime"; p[#p + 1] = nativeTime
            result.byTime[nativeTime] = areaWrite(shared, native.byTime[nativeTime], before.times and before.times[time], p)
          end
        end
      end
      return result
    end
    for _, key in ipairs({ "grass", "water" }) do
      if value[key] ~= nil then out[key] = areaWrite(value[key], old and old[key], previous[key], { key }) end
    end
  end
  return out, replacements
end

local function supported(kind, gen)
  if kind == "encounters" and gen >= 4 then
    return false, "unsupported: DS encounters have seasonal/daily replacement tables; use native content"
  end
  return true
end
local function protect(fn)
  local result = { pcall(fn) }
  if not result[1] then
    if type(result[2]) == "table" and result[2].unsupported then return nil, "unsupported: " .. result[2].unsupported end
    error(result[2], 0)
  end
  return unpack(result, 2)
end
function U.new(loader, mod, native, gen)
  local out = {}; for name, handle in pairs(native) do out[name] = handle end
  if native.text and gen <= 3 then
    out.text = require("src.mods.TextContent").api(loader, mod, native.text, gen)
  end
  if native.held_items then
    out.held_items = require("src.mods.HeldItemContent").api(loader, mod, native.held_items, gen, true)
  end
  if native.marts then
    out.marts = require("src.mods.MartContent").api(loader, mod, native.marts, gen, true)
  end
  for kind, shape in pairs(Shapes) do
    local registry = loader.content[kind]
    if gen >= 4 and kind ~= "encounters" then registry.numericIds = true end
    local f = Schemas.f
    registry.referenceSpec = copy(registry.spec)
    if kind == "pokemon" then
      registry.referenceSpec.fields.evolutions = f.list(f.rec {
        species = f.opt(f.id("pokemon")), target = f.opt(f.id("pokemon")),
        item = f.opt(f.id("items")), heldItem = f.opt(f.id("items")),
      })
    elseif kind == "trainers" then
      local parties = f.list(f.list(f.rec { species = f.id("pokemon"),
        item = f.opt(f.id("items")), moves = f.opt(f.list(f.id("moves"))) }))
      registry.referenceSpec.fields.parties = parties
      registry.referenceSpec.fields.party = parties.inner
    elseif kind == "encounters" then
      local slots = f.list(f.rec { species = f.id("pokemon") })
      local area = f.rec { slots = slots, byTime = f.opt(f.map(f.str, f.rec { slots = slots })) }
      registry.referenceSpec.fields.grass, registry.referenceSpec.fields.water = area, area
      if gen >= 4 then
        -- The DS writer is unavailable, but removing a numeric species must
        -- still see native encounter references, including seasonal tables.
        local fields = {}
        for _, key in ipairs({ "grass", "darkGrass", "rustling" }) do fields[key] = slots end
        for _, key in ipairs({ "surf", "oldRod", "goodRod", "superRod", "ripplingSurf", "ripplingFishing" }) do
          fields[key] = f.rec { slots = slots }
        end
        fields.timed = f.map(f.str, f.list(f.id("pokemon")))
        fields.radar = f.list(f.id("pokemon"))
        fields.dualSlot = f.map(f.str, f.list(f.id("pokemon")))
        fields.swarm = f.union { f.list(f.id("pokemon")), f.map(f.str, f.id("pokemon")) }
        fields.seasons = f.map(f.str, f.rec(fields))
        registry.referenceSpec.fields = fields
      end
    end
    local available, why = supported(kind, gen)
    local function context() return { loader = loader, gen = gen, ids = Ids.new(loader) } end
    local function read(id)
      if not available then return nil, why end
      local ctx = context()
      local found, err = ctx.ids:resolve(kind, id)
      if not found then return nil, err end
      local raw = registry:get(found.key)
      return raw and readRecord(ctx, kind, id, raw) or nil
    end
    local handle = { available = available, supports = function() return available, why end,
      get = function(_, id) return read(id) end,
      has = function(_, id) return read(id) ~= nil end,
      each = function()
        if not available then return function() end, why end
        local ctx, keys = context(), {}
        for id, found in pairs(ctx.ids:entries(kind)) do
          if found == false then error("ambiguous " .. kind .. " ID: " .. id, 0) end
          keys[#keys + 1] = id
        end
        table.sort(keys)
        local i = 0
        return function()
          i = i + 1; local id = keys[i]
          if id == nil then return end
          local found = ctx.ids:resolve(kind, id)
          return id, readRecord(ctx, kind, id, registry:get(found.key))
        end
      end,
    }
    for _, verb in ipairs({ "register", "override", "patch", "remove" }) do
      handle[verb] = function(_, id, value)
        if not available then return nil, why end
        return protect(function()
          check(type(id) == "string" and id ~= "", "operation id must be a non-empty string")
          local ctx = context()
          local found, err = ctx.ids:resolve(kind, id)
          if not found and err:match("^ambiguous") then unsupported(err) end
          if not found then
            if gen >= 4 then unsupported("new numeric records require native storage allocation") end
            found = { key = id, keys = { id } }
          end
          local old = registry:get(found.key)
          if verb == "register" then check(old == nil, kind .. " already registered: " .. id) end
          if verb == "remove" then
            check(not registry.frozen, kind .. ": content is frozen after load")
            loader:_journal(kind)
            for _, key in ipairs(found.keys) do registry:remove(key, mod.manifest.id) end
            return true
          end
          finite(value)
          check(type(value) == "table" and value ~= DELETE, "expected record")
          for key in pairs(value) do check(shape.fields[key] ~= nil, "unknown " .. kind .. " field " .. tostring(key)) end
          local function deletes(fields, record)
            for key, entry in pairs(record) do
              local field = fields[key]
              if field and field.kind ~= "opt" then
                check(entry ~= DELETE or field.kind == "list", "cannot delete required field " .. key)
                if field.kind == "rec" and type(entry) == "table" then deletes(field.fields, entry) end
              end
            end
          end
          deletes(shape.fields, value)
          local valid, validation = Schemas.check(shape, kind, id, value, verb)
          check(valid, validation or "invalid record")
          local payload, replacements = writeRecord(ctx, kind, id, value, old, verb)
          if verb == "patch" and not old then unsupported("cannot patch absent " .. kind .. " ID: " .. id) end
          check(not registry.frozen, kind .. ": content is frozen after load")
          loader:_journal(kind)
          for _, key in ipairs(found.keys) do
            if verb == "patch" then registry:patch(key, payload, mod.manifest.id, replacements)
            else
              local record = Merge.deepMerge(copy(old or {}), payload)
              for _, path in ipairs(replacements) do
                local into, from = record, payload
                for i = 1, #path - 1 do into, from = into[path[i]], from[path[i]] end
                into[path[#path]] = copy(from[path[#path]])
              end
              registry[verb](registry, key, record, mod.manifest.id)
            end
          end
          return true
        end)
      end
    end
    out[kind] = handle
  end
  return out
end
return U
