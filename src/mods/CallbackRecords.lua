local Api3Records = require("src.mods.Api3Records")
local EnemyMoveChoice = require("src.battle.EnemyMoveChoice")
-- A call-local transaction. Only known record roles cross this boundary;
-- opaque engine handles (Game, battle, save, map, RNG, UI callbacks) stay native.
local Ids = require("src.mods.UnifiedIds")
local R = {}
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function shallow(t)
  local out = {}
  for k, v in pairs(t or {}) do
    out[k] = v
  end
  return out
end
local function copy(v, seen)
  if type(v) ~= "table" then
    if type(v) == "function" then
      return nil
    end
    return v
  end
  seen = seen or {}
  if seen[v] then
    return seen[v]
  end
  local out = {}
  seen[v] = out
  for k, x in pairs(v) do
    out[k] = copy(x, seen)
  end
  return out
end
local function equal(a, b, seen)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  seen = seen or {}
  if seen[a] == b then
    return true
  end
  seen[a] = b
  for k, v in pairs(a) do
    if not equal(v, b[k], seen) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end
local function integer(v, lo, hi, label)
  assert(type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi, label .. " out of range")
  return v
end
local status =
  { SLP = "sleep", PSN = "poison", BRN = "burn", FRZ = "freeze", PAR = "paralyze", TOX = "toxic" }
local short = {}
for k, v in pairs(status) do
  short[v] = k
end
local stats = {
  hp = "hp",
  attack = "attack",
  defense = "defense",
  speed = "speed",
  special = "special",
  specialAttack = "spatk",
  specialDefense = "spdef",
}
local typeAliases = {
  PSYCHIC = "PSYCHIC_TYPE",
  PSYCHC = "PSYCHIC_TYPE",
  MYSTERY = "CURSE_TYPE",
  FIGHT = "FIGHTING",
  ELECTR = "ELECTRIC",
}
local function typeRead(id)
  return typeAliases[id] or id
end
local monFields = {
  species = true,
  item = true,
  nickname = true,
  name = true,
  level = true,
  hp = true,
  maxHp = true,
  status = true,
  isEgg = true,
  stats = true,
  moves = true,
  native = true,
}
local idRoles = {
  species = "pokemon",
  fromSpecies = "pokemon",
  toSpecies = "pokemon",
  evolveTo = "pokemon",
  moveId = "moves",
  item = "items",
  itemId = "items",
  ball = "items",
}
local recordRoles = {
  mon = "mon",
  pokemon = "mon",
  user = "battler",
  target = "battler",
  attacker = "battler",
  defender = "battler",
  battler = "battler",
  incoming = "battler",
  previous = "battler",
  move = "move",
  defeatedDef = "species",
  ballDef = "item",
  opts = "context",
  alive = "party",
  sent = "mon",
  received = "mon",
  playerAction = "action",
  enemyAction = "action",
}
local function array(t, label, max)
  assert(type(t) == "table", label .. " must be a list")
  local n, count = #t, 0
  assert(not max or n <= max, label .. " too long")
  for k in pairs(t) do
    count = count + 1
    assert(type(k) == "number" and k % 1 == 0 and k >= 1 and k <= n, label .. " must be dense")
  end
  assert(count == n, label .. " must be dense")
end

function R.new(loader, name, generation, api3)
  local portableEnemyAction = api3 and generation == 3 and name == "battle.enemy_action"
  local identityRoll = name == "shiny.roll" or name == "gender.roll"
  local ids = Ids.new(loader)
  local portable = api3 and Api3Records or nil
  local function readStatus(value)
    if portable then
      return portable.status(value)
    end
    return status[value] or value
  end
  local function writeStatus(value, old)
    if portable then
      return portable.nativeStatus(value, old)
    end
    assert(value == nil or value == false or short[value], "unknown status")
    return short[value]
  end
  local byRaw, byView, entries = {}, {}, {}
  local view, restore, commit, refresh
  local open = true
  local function read(kind, id)
    return ids:read(kind, id)
  end
  local function native(kind, id, old)
    if id == read(kind, old) then
      return old
    end
    if id == nil or id == false then
      return nil
    end
    assert(type(id) == "string", kind .. " ID must be a string")
    local entry, why = ids:resolve(kind, id)
    assert(entry, why)
    -- Keep each host's existing numeric/string representation.
    if type(old) == "string" then
      for _, key in ipairs(entry.keys) do
        if type(key) == "string" then
          return key
        end
      end
    end
    return entry.key
  end
  local function moveDef(id)
    local group = ids:resolve("moves", read("moves", id))
    return group and loader.content.moves:get(group.key) or nil
  end
  local function moveViews(raw)
    local out = {}
    for i, m in ipairs(raw or {}) do
      local id = type(m) == "table" and m.id or m
      local def = moveDef(id)
      local ups = type(m) == "table" and (m.ppUps or 0) or 0
      out[i] = {
        id = read("moves", id),
        pp = type(m) == "table" and m.pp or nil,
        maxPp = def and math.floor((def.pp or 0) + ups * math.floor((def.pp or 0) / 5)) or nil,
        ppUps = ups,
      }
    end
    return out
  end
  local function statView(raw)
    local out = {}
    for k, n in pairs(stats) do
      out[k] = (raw or {})[n]
    end
    out.specialAttack = out.specialAttack or out.special
    out.specialDefense = out.specialDefense or out.special
    if portable then
      portable.stats(out, generation)
    end
    return out
  end
  local function fields(raw, kind)
    if kind == "rollIvs" then
      return { hp = raw.hp, atk = raw.attack, def = raw.defense,
        spe = raw.speed, spa = raw.spatk, spd = raw.spdef }
    elseif kind == "mon" then
      return {
        species = read("pokemon", raw.species),
        item = read("items", raw.item),
        nickname = raw.nickname,
        name = portable and raw.nickname and raw.nickname ~= "" and raw.nickname or raw.name,
        level = raw.level,
        hp = raw.hp,
        maxHp = raw.stats and raw.stats.hp,
        status = portable and generation == 3 and raw.toxic == true and readStatus(raw.status) == "PSN" and "TOX" or readStatus(raw.status),
        isEgg = raw.isEgg == true,
        dvs = portable and generation ~= 3 and type(raw.dvs) == "table" and copy(raw.dvs) or nil,
        shiny = portable and portable.shiny(raw, generation),
        stats = statView(raw.stats),
        moves = moveViews(raw.moves),
        native = copy(raw),
      }
    elseif kind == "battler" then
      return {
        mon = view(raw.mon, "mon"),
        id = raw.id,
        side = raw.isPlayer == true and "player" or raw.isPlayer == false and "enemy" or nil,
        native = copy({ name = raw.name, species = raw.species, stages = raw.stages }),
      }
    elseif kind == "heldItem" then
      local out = { native = copy(raw) }
      for k, v in pairs(raw) do
        if type(v) ~= "table" and type(v) ~= "function" then out[k] = v end
      end
      out.id = read("items", raw.id)
      return out
    elseif kind == "move" or kind == "species" or kind == "item" or kind == "identitySpecies" then
      local out = { native = copy(raw), name = raw.name }
      local registryKind = (kind == "species" or kind == "identitySpecies") and "pokemon"
        or kind == "move" and "moves" or "items"
      local key = raw.id or raw.index or raw.numId
      if key == nil then
        for id, row in loader.content[registryKind]:each() do
          if row == raw then
            key = id
            break
          end
        end
      end
      out.id = read(registryKind, key)
      if kind == "species" or kind == "identitySpecies" then
        out.baseStats = statView(raw.baseStats)
        out.types = {}
        for i, t in ipairs(raw.types or {}) do
          out.types[i] = typeRead(t)
        end
        out.baseExp = raw.baseExp or raw.expYield
        out.catchRate = raw.catchRate
        out.growthRate = raw.growthRate
        if kind == "identitySpecies" then out.genderRatio = raw.genderRatio end
      elseif kind == "move" then
        for _, key in ipairs({ "type", "power", "accuracy", "pp", "priority" }) do
          out[key] = raw[key]
        end
        out.type = typeRead(out.type)
        out.category = raw.category or raw.class
        out.effect = type(raw.effect) == "string" and raw.effect or nil
      else
        for _, key in ipairs({ "price", "description", "consumable" }) do
          out[key] = raw[key]
        end
      end
      return out
    elseif kind == "party" or kind == "candidates" or kind == "trainerParty" then
      local out = {}
      local role = kind == "party" and "mon" or kind == "trainerParty" and "trainerMon" or "encounter"
      for i, v in ipairs(raw) do
        out[i] = view(v, role)
      end
      return out
    elseif kind == "trainerMon" then
      local out = copy(raw)
      out.species = read("pokemon", raw.species)
      out.item = read("items", raw.item)
      out.moves = {}
      for i, id in ipairs(raw.moves or {}) do
        out.moves[i] = read("moves", id)
      end
      out.native = copy(raw)
      return out
    end
    local out = shallow(raw)
    local nativeAction = portableEnemyAction and kind == "action" and EnemyMoveChoice.nativeView(raw)
    if nativeAction then
      local def = moveDef(raw.id)
      local number = def and tonumber(def.index or def.numId)
      if not number and type(raw.id) == "number" then number = raw.id end
      out.kind = raw.kind or "move"
      out.move = raw.move ~= nil and raw.move or (raw.struggle and "STRUGGLE" or number)
      out.slot = raw.slot or nativeAction.slot
      out.user = raw.user or "enemy"
      out.battler = raw.battler ~= nil and raw.battler or nativeAction.battler
      out.targetType = raw.targetType or (nativeAction.double and (tonumber(def and def.target) or 0)) or nil
    end
    for k, v in pairs(raw) do
      local role = recordRoles[k]
      if identityRoll and k == "def" then role = "identitySpecies" end
      if identityRoll and (k == "dvs" or k == "ivs") then role = "context" end
      if identityRoll and generation == 3 and k == "ivs" then role = "rollIvs" end
      if name == "held_item.trigger" and k == "def" then role = "heldItem" end
      if name == "world.interacted" and k == "target" then
        role = nil
      end
      if name == "trade.completed" and k == "evolution" then
        role = "context"
      end
      if name == "pokemon.before_give" and k == "ctx" then
        role = nil
      end
      if nativeAction and k == "move" then
        out[k] = v
      elseif k == "status" then
        out[k] = readStatus(v)
      elseif k == "move" and type(v) ~= "table" then
        out[k] = read("moves", v)
      elseif kind == "action" and k == "id" and not raw.special then
        out[k] = read("moves", v)
      elseif idRoles[k] and type(v) ~= "table" then
        out[k] = read(idRoles[k], v)
      elseif role and type(v) == "table" then
        out[k] = view(v, role)
      elseif k == "learnable" and name == "pokemon.level_up" then
        out[k] = {}
        for i, id in ipairs(v) do
          out[k][i] = read("moves", id)
        end
      elseif k == "applyShare" and name == "battle.exp_award" and type(v) == "function" then
        out[k] = function(mon, ...)
          local bound = byView[mon]
          assert(bound and bound.kind == "mon", "applyShare requires a bound Pokemon")
          commit()
          local result = pack(pcall(v, bound.raw, ...))
          if not result[1] then
            error(result[2], 0)
          end
          refresh()
          return unpack(result, 2, result.n)
        end
      end
    end
    if portableEnemyAction and kind == "action" then
      for _, key in ipairs({ "move", "id" }) do
        local authored, unchanged, known = EnemyMoveChoice.publicReference(raw, key)
        if unchanged then out[key] = authored
        elseif known and key == "move" then
          local def = moveDef(raw[key])
          out[key] = def and tonumber(def.index or def.numId) or raw[key]
        end
      end
    end
    return out
  end
  view = function(raw, kind)
    if type(raw) ~= "table" then
      return raw
    end
    byRaw[raw] = byRaw[raw] or {}
    if byRaw[raw][kind] then
      return byRaw[raw][kind].public
    end
    local e = { raw = raw, kind = kind, public = {} }
    byRaw[raw][kind] = e
    byView[e.public] = e
    entries[#entries + 1] = e
    for k, v in pairs(fields(raw, kind)) do
      e.public[k] = v
    end
    e.before = (
      kind == "action"
      or kind == "gift"
      or kind == "context"
      or kind == "encounter"
      or kind == "party"
      or kind == "trainerParty"
      or kind == "candidates"
    )
        and shallow(e.public)
      or copy(e.public)
    return e.public
  end
  local function statChanges(public, old, baseline, ops)
    assert(type(old) == "table", "native stats are missing")
    assert(type(public) == "table", "stats must be a record")
    for k in pairs(public) do
      assert(stats[k], "unknown stat " .. tostring(k))
    end
    if portable then
      local common = public.special ~= baseline.special and public.special or nil
      if generation == 1 then
        for _, k in ipairs({ "specialAttack", "specialDefense" }) do
          if public[k] ~= baseline[k] then
            assert(common == nil or common == public[k], "conflicting special stats")
            common = public[k]
          end
        end
      elseif common ~= nil then
        for _, k in ipairs({ "specialAttack", "specialDefense" }) do
          assert(public[k] == baseline[k] or public[k] == common, "conflicting special stats")
        end
      end
      for k, n in pairs(stats) do
        if k ~= "special" or generation == 1 then
          local value = public[k]
          if common ~= nil and (k == "special" or k == "specialAttack" or k == "specialDefense") then
            value = common
          end
          if value ~= baseline[k] then
            value = integer(value, 1, 65535, "stats." .. k)
            if generation == 1 and (k == "specialAttack" or k == "specialDefense") then
              n = "special"
            end
            local target = n
            ops[#ops + 1] = function()
              old[target] = value
              if generation > 1 and target == "spatk" and old.special ~= nil then
                old.special = value
              end
            end
          end
        end
      end
      return
    end
    local specialValue
    for _, k in ipairs({ "special", "specialAttack", "specialDefense" }) do
      if public[k] ~= baseline[k] and (generation == 1 or k ~= "specialDefense") then
        assert(not specialValue or specialValue == public[k], "conflicting special stats")
        specialValue = public[k]
      end
    end
    for k, n in pairs(stats) do
      local value = public[k]
      if generation == 1 and (k == "special" or k == "specialAttack" or k == "specialDefense") then
        value = specialValue or baseline[k]
        n = "special"
      elseif specialValue and (k == "special" or k == "specialAttack") then
        value = specialValue
      end
      if value ~= baseline[k] then
        value = integer(value, 1, 65535, "stats." .. k)
        ops[#ops + 1] = function()
          old[n] = value
        end
      end
    end
  end
  local pending, visiting
  local function stage(raw, key, value)
    assert(type(raw) == "table", "native record is missing")
    pending[#pending + 1] = function()
      raw[key] = value
    end
  end
  local function movesNative(public, old, baseline)
    array(public, "moves", 4)
    local out = {}
    for i, m in ipairs(public) do
      assert(type(m) == "table", "move must be a record")
      for k in pairs(m) do
        assert(k == "id" or k == "pp" or k == "maxPp" or k == "ppUps", "unknown move field")
      end
      local prev = (old or {})[i]
      local prior = (baseline or {})[i] or {}
      assert(m.maxPp == prior.maxPp, "maxPp is read-only")
      local row = type(prev) == "table" and shallow(prev) or {}
      row.id = native("moves", m.id, row.id)
      assert(row.id, "move ID is required")
      row.ppUps = integer(m.ppUps or 0, 0, 3, "ppUps")
      local def = moveDef(row.id)
      local max = def and math.floor((def.pp or 0) + row.ppUps * math.floor((def.pp or 0) / 5)) or 0
      row.pp = integer(m.pp, 0, max, "pp")
      out[i] = row
    end
    return out
  end
  restore = function(value, kind, original)
    -- GBA enemy-action normalization accepts scalar move choices and false
    -- fallback. Other record boundaries keep their existing validation.
    if name == "battle.enemy_action" and generation == 3 and kind == "action"
        and (type(value) == "string" or type(value) == "number" or value == false) then
      return value
    end
    if type(value) ~= "table" then
      assert(
        value == nil or (kind == "encounter" and value == false),
        "expected " .. tostring(kind) .. " record"
      )
      return value
    end
    local e = byView[value]
    if not e then
      assert(
        kind == "action"
          or kind == "encounter"
          or kind == "trainerMon"
          or kind == "candidates"
          or kind == "trainerParty"
          or (identityRoll and (kind == "context" or kind == "rollIvs" or kind == "identitySpecies")),
        "replacement " .. tostring(kind) .. " must be a bound record"
      )
      local target = identityRoll and api3 and type(original) == "table" and original or nil
      local previous = target and byRaw[target] and byRaw[target][kind]
      e = { public = value, kind = kind, raw = target or {},
        before = previous and previous.before or {}, replacement = true }
      if target then
        byView[value] = e
        entries[#entries + 1] = e
      end
    end
    if visiting[e] then
      return e.raw
    end
    visiting[e] = true
    local raw, before = e.raw, e.before
    kind = e.kind
    if kind == "heldItem" then
      local keys = shallow(before)
      for k in pairs(value) do keys[k] = true end
      for key in pairs(keys) do
        if key ~= "native" and not equal(value[key], before[key]) then
          local v = value[key]
          assert(type(v) ~= "table" and type(v) ~= "function", "held definition field must be scalar")
          if key == "id" then v = native("items", v, raw.id) end
          pending[#pending + 1] = function()
            require("src.battle.HeldItemRead").writeDefinition(raw, key, v)
          end
        end
      end
    elseif kind == "rollIvs" then
      local aliases = { hp = "hp", atk = "attack", def = "defense",
        spe = "speed", spa = "spatk", spd = "spdef" }
      for k, v in pairs(value) do
        assert(aliases[k], "unknown IV field")
        if v ~= before[k] then stage(raw, aliases[k], integer(v, 0, 31, "IV")) end
      end
      for k in pairs(before) do assert(value[k] ~= nil, "IV field is required") end
    elseif kind == "identitySpecies" then
      local current, original = shallow(value), shallow(before)
      current.genderRatio, original.genderRatio = nil, nil
      if e.replacement then
        for key in pairs(original) do if current[key] == nil then original[key] = nil end end
      end
      assert(equal(current, original), "species definition is read-only except genderRatio")
      if value.genderRatio ~= before.genderRatio then
        stage(raw, "genderRatio", integer(value.genderRatio, 0, 255, "gender ratio"))
      end
    elseif kind == "move" or kind == "species" or kind == "item" or kind == "battler" then
      if kind == "battler" then
        assert(
          value.id == before.id and value.side == before.side and equal(value.native, before.native),
          "battler metadata is read-only"
        )
        assert(byView[value.mon] and byView[value.mon].raw == raw.mon, "battler.mon identity is read-only")
        for k in pairs(value) do
          assert(k == "mon" or k == "id" or k == "side" or k == "native", "unknown battler field")
        end
        restore(value.mon, "mon")
      else
        assert(equal(value, before), kind .. " definition is read-only; use mod.content")
      end
    elseif kind == "mon" then
      for k in pairs(value) do
        assert(
          monFields[k] or (portable and (k == "dvs" or k == "shiny")),
          "unknown Pokemon field " .. tostring(k)
        )
      end
      assert(equal(value.native, before.native), "native snapshot is read-only")
      assert(value.name == before.name, "name is read-only; set nickname")
      if portable then
        assert(equal(value.dvs, before.dvs) and value.shiny == before.shiny, "DVs and shiny are read-only")
      end
      for _, key in ipairs({ "species", "item", "nickname", "level", "hp", "maxHp", "status", "isEgg" }) do
        local v = value[key]
        if not equal(v, before[key]) then
          if key == "species" or key == "item" then
            v = native(key == "species" and "pokemon" or "items", v, raw[key])
            assert(key ~= "species" or v, "species is required")
          elseif key == "level" then
            v = integer(v, 1, 100, key)
          elseif key == "hp" then
            v = integer(v, 0, 65535, key)
          elseif key == "maxHp" then
            v = integer(v, 1, 65535, key)
          elseif key == "status" then
            v = writeStatus(v, raw.status)
            if portable and generation == 3 then
              local toxic = v == "TOX"
              stage(raw, "toxic", toxic or nil)
              for _, parent in ipairs(entries) do
                if parent.kind == "battler" and parent.raw.mon == raw then
                  stage(parent.raw, "toxicCounter", toxic and 1 or nil)
                end
              end
              if toxic then v = "PSN" end
            end
          elseif key == "nickname" then
            assert(v == nil or type(v) == "string", "nickname must be a string")
          elseif key == "isEgg" then
            assert(type(v) == "boolean", "isEgg must be boolean")
          end
          if key == "maxHp" then
            stage(raw.stats, "hp", v)
          else
            stage(raw, key, v)
          end
        end
      end
      if value.maxHp ~= before.maxHp and value.stats.hp ~= before.stats.hp then
        assert(value.maxHp == value.stats.hp, "conflicting maxHp and stats.hp")
      end
      local limit = value.stats.hp ~= before.stats.hp and value.stats.hp or value.maxHp
      if value.hp ~= before.hp or limit ~= before.maxHp then
        assert(
          type(value.hp) == "number" and type(value.maxHp) == "number" and value.hp <= limit,
          "hp exceeds maxHp"
        )
      end
      if not equal(value.stats, before.stats) then
        statChanges(value.stats, raw.stats, before.stats, pending)
      end
      if not equal(value.moves, before.moves) then
        local new = movesNative(value.moves, raw.moves, before.moves)
        local target = raw.moves or {}
        stage(raw, "moves", target)
        pending[#pending + 1] = function()
          local previous = shallow(target)
          for i in pairs(target) do
            target[i] = nil
          end
          for i, row in ipairs(new) do
            local slot = type(previous[i]) == "table" and previous[i] or {}
            for k in pairs(slot) do
              slot[k] = nil
            end
            for k, v in pairs(row) do
              slot[k] = v
            end
            target[i] = slot
          end
        end
      end
    elseif kind == "party" or kind == "candidates" or kind == "trainerParty" then
      array(value, kind, kind ~= "candidates" and 6 or nil)
      local out = {}
      local role = kind == "party" and "mon" or kind == "trainerParty" and "trainerMon" or "encounter"
      for i, v in ipairs(value) do
        out[i] = restore(v, role)
      end
      if kind == "party" then
        assert(#value == #raw, "live party membership is read-only")
        for i, v in ipairs(out) do
          assert(v == raw[i], "live party order is read-only")
        end
      else
        pending[#pending + 1] = function()
          for k in pairs(raw) do
            raw[k] = nil
          end
          for i, v in ipairs(out) do
            raw[i] = v
          end
        end
      end
    elseif kind == "gift" then
      assert(value.ctx == before.ctx, "gift context is read-only")
      for k in pairs(value) do
        assert(k == "ctx" or k == "species" or k == "level" or k == "nickname", "unknown gift field")
      end
      stage(raw, "species", assert(native("pokemon", value.species, raw.species), "species is required"))
      stage(raw, "level", integer(value.level, 1, 100, "level"))
      assert(value.nickname == nil or type(value.nickname) == "string", "nickname must be a string")
      stage(raw, "nickname", value.nickname)
    elseif kind == "trainerMon" then
      assert(value.native == nil or equal(value.native, before.native), "native snapshot is read-only")
      local allowed = { species = true, item = true, level = true, moves = true, native = true }
      for k, v in pairs(value) do
        if not allowed[k] then
          assert(equal(v, before[k]), "trainer metadata is read-only")
        end
      end
      stage(raw, "species", assert(native("pokemon", value.species, raw.species), "species is required"))
      stage(raw, "item", native("items", value.item, raw.item))
      stage(raw, "level", integer(value.level, 1, 100, "level"))
      if not equal(value.moves, before.moves) then
        array(value.moves, "trainer moves", 4)
        local out = {}
        for i, id in ipairs(value.moves) do
          out[i] = assert(native("moves", id, (raw.moves or {})[i]), "move is required")
        end
        stage(raw, "moves", out)
      end
    else
      if kind == "encounter" then
        assert(value.species ~= nil, "encounter species is required")
        if value.level ~= nil then
          integer(value.level, 1, 100, "encounter level")
        end
        for _, k in ipairs({ "min", "max" }) do
          if value[k] ~= nil then
            integer(value[k], 1, 100, k)
          end
        end
        assert(
          value.level ~= nil or (value.min and value.max and value.min <= value.max),
          "encounter level is required"
        )
      end
      local keys = shallow(before)
      for k in pairs(value) do
        keys[k] = true
      end
      for k in pairs(keys) do
        local v = value[k]
        local old = raw[k]
        if type(v) == "table" and byView[v] then
          local restored = restore(v)
          if v ~= before[k] then
            stage(raw, k, restored)
          end
        elseif portableEnemyAction and kind == "action" and not value.special
            and (k == "move" or k == "id") and v ~= before[k] then
          local known = type(v) == "string" and ids:resolve("moves", v)
          local converted = known and native("moves", v, old) or v
          stage(raw, k, converted)
          pending[#pending + 1] = function()
            EnemyMoveChoice.rememberReference(raw, k, v, converted)
          end
        elseif kind == "action" and name == "battle.enemy_action" and generation == 3
            and not value.special and (k == "move" or k == "id") and v ~= before[k]
            and (type(v) == "number" or type(v) == "string") then
          local known = type(v) == "string" and ids:resolve("moves", v)
          -- Keep canonical IDs native inside nested callbacks. Numeric and
          -- alternate name spellings are resolved by the actual producer.
          stage(raw, k, known and native("moves", v, old) or v)
        elseif k == "move" and type(v) ~= "table" and v ~= before[k] then
          stage(raw, k, native("moves", v, old))
        elseif kind == "action" and k == "id" and not value.special and v ~= before[k] then
          stage(raw, k, native("moves", v, old))
        elseif k == "status" and v ~= before[k] then
          stage(raw, k, writeStatus(v, old))
        elseif idRoles[k] and v ~= before[k] then
          stage(raw, k, native(idRoles[k], v, old))
        elseif k == "applyShare" and name == "battle.exp_award" then
          assert(v == before[k], "applyShare is read-only")
        elseif k == "learnable" and name == "pokemon.level_up" then
          assert(equal(v, before[k]), "learnable is read-only")
        elseif v ~= before[k] then
          local role = recordRoles[k]
          if identityRoll and k == "def" then role = "identitySpecies" end
          if identityRoll and (k == "dvs" or k == "ivs") then role = "context" end
          if identityRoll and generation == 3 and k == "ivs" then role = "rollIvs" end
          if kind == "encounter" and k == "level" then
            integer(v, 1, 100, "encounter level")
          end
          if role and type(v) == "table" then
            v = restore(v, role, identityRoll and api3 and old or nil)
          end
          stage(raw, k, v)
        end
      end
    end
    return raw
  end
  commit = function(extra)
    assert(open, "callback transaction is closed")
    pending, visiting = {}, {}
    for _, e in ipairs(entries) do
      restore(e.public, e.kind)
    end
    local result
    if extra then
      result = extra()
    end
    for _, op in ipairs(pending) do
      op()
    end
    return result
  end
  refresh = function()
    -- Reuse public identities, but refresh after vanilla mutates native data.
    for _, e in ipairs(entries) do
      local nextValue = fields(e.raw, e.kind)
      for k in pairs(e.public) do
        e.public[k] = nil
      end
      for k, v in pairs(nextValue) do
        e.public[k] = v
      end
    end
    for _, e in ipairs(entries) do
      e.before = (
        e.kind == "action"
        or e.kind == "gift"
        or e.kind == "context"
        or e.kind == "encounter"
        or e.kind == "party"
        or e.kind == "trainerParty"
        or e.kind == "candidates"
      )
          and shallow(e.public)
        or copy(e.public)
    end
  end
  return {
    close = function()
      open = false
    end,
    view = view,
    restore = function(v, kind, original)
      return restore(v, kind, original)
    end,
    commit = commit,
    refresh = refresh,
    read = read,
    native = native,
    copy = copy,
  }
end
return R
