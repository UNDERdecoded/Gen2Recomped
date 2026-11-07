-- The Time Capsule: Gen 1 <-> Gen 2 trades (docs/online-design.md 2.5).
--
-- Gold, Silver and Crystal reach Red, Blue and Yellow through the Time
-- Capsule on PC 2F.  It is a TRADE room only (no Colosseum across it), and
-- the Gen 2 side refuses before the link starts when its party has
-- something the Gen 1 game cannot hold -- pokecrystal
-- engine/link/link.asm CheckTimeCapsuleCompatibility, which answers:
--
--   1  a Pokemon introduced in Gen 2      (species above MEW, dex > 151)
--   2  a move introduced in Gen 2         (move index above STRUGGLE, 165)
--   3  a Pokemon holding MAIL
--
-- plus an EGG, which has no Gen 1 shape at all.
--
-- The held item and the Gen 1 catch-rate byte are the SAME byte of the
-- party struct.  Gen 1 -> 2: the receiver reads the catch rate as the held
-- item, after TimeCapsule_ReplaceTeruSama swaps the indices that are no
-- item ("TERU-SAMA") for real ones (data/items/catch_rate_items.asm
-- TimeCapsule_CatchRateItems).  Gen 2 -> 1: the item's index lands in the
-- catch-rate byte, which is how an item survives a round trip through Red.
--
-- Everything here is by NUMBER (national dex, move index, item index), the
-- only ids the two generations share: the packet carries `dex`, each move's
-- `index` and the held item's `itemIndex` (MonCodec.pack), and the receiver
-- maps them onto its own records.  The receiver's own data then rebuilds
-- the stats (Gen 2 base stats for a mon arriving in Johto, Gen 1's for one
-- arriving in Kanto) -- the conversion the cartridge does too.

local TimeCapsule = {}

TimeCapsule.GEN1_MAX_DEX = 151
TimeCapsule.GEN1_MAX_MOVE = 165

-- TimeCapsule_CatchRateItems: catch-rate value -> Gen 2 item NAME (the names
-- of the cartridge's ITEM constants, matched against the cache's names)
TimeCapsule.CATCH_RATE_ITEMS = {
  [0x19] = "LEFTOVERS",
  [0x2D] = "BITTER BERRY",
  [0x32] = "GOLD BERRY",
  [0x5A] = "BERRY", [0x64] = "BERRY", [0x78] = "BERRY", [0x87] = "BERRY",
  [0xBE] = "BERRY", [0xC3] = "BERRY", [0xDC] = "BERRY", [0xFA] = "BERRY",
  [0xFF] = "BERRY",
}

-- ------------------------------------------------------------ indexes

local indexCache = setmetatable({}, { __mode = "k" })

local function indexes(data)
  local hit = indexCache[data]
  if hit then return hit end
  local out = { dex = {}, move = {}, itemIndex = {}, itemName = {} }
  for id, def in pairs(data.pokemon or {}) do
    local n = type(def) == "table" and tonumber(def.dex)
    if n and not out.dex[n] then out.dex[n] = id end
  end
  for id, def in pairs(data.moves or {}) do
    local n = type(def) == "table" and tonumber(def.index)
    if n and not out.move[n] then out.move[n] = id end
  end
  for id, def in pairs(data.items or {}) do
    if type(def) == "table" then
      local n = tonumber(def.index)
      if n and not out.itemIndex[n] then out.itemIndex[n] = id end
      if type(def.name) == "string" and not out.itemName[def.name] then
        out.itemName[def.name] = id
      end
    end
  end
  indexCache[data] = out
  return out
end

TimeCapsule.indexes = indexes

local function isMail(name)
  return type(name) == "string" and name:upper():find("MAIL", 1, true) ~= nil
end

TimeCapsule.isMail = isMail

-- ------------------------------------------------------------ the gate

-- Can this packed Gen 2 mon go to a Gen 1 game?  true, or false and the
-- cartridge's reason.  The SENDER asks this before its party goes out
-- (CompatRules.canSend), the receiver again before it rebuilds.
function TimeCapsule.gen2ToGen1Allowed(packed)
  if type(packed) ~= "table" then return false, "not a POKéMON" end
  if packed.isEgg then return false, "an EGG can't go" end
  local dex = tonumber(packed.dex)
  if not dex or dex < 1 or dex > TimeCapsule.GEN1_MAX_DEX then
    return false, "a new POKéMON"
  end
  for _, mv in ipairs(packed.moves or {}) do
    local n = tonumber(mv.index)
    if not n or n < 1 or n > TimeCapsule.GEN1_MAX_MOVE then
      return false, "knows a new move"
    end
  end
  if isMail(packed.itemName) then return false, "holds MAIL" end
  return true
end

-- ------------------------------------------------------------ conversion

local function copyMoves(data, packed)
  local idx = indexes(data)
  local moves = {}
  for _, mv in ipairs(packed.moves or {}) do
    local id = idx.move[tonumber(mv.index) or -1]
    if id == nil then return nil end
    moves[#moves + 1] = { id = id, pp = mv.pp, ppUps = mv.ppUps,
                          index = mv.index }
  end
  return moves
end

-- packed (sender's generation) -> packed in the receiver's ids and field
-- set, or nil and why.  The result is fed back through MonCodec.unpack's
-- ordinary checks.
function TimeCapsule.convert(data, packed, fromGen, toGen)
  if fromGen == toGen then return packed end
  if not (fromGen <= 2 and toGen <= 2) then
    return nil, "no Time Capsule between these games"
  end
  local idx = indexes(data)
  if fromGen == 2 and toGen == 1 then
    local ok, why = TimeCapsule.gen2ToGen1Allowed(packed)
    if not ok then return nil, why end
  end
  local species = idx.dex[tonumber(packed.dex) or -1]
  if species == nil then return nil, "not in this game" end
  local moves = copyMoves(data, packed)
  if not moves then return nil, "knows a move this game lacks" end
  local def = data.pokemon[species]
  local out = {
    wire = packed.wire, gen = toGen, dex = packed.dex,
    species = species, level = packed.level, hp = packed.hp,
    status = packed.status, sleepTurns = packed.sleepTurns,
    nickname = packed.nickname, ot = packed.ot, otId = packed.otId,
    dvs = packed.dvs, statExp = packed.statExp, moves = moves,
    extra = packed.extra,
  }
  -- EXP is kept as the cartridge keeps it; both generations share the
  -- growth curves
  out.exp = packed.exp
  if toGen == 1 then
    -- the item's index becomes the catch-rate byte; no item, the species'
    -- own rate (the byte a Gen 1 mon of that species was born with)
    local n = tonumber(packed.itemIndex)
    if packed.itemIndex ~= nil and n and n >= 0 and n <= 255 then
      out.catchRate = math.floor(n)
    else
      out.catchRate = def and tonumber(def.catchRate) or nil
    end
  else
    -- the catch-rate byte becomes the held item
    local rate = tonumber(packed.catchRate)
    if rate and rate > 0 and rate <= 255 then
      local swap = TimeCapsule.CATCH_RATE_ITEMS[rate]
      local item = swap and idx.itemName[swap] or idx.itemIndex[rate]
      local idef = item ~= nil and data.items[item]
      if idef and not (type(idef.name) == "string" and idef.name:find("TERU", 1, true)) then
        out.item = item
      end
    end
    out.catchRate = def and tonumber(def.catchRate) or nil
    out.happiness = require("src.pokemon.Evolution").BASE_HAPPINESS
  end
  return out
end

return TimeCapsule
