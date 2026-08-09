-- Driver: Gen 2 FLY opens the TOWN MAP with a cursor over the visited
-- landmarks (engine/menus/town_map.asm LoadTownMap_Fly / FlyFunction).
--
-- GSC keeps no fly-warp table at all -- picking a landmark off the map sets
-- wDefaultSpawnpoint and LoadSpawnPoint warps there -- so the port shipped
-- `field.flyWarps` AND `field.flyOrder` empty for Gen 2 and the picker had
-- nothing whatever to cycle: FLY opened a map with no cursor on it and no
-- way to depart.  Both are now derived from SpawnPoints
-- (RomExtractorGen2:gen2FlyWarps / gen2FlyOrder), in the landmark order the
-- map is drawn in.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local pass, fail = 0, 0
  local function check(what, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "  ok   " or "  FAIL ") .. what)
  end

  -- 1. the extracted tables
  U.log("1. the fly tables")
  local field = game.data.field or {}
  local order = field.flyOrder or {}
  local warps = field.flyWarps or {}
  check("field.flyOrder is populated", #order > 0)
  check("field.flyWarps is populated", next(warps) ~= nil)
  check("NEW_BARK_TOWN is first (landmark 1)", order[1] == "NEW_BARK_TOWN")
  local inOrder = {}
  for _, id in ipairs(order) do inOrder[id] = true end
  check("GOLDENROD_CITY is a destination", inOrder.GOLDENROD_CITY == true)
  check("a Kanto town is in the list too", inOrder.PALLET_TOWN == true)
  check("no Pokemon Center is offered", inOrder.AZALEA_POKECENTER1_F ~= true)

  -- 2. entering a town marks it visited, which is what the picker filters on
  U.log("2. visiting towns")
  game.save.player = game.save.player or {}
  game.save.player.name = "bryan"
  game.save.visited = {}
  for _, id in ipairs({ "VIOLET_CITY", "AZALEA_TOWN", "GOLDENROD_CITY",
                        "PALLET_TOWN", "NEW_BARK_TOWN" }) do
    local at = warps[id]
    if at then U.teleport(game, id, at.x, at.y, "down") end
  end
  U.wait(6)
  local visited = game.save.visited or {}
  check("VIOLET_CITY was marked visited on entry", visited.VIOLET_CITY == true)
  check("PALLET_TOWN was marked visited on entry", visited.PALLET_TOWN == true)

  -- 3. the picker itself
  U.log("3. the FLY picker")
  local flew = nil
  Screens.push(game, "TownMap",
               { fly = true, onFly = function(id) flew = id end })
  U.wait(4)
  local map = game.stack:top()
  check("FLY opened the town map", map ~= nil and map.locs ~= nil)
  check("it is in fly mode, not the plain viewer", map ~= nil and map.fly == true)
  check("it is the Gen 2 two-picture map", map ~= nil and map.mode == "gen2")
  if not (map and map.fly) then
    U.log(("RESULT FAIL (%d pass, %d fail)"):format(pass, fail))
    return false
  end
  local ids = map.flyMapIds or {}
  check("the cursor has the visited towns to cycle", #map.locs >= 4)
  local names = {}
  for i = 1, #map.locs do names[i] = ids[i] or "?" end
  U.log("  destinations: " .. table.concat(names, ", "))
  U.shot(game, (os.getenv("SHOT_DIR") or "shots") .. "/gen2_fly_johto.png")
  U.wait(4)

  -- 4. the cursor walks them, and the banner names where it stands
  U.log("4. the cursor")
  local function selected() return ids[map.sel] end
  local start = selected()
  U.tap(game, "down"); U.wait(3)
  check("DOWN moved the cursor", selected() ~= start)
  U.tap(game, "up"); U.wait(3)
  check("UP brought it back", selected() == start)
  local guard = 0
  while selected() ~= "PALLET_TOWN" and guard < 24 do
    U.tap(game, "down"); U.wait(2)
    guard = guard + 1
  end
  check("the cursor reaches PALLET_TOWN", selected() == "PALLET_TOWN")
  -- the picture has to turn the page with it, or a Kanto town is picked blind
  check("the map turned to KANTO with it", map.region == "kanto")
  U.shot(game, (os.getenv("SHOT_DIR") or "shots") .. "/gen2_fly_kanto.png")
  U.wait(4)
  local loc = map.locs[map.sel]
  check("the banner reads 'To <NAME>'",
        loc ~= nil and map:bannerText(loc):find("^To ") ~= nil)
  check("the cursor stands on a real landmark",
        loc ~= nil and tonumber(loc.px) ~= nil and tonumber(loc.py) ~= nil)

  -- 5. A departs
  U.log("5. departure")
  U.tap(game, "a")
  U.wait(4)
  check("A flies to the highlighted town", flew == "PALLET_TOWN")
  check("the picker closed", game.stack:top() ~= map)

  U.log(("RESULT %s (%d pass, %d fail)")
        :format(fail == 0 and "PASS" or "FAIL", pass, fail))
  return fail == 0
end
