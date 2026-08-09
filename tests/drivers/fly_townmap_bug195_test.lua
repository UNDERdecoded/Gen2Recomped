-- Driver: regression coverage for #195 "Fly doesn't show the map".
--
-- pret/pokered engine/menus/town_map.asm LoadTownMap_Fly: choosing FLY from
-- the party field-move submenu opens the TOWN MAP with a blinking cursor that
-- cycles ONLY the visited fly destinations (Up/Down), A flies there, B cancels.
-- The port used to push a plain "FLY TO?" ListMenu (src/ui/FlyMenu.lua)
-- instead -- a text list, never the map (the how-it-is screenshot).  This
-- driver walks Fly and asserts the TOWN MAP fly screen appears, that Up/Down
-- cycle the visited towns, and that A actually flies.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- Party slot 1 knows FLY.  Pokemon.movesAtLevel never grants FLY, so inject
  -- the move directly after construction.
  local flyer = Pokemon.new(game.data, "PIDGEOT", 40)
  flyer.moves[1] = { id = "FLY", pp = 15 }
  game.save.party = { flyer }
  game.save.player.name = "bryan"
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.THUNDERBADGE = true -- FLY submenu entry is badge-gated
  game.save.visited = {
    PALLET_TOWN = true, VIRIDIAN_CITY = true, PEWTER_CITY = true,
    CERULEAN_CITY = true, CELADON_CITY = true,
  }

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

  -- The cursor cycles ONLY the visited fly towns.  Walk it to CELADON CITY.
  local function selectedMap()
    return top.flyMapIds and top.flyMapIds[top.sel]
  end
  U.log("initial fly selection:", tostring(selectedMap()))
  local guard = 0
  while selectedMap() ~= "CELADON_CITY" and guard < 12 do
    U.tap(game, "down")
    U.wait(2)
    guard = guard + 1
  end
  assert(selectedMap() == "CELADON_CITY",
    "Up/Down must cycle the fly cursor to CELADON_CITY, landed on "
    .. tostring(selectedMap()))
  U.shot(game, DIR .. "/fly_celadon_selected.png")
  U.wait(4)

  -- A flies to the highlighted town: flyTo departs (48-frame bird), then warps.
  U.tap(game, "a")
  U.wait(3)
  assert(game.overworld and game.overworld.flyDest
         and game.overworld.flyDest.map == "CELADON_CITY",
    "pressing A on the fly map must start the departure to CELADON_CITY, got "
    .. tostring(game.overworld and game.overworld.flyDest
                and game.overworld.flyDest.map))

  -- past the bird sweep + warp transition: the player lands in Celadon
  local landed = false
  for _ = 1, 240 do
    if game.overworld and game.overworld.map
       and game.overworld.map.id == "CELADON_CITY" then
      landed = true
      break
    end
    U.wait(1)
  end
  U.wait(6)
  U.shot(game, DIR .. "/fly_landed.png")
  U.wait(4)
  assert(landed, "Fly must land the player in CELADON_CITY, ended on "
    .. tostring(game.overworld and game.overworld.map and game.overworld.map.id))

  U.log("RESULT bug195 PASS")
end
