-- Gen1Recomp names and native map records meet at the ROM group/number.
-- Never rename shared definitions, saves, connections or script operands.
local Names = require("src.compat.gen1.MapNames")
local Identity = {}
local indexes = {}
-- Reuse only the private native slot index. Each bind still returns its own
-- mutable methods, and every call checks current keys and identity fields.
-- Weak values avoid retaining a released data set through its definitions.
local nativeIndexes = setmetatable({}, {__mode='kv'})
local function unchanged(snapshot, maps, edition)
  if not snapshot or snapshot.edition~=edition then return false end
  local count=0
  for key,def in pairs(maps)do
    local row=snapshot.rows[key]
    if not row or row.value~=def then return false end
    if type(def)=='table'and(row.group~=def.group or row.number~=def.number or row.id~=def.id)then return false end
    count=count+1
  end
  return count==snapshot.count
end

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
  local snapshot=nativeIndexes[maps]
  if not unchanged(snapshot,maps,edition)then
    snapshot={edition=edition,rows={},count=0,native={},ambiguous={}}
    for key,def in pairs(maps)do
      local row={value=def}
      if type(def)=='table'then row.group,row.number,row.id=def.group,def.number,def.id end
      snapshot.rows[key]=row;snapshot.count=snapshot.count+1
      local s=type(def)=='table'and slot(def.group,def.number)
      if s and type(key)=='string'then
        local prior=snapshot.native[s]
        if prior and prior.def~=def then snapshot.ambiguous[s]=true
        elseif not prior or key==def.id then snapshot.native[s]={key=key,def=def}end
      end
    end
    nativeIndexes[maps]=snapshot
  end
  local function record(g, n)
    local s = slot(g, n)
    if snapshot.ambiguous[s] then return nil, "ambiguous native map slot" end
    local row = snapshot.native[s]
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
