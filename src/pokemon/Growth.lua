-- Experience growth curves, ported from engine/pokemon/experience.asm
-- (GrowthRateTable coefficients).  The merged Data.growth_rates registry
-- serves records over these curves; callers that pass it get mod curves,
-- callers that don't keep the vanilla six.

local Logger = require("src.core.Logger")

local Growth = {}

-- Source GSC records and native registries share these evaluations. ROM
-- coefficients remain data; an explicitly registered callback wins.
function Growth.record(data, id)
  if not id then return nil end
  return data and data.growth_rates and data.growth_rates[id]
    or data and data.pokemon and data.pokemon.growthRates and data.pokemon.growthRates[id]
end
function Growth.evaluate(record, level)
  if record and record.expForLevel then
    return math.max(0, math.floor(record.expForLevel(level) or 0))
  end
  if not record then return level*level*level end
  return math.max(0, math.floor((record.numerator or 1)*level^3/(record.denominator or 1))
    +(record.squared or 0)*level^2+(record.linear or 0)*level-(record.constant or 0))
end
function Growth.sourceLevel(record, experience)
  local level=1
  while level<100 and experience>=Growth.evaluate(record,level+1)do level=level+1 end
  return level
end
function Growth.registerCoefficients(registry,data,owner)
  local rows=data and data.pokemon and data.pokemon.growthRates
  if type(rows)~='table'then return end
  for id,row in pairs(rows)do
    registry:register(id,{expForLevel=function(level)return Growth.evaluate(row,level)end},owner)
  end
end

local CURVES = {
  MEDIUM_FAST = function(n) return n * n * n end,
  SLIGHTLY_FAST = function(n) return math.floor((3 * n * n * n) / 4) + 10 * n * n - 30 end,
  SLIGHTLY_SLOW = function(n) return math.floor((3 * n * n * n) / 4) + 20 * n * n - 70 end,
  MEDIUM_SLOW = function(n)
    return math.floor((6 * n * n * n) / 5) - 15 * n * n + 100 * n - 140
  end,
  FAST = function(n) return math.floor((4 * n * n * n) / 5) end,
  SLOW = function(n) return math.floor((5 * n * n * n) / 4) end,
}
Growth.CURVES = CURVES

local warned = {}

-- A cartridge-supplied TABLE beats any formula.
--
-- Gen 1 and Gen 2 get away with the six polynomials above because every one
-- of their curves is closed-form.  Gen 3 adds ERRATIC and FLUCTUATING, which
-- are piecewise -- different rules over different level bands -- and have no
-- polynomial at all.  Emerald's extractor reads gExperienceTables straight off
-- the cartridge into constants.experienceTables, so when that is present it is
-- the exact answer and the formula path is not an approximation of it, it is
-- simply wrong for those two curves.
--
-- Set once at load; nil on a Gen 1/Gen 2 cache, which keeps the formula path
-- byte-identical to what it was.
local tables = nil

function Growth.setTables(byCurve)
  tables = type(byCurve) == "table" and byCurve or nil
end

-- Use a destination cartridge briefly without changing the running preview.
function Growth.withTables(value, fn)
  local previous=tables
  Growth.setTables(value)
  local ok,result=pcall(fn)
  tables=previous
  if not ok then error(result,0) end
  return result
end

function Growth.tableFor(growthRate)
  return tables and tables[growthRate] or nil
end

-- rates is the merged Data.growth_rates (optional); an unknown curve
-- name logs once and falls back to MEDIUM_FAST instead of mis-leveling
-- silently
function Growth.expForLevel(growthRate, level, rates)
  local record = rates and rates[growthRate]
  if record and record.expForLevel then
    return math.max(0, record.expForLevel(level))
  end
  local exact = tables and tables[growthRate]
  if exact then
    -- the table is indexed by level, 1-based, so level n is entry n + 1
    local value = exact[(tonumber(level) or 0) + 1]
    if value then return math.max(0, value) end
    -- past the table's top level, hold at its last entry rather than
    -- silently dropping to a formula with a different shape
    return math.max(0, exact[#exact] or 0)
  end
  local curve = CURVES[growthRate]
  if not curve then
    if growthRate ~= nil and not warned[growthRate] then
      warned[growthRate] = true
      Logger.warn("unknown growth rate %s; using MEDIUM_FAST", tostring(growthRate))
    end
    curve = CURVES.MEDIUM_FAST
  end
  return math.max(0, curve(level))
end

-- one record per curve, each closing over the same clamped evaluation the
-- engine calls, so a registry lookup and Growth.expForLevel cannot diverge
function Growth.registerInto(registry, data, owner)
  -- a cartridge curve with no formula (ERRATIC, FLUCTUATING) still has to
  -- appear in the registry, or a mod asking for it gets nothing
  local ids = {}
  for id in pairs(CURVES) do ids[id] = true end
  for id in pairs(tables or {}) do ids[id] = true end
  local rows=require('src.core.GameVersion').isGen2()
    and data and data.pokemon and data.pokemon.growthRates or {}
  for id in pairs(rows)do ids[id]=true end
  for id in pairs(ids) do
    local row=rows[id]
    registry:register(id,{expForLevel=function(level)
      if row then return Growth.evaluate(row,level)end
      return Growth.expForLevel(id,level)
    end},owner)
  end
end

function Growth.levelForExp(growthRate, exp, cap, rates)
  cap = cap or 100
  local level = 1
  while level < cap and Growth.expForLevel(growthRate, level + 1, rates) <= exp do
    level = level + 1
  end
  return level
end

return Growth
