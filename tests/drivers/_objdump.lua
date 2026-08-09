-- scratch: dump a Gen2 map's object_events and the collision under each,
-- to compare index-for-index with the ROM's <Map>_MapEvents table.
--   OBJMAP=TEAM_ROCKET_BASE_B2F
local U = require("tests.drivers.util")

return function(game)
  U.newGame(game)
  U.wait(5)
  local want = os.getenv("OBJMAP") or ""
  for id in want:gmatch("[^,]+") do
    id = id:gsub("^%s+", ""):gsub("%s+$", "")
    local def = game.data.maps[id]
    if not def then
      U.log(("=== %s (NOT FOUND)"):format(id))
    else
      U.log(("=== %s  %dx%d blocks"):format(id, def.width or 0, def.height or 0))
      for i, o in ipairs(def.objects or {}) do
        U.log(("  obj %2d  (%2s,%2s) %-22s move=%-4s idx=%s script=%s"):format(
          i, tostring(o.x), tostring(o.y), tostring(o.sprite),
          tostring(o.movement), tostring(o.index), tostring(o.script)))
      end
      for i, w in ipairs(def.warps or {}) do
        U.log(("  warp %2d (%2s,%2s) -> %s"):format(i, tostring(w.x),
          tostring(w.y), tostring(w.destMap)))
      end
    end
  end
  U.log("RESULT PASS")
end
