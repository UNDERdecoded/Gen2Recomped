-- Fly destination picker: visited towns, landing at the real fly-warp
-- spots from data/maps/special_warps.asm.

local ListMenu = require("src.ui.ListMenu")
local Map = require("src.world.Map")

local FlyMenu = {}

function FlyMenu.new(game, opts)
  local items = {}
  local visited = game.save.visited or {}
  local seen = {}
  local warps = (game.data.field or {}).flyWarps or {}
  for _, mapId in ipairs((game.data.field or {}).flyOrder or {}) do
    -- towns only (dungeon escape spots share the table), each listed once.
    -- Indigo Plateau (tileset PLATEAU) is a valid Fly destination too, so allow
    -- it past the OVERWORLD-only isOutdoor gate while the CAVERN/FACILITY escape
    -- spots stay excluded (LoadTownMap_Fly cycles it like any town, #203).
    local def = game.data.maps[mapId]
    if visited[mapId] and def and not seen[mapId]
       and (Map.isOutdoor(def) or def.tileset == "PLATEAU") then
      seen[mapId] = true
      -- THE NAME THE PLAYER KNOWS IT BY.  Kanto's map ids read as their own
      -- town names, so the old label was the id with the underscores taken
      -- out.  Hoenn's are MAP_G00_N09, which is nobody's idea of Littleroot
      -- -- so the region-map section name the fly warp carries wins where
      -- there is one, and the id stays the fallback for the generations that
      -- never needed it.
      local warp = warps[mapId]
      table.insert(items, {
        value = mapId,
        label = (warp and warp.name) or mapId:gsub("_", " "),
      })
    end
  end
  return ListMenu.new(game, "FLY TO?", items, {
    onChoose = function(item, list)
      list:close()
      -- the caller may want the choice rather than the flight itself: the
      -- Gen 3 party menu opens this in place of the TOWN MAP screen
      if opts and opts.onFly then return opts.onFly(item.value) end
      game.overworld:flyTo(item.value)
    end,
  })
end

return FlyMenu
