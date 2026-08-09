-- Ad-hoc inspector: dumps the disassembled IR and the lowered rows for a few
-- maps so the scene/coord wiring can be checked against the real game.
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_script_dump.lua love .
return function(game)
  local Data = require("src.core.Data")
  local mapScripts = require("data.scripts.init")
  local store = Data.map_scripts

  local function dumpScript(label, indent, seen)
    seen = seen or {}
    if seen[label] or not label or label == "" then return end
    seen[label] = true
    local rows = store.scripts[label]
    if not rows then print(indent .. label .. " <missing>"); return end
    print(indent .. label .. ":")
    for _, row in ipairs(rows) do
      local parts = {}
      for i = 2, #row do parts[#parts + 1] = tostring(row[i]) end
      print(indent .. "  " .. row[1] .. " " .. table.concat(parts, ", "))
    end
  end

  for _, mapId in ipairs({ "ELMS_LAB", "CHERRYGROVE_CITY", "ROUTE29",
                           "MR_POKEMONS_HOUSE", "MRPOKEMONSHOUSE" }) do
    local entry = store.maps[mapId]
    print("=== " .. mapId .. " " .. (entry and "" or "<no entry>"))
    if entry then
      for i, label in ipairs(entry.scenes or {}) do
        print("  scene " .. i)
        dumpScript(label, "    ")
      end
      for i, cb in ipairs(entry.callbacks or {}) do
        print("  callback " .. i .. " type " .. tostring(cb.type))
        dumpScript(cb.script, "    ")
      end
      for i, coord in ipairs(entry.coords or {}) do
        print(string.format("  coord %d scene=%s x=%s y=%s",
          i, tostring(coord.scene), tostring(coord.x), tostring(coord.y)))
        dumpScript(coord.script, "    ")
      end
    end
    local view = mapScripts.get(mapId)
    local keys = {}
    for k in pairs(view or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    print("  contribution keys: " .. table.concat(keys, ", "))
  end

  love.event.quit(0)
end
