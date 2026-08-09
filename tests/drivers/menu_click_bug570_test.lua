-- Ear check: the menu click on backing out of POKéDEX / POKéMON / ITEM /
-- OPTION, on the first A on an item in ITEM, and on A over CANCEL in OPTION
-- (#570).  HandleMenuInput_ (home/window.asm) replays SFX_PRESS_AB for the
-- PAD_A | PAD_B half of a menu's watched keys; DisplayOptionMenu beeps only
-- at .exitMenu (engine/menus/main_menu.asm).  Silence where the original is
-- silent counts too, so this walks the mute cases as well.  Invariants are in
-- tests/engine/menu_click_bug570.lua.
--   POKEPORT_DRIVER=tests/drivers/menu_click_bug570_test.lua POKEPORT_IDENTITY=bug570 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
-- No POKEPORT_SPEED: it scales the logic clock only while audio runs on its own
-- real-time accumulator in Game:update, so it desyncs the exact ordering of
-- press and click that this run exists to judge.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local ListMenu = require("src.ui.ListMenu")
  local Menu = require("src.ui.Menu")
  local OptionsMenu = require("src.ui.OptionsMenu")
  local PartyMenu = require("src.ui.PartyMenu")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")
  local Strings = require("src.core.Strings")

  -- pokered data/maps/objects/PalletTown.asm: OAK at (8,5), the girl at (3,8),
  -- the fisher at (11,14), warps at (5,5), (13,5) and (12,11).  (10,7) is clear
  -- of all of them and off every mat; the menus are what is being judged, the
  -- cell only has to be somewhere the start menu opens.
  local MAP = "PALLET_TOWN"
  local STAND = { x = 10, y = 7, facing = "down" }
  local PARTY = { { "BULBASAUR", 12 }, { "PIDGEY", 9 } }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the ear cannot check -----------------------------------------
  local opts = game.save.options or {}
  local musicVol = opts.musicVol or 7
  local sfxVol = opts.sfxVol or 7
  if sfxVol == 0 then
    U.log("FAIL SFX volume is 0. Every claim below is about a click that is or")
    U.log("     is not there, and at 0 none of them are. Set SFX to 7 in OPTION")
    U.log("     and run this again, or the whole check is worthless.")
  end
  if musicVol == 0 then
    U.log("FAIL MUSIC volume is 0, so Pallet Town's theme is gone and there is")
    U.log("     nothing to tell a dead audio device from a missing click.")
    U.log("     Set MUSIC to 7 in OPTION.")
  end
  check(("SFX volume %d, MUSIC volume %d"):format(sfxVol, musicVol),
        sfxVol > 0 and musicVol > 0)

  -- an unresolved sfx key is silent in exactly the way the bug was
  local sfx = (game.data.audio or {}).sfx or {}
  for _, key in ipairs({ "Press_AB", "Start_Menu", "Swap" }) do
    check("sfx " .. key .. " is in the cache", sfx[key] ~= nil)
  end

  -- every cue the run makes, forwarded so playback is untouched
  local cues = {}
  local realPlay = Sound.play
  Sound.play = function(data, name)
    cues[#cues + 1] = name
    return realPlay(data, name)
  end
  local function since(mark)
    local clicks, others = 0, {}
    for i = mark + 1, #cues do
      if cues[i] == "Press_AB" then clicks = clicks + 1
      else others[#others + 1] = cues[i] end
    end
    return clicks, others
  end

  -- one press, then long enough for the click to be its own sound
  local function press(btn, want, label)
    local mark = #cues
    U.tap(game, btn)
    U.wait(28)
    local clicks, others = since(mark)
    local note = ""
    if #others > 0 then note = "  (also: " .. table.concat(others, ", ") .. ")" end
    check(("%s: %s gave %d click%s, expected %d%s")
            :format(label, btn:upper(), clicks, clicks == 1 and "" or "s",
                    want, note),
          clicks == want)
    return clicks
  end

  local function top() return game.stack:top() end
  local function isA(class) return getmetatable(top()) == class end

  -- ---- set the save up so every start-menu row is live --------------------
  game.save.party = {}
  for _, slot in ipairs(PARTY) do
    table.insert(game.save.party, Pokemon.new(game.data, slot[1], slot[2]))
  end
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_POKEDEX = true -- StartMenu hides POKéDEX without it
  game.save.pokedex = game.save.pokedex or { seen = {}, owned = {} }
  for _, id in ipairs({ "BULBASAUR", "PIDGEY", "RATTATA" }) do
    game.save.pokedex.seen[id] = true
    game.save.pokedex.owned[id] = true
  end
  Bag.add(game.save, "POTION", 3)
  Bag.add(game.save, "ANTIDOTE", 2)
  game.save.startMenuIndex = 1

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit blocked the cell: any free walkable neighbour will do
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(20)
        ow = game.overworld
        break
      end
    end
  end
  check("standing on " .. MAP, ow ~= nil and ow.map.id == MAP)
  -- the girl and the fisher both WALK: pin them so the map under the menus
  -- looks the same on every run and in every screenshot
  for _, n in ipairs((ow or {}).npcs or {}) do n.frozen = true end

  -- ---- walk the menus -----------------------------------------------------
  press("start", 0, "opening the start menu is silent (its own Start_Menu "
        .. "cue is not the A/B click)")
  check("the start menu is up", isA(Menu))

  -- rows come and go with save state and the ui.start_menu.items hook, so
  -- find each one by label rather than counting cursor steps
  local function rowIndex(label)
    for i, item in ipairs(top().items or {}) do
      if item.label == label then return i end
    end
    return nil
  end
  local function openRow(label)
    local menu = top()
    local i = rowIndex(label)
    if not i then
      check("the start menu has a " .. label .. " row", false)
      return false
    end
    menu.index = i
    menu:clampScroll()
    press("a", 1, "A on " .. label .. " clicks")
    return true
  end

  if openRow(Strings("POKéDEX")) then
    check("the POKéDEX list opened", isA(ListMenu))
    U.shot(game, DIR .. "/bug570_1_pokedex.png")
    press("b", 1, "backing out of POKéDEX clicks (#570)")
    check("and the start menu came back", isA(Menu))
  end

  if openRow(Strings("POKéMON")) then
    check("the party menu opened", getmetatable(top()) == PartyMenu)
    press("b", 1, "backing out of POKéMON clicks (#570)")
    check("and the start menu came back", isA(Menu))
  end

  if openRow(Strings("ITEM")) then
    check("the bag opened", isA(ListMenu))
    check("the bag has items to click on", #(top().items or {}) > 0)
    press("a", 1, "the first A on an item in ITEM clicks (#570)")
    check("the USE / TOSS submenu opened", isA(Menu))
    U.shot(game, DIR .. "/bug570_2_bag_usetoss.png")
    press("b", 1, "backing out of USE / TOSS clicks")
    check("back on the item list", isA(ListMenu))
    -- SELECT is inside DisplayListMenuID's watched mask but outside its
    -- PAD_A | PAD_B sound test (home/list_menu.asm), so arming a swap is
    -- silent and completing it makes the swap chirp, not the menu click
    press("select", 0, "SELECT arms a swap without clicking")
    press("select", 0, "and completing it chirps instead of clicking")
    press("b", 1, "backing out of ITEM clicks (#570)")
    check("and the start menu came back", isA(Menu))
  end

  if openRow(Strings("OPTION")) then
    check("the options screen opened", getmetatable(top()) == OptionsMenu)
    press("right", 0, "the Left/Right toggles are silent")
    press("left", 0, "in both directions")
    -- up from the first row wraps onto CANCEL, which sits one past the rows
    press("up", 0, "moving the cursor is silent")
    check("the cursor is on CANCEL",
          top().index == #top().rows + 1)
    U.shot(game, DIR .. "/bug570_3_option_cancel.png")
    press("a", 1, "A on CANCEL in OPTION clicks (#570)")
    check("and the start menu came back", isA(Menu))
  end

  if openRow(Strings("OPTION")) then
    press("b", 1, "B out of OPTION clicks too (#570)")
    check("and the start menu came back", isA(Menu))
  end

  press("start", 0, "START closes the start menu silently: draw_start_menu's "
        .. "mask watches it, but it is not in the PAD_A | PAD_B sound branch")
  check("back on the map", top() == game.overworld)

  -- ---- over to you --------------------------------------------------------
  U.log("The run above already pressed all of it; do it again by ear. Open START,")
  U.log("go into POKéDEX, POKéMON, ITEM and OPTION and back out of each with B.")
  U.log("Every one of those B presses makes the same short click that A on the")
  U.log("row made going in, the first A on an item in ITEM makes it, and A on")
  U.log("CANCEL in OPTION closes it with it. #570 was silence on all of those.")
  U.log("The near miss is a click at the wrong moment: OPTION's Left/Right")
  U.log("toggles and its A on a setting row stay silent, START opens and closes")
  U.log("the start menu with its own longer cue and no click, and SELECT in the")
  U.log("bag chirps a swap rather than clicking.")
  U.log("Shots: " .. DIR .. "/bug570_*.png")

  -- keeps printing the cue stream after the hand-off, so a click that lands a
  -- beat late reads as a late line rather than as the right sound
  local reported = #cues
  while true do
    if #cues > reported then
      for i = reported + 1, #cues do
        U.log("cue", cues[i], "frame", U.frame())
      end
      reported = #cues
    end
    coroutine.yield()
  end
end
