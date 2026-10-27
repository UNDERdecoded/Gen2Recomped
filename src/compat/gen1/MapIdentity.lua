-- Gen1Recomp names and native map records meet at the ROM group/number.
-- Never rename shared definitions, saves, connections or script operands.
local Names = require("src.compat.gen1.MapNames")
local Identity = {}
local indexes = {}

local function uint(n)
  return type(n) == "number" and n >= 0 and n <= 255 and n % 1 == 0
end
local function slot(g, n)
  return uint(g) and uint(n) and (g .. ":" .. n) or nil
end
local function index(edition)
  if indexes[edition] then return indexes[edition] end
  local rows = Names[edition]
  if not rows then return nil end
  local out = { slots = {}, aliases = {} }
  for _, row in ipairs(rows) do
    local key = assert(slot(row[1], row[2]))
    assert(not out.slots[key], "duplicate Gen1 map slot")
    out.slots[key] = row
    for _, alias in ipairs({ key, row[3], row[4], row[5] }) do
      assert(not out.aliases[alias] or out.aliases[alias] == row, "ambiguous Gen1 map alias")
      out.aliases[alias] = row
    end
  end
  indexes[edition] = out
  return out
end

function Identity.lookup(edition, name, number)
  local catalog = index(edition)
  if not catalog then return nil end
  local row
  if number ~= nil then
    local key = slot(tonumber(name), tonumber(number))
    row = key and catalog.slots[key]
  elseif type(name) == "string" then
    row = catalog.aliases[name]
  end
  if row then return row[3], row[1], row[2], row[4] end
end

-- A binding is tied to one actual data.maps table. Native keys may be
-- renamed by the host's story setup; the checked group/number stays stable.
function Identity.bind(maps, edition)
  assert(type(maps) == "table", "map identity binding needs data.maps")
  assert(index(edition), "unsupported Gen1 map edition")
  local native, ambiguous = {}, {}
  local function equal(a,b,seen,top)
    if a==b then return true end
    if type(a)~='table'or type(b)~='table'then return false end
    seen=seen or{};if seen[a]==b then return true end;seen[a]=b
    for k,v in pairs(a)do
      if not(top and(k=='id'or k=='sourceId'))and not equal(v,b[k],seen)then return false end
    end
    for k,v in pairs(b)do
      if not(top and(k=='id'or k=='sourceId'))and a[k]==nil then return false end
    end
    return true
  end
  local function generatedAlias(key,def)
    local source=def.sourceId;local original=type(source)=='string'and maps[source]
    return type(original)=='table'and original~=def and original.id==source and def.id==key
      and require('src.core.MapIdentity').normalize(source)==key and equal(def,original,nil,true)
  end
  for key, def in pairs(maps) do
    local s = type(def) == "table" and slot(def.group, def.number)
    -- Data's generic spelling aliases are shallow copies with sourceId.
    -- Only an unchanged, correctly spelled copy is an alias, not a second
    -- cartridge room. Authored variants continue to make the slot ambiguous.
    if s and type(key) == "string" and not generatedAlias(key,def) then
      local prior = native[s]
      if prior and prior.def ~= def then ambiguous[s] = true
      elseif not prior or key == def.id then native[s] = { key = key, def = def } end
    end
  end
  local function record(g, n)
    local s = slot(g, n)
    if ambiguous[s] then return nil, "ambiguous native map slot" end
    local row = native[s]
    if not row then return nil, "native map unavailable" end
    local def = row.def
    if maps[row.key] ~= def or def.group ~= g or def.number ~= n then
      return nil, "native map binding retired"
    end
    return row
  end
  local binding = {}
  function binding:nativeId(legacyId)
    local _, g, n = Identity.lookup(edition, legacyId)
    if not g then return nil, "unknown Gen1 map id" end
    local row, why = record(g, n)
    if not row then return nil, why end
    return row.key, row.def
  end
  function binding:legacyId(nativeId)
    local def = type(nativeId) == "string" and maps[nativeId]
    if type(def) ~= "table" then return nil, "unknown native map id" end
    local row, why = record(def.group, def.number)
    if not row then return nil, why end
    if row.def ~= def then return nil, "native map binding retired" end
    local name = Identity.lookup(edition, def.group, def.number)
    if not name then return nil, "unknown Gen1 map slot" end
    return name
  end
  return binding
end

return Identity
