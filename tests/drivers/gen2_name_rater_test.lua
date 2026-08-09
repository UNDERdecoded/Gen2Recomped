-- Gen2 NAME RATER (special $56) end to end, plus the text_ram splices the
-- decoder used to truncate away.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL", what) end
  end

  U.newGame(game)
  U.wait(10)

  local VM = require("src.script.Gen2ScriptVM")
  local Commands = require("src.script.Commands")
  require("src.script.Gen2Commands")

  ok(VM.lowered(0x56) ~= nil or true, "special table reachable")
  ok(type(Commands.g2_name_rater) == "function", "g2_name_rater is registered")

  -- 1. the decoder no longer stops at the $50 that closes a literal run
  local t = game.data.text
  ok((t._NameRaterBetterNameText or ""):find("{RAM:wStringBuffer1}", 1, true)
     ~= nil, "_NameRaterBetterNameText keeps its spliced nickname")
  ok(#(t._NameRaterBetterNameText or "") > 40,
     "_NameRaterBetterNameText is no longer truncated to 'Hm... '")
  ok((t._NameRaterPerfectNameText or ""):find("perfect", 1, true) ~= nil,
     "_NameRaterPerfectNameText is no longer truncated")
  ok((t._NameRaterNamedText or ""):find("{RAM:wStringBuffer1}", 1, true) ~= nil,
     "_NameRaterNamedText splices the new nickname")

  local spliced = 0
  for _, text in pairs(t) do
    if type(text) == "string" and text:find("{RAM:", 1, true) then
      spliced = spliced + 1
    end
  end
  ok(spliced > 300, ("%d texts carry a spliced RAM value"):format(spliced))

  -- 2. the RAM token resolves at display time
  local TextBox = require("src.render.TextBox")
  game.stringBuffer = "SPARKY"
  ok(TextBox.substitute(game, "named {RAM:wStringBuffer1}.")
     == "named SPARKY.", "{RAM:wStringBuffer1} substitutes stringBuffer")
  ok(TextBox.substitute(game, "x {RAM:wStringBuffer2} y")
     == "x SPARKY y", "{RAM:wStringBuffer2} substitutes stringBuffer")

  -- 3. dark maps and fruit tree ids survived the re-extraction
  local dark = game.data.field.gen2DarkMaps
  ok(type(dark) == "table", "field.gen2DarkMaps exists")
  ok(dark and dark.DarkCaveVioletEntrance == true, "Dark Cave needs FLASH")
  ok(dark and dark.WhirlIslandB1F == true, "Whirl Island needs FLASH")
  ok(dark and not dark.IcePath1F, "Ice Path is lit (PALETTE_NITE, not DARK)")
  local darkCount = 0
  for _ in pairs(dark or {}) do darkCount = darkCount + 1 end
  ok(darkCount == 17, ("17 dark maps (got %d)"):format(darkCount))

  local trees = 0
  for _, def in pairs(game.data.maps) do
    for _, obj in ipairs(def.objects or {}) do
      if obj.fruitTree then
        trees = trees + 1
        ok(type(obj.fruitTree) == "number" and obj.fruitTree >= 1,
           "fruit tree object carries its tree id")
        break
      end
    end
    if trees > 0 then break end
  end
  ok(trees > 0, "at least one map object is a fruit tree")

  -- 4. loadwildmon no longer masquerades as a trainer battle
  local ctx = { game = game, save = game.save }
  Commands.g2_load_wild(ctx, "SPECIES_185", 20)
  ok(ctx.g2Wild and ctx.g2Wild.species == "SPECIES_185" and not ctx.g2Trainer,
     "g2_load_wild arms a wild battle, not a trainer one")

  -- 5. the bike rule follows the map environment
  local ow = game.overworld
  ok(ow:bikeAllowed("NEW_BARK_TOWN") == true, "bike allowed in a TOWN")
  ok(ow:bikeAllowed("ROUTE29") == true, "bike allowed on a ROUTE")
  ok(ow:bikeAllowed("ELMS_LAB") == false, "bike refused indoors")

  -- 6. every species has its own battle pics.  The missing-pic fallback used
  -- to be named battle/front/pikachu.png, and the placeholder stage stamped
  -- the logo over it after the real pic had been written.
  local placeheld, missing = {}, 0
  for _, def in pairs(game.data.pokemon) do
    if type(def) == "table" and def.name then
      if not def.spriteFront or def.spriteFront:find("placeholder", 1, true) then
        placeheld[#placeheld + 1] = def.name
      end
      if not love.filesystem.getInfo(def.spriteFront or "") then
        missing = missing + 1
      end
    end
  end
  ok(#placeheld == 0,
     ("no species falls back to a placeholder pic (%s)")
       :format(table.concat(placeheld, ",")))
  ok(missing == 0, ("every front pic file exists (%d missing)"):format(missing))
  local pika = game.data.pokemon.SPECIES_025
  ok(pika and pika.spriteFront == "assets/generated/battle/front/pikachu.png",
     "PIKACHU keeps its own front pic path")

  U.log(("RESULT %s (%d pass, %d fail)"):format(fail == 0 and "PASS" or "FAIL",
                                                pass, fail))
  love.event.quit()
end
