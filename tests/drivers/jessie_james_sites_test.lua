-- Driver: the three post-Mt-Moon Jessie & James ambushes
-- (data/scripts/yellow_jessie_james.lua).  Yellow only:
--   POKEPORT_VERSION=yellow POKEPORT_DRIVER=tests/drivers/jessie_james_sites_test.lua love .
-- For each site: step onto the trigger tile, A-mash through motto /
-- challenge / battle / parting lines, then confirm the beat flag is set
-- and both duo objects are gone.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")

  -- A-mash needs a damaging first move (a stat move stalls the mash)
  game.save.party = {}
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "TACKLE", pp = 35 } }
  table.insert(game.save.party, mon)

  local sites = {
    { tag = "hideout", map = "ROCKET_HIDEOUT_B4F", tx = 24, ty = 14,
      beat = "EVENT_BEAT_ROCKET_HIDEOUT_4_JESSIE_JAMES",
      james = "ROCKETHIDEOUTB4F_JAMES", jessie = "ROCKETHIDEOUTB4F_JESSIE" },
    { tag = "tower", map = "POKEMON_TOWER_7F", tx = 10, ty = 12,
      beat = "EVENT_BEAT_POKEMONTOWER_7_JESSIE_JAMES",
      james = "POKEMONTOWER7F_JAMES", jessie = "POKEMONTOWER7F_JESSIE" },
    { tag = "silph", map = "SILPH_CO_11F", tx = 3, ty = 3,
      beat = "EVENT_BEAT_SILPH_CO_11F_JESSIE_JAMES",
      james = "SILPHCO11F_JAMES", jessie = "SILPHCO11F_JESSIE" },
  }

  local function visible(ow, name)
    for _, n in ipairs(ow.npcs) do
      if n.def and n.def.name == name then return true end
    end
    return false
  end

  for _, s in ipairs(sites) do
    -- heal between fights and re-arm the site
    for _, m in ipairs(game.save.party) do
      m.hp = m.stats.hp
      m.moves[1].pp = 35
    end
    game.save.flags[s.beat] = nil

    -- step onto the trigger from below; fall back to above if blocked
    U.teleport(game, s.map, s.tx, s.ty + 1, "up")
    local ow = game.overworld
    U.hold(game, "up", 20)
    U.wait(10)
    if not ow.runner:isRunning()
       and (ow.player.cellX ~= s.tx or ow.player.cellY ~= s.ty) then
      U.teleport(game, s.map, s.tx, s.ty - 1, "down")
      ow = game.overworld
      U.hold(game, "down", 20)
      U.wait(10)
    end
    U.log(s.tag, "player at", ow.player.cellX, ow.player.cellY,
          "runner:", tostring(ow.runner:isRunning()))
    U.shot(game, DIR .. ("/jj_%s_0_trigger.png"):format(s.tag))

    local settled = false
    for i = 1, 3000 do
      if game.stack:top() == ow and not ow.runner:isRunning()
         and #ow.scriptMoves == 0 and game.save.flags[s.beat] then
        settled = true
        break
      end
      if i == 120 then
        U.shot(game, DIR .. ("/jj_%s_1_scene.png"):format(s.tag))
      end
      U.tap(game, "a")
      U.wait(3)
    end
    U.shot(game, DIR .. ("/jj_%s_2_done.png"):format(s.tag))
    U.log(s.tag, "settled:", tostring(settled),
          "flag:", tostring(game.save.flags[s.beat]),
          "james visible:", tostring(visible(ow, s.james)),
          "jessie visible:", tostring(visible(ow, s.jessie)))
  end

  U.log("DONE")
  love.event.quit()
end
