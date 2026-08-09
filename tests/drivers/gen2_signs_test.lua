-- Driver: Gen2 bg_events run their script, not just their text.
--
-- bg_events are script pointers (BGEVENT_READ and friends); the extractor
-- only chased them far enough to find a `jumptext` target, so every signpost
-- that does real work -- the Ruins of Alph wall patterns, the research-center
-- machines -- was inert.  map_scripts now carries a `signs` label per map and
-- Gen2ScriptVM compiles it into the same talk table objects use.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_signs_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local MapScripts = require("src.script.MapScripts")

  local pass, fail = 0, 0
  local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. what)
  end

  U.newGame(game)
  U.wait(20)

  local pool = game.data.map_scripts
  check(pool ~= nil and pool.info ~= nil and (pool.info.signCount or 0) > 100,
    "map_scripts carries bg_event scripts (" ..
    tostring(pool and pool.info and pool.info.signCount) .. ")")

  local kabuto = pool and pool.maps and pool.maps.RUINS_OF_ALPH_KABUTO_CHAMBER
  check(kabuto ~= nil and kabuto.signs ~= nil,
    "the Kabuto chamber has sign scripts")

  -- the wall pattern is the third bg_event; it runs the puzzle, not text
  local mapDef = game.data.maps.RUINS_OF_ALPH_KABUTO_CHAMBER
  check(mapDef ~= nil and mapDef.signs ~= nil and #mapDef.signs == 4,
    "the chamber map has four signs")

  local wall = mapDef and mapDef.signs and mapDef.signs[3]
  check(wall ~= nil, "the wall pattern sign exists")
  if wall then
    local script = MapScripts.talkScript("RUINS_OF_ALPH_KABUTO_CHAMBER", wall.text)
    check(type(script) == "table" and #script > 0,
      "examining the wall pattern runs a script")
  end

  -- the research center's left machine branches on the Unown count
  local rc = game.data.maps.RUINS_OF_ALPH_RESEARCH_CENTER
  local machine = rc and rc.signs and rc.signs[2]
  check(machine ~= nil and type(
    MapScripts.talkScript("RUINS_OF_ALPH_RESEARCH_CENTER", machine.text)) == "table",
    "the research-center machine runs a script")

  -- a plain signpost still resolves, through its script's jumptext
  local outside = game.data.maps.RUINS_OF_ALPH_OUTSIDE
  local sign = outside and outside.signs and outside.signs[1]
  check(sign ~= nil and sign.text ~= nil, "the outside signposts still carry text")

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
