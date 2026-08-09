-- Driver: regression coverage for #203 "You can't fly to indigo plateau".
--
-- pret/pokered engine/menus/town_map.asm LoadTownMap_Fly cycles EVERY visited
-- fly destination, and Indigo Plateau is a normal Fly spot once reached (its
-- special-warp lands the player on the Plateau exterior, data/maps/
-- special_warps.asm).  The port's fly-list filter gated each entry on
-- Map.isOutdoor(def), which is tileset == "OVERWORLD" -- but Indigo Plateau's
-- map uses tileset "PLATEAU", so it was silently dropped from the fly cursor
-- even though it is visited, has a fly warp, and sits in flyOrder.  This driver
-- walks the party-menu FLY flow, asserts INDIGO_PLATEAU is a cyclable fly
-- destination, flies there, and lands on the Plateau exterior.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- Party slot 1 knows FLY.  Pokemon.movesAtLevel never grants FLY, so inject
  -- the move directly after construction (same setup as the #195 driver).
  local flyer = Pokemon.new(game.data, "PIDGEOT", 40)
  flyer.moves[1] = { id = "FLY", pp = 15 }
  game.save.party = { flyer }
  game.save.player.name = "bryan"
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.THUNDERBADGE = true -- FLY submenu entry is badge-gated
  game.save.visited = {
    PALLET_TOWN = true, VIRIDIAN_CITY = true, INDIGO_PLATEAU = true,
  }

  -- Exercise the real visited-marking path (OverworldController marks any
  -- flyWarps map visited on entry) by standing on the Plateau exterior first,
  -- then hop back to Pallet for a clean starting point.
  U.teleport(game, "INDIGO_PLATEAU", 9, 6, "down")
  U.wait(5)
  assert(game.save.visited.INDIGO_PLATEAU,
    "entering the Plateau exterior must mark INDIGO_PLATEAU visited")
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(5)

  -- open the party menu and pick FLY on slot 1 (submenu: STATS / SWITCH / FLY)
  Screens.push(game, "PartyMenu")
  U.wait(5)
  U.tap(game, "a")    -- open the per-mon submenu
  U.wait(2)
  U.tap(game, "down") -- STATS -> SWITCH
  U.wait(2)
  U.tap(game, "down") -- SWITCH -> FLY
  U.wait(2)
  U.tap(game, "a")    -- choose FLY
  U.wait(5)

  local top = game.stack:top()
  U.shot(game, DIR .. "/fly_map_screen.png")
  U.wait(4) -- let the async png write land before any assert can quit us

  U.log("fly screen top screenId:", tostring(top and top.screenId),
        "fly=", tostring(top and top.fly), "mode=", tostring(top and top.mode))
  local isFlyMap = top ~= nil and top.fly == true
                   and top.locs ~= nil and top.mode ~= nil
  assert(isFlyMap,
    "FLY must open the TOWN MAP in fly mode (LoadTownMap_Fly), got screen '"
    .. tostring(top and top.screenId or "nil") .. "' fly="
    .. tostring(top and top.fly))

  -- KEY ASSERTION (the #203 bug): INDIGO_PLATEAU must be a cyclable fly
  -- destination.  Before the fix the isOutdoor gate drops the PLATEAU-tileset
  -- Plateau, so this list is missing it and the assert fails.
  local hasIndigo = false
  local listStr = {}
  for i, id in ipairs(top.flyMapIds or {}) do
    listStr[i] = id
    if id == "INDIGO_PLATEAU" then hasIndigo = true end
  end
  U.log("fly destinations:", table.concat(listStr, ", "))
  assert(hasIndigo,
    "INDIGO_PLATEAU must appear in the fly destination list (it is visited, "
    .. "has a fly warp, and is in flyOrder); got { "
    .. table.concat(listStr, ", ") .. " }")

  -- walk the cursor to INDIGO PLATEAU (banner reads "To INDIGO PLATEAU")
  local function selectedMap()
    return top.flyMapIds and top.flyMapIds[top.sel]
  end
  U.log("initial fly selection:", tostring(selectedMap()))
  local guard = 0
  while selectedMap() ~= "INDIGO_PLATEAU" and guard < 12 do
    U.tap(game, "down")
    U.wait(2)
    guard = guard + 1
  end
  assert(selectedMap() == "INDIGO_PLATEAU",
    "Up/Down must cycle the fly cursor to INDIGO_PLATEAU, landed on "
    .. tostring(selectedMap()))
  U.shot(game, DIR .. "/fly_indigo_selected.png")
  U.wait(4)

  -- A flies to the highlighted destination: flyTo departs (48-frame bird),
  -- then warps to the Plateau exterior.
  U.tap(game, "a")
  U.wait(3)
  assert(game.overworld and game.overworld.flyDest
         and game.overworld.flyDest.map == "INDIGO_PLATEAU",
    "pressing A on the fly map must start the departure to INDIGO_PLATEAU, got "
    .. tostring(game.overworld and game.overworld.flyDest
                and game.overworld.flyDest.map))

  -- past the bird sweep + warp transition: the player lands on the Plateau
  local landed = false
  for _ = 1, 240 do
    if game.overworld and game.overworld.map
       and game.overworld.map.id == "INDIGO_PLATEAU" then
      landed = true
      break
    end
    U.wait(1)
  end
  U.wait(6)
  U.shot(game, DIR .. "/fly_landed_indigo.png")
  U.wait(4)
  assert(landed, "Fly must land the player on INDIGO_PLATEAU, ended on "
    .. tostring(game.overworld and game.overworld.map and game.overworld.map.id))

  U.log("RESULT bug203 PASS")
end
