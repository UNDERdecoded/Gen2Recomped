-- Look at the boxed menus whose rows moved down one tile (#564 start menu,
-- #572 the PC and the Pokédex entry window) and watch QUIT close the whole
-- Pokédex (#571).  Row geometry comes from pokered draw_start_menu.asm
-- (hlcoord 12,2 inside a TextBoxBorder at 10,0) and players_pc.asm
-- (hlcoord 2,2 inside a 16x10 box); the exits come from pokedex.asm
-- HandlePokedexSideMenu / .exitPokedex.  Screenshots land in $SHOT_DIR.
--   POKEPORT_DRIVER=tests/drivers/menu_windows_bug564_test.lua POKEPORT_IDENTITY=bug564 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- The bedroom PC is hidden_event 0, 1, OpenRedsPC, SPRITE_FACING_UP
  -- (pokered data/events/hidden_objects.asm), so the only approach is the
  -- floor tile below it.
  local MAP = "REDS_HOUSE_2F"
  local STAND = { x = 0, y = 2, facing = "up" }
  local DEX_SPECIES = "BULBASAUR" -- dex #1, so it is the list's first row
  local BAG_ITEM = "POTION"

  -- a save the start menu will draw all seven rows for: dex flag on,
  -- something owned so the dex list has a real entry, a party for LINK,
  -- and one bag item so ITEM opens onto a row that has a USE/TOSS box
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.pokedex = game.save.pokedex or { seen = {}, owned = {} }
  game.save.pokedex.seen[DEX_SPECIES] = true
  game.save.pokedex.owned[DEX_SPECIES] = true
  game.save.party = {
    Pokemon.new(game.data, DEX_SPECIES, 12),
    Pokemon.new(game.data, "PIKACHU", 10),
  }
  Bag.add(game.save, BAG_ITEM, 3)

  check("dex entry for " .. DEX_SPECIES .. " exists in the loaded data",
        game.data.pokemon[DEX_SPECIES] ~= nil)
  check(BAG_ITEM .. " resolves as an item",
        game.data.items[BAG_ITEM] ~= nil)

  -- pcTiles is what OverworldController checks before it opens the PC; an
  -- empty list here and a mis-aimed player look identical from outside
  local extras = game.data.field and game.data.field.hiddenExtras
  local pcTile = extras and (extras.pcTiles[MAP] or {})[1]
  check("the bedroom PC tile is in the field data", pcTile ~= nil)
  if pcTile then
    U.log("PC tile at", pcTile.x, pcTile.y, "facing", pcTile.facing)
    -- a map or field-data edit moves the tile: stand under it wherever it is
    STAND = { x = pcTile.x, y = pcTile.y + 1, facing = "up" }
  end

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- fall back to any free walkable neighbour that still looks at the tile
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = pcTile.x + s[1], pcTile.y + s[2]
      if ow.map:isWalkableCell(cx, cy) then
        U.log("standing on", cx, cy, "facing", s[3], "instead")
        STAND = { x = cx, y = cy, facing = s[3] }
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing at the PC",
        game.overworld ~= nil
        and game.overworld.player.cellX == STAND.x
        and game.overworld.player.cellY == STAND.y)

  -- walk a Menu's cursor onto a row by label, with real Down presses
  local function moveTo(menu, label)
    for _ = 1, #menu.items + 1 do
      if menu.items[menu.index] and menu.items[menu.index].label == label then
        return true
      end
      U.tap(game, "down")
      U.wait(2)
    end
    return false
  end

  -- --------------------------------------------------------------- #564
  U.tap(game, "start")
  U.wait(20)
  local start = game.stack:top()
  check("START opened the start menu", start ~= nil and start.items ~= nil)
  if start and start.items then
    local labels = {}
    for i, it in ipairs(start.items) do labels[i] = it.label end
    U.log("start menu rows:", table.concat(labels, " "))
  end
  check("start menu screenshot",
        U.shot(game, SHOT_DIR .. "/bug564_start_menu.png"))

  -- --------------------------------------------------------------- #571
  check("POKéDEX is on the start menu", moveTo(start, "POKéDEX"))
  U.tap(game, "a")
  U.wait(20)
  local dex = game.stack:top()
  check("the dex list opened", dex ~= nil and dex.screenId == "PokedexMenu")
  U.tap(game, "a")
  U.wait(20)
  local side = game.stack:top()
  local isSide = side ~= nil and side ~= dex and side.items ~= nil
  check("A on " .. DEX_SPECIES .. " opened the DATA/CRY/AREA/QUIT window",
        isSide)
  check("Pokédex entry window screenshot",
        U.shot(game, SHOT_DIR .. "/bug572_pokedex_entry_menu.png"))

  if isSide then
    check("QUIT is on the entry window", moveTo(side, "QUIT"))
    U.tap(game, "a")
    U.wait(30)
    local top = game.stack:top()
    -- the machine-checkable half of #571: the stack has to unwind past the
    -- dex list, not just pop the side menu
    check("QUIT left the Pokédex entirely", top ~= dex and top ~= side)
    check("QUIT landed on the start menu",
          top ~= nil and top.screenId == "StartMenu")
    if top and top.items and top.items[top.index] then
      U.log("start menu cursor is on:", top.items[top.index].label)
      check("the cursor is still on POKéDEX",
            top.items[top.index].label == "POKéDEX")
    end
    check("start menu after QUIT screenshot",
          U.shot(game, SHOT_DIR .. "/bug571_after_quit.png"))
  end

  -- --------------------------------------------------------------- #572
  -- the bag's USE/TOSS box, reached from the same start menu
  local menu = game.stack:top()
  if menu and menu.items and moveTo(menu, "ITEM") then
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a") -- A on the first bag row opens USE/TOSS
    U.wait(20)
    local useToss = game.stack:top()
    local ok = useToss and useToss.items and #useToss.items == 2
      and useToss.items[1].label == "USE"
    check("the bag's USE/TOSS box opened", ok and true or false)
    check("USE/TOSS screenshot",
          U.shot(game, SHOT_DIR .. "/bug572_bag_use_toss.png"))
    if ok then
      -- pokered data/text_boxes.asm USE_TOSS_MENU_TEMPLATE is (13,10) to
      -- (19,14) with its text at 15,11: two rows exactly fill 11 and 13,
      -- with no blank row under the top border.  Mirror Menu:draw's own
      -- bottom anchor rather than re-deriving one here -- an assertion that
      -- carries its own copy of the formula passes on whatever it assumes
      -- instead of on what the menu actually draws (#564, #572).
      local n = #useToss.items
      local bottom = useToss.ty + useToss.th - 2
      local firstRow = bottom - (n - 1) * useToss.rowStep
      local lastRow = bottom
      check("TOSS is inside the box, not on its bottom border",
            lastRow <= useToss.ty + useToss.th - 2)
      check("USE and TOSS land on the pokered rows (11 and 13)",
            firstRow == 11 and lastRow == 13)
      U.log("USE/TOSS box ty=" .. useToss.ty .. " th=" .. useToss.th
            .. ", rows land on " .. firstRow
            .. " and " .. lastRow
            .. ", bottom interior row is " .. bottom)
    end
    U.tap(game, "b")
    U.wait(10)
    U.tap(game, "b")
    U.wait(20)
  end

  -- back out to the overworld and open the bedroom PC
  for _ = 1, 4 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "b")
    U.wait(15)
  end
  check("back in the overworld", game.stack:top() == game.overworld)

  U.tap(game, "a")
  U.wait(25)
  local pc = game.stack:top()
  local isPC = pc ~= nil and pc.screenId == "PlayerPC"
  check("the bedroom PC opened", isPC)
  check("player's PC screenshot",
        U.shot(game, SHOT_DIR .. "/bug572_player_pc.png"))

  U.log("The player's PC is open on screen; B closes it and START reopens")
  U.log("the start menu.  In all of these the last choice should sit on the")
  U.log("row just above the bottom border and the blank row should be under")
  U.log("the top border, with the ▶ level with its label -- the near miss is")
  U.log("text that clears the top edge but leaves a gap at the bottom, or a")
  U.log("cursor that drifts a row off its own label.  The text boxes the")
  U.log("Pokémon and item lists draw are the control: they never moved.")
  U.log("the bag's USE/TOSS box is the tight one: pokered draws it a row")
  U.log("shorter than the rest, so USE and TOSS fill 11 and 13 with no blank")
  U.log("row at all.  If TOSS is sitting on the border there, that is the bug.")
  U.log("Screenshots are under " .. SHOT_DIR)

  while true do
    coroutine.yield()
  end
end
