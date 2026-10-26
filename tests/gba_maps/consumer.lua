return function(T, Catalog, rows, version)
  local out = {}
  for _, row in ipairs(rows) do
    local g, n, id = row.group, row.number, row.canonical
    T.eq(Catalog.mapIdFor(g, n, version), id, 'physical slot identity')
    T.eq(Catalog.mapIdFor(tostring(g), tostring(n), version), id, 'numeric slot strings')
    T.eq(Catalog.pretToEngine(row.pret, version), id, 'known source symbol identity')
    T.eq(Catalog.resolve(row.pret, nil, version), id, 'source name resolution')
    T.eq(Catalog.resolve(g, n, version), id, 'physical slot resolution')
    T.eq(Catalog.resolve(id, nil, version), id, 'canonical identity is stable')
    T.eq(Catalog.resolve(g .. ':' .. n, nil, version), id, 'slot-key resolution')
    T.eq(Catalog.isKnown(id, version), true, 'canonical name is known')
    T.eq(Catalog.isKnown(row.pret, version), true, 'source symbol is known')
    T.eq(Catalog.slotKeyFor(id, version), g .. '_' .. n, 'native group/number key')
    local rg, rn = Catalog.groupNumFor(id, version)
    T.eq(rg, g, 'reverse group'); T.eq(rn, n, 'reverse number')
    if row.constant then T.eq(Catalog.resolve(row.constant, nil, version), id, 'source map constant resolution') end
    out[#out + 1] = id
  end
  T.eq(Catalog.mapIdFor(255, 255, version), nil, 'unknown slot has no guessed identity')
  T.eq(Catalog.isKnown('NonexistentMap', version), false, 'unlisted source symbol is not a known map')
  T.eq(Catalog.resolve('NonexistentMap', nil, version), 'NonexistentMap', 'unknown literal retained')
  T.eq(Catalog.slotKeyFor('NonexistentMap', version), nil, 'unknown literal has no physical slot')
  T.eq(Catalog.pretToEngine('', version), nil, 'empty source symbol declined')
  T.eq(Catalog.pretToEngine('MissingRoom_1F', version),
    ({firered='FR_',leafgreen='FR_',emerald='EM_',ruby='RU_',sapphire='SA_'})[version] .. 'MISSING_ROOM_1F',
    'spelling conversion does not register an unknown physical map')
  T.eq(Catalog.isKnown(Catalog.pretToEngine('MissingRoom_1F', version), version), false, 'conversion alone is not proof')
  return { version = version, canonical = out }
end
