-- MonCodec v3: one Pokemon on the wire, per generation (docs/online-design.md
-- 2.5, workstream WS3).
--
-- The v2 packet (Protocol.packMon) carried the Gen 1/2 field set only, so a
-- Gen 3+ mon lost its personality, IVs, EVs, nature and ability on the way
-- across and came out with different stats, a re-rolled gender and no
-- shininess.  This codec carries a PER-GENERATION ALLOWLIST of the engine's
-- own mon fields, and the receiver rebuilds the mon itself:
--
--   * every field is range-checked, and an illegal value REJECTS the mon
--     (unpack returns nil, why) instead of being clamped into something
--     the sender never had;
--   * stats are never read off the wire.  They are recomputed with the
--     engine's own Stats.calc from the receiver's species record, the IVs /
--     EVs / nature (Gen 3+) or DVs / stat exp (Gen 1/2), the same way
--     Pokemon.new and Pokemon.applySeed build them;
--   * a field the engine stores under two names (pokerus / gen3Pokerus,
--     markings / gen3Markings ...) crosses under the name it had, so
--     whichever reader the receiving screen uses finds it.
--
-- The v2 header fields stay at the top level under their v2 names, so a v2
-- peer that reads this packet (Gen 1/2 only; Handshake refuses a v2 peer a
-- Gen 3+ link) still finds everything it knew.  `wire = 3` marks the packet;
-- Protocol.unpackMon dispatches on it.
--
-- Cross-generation numbers ride along for the Time Capsule (Gen 1 <-> 2):
-- `dex` (national number), each move's `index` and the held item's `itemIndex`,
-- so the receiver can rebuild in its own ids without the sender's data.

local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local MonCodec = {}

MonCodec.WIRE = 3

-- ------------------------------------------------------------ helpers

local function isInt(v, lo, hi)
  return type(v) == "number" and v == v and v % 1 == 0 and v >= lo and v <= hi
end

-- a printable UTF-8 string of at most `max` code points; nil when invalid
local function utf8len(s)
  local n, i, len = 0, 1, #s
  while i <= len do
    local c = s:byte(i)
    local extra
    if c < 0x80 then extra = 0
    elseif c >= 0xC2 and c <= 0xDF then extra = 1
    elseif c >= 0xE0 and c <= 0xEF then extra = 2
    elseif c >= 0xF0 and c <= 0xF4 then extra = 3
    else return nil end
    for k = 1, extra do
      local d = s:byte(i + k)
      if not d or d < 0x80 or d > 0xBF then return nil end
    end
    i = i + extra + 1
    n = n + 1
  end
  return n
end

MonCodec.utf8len = utf8len

local function nameOk(v, max)
  if type(v) ~= "string" then return false end
  if v:find("[%z\1-\31\127]") then return false end
  local n = utf8len(v)
  return n ~= nil and n <= max
end

-- the extra bag is JSON-safe by contract (Protocol.plainCopy); same rule
local function plainCopy(value, depth)
  if type(value) ~= "table" then return nil end
  if (depth or 0) > 8 then return nil end
  local out = {}
  for k, v in pairs(value) do
    local kt, vt = type(k), type(v)
    if kt == "string" or kt == "number" then
      if vt == "string" or vt == "number" or vt == "boolean" then
        out[k] = v
      elseif vt == "table" then
        out[k] = plainCopy(v, (depth or 0) + 1)
      end
    end
  end
  return out
end

-- ------------------------------------------------------------ generation

-- which generation a merged data set is, decided by the cache as Data does
-- (a Gen 1 cache carries no generation constant; its species have no Sp.Def)
function MonCodec.genOf(data)
  if type(data) ~= "table" then return 1 end
  local c = data.constants or {}
  local g = tonumber(c.gen) or tonumber(c.generation)
  if data.isGen3Cache then return 3 end
  if g and g >= 1 and g <= 5 then return math.floor(g) end
  for _, def in pairs(data.pokemon or {}) do
    if type(def) == "table" and type(def.baseStats) == "table" then
      if Stats.isGen3(def) then return 3 end
      return def.baseStats.spdef ~= nil and 2 or 1
    end
  end
  return 1
end

-- ------------------------------------------------------------ field kinds

local STAT6 = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
local STAT5 = { "hp", "attack", "defense", "speed", "special" }
local CONTEST = { "cool", "beauty", "cute", "smart", "tough", "sheen" }
local STATUSES = { SLP = true, PSN = true, BRN = true, FRZ = true, PAR = true,
                   TOX = true }
local GENDERS = { male = true, female = true, none = true, genderless = true,
                  unknown = true }
local OT_GENDERS = { boy = true, girl = true, male = true, female = true }

MonCodec.STATUSES = STATUSES

local function itemExists(data, v)
  return v ~= nil and data and data.items and data.items[v] ~= nil
end

-- a location the engine stores either as a cartridge number or as a name
local function scalarOk(v)
  return isInt(v, 0, 65535) or nameOk(v, 48)
end

local function statBlock(keys, lo, hi, total)
  return function(v)
    if type(v) ~= "table" then return false, "not a table" end
    local sum = 0
    for k, x in pairs(v) do
      local known = false
      for _, key in ipairs(keys) do if key == k then known = true break end end
      if not known then return false, "unknown key " .. tostring(k) end
      if not isInt(x, lo, hi) then return false, tostring(k) .. " out of range" end
      sum = sum + x
    end
    if total and sum > total then return false, "total over " .. total end
    return true
  end
end

local function dateOk(v)
  if type(v) ~= "table" then return false end
  for k in pairs(v) do
    if k ~= "year" and k ~= "month" and k ~= "day" then return false end
  end
  return isInt(v.year, 2000, 2099) and isInt(v.month, 1, 12)
     and isInt(v.day, 1, 31)
end

-- ribbons: Gen 3 keys them by name (contest ranks 0..4, singles true), Gen 4
-- by cartridge ribbon id (true).  JSON cannot carry a sparse number-keyed
-- table, so the wire form is a list of {key, value} pairs.
local function encodeRibbons(r)
  if type(r) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(r) do
    if (type(k) == "string" or type(k) == "number")
       and (type(v) == "boolean" or type(v) == "number") then
      out[#out + 1] = { k, v }
    end
  end
  table.sort(out, function(a, b)
    if type(a[1]) ~= type(b[1]) then return type(a[1]) == "number" end
    return a[1] < b[1]
  end)
  return out
end

local function decodeRibbons(list)
  if type(list) ~= "table" then return nil, "ribbons not a list" end
  if #list > 160 then return nil, "too many ribbons" end
  local out = {}
  for _, pair in ipairs(list) do
    if type(pair) ~= "table" then return nil, "bad ribbon" end
    local k, v = pair[1], pair[2]
    local keyOk = isInt(k, 0, 255)
      or (type(k) == "string" and #k <= 32 and k:match("^[%w_]+$") ~= nil)
    if not keyOk then return nil, "bad ribbon id" end
    if not (v == true or v == false or isInt(v, 0, 255)) then
      return nil, "bad ribbon value"
    end
    if out[k] ~= nil then return nil, "duplicate ribbon" end
    out[k] = v
  end
  return out
end

-- MON_DATA_BALL_CAPSULE: { seals = { {type, x, y} x8 } } (Gen4SealCase)
local function sealsOk(v)
  if type(v) ~= "table" then return false end
  for k in pairs(v) do if k ~= "seals" then return false end end
  local seals = v.seals
  if type(seals) ~= "table" or #seals > 8 then return false end
  for k in pairs(seals) do if not isInt(k, 1, 8) then return false end end
  for _, s in ipairs(seals) do
    if type(s) ~= "table" then return false end
    for key in pairs(s) do
      if key ~= "type" and key ~= "x" and key ~= "y" then return false end
    end
    if not (isInt(s.type, 0, 255) and isInt(s.x, 0, 255) and isInt(s.y, 0, 255)) then
      return false
    end
  end
  return true
end

local function toHex(s)
  return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

local function fromHex(h)
  if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^0-9a-f]") then return nil end
  return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

-- ------------------------------------------------------------ the allowlist
--
-- name -> { from = first generation that carries it, to = last (optional),
--           check = function(value, data) -> ok[, why],
--           encode / decode = wire transforms (optional) }
--
-- species, level, moves, extra and the derived blocks (stats, hp) are
-- handled by pack/unpack themselves.

local function int(lo, hi) return function(v) return isInt(v, lo, hi) end end
local function bool(v) return v == true or v == false end
local function name(max) return function(v) return nameOk(v, max) end end

local FIELDS = {
  -- every generation: the v2 header
  exp        = { from = 1, check = int(0, 2 ^ 31) },
  status     = { from = 1, check = function(v) return STATUSES[v] == true end },
  sleepTurns = { from = 1, check = int(0, 7) },
  nickname   = { from = 1, check = name(12) },
  item       = { from = 1, check = function(v, data) return itemExists(data, v) end },
  heldItem   = { from = 1, check = function(v, data) return itemExists(data, v) end },
  ot         = { from = 1, check = name(12) },
  dvs        = { from = 1, check = statBlock(STAT5, 0, 15) },
  statExp    = { from = 1, check = statBlock(STAT5, 0, 65535) },
  catchRate  = { from = 1, check = int(0, 255) },
  isEgg      = { from = 2, check = bool },
  eggSteps   = { from = 2, check = int(0, 65535) },
  shiny      = { from = 1, check = bool },
  gender     = { from = 2, check = function(v)
                   return type(v) == "string" and GENDERS[v:lower()] == true end },
  -- Gen 2: friendship, the virus byte and the caught-data word
  happiness  = { from = 2, check = int(0, 255) },
  friendship = { from = 2, check = int(0, 255) },
  pokerus    = { from = 2, check = int(0, 255) },
  caughtData = { from = 2, to = 2, check = int(0, 65535) },
  caughtLocation = { from = 2, to = 2, check = scalarOk },
  -- Gen 3: the personality and everything the cartridge keys off it
  personality = { from = 3, check = int(0, 4294967295) },
  secretId    = { from = 3, check = int(0, 65535) },
  ivs         = { from = 3, check = statBlock(STAT6, 0, 31) },
  evs         = { from = 3, check = statBlock(STAT6, 0, 255, 510) },
  nature      = { from = 3, check = function(v, data)
                    local order = data and data.constants and data.constants.natureOrder
                    if isInt(v, 0, 24) then return true end
                    if type(v) ~= "string" or type(order) ~= "table" then return false end
                    for _, n in ipairs(order) do if n == v then return true end end
                    return false
                  end },
  abilitySlot = { from = 3, check = int(1, 3) },
  altAbility  = { from = 3, to = 3, check = bool },
  contest     = { from = 3, check = statBlock(CONTEST, 0, 255) },
  ribbons     = { from = 3, encode = encodeRibbons, decode = decodeRibbons },
  gen3Ribbons = { from = 3, check = int(0, 4294967295) },
  markings    = { from = 3, check = int(0, 255) },
  gen3Markings = { from = 3, check = int(0, 255) },
  gen3Pokerus = { from = 3, check = int(0, 255) },
  gen4Pokerus = { from = 4, check = int(0, 255) },
  language    = { from = 3, check = int(0, 15) },
  gen3Language = { from = 3, check = int(0, 15) },
  ball        = { from = 3, check = function(v, data)
                    return itemExists(data, v) or isInt(v, 0, 255) end },
  metLevel    = { from = 3, check = int(0, 100) },
  metLocation = { from = 3, check = scalarOk },
  gen3MetGame = { from = 3, check = int(0, 15) },
  gen3Origin  = { from = 3, check = name(16) },
  otGender    = { from = 3, check = function(v)
                    return isInt(v, 0, 1) or (type(v) == "string" and OT_GENDERS[v] == true) end },
  gen3OtFemale = { from = 3, check = bool },
  gen3OtName  = { from = 3, check = name(12) },
  fatefulEncounter = { from = 3, check = bool },
  fateful     = { from = 3, check = bool },
  eggCycles   = { from = 3, check = int(0, 255) },
  walkerEvent = { from = 3, check = function(v) return isInt(v, 0, 65535) or nameOk(v, 48) end },
  walkerLegendary = { from = 3, check = bool },
  -- Gen 4: forms, the egg's own origin, dates, the ball capsule, HGSS mood,
  -- and the cartridge record the save codec rebuilds from (ribbons, seals and
  -- every byte the port does not model, NdsSave.encodeMon)
  -- Gen 2: only Polished Crystal stores one (its Unown, PolishedUnown)
  form        = { from = 2, check = int(0, 31) },
  formIndex   = { from = 4, check = int(0, 31) },
  gen4Form    = { from = 4, check = int(0, 31) },
  eggLocation = { from = 4, check = scalarOk },
  eggDate     = { from = 4, check = dateOk },
  metDate     = { from = 4, check = dateOk },
  ballCapsule = { from = 4, check = int(0, 255) },
  ballCapsuleSeals = { from = 4, check = sealsOk },
  hgssMood    = { from = 4, check = int(-127, 127) },
  ndsGame     = { from = 4, check = int(0, 255) },
  ndsAbility  = { from = 4, check = int(0, 1023) },
  ndsNature   = { from = 4, check = int(0, 24) },
  ndsRaw      = { from = 4, encode = function(v)
                    if type(v) == "string" and #v <= 256 then return toHex(v) end
                  end,
                  decode = function(v)
                    local raw = fromHex(v)
                    if not raw or #raw > 256 then return nil, "bad record bytes" end
                    return raw
                  end },
  -- Gen 5: the Hidden Ability is its own flag (abilitySlot 3); the nature is
  -- its own field (Pokemon.natureIsOwnField), carried above
  hiddenAbility = { from = 5, check = bool },
}

MonCodec.FIELDS = FIELDS

-- the field names one generation carries, sorted (the report and the tests
-- read this)
function MonCodec.fieldsFor(gen)
  local out = {}
  for k, spec in pairs(FIELDS) do
    if gen >= spec.from and (spec.to == nil or gen <= spec.to) then
      out[#out + 1] = k
    end
  end
  table.sort(out)
  return out
end

-- ------------------------------------------------------------ cross-gen ids

local function numberOf(record, keyName)
  return record and tonumber(record[keyName]) or nil
end

-- ------------------------------------------------------------ pack

-- data: the sender's merged data (for gen and the cross-generation numbers);
-- gen defaults to the data's.  Never fails: unpack is where checking lives.
function MonCodec.pack(data, mon, gen)
  gen = gen or MonCodec.genOf(data)
  local out = {
    wire = MonCodec.WIRE,
    gen = gen,
    species = mon.species,
    level = mon.level,
    hp = mon.hp,
    otId = mon.otId,
    moves = {},
    extra = plainCopy(mon.extra),
  }
  local def = data and data.pokemon and data.pokemon[mon.species]
  out.dex = numberOf(def, "dex") or (type(mon.species) == "number" and mon.species or nil)
  for _, mv in ipairs(mon.moves or {}) do
    local mdef = data and data.moves and data.moves[mv.id]
    -- the cartridge number (a DS cache's move id IS it) and the name: the
    -- Time Capsule maps by number, Pal Park / Poke Transfer by both
    out.moves[#out.moves + 1] = { id = mv.id, pp = mv.pp, ppUps = mv.ppUps,
                                  index = numberOf(mdef, "index")
                                    or (type(mv.id) == "number" and mv.id or nil),
                                  name = mdef and type(mdef.name) == "string"
                                    and mdef.name or nil }
  end
  local held = mon.item or mon.heldItem
  local idef = held ~= nil and data and data.items and data.items[held]
  if idef then
    out.itemIndex = numberOf(idef, "index") or (type(held) == "number" and held or nil)
    out.itemName = type(idef.name) == "string" and idef.name or nil
  end
  local bdef = mon.ball ~= nil and data and data.items and data.items[mon.ball]
  if bdef and type(bdef.name) == "string" then out.ballName = bdef.name end
  for k, spec in pairs(FIELDS) do
    if gen >= spec.from and (spec.to == nil or gen <= spec.to) then
      local v = mon[k]
      if v ~= nil then
        if spec.encode then
          v = spec.encode(v)
        elseif type(v) == "table" then
          v = plainCopy(v)
        elseif type(v) ~= "string" and type(v) ~= "number" and type(v) ~= "boolean" then
          v = nil
        end
        out[k] = v
      end
    end
  end
  if gen >= 5 and tonumber(mon.abilitySlot) == 3 then out.hiddenAbility = true end
  return out
end

-- ------------------------------------------------------------ unpack

local function reject(packed, why)
  return nil, why
end

-- opts: { strict, forceLevel, timeCapsule = sender gen (set by the caller
-- after TimeCapsule.convert) }
function MonCodec.unpack(data, packed, opts)
  opts = opts or {}
  if type(packed) ~= "table" then return nil, "not a POKéMON" end
  if not isInt(packed.wire, 3, 99) then return nil, "old wire format" end
  local gen = MonCodec.genOf(data)
  local senderGen = packed.gen
  if not isInt(senderGen, 1, 5) then return nil, "bad generation" end
  if senderGen ~= gen then
    if senderGen <= 2 and gen <= 2 then
      local TimeCapsule = require("src.online.TimeCapsule")
      local converted, why = TimeCapsule.convert(data, packed, senderGen, gen)
      if not converted then return nil, why end
      packed = converted
    else
      return nil, "from another generation"
    end
  end

  local def = data.pokemon and data.pokemon[packed.species]
  if type(def) ~= "table" then return reject(packed, "unknown POKéMON") end
  local level = packed.level
  if not isInt(level, 1, 100) then return reject(packed, "bad level") end
  local forceLevel = tonumber(opts.forceLevel)
  if forceLevel then level = math.max(1, math.min(100, math.floor(forceLevel))) end

  local mon = { species = packed.species, level = level }

  -- every allowlisted field this generation keeps, each one checked
  for k, spec in pairs(FIELDS) do
    if gen >= spec.from and (spec.to == nil or gen <= spec.to) then
      local v = packed[k]
      if v ~= nil then
        if spec.decode then
          local out, why = spec.decode(v)
          if out == nil then return reject(packed, why or ("bad " .. k)) end
          v = out
        else
          local ok, why = spec.check(v, data)
          if not ok then
            return reject(packed, ("bad %s%s"):format(k, why and (": " .. why) or ""))
          end
          if type(v) == "table" then v = plainCopy(v) end
        end
        mon[k] = v
      end
    end
  end

  -- the form decides the personal record a Gen 4 / 5 mon is built from
  local Forms = require("src.pokemon.Gen4Forms")
  local fdef = Forms.definition(data, mon) or def
  if gen == 1 and packed.isEgg then return reject(packed, "an EGG") end

  -- otId: a Gen 3 engine mon keeps the public half (secretId apart), a DS
  -- one the full word (NdsSave.decodeMon)
  if packed.otId ~= nil then
    if not isInt(packed.otId, 0, gen >= 3 and 4294967295 or 65535) then
      return reject(packed, "bad OT ID")
    end
    mon.otId = packed.otId
  end

  -- moves: one to four, each known here, no duplicates, PP Ups 0..3
  local moves, seen = {}, {}
  if type(packed.moves) ~= "table" or #packed.moves > 4 then
    return reject(packed, "bad moves")
  end
  for _, mv in ipairs(packed.moves) do
    if type(mv) ~= "table" then return reject(packed, "bad move") end
    local mdef = data.moves and data.moves[mv.id]
    if not mdef then return reject(packed, "unknown move") end
    if seen[mv.id] then return reject(packed, "a move twice") end
    seen[mv.id] = true
    if mv.ppUps ~= nil and not isInt(mv.ppUps, 0, 3) then
      return reject(packed, "bad PP Up")
    end
    if not isInt(mv.pp, 0, 255) then return reject(packed, "bad PP") end
    local entry = { id = mv.id }
    if mv.ppUps ~= nil then entry.ppUps = mv.ppUps end
    local maxPP = require("src.pokemon.Pokemon").maxPP(mdef, entry)
    -- PP above the move's ceiling is clamped, not refused: a Gen 1 PP Up on
    -- a 0-PP move famously overflows on the cartridge itself
    entry.pp = math.min(mv.pp, math.max(maxPP, 0))
    moves[#moves + 1] = entry
  end
  if #moves == 0 then return reject(packed, "no moves") end
  mon.moves = moves

  -- experience inside the level's band (Growth), unless a ruling rebuilds
  -- everyone at one level
  local rate = fdef.growthRate
  if forceLevel then
    mon.exp = Growth.expForLevel(rate, level)
  elseif mon.exp ~= nil then
    local lo = Growth.expForLevel(rate, level)
    local hi = level < 100 and Growth.expForLevel(rate, level + 1) or math.huge
    if mon.exp < lo or mon.exp >= hi then
      return reject(packed, "EXP does not match the level")
    end
  else
    mon.exp = Growth.expForLevel(rate, level)
  end

  if gen >= 3 then
    -- abilities: slot 2 needs a second ability, slot 3 (B/W Hidden Ability)
    -- needs a hidden one and exists only on Gen 5
    local slot = mon.abilitySlot
    local hidden = packed.hiddenAbility
    if gen >= 5 and hidden ~= nil and hidden ~= (slot == 3) then
      return reject(packed, "Hidden Ability flag disagrees")
    end
    if slot == 3 then
      local ids = fdef.abilityIds or fdef.abilities
      if gen < 5 or type(ids) ~= "table" or (tonumber(ids[3]) or (ids[3] and 1) or 0) == 0 then
        return reject(packed, "no Hidden Ability")
      end
    end
    mon.hiddenAbility = nil
    -- nature: its own field on B/W; on Gen 3/4 the personality's, unless the
    -- engine gave this mon a fixed one (a gift like HGSS's Spiky-eared Pichu
    -- is Naughty whatever its personality says) -- carried either way, so
    -- the stats come out the same
    local order = data.constants and data.constants.natureOrder
    if mon.nature == nil and mon.personality and order then
      mon.nature = order[(mon.personality % 25) + 1]
    end
    if slot == nil and mon.personality then
      mon.abilitySlot = require("src.pokemon.Pokemon").abilitySlotFor(fdef, mon.personality)
    end
    mon.stats = Stats.calc(fdef, level, mon.ivs, nil, mon.evs, mon.nature)
  else
    mon.dvs = mon.dvs or { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
    mon.statExp = mon.statExp or { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
    mon.stats = Stats.calc(fdef, level, mon.dvs, mon.statExp)
  end

  -- current HP: whole, never above the rebuilt maximum
  local hp = packed.hp
  if forceLevel then
    mon.hp = mon.stats.hp
    mon.status, mon.sleepTurns = nil, nil
  elseif hp == nil then
    mon.hp = mon.stats.hp
  else
    if not isInt(hp, 0, 65535) then return reject(packed, "bad HP") end
    mon.hp = math.min(hp, mon.stats.hp)
  end
  mon.extra = plainCopy(packed.extra)
  return mon
end

-- checks only: true, or false and why
function MonCodec.validate(data, packed, opts)
  local mon, why = MonCodec.unpack(data, packed, opts)
  if mon then return true end
  return false, why
end

return MonCodec
