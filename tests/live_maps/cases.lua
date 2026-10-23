local M = {}
function M.run(f)
  local T, e, rows = f.T, f.e, {}
  f.rebuild()
  if f.commonEvents then
    T.eq(#e.events, 2, "native rebuild emits one pair")
    T.eq(e.events[1].phase, "preparing", "preparing arrives first")
    T.eq(e.events[2].phase, "updated", "updated arrives last")
    T.eq(f.phase[1].preparing, true, "native preparation flag is set")
    T.eq(f.phase[1].ghosts, 1, "preparing precedes ghost rebuild")
    T.eq(f.phase[2].preparing, false, "updated observes settled preparation")
    T.eq(f.phase[2].ghosts, 0, "updated follows ghost rebuild")
    for _, event in ipairs(e.events) do
      T.eq(event.mapId, "ROOT", "event identifies active map")
      T.eq(#event.maps, 3, "event includes active and connected maps")
      T.eq(event.maps[1].mapId, "ROOT", "active placement first")
      T.eq(event.maps[1].active, true, "active flag")
      T.eq(event.maps[2].ox, 2 * f.pixel, "east offset is pixels")
      T.eq(event.maps[2].oy, -f.pixel, "negative offset preserved")
      rows[#rows + 1] = event
    end
    e.events[1].maps[1].mapId = "changed-copy"
    T.eq(f.world.map.id, "ROOT", "event mutation cannot change native map")
    e.events[1].maps[1].mapId = "ROOT"
  end
  if f.api >= 3 then
    local before = f.loaderCalls()
    local maps = assert(e.maps())
    T.eq(#maps, 3, "API-3 query reports loaded maps")
    T.eq(maps[1].ox, 0, "API-3 active x is pixels")
    T.eq(maps[2].ox, 2 * f.pixel, "API-3 neighbor x is pixels")
    T.eq(maps[2].oy, -f.pixel, "API-3 neighbor y is pixels")
    T.eq(maps[2].x, nil, "API-3 does not substitute cell coordinates")
    T.eq(f.loaderCalls(), before, "query never loads a map")
    maps[2].ox = 999
    T.eq(e.maps()[2].ox, 2 * f.pixel, "query returns detached placements")
    rows[#rows + 1] = { query = e.maps() }
  end
  return rows
end
return M
