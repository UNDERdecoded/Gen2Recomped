-- Semantic texture names resolve from BOTH original source bank identities.
-- No map-name guesses, shared aliases, texture allocation or global edition.
local metadata = require('src.compat.gen1.PairNames')
local M, indexes = {}, {}
local function address(n)
  return type(n) == 'number' and n >= 0 and n < 0x2000000 and n % 1 == 0
end
local function index(edition)
  if indexes[edition] then return indexes[edition] end
  local rows = metadata[edition]; if not rows then return nil end
  local out = {}
  for _, row in ipairs(rows) do
    local p = out[row[1]] or {}; out[row[1]] = p
    assert(not p[row[2]], 'ambiguous source pair metadata'); p[row[2]] = row
  end
  indexes[edition] = out; return out
end
function M.lookup(edition, primary, secondary)
  local rows = index(edition)
  local row = rows and address(primary) and address(secondary) and rows[primary] and rows[primary][secondary]
  if row then return row[3], row[4], row[5], row[6] end
end
function M.bind(pairDefs, banks, edition)
  assert(type(pairDefs) == 'table' and type(banks) == 'table', 'native pair and bank tables required')
  assert(index(edition), 'unsupported pair identity edition')
  local byNative, byName, ambiguous, released = {}, {}, {}, false
  for key, def in pairs(pairDefs) do
    if type(key) == 'string' and type(def) == 'table' then
      local primary, secondary = banks[def.primaryKey], banks[def.secondaryKey]
      if type(primary) == 'table' and type(secondary) == 'table'
          and primary.secondary == false and secondary.secondary == true then
        local name, pn, sn, tileset = M.lookup(edition, primary.address, secondary.address)
        if name then
          local row = {id=name,nativeId=key,primary=pn,secondary=sn,
            primaryKey=def.primaryKey,secondaryKey=def.secondaryKey,tileset=tileset,
            pa=primary.address,sa=secondary.address,def=def,p=primary,s=secondary}
          byNative[key] = row
          local prior = byName[name]
          if prior and prior.def ~= def then ambiguous[name] = true
          elseif not prior or key == def.id then byName[name] = row end
        end
      end
    end
  end
  local function valid(row)
    return not released and row and pairDefs[row.nativeId] == row.def
      and row.def.primaryKey == row.primaryKey and row.def.secondaryKey == row.secondaryKey
      and banks[row.primaryKey] == row.p and banks[row.secondaryKey] == row.s
      and row.p.address == row.pa and row.s.address == row.sa
      and row.p.secondary == false and row.s.secondary == true
  end
  local binding = {}
  function binding:nativeId(name)
    if released then return nil, 'pair binding released' end
    if ambiguous[name] then return nil, 'ambiguous native pair identity' end
    local row = byName[name]
    if not valid(row) then return nil, 'native pair unavailable or retired' end
    return row.nativeId
  end
  function binding:canonicalId(key)
    if released then return nil, 'pair binding released' end
    local row = byNative[key]
    if not valid(row) then return nil, 'native pair unavailable or retired' end
    return row.id
  end
  function binding:descriptor(key)
    if released then return nil, 'pair binding released' end
    local row = byNative[key]
    if not row then
      local native, why = self:nativeId(key); if not native then return nil, why end
      row = byNative[native]
    end
    if not valid(row) then return nil, 'native pair unavailable or retired' end
    return {id=row.id,nativeId=row.nativeId,primary=row.primary,secondary=row.secondary,
      primaryKey=row.primaryKey,secondaryKey=row.secondaryKey,tileset=row.tileset}
  end
  function binding:release()
    released = true; pairDefs, banks, byNative, byName, ambiguous = nil, nil, {}, {}, {}
  end
  return binding
end
return M
