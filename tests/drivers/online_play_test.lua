-- Driver: screenshots the new online-play menu surface (LinkState's
-- restructured top menu, the online host/join flow). Pushed directly
-- (bypassing Start-menu navigation, matching options_test.lua's
-- convention) so it doesn't depend on party/save state.
--
-- Run with no mods discoverable (mod enable/disable only takes effect at
-- the next boot -- see Handshake.onlineAllowed's comment -- so a live
-- toggle can't simulate "vanilla" mid-session; the mod directory has to
-- actually be absent for this run).
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")

  local LinkState = require("src.link.LinkState")

  local function closeAnyOpenScreens()
    while game.stack:top() and game.stack:top().exitWith do
      game.stack:top():exitWith(nil)
      U.wait(2)
    end
  end

  -- top menu (3 rows: LAN / ONLINE MATCH / TOURNAMENT)
  game.stack:push(LinkState.new(game))
  U.wait(5)
  U.shot(game, DIR .. "/link_0_top_menu.png")
  U.tap(game, "down"); U.wait(2)
  U.shot(game, DIR .. "/link_1_top_menu_online.png")

  -- ONLINE MATCH -> HOST ONLINE (needs pokeserver reachable at the
  -- default relay address; POKEPORT_RELAY_ADDR overrides)
  U.tap(game, "a"); U.wait(3) -- into onlineMenu
  U.shot(game, DIR .. "/link_2_online_menu.png")
  U.tap(game, "a"); U.wait(20) -- HOST ONLINE -> connect
  U.shot(game, DIR .. "/link_3_online_hosting.png")

  -- back out, try JOIN ONLINE's code-entry screen
  closeAnyOpenScreens()
  game.stack:push(LinkState.new(game))
  U.wait(5)
  U.tap(game, "down"); U.wait(2) -- ONLINE MATCH row
  U.tap(game, "a"); U.wait(3)
  U.tap(game, "down"); U.wait(2) -- JOIN ONLINE row
  U.tap(game, "a"); U.wait(3)
  U.shot(game, DIR .. "/link_4_code_entry.png")
  U.tap(game, "up"); U.wait(1)
  U.tap(game, "right"); U.wait(1)
  U.shot(game, DIR .. "/link_5_code_entry_scrubbed.png")
  closeAnyOpenScreens()

  U.log("ONLINE_PLAY_DRIVER: done")
end
