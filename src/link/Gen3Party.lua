-- Native GBA party data. Keep this separate from the older DV/stat-exp codec.
local C = { REVISION = 1 }
local STATS = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
local CONDITIONS = { "cool", "beauty", "cute", "smart", "tough", "sheen" }
function C.signature(mon)
  local out = {}
  for _, k in ipairs({ "personality", "abilitySlot", "level", "exp", "otId", "otSecretId", "happiness" }) do
    out[#out + 1] = tostring(mon[k] or 0)
  end
  for _, kind in ipairs({ "ivs", "evs" }) do
    for _, k in ipairs(STATS) do
      out[#out + 1] = tostring((mon[kind] or {})[k] or 0)
    end
  end
  return ":gen3=" .. table.concat(out, ",")
end
local STATUSES = { SLP = true, PSN = true, BRN = true, FRZ = true, PAR = true }
local function integer(value, lo, hi, default)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then
    n = default or lo
  end
  return math.max(lo, math.min(hi, math.floor(n)))
end
local function tableOf(v)
  return type(v) == "table" and v or {}
end
local function name(value, limit)
  if type(value) ~= "string" then
    return ""
  end
  local out, count = {}, 0
  for c in value:gsub("%c", ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if count == limit then
      break
    end
    out[#out + 1], count = c, count + 1
  end
  return table.concat(out)
end
local function copyStats(value, max)
  local out = {}
  for _, k in ipairs(STATS) do
    out[k] = integer(tableOf(value)[k], 0, max, 0)
  end
  return out
end
function C.pack(mon, plainCopy)
  local pid = integer(mon.personality, 0, 4294967295, 0)
  local Identity = require("src.pokemon.IdentityRolls")
  local data = Identity.data()
  -- Live links have a mounted registry. Standalone tools can omit it; the
  -- receiver still derives gender from its authoritative species and PID.
  local gender = data
      and data.pokemon
      and data.pokemon[mon.species]
      and Identity.gender(data, { species = mon.species, personality = pid }, 3)
    or nil
  local slot = mon.abilitySlot or (mon.altAbility and 2) or pid % 2 + 1
  local fullOt = integer(mon.otId, 0, 4294967295, 0)
  local ribbons = integer(mon.ribbons, 0, 4294967295, 0)
  if mon.modernFatefulEncounter ~= nil then
    local has = math.floor(ribbons / 2147483648) % 2 == 1
    if mon.modernFatefulEncounter and not has then
      ribbons = ribbons + 2147483648
    end
    if not mon.modernFatefulEncounter and has then
      ribbons = ribbons - 2147483648
    end
  end
  local moves = {}
  for i, mv in ipairs(tableOf(mon.moves)) do
    if i > 4 then
      break
    end
    moves[i] = { id = mv.id, pp = mv.pp, ppUps = mv.ppUps or 0 }
  end
  return {
    gen3Codec = C.REVISION,
    species = mon.species,
    level = mon.level,
    exp = mon.exp,
    hp = mon.hp,
    status = mon.status,
    sleepTurns = mon.sleepTurns,
    toxic = mon.status == "PSN" and mon.toxic == true or nil,
    personality = pid,
    gender = gender,
    nature = pid % 25,
    abilitySlot = integer(slot, 1, 2, 1),
    ivs = copyStats(mon.ivs, 31),
    evs = copyStats(mon.evs, 255),
    nickname = name(mon.nickname, 10),
    moves = moves,
    item = mon.item,
    ot = name(mon.gen3OtName or mon.otName or mon.ot, 7),
    otId = fullOt % 65536,
    secretId = integer(mon.secretId or mon.otSecretId, 0, 65535, math.floor(fullOt / 65536)),
    otGender = integer(mon.otGender, 0, 1, 0),
    happiness = integer(mon.friendship or mon.happiness, 0, 255, 70),
    gen3Language = integer(mon.gen3Language or mon.language, 0, 255, mon.isEgg and 1 or 2),
    gen3Pokerus = integer(mon.gen3Pokerus or mon.pokerus, 0, 255, 0),
    gen3Markings = integer(mon.gen3Markings or mon.markings, 0, 15, 0),
    contest = plainCopy(mon.contest),
    ribbons = ribbons,
    metLocation = integer(mon.metLocation, 0, 255, 0),
    metLevel = integer(mon.metLevel, 0, 100, 0),
    metGame = integer(mon.metGame, 0, 15, 0),
    ball = mon.ball,
    isEgg = mon.isEgg == true,
    eggCycles = mon.isEgg and integer(mon.eggCycles, 0, 255, 0) or nil,
    fatefulEncounter = mon.fatefulEncounter == true,
    modernFatefulEncounter = mon.modernFatefulEncounter == true,
    extra = plainCopy(mon.extra),
  }
end
function C.unpack(data, packed, opts, plainCopy)
  opts = opts or {}
  if type(packed) ~= "table" or packed.gen3Codec ~= C.REVISION then
    return nil, "native party codec required"
  end
  local def = data.pokemon[packed.species]
  if not def then
    return nil, "unknown POKéMON"
  end
  local strict = opts.strict == true
  local function field(value, lo, hi, default)
    local n = tonumber(value)
    if strict and (not n or n ~= n or n < lo or n > hi or n ~= math.floor(n)) then
      return nil
    end
    return integer(value, lo, hi, default)
  end
  local level = field(packed.level, 1, 100, 5)
  if not level then
    return nil, "bad level"
  end
  local pid = field(packed.personality, 0, 4294967295, 0)
  if not pid then
    return nil, "bad personality"
  end
  if strict and packed.nature ~= pid % 25 then
    return nil, "nature mismatch"
  end
  local ivs, evs, total = {}, {}, 0
  for _, k in ipairs(STATS) do
    ivs[k] = field(tableOf(packed.ivs)[k], 0, 31, 0)
    evs[k] = field(tableOf(packed.evs)[k], 0, 255, 0)
    if not ivs[k] then
      return nil, "bad ivs"
    end
    if not evs[k] then
      return nil, "bad evs"
    end
    total = total + evs[k]
  end
  if total > 510 then
    if strict then
      return nil, "bad evs"
    end
    for i = #STATS, 1, -1 do
      local k = STATS[i]
      local cut = math.min(evs[k], total - 510)
      evs[k], total = evs[k] - cut, total - cut
    end
  end
  local slot = field(packed.abilitySlot, 1, 2, 1)
  if not slot then
    return nil, "bad ability"
  end
  local abilities = def.abilities or {}
  if not abilities[2] or abilities[2] == 0 or abilities[2] == "NONE" then
    slot = 1
  end
  local constants = data.constants or {}
  local nature = (constants.natureOrder or {})[pid % 25 + 1]
  if not nature then
    for id, row in pairs(constants.natures or {}) do
      if row.index == pid % 25 then
        nature = id
        break
      end
    end
  end
  local Growth, Stats = require("src.pokemon.Growth"), require("src.pokemon.Stats")
  local function expAt(n)
    return Growth.withTables(constants.experienceTables, function()
      return Growth.expForLevel(def.growthRate, n, data.growth_rates)
    end)
  end
  local minExp, maxExp = expAt(level), expAt(math.min(level + 1, 100))
  if level < 100 then
    maxExp = maxExp - 1
  end
  local exp = field(packed.exp, minExp, maxExp, minExp)
  if not exp then
    return nil, "bad level"
  end
  local forced = tonumber(opts.forceLevel)
  if forced and (forced ~= forced or math.abs(forced) == math.huge) then
    forced = nil
  end
  if forced then
    level = integer(forced, 1, 100, 50)
    exp = expAt(level)
  end
  -- PID's native matrix works even without an English nature registry/global preview.
  local stats = Stats.calcGen3(def, level, ivs, evs)
  local order = { "attack", "defense", "speed", "spatk", "spdef" }
  local up, down = math.floor(pid % 25 / 5) + 1, pid % 5 + 1
  if up ~= down then
    stats[order[up]] = math.floor(stats[order[up]] * 110 / 100)
    stats[order[down]] = math.floor(stats[order[down]] * 90 / 100)
  end
  stats.special = stats.spatk
  local moves, seen = {}, {}
  local entries = tableOf(packed.moves)
  if strict and (#entries < 1 or #entries > 4) then
    return nil, "bad move"
  end
  for _, mv in ipairs(entries) do
    mv = tableOf(mv)
    local mdef = data.moves[mv.id]
    if not mdef or seen[mv.id] or #moves == 4 then
      if strict then
        return nil, "bad move"
      end
    else
      local ups = field(mv.ppUps, 0, 3, 0)
      if not ups then
        return nil, "bad move"
      end
      local maxPp = mdef.pp + math.floor(mdef.pp * 20 * ups / 100)
      local pp = field(mv.pp, 0, maxPp, maxPp)
      if not pp then
        return nil, "bad move"
      end
      moves[#moves + 1], seen[mv.id] = { id = mv.id, pp = pp, ppUps = ups, maxPp = maxPp }, true
    end
  end
  if #moves == 0 then
    return nil, "bad move"
  end
  if packed.item ~= nil and not data.items[packed.item] then
    return nil, "bad item"
  end
  if packed.ball ~= nil and not data.items[packed.ball] then
    return nil, "bad ball"
  end
  local otId, secretId = field(packed.otId, 0, 65535, 0), field(packed.secretId, 0, 65535, 0)
  if not otId or not secretId then
    return nil, "bad ot"
  end
  local ot, nickname = name(packed.ot, 7), name(packed.nickname, 10)
  if strict and (ot ~= packed.ot or nickname ~= packed.nickname) then
    return nil, "bad name"
  end
  local status = not forced and STATUSES[packed.status] and packed.status or nil
  local gender =
    require("src.pokemon.IdentityRolls").gender(data, { species = packed.species, personality = pid }, 3)
  if strict and packed.gender ~= nil and packed.gender ~= gender then
    return nil, "gender mismatch"
  end
  local mon = {
    species = packed.species,
    level = level,
    exp = exp,
    personality = pid,
    ivs = ivs,
    evs = evs,
    nature = nature,
    abilitySlot = slot,
    ability = abilities[slot],
    altAbility = slot == 2 or nil,
    gender = gender,
    stats = stats,
    hp = forced and stats.hp or integer(packed.hp, 0, stats.hp, stats.hp),
    status = status,
    sleepTurns = status == "SLP" and integer(packed.sleepTurns, 1, 7, 1) or nil,
    toxic = status == "PSN" and packed.toxic == true or nil,
    moves = moves,
    nickname = nickname,
    item = packed.item,
    ball = packed.ball,
    ot = ot,
    gen3OtName = ot,
    otId = otId,
    secretId = secretId,
    otSecretId = secretId,
    shiny = require("src.pokemon.IdentityRolls").nativeGen3Shiny(pid, otId, secretId),
    otGender = integer(packed.otGender, 0, 1, 0),
    friendship = integer(packed.happiness, 0, 255, def.friendship or 70),
    happiness = integer(packed.happiness, 0, 255, def.friendship or 70),
    gen3Language = integer(packed.gen3Language, 0, 255, 2),
    gen3Pokerus = integer(packed.gen3Pokerus, 0, 255, 0),
    gen3Markings = integer(packed.gen3Markings, 0, 15, 0),
    contest = {},
    ribbons = integer(packed.ribbons, 0, 4294967295, 0),
    metLocation = integer(packed.metLocation, 0, 255, 0),
    metLevel = integer(packed.metLevel, 0, 100, 0),
    metGame = integer(packed.metGame, 0, 15, 0),
    isEgg = packed.isEgg == true or nil,
    eggCycles = packed.isEgg == true and integer(packed.eggCycles, 0, 255, 0) or nil,
    fatefulEncounter = packed.fatefulEncounter == true,
    modernFatefulEncounter = packed.modernFatefulEncounter == true
      or math.floor(integer(packed.ribbons, 0, 4294967295, 0) / 2147483648) % 2 == 1,
    extra = plainCopy(packed.extra),
  }
  for _, k in ipairs(CONDITIONS) do
    mon.contest[k] = integer(tableOf(packed.contest)[k], 0, 255, 0)
  end
  return mon
end
return C
